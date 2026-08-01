## Headless test: shop pricing, gold spending, node generation.
## Run: godot --headless --script tests/test_shop.gd
extends SceneTree

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_shop_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_shop_settings.json"
	var fails := 0

	# --- prices rise with rarity, derived from drop weight ---
	var prev := 0
	for r in range(0, 5):
		var p: int = Balance.card_price(r)
		if p <= 0:
			fails += 1; print("FAIL non-positive price at rarity %d" % r)
		if p < prev:
			fails += 1; print("FAIL price not rising at rarity %d (%d < %d)" % [r, p, prev])
		prev = p
	# A legendary must cost more than a common but stay within a few runs of income.
	#
	# Measured at MID depth, not the first dungeon. Gold now climbs superlinearly
	# with depth (see Balance.GOLD_DEPTH_EXP) so that farming an outgrown floor is
	# not optimal — which makes the shallowest dungeon the poorest by design. Pricing
	# the rarest card against the poorest floor would call every legendary
	# unobtainable, when the player buying one is several zones deeper.
	var deepest := 1
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null:
			deepest = maxi(deepest, dd.difficulty)
	var mid: int = maxi(1, deepest / 2)
	var per_run := Balance.gold_reward(mid, Balance.Tier.NORMAL, 2) * 3 \
		+ Balance.gold_reward(mid, Balance.Tier.ELITE, 2) \
		+ Balance.gold_reward(mid, Balance.Tier.BOSS, 2)
	var legendary: int = Balance.card_price(4)
	if legendary <= Balance.card_price(0):
		fails += 1; print("FAIL legendary not pricier than common")
	if legendary > per_run * 6:
		fails += 1; print("FAIL legendary unaffordable: %dg vs %dg/run at d%d" % [
			legendary, per_run, mid])
	# and it must not be pocket change at the depth it appears
	if legendary < per_run:
		fails += 1; print("FAIL legendary costs less than one d%d run" % mid)

	# --- healing priced against what it restores ---
	var heal: int = Balance.heal_amount(100)
	var hprice: int = Balance.heal_price(100)
	if heal <= 0 or hprice <= 0:
		fails += 1; print("FAIL bad heal numbers")
	if heal >= 100:
		fails += 1; print("FAIL heal is a full restore")

	# --- gold spending guards ---
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new()
	m.new_save()
	m.gold = 0
	if m.spend_gold(10):
		fails += 1; print("FAIL spent gold while broke")
	m.add_gold(100)
	if not m.spend_gold(40):
		fails += 1; print("FAIL could not spend affordable amount")
	if m.gold != 60:
		fails += 1; print("FAIL gold after spend: %d (expect 60)" % m.gold)
	if m.spend_gold(0) or m.spend_gold(-5):
		fails += 1; print("FAIL non-positive spend accepted")
	if m.spend_gold(61):
		fails += 1; print("FAIL overspend accepted")
	if m.gold != 60:
		fails += 1; print("FAIL gold mutated by failed spends: %d" % m.gold)

	# gold survives a save/load round trip
	m.save_game()
	var m2 = Meta.new()
	m2.load_game()
	if m2.gold != 60:
		fails += 1; print("FAIL gold not persisted: %d" % m2.gold)

	# --- shop nodes actually appear on generated floors ---
	#
	# This used to generate graph maps and count nodes per row. The graph went with its
	# model in D94, so it counts what the crawl lays on its tiles instead — the property
	# is the same one either way: a gold sink the player cannot reach is not a sink.
	var shops := 0
	var rests := 0
	var trials := 0
	for did in Balance.DUNGEONS:
		for t in 20:
			var iso := TraversalIso.new()
			iso.generate(Balance.dungeon(did))
			trials += 1
			# Every floor, not just the one being stood on: the dungeon's whole budget is
			# dealt across the floors up front, and a shop dealt to floor three still has
			# to exist. `plan` holds what the floors below are still owed.
			var laid: Array = []
			for e in iso.enc:
				laid.append(int(e))
			for pf in iso.plan:
				for e in pf:
					laid.append(int(e))
			for e in laid:
				if e == Traversal.Enc.SHOP:
					shops += 1
				elif e == Traversal.Enc.REST:
					rests += 1
	if shops == 0:
		fails += 1; print("FAIL no shop nodes generated in %d floors" % trials)
	# The boss is the last thing in a dungeon, so it must never be laid on a floor the
	# player can reach before the deepest one — a boss on floor one is the whole run.
	for did in Balance.DUNGEONS:
		for t in 20:
			var iso2 := TraversalIso.new()
			iso2.generate(Balance.dungeon(did))
			if iso2.floors <= 1:
				continue
			var early := false
			for e in iso2.enc:
				if int(e) == Traversal.Enc.BOSS:
					early = true
			if early:
				fails += 1
				print("FAIL %s: the boss is standing on the first floor" % did); break
	print("  (info: %.1f shops and %.1f rests per dungeon)" % [
		float(shops) / float(maxi(1, trials)), float(rests) / float(maxi(1, trials))])

	# --- prices are quoted in FIGHTS, so a shop is usable at every depth (D71) ---
	#
	# They were flat gold at every depth while income scales with GOLD_DEPTH_EXP:
	# measured over 400 generated Crypt maps, a first-run player reached the merchant
	# holding a median of 20 gold against a cheapest item of 40 and could buy NOTHING
	# on 74% of visits, while the same 40g common was under one fight's takings in the
	# Maw. What is pinned is the RATIO to income, not the gold, because the gold is
	# supposed to move with depth.
	var deepest_d := 1
	var shallowest_d := 99
	for did2 in Balance.DUNGEONS:
		var dd2 := Balance.dungeon(did2)
		if dd2 != null:
			deepest_d = maxi(deepest_d, dd2.difficulty)
			shallowest_d = mini(shallowest_d, dd2.difficulty)
	for d in [shallowest_d, deepest_d]:
		var fight: int = Balance.fight_income(d)
		var cheapest: int = mini(Balance.card_price(0, d),
			mini(Balance.heal_price(Balance.BASE_MAX_HP, d), Balance.removal_price(0, d)))
		# "reachable" = within a few fights of arriving, at any depth
		if cheapest > fight * 4:
			fails += 1
			print("FAIL d%d: cheapest item %dg is %.1f fights of income — the merchant sells nothing" % [
				d, cheapest, float(cheapest) / float(fight)])
		# ...and never so cheap it stops being a decision
		if cheapest < fight:
			fails += 1
			print("FAIL d%d: cheapest item %dg is under one fight — the shop is not a gold sink" % [
				d, cheapest])
	# prices must actually MOVE with depth, or this is flat pricing again
	if Balance.card_price(0, deepest_d) <= Balance.card_price(0, shallowest_d):
		fails += 1
		print("FAIL card price does not rise with depth (d%d %dg vs d%d %dg)" % [
			deepest_d, Balance.card_price(0, deepest_d),
			shallowest_d, Balance.card_price(0, shallowest_d)])
	print("  (info: common %dg at d%d, %dg at d%d; one fight pays %dg / %dg)" % [
		Balance.card_price(0, shallowest_d), shallowest_d,
		Balance.card_price(0, deepest_d), deepest_d,
		Balance.fight_income(shallowest_d), Balance.fight_income(deepest_d)])

	# --- fusion must NOT have been repriced by any of that ---
	#
	# `fuse_gold_cost` shares `rarity_price_mult` with the shop but takes no depth,
	# because fusion happens between runs. If it ever grows a difficulty argument,
	# every existing player's upgrade costs move silently.
	for r2 in range(0, 5):
		if Balance.fuse_gold_cost(r2, 1) != [20, 32, 52, 89, 200][r2]:
			fails += 1
			print("FAIL fusion price moved at rarity %d: %d (expected %d)" % [
				r2, Balance.fuse_gold_cost(r2, 1), [20, 32, 52, 89, 200][r2]])

	# --- one copy of the rarity multiplier, not three ---
	#
	# `card_price` and `fuse_gold_cost` each carried their own `sqrt(common/weight)`,
	# which is the D34 restated-table shape and is what made pricing by depth risk
	# repricing fusion. Derive, don't restate.
	var bal := FileAccess.open("res://scripts/balance.gd", FileAccess.READ)
	if bal != null:
		var text := bal.get_as_text()
		bal.close()
		var copies := text.count("sqrt(float(w[0])")
		if copies > 1:
			fails += 1
			print("FAIL %d copies of the rarity-multiplier formula; use rarity_price_mult()" % copies)

	if fails == 0:
		print("SHOP TEST: PASS (pricing by rarity AND depth, spend guards, persistence, node gen)")
	else:
		print("SHOP TEST: FAIL (%d)" % fails)
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
