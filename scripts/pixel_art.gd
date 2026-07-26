## Pixel art assets.
##
## Split deliberately:
##
## * **Enemy sprites and UI panels** come from Kenney's CC0 pixel packs
##   (`assets/pixel/`, licences kept beside them). Any distinct sprite works for an
##   enemy, so borrowing real art is the right call.
## * **Effect symbols are authored here as 16x16 bitmaps.** Those *must* mean
##   exactly what they show — a shield has to read as a shield — and the packs ship
##   unlabelled spritesheets (`tile_0093.png`), so picking icons from them would
##   have been guesswork dressed up as art. Twelve small glyphs is cheaper than
##   being wrong about every one of them.
##
## Symbols are monochrome so callers can tint them (rarity colour, faded states).
class_name PixelArt
extends RefCounted

const ENEMY_DIR := "res://assets/pixel/enemies/"
const UI_DIR := "res://assets/pixel/ui/"

## 16x16 glyphs. '.' transparent, 'X' solid, 'o' half-tone for shading.
const GLYPHS := {
"attack": [
"................",
".............XX.",
"............XXX.",
"...........XXX..",
"..........XXX...",
".........XXX....",
"........XXX.....",
".......XXX......",
"......XXX.......",
".....XXX........",
"..oXXXX.........",
"..XXXX..........",
".oXXo...........",
"XXo.............",
"XX..............",
"................"],
"block": [
"................",
"...XXXXXXXXXX...",
"..XXXXXXXXXXXX..",
"..XXoooooooXXX..",
"..XXoooooooXXX..",
"..XXoooooooXXX..",
"..XXoooooooXXX..",
"..XXXoooooXXXX..",
"...XXXoooXXXX...",
"...XXXXoXXXXX...",
"....XXXXXXXX....",
".....XXXXXX.....",
"......XXXX......",
".......XX.......",
"................",
"................"],
"poison": [
"................",
".......XX.......",
"......XXXX......",
"......XooX......",
".....XXooXX.....",
".....XoooX X....",
"....XXoooXX.....",
"....XoooooX.....",
"...XXoooooXX....",
"...XoooooooX....",
"...XoooXoooX....",
"...XXoooooXX....",
"....XXXXXXX.....",
"................",
"................",
"................"],
"thorns": [
"................",
"..X..........X..",
"..XX........XX..",
"...XX......XX...",
"....XX....XX....",
".....XXooXX.....",
"......XXXX......",
".....XXooXX.....",
"....XX....XX....",
"...XX......XX...",
"..XX........XX..",
"..X..........X..",
"................",
"................",
"................",
"................"],
"heart": [
"................",
"..XXX....XXX....",
".XXXXX..XXXXX...",
"XXXXXXXXXXXXXX..",
"XXXooXXXXooXXX..",
"XXXXXXXXXXXXXX..",
".XXXXXXXXXXXX...",
"..XXXXXXXXXX....",
"...XXXXXXXX.....",
"....XXXXXX......",
".....XXXX.......",
"......XX........",
"................",
"................",
"................",
"................"],
"gold": [
"................",
".....XXXXXX.....",
"...XXXXXXXXXX...",
"..XXXooooooXXX..",
"..XXoXXXXXXoXX..",
".XXoXXoooXXXoXX.",
".XXoXXo..XXXoXX.",
".XXoXXXooXXXoXX.",
".XXoXXXXXoXXoXX.",
".XXoXXo..oXXoXX.",
"..XXoXXoooXXoX..",
"..XXXooooooXXX..",
"...XXXXXXXXXX...",
".....XXXXXX.....",
"................",
"................"],
"card": [
"................",
"..XXXXXXXXXXXX..",
"..XooooooooooX..",
"..XoXXXXXXXXoX..",
"..XoXooooooXoX..",
"..XoXoXXXXoXoX..",
"..XoXoXooXoXoX..",
"..XoXoXooXoXoX..",
"..XoXoXXXXoXoX..",
"..XoXooooooXoX..",
"..XoXXXXXXXXoX..",
"..XooooooooooX..",
"..XXXXXXXXXXXX..",
"................",
"................",
"................"],
"dice": [
"................",
"..XXXXXXXXXXXX..",
"..XooooooooooX..",
"..XoXXoooXXooX..",
"..XoXXoooXXooX..",
"..XooooooooooX..",
"..XoooXXXooooX..",
"..XoooXXXooooX..",
"..XooooooooooX..",
"..XoXXoooXXooX..",
"..XoXXoooXXooX..",
"..XooooooooooX..",
"..XXXXXXXXXXXX..",
"................",
"................",
"................"],
"skull": [
"................",
"....XXXXXXXX....",
"...XXXXXXXXXX...",
"..XXXXXXXXXXXX..",
"..XXooXXXXooXX..",
"..XXooXXXXooXX..",
"..XXXXXoXXXXXX..",
"..XXXXXoXXXXXX..",
"...XXXXXXXXXX...",
"....XXoXoXXX....",
"....XXoXoXXX....",
".....XXXXXX.....",
"................",
"................",
"................",
"................"],
"campfire": [
"................",
".......X........",
"......XXX.......",
".....XXoXX......",
"....XXoooXX.....",
"....XoooooX.....",
"...XXoooooXX....",
"...XoooooooX....",
"....XXoooXX.....",
".....XXXXX......",
"..XX.......XX...",
"...XXXXXXXXX....",
"..XXXXXXXXXXX...",
"................",
"................",
"................"],
"rope": [
"................",
"...XXXXXXXX.....",
"..XX......XX....",
"..X........X....",
"..X........X....",
"..XX......XX....",
"...XXXXXXXX.....",
".....XoooX......",
"......XoX.......",
".....XoooX......",
"......XoX.......",
".....XoooX......",
"......XX........",
"................",
"................",
"................"],
"chest": [
"................",
"...XXXXXXXXXX...",
"..XXooooooooXX..",
"..XoXXXXXXXXoX..",
"..XoooooooooOX..",
"XXXXXXXXXXXXXXXX",
"XXooooXXooooooXX",
"XXooooXXooooooXX",
"XXXXXXXXXXXXXXXX",
"..XooooXXoooooX.",
"..XooooXXoooooX.",
"..XoooooooooooX.",
"..XXXXXXXXXXXXX.",
"................",
"................",
"................"],
"book": [
"................",
"..XXXXXX.XXXXXX.",
".XooooooXoooooo.",
".XoXXXooXooXXXo.",
".XooooooXoooooo.",
".XoXXXooXooXXXo.",
".XooooooXoooooo.",
".XoXXXooXooXXXo.",
".XooooooXoooooo.",
".XoXXXooXooXXXo.",
".XooooooXoooooo.",
".XXXXXXXXXXXXXX.",
"................",
"................",
"................",
"................"]
}

