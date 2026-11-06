-- Tricky Sticks FPV: detection core.
-- Pure Lua (5.1-5.4 / EdgeTX 5.2). No EdgeTX API calls, so it runs in unit
-- tests on a computer. All state lives in one table created by new(); update()
-- does no per-tick table allocations (strings are only built on events).
--
-- Inputs per tick (see update()):
--   t        time in seconds (any monotonic origin)
--   armed    true / false / nil (nil = unknown, e.g. telemetry lost: hold)
--   sRoll    roll stick   -1..1 (right = +)
--   sPitch   pitch stick  -1..1 (forward = +, nose down)
--   sYaw     yaw stick    -1..1
--   thr      throttle      0..1
--   attOk    true if the attitude values below are valid
--   aPitch   attitude pitch, radians (Betaflight: +-pi/2)
--   aRoll    attitude roll,  radians (Betaflight: +-pi)
--   aYaw     attitude yaw,   radians (Betaflight: +-pi)

local M = {}

M.EV_NONE   = 0
M.EV_ROLL   = 1
M.EV_FRONT  = 2
M.EV_BACK   = 3
M.EV_CRASH  = 4
M.EV_ARM    = 5
M.EV_DISARM = 6
M.EV_MISS   = 7   -- candidate expired without telemetry confirmation
M.EV_TURTLE = 8   -- armed while inverted (turtle / flip over after crash)
M.EV_LOOP   = 9   -- power loop
M.EV_SPIN   = 10  -- yaw spin
M.EV_ORBIT  = 11  -- banked 360 turn
M.EV_STYLE  = 12  -- freestyle aggression points
M.EV_BEST   = 13  -- passed the saved high score this flight
M.EV_MATTY  = 14  -- Matty flip: back flip with a pause while inverted
M.NUM_EV    = 14

local abs, cos, rad, deg, floor = math.abs, math.cos, math.rad, math.deg, math.floor

local BUCKET = 0.1             -- seconds per integrator bucket
local MAX_DT = 0.1             -- clamp for long gaps between ticks
local OSD_MAX = 16             -- Betaflight craft name length

-- Integrator channels (sliding windows of BUCKET-sized buckets)
local C_ROLL, C_PITCH, C_YAW = 1, 2, 3   -- commanded rotation, deg
local C_YAWATT = 4                       -- telemetry yaw change, deg
local C_THR, C_DT = 5, 6                 -- throttle*dt and dt (for averages)
local NCH = 6

-- Extra entries in S.msgs (after the event codes) and the tilt thresholds in
-- S.zt. Kept in arrays so the state table stays at <= 64 fields (a smaller
-- hash part: memory is tight on the radio).
local MSG_DOUBLE, MSG_TRIPLE, MSG_FULLSEND, MSG_SCOREMSG = 15, 16, 17, 18
local Z_INV, Z_UP, Z_CRASH, Z_CRASHCLR, Z_TURTLE, Z_TURTLECLR = 1, 2, 3, 4, 5, 6

-- Betaflight appends a status char to the CRSF flight mode when disarmed:
-- '*' ready to arm, '!' arming disabled, '?' GPS rescue not ready.
-- Failsafe ("!FS!") is reported as not armed for scoring purposes.
function M.parseArmed(fm)
  if type(fm) ~= "string" or fm == "" then return nil end
  local c = string.byte(fm, -1)
  if c == 42 or c == 33 or c == 63 then return false end
  return true
end

local function wrap180(d)
  d = d % 360
  if d > 180 then d = d - 360 end
  return d
end

---------------------------------------------------------------------------
-- Ring buffer with a short (WINDOW) and long (LOOP_WINDOW) running sum per
-- channel. ss[c] / sl[c] are the short / long window sums.
---------------------------------------------------------------------------
local function ringClear(S, c1, c2)
  for c = c1, c2 do
    local r = S.ring[c]
    for i = 1, S.nl do r[i] = 0 end
    S.ss[c], S.sl[c] = 0, 0
  end
end

local function clearSticks(S) ringClear(S, C_ROLL, C_YAW) end

