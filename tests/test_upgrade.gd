## Headless test: upgrade caps, fusion pricing, and what a level actually buys.
##
## The promise that every level moves a number is swept across the whole catalogue
## by tests/test_levels.gd; this suite covers the caps and the economy around it.
## Run: godot --headless --script tests/test_upgrade.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_upgrade_"

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0

	# --- caps derived from rarity, common = 100 ---
	var expect := {0: 100, 1: 40, 2: 15, 3: 5, 4: 5}
	for r in expect:
		var got: int = Balance.max_level(r)
		if got != int(expect[r]):
			fails += 1; print("FAIL cap rarity %d: %d (expect %d)" % [r, got, expect[r]])
	# rarer must never allow a longer track than commoner
	for r in range(1, 5):
		if Balance.max_level(r) > Balance.max_level(r - 1):
			fails += 1; print("FAIL cap not monotonic at rarity %d" % r)
	# every rarity stays upgradeable
	for r in range(0, 5):
		if Balance.max_level(r) < Balance.MIN_MAX_LEVEL:
			fails += 1; print("FAIL cap below floor at rarity %d" % r)

	# --- fusion cost model: both prices must RISE with level ---
	#
	# A flat price made power grow linearly with copies hoarded, and nothing else
	# gated it, so a player who banked commons outran the difficulty curve.
	if Balance.copies_to_reach(1) != 1:
		fails += 1; print("FAIL copies_to_reach(1): %d" % Balance.copies_to_reach(1))
	for lv in [1, 5, 20, 60]:
		if Balance.fuse_copy_cost(lv + 20) <= Balance.fuse_copy_cost(lv):
			fails += 1; print("FAIL copy cost flat across 20 levels from %d" % lv)
		if Balance.fuse_gold_cost(0, lv + 1) <= Balance.fuse_gold_cost(0, lv):
			fails += 1; print("FAIL gold cost not rising at level %d" % lv)
	# the climb must be superlinear, or the rise is cosmetic
	var half: int = Balance.copies_to_reach(50)
	var full: int = Balance.copies_to_reach(100)
	if full <= half * 2:
		fails += 1; print("FAIL copy curve is linear: 50 costs %d, 100 costs %d" % [half, full])
	if Balance.gold_to_reach(0, 100) <= Balance.gold_to_reach(0, 50) * 2:
		fails += 1; print("FAIL gold curve is linear")
	# rarer cards cost more gold per level, like they cost more in the shop
	for r in range(1, 5):
		if Balance.fuse_gold_cost(r, 1) <= Balance.fuse_gold_cost(r - 1, 1):
			fails += 1; print("FAIL rarity %d not pricier to fuse than %d" % [r, r - 1])

	# --- gold actually gates fusion ---
	var broke = load("res://scripts/meta_state.gd").new()
	broke.collection = {"hack": {"count": 999, "level": 1}}
	broke.gold = 0
	if broke.can_fuse("hack"):
		fails += 1; print("FAIL fusable with 999 copies and no gold")
	broke.gold = Balance.fuse_gold_cost(0, 1)
	if not broke.can_fuse("hack"):
		fails += 1; print("FAIL exact gold is not enough to fuse")
	broke.fuse("hack")
	if broke.gold != 0:
		fails += 1; print("FAIL gold not spent: %d" % broke.gold)
	if broke.fusable_levels("hack") != 0:
		fails += 1; print("FAIL fusable_levels ignores an empty purse")

	# --- fusion stops at the cap ---
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new()
	m.collection = {"set_stone": {"count": 999, "level": 1}}   # legendary, cap 5
	m.gold = 9_999_999                                          # cap test, not a price test
	var lvls := 0
	while m.can_fuse("set_stone") and lvls < 500:
		m.fuse("set_stone"); lvls += 1
	var cap_leg: int = m.max_level("set_stone")
	if m.collection["set_stone"]["level"] != cap_leg:
		fails += 1; print("FAIL legendary stopped at Lv%d (cap %d)" % [m.collection["set_stone"]["level"], cap_leg])
	if m.can_fuse("set_stone") or not m.at_max_level("set_stone"):
		fails += 1; print("FAIL still fusable at cap")

	# common reaches 100 and no further
	var m2 = Meta.new()
	m2.collection = {"hack": {"count": 100000, "level": 1}}
	m2.gold = 999_999_999
	var n := 0
	while m2.can_fuse("hack") and n < 5000:
		m2.fuse("hack"); n += 1
	if m2.collection["hack"]["level"] != 100:
		fails += 1; print("FAIL common cap: Lv%d" % m2.collection["hack"]["level"])

	# --- EVERY level must move the number (D109) ---
	#
	# This replaces a guard that a maxed card stays under 6x its base. That number
	# encoded the old sub-linear curve, and the curve was the bug: `base + round(base
	# * rate * sqrt(level - 1))` handed to integer rounding ate every step smaller
	# than half a point, so 84 of a common's 99 level-ups landed on the number below
	# and the player paid copies and gold for nothing at all.
	#
	# The ceiling a maxed card is allowed to reach is not this suite's business any
	# more — it belongs to the ratchet, which prices it (see MAX_ACHIEVABLE_RATIO and
	# tests/test_balance.gd). What belongs here is the promise fusion makes.
	var s := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
	var cap_s: int = s.level_cap()
	var prev := 0
	for L in range(1, cap_s + 1):
		s.level = L
		var v: int = s.eff_damage()
		if L > 1 and v <= prev:
			fails += 1
			print("FAIL Lv%d buys nothing: damage stays %d" % [L, v])
			break
		prev = v
	# ...and early levels must still be the better buy, or the whole track is flat
	s.level = 1
	var first_step: int = s.eff_damage()
	s.level = 2
	first_step = s.eff_damage() - first_step
	s.level = cap_s - 1
	var last_step: int = s.eff_damage()
	s.level = cap_s
	last_step = s.eff_damage() - last_step
	if last_step > first_step:
		fails += 1
		print("FAIL growth is back-loaded: first level buys +%d, last buys +%d" % [
			first_step, last_step])

	# status growth must stay small at max level
	var stave_in := (load(CARD_DIR + "stave_in.tres") as CardData).duplicate()
	# level to the card's OWN cap: rarity determines the track length
	stave_in.level = Balance.max_level(stave_in.rarity)
	if stave_in.eff_vulnerable() > 8:
		fails += 1; print("FAIL vulnerable stacks explode at max: %d" % stave_in.eff_vulnerable())

	# --- MAX_ACHIEVABLE_RATIO has to keep being measured, not remembered ---
	#
	# It is the number the whole ratchet is hung from: the deepest dungeon's ceiling
	# is set to clear it, and if a maxed deck quietly climbs past it the endgame
	# stops resisting and nothing says so. Levelling is exactly the thing that moves
	# it, so this suite is where it gets checked.
	var deck: Array[CardData] = []
	for i in 10:
		var c := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		c.level = c.level_cap()
		deck.append(c)
	var ratio := Balance.power_ratio(deck)
	if ratio > Balance.MAX_ACHIEVABLE_RATIO:
		fails += 1
		print("FAIL a maxed common deck reaches %.2f, past the measured ceiling %.2f — re-measure it and move the dungeon ceilings with it" % [
			ratio, Balance.MAX_ACHIEVABLE_RATIO])

	# --- fusion has to state what it BUYS, not only what it costs ---
	#
	# The Collection quoted "+1 (-4x, -180g)" and nothing else. Since D35 fusion
	# spends gold as well, that is an economic decision against the shop with the
	# benefit side missing. `level_up_text` generates the gain from the same getters
	# the engine resolves with, so the preview cannot promise what the card will not
	# deliver.
	for pid in ["hack", "cover", "stave_in"]:
		var pc := (load("res://resources/cards/%s.tres" % pid) as CardData).duplicate() as CardData
		pc.level = 1
		var cap2: int = Balance.max_level(pc.rarity)
		var says := pc.level_up_text(2)
		if pc.eff_damage() > 0 or pc.eff_block() > 0:
			if says.strip_edges() == "":
				fails += 1
				print("FAIL %s does not say what its next level buys" % pid)
			# the numbers quoted must be the real before and after
			var after := pc.duplicate() as CardData
			after.level = 2
			for pair2 in [[pc.eff_damage(), after.eff_damage()],
					[pc.eff_block(), after.eff_block()]]:
				if int(pair2[1]) > int(pair2[0]) and says.find("%d\u2192%d" % [pair2[0], pair2[1]]) == -1:
					fails += 1
					print("FAIL %s preview '%s' omits %d->%d" % [pid, says, pair2[0], pair2[1]])
		# at the cap there is no next level, and it must not invent one
		pc.level = cap2
		if pc.level_up_text(cap2) != "":
			fails += 1; print("FAIL %s previews a gain at its cap" % pid)

	# ...and the screen must actually use it, or the preview exists only in a test
	var coll := FileAccess.open("res://scripts/collection.gd", FileAccess.READ)
	if coll != null:
		var src2 := coll.get_as_text()
		coll.close()
		if src2.find("level_up_text") == -1:
			fails += 1
			print("FAIL the collection screen never shows what a level buys")

	if fails == 0:
		print("UPGRADE TEST: PASS (caps by rarity, fusion stops at cap, every level lands, gain previewed)")
	else:
		print("UPGRADE TEST: FAIL (%d)" % fails)
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
