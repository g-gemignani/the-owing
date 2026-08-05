#!/usr/bin/env python3
"""Generate the game's 24 sound effects as OGG files, in ONE voice with the score.

The instrument is `tools/audio_voices.py`, which `gen_music.py` also builds the score from.
That import is the design: D150's defect was three downloaded packs at three sample rates
answering a button, a sword and a won run in three different voices, and the fix has to be
structural or it comes back. There is one instrument, one rate and one room in this project.

## What changed in D173

The 23 effects were a chiptune — square, triangle, a two-operator bell and one-pole noise,
at 22.05 kHz, with no room on any of them. Measured against the new metrics the old set says
it plainly: `ui_click` had a 35 ms tail, `attack` 65 ms, `block` 130 ms. Nothing in the game
happened anywhere. A dry sound is the single loudest thing telling a player they are looking
at a toy, and it is why "the sound is not convincing" survived a set that passed every gate
it had.

So: physical models instead of oscillators, and every effect is put in a room.

  * a blade is air moving and then something being struck (`air` + `drum` + `metal` + `sub`)
  * coins are eleven small inharmonic grains, not three bells
  * a locked door is a thud with no ring in it, because that is what "no" sounds like
  * a footstep exists at all, which is the sound a dungeon crawl makes most often

The room is deliberately SMALL here. `scripts/audio.gd` puts a second, bigger reverb on the
SFX bus and changes it with where the player is, so a blow in a dungeon rings longer than
the same blow in a menu. Baking the whole space into the file would fight that and cost
bytes; baking none of it would leave every effect naked if the bus ever failed to build.

Nothing is copied from another game. A struck plate, a frame drum, a coin scatter and a
choir are the vocabulary; the recipes are this project's.

## The rules, which are the whole design

  1. **One instrument family**, imported, not restated.
  2. **In the score's key.** Everything pitched is picked from `SCALE` by NAME, so an
     accidental cannot be typed as a frequency. The set now includes the flat second and
     the tritone, because those are the two colours the new score is built on.
  3. **One loudness ladder, stated rather than mixed by ear.** The interface sits under the
     world, the world under the stingers, all of it over the music. Every file is normalised
     to its family's peak, so `audio.gd` never adjusts a level per event.
  4. **Length and space by family.** A click is a click; a blow lands and is gone; only a
     stinger is a phrase. Each family also has a MINIMUM tail, which is the D173 rule: a
     sound with no tail did not happen anywhere.

## What is measured, and what fails the run

  peak/rms     — the ladder in rule 3, per family, plus the spread across the whole set.
  centroid     — the register each family is written in. The number that caught D150.
  tail         — the room, as milliseconds from the peak down 30 dB. FLOOR, per family.
  onset        — milliseconds until the sound is audible at all. CEILING: all the space in
                 the world is worth nothing if the feedback for a button is late.
  seconds      — rule 4.
  distinct     — two effects that measure the same are one effect under two names.
  one set      — the effects' register is checked against the SCORE's measurements on disk,
                 and the rates are checked against each other. That is D150's actual bug,
                 finally asked as a question instead of asserted in a file header.

Usage (ffmpeg is only needed here, never at runtime):
    nix shell nixpkgs#ffmpeg-headless --command python3 tools/gen_sfx.py
Then:
    godot --headless --import
"""

import json
import math
import pathlib
import random
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audio_voices as V                                     # noqa: E402
from audio_voices import RATE, buf, hz, up                   # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "audio"
SCORE_MEASUREMENTS = OUT / "music" / "measurements.json"

