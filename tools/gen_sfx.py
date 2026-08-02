#!/usr/bin/env python3
"""Generate the game's 23 sound effects as OGG files, in ONE voice.

Why this exists: the sound was three sound sets wearing one name. The effects came
from three CC0 Kenney packs, and the packs do not agree with each other about what
kind of game this is — the receipts are in the file headers:

  * RPG Audio        16 files, 48 kHz stereo   recorded foley: a real knife, real cloth
  * Interface Sounds  5 files, 44.1 kHz mono   soft modern UI blips
  * Music Jingles     5 files, 44.1 kHz stereo 8-bit chiptune fanfares
  * the score (ours)  5 files, 22.05 kHz mono  square waves and pads (gen_music.py)

So winning a fight played a chiptune fanfare, taking a hit played a foley recording,
and clicking a button played a soft modern blip, over a chiptune score. Each file is
fine and the set is incoherent, which is what "the sound is not uniform" means.

Three packs cannot be reconciled by turning knobs, because the difference is the
instrument and not the level. One set can: everything here is synthesised from four
voices at the score's own sample rate, in the score's own key, on one loudness ladder.

## The rules, which are the whole design

  1. **One instrument family.** Square, triangle, filtered noise, and a two-operator
     bell. The same voices `gen_music.py` builds the score from, at the same 22.05 kHz.
     A sound that cannot be made from these is not a sound this game makes.
  2. **In the score's key.** Every pitched effect is built from notes of A natural
     minor, taken through `gen_music.hz`, because the score is in it (menu and dungeon
     are A minor, combat E minor, boss D minor). An effect a semitone out of the key
     is the thing that reads as "from another game" even at the right volume.
  3. **One loudness ladder, stated rather than mixed by ear.** The UI sits under the
     world, the world sits under the stingers, and all of it sits over the music. The
     numbers are `FAMILY` below and every file is normalised to its family's peak.
  4. **Length by family.** A click is a click (≤ 120 ms); a blow lands and is gone
     (≤ 500 ms); only a stinger is allowed to be a phrase (≤ 1.6 s). The old set had a
     10 ms click and a 540 ms confirm in the same menu.

## What is measured, and what fails the run

Blind authoring is not a thing I can do honestly, so the same answer as the music: the
recipe is authored, the RESULT is measured, and the measurements are the gate.

  peak/rms     — the ladder in rule 3, checked per family. A set is uniform when the
                 loudest and the quietest sit inside one stated window, so the spread
                 across the whole set is asserted too (`SPREAD_DB_MAX`).
  centroid     — the spectral centre of mass, in Hz. This is the number that catches
                 the original bug: a foley recording and a square-wave blip differ here
                 by an octave and a half, whatever their levels. Each family has a
                 band, so one effect cannot wander out of the set's timbre.
  seconds      — rule 4.
  distinct     — two effects that measure the same are one effect under two names.

Usage (ffmpeg is only needed here, never at runtime):
    nix shell nixpkgs#ffmpeg-headless --command python3 tools/gen_sfx.py
Then:
    godot --headless --import
"""

import array
import json
import math
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile
import wave

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_music import RATE, hz            # noqa: E402  (same rate, same tuning)

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio"

# --- the ladder --------------------------------------------------------------------
#
# family -> peak, RMS band, seconds ceiling, centroid band in Hz
#
# The peaks are the design: pressing a button is not as loud as being hit, and being hit
# is not as loud as a run ending. The music normalises to 0.55 and has to lose to all of
# it. The centroid bands are the REGISTER each family is written in, and they are a design
# choice rather than a description of the output — the interface plays an octave and a half
# above the score's own arpeggios, so a click is never mistaken for a note in the music,
# while the world and the stingers sit inside the score's register because they are meant
# to belong to it.
FAMILY = {
    "ui":      {"peak": 0.50, "rms": (0.02, 0.30), "secs": 0.12, "hz": (1100, 3600),
                "tight": True},
    "world":   {"peak": 0.72, "rms": (0.04, 0.42), "secs": 0.50, "hz": (150, 3000)},
    "stinger": {"peak": 0.85, "rms": (0.05, 0.40), "secs": 1.60, "hz": (250, 2200)},
}
## How far apart the brightest and the dullest sound in one family may sit, as a ratio of
## centroids — and it is only asked of the family marked `tight`, which is the interface.
## The menu is where uniformity is most audible, because its sounds play back-to-back
## within a second of each other and mean nearly the same thing; two octaves apart there is
## two instruments. The world is deliberately the opposite: a heavy blow at 190 Hz and a
## handful of coins at 2.8 kHz are the same instrument set being used for different things,
## and squeezing that range would cost the game its ability to say which is which.
TIMBRE_RATIO_MAX = 2.6
# How far apart the loudest and quietest file in the whole set may sit, in dB of RMS.
# This is the uniformity check: the old set spanned far more than this, which is why one
# effect could be inaudible and the next one startling at the same slider setting.
SPREAD_DB_MAX = 22.0

