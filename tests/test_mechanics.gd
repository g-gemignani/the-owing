## Headless test: the card mechanics added with the big card batch.
## Every mechanic must (a) do what it says and (b) be priced in power_value, or
## enemy scaling silently falls behind the player's options (the D5/D11 lesson).
## Run: godot --headless --script tests/test_mechanics.gd
extends SceneTree

const DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0
	var deck := _deck({"strike": 8})

	# --- multi-hit deals damage per hit ---
	var e := _fight(deck)
	var tw := _card("twin_strike")
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
	var cl := _card("cleave")
	e2.energy = 3
	e2.hand.append(cl)
	e2.play_card(cl)
	for i in e2.enemies.size():
		if e2.enemies[i].hp >= int(before[i]):
			fails += 1; print("FAIL cleave did not hit enemy %d" % i); break

	# --- exhaust removes the card from the combat ---
	var e3 := _fight(deck)
	var ex := _card("pummel")
	e3.energy = 3
	e3.hand.append(ex)
	var discard_before: int = e3.discard_pile.size()
	e3.play_card(ex)
	if e3.discard_pile.size() != discard_before:
		fails += 1; print("FAIL exhausted card went to the discard pile")

	# --- retain keeps a card through end of turn ---
	var e4 := _fight(deck)
	var keep := _card("dodge_roll")
	e4.hand.append(keep)
	e4.end_turn()
	var still_held := false
	for c in e4.hand:
		if c.id == "dodge_roll":
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
	var bs := _card("body_slam")
	e7.energy = 3
	e7.hand.append(bs)
	var t0: int = e7.enemies[0].hp
	e7.play_card(bs)
	if t0 - e7.enemies[0].hp < 17:
		fails += 1; print("FAIL body_slam ignored Block (%d dealt)" % (t0 - e7.enemies[0].hp))

	# --- grows accumulates within a combat and resets between combats ---
	var g := _card("perfected_strike")
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
	var sw := _card("second_wind")
	e10.energy = 3
	e10.hand.append(sw)
	e10.play_card(sw)
	if e10.player.hp <= 20:
		fails += 1; print("FAIL heal did nothing")
	var ad := _card("adrenaline")
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
	if _card("twin_strike").power_value() <= _card("shiv").power_value():
		fails += 1; print("FAIL multi-hit not priced above a single small hit")
	if _card("cleave").power_value() <= _card("execute").power_value() * 0.5:
		fails += 1; print("FAIL AoE priced too low")
	# exhaust is a real cost, so an exhausting card must price BELOW its raw damage
	var fin := _card("finisher")
	if fin.power_value() >= float(fin.eff_damage()):
		fails += 1; print("FAIL exhaust discount not applied: %.1f vs %d dmg" % [
			fin.power_value(), fin.eff_damage()])

	if fails == 0:
		print("MECHANICS TEST: PASS (multi-hit, AoE, exhaust, retain, poison, thorns, block-scaling, grows, heal, energy)")
	else:
		print("MECHANICS TEST: FAIL (%d)" % fails)
	quit()

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
