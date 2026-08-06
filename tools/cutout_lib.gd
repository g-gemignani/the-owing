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
## A surviving component this big a fraction of the largest is a SECOND SUBJECT, not a
## speck — `despeckle` was never going to catch it, because it only ever asked whether an
## island was small (D194).
const STOWAWAY_MIN := 0.20
## ...and this far clear of the main body, vertically, as a fraction of the source height.
## The gap is what separates a stowaway from a subject that is simply made of two pieces:
## measured over all 310 installed cutouts, the only file with a large detached component
## AND air between the two is `rat_swarm`, at 55px of a 256px frame. Everything else with a
## big second island either overlaps it outright (the two arcs of `expose`, a moth's wings,
## a hexer's sleeves) or sits directly on it (`false_step`'s stair tread, 4px; the clasp of
## `coin_purse`, 3px). 5% of the frame is the gap between 4 and 55.
const STOWAWAY_GAP := 0.05
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
## How much local DETAIL a pixel may carry and still be called background: the standard
## deviation of luma in a 5x5 window, in 0-255 levels.
##
## This is the guard that keeps the fill OUT of the subject, and it is what tolerance alone
## cannot do (D153). A grey mummy on a slate field, brown fur on slate, a pale stone's
## shaded face on slate — all sit inside `TOL` of the field colour somewhere along their
## silhouette, and one such pixel is a doorway: the fill goes through it, spreads over the
## whole body from the inside, and `despeckle` keeps whichever scraps are still connected.
## A painting shredded into confetti, with no error printed anywhere.
##
## What separates them is not colour, it is that **a field has nothing in it.** The
## installers verify the border is flat before cutting (`BORDER_AGREE`), so background is
## smooth by contract, while bandages, fur, wood grain and a carved rune face are not.
## Measured over the 23 iso figures: field-coloured pixels sit at a median 0.0-2.3 levels of
## local deviation, and pixels far from the field at 7-20. 4.0 is the gap.
##
## A single-pixel Sobel gradient was tried first (D152) and is strictly worse: it stops at
## the OUTLINE, so it leaves a two-pixel rim of field colour all the way around every
## subject — the shop, the fire and the ogre all shipped wearing one — and it says nothing
## about a low-contrast flank where the outline has faded.
const STD_FLAT := 4.0
## Radius of the window that deviation is measured in. 2 (a 5x5 box) is the smallest window
## that still separates a smooth field from painted detail; at radius 1 a soft airbrushed
## flank measures as flat as the field does.
const STD_R := 2
## How far from the background an opaque pixel may be and still have its alpha GRADED by how
## close its colour is to the field, in pixels.
##
## The band exists because the flatness gate necessarily stops short: a window centred two
## pixels outside the subject already touches it, so the last two pixels of field read as
## detail and survive the fill. Eroding them off is what the pipeline used to do and it cuts
## real edges too. Grading them by colour is exact — a rim that IS the field goes fully
## transparent, an inked outline stays fully opaque, and a genuinely soft edge lands in
## between, which is what it already was.
const EDGE_BAND := 3
## How much brighter than the field a pixel has to be to be called the subject's own light
## rather than the subject (`clear_bloom`), in 0-1 luma. Small on purpose: the condition that
## does the work is reachability, and this only has to exclude the field's own noise.
const BLOOM_LIFT := 0.008
## Mean local deviation a trapped pocket may carry and still be cleared as field, in 0-255
## levels — tighter than `STD_FLAT`, and it is a SEPARATE question from the one the border
## fill asks (D153).
##
## Clearing a pocket punches a hole in a subject if the judgement is wrong, so the evidence
## has to be stronger than "flat enough to fill through". Untouched field sealed between two
## legs is genuinely featureless; a shadowed patch inside an arm is flat-ish, tight-coloured,
## enclosed, and is not. Measured over the 23 iso figures, that is the whole difference:
##
##   real, cleared   shop 497px/1.45, 218px/1.88 · caster 616px/1.04, 313px/2.29
##                   swarm 149px/2.11 · hound 110px/1.53 · ogre 60px/1.82, 32px/2.21
##   false, kept     mummy 41px/3.50, 21px/3.38 · boss 42px/3.43 · elite 31px/2.96
##                   rune stone 15px/3.01 · swarm 44px/2.83
##
## The false ones are what put a transparent notch in a mummy's arm, and area alone does not
## separate them — the ogre's real armpit gap is smaller than the mummy's false one.
const POCKET_STD := 2.4
## Luma spread, in 0-255 levels, that the region a pocket GREW INTO may carry and still be
## cleared. Asked after the growth, of everything the growth took — and it is a third
## question again, not a restatement of `POCKET_STD` (D###).
##
## `POCKET_STD` averages the LOCAL deviation, so it is blind to a gradient: a smooth
## airbrushed sac spanning a third of the frame is flat at every individual pixel and
## nothing like one colour overall. It passes, and then the growth runs at the ordinary
## `TOL` and takes the whole sac. The Brood-Mother's abdomen went exactly that way — 4009 px
## of painted egg-sac, enclosed by her own legs, base tone within `HOLE_TOL` of the slate
## field, 16 levels of spread across it — and so did seven other installed cutouts.
##
## Testing the SEED instead would catch none of them. The seed is by construction the
## pixels within `HOLE_TOL` of the field, so its spread is bounded near zero whatever it is
## sitting on. What has to be checked is the result: **a field is one colour; paint is not.**
## Measured over the 18 enclosed pockets in the installed enemy, relic and power sets:
##
##   real, cleared   leather_wrap 0.25 · bramble 0.69 · bone_picker 1.09 · blight 1.19
##                   crown_of_thorns 1.25 · cinder_knight 1.45, 1.47 · foresight 1.66
##                   siphon 1.72, 1.85
##   false, kept     the_gardener 3.08 · grave_sexton 3.77 · bone_picker 5.51
##                   crypt_hound 5.73 · rot_priest 13.37 · ember_hound 14.82
##                   brood_mother 16.06 · ancient_battery 24.03
##
## Measured on the 256px OUTPUTS rather than on the sources, which are gone — so the two
## pixels of each pocket that touch the subject were excluded, because `place` scales with
## LANCZOS and the ring it leaves carries the subject's colour whatever the pocket is. Here
## the question is asked before any resize, so no such exclusion is needed. 2.5 is the gap.
const POCKET_SPREAD := 2.5
## The same question asked of a FINISHED file (`find_gouges`), where three things differ.
##
## `GOUGE_CORE_R`: the pocket is measured two pixels in from the subject. `place` scales
## with LANCZOS, which rings, so the boundary of a pocket carries the subject's colour
## whatever the pocket is. Over the whole pocket the ten real ones measure 2.2-3.6 and the
## gap to the eight gouges closes to nothing; two pixels in, they measure under 1.9.
## `GOUGE_CORE_MIN`: below this much interior there is not enough to measure, and what has
## that little interior is a sliver — the gap between two limbs.
## `GOUGE_MIN`: and the pocket has to be a body part, not a nick.
const GOUGE_CORE_R := 2
const GOUGE_CORE_MIN := 50
const GOUGE_MIN := 200
## And `POCKET_SPREAD` only ever REFUSES a region this big a fraction of the frame.
##
## The two mistakes here are not the same size, so the guard should not police them the same
## way. Filling a 300px pocket that was really paint is a blemish; filling a 60,000px one is
## a hole through a monster, which is what happened, and which nothing downstream noticed.
## Conversely a refusal costs a slab of field left inside the subject — tolerable once,
## loudly reported (`kept_pockets`), and fixed by looking at the file.
##
## So the guard is pointed at the catastrophic end only. The Brood-Mother's abdomen was 6.1%
## of the frame; 1% is comfortably below that and above every marginal call in the set, and
## it keeps the guard away from the small pockets where a ring artefact or a lit patch of
## floor could tip the measurement either way.
const POCKET_GUARD_MIN := 0.01

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
	kept_pockets = 0
	var a := alpha_of(img)
	var matted := false
	if opaque_fraction(a) > 0.995:
		# No usable alpha: the generator handed back an opaque painting. Cut it.
		var reason := matte(img, a)
		if reason != "":
			return reason
		matted = true
	var check := _survives(a, w, h)
	if check != "":
		return check
	if matted:
		# Grade the rim by colour rather than eroding it off. `erode_and_soften` is still the
		# answer for an image that arrived WITH alpha, where there is no field colour to
		# measure against and a 1px erode plus a blur is the best guess available.
		feather_edge(img, a, last_field, w, h)
		# And despeckle AGAIN: grading a rim to zero can cut a one-pixel filament that was
		# holding a speck onto the body, and the speck is then an island that the first pass
		# never saw. Eight of them survived on the first mummy, at 1-6 px each.
		despeckle(a, w, h)
	else:
		erode_and_soften(a, w, h)
	# Only on the bottom-anchored families, because that anchor is the premise the check
	# rests on: an enemy plate is ONE figure standing on `PixelArt.STAND_LINE`, so a second
	# body floating clear above it is a stowaway. A relic or a power icon is a composition
	# and may legitimately be two pieces with air between them.
	if anchor_bottom:
		var stow := stowaways(a, w, h)
		if stow != "":
			return stow
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
	kept_pockets = 0
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
## How many looked trapped and turned out to be PAINT, so were left alone (`POCKET_SPREAD`).
## Worth printing rather than swallowing: it is the one signal that a subject has a large
## enclosed area the same colour as its own field, which is also the shape of a real
## background pocket the tool has now declined to cut. Either the art is fine and this is
## the guard working, or there is a slab of field left in the file.
static var kept_pockets := 0
## Luminance spread of the last `mono_alpha()` — how much glyph there was to find.
static var last_mono_range := 0.0
## The field colour the last `matte()` sampled, for the feather pass that follows it.
static var last_field := Vector3.ZERO
## Trim box of the last `place()`, in the SOURCE image's coordinates. `install_sheet.gd`
## checks it against the cell it came from: a subject touching its own cell edge means
## the grid is misaligned and that glyph is clipped.
static var last_bbox := Rect2i()
## How many stowaway subjects the last `cut()` removed. Only ever non-zero when the caller
## asked for it — see `drop_stowaways`.
static var dropped_stowaways := 0
## Cut a stowaway out instead of refusing the image. OFF by default and it should stay
## that way: the honest fix for a painting with two monsters in it is another painting,
## and a tool that quietly deletes half of what it was handed cannot tell a stowaway from
## a floating limb the artist meant. Turned on deliberately, per run, to salvage a file
## whose good subject is already on disk and whose source is gone.
static var drop_stowaways := false

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

	# 4-connected flood from every border pixel that IS the background, and it may only
	# enter FLAT pixels. Connectivity alone is what stops a patch of stone inside the subject
	# that happens to match the field from being punched out into a hole; connectivity plus
	# the flatness gate is what stops the fill walking INTO a subject whose own colour agrees
	# with the field through one shaded pixel on its flank (D152, D153).
	var detail := _local_std(img, w, h)
	last_field = bg
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
			if seen[j] == 0 and detail[j] < STD_FLAT and _near(img.get_pixel(nx, ny), bg):
				seen[j] = 1
				stack.append(j)

	fill_trapped(img, a, bg, w, h, detail)
	clear_bloom(img, a, bg, w, h, detail)
	return ""


