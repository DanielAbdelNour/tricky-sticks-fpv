-- Tricky Sticks FPV: the radio side. Reads sticks + CRSF telemetry, feeds the
-- pure detector (core.lua), writes the OSD text via MSP_SET_NAME (msp.lua),
-- plays tones / announcer clips and keeps the high score on the SD card.
-- Loaded by SCRIPTS/TELEMETRY/trick.lua; the screen lives in ui.lua.
--
-- Only uses what EdgeTX 2.9+ provides on B&W radios (no `table` library, no
-- global `unpack`; see tests/globals.lua). Memory is tight on these radios,
-- so state the screen needs is kept as fields of R instead of extra tables.

local R = { page = 1, linkUp = false, attOk = false, attHz = 0 }
local cfg, core, msp, D, N
local idRoll, idPitch, idYaw, idThr, idAttP, idAttR, idAttY, idFM
local lastLookup, lastTick, hadLink = -1e9, -1, false
local lastP, lastR, attCount, attWinT = nil, nil, 0, 0
local floor = math.floor

local function findField(names)
  if type(names) == "string" then names = { names } end
  for i = 1, #names do
    local fi = getFieldInfo(names[i])
    if fi then return fi.id end
  end
  return nil
end

local function lookup()
  idRoll  = idRoll  or findField(cfg.SRC_ROLL)
  idPitch = idPitch or findField(cfg.SRC_PITCH)
  idYaw   = idYaw   or findField(cfg.SRC_YAW)
  idThr   = idThr   or findField(cfg.SRC_THR)
  idAttP  = idAttP  or findField(cfg.SENSOR_PITCH)
  idAttR  = idAttR  or findField(cfg.SENSOR_ROLL)
  idAttY  = idAttY  or findField(cfg.SENSOR_YAW)
  idFM    = idFM    or findField(cfg.SENSOR_FM)
  R.fmOk = idFM ~= nil
  R.yawOk = idAttY ~= nil
  R.sticksOk = idRoll ~= nil and idPitch ~= nil and idYaw ~= nil and idThr ~= nil
end

---------------------------------------------------------------------------
-- High score file (EdgeTX io API: io.read(file, len), io.write(file, s))
---------------------------------------------------------------------------
local function loadBest()
  local f = io.open(cfg.BEST_FILE, "r")
  if not f then return 0 end
  local s = io.read(f, 16)
  io.close(f)
  return tonumber(s) or 0
end

local function saveBest(v)
  local f = io.open(cfg.BEST_FILE, "w")
  if not f then return end
  io.write(f, tostring(v))
  io.close(f)
end

---------------------------------------------------------------------------
-- Announcer clips: cfg.VOICE_DIR/<callout>/<n>.wav for n = 1..VOICE_MAX.
-- Missing numbers are skipped; a callout with no clips plays its tone.
-- Clips play in shuffled rounds (each once before any repeats, never the
-- same one twice in a row). Per callout we keep just two numbers:
--   vClips[d] = bitmask of clips found + longest clip (cs, max 255) * 2^16
--   vState[d] = bitmask played this round + last clip * 2^16
-- Both stay below 2^24: EdgeTX 2.11+ runs Lua 5.3 with 32-bit floats, which
-- hold whole numbers exactly only up to 2^24 (16.7 million). Bigger packed
-- numbers lose their low bits there and the script picks clips that don't
-- exist (silence). tests/widget.lua and tests/voice.lua check this.
---------------------------------------------------------------------------
local VOICE_DIRS = "roll roll2 roll3 front front2 front3 back back2 back3 loop spin spin2 " ..
                   "spin3 orbit matty style fullsend combo2 combo3 combo4 combo5 best crash arm " ..
                   "score generic generic2"
local VOICE_MAX = 16
local B16 = 65536                 -- 2^16
local VOICE_NAMES = { "roll", "front", "back", "crash", "arm", nil, nil, nil, "loop",
                      "spin", "orbit", "style", "best", "matty" }   -- indexed by event code
local vClips, vState = {}, {}
local scanNext, scanDir, scanN, scanMask, scanCs   -- scan, a few files per tick
local voiceUntil, styleVoiceT = 0, -1e9

local function bit(m, k) return floor(m / 2 ^ (k - 1)) % 2 == 1 end

