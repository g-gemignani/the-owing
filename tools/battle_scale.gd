## What the BATTLE screen draws, measured against a person.
##
##   godot --headless --script tools/battle_scale.gd
##
## The sister of `tools/iso_scale.gd`, and the two exist for the same reason: a size is a
## claim about a painting, and the painting can disagree. This one has an extra job the
## other does not — the two screens draw the same roster from the same `EnemyData.stature`
## since D323, and the last column is where they can be caught coming apart.
##
## ## Why the roster and not three creatures
##
## Creature size in the crawl was got wrong three times (D306, D309, D320), every time by
## tuning a number against a sample of two or three archetypes. The battle screen had the
## same defect, undetected for as long, and from the same cause: every plate was drawn in
## one square box, so the height a creature reached was decided by how much of ITS OWN
## canvas the painting used. A cultist fills 98% of its file and a plague rat fills 98% of
## its file, so a rat was drawn as tall as a man.
##
## Every archetype, every time. A sample cannot find this.
##
## ## It reads the constants rather than restating them
##
## `combat.gd` references autoloads and cannot be loaded in a `--script` run (the same
## reason `IsoFooting` exists), so the person height and the tier table are parsed out of
## its source. A copy here would be a fourth restated constant in a project that has been
## bitten by three.
extends SceneTree

const SRC := "res://scripts/combat.gd"
const ART := "res://assets/art/enemies/"
## An unscaled window. `UITheme.px()` multiplies the whole layout, so every ratio below is
## unaffected by it and the pixels are quoted for the design size.
const VIEW_H := 720.0
const TIERS := ["NORMAL", "ELITE", "BOSS"]


func _init() -> void:
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		push_error("cannot read " + SRC)
		quit(1)
		return
	var src := f.get_as_text()
	var person_frac := _person_frac(src)
	var tier_size := _tier_table(src)
	if person_frac <= 0.0 or tier_size.is_empty():
		push_error("could not parse the person fraction or TIER_SIZE out of " + SRC)
		quit(1)
		return

	print("battle plates — a person is %.0f%% of a %.0f-tall frame, times the tier's camera"
		% [person_frac * 100.0, VIEW_H])
	print("tier camera: " + ", ".join(TIERS.map(func(t): return "%s %.2f" % [t, tier_size[t]])))
	# `was@N` is the ordinary-tier figure only. The camera multiplied the old size and the
	# new one identically, so one tier is enough to read the change by — everywhere the
	# ceiling does not cut in, the other two columns move by the same factor.
	print("\nfile                stature  fill   subject h px           was@N   wide/tall")
	print("                                     NORMAL  ELITE   BOSS")

	var dir := DirAccess.open(ART)
	if dir == null:
		push_error("cannot open " + ART)
		quit(1)
		return
	var rows: Array = []
	for name in dir.get_files():
		var nm := String(name)
		if not nm.ends_with(".png"):
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(ART + nm))
		if img == null:
			continue
		img.convert(Image.FORMAT_RGBA8)
		var box := _bbox(img)
		if box.size.y <= 0:
			continue
		var aid := nm.get_basename()
		var fill: float = float(box.size.y) / float(img.get_height())
		var st: float = Balance.stature(aid)
		var wide: float = float(box.size.x) / float(box.size.y)
		var heights: Array = []
		for t in TIERS:
			# The screen's own arithmetic: a person times the stature, capped by the band
			# the frame has for it. Quoted as the SUBJECT because that is the creature.
			var person: float = VIEW_H * person_frac * float(tier_size[t])
			heights.append(minf(person * st, _ceiling()))
		# What one square box drew: the whole canvas at the tier's height, so the subject
		# came out at the file's own fill and the archetype was never consulted.
		var was: float = minf(VIEW_H * person_frac * float(tier_size["NORMAL"]), _ceiling()) * fill
		rows.append([aid, st, fill, heights, was, wide])
	rows.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	for r in rows:
		var h: Array = r[3]
		print("%-19s %5.2f  %4.2f  %6.1f %6.1f %6.1f  %6.1f    %5.2f" % [
			String(r[0]), float(r[1]), float(r[2]),
			float(h[0]), float(h[1]), float(h[2]), float(r[4]), float(r[5])])

	# The crawl draws the same roster from the same number, so the two screens are one
	# claim measured twice. A creature that reads as a rat in the corridor and a person in
	# the fight is the D320 defect back again, one screen along.
	print("\nagainst the crawl — both screens size from `EnemyData.stature`, so these must agree")
	var iso := DirAccess.open("res://assets/art/iso/foe/")
	var missing: Array = []
	var extra: Array = []
	if iso != null:
		var iso_ids := {}
		for name in iso.get_files():
			var nm := String(name)
			if not nm.ends_with(".png"):
				continue
			var stem := nm.get_basename()
			iso_ids[stem.substr(0, stem.rfind("_"))] = true
		for r in rows:
			if not iso_ids.has(String(r[0])):
				missing.append(String(r[0]))
		for id in iso_ids:
			var found := false
			for r in rows:
				if String(r[0]) == String(id):
					found = true
			if not found:
				extra.append(String(id))
	print("  painted for the fight but not for the floor: %s" % [
		", ".join(missing) if not missing.is_empty() else "none"])
	print("  painted for the floor but not for the fight: %s" % [
		", ".join(extra) if not extra.is_empty() else "none"])
	# An art defect, printed so it stays a defect rather than settling into the numbers.
	var cropped: Array = []
	for aid in Balance.ISO_CROP:
		cropped.append("%s (iso shows %.0f%% of it, so the floor draws %.2f)" % [
			aid, float(Balance.ISO_CROP[aid]) * 100.0, Balance.iso_stature(String(aid))])
	cropped.sort()
	print("  iso file is a BUST, not the whole creature: %s" % [
		", ".join(cropped) if not cropped.is_empty() else "none — repaint done"])

	# An archetype in two tiers is drawn at two sizes, and that is the CAMERA doing it
	# rather than the creature — the whole cast of that fight moves with it. Printed so
	# the difference is a decision somebody made and not a surprise.
	print("\nin more than one tier — same creature, two cameras")
	var rosters := {}
	for t in TIERS:
		for aid in _roster(t):
			if not rosters.has(aid):
				rosters[aid] = []
			(rosters[aid] as Array).append(t)
	var shared: Array = []
	for aid in rosters:
		if (rosters[aid] as Array).size() > 1:
			shared.append("%s (%s)" % [aid, ", ".join(rosters[aid])])
	shared.sort()
	print("  " + (", ".join(shared) if not shared.is_empty() else "none"))
	quit(0)


