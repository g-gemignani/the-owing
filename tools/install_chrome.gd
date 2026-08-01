## One-shot installer for the loose painted `ui/` files — the control chrome and the
## combat HUD.
##
##   godot --headless --script tools/install_chrome.gd -- <src_dir> [--dry]
##   godot --headless --import
##
## `install_cutouts.gd` cannot take these. It resolves a source filename to a
## CATALOGUE id — an archetype, a relic, a card — and there is no catalogue of
## chrome; the names here are the ones the game reaches for by hand
## (`PixelArt.ui_kit("checkbox_on")` and friends), so the table below IS the
## catalogue. Everything downstream of naming is shared: `cutout_lib.gd` does the
## matte, the despeckle and the trim, exactly as it does for a monster.
##
## **The filename is still the wiring** (D73). `ui_theme.gd` builds the theme from
## whatever `ui/<name>.png` happens to exist and silently skips what does not, which
## is what lets the kit arrive in pieces — and also what makes a typo invisible. A
## source under an unknown name is refused loudly here rather than dropped.
##
## Four things make a loose `ui/` file different from a monster, and each is a column:
##
## **CROP.** A generator asked for "a square socket of dark stone" paints the socket
## in a wall, because a wall is what a socket lives in. The matte cannot help: it
## refuses a subject-in-a-room by design (`BORDER_AGREE`), and it is right to — the
## wall is not background, it is the rest of the painting. So the recipe carries a
## rectangle, in fractions of the source, naming the part that is the widget. Only
## the two checkboxes still need one; every other crop here is the whole frame,
## because every other source came back on a field the way it was asked to.
##
## **MATTE.** Three files are installed opaque, and the reason is not the same one
## twice. A checkbox IS a square stone tile — matting it would leave the peg floating
## with the socket cut out from under it — so it keeps its rectangle, cropped to the
## tile's own mortar lines. `card_back` is a tablet that fills its frame edge to
## edge: there is no field to cut and no margin to crop. Everything else is an
## ordinary cutout. `slider_grabber` and `dropdown_arrow` were a fourth case until
## D112, opaque because they CANNOT be cut — both painted on a lit wall rather than
## on a field, only 14% of the slider's border agreeing with itself. That was a
## defect in the prompt, not in the matte (D105); the prompt was fixed, the re-rolls
## came back on a field, and they are cutouts now.
##
## **STRETCH.** `scrollbar_grabber` is used as a NINE-SLICE (`ui_theme.gd` slices it
## 8/8/8/8), so the art has to reach all four edges of its canvas or the slice
## margins bite into transparent gutter and the thumb renders thinner than its own
## bar. Aspect-preserving placement — right for an icon — is wrong for that one, so
## it stretches to fill.
##
## **GLOW.** A bloom is not a cutout and the matte is the wrong tool for it twice
## over: the field a bloom is painted on is black, and so is the outer end of the
## bloom's own falloff, so a flood fill at `TOL` walks up the gradient until it hits
## something bright enough to stop it and leaves a hard-edged disc — a ring, in the
## one asset whose entire job is to have no edge. So alpha comes from LUMINANCE
## instead, which is what a falloff already is, and the trim box comes with it.
## The colour is KEPT, unlike `cut_mono`: these are warm light, not tintable glyphs.
## RGB is left exactly as drawn rather than unpremultiplied, so the file is
## unchanged under the additive blend ART_ASSETS.md asks for and merely a slightly
## tighter glow under a normal one — dividing a near-black tail by its own alpha to
## recover "true" colour amplifies the noise down there into speckle.
extends SceneTree

const Cut := preload("res://tools/cutout_lib.gd")
const OUT := "res://assets/art/ui/"

