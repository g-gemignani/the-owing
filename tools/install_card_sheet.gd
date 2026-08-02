## Installer for Tier 3b card illustrations delivered as a GRID.
##
## One card at a time is a hundred generations; four cards in a 2x2 is twenty-five, and
## four 4:3 cells tile exactly into one 4:3 picture, so the grid costs nothing in shape.
## That is the whole reason this exists next to `install_sheet.gd` — that one mattes,
## trims and anchors CUTOUTS on a flat field, and every one of those steps is wrong for a
## full-bleed painting whose edges are supposed to run to the frame.
##
## Run: godot --headless --script tools/install_card_sheet.gd -- <src.jpg> \
##          --rect=X,Y,W,H --ids=a,b,c,d [--cols=2] [--rows=2] [--inset=6] \
##          [--sat=N] [--luma=N] [--dry]
##
## `--ids` is in reading order and every id is checked against `PixelArt.card_ids()`
## before anything is written. The filename IS the wiring (D73): `cards/<card_id>.png` is
## what `PixelArt.painted_card_art` looks for ahead of the family picture, so an id typed
## wrong here does not fail, it silently keeps the family art and looks exactly like art
## that was never made (D122).
##
## `--inset` drops a few pixels off each cell's edge. The brief says no dividing lines and
## the generator draws them anyway — a dark seam a couple of pixels wide where two cells
## meet. Insetting is cheaper and more reliable than asking again, and a full-bleed
## painting loses nothing at its extreme edge.
extends SceneTree

const ART := "res://assets/art/"
const OUT := "cards/"
const CARD_SIZE := Vector2i(320, 240)

## The style band, measured off the twelve family illustrations already installed rather
## than chosen, and measured ONLY WHERE THERE IS LIGHT. `(max-min)/max` is unstable in
## the dark — a pixel of (10,9,8) is grey to any eye and scores 0.20 — so on paintings
## that are deliberately mostly shadow the plain average reports colour that is not
## there. The first version of this file did exactly that and ranked the cells backwards:
## it passed a cell at 23.5% colourful and refused one at 37.8%, because both were within
## noise of each other once the black was included. Ignoring everything under `LUMA_FLOOR`
## separates them.
##
## What the numbers say once the black is dropped:
##
##     family attack / block / heal   sat 0.34 / 0.34 / 0.24   colourful 100 / 100 / 68%
##     bg_crypt.png (the style bible) sat 0.535                colourful  99.9%
##     greyscale comic-page sheet     sat 0.171                colourful  24.5%
##     flooded-with-colour sheet      sat 0.46-0.67            colourful  85-100%
##
## So the two failures are distinguishable and they are different failures: the greyscale
## one is short of colour everywhere, the flooded one has the right REACH of colour and
## far too much of it. That matters, because the second is rescuable by `--sat` and the
## first is not — scaling up the saturation of a grey page just amplifies its JPEG noise.
const LUMA_FLOOR := 0.18       # below this there is not enough light to call a pixel coloured
const COLOURFUL_AT := 0.20     # saturation at which a lit pixel counts as carrying colour
const SAT_MIN := 0.20
const SAT_MAX := 0.42
const COLOURFUL_MIN := 0.55    # heal.png, the least colourful thing already shipped, is 0.68
const LUMA_MIN := 0.10
const LUMA_MAX := 0.45

