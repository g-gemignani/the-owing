## The colour of the game, read out of the paintings rather than written down.
##
## Every generated asset (D89) is built from a ramp produced here — today that is the
## ten isometric floor and wall materials, and anything drawn later joins them. It is
## its own class rather than a section of the one generator that currently uses it,
## because the moment a SECOND generator needs "the backdrop palette" the tempting
## thing is to write it out again, and that is the D34 bug in a new medium. A drift in
## hue is worse than a stale number, too: nobody notices until the screens are side by
## side.
##
## Nothing here is authored. The input is `assets/art/bg_*.png` — the twelve painted
## dungeon backdrops that ART.md calls "this is the game" — and the output is a
## five-stop ramp. Add a backdrop, or repaint one, and every generated asset moves
## with it on the next regenerate. That is the point.
class_name ArtPalette
extends RefCounted

## Where the floor is in a painted backdrop, as a fraction of its height. Taken from
## `PixelArt.HORIZON_LINE` rather than restated, so a backdrop pass that moves the
## horizon moves the sampling with it. `tests/test_art.gd` already asserts every
## backdrop agrees with that line, so this is sampling ground that is known to be
## ground.
const FLOOR_TOP := PixelArt.HORIZON_LINE + 0.02
const FLOOR_BOTTOM := 0.98

## The shape of the lighting, not its level — `normalise` sets the level. Spread
## deliberately wide: the iso view multiplies these by its fog tints, and a material
## with no range in it has nothing left to read once it is dimmed.
const VALUE_STOPS := [0.26, 0.42, 0.56, 0.70, 0.86]
## Pulled well down from what the paintings actually carry. These are atmospheric
## images and their ground takes the saturation of the air in the room; reproduced at
## full strength on a material that fills most of the screen, worked stone comes out
## as coloured plastic.
const SAT_CAP := 0.34
const SAT_SCALE := 0.75
const TARGET_LUMA := 0.46

static func _neutral() -> Array:
	return [Color(0.13, 0.12, 0.12), Color(0.24, 0.23, 0.22), Color(0.34, 0.32, 0.30),
		Color(0.44, 0.42, 0.39), Color(0.56, 0.53, 0.49)]

## Every floor-band pixel of the named dungeons' backdrops, brightest last.
##
## Read with `Image.load_from_file` rather than `load()`: the import cache hands back
## whatever was there when the project was last imported, which during an art pass is
## the file you are in the middle of replacing (the same trap `tools/strip_sparkle.gd`
## documents).
static func floor_samples(dungeon_ids: Array) -> Array:
	var samples: Array = []
	for did in dungeon_ids:
		var path: String = ProjectSettings.globalize_path(
			"res://assets/art/bg_%s.png" % String(did))
		var img := Image.load_from_file(path)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		for y in range(int(float(h) * FLOOR_TOP), int(float(h) * FLOOR_BOTTOM), 3):
			for x in range(0, w, 3):
				var c := img.get_pixel(x, y)
				# skip what is basically black: these paintings vignette hard, and the
				# frame is not the floor
				if c.get_luminance() >= 0.04:
					samples.append(c)
	samples.sort_custom(func(a, b): return Color(a).get_luminance() < Color(b).get_luminance())
	return samples