local function ringAdvance(S, b)
  local cur = S.bucket
  if b == cur then return end
  local nl, ns = S.nl, S.ns
  local steps = b - cur
  if cur < 0 or steps < 0 or steps >= nl then
    ringClear(S, 1, NCH)
  else
    local ring, ss, sl = S.ring, S.ss, S.sl
    for k = 1, steps do
      local nb = cur + k
      local slot = nb % nl + 1           -- bucket nb-nl leaves the long window
      local sslot = (nb - ns) % nl + 1   -- bucket nb-ns leaves the short window
      for c = 1, NCH do
        local r = ring[c]
        sl[c] = sl[c] - r[slot]
        ss[c] = ss[c] - r[sslot]
        r[slot] = 0
      end
    end
  end
  S.bucket = b
end

local function ringAdd(S, c, v)
  if v == 0 then return end
  local slot = S.bucket % S.nl + 1
  S.ring[c][slot] = S.ring[c][slot] + v
  S.ss[c] = S.ss[c] + v
  S.sl[c] = S.sl[c] + v
end

-- Stick position to rotation rate fraction, with deadband and simple expo.
local function rateFrac(x, db, expo)
  if x > 1 then x = 1 elseif x < -1 then x = -1 end
  if abs(x) < db then return 0 end
  return x * (1 - expo) + x * x * x * expo
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local function resetStyle(S)
  S.stStk, S.stThr, S.stDThr, S.stAtt, S.stTime = 0, 0, 0, 0, 0
end

local function resetOrbit(S)
  S.orbBank, S.orbAcc, S.orbStart, S.orbOkT = 0, 0, 0, -1e9
end

function M.new(cfg)
  local ns = floor(cfg.WINDOW / BUCKET + 0.5)
  local nl = floor(cfg.LOOP_WINDOW / BUCKET + 0.5)
  if nl <= ns then nl = ns + 1 end
  local up = string.upper
  local S = {
    cfg = cfg, ns = ns, nl = nl, ring = {}, ss = {}, sl = {}, bucket = -1,
    -- precomputed cosines: "tilt > X deg" <=> z < cos(X)
    zt = { cos(rad(cfg.INVERTED_TILT)), cos(rad(cfg.UPRIGHT_TILT)),
           cos(rad(cfg.CRASH_TILT)), cos(rad(cfg.CRASH_CLEAR_TILT)),
           cos(rad(cfg.TURTLE_TILT)), cos(rad(cfg.TURTLE_CLEAR_TILT)) },
    msgs = {
      [M.EV_ROLL] = up(cfg.MSG_ROLL), [M.EV_FRONT] = up(cfg.MSG_FRONTFLIP),
      [M.EV_BACK] = up(cfg.MSG_BACKFLIP), [M.EV_CRASH] = up(cfg.MSG_CRASH),
      [M.EV_LOOP] = up(cfg.MSG_LOOP), [M.EV_SPIN] = up(cfg.MSG_SPIN),
      [M.EV_ORBIT] = up(cfg.MSG_ORBIT), [M.EV_STYLE] = up(cfg.MSG_STYLE),
      [M.EV_BEST] = up(cfg.MSG_BEST), [M.EV_MATTY] = up(cfg.MSG_MATTY),
      [MSG_DOUBLE] = up(cfg.MSG_DOUBLE), [MSG_TRIPLE] = up(cfg.MSG_TRIPLE),
      [MSG_FULLSEND] = up(cfg.MSG_FULLSEND), [MSG_SCOREMSG] = up(cfg.MSG_SCORE),
    },
    nouns = {
      [M.EV_ROLL] = up(cfg.NOUN_ROLL), [M.EV_FRONT] = up(cfg.NOUN_FRONTFLIP),
      [M.EV_BACK] = up(cfg.NOUN_BACKFLIP), [M.EV_SPIN] = up(cfg.NOUN_SPIN),
    },
    points = {
      [M.EV_ROLL] = cfg.POINTS_ROLL, [M.EV_FRONT] = cfg.POINTS_FRONTFLIP,
      [M.EV_BACK] = cfg.POINTS_BACKFLIP, [M.EV_LOOP] = cfg.POINTS_LOOP,
      [M.EV_SPIN] = cfg.POINTS_SPIN, [M.EV_ORBIT] = cfg.POINTS_ORBIT,
      [M.EV_MATTY] = cfg.POINTS_MATTY,
    },
    counts = {},                 -- per-flight event counts (summary)
    epEnd = { -1e9, -1e9, -1e9, -1e9 }, epIdx = 1, inInv = false,
    hangT = 0, hangOkT = -1e9,
    lastT = nil,
    armed = false, armT = 0, score = 0, turtle = false, turtleChecked = false,
    z = 1, lastInvT = -1e9, lastUpT = -1e9, tiltSince = nil,
    lastYaw = nil, lastRollD = 0, lastPitchD = 0,
    lastThrT = -1e9, lastThr = 0, lastStickT = -1e9,
    pending = 0, pendT = 0, pendWin = 0, pendCount = 0, pendDir = 1, pendYaw = 0,
    cooldownUntil = -1e9, crashLatched = false,
    combo = 0, bestCombo = 0, lastTrickT = -1e9,
    best = 0, bestAnnounced = false, bestQueued = false, bestDirty = false, newBest = false,
    stylePts = 0, styleNow = 0, flightTime = 0,
    msgText = nil, msgT = -1e9,
    lastEv = 0, lastEvT = -1e9, lastCount = 0,
    txt = nil, txtScore = nil,
  }
  for c = 1, NCH do S.ring[c] = {}; S.ss[c] = 0; S.sl[c] = 0 end
  ringClear(S, 1, NCH)
  for i = 1, M.NUM_EV do S.counts[i] = 0 end
  resetStyle(S)
  resetOrbit(S)
  return S
