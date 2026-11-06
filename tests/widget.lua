-- Smoke test for the colour-radio widget (WIDGETS/TRICKY/main.lua) with
-- stubbed EdgeTX colour APIs. Flies with the widget hidden (background only)
-- and shown in different zone sizes, checks every piece of text and every
-- box lands inside the widget's zone, and pages through the full screen
-- view with keys and touch. Also checks the black-and-white script never
-- loads colour-only code. Run from the repo root:  lua tests/widget.lua

local now = 0
local values = { ail = 0, ele = 0, rud = 0, thr = -1024, Ptch = 0, Roll = 0, Yaw = 0, FM = "ACRO*" }
local ids, names, n = {}, {}, 0
for k in pairs(values) do n = n + 1; ids[k] = n; names[n] = k end
local files = { ["/SCRIPTS/TRICKS/best.txt"] = "5" }
local inbox, osd, loads = {}, {}, {}

-- Colour EdgeTX (2.10/2.11) flag layout: font index in bits 8-11, BLINK
-- 0x1000, RGB colour in the top 16 bits with RGB_FLAG 0x8000.
local FONT = { STD = 0, XS = 0x300, L = 0x400, XL = 0x500, XXL = 0x600 }
-- Line heights and a generous average capital width per font, roughly
-- EdgeTX's 480-wide fonts (STD 16 px, XS 13, L 24, XL 32, XXL 64).
local FH = { [0] = 19, [0x300] = 16, [0x400] = 28, [0x500] = 38, [0x600] = 76 }
local FW = { [0] = 10, [0x300] = 9, [0x400] = 15, [0x500] = 21, [0x600] = 40 }
local RIGHT, CENTER, BLINK, RGB_FLAG = 8, 4, 0x1000, 0x8000

local zoneW, zoneH, problems, texts, boxes = 0, 0, {}, {}, {}
local function problem(s) if #problems < 20 then problems[#problems + 1] = s end end
local function int(v) return math.type(v) == "integer" end

local function fontOf(flags) return flags & 0x0F00 end
local function sizeText(s, flags)
  local f = fontOf(flags or 0)
  return #s * FW[f], FH[f]
end

local env = {}
for name in ([[assert collectgarbage dofile error getmetatable ipairs loadfile
  load next pairs pcall print rawequal rawlen rawget rawset select
  setmetatable tonumber tostring type xpcall string math table]]):gmatch("%S+") do
  env[name] = _G[name]
end
env.io = {
  open = function(path, mode)
    if mode == "r" then
      if not files[path] and path:match("%.wav$") then   -- the real voice pack
        local f = io.open("." .. path, "rb")
        if f then files[path] = f:read(44); f:close() end
      end
      if not files[path] then return nil end
      return { path = path, pos = 1 }
    end
    files[path] = ""
    return { path = path, pos = 1 }
  end,
  read = function(f, len)
    local s = files[f.path]:sub(f.pos, f.pos + len - 1)
    f.pos = f.pos + #s
    return s
  end,
  write = function(f, ...)
    for i = 1, select("#", ...) do files[f.path] = files[f.path] .. tostring(select(i, ...)) end
  end,
  close = function() end,
}
local radio                                     -- the shared state, for the stress draw
env.loadScript = function(path)
  loads[path] = (loads[path] or 0) + 1
  local chunk = loadfile("." .. path, "t", env)
  if not path:match("radio%.lua$") then return chunk end
  return function() radio = chunk(); return radio end
