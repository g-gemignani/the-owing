## Headless test: rarity and scaling discipline across the whole card set.
##
## Rarity has to mean something in two directions:
##   power  — rarer cards are stronger per energy
##   growth — rarer cards gain MORE per level, because their level tracks are
##            shorter (caps derive from drop weight). With one flat gain the
##            scaling inverted and grinding commons beat every legendary.
## Run: godot --headless --script tests/test_rarity.gd
extends SceneTree

const DIR := "res://resources/cards/"
const NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	var ids: Array = m.CATALOG.keys()

	if ids.size() < 100:
		fails += 1; print("FAIL only %d cards" % ids.size())

	# --- maxed multiplier must ASCEND with rarity ---
	var prev_mult := 0.0
	for r in NAMES.size():
		var probe := (load(DIR + "strike.tres") as CardData).duplicate()
		probe.rarity = r
		probe.level = Balance.max_level(r)
		var mult := float(probe.eff_damage()) / 6.0
		if mult <= prev_mult:
			fails += 1; print("FAIL maxed multiplier not ascending at %s (%.2fx vs %.2fx)" % [
				NAMES[r], mult, prev_mult])
		prev_mult = mult
		print("  (info: %-9s cap L%-3d maxed %.2fx)" % [NAMES[r], Balance.max_level(r), mult])

	# --- average power per energy must rise with rarity ---
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0]
	var counts := [0, 0, 0, 0, 0]
	var totals := [0.0, 0.0, 0.0, 0.0, 0.0]
	var all_counts := [0, 0, 0, 0, 0]
	var by_rarity := {}
	for id in ids:
		var c := load(m.CATALOG[id]) as CardData
		by_rarity[c.rarity] = int(by_rarity.get(c.rarity, 0)) + 1
		totals[c.rarity] += c.power_value()
		all_counts[c.rarity] += 1
		# rate-compare only repeatable cards: a one-shot is not a rate
		if c.exhaust or c.hp_cost > 0:
			continue
		sums[c.rarity] += c.power_value() / maxf(1.0, float(c.cost))
		counts[c.rarity] += 1
	var prev_avg := 0.0
	for r in NAMES.size():
		if all_counts[r] == 0:
			fails += 1; print("FAIL no cards at rarity %s" % NAMES[r]); continue
		# Rate-comparison needs a sample. Legendaries are almost all one-shots by
		# design, so their repeatable pool is tiny; the total-power ladder below is
		# what covers them.
		if counts[r] < 3:
			print("  (info: %-9s only %d repeatable cards — rate check skipped)" % [
				NAMES[r], counts[r]])
			continue
		var avg: float = sums[r] / float(counts[r])
		if avg <= prev_avg:
			fails += 1; print("FAIL avg power/energy not rising at %s (%.1f vs %.1f)" % [
				NAMES[r], avg, prev_avg])
		prev_avg = avg
		print("  (info: %-9s %2d cards, avg %.1f power/energy repeatable)" % [NAMES[r], counts[r], avg])

	# total card power must also ascend with rarity (covers one-shot cards)
	var prev_total := 0.0
	for r in NAMES.size():
		if all_counts[r] == 0:
			continue
		var avg_total: float = totals[r] / float(all_counts[r])
		if avg_total <= prev_total:
			fails += 1; print("FAIL avg total power not rising at %s (%.1f vs %.1f)" % [
				NAMES[r], avg_total, prev_total])
		prev_total = avg_total
		print("  (info: %-9s avg total power %.1f)" % [NAMES[r], avg_total])

	# --- the pyramid: commons should be the bulk, legendaries scarce ---
	if int(by_rarity.get(0, 0)) < int(by_rarity.get(3, 0)):
		fails += 1; print("FAIL fewer commons than epics")
	if int(by_rarity.get(4, 0)) > int(by_rarity.get(0, 0)) / 3:
		fails += 1; print("FAIL too many legendaries")

	# --- no accidental duplicates: two cards with identical stats is a bug ---
	var sigs := {}
	for id in ids:
		var c := load(m.CATALOG[id]) as CardData
		var sig := "|".join([str(c.cost), str(c.damage), str(c.block), str(c.draw),
			str(c.hits), str(c.heal), str(c.energy_gain), str(c.hp_cost),
			str(c.strength_mult), str(c.aoe), str(c.exhaust), str(c.retain),
			str(c.lifesteal), str(c.double_block), str(c.damage_from_block),
			str(c.grows), str(c.retain_block),
			str(c.apply_poison), str(c.apply_vulnerable), str(c.apply_weak),
			str(c.gain_thorns), str(c.gain_strength), str(c.gain_dexterity)])
		if sigs.has(sig):
			fails += 1; print("FAIL %s is stat-identical to %s" % [id, sigs[sig]])
		sigs[sig] = id

	# --- every card must be obtainable somewhere ---
	var obtainable := {}
	for did in Balance.DUNGEONS:
		for cid in Balance.card_pool_for(did):
			obtainable[cid] = true
	for id in ids:
		if not obtainable.has(id):
			fails += 1; print("FAIL %s is in no zone/dungeon pool (unobtainable)" % id)

	# --- legendaries must be rule-changers, not just big numbers ---
	for id in ids:
		var c := load(m.CATALOG[id]) as CardData
		if c.rarity == CardData.Rarity.LEGENDARY:
			var special := c.retain_block or c.aoe or c.energy_gain > 0 \
				or c.gain_strength > 0 or c.gain_dexterity > 0 or c.gain_thorns > 0 \
				or c.heal > 0 or c.apply_poison > 0
			if not special:
				fails += 1; print("FAIL legendary %s is only numbers" % id)

	if fails == 0:
		print("RARITY TEST: PASS (%d cards; power and growth both ascend with rarity)" % ids.size())
	else:
		print("RARITY TEST: FAIL (%d)" % fails)
	quit()
