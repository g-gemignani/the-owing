## Remove the generator's sparkle watermark from the painted backdrops.
##
## The image tool stamps a small four-point star into the bottom-right corner. It is
## not part of any of these rooms, it reads as a UI element that cannot be clicked,
## and it is in the same place in every file it touched.
##
## **Finding it is the whole problem, and brightness does not do it.** A "bright blob
## in the corner" test finds a brazier in nine of the twelve dungeon backdrops. What
## separates the mark from a brazier is that the mark is in *all* of them, at the same
## pixel: the twelve share one 1280x720 frame, so the intersection of "brighter than
## its surroundings" across all twelve is the stamp and nothing else. One file's
## brazier is another file's plain wall, and the minimum kills it.
##
## **Removal is a harmonic (Laplace) fill**: the masked region is solved to the
## smoothest surface that meets its own border. A floor stays a floor and a wall
## seam running through it stays straight.
##
## Subtraction was tried first and is worse, which is worth recording because it is
## the more obviously correct idea. The stamp is additive light, so in principle it
## can be taken back off with the drawing intact, and the twelve images give the
## amount: the least any of them is lit above its own local background. But that
## minimum is a LOWER bound — it is dragged down by whichever room happens to have
## dark linework under the stamp — so it under-subtracts everywhere and leaves the
## star as a crisp negative outline. Visibly worse than a smooth patch.
##
## What the fill costs: at 4x these patches read as a smudge where the linework was.
## At 1:1, in a corner that combat dims to 0.55, they are not findable — which is the
## condition that matters. Judge it with the corner contact sheet, not zoomed in.
##
## Two modes:
##
##   godot --headless --script tools/strip_sparkle.gd            # the installed 12
##   godot --headless --script tools/strip_sparkle.gd -- <dir>   # a folder of sources
##
## The second is for art that has NOT been installed yet, and is the one to use for a
## batch that will be cropped on the way in: strip in the frame the generator drew,
## before any geometry changes, while every image in the batch still agrees on where
## the stamp is. Add `--dry` to either to write a mask preview and touch nothing.
## Then: godot --headless --import
extends SceneTree

const ART := "res://assets/art/"

## The corner the stamp lives in. Everything below is measured inside this window.
## Generous on purpose: the background estimate is unreliable within BG_R of the
## window edge (the box mean is clipped there, so a light-to-dark boundary shows a
## false excess), and that margin is excluded — so the window has to be big enough
## that the stamp is nowhere near it.
const WIN_W := 280
const WIN_H := 240
## Background estimate: a box mean this wide. Big enough that the stamp barely moves
## it, small enough to follow a wall-to-floor transition.
const BG_R := 20
## A pixel is "lit" where it beats its own background by this much...
const LIT := 0.02
## ...and part of the stamp where it is lit in EVERY frame-sharing image.
## Grown by this much afterwards, because the star has a soft halo that is under the
## threshold and would be left behind as a faint square.
const GROW := 8
## Sanity bounds on what may be called a watermark, so a bug cannot quietly erase a
## brazier: it has to be a small compact blob, not a region.
const MAX_PIXELS := 4000
const MAX_SIDE := 90
## Jacobi sweeps for the fill. The hole is ~55px across; far past convergence.
const SWEEPS := 600

## Fewest images the intersection is allowed to run on. It was 4, chosen when the only
## caller was the batch of twelve; a RE-ROLL is three or fewer, and three re-rolled
## backdrops share a frame exactly as well as twelve do (D122).
##
## Lowering it costs less than it looks like, because the count is not what protects
## the art. Two other things do, and both still hold at three: MAX_PIXELS/MAX_SIDE
## refuse anything that is not a small compact blob, and `--dry` writes the mask over
## a real image so the box is approved by eye before a pixel moves. What the count
## buys is only how quickly the intersection sheds coincidences — at three, two rooms
## that happen to be lit in the same corner still get thinned by the third, and if
## they do not, the bounds refuse the result rather than erasing a brazier.
##
## Two is where it stops: an intersection of two is "these two agree", which is a
## coincidence rather than a pattern, and one is no intersection at all.
const MIN_FRAMES := 3

