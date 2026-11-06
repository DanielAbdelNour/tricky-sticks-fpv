-- Tricky Sticks FPV: the radio screen (128x64), three pages. ENTER or the
-- wheel switches pages. trick.lua only loads this while the screen is shown,
-- to save memory. R is the radio module (radio.lua) with the shared state.

local floor = math.floor
local S = SMLSIZE
local PAGES = 3
local EV_NAMES = { "ROLL", "FRONT FLIP", "BACK FLIP", "CRASH", "ARMED", "DISARMED",
                   "NO CONFIRM", "TURTLE", "POWER LOOP", "SPIN", "ORBIT", "STYLE",
                   "NEW BEST", "MATTY FLIP" }

-- Draw "LABEL n" at x,y; returns the x after it (plus a gap).
local function pair(x, y, label, n)
  lcd.drawText(x, y, label, S)
  lcd.drawNumber(lcd.getLastRightPos() + 2, y, n, S)
  return lcd.getLastRightPos() + 5
end

local function title(R, text)
  local D = R.D
  lcd.drawFilledRectangle(0, 0, LCD_W, 9)
  lcd.drawText(1, 1, text, S + INVERS)
  local st
  if not R.linkUp then st = "NO LINK"
  elseif R.armedState == nil then st = "NO FM"
  elseif D.armed then st = D.turtle and "TURTLE" or "ARMED"
  else st = "DISARMED" end
  lcd.drawText(LCD_W - 1, 1, st, S + INVERS + RIGHT)
end

local function mspText(N, short)
  if not N then return short and "MSP n/a" or "N/A" end
  if N.known then return short and "MSP ok" or "OK" end
  if N.gaveUp then return short and "MSP fail" or "NO REPLY" end
  return short and "MSP ..." or "READING"
end

local function drawLive(R)
  local D, now = R.D, getTime() / 100
  title(R, "TRICKS")
  lcd.drawText(0, 15, "SCORE", S)
  lcd.drawNumber(30, 11, D.score, DBLSIZE)
  pair(88, 12, "BEST", D.best)
  if D.armed and D.combo > 1 and now - D.lastTrickT <= R.cfg.COMBO_WINDOW then
    lcd.drawText(88, 20, "COMBO X", S + BLINK)
    lcd.drawNumber(lcd.getLastRightPos(), 20, D.combo, S + BLINK)
  end

  lcd.drawText(0, 30, "LAST", S)
  if D.lastEv ~= 0 then
    if D.lastCount > 1 and D.lastEv ~= R.core.EV_STYLE then
      lcd.drawNumber(22, 30, D.lastCount, S)
      lcd.drawText(lcd.getLastRightPos(), 30, "X", S)
    end
    lcd.drawText(32, 30, EV_NAMES[D.lastEv], S)
    lcd.drawNumber(LCD_W - 6, 30, floor(now - D.lastEvT), S + RIGHT)
    lcd.drawText(LCD_W - 5, 30, "s", S)
  else
    lcd.drawText(22, 30, "-", S)
  end

  lcd.drawText(0, 40, "STYLE", S)
  lcd.drawGauge(26, 40, 60, 6, floor(D.styleNow * 100), 100)
  pair(90, 40, "+", D.stylePts)

  -- compact health line
  lcd.drawText(0, 51, (R.linkUp and R.fmOk) and "FM ok" or "FM --", S)
  local x = lcd.getLastRightPos() + 5
  if R.attOk then
    x = pair(x, 51, "ATT", R.attHz)
    lcd.drawText(x - 3, 51, "Hz", S + (R.attHz < 5 and BLINK or 0))
  else
    lcd.drawText(x, 51, "ATT --", S)
  end
  lcd.drawText(lcd.getLastRightPos() + 5, 51, mspText(R.N, true), S)
end

local function drawSummary(R)
  local D, E = R.D, R.core
  local c = D.counts
  title(R, D.armed and "THIS FLIGHT" or "LAST FLIGHT")
  local x = pair(0, 11, "SCORE", D.score)
  x = pair(x, 11, "BEST", D.best)
  if D.newBest and not D.armed then lcd.drawText(x, 11, "NEW!", S + BLINK) end
  x = pair(0, 20, "ROLL", c[E.EV_ROLL])
  x = pair(x, 20, "FRONT", c[E.EV_FRONT])
  pair(x, 20, "BACK", c[E.EV_BACK])
  x = pair(0, 29, "LOOP", c[E.EV_LOOP])
  x = pair(x, 29, "SPIN", c[E.EV_SPIN])
  pair(x, 29, "ORBIT", c[E.EV_ORBIT])
  x = pair(0, 38, "COMBO X", D.bestCombo)
  x = pair(x, 38, "STYLE", D.stylePts)
  pair(x, 38, "MATTY", c[E.EV_MATTY])
  x = pair(0, 47, "CRASH", c[E.EV_CRASH])
  lcd.drawText(x, 47, "TIME", S)
  local secs = D.armed and (getTime() / 100 - D.armT) or D.flightTime
  lcd.drawTimer(lcd.getLastRightPos() + 2, 47, floor(secs), S)
  lcd.drawText(0, 57, "ENTER: next page", S)
end

local function drawDiag(R)
  local N = R.N
  title(R, "STATUS")
  lcd.drawText(0, 12, "FM", S)
  lcd.drawText(14, 12, (R.linkUp and R.fmOk) and "OK" or "--", S)
  lcd.drawText(34, 12, "ATT", S)
  if R.attOk then
    lcd.drawNumber(52, 12, R.attHz, S + (R.attHz < 5 and BLINK or 0))
    lcd.drawText(64, 12, "HZ", S)
  else
    lcd.drawText(52, 12, "--", S)
  end
  lcd.drawText(80, 12, "YAW", S)
  lcd.drawText(98, 12, R.yawOk and "OK" or "--", S)
  lcd.drawText(0, 22, "STICKS", S)
  lcd.drawText(34, 22, R.sticksOk and "OK" or "??", S)
  lcd.drawText(80, 22, "MEM", S)            -- Lua memory in use, KB
  lcd.drawNumber(98, 22, floor(collectgarbage("count")), S)
  lcd.drawText(0, 32, "MSP", S)
  lcd.drawText(20, 32, mspText(N, false), S)
  if N then pair(64, 32, "WRITES", N.writes) end
  lcd.drawText(0, 42, "NAME", S)
  if N and N.known then lcd.drawText(24, 42, N.orig or "(unknown)", S) end
  if R.D.pending ~= 0 then lcd.drawText(0, 52, "CHECKING TRICK...", S + BLINK) end
end

return function(R, event)
  if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_NEXT then
    R.page = R.page % PAGES + 1
  elseif event == EVT_VIRTUAL_PREV then
    R.page = (R.page + PAGES - 2) % PAGES + 1
  end
  lcd.clear()
  if R.page == 1 then drawLive(R) elseif R.page == 2 then drawSummary(R) else drawDiag(R) end
end
