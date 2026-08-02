## Headless test: art coverage and pixel-art correctness.
##
## Art is easy to half-finish: a missing texture shows as an invisible button, and
## with the wrong filter every sprite silently turns to mush when scaled. Both are
## invisible in a headless run unless asserted.
## Run: godot --headless --script tests/test_art.gd
extends SceneTree

## Some properties only exist in source at this stage: UI scripts reference
## autoloads, which are not registered in a headless `--script` run.
func _source_has(path: String, needle: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	return text.find(needle) != -1

## Every directory at or under `root` that holds at least one PNG. Discovered rather
## than listed, which is the whole point of the check that uses it.
func _dirs_with_pngs(root: String) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var has_png := false
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if d.current_is_dir():
				if not f.begins_with("."):
					stack.append(dir + f + "/")
			# an exported PCK lists the sidecar rather than the source, the trap
			# `PixelArt.list_resources` documents — so accept either spelling
			elif f.ends_with(".png") or f.ends_with(".png.import"):
				has_png = true
			f = d.get_next()
		d.list_dir_end()
		if has_png:
			out.append(dir)
	out.sort()
	return out

## Does this README name a generator that actually exists? A README claiming the art is
## generated is worth nothing if the tool it names was deleted — which is exactly what
## happens when a generated set is abandoned and the files are left behind.
func _names_generator(readme: String) -> bool:
	if not FileAccess.file_exists(readme):
		return false
	var text := FileAccess.open(readme, FileAccess.READ).get_as_text()
	var at := text.find("tools/gen_")
	while at >= 0:
		var end := at
		while end < text.length() and not text[end] in [" ", "\n", "\t", "`", ")", ","]:
			end += 1
		if FileAccess.file_exists("res://" + text.substr(at, end - at)):
			return true
		at = text.find("tools/gen_", at + 1)
	return false

## The .gitignore lines that keep PNGs out of the repository.
func _ignored_png_patterns() -> Array:
	var out: Array = []
	if not FileAccess.file_exists("res://.gitignore"):
		return out
	for line in FileAccess.open("res://.gitignore", FileAccess.READ).get_as_text().split("\n"):
		var l: String = String(line).strip_edges()
		if l.is_empty() or l.begins_with("#"):
			continue
		if l.ends_with(".png") or l.ends_with("/"):
			out.append(l)
	return out

## Minimal glob: `*` matches within one path segment, which is all these patterns use.
func _matches_any(path: String, patterns: Array) -> bool:
	for p in patterns:
		var pat := String(p)
		if pat.ends_with("/"):
			if path.begins_with(pat):
				return true
			continue
		if path.matchn(pat):
			return true
	return false

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()

	# --- pixel art must not be filtered ---
	var filter := int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", 1))
	if filter != 0:
		fails += 1; print("FAIL default texture filter is %d, not NEAREST — pixel art will blur" % filter)

	# --- every symbol resolves, is square, and has a shape in it ---
	#
	# This asserted 16x16 exactly, and scanned a hardcoded 16x16 window, until D115
	# gave `PixelArt.symbol()` a painted 64x64 file to prefer over the authored
	# bitmap. Both are legitimate answers, so the assertion cannot name a size — what
	# it is actually protecting is that a symbol is SQUARE (every consumer centres it
	# in a square box, so a non-square glyph arrives letterboxed or stretched) and on
	# the 16px grid the whole pixel-art rule rests on.
	#
	# The emptiness floor moved with it, from 12 pixels to the fraction 12 pixels of a
	# 16x16 frame always meant. An absolute count is not scale-free: 12 lit pixels is
	# a real glyph at 16x16 and a fleck of dust at 64x64, and the 16x16 window was
	# worse than that — on a 64px glyph it sampled only the top-left quadrant, so four
	# painted symbols read as empty while their subject sat untouched in the middle.
	const SYMBOL_MIN_LIT := 12.0 / 256.0
	for name in PixelArt.GLYPHS:
		var t := PixelArt.symbol(name)
		if t == null:
			fails += 1; print("FAIL symbol %s did not build" % name); continue
		var w := t.get_width()
		var h := t.get_height()
		if w != h or w % 16 != 0 or w == 0:
			fails += 1; print("FAIL symbol %s is %dx%d — not a square multiple of 16" % [name, w, h])
		# a glyph that is blank or almost blank reads as a missing icon
		var img := t.get_image()
		var lit := 0
		for y in h:
			for x in w:
				if img.get_pixel(x, y).a > 0.5:
					lit += 1
		var cover := float(lit) / float(maxi(1, w * h))
		if cover < SYMBOL_MIN_LIT:
			fails += 1; print("FAIL symbol %s is nearly empty (%.1f%% of %dx%d lit)" % [
				name, cover * 100.0, w, h])
	print("  (info: %d symbol names)" % PixelArt.GLYPHS.size())

	# --- every semantic name used by the UI resolves ---
	#
	# This loop got sharper teeth in D116 without changing a line. Every name in `MAP`
	# used to bottom out in an authored bitmap, so it could only fail if somebody typed a
	# glyph name wrong; the nine names added for the painted-only meanings (strength,
	# weak, pierce, ...) have NO bitmap under them, so this is now the check that
	# `assets/art/ui/sym_*.png` is still on disk and still imported. A missing painting
	# there draws nothing at all, silently, on the deck builder and the shop.
	for key in Icons.MAP:
		if Icons.tex(key) == null:
			fails += 1; print("FAIL Icons.tex('%s') resolves to nothing" % key)

	# --- every enemy has a sprite, and they are distinct ---
	var used := {}
	var ids := PixelArt.archetype_ids()
	if ids.is_empty():
		fails += 1; print("FAIL no enemy archetypes found")
	# Every archetype has a plate of its own, and no two share one.
	#
	# This used to assert the same thing about a POOL of 41 CC0 sprites handed out by
	# sort order, which needed a 12-entry override table to stop bosses inheriting
	# trash-mob faces. The plates are keyed by id (D89), so "shared sprite" is now
	# impossible by construction and what is worth checking is that one exists at all —
	# a missing plate is silent, and `combat.gd` draws an empty footprint box for it.
	var missing: Array = []
	for id in ids:
		var t := Icons.enemy(id)
		if t == null:
			missing.append(id)
			continue
		used[t.resource_path] = int(used.get(t.resource_path, 0)) + 1
	if not missing.is_empty():
		fails += 1
		print("FAIL %d archetype(s) have no plate in assets/art/enemies/ — run tools/gen_enemy_art.gd then --import: %s" % [
			missing.size(), ", ".join(missing)])
	if used.size() < ids.size() - missing.size():
		fails += 1; print("FAIL two archetypes resolved to the same plate")
	print("  (info: %d archetypes, %d distinct plates)" % [ids.size(), used.size()])

	# --- every card resolves to a symbol that suits it ---
	for cid in m.CATALOG:
		var c := load(m.CATALOG[cid]) as CardData
		var icon := Icons.for_card(c)
		if Icons.tex(icon) == null:
			fails += 1; print("FAIL card %s maps to missing icon '%s'" % [cid, icon])
	# and the mapping must actually discriminate, not label everything "card"
	#
	# The floor was 4 and is 8 since D116, and 8 is DERIVED rather than picked: the old
	# cascade could return exactly seven names for any card anybody could ever write
	# (poison, thorns, attack, block, hp, relic, card), so 8 is the smallest floor that no
	# version of the pre-D116 mapping can satisfy. Raising it to the number today's 100
	# cards happen to produce would pin content, not behaviour.
	var kinds := {}
	for cid in m.CATALOG:
		kinds[Icons.for_card(load(m.CATALOG[cid]) as CardData)] = true
	if kinds.size() < 8:
		fails += 1; print("FAIL card icons only use %d distinct symbols" % kinds.size())
	print("  (info: cards use %d distinct symbols: %s)" % [kinds.size(), kinds.keys()])

	# --- the painted symbols D116 wired up must each be reached by a real card ---
	#
	# A count cannot see this. `kinds.size()` was 7 through the entire period in which
	# healing showed a heart and Strength showed a stack of coins, and it would still be 7
	# if all six of these regressed to `card`. What the paintings need is a *consumer* —
	# the exact thing D115 found missing for three decisions, with 21 files installed and
	# 13 meanings sayable.
	#
	# Failing when the last card of a kind is deleted is the point, not brittleness: it is
	# the only report that a painted symbol has gone back to being decoration on disk.
	for meaning in ["heal", "strength", "dexterity", "energy", "vulnerable", "weak"]:
		if not kinds.has(meaning):
			fails += 1
			print("FAIL no card resolves to '%s' — ui/sym_%s.png has no consumer again" % [
				meaning, meaning])

	# --- and the cascade's ORDER is the behaviour, so pin it ---
	#
	# Most cards do two or three things, so which line of `for_card` wins is the whole
	# design of it. Probed on synthetic cards rather than catalogue ids because a content
	# edit must not be able to quietly delete the case under test — the trap that let a
	# name-filtered harness go silent in D88.
	if Icons.for_card(null) != "card":
		fails += 1; print("FAIL Icons.for_card(null) does not fall back to 'card'")
	var cascade := [
		# The pair the deck builder, the collection, the shop and every card face got
		# wrong for the whole life of the game: a Strength card must show Strength.
		[{"gain_strength": 3}, "strength"],
		[{"gain_dexterity": 5}, "dexterity"],
		[{"heal": 12}, "heal"],
		[{"apply_vulnerable": 2}, "vulnerable"],
		[{"apply_weak": 2}, "weak"],
		# `kick`: the Energy is what the card is for, which is why there is no `draw`
		# branch above it — see Icons.for_card.
		[{"energy_gain": 1, "draw": 1}, "energy"],
		# ...but an attack that also grants Strength is an ATTACK (`forge_strike`). The
		# headline number is what the player reads, and a buff glyph would bury it.
		[{"damage": 6, "gain_strength": 1}, "attack"],
		# Block outranks the healing beside it (`iron_lung`) and poison outranks the
		# damage carrying it (`creeping_death`) — the two ends of the same cascade.
		[{"block": 8, "heal": 15}, "block"],
		[{"damage": 5, "apply_poison": 4}, "poison"],
		# nothing legible: fall back rather than guess
		[{}, "card"],
	]
	for row in cascade:
		var fields: Dictionary = row[0]
		var probe := CardData.new()
		for k in fields:
			probe.set(String(k), fields[k])
		var got := Icons.for_card(probe)
		if got != String(row[1]):
			fails += 1
			print("FAIL Icons.for_card(%s) is '%s', expected '%s'" % [fields, got, row[1]])

	# --- every zone has a real backdrop, and it stays a BACKDROP ---
	#
	# The danger with a background is not that it is missing but that it competes
	# with the text on top of it, so brightness and internal contrast are asserted,
	# not just presence. Seamlessness matters too: a visible tiling seam across
	# every screen is worse than a flat colour.
	for z in Balance.all_zones():
		var art := PixelArt.backdrop_texture(z.id)
		if art == null:
			fails += 1; print("FAIL zone %s has no backdrop art (falls back to authored)" % z.id); continue
		var img := art.get_image()
		var w := img.get_width()
		var h := img.get_height()
		if w != 16 or h != 16:
			fails += 1; print("FAIL backdrop %s is %dx%d, not a 16x16 tile" % [z.id, w, h])
			continue
		var lum := 0.0
		var mr := 0.0
		var mg := 0.0
		var mb := 0.0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				lum += c.get_luminance()
				mr += c.r; mg += c.g; mb += c.b
		lum /= float(w * h)
		mr /= float(w * h); mg /= float(w * h); mb /= float(w * h)
		if lum > 0.40:
			fails += 1; print("FAIL backdrop %s is too bright (%.2f) — it will fight the text" % [z.id, lum])
		# internal contrast: a busy backdrop is a distracting one
		var busy := 0.0
		for y in h:
			for x in w:
				var c := img.get_pixel(x, y)
				busy += abs(c.r - mr) + abs(c.g - mg) + abs(c.b - mb)
		busy /= float(w * h * 3)
		if busy > 0.12:
			fails += 1; print("FAIL backdrop %s is too busy (%.3f)" % [z.id, busy])
		# seamless: opposite edges must match, or tiling shows a grid of seams
		var wrap := 0.0
		for i in 16:
			var l := img.get_pixel(0, i)
			var r := img.get_pixel(15, i)
			var t := img.get_pixel(i, 0)
			var b := img.get_pixel(i, 15)
			wrap += abs(l.r - r.r) + abs(l.g - r.g) + abs(l.b - r.b)
			wrap += abs(t.r - b.r) + abs(t.g - b.g) + abs(t.b - b.b)
		wrap /= 96.0
		if wrap > 0.06:
			fails += 1; print("FAIL backdrop %s does not tile seamlessly (wrap %.3f)" % [z.id, wrap])
		print("  (info: backdrop %-13s lum %.2f busy %.3f wrap %.3f)" % [z.id, lum, busy, wrap])

	# every zone must also have a tint, or they all look the same
	for z in Balance.all_zones():
		if not PixelArt.ZONE_BACKDROP.has(z.id):
			fails += 1; print("FAIL zone %s has no backdrop tint" % z.id)
	# and the tints must differ
	var tints := {}
	for k in PixelArt.ZONE_BACKDROP:
		tints[str(PixelArt.ZONE_BACKDROP[k][1])] = true
	if tints.size() < PixelArt.ZONE_BACKDROP.size():
		fails += 1; print("FAIL some zones share a backdrop tint")

	# --- every card has its own illustration ---
	#
	# The sheet is unlabelled, so what a card's art *depicts* is arbitrary. What must
	# hold is that each card has one, that no two share it (identical art reads as a
	# bug), and that every slice lands inside the sheet.
	var sheet_ok := ResourceLoader.exists(PixelArt.CARD_SHEET)
	if not sheet_ok:
		fails += 1; print("FAIL card art sheet missing")
	else:
		var sheet := load(PixelArt.CARD_SHEET) as Texture2D
		var regions := {}
		for cid in m.CATALOG:
			var a := PixelArt.card_art(cid)
			if a == null:
				fails += 1; print("FAIL no illustration for card %s" % cid); continue
			var at := a as AtlasTexture
			if at == null:
				fails += 1; print("FAIL card %s art is not a sheet slice" % cid); continue
			var r := at.region
			if r.position.x < 0 or r.position.y < 0 \
					or r.end.x > float(sheet.get_width()) or r.end.y > float(sheet.get_height()):
				fails += 1; print("FAIL card %s art region %s falls outside the sheet" % [cid, r])
			if r.size != Vector2(PixelArt.CARD_TILE, PixelArt.CARD_TILE):
				fails += 1; print("FAIL card %s art slice is %s, not one tile" % [cid, r.size])
			regions[str(r)] = int(regions.get(str(r), 0)) + 1
		var dupes := 0
		for k in regions:
			if int(regions[k]) > 1:
				dupes += 1
		if dupes > 0:
			fails += 1; print("FAIL %d illustration(s) shared between cards" % dupes)
		if PixelArt.CARD_TILES.size() < m.CATALOG.size():
			fails += 1; print("FAIL only %d tiles for %d cards" % [
				PixelArt.CARD_TILES.size(), m.CATALOG.size()])
		print("  (info: %d cards, %d distinct illustrations, %d tile pool)" % [
			m.CATALOG.size(), regions.size(), PixelArt.CARD_TILES.size()])

	# --- the card's meaningful symbol must still be distinct from its art ---
	# (illustration is decoration; the symbol states the effect and must be present)
	for cid in m.CATALOG:
		var c := load(m.CATALOG[cid]) as CardData
		if Icons.tex(Icons.for_card(c)) == null:
			fails += 1; print("FAIL card %s lost its effect symbol" % cid)

	# --- no PNG in this tree may be both committable and unlicensed (D89) ---
	#
	# This check used to name FOUR directories, and that is precisely how the isometric
	# floor art sat in the tree for a whole milestone with no licence file, no
	# attribution, and a README of its own saying "licence status: UNKNOWN for the
	# floor, NON-COMMERCIAL for the hero". Nothing was watching, because the watcher had
	# a hand-kept list and the new directory was not on it.
	#
	# So the directories are DISCOVERED now, and each PNG has to be accounted for in one
	# of exactly three ways:
	#
	#   1. a licence file sits beside it (the CC0 packs),
	#   2. its directory's README names the generator that made it (ours outright), or
	#   3. .gitignore keeps it out of the repository (local stand-ins).
	#
	# Anything else is art we would be redistributing without knowing whether we may.
	var ignored := _ignored_png_patterns()
	var checked := 0
	for dir in _dirs_with_pngs("res://assets/"):
		var d := DirAccess.open(dir)
		if d == null:
			continue
		var has_licence := false
		var pngs: Array = []
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.to_lower().contains("licen"):
				has_licence = true
			if f.ends_with(".png"):
				pngs.append(f)
			f = d.get_next()
		d.list_dir_end()
		# a subdirectory may be documented by its parent's README — the UI frame kit is
		# explained in `assets/art/README.md` and has no README of its own, which is
		# reasonable and would otherwise read as undeclared art
		var generated := _names_generator(dir + "README.md") \
			or _names_generator(String(dir).get_base_dir().get_base_dir() + "/README.md")
		for png in pngs:
			checked += 1
			if has_licence or generated:
				continue
			if _matches_any(String(dir).replace("res://", "") + String(png), ignored):
				continue
			fails += 1
			print("FAIL %s%s has no licence beside it, no generator named in %sREADME.md, and is not gitignored — committing it redistributes art we have not cleared" % [
				dir, png, dir])
	print("  (info: %d PNGs across %d directories, each licensed, generated or gitignored)" % [
		checked, _dirs_with_pngs("res://assets/").size()])

	for dir2 in ["res://assets/art/enemies/", "res://assets/pixel/bg/", "res://assets/pixel/cards/"]:
		if DirAccess.open(dir2) == null:
			fails += 1; print("FAIL missing art directory %s" % dir2)

	# --- rarity colours must be distinguishable, since rarity is read by colour ---
	for i in Icons.RARITY_COLOURS.size():
		for j in range(i + 1, Icons.RARITY_COLOURS.size()):
			var a: Color = Icons.RARITY_COLOURS[i]
			var b: Color = Icons.RARITY_COLOURS[j]
			var dist: float = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
			if dist < 0.25:
				fails += 1; print("FAIL rarity colours %d and %d are too similar (%.2f)" % [i, j, dist])

	# --- sound ---
	#
	# Audio fails quietly by nature: a missing file is silence, and a silence is
	# indistinguishable from "no sound was meant to play". So every declared event
	# must resolve to a real stream, and the volume mapping must actually mute.
	var A = load("res://scripts/audio.gd")
	var declared := 0
	for event in A.SOUNDS:
		declared += 1
		var path: String = A.DIR + String(A.SOUNDS[event]) + ".ogg"
		if not ResourceLoader.exists(path):
			fails += 1; print("FAIL sound event '%s' has no file (%s)" % [event, path])
			continue
		var st := load(path) as AudioStream
		if st == null:
			fails += 1; print("FAIL sound '%s' did not load as audio" % event)
		elif st.get_length() <= 0.0:
			fails += 1; print("FAIL sound '%s' is empty" % event)
	if declared < 15:
		fails += 1; print("FAIL only %d sound events declared" % declared)
	print("  (info: %d sound events)" % declared)

	# every sound file shipped should be referenced, or it is dead weight
	var used_sounds := {}
	for event in A.SOUNDS:
		used_sounds[String(A.SOUNDS[event])] = true
	var d := DirAccess.open(A.DIR)
	if d != null:
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".ogg") and not used_sounds.has(f.replace(".ogg", "")):
				print("  WARN unused sound file: %s" % f)
			f = d.get_next()
		d.list_dir_end()

	# volume mapping: 0 must be silent, 100 must be unattenuated, monotonic between
	if A.to_db(0) > -60.0:
		fails += 1; print("FAIL volume 0 is not silent (%.1f dB)" % A.to_db(0))
	if abs(A.to_db(100)) > 0.5:
		fails += 1; print("FAIL volume 100 is attenuated (%.1f dB)" % A.to_db(100))
	var prev_db := -999.0
	for v in [0, 10, 25, 50, 75, 100]:
		var db: float = A.to_db(v)
		if db < prev_db - 0.001:
			fails += 1; print("FAIL volume mapping not monotonic at %d" % v)
		prev_db = db

	# --- the floor every enemy stands on ---------------------------------------
	#
	# The fight is framed head-on into the backdrop's corridor with no player
	# character rendered, so the enemies are placed on ONE line — PixelArt.STAND_LINE
	# — and every painted backdrop has to put its floor there. A backdrop that puts
	# it somewhere else does not look wrong on its own; it makes the enemies in that
	# dungeon hover or sink, which reads as an enemy bug.
	#
	# The measurement is a heuristic — the largest row-to-row luminance step in the
	# lower half — and when the other nine backdrops landed (D73) it turned out not to
	# be good enough to assert on. It scored the Foundry at 51% and the Maw at 82%,
	# and BOTH are correct: rendering those two fights shows the enemies' feet on
	# STAND_LINE, on the painted floor. What it actually found was a stone lintel
	# running across the Foundry's walls and the pale bone clutter low in the Maw. Six
	# of twelve tripped a ±10pt band. Tightening the search to the centre corridor was
	# tried and simply moved the errors around (it fixed the Foundry and broke the
	# Ossuary, 66% -> 55%).
	#
	# So this PRINTS for every backdrop and fails only on a value no dungeon room
	# could legitimately produce — a floor in the top half, or off the bottom edge.
	# That still catches a portrait, a sky-filled scene or a wrong file, which is the
	# gross miss worth automating. Whether a specific enemy hovers is a question for
	# `tools/screenshots.gd`, where you can see it; a number that is confidently wrong
	# half the time is worse than an honest eyeball.
	var floor_lo := 0.45
	var floor_hi := 0.95
	var checked_bg := 0
	for did in Balance.DUNGEONS:
		var bg := PixelArt.battle_art(did)
		if bg == null:
			continue
		checked_bg += 1
		var f := _floor_fraction(bg.get_image())
		var off: float = absf(f - PixelArt.HORIZON_LINE)
		print("  (info: %s floor ~%.0f%% (line %.0f%%, off %.0f pts))" % [
			did, f * 100.0, PixelArt.HORIZON_LINE * 100.0, off * 100.0])
		if f < floor_lo or f > floor_hi:
			fails += 1
			print("FAIL %s has no floor in the lower half (~%.0f%%) — wrong image?" % [
				did, f * 100.0])
	if checked_bg == 0:
		fails += 1; print("FAIL no painted battle backdrop was measured")
	# a figure standing ABOVE the horizon is standing in the back wall
	if PixelArt.STAND_LINE <= PixelArt.HORIZON_LINE:
		fails += 1
		print("FAIL the stand line (%.2f) is not below the horizon (%.2f) — enemies would stand in the wall" % [
			PixelArt.STAND_LINE, PixelArt.HORIZON_LINE])

	# --- the generator's signature must not be in the shipped art --------------
	#
	# The image tool stamps a sparkle into the bottom-right corner. Twelve files
	# carried one and nobody noticed for two milestones, because at 45px in a dim
	# corner it reads as a highlight until you put the corners side by side.
	#
	# Detected the same way `tools/strip_sparkle.gd` removes it: anything brighter
	# than its own surroundings in EVERY one of the twelve, at the same pixel. A
	# brazier is bright in one room and absent from the next; a stamp is in all of
	# them. This is a re-derivation rather than a call into the tool, on purpose —
	# a check that shares its subject's code cannot catch its subject being wrong.
	var bgs: Array[Image] = []
	for did3 in Balance.DUNGEONS:
		var bt := PixelArt.battle_art(did3)
		if bt == null:
			continue
		var bi := bt.get_image()
		if bi == null:
			continue
		if bi.is_compressed():
			bi.decompress()
		bgs.append(bi)
	if bgs.size() >= 4:
		var common := _common_bright_corner(bgs)
		print("  (info: corner lit in all %d backdrops: %d px, largest blob %d)" % [
			bgs.size(), common[0], common[1]])
		# The LARGEST CONNECTED BLOB, not the total, and the difference is what makes
		# this assertable. Twelve rooms drawn by one generator share more than a
		# watermark: they all put a lit pillar edge in this corner, which is 225 px of
		# scattered agreement and cannot be thresholded away from the stamp's 759.
		# As one blob they separate cleanly — the stamp measured 461 px in a 38x34
		# box, the pillar edge 58 px in a 6x20 sliver. Eight times over.
		if common[1] > 200:
			fails += 1
			print("FAIL a %d px blob is lit in every dungeon backdrop's corner — that is the generator's watermark. Run tools/strip_sparkle.gd" % common[1])

	# --- the non-combat backdrops share that directory and that prefix ---------
	#
	# `scene_art("shop")` and `battle_art("shop")` are the same path. Today the two
	# name sets are disjoint, and this is what keeps them that way: the day someone
	# adds a dungeon called `rest`, the campfire becomes its fight arena and the
	# rest screen shows the fight arena, with nothing anywhere reporting a problem.
	for scene in PixelArt.SCENE_ART:
		if Balance.DUNGEONS.has(scene):
			fails += 1
			print("FAIL '%s' is both a dungeon id and a scene backdrop — one file, two meanings" % scene)
	# The zone shots live in their own namespace for the same reason, and this is
	# the case that would actually happen: `foundry` is a zone AND a dungeon, and
	# the generator delivered the zone painting under that exact name.
	var zones_done := 0
	for zid2 in Balance.ZONES:
		if not _source_has("res://scripts/pixel_art.gd", "bg_zone_"):
			break
		var za := PixelArt.zone_art(zid2)
		if za == null:
			continue
		zones_done += 1
		if za.get_width() != 1280 or za.get_height() != 720:
			fails += 1
			print("FAIL bg_zone_%s.png is %dx%d, not 1280x720" % [
				zid2, za.get_width(), za.get_height()])
		if FileAccess.file_exists("res://assets/art/bg_" + zid2 + ".png") \
				and not Balance.DUNGEONS.has(zid2):
			fails += 1
			print("FAIL zone %s also has an unprefixed bg_%s.png — one of them is misfiled" % [
				zid2, zid2])
	print("  (info: %d of %d zone backdrops painted)" % [zones_done, Balance.ZONES.size()])
	if not _source_has("res://scripts/ui.gd", "PixelArt.zone_art"):
		fails += 1
		print("FAIL nothing loads the zone backdrops — the files would do nothing")

	var scenes_done := 0
	for scene2 in PixelArt.SCENE_ART:
		var sa := PixelArt.scene_art(scene2)
		if sa == null:
			continue
		scenes_done += 1
		# Installed at the shipped size by `tools/install_scene_backdrops.gd`. A file
		# at some other aspect gets COVER-cropped at runtime, which silently eats the
		# edges of a painting that was composed symmetrically.
		if sa.get_width() != 1280 or sa.get_height() != 720:
			fails += 1
			print("FAIL bg_%s.png is %dx%d, not 1280x720 — run tools/install_scene_backdrops.gd" % [
				scene2, sa.get_width(), sa.get_height()])
	print("  (info: %d of %d scene backdrops painted)" % [scenes_done, PixelArt.SCENE_ART.size()])
	if not _source_has("res://scripts/ui.gd", "PixelArt.scene_art"):
		fails += 1
		print("FAIL nothing loads the scene backdrops — the files would do nothing")

	# --- a painted backdrop must be painted all the way down -------------------
	#
	# Unlike the floor-fraction heuristic above, this one is not a judgement call and
	# is safe to assert on: a ROW of a painted image whose pixels all share one
	# luminance is not art, it is fill. Real paint always has tooth.
	#
	# It is here because four meta-screen backdrops shipped with their lower halves
	# filled in as flat rectangles, and the brief asked for it — "one continuous
	# surface at one even value ... no grain that changes value" reads to a generator
	# as "flood this". `bg_world.png` measured 0.001 row-variance below 65% of frame
	# height where `bg_crypt.png` runs 0.049-0.202 throughout. It hides under a full
	# list and is a grey slab on a sparse screen like Packs (D125).
	#
	# The threshold is deliberately far below anything a painting produces: the worst
	# legitimate row measured across the twelve dungeons and six scene backdrops is an
	# order of magnitude above it, so this fires on fill and on nothing else.
	## Texture in the top half against texture in the bottom half. A painting keeps
	## comparable tooth all the way down; one that stops partway falls off a cliff.
	##
	## This is the measurement that works, and it took three tries. Counting rows with
	## ZERO horizontal variance catches the worst two and misses `bg_table.png`, whose
	## dead half is filled at 0.021 rather than at nothing. Thresholding the bottom
	## half's texture on its own cannot work either: `bg_shop.png` legitimately bottoms
	## out at 0.016, which is the same neighbourhood. Only the DROP separates them, and
	## it separates them with an enormous margin — the four broken meta backdrops run
	## 4.9 to 49.9, and every legitimate backdrop in the tree runs 0.4 to 1.2 (D125).
	##
	## The floor underneath is for the degenerate case the ratio cannot see: an image
	## flat in BOTH halves would score 1.0 and pass. Nothing in the tree is close —
	## the lowest legitimate bottom half is 0.053, ten times the floor.
	var TEXTURE_DROP_MAX := 3.0
	var TEXTURE_FLOOR := 0.005
	for bgname in PixelArt.SCENE_ART:
		var bgt := PixelArt.scene_art(bgname)
		if bgt == null:
			continue
		var bgi := bgt.get_image()
		bgi.convert(Image.FORMAT_RGBA8)
		var bw := bgi.get_width()
		var bh := bgi.get_height()
		var halves := [0.0, 0.0]
		for half in 2:
			var tot := 0.0
			var n := 0
			for yy in range(bh * half / 2, bh * (half + 1) / 2):
				var rs := 0.0
				var rs2 := 0.0
				for xx in bw:
					var rl := bgi.get_pixel(xx, yy).get_luminance()
					rs += rl
					rs2 += rl * rl
				var rmean := rs / float(bw)
				tot += sqrt(maxf(rs2 / float(bw) - rmean * rmean, 0.0))
				n += 1
			halves[half] = tot / float(maxi(n, 1))
		var top_t: float = halves[0]
		var bot_t: float = halves[1]
		if bot_t < TEXTURE_FLOOR:
			fails += 1
			print("FAIL bg_%s.png: its lower half has no paint in it at all (texture %.4f)" % [
				bgname, bot_t])
		elif top_t / bot_t > TEXTURE_DROP_MAX:
			fails += 1
			print("FAIL bg_%s.png: the painting stops partway down (top %.3f, bottom %.3f, %.0fx drop) — a list cannot sit on a slab" % [
				bgname, top_t, bot_t, top_t / bot_t])

	# --- painted enemies are keyed by id, not by position ----------------------
	#
	# The CC0 pixel sprites are assigned by position in a sorted directory listing,
	# so a correctly-named file dropped in THERE is handed to whichever archetype the
	# sort order reaches. The painted directory is keyed by archetype id instead, and
	# a file whose name is not an archetype silently does nothing — so say so.
	var arche := {}
	for did2 in Balance.DUNGEONS:
		var dd3 := Balance.dungeon(did2)
		if dd3 == null:
			continue
		for aid in dd3.enemy_roster:
			arche[String(aid)] = true
		if dd3.boss != "":
			arche[dd3.boss] = true
	var d4 := DirAccess.open(PixelArt.ENEMY_ART_DIR)
	var painted := 0
	if d4 != null:
		d4.list_dir_begin()
		var f4 := d4.get_next()
		while f4 != "":
			if f4.ends_with(".png") or f4.ends_with(".png.import"):
				var id4 := f4.replace(".png.import", "").replace(".png", "")
				painted += 1
				if not arche.has(id4):
					fails += 1
					print("FAIL %s%s.png is not an archetype id — nothing will ever load it" % [
						PixelArt.ENEMY_ART_DIR, id4])
			f4 = d4.get_next()
		d4.list_dir_end()
	print("  (info: %d of %d archetypes have painted art)" % [painted, arche.size()])
	if not _source_has("res://scripts/pixel_art.gd", "ENEMY_ART_DIR + archetype_id"):
		fails += 1
		print("FAIL painted enemy art is not looked up by archetype id")

	# --- the art the game does not have yet must still have somewhere to land ----
	#
	# Two whole paths in ART_ASSETS had no code behind them: the twelve card-family
	# illustrations, and 22 of the 24 frame-kit files. Files dropped in would have
	# sat on disk doing nothing, which is the worst kind of gap — it looks like an
	# art problem. These assert the HOOK, not the file.
	if not _source_has("res://scripts/pixel_art.gd", "CARD_ART_DIR + card_id"):
		fails += 1; print("FAIL card illustrations are not looked up by card id")
	if not _source_has("res://scripts/pixel_art.gd", "CARD_ART_DIR + family"):
		fails += 1; print("FAIL card illustrations are not looked up by effect family")
	for hook in ["frame_button", "frame_panel", "frame_tooltip", "dropdown",
			"slider_track", "slider_grabber", "scrollbar_track", "scrollbar_grabber",
			"checkbox_on", "checkbox_off"]:
		if not _source_has("res://scripts/ui_theme.gd", hook):
			fails += 1
			print("FAIL nothing loads ui/%s.png — the file would do nothing" % hook)
	for cardhook in ["frame_card_rarity_%d", "frame_card"]:
		if not _source_has("res://scripts/icons.gd", cardhook):
			fails += 1
			print("FAIL nothing loads ui/%s.png" % cardhook)
	# The family a card resolves to must come from ONE function. The manifest used to
	# carry its own copy: twelve families there, seven in the code, and filenames
	# that did not match — so five of the paintings it asked for could never have
	# been loaded and the other seven would have been looked for under other names.
	var fams := {}
	for cid2 in m.CATALOG:
		fams[Icons.card_family(load(m.CATALOG[cid2]) as CardData)] = true
	print("  (info: %d card families to paint: %s)" % [fams.size(), fams.keys()])
	if _source_has("res://tools/art_manifest.gd", "func _family("):
		fails += 1
		print("FAIL the art manifest keeps its own card-family table; use Icons.card_family")

	# --- music -----------------------------------------------------------------
	#
	# The Music bus and its slider existed for a long time with nothing routed to
	# them: the setting adjusted the volume of silence. That is worse than an
	# obviously missing feature, because the UI claims otherwise. So the checks are
	# about the WIRING, not the notes.
	var scores: int = A.SCORES.size()
	if scores < 3:
		fails += 1; print("FAIL only %d scores declared — one loop for the whole game" % scores)
	var streams := {}
	for score in A.SCORES:
		var mpath: String = A.MUSIC_DIR + String(A.SCORES[score]) + ".ogg"
		if not ResourceLoader.exists(mpath):
			fails += 1; print("FAIL score '%s' has no file (%s)" % [score, mpath])
			continue
		var mst := load(mpath) as AudioStream
		if mst == null or mst.get_length() <= 1.0:
			fails += 1; print("FAIL score '%s' is missing or too short to be a loop" % score)
			continue
		# A track that does not loop stops after half a minute and the game goes
		# quiet mid-dungeon, which reads as a bug in the sound, not in the flag.
		if mst is AudioStreamOggVorbis and not (mst as AudioStreamOggVorbis).loop:
			if not _source_has("res://scripts/audio.gd", "loop = true"):
				fails += 1; print("FAIL score '%s' does not loop and nothing sets it" % score)
		streams[String(A.SCORES[score])] = true
	# five names pointing at one file is one track pretending to be five
	if streams.size() != scores:
		fails += 1; print("FAIL %d scores share only %d files" % [scores, streams.size()])

	# every screen resolves to a real score, including ones nobody listed
	for scene_name in A.SCENE_SCORE:
		if not A.SCORES.has(String(A.SCENE_SCORE[scene_name])):
			fails += 1; print("FAIL %s asks for score '%s', which does not exist" % [
				scene_name, A.SCENE_SCORE[scene_name]])
	if not A.SCORES.has(A.DEFAULT_SCORE):
		fails += 1; print("FAIL the fallback score '%s' does not exist" % A.DEFAULT_SCORE)
	# the point of the whole exercise: music must be on the bus the slider drives
	if not _source_has("res://scripts/audio.gd", "_music.bus = \"Music\""):
		fails += 1; print("FAIL the music player is not on the Music bus — the slider does nothing")

	# licences for the audio packs too
	var has_audio_licence := false
	if d != null:
		d.list_dir_begin()
		var f2 := d.get_next()
		while f2 != "":
			if f2.to_lower().contains("licen"):
				has_audio_licence = true
			f2 = d.get_next()
		d.list_dir_end()
	if not has_audio_licence:
		fails += 1; print("FAIL no licence file in %s" % A.DIR)

	# --- painted title art exists and is not filtered like a pixel sprite ---
	#
	# Only the source-level half lives here: reading UI.* would pull in UITheme,
	# an autoload that is NOT registered in a headless `--script` run, and the
	# resulting compile error silently skips the checks while still reporting a
	# pass. The runtime half is tests/MenuArtTest.tscn.
	if PixelArt.title_art_path() == "":
		fails += 1; print("FAIL title art missing: none of %s" % [PixelArt.TITLE_ART_CANDIDATES])
	if not _source_has("res://scripts/ui.gd", "TEXTURE_FILTER_LINEAR"):
		fails += 1; print("FAIL painted backdrop is not LINEAR-filtered — it will look jagged")

	if fails == 0:
		print("ART TEST: PASS (filtering, symbols, sprites, illustrations, backdrops, title art, sound, licences)")
	else:
		print("ART TEST: FAIL (%d)" % fails)
	quit()

