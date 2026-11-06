-- Tricky Sticks FPV: MSP over CRSF + craft name manager.
-- Pure Lua: the CRSF push/pop functions are passed in, so this runs in unit
-- tests with a fake transport. Framing mirrors betaflight-tx-lua-scripts
-- (MSP/common.lua + MSP/crsf.lua):
--   CRSF frame 0x7A (MSP request) / 0x7C (MSP write), body:
--     { 0xC8 (FC), 0xEA (radio), status, up to 7 MSP bytes }
--   status = seq(4 bits) | 0x20 (MSP "version 1") | 0x10 (first chunk)
--   MSP byte stream = size, cmd, payload..., xor CRC of all of them
--   Replies: CRSF 0x7B, body { 0xEA, 0xC8, status, size, cmd, data... }

local M = {}

M.MSP_NAME     = 10
M.MSP_SET_NAME = 11

local ADDR_FC, ADDR_RADIO = 0xC8, 0xEA
local FT_REQ, FT_RESP, FT_WRITE = 0x7A, 0x7B, 0x7C
local TX_MAX = 8        -- status + 7 data bytes per frame (BF crsf maxTxBufferSize)
local RX_MAX = 58       -- MSP bytes per reply frame (BF crsf maxRxBufferSize)

local floor = math.floor
local sbyte, schar = string.byte, string.char
-- EdgeTX B&W radios (e.g. Pocket) have neither the `table` library nor a
-- global `unpack` (2.10: absent; 2.11+: compile option that needs `table`).
-- tests/globals.lua checks radio code only uses what EdgeTX 2.10 B&W has.

local bxor = bit32 and bit32.bxor or function(a, b)
  local r, p = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + p end
    a, b, p = floor(a / 2), floor(b / 2), p * 2
  end
  return r
end
M.bxor = bxor

---------------------------------------------------------------------------
-- Transport
---------------------------------------------------------------------------
function M.new(push, pop)
  return {
    push = push, pop = pop,
    txBuf = {}, txLen = 0, txIdx = 1, txCRC = 0, seq = 0, frameType = FT_REQ,
    lastReq = 0, out = {},
    rxBuf = {}, rxLen = 0, rxSize = 0, rxReq = 0, rxCRC = 0, rxErr = false,
    rxStarted = false, remoteSeq = 0,
  }
end

function M.busy(L) return L.txLen > 0 end

-- Send the next chunk if the module is ready. Returns true while more remain.
function M.pump(L)
  if L.txLen == 0 then return false end
  if not L.push() then return true end
  local out = L.out
  out[1], out[2] = ADDR_FC, ADDR_RADIO
  local status = L.seq + 0x20
  if L.txIdx == 1 then status = status + 0x10 end
  L.seq = (L.seq + 1) % 16
  out[3] = status
  local i = 4
  local last = TX_MAX + 2
  while i <= last and L.txIdx <= L.txLen do
    local v = L.txBuf[L.txIdx]
    out[i] = v
    L.txCRC = bxor(L.txCRC, v)
    L.txIdx = L.txIdx + 1
    i = i + 1
  end
  local done = false
  if i <= last then
    out[i] = L.txCRC
    i = i + 1
    done = true
  end
  for k = i, last do out[k] = nil end
  L.push(L.frameType, out)
  if done then
    L.txLen, L.txIdx, L.txCRC = 0, 1, 0
  end
  return not done
end

-- Queue an MSP request. payload is a string (may be ""). Returns false if busy.
function M.request(L, cmd, payload, isWrite)
  if L.txLen > 0 then return false end
  local n = #payload
  local b = L.txBuf
  b[1] = n
  b[2] = cmd % 256
  for i = 1, n do b[i + 2] = sbyte(payload, i) end
  L.txLen, L.txIdx, L.txCRC = n + 2, 1, 0
  L.frameType = isWrite and FT_WRITE or FT_REQ
  L.lastReq = cmd
  M.pump(L)
  return true
end

-- Feed one CRSF MSP reply body. Returns true when a full reply is assembled.
local function rxFrame(L, data)
  local status = data[3]
  if not status then return false end
  local version = floor(status / 32) % 4
  local start = floor(status / 16) % 2 == 1
  local seq = status % 16
  local idx = 2                      -- MSP byte index (1 = status)
  if start then
    L.rxLen = 0
    L.rxErr = status >= 128
    L.rxSize = data[2 + idx] or 0
    idx = idx + 1
    L.rxReq = L.lastReq
    if version == 1 then
      L.rxReq = data[2 + idx] or 0
      idx = idx + 1
    end
    L.rxCRC = bxor(L.rxSize, L.rxReq)
    L.rxStarted = true
  elseif not L.rxStarted then
    return false
  elseif (L.remoteSeq + 1) % 16 ~= seq then
    L.rxStarted = false
    return false
  end
  while idx <= RX_MAX and L.rxLen < L.rxSize do
    local v = data[2 + idx]
    if v == nil then L.rxStarted = false; return false end
    L.rxLen = L.rxLen + 1
    L.rxBuf[L.rxLen] = v
    L.rxCRC = bxor(L.rxCRC, v)
    idx = idx + 1
  end
  if idx > RX_MAX then
    L.remoteSeq = seq
    return false
  end
  L.rxStarted = false
  if version == 0 and L.rxCRC ~= data[2 + idx] then return false end
  return true
