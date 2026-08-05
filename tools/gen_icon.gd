## The app icon: 48x48 pixel art, computed, in every size the platforms ask for.
##
## Until D181 there was no icon at all — no `application/config/icon` in `project.godot` and
## no `launcher_icons/*` in the Android preset — so the game shipped wearing the engine's own
## logo. That is the worst kind of placeholder, because it is somebody else's brand on the
## home screen of a phone, and nothing in a build log says so.
##
## ## Why this is a generator and not a painting
##
## Everything else in `assets/art/` is painted, and this is deliberately not, for the same
## reason `tools/gen_ui_kit.gd` computes the frame kit: an illustration tool is bad at the one
## rule this asset lives or dies by. **A pixel-art icon must sit on its grid at every size it
## ships in.** An image model draws 48-pixel-looking shapes out of anti-aliased edges and
## three hundred colours, and downsampling that to a real 48x48 grid throws away the drawing.
## Authoring the grid itself and scaling it by whole numbers keeps every pixel square:
##
##     48 x 4 = 192   the legacy Android launcher icon
##     48 x 8 = 384   the project icon (window, and the fallback every exporter uses)
##     48 x 9 = 432   the two adaptive layers
##
## Which is also why the project icon is 384 and not the 256 that `ART.md` wished for: 256/48
## is 5.33, and a nearest-neighbour scale by 5.33 draws some pixels five wide and others six.
## That is the mush `rendering/textures/canvas_textures/default_texture_filter = NEAREST` and
## the whole 16px-grid rule exist to prevent, and 48 is a multiple of 16.
##
## ## The design, and what it says
##
## A gold coin with a skull struck into it, on a lit stone plate — money and death, which is
## the whole title. **The coin has a bite missing from its rim.** That is the game: something
## is owed and it is not whole. It is also the only detail here that survives being 48 pixels
## wide, which is the test every idea for this icon had to pass; a lantern, a ledger and a
## hand of cards all read as grey mush at launcher size and were dropped.
##
## ## Android wants three files, not one, and the middle one is a trap
##
## An adaptive icon is two layers the launcher composites and then masks to whatever shape
## the phone likes — circle, squircle, rounded square. **Only the central 66% of the 432px
## layer is guaranteed to survive that mask**, so the emblem is drawn inside the middle 32 of
## the 48 cells and the plate is full-bleed underneath it. Draw the emblem to the edges and
## every round-masked launcher clips the coin. The legacy 192 icon is composited here instead,
## because Android before 8.0 does no compositing of its own.
##
## A monochrome layer ships too, for Android 13's themed icons: the same silhouette flattened
## to one colour, which the system then tints with the user's wallpaper palette. Without it a
## themed home screen falls back to shrinking the full-colour icon inside a grey blob.
##
## Run:   godot --headless --script tools/gen_icon.gd
## Then:  godot --headless --import
extends SceneTree

const OUT := "res://assets/art/icon/"

## The grid everything is authored on. A multiple of 16 (the project's pixel-art grid) that
## also divides both Android sizes by a whole number — see the header.
const GRID := 48

## The share of an adaptive layer that survives the launcher's mask. Android's own figure;
## the emblem is kept inside it.
const SAFE := 2.0 / 3.0

## Sizes to write, and what each is for. Every one is GRID times a whole number.
const SIZES := {
	"icon_384.png": 8,          # project icon: window title bar, and the exporters' fallback
	"icon_192.png": 4,          # Android legacy launcher icon
}

# --- the palette -------------------------------------------------------------------
#
# Eight colours, and they are the game's own rather than a fresh set: the plate is the boot
# background and the stone violet the backdrops are lit against, the ink is `UITheme.INK`,
# and the golds are the coin the whole meta layer is denominated in. An icon in colours
# nothing else uses is a logo for a different game.

const PLATE_DEEP := Color(0.07, 0.06, 0.09)      ## boot_splash/bg_color
const PLATE_MID := Color(0.16, 0.15, 0.20)
const PLATE_LIT := Color(0.28, 0.26, 0.34)       ## the stone violet of the backdrops
const PLATE_EDGE := Color(0.38, 0.35, 0.45)
const GOLD_LIT := Color(0.98, 0.87, 0.56)
const GOLD_MID := Color(0.84, 0.65, 0.24)
const GOLD_DIM := Color(0.56, 0.39, 0.15)
const INK := Color(0.11, 0.08, 0.07)             ## UITheme.INK, near enough to read as a hole