## `--luma` is the same idea as `--sat`, for the axis that drifts second. Over a run in one
## chat the generator slides toward bright, flat compositions — two sheets in a row came
## back as objects laid against a lit stone wall at 0.394 and 0.401 against a family band
## of 0.149 to 0.308 — and, like saturation, it has no dial between "too dark" and "too
## bright" that a prompt can reach reliably.
##
## It only ever DARKENS. Scaling an over-bright painting down is exposure; scaling a dark
## one up lifts JPEG noise out of the shadows, which is the same asymmetry `--sat` has and
## for the same reason. A cell that came back too dark is a re-roll, not a correction.
const LUMA_TARGET_MAX := 1.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: install_card_sheet.gd -- <src> --rect=X,Y,W,H --ids=a,b,c,d [--cols=2] [--rows=2] [--inset=6] [--sat=N] [--dry]")
		quit(1)
		return

	var src: String = args[0]
	var rect := Rect2i()
	var have_rect := false
	var ids: Array = []
	var cols := 2
	var rows := 2
	var inset := 6
	var sat_target := -1.0
	var luma_target := -1.0
	var dry := false

	for a in args.slice(1):
		if a.begins_with("--rect="):
			var p := a.trim_prefix("--rect=").split(",")
			if p.size() != 4:
				push_error("--rect wants X,Y,W,H")
				quit(1)
				return
			rect = Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3]))
			have_rect = true
		elif a.begins_with("--ids="):
			ids = Array(a.trim_prefix("--ids=").split(","))
		elif a.begins_with("--cols="):
			cols = int(a.trim_prefix("--cols="))
		elif a.begins_with("--rows="):
			rows = int(a.trim_prefix("--rows="))
		elif a.begins_with("--inset="):
			inset = int(a.trim_prefix("--inset="))
		elif a.begins_with("--sat="):
			sat_target = float(a.trim_prefix("--sat="))
		elif a.begins_with("--luma="):
			luma_target = float(a.trim_prefix("--luma="))
		elif a == "--dry":
			dry = true

	if not have_rect:
		push_error("--rect is required")
		quit(1)
		return
	if ids.size() != cols * rows:
		push_error("--ids has %d entries for a %dx%d grid, which wants %d" % [ids.size(), cols, rows, cols * rows])
		quit(1)
		return

	# Every id checked BEFORE a single file is written: a half-installed sheet with one
	# wrong name is worse than a refused one, because the wrong name is the invisible
	# failure and the other three look like success.
	var known := PixelArt.card_ids()
	var bad: Array = []
	for cid in ids:
		if not known.has(String(cid)):
			bad.append(cid)
	if not bad.is_empty():
		push_error("not card ids: %s" % ", ".join(bad))
		quit(1)
		return

	var shot := Image.load_from_file(src)
	if shot == null:
		push_error("cannot read %s" % src)
		quit(1)
		return
	shot.convert(Image.FORMAT_RGBA8)

	var clamped := rect.intersection(Rect2i(Vector2i.ZERO, shot.get_size()))
	if clamped != rect:
		print("NOTE  rect clamped %s -> %s" % [rect, clamped])

	var cw := int(clamped.size.x / cols)
	var ch := int(clamped.size.y / rows)
	var fails := 0
	var pending: Array = []

	for r in rows:
		for c in cols:
			var idx := r * cols + c
			var cid := String(ids[idx])
			var cell := Rect2i(
				clamped.position.x + c * cw + inset,
				clamped.position.y + r * ch + inset,
				cw - inset * 2, ch - inset * 2)

			var cut := Image.create_empty(cell.size.x, cell.size.y, false, Image.FORMAT_RGBA8)
			cut.blit_rect(shot, cell, Vector2i.ZERO)
			cut = _to_four_three(cut)

			if sat_target > 0.0:
				_scale_saturation(cut, sat_target)
			if luma_target > 0.0:
				_darken_to(cut, luma_target)

			var m := _measure(cut)
			var why := ""
			if m.sat < SAT_MIN or m.colourful < COLOURFUL_MIN:
				why = "greyscale — the colour did not survive the grid"
			elif m.sat > SAT_MAX:
				why = "flooded with colour — the one light source became a wash (try --sat)"
			elif m.luma < LUMA_MIN:
				why = "too dark to read"
			elif m.luma > LUMA_MAX:
				why = "too bright for the palette"

			print("%-22s sat %.3f  colourful %5.1f%%  lit %5.1f%%  luma %.3f  %s" % [
				cid, m.sat, 100.0 * m.colourful, 100.0 * m.lit, m.luma,
				"REFUSED: " + why if why != "" else "ok"])
			if why != "":
				fails += 1
				continue

			cut.resize(CARD_SIZE.x, CARD_SIZE.y, Image.INTERPOLATE_LANCZOS)
			pending.append([cid, cut])

	# Refusing the whole sheet because one cell is wrong is D122's mistake in a new place:
	# `install_backdrops.gd` used to fail a nine-file delivery because a re-roll only
	# answered one row, which read as eight failures. A cell that is too dark is a QUALITY
	# fault and belongs to that cell alone, so the good ones install and the bad ones are
	# named for a re-roll. The id check above stays atomic, because a wrong NAME is the
	# invisible failure — the file lands somewhere plausible and looks like art that was
	# never made — and that is worth blocking the batch for.
	if fails > 0:
		print("%d of %d cells refused and are left for a re-roll" % [fails, ids.size()])
	if pending.is_empty():
		push_error("every cell refused — fix the sheet, not the tool")
		quit(1)
		return

	if dry:
		print("(dry run, %d cells would be written)" % pending.size())
		quit(0)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ART + OUT))
	for pair in pending:
		var path := ART + OUT + String(pair[0]) + ".png"
		var err := (pair[1] as Image).save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("cannot write %s (%d)" % [path, err])
			quit(1)
			return
		print("wrote %s" % path)
	quit(0)