# --- the ladder --------------------------------------------------------------------
#
# family -> peak, RMS band, seconds ceiling, centroid band in Hz, tail floor in ms,
#           onset ceiling in ms
#
# The peaks are the design: pressing a button is not as loud as being hit, and being hit is
# not as loud as a run ending. The music normalises to 0.52 and loses to all of it.
#
# The centroid bands are the REGISTER each family is written in, and they are a choice
# rather than a description of the output. They all moved down in D173: the old interface
# band was 1100-3600 Hz, which is a modern app's blip. A menu in this game is wood, leather
# and stone, and it belongs under the score's own plucked string rather than above it.
#
# The tail floors are new and are the point of D173. The ceilings on length are what stops
# a floor on the tail from turning every click into a cathedral.
FAMILY = {
    "ui":      {"peak": 0.44, "rms": (0.02, 0.26), "secs": 0.42, "hz": (380, 1900),
                "tail": 90.0, "onset": 14.0, "tight": True},
    "world":   {"peak": 0.72, "rms": (0.03, 0.36), "secs": 1.30, "hz": (180, 2300),
                "tail": 170.0, "onset": 26.0},
    "stinger": {"peak": 0.85, "rms": (0.04, 0.34), "secs": 3.10, "hz": (180, 1500),
                "tail": 480.0, "onset": 130.0},
}
## How far apart the brightest and the dullest sound in one family may sit, as a ratio of
## centroids — asked only of the family marked `tight`, which is the interface. The menu is
## where uniformity is most audible: its sounds play back-to-back within a second of each
## other and mean nearly the same thing, so two octaves apart there is two instruments. The
## world is deliberately the opposite — a heavy blow at 200 Hz and a handful of coins at
## 1.8 kHz are one instrument set used for different things, and squeezing that range would
## cost the game its ability to say which is which.
TIMBRE_RATIO_MAX = 2.6
## How far apart the loudest and quietest file in the whole set may sit, in dB of RMS. The
## uniformity check: the old Kenney set spanned far more than this, which is why one effect
## could be inaudible and the next startling at the same slider setting.
SPREAD_DB_MAX = 22.0
## And the check across the two sets. The score's median centroid and the effects' median
## centroid have to sit within this factor of each other, or the game is playing sound
## effects from one instrument over music from another — which is exactly what D150 was.
SET_REGISTER_MAX = 4.0
## The effects have to fit in a phone download beside 310 paintings and a 1.3 MB score.
BUDGET_KB = 260.0

## The pitched material, by name. A natural minor is the spine (the score's menu and
## dungeon are in A), and `bb`/`eb` are here because the dungeon's flat second and the
## boss's grinding semitone are the score's two signature colours — an effect that wants
## to sound wrong should sound wrong in the same way the music does.
SCALE = ["a2", "bb2", "c3", "d3", "eb3", "e3", "f3", "g3",
         "a3", "bb3", "c4", "d4", "eb4", "e4", "f4", "g4",
         "a4", "bb4", "c5", "d5", "e5", "f5", "a5", "c6"]


def note(name: str) -> float:
    if name not in SCALE:
        raise ValueError("%s is not in the score's key" % name)
    return hz(name)


## The room each family is heard in, before the bus adds the space. Small, short and
## damped — see the header for why the big reverb is not baked in.
ROOM = {
    "ui":      dict(room=0.72, damp=0.52, wet=0.20, pre=0.006, size=0.55),
    "world":   dict(room=0.80, damp=0.44, wet=0.26, pre=0.009, size=0.80),
    "stinger": dict(room=0.88, damp=0.34, wet=0.34, pre=0.018, size=1.00),
}


# --- the interface: wood, leather and stone -----------------------------------------
#
# One function per event name in `Audio.SOUNDS`. Each returns (buffer, family).


def ui_click():
    """A finger on something wooden. `drum` at this size and this decay is not a drum, it
    is a knock — a membrane with a 60 ms tail is a plank."""
    b = buf(0.34)
    V.drum(b, 0, 0.07, 190.0, 0.40, snap=0.55, bend=0.30, t60=0.045, shell=0.45)
    V.air(b, 0, 0.03, 0.10, low=1500.0, high=800.0, q=1.2, attack=0.1, release=0.5)
    return b, "ui"


def ui_select():
    """Moving between things: the same knock, smaller and higher, so a menu is one
    instrument being played rather than a set of unrelated noises."""
    b = buf(0.30)
    V.drum(b, 0, 0.05, 260.0, 0.30, snap=0.45, bend=0.25, t60=0.035, shell=0.40)
    return b, "ui"


