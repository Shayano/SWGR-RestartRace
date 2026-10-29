-- Restart Race
-- Ajoute un bouton "Recommencer la course" au menu pause des courses de campagne.
--
-- Quand une course de campagne démarre, on capture tout ce qu'une course peut modifier dans la
-- run : crédits (avant le side bet), santé du véhicule, strikes, état des pièces (affixes) et
-- état de génération de l'événement. Au restart, cette capture est réappliquée avant le voyage
-- puis une seconde fois au chargement de la nouvelle course, pour que la nouvelle tentative
-- commence exactement comme la première.

local MOD_DIR = debug.getinfo(1, 'S').source:gsub('^@', ''):gsub('[\\/][Ss]cripts[\\/]main%.lua$', '')

local TEXTS = {
  en = { label = 'Restart Race',
         description = 'Restart this race. Credits (side bet included), vehicle health and part damage go back to how they were at the start.' },
  fr = { label = 'Recommencer la course',
         description = 'Recommence cette course. Les crédits (side bet compris), la santé du véhicule et les dégâts des pièces reviennent à leur état du départ.' },
}

local config = {
  label = nil,          -- nil : selon la langue du jeu
  description = nil,    -- nil : selon la langue du jeu
  restore_run_state = true,
  retry_if_track_changes = false,
  track_diagnostics = false,
  debug = false,
}
do
  local ok, user = pcall(dofile, MOD_DIR .. '/config.lua')
  if ok and type(user) == 'table' then
    for k, v in pairs(user) do config[k] = v end
  end
end

local TAG = '[RestartRace] '
local TICK_MS = 50
local TICKS_PER_SEC = 1000 // TICK_MS
local FLOW_CAMPAIGN = 1                  -- EGfnPrimaryFlow::Campaign
local VIS_VISIBLE, VIS_COLLAPSED = 0, 1  -- ESlateVisibility
local AFFIX_FAULTY = 2                   -- EAffixStatus::Faulty
local CONTINUE_START_EVENT = 4           -- EContinueRunState::StartEvent
local PAUSE_CLASS = 'WBP_PauseRacing_C'
local BUTTON_CLASS = '/Game/Griffin/UI/Widgets/Buttons/WBP_Vertical_Btn.WBP_Vertical_Btn_C'
local BUTTON_ASSET = '/Game/Griffin/UI/Widgets/Buttons/WBP_Vertical_Btn.WBP_Vertical_Btn'
local AFFIX_ARRAYS = { 'AffixSlots', 'PlaneOnlyAffixSlots' }

local function say(s) print(TAG .. tostring(s) .. '\n') end
local function trace(s) if config.debug then say(s) end end
local function call(fn) local ok, r = pcall(fn); if ok then return r end; return nil end
local function valid(o) return o ~= nil and call(function() return o:IsValid() end) == true end
local function same(a, b)
  return valid(a) and valid(b) and call(function() return a:GetAddress() == b:GetAddress() end) == true
end
-- GetFName et GetFullName sur un objet nul font planter le jeu (pas d'erreur Lua que pcall
-- pourrait rattraper) : on vérifie l'objet avant.
local function name_of(o)
  return valid(o) and call(function() return o:GetFName():ToString() end) or nil
end

local function find_first(class_name)
  local all = call(function() return FindAllOf(class_name) end)
  if type(all) ~= 'table' then return nil end
  for _, o in ipairs(all) do if valid(o) then return o end end
  return nil
end

local cache = {}
local function cached(class_name)
  local o = cache[class_name]
  if valid(o) then return o end
  o = find_first(class_name)
  cache[class_name] = o
  return o
end

