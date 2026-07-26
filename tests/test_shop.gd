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

	# --- shop nodes actually appear on generated maps ---
	var GS := TraversalGraph.new()
	var shops := 0
	var rests := 0
	var trials := 200
	for t in trials:
		GS.generate(null)
		for r in GS.map.size():
			for node in GS.map[r]:
				if node["type"] == Traversal.Enc.SHOP:
					shops += 1
				elif node["type"] == Traversal.Enc.REST:
					rests += 1
	if shops == 0:
		fails += 1; print("FAIL no shop nodes generated in %d maps" % trials)
	# boss row and first row must never be shops
	for t in 50:
		GS.generate(null)
		if GS.map[0][0]["type"] == Traversal.Enc.SHOP:
			fails += 1; print("FAIL shop on first row"); break
		for node in GS.map[GS.map.size() - 1]:
			if node["type"] != Traversal.Enc.BOSS:
				fails += 1; print("FAIL boss row polluted"); break
	print("  (info: %.1f shops and %.1f rests per map)" % [
		float(shops) / trials, float(rests) / trials])

	if fails == 0:
		print("SHOP TEST: PASS (pricing by rarity, spend guards, persistence, node gen)")
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
