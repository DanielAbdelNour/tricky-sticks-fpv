-- Tricky Sticks FPV: the screen for colour radios, drawn into the widget's
-- zone (WIDGETS/TRICKY/main.lua). Only loaded on colour radios; the
-- black-and-white screen is ui.lua.
--
-- The layout adapts to the zone. A big zone (full screen, or a large part of
-- one) gets three pages like the B&W screen: live, flight summary, status.
-- In full screen mode, ENTER, the wheel, a tap or a swipe changes page;
-- otherwise the page follows the flight (live while armed, summary after
-- landing). Smaller zones show the score, last trick and combo.
-- Coordinates are relative to the zone (EdgeTX 2.9+).

local floor = math.floor
local PAGES = 3
local EV_NAMES = { "ROLL", "FRONT FLIP", "BACK FLIP", "CRASH", "ARMED", "DISARMED",
                   "NO CONFIRM", "TURTLE", "POWER LOOP", "SPIN", "ORBIT", "STYLE",
                   "NEW BEST" }

local C, H                       -- colours and font heights, set on first draw
local btn                        -- STATUS page test button: x, y, w, h (full screen)
local testT, quietUntil, test2T = -1e9, 0, nil

-- Sound test (STATUS page), in two parts: an arm callout through the same
-- code a trick uses (random clip); then 3 s later a beep, a clip played
-- directly and a number in the radio's own voice (from /SOUNDS/<language>).
-- Which ones you hear shows where sound stops.
local function soundTest(R, now)
  R.say("arm")
  testT, quietUntil, test2T = now, now + 1, now + 3   -- ignore the ENTER release
end

local function soundTest2(R, now)
  if test2T and now >= test2T then
    test2T = nil
    playTone(1000, 150, 100)
    playFile(R.cfg.VOICE_DIR .. "arm/1.wav")
    playNumber(42, 0)
  end
end

local function setup()
  local rgb = lcd.RGB
  C = {
    bg = rgb(16, 18, 26), panel = rgb(32, 36, 50), line = rgb(52, 58, 78),
    text = rgb(236, 239, 246), dim = rgb(132, 140, 162), accent = rgb(255, 178, 36),
    hot = rgb(255, 84, 84), ok = rgb(70, 214, 124), cool = rgb(80, 196, 255),
  }
  H = {}
  for _, f in ipairs({ SMLSIZE, 0, MIDSIZE, DBLSIZE, XXLSIZE }) do
    local _, h = lcd.sizeText("0", f)
    H[f] = h
  end
end

local function text(x, y, s, f, c)
  lcd.drawText(floor(x), floor(y), s, (f or 0) + (c or C.text))
end

local function width(s, f)
  return (lcd.sizeText(s, f or 0))
end

local function rect(x, y, w, h, c)
  lcd.drawFilledRectangle(floor(x), floor(y), floor(w), floor(h), c)
end

local function int(v) return tostring(floor(v + 0.5)) end

-- Status word and its colour.
local function status(R)
  local D = R.D
  if not R.linkUp then return "NO LINK", C.hot end
  if R.armedState == nil then return "NO FM", C.hot end
  if D.armed then
    if D.turtle then return "TURTLE", C.accent end
    return "ARMED", C.ok
  end
  return "DISARMED", C.dim
end

local function mspText(N)
  if not N then return "MSP N/A", C.dim end
  if N.known then return "MSP OK", C.ok end
  if N.gaveUp then return "MSP NO REPLY", C.hot end
  return "MSP ...", C.dim
end

-- "2X BACK FLIP", "ROLL", or nil before the first trick.
local function lastTrick(R)
  local D = R.D
  if D.lastEv == 0 then return nil end
  local s = EV_NAMES[D.lastEv]
  if D.lastCount > 1 and D.lastEv ~= R.core.EV_STYLE then s = D.lastCount .. "X " .. s end
  return s
end

local function comboActive(R, now)
  local D = R.D
  return D.armed and D.combo > 1 and now - D.lastTrickT <= R.cfg.COMBO_WINDOW
end

local function header(R, w, title)
  local hh = H[SMLSIZE] + 8
  rect(0, 0, w, hh, C.panel)
  text(8, 4, title, SMLSIZE, C.accent)
  local st, sc = status(R)
  text(w - 8, 4, st, SMLSIZE + RIGHT, sc)
  return hh
