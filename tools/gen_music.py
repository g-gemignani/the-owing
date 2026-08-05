#!/usr/bin/env python3
"""Generate the game's looping score as seamless OGG files.

The instrument is `tools/audio_voices.py` and the effects are built from the same one, so
the score and the sound cannot drift apart (that was D150's lesson and it is now structural
rather than a comment in two files).

## What changed in D173, and why

This score was five chiptune loops: square-wave arpeggios and sine pads over a four-chord
progression, bone dry, 22.05 kHz, each with a beat you could tap. It measured clean. It
sounded like a different, older, smaller game than the one the art is for.

The target is *Diablo*'s kind of score, arrived at from first principles rather than copied:

  * **A place, not a tune.** Drones and modal colour instead of chord progressions. A
    progression tells you where the music is going; a drone tells you where you are.
  * **No pulse outside a fight.** The town, the overworld and the dungeon have no beat at
    all. Phrases fall at intervals nobody can count, so the music never becomes furniture
    you tap along to — and when the drums DO arrive, they mean a fight.
  * **A stone room.** Every track is put through `reverb_loop`, and the dungeon's room is
    the biggest thing in the mix.
  * **Real instruments, modelled.** A plucked string (`pluck`), low bowed strings (`bow`),
    a far-off choir (`choir`), struck metal (`metal`) and frame drums (`drum`).

Nothing here is transcribed from anything. Drones, minor seconds, tritones and bare fifths
are the shared vocabulary of dark fantasy, the way a minor key is the vocabulary of sad;
the phrases, the instrument set and the arrangements are this project's.

## What is measured, and what fails the run

Choosing music by ear is not a judgement I can make honestly, so the recipe is authored and
the RESULT is measured. Printed on every run, and a file outside its band is a failure, not
a shrug:

  seam       — the sample-to-sample step across the loop point, against the steps the
               waveform takes everywhere else. A loop is a circle, and a discontinuity
               there clicks every N seconds forever. The comparison is the trick: a first
               pass compared the first 50 ms with the last 50 ms and failed everything,
               because a loop that begins on a downbeat and ends on a decay is SUPPOSED to
               jump in level there. That is music. A click is a step the waveform does not
               otherwise take.
  rms/peak   — music must sit under the effects. Anything that competes with the attack
               sound for attention is a bug.
  pulse      — how strongly the track keeps time, 0 to 1, and the number that says what
               actually changed here. Measured on the OLD score, every track had a beat:
               menu 0.48, overworld 0.23, dungeon 0.59, combat 0.78, boss 0.58. A dungeon
               you can tap along to is a dungeon you stop being afraid of. The three
               ambient tracks now have to measure BELOW a ceiling and the two fight tracks
               ABOVE a floor — a fight you count turns against needs something to count.
  centroid   — the spectral centre of mass, with a ceiling. Worth being honest about: the
               old score measured 121-175 Hz here, DARKER than what replaced it, because
               sine pads at 22.05 kHz are not dark so much as muffled. The ceiling is not a
               correction of the old score; it is a guard on the new instrument, which owns
               struck metal, a choir and two air beds and could go bright by accident.
  low        — the share of energy under 200 Hz. Weight, as a number, with a floor, for the
               same reason: the plucked string and the choir must not float off the bottom.
  quiet      — the quietest two seconds against the track's own average, with a floor. New
               with the style: phrases are now up to 4.6 seconds apart, and a gap with
               nothing under it reads as the music having stopped rather than as space.
  distinct   — two tracks that measure the same are one track shipped twice.

Seams cannot drift, because they are not fixed afterwards: every voice is written into the
buffer modulo its length, and the room is primed with the loop's own tail (`reverb_loop`),
so the loop is continuous by construction.

Usage (ffmpeg is only needed here, never at runtime):
    nix shell nixpkgs#ffmpeg-headless --command python3 tools/gen_music.py
"""

import json
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_voices as V                                    # noqa: E402
from audio_voices import RATE, hz, up                       # noqa: E402  (re-exported)

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio" / "music"


# --- the tracks ---------------------------------------------------------------------
#
# Times are in SECONDS, not beats, for everything without a pulse — which is three of the
# five. Writing a dungeon on a beat grid is how it ends up with a beat.


