## What the isometric floor draws, measured against the HERO.
##
##   godot --headless --script tools/iso_scale.gd
##
## ## Why this is a tool and not a number somebody remembers
##
## `iso_run.SPRITE_H` is a table of CANVAS heights and it reads like a table of subject
## heights. Every sprite file is 128x192 and bottom-anchored, so a subject wider than that
## aspect hits the width limit first and leaves its headroom empty: the crossed axes of
## `elite.png` fill 55% of their canvas top to bottom where the hero fills 98%. The number
## in the table is therefore multiplied by the file's own fill before the player sees
## anything, and two entries one notch apart can land 40% apart on screen.
##
## That is invisible from the source and obvious here. `rest` was 2.15 against the hero's
## 2.20 — one notch shorter — and drew a campfire 0.83x her height, which is a fire she
## could have warmed her hands on the top of (D288).
##
## The props have the same shape of problem from the other side: they are sized by the
## tile's WIDTH rather than by a canvas, so their numbers are not comparable with
## `SPRITE_H`'s at all. Both are converted to one unit here — a multiple of the hero — so
## a ring and a campfire and a boss can be argued about in the same sentence.
##
## ## It reads the constants rather than restating them
##
## `iso_run.gd` references autoloads and cannot be loaded in a `--script` run (the same
## reason `IsoFooting` exists), so the obvious thing is to copy `SPRITE_H` in here. That
## copy is a restated constant, and this project has been bitten by three of them. The
## table is parsed out of the source text instead: a value changed there changes the
## report, and a value deleted there fails this loudly rather than being measured against
## a stale twin.
extends SceneTree

const SRC := "res://scripts/iso_run.gd"
const ART := "res://assets/art/iso/"
## `TILE_H` at scale 1.0. `UITheme.px()` multiplies both axes, so every ratio below is
## unaffected by it and the absolute pixels are quoted for an unscaled window.
const TILE_H := 58.0
const TILE_W := 116.0
## The file drawn for each `SPRITE_H` key. The key is not the filename for two of them —
## `wander` is a design index and `hero` is a facing — so the map is explicit.
const SPRITE_FILE := {
	"hero": "hero_s", "combat": "combat", "elite": "elite", "boss": "boss",
	"shop": "shop", "rest": "rest", "event": "event", "treasure": "treasure",
	"wander": "wander_0_s",
}
## Alpha at or above which a pixel is the subject. Matches `IsoFooting.STAND_SOLID` in
## intent: the soft haze a painted subject sits in is not the subject.
const SOLID := 0.35