end

local function footer(R, w, h, full)
  local y = h - H[SMLSIZE] - 4
  -- page dots, bottom right
  for i = 1, PAGES do
    rect(w - 8 - (PAGES - i) * 12 - 6, y + H[SMLSIZE] / 2 - 3, 6, 6, i == R.page and C.accent or C.line)
  end
  if full then text(8, y, "ENTER / TAP: NEXT PAGE", SMLSIZE, C.dim) end
end

---------------------------------------------------------------------------
-- Big zone pages
---------------------------------------------------------------------------
local function stat(x, y, label, v, f)
  text(x, y, label, SMLSIZE, C.dim)
  text(x, y + H[SMLSIZE], tostring(v), f, C.text)
end

local function drawLive(R, w, h, full)
  local D, E, now = R.D, R.core, getTime() / 100
  local y = header(R, w, "TRICKY STICKS FPV") + 6
  local S, M = H[SMLSIZE], H[MIDSIZE]
  local bottom = h - S - 8                        -- footer line
  -- the score as big as fits, then the style bar if there's still room
  local rest = S + 12 + S + M + 8                 -- score label, last trick
  local big, withStyle = MIDSIZE, false
  local fonts = { XXLSIZE, DBLSIZE, MIDSIZE }
  for i = 1, #fonts do
    if y + H[fonts[i]] + rest + S + 4 <= bottom then big, withStyle = fonts[i], true; break end
  end

  local score, best = int(D.score), int(D.best)
  text(10, y, "SCORE", SMLSIZE, C.dim)
  text(10, y + S, score, big, C.text)
  text(w - 10, y, "BEST", SMLSIZE + RIGHT, C.dim)
  text(w - 10, y + S, best, MIDSIZE + RIGHT, C.text)
  if comboActive(R, now) then                     -- beside the score, bottom-aligned
    local cx = 10 + width(score, big) + 16
    local room = w - 10 - width(best, MIDSIZE) - 12 - cx
    local s = "COMBO X" .. D.combo
    if width(s, MIDSIZE) > room then s = "X" .. D.combo end
    if width(s, MIDSIZE) <= room then
      text(cx, y + S + H[big] - M, s, MIDSIZE + BLINK, C.accent)
    end
  end
  y = y + S + H[big] + 6

  rect(8, y, w - 16, 1, C.line)
  y = y + 6
  text(10, y, "LAST", SMLSIZE, C.dim)
  local last = lastTrick(R)
  if last then
    text(10, y + S, last, MIDSIZE, C.accent)
    text(w - 10, y + S, floor(now - D.lastEvT) .. "s", MIDSIZE + RIGHT, C.dim)
  else
    text(10, y + S, "-", MIDSIZE, C.dim)
  end
  y = y + S + M + 8

  if withStyle then
    text(10, y, "STYLE", SMLSIZE, C.dim)
    local pts = "+" .. int(D.stylePts)
    local gx = 10 + width("STYLE ", SMLSIZE)
    local gw = w - 10 - width(pts, SMLSIZE) - 8 - gx
    if gw > 20 then
      rect(gx, y + 2, gw, S - 4, C.line)
      local fill = D.styleNow > 1 and 1 or D.styleNow
      if fill > 0 then
        rect(gx, y + 2, gw * fill, S - 4, D.styleNow >= R.cfg.STYLE_FULL and C.hot or C.cool)
      end
    end
    text(w - 10, y, pts, SMLSIZE + RIGHT, C.text)
    y = y + S + 10
  end

  -- this flight's tricks, if there's room
  if y + S + M <= bottom then
    local c = D.counts
    local cols = {
      { "ROLL", c[E.EV_ROLL] }, { "FLIP", c[E.EV_FRONT] + c[E.EV_BACK] }, { "LOOP", c[E.EV_LOOP] },
      { "SPIN", c[E.EV_SPIN] }, { "ORBIT", c[E.EV_ORBIT] },
    }
    for i = 1, #cols do stat(10 + floor((i - 1) * (w - 20) / #cols), y, cols[i][1], cols[i][2], MIDSIZE) end
  end

  footer(R, w, h, full)
end