local function scanVoices()
  for _ = 1, 6 do                 -- SD access is slow
    if not scanDir then return end
    scanN = scanN + 1
    local f = io.open(cfg.VOICE_DIR .. scanDir .. "/" .. scanN .. ".wav", "r")
    if f then
      local cs = floor((core.wavSecs(io.read(f, 44)) or cfg.VOICE_SECS) * 100 + 0.5)
      io.close(f)
      scanMask = scanMask + 2 ^ (scanN - 1)
      if cs > scanCs then scanCs = cs > 255 and 255 or cs end
    end
    if scanN >= VOICE_MAX then
      if scanMask > 0 then vClips[scanDir] = scanMask + scanCs * B16 end
      scanDir, scanN, scanMask, scanCs = scanNext(), 0, 0, 0
    end
  end
end

-- Choose the next clip of callout d: a random one not yet played this round
-- and not the one played last.
local function pick(d)
  local mask = vClips[d] % B16
  local st = vState[d] or 0
  local played, last = st % B16, floor(st / B16)
  local n = 0
  for k = 1, VOICE_MAX do
    if bit(mask, k) and not bit(played, k) and k ~= last then n = n + 1 end
  end
  if n == 0 then                  -- round over: start a new one
    played = 0
    for k = 1, VOICE_MAX do
      if bit(mask, k) and k ~= last then n = n + 1 end
    end
    if n == 0 then return last end  -- the callout has a single clip
  end
  local r = math.random(n)
  for k = 1, VOICE_MAX do
    if bit(mask, k) and not bit(played, k) and k ~= last then
      r = r - 1
      if r == 0 then
        vState[d] = played + 2 ^ (k - 1) + k * B16
        return k
      end
    end
  end
end

-- Play a clip unless another is still talking (force = queue it anyway).
local function say(t, d, force)
  local info = vClips[d]
  if not info or (t < voiceUntil and not force) then return false end
  playFile(cfg.VOICE_DIR .. d .. "/" .. pick(d) .. ".wav")
  if t > voiceUntil then voiceUntil = t end
  voiceUntil = voiceUntil + floor(info / B16) / 100 + 0.1
  return true
end

local function tones3(a, b, c, len)
  playTone(a, 60, 20); playTone(b, 60, 20); playTone(c, len or 140, 0)
end

local function sound(ev, t)
  if not cfg.SOUND_ON then return end
  local E = core
  if ev == E.EV_CRASH then playHaptic(150, 0) end
  -- Voice
  local name = VOICE_NAMES[ev]
  if ev == E.EV_STYLE then
    if D.styleNow >= cfg.STYLE_FULL then name = "fullsend" end
    if t - styleVoiceT < cfg.VOICE_STYLE_GAP then name = nil end
  elseif ev == E.EV_ROLL or ev == E.EV_FRONT or ev == E.EV_BACK or ev == E.EV_LOOP
      or ev == E.EV_SPIN or ev == E.EV_ORBIT or ev == E.EV_MATTY then
    local multi = D.lastCount > 1
    if multi and vClips[name .. D.lastCount] then name = name .. D.lastCount end
    -- Sometimes a generic line ("Nailed it!") instead; bigger ones for multis
    local g = multi and "generic2" or "generic"
    if vClips[g] and math.random() < cfg.VOICE_GENERIC then name = g end
  end
  local spoke = name and say(t, name, ev == E.EV_BEST or ev == E.EV_CRASH)
  if spoke then
    if ev == E.EV_STYLE then styleVoiceT = t end
    if D.combo > 1 and ev ~= E.EV_STYLE and ev ~= E.EV_BEST and ev ~= E.EV_CRASH then
      say(t, "combo" .. (D.combo > 5 and 5 or D.combo), true)
    end
  end
  -- Landed: "Final score" + the number in the radio's own voice
  if (ev == E.EV_DISARM or (ev == E.EV_CRASH and not D.armed)) and cfg.VOICE_SCORE
      and D.score > 0 and say(t, "score", true) then
    playNumber(D.score, 0)
  end
  if spoke or ev == E.EV_ARM or ev == E.EV_DISARM then return end
  -- Combos and multi-rotations play higher
  local up = 0
  if ev ~= E.EV_STYLE and ev ~= E.EV_CRASH and ev ~= E.EV_BEST then
    up = (D.combo > 1 and (D.combo - 1) * 150 or 0) + (D.lastCount - 1) * 200
  end
  if ev == E.EV_ROLL then
    playTone(1200 + up, 60, 20); playTone(1800 + up, 120, 0)
  elseif ev == E.EV_FRONT then tones3(900 + up, 1300 + up, 1900 + up)
  elseif ev == E.EV_BACK then tones3(1100 + up, 1600 + up, 2200 + up)
  elseif ev == E.EV_MATTY then tones3(1100 + up, 1100 + up, 2200 + up, 220)
  elseif ev == E.EV_LOOP then playTone(600 + up, 500, 0, 0, 3)
  elseif ev == E.EV_SPIN then tones3(1500 + up, 1200 + up, 1500 + up, 80)
  elseif ev == E.EV_ORBIT then playTone(1000 + up, 120, 40); playTone(1000 + up, 120, 0)
  elseif ev == E.EV_STYLE then playTone(2400, 40, 0)
  elseif ev == E.EV_BEST then tones3(1000, 1500, 2000, 300)
  elseif ev == E.EV_CRASH then playTone(700, 400, 0, 0, -10)
  end
