## Installer for the level-progress overlays (Tier 3c, D132).
##
## These are not pictures, they are LIGHT. Each one is drawn over a finished card
## illustration or power sigil with `BLEND_MODE_ADD` and tinted to the rarity colour, so
## the file has three jobs the other installers never have to think about:
##
## * **Black must be actually black.** Under an additive blend a pixel of value 8 is not
##   "nearly invisible", it is a grey wash laid over the whole illustration underneath.
##   The capture path is a JPEG screenshot (the page will not hand over the PNG bytes,
##   and the canvas route that does is blocked), so the floor is subtracted and what
##   survives is rescaled back up rather than the image being used as it arrived. On the
##   captures so far that floor comes out at 1/255 — a big flat black field is the one
##   thing JPEG compresses almost perfectly — but it is measured every time rather than
##   assumed, because the cost of being wrong is a grey wash over every card.
## * **It must be monochrome.** The generator paints a warm white; warm white carries a
##   hue, and a hue fights the rarity tint that gets multiplied through it. Luminance
##   collapses it to one channel, which is what the tint expects.
## * **The four corners must be empty.** The cost and the damage are drawn over them
##   (D132). This is also, for free, where Gemini stamps its sparkle watermark — so the
##   corner clear is not a workaround for the watermark, it is a requirement the art has
##   to meet anyway, and the watermark happens to live inside it.
##
## Run: godot --headless --script tools/install_overlay.gd -- <src.jpg> <out_name> \
##          --rect=X,Y,W,H [--size=WxH] [--corner=0.16] [--floor=auto] [--gain=1.0] [--dry]
##
## `--rect` is the image's exact position in the screenshot, in SCREENSHOT pixels. It is
## required and not guessed: autocrop cannot find the edge of a black picture, which is
## why the capture puts a magenta field behind it and reads the rect off
## `getBoundingClientRect()` instead (D122's lesson, in the one case where it bites
## hardest).
##
## `--dry` measures and prints without writing, which is the only honest way to pick a
## floor — the numbers below decide whether a capture is usable, not the eye.
extends SceneTree

const OUT_DIR := "res://assets/art/fx/"

## `--floor=auto` measures THIS capture's own JPEG noise rather than applying a number
## carried over from another one, because there is nothing in the histogram to find: the
## glow fades continuously into the black, so sweeping the floor over 2..24 moves the lit
## fraction 15.1% -> 3.8% with no knee anywhere in it. Value alone cannot say where noise
## stops and paint starts.
##
## What CAN say is position. The brief promises the four corners are empty (D132), so
## whatever is in them is exactly the mush the JPEG added, and its upper reach is the
## floor. The 90th percentile rather than the maximum because Gemini's sparkle watermark
## sits in one of those corners — it is around 1.5% of the four boxes together, so a high
## percentile clears the noise and still passes under the stamp.
const NOISE_PERCENTILE := 0.90

## How far in from each corner the frame is forced to nothing, as a fraction of the
## shorter side, and how far past that the clear feathers out. A hard box would be
## invisible here anyway — it is cutting into black — but the feather costs nothing and
## keeps the clear from showing if a future capture puts glow nearer a corner.
const CORNER_HARD := 0.16
const CORNER_FEATHER := 0.09

## `--gain` scales the whole overlay down after the floor and before the corner clear.
## It exists because the one thing the generator cannot be asked for is a RELATION: each
## image is drawn in its own conversation with no sight of the others, so "a third dimmer
## than the ring you drew a minute ago" is not a prompt that can be written. The bands
## have to escalate (D132) and escalation is a comparison, so it is enforced here, on the
## measured `hiding` numbers, rather than hoped for three prompts in a row.
##
## Not a brightness taste dial: the only thing it is for is putting the bands in order.

