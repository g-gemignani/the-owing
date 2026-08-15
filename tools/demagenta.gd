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
## sits far below both other channels while the pixel stays saturated. So it can be run
## without knowing which field each file was cut against, and re-run safely: once the key is
## gone it finds nothing and writes nothing.
##
## **POINT IT AT CREATURE CUTOUTS ONLY (D294):**
##
##     assets/art/enemies/  assets/art/iso/  assets/art/iso/foe/
##
## That is a restriction this file used to lack, and it was wrong to lack it. `assets/art/ui/`
## is COMPUTED by `tools/gen_ui_kit.gd` and any edit here is undone by the next generate; the
## rest is a false-positive problem the hue test cannot solve from colour alone:
##
##     assets/art/cards/    100% opaque illustrations, never cut against a key at all
##     assets/art/relics/   `merchants_seal` is a purple wax seal, `reliquary_heart` a violet glow
##     assets/art/powers/   `overwhelm` is a violet mace, `twice_over` a violet ring
##     assets/art/ui/       `frame_card_rarity_3` is Epic, whose whole job is a violet inlay
##
## Measured, the card directory alone offered 46 files and 46,885 pixels of "key" that is
## paint. `PAINT_RATIO` refuses the worst of these — the seal, the Epic frame, the mycelial
## lord — but it is a guard against an accident, not a licence: `twice_over` and
## `reliquary_heart` both sit under its threshold and would be quietly drained.
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
## happens to lean blue-red. **Was 0.35, and that is the number the whole remaining defect
## was hiding behind (D267.)**
##
## The key is pure (1, 0, 1), so a rim that is key BLENDED WITH A DARK SUBJECT keeps the hue
## and loses the brightness. Measured over the 110 installed iso files: every leaning pixel
## in the set tops out between 0.30 and 0.349, and not one of them reaches 0.35. So the gap
## rule and the brightness rule were reading the same rim from opposite ends, and 14,556
## pixels across 89 of the 110 files walked out between them — a pink hairline on nearly
## every creature on the floor, on the day D202 reported none. It reported none because it
## measured with this threshold.
const KEY_MIN := 0.12
## What makes that lower floor safe, and it is the rule the brightness one was always a proxy
## for: the key has NO GREEN, so what survives of it keeps green near zero in ABSOLUTE terms
## rather than merely below the other two channels.
##
## Measured across the same 110 files: of the 14,556 pixels that pass `KEY_GAP`, every one
## has green under 0.15 and 13,259 of them under 0.05, and not one pixel with a gap over 0.30
## reaches green 0.06. Painted violet fails the other way round: the mycelial lord's cap sits
## at roughly (0.6, 0.5, 0.75), where green is HIGH and the gap is 0.1 — so it misses both
## halves of this test rather than one, which is what makes lowering the brightness safe.
const KEY_GREEN_MAX := 0.16
## **That ceiling was measured on the ISO figures and does not survive a change of subject
## (D294).** On the 35 combat plates in `assets/art/enemies/` the tool converged, reported
## nothing left, and thirteen creatures still wore a plainly pink outline. Every surviving
## pixel passes `KEY_GAP` and fails here by a hair: green 0.161 on the bog lurker, 0.165 on
## the crypt hound, 0.173 on the ember hound, 0.220 on the forge hound, 0.247 on the
## gardener. The key is pure and green-free; what it is BLENDED WITH is not, and these
## subjects are grey-green where the iso figures were not.
##
## Raising the ceiling for every pixel is the wrong fix — it puts the mycelial lord's violet
## cap back in range, which is the subject `KEY_GREEN_MAX` exists to protect. What separates
## them is not the colour, it is WHERE. Key bleed is an EDGE artefact: it is what LANCZOS
## mixed across the alpha boundary, so it hugs that boundary. Painted violet does not.
##
## Measured over the 35 plates: 30,300 of the 30,957 leaning pixels sit within `RIM_R` of
## transparency, and the one subject that leans from the inside — the mycelial lord, 7,773
## interior pixels — tops out at a gap of 0.125 anywhere on the canvas, against the 0.22
## `KEY_GAP` already demands. So the cap is excluded twice over whatever this second ceiling
## says, and the relaxation cannot reach it.
const KEY_GREEN_MAX_RIM := 0.30
## How close to a transparent pixel counts as the rim. The CANVAS border deliberately does
## not count: these sprites are foot-anchored with the feet flush to the bottom edge, so
## treating the border as an edge would put every foot inside the relaxed rule.
const RIM_R := 4
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
## The same dilute key, on the SILHOUETTE EDGE rather than under the feet, and it is most of
## what a player actually sees (D294). After the strict pass converged on the combat plates,
## ~25,000 pixels were still leaning purple, and nearly all of them sat within `RIM_R` of
## transparency at gaps too low for `KEY_GAP` — the pink outline the eye reads as "magenta
## that did not come off".
##
## The contact band cannot reach them and a looser `TINT_GAP` everywhere would drain the
## mycelial lord, so this needs its own floor. Measured, the rim gaps bucket like this:
##
##     rim gap        0.06-0.10  0.10-0.14  0.14-0.18  0.18-0.22
##     mycelial lord        514         30          0          0
##     forge hound          403        595       1106       1756
##     ossuary wretch       595        984       1311       1485
##     crypt hound          161        416        755       1027
##
## The one subject whose violet is PAINT stops dead at 0.14 and every subject wearing bleed
## has its mass above it. So 0.14 is not a tuned number, it is where the two populations
## stop overlapping — and the lord loses exactly zero pixels to this rule.
const RIM_TINT_GAP := 0.14
## Rings searched for clean paint to borrow, growing until something is found.
const MAX_R := 6
## How many times to sweep. Each pass reaches one ring further into a thin feature.
const PASSES := 6
## How many times to run the whole strict-then-tint cycle before giving up on it settling.
## Measured, two is enough on every file in the project and the third round finds nothing.
const ROUNDS := 4
## A subject that is violet BY DESIGN, refused rather than cleaned (D294).
##
## The rim rule assumes purple on the outline is bleed, and for a creature it is. For a subject
## drawn as a violet object it is the object. What tells them apart is how much of the SUBJECT
## leans purple away from its own edge — measured as interior lean above `RIM_TINT_GAP` over
## total opaque area. Across the three directories this tool is allowed near:
##
##     bleed    every creature plate and iso figure     0.0% - 2.6%
##     paint    mycelial_lord_n 38.6%   mycelial_lord_s 35.2%   (enemies plate the same)
##
## A share and not a ratio, because a ratio against the RIM is measured on a moving target:
## cleaning removes rim lean and leaves interior lean, so the second run reads a file it has
## already fixed as paint. Interior pixels are never touched, so this number does not move.
##
## It is a guard against an accident inside those three directories, not a classifier — the
## icons the header forbids straddle it (`twice_over` 19.3%, `merchants_seal` 4.5%).
const PAINT_SHARE := 0.10


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
	print("%-26s %8s %8s %8s %s" % ["file", "repaired", "cleared", "detinted", "verdict"])
	var files := 0
	var total_fix := 0
	var total_cut := 0
	var total_tint := 0
	var skipped := 0
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
				if int(r[3]) == 1:
					skipped += 1
					print("%-26s %8s %8s %8s %s" % [f, "-", "-", "-",
						"SKIPPED: violet interior, this is paint"])
				elif int(r[0]) > 0 or int(r[1]) > 0 or int(r[2]) > 0:
					files += 1
					total_fix += int(r[0])
					total_cut += int(r[1])
					total_tint += int(r[2])
					print("%-26s %8d %8d %8d %s" % [f, int(r[0]), int(r[1]), int(r[2]),
						"would rewrite" if dry else "rewritten"])
			f = da.get_next()
		da.list_dir_end()

	print("\n%d files touched, %d px repainted, %d px cleared, %d px detinted, %d refused%s" % [
		files, total_fix, total_cut, total_tint, skipped, " (dry run)" if dry else ""])
	if files > 0 and not dry:
		print("Run `godot --headless --import`.")
	quit(0)