const BG_DIR := "res://assets/pixel/bg/"
const CARD_SHEET := "res://assets/pixel/cards/sheet.png"
const CARD_TILE := 16

## Tiles from the 1-Bit sheet worth using as card illustrations, sampled across the
## whole sheet so they are not all variations of one row. Baked rather than scanned
## at startup: checking 1078 tiles pixel by pixel is not something to do on boot.
##
## The sheet is monochrome, so illustrations are tinted by rarity — which reuses the
## colour language the rest of the UI already speaks.
const CARD_TILES: Array[int] = [
	1, 9, 20, 27, 34, 41, 48, 55, 67, 75, 82, 89, 96, 103, 114, 122, 129, 137, 144, 151,
	159, 168, 175, 187, 194, 201, 213, 224, 235, 242, 249, 259, 266, 273, 283, 293, 300, 307, 314, 321,
	331, 338, 345, 352, 359, 366, 373, 380, 391, 398, 405, 412, 419, 426, 434, 442, 449, 456, 464, 471,
	478, 485, 493, 500, 507, 515, 522, 530, 537, 544, 551, 558, 565, 572, 579, 586, 594, 603, 610, 617,
	625, 633, 640, 647, 654, 661, 668, 677, 684, 692, 699, 706, 715, 722, 729, 736, 745, 752, 759, 766,
	773, 780, 787, 794, 801, 808, 815, 822, 829, 836, 843, 850, 857, 864, 872, 881, 888, 895, 902, 909,
	916, 923, 931, 938, 945, 952, 959, 966, 974, 981, 988, 995, 1004, 1012, 1021, 1031, 1038, 1045, 1052, 1059,
]