## Is pocket `id` the untouched field: enclosed, big enough to matter, and featureless.
static func _is_field(id: int, sizes: Array[int], open: Array[bool], rough: Array[float],
		min_area: int) -> bool:
	return not open[id] and sizes[id] >= min_area and rough[id] < POCKET_STD


## Clear the subject's own LIGHT off the field.
##
## The campfire is painted with a glow that spills onto the background for a dozen pixels,
## and that spill is lit field rather than fire: keep it and the marker wears a grey disc on
## the dungeon floor, because what shows through is the source's slate showing through its
## own bloom. No colour rule reaches it — the spill is far from the field colour by
## construction, since being lit is what changed it — and no flatness rule reaches it either,
## because the tolerance test comes first.
##
## What a bloom is, precisely: **flat, brighter than the field, and reachable from outside
## without crossing anything dark or detailed.** Light spills; ink does not. That is what
## separates it from a pale subject on a slate field, which is the case this must not touch:
## a mummy's bandages are also flat and also brighter than the field, but reaching them from
## the frame means crossing the dark line drawn around the mummy.
##
## Measured over the 23 iso figures, this clears 1952 px on the campfire, 10 px on the rune
## stone, 2 px on one caster and nothing at all on the other twenty. A pass that removes a
## defect on one file and cannot find anything to do on the rest is the right shape for a
## rule about light. Dropping the brightness condition instead — flat and reachable, any
## colour — clears the fire and destroys both mummies, because a soft flank is a doorway
## again.
static func clear_bloom(img: Image, a: PackedByteArray, bg: Vector3, w: int, h: int,
		detail: PackedFloat32Array) -> int:
	var field_lum: float = 0.299 * bg.x + 0.587 * bg.y + 0.114 * bg.z
	var stack: Array[int] = []
	for i in w * h:
		if a[i] <= ALPHA_CUT:
			stack.append(i)
	var cleared := 0
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x: int = i % w
		var y: int = i / w
		for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j: int = ny * w + nx
			if a[j] <= ALPHA_CUT or (j < detail.size() and detail[j] >= STD_FLAT):
				continue
			var c := img.get_pixel(nx, ny)
			if 0.299 * c.r + 0.587 * c.g + 0.114 * c.b <= field_lum + BLOOM_LIFT:
				continue
			a[j] = 0
			cleared += 1
			stack.append(j)
	return cleared


