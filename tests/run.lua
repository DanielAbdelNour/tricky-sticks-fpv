-- Unit tests. Run from the repo root:  lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path

local core = dofile("SCRIPTS/TRICKS/core.lua")
local msp = dofile("SCRIPTS/TRICKS/msp.lua")
local Sim = require("sim")

local function config(over)
  local c = dofile("SCRIPTS/TRICKS/config.lua")
  for k, v in pairs(over or {}) do c[k] = v end
  return c
end

local passed, failed = 0, 0
local current
local function check(cond, msg)
  if not cond then
    error(msg or "check failed", 2)
  end
end
local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
  end
end
local function test(name, fn)
  current = name
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. "\n       " .. tostring(err))
  end
end

local E = core

print("Detection")

test("clean roll right scores 10", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5)        -- 360 deg at 600 deg/s
  s:run(0.3, 0, 0, 0.4)
  eq(s:count(E.EV_ROLL), 1, "rolls")
  eq(s.S.score, 10, "score")
  eq(s.text, "NICE ROLL! 10", "osd text")
  s:run(2.0, 0, 0, 0.4)
  eq(s.text, "SCORE 10", "falls back to score")
  eq(s:count(E.EV_MISS), 0, "misses")
end)

test("clean roll left scores 10", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, -1, 0, 0.5)
  s:run(1.0, 0, 0, 0.4)
  eq(s:count(E.EV_ROLL), 1, "rolls")
  eq(s.S.score, 10, "score")
end)

test("front flip scores 25", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 0, 1, 0.3)
  s:run(1.0, 0, 0, 0.4)
  eq(s:count(E.EV_FRONT), 1, "front flips")
  eq(s:count(E.EV_BACK), 0, "back flips")
  eq(s.S.score, 25, "score")
end)

test("back flip scores 25", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 0, -1, 0.3)
  s:run(0.2, 0, 0, 0.4)
  eq(s.text, "BACK FLIP! 25", "osd text")
  s:run(0.8, 0, 0, 0.4)
  eq(s:count(E.EV_BACK), 1, "back flips")
  eq(s.S.score, 25, "score")
end)

test("roll + front flip + back flip in quick succession build a combo", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5);  s:run(1.0)
  eq(s.text, "NICE ROLL! 10", "first trick shows score")
  s:run(0.6, 0, 1, 0.5);  s:run(1.0)
  eq(s.text, "FRONT FLIP! X2", "second trick shows combo")
  s:run(0.6, 0, -1, 0.3); s:run(1.0)
  eq(s.text, "BACK FLIP! X3", "third trick shows combo")
  eq(s.S.score, 10 + 25 * 2 + 25 * 3, "score with multipliers")
  eq(s.S.bestCombo, 3, "best combo")
end)

test("crash: stuck on its side with sticks centred", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 10, "score before crash")
  s:setAttitude(95, 0)
  s:run(1.5, 0, 0, 0)
  eq(s:count(E.EV_CRASH), 1, "crashes")
  eq(s.S.score, 10, "default penalty is 0")
  check(s.text == "CRASH! 10" or s.text == "SCORE 10", "osd shows crash then score")
  s:run(3.0, 0, 0, 0)
  eq(s:count(E.EV_CRASH), 1, "crash is latched while still tilted")
end)

test("crash penalty is applied", function()
  local s = Sim.new(core, config({ CRASH_PENALTY = 5 }))
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  s:setAttitude(180, 0)
  s:run(1.5, 0, 0, 0)
  eq(s.S.score, 5, "score")
end)

test("crash cancels a trick being evaluated", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.26, 0, 1, 0.5)          -- quad pitches ~150 deg...
  s.locked = true                 -- ...and gets stuck there (hit the floor)
  s:run(0.30, 0, 1, 0.5)          -- stick keeps going: candidate opens
  check(s.S.pending ~= 0 or s:count(E.EV_MISS) == 0, "candidate was opened")
  s:run(2.0, 0, 0, 0)
  eq(s:count(E.EV_CRASH), 1, "crashes")
  eq(s:count(E.EV_FRONT), 0, "no flip scored")
  eq(s.S.score, 0, "score")
