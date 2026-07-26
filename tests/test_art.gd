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

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()

	# --- pixel art must not be filtered ---
	var filter := int(ProjectSettings.get_setting(
		"rendering/textures/canvas_textures/default_texture_filter", 1))
	if filter != 0:
		fails += 1; print("FAIL default texture filter is %d, not NEAREST — pixel art will blur" % filter)

	# --- every authored symbol builds, and is actually 16x16 pixel art ---
	for name in PixelArt.GLYPHS:
		var t := PixelArt.symbol(name)
		if t == null:
			fails += 1; print("FAIL symbol %s did not build" % name); continue
		if t.get_width() != 16 or t.get_height() != 16:
			fails += 1; print("FAIL symbol %s is %dx%d, not 16x16" % [name, t.get_width(), t.get_height()])
		# a glyph that is blank or almost blank reads as a missing icon
		var img := t.get_image()
		var lit := 0
		for y in 16:
			for x in 16:
				if img.get_pixel(x, y).a > 0.5:
					lit += 1
		if lit < 12:
			fails += 1; print("FAIL symbol %s is nearly empty (%d pixels)" % [name, lit])
	print("  (info: %d authored symbols)" % PixelArt.GLYPHS.size())

	# --- every semantic name used by the UI resolves ---
	for key in Icons.MAP:
		if Icons.tex(key) == null:
			fails += 1; print("FAIL Icons.tex('%s') resolves to nothing" % key)

	# --- every enemy has a sprite, and they are distinct ---
	var used := {}
	var ids := PixelArt.archetype_ids()
	if ids.is_empty():
		fails += 1; print("FAIL no enemy archetypes found")
	for id in ids:
		var t := Icons.enemy(id)
		if t == null:
			fails += 1; print("FAIL no sprite for enemy %s" % id); continue
		used[t.resource_path] = int(used.get(t.resource_path, 0)) + 1
	var shared := 0
	for k in used:
		if int(used[k]) > 1:
			shared += 1
	if shared > 0:
		fails += 1; print("FAIL %d sprite(s) shared between enemies — they look identical" % shared)
	print("  (info: %d enemies, %d distinct sprites, %d available)" % [
		ids.size(), used.size(), PixelArt.enemy_sprites().size()])
	if PixelArt.enemy_sprites().size() < ids.size():
		fails += 1; print("FAIL fewer sprites (%d) than enemies (%d)" % [
			PixelArt.enemy_sprites().size(), ids.size()])

	# --- every card resolves to a symbol that suits it ---
	for cid in m.CATALOG:
		var c := load(m.CATALOG[cid]) as CardData
		var icon := Icons.for_card(c)
		if Icons.tex(icon) == null:
			fails += 1; print("FAIL card %s maps to missing icon '%s'" % [cid, icon])
	# and the mapping must actually discriminate, not label everything "card"
	var kinds := {}
	for cid in m.CATALOG:
		kinds[Icons.for_card(load(m.CATALOG[cid]) as CardData)] = true
	if kinds.size() < 4:
		fails += 1; print("FAIL card icons only use %d distinct symbols" % kinds.size())
	print("  (info: cards use %d distinct symbols: %s)" % [kinds.size(), kinds.keys()])

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

	# --- licences must ship beside the borrowed art ---
	for dir in ["res://assets/pixel/enemies/", "res://assets/pixel/ui/", "res://assets/pixel/bg/", "res://assets/pixel/cards/"]:
		var d := DirAccess.open(dir)
		if d == null:
			fails += 1; print("FAIL missing art directory %s" % dir); continue
		var has_licence := false
		var pngs := 0
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.to_lower().contains("licen"):
				has_licence = true
			if f.ends_with(".png"):
				pngs += 1
			f = d.get_next()
		d.list_dir_end()
		if not has_licence:
			fails += 1; print("FAIL no licence file in %s" % dir)
		if pngs == 0:
			fails += 1; print("FAIL no art in %s" % dir)

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

	# --- a pinned sprite must exist, or the pin silently does nothing ---
	# Four boss overrides named tiles that had never been copied into the project.
	# enemy_sprite() fell back to positional assignment without a word, and the
	# bosses quietly wore other enemies' faces.
	for aid in PixelArt.OVERRIDES:
		var pinned: String = PixelArt.ENEMY_DIR + String(PixelArt.OVERRIDES[aid]) + ".png"
		if not ResourceLoader.exists(pinned):
			fails += 1; print("FAIL %s is pinned to %s, which does not exist" % [aid, pinned])

	# --- painted title art exists and is not filtered like a pixel sprite ---
	#
	# Only the source-level half lives here: reading UI.* would pull in UITheme,
	# an autoload that is NOT registered in a headless `--script` run, and the
	# resulting compile error silently skips the checks while still reporting a
	# pass. The runtime half is tests/MenuArtTest.tscn.
	var title_art := "res://assets/art/main_menu.jpg"
	if not ResourceLoader.exists(title_art):
		fails += 1; print("FAIL title art missing: %s" % title_art)
	if not _source_has("res://scripts/ui.gd", "TEXTURE_FILTER_LINEAR"):
		fails += 1; print("FAIL painted backdrop is not LINEAR-filtered — it will look jagged")

	if fails == 0:
		print("ART TEST: PASS (filtering, symbols, sprites, illustrations, backdrops, title art, sound, licences)")
	else:
		print("ART TEST: FAIL (%d)" % fails)
	quit()