def ui_back():
    """Down where the others go up, and duller: leaving is not a decision.

    "Duller" is a decay, not a register. The first version dropped the knock to 130 Hz and
    measured 306 Hz against a family that lives near 700, which is a different instrument
    rather than the same one lower — so the pitch came back up and the shell came down.
    """
    b = buf(0.32)
    V.drum(b, 0, 0.07, 172.0, 0.34, snap=0.40, bend=0.28, t60=0.050, shell=0.22)
    V.air(b, 0, 0.03, 0.10, low=1150.0, high=640.0, q=1.2, attack=0.1, release=0.5)
    return b, "ui"


def ui_open():
    """A panel arriving. Two short breaths of leather rather than a note, because a bag
    opening is the most inventory-shaped sound there is."""
    b = buf(0.38)
    V.air(b, 0, 0.06, 0.24, low=520.0, high=1050.0, q=1.0, grain=0.5,
          attack=0.08, release=0.6)
    V.air(b, int(0.055 * RATE), 0.08, 0.16, low=980.0, high=430.0, q=1.1, grain=0.5,
          attack=0.06, release=0.6)
    # The knock carries more of it than it looks like it should: leather sweeping to 2 kHz
    # measured 2039 Hz, three octaves off `ui_denied`, and a menu whose sounds are three
    # octaves apart is two instruments however good each one is.
    V.drum(b, 0, 0.05, 190.0, 0.30, snap=0.30, bend=0.2, t60=0.04, shell=0.25)
    return b, "ui"


def ui_confirm():
    """Committing: the one interface sound allowed to ring, because it is the one
    interface action with a consequence. A struck bar, on the tonic."""
    b = buf(0.40)
    V.drum(b, 0, 0.05, 200.0, 0.20, snap=0.40, bend=0.25, t60=0.04, shell=0.3)
    V.metal(b, 0, 0.26, note("a4"), 0.34, kind="bar", t60=0.22, strike=0.35)
    return b, "ui"


def ui_denied():
    """No. A thud with nothing ringing after it — the two notes a semitone apart that used
    to do this job were an idea about dissonance, and a locked door is not dissonant. It is
    dead. Everything with a tail is deliberately absent, and the room is the only reason
    this has any decay at all."""
    b = buf(0.30)
    V.drum(b, 0, 0.09, 150.0, 0.42, snap=0.28, bend=0.15, t60=0.045, shell=0.12)
    # A door is wood and iron, not a subwoofer: at 96 Hz and nothing else this measured
    # 177 Hz against a family living near 700, so it had a body but no contact. The grit is
    # what puts the two surfaces back in the same room as the rest of the menu, and the
    # decay — which is the part that means "no" — is untouched.
    V.scrape(b, 0, 0.06, 0.14, freq=180.0, rough=0.5, bright=900.0)
    return b, "ui"


# --- the world ---------------------------------------------------------------------


def step():
    """A boot on stone, and the sound the game makes most often: one per tile of the crawl.
    Grit under the heel, then the floor. Quiet on purpose — `audio.gd` jitters its pitch
    harder than anything else, because a footstep that repeats identically is a machine."""
    b = buf(0.42)
    V.drum(b, 0, 0.10, 98.0, 0.44, snap=0.50, bend=0.35, t60=0.075, shell=0.30)
    V.air(b, 0, 0.05, 0.18, low=1600.0, high=520.0, q=1.0, grain=0.6,
          attack=0.06, release=0.5)
    return b, "world"


def card_play():
    """A card leaving the hand: parchment sliding on parchment, with the table under it."""
    b = buf(0.60)
    V.air(b, 0, 0.11, 0.34, low=900.0, high=2500.0, q=1.1, grain=0.55, attack=0.1,
          release=0.55)
    V.drum(b, int(0.07 * RATE), 0.08, 170.0, 0.20, snap=0.35, bend=0.25, t60=0.06,
           shell=0.2)
    return b, "world"


