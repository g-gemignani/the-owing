## Headless test: no card is a worse copy of another card.
##
## A reward screen offers three cards. If one of them is beaten outright by a card
## already in the pool, the choice was never a choice — and the player cannot tell,
## because both faces read like reasonable cards. Jab and Nick were the report that
## started this (same cost, same rarity, same slot, one just better once you play
## three cards a turn), but the catalogue had eight more, and they had accumulated
## quietly: every one of them arrived as a sensible card next to a NEIGHBOUR that
## later got tuned past it.
##
## DOMINATION is the honest test, and it is mechanical rather than a matter of
## taste: A beats B if A costs no more, is no rarer, is at least as good on every
## axis the engine reads, and is strictly better on one. No judgement about whether
## a card is FUN lives here — only whether picking it can ever be correct.
##
## The two starter cards are exempt, and must stay exempt. Hack and Cover are
## SUPPOSED to be the worst cards you own: the entire meta layer is the business of
## replacing them, `Balance.power_ratio` uses that deck as its 1.0 baseline, and a
## starter that competed with the pool would flatten the reward curve it anchors.
## Run: godot --headless --script tests/test_distinct.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_distinct_"

## The deck the game hands you. Deliberately outclassed; see the note above.
const STARTERS := ["hack", "cover"]

## Axes where MORE is better for the player.
const BETTER_HIGHER := ["damage", "block", "draw", "hits", "heal", "energy_gain",
	"lifesteal", "strength_mult", "double_block", "damage_from_block", "grows",
	"apply_vulnerable", "apply_weak", "apply_poison", "gain_thorns", "gain_strength",
	"gain_dexterity", "retain", "retain_block", "aoe", "damage_per_poison",
	"damage_per_thorns", "bonus_vs_debuffed", "combo_bonus", "energy_on_kill",
	"block_per_card_in_hand"]
## Axes where more is a COST. `exhaust` is here because one use per combat is a real
## price — it is why Plague Bearer and Blight Bloom can share an effect honestly.
const BETTER_LOWER := ["hp_cost", "exhaust"]

func _init() -> void:
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	var fails := 0

	var m = load("res://scripts/meta_state.gd").new()
	var cards := {}
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		if c != null:
			cards[id] = c

	for loser in cards:
		if loser in STARTERS:
			continue
		for winner in cards:
			if winner == loser or not _beats(cards[winner], cards[loser]):
				continue
			fails += 1
			print("FAIL %s is a strictly worse %s — no reason to ever pick it" % [
				loser, winner])
			print("     %-16s r%d cost%d  %s" % [loser, cards[loser].rarity,
				cards[loser].eff_cost(), cards[loser].effect_text()])
			print("     %-16s r%d cost%d  %s" % [winner, cards[winner].rarity,
				cards[winner].eff_cost(), cards[winner].effect_text()])

	# Exact twins slip past domination, which needs a STRICTLY better axis: two cards
	# equal on all of them beat each other on none. Different art and a different name
	# is not a different card.
	var seen := {}
	for id in cards:
		var key := _signature(cards[id])
		if seen.has(key):
			fails += 1
			print("FAIL %s and %s are the same card: %s" % [
				seen[key], id, cards[id].effect_text()])
		else:
			seen[key] = id

	# ...and the exemption must stay an exemption rather than quietly becoming the
	# rule. If a starter stops being outclassed, the reward curve has drifted and
	# somebody should decide that on purpose.
	for s in STARTERS:
		if not cards.has(s):
			fails += 1; print("FAIL the starter card %s is gone; update STARTERS" % s)
			continue
		var beaten := false
		for winner in cards:
			if winner != s and _beats(cards[winner], cards[s]):
				beaten = true
				break
		if not beaten:
			fails += 1
			print("FAIL %s is no longer outclassed by anything — it is a starter," % s)
			print("     so the pool has drifted down to it. Re-check the reward curve.")

	if fails == 0:
		print("DISTINCT TEST: PASS (every card in the pool can be the right pick)")
	else:
		print("DISTINCT TEST: FAIL (%d)" % fails)
	quit()


## True if `a` is at least as good as `b` everywhere and better somewhere, at no
## greater cost or rarity — i.e. taking `b` over `a` is never right.
func _beats(a: CardData, b: CardData) -> bool:
	if a.type != b.type:
		return false          # an attack and a skill are not competing for the same job
	if a.eff_cost() > b.eff_cost() or a.rarity > b.rarity:
		return false
	# A combo bonus that needs MORE cards down first is a worse bonus, so a card
	# asking for a longer combo is not beaten by one asking for a shorter one.
	if a.combo_bonus > 0 and b.combo_at > 0 and a.combo_at > b.combo_at:
		return false
	for f in BETTER_HIGHER:
		if _num(a.get(f)) < _num(b.get(f)):
			return false
	for f in BETTER_LOWER:
		if _num(a.get(f)) > _num(b.get(f)):
			return false
	if a.eff_cost() < b.eff_cost() or a.rarity < b.rarity:
		return true
	for f in BETTER_HIGHER:
		if _num(a.get(f)) > _num(b.get(f)):
			return true
	for f in BETTER_LOWER:
		if _num(a.get(f)) < _num(b.get(f)):
			return true
	return false              # identical on every axis: caught by the twin check below

## Everything the engine reads off a card, in one string. Name, art and flavour are
## deliberately absent: they are what makes two identical cards LOOK different.
func _signature(c: CardData) -> String:
	var parts: Array[String] = [str(c.type), str(c.eff_cost()), str(c.combo_at)]
	for f in BETTER_HIGHER + BETTER_LOWER:
		parts.append("%.1f" % _num(c.get(f)))
	return ",".join(parts)

func _num(v) -> float:
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	return float(v)