local function drawSummary(R, w, h, full)
  local D, E = R.D, R.core
  local c = D.counts
  local y = header(R, w, D.armed and "THIS FLIGHT" or "LAST FLIGHT") + 6
  local S, M = H[SMLSIZE], H[MIDSIZE]
  local row = S + M + 6
  text(10, y, "SCORE", SMLSIZE, C.dim)
  text(10, y + S, int(D.score), MIDSIZE, C.text)
  local x2 = floor(w / 3) + 10
  local best, isNew = int(D.best), D.newBest and not D.armed
  local nx = x2 + width(best, MIDSIZE) + 10
  local newFits = nx + width("NEW!", MIDSIZE) <= floor(2 * w / 3)
  text(x2, y, isNew and not newFits and "NEW BEST" or "BEST", SMLSIZE, isNew and C.accent or C.dim)
  text(x2, y + S, best, MIDSIZE, C.text)
  if isNew and newFits then text(nx, y + S, "NEW!", MIDSIZE + BLINK, C.accent) end
  local secs = floor(D.armed and (getTime() / 100 - D.armT) or D.flightTime)
  text(floor(2 * w / 3) + 10, y, "TIME", SMLSIZE, C.dim)
  text(floor(2 * w / 3) + 10, y + S, floor(secs / 60) .. ":" .. string.format("%02d", secs % 60),
    MIDSIZE, C.text)
  y = y + row + 2
  rect(8, y - 4, w - 16, 1, C.line)

  local grid = {
    { "ROLL", c[E.EV_ROLL] }, { "FRONT", c[E.EV_FRONT] }, { "BACK", c[E.EV_BACK] },
    { "LOOP", c[E.EV_LOOP] }, { "SPIN", c[E.EV_SPIN] }, { "ORBIT", c[E.EV_ORBIT] },
    { "BEST COMBO", "X" .. D.bestCombo }, { "STYLE", int(D.stylePts) }, { "CRASH", c[E.EV_CRASH] },
  }
  local bottom = h - S - 8
  local f = MIDSIZE                 -- smaller numbers if three rows don't fit
  if y + 3 * row > bottom then f, row = 0, S + H[0] + 2 end
  for i = 1, #grid do
    local col, r = (i - 1) % 3, floor((i - 1) / 3)
    local gy = y + r * row
    if gy + row > bottom then break end
    stat(floor(col * w / 3) + 10, gy, grid[i][1], grid[i][2], f)
  end
  footer(R, w, h, full)
end

local function line(x, y, w, label, value, vc)
  text(x, y, label, SMLSIZE, C.dim)
  text(x + w, y, value, SMLSIZE + RIGHT, vc or C.text)
end

local function drawStatus(R, w, h, full)
  local N = R.N
  local y = header(R, w, "STATUS") + 8
  local step = H[SMLSIZE] + 8
  local cw = floor(w / 2) - 20
  local x2 = floor(w / 2) + 10
  line(10, y, cw, "FLIGHT MODE", (R.linkUp and R.fmOk) and "OK" or "--",
    (R.linkUp and R.fmOk) and C.ok or C.hot)
  if R.attOk then
    line(x2, y, cw, "ATTITUDE", R.attHz .. " HZ", R.attHz < 5 and C.hot or C.ok)
  else
    line(x2, y, cw, "ATTITUDE", "--", C.hot)
  end
  y = y + step
  line(10, y, cw, "YAW", R.yawOk and "OK" or "--", R.yawOk and C.ok or C.hot)
  line(x2, y, cw, "STICKS", R.sticksOk and "OK" or "??", R.sticksOk and C.ok or C.hot)
  y = y + step
  local mt, mc = mspText(N)
  line(10, y, cw, "OSD", mt, mc)
  line(x2, y, cw, "WRITES", N and tostring(N.writes) or "-")
  y = y + step
  line(10, y, cw, "CRAFT NAME", (N and N.known) and (N.orig or "(unknown)") or "-")
  line(x2, y, cw, "LUA MEM", floor(collectgarbage("count")) .. " KB")
  y = y + step
  -- announcer clips found (callouts with at least one clip)
  if not (R.cfg.VOICE and R.cfg.SOUND_ON) then line(10, y, cw, "VOICE", "OFF", C.dim)
  elseif not R.voiceDone then line(10, y, cw, "VOICE", "CHECKING", C.dim)
  elseif R.voices == 0 then line(10, y, cw, "VOICE", "NO CLIPS", C.hot)
  else line(10, y, cw, "VOICE", R.voices .. " CALLOUTS", C.ok) end
  line(x2, y, cw, "CLIPS PLAYED", tostring(R.said))
  y = y + step
  if R.lastClip then line(10, y, w - 20, "LAST CLIP", R.lastClip) ; y = y + step end
  if R.D.pending ~= 0 then text(10, y, "CHECKING TRICK...", SMLSIZE + BLINK, C.accent) end
  if full then                                   -- sound test button, bottom right
    btn = nil
    local S = H[SMLSIZE]
    local label = "TEST SOUND"
    local bw, bh = width(label, SMLSIZE) + 28, S + 12
    local bx, by = w - 10 - bw, h - S - 8 - bh - 6
    if by > y + S then
      btn = { bx, by, bw, bh }
      local since = getTime() / 100 - testT
      rect(bx, by, bw, bh, since < 7 and C.accent or C.line)
      text(bx + 14, by + 6, label, SMLSIZE, C.text)
      local hint = since < 3 and "1: LIKE A CALLOUT" or since < 7 and "2: BEEP, CLIP, \"42\""
        or "TAP OR HOLD ENTER"
      text(bx - 10, by + 6, hint, SMLSIZE + RIGHT, C.dim)
    end
  end
  footer(R, w, h, full)
