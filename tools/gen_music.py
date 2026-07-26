#!/usr/bin/env python3
"""Generate the game's looping music as seamless OGG files.

Why generated rather than downloaded: the art and the sound effects are CC0 packs
because packs of those exist. There is no CC0 pack of looping game music with a
licence I could verify the way `assets/pixel/*/LICENSE-*.txt` were verified, and
picking tracks by ear is not something I can do honestly. Synthesis is the same
answer D29 reached for the meaning-carrying symbols: author it, and *measure* the
result, rather than guess at somebody else's unlabelled material.

The measurements are the point, and they are printed on every run:

  seam       — the sample-to-sample step across the loop point, compared against
               the steps the waveform takes everywhere else. A loop is a circle;
               a discontinuity there clicks every N seconds, which is worse than
               no music. The comparison matters: a first pass measured the RMS of
               the first 50 ms against the last 50 ms and failed every track,
               because a loop that begins on a downbeat and ends on a decay is
               *supposed* to jump in level there. That is music, not a click. A
               click is a step the waveform does not otherwise take.
  rms/peak   — music must sit UNDER the sound effects. Anything that competes
               with the attack sound for attention is a bug.
  distinct   — two tracks that measure the same are one track used twice.

Seams cannot drift, because they are not fixed afterwards: every voice is written
into the buffer modulo its length, so a note or a delay tail that runs past the
end wraps into the beginning. The loop is continuous by construction.

Usage (ffmpeg is only needed here, never at runtime):
    nix shell nixpkgs#ffmpeg-headless --command python3 tools/gen_music.py
"""

import array
import json
import math
import pathlib
import random
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

# 22050 Hz on purpose: the content is low-harmonic pads and square-wave arpeggios
# to sit beside 16x16 pixel art, and half the rate is half the bytes.
RATE = 22050
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "music"

# --- notes -------------------------------------------------------------------

A4 = 440.0
NAMES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def hz(note: str) -> float:
    """'a3' / 'c#4' -> frequency."""
    name = note[0]
    octave = int(note[-1])
    semis = NAMES[name] + (1 if "#" in note else 0) + (-1 if "b" in note[1:] else 0)
    midi = 12 * (octave + 1) + semis
    return A4 * (2.0 ** ((midi - 69) / 12.0))


def chord(root: str, kind: str) -> list:
    """Triads and sevenths, as frequencies."""
    steps = {
        "min": [0, 3, 7], "maj": [0, 4, 7], "min7": [0, 3, 7, 10],
        "maj7": [0, 4, 7, 11], "sus": [0, 5, 7], "dim": [0, 3, 6],
    }[kind]
    base = hz(root)
    return [base * (2.0 ** (s / 12.0)) for s in steps]


# --- voices ------------------------------------------------------------------
#
# Everything writes with `i % n`, so a tail crossing the end of the loop lands at
# the beginning of it. That is what makes the seam exact rather than corrected.


def pad(buf, start, dur, freqs, gain, harmonics=3):
    """Soft sustained chord: slow in, slow out, a few decaying harmonics."""
    n = len(buf)
    total = int(dur * RATE)
    attack = int(total * 0.35)
    release = int(total * 0.55)
    for f in freqs:
        for h in range(1, harmonics + 1):
            amp = gain / (h * h) / len(freqs)
            w = 2.0 * math.pi * f * h / RATE
            # a touch of detune per harmonic keeps it from sounding like a beep
            phase = random.random() * math.tau
            for i in range(total):
                if i < attack:
                    env = i / attack
                elif i > total - release:
                    env = (total - i) / release
                else:
                    env = 1.0
                buf[(start + i) % n] += amp * env * math.sin(w * i + phase)


def pluck(buf, start, dur, freq, gain, square=False):
    """Short decaying note — the arpeggio voice."""
    n = len(buf)
    total = int(dur * RATE)
    w = 2.0 * math.pi * freq / RATE
    for i in range(total):
        env = math.exp(-4.0 * i / total)
        s = math.sin(w * i)
        if square:
            # soft square: odd harmonics, band-limited by only taking three
            s = (s + math.sin(3 * w * i) / 3.0 + math.sin(5 * w * i) / 5.0) * 0.8
        buf[(start + i) % n] += gain * env * s


def bass(buf, start, dur, freq, gain):
    n = len(buf)
    total = int(dur * RATE)
    w = 2.0 * math.pi * freq / RATE
    for i in range(total):
        env = min(1.0, i / (0.02 * RATE)) * math.exp(-1.6 * i / total)
        buf[(start + i) % n] += gain * env * (math.sin(w * i) + 0.3 * math.sin(2 * w * i))