end

---------------------------------------------------------------------------
-- Messages, scoring
---------------------------------------------------------------------------

-- Fit "<MSG> <tail>" into 16 characters, truncating the message if needed.
-- tail is the score (number) or a short string like "X3".
function M.fit(msg, tail)
  tail = " " .. tail
  local room = OSD_MAX - #tail
  if #msg > room then
    msg = string.gsub(string.sub(msg, 1, room), " +$", "")
  end
  return msg .. tail
end

local function msgActive(S, t)
  return S.msgText ~= nil and t - S.msgT < S.cfg.MSG_TIME
end

local function setMsg(S, t, text)
  S.msgText, S.msgT = text, t
end

local function event(S, t, ev)
  S.lastEv, S.lastEvT = ev, t
  return ev
end

local function checkBest(S)
  if S.best > 0 and S.score > S.best and not S.bestAnnounced then
    S.bestAnnounced, S.bestQueued = true, true
  end
end

-- Score a confirmed trick of n rotations.
local function award(S, t, ev, n)
  local cfg = S.cfg
  if t - S.lastTrickT <= cfg.COMBO_WINDOW then S.combo = S.combo + 1 else S.combo = 1 end
  S.lastTrickT = t
  if S.combo > S.bestCombo then S.bestCombo = S.combo end
  local mult = S.combo
  if mult > cfg.COMBO_MAX then mult = cfg.COMBO_MAX end
  local pts = S.points[ev] * n * mult
  S.score = S.score + pts
  S.counts[ev] = S.counts[ev] + 1
  S.lastCount = n

  local name = S.msgs[ev]
  if n >= 3 and S.nouns[ev] then name = S.msgs[MSG_TRIPLE] .. " " .. S.nouns[ev]
  elseif n == 2 and S.nouns[ev] then name = S.msgs[MSG_DOUBLE] .. " " .. S.nouns[ev] end
  if S.combo >= 2 then
    setMsg(S, t, M.fit(name, "X" .. S.combo))
  else
    setMsg(S, t, M.fit(name, S.score))
  end

  S.pending = 0
  S.cooldownUntil = t + cfg.COOLDOWN
  clearSticks(S)
  checkBest(S)
  return event(S, t, ev)
end