def attack():
    """A blade: air moving, then something being struck. The whoosh comes first and the
    impact lands 60 ms in, which is what makes it read as a swing rather than a hit — the
    old version was one noise burst with a square wave under it."""
    b = buf(0.80)
    V.air(b, 0, 0.10, 0.30, low=2600.0, high=700.0, q=1.3, attack=0.15, release=0.45)
    t = int(0.06 * RATE)
    V.drum(b, t, 0.20, 150.0, 0.62, snap=0.75, bend=0.55, t60=0.13, shell=0.35)
    V.metal(b, t, 0.26, note("d4"), 0.22, kind="plate", t60=0.20, strike=0.7)
    V.sub(b, t, 0.24, 62.0, 0.30, fall=0.22, t60=0.16)
    return b, "world"


def attack_heavy():
    """The same blow, bigger. Heavier is not louder — the ladder gives both the same family
    peak — it is slower, darker and longer: the swing takes half again as long, the impact
    is a fifth lower, and the plate under it rings twice as far."""
    b = buf(1.20)
    V.air(b, 0, 0.17, 0.30, low=1700.0, high=380.0, q=1.4, attack=0.2, release=0.4)
    t = int(0.12 * RATE)
    V.drum(b, t, 0.40, 92.0, 0.64, snap=0.65, bend=0.60, t60=0.30, shell=0.40)
    V.metal(b, t, 0.50, note("a3"), 0.24, kind="plate", t60=0.42, strike=0.85)
    V.sub(b, t, 0.44, 44.0, 0.40, fall=0.30, t60=0.34)
    return b, "world"


def block():
    """Something hard stopping something hard. A struck plate is the whole sound: modes at
    ratios nothing divides, the top ones dying first, which is why it is armour and not a
    bell."""
    b = buf(0.85)
    V.metal(b, 0, 0.45, note("d4"), 0.60, kind="plate", t60=0.38, strike=0.95)
    V.drum(b, 0, 0.10, 210.0, 0.26, snap=0.60, bend=0.3, t60=0.07, shell=0.3)
    return b, "world"


def hurt():
    """Taking it: weight arriving, and the breath it knocks out. The breath is a resonance
    around 520 Hz on filtered air, not a voice — at this level it reads as a wince, and
    anything more articulate would read as a cartoon."""
    b = buf(0.80)
    V.sub(b, 0, 0.30, 74.0, 0.34, fall=0.35, t60=0.22)
    V.drum(b, 0, 0.16, 132.0, 0.42, snap=0.60, bend=0.45, t60=0.12, shell=0.30)
    V.air(b, int(0.04 * RATE), 0.26, 0.22, low=620.0, high=300.0, q=3.4, grain=0.3,
          attack=0.12, release=0.55)
    return b, "world"


def poison():
    """Something wet. Four bubbles — a rising resonance is what a bubble is, physically,
    because the cavity shrinks as it collapses — over a slow hiss."""
    b = buf(0.95)
    V.air(b, 0, 0.55, 0.14, low=520.0, high=900.0, q=1.0, grain=0.55,
          attack=0.15, release=0.5)
    for k, (t, f) in enumerate([(0.02, 210.0), (0.13, 300.0), (0.27, 250.0),
                                (0.40, 340.0)]):
        V.sub(b, int(t * RATE), 0.09, f, 0.26 - 0.03 * k, fall=-0.55, t60=0.05)
        V.air(b, int(t * RATE), 0.05, 0.10, low=f * 3.0, high=f * 6.0, q=2.2,
              attack=0.1, release=0.5)
    return b, "world"


def buff():
    """Something being added to you: a choir swelling under a struck bell, rising. The one
    hopeful sound in the game, and it is still in a minor key."""
    b = buf(1.15)
    # The bell is struck at zero and the choir swells in under it. Written the other way
    # round — choir first, bell 50 ms later — the whole sound was 30 ms late reaching a
    # tenth of its peak, because a swell has no attack. Nothing that answers a card being
    # played may begin with a swell.
    V.metal(b, 0, 0.70, note("a4"), 0.34, kind="bell", t60=0.55, strike=0.4)
    V.choir(b, 0, 0.55, note("a3"), 0.34, vowel="oo", breath=0.2, attack=0.18,
            release=0.45)
    V.air(b, 0, 0.35, 0.10, low=600.0, high=2200.0, q=1.2, attack=0.2, release=0.4)
    return b, "world"