def hit(buf, start, dur, gain, tone=0.0):
    """Filtered noise: the only percussion, and it stays quiet.

    The 1.5 ms attack is not a nicety. A drum written with an instant attack puts
    a full-amplitude sample at index 0, and the downbeat of a loop IS index 0 —
    so the loop point stepped further than the waveform ever steps elsewhere, and
    the seam check called it a click. Ramping the attack keeps the punch and
    removes the discontinuity.
    """
    n = len(buf)
    total = int(dur * RATE)
    attack = max(1, int(0.0015 * RATE))
    last = 0.0
    for i in range(total):
        env = math.exp(-9.0 * i / total) * min(1.0, i / attack)
        raw = random.uniform(-1.0, 1.0)
        last = last * 0.55 + raw * 0.45          # one-pole low pass, no click
        s = last
        if tone > 0.0:
            s += 0.6 * math.sin(2.0 * math.pi * tone * i / RATE) * env
        buf[(start + i) % n] += gain * env * s


def echo(buf, delay_s, feedback, taps=3):
    """Wrapping delay. Also folds the tail back over the loop point."""
    n = len(buf)
    d = int(delay_s * RATE)
    src = list(buf)
    for t in range(1, taps + 1):
        g = feedback ** t
        off = d * t
        for i in range(n):
            buf[(i + off) % n] += g * src[i]


# --- tracks ------------------------------------------------------------------
#
# Each returns (buffer, bars, bpm). Progressions are all natural minor: this is a
# game about descending into places that want you dead.


def make(bpm, bars, beats=4):
    n = int(RATE * bars * beats * 60.0 / bpm)
    return array.array("d", [0.0] * n), (60.0 / bpm)


def track_menu():
    """Title and save slots: still, patient, no pulse at all."""
    buf, beat = make(56, 8)
    prog = [("a2", "min7"), ("f2", "maj7"), ("c3", "maj7"), ("e2", "min7")]
    for i, (root, kind) in enumerate(prog):
        t = int(i * 2 * 4 * beat * RATE)
        pad(buf, t, 2 * 4 * beat * 1.05, chord(root, kind), 0.30, harmonics=4)
        bass(buf, t, 2 * beat, hz(root) / 2.0, 0.22)
    for i, note in enumerate(["e4", "a4", "b4", "e5", "b4", "a4"]):
        pluck(buf, int((1 + i * 5) * beat * RATE), beat * 2.4, hz(note), 0.055)
    echo(buf, beat * 1.5, 0.30)
    return buf


def track_world():
    """Overworld and every menu reached from it: open, moving, not tense."""
    buf, beat = make(72, 8)
    prog = [("d3", "min"), ("b2", "maj"), ("f3", "maj"), ("c3", "maj")]
    for i, (root, kind) in enumerate(prog):
        t = int(i * 2 * 4 * beat * RATE)
        pad(buf, t, 2 * 4 * beat * 1.02, chord(root, kind), 0.24)
        for b in range(4):
            bass(buf, t + int(b * 2 * beat * RATE), beat * 1.4, hz(root) / 2.0, 0.20)
        notes = chord(root, kind) * 3
        for j in range(8):
            pluck(buf, t + int(j * beat * RATE), beat * 0.9, notes[j % len(notes)] * 2.0,
                  0.045, square=True)
    echo(buf, beat * 0.75, 0.26)
    return buf


def track_dungeon():
    """Traversal, shop, event: low, sparse, waiting for something."""
    buf, beat = make(64, 8)
    prog = [("a2", "min"), ("a2", "min"), ("f2", "maj"), ("g2", "sus")]
    for i, (root, kind) in enumerate(prog):
        t = int(i * 2 * 4 * beat * RATE)
        pad(buf, t, 2 * 4 * beat * 1.04, chord(root, kind), 0.26, harmonics=2)
        bass(buf, t, beat * 3.0, hz(root) / 2.0, 0.26)
    for i in range(8):
        pluck(buf, int((i * 4 + 2) * beat * RATE), beat * 1.8,
              hz(["a3", "c4", "e4", "d4"][i % 4]), 0.040)
    for i in range(16):
        hit(buf, int(i * 2 * beat * RATE), 0.16, 0.05)
    echo(buf, beat * 2.0, 0.34)
    return buf


def track_combat():
    """A fight: a pulse you can count turns against."""
    buf, beat = make(104, 8)
    prog = [("e2", "min"), ("c3", "maj"), ("g2", "maj"), ("d3", "min")]
    for i, (root, kind) in enumerate(prog):
        t = int(i * 2 * 4 * beat * RATE)
        pad(buf, t, 2 * 4 * beat * 1.02, chord(root, kind), 0.18, harmonics=2)
        for b in range(8):
            bass(buf, t + int(b * beat * RATE), beat * 0.8, hz(root) / 2.0, 0.24)
        notes = [f * 2.0 for f in chord(root, kind)]
        for j in range(16):
            pluck(buf, t + int(j * beat * 0.5 * RATE), beat * 0.45,
                  notes[[0, 2, 1, 2][j % 4] % len(notes)], 0.050, square=True)
    for i in range(32):
        hit(buf, int(i * beat * RATE), 0.12, 0.06 if i % 4 else 0.10, tone=90.0)
    echo(buf, beat * 0.5, 0.20)
    return buf


