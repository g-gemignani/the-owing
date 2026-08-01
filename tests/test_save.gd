## Headless test: save versioning and migration.
## The save shape has changed repeatedly; this guards that an older file still
## loads, that a newer one is refused rather than silently truncated, and that
## garbage does not wipe a player's progress.
## Run: godot --headless --script tests/test_save.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_save_"

## Resolved through MetaState so it follows the test sandbox prefix rather than
## writing over the player's real save.
static func path() -> String:
	return load("res://scripts/meta_state.gd").path_for(0)

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")

	# --- a current save round-trips ---
	var m = Meta.new()
	m.new_save()
	m.add_gold(123)
	m.add_relic("iron_heart")
	m.mark_cleared(Balance.DUNGEONS[0])
	m.save_deck("Test", {"hack": 4, "cover": 4})
	m.save_game()
	var m2 = Meta.new()
	if not m2.load_game():
		fails += 1; print("FAIL current save did not load")
	if m2.gold != 123 or not m2.has_relic("iron_heart") or m2.clear_count() != 1:
		fails += 1; print("FAIL round-trip lost data")
	if not m2.decks.has("Test"):
		fails += 1; print("FAIL round-trip lost decks")

	# --- a v0 save (pre-versioning: no relics/decks/clears/gold) migrates ---
	_write({
		"collection": {"hack": {"count": 5, "level": 2}, "cover": {"count": 4, "level": 1}},
		"highest_dungeon": 3,
	})
	var m3 = Meta.new()
	if not m3.load_game():
		fails += 1; print("FAIL v0 save did not load")
	if int(m3.collection["hack"]["count"]) != 5 or int(m3.collection["hack"]["level"]) != 2:
		fails += 1; print("FAIL v0 collection not preserved")
	if m3.gold != 0 or m3.relics.size() != 0 or m3.clear_count() != 0:
		fails += 1; print("FAIL v0 defaults wrong")
	if not m3.decks.has("Starter"):
		fails += 1; print("FAIL v0 did not get a starter deck")
	if m3.highest_dungeon != 3:
		fails += 1; print("FAIL v0 lost highest_dungeon")
	# migration must have rewritten the file at the current version
	var again = Meta.new()
	again.load_game()
	if again.gold != 0 or not again.decks.has("Starter"):
		fails += 1; print("FAIL migrated save did not persist")
	# a backup of the pre-migration file must exist
	if not FileAccess.file_exists(path() + ".v0.bak"):
		fails += 1; print("FAIL no backup written before migrating")

	# --- a save from a FUTURE version is refused, not truncated ---
	_write({"version": Meta.SAVE_VERSION + 5, "collection": {"hack": {"count": 4, "level": 1}}})
	var m4 = Meta.new()
	if m4.load_game():
		fails += 1; print("FAIL loaded a save from a newer version")

	# --- unknown content ids are dropped, not fatal ---
	_write({
		"version": Meta.SAVE_VERSION,
		"collection": {"hack": {"count": 4, "level": 1}, "ghost_card": {"count": 9, "level": 3}},
		"relics": ["iron_heart", "ghost_relic"],
		"cleared_dungeons": ["crypt", "ghost_dungeon"],
		"decks": {"D": {"hack": 4, "ghost_card": 2}},
		"gold": 50,
	})
	var m5 = Meta.new()
	if not m5.load_game():
		fails += 1; print("FAIL save with unknown ids refused")
	if m5.collection.has("ghost_card"):
		fails += 1; print("FAIL unknown card kept in collection")
	if m5.has_relic("ghost_relic"):
		fails += 1; print("FAIL unknown relic kept")
	if "ghost_dungeon" in m5.cleared_dungeons:
		fails += 1; print("FAIL unknown dungeon kept")
	if m5.decks.has("D") and m5.decks["D"].has("ghost_card"):
		fails += 1; print("FAIL unknown card kept in a saved deck")
	if m5.gold != 50:
		fails += 1; print("FAIL good fields lost alongside bad ones")

	# --- corrupt file must not load (and must not crash) ---
	var f := FileAccess.open(path(), FileAccess.WRITE)
	f.store_string("{ this is not json ")
	f.close()
	var m6 = Meta.new()
	if m6.load_game():
		fails += 1; print("FAIL corrupt save reported success")

	# --- an empty collection is repaired rather than left unplayable ---
	_write({"version": Meta.SAVE_VERSION, "collection": {}})
	var m7 = Meta.new()
	m7.load_game()
	var sel := {}
	for id in m7.collection:
		sel[id] = m7.collection[id]["count"]
	if not m7.deck_valid(sel):
		fails += 1; print("FAIL empty collection left the player unable to build a deck")

	# --- every historical save version must still migrate ---
	#
	# The migration chain grows a step per release and had no fixtures: only v0 was
	# ever exercised, so a v2 or v3 save could have failed silently for releases.
	# Each fixture is the shape that version actually wrote, and each must arrive
	# with its progress intact and the current version's defaults filled in.
	for old in [
			{"v": 0, "d": {"collection": {"hack": {"count": 6, "level": 2}}}},
			{"v": 1, "d": {"version": 1, "collection": {"hack": {"count": 6, "level": 2}},
				"relics": ["iron_heart"], "gold": 120, "cleared_dungeons": ["crypt"],
				"decks": {"Starter": {"hack": 4}}}},
			{"v": 2, "d": {"version": 2, "collection": {"hack": {"count": 6, "level": 2}},
				"relics": ["iron_heart"], "gold": 120, "cleared_dungeons": ["crypt"],
				"decks": {"Starter": {"hack": 4}}, "consumables": {"escape_rope": 2}}},
			{"v": 3, "d": {"version": 3, "collection": {"hack": {"count": 6, "level": 2}},
				"relics": ["iron_heart"], "gold": 120, "cleared_dungeons": ["crypt"],
				"decks": {"Starter": {"hack": 4}}, "consumables": {"escape_rope": 2},
				"starter_kit": "blade", "ascension": 1}},
			{"v": 4, "d": {"version": 4, "collection": {"hack": {"count": 6, "level": 2}},
				"relics": ["iron_heart"], "gold": 120, "cleared_dungeons": ["crypt"],
				"decks": {"Starter": {"hack": 4}}, "consumables": {"escape_rope": 2},
				"starter_kit": "blade", "ascension": 1, "highest_dungeon": 3}},
		]:
		_write(old["d"])
		var mv = Meta.new()
		if not mv.load_game():
			fails += 1; print("FAIL a v%d save does not load" % old["v"]); continue
		if mv.owned("hack") != 6 or int(mv.collection["hack"]["level"]) != 2:
			fails += 1; print("FAIL v%d migration lost the collection" % old["v"])
		if old["v"] >= 1 and mv.gold != 120:
			fails += 1; print("FAIL v%d migration lost gold (%d)" % [old["v"], mv.gold])
		if old["v"] >= 1 and not mv.has_cleared("crypt"):
			fails += 1; print("FAIL v%d migration lost dungeon clears" % old["v"])
		# every version predates powers, so each must arrive with the starter one
		if mv.power_data() == null:
			fails += 1
			print("FAIL v%d migration leaves the player with no power" % old["v"])
		# and it must be rewritten in the current shape, not left stale
		var reread = Meta.new()
		if not reread.load_game() or reread.power_data() == null:
			fails += 1; print("FAIL v%d save was not rewritten in the current shape" % old["v"])

	# --- sealed packs survive a save, and unknown ones are dropped (D80) --------
	var MP = load("res://scripts/meta_state.gd")
	var mp = MP.new()
	mp.path_prefix = SANDBOX + "packs_"
	mp.slot = 0
	mp.new_save()
	mp.add_pack(Balance.PACK_BOSS, Balance.DUNGEONS[0])
	mp.add_pack(Balance.PACK_TREASURE, Balance.DUNGEONS[1])
	mp.save_game()
	var mp2 = MP.new()
	mp2.path_prefix = SANDBOX + "packs_"
	mp2.slot = 0
	mp2.load_game()
	if mp2.packs.size() != 2:
		fails += 1; print("FAIL packs did not survive a save: %d of 2" % mp2.packs.size())
	elif String(mp2.packs[0].get("dungeon", "")) != Balance.DUNGEONS[0]:
		fails += 1; print("FAIL a pack forgot where it was found")
	# a pack naming a dungeon that no longer exists must be dropped on LOAD, never
	# in migration, so renaming content cannot corrupt a save (D15)
	mp2.packs.append({"kind": Balance.PACK_BOSS, "dungeon": "a_dungeon_that_was_renamed"})
	mp2.save_game()
	var mp3 = MP.new()
	mp3.path_prefix = SANDBOX + "packs_"
	mp3.slot = 0
	mp3.load_game()
	if mp3.packs.size() != 2:
		fails += 1
		print("FAIL a pack from renamed content was kept: %d packs" % mp3.packs.size())
	mp.writes_disabled = true

	if fails == 0:
		print("SAVE TEST: PASS (round-trip, every version migrates, backups, future refused, junk dropped)")
	else:
		print("SAVE TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

func _write(d: Dictionary) -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

## Remove this test's sandboxed files so a test run leaves no residue in the
## player's data directory.
func _cleanup_sandbox() -> void:
	# stop any surviving instance from re-writing what we are about to delete
	load("res://scripts/meta_state.gd").writes_disabled = true
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
