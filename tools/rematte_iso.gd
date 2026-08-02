## Repairs an installed iso figure whose matte ate the subject, from the subject that is
## still in the file (D152).
##
## The five broken sprites did not need repainting, and that is the whole reason this tool
## exists rather than a new art order. `cutout_lib.apply_alpha` writes alpha and leaves RGB
## alone, so a pixel the flood fill "removed" is still there in full colour underneath —
## and 85% of the transparent pixels in `event.png` carried paint. What was destroyed was
## the mask, not the painting. So the repair is to throw the mask away and cut it again with
## the fill that now knows to stop where the paint starts (`cutout_lib.STD_FLAT`).
##
##   godot --headless --script tools/rematte_iso.gd [-- --dry]
##   godot --headless --import
##
## Deterministic and idempotent in the way that matters: run it on a file it already fixed
## and the recovered mask is the same mask, so the coverage gain is zero and the file is
## left alone. Nothing is written unless the subject grows.
extends SceneTree

const DIR := "res://assets/art/iso/"
const Cut := preload("res://tools/cutout_lib.gd")
## Iso figures and furniture are 128x192, footed — the same numbers `install_sheet.gd`
## installs them at, because this rewrites what that tool wrote.
const CANVAS := Vector2i(128, 192)
## How much of the region the two masks have to DISAGREE about before the file is rewritten,
## in percent. Below it the old mask was already right and the file is left byte-identical.
##
## Disagreement rather than a coverage gain, and that is not a refinement: the fire's old mask
## was 4.8 points LARGER than the correct one, because what it had kept was a rim of
## background. A one-sided "did the subject grow" test reads that as a regression and leaves
## the defect in place, which is exactly what it did on the first run of this tool.
const MIN_CHANGE := 2.0
## A pixel counts as painted for the crop below if its alpha survives OR it still carries
## colour under a cleared alpha. 12 rather than 0 because the padding `place` composites
## onto is exactly transparent black and JPEG-ish ringing around it is not.
const PAINT_FLOOR := 12

func _init() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	var names := _figures()
	if names.is_empty():
		print("no iso figures found in %s" % DIR)
		quit(1)
		return
	print("=== rematte iso figures (%d) ===%s" % [names.size(), "  [dry run]" if dry else ""])
	print("%-16s %8s %8s %7s %8s  %s" % [
		"file", "before", "after", "gain", "changed", "verdict"])

	var fixed := 0
	var skipped := 0
	var refused := 0
	for name in names:
		var path: String = DIR + name + ".png"
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			print("%-16s %s" % [name, "FAILED to load"])
			refused += 1
			continue
		img.convert(Image.FORMAT_RGBA8)

		# Crop to the paint before re-cutting. The canvas has transparent padding around
		# the blitted subject, and forcing that opaque would hand `matte` a black frame
		# border to sample as the field — after which the fill removes the padding it was
		# already going to remove and leaves the actual background untouched, as subject.
		var box := _paint_box(img)
		# Both coverages are of the SAME region: the paint that is in the file.
		var before := _cover_region(img, box)
		if box.size.x <= 2 or box.size.y <= 2:
			print("%-16s %8.1f%% %8s %7s  no paint under the mask — cannot repair here" % [
				name, before, "-", "-"])
			refused += 1
			continue
		var crop := img.get_region(box)
		_make_opaque(crop)

		# `cut()`'s own sequence, run step by step, because the measurement that decides
		# whether to rewrite has to be taken in the MIDDLE of it. Coverage after `place`
		# is not comparable to coverage before: `place` trims to the new bounding box and
		# scales it to fit, so a mask that recovered a tall thin subject reports LESS of
		# the canvas than the broken mask did — on the first attempt that read as five
		# regressions and four false repairs, and the four were bounding boxes moving.
		var a := Cut.alpha_of(crop)
		var reason := Cut.matte(crop, a)
		if reason != "":
			print("%-16s %8.1f%% %8s %7s  refused: %s" % [name, before, "-", "-", reason])
			refused += 1
			continue
		Cut.despeckle(a, crop.get_width(), crop.get_height())
		var after := _cover_of(a)
		var gain := after - before
		var changed := _disagreement(img, box, a)
		if changed < MIN_CHANGE:
			print("%-16s %8.1f%% %8.1f%% %+7.1f %7.1f%%  left alone" % [
				name, before, after, gain, changed])
			skipped += 1
			continue
		if dry:
			print("%-16s %8.1f%% %8.1f%% %+7.1f %7.1f%%  would rewrite (%d pockets filled)" % [
				name, before, after, gain, changed, Cut.filled_pockets])
			fixed += 1
			continue
		Cut.feather_edge(crop, a, Cut.last_field, crop.get_width(), crop.get_height())
		Cut.despeckle(a, crop.get_width(), crop.get_height())
		Cut.apply_alpha(crop, a)
		var placed := Cut.place(crop, a, CANVAS, true)
		if placed != "":
			print("%-16s %8.1f%% %8.1f%% %+7.1f  refused: %s" % [name, before, after, gain, placed])
			refused += 1
			continue
		if crop.save_png(ProjectSettings.globalize_path(path)) != OK:
			print("%-16s %8.1f%% %8.1f%% %+7.1f  FAILED to write" % [name, before, after, gain])
			refused += 1
			continue
		print("%-16s %8.1f%% %8.1f%% %+7.1f %7.1f%%  REPAIRED (%d pockets filled)" % [
			name, before, after, gain, changed, Cut.filled_pockets])
		fixed += 1

	print("\n%d repaired, %d already fine, %d refused" % [fixed, skipped, refused])
	if not dry and fixed > 0:
		print("Run `godot --headless --import`, then tests/run.sh.")
	quit(1 if refused > 0 else 0)