## Local standard deviation of luma, in 0-255 levels, over a (2 * STD_R + 1) box.
##
## Computed from summed-area tables rather than a window per pixel: this runs over every
## pixel of every source a sheet installer opens, and the naive form is 25 reads per pixel
## for the same answer.
static func _local_std(img: Image, w: int, h: int) -> PackedFloat32Array:
	var s1 := PackedFloat64Array()
	var s2 := PackedFloat64Array()
	var sw := w + 1
	s1.resize(sw * (h + 1))
	s2.resize(sw * (h + 1))
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var v: float = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
			var i := (y + 1) * sw + (x + 1)
			s1[i] = s1[i - sw] + s1[i - 1] - s1[i - sw - 1] + v
			s2[i] = s2[i - sw] + s2[i - 1] - s2[i - sw - 1] + v * v
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		var y0: int = maxi(0, y - STD_R)
		var y1: int = mini(h - 1, y + STD_R)
		for x in w:
			var x0: int = maxi(0, x - STD_R)
			var x1: int = mini(w - 1, x + STD_R)
			var n: float = float((y1 - y0 + 1) * (x1 - x0 + 1))
			var a1: float = s1[(y1 + 1) * sw + x1 + 1] - s1[y0 * sw + x1 + 1] \
				- s1[(y1 + 1) * sw + x0] + s1[y0 * sw + x0]
			var a2: float = s2[(y1 + 1) * sw + x1 + 1] - s2[y0 * sw + x1 + 1] \
				- s2[(y1 + 1) * sw + x0] + s2[y0 * sw + x0]
			var mean: float = a1 / n
			out[y * w + x] = sqrt(maxf(0.0, a2 / n - mean * mean))
	return out