## A five-stop ramp, dark to light, for the named dungeons.
##
## ONE HUE, LIT ACROSS A RANGE — which is what a material is, and what two earlier
## versions of this failed to produce.
##
## Taking a colour per percentile does not work, in either of the two ways it can be
## done. Indexing a single sample gave worked stone `#3c0c00 #2d2136 #22346a #773c22`:
## a red, a purple, a blue and a brown, because four dungeons feed that ramp and
## consecutive luminances belong to whichever painting owned that brightness.
## Averaging a window around each percentile fixed the incoherence and left a hue
## SWEEP — dark violet climbing to pink, because the brightest percentile in a floor
## band is not floor at all, it is the braziers these rooms are lit by.
##
## So chroma and value come from different places on purpose. Hue and saturation are
## one circular mean over the middle of the distribution, which is the colour of the
## ground itself; the value ramp is the percentile spread, which is how that ground is
## lit. No stop can drift to a different hue because there is only one hue.
static func ramp(dungeon_ids: Array) -> Array:
	var samples := floor_samples(dungeon_ids)
	if samples.is_empty():
		return _neutral()
	var n := samples.size()
	var hx := 0.0
	var hy := 0.0
	var sat := 0.0
	var count := 0
	for i in range(int(float(n) * 0.20), int(float(n) * 0.80)):
		var c: Color = samples[i]
		var a: float = c.h * TAU
		# weighted by saturation: a near-grey pixel has no meaningful hue to average,
		# and a dim painting holds enough of them to drag a circular mean to whatever
		# the accidental residue is
		hx += cos(a) * c.s
		hy += sin(a) * c.s
		sat += c.s
		count += 1
	if count == 0:
		return _neutral()
	var hue: float = fposmod(atan2(hy, hx) / TAU, 1.0)
	var s: float = minf(SAT_CAP, sat / float(count) * SAT_SCALE)
	var out: Array = []
	for v in VALUE_STOPS:
		# light desaturates as it approaches white, which is true of real surfaces and
		# also stops the top stop reading as a coloured lamp
		out.append(Color.from_hsv(hue, s * (1.0 - 0.45 * float(v) * float(v)), float(v)))
	return normalise(out)

## Lift a ramp to the level the screens need, keeping hue and internal spacing.
##
## The paintings are dim and vignetted, so ground sampled straight out of one has a
## mean luminance near 0.20 — and the iso view multiplies that AGAIN by its fog tints
## (0.52 for ground merely seen). Shipped as sampled, the floor came out near-black
## and the fog stopped being legible, because there was no headroom left to dim.
##
## The factor is backed off rather than clamped per channel. Clamping is what turned
## the brightest stop of worked stone into `#ffc5dc` — red pinned at 1.0 while green
## and blue kept scaling is a hue shift toward pink, applied to exactly the stop the
## eye reads as the material's colour. A slightly darker ramp is a far smaller error.
static func normalise(ramp_in: Array) -> Array:
	var mean := 0.0
	for c in ramp_in:
		mean += Color(c).get_luminance()
	mean /= float(ramp_in.size())
	if mean <= 0.001:
		return ramp_in
	var k: float = TARGET_LUMA / mean
	var peak := 0.0
	for c in ramp_in:
		var col := Color(c)
		peak = maxf(peak, maxf(col.r, maxf(col.g, col.b)))
	if peak * k > 1.0:
		k = 1.0 / peak
	var out: Array = []
	for c in ramp_in:
		var col := Color(c)
		out.append(Color(col.r * k, col.g * k, col.b * k))
	return out

## Pick along a five-stop ramp with a continuous parameter.
static func shade(ramp_in: Array, t: float) -> Color:
	var f: float = clampf(t, 0.0, 1.0) * float(ramp_in.size() - 1)
	var i: int = clampi(int(f), 0, ramp_in.size() - 2)
	return Color(ramp_in[i]).lerp(Color(ramp_in[i + 1]), f - float(i))

## The line colour everything generated is drawn with.
##
## Not black. ART.md's diagnosis of the game's one good visual language is "painted,
## INKED illustration", and the ink in those paintings is a very dark version of the
## room rather than a neutral — black outlines sit on top of a painting instead of
## inside it. So the ink is the ramp's own dark end, taken down further.
static func ink(ramp_in: Array) -> Color:
	var c := Color(ramp_in[0])
	return Color(c.r * 0.30, c.g * 0.30, c.b * 0.32)

## Which dungeons use a terrain, sorted — the input `ramp()` wants for the iso floor.
static func dungeons_with_terrain(terrain: String) -> Array:
	var out: Array = []
	for did in Balance.ISO_TERRAIN_OF:
		if String(Balance.ISO_TERRAIN_OF[did]) == terrain:
			out.append(String(did))
	out.sort()
	return out

## Every dungeon that has a painted backdrop, sorted. The input for anything that has
## to look right on ALL of them rather than in one place — markers, enemy plates.
static func all_dungeons() -> Array:
	var out: Array = []
	for did in Balance.DUNGEONS:
		if FileAccess.file_exists("res://assets/art/bg_%s.png" % String(did)):
			out.append(String(did))
	out.sort()
	return out
