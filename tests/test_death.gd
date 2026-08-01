## Headless test: death penalty (gold loss + card loss, floors, last-attack guard).
## Run: godot --headless --script tests/test_death.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_death_"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var Meta = load("res://scripts/meta_state.gd")
	var fails := 0

	# --- gold + card loss scaling ---
	var m = Meta.new()
	m.new_save()                       # strike4, defend4, gold0
	m.add_gold(100)
	for i in 3: m.add_card("stave_in")
	for i in 3: m.add_card("shoulder")
	for i in 3: m.add_card("clear_mind")
	# starting contents depend on the chosen kit, so derive rather than assert a number
	var before: int = m.total_copies()
	if before < Balance.MIN_KEEP + 6:
		fails += 1; print("FAIL setup total too small for the test: ", before)

	# card loss is derived from Balance (retuned when run-escrow landed), so this
	# expectation follows the rule instead of hardcoding a number
	var expect_cards: int = Balance.cards_lost_on_death(3)
	var pen = m.penalize_death(3)      # frac 0.45 -> lose 45 gold
	if pen["gold_lost"] != 45: fails += 1; print("FAIL gold_lost ", pen["gold_lost"])
	if m.gold != 55: fails += 1; print("FAIL gold remaining ", m.gold)
	if pen["cards_lost"].size() != expect_cards:
		fails += 1; print("FAIL cards_lost %d (expect %d)" % [pen["cards_lost"].size(), expect_cards])
	if m.total_copies() != before - expect_cards:
		fails += 1; print("FAIL total after ", m.total_copies())

	# --- floor: repeated deaths never drop below MIN_KEEP ---
	for i in 20:
		m.penalize_death(5)
	if m.total_copies() < m.MIN_KEEP: fails += 1; print("FAIL floor breached ", m.total_copies())

	# --- last-attack guard: strike is the only attack, must survive ---
	var m2 = Meta.new()
	m2.collection = {"hack": {"count": 1, "level": 1}, "cover": {"count": 10, "level": 1}}
	m2.gold = 0
	for i in 30:
		m2.penalize_death(4)
	if not m2.collection.has("hack"): fails += 1; print("FAIL last attack was stripped")
	if m2.total_copies() < m2.MIN_KEEP: fails += 1; print("FAIL floor breached (m2) ", m2.total_copies())

	# --- persistence of gold ---
	m.add_gold(7)
	m.save_game()
	var m3 = Meta.new()
	m3.load_game()
	if m3.gold != m.gold: fails += 1; print("FAIL gold not persisted ", m3.gold, " vs ", m.gold)

	if fails == 0:
		print("DEATH TEST: PASS (gold + card penalty, floors, last-attack guard, persistence)")
	else:
		print("DEATH TEST: FAIL (%d)" % fails)
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
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