## Grade the alpha of the pixels just inside the background by how close their colour is to
## the field: field colour goes transparent, an inked outline stays opaque, a soft edge lands
## where it already was. Replaces the erode-and-blur pass for anything that was matted, and
## it is what removes the rim the flatness gate has to leave behind (D153).
static func feather_edge(img: Image, a: PackedByteArray, bg: Vector3, w: int, h: int) -> void:
	var band := PackedByteArray()
	band.resize(w * h)
	for y in h:
		for x in w:
			if a[y * w + x] > ALPHA_CUT:
				continue
			for dy in range(-EDGE_BAND, EDGE_BAND + 1):
				var ny := y + dy
				if ny < 0 or ny >= h:
					continue
				for dx in range(-EDGE_BAND, EDGE_BAND + 1):
					var nx := x + dx
					if nx < 0 or nx >= w:
						continue
					var j := ny * w + nx
					if a[j] > ALPHA_CUT:
						band[j] = 1
	for i in w * h:
		if band[i] == 0:
			continue
		var c := img.get_pixel(i % w, i / w)
		var d: float = maxf(maxf(absf(c.r - bg.x), absf(c.g - bg.y)), absf(c.b - bg.z))
		var t: float = clampf((d - HOLE_TOL) / (TOL - HOLE_TOL), 0.0, 1.0)
		a[i] = int(round(float(a[i]) * t))


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
static func fill_trapped(img: Image, a: PackedByteArray, bg: Vector3, w: int, h: int,
		detail: PackedFloat32Array = PackedFloat32Array()) -> int:
	var min_area := int(w * h * HOLE_MIN)
	var guard_min := int(w * h * POCKET_GUARD_MIN)
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var sizes: Array[int] = []
	var open: Array[bool] = []   # touches the frame edge, therefore not trapped
	var rough: Array[float] = []   # mean local deviation: how featureless it really is
	# A pocket is field, and field is FLAT (D153). Requiring that of every pixel the
	# component grows over is what stops this pass undoing the border fill's own guard:
	# with the fill correctly kept out of a subject whose colour agrees with the field, a
	# body sealed inside its own outline is exactly what "enclosed and field-coloured"
	# describes, and the first version of this reached the mummies from the inside and
	# shredded them all over again.
	for start in w * h:
		if comp[start] >= 0 or a[start] <= ALPHA_CUT or not _tight(img, start, w, bg):
			continue
		if start < detail.size() and detail[start] >= STD_FLAT:
			continue
		var id := sizes.size()
		var n := 0
		var detail_sum := 0.0
		var edge := false
		var stack: Array[int] = [start]
		comp[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			if i < detail.size():
				detail_sum += detail[i]
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
				if comp[j] < 0 and a[j] > ALPHA_CUT and _tight(img, j, w, bg) \
						and (j >= detail.size() or detail[j] < STD_FLAT):
					comp[j] = id
					stack.append(j)
		sizes.append(n)
		open.append(edge)
		rough.append(detail_sum / float(maxi(1, n)))

	var seeds: Array[int] = []
	for id in sizes.size():
		if _is_field(id, sizes, open, rough, min_area):
			seeds.append(id)
	kept_pockets = 0
	filled_pockets = 0
	if seeds.is_empty():
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
	#
	# One pocket at a time, and the clear is not committed until the region is measured:
	# what the growth TOOK is the only thing that can answer whether this was field or a
	# painted body sealed inside its own outline (`POCKET_SPREAD`). Grown together in one
	# pass, as this used to be, a gouge and a real pocket are indistinguishable afterwards
	# — there is nothing left to attribute to either.
	var seen := PackedInt32Array()
	seen.resize(w * h)
	seen.fill(-1)
	for id in seeds:
		var region: Array[int] = []
		var stack2: Array[int] = []
		for i in w * h:
			if comp[i] == id:
				seen[i] = id
				stack2.append(i)
		while not stack2.is_empty():
			var i: int = stack2.pop_back()
			region.append(i)
			var x: int = i % w
			var y: int = i / w
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				# and the growth is gated the same way the border fill is, for the same reason
				if seen[j] != id and a[j] > ALPHA_CUT \
						and (j >= detail.size() or detail[j] < STD_FLAT) \
						and _near(img.get_pixel(nx, ny), bg):
					seen[j] = id
					stack2.append(j)
		# Measured on the region's INTERIOR. Its boundary is the ramp where the field meets
		# the subject's outline, and a ramp from field to ink is 40 levels wide whatever it
		# encloses — measured over the whole region, `leather_wrap`'s pocket reads the same as
		# the Brood-Mother's abdomen and the question answers itself wrong every time.
		var inner := _interior(region, w, h, GOUGE_CORE_R)
		if region.size() >= guard_min and inner.size() >= GOUGE_CORE_MIN \
				and luma_spread(img, inner, w) >= POCKET_SPREAD:
			# Paint, not field. Leave it alone: the cost of being wrong here is a flat slab
			# of background behind a rib cage, and the cost of being wrong the other way is
			# a hole through a monster.
			kept_pockets += 1
			continue
		for i in region:
			a[i] = 0
		filled_pockets += 1
	return filled_pockets


## The members of `region` that are at least `r` pixels clear of its boundary.
static func _interior(region: Array[int], w: int, h: int, r: int) -> Array[int]:
	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in region:
		mask[i] = 1
	var kept := _erode(mask, w, h, r)
	var out: Array[int] = []
	for i in region:
		if kept[i] == 1:
			out.append(i)
	return out


## Standard deviation of luma over `members`, in 0-255 levels. A field is one colour and
## measures near zero; paint does not.
static func luma_spread(img: Image, members: Array[int], w: int) -> float:
	if members.is_empty():
		return 0.0
	var s := 0.0
	var s2 := 0.0
	for i in members:
		var c := img.get_pixel(i % w, i / w)
		var v: float = (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) * 255.0
		s += v
		s2 += v * v
	var n := float(members.size())
	var mean := s / n
	return sqrt(maxf(0.0, s2 / n - mean * mean))


## Enclosed transparent pockets of a FINISHED cutout that are worth LOOKING at: big enough
## to be a body part, with an interior that is not one colour. Returns
## `{"pixels": Array[int], "core": int, "spread": float}` per pocket, biggest first.
##
## **This is a shortlist, not a verdict, and the difference is the whole point.** Run over
## the installed enemy, relic and power sets it returns eight pockets, and looking at them
## one is the defect (the Brood-Mother's abdomen) and seven are correct background — the
## gap between a hound's legs, the space under a sexton's robe, the slot between the ancient
## battery's pillars. They score high because the field BEHIND the subject is shadowed or
## lit, so the untouched field in a pocket genuinely carries a gradient. Nothing measurable
## on a finished file separated the eight: spread does not, and neither does the residual
## after fitting a plane, which tracks it at 0.76-1.00 (D195).
##
## So this exists to point a person at candidates, and `refill_pockets.gd` prints them and
## restores only what it is told to. It is deliberately NOT wired into `test_art.gd`: an
## assertion with seven false positives out of eight is not a measure, it is noise that
## teaches the suite to be ignored.
##
## The pipeline-side question is different and answerable, because `fill_trapped` still has
## the source and the sampled field colour to compare against — see `POCKET_SPREAD`.
static func find_gouges(img: Image, w: int, h: int) -> Array[Dictionary]:
	var clear := PackedByteArray()
	clear.resize(w * h)
	for y in h:
		for x in w:
			clear[y * w + x] = 1 if img.get_pixel(x, y).a * 255.0 <= float(ALPHA_CUT) else 0
	var core := _erode(clear, w, h, GOUGE_CORE_R)

	var seen := PackedByteArray()
	seen.resize(w * h)
	var out: Array[Dictionary] = []
	for start in w * h:
		if seen[start] == 1 or clear[start] == 0:
			continue
		var edge := false
		var members: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			members.append(i)
			var x: int = i % w
			var y: int = i / w
			# a region that reaches the frame is the surround, not a pocket
			if x == 0 or y == 0 or x == w - 1 or y == h - 1:
				edge = true
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j: int = ny * w + nx
				if seen[j] == 0 and clear[j] == 1:
					seen[j] = 1
					stack.append(j)
		if edge or members.size() < GOUGE_MIN:
			continue
		var inner: Array[int] = []
		for i in members:
			if core[i] == 1:
				inner.append(i)
		# too thin to judge, and a sliver is a gap between two limbs
		if inner.size() < GOUGE_CORE_MIN:
			continue
		var spread := luma_spread(img, inner, w)
		if spread < POCKET_SPREAD:
			continue
		out.append({"pixels": members, "core": inner.size(), "spread": spread})
	out.sort_custom(func(p, q): return int(p["pixels"].size()) > int(q["pixels"].size()))
	return out


## Shrink a mask by `r` pixels. Used to reach a pocket's INTERIOR, clear of the LANCZOS
## ring `place` leaves where the pocket meets the subject.
static func _erode(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			var ok := true
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h or mask[ny * w + nx] == 0:
						ok = false
			out[y * w + x] = 1 if ok else 0
	return out


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
	var lab := label(a, w, h)
	var comp: PackedInt32Array = lab[0]
	var sizes: Array = lab[1]
	if sizes.is_empty():
		return -1
	var biggest := 0
	for n in sizes:
		biggest = maxi(biggest, int(n))
	var floor_size := int(biggest * ISLAND_MIN)
	var dropped := 0
	for id in sizes.size():
		if int(sizes[id]) < floor_size:
			dropped += 1
	if dropped == 0:
		return 0
	for i in w * h:
		var id := comp[i]
		if id >= 0 and int(sizes[id]) < floor_size:
			a[i] = 0
	return dropped


## Four-connected components of the opaque pixels. Returns `[comp, sizes, boxes]`:
## a per-pixel label (-1 where transparent), each label's pixel count, and each label's
## bounding box. One flood fill serving both the size question `despeckle` asks and the
## where question `_stowaways` asks, so the two cannot disagree about what a component is.
static func label(a: PackedByteArray, w: int, h: int) -> Array:
	var comp := PackedInt32Array()
	comp.resize(w * h)
	comp.fill(-1)
	var sizes: Array[int] = []
	var boxes: Array[Rect2i] = []
	for start in w * h:
		if a[start] <= ALPHA_CUT or comp[start] >= 0:
			continue
		var id := sizes.size()
		var n := 0
		var minx := w
		var maxx := 0
		var miny := h
		var maxy := 0
		var stack: Array[int] = [start]
		comp[start] = id
		while not stack.is_empty():
			var i: int = stack.pop_back()
			n += 1
			var x: int = i % w
			var y: int = i / w
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
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
		boxes.append(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))
	return [comp, sizes, boxes]


## A SECOND SUBJECT in a one-subject frame: big enough to be a body, with air between it
## and the one standing on the floor. Returns "" when the frame is clean, the refusal
## otherwise — or drops it and returns "" when `drop_stowaways` is set.
##
## This is the hole `despeckle` leaves and cannot close. Despeckle asks one question, "is
## this island small", and answers it well; a generator that paints two monsters hands
## back two islands that are both large, both survive, and the trim box then stretches
## around BOTH. The subject is not corrupted — it is squeezed into whatever fraction of
## the canvas the intruder left it, which in the game is an enemy rendered at a third of
## its size with someone else's legs above it. Nothing in the pipeline said a word, and
## the file looks like art that was simply drawn badly (D194).
##
## Which one is the subject is decided by the floor, not by mass: the keeper is the
## component reaching LOWEST, because that is the one whose feet are on the standing line.
## In the rat plate the intruder was the bigger of the two.
static func stowaways(a: PackedByteArray, w: int, h: int) -> String:
	dropped_stowaways = 0
	var lab := label(a, w, h)
	var comp: PackedInt32Array = lab[0]
	var sizes: Array = lab[1]
	var boxes: Array = lab[2]
	if sizes.size() < 2:
		return ""
	var biggest := 0
	for n in sizes:
		biggest = maxi(biggest, int(n))
	var gap := maxi(1, int(h * STOWAWAY_GAP))

	# The subject: lowest bottom edge among the components substantial enough to be one.
	var keeper := -1
	for id in sizes.size():
		if float(sizes[id]) / float(biggest) < STOWAWAY_MIN:
			continue
		if keeper < 0 or (boxes[id] as Rect2i).end.y > (boxes[keeper] as Rect2i).end.y:
			keeper = id
	if keeper < 0:
		return ""

	var kept: Rect2i = boxes[keeper]
	var found: Array[int] = []
	for id in sizes.size():
		if id == keeper or float(sizes[id]) / float(biggest) < STOWAWAY_MIN:
			continue
		var b: Rect2i = boxes[id]
		# Vertical clearance between the two boxes. Negative overlap is a gap.
		if maxi(kept.position.y, b.position.y) - mini(kept.end.y, b.end.y) > gap:
			found.append(id)
	if found.is_empty():
		return ""

	if not drop_stowaways:
		var parts: Array[String] = []
		for id in found:
			var b: Rect2i = boxes[id]
			parts.append("%dx%d at (%d,%d), %d%% the size of the subject" % [
				b.size.x, b.size.y, b.position.x, b.position.y,
				int(round(100.0 * float(sizes[id]) / float(sizes[keeper])))])
		return ("a second subject in the frame — %s. One monster per image: the trim box "
			+ "would stretch around both and the real subject would be installed at a "
			+ "fraction of its size. Repaint it, or pass --drop-stowaways to cut it out."
			) % "; ".join(parts)

	# Everything clear of the keeper goes, not just the large ones: a filament of the
	# intruder left behind is a speck that drags the trim box right back where it was.
	var doomed := {}
	for id in sizes.size():
		if id == keeper:
			continue
		var b: Rect2i = boxes[id]
		if maxi(kept.position.y, b.position.y) - mini(kept.end.y, b.end.y) > gap:
			doomed[id] = true
	for i in w * h:
		if comp[i] >= 0 and doomed.has(comp[i]):
			a[i] = 0
	dropped_stowaways = found.size()
	return ""


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