# A natural minor, which is the key the score is in. Everything pitched is picked from
# here by NAME, so an accidental cannot be typed as a frequency.
SCALE = ["a3", "b3", "c4", "d4", "e4", "f4", "g4", "a4", "b4", "c5", "d5", "e5",
         "a5", "b5", "c6", "d6", "e6"]


def note(name: str) -> float:
    if name not in SCALE:
        raise ValueError("%s is not in the score's key" % name)
    return hz(name)


# --- voices ------------------------------------------------------------------------
#
# One-shots, so nothing wraps: a tail that runs past the end of the buffer is simply
# cut, and every recipe leaves room for its own tail. (The score's voices wrap on
# purpose, because a loop is a circle — see gen_music.)


def buf(secs: float) -> array.array:
    return array.array("d", [0.0] * int(secs * RATE))


def _env(i: int, total: int, attack: int, decay: float) -> float:
    """Ramped attack, exponential decay. The ramp is not a nicety: a one-shot that
    starts at full amplitude puts a step in the waveform at sample zero, which is a
    click in front of every sound — the same defect `gen_music.hit` documents."""
    return min(1.0, i / attack) * math.exp(-decay * i / total)


def square(b, start, dur, freq, gain, decay=5.0, detune=0.0):
    """The score's arpeggio voice: three odd harmonics, band-limited by stopping there."""
    n = len(b)
    total = int(dur * RATE)
    attack = max(1, int(0.0015 * RATE))
    w = 2.0 * math.pi * freq / RATE
    for i in range(total):
        j = start + i
        if j >= n:
            break
        f = w * (1.0 + detune * i / total)
        s = math.sin(f * i) + math.sin(3 * f * i) / 3.0 + math.sin(5 * f * i) / 5.0
        b[j] += gain * _env(i, total, attack, decay) * s * 0.8


def tri(b, start, dur, freq, gain, decay=4.0):
    """Softer than the square and darker than a sine: the UI voice."""
    n = len(b)
    total = int(dur * RATE)
    attack = max(1, int(0.002 * RATE))
    w = 2.0 * math.pi * freq / RATE
    for i in range(total):
        j = start + i
        if j >= n:
            break
        s = math.sin(w * i) + math.sin(3 * w * i) / 9.0 + math.sin(5 * w * i) / 25.0
        b[j] += gain * _env(i, total, attack, decay) * s


def bell(b, start, dur, freq, gain, ratio=2.76, index=1.4, decay=3.2):
    """Two operators: a struck, metallic tone. What a coin, a chest and a fusion get,
    because a pitched click cannot say "something valuable happened" and this can."""
    n = len(b)
    total = int(dur * RATE)
    attack = max(1, int(0.001 * RATE))
    w = 2.0 * math.pi * freq / RATE
    for i in range(total):
        j = start + i
        if j >= n:
            break
        e = _env(i, total, attack, decay)
        mod = index * e * math.sin(w * ratio * i)
        b[j] += gain * e * math.sin(w * i + mod)


def noise(b, start, dur, gain, tone=0.0, decay=9.0, colour=0.55, width=0.0):
    """Filtered noise: impact, cloth, breath. `colour` is a one-pole low pass (higher is
    darker), `tone` adds a pitched body, `width` sweeps the filter open as it decays so a
    hit opens rather than just stops."""
    n = len(b)
    total = int(dur * RATE)
    attack = max(1, int(0.0015 * RATE))
    last = 0.0
    for i in range(total):
        j = start + i
        if j >= n:
            break
        e = _env(i, total, attack, decay)
        k = colour + width * (i / total)
        last = last * k + random.uniform(-1.0, 1.0) * (1.0 - k)
        s = last
        if tone > 0.0:
            s += 0.6 * math.sin(2.0 * math.pi * tone * i / RATE) * e
        b[j] += gain * e * s