local function crash(S, t)
  S.score = S.score - S.cfg.CRASH_PENALTY
  setMsg(S, t, M.fit(S.msgs[M.EV_CRASH], S.score))
  S.counts[M.EV_CRASH] = S.counts[M.EV_CRASH] + 1
  S.pending = 0
  S.combo = 0
  S.crashLatched = true
  S.tiltSince = nil
  S.cooldownUntil = t + S.cfg.COOLDOWN
  clearSticks(S)
  resetStyle(S)
  resetOrbit(S)
  return event(S, t, M.EV_CRASH)
end

-- Number of inverted episodes whose last inverted sample is at/after `since`.
local function episodesSince(S, since)
  local n = 0
  for i = 1, 4 do if S.epEnd[i] >= since then n = n + 1 end end
  return n
end

local function startFlight(S, t)
  S.armed, S.armT = true, t
  S.score, S.pending, S.msgText = 0, 0, nil
  S.crashLatched, S.turtle, S.turtleChecked = false, false, false
  S.cooldownUntil = -1e9
  S.lastInvT, S.lastUpT = -1e9, -1e9
  for i = 1, 4 do S.epEnd[i] = -1e9 end
  S.hangT, S.hangOkT = 0, -1e9
  for i = 1, M.NUM_EV do S.counts[i] = 0 end
  S.combo, S.bestCombo, S.lastTrickT = 0, 0, -1e9
  S.bestAnnounced, S.bestQueued, S.newBest = false, false, false
  S.stylePts, S.styleNow, S.flightTime = 0, 0, 0
  ringClear(S, 1, NCH)
  resetStyle(S)
  resetOrbit(S)
end

