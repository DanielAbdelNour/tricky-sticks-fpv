-- Tricky Sticks FPV configuration.
-- Every tunable lives here. Times are in seconds, angles in degrees.
-- Edit on your computer or on the radio, then restart the script
-- (re-select the model or power-cycle the radio).

return {
  ---------------------------------------------------------------------------
  -- Points (per rotation; multiplied by the combo multiplier)
  ---------------------------------------------------------------------------
  POINTS_ROLL       = 10,
  POINTS_FRONTFLIP  = 25,
  POINTS_BACKFLIP   = 25,
  POINTS_LOOP       = 40,        -- power loop
  POINTS_SPIN       = 15,        -- 360 yaw spin
  POINTS_ORBIT      = 30,        -- full banked 360 turn
  POINTS_MATTY      = 50,        -- Matty flip (back flip that hangs inverted)
  POINTS_JUICY      = 35,        -- juicy flick (half flip and back)
  STYLE_POINTS      = 10,        -- max freestyle points per STYLE_PERIOD
  CRASH_PENALTY     = 0,         -- points subtracted on a crash (0 = none)

  ---------------------------------------------------------------------------
  -- OSD messages (UPPERCASE, max 16 chars including the score or "X3")
  ---------------------------------------------------------------------------
  MSG_ROLL          = "NICE ROLL!",
  MSG_FRONTFLIP     = "FRONT FLIP!",
  MSG_BACKFLIP      = "BACK FLIP!",
  MSG_LOOP          = "POWER LOOP!",
  MSG_SPIN          = "SPIN!",
  MSG_ORBIT         = "ORBIT!",
  MSG_MATTY         = "MATTY FLIP!",
  MSG_JUICY         = "JUICY FLICK!",
  MSG_STYLE         = "SENDING IT!",   -- freestyle score above STYLE_MIN
  MSG_FULLSEND      = "FULL SEND!",    -- freestyle score above STYLE_FULL
  MSG_BEST          = "NEW BEST!",
  MSG_CRASH         = "CRASH!",
  MSG_SCORE         = "SCORE",         -- idle text, shown as "SCORE 45"
  -- Multi-rotation names: "DOUBLE ROLL!", "TRIPLE FRONT!" ...
  MSG_DOUBLE        = "DOUBLE",
  MSG_TRIPLE        = "TRIPLE",
  NOUN_ROLL         = "ROLL!",
  NOUN_FRONTFLIP    = "FRONT!",
  NOUN_BACKFLIP     = "BACK!",
  NOUN_SPIN         = "SPIN!",
  MSG_TIME          = 2.0,       -- how long an event message stays up

  ---------------------------------------------------------------------------
  -- Stage 1: sticks propose a candidate
  ---------------------------------------------------------------------------
  -- Rotation rate at full stick (deg/s). Match your Betaflight max rates.
  MAX_RATE_ROLL     = 600,
  MAX_RATE_PITCH    = 600,
  MAX_RATE_YAW      = 600,
  -- Rate curve shape: 0 = linear (rate = stick * max). Higher values model
  -- Betaflight expo (less rotation at partial stick). Range 0..1.
  RATE_EXPO         = 0.3,
  STICK_DEADBAND    = 0.05,      -- fraction of full stick ignored around centre
  CANDIDATE_DEG     = 300,       -- commanded rotation that opens a roll/flip candidate
  WINDOW            = 1.2,       -- sliding window for the rotation estimate
  THR_MIN           = 0.05,      -- throttle (0..1) that counts as "flying"
  THR_RECENT        = 1.5,       -- throttle must have been above THR_MIN this recently
  -- A trick is only scored once the stick on its axis is released below this
  -- (fraction of full rate), so doubles/triples aren't cut short.
  SETTLE_FRAC       = 0.25,

  ---------------------------------------------------------------------------
  -- Stage 2: attitude telemetry confirms
  ---------------------------------------------------------------------------
  INVERTED_TILT     = 110,       -- tilt from level that counts as "inverted"
  UPRIGHT_TILT      = 60,        -- tilt from level that counts as "back upright"
  CONFIRM_TIME      = 1.0,       -- time after the candidate (or last rotation) to confirm
  COOLDOWN          = 0.5,       -- ignore new candidates after a scored trick

  ---------------------------------------------------------------------------
  -- Multi-rotation tricks and combos
  ---------------------------------------------------------------------------
  MULTI_DEG         = 360,       -- extra commanded rotation that counts one more rotation
  MAX_ROTATIONS     = 3,         -- cap (triple)
  COMBO_WINDOW      = 3.0,       -- next trick within this time continues the combo
  COMBO_MAX         = 5,         -- highest combo multiplier

  ---------------------------------------------------------------------------
  -- Power loops: back-pitch rotation with throttle held up
  ---------------------------------------------------------------------------
  LOOP_THR_AVG      = 0.5,       -- average throttle (0..1) during the rotation
  LOOP_WINDOW       = 2.5,       -- slow rotations up to this long still count
  LOOP_CANDIDATE_DEG = 300,      -- commanded back-pitch within LOOP_WINDOW
  LOOP_CONFIRM_TIME = 1.5,

  ---------------------------------------------------------------------------
  -- Yaw spins (rudder proposes, telemetry yaw confirms)
  ---------------------------------------------------------------------------
  SPIN_CANDIDATE_DEG = 300,      -- commanded yaw rotation within WINDOW
  SPIN_CONFIRM_DEG  = 270,       -- telemetry yaw rotation needed for one spin

  ---------------------------------------------------------------------------
  -- Matty flips: back flip to inverted, pause there (pitch stick released),
  -- then finish the flip. The whole trick has to fit in LOOP_WINDOW.
  ---------------------------------------------------------------------------
  MATTY_HANG        = 0.3,       -- inverted with pitch below SETTLE_FRAC this long

  ---------------------------------------------------------------------------
  -- Juicy flicks: half flip (pitch) to inverted, then flick back the way you
  -- came, ending upright. Telemetry must see it inverted, then upright.
  ---------------------------------------------------------------------------
  JUICY_DEG         = 150,       -- commanded pitch one way that starts one
  JUICY_RETURN_DEG  = 60,        -- ...then back to within this of the start
  JUICY_TIME        = 1.5,       -- ...this soon after JUICY_DEG was reached

  ---------------------------------------------------------------------------
  -- Orbits: banked, continuous 360 heading change (no GPS: this is a full
  -- banked turn, the closest thing to an orbit we can measure)
  ---------------------------------------------------------------------------
  ORBIT_MIN_BANK    = 15,        -- bank angle that counts as "turning"
  ORBIT_MAX_PITCH   = 60,        -- ignore while flipping
  ORBIT_MIN_TIME    = 1.5,       -- faster than this is a spin, not an orbit
  ORBIT_MAX_TIME    = 8.0,       -- slower than this doesn't count
  ORBIT_GAP         = 0.6,       -- tolerated time out of the turn before it resets

  ---------------------------------------------------------------------------
  -- Freestyle "aggression" score, evaluated every STYLE_PERIOD seconds:
  --   style = W_STICK * stick deflection + W_THR * avg throttle
  --         + W_PUNCH * throttle movement      (each part 0..1, total 0..1)
  -- Points only if telemetry shows the quad really moving (STYLE_MIN_ATT_RATE).
  ---------------------------------------------------------------------------
  STYLE_PERIOD      = 5.0,
  STYLE_W_STICK     = 0.4,
  STYLE_W_THR       = 0.3,
  STYLE_W_PUNCH     = 0.3,
  STYLE_STICK_FULL  = 0.5,       -- average |stick| (roll+pitch+yaw)/3 that counts as max
  STYLE_PUNCH_FULL  = 1.5,       -- throttle travel per second (0..1 units) that counts as max
  STYLE_MIN         = 0.45,      -- below this: no points
  STYLE_FULL        = 0.7,       -- above this: "FULL SEND!"
  STYLE_MIN_ATT_RATE = 45,       -- deg/s of attitude change needed (no ground flicks)

  ---------------------------------------------------------------------------
  -- Arming
  ---------------------------------------------------------------------------
  ARM_GRACE         = 2.0,       -- ignore everything this long after arming
  TURTLE_TILT       = 100,       -- armed while tilted beyond this = turtle mode
  TURTLE_CLEAR_TILT = 45,        -- turtle ends once tilt drops below this

  ---------------------------------------------------------------------------
  -- Crash rules (see README for details)
  ---------------------------------------------------------------------------
  CRASH_TILT        = 70,        -- tilt that counts as "on its side or worse"
  CRASH_TIME        = 1.0,       -- ...held this long with sticks centred
  CRASH_STICK       = 0.15,      -- "sticks centred" = roll and pitch below this
  CRASH_MAX_WINDOW_DEG = 90,     -- ...and less commanded rotation than this in the window
  CRASH_ON_DISARM   = true,      -- disarming while tilted beyond CRASH_TILT is a crash
  CRASH_CLEAR_TILT  = 45,        -- after a crash, re-arm crash detection below this tilt

  ---------------------------------------------------------------------------
  -- MSP / OSD writing
  ---------------------------------------------------------------------------
  OSD               = true,      -- false: send nothing to the quad (radio screen and sound only)
  WRITE_INTERVAL    = 0.5,       -- min time between MSP_SET_NAME writes (2/s)
  WRITE_RETRY       = 1.5,       -- re-send a write if the FC hasn't acknowledged it by then
  READ_RETRY        = 1.0,       -- retry interval for reading the original name
  READ_GIVEUP       = 15,        -- give up reading after this many attempts
  -- If the original name can't be read (or the FC already shows our text after
  -- a script restart), restore to this on disarm. "" = leave the FC alone.
  FALLBACK_NAME     = "",
  -- Write messages even if the original name couldn't be read.
  WRITE_WITHOUT_NAME = false,

  ---------------------------------------------------------------------------
  -- High score file on the SD card (one number). Delete it to reset.
  ---------------------------------------------------------------------------
  BEST_FILE         = "/SCRIPTS/TRICKS/best.txt",

  ---------------------------------------------------------------------------
  -- Radio inputs. Stick source names are tried in order; the first one that
  -- exists is used. You can use channel outputs instead, e.g. { "ch1" }.
  ---------------------------------------------------------------------------
  SRC_ROLL          = { "ail", "Ail" },
  SRC_PITCH         = { "ele", "Ele" },
  SRC_YAW           = { "rud", "Rud" },
  SRC_THR           = { "thr", "Thr" },
  SENSOR_PITCH      = "Ptch",
  SENSOR_ROLL       = "Roll",
  SENSOR_YAW        = "Yaw",
  SENSOR_FM         = "FM",

  ---------------------------------------------------------------------------
  -- Audio. Announcer clips are played from VOICE_DIR/<callout>/1.wav, 2.wav...
  -- (see tools/voice_lines.txt for the callouts). A callout with no clips
  -- plays its built-in tone, so you can replace or delete files freely.
  ---------------------------------------------------------------------------
  SOUND_ON          = true,
  VOICE             = true,    -- true = announcer voice, false = tones
  VOICE_DIR         = "/SCRIPTS/TRICKS/voice/",  -- full path <= 42 chars incl. clip
  VOICE_SECS        = 1.2,      -- assumed clip length if a WAV header can't be
                                -- read. A trick called out while a clip still
                                -- plays gets its tone instead.
  VOICE_GENERIC     = 0.25,     -- share of trick callouts that use a generic
                                -- line ("Nailed it!") instead of the trick's own
  VOICE_STYLE_GAP   = 10,       -- min s between spoken freestyle callouts
  VOICE_SCORE       = false,     -- say "Final score <n>" on disarm
}
