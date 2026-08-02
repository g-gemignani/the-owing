## Pull one hue band of a painting into another, in place.
##
##   godot --headless --script tools/regrade.gd -- <file.png> [--dry]
##   godot --headless --import
##
## Built for one measured defect and kept general enough to be re-run: the title
## backdrop came back **41.5% green** against a style bible (`bg_crypt.png`, attached
## to every generation request) that is **0.0% green**. The cause was not the palette
## line — the style block says "cool desaturated violet-grey stone base, ONE saturated
## light source" on every request — it was the subject line asking for "a valley of
## firs". A concrete noun beats an adjective, which is D101 and D108 in a third place,
## and the brief is fixed alongside this (D134).
##
## **Why grade rather than re-roll.** The composition took three attempts to land:
## the traveller and the flame right of centre, the left third quiet under the text
## column, the fortress far off. Only the hue is wrong. A re-roll spends that to fix
## something an arithmetic operation fixes exactly.
##
## **It refuses to run twice.** A grade is not idempotent — applied to its own output
## it would walk the hue further every time — so it measures the band first and exits
## saying so if the band is already empty. That is what makes it safe to leave in a
## script somebody re-runs after the next re-roll.
extends SceneTree

## The band to move, in degrees. 70-160 is yellow-green through teal-green.
const FROM_LO := 70.0
const FROM_HI := 160.0
## Where it lands. DESCENDING on purpose: the tealest greens (160) go to blue (235)
## and stay nearest the cyan flame they sit beside, while the yellow-greens (70) go
## furthest, to violet (275). Mapping ascending would have swapped them and put the
## forest's warm edge next to the one saturated light source in the frame.
const TO_AT_LO := 275.0
const TO_AT_HI := 235.0
## Saturation multiplier for moved pixels. The rule is one saturated light source and
## everything else in deep shadow, so the forest becomes cool desaturated stone rather
## than a blue forest — a saturated blue mass would be the same defect in a new hue.
const SAT := 0.45
## Below this share of the frame the band is not a subject and the file is left alone.
const ALREADY := 0.03

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dry := args.has("--dry")
	var path := ""
	for a in args:
		if not String(a).begins_with("--"):
			path = String(a)
	if path == "":
		print("usage: -- <file.png> [--dry]")
		quit(2); return

	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	var im := Image.new()
	if im.load(abs) != OK:
		print("cannot read %s" % path)
		quit(2); return
	im.convert(Image.FORMAT_RGBA8)

	var w := im.get_width()
	var h := im.get_height()
	var hits := 0
	for y in h:
		for x in w:
			if _in_band(im.get_pixel(x, y)):
				hits += 1
	var share := float(hits) / float(w * h)
	print("%s: %.1f%% of the frame is in the %.0f-%.0f band" % [
		path.get_file(), 100.0 * share, FROM_LO, FROM_HI])
	if share < ALREADY:
		print("already inside the palette — nothing to do")
		quit(0); return
	if dry:
		print("dry run, nothing written")
		quit(0); return

	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if not _in_band(c):
				continue
			var t := (c.h * 360.0 - FROM_LO) / (FROM_HI - FROM_LO)
			var nh := lerpf(TO_AT_LO, TO_AT_HI, t)
			im.set_pixel(x, y, Color.from_hsv(nh / 360.0, c.s * SAT, c.v, c.a))
	if im.save_png(abs) != OK:
		print("FAIL writing %s" % path)
		quit(2); return
	print("regraded %d px -> %.0f-%.0f at %.0f%% saturation" % [
		hits, TO_AT_HI, TO_AT_LO, SAT * 100.0])
	quit(0)

## Saturated enough to read as a colour, and inside the band. The saturation floor
## matters: a near-grey pixel has a meaningless hue, and rotating it would tint the
## stone the scrim and the text sit on.
func _in_band(c: Color) -> bool:
	if c.s < 0.18:
		return false
	var deg := c.h * 360.0
	return deg >= FROM_LO and deg < FROM_HI