## Every loose `ui/` file the game reaches for by name, with the recipe each needs.
##   canvas  — the size ART_ASSETS asks for, already 2x the 1280x720 layout
##   crop    — the part of the source that is the widget, in fractions of the source
##   matte   — cut the subject out of its field, or install the crop opaque
##   stretch — fill the canvas (nine-slice, backdrop, bloom), rather than fit inside
##             it (icon)
##   glow    — alpha from luminance instead of a matte; see GLOW above. Carried only
##             by the two files that are blooms, since it is the only column here
##             that does not vary across the rest.
var KIT := {
	"dropdown_arrow": {
		# Both of these were installed opaque on a hand-measured crop until D112,
		# because both had been painted onto a lit cave wall and the matte refuses a
		# subject-in-a-room by design: the chevron's darkest arm sat 0.049 from the
		# sampled field while the field's own worst border pixel sat at 0.143, so the
		# subject was CLOSER to the background than the background was to itself. That
		# is a defect in the prompt, not in the matte (D105), the prompt was fixed, and
		# the re-rolls came back on a flat field — so the crop rectangles are gone and
		# these are ordinary cutouts now.
		"canvas": Vector2i(32, 32),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": false,
	},
	"slider_grabber": {
		"canvas": Vector2i(48, 48),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": false,
	},
	"scrollbar_grabber": {
		"canvas": Vector2i(24, 48),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": true,
	},
	"checkbox_on": {
		# The raised block between the mortar lines. Both checkbox states take the SAME
		# rectangle — they are the same wall, and a crop that drifts between them is the
		# box jumping when it is ticked.
		"canvas": Vector2i(64, 64),
		"crop": Rect2(0.176, 0.161, 0.645, 0.654),
		"matte": false,
		"stretch": true,
	},
	"checkbox_off": {
		"canvas": Vector2i(64, 64),
		"crop": Rect2(0.176, 0.161, 0.645, 0.654),
		"matte": false,
		"stretch": true,
	},

	# --- the combat HUD (Tier 1b) and the card back (Tier 0) -------------------
	# Not chrome — `ui_theme.gd` never asks for these — but loose `ui/` paintings
	# with no catalogue behind them, which is the only thing this tool needs to be
	# true. They arrived as one batch and this is where a batch of loose `ui/` art
	# gets placed (D112).
	"energy_orb_full": {
		# An orb on a flat field: the ordinary cutout, and the only one of the six
		# that needs nothing special. Both orb states trim to their own bounding box
		# and fit the same canvas, which is what keeps the silhouette from jumping
		# when one is spent — the two sources do NOT draw the orb the same size.
		"canvas": Vector2i(128, 128),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": false,
	},
	"energy_orb_empty": {
		"canvas": Vector2i(128, 128),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": false,
	},
	"target_ring": {
		"canvas": Vector2i(256, 256),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": true,
		"stretch": false,
	},
	"orb_glow": {
		"canvas": Vector2i(192, 192),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": false,
		"stretch": true,
		"glow": true,
	},
	"card_glow": {
		# The trim is what makes this one land: the halo is painted inside its frame
		# with field to either side, so stretching the WHOLE frame onto the canvas
		# would keep that margin and hand back a halo narrower than the card it is
		# supposed to surround. Trimmed to the light itself, the halo takes the
		# card's own proportions. The luminance alpha also does the second job here
		# that a matte could not: this take paints the card's own dark slab inside
		# the rim, and the slab is DARKER than the field, so it clamps to fully
		# transparent and leaves the light standing on its own.
		"canvas": Vector2i(320, 448),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": false,
		"stretch": true,
		"glow": true,
	},
	"card_back": {
		# Opaque and stretched, because the tablet fills its source frame edge to
		# edge — there is no field to matte and no margin to crop, so the canvas can
		# only be reached by stretching. That is only safe because the source is
		# PORTRAIT: 864x1216 is 0.7105 against the card's 0.7143, half a percent, and
		# the stretch is invisible. The first take of this file came back square and
		# the same recipe would have drawn the sigil out 1.4x taller — which is what
		# the per-file size column in ART_PROMPTS.md now exists to prevent (D109).
		"canvas": Vector2i(320, 448),
		"crop": Rect2(0.0, 0.0, 1.0, 1.0),
		"matte": false,
		"stretch": true,
	},
}

var _dry := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dry = args.has("--dry")
	var positional: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			positional.append(String(a))
	if positional.is_empty():
		print("usage: -- <src_dir> [--dry]")
		quit(2)
		return
	var src: String = positional[0]
	if not src.ends_with("/"):
		src += "/"

	if not _dry:
		DirAccess.make_dir_recursive_absolute(Cut.abs_path(OUT))

	var wrote := 0
	var failed := 0
	var unmatched: Array[String] = []
	for path in Cut.sources(src):
		var name := path.get_file().get_basename().to_lower().replace("-", "_")
		if not KIT.has(name):
			unmatched.append(path.get_file())
			continue
		var spec: Dictionary = KIT[name]
		var img := Cut.load_image(path)
		if img == null:
			print("FAIL  could not read %s" % path.get_file())
			failed += 1
			continue
		var canvas: Vector2i = spec["canvas"]
		var note := _shape(img, spec)
		if note != "":
			print("FAIL  %-22s %s" % [path.get_file(), note])
			failed += 1
			continue
		if _dry:
			print("DRY   %-22s -> ui/%s.png  %dx%d" % [
				path.get_file(), name, canvas.x, canvas.y])
			continue
		if img.save_png(Cut.abs_path(OUT + name + ".png")) != OK:
			print("FAIL  writing ui/%s.png" % name)
			failed += 1
			continue
		var notes := ""
		if spec["matte"] and Cut.dropped_islands > 0:
			notes += "  (dropped %d stray island(s) — watermark or specks)" % Cut.dropped_islands
		print("  %-22s <- %-24s %dx%d%s" % [name + ".png", path.get_file(),
			canvas.x, canvas.y, notes])
		wrote += 1

	# A source nobody could place is the loud failure this tool exists for: the art
	# was made, and under that name the theme will never ask for it.
	if not unmatched.is_empty():
		print("\nUNMATCHED (%d) — these were NOT installed:" % unmatched.size())
		for u in unmatched:
			print("  %s" % u)
		print("  valid names: %s" % ", ".join(KIT.keys()))

	var missing: Array[String] = []
	for name in KIT:
		if not FileAccess.file_exists(Cut.abs_path(OUT + String(name) + ".png")):
			missing.append(String(name))
	print("\nwrote %d, failed %d, unmatched %d" % [wrote, failed, unmatched.size()])
	if missing.is_empty():
		print("every chrome cutout is installed")
	else:
		print("STILL MISSING (%d/%d): %s" % [
			missing.size(), KIT.size(), ", ".join(missing)])
	quit(1 if (failed > 0 or not unmatched.is_empty()) else 0)


