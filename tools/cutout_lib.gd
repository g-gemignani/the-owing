## Turning a generated painting into an installable asset: matte, despeckle, trim,
## scale, anchor. Shared by `install_cutouts.gd` (one subject per file) and
## `install_sheet.gd` (a grid of subjects in one file), which differ only in how they
## get to an Image and what they call the result.
##
## Deliberately NOT a `class_name`: these are diagnostics that never ship, and a global
## class would put them in the game's class list beside `CardData` and `EnemyData`.
## Loaded with `preload("res://tools/cutout_lib.gd")` and called statically.
##
## The two entry points are `cut()` and `cut_mono()`. Everything else is a step in
## them, exposed because the sheet installer needs to check a cell's bounding box
## before deciding the grid was aligned.
extends RefCounted

## How close to the sampled background a pixel has to be to be called background.
## Per-channel-max distance, 0-1. Generous: the flat field a generator paints is flat
## to the eye and noisy to a comparison, and the despeckle pass covers the rest.
const TOL := 0.14
## The background must actually BE flat. If fewer than this many border pixels agree
## with their own average, the image is a painting with the subject in a room, not a
## subject on a field — refuse it rather than cutting a hole in a wall.
const BORDER_AGREE := 0.80
## Sanity bounds on what is left after matting, as a fraction of the frame. Under the
## floor the matte ate the subject; over the ceiling it found nothing.
const MIN_COVER := 0.02
const MAX_COVER := 0.92
## Opaque components smaller than this fraction of the largest are dropped.
const ISLAND_MIN := 0.08
## Second-pass tolerance for background the border flood fill could not REACH — a pocket
## sealed off by the subject's own silhouette (see `fill_trapped`). Much tighter than
## `TOL` on purpose: a trapped pocket is the literal untouched field, so its distance to
## the sampled background is ~0, while a grey pauldron on a grey field is merely close.
## Measured on the boss batch (D90): at 0.05 the real pockets stay in the thousands of
## pixels and the false positives collapse to under a hundred.
const HOLE_TOL := 0.05
## A trapped pocket has to be this fraction of the FRAME to be filled. The tolerance
## alone leaves a scatter of single pixels inside textured armour, and punching those out
## is not a fix, it is speckle. The gap between the smallest real pocket (0.08% of frame)
## and the largest false one (0.009%) is an order of magnitude, so this sits between.
const HOLE_MIN := 0.0005
## Alpha at or under this is transparent for trimming purposes.
const ALPHA_CUT := 8
## Breathing room left at the top and sides, as a fraction of the canvas. NEVER at the
## bottom on a bottom-anchored family — see `place()`.
const PAD := 0.02
## Where the glyph's own peak brightness is taken from when flattening to white+alpha.
## The literal maximum is one stray pixel; this is the percentile that stands in for it.
const MONO_PEAK_PCT := 0.99
## Below this much dynamic range, a mono cell has no glyph in it. Without the check the
## autocontrast below divides an empty cell's sensor noise by its own tiny span and
## produces a confident, fully-opaque field of static — which then passes every coverage
## test there is. An empty cell has to be recognised as empty, not normalised into one.
const MONO_MIN_RANGE := 0.08


## Matte, despeckle, trim and anchor `img` INTO `canvas`, in place.
## Returns "" on success, or the reason it was refused.
static func cut(img: Image, canvas: Vector2i, anchor_bottom: bool) -> String:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# An image that arrives WITH alpha never reaches `matte`, so this would otherwise
	# report the previous image's pockets — a per-file counter has to be cleared per file.
	filled_pockets = 0
	var a := alpha_of(img)
	if opaque_fraction(a) > 0.995:
		# No usable alpha: the generator handed back an opaque painting. Cut it.
		var reason := matte(img, a)
		if reason != "":
			return reason
	var check := _survives(a, w, h)
	if check != "":
		return check
	erode_and_soften(a, w, h)
	apply_alpha(img, a)
	return place(img, a, canvas, anchor_bottom)


