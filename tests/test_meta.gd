## Headless test: collection persistence + fusion + deck build.
## Run: godot --headless --script tests/test_meta.gd
extends SceneTree

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_meta_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_meta_settings.json"
	var Meta = load("res://scripts/meta_state.gd")
	var fails := 0

	var m1 = Meta.new()
	m1.new_save()
	var strike0: int = m1.owned("strike")     # depends on the starting kit
	var total0: int = m1.total_copies()
	m1.add_card("bash")
	m1.add_card("strike"); m1.add_card("strike"); m1.add_card("strike")
	if m1.owned("strike") != strike0 + 3:
		fails += 1; print("FAIL strike count %d (expect %d)" % [m1.owned("strike"), strike0 + 3])
	if m1.collection["bash"]["count"] != 1: fails += 1; print("FAIL bash count")

	# fusion is bought with gold as well as copies (see Balance.fuse_gold_cost)
	var before_fuse: int = m1.owned("strike")
	if m1.fuse("strike"):
		fails += 1; print("FAIL fused with no gold")
	var price: int = m1.fuse_gold_cost("strike")
	var copy_cost: int = m1.fuse_copy_cost("strike")
	m1.add_gold(price)
	if not m1.fuse("strike"): fails += 1; print("FAIL fuse returned false")
	if m1.gold != 0:
		fails += 1; print("FAIL fusion did not spend the gold: %d left" % m1.gold)
	if m1.owned("strike") != before_fuse - copy_cost:
		fails += 1; print("FAIL post-fuse count %d (expect %d)" % [m1.owned("strike"), before_fuse - copy_cost])
	if m1.collection["strike"]["level"] != 2: fails += 1; print("FAIL post-fuse level")
	m1.save_game()

	# reload in a fresh instance -> must match what was saved
	var m2 = Meta.new()
	if not m2.load_game(): fails += 1; print("FAIL load_game")
	if m2.owned("strike") != m1.owned("strike") or int(m2.collection["strike"]["level"]) != 2:
		fails += 1; print("FAIL persisted strike ", m2.collection["strike"])
	if m2.collection["bash"]["count"] != 1: fails += 1; print("FAIL persisted bash")

	# deck build must materialise exactly what is owned
	var deck = m2.build_run_deck()
	if deck.size() != m2.total_copies():
		fails += 1; print("FAIL deck size %d (expect %d)" % [deck.size(), m2.total_copies()])
	# expected value comes from the card model itself (scaling formula may change)
	var ref := (load("res://resources/cards/strike.tres") as CardData).duplicate()
	ref.level = 2
	var want: int = ref.eff_damage()
	ref.level = 1
	var base: int = ref.eff_damage()
	if want <= base: fails += 1; print("FAIL level 2 not stronger than level 1")
	var strike_dmg := -1
	for c in deck:
		if c.id == "strike": strike_dmg = c.eff_damage()
	if strike_dmg != want: fails += 1; print("FAIL leveled strike dmg %d (expect %d)" % [strike_dmg, want])

	# can't fuse when only 1 copy
	if m2.can_fuse("bash"): fails += 1; print("FAIL bash should not be fusable")

	if fails == 0:
		print("META TEST: PASS (persistence + fusion + deck build)")
	else:
		print("META TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

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
