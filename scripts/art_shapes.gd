## The drawing language every generated figure is built in (D89).
##
## One place, because the whole point of generating this art is that the game stops
## speaking four visual dialects at once (ART.md's diagnosis). What it produces is a
## flat shape read entirely by outline: inked in the palette's own dark end, lit from
## above-left, on a transparent canvas with the subject's feet flush with the bottom.
##
## Nothing here knows what it is drawing. Callers pass polygons.
class_name ArtShapes
extends RefCounted

## Everything is rasterised at this multiple of the final size and downsampled at the
## end. Simpler than per-edge coverage maths and better than it too, and it is what
## lets the ink line be one clean constant-width band instead of a crawling stair.
const SS := 3

## Where the body sits on the value scale, and where the rim sits.
##
## The body is DARK and the gap between its two stops is small. The floor is the
## brightest band in every one of these paintings (`tools/art_manifest.gd` says so, and
## `combat.gd` already draws its missing-art placeholder this way), so a pale figure
## dissolves into the ground it stands on. Every attempt to model form *inside* the
## silhouette came back looking like a gradient rather than like a creature, so the
## light is spent almost entirely on the rim.
const BODY_DARK := 0.10
const BODY_LIGHT := 0.30
const RIM := 0.92

static func ellipse(cx: float, cy: float, rx: float, ry: float, n: int = 28) -> Array:
	var out: Array = []
	for i in n:
		var a: float = TAU * float(i) / float(n)
		out.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return out

## A tapered limb or trunk: wider at `y0`, narrower at `y1`, optionally leaning.
static func taper(cx: float, y0: float, y1: float, w0: float, w1: float,
		lean: float = 0.0) -> Array:
	return [Vector2(cx - w0, y0), Vector2(cx + w0, y0),
		Vector2(cx + lean + w1, y1), Vector2(cx + lean - w1, y1)]

## Even-odd scanline fill into a byte mask. Polygons are normalised (0..1, y down), so
## a shape table is resolution-independent and one definition draws at tile size and at
## arena size.
static func fill(mask: PackedByteArray, w: int, h: int, polys: Array, value: int) -> void:
	for poly in polys:
		var pts: Array = poly
		if pts.size() < 3:
			continue
		var ymin := 1.0
		var ymax := 0.0
		for p in pts:
			ymin = minf(ymin, Vector2(p).y)
			ymax = maxf(ymax, Vector2(p).y)
		var y0: int = clampi(int(ymin * float(h)) - 1, 0, h - 1)
		var y1: int = clampi(int(ymax * float(h)) + 1, 0, h - 1)
		for y in range(y0, y1 + 1):
			var yc: float = (float(y) + 0.5) / float(h)
			var xs: Array = []
			for i in pts.size():
				var a := Vector2(pts[i])
				var b := Vector2(pts[(i + 1) % pts.size()])
				if (a.y <= yc and b.y > yc) or (b.y <= yc and a.y > yc):
					xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
			xs.sort()
			var i2 := 0
			while i2 + 1 < xs.size():
				var xa: int = clampi(int(float(xs[i2]) * float(w)), 0, w - 1)
				var xb: int = clampi(int(float(xs[i2 + 1]) * float(w)), 0, w - 1)
				for x in range(xa, xb + 1):
					mask[y * w + x] = value
				i2 += 2