func _init() -> void:
	var src := FileAccess.get_file_as_string(ProjectSettings.globalize_path(SRC))
	if src == "":
		print("cannot read %s" % SRC)
		quit(2)
		return
	var sprite_h := _sprite_table(src)
	if sprite_h.is_empty():
		print("no SPRITE_H entries found in %s — has the table moved?" % SRC)
		quit(2)
		return

	var hero := _subject_h(SPRITE_FILE["hero"], float(sprite_h.get("hero", 0.0)))
	if hero <= 0.0:
		print("no hero art — nothing to measure against")
		quit(2)
		return
	print("=== iso scale, against the hero (%.0f px of subject, unscaled) ===\n" % hero)
	print("role        file       fill   drawn WxH     subject h   x hero")
	for key in SPRITE_FILE:
		var stem := String(SPRITE_FILE[key])
		var img := _load(stem)
		if img == null:
			print("%-10s  %-10s MISSING" % [key, stem])
			continue
		var box := _bbox(img)
		var fill := float(box.size.y) / float(img.get_height())
		var drawn := float(sprite_h.get(key, 0.0)) * TILE_H
		var subject := drawn * fill
		print("%-10s  %-10s %3.0f%%   %4.0fx%-4.0f    %6.1f      %5.2f" % [
			key, stem, fill * 100.0,
			drawn * float(img.get_width()) / float(img.get_height()), drawn,
			subject, subject / hero])

	# The 70 per-archetype creatures, and the column that used to decide their size.
	#
	# `iso_run` sizes a creature by its SUBJECT now, not by its canvas, so the fill below
	# DIVIDES OUT and no longer reaches the screen (D306). It is still worth printing: it is
	# the spread that used to be the size, from 0.40 to 0.98, and the two facings of one
	# archetype disagreeing inside it is what the old rule turned into a monster that grew
	# when it turned round.
	#
	# The "x hero if it still scaled by canvas" column is therefore a record of the defect
	# rather than a reading of the game. What the floor draws now is
	# `SPRITE_H[tier] x FAMILY_H[family]`, and this tool cannot name the family: it comes
	# from `Balance.iso_family()`, which needs the autoloads a `--script` run does not have.
	# Guessing it from the filename would be a restated table, which is the habit that has
	# cost this project four bugs.
	var foe_dir := DirAccess.open(ART + "foe/")
	if foe_dir != null:
		print("\niso/foe/ — fill no longer sets the size (D306); this is the spread it used to set")
		print("file                      fill   x hero IF it still scaled by the canvas")
		var rows: Array = []
		for f in foe_dir.get_files():
			var nm := String(f)
			if not nm.ends_with(".png"):
				continue
			var img := Image.load_from_file(ProjectSettings.globalize_path(
				ART + "foe/" + nm))
			if img == null:
				continue
			img.convert(Image.FORMAT_RGBA8)
			var b := _bbox(img)
			var fl := float(b.size.y) / float(img.get_height())
			var sub: float = float(sprite_h.get("combat", 0.0)) * TILE_H * fl
			rows.append([nm.get_basename(), fl, sub, sub / hero])
		rows.sort_custom(func(a, b): return float(a[3]) < float(b[3]))
		for r in rows:
			print("%-24s %3.0f%%   %5.2f" % [
				String(r[0]), float(r[1]) * 100.0, float(r[3])])
		var fam_re := RegEx.new()
		fam_re.compile('"([a-z]+)"\\s*:\\s*([0-9]+\\.[0-9]+)')
		var fam_start := src.find("const FAMILY_H := {")
		if fam_start >= 0:
			var fam_body := src.substr(fam_start, src.find("}", fam_start) - fam_start)
			print("\nwhat the floor draws now, per family, on a COMBAT tile:")
			for m in fam_re.search_all(fam_body):
				var hh: float = float(sprite_h.get("combat", 0.0)) * TILE_H \
					* float(m.get_string(2))
				print("  %-8s %.2f x combat = %5.1f px = %.2f x hero" % [
					m.get_string(1), float(m.get_string(2)), hh, hh / hero])

	print("\nprops, sized by the tile's WIDTH rather than by a canvas")
	var ring := _const(src, "PROP_WALL_RING")
	var drape := _const(src, "PROP_WALL_DRAPE")
	var ground := _const(src, "PROP_TILE")
	print("  PROP_TILE %.2f   PROP_WALL_RING %.2f   PROP_WALL_DRAPE %.2f" % [
		ground, ring, drape])
	var dir := DirAccess.open(ART)
	if dir == null:
		quit(0)
		return
	var stems: Array = []
	for f in dir.get_files():
		var name := String(f)
		if name.begins_with("prop_") and name.ends_with(".png"):
			stems.append(name.get_basename())
	stems.sort()
	for stem in stems:
		var img := _load(String(stem))
		if img == null:
			continue
		var box := _bbox(img)
		# A ring is the only wall prop that is a fixture; the rest of what hangs is matter
		# falling down the face. Read off the filename here because `Balance.iso_props`
		# needs the autoloads this script cannot have.
		var on_wall: bool = String(stem).ends_with("ring") or String(stem) in [
			"prop_roots", "prop_hanging_matter"]
		var frac: float = ground
		if on_wall:
			frac = ring if String(stem).ends_with("ring") else drape
		var w: float = TILE_W * frac
		var h: float = w * float(img.get_height()) / float(img.get_width())
		var subject: float = h * float(box.size.y) / float(img.get_height())
		print("  %-24s %-6s drawn %3.0fx%-3.0f   subject h %5.1f   x hero %5.2f" % [
			stem, "wall" if on_wall else "floor", w, h, subject, subject / hero])
	quit(0)


## The `SPRITE_H` entries, parsed out of the source. Every `"key": number` pair between the
## `const SPRITE_H := {` line and its closing brace, so a comment between two entries — and
## there are several, they carry the reasoning — cannot break it.
func _sprite_table(src: String) -> Dictionary:
	var out := {}
	var start := src.find("const SPRITE_H := {")
	if start < 0:
		return out
	var end := src.find("\n}", start)
	if end < 0:
		return out
	var body := src.substr(start, end - start)
	var re := RegEx.new()
	re.compile('"([a-z_]+)"\\s*:\\s*([0-9]+\\.[0-9]+)')
	for m in re.search_all(body):
		out[m.get_string(1)] = float(m.get_string(2))
	return out


func _const(src: String, name: String) -> float:
	var re := RegEx.new()
	re.compile("const %s\\s*:=\\s*([0-9]+\\.[0-9]+)" % name)
	var m := re.search(src)
	return float(m.get_string(1)) if m != null else 0.0


func _subject_h(stem: String, sprite_h: float) -> float:
	var img := _load(stem)
	if img == null:
		return 0.0
	var box := _bbox(img)
	return sprite_h * TILE_H * float(box.size.y) / float(img.get_height())


func _load(stem: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ART + stem + ".png"))
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## The opaque box, which is the only part of a file the player sees.
func _bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > SOLID:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
