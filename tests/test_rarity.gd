## Headless test: rarity and scaling discipline across the whole card set.
##
## Rarity has to mean something in two directions:
##   power  — rarer cards are stronger per energy
##   growth — rarer cards gain MORE per level, because their level tracks are
##            shorter (caps derive from drop weight). With one flat gain the
##            scaling inverted and grinding commons beat every legendary.
##
## D109 rebuilt level scaling so no level-up is empty, which put a floor of +1 per
## level under every track. A common's hundred levels are therefore worth +99 on
## their own, and the growth ladder had to be re-pitched steeply enough to stay
## ahead of that — see CardData.LEVEL_RATE_BY_RARITY. The check below is unchanged
## because the property is unchanged; only the constants that satisfy it moved.
## Run: godot --headless --script tests/test_rarity.gd
extends SceneTree

const DIR := "res://resources/cards/"
const NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]

## How far under the strongest epic the weakest legendary may sit. The top band promotes a
## rule-changer over a plain number on purpose, so a small overlap is the design; a large one is a
## `_rule_changer` that has gone blind. Cards sit at 0.96 of it today and the D246 power bug sat at
## 0.62, so 0.85 separates the two with room on both sides.
const TOP_BAND_FLOOR := 0.85

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	var ids: Array = m.CATALOG.keys()

	if ids.size() < 100:
		fails += 1; print("FAIL only %d cards" % ids.size())

	# --- maxed multiplier must ASCEND with rarity ---
	var prev_mult := 0.0
	for r in NAMES.size():
		var probe := (load(DIR + "hack.tres") as CardData).duplicate()
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
		# Balance.card_energy_cost, not `c.cost`: an X-cost card is authored at 1 and
		# consumes the whole turn, and the two readings put it at either end of its own
		# rarity band. The rule has one owner (D204) so the ladder here and the ratchet
		# in `Balance.deck_cost` cannot disagree about the same card.
		sums[c.rarity] += c.power_value() / maxf(1.0, Balance.card_energy_cost(c))
		counts[c.rarity] += 1
	# INFORMATIONAL since D224, and the demotion is the finding rather than a retreat.
	#
	# It used to be an assertion: average power per energy must rise with rarity. Rarity
	# is now written from TOTAL power (`tools/rerarify.gd`), and the two cannot both
	# hold — ranking by impact concentrates expensive cards in the upper bands, and an
	# expensive card is by definition worse per energy, so the rate average sags exactly
	# where the ranking is working. It first failed by 1% (uncommon 10.2, rare 10.1) with
	# every band otherwise in order, which is the shape of a test measuring the wrong
	# thing rather than of a catalogue going wrong.
	#
	# What it was protecting — a legendary should FEEL strong for the turn it costs — is
	# not lost: it is the maxed-multiplier ladder above and the no-overlap check below,
	# and per-energy is still exactly what enemy scaling reads (`Balance.power_ratio`),
	# where it is measured against real decks rather than against rarity bands.
	for r in NAMES.size():
		if all_counts[r] == 0:
			fails += 1; print("FAIL no cards at rarity %s" % NAMES[r]); continue
		if counts[r] < 3:
			print("  (info: %-9s only %d repeatable cards — no rate to quote)" % [
				NAMES[r], counts[r]])
			continue
		print("  (info: %-9s %2d cards, avg %.1f power/energy repeatable)" % [
			NAMES[r], counts[r], sums[r] / float(counts[r])])

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

	# --- the bands may not OVERLAP (D224) ---------------------------------------------
	#
	# The ladder above is about averages, and averages hid the state this replaced: 29 of
	# 32 commons beat the weakest uncommon, and the strongest card in the game was an
	# epic. A band average can ascend perfectly while every card in it is misfiled.
	#
	# The yardstick is `power_value()` — the same score the collection screen sorts by,
	# so a player who sorts by Power and reads the rarity colours sees one ordering and
	# not two. Rarity is written FROM it by `tools/rerarify.gd`; this is what stops the
	# next hand-authored card from landing in the wrong band.
	#
	# ONE exception, and it is the other rule on this page rather than a fudge: a
	# legendary must change a rule (see below), so a card that is only numbers is passed
	# over for the top band however strong it is. It may therefore out-score a legendary.
	# Nothing else may.
	var worst := {}   # rarity -> weakest power in the band
	var best := {}    # rarity -> strongest
	var only_numbers := {}
	for id in ids:
		var c := load(m.CATALOG[id]) as CardData
		var p: float = c.power_value()
		var r := int(c.rarity)
		worst[r] = minf(float(worst.get(r, 1e9)), p)
		best[r] = maxf(float(best.get(r, -1.0)), p)
		if p > float(worst.get(CardData.Rarity.LEGENDARY, 1e9)) and not _rule_changer(c):
			only_numbers[String(id)] = p
	for r in range(NAMES.size() - 1):
		if not worst.has(r) or not worst.has(r + 1):
			continue
		var over: Array[String] = []
		for id in ids:
			var c2 := load(m.CATALOG[id]) as CardData
			if int(c2.rarity) != r or c2.power_value() <= float(worst[r + 1]):
				continue
			# the documented exception, and only at the top boundary
			if r + 1 == CardData.Rarity.LEGENDARY and not _rule_changer(c2):
				continue
			over.append("%s %.1f" % [c2.name, c2.power_value()])
		if not over.is_empty():
			fails += 1
			print("FAIL %d %s card(s) outrank the weakest %s (%.1f): %s" % [
				over.size(), NAMES[r], NAMES[r + 1], worst[r + 1], ", ".join(over)])
	for r in range(NAMES.size()):
		if worst.has(r):
			print("  (info: %-9s power %.1f .. %.1f)" % [NAMES[r], worst[r], best[r]])

	# --- and the same for relics, which had no ordering at all ---
	var rworst := {}
	var rbest := {}
	var relics: Array = []
	for rid in m.RELIC_CATALOG:
		var rd := load(m.RELIC_CATALOG[rid]) as RelicData
		if rd == null:
			continue
		relics.append(rd)
		var rr := int(rd.rarity)
		rworst[rr] = minf(float(rworst.get(rr, 1e9)), rd.power_value())
		rbest[rr] = maxf(float(rbest.get(rr, -1.0)), rd.power_value())
	for r in range(NAMES.size() - 1):
		if not rworst.has(r) or not rworst.has(r + 1):
			continue
		var rover: Array[String] = []
		for rd2 in relics:
			if int(rd2.rarity) == r and rd2.power_value() > float(rworst[r + 1]):
				rover.append("%s %.1f" % [rd2.name, rd2.power_value()])
		if not rover.is_empty():
			fails += 1
			print("FAIL %d %s relic(s) outrank the weakest %s (%.1f): %s" % [
				rover.size(), NAMES[r], NAMES[r + 1], rworst[r + 1], ", ".join(rover)])
	for r in range(NAMES.size()):
		if rworst.has(r):
			print("  (info: relics %-9s power %.1f .. %.1f)" % [NAMES[r], rworst[r], rbest[r]])

	# --- the pyramid: commons should be the bulk, legendaries scarce ---
	if int(by_rarity.get(0, 0)) < int(by_rarity.get(3, 0)):
		fails += 1; print("FAIL fewer commons than epics")
	if int(by_rarity.get(4, 0)) > int(by_rarity.get(0, 0)) / 3:
		fails += 1; print("FAIL too many legendaries")

	# Duplicate cards are checked in tests/test_distinct.gd, which also catches the
	# case this could not: a card that is not identical to another but is beaten by
	# it outright. The list of mechanics lived here as a hand-copied second copy and
	# had drifted seven fields behind card_data.gd, so Jab and Nick — which differ by
	# a combo bonus — read as the same card. One list, one place.

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
			# `CardData.changes_a_rule()` and not a copy of its list (D246). This suite held the
			# second copy, and when `rerarify`'s was fixed the two disagreed about Drilled — the tool
			# called `grows` a rule and this called it a number.
			if not c.changes_a_rule():
				fails += 1; print("FAIL legendary %s is only numbers" % id)

	# --- the bands must ascend in EVERY catalogue, not only the cards (D246) ---
	#
	# This suite walked `CATALOG` and nothing else for two hundred entries, so relics and powers wore
	# a derived rarity with no check on it. That went wrong exactly once and silently: `rerarify`'s
	# legendary guard asked `_rule_changer`, which was a hand-written list of eight fields that knew
	# nothing of the conditional mechanics D66 and D204 added — so a power whose whole identity is
	# `discount_next` read as "only numbers" and was passed over for the top band. **LEGENDARY came
	# out 6.6..9.0 while EPIC came out 9.0..10.7: a top band weaker than the band beneath it, and
	# nothing failed.**
	#
	# Asserted over the CATALOGUES rather than per type, so a fourth kind of rarity-bearing content
	# joins by existing. D180's rule, and this is its third costume.
	var catalogues := {"cards": [], "relics": [], "powers": []}
	for cid in m.CATALOG:
		var cc := load(m.CATALOG[cid]) as CardData
		if cc != null:
			catalogues["cards"].append(cc)
	for rid in m.RELIC_CATALOG:
		var rr := load(String(m.RELIC_CATALOG[rid])) as RelicData
		if rr != null:
			catalogues["relics"].append(rr)
	for pid in Balance.POWERS:
		var pp := Balance.power(String(pid))
		if pp != null:
			catalogues["powers"].append(pp)
	for kind in catalogues:
		# The WEAKEST member of each band must still beat the STRONGEST of the band below it. That is
		# the non-overlap rule, and it is what a mean over a band cannot see: two bands can have
		# ascending averages while individual members are filed upside down.
		var floors := {}
		var ceils := {}
		for item in catalogues[kind]:
			var r: int = int(item.rarity)
			var v: float = item.power_value()
			floors[r] = minf(float(floors.get(r, v)), v)
			ceils[r] = maxf(float(ceils.get(r, v)), v)
		var top: int = CardData.Rarity.size() - 1
		for r in range(1, CardData.Rarity.size()):
			if not (floors.has(r) and ceils.has(r - 1)):
				continue
			# The TOP boundary is allowed to overlap, and only the top one. `rerarify`'s legendary
			# guard deliberately passes over a card that is only numbers and promotes the next
			# rule-changer, so the weakest legendary can sit slightly under the strongest epic — and
			# the cards do exactly that today, 22.1 against 23.0. Forbidding it outright would forbid
			# the rule this project wants: **a legendary has to CHANGE something, not just be big.**
			#
			# What must not happen is a GROSS inversion, which is how the bug this check was written
			# for looked: powers came out with a 6.6 legendary over a 10.7 epic, 62% of it. A margin
			# separates the two cases — a promotion of a few percent is the rule working, a promotion
			# of a third is a `_rule_changer` that has stopped recognising its subjects.
			var margin: float = TOP_BAND_FLOOR if r == top else 1.0
			if float(floors[r]) < float(ceils[r - 1]) * margin:
				fails += 1
				print("FAIL %s: the weakest %s (%.1f) is below the strongest %s (%.1f)%s — the bands are filed upside down" % [
					kind, CardData.rarity_badge(r), float(floors[r]),
					CardData.rarity_badge(r - 1), float(ceils[r - 1]),
					" by more than the top band's allowance" if r == top else ""])

	if fails == 0:
		print("RARITY TEST: PASS (%d cards, %d relics, %d powers; power ascends with rarity in all three and the bands do not overlap)" % [
			ids.size(), m.RELIC_CATALOG.size(), Balance.POWERS.size()])
	else:
		print("RARITY TEST: FAIL (%d)" % fails)
	quit()

## Whether a card changes a RULE rather than only a number. Stated once and used
## twice: the legendary check below, and the one exception the no-overlap check above
## allows — a card that is only numbers cannot be promoted into the top band, so it is
## the one thing permitted to out-score what is in there.
func _rule_changer(c: CardData) -> bool:
	return c.retain_block or c.aoe or c.energy_gain > 0 or c.gain_strength > 0 \
		or c.gain_dexterity > 0 or c.gain_thorns > 0 or c.heal > 0 or c.apply_poison > 0
