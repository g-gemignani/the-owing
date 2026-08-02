## Pixel art assets.
##
## Split deliberately:
##
## * **Enemy sprites and UI panels** come from Kenney's CC0 pixel packs
##   (`assets/pixel/`, licences kept beside them). Any distinct sprite works for an
##   enemy, so borrowing real art is the right call.
## * **Effect symbols are PAINTED where a painting exists, and authored here as
##   16x16 bitmaps where it does not** (D115). They *must* mean exactly what they
##   show — a shield has to read as a shield — and the packs ship unlabelled
##   spritesheets (`tile_0093.png`), so picking icons from them would have been
##   guesswork dressed up as art. Twelve small glyphs was cheaper than being wrong
##   about every one of them, and stayed the answer until a painted set arrived that
##   covers 21 meanings against these 13. The bitmaps are the fallback now, not the
##   plan; `symbol()` is where the preference lives.
##
## Symbols are monochrome so callers can tint them (rarity colour, faded states).
class_name PixelArt
extends RefCounted

## The CC0 Kenney sprite pool and the Kenney UI pack both lived here and are gone
## (D89). Enemies are drawn from `ENEMY_ART_DIR`, one generated plate per archetype id;
## the UI wears the procedural frame kit in `assets/art/ui/`. Nothing referenced the UI
## pack at all by the end, and the sprite pool was assigned POSITIONALLY, which is the
## misfeature the plates exist to remove.

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

## Where the painted set and the authored glyphs disagree on a name. One entry, and the
## rename that would remove it is not worth making: the bitmap is named after what it
## draws and the manifest after what it means, and "hp" is already the semantic key
## `Icons.MAP` hands out to five screens.
const SYMBOL_ART_ALIAS := {"heart": "hp"}