## The skull, struck into the coin. Hand-authored, because this is the one part of the icon
## whose character cannot be computed: 14x12 cells is small enough that every pixel is a
## decision about whether it reads as a skull or as a potato.
##
##   X  ink — the bone, which is the DARK part here because it is stamped into the metal
##   o  the coin showing through: eye sockets, the nose, the gaps between teeth
##   .  outside the stamp
const SKULL := [
	"...XXXXXXXX...",
	".XXXXXXXXXXXX.",
	"XXXXXXXXXXXXXX",
	"XXoooXXXXoooXX",
	"XXoooXXXXoooXX",
	"XXoooXXXXoooXX",
	"XXXXXXooXXXXXX",
	".XXXXXooXXXXX.",
	"..XXXXXXXXXX..",
	"..XoXoXoXoXo..",
	"..XXXXXXXXXX..",
	"....XXXXXX....",
]

## Where the coin sits and how big it is, in cells. The radius is set by the mask, not by
## taste: 14 puts the coin's 28-cell diameter inside the 32 cells an adaptive layer is
## allowed to keep.
const COIN_R := 14.0
## The bite out of the rim: centre (in cells, from the middle of the grid) and radius.
## Upper right, where a mask never cuts and the eye lands first. Its centre sits ON the rim
## (14 cells out, at 45 degrees) rather than beyond it, which is the difference between a
## chunk taken out of a coin and a nick in its edge that reads as a shading mistake — the
## first attempt put it at 15.9 cells and looked like a bug. It reaches 9 cells in, and the
## skull's nearest bone is 8.1 cells out in that direction, so the two do not touch.
const BITE_AT := Vector2(10.0, -10.0)
const BITE_R := 5.0


func _init() -> void:
	var dir := DirAccess.open("res://assets/art/")
	if dir != null and not dir.dir_exists("icon"):
		dir.make_dir("icon")

	var written := 0
	# The composited icon: plate plus emblem. The project icon and the legacy Android one are
	# the same drawing at two scales.
	var full := _cell_image()
	_plate(full)
	_emblem(full)
	for name in SIZES:
		_write(name, _scaled(full, int(SIZES[name])))
		written += 1

	# The two adaptive layers, which must be separate images: the launcher moves them
	# independently (that is the parallax you see when you drag an icon on some phones), and
	# it masks them together. Anything drawn on the wrong layer stops being maskable.
	_write("icon_adaptive_bg_432.png", _scaled(_bg_layer(), 9))
	_write("icon_adaptive_fg_432.png", _scaled(_fg_layer(), 9))
	_write("icon_adaptive_mono_432.png", _scaled(_mono_layer(), 9))
	written += 3

	# The grid itself, at 1:1. Not shipped to a platform and not a debug leftover: it is the
	# only file here a human can open to see what was actually authored, and the legibility
	# question — does this read at 48 pixels — is the one this asset is judged on.
	_write("icon_48.png", _cell_copy(full))
	written += 1

	print("wrote %d files to %s" % [written, OUT])
	var fails: Array = _report(full)
	if not fails.is_empty():
		print("\nFAILED:")
		for f in fails:
			print("  " + String(f))
	quit(1 if not fails.is_empty() else 0)


# --- layers -----------------------------------------------------------------------


## Is this pixel that colour? `Color.is_equal_approx` is the obvious answer and it is the
## wrong one: an RGBA8 image stores 0.84 as 214/255 = 0.8392, and the built-in tolerance is
## 1e-5, so every read-back comparison fails. It failed silently in both directions — the
## report said the emblem covered 0% of a grid it visibly covers, and the monochrome layer
## classified the struck bone as metal and flattened to exactly the featureless blob the
## header warns about. One 8-bit step of slack, and both work.
func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006


func _cell_image() -> Image:
	return Image.create(GRID, GRID, false, Image.FORMAT_RGBA8)


func _cell_copy(src: Image) -> Image:
	var img := _cell_image()
	img.blit_rect(src, Rect2i(0, 0, GRID, GRID), Vector2i.ZERO)
	return img


