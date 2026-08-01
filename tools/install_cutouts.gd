## One-shot installer for painted CUTOUTS: enemies, relics, powers, card art.
##
## The three installers that came before it (`install_backdrops.gd`,
## `install_scene_backdrops.gd`) all assume an opaque 16:9 frame. Everything left on
## the art list is the opposite shape — a subject on transparent, at a fixed canvas
## size, anchored somewhere specific — and no image generator produces that. It
## produces a painting of a monster standing in a room. This turns one into the other:
##
##   matte -> despeckle -> trim -> scale -> anchor -> `assets/art/<family>/<id>.png`
##
##   godot --headless --script tools/install_cutouts.gd -- enemies <src_dir> [--dry]
##   godot --headless --script tools/install_cutouts.gd -- relics  <src_dir>
##   godot --headless --script tools/install_cutouts.gd -- powers  <src_dir>
##   godot --headless --script tools/install_cutouts.gd -- cards   <src_dir>
##   godot --headless --import
##
## **The filename is the wiring, again** (D73). `PixelArt.enemy_art(id)` resolves
## `enemies/<archetype_id>.png` directly, so a file under the wrong name is not a
## mis-titled asset, it is an invisible one — indistinguishable from art that was
## never made. Every target id here is checked against the catalogue before anything
## is written, and source names are matched against BOTH the id and the content's
## display name, because a generator names its output after the prompt: "The
## Grave-Sexton.png" has to land on `grave_sexton`.
##
## **Anchoring is the part that is easy to get silently wrong.** Enemies are placed
## by `combat.gd` with their feet on `PixelArt.STAND_LINE`, so the subject's lowest
## opaque pixel must be the canvas's bottom row — any transparent padding under it is
## the enemy hovering by exactly that much, in every fight, forever. Relics and
## powers are shown in a square slot and are centred. That is the whole difference,
## and it is why `ANCHOR_BOTTOM` is per-family rather than a flag someone remembers.
##
## **The watermark comes off for free here, and it is not luck.** `strip_sparkle.gd`
## finds the generator's stamp by intersecting "brighter than its own surroundings"
## across images that share one frame — a trick that has no subject on a batch of
## cutouts at different sizes with different silhouettes. It does not need one: the
## stamp sits in the corner, the corner is background, and the matte takes it. What
## it leaves is a small ISLAND of opaque pixels away from the subject, which would
## then drag the trim box out to the corner and shrink the monster to fit beside its
## own watermark. So the despeckle pass is load-bearing, not tidiness: components
## under `ISLAND_MIN` of the largest are dropped, and the count is printed, because a
## silently-deleted limb and a silently-deleted watermark look the same from here.
extends SceneTree

const ART := "res://assets/art/"

## The image work — matte, despeckle, trim, scale, anchor — lives in the library, so
## this file and `install_sheet.gd` cannot drift into two different ideas of what a
## cutout is. What is left here is the half that is specific to one-subject-per-file:
## resolving a source filename to a catalogue id.
const Cut := preload("res://tools/cutout_lib.gd")

## family -> [subdirectory, default canvas, anchor-to-bottom]
const FAMILIES := {
	"enemies": ["enemies", 256, true],
	"relics": ["relics", 128, false],
	"powers": ["powers", 128, false],
	"cards": ["cards", 320, false],
}
## Bosses are drawn bigger because they are RENDERED bigger (combat.gd TIER_SIZE is
## 1.34x): a 256px boss upscaled to the biggest thing on screen is a soft boss.
const BOSS_SIZE := 512
## Card illustrations are the one non-square canvas: they fill the card's top band.
const CARD_SIZE := Vector2i(320, 240)