end)

test("crash on disarm while tilted", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:setAttitude(90, 0)
  s:run(0.4, 0, 0, 0)
  s.armed = false
  s:run(0.2, 0, 0, 0)
  eq(s:count(E.EV_CRASH), 1, "crashes")
  eq(s.text, nil, "disarmed: restore original name")
end)

test("stick flicks while disarmed never score", function()
  for _, suffix in ipairs({ "*", "!", "?" }) do
    local s = Sim.new(core, config())
    s.fmSuffix = suffix
    s:run(3.0, 0, 0, 0)
    s:run(0.6, 1, 0, 0.5); s:run(1.0)
    s:run(0.6, 0, 1, 0.5); s:run(1.0)
    eq(#s.events, 0, "events with suffix " .. suffix)
    eq(s.S.score, 0, "score")
    eq(s.text, nil, "no OSD text while disarmed")
  end
end)

test("stick flicks while armed with no real rotation never score", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s.locked = true
  s:run(0.6, 1, 0, 0.5);  s:run(1.5)
  s:run(0.6, 0, 1, 0.5);  s:run(1.5)
  s:run(0.6, 0, -1, 0.5); s:run(1.5)
  eq(s.S.score, 0, "score")
  eq(s:count(E.EV_MISS), 3, "three unconfirmed candidates")
  eq(s:count(E.EV_CRASH), 0, "no crash")
end)

test("trick right after arming doesn't score", function()
  local s = Sim.new(core, config())
  s.armed = true
  s:run(0.3, 0, 0, 0.5)
  s:run(0.6, 1, 0, 0.5)
  s:run(0.6, 0, 0, 0.4)
  eq(s:count(E.EV_ROLL), 0, "rolls")
  eq(s.S.score, 0, "score")
  s:run(1.0)                       -- grace over: next roll counts
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 10, "score after grace")
end)

test("turtle mode: armed inverted, flipping over doesn't score or crash", function()
  local s = Sim.new(core, config())
  s:setAttitude(180, 0)
  s:run(0.5, 0, 0, 0)
  s.armed = true
  s:run(3.0, 0, 0, 0)              -- sitting upside down, armed
  s:run(0.3, 1, 0, 0.2)            -- turtle flip over (180 deg)
  s:run(1.0, 0, 0, 0)
  eq(s:count(E.EV_TURTLE), 1, "turtle detected")
  eq(s:count(E.EV_CRASH), 0, "no crash")
  eq(s:count(E.EV_ROLL), 0, "no roll")
  s:run(1.5)                       -- grace restarted after turtle ends
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 10, "normal flying scores afterwards")
end)

test("one messy 1.5 rotation counts once (cooldown)", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.9, 1, 0, 0.5)            -- 540 deg
  s:run(1.5, 0, 0, 0.4)
  eq(s:count(E.EV_ROLL), 1, "rolls")
  eq(s.S.score, 10, "score")
end)

test("score resets on each new arm", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 10, "first flight")
  s.armed = false; s:run(1.0)
  s:armAndHover()
  eq(s.S.score, 0, "second flight")
  eq(s.text, "SCORE 0", "osd shows zero")
end)

test("zero throttle for a while blocks candidates", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(2.0, 0, 0, 0)
  s.locked = true
  s:run(0.6, 1, 0, 0)
  s:run(1.5, 0, 0, 0)
  eq(#s.events, 1, "only the arm event")
end)

test("works with 5 Hz attitude telemetry and 150 ms latency", function()
  local s = Sim.new(core, config(), { attHz = 5, latency = 0.15 })
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.2)
  s:run(0.6, 0, 1, 0.5); s:run(1.2)
  eq(s.S.score, 10 + 25 * 2, "score (second trick is a X2 combo)")
end)

