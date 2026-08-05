#!/usr/bin/env python3
"""The instrument. One voice set, one tuning, one room — imported by both generators.

`gen_music.py` writes the score with it and `gen_sfx.py` writes the effects with it, so
"one instrument family" is structural instead of a promise in two file headers. That rule
came out of D150, where the effects were three downloaded packs at three sample rates and
the game answered a button, a sword and a won run in three different voices. The rule
survived; the instrument did not.

## Why this replaced the square waves (D173)

The old set was a chiptune: square, triangle, a two-operator bell, and one-pole noise, at
22.05 kHz, bone dry. Every file was in key and on the ladder and the set was uniform — and
it sounded like a 1988 arcade cabinet, which is not what this game looks like. The target
is the sound of *Diablo*: a dark, physical, reverberant dungeon. Four things carry that,
and none of them is a waveform:

  1. **A room.** Diablo's identity is reverb — every blow, coin and footstep happens in a
     stone space. Dry sound is the single biggest reason a game reads as a toy. Every voice
     here is written to be put in `reverb()`, and the SFX bus adds more at runtime.
  2. **Physical excitation.** A string is plucked, a plate is struck, a membrane is hit, a
     throat is breathed through. Those are `pluck`, `metal`, `drum`, `choir` — models, not
     oscillators, so the timbre changes across a note the way a real one does.
  3. **Inharmonic metal.** A struck plate's partials are not multiples of anything. That is
     what makes a coin sound like a coin and a bell not sound like a sine.
  4. **Weight and darkness.** Content low and rolled off on top, rather than the old set's
     1-3 kHz brightness. The centroid bands in both generators enforce it.

None of this is copied from anything. The interval language (drones, minor seconds,
tritones, open fifths) and the instrument choices (plucked string, low bowed strings,
breathy choir, struck metal, frame drums) are the *vocabulary* of dark fantasy; no melody,
progression or figure here is taken from another game's score.

## 44.1 kHz, both sets

The old rate was 22.05 kHz "because the content is low-harmonic pads beside pixel art".
Struck metal is not low-harmonic: the modes that make a coin bright live at 6-10 kHz, and
an 11 kHz Nyquist plus its anti-alias filter takes exactly those off. So the rate doubled.
It is still ONE rate for both sets, which is the invariant that mattered.

## The API

Every voice is `voice(b, start, dur, ..., gain, wrap=False)`, adds into `b`, and is
normalised so `gain` IS the peak it contributes. That makes the loudness ladder in
`gen_sfx.py` authorable rather than mixed by ear.

`wrap=True` writes modulo the buffer length, so a tail crossing the end of a loop lands at
its beginning — how the score's seams stay exact rather than corrected (`gen_music.py`).
"""

import array
import math
import random

# One rate for the score and the effects both. See the header.
RATE = 44100

# --- tuning ------------------------------------------------------------------------
#
# Names, not numbers, everywhere. A frequency typed by hand is how an accidental gets into
# a set that is supposed to be in one key.

