-- Tiny flight simulator for unit tests.
-- Keeps a body->earth rotation matrix, rotates it by stick-commanded rates,
-- and reports Betaflight-style Euler angles (pitch +-90, roll +-180) at a
-- limited telemetry rate, like CRSF attitude frames over ELRS.

local Sim = {}
Sim.__index = Sim

local sin, cos, asin, rad = math.sin, math.cos, math.asin, math.rad
local atan2 = math.atan2 or math.atan

local function mul(A, B)
  local C = {}
  for i = 1, 3 do
    C[i] = {}
    for j = 1, 3 do
      C[i][j] = A[i][1] * B[1][j] + A[i][2] * B[2][j] + A[i][3] * B[3][j]
    end
  end
  return C
end

local function rotX(a) local c, s = cos(a), sin(a)
  return { { 1, 0, 0 }, { 0, c, -s }, { 0, s, c } } end
local function rotY(a) local c, s = cos(a), sin(a)
  return { { c, 0, s }, { 0, 1, 0 }, { -s, 0, c } } end
local function rotZ(a) local c, s = cos(a), sin(a)
  return { { c, -s, 0 }, { s, c, 0 }, { 0, 0, 1 } } end

-- opts: attHz (telemetry rate, default 5), dt (tick, default 0.02),
--       latency (telemetry delay in s, default 0.1)
function Sim.new(core, cfg, opts)
  opts = opts or {}
  local self = setmetatable({}, Sim)
  self.core, self.cfg = core, cfg
  self.S = core.new(cfg)
  self.t = 100.0
  self.dt = opts.dt or 0.02
  self.attPeriod = 1 / (opts.attHz or 5)
  self.latency = opts.latency or 0.1
  self.nextAtt = self.t
  self.R = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
  self.locked = false     -- true: sticks move but the quad doesn't rotate
  self.armed = false
  self.fmSuffix = "*"
  self.attP, self.attR, self.attY = 0, 0, 0
  self.earthYawRate = 0   -- deg/s heading change applied in the earth frame (turns)
  self.queue = {}         -- delayed attitude samples
  self.events = {}
  self.texts = {}
  return self
end

function Sim:euler()
  local R = self.R
  local s = -R[3][1]
  if s > 1 then s = 1 elseif s < -1 then s = -1 end
  return asin(s), atan2(R[3][2], R[3][3]), atan2(R[2][1], R[1][1])
end

-- Set attitude directly: roll then pitch, in degrees.
function Sim:setAttitude(rollDeg, pitchDeg)
  self.R = mul(rotX(rad(rollDeg or 0)), rotY(rad(pitchDeg or 0)))
end

function Sim:fm()
  if self.armed then return "ACRO" end
  return "ACRO" .. self.fmSuffix
end

local function frac(cfg, x)
  if math.abs(x) < cfg.STICK_DEADBAND then return 0 end
  return x * (1 - cfg.RATE_EXPO) + x * x * x * cfg.RATE_EXPO
end

-- Run for `secs` with the given sticks. Returns nothing; events accumulate.
function Sim:run(secs, roll, pitch, thr, yaw)
  roll, pitch, thr, yaw = roll or 0, pitch or 0, thr or 0.4, yaw or 0
  local n = math.floor(secs / self.dt + 0.5)
  for _ = 1, n do
    self.t = self.t + self.dt
    if not self.locked then
      local p = rad(frac(self.cfg, roll) * self.cfg.MAX_RATE_ROLL) * self.dt
      -- forward pitch stick = nose down = negative rotation about body Y here
      local q = -rad(frac(self.cfg, pitch) * self.cfg.MAX_RATE_PITCH) * self.dt
      local r = rad(frac(self.cfg, yaw) * self.cfg.MAX_RATE_YAW) * self.dt
      if p ~= 0 then self.R = mul(self.R, rotX(p)) end
      if q ~= 0 then self.R = mul(self.R, rotY(q)) end
      if r ~= 0 then self.R = mul(self.R, rotZ(r)) end
      if self.earthYawRate ~= 0 then
        self.R = mul(rotZ(rad(self.earthYawRate) * self.dt), self.R)
      end
    end
    -- telemetry sampling with latency
    if self.t >= self.nextAtt then
      self.nextAtt = self.nextAtt + self.attPeriod
      local ep, er, ey = self:euler()
      self.queue[#self.queue + 1] = { self.t + self.latency, ep, er, ey }
    end
    while self.queue[1] and self.queue[1][1] <= self.t do
      self.attP, self.attR, self.attY = self.queue[1][2], self.queue[1][3], self.queue[1][4]
      table.remove(self.queue, 1)
    end
    local armed = self.core.parseArmed(self:fm())
    local ev = self.core.update(self.S, self.t, armed, roll, pitch, yaw, thr, true,
      self.attP, self.attR, self.attY)
    if ev ~= 0 then self.events[#self.events + 1] = ev end
    self.text = self.core.osdText(self.S, self.t)
  end
end

function Sim:count(ev)
  local c = 0
  for _, e in ipairs(self.events) do if e == ev then c = c + 1 end end
  return c
end

-- Arm and hover past the grace period.
function Sim:armAndHover(secs)
  self.armed = true
  self:run(secs or 2.5, 0, 0, 0.4)
end

return Sim