def track_menu():
    """Title and save slots: a room somewhere safe, at night, with someone playing.

    One plucked string, a low pedal underneath, and long silences. The phrase is A aeolian
    and deliberately unresolved — it keeps landing on the fifth and the fourth rather than
    the tonic, so it never finishes and you never wait for it to.
    """
    b = V.buf(44.0)
    # the pedal: two long bowed notes that overlap and wrap, so the drone has no beginning
    V.bow(b, 0, 24.0, hz("a2"), 0.16, cutoff=520.0, wrap=True)
    V.bow(b, int(21.0 * RATE), 25.0, hz("a2"), 0.16, cutoff=520.0, wrap=True)
    V.bow(b, int(12.0 * RATE), 15.0, hz("e3"), 0.07, cutoff=700.0, wrap=True)
    # the phrase. Irregular on purpose: the gaps are 1.1 to 4.6 seconds, so there is no
    # interval for a listener to lock onto.
    phrase = [
        (0.9, "a3", 0.34), (2.6, "e4", 0.26), (3.5, "c4", 0.22), (6.3, "d4", 0.30),
        (9.1, "a3", 0.24), (10.4, "b3", 0.20), (13.8, "e4", 0.32), (17.3, "c4", 0.24),
        (18.6, "d4", 0.22), (21.2, "a3", 0.30), (25.7, "f4", 0.26), (27.2, "e4", 0.22),
        (30.4, "c4", 0.28), (34.1, "a3", 0.24), (35.4, "b3", 0.20), (38.9, "e4", 0.30),
        (41.6, "d4", 0.22),
    ]
    for t, n, g in phrase:
        V.pluck(b, int(t * RATE), 4.0, hz(n), g, t60=2.8, damp=0.40, wrap=True)
    # something metal, far off, twice — a latch or a bell in another building
    V.metal(b, int(16.0 * RATE), 5.0, hz("a3"), 0.045, kind="bell", t60=3.4,
            strike=0.15, wrap=True)
    V.metal(b, int(33.2 * RATE), 5.0, hz("e3"), 0.038, kind="bell", t60=3.6,
            strike=0.12, wrap=True)
    V.air(b, 0, 44.0, 0.05, low=280.0, high=420.0, q=0.9, attack=0.02, release=0.02,
          wrap=True)
    return b, dict(room=0.90, damp=0.30, wet=0.44, pre=0.030)


def track_world():
    """The overworld and the screens reached from it: outdoors, moving, not yet in danger.

    The same string, but in open fifths rather than single notes, and a bell that says
    there is a settlement somewhere. D aeolian, a fourth down from the menu's key, which is
    what makes leaving town feel like going out rather than changing screens.
    """
    b = V.buf(40.0)
    V.bow(b, 0, 22.0, hz("d2"), 0.15, cutoff=560.0, wrap=True)
    V.bow(b, int(19.5 * RATE), 23.0, hz("d2"), 0.15, cutoff=560.0, wrap=True)
    V.bow(b, int(8.0 * RATE), 13.0, hz("a2"), 0.08, cutoff=720.0, wrap=True)
    V.bow(b, int(26.0 * RATE), 12.0, hz("a2"), 0.07, cutoff=720.0, wrap=True)
    # bare fifths: no third, so it is open country and not a chord
    for t, low, high, g in [(0.4, "d3", "a3", 0.30), (5.3, "a3", "e4", 0.24),
                            (10.1, "d3", "a3", 0.26), (16.4, "f3", "c4", 0.24),
                            (21.2, "d3", "a3", 0.28), (27.5, "g3", "d4", 0.22),
                            (32.1, "a3", "e4", 0.26), (36.6, "d3", "a3", 0.24)]:
        V.pluck(b, int(t * RATE), 4.5, hz(low), g, t60=3.0, damp=0.38, wrap=True)
        V.pluck(b, int((t + 0.09) * RATE), 4.5, hz(high), g * 0.7, t60=2.6, damp=0.42,
                wrap=True)
    for t, n, g in [(3.1, "d4", 0.20), (8.2, "f4", 0.18), (13.6, "e4", 0.20),
                    (19.0, "a4", 0.16), (24.4, "d4", 0.18), (30.2, "c4", 0.18),
                    (34.8, "e4", 0.16)]:
        V.pluck(b, int(t * RATE), 3.2, hz(n), g, t60=2.2, damp=0.44, wrap=True)
    V.metal(b, int(11.5 * RATE), 6.0, hz("d3"), 0.05, kind="bell", t60=4.2, strike=0.12,
            wrap=True)
    V.metal(b, int(30.8 * RATE), 6.0, hz("d3"), 0.045, kind="bell", t60=4.2, strike=0.10,
            wrap=True)
    V.air(b, 0, 40.0, 0.06, low=340.0, high=620.0, q=0.8, grain=0.35, attack=0.02,
          release=0.02, wrap=True)
    return b, dict(room=0.88, damp=0.34, wet=0.38, pre=0.024)