## Where an additive overlay stops tinting the art under it and starts replacing it.
## Adding 0.5 takes any mid-tone to near-white, so at and above this the illustration is
## gone rather than coloured; below it, it shows through. The ceiling is what fraction of
## the frame may be that bright, and the maxed state is meant to be close to it — it is
## the one state that gets to be loud.
const HIDES_AT := 0.5
const HIDES_CEILING := 25.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: install_overlay.gd -- <src> <out_name> --rect=X,Y,W,H [--size=WxH] [--corner=F] [--floor=N|auto] [--gain=F] [--dry]")
		quit(1)
		return

	var src: String = args[0]
	var out_name: String = args[1]
	var rect := Rect2i()
	var have_rect := false
	var size := Vector2i(320, 240)
	var corner := CORNER_HARD
	var floor_arg := "auto"
	var gain := 1.0
	var dry := false

	for a in args.slice(2):
		if a.begins_with("--rect="):
			var p := a.trim_prefix("--rect=").split(",")
			if p.size() != 4:
				push_error("--rect wants X,Y,W,H")
				quit(1)
				return
			rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
			have_rect = true
		elif a.begins_with("--size="):
			var p2 := a.trim_prefix("--size=").split("x")
			size = Vector2i(int(p2[0]), int(p2[1]))
		elif a.begins_with("--corner="):
			corner = float(a.trim_prefix("--corner="))
		elif a.begins_with("--floor="):
			floor_arg = a.trim_prefix("--floor=")
		elif a.begins_with("--gain="):
			gain = float(a.trim_prefix("--gain="))
		elif a == "--dry":
			dry = true

	if not have_rect:
		push_error("--rect is required: a black picture has no findable edge to autocrop to")
		quit(1)
		return

	var shot := Image.load_from_file(src)
	if shot == null:
		push_error("cannot read %s" % src)
		quit(1)
		return

	# the rect comes from the page and the screenshot may be a hair smaller; clamp rather
	# than fail, but say so, because a rect that needed clamping usually means the scale
	# factor was computed against the wrong innerWidth
	var clamped := rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	if clamped != rect:
		print("NOTE  rect clamped %s -> %s against a %s screenshot" % [rect, clamped, shot.get_size()])
	if clamped.size.x < 16 or clamped.size.y < 16:
		push_error("rect leaves nothing to install")
		quit(1)
		return

	# a JPEG loads as RGB8 and `blit_rect` refuses to cross formats — silently, into an
	# all-zero destination, which reads downstream as "the capture is blank"
	shot.convert(Image.FORMAT_RGBA8)
	var cut := Image.create_empty(clamped.size.x, clamped.size.y, false, Image.FORMAT_RGBA8)
	cut.blit_rect(shot, clamped, Vector2i.ZERO)

	# --- to one channel -------------------------------------------------------------
	var w := cut.get_width()
	var h := cut.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			var c := cut.get_pixel(x, y)
			# Rec. 601 luminance: the paint is a warm white, and its hue is exactly what
			# must not survive into a file the game is going to tint
			lum[y * w + x] = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

	# --- pick the floor -------------------------------------------------------------
	var short_side := float(mini(w, h))
	var hard := corner * short_side
	var feather := (corner + CORNER_FEATHER) * short_side

	var flr := 0.0
	if floor_arg == "auto":
		var corner_px := Array()
		for y5 in h:
			for x5 in w:
				if _corner_gain(x5, y5, w, h, hard, feather) <= 0.0:
					corner_px.append(lum[y5 * w + x5])
		if corner_px.is_empty():
			push_error("--corner=%.2f leaves no corner to measure the noise in" % corner)
			quit(1)
			return
		corner_px.sort()
		flr = float(corner_px[int(float(corner_px.size() - 1) * NOISE_PERCENTILE)])
	else:
		flr = float(floor_arg) / 255.0

	# --- measure before deciding ----------------------------------------------------
	var peak := 0.0
	for v in lum:
		peak = maxf(peak, v)
	if peak <= flr + 0.02:
		push_error("nothing survives the floor: peak %.3f against floor %.3f — the capture is blank" % [peak, flr])
		quit(1)
		return

	var lit := 0
	var opaque := 0
	var corner_peak := 0.0
	for y2 in h:
		for x2 in w:
			var v2: float = lum[y2 * w + x2]
			if v2 > flr:
				lit += 1
			# against the value that will actually be in the file: measuring before the
			# gain reports a picture nobody is going to see, and the gain exists precisely
			# to move this number
			if clampf((v2 - flr) / (1.0 - flr), 0.0, 1.0) * gain > HIDES_AT:
				opaque += 1
			if _corner_gain(x2, y2, w, h, hard, feather) < 1.0:
				corner_peak = maxf(corner_peak, v2)

	var lit_f := 100.0 * float(lit) / float(w * h)
	var opaque_f := 100.0 * float(opaque) / float(w * h)
	print("%s  %dx%d  floor %.3f (%d/255)  peak %.3f  gain %.2f  lit %.1f%%  hiding %.1f%%  corner peak before clear %.3f" % [
		out_name, w, h, flr, int(flr * 255.0), peak, gain, lit_f, opaque_f, corner_peak])

	# An overlay that covers most of the frame is not an overlay, it is a curtain: the
	# illustration underneath has to stay readable through it (D132). Loud enough to
	# refuse rather than install and find out on the card.
	#
	# Judged on the HIDING fraction, not the lit one. The first guard here counted every
	# pixel above the noise floor and refused the maxed corona at 61%, which was the wrong
	# question asked precisely: most of that 61% is ray haze at 0.02-0.10, and haze that
	# faint tints the art rather than covering it. Measured across the three bands, above
	# the noise floor reads 10 / 16 / 53% and above the hiding level 0.3 / 1.3 / 18% — the
	# second is the one that tracks what the eye calls "I cannot see the card any more".
	if opaque_f > HIDES_CEILING:
		push_error("%.0f%% of this is bright enough to cover what it sits on — the art under it would not read" % opaque_f)
		quit(1)
		return

	# --- floor, rescale, clear the corners ------------------------------------------
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var span := 1.0 - flr
	for y3 in h:
		for x3 in w:
			var v3: float = (lum[y3 * w + x3] - flr) / span
			v3 = clampf(v3, 0.0, 1.0) * gain * _corner_gain(x3, y3, w, h, hard, feather)
			out.set_pixel(x3, y3, Color(v3, v3, v3, 1.0))

	out.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)

	# resampling can lift a corner back off zero; the corners are a hard promise, so they
	# are re-cleared at the final size rather than trusted through a filter
	var hard2 := corner * float(mini(size.x, size.y))
	var feather2 := (corner + CORNER_FEATHER) * float(mini(size.x, size.y))
	var worst_corner := 0.0
	for y4 in size.y:
		for x4 in size.x:
			var g := _corner_gain(x4, y4, size.x, size.y, hard2, feather2)
			if g < 1.0:
				var c4 := out.get_pixel(x4, y4)
				var v4 := c4.r * g
				out.set_pixel(x4, y4, Color(v4, v4, v4, 1.0))
				if g <= 0.0:
					worst_corner = maxf(worst_corner, v4)

	print("      -> %dx%d  corner peak after clear %.4f" % [size.x, size.y, worst_corner])

	if dry:
		print("      (dry run, nothing written)")
		quit(0)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := OUT_DIR + out_name + ".png"
	var err := out.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("cannot write %s (%d)" % [path, err])
		quit(1)
		return
	print("      wrote %s" % path)
	quit(0)


## 1.0 everywhere the frame is free, falling to 0.0 inside the corner boxes. Distance is
## taken per axis to the nearest corner so the clear is a rounded box rather than a disc:
## a disc large enough to reach a corner stamp eats the middle of the edges with it.
func _corner_gain(x: int, y: int, w: int, h: int, hard: float, feather: float) -> float:
	var dx := float(mini(x, w - 1 - x))
	var dy := float(mini(y, h - 1 - y))
	if dx >= feather or dy >= feather:
		return 1.0
	var gx := clampf((dx - hard) / maxf(feather - hard, 0.001), 0.0, 1.0)
	var gy := clampf((dy - hard) / maxf(feather - hard, 0.001), 0.0, 1.0)
	# inside the hard box on BOTH axes is a corner; inside on one axis only is an edge,
	# which stays lit
	return maxf(gx, gy)