var _dry := false

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dry = args.has("--dry")
	var src := ""
	for a in args:
		if not String(a).begins_with("--"):
			src = String(a)
	var paths := _source_dir(src) if src != "" else _dungeon_backdrops()
	if paths.size() < MIN_FRAMES:
		print("need at least %d images sharing one frame to isolate the stamp; found %d" % [
			MIN_FRAMES, paths.size()])
		quit(2)
		return

	var imgs: Array[Image] = []
	var w := 0
	var h := 0
	for p in paths:
		var im := _load(p)
		if im == null:
			continue
		# NOT required to be the same size. The window is anchored to the bottom-right
		# CORNER, and the generator places its stamp at a fixed inset from that corner
		# — so a 1372x784 source lines up with a 1376x768 one inside the window even
		# though the images do not line up anywhere else.
		if im.get_width() < WIN_W or im.get_height() < WIN_H:
			print("SKIP  %s is smaller than the window" % p.get_file())
			continue
		w = maxi(w, im.get_width())
		h = maxi(h, im.get_height())
		imgs.append(im)
	print("%d images, largest %dx%d, window anchored to the bottom-right corner" % [
		imgs.size(), w, h])

	var mask := _stamp_mask(imgs)
	if mask.is_empty():
		print("no stamp found — nothing is lit in every image")
		quit(0)
		return

	var n := 0
	var minx := WIN_W
	var maxx := -1
	var miny := WIN_H
	var maxy := -1
	for i in mask.size():
		if not mask[i]:
			continue
		n += 1
		var mx: int = i % WIN_W
		var my: int = i / WIN_W
		minx = mini(minx, mx); maxx = maxi(maxx, mx)
		miny = mini(miny, my); maxy = maxi(maxy, my)
	print("stamp: %d px, %d-%d px in from the right edge, %d-%d up from the bottom = %dx%d" % [
		n, WIN_W - maxx, WIN_W - minx, WIN_H - maxy, WIN_H - miny,
		maxx - minx + 1, maxy - miny + 1])
	if n > MAX_PIXELS or maxx - minx + 1 > MAX_SIDE or maxy - miny + 1 > MAX_SIDE:
		print("REFUSED: that is too big to be a watermark. Tune LIT/GROW, do not widen the bounds.")
		quit(2)
		return
	if _dry:
		# Paint the mask over one image and write it out, because "1651 px in a
		# 63x85 box" is not something anybody can approve or reject.
		var dbg := Image.create(WIN_W * 2, WIN_H, false, Image.FORMAT_RGBA8)
		var wx := imgs[0].get_width() - WIN_W
		var wy := imgs[0].get_height() - WIN_H
		dbg.blit_rect(imgs[0], Rect2i(wx, wy, WIN_W, WIN_H), Vector2i(0, 0))
		dbg.blit_rect(imgs[0], Rect2i(wx, wy, WIN_W, WIN_H), Vector2i(WIN_W, 0))
		for y in WIN_H:
			for x in WIN_W:
				if mask[y * WIN_W + x]:
					dbg.set_pixel(WIN_W + x, y, Color(1, 0, 1))
		var preview := ProjectSettings.globalize_path("user://sparkle_mask.png")
		dbg.save_png(preview)
		print("wrote mask preview: %s" % preview)
		quit(0)
		return

	var wrote := 0
	for i in imgs.size():
		var out := paths[i]
		_fill(imgs[i], mask, imgs[i].get_width() - WIN_W, imgs[i].get_height() - WIN_H)
		if imgs[i].save_png(_abs(out)) != OK:
			print("FAIL  %s" % out)
			continue
		print("OK    %s" % out.get_file())
		wrote += 1
	print("strip_sparkle: %d cleaned" % wrote)
	quit(0)