def sweep(b, start, dur, f0, f1, gain, decay=2.5, kind="tri"):
    """A glide. Movement — a card leaving the hand, a door, a run beginning."""
    n = len(b)
    total = int(dur * RATE)
    attack = max(1, int(0.004 * RATE))
    phase = 0.0
    for i in range(total):
        j = start + i
        if j >= n:
            break
        f = f0 * (f1 / f0) ** (i / total)
        phase += 2.0 * math.pi * f / RATE
        s = math.sin(phase)
        if kind == "square":
            s = s + math.sin(3 * phase) / 3.0 + math.sin(5 * phase) / 5.0
        b[j] += gain * _env(i, total, attack, decay) * s * 0.8


# --- the effects -------------------------------------------------------------------
#
# One function per event name in `Audio.SOUNDS`. Each returns (buffer, family).


def ui_click():
    b = buf(0.09)
    tri(b, 0, 0.06, note("a5"), 0.5, decay=7.0)
    return b, "ui"


def ui_select():
    """Moving between things: the same tick, one scale step up, so a menu sounds like
    one instrument being played rather than a set of unrelated noises."""
    b = buf(0.10)
    tri(b, 0, 0.07, note("c6"), 0.45, decay=6.0)
    return b, "ui"


def ui_back():
    """Down where the others go up. Nothing else about it changes."""
    b = buf(0.11)
    tri(b, 0, 0.08, note("e5"), 0.45, decay=6.0)
    return b, "ui"


def ui_open():
    """A panel arriving: two notes up, fast."""
    b = buf(0.12)
    tri(b, 0, 0.05, note("e5"), 0.38, decay=7.0)
    tri(b, int(0.035 * RATE), 0.07, note("a5"), 0.42, decay=6.0)
    return b, "ui"


def ui_confirm():
    """Up a fifth. The one UI sound allowed to be an interval, because committing is the
    one UI action with a consequence."""
    b = buf(0.12)
    tri(b, 0, 0.06, note("a5"), 0.40, decay=6.5)
    tri(b, int(0.04 * RATE), 0.07, note("e6"), 0.45, decay=6.0)
    return b, "ui"


def ui_denied():
    """The minor second, unresolved — the one interval in the key that means no. Two
    notes a semitone apart beat a buzzer: a buzzer is not in any key."""
    b = buf(0.12)
    tri(b, 0, 0.09, note("b5"), 0.40, decay=5.0)
    tri(b, 0, 0.09, note("c6"), 0.40, decay=5.0)
    return b, "ui"


def card_play():
    """A card leaving the hand: a short upward glide with a breath of cloth under it."""
    b = buf(0.24)
    sweep(b, 0, 0.14, note("a4"), note("e5"), 0.30, decay=3.0)
    noise(b, 0, 0.16, 0.16, decay=7.0, colour=0.40, width=0.30)
    return b, "world"


def attack():
    b = buf(0.26)
    noise(b, 0, 0.16, 0.55, tone=note("a3") / 2.0, decay=8.0, colour=0.35, width=0.35)
    square(b, 0, 0.10, note("a3"), 0.16, decay=9.0, detune=-0.25)
    return b, "world"


def attack_heavy():
    """The same blow, lower and slower, with a second impact under it. Heavier is not
    louder — the ladder gives both the same family peak — it is longer and darker."""
    b = buf(0.42)
    noise(b, 0, 0.30, 0.55, tone=note("a3") / 4.0, decay=6.0, colour=0.62, width=0.22)
    noise(b, int(0.05 * RATE), 0.24, 0.30, decay=7.0, colour=0.72)
    square(b, 0, 0.18, note("a3") / 2.0, 0.22, decay=7.0, detune=-0.35)
    return b, "world"


def block():
    """Something hard stopping something hard: a bright, short, metallic tap."""
    b = buf(0.30)
    bell(b, 0, 0.22, note("e5"), 0.34, ratio=3.4, index=1.9, decay=6.0)
    noise(b, 0, 0.10, 0.26, decay=11.0, colour=0.22)
    return b, "world"