end
env.getTime = function() return now end
env.getRSSI = function() return 100 end
env.getFieldInfo = function(name) if ids[name] then return { id = ids[name] } end end
env.getValue = function(id) return values[names[id]] end
local played = {}
for _, k in ipairs({ "playTone", "playNumber", "playHaptic" }) do env[k] = function() end end
env.playFile = function(path)
  assert(#path <= 42, "EdgeTX ignores audio paths over 42 chars: " .. path)
  assert(io.open("." .. path, "rb"), "played a clip that doesn't exist: " .. path)
  played[#played + 1] = path
end
env.crossfireTelemetryPush = function(cmd, data)
  if cmd == nil then return true end
  if cmd == 0x7C then osd[#osd + 1] = true end
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
env.SMLSIZE, env.MIDSIZE, env.DBLSIZE, env.XXLSIZE = FONT.XS, FONT.L, FONT.XL, FONT.XXL
env.RIGHT, env.CENTER, env.BLINK, env.INVERS, env.BOLD = RIGHT, CENTER, BLINK, 1, 0x100
env.LCD_W, env.LCD_H = 480, 320                 -- Jumper T15
env.EVT_VIRTUAL_ENTER, env.EVT_VIRTUAL_NEXT, env.EVT_VIRTUAL_PREV = 100, 101, 102
env.EVT_TOUCH_FIRST, env.EVT_TOUCH_BREAK, env.EVT_TOUCH_SLIDE, env.EVT_TOUCH_TAP = 200, 201, 202, 203

-- WIDGET_SVG=<dir> lua tests/widget.lua  writes a picture of each layout
local svgDir, svg, shot = os.getenv("WIDGET_SVG"), nil, 0
local function rgb(flags)
  return string.format("#%02x%02x%02x", (flags >> 27 & 31) << 3, (flags >> 21 & 63) << 2,
    (flags >> 16 & 31) << 3)
end

local function inZone(what, x, y, w, h)
  if x < 0 or y < 0 or x + w > zoneW or y + h > zoneH then
    problem(string.format("%s at %d,%d size %dx%d outside %dx%d zone", what, x, y, w, h, zoneW, zoneH))
  end
end
env.lcd = {
  RGB = function(r, g, b)
    assert(int(r) and int(g) and int(b), "lcd.RGB takes integers")
    return ((r >> 3) << 27 | (g >> 2) << 21 | (b >> 3) << 16) | RGB_FLAG
  end,
  sizeText = sizeText,
  drawText = function(x, y, s, flags)
    flags = flags or 0
    assert(int(x) and int(y) and int(flags), "drawText needs integer x, y, flags")
    assert(type(s) == "string", "drawText needs a string")
    if flags & RGB_FLAG == 0 then problem("text without a colour: " .. s) end
    local w, h = sizeText(s, flags)
    local left = x
    if flags & RIGHT ~= 0 then left = x - w elseif flags & CENTER ~= 0 then left = x - w // 2 end
    inZone("text '" .. s .. "'", left, y, w, h)
    for _, b in ipairs(boxes) do                  -- text on top of other text
      if left < b[1] + b[3] and b[1] < left + w and y < b[2] + b[4] and b[2] < y + h then
        problem(string.format("text '%s' overlaps '%s' in %dx%d zone", s, b[5], zoneW, zoneH))
      end
    end
    boxes[#boxes + 1] = { left, y, w, h, s }
    texts[s] = true
    if svg then
      svg[#svg + 1] = string.format('<text x="%d" y="%.0f" textLength="%d" lengthAdjust="spacingAndGlyphs" '
        .. 'font-size="%.0f" fill="%s">%s</text>', left, y + h * 0.8, w, h * 0.85, rgb(flags), s)
    end
  end,
  drawFilledRectangle = function(x, y, w, h, flags)
    assert(int(x) and int(y) and int(w) and int(h), "drawFilledRectangle needs integers")
    assert(flags and flags & RGB_FLAG ~= 0, "box without a colour")
    inZone("box", x, y, w, h)
    if svg then
      svg[#svg + 1] = string.format('<rect x="%d" y="%d" width="%d" height="%d" fill="%s"/>', x, y, w, h, rgb(flags))
    end
  end,
}
setmetatable(env, { __index = function(_, k)
  if k == "bit32" then return nil end      -- exists on the radio, not in desktop 5.4
  error("global '" .. tostring(k) .. "' is not available to colour EdgeTX widgets", 2)
end })

-- The widget as EdgeTX sees it
local mainSrc = assert(io.open("WIDGETS/TRICKY/main.lua")):read("a")
local W = assert(load(mainSrc, "=main.lua", "t", env))()
assert(#W.name <= 10, "EdgeTX widget names are at most 10 characters")
assert(#("TRICKY") <= 8, "widget folder name at most 8 characters")
assert(type(W.create) == "function" and type(W.refresh) == "function")

local ZONES = {                                   -- w, h; nil event = not full screen
  { 480, 320, true }, { 480, 272, true },          -- full screen: T15, TX16S
  { 480, 268 }, { 480, 220 }, { 392, 200 },        -- big zones
  { 240, 136 }, { 225, 98 }, { 160, 80 }, { 192, 54 }, { 100, 40 }, -- smaller layouts
}
local wA = W.create({ x = 0, y = 0, w = 480, h = 268 }, {})
local wB = W.create({ x = 0, y = 0, w = 225, h = 98 }, {})  -- a second copy
assert(loads["/SCRIPTS/TRICKS/radio.lua"] == 1, "two widget copies share one detector")

local shown = false
local function drawAll(event, touch)       -- the event goes to the first full screen only
  for _, z in ipairs(ZONES) do
    zoneW, zoneH = z[1], z[2]
    local widget = { zone = { x = 0, y = 0, w = z[1], h = z[2] } }
    boxes = {}
    if svgDir then svg = {} end
    if z[3] then
      env.LCD_W, env.LCD_H = z[1], z[2]
      W.refresh(widget, event or 0, touch)
      event, touch = 0, nil
    else
      W.refresh(widget, nil, nil)
    end
    if svg then
      shot = shot + 1
      local f = assert(io.open(string.format("%s/%03d-%dx%d.svg", svgDir, shot, z[1], z[2]), "w"))
      f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
        .. 'font-family="Helvetica, Arial, sans-serif">', z[1], z[2]), table.concat(svg, "\n"), "</svg>")
      f:close()
      svg = nil
    end
  end
  zoneW, zoneH = 480, 268
  boxes = {}; W.refresh(wA, nil)
  zoneW, zoneH = 225, 98
  boxes = {}; W.refresh(wB, nil)
end

local function step(secs, roll, rollRate)
  for _ = 1, math.floor(secs * 50) do
    now = now + 2
    values.ail = roll * 1024
    if rollRate then values.Roll = ((values.Roll + rollRate * 0.02 + math.pi) % (2 * math.pi)) - math.pi end
    W.background(wA); W.background(wB)             -- both copies, same tick
    if shown and now % 10 == 0 then drawAll() end
  end
end

-- Hidden: tricks still count
step(2, 0)
values.FM, values.thr = "ACRO", 0
step(3, 0)
step(0.6, 1, math.rad(600))
values.Roll = 0
step(1.0, 0)
shown = true                                      -- now draw, and read the score
step(0.2, 0)
assert(texts["10"] or texts["20"] or texts["30"], "score counted while the widget was hidden")
step(0.6, 1, math.rad(600))                       -- shown: second roll, combo
values.Roll = 0
step(1.0, 0)
assert(texts["COMBO X2"], "combo shown")
step(1.5, 0)
values.FM = "ACRO*"
step(1.5, 0)                                      -- landed: summary page
assert(texts["LAST FLIGHT"], "summary page after landing")

-- Full screen paging: ENTER, wheel, tap, swipe
texts = {}
drawAll(env.EVT_VIRTUAL_ENTER)                    -- -> status
assert(texts["STATUS"], "ENTER: next page")
texts = {}
drawAll(env.EVT_TOUCH_TAP, { x = 10, y = 10, tapCount = 1 }) -- -> live
assert(texts["TRICKY STICKS FPV"], "tap: next page")
texts = {}
drawAll(env.EVT_TOUCH_SLIDE, { swipeRight = true }) -- -> status
assert(texts["STATUS"], "swipe right: previous page")
texts = {}
drawAll(env.EVT_VIRTUAL_NEXT)                     -- -> live
drawAll(env.EVT_VIRTUAL_NEXT)                     -- -> summary
assert(texts["LAST FLIGHT"], "wheel: next page")

-- Worst case for space: big numbers everywhere, on every page and zone.
local D = radio.D
D.score, D.best, D.stylePts, D.bestCombo, D.newBest = 99999, 99999, 9999, 12, true
for i = 1, #D.counts do D.counts[i] = 999 end
D.armed, D.combo, D.lastTrickT, D.lastEv, D.lastCount, D.lastEvT, D.styleNow = true, 5, now / 100,
  radio.core.EV_FRONT, 3, now / 100 - 99, 1
for _ = 1, 3 do drawAll(env.EVT_VIRTUAL_NEXT) end
D.lastEv = radio.core.EV_LOOP
drawAll()

assert(#played > 0, "announcer clips played from the widget")
assert(texts["26 CALLOUTS"], "STATUS page shows the voice clips found")

assert(#osd > 0, "OSD text written over MSP")
assert(files["/SCRIPTS/TRICKS/best.txt"] ~= "5", "best score saved")

-- The black-and-white script must never load colour-only code (memory).
local trick = assert(io.open("SCRIPTS/TELEMETRY/trick.lua")):read("a")
assert(not trick:find("ui_color", 1, true) and not trick:find("WIDGETS", 1, true),
  "B&W loader references colour-only files")
for _, f in ipairs({ "radio.lua", "core.lua", "msp.lua", "config.lua" }) do
  local src = assert(io.open("SCRIPTS/TRICKS/" .. f)):read("a")
  assert(not src:find("lcd%."), f .. " is shared by both radios and must not draw")
end

if #problems > 0 then
  for _, p in ipairs(problems) do print("  " .. p) end
  error(#problems .. " layout problem(s)")
end
print("widget ok (" .. #ZONES .. " zone sizes, paging, hidden detection)")
