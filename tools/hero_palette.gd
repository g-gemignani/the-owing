## Pull the eight hero paintings onto one palette, without repainting any of them.
##
##     godot --headless --script tools/hero_palette.gd --check          # measure, change nothing
##     godot --headless --script tools/hero_palette.gd --out=/tmp/hero  # write corrected copies
##     godot --headless --script tools/hero_palette.gd --install        # overwrite the art
##
## Idempotent: a second run corrects by x1.000 and moves nothing, because the target is
## measured off the files each time.
##
## ## The two faults
##
## The cycle is eight separately generated images of one character, and a generator holds a
## palette loosely. Measured on the installed art over the cloak — every pixel at saturation
## 0.35 or more — before this tool was written:
##
##     file        hue   sat   value at the 90th percentile
##     hero_s       60   0.58   0.745
##     hero_s_a     63   0.60   0.773
##     hero_s_p     54   0.59   0.663      <- 12% darker than its own siblings
##     hero_s_b     59   0.59   0.753
##     hero_n       53   0.69   0.714
##     hero_n_a     54   0.68   0.753
##     hero_n_p     45   0.65   0.671      <- 11% darker
##     hero_n_b     52   0.68   0.761
##
## **The passing frame is underexposed in both facings.** That is one frame in four on the
## figure the player watches longest, so she pulses darker twice per two steps.
##
## **And the passing frames wear different clothes.** Their tunic and trousers are green where
## every other frame paints warm tan — 1,664 pixels, 19% of the figure, against essentially
## none on `hero_s`. That is not a grade, it is a different garment, and it is the half a
## player actually notices.
##
## ## Why a transform and not a repaint
##
## A fresh generation is a fresh sample from the same loose palette: it fixes this frame and
## moves another, and the geometry has to be re-anchored afterwards (D317). `install_sheet.gd
## --luma=N` and the saturation band in `install_card_sheet.gd` are the same idea already in
## this repository — generate loosely, then correct to a measured target.
##
## ## Two things this deliberately does NOT do, both learned by looking at the output
##
## **It does not match hue.** The obvious companion to the exposure fix, and it makes things
## worse. A file's mean cloak hue is dragged down by its shadowed folds, so `hero_n_p` reads 45
## degrees against its siblings' 52-54 — and rotating it +8 to agree overshoots the LIT
## surface, which was already gold, straight into yellow-green. The frame came out further from
## its siblings than it started, with every number in the report improved.
##
## **It does not match saturation across the two facings.** The north set measures 0.09 more
## saturated than the south set, and that is the art working: the back of a cloak in full light
## IS more saturated than the front, which is mostly shaded inner folds. Pulling them together
## turned the whole north set a flat pale yellow.
##
## Both versions were rendered and looked at before being thrown away. **The measurement said
## the eight files disagreed; only the picture said which disagreements were the painting doing
## its job.** That is the standing rule for this tool: change nothing here without rendering the
## before-and-after and looking at it.
extends SceneTree

const ART := "res://assets/art/iso/"
const FILES := ["hero_s", "hero_s_a", "hero_s_p", "hero_s_b",
	"hero_n", "hero_n_a", "hero_n_p", "hero_n_b"]
## What counts as the cloak. Everything in the table above is measured at this threshold.
const CLOAK_SAT := 0.35
## Where the exposure is read. The MEDIAN value is not comparable between the two facings — the
## front shows shaded inner folds and the back is all lit outer surface, so the front reads 0.36
## against the back's 0.60 with both correctly exposed. The 90th percentile is the lit surface
## in both, and that is the number that flickers.
const V_PCT := 0.9
## Each facing is corrected to the median of its three AGREEING frames: the idle and the two
## contacts. The passing frame is the outlier in both sets, so it is kept out of the target it
## is about to be corrected to — averaging it in would drag the target a third of the way
## toward the fault.
const FACINGS := {"hero_s": ["hero_s", "hero_s_a", "hero_s_b"],
	"hero_n": ["hero_n", "hero_n_a", "hero_n_b"]}