def hurt():
    """Taking it: a falling glide, which is the shape of every wince there has ever
    been, over a dull impact."""
    b = buf(0.30)
    sweep(b, 0, 0.20, note("d4"), note("a3"), 0.34, decay=4.0)
    noise(b, 0, 0.14, 0.30, tone=note("a3") / 2.0, decay=9.0, colour=0.66)
    return b, "world"


def poison():
    """A bubble: the filter opening on a slow, quiet hiss with a rising tone in it."""
    b = buf(0.40)
    noise(b, 0, 0.34, 0.30, decay=4.0, colour=0.80, width=-0.35)
    sweep(b, int(0.02 * RATE), 0.22, note("a3"), note("c4"), 0.16, decay=3.0)
    return b, "world"


def buff():
    """Something being added to you: the minor triad, up, arpeggiated fast."""
    b = buf(0.34)
    for k, n in enumerate(["a4", "c5", "e5"]):
        square(b, int(k * 0.045 * RATE), 0.16, note(n), 0.22, decay=5.0)
    return b, "world"


def gold():
    """Coins: three bells at scale steps, close together and slightly random in level,
    because a handful of coins is not one coin three times."""
    b = buf(0.44)
    for k, n in enumerate(["e5", "a5", "c5"]):
        bell(b, int(k * 0.035 * RATE), 0.30, note(n), 0.26 + 0.03 * k,
             ratio=2.4, index=1.2, decay=5.0)
    return b, "world"


def treasure():
    """A chest: the lid (a wooden knock) then what is inside it (a bell)."""
    b = buf(0.46)
    noise(b, 0, 0.10, 0.34, tone=note("a3"), decay=12.0, colour=0.58)
    bell(b, int(0.09 * RATE), 0.34, note("c5"), 0.30, ratio=2.0, index=1.5, decay=4.0)
    return b, "world"


def fuse():
    """Two cards becoming one, which is the meta layer's whole verb: two notes sliding
    into the same note."""
    b = buf(0.46)
    sweep(b, 0, 0.30, note("a3"), note("a4"), 0.24, decay=2.2)
    sweep(b, 0, 0.30, note("e5"), note("a4"), 0.24, decay=2.2)
    bell(b, int(0.26 * RATE), 0.20, note("a4"), 0.26, decay=5.0)
    return b, "world"


def event():
    """A rune stone waking up: a low fifth, quiet, with air under it."""
    b = buf(0.44)
    tri(b, 0, 0.34, note("a3"), 0.26, decay=3.0)
    tri(b, int(0.03 * RATE), 0.30, note("e4"), 0.20, decay=3.0)
    noise(b, 0, 0.30, 0.10, decay=3.5, colour=0.85)
    return b, "world"


def enter():
    """Going down. A descending fourth and a breath, and it is the mirror of `leave`
    because the two are one door used twice."""
    b = buf(0.46)
    sweep(b, 0, 0.26, note("d4"), note("a3"), 0.28, decay=2.6, kind="square")
    noise(b, 0, 0.34, 0.16, decay=4.0, colour=0.78, width=0.14)
    return b, "world"


def leave():
    b = buf(0.46)
    sweep(b, 0, 0.26, note("a3"), note("d4"), 0.28, decay=2.6, kind="square")
    noise(b, 0, 0.34, 0.16, decay=4.0, colour=0.78, width=0.14)
    return b, "world"


def reward():
    """Cards banked: the minor triad up, held, with a bell on the top note. Same shape
    as `buff` an octave up and twice as long — a reward is a buff you keep."""
    b = buf(0.90)
    for k, n in enumerate(["a4", "c5", "e5"]):
        square(b, int(k * 0.09 * RATE), 0.40, note(n), 0.22, decay=3.4)
    bell(b, int(0.27 * RATE), 0.55, note("a5"), 0.26, decay=3.0)
    return b, "stinger"