## Is this the chroma key rather than paint?
##
## `rim` says the pixel sits within `RIM_R` of transparency, which is the only place the key
## can have got in. It buys a looser green ceiling and nothing else: the gap and brightness
## rules are unchanged, so a subject that is violet in its own right is still refused there.
static func _is_key(c: Color, rim: bool = false) -> bool:
	if minf(c.r, c.b) - c.g <= KEY_GAP or maxf(c.r, c.b) <= KEY_MIN:
		return false
	return c.g < (KEY_GREEN_MAX_RIM if rim else KEY_GREEN_MAX)


## Opaque pixels within `RIM_R` of a transparent one. Built once per image because the repair
## sweeps six times and the answer cannot change: repainting rewrites RGB and never alpha.
static func _rim_mask(img: Image) -> PackedByteArray:
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a * 255.0 > 8.0 else 0
	var rim := PackedByteArray()
	rim.resize(w * h)
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				continue
			for dy in range(-RIM_R, RIM_R + 1):
				var ny := y + dy
				if ny < 0 or ny >= h:
					continue          # the canvas border is not an edge — see `RIM_R`
				for dx in range(-RIM_R, RIM_R + 1):
					var nx := x + dx
					if nx < 0 or nx >= w:
						continue
					if solid[ny * w + nx] == 0:
						rim[y * w + x] = 1
						break
				if rim[y * w + x] == 1:
					break
	return rim