## A FILLED rectangle, not a cutout: no matte, no trim, no alpha.
##
## Card illustrations are the one family that is a picture rather than a subject —
## the brief says "a filled 4:3 rectangle, not a cutout" and means it, because the
## art is a band across the top of a card face, not an object standing on a floor.
## Running them through `cut` asks the matte to find a flat border on a painting that
## deliberately bleeds to every edge, and it correctly refuses: "background is not
## flat (28% of the border agrees, need 80%)". Every card family failed that way, and
## the failure looked like a bad generation rather than a mis-routed installer (D118).
##
## Cover-crop rather than squash: scale to the LARGER ratio and centre-crop the
## overflow, so a source that is a few percent off 4:3 loses a sliver instead of
## stretching the subject.
static func fill(img: Image, canvas: Vector2i) -> String:
	if img.get_width() <= 0 or img.get_height() <= 0:
		return "empty image"
	img.convert(Image.FORMAT_RGBA8)
	var s: float = maxf(float(canvas.x) / float(img.get_width()),
		float(canvas.y) / float(img.get_height()))
	var nw := maxi(canvas.x, int(round(img.get_width() * s)))
	var nh := maxi(canvas.y, int(round(img.get_height() * s)))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var ox := (nw - canvas.x) / 2
	var oy := (nh - canvas.y) / 2
	var dst := img.get_region(Rect2i(ox, oy, canvas.x, canvas.y))
	img.copy_from(dst)
	last_bbox = Rect2i(0, 0, canvas.x, canvas.y)
	return ""


## The same, for a symbol that has to stay TINTABLE.
##
## `Icons` tints these by rarity and fades them for spent states, and that behaviour is
## load-bearing — a coloured glyph cannot be tinted, only muddied. So the pipeline is
## different in its first step and only its first step: alpha comes from LUMINANCE
## rather than from a flood fill, and the colour is thrown away.
##
## Luminance is the better matte here and not merely the cheaper one. A flood fill
## resolves every pixel to in or out, which turns a glyph's anti-aliased edge into a
## staircase — visible immediately, because these are drawn at 64px and scaled up to 3x
## on a 4K display (D65). Luminance keeps the edge as partial alpha, which is what it
## already is. There is nothing to lose by discarding the hue: the destination is one
## colour by contract.
static func cut_mono(img: Image, canvas: Vector2i) -> String:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	filled_pockets = 0   # `cut_mono` mattes by luminance and never traps a pocket
	var a := mono_alpha(img)
	if last_mono_range < MONO_MIN_RANGE:
		return "flat — no glyph here (dynamic range %.3f)" % last_mono_range
	var check := _survives(a, w, h)
	if check != "":
		return check
	# No erode: the anti-aliased edge IS the edge here, and eroding a 64px glyph thins
	# it enough to change the shape.
	white_out(img, a)
	return place(img, a, canvas, false)


## How many stray opaque islands the last `cut()`/`cut_mono()` threw away. Reported by
## the callers rather than swallowed, because a silently-deleted limb and a
## silently-deleted watermark look identical from inside this file.
static var dropped_islands := 0
## How many trapped background pockets the last `cut()` filled. Reported for the same
## reason: from inside here, a filled pocket and a gouged subject look identical.
static var filled_pockets := 0
## Luminance spread of the last `mono_alpha()` — how much glyph there was to find.
static var last_mono_range := 0.0
## Trim box of the last `place()`, in the SOURCE image's coordinates. `install_sheet.gd`
## checks it against the cell it came from: a subject touching its own cell edge means
## the grid is misaligned and that glyph is clipped.
static var last_bbox := Rect2i()

static func _survives(a: PackedByteArray, w: int, h: int) -> String:
	var kept := despeckle(a, w, h)
	dropped_islands = maxi(0, kept)
	if kept < 0:
		return "nothing opaque left after matting"
	var cover := opaque_fraction(a)
	if cover < MIN_COVER:
		return "only %.1f%% of the frame survived the matte — it ate the subject" % (cover * 100.0)
	if cover > MAX_COVER:
		return "%.1f%% of the frame survived — the matte found no background" % (cover * 100.0)
	return ""