def victory():
    """A run brought home. Four notes, minor, RISING and landing on the tonic an octave
    up: this game does not do major keys, and it does not need one to sound like winning.
    """
    b = buf(1.40)
    for k, n in enumerate(["a3", "c4", "e4", "a4"]):
        square(b, int(k * 0.13 * RATE), 0.44, note(n), 0.26, decay=3.0)
    square(b, int(0.52 * RATE), 0.70, note("a4"), 0.24, decay=1.8)
    bell(b, int(0.52 * RATE), 0.75, note("e5"), 0.22, decay=2.4)
    noise(b, int(0.52 * RATE), 0.30, 0.12, decay=5.0, colour=0.30)
    return b, "stinger"


def defeat():
    """The same four notes, backwards and slowing, ending on the note it started from an
    octave down. Everything found this run is forfeit, and the sound is the fanfare
    losing its nerve rather than a new idea."""
    b = buf(1.55)
    for k, n in enumerate(["a4", "e4", "c4", "a3"]):
        tri(b, int(k * 0.17 * RATE), 0.50, note(n), 0.26, decay=2.6)
    tri(b, int(0.70 * RATE), 0.80, note("a3") / 2.0, 0.30, decay=1.6)
    noise(b, int(0.70 * RATE), 0.50, 0.10, decay=3.0, colour=0.86)
    return b, "stinger"


def boss_cleared():
    """The one named thing on the floor is down. Victory's phrase with the fifth added
    under it and a struck bell on top — the largest sound in the game, and still in the
    same key on the same four voices."""
    b = buf(1.60)
    for k, n in enumerate(["a3", "c4", "e4", "a4"]):
        square(b, int(k * 0.11 * RATE), 0.40, note(n), 0.22, decay=3.2)
        square(b, int(k * 0.11 * RATE), 0.40, note(n) / 2.0, 0.14, decay=3.2)
    bell(b, int(0.46 * RATE), 0.90, note("a5"), 0.26, ratio=2.0, index=1.6, decay=2.0)
    tri(b, int(0.46 * RATE), 0.95, note("e5"), 0.20, decay=1.8)
    noise(b, int(0.46 * RATE), 0.40, 0.14, decay=4.0, colour=0.30)
    return b, "stinger"


# Keyed exactly like `Audio.SOUNDS`: the event name IS the file stem, and a name here
# that the game never asks for is dead weight the game cannot tell you about.
EFFECTS = {
    "ui_click": ui_click, "ui_select": ui_select, "ui_back": ui_back,
    "ui_confirm": ui_confirm, "ui_denied": ui_denied, "ui_open": ui_open,
    "attack": attack, "attack_heavy": attack_heavy, "block": block,
    "hurt": hurt, "poison": poison, "card_play": card_play, "buff": buff,
    "gold": gold, "event": event, "enter": enter, "leave": leave,
    "treasure": treasure, "fuse": fuse,
    "reward": reward, "victory": victory, "defeat": defeat,
    "boss_cleared": boss_cleared,
}


# --- measurement -------------------------------------------------------------------


def trim(b, floor=0.0015):
    """Cut silence off the tail. The recipes leave room for their own decay, and what is
    left over is bytes and latency rather than sound."""
    end = len(b)
    while end > 1 and abs(b[end - 1]) < floor:
        end -= 1
    # a few ms of run-out, so the encoder is not asked to stop mid-decay
    end = min(len(b), end + int(0.005 * RATE))
    return b[:end]


def normalize(b, target_peak):
    peak = max((abs(s) for s in b), default=0.0) or 1.0
    g = target_peak / peak
    for i in range(len(b)):
        b[i] *= g


def centroid(b):
    """Spectral centre of mass in Hz, by Goertzel over log-spaced bins. Cheap, and it
    only has to separate a square-wave blip from a foley recording — which it does by
    the better part of an octave."""
    n = len(b)
    if n < 64:
        return 0.0
    num = den = 0.0
    f = 80.0
    while f < RATE / 2.0 * 0.98:
        w = 2.0 * math.pi * f / RATE
        cr = math.cos(w)
        coeff = 2.0 * cr
        s1 = s2 = 0.0
        for i in range(0, n, 2):          # every other sample: this is a shape, not a spec
            s0 = b[i] + coeff * s1 - s2
            s2 = s1
            s1 = s0
        power = s1 * s1 + s2 * s2 - coeff * s1 * s2
        power = max(0.0, power)
        num += f * power
        den += power
        f *= 1.25
    return num / den if den else 0.0


