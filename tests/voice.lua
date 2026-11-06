-- Check the voice pack and lines list against what the radio script expects:
-- every callout in tools/voice_lines.txt is one the script knows, no clip is
-- numbered above VOICE_MAX (the script wouldn't find it), and each clip is a
-- WAV EdgeTX can play (RIFF/WAVE, PCM 16-bit or a-law / u-law, mono,
-- 8/16/32 kHz, path <= 42 chars). Run from the repo root.
local src = assert(io.open("SCRIPTS/TRICKS/radio.lua")):read("a")
local list = src:match('local VOICE_DIRS = (.-)\nlocal')
list = list:gsub('"%s*%.%.%s*"', ""):gsub('"', "")
local max = tonumber(src:match("local VOICE_MAX = (%d+)"))
-- Packed voice state must stay exact in EdgeTX 2.11+'s 32-bit floats (< 2^24):
-- clip mask + longest clip (cs, capped at 255) * B16, and mask + last clip * B16.
local b16 = tonumber(src:match("local B16 = (%d+)"))
assert(b16 and 2 ^ max <= b16, "VOICE_MAX clips must fit below B16")
assert(b16 - 1 + 255 * b16 < 2 ^ 24 and b16 - 1 + max * b16 < 2 ^ 24,
  "packed voice state would lose bits in 32-bit floats (EdgeTX 2.11+)")
local known, dirs = {}, {}
for d in list:gmatch("%S+") do known[d] = true; dirs[#dirs + 1] = d end

for line in io.lines("tools/voice_lines.txt") do
  local d = line:match("^([^#|]+)|")
  if d then assert(known[d], "voice_lines.txt: unknown callout '" .. d .. "'") end
end

local core = dofile("SCRIPTS/TRICKS/core.lua")
local function exists(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end
local clips, folders = 0, 0
for _, d in ipairs(dirs) do
  local n = 0
  for k = 1, max + 5 do
    local path = "/SCRIPTS/TRICKS/voice/" .. d .. "/" .. k .. ".wav"
    if exists("." .. path) then
      assert(k <= max, path .. ": the script only looks for clips 1-" .. max)
      assert(#path <= 42, "path too long for EdgeTX: " .. path)
      local f = assert(io.open("." .. path, "rb"))
      local h = f:read(44); f:close()
      assert(h:sub(1, 4) == "RIFF" and h:sub(9, 16) == "WAVEfmt ", path .. ": not a WAV")
      local codec, chans, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", h, 21)
      assert(codec == 1 and bits == 16 or codec == 6 or codec == 7, path .. ": codec " .. codec)
      assert(chans == 1, path .. ": must be mono")
      assert(rate == 8000 or rate == 16000 or rate == 32000, path .. ": rate " .. rate)
      local f2 = assert(io.open("." .. path, "rb"))
      local size = f2:seek("end"); f2:close()
      local secs = core.wavSecs(h)
      assert(secs and math.abs(secs - (size - 44) / (rate * 2)) < 0.001,
        path .. ": radio would misread the clip length")
      n = n + 1
    end
  end
  if n > 0 then folders = folders + 1 end
  clips = clips + n
end
print("voice ok (" .. clips .. " clips in " .. folders .. " callouts)")
