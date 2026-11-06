-- Fuzz test: random sticks, attitude, telemetry dropouts and arm/disarm
-- cycles. Checks for runtime errors, NaN scores and OSD text over 16 chars.
-- Run from the repo root:  lua tests/fuzz.lua

local core = dofile("SCRIPTS/TRICKS/core.lua")
local cfg = dofile("SCRIPTS/TRICKS/config.lua")
math.randomseed(42)
for run = 1, 20 do
  local S = core.new(cfg)
  local t, armed = 0, false
  local r, p, y, th = 0, 0, 0, 0
  local ap, ar, ay = 0, 0, 0
  local evs = {}
  for i = 1, 1500 do
    t = t + 0.01 + math.random() * 0.06
    if math.random() < 0.003 then armed = not armed end
    if math.random() < 0.1 then r, p, y = math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1 end
    if math.random() < 0.1 then th = math.random() end
    if math.random() < 0.2 then ap, ar, ay = (math.random() - 0.5) * math.pi, (math.random() * 2 - 1) * math.pi, (math.random() * 2 - 1) * math.pi end
    local a = armed
    if math.random() < 0.02 then a = nil end
    local attOk = math.random() > 0.05
    local ev = core.update(S, t, a, r, p, y, th, attOk, ap, ar, ay)
    evs[ev] = (evs[ev] or 0) + 1
    local txt = core.osdText(S, t)
    assert(S.score == S.score, "NaN score")
    assert(txt == nil or (type(txt) == "string" and #txt <= 16), "bad text: " .. tostring(txt))
  end
  if run == 1 then
    local parts = {}
    for k, v in pairs(evs) do parts[#parts + 1] = k .. ":" .. v end
    print("run 1 event histogram: " .. table.concat(parts, " "))
  end
end
print("fuzz ok")
