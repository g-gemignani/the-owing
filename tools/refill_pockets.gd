## Put back the part of a subject the matte cut out of it, on an installed cutout whose
## source painting is gone.
##
## `cutout_lib.fill_trapped` clears background the border flood could not reach — the
## triangle between two legs, the eye of a hook. It used to recognise such a pocket by
## three things: enclosed, big enough to matter, and featureless, where featureless meant
## `POCKET_STD`, the mean of the LOCAL deviation. That statistic cannot see a gradient: a
## smooth airbrushed sac spanning a third of the frame is flat at every individual pixel
## and nothing like one colour overall, so it measured as field, and the growth then ran at
## the ordinary `TOL` and took the whole sac. The Brood-Mother's abdomen went that way, and
## seven other installed cutouts with it (D195).
##
## `cutout_lib` now measures what the growth TOOK and refuses the ones that carry paint, so
## the defect cannot recur. This is the other half: the sources for the installed set are
## long gone, and a hole already on disk needs a repair rather than a re-cut.
##
## **The paint is still there.** The pipeline only ever writes the ALPHA channel — `matte`,
## `fill_trapped` and `clear_bloom` all zero `a[]` and leave the colour alone, and `place`
## resizes RGBA without premultiplying. So a wrongly-cleared pocket is not lost data, it is
## visible data with its alpha set to zero. Restoring it is exact, not an inpaint. That is
## the whole reason this tool can exist rather than being a request for another painting.
##
## **What it lists is a shortlist to look at, not a list of defects, and `--all` does not
## exist for that reason.** `cutout_lib.find_gouges` finds every enclosed pocket whose
## interior is not one colour; over the installed sets that is eight pockets, of which one
## was the Brood-Mother and seven are correct background that happens to sit on a shadowed
## or lit patch of field — the gap between a hound's legs, the space under a sexton's robe.
## Nothing measurable on a finished file told them apart (D195). So the operator names the
## file, having looked at it; the tool measures and restores, and does not decide.
##
## Reports and changes nothing by default. `--fix <file>` writes.
##
##   godot --headless --script tools/refill_pockets.gd
##   godot --headless --script tools/refill_pockets.gd -- --fix enemies/brood_mother
##   godot --headless --import
extends SceneTree

const Cut := preload("res://tools/cutout_lib.gd")

const DIRS := ["enemies", "relics", "powers", "cards"]
## How far the restore may walk out of a pocket to reclaim the feathered rim, in pixels.
##
## `feather_edge` grades a band around EVERY transparent pixel, including the ones a pocket
## should never have had, so a bare alpha restore leaves the hole ringed by the
## half-transparent halo that band became — which reads as a bright outline drawn around
## the repair. Measured on the Brood-Mother, the graded rim is 5px wide at 256; 6 clears it.
const RIM_R := 6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var fix := args.has("--fix")
	var targets: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			targets.append(String(a))
	# No --all. Seven of the eight pockets this lists are correct background, so a switch
	# that restored them in bulk would put a slab of field back inside seven good cutouts.
	if fix and targets.is_empty():
		print("--fix needs a named target, e.g. enemies/brood_mother")
		quit(2)
		return

	var found := 0
	var written := 0
	print("%-26s %7s %7s %8s  %s" % ["pocket", "px", "core", "spread", ""])
	for sub in DIRS:
		var dir_path := "res://assets/art/%s/" % sub
		for name in _pngs(dir_path):
			var rel := "%s/%s" % [sub, name.get_basename()]
			var mine := targets.has(rel) or targets.has(name.get_basename())
			if not targets.is_empty() and not mine:
				continue
			var n := _handle(dir_path + name, rel, fix and mine)
			found += int(n[0])
			written += int(n[1])

	print("\n%d enclosed pocket(s) worth looking at" % found)
	if written > 0:
		print("%d file(s) rewritten — run `godot --headless --import`" % written)
	elif found > 0:
		print("nothing written, and most of these are fine. Open the file, confirm the hole "
			+ "is real, then: --fix <family>/<id>")
	quit(0)


func _pngs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ProjectSettings.globalize_path(dir_path))
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.to_lower().ends_with(".png"):
			out.append(f)
		f = d.get_next()
	out.sort()
	return out


## Returns [pockets_carrying_paint, 1 if the file was rewritten else 0].
func _handle(path: String, label: String, fix: bool) -> Array:
	var im := Cut.load_image(path)
	if im == null:
		return [0, 0]
	var w := im.get_width()
	var h := im.get_height()
	var gouges := Cut.find_gouges(im, w, h)
	if gouges.is_empty():
		return [0, 0]
	for g in gouges:
		print("%-26s %7d %7d %8.2f  %s" % [
			label, int(g["pixels"].size()), int(g["core"]), float(g["spread"]),
			"restored" if fix else "candidate — LOOK at it before restoring it"])
	if not fix:
		return [gouges.size(), 0]

	for g in gouges:
		_restore(im, g["pixels"], w, h)
	if im.save_png(Cut.abs_path(path)) != OK:
		print("  FAILED writing %s" % path)
		return [gouges.size(), 0]
	return [gouges.size(), 1]


## Alpha back to opaque over the pocket, then out through the feathered rim it left.
##
## The rim walk is bounded twice on purpose. It may only cross PARTIALLY transparent
## pixels, so it cannot enter the fully-transparent surround even where the two touch, and
## it may not travel further than `RIM_R` from the pocket, so a chain of soft pixels running
## along the subject's own edge cannot carry it somewhere it was not invited.
func _restore(im: Image, members: Array, w: int, h: int) -> void:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[int] = []
	for i in members:
		dist[int(i)] = 0
		queue.append(int(i))
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var c := im.get_pixel(i % w, i / w)
		c.a = 1.0
		im.set_pixel(i % w, i / w, c)
		if dist[i] >= RIM_R:
			continue
		var x: int = i % w
		var y: int = i / w
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j: int = ny * w + nx
			if dist[j] >= 0:
				continue
			var a := im.get_pixel(nx, ny).a * 255.0
			if a <= float(Cut.ALPHA_CUT) or a >= 255.0:
				continue
			dist[j] = dist[i] + 1
			queue.append(j)