def measure(b):
    n = len(b)
    rms = math.sqrt(sum(x * x for x in b) / n)
    return {
        "seconds": round(n / RATE, 3),
        "peak": round(max(abs(s) for s in b), 4),
        "rms": round(rms, 4),
        "centroid_hz": round(centroid(b)),
    }


def write_wav(path, b):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array("h", [
            int(max(-1.0, min(1.0, s)) * 32767) for s in b]).tobytes())


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found. Run under:  nix shell nixpkgs#ffmpeg-headless")
        return 127
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed(20260802)                 # reproducible: same script, same bytes
    report = {}
    fails = []
    tmp = pathlib.Path(tempfile.mkdtemp())
    print("%-14s %-8s %6s %6s %6s %8s %7s" % (
        "file", "family", "secs", "peak", "rms", "centroid", "KB"))
    for name, fn in EFFECTS.items():
        b, fam = fn()
        spec = FAMILY[fam]
        b = trim(b)
        normalize(b, spec["peak"])
        m = measure(b)
        m["family"] = fam
        wav = tmp / (name + ".wav")
        write_wav(wav, b)
        ogg = OUT / (name + ".ogg")
        # -q:a 3 rather than the score's fixed 56k: these are transients, and vorbis
        # spends its bits where the file needs them when it is asked by quality.
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
             "-c:a", "libvorbis", "-q:a", "3", "-ac", "1", str(ogg)],
            check=True)
        m["kb"] = round(ogg.stat().st_size / 1024, 1)
        report[name] = m

        flags = []
        if m["seconds"] > spec["secs"]:
            flags.append("TOO LONG")
        if not (spec["rms"][0] <= m["rms"] <= spec["rms"][1]):
            flags.append("RMS OUT OF FAMILY")
        if not (spec["hz"][0] <= m["centroid_hz"] <= spec["hz"][1]):
            flags.append("TIMBRE OUT OF FAMILY")
        if flags:
            fails.append("%s: %s" % (name, ", ".join(flags)))
        print("%-14s %-8s %6.3f %6.3f %6.3f %7dHz %6.1f %s" % (
            name, fam, m["seconds"], m["peak"], m["rms"], m["centroid_hz"], m["kb"],
            " ".join(flags)))

    # the uniformity checks: one set, not several
    loud = max(report.values(), key=lambda m: m["rms"])
    quiet = min(report.values(), key=lambda m: m["rms"])
    spread = 20.0 * math.log10(loud["rms"] / max(1e-9, quiet["rms"]))
    if spread > SPREAD_DB_MAX:
        fails.append("the set spans %.1f dB of RMS (ceiling %.1f) — that is not one set"
                     % (spread, SPREAD_DB_MAX))
    for fam, spec in FAMILY.items():
        band = [m["centroid_hz"] for m in report.values() if m["family"] == fam]
        if len(band) < 2:
            continue
        ratio = max(band) / max(1.0, min(band))
        tight = bool(spec.get("tight", False))
        print("  %-8s %2d files, %4d-%4dHz, timbre spread x%.2f%s" % (
            fam, len(band), min(band), max(band), ratio,
            " (ceiling x%.2f)" % TIMBRE_RATIO_MAX if tight else ""))
        if tight and ratio > TIMBRE_RATIO_MAX:
            fails.append("the %s family spans x%.2f in timbre (ceiling x%.2f)"
                         % (fam, ratio, TIMBRE_RATIO_MAX))

    # two effects that measure the same are one effect under two names
    keys = list(report)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, c = report[keys[i]], report[keys[j]]
            if (abs(a["rms"] - c["rms"]) < 0.002
                    and abs(a["seconds"] - c["seconds"]) < 0.005
                    and abs(a["centroid_hz"] - c["centroid_hz"]) < 30):
                fails.append("%s and %s measure identically" % (keys[i], keys[j]))

    (OUT / "measurements.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n")
    print("\n%d files, %.1f KB total, RMS spread %.1f dB (ceiling %.1f)" % (
        len(report), sum(m["kb"] for m in report.values()), spread, SPREAD_DB_MAX))
    if fails:
        print("\nFAILED:")
        for f in fails:
            print("  " + f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