def track_boss():
    """The boss row, where the runs end. Same pulse, one grinding semitone."""
    buf, beat = make(112, 8)
    prog = [("d2", "min"), ("bb2", "maj"), ("d2", "dim"), ("a2", "min")]
    for i, (root, kind) in enumerate(prog):
        t = int(i * 2 * 4 * beat * RATE)
        pad(buf, t, 2 * 4 * beat * 1.02, chord(root, kind), 0.20, harmonics=3)
        # the tension note: a minor second over the root, quiet but never resolved
        pad(buf, t, 2 * 4 * beat, [hz(root) * (2 ** (1 / 12.0)) * 2], 0.05)
        for b in range(8):
            bass(buf, t + int(b * beat * RATE), beat * 0.7, hz(root) / 2.0, 0.28)
        notes = [f * 2.0 for f in chord(root, kind)]
        for j in range(16):
            pluck(buf, t + int(j * beat * 0.5 * RATE), beat * 0.4,
                  notes[[0, 1, 2, 1][j % 4] % len(notes)], 0.055, square=True)
    for i in range(32):
        hit(buf, int(i * beat * RATE), 0.14, 0.11 if i % 2 == 0 else 0.06, tone=70.0)
    echo(buf, beat * 0.75, 0.22)
    return buf


TRACKS = {
    "music_menu": track_menu,
    "music_world": track_world,
    "music_dungeon": track_dungeon,
    "music_combat": track_combat,
    "music_boss": track_boss,
}

# Music must lose to the sound effects; these bounds are what "underneath" means.
PEAK_CEILING = 0.90
RMS_BAND = (0.02, 0.22)
# The loop step must not be an outlier among the steps the waveform already
# takes. 1.0 = exactly as big as the largest 1% of ordinary steps.
SEAM_RATIO_LIMIT = 1.0


def normalize(buf, target_peak=0.55):
    peak = max(abs(s) for s in buf) or 1.0
    g = target_peak / peak
    for i in range(len(buf)):
        buf[i] *= g


def measure(buf):
    n = len(buf)
    rms = math.sqrt(sum(x * x for x in buf) / n)
    steps = sorted(abs(buf[i + 1] - buf[i]) for i in range(0, n - 1, 7))
    ordinary = steps[int(len(steps) * 0.99)] or 1e-9
    seam = abs(buf[0] - buf[-1])
    return {
        "seconds": round(n / RATE, 2),
        "peak": round(max(abs(s) for s in buf), 4),
        "rms": round(rms, 4),
        "seam": round(seam, 5),
        "seam_ratio": round(seam / ordinary, 3),
    }


def write_wav(path, buf):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array("h", [
            int(max(-1.0, min(1.0, s)) * 32767) for s in buf]).tobytes())


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found. Run under:  nix shell nixpkgs#ffmpeg-headless")
        return 127
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed(20260726)          # reproducible: same script, same bytes
    report = {}
    fails = []
    tmp = pathlib.Path(tempfile.mkdtemp())
    for name, fn in TRACKS.items():
        buf = fn()
        normalize(buf)
        m = measure(buf)
        wav = tmp / (name + ".wav")
        write_wav(wav, buf)
        ogg = OUT / (name + ".ogg")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
             "-c:a", "libvorbis", "-b:a", "56k", "-ac", "1", str(ogg)],
            check=True)
        m["kb"] = round(ogg.stat().st_size / 1024, 1)
        report[name] = m
        flags = []
        if m["seam_ratio"] > SEAM_RATIO_LIMIT:
            flags.append("SEAM CLICK")
        if m["peak"] > PEAK_CEILING:
            flags.append("TOO LOUD")
        if not (RMS_BAND[0] <= m["rms"] <= RMS_BAND[1]):
            flags.append("RMS OUT OF BAND")
        if flags:
            fails.append("%s: %s" % (name, ", ".join(flags)))
        print("%-15s %5.1fs  peak %.3f  rms %.3f  seam %.5f (x%.2f ordinary)  %6.1f KB  %s" % (
            name, m["seconds"], m["peak"], m["rms"], m["seam"], m["seam_ratio"],
            m["kb"], " ".join(flags)))

    # two tracks that measure the same are one track shipped twice
    keys = list(report)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = report[keys[i]], report[keys[j]]
            if (abs(a["rms"] - b["rms"]) < 0.002 and abs(a["seconds"] - b["seconds"]) < 0.01):
                fails.append("%s and %s measure identically" % (keys[i], keys[j]))

    (OUT / "measurements.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    total = sum(m["kb"] for m in report.values())
    print("total %.1f KB" % total)
    if fails:
        print("\nFAILED:")
        for f in fails:
            print("  " + f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
