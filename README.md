# Tricky Sticks FPV

An EdgeTX Lua script that spots tricks on a Betaflight tinywhoop and shows them
on your goggles' OSD with a running score:

```
NICE ROLL! 10  →  FRONT FLIP! X2  →  DOUBLE ROLL! X3  →  SCORE 120  →  FULL SEND! 128  →  NEW BEST! 128
```

It detects rolls, front/back flips, doubles and triples, power loops, yaw
spins, orbits, combos, crashes, and rewards aggressive freestyle. It keeps your
high score on the SD card and shows a flight summary on the radio.

It works with stock Betaflight and stock ExpressLRS. The radio writes the text
into the Betaflight **craft name** over MSP (passed through the ELRS link), so
nothing needs flashing. It runs on EdgeTX 2.9+ radios with an ELRS module:

- **Black-and-white screens** (Radiomaster Pocket, Zorro, Boxer, TX12...) as a
  telemetry script. Built on a Pocket and confirmed on its factory EdgeTX
  (July 2023, around 2.9).
- **Colour screens** (Radiomaster TX16S/TX15, Jumper T15...) as a widget.
  Confirmed on a Jumper T15 Pro. If it looks wrong on your radio, please
  [open an issue](https://github.com/DanielAbdelNour/tricky-sticks-fpv/issues).

It's a toy, not a judge. A trick shows up up to ~1 s late, because the script
waits for telemetry to confirm it.

## Install

Download `tricky-sticks-fpv-<version>.zip` from the
[latest release](https://github.com/DanielAbdelNour/tricky-sticks-fpv/releases/latest)
and unzip it. It holds the `SCRIPTS` and `WIDGETS` folders that go on the
radio's SD card. The same download works on black-and-white and colour radios;
each radio ignores the part meant for the other.

1. Copy the files onto the radio's SD card (USB → "USB Storage", or a card
   reader). On a Mac, **don't drag the whole `SCRIPTS` or `WIDGETS` folder
   over** (Finder's "Replace" deletes your other scripts). Copy these instead:
   - the `SCRIPTS/TRICKS` folder → into `SCRIPTS/` on the SD card
   - `SCRIPTS/TELEMETRY/trick.lua` → into `SCRIPTS/TELEMETRY/` on the SD card
   - the `WIDGETS/TRICKY` folder → into `WIDGETS/` on the SD card
2. On the radio, open your whoop's model → **Telemetry** page. Run
   **Discover new sensors** with the quad powered on, and check that
   `FM`, `Ptch`, `Roll` and `Yaw` show up.
3. Turn it on. This is the only step that differs:
   - **Black-and-white radios:** on the same Telemetry page, under
     **Screens**, set a screen to **Script** → `trick`. Then, on the main
     screen, press **TELE** (on radios without a TELE button, long-press
     **PAGE**) to open it.
   - **Colour radios:** open the screen setup for the model (the **Screens**
     settings, also reached with **TELE**), add a new main view with the
     full-size **1x1** layout (turning off the top bar and sliders gives it
     more room), choose **Setup widgets**, and pick **Tricky FPV**. Smaller
     zones work too and show the score, last trick and combo.

It runs in the background as long as this model is selected, even when its
screen isn't showing.

### Updating

Copy the new files over the old ones, then **delete every `.luac` file** in
`SCRIPTS/TRICKS/`, `SCRIPTS/TELEMETRY/trick.luac` and `WIDGETS/TRICKY/`. EdgeTX loads whichever of
`.lua`/`.luac` is newer, so an old compiled file can win over the new source.
Then restart the radio.

The first start after an update compiles the scripts on the radio, which takes
a moment. The script compiles one file at a time and then loads the smaller
compiled copies, so this fits in the radio's memory.

If you ever see "not enough memory", the message names the file that didn't
fit. Restart the radio once (later starts use less memory). If it keeps
happening, [open an issue](https://github.com/DanielAbdelNour/tricky-sticks-fpv/issues)
with your radio, EdgeTX version and the **MEM** number from the STATUS page.

## Betaflight and ELRS setup (required)

- **OSD: enable the Craft Name element** (Configurator → OSD → "Craft name")
  and put it somewhere visible. The script needs this element to show anything.
- **ELRS telemetry ratio: 1:4 or 1:2** (or 500 Hz with 1:8). In the ELRS Lua
  script on the radio, set *Telem Ratio*. Don't use:
  - **Off**: no telemetry at all.
  - **Race**: telemetry is switched off while armed.
  - **Std** or **1:64**: about 4 telemetry packets per second, so attitude
    arrives well under once a second, which is too slow to see a flip.

  The live page shows the attitude rate (`ATT n Hz`). Aim for **5 Hz or
  more**; it blinks below that.
- **Betaflight telemetry on.** The TELEMETRY feature is on by default.
- Leave **`osd_craftname_msgs` OFF** (the DJI option). It also writes to the
  craft name and would fight with this script.
- Don't use **SPI** (built-in) ELRS receivers without testing first: Betaflight's
  own source warns that the OSD refresh this script triggers can upset
  scheduler timing on SPI receivers. It was designed for a UART (serial CRSF)
  receiver.

## What it detects

| Trick | Points | OSD text | How it's detected |
|-------|--------|----------|-------------------|
| Roll | 10 | `NICE ROLL!` | roll stick commands ~300° in 1.2 s, **and** telemetry sees the quad inverted, then upright again |
| Front flip | 25 | `FRONT FLIP!` | same, pitch stick forward |
| Back flip | 25 | `BACK FLIP!` | same, pitch stick back, throttle low |
| Power loop | 40 | `POWER LOOP!` | back-pitch rotation (up to 2.5 s) with throttle averaging 50% or more, inverted then upright |
| Double / triple | ×2 / ×3 | `DOUBLE ROLL!`, `TRIPLE FRONT!` | each extra 360° of stick, capped by how many separate times telemetry saw the quad inverted (for spins: by telemetry yaw) |
| Yaw spin | 15 | `SPIN!` | yaw stick commands ~300°, telemetry yaw turns 270° or more |
| Orbit | 30 | `ORBIT!` | telemetry: banked at least 15° and heading turns a full 360° in 1.5–8 s |
| Freestyle | up to 10 every 5 s | `SENDING IT!` / `FULL SEND!` | see below |
| Combo | ×2 … ×5 | `FRONT FLIP! X2` | trick within 3 s of the previous one; a crash breaks it |
| Crash | 0 (configurable penalty) | `CRASH!` | see below; cancels any trick being checked and the combo |
| New best | – | `NEW BEST!` | your score passes the saved high score (once per flight) |

A message stays up for 2 s, then the OSD falls back to `SCORE n`. Combo
messages show the multiplier instead of the score (`BACK FLIP! X3`). The score
resets every time you arm. On disarm the original craft name is put back.

### How detection works

1. **Armed check.** Betaflight's CRSF flight mode (`FM`) ends with `*`, `!` or `?`
   while disarmed. If none of those is there, the quad is armed. Failsafe
   (`!FS!`) counts as not armed. For 2 s after arming nothing counts.
2. **Sticks propose.** Stick positions are turned into rotation rates (your max
   rate × stick, with a little expo) and added up over sliding windows (1.2 s,
   and 2.5 s for slow loops). At 300° the script opens a *candidate* for the
   axis and direction. This also needs throttle above 5% at some point in the
   last 1.5 s.
3. **Telemetry confirms.** Rolls, flips and loops only score if attitude
   telemetry shows the quad tilted past 110° (inverted) and then back within
   60° of level. Betaflight's pitch only goes to ±90°, so "inverted" is computed
   from the up vector `cos(pitch)·cos(roll)` rather than from pitch alone.
   Spins need the telemetry yaw to actually turn. The trick is only scored once
   you release the stick, so doubles and triples aren't cut short. No
   confirmation within 1 s (1.5 s for loops) means no points (the screen shows
   `NO CONFIRM`).
4. **Cooldown.** After a trick scores, new candidates are ignored for 0.5 s, so
   one sloppy 1.5 rotation counts once.

**Power loop vs back flip** is decided by throttle: the same back-pitch rotation
with throttle averaging 50% or more is a power loop, and with less it's a back
flip. Tune `LOOP_THR_AVG` to match how you fly them.

**Orbits** without GPS can't be measured around a point. What the script
measures is a full, continuous, banked 360° turn that takes 1.5–8 s. That's what
an orbit looks like from the quad's attitude, but a wide circle counts too.

### Freestyle score

Every 5 s the script rates how aggressive your flying was, from 0 to 1:

- **40%** stick deflection (roll + pitch + yaw, averaged; 50% average = max)
- **30%** average throttle
- **30%** throttle movement (punch-outs and chops; 1.5 full-throttle travels
  per second = max)

Above **0.45** you get up to 10 points (`SENDING IT!`), and above **0.7** it
says `FULL SEND!`. It only pays out if telemetry shows the quad really moving
(at least 45°/s of attitude change on average), so wiggling sticks on the
ground or hovering earns nothing. The live page shows the last period's level
as a bar. Freestyle points don't interrupt a trick message on the OSD.

### Crash rules

- **Stuck tilted.** Tilted beyond 70° from level for more than 1 s while roll
  and pitch sticks are near centre (under 15%) and less than 90° of rotation
  has been commanded in the window. Example: lying on its side or upside down
  after hitting something.
- **Disarm while tilted.** Disarming while the last attitude is beyond 70°.
  This plays the crash sound, but the OSD is already showing Betaflight's
  post-flight stats, so you won't see the text.
- After a crash, crash detection (and orbit/freestyle scoring) pauses until
  the quad is back within 45° of level.
- **Turtle mode isn't reported in `FM`** (Betaflight just says ACRO/AIR). So if
  the quad is upside down at the moment you arm, the script treats it as
  turtle mode and ignores everything until it is upright again. Then it waits
  the 2 s grace period again.

### High score

Your best score is saved in `SCRIPTS/TRICKS/best.txt` when you disarm. During a
flight, passing it plays a fanfare and shows `NEW BEST!` once. Delete the file
to reset it. There's one high score for all models.

## Announcer voice

By default an announcer calls out your tricks. Set `VOICE = false` in
`SCRIPTS/TRICKS/config.lua` to hear the tones instead. The clips are in
`SCRIPTS/TRICKS/voice/` and are copied with the rest of that folder.

- **Every callout has several lines** ("Nice roll!", "Barrel roll!", "Clean
  roll!"…). They play in shuffled order: all of them before any repeat, and
  never the same line twice in a row.
- **Doubles and triples** have their own lines ("Double back flip!",
  "Ten-eighty!"), and so do combos ("Three in a row!"), freestyle ("Sending
  it!", "Full send!"), new best, crashes and arming.
- **Generic lines:** about one trick in four (`VOICE_GENERIC`) gets a generic
  line instead, like "Nailed it!" or "Ripping it!". Doubles and triples get
  bigger ones ("Unbelievable!").
- **On landing (optional):** set `VOICE_SCORE = true` to hear "Final score"
  or "You scored", followed by the number in your radio's own voice. It's off
  by default.
- **Only one callout plays at a time.** The script reads each clip's length
  from its file. If you land another trick while a clip is still playing, you
  hear that trick's tone instead, so the callouts never lag behind your
  flying. "Sending it!" is said at most once every 10 s
  (`VOICE_STYLE_GAP`).
- **Missing clips are fine.** The script uses whichever clips it finds, and a
  callout with none at all plays its normal tone.
- The radio's **wav volume** setting (SYS → Sound) controls how loud the
  voice is.

**Changing the lines:** edit `tools/voice_lines.txt` (one `callout|line` per
clip, up to 20 per callout), then run `tools/make_voice.py` to voice them with
ElevenLabs. It needs `ELEVENLABS_API_KEY` in your environment or in a `.env`
file at the repo root, plus `ffmpeg`. Lines that haven't changed come from a
local cache and don't use credits. Clips are sped up 15% with the pitch
unchanged (`--tempo`, 1 = as generated), and the script lists any that run
over 1.3 s. Copy the `voice` folder to the radio again afterwards (about 9 MB).

**Your own recordings:** put them in one folder per callout (any audio
format, any file names), e.g. `~/clips/roll/whatever.mp3`, and run
`tools/make_voice.py --from ~/clips`. That converts them to what EdgeTX plays
(mono 32 kHz 16-bit WAV, silence trimmed, loudness evened out).

Short clips (around a second) work best.

## Radio screen

### Black-and-white radios

Three pages. Press **ENTER** (or turn the wheel) to switch. The script jumps to
the live page when you arm and to the summary when you disarm.

```
TRICKS              ARMED      LAST FLIGHT       DISARMED     STATUS           DISARMED
SCORE  120     BEST 95         SCORE 120 BEST 120 NEW!        FM OK  ATT 6 HZ  YAW OK
               COMBO X3        ROLL 4 FRONT 2 BACK 1          STICKS OK      MEM 41
LAST  2X ROLL         1s       LOOP 1 SPIN 2 ORBIT 1          MSP OK   WRITES 14
STYLE [██████░░░░]  +18        COMBO X3 STYLE 18              NAME MY WHOOP
FM ok ATT 6 Hz MSP ok          CRASH 1 TIME 02:34
```

### Colour radios

The widget has the same three pages: live (big score, best, combo, last
trick, style bar and this flight's tricks), flight summary and status. It
switches to the live page when you arm and to the summary when you land.
To flip pages yourself, put the widget in full screen mode (select it, press
**ENTER**, choose **Full screen**; long-press **RTN** to leave) and press
**ENTER**, turn the wheel, tap or swipe. In a smaller zone it shows the
score, best, last trick and combo, with a status light (green: armed, grey:
disarmed, red: no link or no flight mode).

## Tuning

Everything is in `SCRIPTS/TRICKS/config.lua`, with comments. The ones you're most
likely to change:

| Setting | Default | Change it when |
|---------|---------|----------------|
| `MAX_RATE_ROLL` / `_PITCH` / `_YAW` | 600 | Set to your Betaflight max rates (deg/s). Too high means candidates fire early; too low and slow tricks are missed. |
| `RATE_EXPO` | 0.3 | Your rates have lots of expo (slow near centre): raise it. Linear rates: 0. |
| `CANDIDATE_DEG` | 300 | Tricks are missed: lower it (e.g. 270). False candidates: raise it. |
| `INVERTED_TILT` | 110 | Tricks show `NO CONFIRM` even though they were clean: lower to ~100, or raise the ELRS telemetry ratio. |
| `UPRIGHT_TILT` | 60 | You exit flips at a steep angle: raise it. |
| `SETTLE_FRAC` | 0.25 | Tricks score late because you keep some stick in afterwards: raise it. |
| `LOOP_THR_AVG` | 0.5 | Power loops register as back flips: lower it. Punchy back flips register as loops: raise it. |
| `SPIN_CONFIRM_DEG` | 270 | Spins show `NO CONFIRM`: lower it. |
| `ORBIT_MIN_BANK` / `ORBIT_MIN_TIME` | 15° / 1.5 s | Orbits not counted: lower them. Ordinary turns counted: raise them. |
| `COMBO_WINDOW` / `COMBO_MAX` | 3 s / 5 | Make combos easier or harder. |
| `STYLE_MIN` / `STYLE_FULL` | 0.45 / 0.7 | Freestyle pays too often or never: raise or lower them. |
| `STYLE_W_*` | 0.4 / 0.3 / 0.3 | Change what counts as aggressive (sticks / throttle / punches). |
| `CRASH_TILT` / `CRASH_TIME` | 70° / 1 s | False crashes during fast forward flight: raise either. |
| `POINTS_*`, `MSG_*`, `NOUN_*` | | Your own scoring and wording. OSD text is 16 chars max including the score. |
| `VOICE`, `VOICE_GENERIC`, `VOICE_SECS`, `VOICE_STYLE_GAP`, `VOICE_SCORE` | | Voice on/off, share of generic lines, how long a clip is assumed to last, how often "Sending it!" is said, the final score callout. |
| `SRC_*` | `ail`, `ele`, `rud`, `thr` | Stick sources. Use channel outputs like `{ "ch1" }` if needed. |

**How to tune:** watch `LAST` on the live page while you fly (or ask a friend
to watch). `NO CONFIRM` after a real trick means telemetry didn't see the
rotation: check `ATT n Hz` first. Nothing at all means the sticks didn't add up
to 300°: check your rates.

## Known limitations

- **Telemetry rate is the bottleneck.** A 600°/s roll spends only about
  0.23 s past 110°, so you need about 5 Hz of attitude telemetry to reliably
  catch it. Below that, tricks get missed (never falsely scored). Triples need
  every inversion to be seen to count as triples.
- **No restore when the script stops.** EdgeTX gives Lua scripts no "stop"
  callback, and telemetry scripts are paused while a tool script (ELRS Lua,
  Betaflight Lua) runs. If that happens mid-flight, the craft name keeps
  showing the last message until you disarm with the script running, or
  power-cycle the quad. Writes are RAM-only, so a power cycle always brings
  back your saved name.
- **Don't save settings while a message is showing.** Clicking *Save* in
  Configurator, or saving from the OSD/CMS menu, while the craft name shows
  `SCORE 45` will store that as your craft name. Disarm first (the original is
  restored on disarm).
- **If the script restarts while the FC shows its text**, it recognises its own
  messages and won't treat them as your craft name. On disarm it then restores
  `FALLBACK_NAME` (empty by default = leaves the FC alone).
- **Orbits are banked 360° turns**; there's no position data to check the
  centre point.
- **The freestyle score is a heuristic.** It rewards busy sticks, throttle and
  real movement, not good lines.
- Stick-based rotation is an estimate. Betaflight's real rate curve is more
  complex than `max × stick` with expo; telemetry confirmation covers the
  difference.
- Older Betaflight versions may send yaw without wrapping it to ±180°. Spins
  and orbits then pick up a ~15° error each time yaw passes 188°, which
  doesn't matter in practice.
- Memory: B&W radios have little RAM for Lua. The screen code is only
  loaded while the screen is shown, and `tests/mem.lua` keeps the total
  within a budget. If the screen ever can't load, the script keeps detecting
  tricks and shows a bare "LOW MEMORY" score screen. The STATUS page shows
  Lua memory in use (MEM, KB).

## Development

```
make test        # globals check, unit tests, smoke, voice, memory and fuzz tests
make release V=1.0.0   # dist/tricky-sticks-fpv-1.0.0.zip (just SCRIPTS/)
```

- `SCRIPTS/TRICKS/core.lua`: detection, pure Lua, no EdgeTX calls.
- `SCRIPTS/TRICKS/msp.lua`: MSP-over-CRSF framing (mirrors
  [betaflight-tx-lua-scripts](https://github.com/betaflight/betaflight-tx-lua-scripts)
  `MSP/common.lua` + `MSP/crsf.lua`) and the craft-name read/write/restore
  logic, with the CRSF push/pop functions passed in.
- `SCRIPTS/TELEMETRY/trick.lua`: a small loader. It compiles each module on
  its own, then loads the stripped compiled copies, and loads the screen only
  while it's shown. Its filename must stay at 6 characters or fewer.
- `SCRIPTS/TRICKS/radio.lua`: sensors, sticks, sound and voice, high score
  file.
- `SCRIPTS/TRICKS/ui.lua`: the three screen pages (black-and-white).
- `WIDGETS/TRICKY/main.lua`: the colour-radio widget. A small entry point
  that loads the same modules as `trick.lua` plus `ui_color.lua`.
- `SCRIPTS/TRICKS/ui_color.lua`: the colour screen, which adapts to the
  widget's size. Only colour radios load it.
- `tests/globals.lua`: checks the radio scripts only use globals and library
  functions EdgeTX 2.9/2.10 has: the black-and-white set for the shared code
  and `trick.lua` (no `table` library, no `unpack`, no string methods), the
  colour set for the widget files (no `lcd.getLastRightPos`).
- `tests/run.lua`: unit tests with a small attitude simulator (rotation
  matrix → Betaflight-style Euler angles incl. yaw, sampled at a limited
  telemetry rate with latency; coordinated turns for orbits).
- `tests/smoke.lua`: runs the wrapper in a sandbox with only the B&W EdgeTX
  libraries, EdgeTX's `io` API and stubbed radio functions.
- `tests/widget.lua`: runs the widget with the colour EdgeTX API stubbed,
  hidden and in ten zone sizes, and fails if any text runs outside the zone
  or over other text (worst case: five-digit scores). It also checks the
  black-and-white loader never loads colour-only code.
  `WIDGET_SVG=<dir> lua tests/widget.lua` saves a picture of every layout.
- `tests/fuzz.lua`: random inputs to catch runtime errors.
- `tests/voice.lua`: checks the voice lines and clips match what the script
  looks for, in a format EdgeTX plays.
- `tests/mem.lua`: runs the scripts like EdgeTX does (first start compiling,
  later starts from `.luac`, screen hidden and shown) and fails if memory goes
  over budget.
- `tools/make_voice.py` + `tools/voice_lines.txt`: builds the voice clips
  (ElevenLabs + ffmpeg).

The code targets EdgeTX's Lua 5.2 and also runs on desktop Lua 5.1–5.4. It
avoids per-tick table allocation to keep the Pocket's Lua memory happy.

### Facts this relies on (checked against source, Nov 2026)

- `MSP_SET_NAME` (11) only changes RAM (`pilotConfigMutable()->craftName`)
  and calls `osdAnalyzeActiveElements()`, which redraws the craft name
  background element. There's no armed check. `MSP_NAME` (10) returns the
  name. (betaflight `src/main/msp/msp.c`, `osd/osd.c`, `osd/osd_elements.c`)
- CRSF flight mode disarmed suffixes `*` / `!` / `?`, and failsafe `!FS!`.
  Attitude angles are sent wrapped to ±180°. (betaflight `src/main/telemetry/crsf.c`)
- EdgeTX sensors `Ptch` / `Roll` / `Yaw` are in radians (CRSF rad×10000 → stored
  rad×1000, precision 3), and `FM` is a text sensor. (EdgeTX
  `radio/src/telemetry/crossfire.cpp`)
- Telemetry scripts: filename ≤ 6 chars, `background()` runs while the screen
  is hidden. ([EdgeTX Lua docs](https://luadoc.edgetx.org/part_i_-_script_type_overview/telemetry))
- B&W EdgeTX has no `table` library and no global `unpack`; its `io` API is
  `io.open/read(file, n)/write(file, s)/close`; `loadScript` saves a
  debug-stripped `.luac` after the first compile. (EdgeTX 2.9/2.10
  `radio/src/thirdparty/Lua/src/*.c`, `radio/src/lua/interface.cpp`)
- `playFile` takes an absolute path of at most 42 characters and queues the
  clip. WAV files must be PCM 16-bit, a-law or u-law, and mono. The sample rate must divide 32 kHz.
  (EdgeTX 2.9 `radio/src/lua/api_general.cpp`, `radio/src/audio.cpp`/`audio.h`)

## License and credits

The code is under the [MIT License](LICENSE).

The announcer clips in `SCRIPTS/TRICKS/voice/` are not covered by the MIT
License. They were generated with [ElevenLabs](https://elevenlabs.io) on a
free plan, which allows non-commercial use only: you can use and share them
for free, but not sell them or use them in paid or monetized products. To use
the script commercially, generate your own clips (see "Changing the lines" or
"Your own recordings" above).

Voice clips generated by ElevenLabs (elevenlabs.io).