def gold():
    """Coins. Eleven small inharmonic grains scattered over 190 ms with a bag under them:
    a handful of coins is not one coin three times, and the thing that makes it read as
    *many* is that no two grains share a pitch, a level or an onset."""
    b = buf(1.00)
    grains = [(0.000, "e5", 0.30), (0.018, "c5", 0.24), (0.041, "a4", 0.27),
              (0.058, "e5", 0.20), (0.079, "d5", 0.26), (0.096, "a5", 0.22),
              (0.114, "c5", 0.19), (0.131, "e5", 0.24), (0.152, "a4", 0.18),
              (0.170, "d5", 0.21), (0.190, "c6", 0.16)]
    for t, n, g in grains:
        V.metal(b, int(t * RATE), 0.34, note(n), g, kind="coin",
                t60=0.10 + 0.04 * (t * 5.0 % 1.0), strike=0.5, jitter=0.03)
    V.drum(b, 0, 0.12, 104.0, 0.22, snap=0.40, bend=0.3, t60=0.09, shell=0.2)
    return b, "world"


def event():
    """A rune stone waking up. A bare fifth on the choir, a drag of stone, and weight
    underneath — the shape of something old noticing you."""
    b = buf(1.30)
    V.choir(b, 0, 0.85, note("a2"), 0.30, vowel="oh", breath=0.35, attack=0.2,
            release=0.5)
    V.choir(b, int(0.06 * RATE), 0.80, up(note("a2"), "fifth"), 0.20, vowel="oh",
            breath=0.3, attack=0.25, release=0.5)
    V.scrape(b, 0, 0.40, 0.20, freq=64.0, rough=0.7, bright=700.0)
    V.sub(b, 0, 0.55, 52.0, 0.24, fall=0.1, t60=0.45)
    V.metal(b, int(0.30 * RATE), 0.60, note("e4"), 0.12, kind="bar", t60=0.5, strike=0.2)
    return b, "world"


def enter():
    """Going down: stone dragging, and then a floor. The mirror of `leave`, because the two
    are one door used twice — this one falls."""
    b = buf(1.25)
    V.scrape(b, 0, 0.50, 0.34, freq=52.0, rough=0.75, bright=620.0)
    V.sub(b, 0, 0.60, 58.0, 0.36, fall=0.35, t60=0.5)
    V.drum(b, int(0.42 * RATE), 0.35, 84.0, 0.44, snap=0.35, bend=0.4, t60=0.24,
           shell=0.25)
    return b, "world"


def leave():
    """And this one rises."""
    b = buf(1.20)
    V.scrape(b, 0, 0.45, 0.32, freq=78.0, rough=0.65, bright=900.0)
    V.sub(b, 0, 0.50, 48.0, 0.32, fall=-0.30, t60=0.45)
    V.drum(b, int(0.38 * RATE), 0.30, 120.0, 0.36, snap=0.40, bend=0.35, t60=0.18,
           shell=0.30)
    return b, "world"


def treasure():
    """A chest: the lid (wood turning on wood), the latch (a struck bar), and three coins
    of what is inside it."""
    b = buf(1.25)
    V.scrape(b, 0, 0.30, 0.26, freq=140.0, rough=0.8, bright=1100.0)
    V.metal(b, int(0.26 * RATE), 0.40, note("c4"), 0.44, kind="bar", t60=0.30,
            strike=0.75)
    for k, (t, n) in enumerate([(0.34, "a4"), (0.37, "e5"), (0.41, "c5")]):
        V.metal(b, int(t * RATE), 0.30, note(n), 0.20 - 0.03 * k, kind="coin", t60=0.16,
                strike=0.45)
    return b, "world"


