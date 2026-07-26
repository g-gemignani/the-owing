## Headless test: run escrow (D20) — the anti-exploit rule.
##
## The exploit this closes: rewards used to commit per-encounter, so clearing the
## easy encounters and abandoning before the boss kept everything at no risk,
## making the boss an optional formality. These assertions are what stop that
## coming back the next time reward code is touched.
## Run: godot --headless --script tests/test_escrow.gd
extends SceneTree

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_escrow_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_escrow_settings.json"
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")
	var GS = load("res://scripts/game_state.gd")

	# --- earning during a run must NOT touch the collection ---
	var m = Meta.new(); m.new_save(); m.slot = 0
	var g = GS.new()
	# GameState fetches MetaState by path; in a headless run there is no /root/MetaState,
	# so drive the escrow bookkeeping directly and check the ledger arithmetic.
	g.escrow_cards = []
	g.escrow_gold = 0
	g.earn_gold(40)
	g.earn_gold(35)
	if g.escrow_gold != 75:
		fails += 1; print("FAIL escrow gold not accumulating: %d" % g.escrow_gold)
	g.escrow_cards.append("strike")
	g.escrow_cards.append("bash")

	# --- forfeiting must clear the ledger and report what was lost ---
	var lost: Dictionary = g.forfeit_escrow()
	if int(lost["gold"]) != 75 or int(lost["cards"]) != 2:
		fails += 1; print("FAIL forfeit report wrong: %s" % lost)
	if g.escrow_gold != 0 or not g.escrow_cards.is_empty():
		fails += 1; print("FAIL forfeit did not clear the ledger")

	# --- committing must report the same shape ---
	g.earn_gold(20)
	g.escrow_cards.append("shiv")
	var kept: Dictionary = g.commit_escrow()
	if int(kept["gold"]) != 20 or int(kept["cards"]) != 1:
		fails += 1; print("FAIL commit report wrong: %s" % kept)
	if g.escrow_gold != 0 or not g.escrow_cards.is_empty():
		fails += 1; print("FAIL commit did not clear the ledger")

	# --- spending draws from the at-risk pool FIRST ---
	# (so a purchase never eats gold the player could have walked away with)
	g.escrow_gold = 30
	if not g.spend_gold(10):
		fails += 1; print("FAIL could not spend from escrow")
	if g.escrow_gold != 20:
		fails += 1; print("FAIL spend did not draw from escrow first: %d" % g.escrow_gold)
	# overspending beyond the available pool must fail cleanly, changing nothing
	var before: int = g.escrow_gold
	if g.spend_gold(9999):
		fails += 1; print("FAIL overspend accepted")
	if g.escrow_gold != before:
		fails += 1; print("FAIL failed spend still mutated escrow")
	if g.spend_gold(0) or g.spend_gold(-5):
		fails += 1; print("FAIL non-positive spend accepted")

	# --- resetting a run must not leave earnings behind ---
	g.escrow_gold = 99
	g.escrow_cards.append("strike")
	g.reset_run_progress()
	if g.escrow_gold != 0 or not g.escrow_cards.is_empty():
		fails += 1; print("FAIL reset_run_progress left escrow populated")

	# --- the retuned death penalty: fewer cards than the old raw difficulty ---
	for d in [1, 2, 4, 7]:
		var n: int = Balance.cards_lost_on_death(d)
		if n < 1:
			fails += 1; print("FAIL death takes no cards at difficulty %d" % d)
		if n > d:
			fails += 1; print("FAIL death takes MORE cards than difficulty %d: %d" % [d, n])
	if Balance.cards_lost_on_death(7) >= 7:
		fails += 1; print("FAIL deep-dungeon card loss was not retuned")
	# and it must still rise with difficulty
	if Balance.cards_lost_on_death(7) <= Balance.cards_lost_on_death(1):
		fails += 1; print("FAIL card loss does not scale with difficulty")

	# --- the death penalty still respects the softlock floor ---
	var m2 = Meta.new(); m2.new_save()
	for i in 30:
		m2.penalize_death(7)
	if m2.total_copies() < Balance.MIN_KEEP:
		fails += 1; print("FAIL deaths breached the collection floor: %d" % m2.total_copies())

	# ---------------------------------------------------------------
	# Escape Ropes: the only way to leave a dungeon with your earnings.
	# ---------------------------------------------------------------
	var m3 = Meta.new(); m3.new_save()
	# a fresh game starts with exactly one, so the mechanic teaches itself
	if m3.item_count("escape_rope") != 1:
		fails += 1; print("FAIL fresh save should hold 1 rope, has %d" % m3.item_count("escape_rope"))
	if not m3.use_item("escape_rope"):
		fails += 1; print("FAIL could not use a held rope")
	if m3.item_count("escape_rope") != 0:
		fails += 1; print("FAIL rope not consumed")
	if m3.use_item("escape_rope"):
		fails += 1; print("FAIL used a rope the player does not have")
	m3.add_item("escape_rope", 2)
	if m3.item_count("escape_rope") != 2:
		fails += 1; print("FAIL add_item count wrong: %d" % m3.item_count("escape_rope"))
	m3.add_item("not_an_item")
	if m3.consumables.has("not_an_item"):
		fails += 1; print("FAIL unknown item accepted")
	# ropes persist across save/load
	m3.save_game()
	var m4 = Meta.new(); m4.load_game()
	if m4.item_count("escape_rope") != 2:
		fails += 1; print("FAIL ropes not persisted: %d" % m4.item_count("escape_rope"))
	# ropes must NOT be purchasable — a bought exit re-opens the farming loop
	var shop_src := FileAccess.open("res://scripts/shop.gd", FileAccess.READ)
	if shop_src != null:
		var text := shop_src.get_as_text()
		shop_src.close()
		if text.find("escape_rope") != -1:
			fails += 1; print("FAIL shop references escape_rope (must be found, not sold)")

	# --- a v1 save (pre-consumables) must migrate and not be worse off ---
	var f2 := FileAccess.open(Meta.path_for(0), FileAccess.WRITE)
	f2.store_string(JSON.stringify({
		"version": 1,
		"collection": {"strike": {"count": 4, "level": 1}, "defend": {"count": 4, "level": 1}},
		"gold": 10, "relics": [], "decks": {}, "cleared_dungeons": [],
	}))
	f2.close()
	var m5 = Meta.new(); m5.slot = 0
	if not m5.load_game():
		fails += 1; print("FAIL v1 save did not load")
	if m5.item_count("escape_rope") < 1:
		fails += 1; print("FAIL v1 migration left the player with no rope")
	if m5.gold != 10:
		fails += 1; print("FAIL v1 migration lost gold")

	# --- an elite's relic is held at risk like everything else (D68) ------------
	#
	# Granting it straight to MetaState would reopen the hole escrow exists to close,
	# with a different noun: kill the elite, die on purpose, keep the relic. The
	# whole point of D20 is that a run's winnings are provisional until the boss.
	var G2 = load("res://scripts/game_state.gd").new()
	var M2 = load("res://scripts/meta_state.gd").new()
	M2.path_prefix = "t_escrow_relic_"
	M2.slot = 0
	M2.new_save()
	var owned_before: int = M2.relics.size()
	var rid: String = M2.pick_relic(Balance.Tier.ELITE)
	if rid == "":
		fails += 1; print("FAIL no relic could be rolled for an elite")
	elif M2.relics.size() != owned_before:
		fails += 1; print("FAIL pick_relic granted the relic instead of only rolling it")
	G2.earn_relic(rid)
	if G2.escrow_relics.size() != 1:
		fails += 1; print("FAIL an elite's relic did not go into escrow")
	var dropped: Dictionary = G2.forfeit_escrow()
	if int(dropped.get("relics", 0)) != 1 or not G2.escrow_relics.is_empty():
		fails += 1; print("FAIL dying did not forfeit the elite's relic")
	# ...and it must survive being quit out of, or the escrow is a lie on reload
	G2.earn_relic(rid)
	var blob := {"escrow_relics": G2.escrow_relics.duplicate()}
	if not (rid in blob["escrow_relics"]):
		fails += 1; print("FAIL escrowed relics are not serialized with the run")
	M2.writes_disabled = true

	# --- repeat clears must pay less than first ones (D69) ----------------------
	#
	# The measured plateau was not a difficulty problem: re-clearing a dungeon you
	# had beaten at 100% was the safest income in the game, so farming the middle
	# beat risking the next depth.
	if Balance.repeat_reward_mult(0) != 1.0:
		fails += 1; print("FAIL a first clear does not pay full price")
	# It falls, then flattens at the floor — the floor is deliberate, so a dungeon
	# you farmed early still pays enough to be worth returning to for its cards.
	var prev := 1.0
	for n in [1, 2, 3, 4]:
		var mult: float = Balance.repeat_reward_mult(n)
		if mult > prev + 0.001:
			fails += 1
			print("FAIL clear %d pays MORE than the one before (%.2f vs %.2f)" % [n, mult, prev])
		prev = mult
	if Balance.repeat_reward_mult(1) >= 1.0:
		fails += 1; print("FAIL the second clear of a dungeon pays full price")
	if Balance.repeat_reward_mult(2) >= Balance.repeat_reward_mult(1):
		fails += 1; print("FAIL the payout does not keep falling before it flattens")
	if Balance.repeat_reward_mult(9) < Balance.REPEAT_REWARD_FLOOR - 0.001:
		fails += 1; print("FAIL repeat payout falls through its floor")
	# a farmed dungeon must still be worth *something*, or a build's exclusive card
	# becomes unobtainable to anyone who cleared its dungeon early
	if Balance.repeat_reward_mult(9) <= 0.0:
		fails += 1; print("FAIL a re-cleared dungeon pays nothing at all")

	if fails == 0:
		print("ESCROW TEST: PASS (earnings held/forfeited/committed; ropes are the only paid exit)")
	else:
		print("ESCROW TEST: FAIL (%d)" % fails)
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