local function text(key)
  if config[key] then return config[key] end
  if not config.lang then
    local ksl = call(function() return StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary') end)
    local lang = valid(ksl) and call(function() return ksl:GetCurrentLanguage():ToString() end) or 'en'
    config.lang = TEXTS[lang:sub(1, 2)] and lang:sub(1, 2) or 'en'
  end
  return TEXTS[config.lang][key]
end

---------------------------------------------------------------------------------------------
-- État de la campagne
---------------------------------------------------------------------------------------------

-- Renvoie la run de campagne active et le CampaignSubsystem, ou nil hors campagne.
local function campaign()
  local gi = cached('GfnGameInstance')
  if not gi or call(function() return tonumber(gi.PrimaryFlow) end) ~= FLOW_CAMPAIGN then return nil end
  local cs = cached('CampaignSubsystem')
  if not cs then return nil end
  local run = call(function() return cs.ActiveRun end)
  if not valid(run) then return nil end
  return run, cs
end

-- Diagnostic des changements de tracé (Scripts/track_diag.lua), chargé seulement sur demande.
local diag = nil
if config.track_diagnostics then
  local ok, res = pcall(dofile, MOD_DIR .. '/Scripts/track_diag.lua')
  if ok and type(res) == 'function' then
    ok, res = pcall(res, { call = call, valid = valid, name_of = name_of, mod_dir = MOD_DIR,
      game_instance = function() return cached('GfnGameInstance') end })
  end
  if ok and type(res) == 'table' then diag = res else say('Track diagnostics unavailable: ' .. tostring(res)) end
end

-- RacingGameState de la course chargée, transmis par NotifyOnNewObject. FindAllOf parcourt tous
-- les objets du jeu sur le thread du jeu (ce build d'UE4SS n'a pas de cache d'objets) : la
-- boucle ne doit jamais chercher, seulement les actions ponctuelles (search).
local race_gs = nil
local function racing_state(search)
  if not valid(race_gs) and search then race_gs = find_first('RacingGameState') end
  return valid(race_gs) and race_gs or nil
end

local function race_in_progress()
  local gs = racing_state(true)
  return gs ~= nil and call(function() return gs.bIsRaceFinished end) ~= true
end

-- Appelle fn(clé, affix) pour chaque emplacement d'affix de chaque build du joueur.
local function each_affix(run, fn)
  call(function()
    run.playerRacer.Build.VehicleBuilds:ForEach(function(bi, b)
      local build = b:get()
      for _, field in ipairs(AFFIX_ARRAYS) do
        call(function()
          build[field]:ForEach(function(ai, a) fn(bi .. ':' .. field .. ':' .. ai, a:get()) end)
        end)
      end
    end)
  end)
end

local function affix_id(affix)
  local primary = call(function() return affix.PrimaryAffix end)
  return valid(primary) and call(function() return primary:GetFullName() end) or '?'
end

local function int(fn) return call(function() return tonumber(fn()) end) end

local function continue_state(cs) return int(function() return cs:GetContinueRunState() end) end

-- Nom interne et circuit de la première étape de l'événement en cours (diagnostic).
local function track_name()
  local gs = racing_state(false)
  if not gs then return 'nil' end
  return call(function()
    local name = nil
    gs.EventRecipe.EventStages:ForEach(function(_, e)
      if name then return end
      local st = e:get()
      name = (call(function() return st.InternalName:ToString() end) or '?') .. '/'
        .. (name_of(call(function() return st.TrackDef end)) or '?')
    end)
    return name
  end) or '?'
end

-- Nombre d'entrées et dernier circuit d'un historique de la run (diagnostic). Le jeu réécrit
-- la dernière étape de mPlayerPath quand il retire l'événement du nœud pendant le voyage.
local function crumbs_summary(run, field)
  local count, last = 0, nil
  call(function()
    run[field]:ForEach(function(_, e)
      count = count + 1
      last = call(function() return e:get().track end)
    end)
  end)
  return count .. '/' .. (name_of(last) or '-')
end

-- Toutes les valeurs simples (nombres, booléens, énumérations) déclarées par les classes du
-- jeu sur un objet, plus la taille de ses tableaux. Sert à remettre en place ce qu'une course
-- a pu modifier sans qu'on sache le nommer, et à loguer ce qui a changé.
local SCALAR_TYPES = { IntProperty = true, Int64Property = true, Int16Property = true, Int8Property = true,
  UInt16Property = true, UInt32Property = true, UInt64Property = true, FloatProperty = true,
  DoubleProperty = true, BoolProperty = true, ByteProperty = true, EnumProperty = true }

local function read_fields(obj)
  local scalars, arrays = {}, {}
  local cls = call(function() return obj:GetClass() end)
  while valid(cls) and (call(function() return cls:GetFullName() end) or ''):find('/Script/Griffin.', 1, true) do
    call(function()
      cls:ForEachProperty(function(p)
        local kind = call(function() return p:GetClass():GetFName():ToString() end)
        local name = call(function() return p:GetFName():ToString() end)
        if not name then return end
        if SCALAR_TYPES[kind] then
          scalars[name] = call(function() return obj[name] end)
        elseif kind == 'ArrayProperty' then
          arrays[name] = call(function() return obj[name]:GetArrayNum() end)
        end
      end)
    end)
    cls = call(function() return cls:GetSuperStruct() end)
  end
  return { scalars = scalars, arrays = arrays }
end

local RACER_FIELDS = { 'RivalScore', 'PowerLevelModifier', 'bIsRivalrySuppressed' }

local function read_racer(r)
  local entry = {}
  for _, f in ipairs(RACER_FIELDS) do entry[f] = call(function() return r[f] end) end
  return entry
end

local function read_racers(run)
  local list = { player = call(function() return read_racer(run.playerRacer) end) or {} }
  call(function()
    run.OpponentRacers:ForEach(function(i, e) list[i] = read_racer(e:get()) end)
  end)
  return list
end

local function diff_fields(label, old, new, out)
  if not old or not new then return end
  for name, v in pairs(new.scalars) do
    if old.scalars[name] ~= v then
      out[#out + 1] = label .. '.' .. name .. ' ' .. tostring(old.scalars[name]) .. '->' .. tostring(v)
    end
  end
  for name, n in pairs(new.arrays) do
    if old.arrays[name] ~= n then
      out[#out + 1] = label .. '.' .. name .. ' #' .. tostring(old.arrays[name]) .. '->' .. tostring(n)
    end
  end
end

local function diff_racers(old, new, out)
  for key, entry in pairs(new) do
    local was = old[key] or {}
    for _, f in ipairs(RACER_FIELDS) do
      if was[f] ~= entry[f] then
        out[#out + 1] = 'racer' .. tostring(key) .. '.' .. f .. ' ' .. tostring(was[f]) .. '->' .. tostring(entry[f])
      end
    end
  end
end

-- Valeurs restaurées ailleurs (crédits par les fonctions du jeu) ou qui ne doivent pas bouger.
local KEEP_FIELDS = { RunId = true, Credits = true }

local function restore_fields(obj, saved)
  local n = 0
  for name, v in pairs(saved.scalars) do
    if not KEEP_FIELDS[name] and v ~= nil and call(function() return obj[name] end) ~= v then
      call(function() obj[name] = v end)
      n = n + 1
    end
  end
  return n
end

local function restore_racers(run, saved)
  local n = 0
  local function put(r, was)
    if not was then return end
    for _, f in ipairs(RACER_FIELDS) do
      if was[f] ~= nil and call(function() return r[f] end) ~= was[f] then
        call(function() r[f] = was[f] end)
        n = n + 1
      end
    end
  end
  call(function() put(run.playerRacer, saved.player) end)
  call(function()
    run.OpponentRacers:ForEach(function(i, e) put(e:get(), saved[i]) end)
  end)
  return n
end

-- Tableaux de structures de la run dont une course modifie le contenu sans changer la taille :
-- progression des contrats de sponsor par planète, pilotes proposés en side bet.
local STRUCT_ARRAYS = { 'VisitedPlanets', 'mAvailableSidebets' }

local function array_struct(obj, field)
  local st = nil
  local cls = call(function() return obj:GetClass() end)
  while not st and valid(cls) do
    call(function()
      cls:ForEachProperty(function(p)
        if not st and call(function() return p:GetFName():ToString() end) == field then
          st = call(function() return p:GetInner():GetStruct() end)
        end
      end)
    end)
    cls = call(function() return cls:GetSuperStruct() end)
  end
  return valid(st) and st or nil
end

-- Valeurs simples et références d'objets d'une structure, parents compris.
local function struct_fields(st)
  local list = {}
  while valid(st) do
    call(function()
      st:ForEachProperty(function(p)
        local kind = call(function() return p:GetClass():GetFName():ToString() end)
        local name = call(function() return p:GetFName():ToString() end)
        if name and (SCALAR_TYPES[kind] or kind == 'ObjectProperty') then
          list[#list + 1] = { name = name, object = kind == 'ObjectProperty' }
        end
      end)
    end)
    st = call(function() return st:GetSuperStruct() end)
  end
  return list
end

-- Un objet nul est noté false.
local function read_struct_array(obj, field)
  local fields, items = nil, {}
  call(function()
    obj[field]:ForEach(function(i, e)
      local v = e:get()
      if not fields then
        fields = struct_fields(array_struct(obj, field) or call(function() return v:GetStruct() end))
      end
      local item = {}
      for _, f in ipairs(fields) do
        local x = call(function() return v[f.name] end)
        if f.object then x = valid(x) and x or false end
        item[f.name] = x
      end
      items[i] = item
    end)
  end)
  return { fields = fields or {}, items = items, count = #items }
end

-- Seulement si le tableau a gardé sa taille : UE4SS ne sait pas en retirer ou en ajouter.
local function restore_struct_array(obj, field, saved)
  if not saved or saved.count == 0 then return 0 end
  if int(function() return obj[field]:GetArrayNum() end) ~= saved.count then return 0 end
  local n = 0
  call(function()
    obj[field]:ForEach(function(i, e)
      local v, was = e:get(), saved.items[i]
      for _, f in ipairs(saved.fields) do
        local old = was and was[f.name]
        local cur = call(function() return v[f.name] end)
        if f.object then
          if old and not same(cur, old) then
            call(function() v[f.name] = old end)
            n = n + 1
          elseif old == false and valid(cur) then
            call(function() v[f.name] = CreateInvalidObject() end)
            n = n + 1
          end
        elseif old ~= nil and cur ~= old then
          call(function() v[f.name] = old end)
          n = n + 1
        end
      end
    end)
  end)
  return n
end

local function describe(run, cs)
  local faulty = 0
  each_affix(run, function(_, a) if int(function() return a.Status end) == AFFIX_FAULTY then faulty = faulty + 1 end end)
  return string.format('run=%s credits=%s health=%s strikes=%s faulty_parts=%s queued_faults=%s seed=%s rand=%s/%s saved=%s loading=%s reward_seed=%s failed=%s continue=%s node=%s track=%s history=%s path=%s',
    tostring(int(function() return run.RunId end)),
    tostring(int(function() return run.Credits end)),
    tostring(int(function() return run.PlayerVehicleHealth end)),
    tostring(int(function() return run.Strikes end)),
    tostring(faulty),
    tostring(call(function() return run.mAffixesToTurnFaultyThroughoutRace:GetArrayNum() end)),
    tostring(int(function() return run.mGeneratedEventSeed end)),
    tostring(int(function() return run.mRand.InitialSeed end)),
    tostring(int(function() return run.mRand.Seed end)),
    tostring(call(function() return run.mSavedDuringEventInfo.SavedDuringEvent end)),
    tostring(call(function() return run.mSavedDuringEventInfo.IsLoading end)),
    tostring(int(function() return run.mSavedDuringEventInfo.RewardRandomSeed end)),
    tostring(call(function() return run.mSavedDuringEventInfo.PlayerFailedEvent end)),
    tostring(continue_state(cs)),
    tostring(name_of(call(function() return run:GetCurrentNode() end))),
    track_name(),
    crumbs_summary(run, 'mTrackHistory'),
    crumbs_summary(run, 'mPlayerPath'))
end

local snapshot = nil              -- état de la run au chargement de la course en cours
local restore_after_travel = nil  -- { snap, ticks } tant que la course relancée n'a pas chargé
local verify_track = nil          -- { snap, ticks } : tracé de la course relancée à comparer
local retry_at = nil              -- tick auquel relancer à nouveau (tracé différent)

local function known_track()
  local t = track_name()
  if t == '?' or t == 'nil' then return nil end
  return t
end

local function take_snapshot(run, cs)
  local s = {
    run_id = int(function() return run.RunId end),
    credits = int(function() return run.Credits end),
    health = int(function() return run.PlayerVehicleHealth end),
    strikes = int(function() return run.Strikes end),
    seed = int(function() return run.mGeneratedEventSeed end),
    rand_initial = int(function() return run.mRand.InitialSeed end),
    rand_seed = int(function() return run.mRand.Seed end),
    failed = call(function() return run.mSavedDuringEventInfo.PlayerFailedEvent end),
    reward_seed = int(function() return run.mSavedDuringEventInfo.RewardRandomSeed end),
    saved = call(function() return run.mSavedDuringEventInfo.SavedDuringEvent end),
    loading = call(function() return run.mSavedDuringEventInfo.IsLoading end),
    queued_faults = call(function() return run.mAffixesToTurnFaultyThroughoutRace:GetArrayNum() end),
    affixes = {},
    track = known_track(),  -- souvent pas encore connu au premier tick, complété par la boucle
    retries = 0,
  }
  s.fields = read_fields(run)
  s.node = call(function() return run:GetCurrentNode() end)
  s.node_fields = valid(s.node) and read_fields(s.node) or nil
  s.racers = read_racers(run)
  s.cs_fields = read_fields(cs)
  s.struct_arrays = {}
  for _, f in ipairs(STRUCT_ARRAYS) do s.struct_arrays[f] = read_struct_array(run, f) end
  -- Les side bets sont souvent proposées juste après le premier tick : la boucle les capture
  -- dès qu'elles apparaissent, avant que le joueur ait pu parier.
  s.sidebets_pending = s.struct_arrays.mAvailableSidebets.count == 0
  each_affix(run, function(key, affix)
    local second = call(function() return affix.SecondaryAffix end)
    s.affixes[key] = {
      id = affix_id(affix),
      status = int(function() return affix.Status end),
      second = valid(second) and second or nil,
      second_addr = valid(second) and call(function() return second:GetAddress() end) or 0,
    }
  end)
  return s
end

-- Logue ce qui a changé dans la run, le nœud en cours, les adversaires et le CampaignSubsystem
-- depuis le départ de la course (diagnostic du tirage d'événement).
local function log_changes(run, cs, s)
  if not config.debug then return end
  local out = {}
  diff_fields('run', s.fields, read_fields(run), out)
  local node = call(function() return run:GetCurrentNode() end)
  if s.node_fields and same(node, s.node) then diff_fields('node', s.node_fields, read_fields(node), out) end
  diff_racers(s.racers, read_racers(run), out)
  diff_fields('campaign', s.cs_fields, read_fields(cs), out)
  trace('changed during the race: ' .. (#out > 0 and table.concat(out, ', ') or 'nothing'))
end

-- Réapplique la capture. with_event restaure aussi la génération de l'événement, ce qui n'a de
-- sens qu'avant le voyage.
local function restore(run, cs, s, with_event)
  local cur = int(function() return run.Credits end)
  if s.credits and cur and cur ~= s.credits then
    if s.credits > cur then
      call(function() run:AddCreditsUnrecorded(s.credits - cur) end)
    else
      call(function() run:RemoveCreditsUnrecorded(cur - s.credits) end)
    end
    if int(function() return run.Credits end) ~= s.credits then call(function() run.Credits = s.credits end) end
  end
  if s.credits then call(function() cs:SetLastVisualCreditsValue(s.credits) end) end
  -- Après les crédits : le remboursement du side bet fait aussi monter LifetimeCreditsEarned,
  -- que la restauration des champs remet à sa valeur du départ.
  local fields = restore_fields(run, s.fields) + restore_racers(run, s.racers)
  for _, f in ipairs(STRUCT_ARRAYS) do
    fields = fields + restore_struct_array(run, f, s.struct_arrays and s.struct_arrays[f])
  end
  if s.node_fields and same(call(function() return run:GetCurrentNode() end), s.node) then
    fields = fields + restore_fields(s.node, s.node_fields)
  end
  if fields > 0 then trace('restored ' .. fields .. ' run field(s)') end
  if s.health then call(function() run.PlayerVehicleHealth = s.health end) end
  if s.strikes then call(function() run.Strikes = s.strikes end) end
  -- Une panne passe la pièce en Faulty et peut lui accrocher un affixe secondaire : on remet les
  -- deux comme au départ.
  local parts = 0
  each_affix(run, function(key, affix)
    local was = s.affixes[key]
    if not was or was.id ~= affix_id(affix) then return end
    if was.status and int(function() return affix.Status end) ~= was.status then
      call(function() affix.Status = was.status end)
      parts = parts + 1
    end
    local second = call(function() return affix.SecondaryAffix end)
    local addr = valid(second) and call(function() return second:GetAddress() end) or 0
    if addr ~= was.second_addr then
      if was.second_addr == 0 then
        call(function() affix.SecondaryAffix = CreateInvalidObject() end)
      elseif valid(was.second) then
        call(function() affix.SecondaryAffix = was.second end)
      end
      parts = parts + 1
    end
  end)
  if parts > 0 then trace('restored ' .. parts .. ' part field(s)') end
  if with_event then
    if s.seed then call(function() run.mGeneratedEventSeed = s.seed end) end
    if s.rand_initial then call(function() run.mRand.InitialSeed = s.rand_initial end) end
    if s.rand_seed then call(function() run.mRand.Seed = s.rand_seed end) end
    -- Ces drapeaux pilotent GetContinueRunState : SavedDuringEvent + IsLoading le fait passer
    -- en PostEvent et le voyage termine alors la course au lieu de la relancer.
    if s.failed ~= nil then call(function() run.mSavedDuringEventInfo.PlayerFailedEvent = s.failed end) end
    if s.saved ~= nil then call(function() run.mSavedDuringEventInfo.SavedDuringEvent = s.saved end) end
    if s.loading ~= nil then call(function() run.mSavedDuringEventInfo.IsLoading = s.loading end) end
    if s.reward_seed then call(function() run.mSavedDuringEventInfo.RewardRandomSeed = s.reward_seed end) end
  end
end

-- Une pièce tombée en panne pendant la course reste en file jusqu'au voyage, où le jeu
-- l'applique, donc après notre restauration. On le laisse appliquer ces pannes avant de
-- restaurer, pour que la restauration les annule avant le voyage (cette version d'UE4SS ne
-- sait pas vider un TArray).
local function flush_queued_faults(run, s)
  local queued = call(function() return run.mAffixesToTurnFaultyThroughoutRace:GetArrayNum() end) or 0
  if queued <= (s.queued_faults or 0) then return end
  call(function() run:ApplyAffixFaultChanges() end)
  trace('applied ' .. queued .. ' queued part fault(s) before restoring, '
    .. tostring(call(function() return run.mAffixesToTurnFaultyThroughoutRace:GetArrayNum() end)) .. ' left')
end

-- Appelé une fois par chargement de course, au premier tick après la création du
-- RacingGameState (avant que le joueur ait pu placer son side bet).
local function on_race_level()
  local run, cs = campaign()
  if not run then snapshot = nil; restore_after_travel = nil; return end
  local pending_restore = restore_after_travel
  restore_after_travel = nil
  if pending_restore and pending_restore.snap.run_id == int(function() return run.RunId end) then
    trace('race reloaded: ' .. describe(run, cs))
    if diag then call(function() diag.after_reload(run, cs, describe(run, cs)) end) end
    restore(run, cs, pending_restore.snap, false)
    snapshot = pending_restore.snap
    verify_track = { snap = snapshot, ticks = 0 }
    trace('after restore: ' .. describe(run, cs))
    return
  end
  snapshot = take_snapshot(run, cs)
  trace('race start: ' .. describe(run, cs))
  if config.debug then
    -- Coût d'une recherche d'objets, mesuré une fois par course pendant le chargement.
    local t0 = os.clock()
    find_first('RacingGameState')
    trace(string.format('one object search (FindAllOf) took %.1f ms', (os.clock() - t0) * 1000))
  end
  if diag then call(function() diag.race_start(run, cs, describe(run, cs)) end) end
end

---------------------------------------------------------------------------------------------
-- Bouton du menu pause
---------------------------------------------------------------------------------------------

local ui = { screen = nil, button = nil, was_active = false, focus = false }
local screen_buttons = {}  -- adresse d'un écran de pause -> notre bouton dans cet écran
local new_screens = {}
local click_requested = false

local click_hooked = pcall(function()
  RegisterHook('/Script/CommonUI.CommonButtonBase:HandleButtonClicked', function(ctx)
    if ui.button and same(ctx:get(), ui.button) then click_requested = true end
  end)
end)

local function screen_active(w) return valid(w) and call(function() return w:IsActivated() end) == true end

local function set_shown(widget, shown)
  if not valid(widget) then return end
  call(function() widget:SetVisibility(shown and VIS_VISIBLE or VIS_COLLAPSED) end)
  call(function() widget:SetIsEnabled(shown) end)
end

-- Apparence de WBP_Vertical_Btn, recopiée depuis un bouton du menu pour que le nôtre ait le
-- même style que ses voisins.
local LOOK_VALUES = { 'IsInvert', 'WidthOverride' }
local LOOK_COLORS = { 'SetColor', 'LinearSelectColor', 'LinearUnselectColor', 'LinearSelectBackgroundColor' }

local function copy_look(from, to)
  for _, name in ipairs(LOOK_VALUES) do
    local v = call(function() return from[name] end)
    if v ~= nil then call(function() to[name] = v end) end
  end
  for _, name in ipairs(LOOK_COLORS) do
    local c = call(function() local s = from[name]; return { R = s.R, G = s.G, B = s.B, A = s.A } end)
    if c then call(function() to[name] = c end) end
  end
end

local function new_button(screen)
  local cls = call(function() return StaticFindObject(BUTTON_CLASS) end)
  if not valid(cls) then
    call(function() LoadAsset(BUTTON_ASSET) end)
    cls = call(function() return StaticFindObject(BUTTON_CLASS) end)
  end
  local lib = call(function() return StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary') end)
  local pc = call(function() return screen:GetOwningPlayer() end)
  if not (valid(cls) and valid(lib) and valid(pc)) then return nil end
  local b = call(function() return lib:Create(pc, cls, pc) end)
  if not valid(b) then return nil end
  local model = call(function() return screen.Btn_Settings end)
  if not valid(model) then model = call(function() return screen.Btn_ResumeRace end) end
  if valid(model) then copy_look(model, b) end
  -- Lu par le widget à sa construction, donc avant l'ajout au menu.
  call(function() b.ButtonLabel = FText(text('label')) end)
  return b
end

local function refresh_label(b)
  local label = text('label')
  call(function() b:SetText(FText(label)) end)
  if call(function() return b:GetText():ToString() end) ~= label then
    local t = call(function() return b.Txt_Label end)
    if valid(t) then call(function() t:SetText(FText(label)) end) end
  end
end

-- La validation manette de CommonUI appelle HandleButtonClicked directement en C++ et échappe
-- au hook. Un bouton basculable passe en "sélectionné" quel que soit le chemin du clic : c'est
-- ce que la boucle surveille.
local function make_clickable(b)
  set_shown(b, true)
  for _, setter in ipairs({ 'BP_SetIsInteractionEnabled', 'BP_SetIsFocusable', 'SetIsSelectable', 'SetIsToggleable' }) do
    call(function() b[setter](b, true) end)
  end
  call(function() b:SetShouldSelectUponReceivingFocus(false) end)
end

local function layout_of(widget)
  local s = call(function() return widget.Slot end)
  if not valid(s) then return nil end
  return {
    padding = call(function() local p = s.Padding; return { Left = p.Left, Top = p.Top, Right = p.Right, Bottom = p.Bottom } end),
    size = call(function() local z = s.Size; return { Value = z.Value, SizeRule = z.SizeRule } end),
    halign = call(function() return s.HorizontalAlignment end),
    valign = call(function() return s.VerticalAlignment end),
  }
end

local function add_with_layout(box, widget, layout)
  local s = call(function() return box:AddChildToVerticalBox(widget) end)
  if not valid(s) or not layout then return end
  if layout.padding then call(function() s:SetPadding(layout.padding) end) end
  if layout.size then call(function() s:SetSize(layout.size) end) end
  if layout.halign ~= nil then call(function() s:SetHorizontalAlignment(layout.halign) end) end
  if layout.valign ~= nil then call(function() s:SetVerticalAlignment(layout.valign) end) end
end

local function index_in(box, widget)
  local i = int(function() return box:GetChildIndex(widget) end)
  if i and i >= 0 then return i end
  for j = 0, (int(function() return box:GetChildrenCount() end) or 0) - 1 do
    if same(call(function() return box:GetChildAt(j) end), widget) then return j end
  end
  return nil
end

-- Place widget juste après anchor. UMG ne sait pas insérer à un index une fois le menu
-- construit : on détache ce qui suit l'ancre, on ajoute le widget avec la mise en page de
-- l'ancre, puis on rattache le reste avec sa propre mise en page.
local function insert_after(box, anchor, widget)
  local at = valid(anchor) and index_in(box, anchor)
  if not at then add_with_layout(box, widget, nil); return end
  local following = {}
  for i = at + 1, (int(function() return box:GetChildrenCount() end) or 0) - 1 do
    local c = call(function() return box:GetChildAt(i) end)
    if valid(c) then following[#following + 1] = { widget = c, layout = layout_of(c) } end
  end
  for _, f in ipairs(following) do call(function() box:RemoveChild(f.widget) end) end
  add_with_layout(box, widget, layout_of(anchor))
  for _, f in ipairs(following) do add_with_layout(box, f.widget, f.layout) end
end

-- Installe ou met à jour notre bouton dans un écran de pause. Renvoie false si l'arbre de
-- widgets n'est pas encore prêt (on réessaiera au tick suivant).
local function install(w, late)
  local box = call(function() return w.FuseFilteredVerticalBox end)
  if not valid(box) then return false end
  local key = w:GetAddress()
  local b = screen_buttons[key]
  -- Une adresse peut resservir après un passage du ramasse-miettes : on ne garde le bouton
  -- que s'il est encore enfant de ce menu.
  if not (valid(b) and same(call(function() return b:GetParent() end), box)) then
    b = nil
    screen_buttons[key] = nil
  end
  ui.screen, ui.button = w, b
  -- Visible seulement pendant une course qu'on peut réellement relancer : le menu pause de
  -- type course s'ouvre aussi pendant la sélection d'événement.
  local run, cs = campaign()
  if not run or not race_in_progress() or continue_state(cs) ~= CONTINUE_START_EVENT then
    set_shown(b, false)
    return true
  end
  local resume = call(function() return w.Btn_ResumeRace end)
  if not b then
    b = new_button(w)
    if not b then return false end
    insert_after(box, resume, b)
    screen_buttons[key] = b
    -- Menu découvert alors qu'il était déjà ouvert : on rend le focus à "Reprendre" pour ne
    -- pas laisser le menu sans focus après l'insertion.
    if late and valid(resume) then call(function() resume:SetFocus() end) end
    trace('button added to ' .. (name_of(w) or 'pause menu')
      .. ', track=' .. track_name())
  end
  refresh_label(b)
  make_clickable(b)
  set_shown(call(function() return w.Btn_RetryRace end), false)  -- retry natif, réservé à l'arcade
  ui.button = b
  return true
end

local function find_pause_screen()
  local all = call(function() return FindAllOf(PAUSE_CLASS) end)
  if type(all) ~= 'table' then return nil end
  for _, w in ipairs(all) do if screen_active(w) then return w end end
  return nil
end

local function show_description()
  local td = call(function() return ui.screen.Txt_Description end)
  if valid(td) then call(function() td:SetText(FText(text('description'))) end) end
end

---------------------------------------------------------------------------------------------
-- Restart
---------------------------------------------------------------------------------------------

-- Le voyage ne relance la course que depuis StartEvent ; tout autre état mène ailleurs
-- (PostEvent, par exemple, termine la course).
local function at_event_start(cs, when)
  local state = continue_state(cs)
  if state == CONTINUE_START_EVENT then return true end
  say('Restart cancelled ' .. when .. ': campaign is not at the start of an event (state ' .. tostring(state) .. ')')
  return false
end

-- auto : relance déclenchée par le mod parce que le tracé avait changé.
local function travel(auto)
  local run, cs = campaign()
  if not run then say('Restart cancelled: no active campaign run'); return end
  trace((auto and 'automatic restart: ' or 'restart requested: ') .. describe(run, cs))
  if not at_event_start(cs, 'before restore') then return end
  local snap = snapshot
  if snap and not auto then snap.retries = 0 end
  if config.restore_run_state and snap and snap.run_id == int(function() return run.RunId end) then
    log_changes(run, cs, snap)
    flush_queued_faults(run, snap)
    restore(run, cs, snap, true)
    restore_after_travel = { snap = snap, ticks = 0 }
    trace('restored before travel: ' .. describe(run, cs))
  elseif config.restore_run_state then
    say('No race start state captured, restarting without restoring the run')
  end
  if not at_event_start(cs, 'after restore') then restore_after_travel = nil; return end
  say('Restarting race')
  if diag then call(function() diag.before_travel(run, cs, auto, describe(run, cs)) end) end
  local ok, err = pcall(function() cs:TravelToStartOrContinueCampaign() end)
  if not ok then restore_after_travel = nil; say('Restart failed: ' .. tostring(err)) end
end

-- On referme d'abord le menu par son propre bouton "Reprendre", qui gère la fin de la pause,
-- puis on voyage une fois le jeu repris.
local restart = nil  -- { screen, button, ticks, resumed_at }

local function press_resume(screen)
  local resume = call(function() return screen.Btn_ResumeRace end)
  if valid(resume) then call(function() resume:HandleButtonClicked() end) end
end

local function begin_restart()
  restart = { screen = ui.screen, button = ui.button, ticks = 0, resumed_at = nil }
  call(function() restart.button:SetIsEnabled(false) end)
  press_resume(restart.screen)
end

local function step_restart()
  local r = restart
  r.ticks = r.ticks + 1
  if not r.resumed_at then
    if not screen_active(r.screen) then r.resumed_at = r.ticks; return end
    if r.ticks == TICKS_PER_SEC then press_resume(r.screen) end
    if r.ticks >= 3 * TICKS_PER_SEC then
      restart = nil
      set_shown(r.button, true)
      say('Restart cancelled: the pause menu did not close')
    end
    return
  end
  if r.ticks - r.resumed_at < TICKS_PER_SEC // 4 then return end
  restart = nil
  travel()
end

---------------------------------------------------------------------------------------------
-- Boucle
---------------------------------------------------------------------------------------------

local tick_no = 0
local last_credits = nil
local race_level_loaded = false
local MAX_TRACK_RETRIES = 2

-- Le tirage de l'événement par le jeu dépend parfois d'autre chose que ce que le mod restaure :
-- si la course relancée n'est pas sur le tracé du départ, on relance à nouveau.
local function check_track(snap, now)
  local target = snap.track
  local retry = target and now ~= target and config.retry_if_track_changes and snap.retries < MAX_TRACK_RETRIES
  -- Sauf pendant les relances automatiques, le tracé obtenu devient la référence : le restart
  -- suivant doit ramener la course qu'on est en train de jouer, pas celle du tout premier départ.
  if not retry then snap.track = now end
  if diag then call(function() diag.track_result(target, now) end) end
  if not target or now == target then
    if snap.retries > 0 then say('Back on ' .. now .. ' after ' .. snap.retries .. ' automatic restart(s)') end
    snap.retries = 0
    return
  end
  if not config.retry_if_track_changes then
    say('Track changed on restart: ' .. target .. ' -> ' .. now)
    return
  end
  if not retry then
    say('Track still different after ' .. snap.retries .. ' automatic restart(s): ' .. now .. ' instead of ' .. target)
    return
  end
  snap.retries = snap.retries + 1
  say('Track changed on restart (' .. now .. ' instead of ' .. target .. '), restarting again')
  retry_at = tick_no + TICKS_PER_SEC
end

local function trace_credits()
  local run = campaign()
  local cur = run and int(function() return run.Credits end)
  if cur and last_credits and cur ~= last_credits then
    trace('credits ' .. last_credits .. ' -> ' .. cur)
  end
  last_credits = cur
end

local function tick()
  tick_no = tick_no + 1
  if race_level_loaded then
    race_level_loaded = false
    on_race_level()
  end
  if config.debug and tick_no % (TICKS_PER_SEC // 2) == 0 then trace_credits() end
  if restore_after_travel then
    restore_after_travel.ticks = restore_after_travel.ticks + 1
    if restore_after_travel.ticks > TICKS_PER_SEC * 120 then restore_after_travel = nil end
  end
  if snapshot and not snapshot.track and tick_no % TICKS_PER_SEC == 0 then snapshot.track = known_track() end
  if snapshot and snapshot.sidebets_pending then
    local run = campaign()
    if run and (int(function() return run.mAvailableSidebets:GetArrayNum() end) or 0) > 0 then
      snapshot.struct_arrays.mAvailableSidebets = read_struct_array(run, 'mAvailableSidebets')
      snapshot.sidebets_pending = false
      trace('side bets offered: ' .. snapshot.struct_arrays.mAvailableSidebets.count)
    end
  end
  if verify_track then
    verify_track.ticks = verify_track.ticks + 1
    local now = known_track()
    if now then
      local v = verify_track
      verify_track = nil
      check_track(v.snap, now)
    elseif verify_track.ticks > 5 * TICKS_PER_SEC then
      verify_track = nil
    end
  end
  if retry_at and tick_no >= retry_at then
    retry_at = nil
    travel(true)
    return
  end
  if restart then step_restart(); return end

  for i = #new_screens, 1, -1 do
    local w = new_screens[i]
    if not valid(w) or install(w, false) then table.remove(new_screens, i) end
  end

  -- Les écrans de pause arrivent par NotifyOnNewObject. On ne cherche qu'au premier tick, pour
  -- un menu déjà ouvert quand le mod se charge.
  if tick_no == 1 then
    local w = find_pause_screen()
    if w then install(w, true); ui.was_active = true end
  end
  if not valid(ui.screen) then
    ui.screen, ui.button, ui.was_active = nil, nil, false
    return
  end

  local active = screen_active(ui.screen)
  if active and not ui.was_active then install(ui.screen, false) end
  ui.was_active = active
  if not active or not valid(ui.button) then click_requested = false; return end

  local selected = call(function() return ui.button:GetSelected() end) == true
  if click_requested or selected then
    trace('click detected via ' .. (click_requested and 'hook' or 'selection'))
    click_requested = false
    call(function() ui.button:SetIsSelected(false, false) end)
    begin_restart()
    return
  end
  local focus = call(function() return ui.button.bHasFocus end) == true
  if focus ~= ui.focus then trace('button focus: ' .. tostring(focus)) end
  ui.focus = focus
  if focus or call(function() return ui.button:IsHovered() end) == true then show_description() end
end

call(function()
  NotifyOnNewObject('/Script/Griffin.FuseScreenWidget', function(o)
    if name_of(call(function() return o:GetClass() end)) == PAUSE_CLASS then
      new_screens[#new_screens + 1] = o
    end
  end)
end)

call(function()
  NotifyOnNewObject('/Script/Griffin.RacingGameState', function(o)
    local name = name_of(o) or ''
    if not name:find('^Default__') then race_gs, race_level_loaded = o, true end
  end)
end)

local last_err = nil
LoopInGameThreadWithDelay(TICK_MS, function()
  local ok, err = pcall(tick)
  if not ok and tostring(err) ~= last_err then last_err = tostring(err); say('error: ' .. last_err) end
end)

say('Loaded' .. (click_hooked and '' or ' (click hook unavailable, detecting clicks by selection only)')
  .. (diag and ', track diagnostics written to track_diag.log' or ''))
