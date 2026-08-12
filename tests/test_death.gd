## Headless test: what dying costs (D235).
##
## It used to assert the death PENALTY — a fraction of banked gold and a count of cards deleted
## from the collection, plus the floors and last-attack guards those needed. That penalty is gone:
## death costs what you chose to risk and never what you already owned (D231). So this suite now
## asserts the opposite of what it used to, which is the point — the strongest statement about a
## deleted mechanic is a test that fails if it comes back.
##
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

	# --- dying takes NOTHING from the collection ---
	var m = Meta.new()
	m.new_save()
	m.add_gold(100)
	for i in 3: m.add_card("stave_in")
	for i in 3: m.add_card("shoulder")
	for i in 3: m.add_card("clear_mind")
	var before: int = m.total_copies()
	var gold_before: int = m.gold
	if before < Balance.MIN_KEEP + 6:
		fails += 1; print("FAIL setup total too small for the test: ", before)

	# The mechanism is gone rather than set to zero, so this is a check that nothing has been
	# reintroduced under another name. `has_method` and not a call: calling a method that should
	# not exist is a crash, and a crash is a worse failure report than a sentence.
	if m.has_method("penalize_death"):
		fails += 1
		print("FAIL MetaState.penalize_death is back — death must not touch the collection (D235)")
	# `Balance` is a class with static members, so `has_method` on it is a parse error rather than
	# a question. Read the SOURCE instead, which is what `test_relic.gd` already does to ask
	# whether the engine consumes a field.
	var bal := FileAccess.open("res://scripts/balance.gd", FileAccess.READ)
	if bal != null:
		var src := bal.get_as_text()
		bal.close()
		for fn in ["func gold_loss_fraction", "func cards_lost_on_death"]:
			if src.find(fn) != -1:
				fails += 1
				print("FAIL balance.gd declares %s — the collection penalty was deleted (D235)" % fn)

	# --- a lost run pays by DEPTH, and pays nothing from the collection ---
	#
	# `forfeit_escrow` is the only thing a death now calls. Driven directly, because the run loop
	# that would otherwise reach it needs a whole dungeon and this is arithmetic.
	var GS = load("res://scripts/game_state.gd")
	var g = GS.new()
	g.escrow_gold = 100
	g.escrow_cards = ["hack", "hack", "cover", "cover"]
	# Depth 0.0: the first floor salvages nothing, so everything carried is lost.
	var shallow: Dictionary = g.forfeit_escrow(0.0)
	if int(shallow["kept_gold"]) != 0 or int(shallow["kept_cards"]) != 0:
		fails += 1; print("FAIL a first-floor death salvaged something: ", shallow)
	if int(shallow["gold"]) != 100 or int(shallow["cards"]) != 4:
		fails += 1; print("FAIL a first-floor death did not report the whole loss: ", shallow)

	# The bottom salvages `ESCROW_SALVAGE_AT_BOTTOM`, derived rather than restated as 50: the
	# constant is the one owner and a number typed here would go stale the first time it moves.
	var g2 = GS.new()
	g2.escrow_gold = 100
	g2.escrow_cards = ["hack", "hack", "cover", "cover"]
	var deep: Dictionary = g2.forfeit_escrow(1.0)
	var want_gold: int = int(floor(100.0 * Balance.ESCROW_SALVAGE_AT_BOTTOM))
	var want_cards: int = int(floor(4.0 * Balance.ESCROW_SALVAGE_AT_BOTTOM))
	if int(deep["kept_gold"]) != want_gold:
		fails += 1; print("FAIL bottom-floor gold salvage %d, expected %d" % [
			int(deep["kept_gold"]), want_gold])
	if int(deep["kept_cards"]) != want_cards:
		fails += 1; print("FAIL bottom-floor card salvage %d, expected %d" % [
			int(deep["kept_cards"]), want_cards])
	# Kept plus lost is everything, at every depth. The two halves are reported separately and a
	# screen states both, so a drift between them would show up as a defeat screen that does not
	# add up — which nothing else in the suite could see.
	if int(deep["kept_gold"]) + int(deep["gold"]) != 100:
		fails += 1; print("FAIL gold does not add up: ", deep)
	if int(deep["kept_cards"]) + int(deep["cards"]) != 4:
		fails += 1; print("FAIL cards do not add up: ", deep)

	# ...and deeper always pays at least as much as shallower. Asserted over the curve rather than
	# at its ends, because a non-monotonic salvage would make "get further" the wrong advice at
	# some depth and no single pair of readings could show it.
	var last := -1
	for step in 11:
		var gg = GS.new()
		gg.escrow_gold = 1000
		var res: Dictionary = gg.forfeit_escrow(float(step) / 10.0)
		var kept: int = int(res["kept_gold"])
		if kept < last:
			fails += 1
			print("FAIL salvage fell as depth rose: %d at %.1f after %d" % [
				kept, float(step) / 10.0, last])
		last = kept

	# The collection and the purse are untouched by all of the above: `forfeit_escrow` banks INTO
	# meta and never out of it.
	if m.total_copies() != before:
		fails += 1; print("FAIL collection changed: %d -> %d" % [before, m.total_copies()])
	if m.gold != gold_before:
		fails += 1; print("FAIL banked gold changed: %d -> %d" % [gold_before, m.gold])

	# --- a lost run banks the DISCOVERY even when it banks nothing else ---
	var m4 = Meta.new()
	m4.new_save()
	if not m4.note_relic_seen("iron_heart"):
		fails += 1; print("FAIL a first sighting was not logged")
	if m4.note_relic_seen("iron_heart"):
		fails += 1; print("FAIL a second sighting counted as new")
	if not m4.seen_relic("iron_heart"):
		fails += 1; print("FAIL seen_relic does not report what note_relic_seen logged")
	if m4.has_relic("iron_heart"):
		fails += 1; print("FAIL meeting a relic granted it — the log must carry no power")
	m4.save_game()
	var m5 = Meta.new()
	m5.load_game()
	if not m5.seen_relic("iron_heart"):
		fails += 1; print("FAIL the discovery log did not persist")

	# --- persistence of gold ---
	m.add_gold(7)
	m.save_game()
	var m3 = Meta.new()
	m3.load_game()
	if m3.gold != m.gold: fails += 1; print("FAIL gold not persisted ", m3.gold, " vs ", m.gold)

	if fails == 0:
		print("DEATH TEST: PASS (no collection penalty, depth salvage, monotonic curve, discovery log)")
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