## Crop, optionally matte, and land the result on its canvas, in place.
## Returns "" on success or the reason it was refused.
func _shape(img: Image, spec: Dictionary) -> String:
	var canvas: Vector2i = spec["canvas"]
	var crop: Rect2 = spec["crop"]
	if crop != Rect2(0.0, 0.0, 1.0, 1.0):
		var w := img.get_width()
		var h := img.get_height()
		var r := Rect2i(int(crop.position.x * w), int(crop.position.y * h),
			int(crop.size.x * w), int(crop.size.y * h))
		if r.size.x < 8 or r.size.y < 8:
			return "crop is %dx%d — nothing to install" % [r.size.x, r.size.y]
		img.copy_from(img.get_region(r))

	if spec.get("glow", false):
		return _glow(img, canvas)

	if not spec["matte"]:
		# Opaque by intent: the crop IS the widget. Stretched, it fills the canvas edge
		# to edge; unstretched it keeps its proportions and the canvas pads it out with
		# transparency, which is how a wide bar lands on a square icon slot without
		# being squashed into a block.
		if spec["stretch"]:
			img.resize(canvas.x, canvas.y, Image.INTERPOLATE_LANCZOS)
			return ""
		var s: float = minf(float(canvas.x) / float(img.get_width()),
			float(canvas.y) / float(img.get_height()))
		var nw := maxi(1, int(round(img.get_width() * s)))
		var nh := maxi(1, int(round(img.get_height() * s)))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
		var dst := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
		dst.fill(Color(0, 0, 0, 0))
		dst.blit_rect(img, Rect2i(0, 0, nw, nh),
			Vector2i((canvas.x - nw) / 2, (canvas.y - nh) / 2))
		img.copy_from(dst)
		return ""
	if not spec["stretch"]:
		return Cut.cut(img, canvas, false)

	# Matte, then FILL rather than fit. `Cut.place()` cannot do this — it preserves
	# aspect on purpose, because a stretched monster is a deformed monster. A
	# nine-sliced strip of iron is the one case where the deformation is the point.
	img.convert(Image.FORMAT_RGBA8)
	var w2 := img.get_width()
	var h2 := img.get_height()
	var a := Cut.alpha_of(img)
	if Cut.opaque_fraction(a) > 0.995:
		var reason := Cut.matte(img, a)
		if reason != "":
			return reason
	var kept := Cut.despeckle(a, w2, h2)
	Cut.dropped_islands = maxi(0, kept)
	if kept < 0:
		return "nothing opaque left after matting"
	var cover := Cut.opaque_fraction(a)
	if cover < Cut.MIN_COVER:
		return "only %.1f%% of the frame survived the matte — it ate the subject" % (cover * 100.0)
	if cover > Cut.MAX_COVER:
		return "%.1f%% of the frame survived — the matte found no background" % (cover * 100.0)
	Cut.erode_and_soften(a, w2, h2)
	Cut.apply_alpha(img, a)
	var box := Cut.bbox(a, w2, h2)
	if box.size.x <= 0 or box.size.y <= 0:
		return "empty bounding box"
	var sub := img.get_region(box)
	sub.resize(canvas.x, canvas.y, Image.INTERPOLATE_LANCZOS)
	img.copy_from(sub)
	return ""


## A bloom: alpha from luminance, colour kept, trimmed to the light and stretched to
## fill. See GLOW in the header for why this is not the matte.
func _glow(img: Image, canvas: Vector2i) -> String:
	img.convert(Image.FORMAT_RGBA8)
	var a := Cut.mono_alpha(img)
	if Cut.last_mono_range < Cut.MONO_MIN_RANGE:
		return "flat — there is no light in this image (dynamic range %.3f)" % Cut.last_mono_range
	Cut.apply_alpha(img, a)
	# No erode and no despeckle. Both exist to clean up a hard-thresholded matte;
	# here the edge is a gradient that is already correct, and the corner watermark
	# they would otherwise catch has to be gone BEFORE this point — `strip_sparkle.gd`
	# takes it, and a bloom's own falloff would hide a leftover stamp from the island
	# test by connecting it to the subject.
	var box := Cut.bbox(a, img.get_width(), img.get_height())
	if box.size.x <= 0 or box.size.y <= 0:
		return "empty bounding box — nothing above the black"
	var sub := img.get_region(box)
	sub.resize(canvas.x, canvas.y, Image.INTERPOLATE_LANCZOS)
	img.copy_from(sub)
	return ""