test("1 Hz attitude telemetry is too slow to confirm (documented limit)", function()
  local s = Sim.new(core, config(), { attHz = 1 })
  s:armAndHover()
  local scored = 0
  for _ = 1, 5 do
    s:run(0.6, 1, 0, 0.5); s:run(1.5)
  end
  scored = s:count(E.EV_ROLL)
  check(scored < 5, "most rolls should be missed at 1 Hz, got " .. scored)
end)


print("Multi-rotation and combos")

test("double roll scores two rotations", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.2, 1, 0, 0.5)            -- 720 deg
  s:run(1.0)
  eq(s:count(E.EV_ROLL), 1, "one trick")
  eq(s.S.lastCount, 2, "rotations")
  eq(s.S.score, 20, "score")
  eq(s.text, "DOUBLE ROLL! 20", "osd")
end)

test("triple front flip scores three rotations", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.8, 0, 1, 0.3)            -- 1080 deg
  s:run(1.0)
  eq(s.S.lastCount, 3, "rotations")
  eq(s.S.score, 75, "score")
  eq(s.text, "TRIPLE FRONT! 75", "osd")
end)

test("sticks alone can't inflate the rotation count", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5)            -- one real roll...
  s.locked = true
  s:run(0.6, 1, 0, 0.5)            -- ...stick keeps going, quad doesn't
  s.locked = false
  s:run(1.0)
  eq(s.S.lastCount, 1, "telemetry saw one inversion")
  eq(s.S.score, 10, "score")
end)

test("combo breaks after COMBO_WINDOW", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(4.0)
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 20, "no multiplier")
  eq(s.text, "NICE ROLL! 20", "osd")
end)

test("crash resets the combo", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(0.5)
  s:setAttitude(95, 0); s:run(1.3, 0, 0, 0)
  eq(s:count(E.EV_CRASH), 1, "crashed")
  s:setAttitude(0, 0); s:run(0.6)
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  eq(s.S.score, 20, "second roll has no multiplier")
end)

print("Spins, orbits, power loops")

test("yaw spin scores 15", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 0, 0, 0.5, 1)         -- 360 yaw
  s:run(1.0)
  eq(s:count(E.EV_SPIN), 1, "spins")
  eq(s.S.score, 15, "score")
  eq(s.text, "SPIN! 15", "osd")
end)

test("double spin", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.2, 0, 0, 0.5, -1)        -- 720 yaw, other direction
  s:run(1.0)
  eq(s.S.lastCount, 2, "rotations")
  eq(s.text, "DOUBLE SPIN! 30", "osd")
end)

test("yaw stick without real rotation doesn't score", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s.locked = true
  s:run(0.6, 0, 0, 0.5, 1); s:run(1.5)
  eq(s.S.score, 0, "score")
  eq(s:count(E.EV_MISS), 1, "unconfirmed")
end)

test("orbit: banked 360 turn over 3 s", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:setAttitude(30, 0)
  s.earthYawRate = 120
  s:run(3.4, 0, 0, 0.5)
  s.earthYawRate = 0
  s:setAttitude(0, 0)
  s:run(0.5)
  eq(s:count(E.EV_ORBIT), 1, "orbits")
  eq(s.S.score, 30, "score")
  eq(s:count(E.EV_SPIN), 0, "not a spin")
end)

test("two orbits in a row", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:setAttitude(-25, 0)
  s.earthYawRate = -150            -- 2.4 s per orbit, plus telemetry delay
  s:run(5.6, 0, 0, 0.5)
  eq(s:count(E.EV_ORBIT), 2, "orbits")
end)

test("flat (unbanked) yaw turn is not an orbit", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s.earthYawRate = 120
  s:run(4.0, 0, 0, 0.5)
  eq(s:count(E.EV_ORBIT), 0, "orbits")
end)

