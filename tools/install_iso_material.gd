## Installs a PAINTED ground or wall material for the isometric floor (D267).
##
##   godot --headless --script tools/install_iso_material.gd -- \
##       <source.png|jpg> <role> [--crop=x,y,w,h] [--band=0.30] [--luma=0.49] [--dry]
##   godot --headless --import
##
## `role` is the file stem under `assets/art/iso/`: `floor_stone`, `rock_moss` and so on,
## the same keys `iso_run._surface()` asks for.
##
## ## Why this exists beside `tools/gen_iso_art.gd` rather than replacing it
##
## The generator's materials are correct and they are not painted. They are noise fields
## sampled from the backdrops' own floor band, so they agree with the paintings on COLOUR
## by construction (D34 applied to pixels) and on nothing else: no ink, no brush, no
## stonework. That was invisible for as long as every diamond crushed a whole 256px repeat
## into 116x58 — at that scale everything is noise. `GROUND_UV_TILES` fixed the scale and
## the gap became the loudest thing on the screen.
##
## So the generator stays as the fallback and as the palette authority, and this installs a
## painting over it for the terrains that have one. A checkout with neither still gets a
## floor; a checkout with only the generated one looks like it did before.
##
## ## Three things are done TO the painting, and each is a measurement rather than a taste
##
## **Seamless, by offset-and-blend.** `iso_run` does not tile these edge to edge — it
## UV-projects them across the grid, so the wrap lands INSIDE the floor wherever the period
## comes round. A generator cannot be asked for a torus-seamless painting and will not
## produce one. So B is the source shifted by half in both axes, which is continuous exactly
## where the source's seam is, and the two are mixed by a mask that falls to zero at the
## border: the border is entirely B, the middle is entirely A, and B's own seam lands in the
## middle where it contributes nothing. Measured with `gen_iso_art`'s own metric, printed
## against that generator's numbers so the two are comparable.
##
## **Normalised to a target mean luminance.** This is the one that is not cosmetic. Every
## constant on the floor — `TINT_OPEN`, `TINT_WALKED`, `LIGHT_DIM`, `LIGHT_LIT` — is a
## MULTIPLIER on the material, tuned against a generated one whose mean sits near 0.47. A
## painting half a stop darker walks straight through all of them and arrives as unlit rock:
## measured, the first painted crypt floor came back at 0.39 and the lit tiles were within a
## few percent of the walls. Rather than retune four constants per painting, the painting is
## brought to the number they were tuned against.
##
## **The sparkle is not stripped here.** A four-point star lands in a corner of most
## generations and it is a small bright island. On a full-bleed material there is no matte
## to drop it, so `tools/strip_sparkle.gd` is the answer, run BEFORE this — a bright island
## survives the blend and then gets normalised around, which shifts every other pixel.
extends SceneTree

const OUT := "res://assets/art/iso/"
const SIZE := 256
## What the generated materials measure, and therefore what every tint and light constant in
## `iso_run.gd` was tuned against. `gen_iso_art.gd` prints the live figure per terrain; this
## is the middle of the eight it writes.
const LUMA_TARGET := 0.47
## How far in from the border the wrap blend reaches, as a fraction of the width. Wide
## enough that a stone straddling the seam is crossed over rather than cut, narrow enough
## that the middle of the material is untouched paint.
const BAND := 0.30

static func _rgb_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

## The same seam metric `gen_iso_art.gd` prints, copied deliberately rather than shared:
## these are two tools that must produce COMPARABLE numbers, and a helper one of them
## imports from the other is a helper that can be changed for one caller's benefit.
static func seam(img: Image) -> float:
	var n := img.get_width()
	var s := 0.0
	for y in n:
		s += _rgb_dist(img.get_pixel(n - 1, y), img.get_pixel(0, y))
	for x in n:
		s += _rgb_dist(img.get_pixel(x, n - 1), img.get_pixel(x, 0))
	s /= float(n * 2)
	var interior := 0.0
	var pairs := 0
	for x in range(0, n - 1):
		for y in range(0, n, 8):
			interior += _rgb_dist(img.get_pixel(x, y), img.get_pixel(x + 1, y))
			pairs += 1
	for y in range(0, n - 1):
		for x in range(0, n, 8):
			interior += _rgb_dist(img.get_pixel(x, y), img.get_pixel(x, y + 1))
			pairs += 1
	interior /= float(maxi(1, pairs))
	return s / maxf(0.0001, interior)

