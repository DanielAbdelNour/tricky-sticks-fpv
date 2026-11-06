#!/usr/bin/env python3
"""Build the announcer voice pack in SCRIPTS/TRICKS/voice/<callout>/<n>.wav.

Lines come from tools/voice_lines.txt and are voiced with ElevenLabs:

  tools/make_voice.py                        # default voice below
  tools/make_voice.py --voice <voice id>     # another ElevenLabs voice
  tools/make_voice.py --from ~/my_clips      # or convert your own recordings
                                             # (any format, ~/my_clips/<callout>/*)

  --only roll,back      just these callouts
  --model eleven_v3     ElevenLabs model (default below)
  --tempo 1.15          speed the clips up (pitch unchanged); 1 = as generated

ElevenLabs needs ELEVENLABS_API_KEY in the environment or in a .env file at
the repo root (ELEVENLABS_API_KEY=...; .env is git-ignored). Generated audio
is cached in tools/.voice_cache, so re-running only pays for new or changed
lines.

Every clip is converted to what EdgeTX plays (mono, 32 kHz, 16-bit PCM WAV
with a plain header), with the silence at both ends trimmed and the loudness
evened out for the radio's small speaker. Needs ffmpeg.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINES = os.path.join(ROOT, "tools", "voice_lines.txt")
OUT = os.path.join(ROOT, "SCRIPTS", "TRICKS", "voice")
CACHE = os.path.join(ROOT, "tools", ".voice_cache")

DEFAULT_EL_VOICE = "O9muPbiD3YbjvqpUFCOL"   # "Tricky Sticks FPV"
DEFAULT_EL_MODEL = "eleven_v3"
MAX_PER_FOLDER = 16                          # VOICE_MAX in SCRIPTS/TRICKS/radio.lua
MAX_PATH = 42                                # EdgeTX audio path limit
LONG_CLIP = 1.3                              # warn above this (seconds)

TEMPO = 1.15                                 # speed-up, pitch unchanged
TRIM = ("silenceremove=start_periods=1:start_threshold={th},areverse,"
        "silenceremove=start_periods=1:start_threshold={th},areverse")


def audio_filter(tempo):
    return ",".join([TRIM.format(th="-45dB"), f"atempo={tempo}", TRIM.format(th="-32dB"),
                     "speechnorm=e=8:r=0.0005:l=1", "alimiter=limit=0.95", "apad=pad_dur=0.04"])


AUDIO_EXT = (".wav", ".mp3", ".m4a", ".aac", ".ogg", ".flac", ".aiff", ".aif", ".webm", ".opus")


def read_lines():
    folders = {}
    with open(LINES, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "|" not in line:
                sys.exit(f"{LINES}:{n}: expected <folder>|<line>")
            folder, text = (s.strip() for s in line.split("|", 1))
            folders.setdefault(folder, []).append(text)
    return folders


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY")
    env = os.path.join(ROOT, ".env")
    if not key and os.path.exists(env):
        with open(env) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k.strip() == "ELEVENLABS_API_KEY":
                    key = v.strip().strip("'\"")
    if not key:
        sys.exit("ELEVENLABS_API_KEY not found: set it in your shell or in .env at the repo root")
    return key


def elevenlabs(text, voice, model, key, dest):
    # curl rather than urllib: it uses the system certificates on macOS. The
    # key goes in via stdin (curl -K -) so it never shows up in `ps`.
    url = (f"https://api.elevenlabs.io/v1/text-to-speech/{voice}"
           "?output_format=mp3_44100_128")
    body = json.dumps({"text": text, "model_id": model})
    conf = f'header = "xi-api-key: {key}"\n'
    for attempt in range(5):
        r = subprocess.run(["curl", "-sS", "-K", "-", "-X", "POST", url,
                            "-H", "Content-Type: application/json", "-H", "Accept: audio/mpeg",
                            "--data-binary", body, "-o", dest, "-w", "%{http_code}"],
                           input=conf, capture_output=True, text=True)
        code = int(r.stdout.strip() or 0)
        if r.returncode == 0 and code == 200:
            return
        if code == 429 or code >= 500 or r.returncode != 0:
            time.sleep(2 + 3 * attempt)
            continue
        detail = open(dest, errors="replace").read() if os.path.exists(dest) else r.stderr
        os.remove(dest) if os.path.exists(dest) else None
        sys.exit(f"ElevenLabs error {code} for {text!r}: {detail}")
    sys.exit(f"ElevenLabs kept failing for {text!r}")


def to_wav(src, dest, tempo):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-af", audio_filter(tempo),
                    "-ac", "1", "-ar", "32000", "-c:a", "pcm_s16le", "-map_metadata", "-1",
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", dest], check=True)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True).stdout
    return float(out.strip() or 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--voice", default=DEFAULT_EL_VOICE)
    ap.add_argument("--model", default=DEFAULT_EL_MODEL)
    ap.add_argument("--tempo", type=float, default=TEMPO, help="speed-up factor (1 = as generated)")
    ap.add_argument("--from", dest="src", help="folder of your own recordings, <callout>/*")
    ap.add_argument("--only", help="comma-separated callouts to rebuild")
    args = ap.parse_args()

    folders = read_lines()
    if args.src:   # own recordings: callouts are whatever sub-folders exist
        folders = {}
        for d in sorted(os.listdir(args.src)):
            p = os.path.join(args.src, d)
            if os.path.isdir(p):
                clips = sorted(f for f in os.listdir(p) if f.lower().endswith(AUDIO_EXT))
                if clips:
                    folders[d] = [os.path.join(p, f) for f in clips]
    if args.only:
        want = set(args.only.split(","))
        folders = {k: v for k, v in folders.items() if k in want}

    voice = args.voice
    key = None if args.src else api_key()
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)

    total, long_clips = 0, []
    for folder, items in folders.items():
        if len(items) > MAX_PER_FOLDER:
            sys.exit(f"{folder}: {len(items)} clips, the radio only looks for {MAX_PER_FOLDER}")
        path = f"/SCRIPTS/TRICKS/voice/{folder}/{len(items)}.wav"
        if len(path) > MAX_PATH:
            sys.exit(f"{folder}: path {path} is over EdgeTX's {MAX_PATH} characters")
        dest_dir = os.path.join(OUT, folder)
        os.makedirs(dest_dir, exist_ok=True)
        for f in os.listdir(dest_dir):          # drop clips from an older, longer list
            if f.endswith(".wav"):
                os.remove(os.path.join(dest_dir, f))
        for i, item in enumerate(items, 1):
            if args.src:
                src, label = item, os.path.basename(item)
            else:
                tag = f"{voice}|{args.model}|{item}"
                src = os.path.join(CACHE, hashlib.sha1(tag.encode()).hexdigest()[:16] + ".mp3")
                label = item
                if not os.path.exists(src):
                    elevenlabs(item, voice, args.model, key, src + ".part")
                    os.replace(src + ".part", src)
            dest = os.path.join(dest_dir, f"{i}.wav")
            to_wav(src, dest, args.tempo)
            secs = duration(dest)
            total += 1
            flag = "  <- long" if secs > LONG_CLIP else ""
            if flag:
                long_clips.append(f"{folder}/{i}")
            print(f"{folder}/{i}.wav  {secs:4.2f} s  {label}{flag}")

    for f in os.listdir(OUT):                    # old flat layout (voice/roll.wav)
        if f.endswith(".wav"):
            os.remove(os.path.join(OUT, f))
    print(f"\n{total} clips in {OUT}")
    if long_clips:
        print(f"Long clips (over {LONG_CLIP} s) may cut off the next callout: {', '.join(long_clips)}")


if __name__ == "__main__":
    main()