## Tiling 16x16 backdrops, one per zone.
##
## The real art comes from Kenney's CC0 **pixel pattern pack** — genuinely seamless
## tiles, unlike the unlabelled terrain tiles in the dungeon packs. They were picked
## by *measurement* rather than by eye: each candidate was scored for wrap error
## (how different its opposite edges are, so tiling shows no seam) and for internal
## contrast (so a backdrop stays a backdrop). The five installed all score a wrap
## error of 0.000 and sit around 20-30% luminance, which keeps UI text legible.
##
## The authored patterns below remain only as a fallback if the art is missing —
## a screen with no backdrop is better than a crash.
const PATTERNS := {
"stone": [
"XXXXXXXo.XXXXXXo",
"XoooooXo.XooooXo",
"XoooooXo.XooooXo",
"XXXXXXXo.XXXXXXo",
"ooooooooooooooooo",
".o..o..o..o..o..",
"XXXXo.XXXXXXXo.X",
"Xoooo.XoooooXo.X",
"Xoooo.XoooooXo.X",
"XXXXo.XXXXXXXo.X",
"oooooooooooooooo",
"..o..o..o..o..o.",
"XXXXXXXo.XXXXXXo",
"XoooooXo.XooooXo",
"XXXXXXXo.XXXXXXo",
"oooooooooooooooo"],
"forge": [
"oooooooooooooooo",
"oXXo..oXXo..oXXo",
"oXXo..oXXo..oXXo",
"oooooooooooooooo",
"..oXXo..oXXo..oX",
"..oXXo..oXXo..oX",
"oooooooooooooooo",
"oXXo..oXXo..oXXo",
"oXXo..oXXo..oXXo",
"oooooooooooooooo",
"..oXXo..oXXo..oX",
"..oXXo..oXXo..oX",
"oooooooooooooooo",
"oXXo..oXXo..oXXo",
"oXXo..oXXo..oXXo",
"oooooooooooooooo"],
"rot": [
"..o..X....o.....",
".oXo...o..oXo...",
"..o...oXo..o..o.",
".....o.o.....oXo",
"..oXo.....o...o.",
".o.o....oXo.....",
"...........o..o.",
"..o...oXo....oXo",
".oXo...o.....o.o",
"..o.......o.....",
"....o..o.oXo..o.",
"..oXo.oXo.o..oXo",
"...o...o.....o.o",
".....o.....o....",
"..o.oXo...oXo...",
".oXo..o....o....."],
"deeps": [
"................",
"..XX........XX..",
".X..X..oo..X..X.",
"X....XX..XX....X",
"................",
"....oo....oo....",
"...X..X..X..X...",
"..X....XX....X..",
"................",
"..XX........XX..",
".X..X..oo..X..X.",
"X....XX..XX....X",
"................",
"....oo....oo....",
"...X..X..X..X...",
"................"],
"void": [
"................",
".......o........",
"................",
"...o.........o..",
"................",
"........X.......",
"..o.............",
"................",
".............o..",
"....X...........",
"................",
"........o.......",
"..............o.",
"...o............",
"................",
"........o......."]
}

## Zone id -> (pattern, tint). Anything unlisted falls back to stone.
const ZONE_BACKDROP := {
	"barrows": ["stone", Color(0.30, 0.30, 0.38)],
	"foundry_zone": ["forge", Color(0.42, 0.26, 0.20)],
	"rot": ["rot", Color(0.24, 0.36, 0.24)],
	"deeps": ["deeps", Color(0.20, 0.30, 0.44)],
	"beyond": ["void", Color(0.34, 0.24, 0.42)]
}

