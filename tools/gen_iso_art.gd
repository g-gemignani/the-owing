## Generates the isometric floor's ground and wall materials, from the backdrops.
##
## Replaces the downloaded tile packs (D89). Those were `~/Downloads` directories
## with no licence file and no attribution — `assets/art/iso/README.md` reads them as
## the free tiers that commonly permit *use in a game* while forbidding
## **redistribution of the art**, and committing a file to a repository is
## redistribution. So the blocker was never that they looked wrong. They could not
## be pushed.
##
## The answer is the one `tools/gen_music.py` reached for the soundtrack and D29
## reached for the symbols: **author it, and measure the result**, rather than guess
## at somebody else's unlabelled material. Everything here is computed, so it is ours
## outright, it is reproducible from a one-line command, and the repository carries a
## generator rather than a redistribution.
##
## ## The palette is not chosen, it is sampled
##
## "Goes with the painted backdrops" is a judgement, and a judgement drifts. So it is
## made mechanical instead: each terrain's ramp is read out of **the floor band of the
## backdrops of the dungeons that actually use that terrain**. The Warrens are `earth`
## (`Balance.ISO_TERRAIN_OF`), so the Warrens' iso floor is built from the colours of
## the floor in `bg_warrens.png`. The band is taken below `PixelArt.HORIZON_LINE`,
## which is where those paintings put the wall/floor junction and is already measured
## and asserted by `tests/test_art.gd` — the same number, so the two cannot drift.
##
## The consequence worth stating: adding a dungeon backdrop changes this output, and
## that is correct. The material is DERIVED from the art direction rather than matched
## to it by eye (D34's rule, applied to pixels).
##
## ## Seamless by construction, not by touch-up
##
## Every pattern here is evaluated on a torus: cell indices wrap with `posmod`, and
## noise lattices divide the image exactly. Nothing is blended or mirrored at the
## edge. That matters more than usual because `iso_run.gd` does not tile these — it
## UV-projects them per diamond with a per-cell offset, so a pixel near the right edge
## sits next to a pixel near the left edge *inside a single tile*. A mirror-blended
## "seamless" texture shows its axis there immediately.
##
## The seam is measured on every run and printed, against the interior as the control.
##
## Run: godot --headless --script tools/gen_iso_art.gd
## Then: godot --headless --import
extends SceneTree

const OUT := "res://assets/art/iso/"
const SIZE := 256

## Which terrain's material dresses a wall for each floor terrain. Not the identity
## map: `moss` is an overgrown floor between STONE walls, because greenery climbing a
## wall face reads as a hillside rather than as a ruin. Inherited deliberately from
## the installer this replaces — it was the one art decision in that file worth
## keeping, and it was right.
const WALL_OF := {"stone": "stone", "earth": "earth", "moss": "stone", "sand": "sand"}


# --- deterministic hashing -----------------------------------------------------
#
# Not `randf()`: the output has to be identical on every machine and every run, or a
# regenerate shows up as a diff in twelve binary files for no reason. An integer hash
# gives that for free and makes the pattern a pure function of position.

static func _hash(x: int, y: int, salt: int) -> float:
	var h: int = x * 374761393 + y * 668265263 + salt * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0xFFFFFF)

## Value noise on a wrapping lattice. `cells` must divide SIZE, which is what makes
## the result tile: the lattice point at `cells` IS the lattice point at 0.
static func _noise(px: float, py: float, cells: int, salt: int) -> float:
	var fx: float = px * float(cells) / float(SIZE)
	var fy: float = py * float(cells) / float(SIZE)
	var ix: int = int(floor(fx))
	var iy: int = int(floor(fy))
	var tx: float = fx - float(ix)
	var ty: float = fy - float(iy)
	# smoothstep, so the lattice does not show as a diamond grid
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _hash(posmod(ix, cells), posmod(iy, cells), salt)
	var b := _hash(posmod(ix + 1, cells), posmod(iy, cells), salt)
	var c := _hash(posmod(ix, cells), posmod(iy + 1, cells), salt)
	var d := _hash(posmod(ix + 1, cells), posmod(iy + 1, cells), salt)
	return lerp(lerp(a, b, tx), lerp(c, d, tx), ty)

## Fractal sum of the above. Octaves double the lattice, which keeps every one of them
## a divisor of SIZE as long as the base is.
static func _fbm(px: float, py: float, cells: int, octaves: int, salt: int) -> float:
	var sum := 0.0
	var amp := 1.0
	var norm := 0.0
	var c := cells
	for o in octaves:
		sum += amp * _noise(px, py, c, salt + o * 77)
		norm += amp
		amp *= 0.5
		c *= 2
	return sum / norm