end

-- Drain pending CRSF frames. Returns cmd, err when a full MSP reply arrived.
function M.poll(L)
  for _ = 1, 8 do
    local cmd, data = L.pop()
    if cmd == nil then return nil end
    if cmd == FT_RESP and data and data[1] == ADDR_RADIO and data[2] == ADDR_FC then
      if rxFrame(L, data) then
        L.lastReq = 0
        return L.rxReq, L.rxErr
      end
    end
  end
  return nil
end

-- Only called for name replies (<= 16 bytes, rare), so concatenation is fine.
function M.rxString(L)
  local s = ""
  for i = 1, L.rxLen do s = s .. schar(L.rxBuf[i]) end
  return s
end

---------------------------------------------------------------------------
-- Craft name manager: read the original name, write messages (rate limited,
-- only on change), restore the original when desired == nil.
---------------------------------------------------------------------------
function M.newName(cfg, L)
  local msgs = {}
  for _, k in ipairs({ "MSG_ROLL", "MSG_FRONTFLIP", "MSG_BACKFLIP", "MSG_CRASH", "MSG_SCORE",
      "MSG_LOOP", "MSG_SPIN", "MSG_ORBIT", "MSG_STYLE", "MSG_FULLSEND", "MSG_BEST",
      "MSG_DOUBLE", "MSG_TRIPLE" }) do
    if cfg[k] then msgs[#msgs + 1] = string.upper(cfg[k]) end
  end
  return {
    cfg = cfg, L = L, msgs = msgs,
    orig = nil,        -- original craft name (nil = unknown)
    known = false,     -- finished reading (orig may still be nil if it looked like ours)
    gaveUp = false,
    tries = 0, lastReadT = -1e9,
    written = nil,     -- what we believe the FC currently shows
    lastWriteT = -1e9, ackPending = false,
    lastReplyT = -1e9, writes = 0,
  }
end

-- Does this name look like text we wrote (e.g. "SCORE 45", "BACK FLIP! 10",
-- "FRONT FLIP! X2")?
function M.looksOurs(N, s)
  local head = string.match(s, "^(.-) %-?%d+$") or string.match(s, "^(.-) X%d+$")
  if not head or head == "" then return false end
  for i = 1, #N.msgs do
    local m = N.msgs[i]
    -- head is a (possibly truncated) message, or starts with DOUBLE/TRIPLE
    if string.sub(m, 1, #head) == head or string.sub(head, 1, #m + 1) == m .. " " then
      return true
    end
  end
  return false
end

-- Call when the RF link (re)connects: the FC may have rebooted, so re-read.
function M.relink(N)
  N.known, N.gaveUp, N.tries, N.lastReadT = false, false, 0, -1e9
  N.written, N.ackPending = nil, false
end

local function onNameReply(N, s)
  if M.looksOurs(N, s) then
    -- Script restarted mid-session: keep any original we already had.
  else
    N.orig = s
  end
  N.known = true
  N.written = s
end

-- desired: text to show, or nil to restore the original. linkUp: RF link ok.
function M.nameTick(N, t, desired, linkUp)
  local L, cfg = N.L, N.cfg
  M.pump(L)
  local cmd, err = M.poll(L)
  if cmd == M.MSP_NAME and not err then
    N.lastReplyT = t
    onNameReply(N, M.rxString(L))
  elseif cmd == M.MSP_SET_NAME then
    N.lastReplyT = t
    N.ackPending = false
  end

  if not linkUp or M.busy(L) then return end

  if not N.known and not N.gaveUp then
    if t - N.lastReadT >= cfg.READ_RETRY then
      if N.tries >= cfg.READ_GIVEUP then
        N.gaveUp = true
      else
        M.request(L, M.MSP_NAME, "", false)
        N.tries, N.lastReadT = N.tries + 1, t
      end
    end
    if not N.gaveUp then return end
  end
  if not N.known and not cfg.WRITE_WITHOUT_NAME then return end

  local target = desired
  if target == nil then
    target = N.orig
    if target == nil and cfg.FALLBACK_NAME ~= "" then target = cfg.FALLBACK_NAME end
    if target == nil then return end
  end

  if N.ackPending and t - N.lastWriteT >= cfg.WRITE_RETRY then
    N.written, N.ackPending = nil, false     -- unacknowledged: send again
  end
  if target ~= N.written and t - N.lastWriteT >= cfg.WRITE_INTERVAL then
    M.request(L, M.MSP_SET_NAME, target, true)
    N.written, N.lastWriteT, N.ackPending = target, t, true
    N.writes = N.writes + 1
  end
end

return M
