-- Static check: radio scripts may only use what EdgeTX 2.10 provides on a
-- black & white radio (e.g. Radiomaster Pocket). Lists taken from EdgeTX 2.10
-- radio/src/thirdparty/Lua/src/{linit,lbaselib,lstrlib,lmathlib,lbitlib}.c:
--   * no `table` library (colour radios only)
--   * no global `unpack`, no `loadstring` (compile options, off)
--   * string methods (s:upper()) need LUA_ENABLE_STRLIB_MT, so avoid them
-- Uses `luac -l` (Lua 5.4) to list global and library accesses.
-- Run from the repo root:  lua tests/globals.lua

local function set(s) local t = {} for w in s:gmatch("%S+") do t[w] = true end return t end

local GLOBALS = set([[
  assert collectgarbage dofile error getmetatable ipairs loadfile load next
  pairs pcall print rawequal rawlen rawget rawset select setmetatable
  tonumber tostring type xpcall
  io string math bit32 lcd model bitmap
  getTime getValue getFieldInfo getRSSI loadScript playTone playFile playHaptic playNumber
  crossfireTelemetryPush crossfireTelemetryPop
  LCD_W LCD_H SMLSIZE MIDSIZE DBLSIZE INVERS RIGHT BLINK BOLD
  EVT_VIRTUAL_ENTER EVT_VIRTUAL_NEXT EVT_VIRTUAL_PREV
]])

local LIBS = {
  string = set("byte char dump find format gmatch gsub len lower match rep reverse sub upper"),
  math = set([[abs acos asin atan2 atan ceil cosh cos deg exp floor fmod frexp
    ldexp log max min modf pow rad random randomseed sinh sin sqrt tanh tan pi huge]]),
  bit32 = set("arshift band bnot bor bxor btest extract lrotate lshift replace rrotate rshift"),
  lcd = set([[clear drawText drawNumber drawFilledRectangle drawRectangle drawLine drawPoint
    drawTimer drawGauge getLastPos getLastRightPos getLastLeftPos]]),
  io = set("open read write close seek"),   -- EdgeTX style: io.read(file, len)
}

local files = (arg and #arg > 0) and arg or {
  "SCRIPTS/TELEMETRY/trick.lua",
  "SCRIPTS/TRICKS/radio.lua",
  "SCRIPTS/TRICKS/ui.lua",
  "SCRIPTS/TRICKS/core.lua",
  "SCRIPTS/TRICKS/msp.lua",
  "SCRIPTS/TRICKS/config.lua",
}

local bad = 0
local function report(f, line, msg)
  print(string.format("  %s:%s %s", f, line:match("%[(%d+)%]") or "?", msg))
  bad = bad + 1
end

for _, f in ipairs(files) do
  local p = assert(io.popen("luac -p -l '" .. f .. "' 2>&1"))
  local out = p:read("a")
  p:close()
  if not out:match("^%s*main <") then
    print("  " .. f .. ": luac failed: " .. out)
    bad = bad + 1
  end
  local libReg, lib = nil, nil
  for line in out:gmatch("[^\n]+") do
    local reg, name = line:match("GETTABUP%s+(%d+)%s+%d+%s+%d+.-_ENV \"([%w_]+)\"")
    local sname = line:match("SETTABUP.-_ENV \"([%w_]+)\"")
    if reg then
      if not GLOBALS[name] then
        report(f, line, "uses global '" .. name .. "', not on EdgeTX 2.10 B&W")
      end
      if LIBS[name] then libReg, lib = reg, name else libReg, lib = nil, nil end
    else
      if sname then report(f, line, "assigns global '" .. sname .. "'") end
      local src, field = line:match("GETFIELD%s+%d+%s+(%d+)%s+%d+.-\"([%w_]+)\"")
      if lib and src == libReg and field and not LIBS[lib][field] then
        report(f, line, "uses " .. lib .. "." .. field .. ", not on EdgeTX 2.10 B&W")
      end
      if line:match("%sSELF%s") then
        report(f, line, "uses a method call (obj:fn()); string methods need LUA_ENABLE_STRLIB_MT")
      end
      libReg, lib = nil, nil
    end
  end
end

if bad > 0 then
  print(bad .. " problem(s)")
  os.exit(1)
end
print("globals ok (" .. #files .. " files, EdgeTX 2.10 B&W library set)")