## Every painted backdrop at the shared dungeon frame. The scene backdrops are built
## by `install_scene_backdrops.gd`, which crops to 16:9 and takes the stamp with it,
## so they are not in this list — and if one ever does keep it, it will fail the
## same-frame check above rather than being silently mangled.
## Every image in a folder, for the pre-install pass.
func _source_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		print("cannot open %s" % dir_path)
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var lower := f.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg"):
			out.append(dir_path.path_join(f))
		f = d.get_next()
	out.sort()
	return out

func _dungeon_backdrops() -> Array[String]:
	var out: Array[String] = []
	for did in Balance.DUNGEONS:
		var p: String = ART + "bg_" + String(did) + ".png"
		if FileAccess.file_exists(p):
			out.append(p)
	return out

## Straight off disk, NOT through ResourceLoader. Two reasons: the import cache can
## hand back the file as it was before the last write, and the imported `.ctex` is a
## processed copy — round-tripping the whole image through it to edit 1600 pixels
## risks changing every other pixel as well.
func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p

func _load(p: String) -> Image:
	var im := Image.new()
	if im.load(_abs(p)) != OK:
		return null
	im.convert(Image.FORMAT_RGBA8)
	return im

## Lit in every image, grown by GROW. Window coordinates, bottom-right anchored.
func _stamp_mask(imgs: Array[Image]) -> Array[bool]:
	var lit: Array[bool] = []
	lit.resize(WIN_W * WIN_H)
	lit.fill(true)
	for im in imgs:
		var ex := _excess(im, im.get_width() - WIN_W, im.get_height() - WIN_H)
		for i in lit.size():
			if ex[i] <= LIT:
				lit[i] = false
	# the margin where the clipped box mean lies
	for y in WIN_H:
		for x in WIN_W:
			if x < BG_R or x >= WIN_W - BG_R or y < BG_R or y >= WIN_H - BG_R:
				lit[y * WIN_W + x] = false
	# One stamp, so one blob. Anything else that survived twelve images is a
	# coincidence between two rooms, not the thing being removed.
	return _grow(_largest_blob(lit), GROW)

## The biggest 4-connected component, everything else dropped.
func _largest_blob(mask: Array[bool]) -> Array[bool]:
	var seen: Array[bool] = []
	seen.resize(mask.size())
	seen.fill(false)
	var best: Array[int] = []
	for start in mask.size():
		if not mask[start] or seen[start]:
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			var x: int = i % WIN_W
			var y: int = i / WIN_W
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= WIN_W or ny >= WIN_H:
					continue
				var j: int = ny * WIN_W + nx
				if mask[j] and not seen[j]:
					seen[j] = true
					stack.append(j)
		if comp.size() > best.size():
			best = comp
	var out: Array[bool] = []
	out.resize(mask.size())
	out.fill(false)
	for i in best:
		out[i] = true
	return out