def fuse():
    """Two cards becoming one, which is the meta layer's whole verb. Two bars struck a
    semitone apart — the score's own dissonance — and then a bell on the note they were
    arguing about, over the hiss of a forge."""
    b = buf(1.25)
    V.metal(b, 0, 0.40, note("d4"), 0.36, kind="bar", t60=0.32, strike=0.6)
    V.metal(b, 0, 0.40, up(note("d4"), "min2"), 0.30, kind="bar", t60=0.32, strike=0.5)
    V.air(b, 0, 0.45, 0.18, low=2200.0, high=600.0, q=1.1, grain=0.5, attack=0.1,
          release=0.5)
    V.metal(b, int(0.34 * RATE), 0.65, note("d4"), 0.40, kind="bell", t60=0.55,
            strike=0.35)
    return b, "world"


# --- the stingers ------------------------------------------------------------------
#
# These stay on the SFX bus although they are music, because they are feedback for a thing
# that just happened: a player who turns the music off still wants to hear that they won.


def reward():
    """Cards banked. A choir and a bell, held — the same two voices as `buff`, twice as
    long and an octave apart, because a reward is a buff you keep."""
    b = buf(2.00)
    V.choir(b, 0, 1.10, note("a3"), 0.36, vowel="oo", breath=0.2, attack=0.2,
            release=0.5)
    V.choir(b, int(0.10 * RATE), 1.00, up(note("a3"), "min3"), 0.22, vowel="oo",
            breath=0.2, attack=0.25, release=0.5)
    V.metal(b, int(0.08 * RATE), 1.30, note("a4"), 0.40, kind="bell", t60=1.10,
            strike=0.35)
    V.drum(b, 0, 0.40, 76.0, 0.20, snap=0.25, bend=0.3, t60=0.25, shell=0.2)
    return b, "stinger"


def victory():
    """A run brought home, and it is not a fanfare. Three plucked notes rising to the
    tonic, a choir arriving under them, a bell on top and one deep drum — slow, because
    this game's idea of triumph is getting out, not winning a tournament. Minor throughout:
    it does not need a major key to sound like living."""
    b = buf(2.90)
    for k, n in enumerate(["a3", "c4", "e4"]):
        V.pluck(b, int(k * 0.22 * RATE), 2.4, note(n), 0.34, t60=2.2, damp=0.38)
    V.choir(b, int(0.50 * RATE), 1.70, note("a3"), 0.34, vowel="oh", breath=0.22,
            attack=0.25, release=0.45)
    V.pluck(b, int(0.66 * RATE), 2.2, note("a4"), 0.30, t60=2.4, damp=0.36)
    V.metal(b, int(0.70 * RATE), 1.90, note("a4"), 0.34, kind="bell", t60=1.60,
            strike=0.30)
    V.drum(b, 0, 0.55, 62.0, 0.26, snap=0.20, bend=0.35, t60=0.40, shell=0.2)
    return b, "stinger"


def defeat():
    """Everything found this run is forfeit. The same voices as `victory` going the other
    way: a choir stepping down a minor third and then a tritone, weight sliding after it,
    one dead drum, and the room left to swallow the lot. No new idea — the win losing its
    nerve."""
    b = buf(3.05)
    for k, n in enumerate(["a3", "f3", "eb3"]):
        V.choir(b, int(k * 0.55 * RATE), 1.50, note(n), 0.34 - 0.04 * k, vowel="oh",
                breath=0.3, attack=0.2, release=0.5)
    V.sub(b, int(0.10 * RATE), 1.60, 74.0, 0.40, fall=0.45, t60=1.30)
    V.drum(b, int(1.55 * RATE), 0.70, 54.0, 0.34, snap=0.18, bend=0.3, t60=0.45,
           shell=0.15)
    V.scrape(b, int(1.60 * RATE), 0.80, 0.12, freq=46.0, rough=0.6, bright=520.0)
    return b, "stinger"