static var _cache := {}

## Texture for a symbol, or null if unknown. Cached: these are built pixel by pixel.
static func symbol(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	if not GLYPHS.has(name):
		return null
	var rows: Array = GLYPHS[name]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in mini(16, rows.size()):
		var line: String = rows[y]
		for x in mini(16, line.length()):
			match line[x]:
				"X":
					img.set_pixel(x, y, Color(1, 1, 1, 1))
				"o", "O":
					img.set_pixel(x, y, Color(0.62, 0.62, 0.62, 1))
	var tex := ImageTexture.create_from_image(img)
	_cache[name] = tex
	return tex

## Tiling backdrop texture for a pattern name. Tones are deliberately dark.
static func pattern(name: String) -> Texture2D:
	var key := "pat_" + name
	if _cache.has(key):
		return _cache[key]
	if not PATTERNS.has(name):
		name = "stone"
		key = "pat_stone"
		if _cache.has(key):
			return _cache[key]
	var rows: Array = PATTERNS[name]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	# base, mid, light — all low so UI text keeps its contrast
	var tones := {".": Color(0.055, 0.05, 0.075), "o": Color(0.085, 0.078, 0.105),
		"X": Color(0.125, 0.115, 0.15)}
	for y in 16:
		var line: String = rows[y] if y < rows.size() else "................"
		for x in 16:
			var ch := line[x] if x < line.length() else "."
			img.set_pixel(x, y, tones.get(ch, tones["."]))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Sorted card ids, so illustration assignment is by POSITION and therefore stable
## and collision-free (hashing ids previously left different enemies sharing art).
static func card_ids() -> Array:
	if _cache.has("_cards"):
		return _cache["_cards"]
	var out: Array = []
	for p in list_resources("res://resources/cards/", ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	_cache["_cards"] = out
	return out

## Which illustration a card uses. Arbitrary but deterministic: the sheet ships
## unlabelled, so semantics need a human eye — add entries here to correct one.
const CARD_ART_OVERRIDES := {}

## A 16x16 slice of the sheet for this card, or null if the sheet is missing.
static func card_art(card_id: String) -> Texture2D:
	var key := "art_" + card_id
	if _cache.has(key):
		return _cache[key]
	if not ResourceLoader.exists(CARD_SHEET) or CARD_TILES.is_empty():
		return null
	var sheet := load(CARD_SHEET) as Texture2D
	var cols: int = sheet.get_width() / CARD_TILE
	var tile: int = int(CARD_ART_OVERRIDES.get(card_id, -1))
	if tile < 0:
		var i := card_ids().find(card_id)
		if i < 0:
			i = card_id.length()
		tile = CARD_TILES[i % CARD_TILES.size()]
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(float((tile % cols) * CARD_TILE), float((tile / cols) * CARD_TILE),
		float(CARD_TILE), float(CARD_TILE))
	_cache[key] = at
	return at

## The installed backdrop art for a zone, or null if it is missing.
static func backdrop_texture(zone_id: String) -> Texture2D:
	var p := BG_DIR + "bg_" + zone_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## Backdrop for a zone: a tiling TextureRect ready to sit behind a screen.
static func backdrop(zone_id: String) -> TextureRect:
	var entry: Array = ZONE_BACKDROP.get(zone_id, ["stone", Color(0.30, 0.30, 0.38)])
	var tr := TextureRect.new()
	# real art first; the authored pattern is only a fallback
	var art := backdrop_texture(zone_id)
	tr.texture = art if art != null else pattern(String(entry[0]))
	tr.stretch_mode = TextureRect.STRETCH_TILE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The art is near-monochrome, so the zone identity comes from tinting it.
	# Darkened hard: this sits under every screen and must never fight the text.
	tr.modulate = (entry[1] as Color) * 1.15
	tr.modulate.a = 1.0
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

## Enemy sprites, sorted so the mapping is stable across runs.
static func enemy_sprites() -> Array:
	if _cache.has("_enemies"):
		return _cache["_enemies"]
	var out := list_resources(ENEMY_DIR, ".png")
	_cache["_enemies"] = out
	return out

## List resources of one kind in a directory, in a form that survives EXPORT.
##
## Godot does not ship source .png files in a PCK — it ships the imported texture
## and leaves a `foo.png.remap` beside it. Code that listed `f.ends_with(".png")`
## therefore found every sprite while developing and NOTHING in an exported build:
## the game would have shipped with no enemy art and no card art at all, and no
## dev run could ever have revealed it, because the editor and `--headless` both
## read the real filesystem.
##
## `load()` still takes the original path, so only the listing needs fixing.
static func list_resources(dir: String, suffix: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		# an exported build hands back "sprite.png.remap"; strip it back to the
		# path load() understands
		if f.ends_with(".remap"):
			f = f.substr(0, f.length() - 6)
		if f.ends_with(suffix) and not out.has(dir + f):
			out.append(dir + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## A stable sprite for an archetype id.
##
## The packs ship unlabelled files, so which sprite lands on which enemy is
## arbitrary — but it is *deterministic*, so an enemy always looks the same. To
## correct one by eye later, add it to OVERRIDES.
##
## Every BOSS is pinned here rather than left to fall out of a sorted index. Two
## reasons: a named boss deserves a sprite chosen for it, not the next one in the
## list; and positional assignment shifts every enemy whenever a .tres is added,
## so the finale of a dungeon would silently change face on the next content pass.
const OVERRIDES := {
	"grave_sexton": "tile_0111",   # hooded gravedigger
	"brood_mother": "tile_0122",   # spider — nothing here fights alone
	"marrow_abbot": "tile_0124",   # helmed skull
	"bellows_master": "tile_0109", # bare-armed at the forge
	"warden": "tile_0096",         # armoured, blocks the way
	"cinder_knight": "tile_0097",  # armoured, molten
	"mycelial_lord": "tile_0112",  # green, growing
	"the_gardener": "tile_0123",   # earth-coloured
	"deep_warden": "tile_0098",
	"last_vendor": "tile_0100",    # a merchant, still at his stall
	"false_step": "tile_0121",     # a ghost of a stair
	"abyss_horror": "tile_0110",   # the red thing at the bottom
}

## Sorted list of every archetype id, so sprite assignment is by POSITION.
## Hashing the id collided and left different enemies sharing a sprite; indexing a
## sorted catalogue guarantees each one is visually distinct while sprites last.
static func archetype_ids() -> Array:
	if _cache.has("_archetypes"):
		return _cache["_archetypes"]
	var out: Array = []
	for p in list_resources("res://resources/enemies/", ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	_cache["_archetypes"] = out
	return out

static func enemy_sprite(archetype_id: String) -> Texture2D:
	var files := enemy_sprites()
	if files.is_empty():
		return null
	if OVERRIDES.has(archetype_id):
		var p: String = ENEMY_DIR + OVERRIDES[archetype_id] + ".png"
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	# Positional assignment must skip anything a boss has claimed, or a trash mob
	# ends up wearing the face of the finale.
	var free: Array = []
	var taken := {}
	for k in OVERRIDES:
		taken[ENEMY_DIR + String(OVERRIDES[k]) + ".png"] = true
	for f in files:
		if not taken.has(f):
			free.append(f)
	if free.is_empty():
		free = files
	# index among the UNPINNED archetypes, so the pinned ones do not leave gaps
	var pool: Array = archetype_ids().filter(func(a): return not OVERRIDES.has(a))
	var idx := pool.find(archetype_id)
	if idx < 0:
		idx = archetype_id.length()   # unknown id: still deterministic
	return load(free[idx % free.size()]) as Texture2D

static func ui(name: String) -> Texture2D:
	var p := UI_DIR + name + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null
