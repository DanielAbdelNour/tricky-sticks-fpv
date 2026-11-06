-- Tricky Sticks FPV: EdgeTX telemetry script (a small loader).
-- The work happens in /SCRIPTS/TRICKS/: radio.lua (sticks, telemetry, OSD,
-- sound), core.lua (trick detection), msp.lua (OSD text over MSP),
-- config.lua (settings) and ui.lua (the screen, loaded only while shown).
-- Filename must stay <= 6 chars (EdgeTX limit).
--
-- Memory is tight on B&W radios. When EdgeTX compiles a .lua file it keeps
-- debug info in memory and saves a smaller stripped .luac next to it. So
-- init() first compiles each module on its own (nothing else loaded yet),
-- then loads the stripped copies. This keeps even the first start after an
-- update (when everything compiles) within the radio's memory.

local BASE = "/SCRIPTS/TRICKS/"
local R, ui
local shownT, retryT = 0, 0

local MODULES = { "core.lua", "msp.lua", "config.lua", "radio.lua", "ui.lua" }

-- Load a module from its stripped .luac (compiled by init() if needed).
local function load(name)
  collectgarbage()
  local f, err = loadScript(BASE .. name)
  if not f then error(name .. ": " .. tostring(err), 0) end
  return f()
end

local function init()
  -- Compile pass, with nothing else in memory yet: loading a module whose
  -- .lua is newer than its .luac compiles it (keeping debug info, the most
  -- memory-hungry step) and saves the stripped .luac. Drop each right away.
  for i = 1, #MODULES do
    local f = loadScript(BASE .. MODULES[i])
    f = nil
    collectgarbage()
  end
  R = load("radio.lua")
  R.init(load)
  collectgarbage()
end

-- EdgeTX calls background() every cycle, and run() as well while this
-- script's screen is shown.
local function background()
  R.tick()
  if ui and getTime() - shownT > 100 then   -- hidden for 1 s: free the screen
    ui = nil
    collectgarbage()
  end
end

local function run(event)
  R.tick()
  local now = getTime()
  shownT = now
  if not ui and now >= retryT then
    local ok, f = pcall(load, "ui.lua")
    if ok then ui = f else retryT = now + 500 end
  end
  if ui then
    ui(R, event)
  else                             -- not enough memory for the screen: tricks
    lcd.clear()                    -- still work, show the bare minimum
    lcd.drawText(0, 0, "TRICKS: LOW MEMORY", SMLSIZE)
    lcd.drawText(0, 20, "SCORE", SMLSIZE)
    lcd.drawNumber(40, 16, R.D.score, DBLSIZE)
  end
  return 0
end

return { init = init, background = background, run = run }