## The tallest a creature may be drawn, in an unscaled 720-tall frame: the floor line, less
## the top band and the three text rows. Parsed from nothing — these are `UITheme.px()`
## values at scale 1.0 and `PixelArt.STAND_LINE`, which this script cannot load either, so
## they are quoted here and the report says so on the tin.
func _ceiling() -> float:
	return VIEW_H * 0.72 - 96.0 - 66.0


## The fraction of the frame an ordinary person is drawn at, out of `_place_slots`.
func _person_frac(src: String) -> float:
	var re := RegEx.new()
	re.compile("var person := vp\\.y \\* ([0-9]+\\.[0-9]+) \\* tier_scale")
	var m := re.search(src)
	return float(m.get_string(1)) if m != null else 0.0


## `TIER_SIZE`, parsed rather than restated.
func _tier_table(src: String) -> Dictionary:
	var out := {}
	var start := src.find("const TIER_SIZE := {")
	if start < 0:
		return out
	var body := src.substr(start, src.find("\n}", start) - start)
	var re := RegEx.new()
	re.compile("Balance\\.Tier\\.([A-Z]+)\\s*:\\s*([0-9]+\\.[0-9]+)")
	for m in re.search_all(body):
		out[m.get_string(1)] = float(m.get_string(2))
	return out


## One tier's roster. `Balance` is a plain class rather than an autoload, so this one can be
## read directly instead of parsed.
func _roster(tier_name: String) -> Array:
	match tier_name:
		"NORMAL": return Array(Balance.ROSTER[Balance.Tier.NORMAL])
		"ELITE": return Array(Balance.ROSTER[Balance.Tier.ELITE])
		"BOSS": return Array(Balance.ROSTER[Balance.Tier.BOSS])
	return []


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
			if img.get_pixel(x, y).a >= 0.03:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