def track_dungeon():
    """Traversal, the shop, an event: underground, and it has no melody at all.

    This is the track the whole exercise was for. Nothing here plays a tune: two bowed
    drones a few cents apart beat against each other, a choir swells somewhere behind the
    wall, stone drags, and something the size of a room takes a slow irregular breath. The
    flat second (bb over a) arrives halfway through and never resolves, which is the sound
    of being somewhere you are not welcome.

    A phrygian. The heartbeat hits are at 2.0, 9.3, 17.8, 23.1, 31.6 and 42.0 seconds —
    intervals of 7.3, 8.5, 5.3, 8.5 and 10.4, so there is nothing to count.
    """
    b = V.buf(48.0)
    root = hz("a2")
    V.bow(b, 0, 26.0, root, 0.17, cutoff=420.0, wrap=True)
    V.bow(b, int(23.0 * RATE), 27.0, root, 0.17, cutoff=420.0, wrap=True)
    # the beating pair: 6 cents apart, which is a slow throb rather than a chord
    V.bow(b, 0, 30.0, root * 1.0035, 0.11, cutoff=380.0, wrap=True)
    V.bow(b, int(27.0 * RATE), 24.0, root * 1.0035, 0.11, cutoff=380.0, wrap=True)
    # the flat second, entering late and leaving before it can be resolved
    V.bow(b, int(20.0 * RATE), 17.0, up(root, "min2"), 0.055, cutoff=340.0, wrap=True)
    V.choir(b, int(7.5 * RATE), 13.0, hz("a3"), 0.075, vowel="oo", breath=0.35, wrap=True)
    V.choir(b, int(29.0 * RATE), 15.0, hz("e3"), 0.060, vowel="oo", breath=0.40, wrap=True)
    for t, f, g, d in [(4.2, 62.0, 0.075, 1.4), (13.1, 48.0, 0.060, 2.1),
                       (25.6, 74.0, 0.070, 1.1), (39.4, 55.0, 0.055, 1.8)]:
        V.scrape(b, int(t * RATE), d, g, freq=f, rough=0.7, bright=760.0, wrap=True)
    for t, f, g in [(2.0, 54.0, 0.13), (9.3, 49.0, 0.10), (17.8, 58.0, 0.12),
                    (23.1, 49.0, 0.09), (31.6, 54.0, 0.12), (42.0, 46.0, 0.10)]:
        V.drum(b, int(t * RATE), 1.1, f, g, snap=0.10, bend=0.35, t60=0.55, shell=0.15,
               wrap=True)
        V.sub(b, int(t * RATE), 1.6, f * 0.62, g * 0.55, fall=0.12, t60=0.9, wrap=True)
    V.metal(b, int(20.4 * RATE), 4.0, hz("e4"), 0.030, kind="bar", t60=2.2, strike=0.25,
            wrap=True)
    V.metal(b, int(44.6 * RATE), 4.0, hz("c4"), 0.026, kind="bar", t60=2.4, strike=0.20,
            wrap=True)
    # two beds: one under the drone, one moving across it, which is what a cave does
    V.air(b, 0, 48.0, 0.07, low=140.0, high=200.0, q=0.7, attack=0.02, release=0.02,
          wrap=True)
    V.air(b, 0, 48.0, 0.045, low=1400.0, high=520.0, q=1.4, grain=0.55, attack=0.02,
          release=0.02, wrap=True)
    return b, dict(room=0.93, damp=0.26, wet=0.50, pre=0.038)