A4 = 440.0
NAMES = {"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}


def hz(note: str) -> float:
    """'a3' / 'c#4' / 'bb2' -> frequency."""
    name = note[0]
    octave = int(note[-1])
    semis = NAMES[name] + (1 if "#" in note else 0) + (-1 if "b" in note[1:] else 0)
    midi = 12 * (octave + 1) + semis
    return A4 * (2.0 ** ((midi - 69) / 12.0))


## Modes rather than chords. The score is built on drones and colour tones, because a
## chord progression states a key and a drone just *is* one — which is the difference
## between music that goes somewhere and music that is a place.
##
## `phryg` (the flat second) and `locrian` (the flat fifth) are the two that read as dread
## in every dark score there has ever been, and both are here so a recipe can ask for them
## by name instead of typing a semitone.
MODES = {
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "phryg": [0, 1, 3, 5, 7, 8, 10],
    "locrian": [0, 1, 3, 5, 6, 8, 10],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
}

## Intervals a recipe asks for by meaning. The comments are the whole reason this exists.
STEP = {
    "unison": 0,
    "min2": 1,      # dread; two of them beating against each other is the boss drone
    "min3": 3,      # the minor colour
    "fourth": 5,
    "tritone": 6,   # the interval that means something is wrong
    "fifth": 7,     # open space; a fifth with no third is a cave, not a chord
    "min6": 8,      # the ache
    "min7": 10,
    "octave": 12,
}


def up(freq: float, interval: str, octaves: int = 0) -> float:
    return freq * (2.0 ** ((STEP[interval] + 12 * octaves) / 12.0))


def mode(root: str, name: str, octaves: int = 2) -> list:
    """The pitches of a mode, low to high, as frequencies."""
    base = hz(root)
    out = []
    for o in range(octaves):
        for s in MODES[name]:
            out.append(base * (2.0 ** ((s + 12 * o) / 12.0)))
    return out


def buf(secs: float) -> array.array:
    return array.array("d", [0.0] * max(1, int(secs * RATE)))


# --- mixing ------------------------------------------------------------------------


def _mix(b, start: int, out: list, gain: float, wrap: bool) -> None:
    """Splice a rendered voice in, normalised so `gain` is the peak it contributes.

    Wrapping lives here and nowhere else: the synthesis loops stay free of a per-sample
    branch, and there is one place to be wrong about a loop seam.
    """
    peak = 0.0
    for v in out:
        a = v if v >= 0.0 else -v
        if a > peak:
            peak = a
    if peak <= 0.0:
        return
    g = gain / peak
    n = len(b)
    if wrap:
        for i in range(len(out)):
            b[(start + i) % n] += g * out[i]
    else:
        for i in range(len(out)):
            j = start + i
            if j >= n:
                break
            if j >= 0:
                b[j] += g * out[i]


def _env(i: int, total: int, attack: int, decay: float) -> float:
    """Ramped attack, exponential decay.

    The ramp is not a nicety. A one-shot that starts at full amplitude puts a step in the
    waveform at sample zero — a click in front of every sound — and for a loop, sample zero
    IS the seam, so an instant attack on a downbeat measures as a seam click.
    """
    return (1.0 if i >= attack else i / attack) * math.exp(-decay * i / total)


def _swell(i: int, total: int, attack: float, release: float) -> float:
    """Slow in, slow out, as fractions of the note. The sustained voices' envelope."""
    a = max(1, int(total * attack))
    r = max(1, int(total * release))
    if i < a:
        x = i / a
        return x * x * (3.0 - 2.0 * x)          # smoothstep in, so there is no corner
    if i > total - r:
        x = (total - i) / r
        return x * x * (3.0 - 2.0 * x)
    return 1.0


# --- filters ------------------------------------------------------------------------
#
# All one-pass and in place. Nothing here is a design; they are the tools the voices and
# the room are built out of.


## How much of the signal a wrapping filter is primed with before it starts writing.
## A filter has state, and a loop has no first sample: an un-primed one-pole writes
## sample zero as if silence came before it, which for a track full of drone is a step at
## exactly the place a seam is measured. 0.4 s is a hundred time constants at 30 Hz.
_PRIME = 0.4


def lowpass(b, cutoff: float, poles: int = 1, wrap: bool = False) -> None:
    k = math.exp(-2.0 * math.pi * cutoff / RATE)
    j = 1.0 - k
    n = len(b)
    pre = min(n, int(_PRIME * RATE)) if wrap else 0
    for _ in range(poles):
        last = 0.0
        for i in range(n - pre, n):
            last = last * k + b[i] * j
        for i in range(n):
            last = last * k + b[i] * j
            b[i] = last


def highpass(b, cutoff: float, wrap: bool = False) -> None:
    """Kill the rumble under the music. Stacked drones and a room put a lot of energy
    below hearing, and every dB of it is headroom the audible part does not get."""
    k = math.exp(-2.0 * math.pi * cutoff / RATE)
    j = 1.0 - k
    n = len(b)
    last = 0.0
    if wrap:
        for i in range(n - min(n, int(_PRIME * RATE)), n):
            last = last * k + b[i] * j
    for i in range(n):
        x = b[i]
        last = last * k + x * j
        b[i] = x - last


def _coeffs(freq: float, q: float, mode_: str) -> tuple:
    """Biquad coefficients (RBJ). A two-pole resonance that is stable at any frequency —
    which a Chamberlin state-variable filter is not: the first version of the analysis
    filter bank returned NaN for every band above about 7 kHz, and NaN measures as "no
    finding" rather than as a failure, which is the worst way for a gate to break."""
    w0 = 2.0 * math.pi * min(0.49, freq / RATE)
    cs = math.cos(w0)
    alpha = math.sin(w0) / (2.0 * max(0.35, q))
    a0 = 1.0 + alpha
    if mode_ == "bp":
        b0, b1, b2 = q * alpha, 0.0, -q * alpha
    elif mode_ == "lp":
        b0 = b2 = (1.0 - cs) * 0.5
        b1 = 1.0 - cs
    else:
        b0 = b2 = (1.0 + cs) * 0.5
        b1 = -(1.0 + cs)
    return (b0 / a0, b1 / a0, b2 / a0, -2.0 * cs / a0, (1.0 - alpha) / a0)


def _band(sig, freq: float, q: float, mode_: str = "bp") -> list:
    """One resonant band. The workhorse: a vowel is three of these in parallel, a drum
    shell is one at high Q, and the centroid measurement is a bank of them."""
    b0, b1, b2, a1, a2 = _coeffs(freq, q, mode_)
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(sig)
    for i in range(len(sig)):
        x = sig[i]
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        out[i] = y
    return out


def _noise(total: int, colour: float = 0.0) -> list:
    """White noise, optionally darkened by a one-pole. The excitation for everything that
    is struck, scraped, breathed or blown."""
    out = [0.0] * total
    if colour <= 0.0:
        for i in range(total):
            out[i] = random.uniform(-1.0, 1.0)
        return out
    last = 0.0
    for i in range(total):
        last = last * colour + random.uniform(-1.0, 1.0) * (1.0 - colour)
        out[i] = last
    return out


def soft_clip(b, drive: float = 1.0) -> None:
    """Round the peaks instead of flattening them. A room sums a lot of voices and the
    result is spiky; normalising to the spike leaves the body of the sound quiet, which is
    how a big sound ends up small."""
    for i in range(len(b)):
        x = b[i] * drive
        b[i] = x / (1.0 + (x if x >= 0.0 else -x))


# --- the room ----------------------------------------------------------------------


## Freeverb's delay lines, which are given in samples at 44.1 kHz — the rate this module
## runs at, so they are used as written. Six combs rather than eight: the pair that was
## dropped is not audible under a mono dungeon bed and the generator is pure Python.
_COMBS = (1116, 1188, 1277, 1356, 1422, 1491)
_ALLPASS = (556, 441, 341)


def reverb(b, room: float = 0.84, damp: float = 0.35, wet: float = 0.32,
           pre: float = 0.012, size: float = 1.0) -> None:
    """Put the sound in a stone space. In place, mono, Schroeder/Freeverb topology.

    This is the most important function in the file. `room` is how long the space rings,
    `damp` is how much stone eats the top of each reflection (dark rooms are damped rooms),
    `pre` is the gap before the first reflection, which is what says *large*.

    A one-shot needs its buffer to have room for the tail. `reverb_loop` is the version for
    something that has to come back around.
    """
    n = len(b)
    d = int(pre * RATE)
    src = [0.0] * n
    for i in range(n):
        j = i - d
        src[i] = b[j] if j >= 0 else 0.0
    wetbuf = [0.0] * n
    for base in _COMBS:
        length = max(4, int(base * size))
        line = [0.0] * length
        p = 0
        store = 0.0
        keep = 1.0 - damp
        for i in range(n):
            y = line[p]
            store = y * keep + store * damp
            line[p] = src[i] + store * room
            wetbuf[i] += y
            p += 1
            if p == length:
                p = 0
    g = 1.0 / len(_COMBS)
    for i in range(n):
        wetbuf[i] *= g
    for base in _ALLPASS:
        length = max(4, int(base * size))
        line = [0.0] * length
        p = 0
        for i in range(n):
            x = wetbuf[i]
            y = line[p]
            line[p] = x + y * 0.5
            wetbuf[i] = y - x
            p += 1
            if p == length:
                p = 0
    dry = 1.0 - wet
    for i in range(n):
        b[i] = b[i] * dry + wetbuf[i] * wet


def reverb_loop(b, tail: float = 6.0, **kw) -> None:
    """The room, for something that loops.

    A recursive reverb has state, and state is what a loop cannot have: the first second of
    the track would be reverb-free while the last second rings into nothing. So the input
    is primed with the loop's own last `tail` seconds — the material that really does
    precede sample zero when the file wraps — and that lap is thrown away. What is left is
    the steady-state room, continuous across the seam by construction rather than by
    correction. It only works because the dry signal is already periodic: every voice in
    the score is written with `wrap=True`.
    """
    n = len(b)
    t = min(n, int(tail * RATE))
    pad = array.array("d", [0.0] * (t + n))
    for i in range(t):
        pad[i] = b[n - t + i]
    for i in range(n):
        pad[t + i] = b[i]
    reverb(pad, **kw)
    for i in range(n):
        b[i] = pad[t + i]


def delay(b, secs: float, feedback: float = 0.3, taps: int = 3, wrap: bool = True) -> None:
    """Discrete echoes, which a room does not give you: a struck thing in a corridor comes
    back once, distinctly. Wraps, for the same reason the voices do."""
    n = len(b)
    d = max(1, int(secs * RATE))
    src = list(b)
    for t in range(1, taps + 1):
        g = feedback ** t
        off = d * t
        if wrap:
            for i in range(n):
                b[(i + off) % n] += g * src[i]
        else:
            for i in range(n - off):
                b[i + off] += g * src[i]


# --- the voices ---------------------------------------------------------------------


def pluck(b, start, dur, freq, gain, t60: float = 2.4, damp: float = 0.42,
          pick: float = 0.22, colour: float = 0.55, wrap=False) -> None:
    """A plucked string: Karplus-Strong, a noise burst going round a damped delay line.

    The score's melodic voice and the closest thing this game has to a tune. A string is
    used rather than an oscillator because the *change* across the note is the character —
    it starts as a handful of noise and settles into a pitch, and its top dies before its
    bottom does, which is why a real instrument sounds nothing like a synthesiser holding
    the same note.

    `damp` is the loop filter, so it is both the timbre and how fast the top goes: 0.5 is a
    nylon string in a cellar, 0.1 is bright steel. `pick` combs the excitation, which is
    where on the string it was struck. `t60` is seconds to -60 dB.

    The delay line is a whole number of samples, so tuning above about a5 drifts by a few
    cents. Everything melodic here is written below that.
    """
    total = int(dur * RATE)
    length = max(4, int(round(RATE / freq)))
    exc = _noise(length, colour)
    off = max(1, int(pick * length))
    for i in range(length - 1, off - 1, -1):
        exc[i] -= 0.7 * exc[i - off]
    for i in range(length):                     # window, or the burst is a click
        exc[i] *= 0.5 - 0.5 * math.cos(2.0 * math.pi * i / length)
    # Zero-mean it. The loop filter passes DC at unity, so any offset left in the burst
    # rings for the whole note as a thud a fifth below nothing — it measured as a third of
    # the energy of a d4 pluck sitting at 60 Hz, which is headroom spent on inaudible mud.
    avg = sum(exc) / length
    for i in range(length):
        exc[i] -= avg
    line = exc
    per_period = 10.0 ** (-3.0 / max(1.0, freq * t60))
    keep = 1.0 - damp
    out = [0.0] * total
    p = 0
    last = 0.0
    for i in range(total):
        cur = line[p]
        v = cur * keep + last * damp
        last = cur
        line[p] = v * per_period
        out[i] = v
        p += 1
        if p == length:
            p = 0
    _mix(b, start, out, gain, wrap)


def bow(b, start, dur, freq, gain, cutoff: float = 900.0, q: float = 1.6,
        detune: float = 0.004, vib: float = 0.0, attack: float = 0.3,
        release: float = 0.45, wrap=False) -> None:
    """Low bowed strings: three detuned saws through a resonant lowpass that breathes.

    The bed under everything dark. Three of them rather than one because a single saw is a
    synthesiser and three a semitone-hundredth apart is a section — the beating between
    them is the whole effect, and it is also why this can hold a note for twenty seconds
    without becoming a test tone.
    """
    total = int(dur * RATE)
    raw = [0.0] * total
    lfo_w = 2.0 * math.pi * 0.07 / RATE
    for k, mult in enumerate((1.0 - detune, 1.0, 1.0 + detune)):
        phase = random.random()
        step = freq * mult / RATE
        vw = 2.0 * math.pi * (4.3 + 0.7 * k) / RATE
        for i in range(total):
            s = step
            if vib > 0.0:
                s *= 1.0 + vib * math.sin(vw * i)
            phase += s
            if phase >= 1.0:
                phase -= 1.0
            raw[i] += 2.0 * phase - 1.0         # naive saw: the lowpass below eats the alias
    for i in range(total):
        raw[i] *= 0.33
    out = _band(raw, cutoff, q, "lp")
    # the cutoff is fixed, so the movement is put on the amplitude instead: a slow
    # tremolo, which is what a bow arm actually does over a long note
    for i in range(total):
        out[i] *= _swell(i, total, attack, release) * (1.0 + 0.12 * math.sin(lfo_w * i))
    _mix(b, start, out, gain, wrap)


def choir(b, start, dur, freq, gain, vowel: str = "oo", breath: float = 0.25,
          attack: float = 0.35, release: float = 0.4, wrap=False) -> None:
    """Voices, far off: a pulse train shaped by three formants, with breath over it.

    What the catacombs sound like. It is not a sample and it is not meant to pass for one —
    at this distance and this level, three resonances and some air read as *people
    somewhere*, which is more frightening than anything articulate.
    """
    formants = {
        "oo": ((320.0, 6.0), (800.0, 4.0), (2300.0, 2.2)),
        "oh": ((500.0, 5.0), (1000.0, 4.0), (2600.0, 2.0)),
        "ah": ((720.0, 5.0), (1200.0, 3.4), (2700.0, 2.0)),
    }[vowel]
    total = int(dur * RATE)
    src = array.array("d", [0.0] * total)
    phase = random.random()
    step = freq / RATE
    for i in range(total):
        phase += step * (1.0 + 0.004 * math.sin(2.0 * math.pi * 5.1 * i / RATE))
        if phase >= 1.0:
            phase -= 1.0
        src[i] = 1.0 - 2.0 * phase               # saw, rich enough to excite all three
    # A throat is not a buzzer: roll the source off before the formants, or the top
    # partials come through the third resonance and the "voices" are a sawtooth again.
    lowpass(src, 2600.0, poles=2)
    src = list(src)
    out = [0.0] * total
    for f, q in formants:
        band = _band(src, f, q, "bp")
        w = 1.0 / (1.0 + f / 400.0)              # the low formant carries the vowel
        for i in range(total):
            out[i] += band[i] * w
    if breath > 0.0:
        air = _band(_noise(total, 0.2), formants[1][0], 1.2, "bp")
        for i in range(total):
            out[i] += air[i] * breath
    for i in range(total):
        out[i] *= _swell(i, total, attack, release)
    _mix(b, start, out, gain, wrap)


## Partial ratios for struck metal. None of them is a whole number, and that is the
## point: a bar, a plate and a coin have modes at ratios nothing divides, which is why
## a struck metal thing has a pitch you cannot quite name.
METAL = {
    "bar":   (1.0, 2.76, 5.40, 8.93, 13.34, 18.64),      # a free bar: chime, latch, blade
    "plate": (1.0, 1.59, 2.14, 2.65, 3.31, 4.09, 5.43),  # armour, a shield taking a blow
    "bell":  (1.0, 2.00, 2.41, 3.00, 3.61, 4.50, 5.33),  # a cast bell: the stingers
    "coin":  (1.0, 2.31, 3.72, 5.11, 7.03, 9.44, 12.1),  # small, bright, dies fast
}


def metal(b, start, dur, freq, gain, kind: str = "bar", t60: float = 0.7,
          strike: float = 0.5, jitter: float = 0.012, wrap=False) -> None:
    """Struck metal: a bank of inharmonic modes, each with its own decay.

    The voice the old set was missing entirely. Higher modes die faster — that is the law
    for real plates, and obeying it is the difference between a struck thing and an organ
    chord. `strike` is how hard: a hard strike puts more energy in the high modes and adds
    the contact noise of whatever hit it.
    """
    total = int(dur * RATE)
    out = [0.0] * total
    ratios = METAL[kind]
    for k, r in enumerate(ratios):
        f = freq * r * (1.0 + random.uniform(-jitter, jitter))
        if f >= RATE * 0.47:
            continue
        amp = (0.55 + 0.45 * strike) ** k / (1.0 + 0.35 * k)
        life = t60 / (1.0 + 0.55 * k)            # the top goes first
        d = 6.91 * (dur / max(0.02, life))
        w = 2.0 * math.pi * f / RATE
        ph = random.random() * math.tau
        att = max(2, int(0.0008 * RATE))
        for i in range(total):
            out[i] += amp * _env(i, total, att, d) * math.sin(w * i + ph)
    if strike > 0.0:
        hit = _noise(int(0.012 * RATE), 0.2)
        ramp = max(2, int(0.0004 * RATE))
        for i in range(len(hit)):
            if i < total:
                out[i] += (hit[i] * strike * 0.5 * (1.0 - i / len(hit))
                           * (1.0 if i >= ramp else i / ramp))
    _mix(b, start, out, gain, wrap)


def drum(b, start, dur, freq, gain, snap: float = 0.35, bend: float = 0.55,
         t60: float = 0.4, shell: float = 0.3, wrap=False) -> None:
    """A membrane: a pitch that falls as the skin relaxes, a slap of contact noise, and a
    resonance from the shell.

    Frame drums and something taiko-shaped, and the only percussion in the game. There is
    no hi-hat and there will not be one: a bright repeating tick is a metronome, and a
    metronome is the thing that made the old score sound like an arcade.
    """
    total = int(dur * RATE)
    out = [0.0] * total
    d = 6.91 * (dur / max(0.02, t60))
    att = max(2, int(0.0012 * RATE))
    w = 2.0 * math.pi * freq / RATE
    phase = 0.0
    for i in range(total):
        e = _env(i, total, att, d)
        phase += w * (1.0 + bend * math.exp(-9.0 * i / total))
        out[i] = e * (math.sin(phase) + 0.22 * math.sin(2.0 * phase))
    if snap > 0.0:
        slap = _noise(int(min(dur, 0.05) * RATE), 0.45)
        # The 0.4 ms ramp on the contact noise is the same defect `_env` documents, in the
        # one place it was easy to miss: the pitched part of the drum was ramped and the
        # slap on top of it was not, so a drum on a loop's downbeat still put a full-
        # amplitude sample at index zero and the boss track measured a seam click.
        ramp = max(2, int(0.0004 * RATE))
        for i in range(len(slap)):
            out[i] += (slap[i] * snap * math.exp(-7.0 * i / len(slap))
                       * (1.0 if i >= ramp else i / ramp))
    if shell > 0.0:
        body = _band(list(out), freq * 4.2, 3.2, "bp")
        for i in range(total):
            out[i] += body[i] * shell
    _mix(b, start, out, gain, wrap)


def air(b, start, dur, gain, low: float = 240.0, high: float = 240.0, q: float = 1.1,
        grain: float = 0.0, attack: float = 0.25, release: float = 0.3, wrap=False) -> None:
    """Noise through a resonance that moves: wind, breath, water, the cave itself.

    The layer that makes a place feel occupied. `low`->`high` sweeps the centre over the
    note, so it is also a whoosh: a blade, a card leaving a hand, a door.
    """
    total = int(dur * RATE)
    src = _noise(total, 0.12)
    if grain > 0.0:
        for i in range(total):
            src[i] *= 1.0 - grain + grain * abs(math.sin(2.0 * math.pi * 3.7 * i / RATE))
    # A swept band, inlined because `_band` holds its frequency still. Coefficients are
    # recomputed once a block rather than once a sample: two trig calls per sample is the
    # difference between this generator taking a minute and taking ten, and a 1.5 ms step
    # in a filter's cutoff is not something anybody can hear.
    out = [0.0] * total
    block = 64
    x1 = x2 = y1 = y2 = 0.0
    for s in range(0, total, block):
        b0, b1, b2, a1, a2 = _coeffs(low * (high / low) ** (s / total), q, "bp")
        for i in range(s, min(total, s + block)):
            x = src[i]
            y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1 = x1, x
            y2, y1 = y1, y
            out[i] = y
    for i in range(total):
        out[i] *= _swell(i, total, attack, release)
    _mix(b, start, out, gain, wrap)


def sub(b, start, dur, freq, gain, fall: float = 0.0, t60: float = 0.5, wrap=False) -> None:
    """The weight. A sine low enough to be felt rather than heard, under an impact or
    holding the floor of a drone. `fall` glides it down, which is what makes a big sound
    read as *heavy* instead of merely loud."""
    total = int(dur * RATE)
    out = [0.0] * total
    d = 6.91 * (dur / max(0.02, t60))
    att = max(2, int(0.004 * RATE))
    w = 2.0 * math.pi * freq / RATE
    phase = 0.0
    for i in range(total):
        phase += w * (1.0 - fall * i / total)
        out[i] = _env(i, total, att, d) * math.sin(phase)
    _mix(b, start, out, gain, wrap)


def scrape(b, start, dur, gain, freq: float = 70.0, rough: float = 0.6,
           bright: float = 900.0, wrap=False) -> None:
    """Stone on stone, a chain dragging, a lid. Noise through a comb — which gives it a
    pitch without a note — modulated so it grinds rather than hisses."""
    total = int(dur * RATE)
    src = _noise(total, 0.25)
    length = max(2, int(RATE / freq))
    line = [0.0] * length
    p = 0
    for i in range(total):
        y = line[p]
        line[p] = src[i] + y * 0.72
        src[i] = y
        p += 1
        if p == length:
            p = 0
    out = _band(src, bright, 1.4, "bp")
    step = 2.0 * math.pi * 17.0 / RATE
    for i in range(total):
        g = 1.0 - rough + rough * (0.5 + 0.5 * math.sin(step * i + 3.0 * math.sin(step * 0.31 * i)))
        out[i] *= g * _swell(i, total, 0.08, 0.35)
    _mix(b, start, out, gain, wrap)


# --- measurement helpers, shared so both reports mean the same thing ---------------


def rms(b) -> float:
    return math.sqrt(sum(x * x for x in b) / max(1, len(b)))


def peak(b) -> float:
    return max((abs(s) for s in b), default=0.0)


def centroid(b, window: float = 0.0) -> float:
    """Spectral centre of mass in Hz, by a bank of bandpass filters.

    The number that catches a set wearing two instruments: a struck plate and a square-wave
    blip differ here by an octave and a half whatever their levels.

    It was a bank of single-frequency Goertzel probes first, and that was wrong in a way
    worth recording. A narrow probe measures spectral *density*, and summing densities over
    log-spaced frequencies weights every octave equally — so a whisper of broadband hiss,
    which has the same density at 15 kHz as at 150 Hz, dragged the answer up by an octave.
    Two plucked notes a fourth apart measured 2.1 kHz and 5.7 kHz. Filter bands integrate
    over their own bandwidth instead, which is what "how much energy is up there" means.
    """
    n = len(b) if window <= 0.0 else min(len(b), int(window * RATE))
    if n < 256:
        return 0.0
    sig = list(b[:n])
    num = den = 0.0
    f = 70.0
    while f < RATE / 2.0 * 0.9:
        band = _band(sig, f, 2.2, "bp")
        energy = 0.0
        for v in band:
            energy += v * v
        num += f * energy
        den += energy
        f *= 1.6
    return num / den if den else 0.0


def band_ratio(b, cutoff: float = 200.0, window: float = 0.0) -> float:
    """Share of the energy below `cutoff`. Weight, as a number.

    Dark fantasy is bottom-heavy, and "make it darker" without a measurement is how a mix
    ends up merely quieter. Cheap because it is a copy and a one-pole.
    """
    n = len(b) if window <= 0.0 else min(len(b), int(window * RATE))
    if n < 256:
        return 0.0
    low = array.array("d", b[:n])
    lowpass(low, cutoff, poles=2)
    total = sum(x * x for x in b[:n])
    return math.sqrt(sum(x * x for x in low) / max(1e-12, total))


def envelope(b, hop: float = 0.02) -> list:
    """Loudness over time, one value per `hop`. What the pulse test reads."""
    step = max(1, int(hop * RATE))
    out = []
    for s in range(0, len(b) - step, step):
        acc = 0.0
        for i in range(s, s + step):
            acc += b[i] * b[i]
        out.append(math.sqrt(acc / step))
    return out


def pulse(b, lo: float = 0.30, hi: float = 3.20) -> float:
    """How strongly the track keeps time, 0 (no beat) to 1 (a metronome).

    The autocorrelation peak of the ONSET signal — the rising edges of the loudness
    envelope — over the range of lags a beat can live in. This exists because "ambient, not
    chiptune" is otherwise an opinion: the menu, overworld and dungeon have to measure BELOW
    a ceiling, since a player should not be able to tap along to a dungeon, and combat and
    the boss have to measure ABOVE a floor for the same reason inverted.

    Onsets rather than loudness, and that correction is the whole reason this docstring is
    long. The first version autocorrelated the envelope itself and scored the dungeon at
    0.74 — a track with no percussion in it at all. It was reading the two bowed drones
    beating against each other: six cents apart at 110 Hz is a 2.6-second throb, which is
    as periodic as a drum and is not a beat, because you cannot tap to it and nothing in it
    starts. What a beat has that a throb does not is attack, so the measurement takes the
    positive difference of the envelope, where a smooth swell contributes almost nothing.

    The lag range reaches 3.2 s because a *bar* is a pulse too. Capped at 1.3 s it read the
    combat track — whose pattern deliberately limps, so its shortest exact repeat is the
    bar — as nearly beatless at 0.20, while a listener counts it fine.
    """
    env = envelope(b)
    if len(env) < 64:
        return 0.0
    onset = [max(0.0, env[i] - env[i - 1]) for i in range(1, len(env))]
    mean = sum(onset) / len(onset)
    e = [v - mean for v in onset]
    energy = sum(v * v for v in e) or 1e-12
    hop = 0.02
    best = 0.0
    for lag in range(int(lo / hop), min(len(e) - 8, int(hi / hop))):
        acc = 0.0
        for i in range(len(e) - lag):
            acc += e[i] * e[i + lag]
        best = max(best, acc / energy)
    return best


def attack_ms(b, floor: float = 0.1) -> float:
    """Time to the peak, from where the sound crosses `floor` of it. A hit has to READ as
    a hit: all the room in the world does not help if the transient is late."""
    pk = peak(b)
    if pk <= 0.0:
        return 0.0
    at = 0
    for i in range(len(b)):
        if abs(b[i]) >= pk - 1e-12:
            at = i
            break
    start = 0
    thresh = pk * floor
    for i in range(at, -1, -1):
        if abs(b[i]) < thresh:
            start = i
            break
    return 1000.0 * (at - start) / RATE


def onset_ms(b, floor: float = 0.1) -> float:
    """How long until the sound is audible at all: file start to a tenth of the peak.

    The counterweight to `tail_ms`. Putting everything in a room is the point of D173, and
    the way that goes wrong is feedback that arrives late — a blade whose swing takes 60 ms
    to reach the impact is right, a button whose click does that is broken. Every family has
    a ceiling on this, and it is the one measurement here about the *game* rather than the
    sound.
    """
    pk = peak(b)
    if pk <= 0.0:
        return 0.0
    thresh = pk * floor
    for i in range(len(b)):
        if abs(b[i]) >= thresh:
            return 1000.0 * i / RATE
    return 0.0


def tail_ms(b, drop_db: float = 30.0) -> float:
    """Time from the peak to `drop_db` below it, measured on the envelope.

    The room, as a number. This is the metric the old set would have failed: a dry sound
    has no tail, and no tail is the reason a game sounds like it is happening on a desk
    instead of in a dungeon. Both generators assert a FLOOR on it.
    """
    env = envelope(b, hop=0.005)
    if not env:
        return 0.0
    pk = max(env)
    if pk <= 0.0:
        return 0.0
    at = env.index(pk)
    thresh = pk * (10.0 ** (-drop_db / 20.0))
    for i in range(at, len(env)):
        if env[i] < thresh:
            return 1000.0 * (i - at) * 0.005
    return 1000.0 * (len(env) - at) * 0.005


def write_wav(path, b) -> None:
    import wave
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array("h", [
            int(max(-1.0, min(1.0, s)) * 32767) for s in b]).tobytes())


def normalize(b, target_peak: float) -> None:
    pk = peak(b) or 1.0
    g = target_peak / pk
    for i in range(len(b)):
        b[i] *= g
