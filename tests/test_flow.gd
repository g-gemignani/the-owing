## Headless test: menu/flow integrity and settings persistence.
##
## With this many screens the likely failure is a typo'd scene path — which only
## shows up when a player clicks that one button. So this scans every script for
## `res://scenes/...` references and asserts each target actually exists, rather
## than trusting the navigation by inspection.
## Run: godot --headless --script tests/test_flow.gd
extends SceneTree

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_flow_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_flow_settings.json"
	var fails := 0

	# --- every referenced scene exists ---
	var refs := {}
	for path in _all_scripts():
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var re := RegEx.new()
		re.compile('res://scenes/[A-Za-z0-9_]+\\.tscn')
		for m in re.search_all(text):
			refs[m.get_string()] = refs.get(m.get_string(), [])
			var arr: Array = refs[m.get_string()]
			if not path in arr:
				arr.append(path)
			refs[m.get_string()] = arr
	if refs.is_empty():
		fails += 1; print("FAIL scanned no scene references at all")
	for scene in refs:
		if not ResourceLoader.exists(scene):
			fails += 1; print("FAIL missing scene %s (referenced by %s)" % [scene, refs[scene]])
	print("  (info: %d distinct scene targets referenced)" % refs.size())

	# --- every scene on disk is reachable from some script ---
	var on_disk := _all_scenes()
	for scene in on_disk:
		if not refs.has(scene) and not scene.ends_with("MainMenu.tscn"):
			print("  WARN %s is never navigated to" % scene)

	# --- settings round-trip and clamping ---
	var S = load("res://scripts/settings_state.gd").new()
	S.ui_scale = 99.0          # out of range
	S.master_volume = 500
	S.fullscreen = false
	S.show_numbers = false
	S.save_settings()
	var S2 = load("res://scripts/settings_state.gd").new()
	S2.load_settings()
	if S2.ui_scale > 3.0 or S2.ui_scale < 0.6:
		fails += 1; print("FAIL ui_scale not clamped on load: %.2f" % S2.ui_scale)
	if S2.master_volume > 100:
		fails += 1; print("FAIL volume not clamped on load: %d" % S2.master_volume)
	if S2.fullscreen != false or S2.show_numbers != false:
		fails += 1; print("FAIL settings booleans not persisted")

	# --- save slots are independent ---
	var Meta = load("res://scripts/meta_state.gd")
	for i in Meta.SLOT_COUNT:
		Meta.delete_slot(i)
	var a = Meta.new(); a.slot = 0; a.new_save(); a.add_gold(111); a.save_game()
	var b = Meta.new(); b.slot = 1; b.new_save(); b.add_gold(222); b.save_game()
	var s0: Dictionary = Meta.slot_summary(0)
	var s1: Dictionary = Meta.slot_summary(1)
	var s2: Dictionary = Meta.slot_summary(2)
	if int(s0.get("gold", -1)) != 111 or int(s1.get("gold", -1)) != 222:
		fails += 1; print("FAIL slots not independent: %s / %s" % [s0, s1])
	if bool(s2.get("exists", true)):
		fails += 1; print("FAIL empty slot reported as existing")
	# summaries must not disturb loaded state
	var c = Meta.new(); c.slot = 1; c.load_game()
	Meta.slot_summary(0)
	if c.gold != 222:
		fails += 1; print("FAIL slot_summary mutated loaded state")
	# deleting one slot must leave the other
	Meta.delete_slot(0)
	var after: Dictionary = Meta.slot_summary(0)
	if bool(after.get("exists", true)):
		fails += 1; print("FAIL slot 0 not deleted")
	var other: Dictionary = Meta.slot_summary(1)
	if not bool(other.get("exists", false)):
		fails += 1; print("FAIL deleting slot 0 removed slot 1")

	# --- a new game must be immediately playable ---
	var n = Meta.new(); n.slot = 2; n.new_save()
	var sel := {}
	for id in n.collection:
		sel[id] = n.collection[id]["count"]
	if not n.deck_valid(sel):
		fails += 1; print("FAIL fresh game cannot field a legal deck")
	var first := Balance.dungeon(Balance.DUNGEONS[0])
	if not n.dungeon_unlocked(first):
		fails += 1; print("FAIL fresh game has no unlocked dungeon")
	var z0: ZoneData = Balance.all_zones()[0]
	if z0.unlock_after_clears > 0:
		fails += 1; print("FAIL first zone is not open on a fresh game")

	for i in Meta.SLOT_COUNT:
		Meta.delete_slot(i)

	if fails == 0:
		print("FLOW TEST: PASS (scene refs resolve, settings clamp+persist, slots independent)")
	else:
		print("FLOW TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

func _all_scripts() -> Array:
	var out: Array = []
	for dir in ["res://scripts", "res://"]:
		var d := DirAccess.open(dir)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if f.ends_with(".gd"):
				out.append(dir.path_join(f) if dir != "res://" else "res://" + f)
			f = d.get_next()
		d.list_dir_end()
	return out

func _all_scenes() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://scenes")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tscn"):
			out.append("res://scenes/" + f)
		f = d.get_next()
	d.list_dir_end()
	return out

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
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