def track_combat():
    """A fight. The drums arrive, and they are the only thing in the game that keeps time.

    Frame drums on a heavy, limping pattern rather than a march — the accents fall on 1 and
    the second half of 2, so it drives without becoming a beat you dance to. E phrygian,
    with the tritone appearing under the second third and the flat second under the last:
    the track gets worse as it goes on, and it loops back to where it started.
    """
    bpm = 86.0
    beat = 60.0 / bpm
    bars = 12
    b = V.buf(bars * 4 * beat)
    root = hz("e2")
    V.bow(b, 0, bars * 4 * beat * 0.6, root, 0.16, cutoff=480.0, wrap=True)
    V.bow(b, int(bars * 4 * beat * 0.55 * RATE), bars * 4 * beat * 0.55, root, 0.16,
          cutoff=480.0, wrap=True)
    V.bow(b, int(4 * 4 * beat * RATE), 4 * 4 * beat, up(root, "tritone"), 0.055,
          cutoff=420.0, wrap=True)
    V.bow(b, int(8 * 4 * beat * RATE), 4 * 4 * beat, up(root, "min2"), 0.050,
          cutoff=400.0, wrap=True)
    # the pattern, in eighths of a bar: (position, gain, pitch)
    pattern = [(0.0, 0.26, 76.0), (1.5, 0.14, 108.0), (2.0, 0.20, 88.0),
               (3.0, 0.13, 108.0), (3.5, 0.16, 96.0)]
    for bar in range(bars):
        t0 = bar * 4 * beat
        for pos, g, f in pattern:
            # every fourth bar drops the last hit and doubles the first: a phrase, so
            # twelve bars is not the same bar twelve times
            if bar % 4 == 3 and pos == 3.5:
                continue
            V.drum(b, int((t0 + pos * beat) * RATE), 0.8, f, g, snap=0.30, bend=0.50,
                   t60=0.32, shell=0.28, wrap=True)
        V.sub(b, int(t0 * RATE), 0.9, 44.0, 0.16, fall=0.15, t60=0.45, wrap=True)
        if bar % 4 == 3:
            V.drum(b, int((t0 + 3.25 * beat) * RATE), 0.7, 84.0, 0.20, snap=0.35,
                   bend=0.55, t60=0.28, shell=0.30, wrap=True)
            V.drum(b, int((t0 + 3.75 * beat) * RATE), 0.7, 72.0, 0.24, snap=0.35,
                   bend=0.55, t60=0.30, shell=0.30, wrap=True)
        # two plucked notes a bar, off the beat, from the mode's dark end
        n = [hz("e3"), hz("f3"), hz("e3"), hz("b3")][bar % 4]
        V.pluck(b, int((t0 + 1.25 * beat) * RATE), 2.0, n, 0.16, t60=1.6, damp=0.44,
                wrap=True)
        V.pluck(b, int((t0 + 2.75 * beat) * RATE), 1.6, n * 1.5, 0.11, t60=1.3,
                damp=0.46, wrap=True)
    for bar in (2, 6, 10):
        V.metal(b, int(bar * 4 * beat * RATE), 2.2, hz("e4"), 0.075, kind="plate",
                t60=1.1, strike=0.6, wrap=True)
    V.air(b, 0, bars * 4 * beat, 0.045, low=900.0, high=380.0, q=1.0, grain=0.4,
          attack=0.02, release=0.02, wrap=True)
    return b, dict(room=0.86, damp=0.40, wet=0.30, pre=0.018)