def boss_cleared():
    """The one named thing on the floor is down, and this is the largest sound in the game.
    Victory's shape with a drum under every part of it, the bell an octave up, and the
    tritone that has been grinding under the boss track finally resolving to the tonic."""
    b = buf(3.05)
    V.drum(b, 0, 0.80, 58.0, 0.44, snap=0.30, bend=0.45, t60=0.55, shell=0.25)
    V.sub(b, 0, 0.90, 42.0, 0.34, fall=0.2, t60=0.70)
    V.metal(b, int(0.04 * RATE), 1.20, note("d4"), 0.26, kind="plate", t60=0.95,
            strike=0.9)
    for k, n in enumerate(["a3", "e4", "a4"]):
        V.pluck(b, int((0.30 + k * 0.20) * RATE), 2.3, note(n), 0.32, t60=2.3, damp=0.36)
    V.choir(b, int(0.55 * RATE), 1.90, note("a3"), 0.36, vowel="oh", breath=0.22,
            attack=0.22, release=0.45)
    V.choir(b, int(0.60 * RATE), 1.80, up(note("a3"), "fifth"), 0.24, vowel="oh",
            breath=0.2, attack=0.25, release=0.45)
    V.metal(b, int(0.90 * RATE), 2.00, note("a5"), 0.30, kind="bell", t60=1.70,
            strike=0.30)
    V.drum(b, int(1.30 * RATE), 0.70, 74.0, 0.30, snap=0.30, bend=0.4, t60=0.45,
           shell=0.25)
    return b, "stinger"


# Keyed exactly like `Audio.SOUNDS`: the event name IS the file stem, and a name here that
# the game never asks for is dead weight the game cannot tell you about.
EFFECTS = {
    "ui_click": ui_click, "ui_select": ui_select, "ui_back": ui_back,
    "ui_confirm": ui_confirm, "ui_denied": ui_denied, "ui_open": ui_open,
    "step": step, "attack": attack, "attack_heavy": attack_heavy, "block": block,
    "hurt": hurt, "poison": poison, "card_play": card_play, "buff": buff,
    "gold": gold, "event": event, "enter": enter, "leave": leave,
    "treasure": treasure, "fuse": fuse,
    "reward": reward, "victory": victory, "defeat": defeat,
    "boss_cleared": boss_cleared,
}


# --- measurement -------------------------------------------------------------------


def trim(b, floor=0.0012):
    """Cut silence off the tail. The recipes leave room for their own decay AND for the
    room's, and what is left over is bytes and latency rather than sound."""
    end = len(b)
    while end > 1 and abs(b[end - 1]) < floor:
        end -= 1
    end = min(len(b), end + int(0.006 * RATE))   # a run-out, so the encoder is not asked
    return b[:end]                               # to stop mid-decay


def measure(b):
    return {
        # Recorded so the game can check it, not just this script: `tests/test_art.gd` reads
        # both measurement files and fails if the two sets disagree about the rate. D150 was
        # four rates in one game and nothing in the project was watching.
        "rate": RATE,
        "seconds": round(len(b) / RATE, 3),
        "peak": round(V.peak(b), 4),
        "rms": round(V.rms(b), 4),
        "centroid_hz": round(V.centroid(b)),
        "tail_ms": round(V.tail_ms(b), 1),
        "onset_ms": round(V.onset_ms(b), 2),
        "attack_ms": round(V.attack_ms(b), 2),
    }