## The stone the coin lies on. Lit from the upper left like every backdrop in the game, with
## the corners taken down so the plate reads as a tile with edges rather than as a
## background — a launcher that does NOT mask the legacy icon shows those corners.
func _plate(img: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260805                     # fixed: same script, same bytes
	for y in GRID:
		for x in GRID:
			# a diagonal gradient, brightest at the top left
			var t: float = 1.0 - (x + y) / float(2 * GRID - 2)
			var c: Color = PLATE_DEEP.lerp(PLATE_LIT, clampf(t * 1.15, 0.0, 1.0))
			# grain, so 2304 flat cells do not look like a swatch
			if rng.randf() < 0.10:
				c = c.lerp(PLATE_MID, 0.55)
			# a one-cell lit lip along the top and left, and a dark one opposite: the same
			# bevel `gen_ui_kit` draws, at the only thickness 48 cells can afford
			if x == 0 or y == 0:
				c = PLATE_EDGE
			elif x == GRID - 1 or y == GRID - 1:
				c = PLATE_DEEP
			# cut corners, 3 cells, so the plate is a shape and not a rectangle
			var cut: int = 3
			if x + y < cut or (GRID - 1 - x) + y < cut \
					or x + (GRID - 1 - y) < cut or (GRID - 1 - x) + (GRID - 1 - y) < cut:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			img.set_pixel(x, y, c)


## The coin, struck skull and all, drawn into whatever is already there.
func _emblem(img: Image) -> void:
	var centre := Vector2((GRID - 1) * 0.5, (GRID - 1) * 0.5)
	var bite := centre + BITE_AT
	for y in GRID:
		for x in GRID:
			var p := Vector2(x, y)
			var d: float = p.distance_to(centre)
			if d > COIN_R:
				continue
			# the bite: plate shows through, and the cut edge inside it is dimmed so the
			# break reads as depth rather than as a hole punched in a sticker
			var db: float = p.distance_to(bite)
			if db <= BITE_R:
				continue
			var c: Color = GOLD_MID
			if db <= BITE_R + 1.2:
				c = GOLD_DIM
			elif d > COIN_R - 2.2:
				# the rim, lit from the upper left
				var n: Vector2 = (p - centre).normalized()
				var lit: float = n.dot(Vector2(-0.7071, -0.7071))
				c = GOLD_LIT if lit > 0.30 else (GOLD_DIM if lit < -0.30 else GOLD_MID)
			elif d > COIN_R - 3.6:
				c = GOLD_DIM                 # the shoulder under the rim: it is a disc, not a dot
			elif d > COIN_R - 4.6:
				c = GOLD_MID                 # and the face inside it, one step brighter
			img.set_pixel(x, y, c)
	_stamp(img, SKULL, centre)


## Press the skull into the coin. `o` cells are left as they are — the coin showing through is
## what makes the sockets sockets — and the ink gets a one-cell lit edge along its bottom
## right, which is what a struck impression does to metal under a light from the other side.
func _stamp(img: Image, glyph: Array, centre: Vector2) -> void:
	var h: int = glyph.size()
	var w: int = String(glyph[0]).length()
	var ox: int = int(round(centre.x - (w - 1) * 0.5))
	var oy: int = int(round(centre.y - (h - 1) * 0.5)) - 1     # sits a cell high: teeth read
	for gy in h:
		var row := String(glyph[gy])
		for gx in w:
			if row[gx] != "X":
				continue
			var x: int = ox + gx
			var y: int = oy + gy
			if x < 0 or y < 0 or x >= GRID or y >= GRID:
				continue
			if img.get_pixel(x, y).a <= 0.0:
				continue                     # never draw bone outside the coin
			var below_right := gy + 1 < h and gx + 1 < w \
					and row[gx + 1] != "X" and String(glyph[gy + 1])[gx] != "X"
			img.set_pixel(x, y, GOLD_LIT.lerp(INK, 0.55) if below_right else INK)


## Adaptive background: the plate, full bleed and with no cut corners, because the launcher's
## own mask decides the shape and a corner cut here shows up as a notch inside it.
func _bg_layer() -> Image:
	var img := _cell_image()
	_plate(img)
	for y in GRID:
		for x in GRID:
			if img.get_pixel(x, y).a <= 0.0:
				img.set_pixel(x, y, PLATE_DEEP)
	return img


## Adaptive foreground: the emblem alone, on nothing, inside the safe area.
func _fg_layer() -> Image:
	var img := _cell_image()
	_emblem(img)
	return img


## Themed icons (Android 13+): the silhouette, one colour, alpha carrying the shape. The
## system tints it, so any colour here is thrown away — what matters is that the holes stay
## holes, or the skull disappears into a gold blob the moment it is flattened.
func _mono_layer() -> Image:
	var src := _fg_layer()
	var img := _cell_image()
	for y in GRID:
		for x in GRID:
			var c := src.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			# the stamped bone and the sockets read as absence; the metal reads as presence
			var ink: bool = _same(c, INK) or _same(c, GOLD_LIT.lerp(INK, 0.55))
			img.set_pixel(x, y, Color(0, 0, 0, 0) if ink else Color(1, 1, 1, 1))
	return img


# --- output -----------------------------------------------------------------------


## Nearest neighbour, by whole numbers only. `Image.resize` would do it, and it is not used:
## an integer block copy cannot be talked into resampling, and this is the one property the
## whole file exists to guarantee.
func _scaled(src: Image, n: int) -> Image:
	var w: int = src.get_width() * n
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			for dy in n:
				for dx in n:
					img.set_pixel(x * n + dx, y * n + dy, c)
	return img


func _write(name: String, img: Image) -> void:
	var path: String = OUT + name
	if img.save_png(path) != OK:
		push_error("could not write " + path)
		return
	print("  %-28s %dx%d" % [name, img.get_width(), img.get_height()])


## What the drawing measures, so "is it legible" is not answered only by looking at it while
## wanting it to be. Three numbers, each a way this asset fails without looking broken:
##
##   coverage   how much of the grid the emblem occupies. An icon that is mostly plate reads
##              as an empty box at launcher size, which is what a placeholder looks like.
##   contrast   metal against bone. The whole design is one shape read against another, and
##              at 48 pixels a low ratio is not "subtle", it is a gold disc with a smudge.
##   monochrome how much of the themed layer is opaque. This is the one that would have
##              shipped wrong: the layer is white-on-transparent, so a blank one and a
##              correct one look identical in every viewer, and it only appears on a phone
##              with themed icons switched on. It was in fact empty on the first run — the
##              colour comparison `_same` documents — and nothing said so.
func _report(full: Image) -> Array:
	var gold := 0
	var ink := 0
	var plate := 0
	for y in GRID:
		for x in GRID:
			var c := full.get_pixel(x, y)
			if _same(c, GOLD_LIT) or _same(c, GOLD_MID) or _same(c, GOLD_DIM):
				gold += 1
			elif _same(c, INK) or _same(c, GOLD_LIT.lerp(INK, 0.55)):
				ink += 1
			elif c.a > 0.0:
				plate += 1
	var cells: float = float(GRID * GRID)
	var lum_gold: float = GOLD_MID.get_luminance()
	var lum_ink: float = INK.get_luminance()
	var ratio: float = (maxf(lum_gold, lum_ink) + 0.05) / (minf(lum_gold, lum_ink) + 0.05)
	var coverage: float = 100.0 * (gold + ink) / cells
	print("  emblem covers %.0f%% of the grid (gold %.0f%%, struck %.0f%%), plate %.0f%%" % [
		coverage, 100.0 * gold / cells, 100.0 * ink / cells, 100.0 * plate / cells])
	print("  metal-to-bone contrast %.1f:1 (WCAG large-text floor is 3:1)" % ratio)

	var mono := _mono_layer()
	var opaque := 0
	var holes := 0
	for y in GRID:
		for x in GRID:
			if mono.get_pixel(x, y).a > 0.5:
				opaque += 1
	# the sockets and the nose have to survive being flattened, or the themed icon is a disc
	for y in GRID:
		for x in GRID:
			var inside: bool = Vector2(x, y).distance_to(
				Vector2((GRID - 1) * 0.5, (GRID - 1) * 0.5)) < COIN_R - 5.0
			if inside and mono.get_pixel(x, y).a <= 0.5:
				holes += 1
	print("  themed layer %.0f%% opaque, %d cells of the struck skull left open" % [
		100.0 * opaque / cells, holes])

	var fails: Array = []
	if coverage < 18.0:
		fails.append("the emblem covers %.0f%% of the grid — that reads as an empty box at 48px"
			% coverage)
	if ratio < 3.0:
		fails.append("metal-to-bone contrast is %.1f:1, under the 3:1 floor" % ratio)
	if opaque < 200:
		fails.append("the themed layer is %.0f%% opaque — it is blank, and no viewer will say so"
			% (100.0 * opaque / cells))
	if holes < 30:
		fails.append("only %d cells of the skull survive the themed flatten — that is a disc" % holes)
	return fails