## Every figure in the iso directory. `floor*` and `rock*` are computed materials with no
## alpha at all and nothing to matte.
func _figures() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".png") and not f.begins_with("floor") and not f.begins_with("rock"):
			out.append(f.get_basename())
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## What fraction of `box` is opaque in `img`, as a percentage.
func _cover_region(img: Image, box: Rect2i) -> float:
	if box.size.x <= 0 or box.size.y <= 0:
		return 0.0
	var n := 0
	for y in range(box.position.y, box.position.y + box.size.y):
		for x in range(box.position.x, box.position.x + box.size.x):
			if img.get_pixel(x, y).a * 255.0 > float(Cut.ALPHA_CUT):
				n += 1
	return float(n) / float(box.size.x * box.size.y) * 100.0

## How much the old and new masks disagree about, as a percentage of the region. Opacity is
## read as in-or-out on both sides: a feathered edge moving by a few levels is not a repair.
func _disagreement(img: Image, box: Rect2i, a: PackedByteArray) -> float:
	if box.size.x <= 0 or box.size.y <= 0 or a.size() != box.size.x * box.size.y:
		return 100.0
	var differ := 0
	for y in box.size.y:
		for x in box.size.x:
			var was: bool = img.get_pixel(box.position.x + x, box.position.y + y).a * 255.0 \
				> float(Cut.ALPHA_CUT)
			var now: bool = a[y * box.size.x + x] > Cut.ALPHA_CUT
			if was != now:
				differ += 1
	return float(differ) / float(box.size.x * box.size.y) * 100.0

## The same, for a bare alpha buffer covering exactly that region.
func _cover_of(a: PackedByteArray) -> float:
	var n := 0
	for v in a:
		if v > Cut.ALPHA_CUT:
			n += 1
	return float(n) / float(maxi(1, a.size())) * 100.0

## The region that has paint in it, whether or not the mask still admits it.
func _paint_box(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var painted: bool = c.a * 255.0 > float(Cut.ALPHA_CUT) \
				or maxf(maxf(c.r, c.g), c.b) * 255.0 > float(PAINT_FLOOR)
			if not painted:
				continue
			x0 = mini(x0, x); x1 = maxi(x1, x)
			y0 = mini(y0, y); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

## Throw the old mask away. `cut` only mattes an image that arrives without usable alpha,
## which is the correct rule for an installer and the wrong one for a repair.
func _make_opaque(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			c.a = 1.0
			img.set_pixel(x, y, c)