test("fast banked spin is not an orbit", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:setAttitude(30, 0)
  s.earthYawRate = 600
  s:run(0.7, 0, 0, 0.5)
  s.earthYawRate = 0
  s:run(1.0)
  eq(s:count(E.EV_ORBIT), 0, "orbits")
end)

test("power loop: back pitch with throttle up", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.3, 0, -0.6, 0.85)        -- ~380 deg at ~290 deg/s
  s:run(1.5, 0, 0, 0.5)
  eq(s:count(E.EV_LOOP), 1, "loops")
  eq(s:count(E.EV_BACK), 0, "not a back flip")
  eq(s.S.score, 40, "score")
  eq(s.text, "POWER LOOP! 40", "osd")
end)

test("slow power loop (long window)", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.8, 0, -0.45, 0.8)        -- ~370 deg at ~205 deg/s
  s:run(1.5, 0, 0, 0.5)
  eq(s:count(E.EV_LOOP), 1, "loops")
end)

test("same rotation with low throttle is a back flip", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(1.3, 0, -0.6, 0.15)
  s:run(1.5, 0, 0, 0.4)
  eq(s:count(E.EV_LOOP), 0, "loops")
  eq(s:count(E.EV_BACK), 1, "back flips")
end)

print("Freestyle score")

local function aggressive(s, secs)
  local n = math.floor(secs / 0.25)
  for i = 1, n do
    local a = (i % 2 == 0) and 1 or -1
    s:run(0.25, 0.6 * a, -0.5 * a, (i % 2 == 0) and 0.9 or 0.3, 0.3 * a)
  end
end

test("aggressive freestyle earns style points", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  aggressive(s, 10.5)
  check(s:count(E.EV_STYLE) >= 1, "style events: " .. s:count(E.EV_STYLE))
  check(s.S.stylePts > 0, "style points")
  check(s.S.styleNow >= 0.7, "full send level, got " .. s.S.styleNow)
  eq(s.S.score, s.S.stylePts, "only style points")
  eq(s:count(E.EV_CRASH), 0, "no crash")
end)

test("same stick input without the quad moving earns nothing", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s.locked = true
  aggressive(s, 10.5)
  eq(s:count(E.EV_STYLE), 0, "style events")
  eq(s.S.score, 0, "score")
end)

test("calm hover earns nothing", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(11, 0.05, 0.05, 0.4)
  eq(s:count(E.EV_STYLE), 0, "style events")
end)

print("High score and summary")

test("NEW BEST! when passing the saved best, best saved on disarm", function()
  local s = Sim.new(core, config())
  s.S.best = 15
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.0)      -- 10
  eq(s:count(E.EV_BEST), 0, "not yet")
  s:run(0.6, 0, 1, 0.5); s:run(1.0)      -- +50 (X2)
  s:run(2.0)
  eq(s:count(E.EV_BEST), 1, "announced once")
  s:run(0.6, 1, 0, 0.5); s:run(3.0)
  eq(s:count(E.EV_BEST), 1, "still once")
  s.armed = false; s:run(0.2)
  eq(s.S.best, s.S.score, "best updated")
  check(s.S.bestDirty and s.S.newBest, "flagged for saving")
end)

test("no NEW BEST! callout without a previous best", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(3.0)
  eq(s:count(E.EV_BEST), 0, "no callout")
  s.armed = false; s:run(0.2)
  eq(s.S.best, 10, "first best recorded")
end)

test("flight summary counts", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  s:run(0.6, 1, 0, 0.5); s:run(1.0)
  s:run(0.6, 0, 1, 0.5); s:run(1.0)
  s:setAttitude(95, 0); s:run(1.3, 0, 0, 0)
  s.armed = false; s:run(0.2)
  local c = s.S.counts
  eq(c[E.EV_ROLL], 1, "rolls"); eq(c[E.EV_FRONT], 1, "front flips")
  eq(c[E.EV_CRASH], 1, "crashes"); eq(s.S.bestCombo, 2, "best combo")
  check(s.S.flightTime > 5, "flight time")
  eq(s.text, nil, "original name restored")
end)

