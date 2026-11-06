-- Smoke test for the EdgeTX wrapper with stubbed EdgeTX APIs.
-- Runs init/background/run through two short simulated flights to catch typos
-- and API misuse in SCRIPTS/TELEMETRY/trick.lua and the modules it loads. Run from the repo root:
--   lua tests/smoke.lua

local now = 0                    -- 10 ms ticks
local values = { ail = 0, ele = 0, rud = 0, thr = -1024, Ptch = 0, Roll = 0, Yaw = 0, FM = "ACRO*" }
local ids, names = {}, {}
local n = 0
for k in pairs(values) do n = n + 1; ids[k] = n; names[n] = k end
local sent, inbox, tones, drawn = {}, {}, 0, 0
local V = "/SCRIPTS/TRICKS/voice/"
local files = { ["/SCRIPTS/TRICKS/best.txt"] = "5",     -- fake SD card
                [V .. "arm/1.wav"] = "", [V .. "roll/1.wav"] = "", [V .. "roll/3.wav"] = "",
                [V .. "combo2/1.wav"] = "", [V .. "score/1.wav"] = "" }  -- some callouts missing
local played = {}
local lastRight = 0
local pagesSeen = {}

-- Integer check: EdgeTX's luaL_checkinteger silently truncates decimals.
local isInt = math.type and function(v) return math.type(v) == "integer" end
  or function(v) return v == math.floor(v) end
local function ints(...)
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    assert(type(v) == "number" and isInt(v), "expected integer argument #" .. i .. ", got " .. tostring(v))
  end
end

-- Sandbox with only what EdgeTX 2.10 provides on a black & white radio (e.g.
-- Pocket): base functions (no unpack, no loadstring), io, string, math, bit32,
-- lcd, model. There is NO `table` library (colour radios only).
local env = {}
for name in ([[assert collectgarbage dofile error getmetatable ipairs loadfile
  load next pairs pcall print rawequal rawlen rawget rawset select
  setmetatable tonumber tostring type xpcall]]):gmatch("%S+") do
  env[name] = _G[name]
end
local function only(lib, names)
  local t = {}
  for n in names:gmatch("%S+") do t[n] = lib[n] end
  return t
end
env.string = only(string, "byte char dump find format gmatch gsub len lower match rep reverse sub upper")
env.math = only(math, [[abs acos asin atan ceil cos deg exp floor fmod log max min
  modf rad random randomseed sin sqrt tan pi huge]])
env.bit32 = bit32                            -- nil on desktop 5.4; msp.lua has a fallback

-- EdgeTX's io API (not desktop Lua's): io.read(file, len), io.write(file, ...)
env.io = {
  open = function(path, mode)
    if mode == "r" then
      if not files[path] then return nil end
      return { path = path, pos = 1 }
    end
    files[path] = ""
    return { path = path, pos = 1 }
  end,
  read = function(f, len)
    assert(type(f) == "table", "io.read(file, len): EdgeTX takes the file first")
    local s = files[f.path]:sub(f.pos, f.pos + len - 1)
    f.pos = f.pos + #s
    return s
  end,
  write = function(f, ...)
    assert(type(f) == "table", "io.write(file, ...): EdgeTX takes the file first")
    for i = 1, select("#", ...) do files[f.path] = files[f.path] .. tostring(select(i, ...)) end
  end,
  close = function(f) assert(type(f) == "table") end,
}

-- EdgeTX API stubs
local uiFails, lowMemShown = true, false   -- first screen load: out of memory
env.loadScript = function(path)
  if uiFails and path:match("ui%.lua$") and now > 0 then
    return nil, "not enough memory"
  end
  local chunk = loadfile("." .. path, "t", env)
  if not path:match("config%.lua$") then return chunk end
  return function()                         -- the voice settings this test expects
    local c = chunk()
    c.VOICE, c.VOICE_SCORE, c.VOICE_GENERIC = true, true, 0
    return c
  end