def track_boss():
    """The named thing at the bottom. The same pulse, heavier, and one grinding semitone.

    D locrian — the mode with a flat fifth, which is the darkest thing available without
    leaving a key. The drone is a minor second held against itself for the whole loop, so
    the beating never stops, and the choir is close enough to be in the room.
    """
    bpm = 92.0
    beat = 60.0 / bpm
    bars = 12
    b = V.buf(bars * 4 * beat)
    root = hz("d2")
    span = bars * 4 * beat
    V.bow(b, 0, span * 0.6, root, 0.17, cutoff=460.0, wrap=True)
    V.bow(b, int(span * 0.55 * RATE), span * 0.55, root, 0.17, cutoff=460.0, wrap=True)
    V.bow(b, 0, span * 0.62, up(root, "min2"), 0.075, cutoff=400.0, wrap=True)
    V.bow(b, int(span * 0.58 * RATE), span * 0.5, up(root, "min2"), 0.075, cutoff=400.0,
          wrap=True)
    V.bow(b, int(4 * 4 * beat * RATE), 5 * 4 * beat, up(root, "tritone"), 0.060,
          cutoff=430.0, wrap=True)
    V.choir(b, int(0.5 * 4 * beat * RATE), 6 * 4 * beat, hz("d3"), 0.070, vowel="oh",
            breath=0.30, wrap=True)
    V.choir(b, int(6.5 * 4 * beat * RATE), 6 * 4 * beat, hz("a3"), 0.058, vowel="oh",
            breath=0.30, wrap=True)
    for bar in range(bars):
        t0 = bar * 4 * beat
        for pos, g, f in [(0.0, 0.46, 68.0), (1.0, 0.18, 100.0), (2.0, 0.34, 80.0),
                          (3.0, 0.19, 100.0)]:
            V.drum(b, int((t0 + pos * beat) * RATE), 0.9, f, g, snap=0.34, bend=0.55,
                   t60=0.36, shell=0.30, wrap=True)
        V.sub(b, int(t0 * RATE), 1.1, 40.0, 0.26, fall=0.18, t60=0.55, wrap=True)
        V.sub(b, int((t0 + 2 * beat) * RATE), 0.9, 46.0, 0.17, fall=0.14, t60=0.40,
              wrap=True)
        if bar % 3 == 2:                      # a three-bar phrase over a four-beat bar,
            for k in (3.33, 3.66):            # so the two never line up the same way twice
                V.drum(b, int((t0 + k * beat) * RATE), 0.6, 88.0, 0.26, snap=0.38,
                       bend=0.6, t60=0.26, shell=0.32, wrap=True)
        n = [hz("d3"), hz("eb3"), hz("ab3"), hz("d3")][bar % 4]
        V.pluck(b, int((t0 + 1.5 * beat) * RATE), 1.8, n, 0.14, t60=1.4, damp=0.46,
                wrap=True)
    for bar in (0, 4, 8):
        V.metal(b, int(bar * 4 * beat * RATE), 3.0, hz("d4"), 0.085, kind="bar", t60=1.6,
                strike=0.7, wrap=True)
    V.air(b, 0, span, 0.05, low=700.0, high=300.0, q=1.1, grain=0.45, attack=0.02,
          release=0.02, wrap=True)
    return b, dict(room=0.90, damp=0.32, wet=0.36, pre=0.026)


TRACKS = {
    "music_menu": track_menu,
    "music_world": track_world,
    "music_dungeon": track_dungeon,
    "music_combat": track_combat,
    "music_boss": track_boss,
}

## Which tracks are allowed a beat. The other three are the ones a player spends hours in.
DRIVEN = {"music_combat", "music_boss"}

# --- the bands ---------------------------------------------------------------------

# Music must lose to the sound effects; these are what "underneath" means.
PEAK_CEILING = 0.90
RMS_BAND = (0.03, 0.24)
# The loop step must not be an outlier among the steps the waveform already takes.
# 1.0 = exactly as big as the largest 1% of ordinary steps.
SEAM_RATIO_LIMIT = 1.0
# Dark, and heavy. Neither is a correction of the old score — see the header, it was
# muffled rather than bright — they are guards on an instrument that now has metal, a
# choir and air in it.
CENTROID_CEILING = 1100.0
LOW_FLOOR = 0.30
# A beat, or the absence of one, per track, and the measurement D173 turns on. The old
# score's five tracks measured 0.23 to 0.78: all of them had one, including the menu.
PULSE_CEILING = 0.32
PULSE_FLOOR = 0.34
# No holes: the quietest two seconds must be at least this share of the track's average.
QUIET_FLOOR = 0.30
# The whole score has to fit in a phone download beside 310 paintings.
BUDGET_KB = 1500.0


