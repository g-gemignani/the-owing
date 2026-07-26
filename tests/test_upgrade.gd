## Headless test: upgrade caps + sub-linear level scaling.
## Run: godot --headless --script tests/test_upgrade.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_upgrade_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_upgrade_settings.json"
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
	broke.collection = {"strike": {"count": 999, "level": 1}}
	broke.gold = 0
	if broke.can_fuse("strike"):
		fails += 1; print("FAIL fusable with 999 copies and no gold")
	broke.gold = Balance.fuse_gold_cost(0, 1)
	if not broke.can_fuse("strike"):
		fails += 1; print("FAIL exact gold is not enough to fuse")
	broke.fuse("strike")
	if broke.gold != 0:
		fails += 1; print("FAIL gold not spent: %d" % broke.gold)
	if broke.fusable_levels("strike") != 0:
		fails += 1; print("FAIL fusable_levels ignores an empty purse")

	# --- fusion stops at the cap ---
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new()
	m.collection = {"barricade": {"count": 999, "level": 1}}   # legendary, cap 5
	m.gold = 9_999_999                                          # cap test, not a price test
	var lvls := 0
	while m.can_fuse("barricade") and lvls < 500:
		m.fuse("barricade"); lvls += 1
	var cap_leg: int = m.max_level("barricade")
	if m.collection["barricade"]["level"] != cap_leg:
		fails += 1; print("FAIL legendary stopped at Lv%d (cap %d)" % [m.collection["barricade"]["level"], cap_leg])
	if m.can_fuse("barricade") or not m.at_max_level("barricade"):
		fails += 1; print("FAIL still fusable at cap")

	# common reaches 100 and no further
	var m2 = Meta.new()
	m2.collection = {"strike": {"count": 100000, "level": 1}}
	m2.gold = 999_999_999
	var n := 0
	while m2.can_fuse("strike") and n < 5000:
		m2.fuse("strike"); n += 1
	if m2.collection["strike"]["level"] != 100:
		fails += 1; print("FAIL common cap: Lv%d" % m2.collection["strike"]["level"])

	# --- scaling stays sane at max level ---
	var s := (load(CARD_DIR + "strike.tres") as CardData).duplicate()
	s.level = 1
	var base: int = s.eff_damage()
	s.level = Balance.max_level(s.rarity)
	var maxed: int = s.eff_damage()
	if maxed <= base:
		fails += 1; print("FAIL maxed strike not stronger")
	if maxed > base * 6:
		fails += 1; print("FAIL maxed strike explodes: %d vs base %d (enemy scaling cannot answer)" % [maxed, base])
	# growth must be monotonic and diminishing
	var prev := 0
	var prev_step := 999
	for L in [1, 2, 5, 10, 25, 50, Balance.max_level(s.rarity)]:
		s.level = L
		var v: int = s.eff_damage()
		if v < prev:
			fails += 1; print("FAIL damage decreased at L%d" % L)
		prev = v
	s.level = 2
	var step_early: int = s.eff_damage()
	s.level = 3
	var step2: int = s.eff_damage()
	s.level = Balance.max_level(s.rarity) - 1
	var a: int = s.eff_damage()
	s.level = Balance.max_level(s.rarity)
	var b: int = s.eff_damage()
	if (b - a) > (step2 - step_early) + 1:
		fails += 1; print("FAIL growth not diminishing")

	# status growth must stay small at max level
	var bash := (load(CARD_DIR + "bash.tres") as CardData).duplicate()
	# level to the card's OWN cap: rarity determines the track length
	bash.level = Balance.max_level(bash.rarity)
	if bash.eff_vulnerable() > 8:
		fails += 1; print("FAIL vulnerable stacks explode at max: %d" % bash.eff_vulnerable())

	# maxed decks must stay inside the ratio cap headroom
	var deck: Array[CardData] = []
	for i in 10:
		var c := (load(CARD_DIR + "strike.tres") as CardData).duplicate()
		c.level = Balance.max_level(c.rarity)
		deck.append(c)
	var ratio := Balance.power_ratio(deck)
	if ratio >= Balance.POWER_RATIO_CAP:
		print("WARN maxed deck pins the ratio cap (%.2f >= %.2f): enemies stop scaling" % [ratio, Balance.POWER_RATIO_CAP])

	# --- fusion has to state what it BUYS, not only what it costs ---
	#
	# The Collection quoted "+1 (-4x, -180g)" and nothing else. Since D35 fusion
	# spends gold as well, that is an economic decision against the shop with the
	# benefit side missing. `level_up_text` generates the gain from the same getters
	# the engine resolves with, so the preview cannot promise what the card will not
	# deliver.
	for pid in ["strike", "defend", "bash"]:
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
		print("UPGRADE TEST: PASS (caps by rarity, fusion stops at cap, sub-linear growth, gain previewed)")
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
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