static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

static func stats(img: Image) -> Array:
	var n := img.get_width()
	var sum := 0.0
	var sq := 0.0
	for y in n:
		for x in n:
			var l := _luma(img.get_pixel(x, y))
			sum += l
			sq += l * l
	var m: float = sum / float(n * n)
	return [m, sqrt(maxf(0.0, sq / float(n * n) - m * m))]

## Scale every channel by one factor so the mean luminance lands on `target`.
##
## A GAIN rather than a curve, on purpose. A gamma or a levels stretch would also hit the
## number and would change the ratio between the stones and the joints, which is the one
## thing the painting is being kept for. A gain moves everything and preserves it, and the
## only pixels it can hurt are ones that clip — which the brief already forbids by asking
## for nothing pure white.
static func normalise(img: Image, target: float) -> float:
	var m: float = stats(img)[0]
	if m <= 0.0001:
		return 1.0
	var k: float = target / m
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(minf(1.0, c.r * k), minf(1.0, c.g * k),
				minf(1.0, c.b * k), c.a))
	return k

## Mix the source with a half-period copy of itself, so the border is the copy and the
## middle is the source. See the header.
static func wrap_blend(src: Image, band: float) -> Image:
	var n := src.get_width()
	var half: int = n / 2
	var out := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var av := src.get_pixel(x, y)
			var bv := src.get_pixel((x + half) % n, (y + half) % n)
			var dx: float = clampf(float(mini(x, n - 1 - x)) / (band * float(n)), 0.0, 1.0)
			var dy: float = clampf(float(mini(y, n - 1 - y)) / (band * float(n)), 0.0, 1.0)
			var m: float = smoothstep(0.0, 1.0, dx) * smoothstep(0.0, 1.0, dy)
			out.set_pixel(x, y, av.lerp(bv, 1.0 - m))
	return out

static func _arg(args: Array, key: String, fallback: String) -> String:
	for a in args:
		var s := String(a)
		if s.begins_with(key):
			return s.substr(key.length())
	return fallback

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var free: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			free.append(String(a))
	if free.size() < 2:
		print("usage: -- <source> <role> [--crop=x,y,w,h] [--band=] [--luma=] [--dry]")
		quit(2)
		return

	var img := Image.load_from_file(ProjectSettings.globalize_path(free[0]))
	if img == null:
		print("cannot read %s" % free[0])
		quit(2)
		return
	img.convert(Image.FORMAT_RGBA8)

	# A browser capture carries page chrome around the picture, so the region is given
	# rather than searched for: autocrop trims a full-bleed material's own dark edges and
	# the only symptom is an aspect ratio nobody checks.
	var crop := _arg(args, "--crop=", "")
	if crop != "":
		var p := crop.split(",")
		img = img.get_region(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
	if img.get_width() != img.get_height():
		print("WARNING: source is %dx%d, not square — it will be squashed"
			% [img.get_width(), img.get_height()])
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)

	var before := stats(img)
	var band := float(_arg(args, "--band=", str(BAND)))
	var target := float(_arg(args, "--luma=", str(LUMA_TARGET)))
	var out := wrap_blend(img, band)
	var gain := normalise(out, target)
	var after := stats(out)

	print("=== install_iso_material ===%s" % ("  [dry run]" if "--dry" in args else ""))
	print("  source   %s" % free[0])
	print("  in       luma %.2f +/- %.2f   seam %.2fx" % [before[0], before[1], seam(img)])
	print("  band %.2f  gain %.2fx" % [band, gain])
	print("  %-14s luma %.2f +/- %.2f   seam %.2fx"
		% [free[1] + ".png", after[0], after[1], seam(out)])
	if "--dry" in args:
		quit(0)
		return
	var path := OUT + free[1] + ".png"
	if out.save_png(ProjectSettings.globalize_path(path)) != OK:
		print("  FAILED to write %s" % path)
		quit(1)
		return
	print("  wrote %s — run `godot --headless --import`" % path)
	quit(0)