## Where the floor meets the wall, as a fraction of image height: the largest
## row-to-row luminance step in the lower half. Sampled every 4th pixel — this runs
## over a dozen 1280x720 images and precision is not what is being asked of it.
func _floor_fraction(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var rows: Array[float] = []
	for y in h:
		var s := 0.0
		var n := 0
		for x in range(0, w, 4):
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
		rows.append(s / maxf(1.0, float(n)))
	var best_y := int(h * 0.68)
	var best_d := 0.0
	for y in range(int(h * 0.45), h - 2):
		var d: float = absf(rows[y + 1] - rows[y])
		if d > best_d:
			best_d = d
			best_y = y
	return float(best_y) / float(h)

## How much of the bottom-right corner is brighter than its own local background in
## EVERY image. Returns [total px, largest connected blob]. Independent of
## `tools/strip_sparkle.gd` by design.
##
## The margin exclusion matters: the local mean is clipped within a radius of the
## window edge, so a light-to-dark boundary there shows a false excess in every
## image at once — which is exactly what this looks for, and would report a
## watermark on twelve clean files.
func _common_bright_corner(imgs: Array[Image]) -> Array:
	const WW := 280
	const WH := 240
	const R := 20
	const LIT := 0.05
	var lit: Array[bool] = []
	lit.resize(WW * WH)
	lit.fill(true)
	for img in imgs:
		var x0 := img.get_width() - WW
		var y0 := img.get_height() - WH
		if x0 < 0 or y0 < 0:
			return [0, 0]
		var lum := PackedFloat32Array()
		lum.resize(WW * WH)
		for y in WH:
			for x in WW:
				lum[y * WW + x] = img.get_pixel(x0 + x, y0 + y).get_luminance()
		for y in range(R, WH - R):
			for x in range(R, WW - R):
				var i := y * WW + x
				if not lit[i]:
					continue
				var s := 0.0
				var n := 0
				for yy in range(y - R, y + R + 1):
					for xx in range(x - R, x + R + 1, 3):
						s += lum[yy * WW + xx]
						n += 1
				if lum[i] - s / float(n) <= LIT:
					lit[i] = false
	for y in WH:
		for x in WW:
			if x < R or x >= WW - R or y < R or y >= WH - R:
				lit[y * WW + x] = false
	var total := 0
	for b in lit:
		if b:
			total += 1
	# largest 4-connected component
	var seen: Array[bool] = []
	seen.resize(lit.size())
	seen.fill(false)
	var biggest := 0
	for start in lit.size():
		if not lit[start] or seen[start]:
			continue
		var size := 0
		var stack: Array[int] = [start]
		seen[start] = true
		while not stack.is_empty():
			var i: int = stack.pop_back()
			size += 1
			var x: int = i % WW
			var y: int = i / WW
			for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= WW or ny >= WH:
					continue
				var j: int = ny * WW + nx
				if lit[j] and not seen[j]:
					seen[j] = true
					stack.append(j)
		biggest = maxi(biggest, size)
	return [total, biggest]
