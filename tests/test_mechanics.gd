## Headless test: the card mechanics added with the big card batch.
## Every mechanic must (a) do what it says and (b) be priced in power_value, or
## enemy scaling silently falls behind the player's options (the D5/D11 lesson).
## Run: godot --headless --script tests/test_mechanics.gd
extends SceneTree

const DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0
	var deck := _deck({"hack": 8})

	# --- multi-hit deals damage per hit ---
	var e := _fight(deck)
	var tw := _card("two_quick")
	var hp0: int = e.enemies[0].hp
	e.energy = 3
	e.hand.append(tw)
	e.play_card(tw)
	var dealt: int = hp0 - e.enemies[0].hp
	if dealt < tw.eff_damage() * 2:
		fails += 1; print("FAIL twin_strike dealt %d, expected >= %d" % [dealt, tw.eff_damage() * 2])

	# --- AoE hits every living enemy ---
	var e2 := _fight(deck, "rat_swarm")
	if e2.enemies.size() < 2:
		print("  (info: rat_swarm spawned 1, AoE check limited)")
	var before: Array = []
	for en in e2.enemies:
		before.append(en.hp)
	var cl := _card("reap")
	e2.energy = 3
	e2.hand.append(cl)
	e2.play_card(cl)
	for i in e2.enemies.size():
		if e2.enemies[i].hp >= int(before[i]):
			fails += 1; print("FAIL cleave did not hit enemy %d" % i); break

	# --- exhaust removes the card from the combat ---
	# Bandage rather than a card that merely happens to exhaust today: this asserts
	# the ENGINE rule, and it was pointed at Keep Hitting, which stopped exhausting
	# the moment that card was given an identity of its own.
	var e3 := _fight(deck)
	var ex := _card("bandage")
	e3.energy = 3
	e3.hand.append(ex)
	var discard_before: int = e3.discard_pile.size()
	e3.play_card(ex)
	if e3.discard_pile.size() != discard_before:
		fails += 1; print("FAIL exhausted card went to the discard pile")

	# --- retain keeps a card through end of turn ---
	var e4 := _fight(deck)
	var keep := _card("give_ground")
	e4.hand.append(keep)
	e4.end_turn()
	var still_held := false
	for c in e4.hand:
		if c.id == "give_ground":
			still_held = true
	if not still_held:
		fails += 1; print("FAIL retain card was discarded at end of turn")

	# --- poison ignores block and ticks at end of turn ---
	var e5 := _fight(deck)
	var vf := _card("venom_fang")
	e5.energy = 3
	e5.hand.append(vf)
	e5.play_card(vf)
	if e5.enemies[0].poison <= 0:
		fails += 1; print("FAIL poison not applied")
	e5.enemies[0].block = 999          # poison must bypass block entirely
	var php: int = e5.enemies[0].hp
	var tick: int = e5.enemies[0].end_turn()
	if tick <= 0 or e5.enemies[0].hp >= php:
		fails += 1; print("FAIL poison did not damage through block")

	# --- thorns retaliate against attackers ---
	var e6 := _fight(deck)
	e6.player.thorns = 5
	e6.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 5}
	var ehp: int = e6.enemies[0].hp
	e6.end_turn()
	if e6.enemies[0].hp >= ehp:
		fails += 1; print("FAIL thorns did not damage the attacker")

	# --- body slam scales off current block ---
	var e7 := _fight(deck)
	e7.player.block = 17
	var bs := _card("ram")
	e7.energy = 3
	e7.hand.append(bs)
	var t0: int = e7.enemies[0].hp
	e7.play_card(bs)
	if t0 - e7.enemies[0].hp < 17:
		fails += 1; print("FAIL body_slam ignored Block (%d dealt)" % (t0 - e7.enemies[0].hp))

	# --- grows accumulates within a combat and resets between combats ---
	var g := _card("drilled")
	var e8 := _fight([g])
	e8.energy = 9
	if not (g in e8.hand):
		e8.hand.append(g)
	var first: int = g.hit_damage()
	e8.play_card(g)
	if g.hit_damage() <= first:
		fails += 1; print("FAIL grows did not increase damage")
	var e9 := CombatEngine.new()
	e9.setup([g], 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	if g.growth != 0:
		fails += 1; print("FAIL growth carried into a new combat")

	# --- heal and energy gain ---
	var e10 := _fight(deck)
	e10.player.hp = 20
	var sw := _card("stitch")
	e10.energy = 3
	e10.hand.append(sw)
	e10.play_card(sw)
	if e10.player.hp <= 20:
		fails += 1; print("FAIL heal did nothing")
	var ad := _card("kick")
	var en_before: int = e10.energy
	e10.hand.append(ad)
	e10.play_card(ad)
	if e10.energy <= en_before:
		fails += 1; print("FAIL energy_gain did not add energy")

	# --- every card must be priced, or enemy scaling falls behind ---
	var m = load("res://scripts/meta_state.gd").new()
	for id in m.CATALOG:
		var c := _card(id)
		if c.power_value() <= 0.0:
			fails += 1; print("FAIL %s has no power_value" % id)
		if c.cost < 0:
			fails += 1; print("FAIL %s has negative cost" % id)
		if c.description.strip_edges() == "" or c.name.strip_edges() == "":
			fails += 1; print("FAIL %s missing name/description" % id)
	# mechanics must actually raise the price they are worth
	if _card("two_quick").power_value() <= _card("nick").power_value():
		fails += 1; print("FAIL multi-hit not priced above a single small hit")
	if _card("reap").power_value() <= _card("execute").power_value() * 0.5:
		fails += 1; print("FAIL AoE priced too low")
	# exhaust is a real cost, so an exhausting card must price BELOW its raw damage
	var fin := _card("last_word")
	if fin.power_value() >= float(fin.eff_damage()):
		fails += 1; print("FAIL exhaust discount not applied: %.1f vs %d dmg" % [
			fin.power_value(), fin.eff_damage()])

	if fails == 0:
		print("MECHANICS TEST: PASS (multi-hit, AoE, exhaust, retain, poison, thorns, block-scaling, grows, heal, energy)")
	else:
		print("MECHANICS TEST: FAIL (%d)" % fails)
	quit()

	# --- cards that read the fight (D66) ------------------------------------------
	#
	# Every one of these has to (a) actually change the number and (b) be priced, or
	# enemy scaling falls behind the deck built around it. Both are asserted, because
	# the second failure is invisible: the card works, the build just quietly stops
	# keeping up with the dungeons it unlocked.
	var cond := _deck({"hack": 8})

	# poison: the same card is worth more into a poisoned target
	var ep := _fight(cond)
	var rup := _card("split")
	var plain: int = ep.card_damage(rup)
	ep.enemies[0].poison = 6
	var poisoned: int = ep.card_damage(rup)
	if poisoned <= plain:
		fails += 1; print("FAIL rupture ignores Poison: %d vs %d" % [plain, poisoned])

	# thorns: scales with what you are wearing, not with the target
	var et := _fight(cond)
	var rip := _card("riposte")
	var bare: int = et.card_damage(rip)
	et.player.thorns = 8
	if et.card_damage(rip) <= bare:
		fails += 1; print("FAIL riposte ignores Thorns")

	# debuffs: the follow-up hits harder
	var ed := _fight(cond)
	var iw := _card("shoulder")
	var clean: int = ed.card_damage(iw)
	ed.enemies[0].vulnerable = 2
	if ed.card_damage(iw) <= clean:
		fails += 1; print("FAIL iron_wave ignores a Vulnerable target")

	# tempo: worth more late in the turn than early
	var ec := _fight(cond)
	var shiv := _card("nick")
	var early: int = ec.card_damage(shiv)
	ec.cards_played_this_turn = 4
	if ec.card_damage(shiv) <= early:
		fails += 1; print("FAIL shiv is worth the same as the first card of a turn")

	# swarm: a kill pays an energy back
	var ek := _fight(cond)
	ek.enemies[0].max_hp = 6
	ek.enemies[0].hp = 6
	var cull := _card("cull")
	ek.energy = 3
	ek.hand.append(cull)
	var e_before: int = ek.energy
	ek.play_card(cull)
	if not ek.enemies[0].is_dead():
		print("  (info: cull did not kill a 6hp enemy, skipping the refund check)")
	elif ek.energy != e_before - cull.cost + 1:
		fails += 1
		print("FAIL cull killed and did not refund energy: %d -> %d (cost %d)" % [
			e_before, ek.energy, cull.cost])
	# ...and NOT when nothing dies
	var ek2 := _fight(cond)
	var cull2 := _card("cull")
	ek2.energy = 3
	ek2.hand.append(cull2)
	ek2.play_card(cull2)
	if ek2.energy != 3 - cull2.cost:
		fails += 1; print("FAIL cull refunded energy without a kill")

	# fortress: a fuller hand is a bigger shield
	var eh := _fight(cond)
	var gd := _card("guard")
	eh.hand = [gd]
	var alone: int = eh.card_block(gd)
	for i in 4:
		eh.hand.append(_card("hack"))
	if eh.card_block(gd) <= alone:
		fails += 1; print("FAIL guard ignores the cards in your hand")

	# ...and every one of them must cost the deck something in priced power
	for pair in [["split", "damage_per_poison"], ["riposte", "damage_per_thorns"],
			["shoulder", "bonus_vs_debuffed"], ["nick", "combo_bonus"],
			["cull", "energy_on_kill"], ["guard", "block_per_card_in_hand"]]:
		var real := _card(String(pair[0]))
		var stripped := _card(String(pair[0]))
		stripped.set(String(pair[1]), 0 if String(pair[1]) != "energy_on_kill" else false)
		if real.power_value() <= stripped.power_value():
			fails += 1
			print("FAIL %s is not priced for %s — enemy scaling will fall behind it" % [
				pair[0], pair[1]])

func _card(id: String) -> CardData:
	return (load(DIR + id + ".tres") as CardData).duplicate()

func _deck(loadout: Dictionary) -> Array[CardData]:
	var d: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			d.append(_card(id))
	return d

func _fight(deck, archetype: String = "cultist") -> CombatEngine:
	var typed: Array[CardData] = []
	for c in deck:
		typed.append(c)
	var e := CombatEngine.new()
	e.setup(typed, 60, 60, 1, Balance.Tier.NORMAL, archetype)
	e.enemies[0].max_hp = 500
	e.enemies[0].hp = 500
	return e