## Is this filled pixel within `r` of an empty one — i.e. is it the ink band?
##
## By erosion rather than by stroking each edge, which is what makes the width exactly
## constant on concave shapes and correct where two polygons of one figure overlap.
## Stroking edges double-darkens every internal seam, and a silhouette assembled from
## nine polygons is nothing but internal seams.
static func is_edge(mask: PackedByteArray, w: int, h: int, x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			# off-canvas counts as empty, so a figure running off the bottom edge keeps
			# its outline instead of bleeding to the border
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				return true
			if mask[ny * w + nx] == 0:
				return true
	return false

## Draw a figure and return it at final size.
##
## `polys` are filled, then `holes` are punched out — holes are how eyes and the gap
## between a pair of legs are done, because a gap in a silhouette reads at any size and
## against any background where a light-coloured mark has to compete with the rim.
static func render(polys: Array, holes: Array, w: int, h: int, ramp: Array,
		hue: float, sat: float, glow: bool, ink_px: float = 2.0) -> Image:
	var sw: int = w * SS
	var sh: int = h * SS
	var mask := PackedByteArray()
	mask.resize(sw * sh)
	mask.fill(0)
	fill(mask, sw, sh, polys, 1)
	if not holes.is_empty():
		fill(mask, sw, sh, holes, 0)

	# `ink_px` is a width in FINAL pixels, so the radius is that many SUPERpixels per
	# final pixel. Dividing by SS instead of multiplying put a 2.5px line at under one
	# pixel after downsampling, and produced a contact sheet of flat pastel shapes with
	# no outline at all — the single thing most responsible for the first pass looking
	# unfinished.
	var r: int = maxi(2, int(ink_px * float(SS)))
	var body_dark := _tinted(ramp, hue, sat, BODY_DARK)
	var body_light := _tinted(ramp, hue, sat, BODY_LIGHT)
	var rim := _tinted(ramp, hue, sat * 0.55, RIM)
	var ink := ArtPalette.ink(ramp)

	var big := Image.create(sw, sh, false, Image.FORMAT_RGBA8)
	for y in sh:
		for x in sw:
			if mask[y * sw + x] == 0:
				big.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var fy: float = float(y) / float(sh)
			if is_edge(mask, sw, sh, x, y, r):
				# The outline is not one colour. An edge whose outside lies up and to
				# the left catches the light every painted backdrop in this game throws
				# from that direction, and becomes a rim; every other edge is ink. That
				# one distinction is what separates a silhouette from a sticker, and it
				# costs a single lookup per edge pixel.
				var ox: int = x - r - 1
				var oy: int = y - r - 1
				var lit: bool = ox < 0 or oy < 0 or mask[oy * sw + ox] == 0
				big.set_pixel(x, y, rim if lit and fy < 0.88 else ink)
				continue
			var t: float = clampf(1.0 - fy * 1.15, 0.0, 1.0)
			if glow:
				t = clampf(t + 0.45 * (1.0 - fy), 0.0, 1.0)
			big.set_pixel(x, y, body_dark.lerp(body_light, t * t))

	big.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return big

## A value on the ramp, pushed toward the figure's own hue. Value comes from the
## palette so the figure belongs to the room; hue and saturation are its own so it does
## not disappear into the floor.
## `v` IS the intended value. It used to be run through `0.25 + luminance * 1.25`,
## which put a floor of 0.25 under everything and rendered `BODY_DARK = 0.10` at about
## 0.50 — so the constants said "dark silhouette" and the capture showed a pale pink
## creature floating in front of the room instead of standing in it. The lesson is
## narrow and worth keeping: **a constant named DARK has to survive the transform
## applied to it**, and the only way to know is to photograph the result in context.
static func _tinted(ramp: Array, hue: float, sat: float, v: float) -> Color:
	# blended toward the room's own colour at that value, so two figures lit by
	# different dungeons differ, without the ramp deciding how dark they are
	return Color.from_hsv(hue, sat, clampf(v, 0.03, 1.0)).lerp(ArtPalette.shade(ramp, v), 0.30)

## Coverage, foot width, and **waist ratio** — how much narrower the figure is at
## mid-height than at the shoulder.
##
## The third one is the measurement that matters and the one whose absence let the
## first pass ship coffins. A humanoid silhouette that goes straight from shoulder to
## floor at constant width is a box whatever you draw on it; the eye reads a figure
## from the pinch at the waist and the gap between the legs. Anything near 1.0 here is
## a slab, and the generator prints it so that is visible without opening the file.
static func measure(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var filled := 0
	var foot := 0
	var widths := PackedInt32Array()
	widths.resize(h)
	for y in h:
		var row := 0
		for x in w:
			if img.get_pixel(x, y).a > 0.5:
				row += 1
				filled += 1
				if y >= h - 3:
					foot += 1
		widths[y] = row
	var shoulder := 0
	for y in range(int(float(h) * 0.20), int(float(h) * 0.40)):
		shoulder = maxi(shoulder, widths[y])
	var waist := 9999
	for y in range(int(float(h) * 0.50), int(float(h) * 0.80)):
		waist = mini(waist, widths[y])
	var ratio: float = 1.0 if shoulder <= 0 else float(waist) / float(shoulder)
	return [100.0 * float(filled) / float(w * h), foot, ratio]

# --- body plans ----------------------------------------------------------------
#
# Shared by the combat arena and the isometric floor, and that sharing is a rule rather
# than a saving: a wanderer crossing a hall IS the fight it will become (D85), so the
# thing you see coming and the thing you meet have to be the same creature. Two copies
# of these tables would drift the moment one screen got a tweak.

## Heavy, shouldered, horned — and unmistakably a FIGURE, which the first attempt was
## not. Head above the shoulders on a neck, a waist, two arms, and two legs with a gap.
static func brute(bulk: float, blade: float, plates: float) -> Array:
	var sh: float = 0.17 + 0.13 * bulk          # half-width at the shoulder
	var wa: float = sh * (0.62 - 0.10 * bulk)   # half-width at the waist
	var hy: float = 0.115                        # head centre
	var out: Array = [
		ArtShapes.ellipse(0.5, hy, 0.072 + 0.014 * bulk, 0.062 + 0.012 * bulk),
		ArtShapes.taper(0.5, hy + 0.04, 0.20, 0.036, 0.055),        # neck
		# torso: shoulders out, pinched at the waist
		[Vector2(0.5 - sh, 0.215), Vector2(0.5 - sh * 0.80, 0.195),
		 Vector2(0.5 + sh * 0.80, 0.195), Vector2(0.5 + sh, 0.215),
		 Vector2(0.5 + wa, 0.56), Vector2(0.5 - wa, 0.56)],
		ArtShapes.taper(0.5 - sh * 0.86, 0.23, 0.56, 0.052, 0.038, -0.02),   # arm
		ArtShapes.taper(0.5 + sh * 0.86, 0.23, 0.56, 0.052, 0.038, 0.02),    # arm
		# legs, planted apart — the gap between them is what makes this read as a
		# standing creature rather than as a block with a head on it
		ArtShapes.taper(0.5 - wa * 0.52, 0.54, 1.0, 0.070, 0.058, -0.030),
		ArtShapes.taper(0.5 + wa * 0.52, 0.54, 1.0, 0.070, 0.058, 0.030),
		# horns sweeping BACK from the head, so they belong to its outline instead of
		# standing on top of it like ears
		[Vector2(0.5 - 0.052, hy - 0.012), Vector2(0.5 - 0.17 - 0.05 * bulk, hy - 0.082),
		 Vector2(0.5 - 0.145 - 0.05 * bulk, hy - 0.018), Vector2(0.5 - 0.042, hy + 0.032)],
		[Vector2(0.5 + 0.052, hy - 0.012), Vector2(0.5 + 0.17 + 0.05 * bulk, hy - 0.082),
		 Vector2(0.5 + 0.145 + 0.05 * bulk, hy - 0.018), Vector2(0.5 + 0.042, hy + 0.032)],
	]
	if blade > 0.05:
		# held point-down beside the figure. Length is the whole signal, so it runs from
		# the hand toward the floor and the crossguard breaks the outline at the grip.
		var bx: float = 0.5 + sh * 0.86 + 0.055
		var reach: float = 0.26 + 0.40 * blade
		out.append(ArtShapes.taper(bx, 0.30, 0.30 + reach, 0.021, 0.012))
		out.append([Vector2(bx - 0.055, 0.285), Vector2(bx + 0.055, 0.285),
			Vector2(bx + 0.055, 0.315), Vector2(bx - 0.055, 0.315)])
	if plates > 0.45:
		out.append([Vector2(0.5 - sh * 1.06, 0.235), Vector2(0.5 + sh * 1.06, 0.235),
			Vector2(0.5 + sh * 0.86, 0.325), Vector2(0.5 - sh * 0.86, 0.325)])  # pauldrons
	return out

## A narrow robe under a hood, with a staff and a light. The hood is separated from the
## shoulders by a real neck — without it the two merge and the whole figure reads as a
## lava lamp, which is what the first attempt produced.
static func caster(bulk: float, blade: float, plates: float) -> Array:
	var hem: float = 0.20 + 0.08 * bulk
	var hy := 0.105
	var out: Array = [
		# hood: a teardrop with a point, not a circle
		[Vector2(0.5, hy - 0.075), Vector2(0.5 + 0.062, hy - 0.010),
		 Vector2(0.5 + 0.052, hy + 0.055), Vector2(0.5, hy + 0.072),
		 Vector2(0.5 - 0.052, hy + 0.055), Vector2(0.5 - 0.062, hy - 0.010)],
		ArtShapes.taper(0.5, hy + 0.055, 0.205, 0.030, 0.052),        # neck
		# robe: narrow at the shoulders, flaring to a wide hem that meets the floor
		[Vector2(0.5 - 0.098, 0.20), Vector2(0.5 + 0.098, 0.20),
		 Vector2(0.5 + 0.135, 0.52), Vector2(0.5 + hem, 1.0),
		 Vector2(0.5 - hem, 1.0), Vector2(0.5 - 0.135, 0.52)],
		ArtShapes.taper(0.5 - 0.115, 0.26, 0.60, 0.040, 0.028, -0.02),  # sleeve
		# staff, taller than the figure so the silhouette breaks the top of the canvas
		ArtShapes.taper(0.5 + 0.175, 0.02, 1.0, 0.013, 0.011),
	]
	out.append(ArtShapes.ellipse(0.5 + 0.175, 0.035, 0.030 + 0.038 * blade,
		0.030 + 0.038 * blade))                                        # the light
	if plates > 0.4:
		out.append(ArtShapes.ellipse(0.5, 0.225, 0.115, 0.030))        # collar
	return out

## Several small things standing together. `n` comes straight from `count_max`, which
## is the number the fight will actually put in front of you.
static func swarm(bulk: float, blade: float, n: int) -> Array:
	var out: Array = []
	var count: int = clampi(n, 2, 5)
	for i in count:
		var t: float = (float(i) + 0.5) / float(count)
		var cx: float = 0.17 + 0.66 * t
		# stagger in depth: the ones behind sit higher and smaller, which is what makes
		# a row of identical shapes read as a group rather than as a fence
		var back: float = 0.0 if i % 2 == 0 else 0.13
		var s: float = (0.15 + 0.085 * bulk) * (1.0 - back * 0.85)
		var base: float = 1.0 - back
		out.append(ArtShapes.ellipse(cx, base - s * 1.45, s, s * 0.80))         # body
		out.append(ArtShapes.ellipse(cx, base - s * 2.45, s * 0.52, s * 0.46))  # head
		for leg in 4:
			var side: float = -1.0 if leg < 2 else 1.0
			var lx: float = cx + side * s * (0.35 + 0.42 * float(leg % 2))
			out.append(ArtShapes.taper(lx, base - s * 1.5, base,
				s * 0.11, s * 0.07, side * s * 0.55))
		if blade > 0.35:
			# Small, and springing SIDEWAYS from the jaw rather than upward. Drawn tall
			# they read as party hats, which is what the first capture showed.
			out.append([Vector2(cx - s * 0.45, base - s * 2.62),
				Vector2(cx - s * 1.05 - blade * 0.030, base - s * 2.72),
				Vector2(cx - s * 0.40, base - s * 2.30)])              # mandible
			out.append([Vector2(cx + s * 0.45, base - s * 2.62),
				Vector2(cx + s * 1.05 + blade * 0.030, base - s * 2.72),
				Vector2(cx + s * 0.40, base - s * 2.30)])
	return out