## The diluted key, in the two places it survives: a drop shadow in the contact band at the
## bottom of the canvas, and a hairline on the silhouette edge. Each carries its own floor —
## see `TINT_GAP` and `RIM_TINT_GAP` — because the contact band is a place nothing paints and
## the rim is not.
static func _is_tint(c: Color, y: int, h: int, rim: bool) -> bool:
	var gap: float = minf(c.r, c.b) - c.g
	# The rim clause has NO ceiling, and that is a correction rather than a widening. With one
	# at `KEY_GAP` the two rules left a hole between them: a pixel over the gap AND over the
	# relaxed green ceiling was refused by the strict pass for being too green and by this one
	# for leaning too hard. The ember hound kept a pink shoulder at gap 0.231 / green 0.349 and
	# the forge hound a pink tail at 0.455 / 0.302, both of them sitting in that hole. The
	# strict pass runs first and takes what it can key; whatever it hands back on the rim has
	# already failed to be paint.
	if rim and gap > RIM_TINT_GAP:
		return true
	if gap > KEY_GAP:
		return false          # the strict pass owns this one
	return float(y) >= float(h) * (1.0 - TINT_BAND) and gap > TINT_GAP


## Settle the file: strict pass, then tint pass, then again until a round changes nothing.
##
## One round is not a fixed point and the second one is not cosmetic. The tint pass rewrites
## green on the rim, which moves those pixels into range for the STRICT pass next time round —
## measured on the combat plates, round one did 1,835 + 26,612 pixels and round two found a
## further 119 + 154 across three files. It used to take two invocations to reach zero, and
## nothing said so: the tool reported "rewritten", looked finished, and had work left.
func _clean(path: String, dry: bool) -> Array:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		return [0, 0, 0]
	img.convert(Image.FORMAT_RGBA8)
	var rim := _rim_mask(img)
	if _is_painted_violet(img, rim):
		return [0, 0, 0, 1]
	var fix := 0
	var cut := 0
	var tint := 0
	for _round in ROUNDS:
		var r := _round_once(img, rim)
		fix += int(r[0])
		cut += int(r[1])
		tint += int(r[2])
		if int(r[0]) == 0 and int(r[1]) == 0 and int(r[2]) == 0:
			break
	if not dry and (fix > 0 or cut > 0 or tint > 0):
		if img.save_png(ProjectSettings.globalize_path(path)) != OK:
			print("   FAILED to write %s" % path)
	return [fix, cut, tint, 0]


## Does a real share of this subject lean purple well away from its own edge? Then the purple
## is its own and none of it comes off. See `PAINT_SHARE`.
static func _is_painted_violet(img: Image, rim: PackedByteArray) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	var opaque := 0
	var inside := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a * 255.0 <= 8.0:
				continue
			opaque += 1
			if minf(c.r, c.b) - c.g > RIM_TINT_GAP and rim[y * w + x] == 0:
				inside += 1
	return opaque > 0 and float(inside) / float(opaque) > PAINT_SHARE


## One strict pass plus one tint pass over `img`, in place. `rim` never changes: repainting
## rewrites RGB and clearing writes alpha 0, and a pixel that went transparent was already
## rim, so it can only make its neighbours MORE rim than the mask says. Rebuilding it per
## round would let the relaxed ceiling creep inward one ring at a time.
func _round_once(img: Image, rim: PackedByteArray) -> Array:
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
			if _is_key(c, rim[y * w + x] == 1):
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
			if _is_key(Color(mean.x, mean.y, mean.z), rim[i] == 1):
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
	#
	# The rim is neutralised the same way and for a sharper version of the same reason: those
	# pixels ARE the ink outline. Borrowing a neighbour's colour there replaces the line with
	# the paint beside it, and the 2-3px outline is the one thing every asset in this game is
	# built on. Lifting green takes the cast off the line and leaves the line.
	var neutralised := 0
	for y in h:
		for x in w:
			var c2 := img.get_pixel(x, y)
			if c2.a * 255.0 <= 8.0 or not _is_tint(c2, y, h, rim[y * w + x] == 1):
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

	# Reported apart rather than summed. They are different edits — one replaces a pixel with
	# its neighbours, one lifts green and keeps the pixel — and a single total hides which of
	# the two rules is doing the work on any given file.
	return [repainted, cleared, neutralised]
