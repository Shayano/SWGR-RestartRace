-- Skip Intros
-- Passe les logos de démarrage (Fuse Games, Secret Mode, Lucasfilm).
--
-- Le menu joue MEDIA_Intro_FUSE_Ident.bk2 puis MEDIA_Intro_Brand_Ident.bk2 dans son lecteur
-- Bink et attend la fin de chaque vidéo. On amène la lecture à la fin : le jeu reçoit son
-- événement "fin de vidéo" normal et enchaîne sur la suite du démarrage.

local TAG = '[SkipIntros] '
local DEBUG = false
local TICK_MS = 100
local GIVE_UP_AFTER_TICKS = 3 * 60 * 1000 // TICK_MS  -- on arrête de surveiller après 3 min
local IDENT_COUNT = 2  -- FUSE puis Brand : FindAllOf coûte cher, on s'arrête dès qu'ils sont passés
local TIMESPAN_TICKS_PER_SEC = 10000000                  -- FTimespan : 1 tick = 100 ns
local END_MARGIN = TIMESPAN_TICKS_PER_SEC // 10          -- on saute à 0,1 s de la fin

local function say(s) print(TAG .. tostring(s) .. '\n') end
local function trace(s) if DEBUG then say(s) end end
local function call(fn) local ok, r = pcall(fn); if ok then return r end; return nil end
local function valid(o) return o ~= nil and call(function() return o:IsValid() end) == true end

local function is_ident(url) return url:find('Intro_[%w_]*Ident') ~= nil end

local skipped = {}   -- url par lecteur déjà traitée
local seen = {}      -- dernière url vue par lecteur (diagnostic)
local skips = 0
local tick_no = 0
local handle = nil

local function skip(player, url)
  local dur = call(function() return player:GetDuration().Ticks end)
  if not dur or dur <= END_MARGIN then return false end
  local ok = call(function() return player:Seek({ Ticks = dur - END_MARGIN }) end)
  say('skipped ' .. url:match('[^/\\]+$') .. (ok == false and ' (seek refused)' or ''))
  return ok ~= false
end

local function tick()
  tick_no = tick_no + 1
  if tick_no > GIVE_UP_AFTER_TICKS or skips >= IDENT_COUNT then return end
  local players = call(function() return FindAllOf('BinkMediaPlayer') end)
  if type(players) ~= 'table' then return end
  for _, p in ipairs(players) do
    if valid(p) then
      local key = call(function() return p:GetAddress() end)
      local url = call(function() return p:GetUrl():ToString() end) or ''
      if key and url ~= seen[key] then
        seen[key] = url
        trace('player ' .. (call(function() return p:GetFName():ToString() end) or '?') .. ' url=' .. url)
      end
      if key and is_ident(url) and skipped[key] ~= url and call(function() return p:IsPlaying() end) == true then
        if skip(p, url) then skipped[key] = url; skips = skips + 1 end
      end
    end
  end
end

handle = LoopInGameThreadWithDelay(TICK_MS, function()
  local ok, err = pcall(tick)
  if not ok then say('error: ' .. tostring(err)) end
  if (tick_no >= GIVE_UP_AFTER_TICKS or skips >= IDENT_COUNT) and handle then
    call(function() CancelDelayedAction(handle) end)
    handle = nil
  end
end)

say('Loaded')
