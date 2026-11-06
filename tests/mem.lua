-- Memory guard. B&W radios have little RAM for Lua, and a version that grew
-- too big failed on a Pocket with "not enough memory". This runs the scripts
-- the way EdgeTX does and checks memory stays within budget, so a new
-- feature can't quietly push it up again. Run from the repo root.
--
-- Simulates two starts:
--   first: right after an update, nothing compiled yet. EdgeTX compiles each
--          .lua (keeping debug info in memory) and saves a stripped .luac.
--   later: everything loads from the stripped .luac files.
-- and, in each, flying with the radio screen hidden, then shown (ui.lua is
-- only loaded while it's shown). Peak memory is sampled before every
-- garbage collection, which EdgeTX also runs every cycle.
--
-- Numbers are desktop Lua 5.4 (64-bit) bytes, not the radio's (Lua 5.2,
-- 32-bit). They are for comparing versions. For reference, the version that
-- ran on the Pocket (git ac925b8) measured: first start peak 50 KB, flying
-- 48 KB; the one that failed: ~115 KB.

local BUDGET = {           -- KB, Lua 5.4 units (see above)
  peak = 84,               -- highest point, either start
  hidden = 74,             -- flying, screen hidden
  shown = 84,              -- flying, screen shown
}

local FILES = { "/SCRIPTS/TELEMETRY/trick.lua", "/SCRIPTS/TRICKS/core.lua",
  "/SCRIPTS/TRICKS/msp.lua", "/SCRIPTS/TRICKS/config.lua",
  "/SCRIPTS/TRICKS/radio.lua", "/SCRIPTS/TRICKS/ui.lua" }

local realCollect = collectgarbage
local function count() return realCollect("count") * 1024 end
local function kb(b) return string.format("%.1f KB", b / 1024) end

local function measure(first)
  local values = { ail = 0, ele = 0, rud = 0, thr = -1024, Ptch = 0, Roll = 0, Yaw = 0, FM = "ACRO*" }
  local ids, names, n = {}, {}, 0
  for k in pairs(values) do n = n + 1; ids[k] = n; names[n] = k end
  local now, base, peak, peakAt = 0, 0, 0, ""
  local function sample(at)
    local c = count() - base
    if c > peak then peak, peakAt = c, at end
  end
  local env = setmetatable({}, { __index = _G })
  env.collectgarbage = function(...) sample("gc"); return realCollect(...) end
  env.io = {                       -- the voice pack is read; nothing else exists
    open = function(p) if p:match("%.wav$") then return io.open("." .. p, "rb") end end,
    read = function(f, len) return f:read(len) or "" end,
    write = function() end,
    close = function(f) f:close() end,
  }
  local luac, compiled = {}, {}    -- stripped bytecode stands in for .luac files
  for _, p in ipairs(FILES) do luac[p] = string.dump(assert(loadfile("." .. p, "t", env)), true) end
  env.loadScript = function(path)
    if compiled[path] or not first then
      local f = load(luac[path], path, "b", env)
      sample("load " .. path)
      return f
    end
    compiled[path] = true
    realCollect("stop")
    local f = assert(loadfile("." .. path, "t", env))
    sample("compile " .. path)
    realCollect("restart")
    return f
  end
  env.getTime = function() return now end
  env.getRSSI = function() return 100 end
  env.getFieldInfo = function(name) if ids[name] then return { id = ids[name] } end end
  env.getValue = function(id) return values[names[id]] end
  for _, k in ipairs({ "playTone", "playFile", "playNumber", "playHaptic" }) do env[k] = function() end end
  env.crossfireTelemetryPush = function() return true end
  env.crossfireTelemetryPop = function() end
  env.SMLSIZE, env.MIDSIZE, env.DBLSIZE, env.INVERS, env.RIGHT, env.BLINK, env.BOLD = 1, 2, 4, 8, 16, 32, 64
  env.LCD_W, env.LCD_H = 128, 64
  env.EVT_VIRTUAL_ENTER, env.EVT_VIRTUAL_NEXT, env.EVT_VIRTUAL_PREV = 100, 101, 102
  env.lcd = setmetatable({ getLastRightPos = function() return 0 end },
    { __index = function() return function() end end })

  realCollect("collect")
  base = count()
  local script = env.loadScript("/SCRIPTS/TELEMETRY/trick.lua")()
  script.init()
  values.FM, values.thr = "ACRO", 0
  local hidden, shown, rehidden
  local function fly(ticks, showScreen)
    for i = 1, ticks do
      now = now + 2
      values.ail = math.sin(now / 40)
      values.Roll = (now % 200) / 60
      script.background()
      if showScreen and i % 2 == 0 then script.run(0) end
      realCollect("collect")
      sample("flying")
    end
    return count() - base
  end
  hidden = fly(2000, false)    -- also lets the voice clip scan finish
  shown = fly(1000, true)
  rehidden = fly(300, false)   -- screen code freed again after 1 s hidden
  return { peak = peak, peakAt = peakAt, hidden = hidden, shown = shown, rehidden = rehidden }
end

local ok = true
for _, first in ipairs({ true, false }) do
  local m = measure(first)
  print(string.format("%-12s peak %s (%s) | flying, screen hidden %s | shown %s",
    first and "first start" or "later start", kb(m.peak), m.peakAt, kb(m.hidden), kb(m.shown)))
  for _, k in ipairs({ "peak", "hidden", "shown" }) do
    if m[k] > BUDGET[k] * 1024 then
      print(string.format("  over budget: %s %s > %d KB", k, kb(m[k]), BUDGET[k]))
      ok = false
    end
  end
  if m.rehidden > m.hidden + 1024 then
    print("  screen code was not freed after the screen was hidden")
    ok = false
  end
end
assert(ok, "memory over budget")
print("mem ok")