end

---------------------------------------------------------------------------
-- Main tick (called from both background() and run())
---------------------------------------------------------------------------
function R.tick()
  local now = getTime()
  if now == lastTick then return end
  lastTick = now
  local t = now / 100

  if not (R.sticksOk and idAttP and idAttR and idAttY and idFM) and t - lastLookup >= 2 then
    lookup()
    lastLookup = t
  end

  local linkUp = getRSSI() > 0
  if N and linkUp and not hadLink then msp.relink(N) end
  hadLink, R.linkUp = linkUp, linkUp

  local armedState = nil
  if linkUp and idFM then armedState = core.parseArmed(getValue(idFM)) end
  R.armedState = armedState

  local r = idRoll and getValue(idRoll) / 1024 or 0
  local p = idPitch and getValue(idPitch) / 1024 or 0
  local y = idYaw and getValue(idYaw) / 1024 or 0
  local thr = idThr and (getValue(idThr) + 1024) / 2048 or 0

  local attOk = linkUp and idAttP ~= nil and idAttR ~= nil
  R.attOk = attOk
  local ap, ar, ay = 0, 0, 0
  if attOk then
    ap, ar = getValue(idAttP), getValue(idAttR)
    if idAttY then ay = getValue(idAttY) end
    if ap ~= lastP or ar ~= lastR then
      attCount = attCount + 1
      lastP, lastR = ap, ar
    end
  end
  if t - attWinT >= 2 then
    R.attHz = floor(attCount / (t - attWinT) + 0.5)
    attCount, attWinT = 0, t
  end

  local ev = core.update(D, t, armedState, r, p, y, thr, attOk, ap, ar, ay)
  if scanDir then scanVoices() end
  if ev ~= 0 then
    sound(ev, t)
    if ev == core.EV_ARM or ev == core.EV_TURTLE then R.page = 1
    elseif ev == core.EV_DISARM or (ev == core.EV_CRASH and not D.armed) then R.page = 2 end
  end
  if D.bestDirty then
    D.bestDirty = false
    saveBest(D.best)
  end

  if N then msp.nameTick(N, t, core.osdText(D, t), linkUp) end
end

-- load(name) loads a module from /SCRIPTS/TRICKS/ (see trick.lua).
function R.init(load)
  cfg = load("config.lua")
  core = load("core.lua")
  msp = load("msp.lua")
  D = core.new(cfg)
  D.best = loadBest()
  R.cfg, R.core, R.D = cfg, core, D
  if cfg.VOICE then
    math.randomseed(getTime())
    scanNext = string.gmatch(VOICE_DIRS, "%S+")
    scanDir, scanN, scanMask, scanCs = scanNext(), 0, 0, 0
  end
  if cfg.OSD and crossfireTelemetryPush and crossfireTelemetryPop then
    N = msp.newName(cfg, msp.new(crossfireTelemetryPush, crossfireTelemetryPop))
    R.N = N
  end
  lookup()
end

return R
