## Takes the chroma key back out of cutouts that are already installed.
##
##   godot --headless --script tools/demagenta.gd -- <dir> [<dir>...] [--dry]
##   godot --headless --import
##
## **Why this exists when `cutout_lib` already despills.** The install-time pass measures a
## pixel against the field it SAMPLED from that cell's border, and it repaints from a clean
## neighbour it has to find nearby. Both halves get weaker as the downscale gets harder: the
## iso sheets are ~1408px wide and land at 128x192, so a cell shrinks by a factor of five and
## LANCZOS mixes key into the silhouette faster than a rim-local repair can walk it back out.
## Measured after a full install with `--key`: **20,507 key-coloured pixels across 91 of the
## 97 files** — a pink hairline on every silhouette, plainly visible on the floor.
##
## **The detector is a HUE test, not a distance to a sampled colour**, and that is the whole
## reason it can be run afterwards. The key is pure (1,0,1): what identifies it is that green
## sits far below both other channels while the pixel stays saturated. Nothing in this art
## does that — the one thing that comes close is the mycelial lord's violet cap at roughly
## (0.6, 0.5, 0.75), where green trails by 0.1 and the test needs 0.22. So this can be run
## over a whole directory without knowing which field each file was cut against, and re-run
## safely: once the key is gone it finds nothing and writes nothing.
##
## **Repaired from the subject, never invented.** A key pixel takes the mean of the nearby
## opaque pixels that are NOT key, searching outward until it finds some. Repaired pixels
## count as clean on the next pass, so the fix walks inward along a feature too thin to have
## an interior of its own — the case that defeats a single-pass repair. What survives every
## pass has no clean paint anywhere near it and is not subject at all, so its alpha goes to
## zero rather than leaving a pink speck on the floor.
extends SceneTree

## How far below BOTH other channels green has to sit. Between the key (1.0) and the most
## violet thing in the set (0.1).
const KEY_GAP := 0.22
## ...and the pixel has to be bright enough to be the key rather than a dark shadow that
## happens to lean blue-red.
const KEY_MIN := 0.35
## A SECOND, gentler rule for what the key leaves behind once it is diluted: the drop shadow
## the brief told the generator not to draw, tinted mauve by the field it was drawn on. Too
## desaturated for `KEY_GAP`, and still plainly a purple smear under a rat at tile size.
##
## It cannot just be a looser gap. Measured, the mycelial lord's violet cap carries **7,300**
## purple-leaning interior pixels, and neutralising those would drain the one subject whose
## colour this genuinely is. What separates them is WHERE: a drop shadow lies in the contact
## band at the very bottom of the canvas and a mushroom cap does not. The rats measure
## 855-1,080 such pixels; the cap has none down there.
const TINT_GAP := 0.06
## How much of the canvas, measured up from the bottom, counts as the contact band.
const TINT_BAND := 0.18
## Rings searched for clean paint to borrow, growing until something is found.
const MAX_R := 6
## How many times to sweep. Each pass reaches one ring further into a thin feature.
const PASSES := 6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var dry := "--dry" in args
	var dirs: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			var d := String(a)
			dirs.append(d if d.ends_with("/") else d + "/")
	if dirs.is_empty():
		print("usage: -- <dir> [<dir>...] [--dry]")
		quit(2)
		return

	print("=== demagenta ===%s" % ("  [dry run]" if dry else ""))
	print("%-26s %8s %8s %s" % ["file", "repaired", "cleared", "verdict"])
	var files := 0
	var total_fix := 0
	var total_cut := 0
	for d in dirs:
		var da := DirAccess.open(d)
		if da == null:
			print("cannot open %s" % d)
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			# `floor*`/`rock*` are computed seamless materials with no alpha and no key.
			if f.ends_with(".png") and not f.begins_with("floor") and not f.begins_with("rock"):
				var r := _clean(d + f, dry)
				if int(r[0]) > 0 or int(r[1]) > 0:
					files += 1
					total_fix += int(r[0])
					total_cut += int(r[1])
					print("%-26s %8d %8d %s" % [f, int(r[0]), int(r[1]),
						"would rewrite" if dry else "rewritten"])
			f = da.get_next()
		da.list_dir_end()

	print("\n%d files touched, %d px repainted, %d px cleared%s" % [
		files, total_fix, total_cut, " (dry run)" if dry else ""])
	if files > 0 and not dry:
		print("Run `godot --headless --import`.")
	quit(0)


## Is this the chroma key rather than paint?
static func _is_key(c: Color) -> bool:
	return minf(c.r, c.b) - c.g > KEY_GAP and maxf(c.r, c.b) > KEY_MIN


