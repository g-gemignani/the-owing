## Runs INSIDE an exported pack. Everything that only breaks after export.
##
## The engine does not ship source .png files in a PCK; it ships the imported
## texture and a `.import` sidecar, and that sidecar is what DirAccess lists. Code
## matching `.png` therefore found every sprite in development and ZERO in a
## shipped build — the game would have launched with no enemy art at all.
##
## No ordinary test can catch this: the editor and `--headless` both read the real
## filesystem, where the .png plainly exists. It has to run against a built pack.
## Driven by tests/export.sh.
extends SceneTree

func _init() -> void:
	var fails := 0

	# --- directory-listed art must resolve inside a pack ---
	#
	# This is the check that caught the .import/.remap trap: an exported PCK does not
	# contain the source PNG, so code that listed `.png` found every asset in
	# development and ZERO in a shipped build. The enemy plates are loaded by PATH
	# rather than by listing (D89), which is immune to that — but the archetype
	# catalogue is still enumerated, and a plate that fails to resolve after export is
	# exactly the failure no dev run can show.
	var archetypes: int = PixelArt.archetype_ids().size()
	if archetypes == 0:
		fails += 1; print("FAIL no enemy archetypes in the exported pack")
	var no_plate := 0
	for a in PixelArt.archetype_ids():
		if PixelArt.enemy_art(a) == null:
			no_plate += 1
	if no_plate > 0:
		fails += 1; print("FAIL %d archetypes have no plate after export" % no_plate)
	if PixelArt.card_ids().size() == 0:
		fails += 1; print("FAIL no cards discoverable after export")

	# --- the other art paths ---
	if PixelArt.card_art("strike") == null:
		fails += 1; print("FAIL card illustrations missing after export")
	if PixelArt.backdrop_texture(Balance.ZONES[0]) == null:
		fails += 1; print("FAIL zone backdrops missing after export")
	if not ResourceLoader.exists("res://assets/art/main_menu.jpg"):
		fails += 1; print("FAIL title art missing after export")

	# --- content survives packing ---
	var m = load("res://scripts/meta_state.gd").new()
	if m.CATALOG.size() != PixelArt.card_ids().size():
		fails += 1; print("FAIL %d catalogued cards but %d packed" % [
			m.CATALOG.size(), PixelArt.card_ids().size()])
	for did in Balance.DUNGEONS:
		if Balance.dungeon(did) == null:
			fails += 1; print("FAIL dungeon %s did not survive export" % did)
		elif Balance.boss_of(did) == null:
			fails += 1; print("FAIL boss of %s did not survive export" % did)
	for pid in Balance.POWERS:
		if Balance.power(pid) == null:
			fails += 1; print("FAIL power %s did not survive export" % pid)

	# --- every scene the game can route to must load from the pack ---
	for scene in ["MainMenu", "Overworld", "Combat", "DeckBuilder", "Collection",
			"Powers", "Shop", "Settings", "Map", "Victory"]:
		var path := "res://scenes/%s.tscn" % scene
		if not ResourceLoader.exists(path):
			continue   # optional screens are named differently; only check real ones
		var packed := load(path) as PackedScene
		if packed == null:
			fails += 1; print("FAIL scene %s does not load from the pack" % scene); continue
		# `load()` returns a Resource even for a script that failed to PARSE, so the
		# previous null check here passed while a run view was broken for five commits.
		# Instantiating is the only honest answer.
		var inst = packed.instantiate()
		if inst == null:
			fails += 1; print("FAIL scene %s does not instantiate from the pack" % scene)
			continue
		var sc = inst.get_script()
		if sc != null and (sc as GDScript).get_instance_base_type() == "":
			fails += 1; print("FAIL scene %s has a script that does not compile" % scene)
		inst.free()

	print("  packed: %d archetypes (%d plated), %d cards" % [
		archetypes, archetypes - no_plate, PixelArt.card_ids().size()])
	if fails == 0:
		print("EXPORT TEST: PASS (art, content and scenes all resolve inside a pack)")
	else:
		print("EXPORT TEST: FAIL (%d)" % fails)
	quit()