---------------------------------------------------------------------------
-- Main update. Returns one event code per tick (EV_NONE most of the time).
---------------------------------------------------------------------------
function M.update(S, t, armed, sRoll, sPitch, sYaw, thr, attOk, aPitch, aRoll, aYaw)
  local cfg = S.cfg
  local dt = 0
  if S.lastT then dt = t - S.lastT end
  if dt < 0 then dt = 0 elseif dt > MAX_DT then dt = MAX_DT end
  S.lastT = t

  if armed == nil then return M.EV_NONE end   -- unknown state: hold

  -- Attitude bookkeeping (up-vector z = cos(pitch)*cos(roll); 1 level, -1 inverted)
  local dYaw, dAct = 0, 0
  if attOk then
    local z = cos(aPitch) * cos(aRoll)
    S.z = z
    local zt = S.zt
    if z < zt[Z_INV] then
      S.lastInvT = t
      if not S.inInv then
        S.epIdx = S.epIdx % 4 + 1
        S.hangOkT = -1e9   -- a hang only counts for the episode it happened in
      end
      S.epEnd[S.epIdx] = t
      S.inInv = true
    else
      S.inInv = false
      S.hangT = 0
    end
    if z > zt[Z_UP] then S.lastUpT = t end
    if z < zt[Z_CRASH] then
      if not S.tiltSince then S.tiltSince = t end
    else
      S.tiltSince = nil
    end
    if S.crashLatched and z > zt[Z_CRASHCLR] then S.crashLatched = false end
    local pd, rd, yd = deg(aPitch), deg(aRoll), deg(aYaw or 0)
    if S.lastYaw then
      dYaw = wrap180(yd - S.lastYaw)
      dAct = abs(wrap180(rd - S.lastRollD)) + abs(pd - S.lastPitchD)
    end
    S.lastYaw, S.lastRollD, S.lastPitchD = yd, rd, pd
  else
    S.tiltSince = nil
    S.lastYaw = nil
  end

  -- Arm / disarm transitions
  if armed and not S.armed then
    startFlight(S, t)
    if attOk then
      S.turtleChecked = true
      if S.z < S.zt[Z_TURTLE] then
        S.turtle = true
        return event(S, t, M.EV_TURTLE)
      end
    end
    return event(S, t, M.EV_ARM)
  elseif not armed then
    if S.armed then
      S.armed = false
      S.pending = 0
      S.flightTime = t - S.armT
      local ev = M.EV_DISARM
      local wasTilted = attOk and S.z < S.zt[Z_CRASH]
      if cfg.CRASH_ON_DISARM and wasTilted and not S.turtle and not S.crashLatched
          and t - S.armT >= cfg.ARM_GRACE then
        crash(S, t)
        ev = M.EV_CRASH
      end
      if S.score > S.best then
        S.best, S.bestDirty, S.newBest = S.score, true, true
      end
      S.msgText = nil
      return event(S, t, ev)
    end
    return M.EV_NONE
  end

  -- Armed from here on.
  if thr >= cfg.THR_MIN then S.lastThrT = t end
  if abs(sRoll) >= cfg.CRASH_STICK or abs(sPitch) >= cfg.CRASH_STICK then S.lastStickT = t end

  -- Turtle mode: armed while inverted. Judged from the first valid attitude
  -- at arming. Ignore everything until upright again, then restart the grace.
  if not S.turtleChecked and attOk then
    S.turtleChecked = true
    if S.z < S.zt[Z_TURTLE] then
      S.turtle = true
      return event(S, t, M.EV_TURTLE)
    end
  end
  if S.turtle then
    if attOk and S.z > S.zt[Z_TURTLECLR] then
      S.turtle = false
      S.armT = t
      S.lastInvT = -1e9
    end
    return M.EV_NONE
  end

  if t - S.armT < cfg.ARM_GRACE then
    S.lastInvT = -1e9   -- rotations during grace (e.g. turtle) don't count
    for i = 1, 4 do S.epEnd[i] = -1e9 end
    S.lastThr = thr
    return M.EV_NONE
  end

  -- Integrate sticks, telemetry yaw and throttle into the windows
  ringAdvance(S, floor(t / BUCKET))
  ringAdd(S, C_YAWATT, dYaw)
  ringAdd(S, C_THR, thr * dt)
  ringAdd(S, C_DT, dt)
  local db, ex = cfg.STICK_DEADBAND, cfg.RATE_EXPO
  local fr, fp, fy = rateFrac(sRoll, db, ex), rateFrac(sPitch, db, ex), rateFrac(sYaw, db, ex)
  if t < S.cooldownUntil or S.crashLatched then
    clearSticks(S)
  else
    ringAdd(S, C_ROLL, fr * cfg.MAX_RATE_ROLL * dt)
    ringAdd(S, C_PITCH, fp * cfg.MAX_RATE_PITCH * dt)
    ringAdd(S, C_YAW, fy * cfg.MAX_RATE_YAW * dt)
  end
  local ss, sl = S.ss, S.sl

  -- Matty flip hang: inverted (telemetry) with the pitch stick released
  if attOk and S.inInv and abs(fp) < cfg.SETTLE_FRAC then
    S.hangT = S.hangT + dt
    if S.hangT >= cfg.MATTY_HANG then S.hangOkT = t end
  else
    S.hangT = 0
  end

  -- Freestyle accumulators
  S.stStk = S.stStk + (abs(sRoll) + abs(sPitch) + abs(sYaw)) * dt
  S.stThr = S.stThr + thr * dt
  S.stDThr = S.stDThr + abs(thr - S.lastThr)
  S.stAtt = S.stAtt + dAct
  S.stTime = S.stTime + dt
  S.lastThr = thr

  -- Pending candidate: count extra rotations, confirm, or expire
  local p = S.pending
  if p ~= 0 then
    local axis, f = C_PITCH, fp
    if p == M.EV_ROLL then axis, f = C_ROLL, fr elseif p == M.EV_SPIN then axis, f = C_YAW, fy end
    if p ~= M.EV_LOOP and ss[axis] * S.pendDir >= cfg.MULTI_DEG
        and S.pendCount < cfg.MAX_ROTATIONS then
      S.pendCount = S.pendCount + 1
      S.pendT = t
      clearSticks(S)
    else
      for c = C_ROLL, C_YAW do
        if c ~= axis and abs(ss[c]) >= cfg.CANDIDATE_DEG then clearSticks(S) end
      end
    end
    local settled = abs(f) < cfg.SETTLE_FRAC
    local limit = (p == M.EV_LOOP) and cfg.LOOP_CONFIRM_TIME or cfg.CONFIRM_TIME
    if p == M.EV_SPIN then
      -- Telemetry yaw lags the sticks: wait until it has seen every commanded
      -- rotation; at the deadline, score what it did see.
      S.pendYaw = S.pendYaw + dYaw
      local acc = abs(S.pendYaw)
      local seen = 0
      if acc >= cfg.SPIN_CONFIRM_DEG then
        seen = 1 + floor((acc - cfg.SPIN_CONFIRM_DEG) / 360)
        if seen > S.pendCount then seen = S.pendCount end
      end
      if settled and (seen == S.pendCount or (seen > 0 and t - S.pendT > limit)) then
        return award(S, t, p, seen)
      end
    elseif settled and S.lastInvT >= S.pendWin and S.lastUpT > S.lastInvT then
      -- A back rotation that paused inverted in its (last) inverted episode
      -- is a Matty flip
      if (p == M.EV_BACK or p == M.EV_LOOP) and S.hangOkT >= S.pendWin then
        return award(S, t, M.EV_MATTY, 1)
      end
      local n = episodesSince(S, S.pendWin)
      if n > S.pendCount then n = S.pendCount end
      if n < 1 then n = 1 end
      return award(S, t, p, n)
    end
    if t - S.pendT > limit then
      S.pending = 0
      return event(S, t, M.EV_MISS)
    end
  end

  -- Open a candidate
  if S.pending == 0 and t >= S.cooldownUntil and not S.crashLatched
      and t - S.lastThrT <= cfg.THR_RECENT then
    local ar, ap, ay = abs(ss[C_ROLL]), abs(ss[C_PITCH]), abs(ss[C_YAW])
    local cand, dir, win = 0, 1, cfg.WINDOW
    if ay >= cfg.SPIN_CANDIDATE_DEG and ay >= ar and ay >= ap then
      cand, dir = M.EV_SPIN, (ss[C_YAW] > 0) and 1 or -1
    elseif ar >= cfg.CANDIDATE_DEG and ar >= ap then
      cand, dir = M.EV_ROLL, (ss[C_ROLL] > 0) and 1 or -1
    elseif ap >= cfg.CANDIDATE_DEG then
      if ss[C_PITCH] > 0 then
        cand = M.EV_FRONT
      else
        dir = -1
        local thrAvg = ss[C_DT] > 0 and ss[C_THR] / ss[C_DT] or 0
        cand = (thrAvg >= cfg.LOOP_THR_AVG) and M.EV_LOOP or M.EV_BACK
      end
    elseif sl[C_PITCH] <= -cfg.LOOP_CANDIDATE_DEG then
      -- slow back-pitch rotation (up to LOOP_WINDOW): power loop or slow back flip
      dir, win = -1, cfg.LOOP_WINDOW
      local thrAvg = sl[C_DT] > 0 and sl[C_THR] / sl[C_DT] or 0
      cand = (thrAvg >= cfg.LOOP_THR_AVG) and M.EV_LOOP or M.EV_BACK
    end
    if cand ~= 0 then
      if cand == M.EV_LOOP then win = cfg.LOOP_WINDOW end
      S.pending, S.pendT, S.pendWin = cand, t, t - win
      S.pendCount, S.pendDir = 1, dir
      S.pendYaw = ss[C_YAWATT]
      clearSticks(S)
    end
  end

  -- Crash: tilted beyond CRASH_TILT for CRASH_TIME with sticks centred (the
  -- time counts from when they were centred) and no trick rotation commanded.
  if not S.crashLatched and S.tiltSince then
    local since = S.tiltSince
    local graceEnd = S.armT + cfg.ARM_GRACE
    if since < graceEnd then since = graceEnd end
    if since < S.lastStickT then since = S.lastStickT end
    if t - since >= cfg.CRASH_TIME
        and abs(ss[C_ROLL]) < cfg.CRASH_MAX_WINDOW_DEG
        and abs(ss[C_PITCH]) < cfg.CRASH_MAX_WINDOW_DEG then
      return crash(S, t)
    end
  end

  -- Orbit: banked turn with a continuous 360 heading change
  if attOk and not S.crashLatched then
    local bank = S.lastRollD
    local ok = abs(bank) >= cfg.ORBIT_MIN_BANK and abs(bank) <= 90
      and abs(S.lastPitchD) <= cfg.ORBIT_MAX_PITCH and t - S.lastThrT <= cfg.THR_RECENT
    local sgn = bank > 0 and 1 or -1
    if ok and S.orbBank ~= 0 and sgn ~= S.orbBank then ok = false end
    if ok and dYaw ~= 0 and abs(S.orbAcc) >= 30 and (dYaw > 0) ~= (S.orbAcc > 0) then
      ok = false   -- heading reversed
    end
    if ok then
      if S.orbBank == 0 then S.orbBank, S.orbAcc, S.orbStart = sgn, 0, t end
      S.orbAcc = S.orbAcc + dYaw
      S.orbOkT = t
    elseif S.orbBank ~= 0 and t - S.orbOkT > cfg.ORBIT_GAP then
      resetOrbit(S)
    end
    if abs(S.orbAcc) >= 360 then
      local el = t - S.orbStart
      S.orbAcc, S.orbStart = 0, t
      if el >= cfg.ORBIT_MIN_TIME and el <= cfg.ORBIT_MAX_TIME then
        return award(S, t, M.EV_ORBIT, 1)
      end
    end
  end

  -- Freestyle score every STYLE_PERIOD
  if S.stTime >= cfg.STYLE_PERIOD then
    local P = S.stTime
    local stick = S.stStk / (3 * P) / cfg.STYLE_STICK_FULL
    if stick > 1 then stick = 1 end
    local punch = S.stDThr / P / cfg.STYLE_PUNCH_FULL
    if punch > 1 then punch = 1 end
    local thrAvg = S.stThr / P
    local style = cfg.STYLE_W_STICK * stick + cfg.STYLE_W_THR * thrAvg + cfg.STYLE_W_PUNCH * punch
    local attRate = S.stAtt / P
    S.styleNow = style
    resetStyle(S)
    if style >= cfg.STYLE_MIN and attRate >= cfg.STYLE_MIN_ATT_RATE and not S.crashLatched then
      local pts = floor(cfg.STYLE_POINTS * (style - cfg.STYLE_MIN) / (1 - cfg.STYLE_MIN) + 0.5)
      if pts < 1 then pts = 1 end
      S.score = S.score + pts
      S.stylePts = S.stylePts + pts
      S.counts[M.EV_STYLE] = S.counts[M.EV_STYLE] + 1
      S.lastCount = 1
      if not msgActive(S, t) then
        setMsg(S, t, M.fit(style >= cfg.STYLE_FULL and S.msgs[MSG_FULLSEND] or S.msgs[M.EV_STYLE], S.score))
      end
      checkBest(S)
      return event(S, t, M.EV_STYLE)
    end
  end

  -- "NEW BEST!" once the current message has finished
  if S.bestQueued and not msgActive(S, t) then
    S.bestQueued = false
    setMsg(S, t, M.fit(S.msgs[M.EV_BEST], S.score))
    return event(S, t, M.EV_BEST)
  end

  return M.EV_NONE
end

-- Text the OSD should show now, or nil for "restore the original name".
-- Builds a new string only when the score changes.
function M.osdText(S, t)
  if not S.armed then return nil end
  if msgActive(S, t) then return S.msgText end
  if S.score ~= S.txtScore then
    S.txtScore = S.score
    S.txt = M.fit(S.msgs[MSG_SCOREMSG], S.score)
  end
  return S.txt
end

-- Length in seconds of a WAV clip from its first 44 bytes (the plain header
-- tools/make_voice.py writes), or nil if the header isn't that layout.
function M.wavSecs(h)
  if type(h) ~= "string" or #h < 44 or string.sub(h, 1, 4) ~= "RIFF"
      or string.sub(h, 37, 40) ~= "data" then
    return nil
  end
  local r1, r2, r3, r4 = string.byte(h, 25, 28)
  local a1, a2 = string.byte(h, 33, 34)
  local s1, s2, s3, s4 = string.byte(h, 41, 44)
  local rate = r1 + r2 * 256 + r3 * 65536 + r4 * 16777216
  local align = a1 + a2 * 256
  if rate == 0 or align == 0 then return nil end
  return (s1 + s2 * 256 + s3 * 65536 + s4 * 16777216) / (rate * align)
end

return M