end
env.getTime = function() return now end
env.getRSSI = function() return 100 end
env.getFieldInfo = function(name) if ids[name] then return { id = ids[name] } end end
env.getValue = function(id) return values[names[id]] end
env.playTone = function(f, d, p, fl, inc) ints(f, d, p, fl or 0, inc or 0); tones = tones + 1 end
env.playFile = function(path)
  assert(#path <= 42, "EdgeTX ignores audio paths over 42 chars: " .. path)
  assert(files[path], "played a file that is not on the SD card: " .. path)
  played[#played + 1] = path:match("([^/]+/[^/]+)%.wav$")
end
env.playNumber = function(v, unit) ints(v, unit); played[#played + 1] = tostring(v) end
env.playHaptic = function(d, p) ints(d, p) end
env.crossfireTelemetryPush = function(cmd, data)
  if cmd == nil then return true end
  local copy = {}                            -- msp.lua reuses its frame table
  for i = 1, #data do copy[i] = data[i] end
  sent[#sent + 1] = { cmd = cmd, data = copy }
  -- Answer MSP_NAME reads like Betaflight (single chunk, v1)
  if cmd == 0x7A and data[5] == 10 then
    inbox[#inbox + 1] = { 0xEA, 0xC8, 0x30, 5, 10, 87, 72, 79, 79, 80, 0 }
  elseif cmd == 0x7C and data[5] == 11 then
    inbox[#inbox + 1] = { 0xEA, 0xC8, 0x30, 0, 11, 11 }
  end
  return true
end
env.crossfireTelemetryPop = function()
  local d = table.remove(inbox, 1)
  if d then return 0x7B, d end
end
env.SMLSIZE, env.MIDSIZE, env.DBLSIZE, env.INVERS = 1, 2, 4, 8
env.RIGHT, env.BLINK, env.BOLD = 16, 32, 64
env.LCD_W, env.LCD_H = 128, 64
env.EVT_VIRTUAL_ENTER, env.EVT_VIRTUAL_NEXT, env.EVT_VIRTUAL_PREV = 100, 101, 102
local function text(x, y, s, f)
  ints(x, y, f or 0)
  assert(type(s) == "string", "drawText needs a string")
  assert(x >= 0 and x < 128 and y >= 0 and y < 64, "off screen: " .. x .. "," .. y .. " " .. s)
  lastRight = x + 5 * #s
  drawn = drawn + 1
  if s == "TRICKS: LOW MEMORY" then lowMemShown = true; uiFails = false end
  if s == "TRICKS" or s == "LAST FLIGHT" or s == "THIS FLIGHT" or s == "STATUS" then pagesSeen[s] = true end
end
env.lcd = {
  clear = function() end,
  drawText = text,
  drawNumber = function(x, y, v, f) ints(x, y, v, f or 0); text(x, y, tostring(v), f) end,
  drawTimer = function(x, y, v, f) ints(x, y, v, f or 0); text(x, y, "00:00", f) end,
  drawGauge = function(x, y, w, h, num, den, f) ints(x, y, w, h, num, den, f or 0) end,
  drawFilledRectangle = function(x, y, w, h, f) ints(x, y, w, h, f or 0) end,
  getLastRightPos = function() return lastRight end,
}
-- Any other global access is an error, like on the radio.
setmetatable(env, { __index = function(_, k)
  if k == "bit32" then return nil end      -- exists on the radio, not in desktop 5.4
  error("global '" .. tostring(k) .. "' is not available on B&W EdgeTX", 2)
end })

local script = assert(loadfile("SCRIPTS/TELEMETRY/trick.lua", "t", env))()
script.init()

local function step(secs, roll, pitch, rollRate, event)
  for _ = 1, math.floor(secs * 50) do
    now = now + 2
    values.ail, values.ele = roll * 1024, pitch * 1024
    if rollRate then values.Roll = ((values.Roll + rollRate * 0.02 + math.pi) % (2 * math.pi)) - math.pi end
    if now % 4 == 0 then script.run(event or 0); event = nil else script.background() end
  end
end

step(2, 0, 0)                               -- disarmed, name read
values.FM, values.thr = "ACRO", 0
step(3, 0, 0)                               -- armed, past grace
step(0.6, 1, 0, math.rad(600))              -- roll
values.Roll = 0
step(1.0, 0, 0)
step(0.6, 1, 0, math.rad(600))              -- second roll: combo X2
values.Roll = 0
step(2.5, 0, 0)
values.FM = "ACRO*"
step(1.5, 0, 0)                             -- disarm: summary page, best saved
step(0.1, 0, 0, nil, env.EVT_VIRTUAL_ENTER) -- -> status page
step(0.1, 0, 0, nil, env.EVT_VIRTUAL_NEXT)  -- -> live page

-- Decode the SET_NAME writes that went out.
local writes, cur = {}, nil
for _, fr in ipairs(sent) do
  if fr.cmd == 0x7C then
    local d = fr.data
    if math.floor(d[3] / 16) % 2 == 1 then cur = {}; writes[#writes + 1] = cur end
    for k = 4, #d do cur[#cur + 1] = d[k] end
  end
end
local texts = {}
for _, w in ipairs(writes) do
  local s = {}
  for k = 3, w[1] + 2 do s[#s + 1] = string.char(w[k]) end
  texts[#texts + 1] = table.concat(s)
end
print("OSD writes: " .. table.concat(texts, " | "))
print("voice: " .. table.concat(played, " "))
print("tones: " .. tones .. ", draw calls: " .. drawn .. ", best.txt: " .. files["/SCRIPTS/TRICKS/best.txt"])
local function wrote(s) for _, x in ipairs(texts) do if x == s then return true end end end
assert(texts[1] == "SCORE 0", "first write is SCORE 0")
assert(wrote("NICE ROLL! 10"), "roll message written")
assert(wrote("NICE ROLL! X2"), "combo message written")
assert(wrote("NEW BEST! 30"), "new best announced (previous best 5)")
assert(texts[#texts] == "WHOOP", "original name restored on disarm")
assert(files["/SCRIPTS/TRICKS/best.txt"] == "30", "best score saved")
assert(tones > 0, "tones for clips that are missing")
local heard = table.concat(played, " ")
assert(heard == "arm/1 roll/1 roll/3 combo2/1 score/1 30"
    or heard == "arm/1 roll/3 roll/1 combo2/1 score/1 30",
  "voice callouts: arm, both roll clips (gap skipped, no repeat), combo, final score")
assert(lowMemShown, "fallback screen when the screen code can't load")
assert(pagesSeen["TRICKS"] and pagesSeen["LAST FLIGHT"] and pagesSeen["STATUS"],
  "all pages drawn once memory allows")
print("smoke ok")