def measure(b):
    n = len(b)
    steps = sorted(abs(b[i + 1] - b[i]) for i in range(0, n - 1, 7))
    ordinary = steps[int(len(steps) * 0.99)] or 1e-9
    seam = abs(b[0] - b[-1])
    return {
        # Recorded so `gen_sfx.py` can check the two sets against each other from the file
        # rather than from a promise. Three rates in one game is what D150 was.
        "rate": RATE,
        "seconds": round(n / RATE, 2),
        "peak": round(V.peak(b), 4),
        "rms": round(V.rms(b), 4),
        "seam": round(seam, 5),
        "seam_ratio": round(seam / ordinary, 3),
        "centroid_hz": round(V.centroid(b, window=12.0)),
        "low": round(V.band_ratio(b, 200.0, window=12.0), 3),
        "pulse": round(V.pulse(b), 3),
        # The quietest two seconds, against the track's own average. A failure mode the old
        # score could not have and this one can: phrases here are up to 4.6 seconds apart,
        # and a gap with nothing under it does not read as space, it reads as the music
        # having stopped. What keeps it filled is the drone and the air bed, so this is the
        # measurement that says those are actually doing their job.
        "quiet": round(min(V.envelope(b, hop=2.0)) / max(1e-9, V.rms(b)), 3),
    }


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found. Run under:  nix shell nixpkgs#ffmpeg-headless")
        return 127
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed(20260805)          # reproducible: same script, same bytes
    report = {}
    fails = []
    tmp = pathlib.Path(tempfile.mkdtemp())
    print("%-14s %6s %6s %6s %8s %8s %5s %6s %6s %8s" % (
        "track", "secs", "peak", "rms", "seam", "centroid", "low", "pulse", "quiet", "KB"))
    for name, fn in TRACKS.items():
        b, room = fn()
        # rumble first: stacked drones put a lot of energy under hearing, and the room
        # would only multiply it. Wrapping, so the filter's own start is not a seam.
        V.highpass(b, 28.0, wrap=True)
        V.reverb_loop(b, tail=8.0, **room)
        # A room sums a lot of voices and the sum is spiky. Rounding the peaks keeps the
        # body of the track audible; normalising to the spike instead is how a big sound
        # ends up quiet.
        V.normalize(b, 0.9)
        V.soft_clip(b, 1.0)
        V.normalize(b, 0.52)
        m = measure(b)
        wav = tmp / (name + ".wav")
        V.write_wav(wav, b)
        ogg = OUT / (name + ".ogg")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
             "-c:a", "libvorbis", "-b:a", "56k", "-ac", "1", str(ogg)],
            check=True)
        m["kb"] = round(ogg.stat().st_size / 1024, 1)
        m["driven"] = name in DRIVEN
        report[name] = m
        flags = []
        if m["seam_ratio"] > SEAM_RATIO_LIMIT:
            flags.append("SEAM CLICK")
        if m["peak"] > PEAK_CEILING:
            flags.append("TOO LOUD")
        if not (RMS_BAND[0] <= m["rms"] <= RMS_BAND[1]):
            flags.append("RMS OUT OF BAND")
        if m["centroid_hz"] > CENTROID_CEILING:
            flags.append("TOO BRIGHT")
        if m["low"] < LOW_FLOOR:
            flags.append("NO WEIGHT")
        if m["driven"] and m["pulse"] < PULSE_FLOOR:
            flags.append("NO PULSE IN A FIGHT")
        if not m["driven"] and m["pulse"] > PULSE_CEILING:
            flags.append("TAPPABLE")
        if m["quiet"] < QUIET_FLOOR:
            flags.append("A HOLE IN IT")
        if flags:
            fails.append("%s: %s" % (name, ", ".join(flags)))
        print("%-14s %6.1f %6.3f %6.3f %8.5f %7dHz %5.2f %6.3f %6.2f %7.1f %s" % (
            name, m["seconds"], m["peak"], m["rms"], m["seam"], m["centroid_hz"],
            m["low"], m["pulse"], m["quiet"], m["kb"], " ".join(flags)))

    # two tracks that measure the same are one loop shipped under several names
    keys = list(report)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, c = report[keys[i]], report[keys[j]]
            if (abs(a["rms"] - c["rms"]) < 0.002
                    and abs(a["seconds"] - c["seconds"]) < 0.01
                    and abs(a["centroid_hz"] - c["centroid_hz"]) < 40):
                fails.append("%s and %s measure identically" % (keys[i], keys[j]))

    (OUT / "measurements.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n")
    total = sum(m["kb"] for m in report.values())
    print("\ntotal %.1f KB (budget %.0f)" % (total, BUDGET_KB))
    if total > BUDGET_KB:
        fails.append("the score is %.1f KB, over the %.0f KB budget" % (total, BUDGET_KB))
    if fails:
        print("\nFAILED:")
        for f in fails:
            print("  " + f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