print("Helpers")

test("parseArmed", function()
  eq(core.parseArmed("ACRO"), true, "ACRO")
  eq(core.parseArmed("AIR"), true, "AIR")
  eq(core.parseArmed("ANGL"), true, "ANGL")
  eq(core.parseArmed("ACRO*"), false, "ACRO*")
  eq(core.parseArmed("AIR!"), false, "AIR!")
  eq(core.parseArmed("ACRO?"), false, "ACRO?")
  eq(core.parseArmed("!FS!"), false, "failsafe")
  eq(core.parseArmed(""), nil, "empty")
  eq(core.parseArmed(nil), nil, "nil")
  eq(core.parseArmed(0), nil, "number")
end)

test("OSD text fits 16 chars", function()
  eq(core.fit("NICE ROLL!", 45), "NICE ROLL! 45", "short")
  local s = core.fit("SUPER MEGA FRONT FLIP!", 1234)
  check(#s <= 16, "length")
  eq(s, "SUPER MEGA 1234", "truncated, trailing space dropped")
  eq(core.fit("FRONT FLIP!", 9999), "FRONT FLIP! 9999", "exactly 16")
  eq(core.fit("FRONT FLIP!", 99999), "FRONT FLIP 99999", "drops the !")
  eq(core.fit("FRONT FLIP!", 123456), "FRONT FLI 123456", "big score")
end)

test("osdText doesn't allocate when nothing changes", function()
  local s = Sim.new(core, config())
  s:armAndHover()
  local a = core.osdText(s.S, s.t)
  local b = core.osdText(s.S, s.t + 0.02)
  check(rawequal(a, b), "same string object")
end)

-- Fake CRSF transport ---------------------------------------------------
local function fakeLink()
  local f = { sent = {}, inbox = {}, ready = true }
  f.push = function(cmd, data)
    if cmd == nil then return f.ready end
    local copy = {}
    for i = 1, #data do copy[i] = data[i] end
    f.sent[#f.sent + 1] = { cmd = cmd, data = copy }
    return true
  end
  f.pop = function()
    local m = table.remove(f.inbox, 1)
    if m then return m.cmd, m.data end
    return nil
  end
  return f
end

-- Reassemble MSP frames as Betaflight would; returns cmd, payload string.
local function decodeFrames(frames)
  local bytes = {}
  for i, fr in ipairs(frames) do
    local d = fr.data
    eq(d[1], 0xC8, "dest FC"); eq(d[2], 0xEA, "origin radio")
    local status = d[3]
    eq(math.floor(status / 32) % 4, 1, "version 1")
    eq(math.floor(status / 16) % 2, i == 1 and 1 or 0, "start flag")
    check(#d <= 10, "frame <= 10 bytes")
    for k = 4, #d do bytes[#bytes + 1] = d[k] end
  end
  local size, cmd = bytes[1], bytes[2]
  local crc = 0
  for k = 1, size + 2 do crc = msp.bxor(crc, bytes[k]) end
  eq(bytes[size + 3], crc, "crc")
  local chars = {}
  for k = 3, size + 2 do chars[#chars + 1] = string.char(bytes[k]) end
  return cmd, table.concat(chars)
end

-- Build a Betaflight MSP reply frame (v1, single chunk).
local function reply(cmd, payload, seq)
  local d = { 0xEA, 0xC8, 0x30 + (seq or 0), #payload, cmd }
  local crc = msp.bxor(#payload, cmd)
  for i = 1, #payload do
    local b = payload:byte(i)
    d[#d + 1] = b
    crc = msp.bxor(crc, b)
  end
  d[#d + 1] = crc
  return { cmd = 0x7B, data = d }
end

print("MSP")

test("MSP_SET_NAME is framed like the Betaflight TX Lua scripts", function()
  local f = fakeLink()
  local L = msp.new(f.push, f.pop)
  check(msp.request(L, msp.MSP_SET_NAME, "BACK FLIP! 25", true), "queued")
  while msp.pump(L) do end
  eq(#f.sent, 3, "frames (2+13+1 bytes / 7 per frame)")
  for _, fr in ipairs(f.sent) do eq(fr.cmd, 0x7C, "MSP write frame type") end
  local cmd, payload = decodeFrames(f.sent)
  eq(cmd, 11, "cmd")
  eq(payload, "BACK FLIP! 25", "payload")
  eq(f.sent[2].data[3] % 16, (f.sent[1].data[3] + 1) % 16, "sequence increments")
end)

test("MSP_NAME read uses request frame type with empty payload", function()
  local f = fakeLink()
  local L = msp.new(f.push, f.pop)
  msp.request(L, msp.MSP_NAME, "", false)
  eq(#f.sent, 1, "one frame")
  eq(f.sent[1].cmd, 0x7A, "MSP request frame type")
  local cmd, payload = decodeFrames(f.sent)
  eq(cmd, 10, "cmd"); eq(payload, "", "empty payload")
end)

test("transport waits while the module isn't ready", function()
  local f = fakeLink()
  f.ready = false
  local L = msp.new(f.push, f.pop)
  msp.request(L, msp.MSP_SET_NAME, "SCORE 0", true)
  eq(#f.sent, 0, "nothing sent")
  check(msp.busy(L), "busy")
  f.ready = true
  while msp.pump(L) do end
  check(not msp.busy(L), "drained")
end)

test("MSP reply is parsed (16-char name)", function()
  local f = fakeLink()
  local L = msp.new(f.push, f.pop)
  msp.request(L, msp.MSP_NAME, "", false)
  f.inbox[1] = { cmd = 0x29, data = { 0xEA, 0xEE, 1, 2, 3 } }   -- unrelated frame
  f.inbox[2] = reply(10, "TINYWHOOP65 ABCD")
  local cmd, err = msp.poll(L)
  eq(cmd, 10, "cmd"); eq(err, false, "no error")
  eq(msp.rxString(L), "TINYWHOOP65 ABCD", "name")
end)

print("Craft name manager")

local function nameRig(over)
  local cfg = config(over)
  local f = fakeLink()
  local L = msp.new(f.push, f.pop)
  local N = msp.newName(cfg, L)
  local rig = { f = f, L = L, N = N, t = 0 }
  function rig.tick(desired, secs, linkUp)
    if linkUp == nil then linkUp = true end
    local n = math.floor((secs or 0.02) / 0.02 + 0.5)
    for _ = 1, n do
      rig.t = rig.t + 0.02
      msp.nameTick(N, rig.t, desired, linkUp)
    end
  end
  -- Collect decoded writes (cmd 11) from sent frames and clear the log.
  function rig.writes()
    local out, group = {}, {}
    for _, fr in ipairs(f.sent) do
      local start = math.floor(fr.data[3] / 16) % 2 == 1
      if start and #group > 0 then
        local c, p = decodeFrames(group); if c == 11 then out[#out + 1] = p end
        group = {}
      end
      group[#group + 1] = fr
    end
    if #group > 0 then
      local c, p = decodeFrames(group); if c == 11 then out[#out + 1] = p end
    end
    f.sent = {}
    return out
  end
  return rig
end

test("reads original name and writes nothing until it is known", function()
  local r = nameRig()
  r.tick("SCORE 0", 0.5)
  eq(#r.writes(), 0, "no writes before name is known")
  r.f.inbox[1] = reply(10, "MY WHOOP")
  r.tick("SCORE 0", 0.1)
  eq(r.N.orig, "MY WHOOP", "original captured")
  r.tick("SCORE 0", 0.1)
  local w = r.writes()
  eq(#w, 1, "one write"); eq(w[1], "SCORE 0", "text")
end)

test("rate limited to 2 writes/s and only on change", function()
  local r = nameRig()
  r.f.inbox[1] = reply(10, "MY WHOOP")
  r.tick(nil, 0.1)
  r.writes()
  -- desired text changes every tick for 2 seconds
  for i = 1, 100 do
    r.tick("SCORE " .. i, 0.02)
    if i % 5 == 0 then r.f.inbox[#r.f.inbox + 1] = reply(11, "") end  -- acks
  end
  local w = r.writes()
  check(#w <= 5 and #w >= 3, "about 2 writes per second, got " .. #w)
  -- unchanged text: no more writes
  for _ = 1, 50 do
    r.tick("SCORE 100", 0.02)
    r.f.inbox[#r.f.inbox + 1] = reply(11, "")
  end
  w = r.writes()
  check(#w <= 1, "at most the final catch-up write, got " .. #w)
  r.tick("SCORE 100", 2.0)
  eq(#r.writes(), 0, "no writes when nothing changes")
end)

test("restores the original name when desired is nil", function()
  local r = nameRig()
  r.f.inbox[1] = reply(10, "MY WHOOP")
  r.tick("SCORE 10", 0.2)
  r.f.inbox[1] = reply(11, "")
  r.tick(nil, 1.0)
  local w = r.writes()
  eq(w[#w], "MY WHOOP", "restored")
end)

test("unacknowledged write is retried", function()
  local r = nameRig()
  r.f.inbox[1] = reply(10, "MY WHOOP")
  r.tick("SCORE 0", 0.2)
  eq(#r.writes(), 1, "first write")
  r.tick("SCORE 0", 2.0)
  check(#r.writes() >= 1, "retried after WRITE_RETRY")
end)

test("recognises its own messages", function()
  local r = nameRig()
  for _, txt in ipairs({ "SCORE 10", "NICE ROLL! 20", "FRONT FLIP! X2", "DOUBLE ROLL! 20",
      "TRIPLE FRONT 75", "POWER LOOP! 40", "FULL SEND! 120", "NEW BEST! 300", "CRASH! -5" }) do
    check(msp.looksOurs(r.N, txt), txt)
  end
  for _, txt in ipairs({ "MY WHOOP", "TINYHAWK 2", "", "MOBULA7" }) do
    check(not msp.looksOurs(r.N, txt), "not ours: " .. txt)
  end
end)

test("after relink, our own text is not taken as the original", function()
  local r = nameRig()
  r.f.inbox[1] = reply(10, "MY WHOOP")
  r.tick("SCORE 10", 0.2)
  msp.relink(r.N)
  r.f.inbox[1] = reply(10, "SCORE 10")
  r.tick(nil, 1.0)
  eq(r.N.orig, "MY WHOOP", "original kept")
  local w = r.writes()
  eq(w[#w], "MY WHOOP", "restored")
end)

test("script restart while FC shows our text uses FALLBACK_NAME", function()
  local r = nameRig()
  r.f.inbox[1] = reply(10, "NICE ROLL! 20")
  r.tick(nil, 1.0)
  eq(r.N.orig, nil, "original unknown")
  eq(#r.writes(), 0, "empty fallback: leave FC alone")
  local r2 = nameRig({ FALLBACK_NAME = "WHOOP" })
  r2.f.inbox[1] = reply(10, "SCORE 5")
  r2.tick(nil, 1.0)
  local w = r2.writes()
  eq(w[#w], "WHOOP", "fallback written")
end)

test("no writes while the RF link is down", function()
  local r = nameRig()
  r.tick("SCORE 0", 3.0, false)
  eq(#r.f.sent, 0, "nothing sent")
end)

test("gives up reading after READ_GIVEUP tries", function()
  local r = nameRig({ READ_GIVEUP = 3, READ_RETRY = 0.5 })
  r.tick("SCORE 0", 3.0)
  check(r.N.gaveUp, "gave up")
  eq(#r.writes(), 0, "WRITE_WITHOUT_NAME=false: still no writes")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
