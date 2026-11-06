-- Tricky Sticks FPV: EdgeTX widget for colour-screen radios (TX16S, T15,
-- TX15, Boxer colour...). Black-and-white radios use
-- SCRIPTS/TELEMETRY/trick.lua instead; both share the code in
-- /SCRIPTS/TRICKS/ (detection, OSD text, sound, voice, settings, high score).
--
-- EdgeTX loads every widget's main.lua when a model is selected, used or
-- not, so this file stays tiny and loads the rest only when the widget is
-- placed on a screen. EdgeTX calls background() while the widget is hidden
-- and refresh() while it shows, so both tick the detector (R.tick() runs
-- once per 10 ms tick, however many times it's called, and however many
-- copies of the widget there are).
-- Folder name <= 8 chars, widget name <= 10 chars (EdgeTX limits).

local BASE = "/SCRIPTS/TRICKS/"
local R, ui

local function load(name)
  local f, err = loadScript(BASE .. name)
  if not f then error(name .. ": " .. tostring(err), 0) end
  return f()
end

local function create(zone, options)
  if not R then
    local r = load("radio.lua")
    r.init(load)
    R = r
    ui = load("ui_color.lua")
  end
  return { zone = zone, options = options }
end

local function update(widget, options)
  widget.options = options
end

local function background(widget)
  R.tick()
end

-- event is nil unless the widget is in full screen mode
local function refresh(widget, event, touchState)
  R.tick()
  ui(R, widget.zone, event, touchState)
end

return {
  name = "Tricky FPV",
  options = {},
  create = create,
  update = update,
  background = background,
  refresh = refresh,
}