## Centre-crop to 4:3. A 2x2 out of a 4:3 sheet is already 4:3 to within a pixel, but the
## generator picks its own output size and has handed back both 1024x1024 and 1024x765 for
## the same words, so the shape is enforced here rather than assumed.
func _to_four_three(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var want := float(CARD_SIZE.x) / float(CARD_SIZE.y)
	var have := float(w) / float(h)
	if absf(have - want) < 0.01:
		return im
	var nw := w
	var nh := h
	if have > want:
		nw = int(round(float(h) * want))
	else:
		nh = int(round(float(w) / want))
	var out := Image.create_empty(nw, nh, false, Image.FORMAT_RGBA8)
	out.blit_rect(im, Rect2i(int((w - nw) / 2.0), int((h - nh) / 2.0), nw, nh), Vector2i.ZERO)
	return out


## Pull the whole cell toward a target mean saturation, keeping hue and value. This is a
## rescue for a sheet that is otherwise right — the subjects are correct and the drawing
## is good, only the colour is too hot — because a re-roll costs a generation against a
## daily cap and does not reliably come back better. It cannot fix composition: a quarter
## flooded with orange light is still lit wrong after the orange is taken out of it, so
## the refusal above stays and this runs before it, not instead of it.
func _scale_saturation(im: Image, target: float) -> void:
	var m := _measure(im)
	if m.sat <= 0.001:
		return
	var k := clampf(target / m.sat, 0.0, 4.0)
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			if mx <= 0.001:
				continue
			im.set_pixel(x, y, Color(
				clampf(mx + (c.r - mx) * k, 0.0, 1.0),
				clampf(mx + (c.g - mx) * k, 0.0, 1.0),
				clampf(mx + (c.b - mx) * k, 0.0, 1.0), 1.0))


## Pull an over-bright cell down to a target mean luminance. Never up: see LUMA_TARGET_MAX.
func _darken_to(im: Image, target: float) -> void:
	var m := _measure(im)
	if m.luma <= 0.001:
		return
	var k := minf(target / m.luma, LUMA_TARGET_MAX)
	if k >= 0.999:
		return
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			im.set_pixel(x, y, Color(
				clampf(c.r * k, 0.0, 1.0),
				clampf(c.g * k, 0.0, 1.0),
				clampf(c.b * k, 0.0, 1.0), 1.0))


## Saturation and colour reach measured only among pixels bright enough for colour to be
## visible, plus mean luminance over the whole cell. See the band above for why the luma
## floor is the difference between a metric that works and one that ranks cells backwards.
func _measure(im: Image) -> Dictionary:
	var lit := 0
	var sat := 0.0
	var hi := 0
	var luma := 0.0
	var n := im.get_width() * im.get_height()
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			luma += l
			if l < LUMA_FLOOR:
				continue
			var mx: float = maxf(c.r, maxf(c.g, c.b))
			var mn: float = minf(c.r, minf(c.g, c.b))
			var sv := 0.0 if mx <= 0.001 else (mx - mn) / mx
			sat += sv
			if sv > COLOURFUL_AT:
				hi += 1
			lit += 1
	if lit == 0:
		return {"sat": 0.0, "colourful": 0.0, "luma": luma / float(n), "lit": 0.0}
	return {"sat": sat / float(lit), "colourful": float(hi) / float(lit),
		"luma": luma / float(n), "lit": float(lit) / float(n)}