## Flood-fill the background in from the border. A magic wand from the edges rather
## than a chroma key, because a key colour that never appears in the subject does not
## exist for this palette — the zone accents run cyan, orange, acid-green, deep-blue
## and MAGENTA (ART.md §2), so every obvious key is somebody's light source.
static func matte(img: Image, a: PackedByteArray) -> String:
	var w := img.get_width()
	var h := img.get_height()
	var border := _border_indices(w, h)

	var sum := Vector3.ZERO
	for i in border:
		var c := img.get_pixel(i % w, i / w)
		sum += Vector3(c.r, c.g, c.b)
	var bg := sum / float(border.size())

	var agree := 0
	for i in border:
		if _near(img.get_pixel(i % w, i / w), bg):
			agree += 1
	var frac := float(agree) / float(border.size())
	if frac < BORDER_AGREE:
		return "background is not flat (%.0f%% of the border agrees, need %.0f%%) — this looks like a painting of a room, not a subject on a field" % [
			frac * 100.0, BORDER_AGREE * 100.0]

	# 4-connected flood from every border pixel that IS the background. Connectivity is
	# what stops a patch of stone inside the subject that happens to match the field
	# from being punched out into a hole.
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[int] = []
	for i in border:
		if seen[i] == 0 and _near(img.get_pixel(i % w, i / w), bg):
			seen[i] = 1
			stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		a[i] = 0
		var x: int = i % w
		var y: int = i / w
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j: int = ny * w + nx
			if seen[j] == 0 and _near(img.get_pixel(nx, ny), bg):
				seen[j] = 1
				stack.append(j)

	fill_trapped(img, a, bg, w, h)
	return ""