def main() -> int:
    if shutil.which("ffmpeg") is None:
        print("ffmpeg not found. Run under:  nix shell nixpkgs#ffmpeg-headless")
        return 127
    OUT.mkdir(parents=True, exist_ok=True)
    random.seed(20260805)                 # reproducible: same script, same bytes
    report = {}
    fails = []
    tmp = pathlib.Path(tempfile.mkdtemp())
    print("%-13s %-8s %6s %6s %6s %8s %8s %7s %6s" % (
        "file", "family", "secs", "peak", "rms", "centroid", "tail", "onset", "KB"))
    for name, fn in EFFECTS.items():
        b, fam = fn()
        spec = FAMILY[fam]
        V.reverb(b, **ROOM[fam])
        b = trim(b)
        V.normalize(b, spec["peak"])
        m = measure(b)
        m["family"] = fam
        wav = tmp / (name + ".wav")
        V.write_wav(wav, b)
        ogg = OUT / (name + ".ogg")
        # -q:a 2 rather than the score's fixed bitrate: these are transients, and vorbis
        # spends its bits where the file needs them when it is asked by quality.
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav),
             "-c:a", "libvorbis", "-q:a", "2", "-ac", "1", str(ogg)],
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
        if m["tail_ms"] < spec["tail"]:
            flags.append("NO ROOM")
        if m["onset_ms"] > spec["onset"]:
            flags.append("LATE")
        if flags:
            fails.append("%s: %s" % (name, ", ".join(flags)))
        print("%-13s %-8s %6.3f %6.3f %6.3f %7dHz %7.0fms %6.1fms %6.1f %s" % (
            name, fam, m["seconds"], m["peak"], m["rms"], m["centroid_hz"], m["tail_ms"],
            m["onset_ms"], m["kb"], " ".join(flags)))

    # the uniformity checks: one set, not several
    loud = max(report.values(), key=lambda m: m["rms"])
    quiet = min(report.values(), key=lambda m: m["rms"])
    spread = 20.0 * math.log10(loud["rms"] / max(1e-9, quiet["rms"]))
    if spread > SPREAD_DB_MAX:
        fails.append("the set spans %.1f dB of RMS (ceiling %.1f) — that is not one set"
                     % (spread, SPREAD_DB_MAX))
    for fam, spec in FAMILY.items():
        band = [m["centroid_hz"] for m in report.values() if m["family"] == fam]
        tails = [m["tail_ms"] for m in report.values() if m["family"] == fam]
        if len(band) < 2:
            continue
        ratio = max(band) / max(1.0, min(band))
        tight = bool(spec.get("tight", False))
        print("  %-8s %2d files, %4d-%4dHz, timbre spread x%.2f%s, tail %.0f-%.0fms" % (
            fam, len(band), min(band), max(band), ratio,
            " (ceiling x%.2f)" % TIMBRE_RATIO_MAX if tight else "",
            min(tails), max(tails)))
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

    # --- and the check ACROSS the two sets, which is D150's actual bug ---------------
    #
    # Asked of the score's measurements on disk rather than of this file's intentions: if
    # the effects and the music end up in different registers or at different rates, this
    # is the line that says so, and no file header can be wrong about it.
    if SCORE_MEASUREMENTS.exists():
        score = json.loads(SCORE_MEASUREMENTS.read_text())
        rates = {int(m.get("rate", RATE)) for m in score.values()}
        if rates != {RATE}:
            fails.append("the score runs at %s and the effects at %d — that is two sets"
                         % (sorted(rates), RATE))
        sc = sorted(m["centroid_hz"] for m in score.values())[len(score) // 2]
        ours = sorted(m["centroid_hz"] for m in report.values())[len(report) // 2]
        factor = max(sc, ours) / max(1.0, min(sc, ours))
        print("  one set: score median %d Hz, effects median %d Hz, x%.2f apart "
              "(ceiling x%.2f)" % (sc, ours, factor, SET_REGISTER_MAX))
        if factor > SET_REGISTER_MAX:
            fails.append("the effects sit x%.2f from the score in register (ceiling x%.2f)"
                         % (factor, SET_REGISTER_MAX))
    else:
        fails.append("no score measurements at %s — run gen_music.py first, or the two "
                     "sets are not being checked against each other at all"
                     % SCORE_MEASUREMENTS)

    (OUT / "measurements.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n")
    total = sum(m["kb"] for m in report.values())
    print("\n%d files, %.1f KB total (budget %.0f), RMS spread %.1f dB (ceiling %.1f)" % (
        len(report), total, BUDGET_KB, spread, SPREAD_DB_MAX))
    if total > BUDGET_KB:
        fails.append("the set is %.1f KB, over the %.0f KB budget" % (total, BUDGET_KB))
    if fails:
        print("\nFAILED:")
        for f in fails:
            print("  " + f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