## Texture for a symbol, or null if unknown. Painted file first, authored bitmap second.
##
## Twenty-one painted symbols sat in `ui/sym_*.png` unread because this function only
## ever knew about `GLYPHS` (D115). Eleven names match outright, `heart` matches through
## the alias above, and `book` — the event marker — has no painted equivalent, which is
## why the bitmap path below is a FALLBACK and not dead code: delete it and the event
## icon goes off the map. Nine painted symbols (pierce, strength, retain, ...) have no
## glyph and no caller yet; they resolve the day something asks for one.
##
## Cached either way — a bitmap is built pixel by pixel and a painted file is a disk hit
## — and cached under the name asked for, so the alias is paid once.
static func symbol(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var painted := ui_kit("sym_" + String(SYMBOL_ART_ALIAS.get(name, name)))
	if painted != null:
		_cache[name] = painted
		return painted
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

## Painted card illustrations, checked before the CC0 atlas below.
##
## Two paths, both keyed by NAME rather than by position: `cards/<card_id>.png` for
## a card somebody drew specifically, then `cards/<family>.png` for the effect
## family it belongs to (attack, block, poison, ...), which is what ART_ASSETS asks
## for first — twelve family paintings shared by a hundred cards, unique art for
## the most-played later. The atlas slice underneath is assigned by POSITION in a
## sorted list, which is why the painted paths cannot share its directory: a
## correctly-named file dropped in there would be handed to whichever card the sort
## order reached.
const CARD_ART_DIR := "res://assets/art/cards/"
## The painted UI kit. Lives HERE rather than on UITheme because UITheme is an
## autoload, and an autoload referenced at compile time makes every script that
## touches it unloadable in a headless `--script` test — which does not fail, it
## HANGS, because the error skips the quit(). Fourth time; see D19.
const UI_KIT_DIR := "res://assets/art/ui/"

static func ui_kit(name: String) -> Texture2D:
	var p := UI_KIT_DIR + name + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

static func painted_card_art(card_id: String, family: String = "") -> Texture2D:
	var own := CARD_ART_DIR + card_id + ".png"
	if ResourceLoader.exists(own):
		return load(own) as Texture2D
	if family != "":
		var fam := CARD_ART_DIR + family + ".png"
		if ResourceLoader.exists(fam):
			return load(fam) as Texture2D
	return null

## A 16x16 slice of the sheet for this card, or null if the sheet is missing.
static func card_art(card_id: String, family: String = "") -> Texture2D:
	var key := "art_" + card_id + ":" + family
	if _cache.has(key):
		return _cache[key]
	var painted := painted_card_art(card_id, family)
	if painted != null:
		_cache[key] = painted
		return painted
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

## Relic icons, one file per relic id, cut out by `tools/install_cutouts.gd`.
##
## Same contract as `enemy_art`: keyed by ID so a file lands on the relic it was
## painted for, and null when it has not been painted yet — which is most of them,
## and which the relics screen has to keep working through (D121).
const RELIC_ART_DIR := "res://assets/art/relics/"

static func relic_art(relic_id: String) -> Texture2D:
	var p := RELIC_ART_DIR + relic_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## Power sigils, one file per power id, cut off the Tier 6b sheet by
## `tools/install_sheet.gd`.
##
## Written at the same time as the ten sigils and for the reason D121 records: an
## installer that reports "wrote 10, failed 0" says nothing about whether anything
## LOADS them, and the relic icons sat correct-and-unreachable for exactly that gap.
## Nothing in `scripts/` referenced `assets/art/powers/` before this (D122).
const POWER_ART_DIR := "res://assets/art/powers/"

static func power_art(power_id: String) -> Texture2D:
	var p := POWER_ART_DIR + power_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## Which progress band a level falls in: "" below the first milestone, then "1", "2",
## "max". The thresholds are INTEGER LEVELS derived from the cap, not a float compared
## against thirds, and that is not fussiness — `(34-1)/(100-1)` is 0.3333 and misses a
## 0.334 threshold, so a Common card sitting exactly a third of the way up its track
## showed nothing at all. Integers have no such edge (D132).
##
## A fraction of the track rather than an absolute level, because the tracks are not
## remotely the same length: a Common card caps at 100 and a Legendary at 5, Bulwark at
## 10 and Foresight at 2 (`Balance.max_level`, `PowerData.level_capped`). Any milestone
## written as "at level 5" is unreachable for one of those and immediate for another.
##
## The floor of 2 is what keeps a two-level track honest: with cap 2 the thirds both
## round down onto level 1, which is where everything STARTS, and an effect that is
## present the moment you own the thing is not a progress effect. Clamped up, cap 2 has
## exactly two states — base and maxed — which is all a two-level track can mean.
static func level_band(level: int, cap: int) -> String:
	if cap <= 1:
		return "max" if level >= cap else ""
	if level >= cap:
		return "max"
	var t2 := maxi(2, 1 + int(round(2.0 * float(cap - 1) / 3.0)))
	var t1 := maxi(2, 1 + int(round(float(cap - 1) / 3.0)))
	if level >= t2:
		return "2"
	if level >= t1:
		return "1"
	return ""

## The progress overlay for a level, or null below the first milestone.
##
## THREE files per shape, not three per subject. The overlay is a separate image
## composited over the illustration and tinted by rarity at draw time, so a hundred
## cards at five rarities across three milestones costs three files rather than fifteen
## hundred. `shape` is "card" for the 4:3 illustration band and "power" for the square
## sigil — the two cannot share one file because they are not the same rectangle, and
## that is the only reason there is more than one set (D132).
const LEVEL_FX_DIR := "res://assets/art/fx/"

## A `level_overlay_halo` lived here — a black scrim drawn under the light so an ADDITIVE
## blend had headroom on bright paint. It went out with the additive blend: screening the
## light does the same job without a second file and without darkening the illustration,
## which is what the halo was really doing (D139).
static func level_overlay(shape: String, level: int, cap: int) -> Texture2D:
	var band := level_band(level, cap)
	if band == "":
		return null
	var p := LEVEL_FX_DIR + "lvl_%s_%s.png" % [shape, band]
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null


## The installed backdrop art for a zone, or null if it is missing.
static func backdrop_texture(zone_id: String) -> Texture2D:
	var p := BG_DIR + "bg_" + zone_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## A painted battle backdrop for a specific dungeon, if one has been drawn.
##
## Separate from the tiling zone patterns: those are CC0 pixel tiles that stand in
## everywhere, these are illustrations for one place each. Falls back to the zone
## pattern so a dungeon without art is not a black screen.
const BATTLE_ART_DIR := "res://assets/art/"
## Enemy plates, one file per archetype id, generated by `tools/gen_enemy_art.gd`.
## Keyed by id, so a file lands on the enemy it was drawn for — which is the whole
## point, and what the CC0 sprite pool it replaced could not do: that pool was handed
## out by sort order, so a boss wore whichever tile the index reached and adding an
## archetype reshuffled everyone downstream of it (D89).
const ENEMY_ART_DIR := "res://assets/art/enemies/"

## Two different lines, and conflating them put the enemies at the wrong depth.
##
## `HORIZON_LINE` is where the BACK WALL meets the floor — a property of the
## painting, measured from the three that exist: 71% / 66% / 66% down. That is the
## far end of the corridor.
##
## `STAND_LINE` is where a combatant's feet go, and it is NOT the same place. In a
## one-point perspective the floor spans a range of depths; standing a figure on
## the horizon puts it as far away as the room allows, which is exactly how it
## looked — small, distant, and detached from the fight. Combatants stand further
## down the floor, nearer the viewer, just clear of the hand.
##
## `tests/test_art.gd` measures every backdrop against HORIZON_LINE (a backdrop that
## puts its floor somewhere else makes that dungeon's enemies hover) and asserts the
## stand line is BELOW it, because a figure above the horizon is standing in a wall.
const HORIZON_LINE := 0.68
const STAND_LINE := 0.72
## Tolerance either side, in the same units.
const FLOOR_TOLERANCE := 0.04

static func battle_art(dungeon_id: String) -> Texture2D:
	var p := BATTLE_ART_DIR + "bg_" + dungeon_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## The painted backdrop for a non-combat screen — shop, rest, event, treasure,
## victory, defeat — or null if that one has not been drawn.
##
## Shares a directory and a prefix with `battle_art()`, which is safe because the
## names are disjoint by construction: those are dungeon ids and these are the
## Tier 5c scene names. `tests/test_art.gd` asserts the two sets never collide,
## because the day a dungeon is called `shop` the merchant gets a fight arena.
##
## The last four are Tier 5d, the META screens, and they are in the same list rather
## than a second one on purpose: this list is what `test_art.gd` walks to check the
## collision and the 1280x720 install size, so an id kept out of it is an id nothing
## checks. Four ids for twelve screens — the grouping and the argument for it are in
## `META_BG` in `tools/art_manifest.gd` (D123).
const SCENE_ART := ["shop", "rest", "event", "treasure", "victory", "defeat",
	"table", "reliquary", "ledger", "world"]

static func scene_art(scene: String) -> Texture2D:
	var p := BATTLE_ART_DIR + "bg_" + scene + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## The painted establishing shot for a zone, for the overworld and zone-select
## screens, or null if it has not been drawn.
##
## `bg_zone_<id>`, NOT `bg_<id>`, and the prefix is load-bearing: `foundry` is both
## a zone id (`foundry_zone`) and a dungeon id, so one namespace would mean the
## Foundry's establishing shot and its fight arena are the same file. Distinct from
## `backdrop_texture()`, which serves the 16x16 CC0 tile these replace.
static func zone_art(zone_id: String) -> Texture2D:
	var p := BATTLE_ART_DIR + "bg_zone_" + zone_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## The title screen backdrop, as a path — `UI.screen()` and three tests all want it
## and none of them should be spelling the extension.
##
## It is the one painting in `assets/art/` that is a .jpg, because it is the one that
## predates the installers. Its re-roll (D114) comes back through
## `install_scene_backdrops.gd` like every other backdrop, and that tool only writes
## PNG — so for one commit both files exist, and after it only the PNG does. Resolving
## here rather than at four call sites is what makes that swap a no-op instead of a
## silent black title screen: the loss would not throw, because `UI.screen()` already
## treats a missing backdrop as "not drawn yet" and draws the menu on flat colour.
## PNG first, so the re-roll wins the moment it lands.
const TITLE_ART_CANDIDATES := [
	"res://assets/art/main_menu.png",
	"res://assets/art/main_menu.jpg",
]

static func title_art_path() -> String:
	for p in TITLE_ART_CANDIDATES:
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			return String(p)
	return ""

## The painted art for one archetype, or null if nobody has drawn it yet.
static func enemy_art(archetype_id: String) -> Texture2D:
	var p := ENEMY_ART_DIR + archetype_id + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return null

## Backdrop for a fight: the dungeon's own illustration where one exists.
##
## Dimmed, and then SCRIMMED where the text goes. Dimming alone is not enough: the
## braziers in these paintings are bright enough that white combat text over one
## measured 1.7:1, and dimming the whole image far enough to fix that (0.33) turns
## the art to mud. So the picture keeps its brightness and the bands that carry
## text get a gradient behind them — the same answer as the title screen.
const BATTLE_DIM := 0.55
## Opacity of the band behind the status line and the combat log.
const BATTLE_SCRIM := 0.78
## Held flat across the rows that actually carry text, then faded out. A pure fade
## left its own tail at almost no opacity while the art was still bright there,
## which measured 2.2:1 — averages and gradients do not read text, worst pixels do.
const BATTLE_SCRIM_HOLD := 0.15
const BATTLE_SCRIM_BAND := 0.34

static func battle_backdrop(dungeon_id: String, zone_id: String) -> Control:
	var art := battle_art(dungeon_id)
	if art == null:
		return backdrop(zone_id)

	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tr := TextureRect.new()
	tr.texture = art
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	# painted art, not pixels: NEAREST is set globally and would alias it
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.modulate = Color(BATTLE_DIM, BATTLE_DIM, BATTLE_DIM, 1.0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(tr)
	host.add_child(_text_scrim(true))    # status line, along the top
	host.add_child(_text_scrim(false))   # combat log, along the bottom
	return host

## A gradient band that fades from opaque at one edge to nothing by BAND.
static func _text_scrim(from_top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(0, 0, 0, BATTLE_SCRIM))
	g.set_offset(1, BATTLE_SCRIM_HOLD / BATTLE_SCRIM_BAND)
	g.set_color(1, Color(0, 0, 0, BATTLE_SCRIM))
	g.add_point(1.0, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 1
	gt.height = 128
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)

	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_TOP_WIDE if from_top else Control.PRESET_BOTTOM_WIDE)
	tr.anchor_left = 0.0
	tr.anchor_right = 1.0
	if from_top:
		tr.anchor_top = 0.0
		tr.anchor_bottom = BATTLE_SCRIM_BAND
	else:
		tr.anchor_top = 1.0 - BATTLE_SCRIM_BAND
		tr.anchor_bottom = 1.0
		tr.flip_v = true
	tr.offset_top = 0
	tr.offset_bottom = 0
	tr.offset_left = 0
	tr.offset_right = 0
	return tr

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

## List resources of one kind in a directory, in a form that survives EXPORT.
##
## An exported PCK does not contain the source `.png` at all. It contains the
## imported texture plus a sidecar, and `DirAccess` lists that sidecar — verified
## against a real export, which reports entries as `tile_0056.png.import`. Code
## that listed `f.ends_with(".png")` therefore found every sprite in development
## and **zero** in a shipped build: the game would have launched with no enemy art.
##
## No dev run can reveal this. The editor and `--headless` both read the real
## filesystem, where the .png plainly exists. It took exporting a pack and loading
## it back to see it — and a first guess at ".remap" was simply wrong, which is why
## tests/test_export.gd now checks the real thing instead of the assumption.
##
## `load()` still accepts the original path, so only the listing needs fixing.
static func list_resources(dir: String, suffix: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		# strip whichever sidecar suffix this build flavour reports
		for tail in [".import", ".remap"]:
			if f.ends_with(tail):
				f = f.substr(0, f.length() - tail.length())
		if f.ends_with(suffix) and not out.has(dir + f):
			out.append(dir + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

## Sorted list of every archetype id. It used to exist so sprites could be assigned by
## POSITION; nothing is positional any more (D89), but the catalogue itself is still
## what the manifest, the export smoke test and the content count enumerate.
static func archetype_ids() -> Array:
	if _cache.has("_archetypes"):
		return _cache["_archetypes"]
	var out: Array = []
	for p in list_resources("res://resources/enemies/", ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	_cache["_archetypes"] = out
	return out