## The green garment, and where it goes.
##
## A hue band with a saturation CEILING, and the ceiling is what makes it safe. The cloak lives
## in the same 35-70 degree band and never falls below 0.35 saturation even in its deepest
## folds, so a ceiling of 0.30 cannot reach it — which is why the corrected frame comes out
## with a gold cloak over tan clothes rather than brown all over.
##
## Applied to all eight files rather than to the two that need it. Not laziness: a rule that
## names its own exceptions is a rule that will be wrong the day a ninth file arrives, and this
## one is measurably a no-op on the other six.
const GARMENT_LO := 35.0
const GARMENT_HI := 70.0
const GARMENT_SAT := 0.30
## `hero_s` paints the same cloth at 10-20 degrees and 0.40 saturation, against the green's
## 0.18-0.25, so the band is rotated to 18 and lifted by a third.
const GARMENT_TO := 18.0
const GARMENT_SAT_GAIN := 1.35


func _init() -> void:
	var out_dir := ""
	var install := false
	var check := false
	for a in OS.get_cmdline_args():
		var s := String(a)
		if s.begins_with("--out="):
			out_dir = s.substr(6)
		elif s == "--install":
			install = true
		elif s == "--check":
			check = true
	# A plain run does NOTHING. Every tool in here that writes over painted art has cost a
	# `git checkout` at least once, and the one that cost most was run in order to READ a
	# number off the art it then overwrote.
	if not (check or install or out_dir != ""):
		print("nothing to do. pass --check, --out=DIR or --install")
		quit(2)
		return
	if install:
		out_dir = ProjectSettings.globalize_path(ART)
	elif out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)

	var target := {}
	for facing in FACINGS:
		var vs: Array = []
		for nm in FACINGS[facing]:
			var im := _load(String(nm))
			if im != null:
				vs.append(_exposure(im))
		if vs.is_empty():
			continue
		vs.sort()
		target[facing] = float(vs[vs.size() / 2])
		print("target %s: v90 %.3f  (median of %s)" % [facing, target[facing], FACINGS[facing]])

	print("%-10s  v90 before -> after   exposure   garment px" % "file")
	for nm in FILES:
		var img := _load(nm)
		if img == null:
			print("%-10s  MISSING" % nm)
			continue
		var was := _exposure(img)
		var key := "hero_n" if nm.begins_with("hero_n") else "hero_s"
		var gain: float = float(target.get(key, was)) / maxf(0.01, was)
		var clipped := 0
		var moved := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				# Multiplicative, so every pixel keeps its place in the shading: the darkest
				# fold stays the darkest fold. An additive lift would flatten the modelling.
				var v: float = c.v * gain
				if v > 1.0:
					clipped += 1
				var h: float = c.h
				var sat: float = c.s
				var deg: float = c.h * 360.0
				if c.s < GARMENT_SAT and deg >= GARMENT_LO and deg <= GARMENT_HI:
					h = GARMENT_TO / 360.0
					sat = c.s * GARMENT_SAT_GAIN
					moved += 1
				img.set_pixel(x, y, Color.from_hsv(
					fposmod(h, 1.0), clampf(sat, 0.0, 1.0), clampf(v, 0.0, 1.0), c.a))
		print("%-10s  %.3f -> %.3f       x%.3f     %5d%s" % [
			nm, was, _exposure(img), gain, moved,
			"   (%d px clipped)" % clipped if clipped > 0 else ""])
		if out_dir != "":
			img.save_png(out_dir.path_join(nm + ".png"))
	if out_dir != "":
		print("\nwritten to %s" % out_dir)
	quit()


func _load(stem: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART + stem + ".png"))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## The cloak's value at `V_PCT`: how bright this painting's lit surface is.
func _exposure(img: Image) -> float:
	var vs: Array = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a >= 0.5 and c.s >= CLOAK_SAT:
				vs.append(c.v)
	if vs.is_empty():
		return 0.0
	vs.sort()
	return float(vs[int(float(vs.size() - 1) * V_PCT)])
