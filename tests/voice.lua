-- Check the voice pack and lines list against what the radio script expects:
-- every callout in tools/voice_lines.txt is one the script knows, no clip is
-- numbered above VOICE_MAX (the script wouldn't find it), and each clip is a
-- WAV EdgeTX can play (RIFF/WAVE, PCM 16-bit or a-law / u-law, mono,
-- 8/16/32 kHz, path <= 42 chars). Run from the repo root.
local src = assert(io.open("SCRIPTS/TRICKS/radio.lua")):read("a")
local list = src:match('local VOICE_DIRS = (.-)\nlocal')
list = list:gsub('"%s*%.%.%s*"', ""):gsub('"', "")
local max = tonumber(src:match("local VOICE_MAX = (%d+)"))
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