end

---------------------------------------------------------------------------
-- Smaller zones: score, last trick, combo
---------------------------------------------------------------------------
local function drawCompact(R, w, h)
  local D, now = R.D, getTime() / 100
  local S = H[SMLSIZE]
  local _, sc = status(R)
  rect(w - 10, 4, 6, 6, sc)                       -- status light
  -- largest score font that fits beside a label line (if there's room)
  local withText = h >= S * 2 + H[MIDSIZE] + 6
  local fonts = { XXLSIZE, DBLSIZE, MIDSIZE, 0, SMLSIZE }
  local f = SMLSIZE
  local avail = h - 4 - (withText and S * 2 + 2 or 0)
  local score = int(D.score)
  for i = 1, #fonts do
    if H[fonts[i]] <= avail and width(score, fonts[i]) <= w - 20 then f = fonts[i]; break end
  end
  local y = 2
  if withText then
    text(6, y, "SCORE", SMLSIZE, C.dim)
    local best = "BEST " .. int(D.best)
    if width(best, SMLSIZE) + width("SCORE ", SMLSIZE) + 24 <= w then
      text(w - 16, y, best, SMLSIZE + RIGHT, C.dim)
    end
    y = y + S
  end
  text(6, y + (withText and 0 or floor((h - 4 - H[f]) / 2)), score, f, C.text)
  if withText then
    local s, c = lastTrick(R), C.accent
    if comboActive(R, now) then s, c = "COMBO X" .. D.combo, C.accent end
    if s then text(6, h - S - 2, s, SMLSIZE, c) end
  end
end

---------------------------------------------------------------------------
return function(R, zone, event, touch)
  if not C then setup() end
  local full = event ~= nil                       -- full screen mode
  local w = full and LCD_W or zone.w
  local h = full and LCD_H or zone.h
  rect(0, 0, w, h, C.bg)

  local big = w >= 300 and h >= 200
  if not big then return drawCompact(R, w, h) end

  local now = getTime() / 100
  soundTest2(R, now)
  if full and R.page == 3 and (event == EVT_VIRTUAL_ENTER_LONG or (event == EVT_TOUCH_TAP
      and btn and touch and touch.x >= btn[1] and touch.x < btn[1] + btn[3]
      and touch.y >= btn[2] and touch.y < btn[2] + btn[4])) then
    soundTest(R, now)
    event = 0
  end
  if event == EVT_VIRTUAL_ENTER and now < quietUntil then event = 0 end
  if full and event ~= 0 then
    if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_ENTER or event == EVT_TOUCH_TAP
        or (touch and touch.swipeLeft) then
      R.page = R.page % PAGES + 1
    elseif event == EVT_VIRTUAL_PREV or (touch and touch.swipeRight) then
      R.page = (R.page + PAGES - 2) % PAGES + 1
    end
  end
  if R.page == 1 then drawLive(R, w, h, full)
  elseif R.page == 2 then drawSummary(R, w, h, full)
  else drawStatus(R, w, h, full) end
end