## Wrapping Worley/cellular. Returns [f1, f2, cell_id] — `f2 - f1` is the ridge
## between two cells, which is the mortar line in a cobbled floor.
static func _worley(px: float, py: float, cells: int, salt: int, jitter: float) -> Array:
	var fx: float = px * float(cells) / float(SIZE)
	var fy: float = py * float(cells) / float(SIZE)
	var ix: int = int(floor(fx))
	var iy: int = int(floor(fy))
	var f1 := 9.0
	var f2 := 9.0
	var id := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var cx: int = ix + int(dx)
			var cy: int = iy + int(dy)
			var wx: int = posmod(cx, cells)
			var wy: int = posmod(cy, cells)
			# the feature point is placed from the WRAPPED index and drawn at the
			# unwrapped one, which is the whole trick: the cell across the seam is
			# the same cell, so its stone continues instead of restarting
			var ox := 0.5 + (_hash(wx, wy, salt) - 0.5) * jitter
			var oy := 0.5 + (_hash(wx, wy, salt + 991) - 0.5) * jitter
			var d := Vector2(float(cx) + ox - fx, float(cy) + oy - fy).length()
			if d < f1:
				f2 = f1
				f1 = d
				id = wy * cells + wx
			elif d < f2:
				f2 = d
	return [f1, f2, id]

# --- the four surfaces ---------------------------------------------------------

