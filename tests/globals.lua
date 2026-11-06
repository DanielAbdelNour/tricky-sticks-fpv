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

-- Colour radios (widget + its screen) have more: the table library, the
-- colour lcd API (no getLastRightPos there; lcd.sizeText instead), colours
-- and touch. Checked against EdgeTX 2.10/2.11 radio/src/lua/api_colorlcd.cpp
-- and api_general.cpp.
local COLOR_GLOBALS = set([[
  table XXLSIZE CENTER VCENTER SHADOWED
  EVT_TOUCH_FIRST EVT_TOUCH_BREAK EVT_TOUCH_SLIDE EVT_TOUCH_TAP
]])
for k in pairs(GLOBALS) do COLOR_GLOBALS[k] = true end
local COLOR_LIBS = {}
for k, v in pairs(LIBS) do COLOR_LIBS[k] = v end
COLOR_LIBS.table = set("concat insert remove sort unpack")
COLOR_LIBS.lcd = set([[clear drawText drawNumber drawFilledRectangle drawRectangle drawLine drawPoint
  drawTimer drawGauge sizeText RGB setColor getColor drawCircle drawFilledCircle
  drawTriangle drawFilledTriangle drawArc drawPie drawAnnulus exitFullScreen]])

local BW = (arg and #arg > 0) and arg or {
  "SCRIPTS/TELEMETRY/trick.lua",
  "SCRIPTS/TRICKS/radio.lua",
  "SCRIPTS/TRICKS/ui.lua",
  "SCRIPTS/TRICKS/core.lua",
  "SCRIPTS/TRICKS/msp.lua",
  "SCRIPTS/TRICKS/config.lua",
}
local COLOR = (arg and #arg > 0) and {} or {
  "WIDGETS/TRICKY/main.lua",
  "SCRIPTS/TRICKS/ui_color.lua",
}

local bad = 0
local function report(f, line, msg)
  print(string.format("  %s:%s %s", f, line:match("%[(%d+)%]") or "?", msg))
  bad = bad + 1
end

local function check(files, GLOBALS, LIBS, label)
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
        report(f, line, "uses global '" .. name .. "', not on EdgeTX " .. label)
      end
      if LIBS[name] then libReg, lib = reg, name else libReg, lib = nil, nil end
    else
      if sname then report(f, line, "assigns global '" .. sname .. "'") end
      local src, field = line:match("GETFIELD%s+%d+%s+(%d+)%s+%d+.-\"([%w_]+)\"")
      if lib and src == libReg and field and not LIBS[lib][field] then
        report(f, line, "uses " .. lib .. "." .. field .. ", not on EdgeTX " .. label)
      end
      if line:match("%sSELF%s") then
        report(f, line, "uses a method call (obj:fn()); string methods need LUA_ENABLE_STRLIB_MT")
      end
      libReg, lib = nil, nil
    end
  end
end
end

check(BW, GLOBALS, LIBS, "2.10 B&W")
check(COLOR, COLOR_GLOBALS, COLOR_LIBS, "2.10 colour")

if bad > 0 then
  print(bad .. " problem(s)")
  os.exit(1)
end
print("globals ok (" .. #BW .. " B&W files, " .. #COLOR .. " colour files, EdgeTX 2.10 library sets)")