## A channel minus its own local box mean, over the window. `chan` is 0/1/2 for
## R/G/B, or -1 for luminance — detection uses luminance, subtraction needs the
## three channels separately or a white stamp comes off as a colour cast.
func _excess(img: Image, x0: int, y0: int, chan: int = -1) -> PackedFloat32Array:
	var lum := PackedFloat32Array()
	lum.resize(WIN_W * WIN_H)
	for y in WIN_H:
		for x in WIN_W:
			var c := img.get_pixel(x0 + x, y0 + y)
			var v := c.get_luminance()
			if chan == 0: v = c.r
			elif chan == 1: v = c.g
			elif chan == 2: v = c.b
			lum[y * WIN_W + x] = v
	# summed-area table, so the box mean is four lookups regardless of BG_R
	var sat := PackedFloat64Array()
	sat.resize((WIN_W + 1) * (WIN_H + 1))
	for y in WIN_H:
		var row := 0.0
		for x in WIN_W:
			row += lum[y * WIN_W + x]
			sat[(y + 1) * (WIN_W + 1) + x + 1] = sat[y * (WIN_W + 1) + x + 1] + row
	var out := PackedFloat32Array()
	out.resize(WIN_W * WIN_H)
	for y in WIN_H:
		var ya := maxi(0, y - BG_R)
		var yb := mini(WIN_H, y + BG_R + 1)
		for x in WIN_W:
			var xa := maxi(0, x - BG_R)
			var xb := mini(WIN_W, x + BG_R + 1)
			var s: float = sat[yb * (WIN_W + 1) + xb] - sat[ya * (WIN_W + 1) + xb] \
				- sat[yb * (WIN_W + 1) + xa] + sat[ya * (WIN_W + 1) + xa]
			var area := float((yb - ya) * (xb - xa))
			out[y * WIN_W + x] = lum[y * WIN_W + x] - float(s) / area
	return out

func _grow(mask: Array[bool], r: int) -> Array[bool]:
	var cur := mask
	for _i in r:
		var next: Array[bool] = cur.duplicate()
		for y in WIN_H:
			for x in WIN_W:
				if cur[y * WIN_W + x]:
					continue
				var hit := false
				if x > 0 and cur[y * WIN_W + x - 1]: hit = true
				elif x < WIN_W - 1 and cur[y * WIN_W + x + 1]: hit = true
				elif y > 0 and cur[(y - 1) * WIN_W + x]: hit = true
				elif y < WIN_H - 1 and cur[(y + 1) * WIN_W + x]: hit = true
				if hit:
					next[y * WIN_W + x] = true
		cur = next
	return cur

## Solve the masked region to the smoothest patch that meets its own border.
func _fill(img: Image, mask: Array[bool], x0: int, y0: int) -> void:
	var r := PackedFloat32Array(); r.resize(WIN_W * WIN_H)
	var g := PackedFloat32Array(); g.resize(WIN_W * WIN_H)
	var b := PackedFloat32Array(); b.resize(WIN_W * WIN_H)
	for y in WIN_H:
		for x in WIN_W:
			var c := img.get_pixel(x0 + x, y0 + y)
			var i := y * WIN_W + x
			r[i] = c.r; g[i] = c.g; b[i] = c.b
	# seed the hole with the mean of its border, so the sweeps start near the answer
	var sr := 0.0; var sg := 0.0; var sb := 0.0; var n := 0
	for y in WIN_H:
		for x in WIN_W:
			var i := y * WIN_W + x
			if mask[i]:
				continue
			var touches := false
			if x > 0 and mask[i - 1]: touches = true
			elif x < WIN_W - 1 and mask[i + 1]: touches = true
			elif y > 0 and mask[i - WIN_W]: touches = true
			elif y < WIN_H - 1 and mask[i + WIN_W]: touches = true
			if touches:
				sr += r[i]; sg += g[i]; sb += b[i]; n += 1
	if n > 0:
		for i in mask.size():
			if mask[i]:
				r[i] = sr / n; g[i] = sg / n; b[i] = sb / n
	for _s in SWEEPS:
		for y in range(1, WIN_H - 1):
			for x in range(1, WIN_W - 1):
				var i := y * WIN_W + x
				if not mask[i]:
					continue
				r[i] = (r[i - 1] + r[i + 1] + r[i - WIN_W] + r[i + WIN_W]) * 0.25
				g[i] = (g[i - 1] + g[i + 1] + g[i - WIN_W] + g[i + WIN_W]) * 0.25
				b[i] = (b[i - 1] + b[i + 1] + b[i - WIN_W] + b[i + WIN_W]) * 0.25
	for y in WIN_H:
		for x in WIN_W:
			var i := y * WIN_W + x
			if mask[i]:
				img.set_pixel(x0 + x, y0 + y, Color(r[i], g[i], b[i], 1.0))
