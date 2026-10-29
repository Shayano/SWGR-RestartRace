-- Diagnostic des changements de tracé au restart (option track_diagnostics de config.lua).
--
-- Écrit dans track_diag.log, à côté de config.lua, sans l'effacer d'un lancement à l'autre :
-- - chaque appel des fonctions du sélecteur d'événement de la run (EventPicker), avec ce
--   qu'elles reçoivent (dont l'état du générateur aléatoire) et l'événement choisi ;
-- - au départ d'une course, avant chaque voyage et au rechargement, une capture détaillée de la
--   run, du nœud en cours, du sélecteur, du CampaignSubsystem et du GameInstance, et ce qui a
--   changé entre deux captures.
-- Ne modifie rien dans le jeu. Les heures sont en UTC, comme UE4SS.log sous Wine.

return function(h)
  local call, valid, name_of = h.call, h.valid, h.name_of
  local PATH = h.mod_dir .. '/track_diag.log'
  local MAX_BYTES = 8 * 1024 * 1024   -- au-delà, l'ancien fichier passe en .old au lancement
  local MAX_DEPTH = 4                 -- niveaux de structures et de tableaux imbriqués
  local MAX_ITEMS = 32                -- éléments lus par tableau
  local MAX_DIFF_LINES = 400

  call(function()
    local f = io.open(PATH, 'r')
    if not f then return end
    local size = f:seek('end')
    f:close()
    if size and size > MAX_BYTES then
      os.remove(PATH .. '.old')
      os.rename(PATH, PATH .. '.old')
    end
  end)

  local function write(lines)
    if type(lines) ~= 'table' then lines = { lines } end
    call(function()
      local f = io.open(PATH, 'a')
      if not f then return end
      local stamp = os.date('!%Y-%m-%d %H:%M:%S')
      for _, l in ipairs(lines) do f:write(stamp, ' ', tostring(l), '\n') end
      f:close()
    end)
  end

  ---------------------------------------------------------------------------------------------
  -- Captures
  ---------------------------------------------------------------------------------------------

  local SCALAR = { IntProperty = true, Int64Property = true, Int16Property = true, Int8Property = true,
    UInt16Property = true, UInt32Property = true, UInt64Property = true, FloatProperty = true,
    DoubleProperty = true, BoolProperty = true, ByteProperty = true, EnumProperty = true }
  local STRINGS = { NameProperty = true, StrProperty = true, TextProperty = true }
  local OBJECTS = { ObjectProperty = true, ClassProperty = true }

  local function kind_of(p) return call(function() return p:GetClass():GetFName():ToString() end) end
  local function prop_name(p) return call(function() return p:GetFName():ToString() end) end

  local function game_class(cls)
    local n = call(function() return cls:GetFullName() end) or ''
    return n:find('/Script/Griffin.', 1, true) ~= nil or n:find(' /Game/', 1, true) ~= nil
  end

  -- Les types qu'UE4SS ne sait pas lire (maps, sets, délégués, pointeurs faibles...) sont
  -- seulement nommés : on ne les lit pas, pour ne pas risquer un plantage natif.
  local dump_struct
  local function dump_value(out, path, kind, prop, get, depth)
    if SCALAR[kind] then
      out[path] = tostring(call(get))
    elseif STRINGS[kind] then
      out[path] = tostring(call(function() return get():ToString() end))
    elseif OBJECTS[kind] then
      out[path] = name_of(call(get)) or 'null'
    elseif kind == 'StructProperty' then
      if depth >= MAX_DEPTH then out[path] = '<struct>'; return end
      local v = call(get)
      if v == nil then out[path] = '<struct?>'; return end
      local st = call(function() return prop:GetStruct() end)
      if not valid(st) then st = call(function() return v:GetStruct() end) end
      if not valid(st) then out[path] = '<struct?>'; return end
      dump_struct(out, path, st, v, depth + 1)
    elseif kind == 'ArrayProperty' then
      local arr = call(get)
      local n = arr ~= nil and call(function() return arr:GetArrayNum() end) or nil
      out[path .. '#'] = tostring(n)
      if not n or n == 0 or depth >= MAX_DEPTH then return end
      local inner = call(function() return prop:GetInner() end)
      local ikind = inner and kind_of(inner)
      if not (SCALAR[ikind] or STRINGS[ikind] or OBJECTS[ikind] or ikind == 'StructProperty') then return end
      call(function()
        arr:ForEach(function(i, e)
          if i <= MAX_ITEMS then
            dump_value(out, path .. '[' .. i .. ']', ikind, inner, function() return e:get() end, depth + 1)
          end
        end)
      end)
    else
      out[path] = '<' .. tostring(kind) .. '>'
    end
  end

  dump_struct = function(out, path, st, v, depth)
    local s = st
    while valid(s) do
      call(function()
        s:ForEachProperty(function(p)
          local n = prop_name(p)
          if n then dump_value(out, path .. '.' .. n, kind_of(p), p, function() return v[n] end, depth) end
        end)
      end)
      s = call(function() return s:GetSuperStruct() end)
    end
  end

  local function dump_object(out, label, obj)
    if not valid(obj) then out[label] = 'null'; return end
    out[label] = name_of(obj) or '?'
    out[label .. '@class'] = name_of(call(function() return obj:GetClass() end)) or '?'
    local cls = call(function() return obj:GetClass() end)
    while valid(cls) and game_class(cls) do
      call(function()
        cls:ForEachProperty(function(p)
          local n = prop_name(p)
          if n then dump_value(out, label .. '.' .. n, kind_of(p), p, function() return obj[n] end, 1) end
        end)
      end)
      cls = call(function() return cls:GetSuperStruct() end)
    end
  end

  local function capture(run, cs)
    local t0 = os.clock()
    local out = {}
    dump_object(out, 'run', run)
    dump_object(out, 'node', call(function() return run:GetCurrentNode() end))
    dump_object(out, 'picker', call(function() return run.EventPicker end))
    dump_object(out, 'campaign', cs)
    dump_object(out, 'game', call(h.game_instance))
    local n = 0
    for _ in pairs(out) do n = n + 1 end
    return out, string.format('%d values in %.0f ms', n, (os.clock() - t0) * 1000)
  end

  local function diff(a, b)
    local lines = {}
    for k, v in pairs(b) do
      if a[k] ~= v then lines[#lines + 1] = k .. ': ' .. tostring(a[k] or '(absent)') .. ' -> ' .. v end
    end
    for k, v in pairs(a) do
      if b[k] == nil then lines[#lines + 1] = k .. ': ' .. v .. ' -> (absent)' end
    end
    table.sort(lines)
    return lines
  end

  local function write_diff(title, lines)
    local out = { '  ' .. title .. ': ' .. (#lines == 0 and 'nothing' or #lines .. ' value(s)') }
    for i = 1, math.min(#lines, MAX_DIFF_LINES) do out[#out + 1] = '    ' .. lines[i] end
    if #lines > MAX_DIFF_LINES then out[#out + 1] = '    ... ' .. (#lines - MAX_DIFF_LINES) .. ' more' end
    write(out)
  end

  ---------------------------------------------------------------------------------------------
  -- Appels du sélecteur d'événement
  ---------------------------------------------------------------------------------------------

  local st = { start = nil, pre = nil, attempt = 0, traveling = false, calls = 0 }

  local function phase()
    return st.traveling and ('travel #' .. st.attempt) or 'outside restart'
  end

  local function summarize(v, depth)
    depth = depth or 0
    local t = type(v)
    if t ~= 'userdata' and t ~= 'table' then return tostring(v) end
    local kind = call(function() return v:type() end) or ''
    if kind == 'FName' or kind == 'FString' or kind == 'FText' then
      return tostring(call(function() return v:ToString() end))
    end
    if kind:find('Struct', 1, true) then
      local s = call(function() return v:GetStruct() end)
      if not valid(s) then return '<struct?>' end
      local out = {}
      dump_struct(out, '', s, v, MAX_DEPTH - 2)
      local keys = {}
      for k in pairs(out) do keys[#keys + 1] = k end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do parts[#parts + 1] = k:sub(2) .. '=' .. out[k] end
      return '{' .. table.concat(parts, ' ') .. '}'
    end
    if kind:find('Array', 1, true) then
      local n = call(function() return v:GetArrayNum() end)
      local parts = {}
      if depth < 1 then
        call(function()
          v:ForEach(function(i, e)
            if i <= 8 then parts[#parts + 1] = summarize(call(function() return e:get() end), depth + 1) end
          end)
        end)
      end
      return '[' .. tostring(n) .. ': ' .. table.concat(parts, ', ') .. ']'
    end
    return name_of(v) or ('<' .. kind .. '>')
  end

  -- Paramètres lus avant et après l'appel. Les paramètres de sortie ne sont lus qu'après :
  -- avant l'appel, leur mémoire n'est pas initialisée et les lire pourrait planter le jeu.
  local PICKER_FUNCS = {
    PickEvent = { pre = { 2 }, post = { 1, 2 } },                  -- (eventOut, rand)
    GenerateEventChoices = { pre = { 1, 2, 3 }, post = {} },       -- (planet, dayIndex, isHighRisk, checkUnlock)
    EnumerateAllChoices = { pre = {}, post = { 1 } },              -- (choices)
  }

  local function on_call(fname, when, indexes)
    return function(ctx, ...)
      local args = { ... }
      local parts = {}
      for _, i in ipairs(indexes) do
        local a = args[i]
        parts[#parts + 1] = a and summarize(call(function() return a:get() end)) or 'nil'
      end
      if when == 'before' then st.calls = st.calls + 1 end
      write(string.format('[%s] %s %s #%d on %s: %s', phase(), when, fname, st.calls,
        name_of(call(function() return ctx:get() end)) or '?', table.concat(parts, ' | ')))
    end
  end

  local hooked = false
  local function hook_picker(picker)
    if hooked or not valid(picker) then return end
    hooked = true
    local found = {}
    local cls = call(function() return picker:GetClass() end)
    while valid(cls) do
      local cname = call(function() return cls:GetFullName() end) or ''
      if cname:find('/Script/CoreUObject.Object', 1, true) then break end
      call(function()
        cls:ForEachFunction(function(fn)
          local n = call(function() return fn:GetFName():ToString() end)
          if n and PICKER_FUNCS[n] then
            local full = call(function() return fn:GetFullName() end) or ''
            found[#found + 1] = { name = n, path = full:match('^%S+ (.+)$') }
          end
        end)
      end)
      cls = call(function() return cls:GetSuperStruct() end)
    end
    local lines = { 'picker ' .. (name_of(picker) or '?') .. ', class '
      .. (call(function() return picker:GetClass():GetFullName() end) or '?') }
    for _, f in ipairs(found) do
      local spec = PICKER_FUNCS[f.name]
      local ok, err = false, 'no path'
      if f.path then
        ok, err = pcall(RegisterHook, f.path, on_call(f.name, 'before', spec.pre), on_call(f.name, 'after', spec.post))
      end
      lines[#lines + 1] = '  hook ' .. tostring(f.path) .. ': ' .. (ok and 'ok' or ('failed: ' .. tostring(err)))
    end
    if #found == 0 then lines[#lines + 1] = '  no picker function found to hook' end
    write(lines)
  end

  ---------------------------------------------------------------------------------------------
  -- Points d'entrée appelés par main.lua
  ---------------------------------------------------------------------------------------------

  local api = {}

  function api.race_start(run, cs, line)
    write({ '', '=== race start: ' .. line })
    hook_picker(call(function() return run.EventPicker end))
    local snap, stats = capture(run, cs)
    st.start, st.pre, st.attempt, st.traveling = snap, nil, 0, false
    write('  captured ' .. stats)
  end

  function api.before_travel(run, cs, auto, line)
    st.attempt = st.attempt + 1
    write('--- travel #' .. st.attempt .. (auto and ' (automatic)' or '') .. ': ' .. line)
    local snap, stats = capture(run, cs)
    write('  captured ' .. stats)
    if st.start then write_diff('different from the race start (not put back)', diff(st.start, snap)) end
    if st.pre then write_diff('different from before the previous travel', diff(st.pre, snap)) end
    st.pre, st.traveling = snap, true
  end

  function api.after_reload(run, cs, line)
    st.traveling = false
    write('--- reloaded after travel #' .. st.attempt .. ': ' .. line)
    local snap, stats = capture(run, cs)
    write('  captured ' .. stats)
    if st.pre then write_diff('changed by the travel', diff(st.pre, snap)) end
  end

  function api.track_result(target, now)
    if target and now ~= target then
      write('!!! TRACK CHANGED after travel #' .. st.attempt .. ': ' .. target .. ' -> ' .. now)
    else
      write('same track after travel #' .. st.attempt .. ': ' .. tostring(now))
    end
  end

  write({ '', '##### game started, RestartRace track diagnostics on (times in UTC)' })
  return api
end