## Clear background the flood fill could not REACH.
##
## The fill above is seeded from the border and 4-connected, which is deliberate — it is
## what stops a patch of stone inside the subject that happens to match the field from
## being punched out into a hole. The cost of that choice is the opposite defect: field
## that the subject's own silhouette seals off from the border SURVIVES, fully opaque and
## still background-coloured. The gap between a raised arm and a torso, the eye of a
## halberd's hook, the triangle between two legs.
##
## This is not a cosmetic flaw and `despeckle` cannot catch it. A trapped pocket touches
## the subject, so it is part of the subject's own connected component — the largest one —
## and no island threshold will ever see it. It ships as a slab of flat magenta behind a
## skeleton's ribs, and because the sources are per-enemy colour fields, every enemy gets
## a different colour of wrong.
##
## Two things separate a trapped pocket from a subject pixel that merely resembles the
## field, and BOTH are required:
##   - `HOLE_TOL`, far tighter than `TOL`: the pocket is the untouched field itself.
##   - enclosure: a component touching the frame edge is not trapped, and clearing one
##     would be the border fill overreaching at a tolerance it was never granted.
## Returns how many pockets were filled; reported by the callers for the same reason
## `dropped_islands` is — from in here, a filled pocket and a gouged subject look alike.
static func fill_trapped(img: Image, a: PackedByteArray, bg: Vector3, w: int, h: int) -> int:
	var min_area := int(w * h * HOLE_MIN)
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var sizes: Array[int] = []
	var open: Array[bool] = []   # touches the frame edge, therefore not trapped
	for start in w * h:
		if comp[start] >= 0 or a[start] <= ALPHA_CUT or not _tight(img, start, w, bg):
			continue
		var id := sizes.size()
		var n := 0
		var edge := false
		var stack: Array[int] = [start]
		comp[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			var x: int = i % w
			var y: int = i / w
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				edge = true
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				if comp[j] < 0 and a[j] > ALPHA_CUT and _tight(img, j, w, bg):
					comp[j] = id
					stack.append(j)
		sizes.append(n)
		open.append(edge)

	var filled := 0
	for id in sizes.size():
		if not open[id] and sizes[id] >= min_area:
			filled += 1
	filled_pockets = filled
	if filled == 0:
		return 0

	# Now GROW each qualifying pocket at the normal `TOL`, 4-connected, exactly as the
	# border fill grows from the frame edge.
	#
	# The two tolerances are doing two different jobs, and collapsing them is what left a
	# magenta rim around the tomb guard's shield on the first attempt. `HOLE_TOL` is not a
	# claim about where the pocket ENDS, only about where it can be safely RECOGNISED: the
	# field carries a faint vignette, so a pocket's middle sits at distance ~0 while its
	# outer ring drifts to 0.08-0.14 and a tight threshold stops short, leaving a halo of
	# background the exact width of the gradient. Once enclosure plus area have
	# established that this pocket IS field, it has earned the same trust the frame edge
	# gets, and the ordinary tolerance can finish the job. Growing an UNVERIFIED seed at
	# `TOL` is the thing that would gouge grey armour on a grey field — so the seed is
	# what the tight test guards, not the growth.
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack2: Array[int] = []
	for i in w * h:
		var id := comp[i]
		if id >= 0 and not open[id] and sizes[id] >= min_area:
			seen[i] = 1
			stack2.append(i)
	while not stack2.is_empty():
		var i: int = stack2.pop_back()
		a[i] = 0
		var x: int = i % w
		var y: int = i / w
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j: int = ny * w + nx
			if seen[j] == 0 and a[j] > ALPHA_CUT and _near(img.get_pixel(nx, ny), bg):
				seen[j] = 1
				stack2.append(j)
	return filled


static func _tight(img: Image, i: int, w: int, bg: Vector3) -> bool:
	var c := img.get_pixel(i % w, i / w)
	return absf(c.r - bg.x) <= HOLE_TOL and absf(c.g - bg.y) <= HOLE_TOL \
		and absf(c.b - bg.z) <= HOLE_TOL


## Alpha from luminance, stretched so the field lands at 0 and the glyph at 255.
##
## Polarity is read off the border rather than assumed: a generator asked for "white
## glyph on black" returns black-on-white often enough that hardcoding it would silently
## invert a fifth of the set, and an inverted glyph is not obviously wrong in a
## thumbnail — it is a filled square with a hole in it.
static func mono_alpha(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for y in h:
		for x in w:
			lum[y * w + x] = img.get_pixel(x, y).get_luminance()

	var field := 0.0
	var border := _border_indices(w, h)
	for i in border:
		field += lum[i]
	field /= float(border.size())
	var dark_glyph := field > 0.5
	if dark_glyph:
		for i in lum.size():
			lum[i] = 1.0 - lum[i]
		field = 1.0 - field

	# The peak is a high percentile, not the maximum: one specular pixel would otherwise
	# set the scale and leave the whole glyph translucent.
	var sorted := PackedFloat32Array(lum)
	sorted.sort()
	var peak: float = sorted[int((sorted.size() - 1) * MONO_PEAK_PCT)]
	last_mono_range = peak - field
	var span: float = maxf(0.05, last_mono_range)

	var a := PackedByteArray()
	a.resize(w * h)
	for i in lum.size():
		a[i] = int(round(clampf((lum[i] - field) / span, 0.0, 1.0) * 255.0))
	return a


## Throw the colour away, keep the shape. White, because `Icons` multiplies by a tint
## and multiplying by anything else loses the tint's top end.
static func white_out(img: Image, a: PackedByteArray) -> void:
	var w := img.get_width()
	for y in img.get_height():
		for x in w:
			img.set_pixel(x, y, Color(1, 1, 1, a[y * w + x] / 255.0))


## Drop opaque components under ISLAND_MIN of the largest. Returns how many went, or
## -1 if there was nothing opaque at all.
##
## Load-bearing, not tidiness: `strip_sparkle.gd` cannot find the generator's watermark
## on a batch of cutouts (it works by intersecting across images that share one frame,
## and these share nothing), but it does not need to — the stamp is in a corner, the
## corner is background, the matte takes it. What it LEAVES is a small opaque island in
## the corner, which would drag the trim box out to meet it and shrink the subject to
## fit beside its own watermark.
static func despeckle(a: PackedByteArray, w: int, h: int) -> int:
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var sizes: Array[int] = []
	for start in w * h:
		if a[start] <= ALPHA_CUT or comp[start] >= 0:
			continue
		var id := sizes.size()
		var n := 0
		var stack: Array[int] = [start]
		comp[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			var x: int = i % w
			var y: int = i / w
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				if comp[j] < 0 and a[j] > ALPHA_CUT:
					comp[j] = id
					stack.append(j)
		sizes.append(n)
	if sizes.is_empty():
		return -1
	var biggest := 0
	for n in sizes:
		biggest = maxi(biggest, n)
	var floor_size := int(biggest * ISLAND_MIN)
	var dropped := 0
	for id in sizes.size():
		if sizes[id] < floor_size:
			dropped += 1
	if dropped == 0:
		return 0
	for i in w * h:
		var id := comp[i]
		if id >= 0 and sizes[id] < floor_size:
			a[i] = 0
	return dropped


## One pixel of erosion, then one box blur of the alpha channel. The flood-fill matte
## cuts on a hard threshold, so the boundary row is a blend of subject and background
## that keeps its background colour — the classic light halo around a cutout. Eroding
## removes that row; the blur puts a soft edge back so the silhouette does not staircase
## when the whole canvas is scaled up on a 1440p display.
static func erode_and_soften(a: PackedByteArray, w: int, h: int) -> void:
	var eroded := a.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if a[i] <= ALPHA_CUT:
				continue
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 \
					or a[i - 1] <= ALPHA_CUT or a[i + 1] <= ALPHA_CUT \
					or a[i - w] <= ALPHA_CUT or a[i + w] <= ALPHA_CUT:
				eroded[i] = 0
	var out := eroded.duplicate()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var s := 0
			for dy in [-w, 0, w]:
				s += eroded[i + dy - 1] + eroded[i + dy] + eroded[i + dy + 1]
			out[i] = s / 9
	for i in out.size():
		a[i] = out[i]


## Trim to the alpha bounding box, scale to fit, and compose onto a fresh canvas.
##
## `anchor_bottom` is the whole reason this is a function and not three lines at the
## call site. Enemies are placed by `combat.gd` with their feet on `PixelArt.STAND_LINE`,
## so transparent padding under the subject is that enemy hovering by exactly that much,
## in every fight, forever — a defect that is invisible in the file and obvious in the
## game. Bottom-anchored families get NO bottom pad: the lowest opaque pixel is the
## canvas's last row.
static func place(img: Image, a: PackedByteArray, canvas: Vector2i, anchor_bottom: bool) -> String:
	var box := bbox(a, img.get_width(), img.get_height())
	last_bbox = box
	if box.size.x <= 0 or box.size.y <= 0:
		return "empty bounding box"

	var sub := img.get_region(box)
	var pad_x := int(canvas.x * PAD)
	var pad_y := int(canvas.y * PAD)
	var avail := Vector2i(canvas.x - pad_x * 2,
		canvas.y - pad_y * (1 if anchor_bottom else 2))
	var scale: float = minf(float(avail.x) / float(box.size.x),
		float(avail.y) / float(box.size.y))
	var nw := maxi(1, int(round(box.size.x * scale)))
	var nh := maxi(1, int(round(box.size.y * scale)))
	sub.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

	var dst := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	dst.fill(Color(0, 0, 0, 0))
	var x := (canvas.x - nw) / 2
	var y := (canvas.y - nh) if anchor_bottom else (canvas.y - nh) / 2
	dst.blit_rect(sub, Rect2i(0, 0, nw, nh), Vector2i(x, y))
	img.copy_from(dst)
	return ""


static func alpha_of(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var out := PackedByteArray()
	out.resize(w * img.get_height())
	for y in img.get_height():
		for x in w:
			out[y * w + x] = int(round(img.get_pixel(x, y).a * 255.0))
	return out


static func apply_alpha(img: Image, a: PackedByteArray) -> void:
	var w := img.get_width()
	for y in img.get_height():
		for x in w:
			var c := img.get_pixel(x, y)
			c.a = a[y * w + x] / 255.0
			img.set_pixel(x, y, c)


static func opaque_fraction(a: PackedByteArray) -> float:
	var n := 0
	for v in a:
		if v > ALPHA_CUT:
			n += 1
	return float(n) / float(a.size())


static func bbox(a: PackedByteArray, w: int, h: int) -> Rect2i:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if a[y * w + x] <= ALPHA_CUT:
				continue
			x0 = mini(x0, x); x1 = maxi(x1, x)
			y0 = mini(y0, y); y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _border_indices(w: int, h: int) -> Array[int]:
	var out: Array[int] = []
	for x in w:
		out.append(x)
		out.append((h - 1) * w + x)
	for y in range(1, h - 1):
		out.append(y * w)
		out.append(y * w + w - 1)
	return out


static func _near(c: Color, bg: Vector3) -> bool:
	return absf(c.r - bg.x) <= TOL and absf(c.g - bg.y) <= TOL and absf(c.b - bg.z) <= TOL


# --- file plumbing, shared by both installers --------------------------------

## Straight off disk, not through ResourceLoader — the import cache can hand back the
## file as it was before the last write (strip_sparkle.gd learned this the hard way).
static func abs_path(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") else p


static func load_image(p: String) -> Image:
	var im := Image.new()
	if im.load(abs_path(p)) != OK:
		return null
	im.convert(Image.FORMAT_RGBA8)
	return im


static func sources(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var lower := f.to_lower()
		if lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") \
				or lower.ends_with(".webp"):
			out.append(dir_path.path_join(f))
		f = d.get_next()
	out.sort()
	return out