var _dry := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dry = args.has("--dry")
	var positional: Array[String] = []
	for a in args:
		if not String(a).begins_with("--"):
			positional.append(String(a))
	if positional.size() < 2 or not FAMILIES.has(positional[0]):
		print("usage: -- <%s> <src_dir> [--dry]" % "|".join(FAMILIES.keys()))
		quit(2)
		return

	var family: String = positional[0]
	var src: String = positional[1]
	if not src.ends_with("/"):
		src += "/"

	var wanted := _wanted(family)          # id -> canvas size
	var lookup := _lookup(family, wanted)  # normalised name -> id
	print("%s: %d wanted" % [family, wanted.size()])

	var out_dir: String = ART + String(FAMILIES[family][0]) + "/"
	if not _dry:
		DirAccess.make_dir_recursive_absolute(Cut.abs_path(out_dir))

	var wrote := 0
	var failed := 0
	var unmatched: Array[String] = []
	for path in Cut.sources(src):
		var key := _normalise(path.get_file().get_basename())
		if not lookup.has(key):
			unmatched.append("%s (read as '%s')" % [path.get_file(), key])
			continue
		var id: String = lookup[key]
		var img := Cut.load_image(path)
		if img == null:
			print("FAIL  could not read %s" % path.get_file())
			failed += 1
			continue
		var canvas: Vector2i = wanted[id]
		var note := Cut.cut(img, canvas, bool(FAMILIES[family][2]))
		if note != "":
			print("FAIL  %-22s %s" % [path.get_file(), note])
			failed += 1
			continue
		if _dry:
			print("DRY   %-22s -> %s/%s.png  %dx%d" % [
				path.get_file(), FAMILIES[family][0], id, canvas.x, canvas.y])
			continue
		var to: String = out_dir + id + ".png"
		if img.save_png(Cut.abs_path(to)) != OK:
			print("FAIL  writing %s" % to)
			failed += 1
			continue
		var notes := ""
		if Cut.dropped_islands > 0:
			notes += "  (dropped %d stray island(s) — watermark or specks)" % Cut.dropped_islands
		if Cut.filled_pockets > 0:
			notes += "  (filled %d trapped background pocket(s))" % Cut.filled_pockets
		print("  %-24s <- %-28s %dx%d%s" % [id + ".png", path.get_file(), canvas.x, canvas.y,
			notes])
		wrote += 1

	# A source nobody could place is the failure mode this whole tool exists to make
	# loud: it means the art was made and the game will never load it.
	if not unmatched.is_empty():
		print("\nUNMATCHED (%d) — these were NOT installed:" % unmatched.size())
		for u in unmatched:
			print("  %s" % u)
		print("  valid ids: %s" % ", ".join(wanted.keys()))

	var missing: Array[String] = []
	for id in wanted:
		if not FileAccess.file_exists(Cut.abs_path(out_dir + String(id) + ".png")):
			missing.append(String(id))
	print("\nwrote %d, failed %d, unmatched %d" % [wrote, failed, unmatched.size()])
	if missing.is_empty():
		print("every %s now has art" % family)
	else:
		print("STILL MISSING (%d/%d): %s" % [
			missing.size(), wanted.size(), ", ".join(missing)])
	quit(1 if (failed > 0 or not unmatched.is_empty()) else 0)


# --- what the catalogues say is wanted ---------------------------------------

## id -> canvas size, straight from the content catalogues, so this cannot list a
## relic the game does not have or miss one it does (D34).
func _wanted(family: String) -> Dictionary:
	var out := {}
	var n := int(FAMILIES[family][1])
	match family:
		"enemies":
			var bosses := _boss_ids()
			for aid in PixelArt.archetype_ids():
				out[aid] = Vector2i.ONE * (BOSS_SIZE if bosses.has(aid) else n)
		"relics":
			for rid in MetaState.RELIC_CATALOG:
				out[rid] = Vector2i.ONE * n
		"powers":
			for pid in Balance.POWERS:
				out[pid] = Vector2i.ONE * n
		"cards":
			for cid in PixelArt.card_ids():
				var c := load("res://resources/cards/%s.tres" % cid) as CardData
				if c != null:
					out[Icons.card_family(c)] = CARD_SIZE
	return out


func _boss_ids() -> Dictionary:
	var out := {}
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null and dd.boss != "":
			out[dd.boss] = true
	return out


## Every name a source file might plausibly carry, mapped to the id it means. Both
## the id and the display name, because the generator is prompted with the name.
func _lookup(family: String, wanted: Dictionary) -> Dictionary:
	var out := {}
	for id in wanted:
		out[_normalise(String(id))] = id
		var display := _display_name(family, String(id))
		if display != "":
			out[_normalise(display)] = id
	return out


func _display_name(family: String, id: String) -> String:
	match family:
		"enemies":
			var a := load("res://resources/enemies/%s.tres" % id) as EnemyData
			return a.name if a != null else ""
		"relics":
			var r := load(String(MetaState.RELIC_CATALOG.get(id, ""))) as RelicData
			return r.name if r != null else ""
		"powers":
			var p := Balance.power(id)
			return p.name if p != null else ""
	return ""


## "The Grave-Sexton (2).png" and "grave_sexton" have to collide. Lowercase, drop a
## leading article, punctuation to underscore, and drop a trailing copy-number —
## which is what a second download from the same prompt is called.
func _normalise(s: String) -> String:
	var t := s.to_lower().strip_edges()
	var clean := ""
	for i in t.length():
		var ch := t[i]
		clean += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while clean.contains("__"):
		clean = clean.replace("__", "_")
	clean = clean.trim_prefix("_").trim_suffix("_")
	clean = clean.trim_prefix("the_")
	# a trailing bare number is a duplicate marker, not part of a name; no id ends in one
	var parts := clean.split("_", false)
	while parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "_".join(parts)