## The diluted key in a drop shadow: purple-leaning, but only down in the contact band, where
## a shadow lies and a subject's own colour does not.
static func _is_shadow_tint(c: Color, y: int, h: int) -> bool:
	if float(y) < float(h) * (1.0 - TINT_BAND):
		return false
	var gap: float = minf(c.r, c.b) - c.g
	return gap > TINT_GAP and gap <= KEY_GAP


func _clean(path: String, dry: bool) -> Array:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return [0, 0]
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()

	# Which pixels are opaque and NOT key — the paint this repair is allowed to borrow from.
	var clean := PackedByteArray()
	clean.resize(w * h)
	var todo: Array[int] = []
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var opaque: bool = c.a * 255.0 > 8.0
			if not opaque:
				continue
			if _is_key(c):
				todo.append(y * w + x)
			else:
				clean[y * w + x] = 1
	# NOT an early return: the tint pass below is independent of the strict one, and a file
	# whose hard key has already been cleaned can still carry a mauve shadow.
	var repainted := 0
	for _p in (PASSES if not todo.is_empty() else 0):
		if todo.is_empty():
			break
		var out := PackedVector3Array()
		var at := PackedInt32Array()
		var left: Array[int] = []
		for i in todo:
			var x0: int = i % w
			var y0: int = i / w
			var sum := Vector3.ZERO
			var n := 0
			# Grow the search until clean paint appears. A thin feature has none close by,
			# which is exactly the case a fixed radius gives up on.
			for r in range(1, MAX_R + 1):
				for dy in range(-r, r + 1):
					var ny := y0 + dy
					if ny < 0 or ny >= h:
						continue
					for dx in range(-r, r + 1):
						if absi(dx) != r and absi(dy) != r:
							continue          # ring only; the inside was covered already
						var nx := x0 + dx
						if nx < 0 or nx >= w or clean[ny * w + nx] == 0:
							continue
						var q := img.get_pixel(nx, ny)
						sum += Vector3(q.r, q.g, q.b)
						n += 1
				if n > 0:
					break
			if n == 0:
				left.append(i)
				continue
			var mean: Vector3 = sum / float(n)
			# If the paint it would borrow is ITSELF key-coloured, repainting achieves
			# nothing and the pixel comes back on the next sweep unchanged — a fixed point
			# that no number of passes resolves. Measured: this converged at 21 pixels
			# across 13 files. A pixel whose whole neighbourhood is key is backdrop.
			if _is_key(Color(mean.x, mean.y, mean.z)):
				left.append(i)
				continue
			out.append(mean)
			at.append(i)
		# Written in a second pass so a pixel repaired now is not a source for its neighbour
		# in the same sweep — otherwise the repair smears along the rim instead of across it.
		for k in at.size():
			var v: Vector3 = out[k]
			var idx: int = at[k]
			var old := img.get_pixel(idx % w, idx / w)
			img.set_pixel(idx % w, idx / w, Color(v.x, v.y, v.z, old.a))
			clean[idx] = 1
			repainted += 1
		todo = left

	# The shadow tint is a COLOUR error, not a geometry one, so it is neutralised in place:
	# green is lifted until the pixel no longer leans purple, and alpha is never touched.
	# Borrowing a neighbour's colour or clearing the pixel would both be wrong here — these
	# sprites are anchored by their FEET and this band is where the feet are, so a repair
	# that can nibble the bottom rows moves the stand point on every figure it touches.
	# Lifting green keeps the silhouette and the luminance and takes only the cast.
	var neutralised := 0
	for y in h:
		if float(y) < float(h) * (1.0 - TINT_BAND):
			continue
		for x in w:
			var c2 := img.get_pixel(x, y)
			if c2.a * 255.0 <= 8.0 or not _is_shadow_tint(c2, y, h):
				continue
			# Landed clearly INSIDE the threshold rather than exactly on it: the file is
			# 8-bit, so a green channel written to land at exactly `TINT_GAP` rounds back
			# out again and the tool stops being idempotent — it rewrote all 97 files on
			# every run, reporting the same 23,788 pixels each time.
			img.set_pixel(x, y, Color(c2.r, minf(c2.r, c2.b) - TINT_GAP * 0.5, c2.b, c2.a))
			neutralised += 1

	# Anything still key after every pass has no paint anywhere near it. It is not part of
	# the subject; it is a speck of backdrop the matte kept.
	var cleared := 0
	for i in todo:
		var c := img.get_pixel(i % w, i / w)
		img.set_pixel(i % w, i / w, Color(c.r, c.g, c.b, 0.0))
		cleared += 1

	if not dry and (repainted > 0 or cleared > 0 or neutralised > 0):
		if img.save_png(ProjectSettings.globalize_path(path)) != OK:
			print("   FAILED to write %s" % path)
	return [repainted + neutralised, cleared]