## Worked stone: cobbles with mortar between them. The cells carry most of the
## reading, so their tones are spread across the whole ramp — a cobbled floor where
## every stone is the same value is a texture, not a floor.
static func _stone(img: Image, ramp: Array, cells: int, mortar: float, salt: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var w := _worley(float(x), float(y), cells, salt, 0.85)
			var f1: float = w[0]
			var f2: float = w[1]
			var id: int = w[2]
			var tone := 0.30 + 0.62 * _hash(id, id * 7, salt + 13)
			# grain inside the stone, so a cobble is not a flat lozenge
			tone += (_fbm(float(x), float(y), 32, 3, salt + 5) - 0.5) * 0.16
			# the mortar line: darken where two cells meet
			var edge: float = clampf((f2 - f1) / mortar, 0.0, 1.0)
			tone *= 0.34 + 0.66 * edge
			# a lip of light on the stone just inside the mortar, which is what makes
			# it read as a raised block rather than as a painted-on grid
			if edge > 0.30 and edge < 0.52:
				tone += 0.10
			img.set_pixel(x, y, ArtPalette.shade(ramp, tone))

## Dug earth: no cells at all. Fractal noise, with a scattering of small stones — the
## first attempt was noise alone and read as a photograph of dirt rather than as a
## floor somebody walks on, because there was nothing in it at the scale of a foot.
static func _earth(img: Image, ramp: Array, salt: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var tone := 0.22 + 0.50 * _fbm(float(x), float(y), 8, 5, salt)
			var peb := _worley(float(x), float(y), 22, salt + 31, 1.0)
			if float(peb[0]) < 0.24:
				var lit: float = 1.0 - float(peb[0]) / 0.24
				tone += 0.26 * lit * (0.4 + 0.6 * _hash(int(peb[2]), 3, salt))
			img.set_pixel(x, y, ArtPalette.shade(ramp, tone))

## Overgrown: earth with moss taking it back. The moss is a thresholded low-frequency
## mask rather than uniform noise, so it grows in PATCHES — uniform green speckle
## reads as a bad carpet, and the point of this terrain is that the floor is being
## reclaimed in places and not in others.
static func _moss(img: Image, ramp: Array, salt: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var tone := 0.22 + 0.50 * _fbm(float(x), float(y), 8, 5, salt)
			var base := ArtPalette.shade(ramp, tone)
			var mask := _fbm(float(x), float(y), 4, 4, salt + 400)
			if mask > 0.52:
				var thick: float = clampf((mask - 0.52) / 0.30, 0.0, 1.0)
				var fuzz := _fbm(float(x), float(y), 48, 2, salt + 9)
				# green pulled toward the ramp's own light end rather than invented, so
				# the moss belongs to the same painting as the stone under it
				var top: Color = ArtPalette.shade(ramp, 0.80)
				var green := Color(top.r * 0.42, top.g * 0.72 + 0.10, top.b * 0.30)
				green = green.lerp(green.darkened(0.35), fuzz)
				base = base.lerp(green, thick * 0.88)
			img.set_pixel(x, y, base)

## Silted: a drowned place that drained. Fine grain plus ripple bands, and almost no
## contrast — the whole character of silt is that it is FLAT, and every attempt to
## give it more interest turned it into either earth or stone.
static func _sand(img: Image, ramp: Array, salt: int) -> void:
	for y in SIZE:
		for x in SIZE:
			var warp := _fbm(float(x), float(y), 4, 3, salt + 70)
			# ripples run on the diagonal and are warped by the noise, so they read as
			# water-laid rather than as a corduroy pattern
			var ripple: float = sin((float(x) + float(y)) * TAU * 6.0 / float(SIZE)
				+ warp * 5.0)
			var tone := 0.42 + 0.10 * ripple + 0.22 * _fbm(float(x), float(y), 64, 3, salt)
			img.set_pixel(x, y, ArtPalette.shade(ramp, tone))

## A wall is the same rock the floor is cut from, seen on a vertical face: coarser,
## darker, and with the mortar deeper. `iso_run.gd` already tints the three faces of a
## block differently, so this must NOT bake in its own lighting — it is a material,
## and the block does the shading.
static func _wall(img: Image, ramp: Array, terrain: String, salt: int) -> void:
	match terrain:
		"earth":
			_earth(img, ramp, salt + 1000)
			_multiply(img, 0.86)
		"sand":
			_sand(img, ramp, salt + 1000)
			_multiply(img, 0.90)
		_:
			_stone(img, ramp, 5, 0.14, salt + 1000)
			_multiply(img, 0.88)

static func _multiply(img: Image, k: float) -> void:
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, c.a))

# --- measurement ---------------------------------------------------------------

## How visible the wrap is, as a ratio against the interior.
##
## The seam is the step from column SIZE-1 to column 0 (and the same in y). The
## control is the mean step between neighbouring interior columns. A truly seamless
## texture scores about 1.0 — the wrap is just another neighbouring column. A mirrored
## or blended fake scores well BELOW 1.0 (the edge is smoother than the interior,
## which is its own artefact), and a hard cut scores far above.
##
## The control is averaged over EVERY interior column, not one column at the middle.
## Sampling a single column reported worked stone at 3.95x — not because the wrap was
## visible but because x=128 happened to fall inside a cobble, where neighbouring
## columns are nearly identical, so the denominator was a smooth patch rather than a
## typical one. A control has to be representative of the whole texture or the ratio
## measures where you put the probe.
static func _rgb_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _seam(img: Image) -> float:
	var seam := 0.0
	for y in SIZE:
		seam += _rgb_dist(img.get_pixel(SIZE - 1, y), img.get_pixel(0, y))
	for x in SIZE:
		seam += _rgb_dist(img.get_pixel(x, SIZE - 1), img.get_pixel(x, 0))
	seam /= float(SIZE * 2)

	var interior := 0.0
	var pairs := 0
	for x in range(0, SIZE - 1):
		for y in range(0, SIZE, 8):
			interior += _rgb_dist(img.get_pixel(x, y), img.get_pixel(x + 1, y))
			pairs += 1
	for y in range(0, SIZE - 1):
		for x in range(0, SIZE, 8):
			interior += _rgb_dist(img.get_pixel(x, y), img.get_pixel(x, y + 1))
			pairs += 1
	interior /= float(maxi(1, pairs))
	return seam / maxf(0.0001, interior)

## Mean luminance and its spread, so a material that came out flat or blown is visible
## in the log rather than only in a capture.
static func _stats(img: Image) -> Array:
	var sum := 0.0
	var n := 0
	for y in range(0, SIZE, 2):
		for x in range(0, SIZE, 2):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	var mean := sum / float(n)
	var var_sum := 0.0
	for y in range(0, SIZE, 2):
		for x in range(0, SIZE, 2):
			var d := img.get_pixel(x, y).get_luminance() - mean
			var_sum += d * d
	return [mean, sqrt(var_sum / float(n))]

# --- driver --------------------------------------------------------------------

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var wrote := 0
	print("=== iso materials, palettes sampled from the painted backdrops ===")
	for terrain in Balance.ISO_TERRAINS:
		var t := String(terrain)
		var ramp := ArtPalette.ramp(ArtPalette.dungeons_with_terrain(t))
		var srcs := ArtPalette.dungeons_with_terrain(t)
		print("\n%s  <- %s" % [t, ", ".join(srcs)])
		print("   ramp %s" % [_ramp_text(ramp)])

		var floor_img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var salt: int = t.hash() & 0xFFFF
		match t:
			"earth": _earth(floor_img, ramp, salt)
			"moss": _moss(floor_img, ramp, salt)
			"sand": _sand(floor_img, ramp, salt)
			_: _stone(floor_img, ramp, 7, 0.16, salt)
		wrote += _save(floor_img, "floor_%s" % t)

		var wall_terrain := String(WALL_OF.get(t, t))
		var wall_ramp: Array = ArtPalette.ramp(ArtPalette.dungeons_with_terrain(wall_terrain)) if wall_terrain != t else ramp
		var wall_img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		_wall(wall_img, wall_ramp, wall_terrain, salt)
		wrote += _save(wall_img, "rock_%s" % t)
		if wall_terrain != t:
			print("   walls are %s, not %s — greenery on a vertical face reads as a hillside" % [
				wall_terrain, t])

		# the bare `floor`/`rock` names are the fallback a dungeon gets when its
		# terrain has no art, and the default terrain is what that should look like
		if t == Balance.ISO_TERRAIN_DEFAULT:
			wrote += _save(floor_img, "floor")
			wrote += _save(wall_img, "rock")

	print("\n%d files written to %s" % [wrote, OUT])
	print("Run `godot --headless --import` to write the .import sidecars.")
	quit(0)

func _ramp_text(ramp: Array) -> String:
	var parts: Array = []
	for c in ramp:
		parts.append("#" + Color(c).to_html(false))
	return " ".join(parts)

func _save(img: Image, name: String) -> int:
	var path := OUT + name + ".png"
	var err := img.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("   FAILED to write %s (%d)" % [name, err])
		return 0
	var st := _stats(img)
	print("   %-12s seam %.2fx interior   luma %.2f +/- %.2f" % [
		name + ".png", _seam(img), st[0], st[1]])
	return 1
