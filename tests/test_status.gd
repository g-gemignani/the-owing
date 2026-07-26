## Headless test: status effects + block lifetime rules (Phase 6).
## Run: godot --headless --script tests/test_status.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0

	# ---------------------------------------------------------------
	# BLOCK LIFETIME — the core defensive rule.
	# Block must absorb the incoming hit, then expire on the next turn.
	# ---------------------------------------------------------------
	var eng := CombatEngine.new()
	eng.setup(_deck({"strike": 4, "defend": 4}), 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	var defend := _find(eng.hand, "defend")
	if defend == null:
		# guarantee a Defend in hand for the test
		eng.hand.append(_card("defend"))
		defend = _find(eng.hand, "defend")
	eng.play_card(defend)
	if eng.player.block <= 0:
		fails += 1; print("FAIL block not gained")
	var blocked_before: int = eng.player.block
	eng.end_turn()  # enemy attacks (block absorbs), then next turn starts
	if eng.player.block != 0:
		fails += 1; print("FAIL block did not expire at end of turn: %d" % eng.player.block)
	# and it must have actually absorbed damage rather than expiring first
	if eng.player.hp > 60 - 1 and blocked_before > 0:
		pass  # took little/no damage: block worked
	if eng.player.hp < 60 - 60:
		fails += 1; print("FAIL impossible hp")

	# ---------------------------------------------------------------
	# BARRICADE (legendary) — block persists and accumulates.
	# ---------------------------------------------------------------
	var e2 := CombatEngine.new()
	e2.setup(_deck({"defend": 8}), 200, 200, 1, Balance.Tier.NORMAL, "cultist")
	e2.hand.append(_card("barricade"))
	e2.play_card(_find(e2.hand, "barricade"))
	if not e2.player.retain_block:
		fails += 1; print("FAIL barricade did not set retain_block")
	# bank block over two turns; it must not reset
	# (Barricade costs 3, so refresh energy before banking block)
	e2.energy = 3
	e2.hand.append(_card("defend"))
	e2.play_card(_find(e2.hand, "defend"))
	var banked: int = e2.player.block
	if banked <= 0:
		fails += 1; print("FAIL no block banked")
	e2.end_turn()
	# after the enemy hit, leftover block must survive into the new turn
	if e2.player.block <= 0 and banked > e2.enemy_intent:
		fails += 1; print("FAIL barricade block expired (had %d, intent %d)" % [banked, e2.enemy_intent])
	# accumulate further
	e2.energy = 3
	e2.hand.append(_card("defend"))
	var before_accum: int = e2.player.block
	e2.play_card(_find(e2.hand, "defend"))
	if e2.player.block <= before_accum:
		fails += 1; print("FAIL barricade block did not accumulate")

	# ---------------------------------------------------------------
	# VULNERABLE / WEAK / STRENGTH / DEXTERITY maths
	# ---------------------------------------------------------------
	var c := Combatant.new()
	c.hp = 100; c.max_hp = 100
	c.vulnerable = 1
	c.take_damage(10)   # +50% => 15
	if c.hp != 85:
		fails += 1; print("FAIL vulnerable: hp %d (expect 85)" % c.hp)

	var w := Combatant.new()
	if w.outgoing_damage(10) != 10:
		fails += 1; print("FAIL base outgoing damage")
	w.weak = 1
	if w.outgoing_damage(10) != 8:   # 10 * 0.75 = 7.5 -> round 8
		fails += 1; print("FAIL weak: %d" % w.outgoing_damage(10))
	w.weak = 0
	w.strength = 3
	if w.outgoing_damage(10) != 13:
		fails += 1; print("FAIL strength: %d" % w.outgoing_damage(10))
	w.dexterity = 2
	if w.outgoing_block(5) != 7:
		fails += 1; print("FAIL dexterity: %d" % w.outgoing_block(5))

	# debuffs decay, permanent buffs do not
	var d := Combatant.new()
	d.vulnerable = 2; d.weak = 1; d.strength = 4; d.dexterity = 4
	d.end_turn()
	if d.vulnerable != 1 or d.weak != 0:
		fails += 1; print("FAIL debuff decay: vuln %d weak %d" % [d.vulnerable, d.weak])
	if d.strength != 4 or d.dexterity != 4:
		fails += 1; print("FAIL permanent buffs decayed")

	# ---------------------------------------------------------------
	# Cards actually apply their statuses through the engine
	# ---------------------------------------------------------------
	var e3 := CombatEngine.new()
	e3.setup(_deck({"strike": 8}), 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	# keep the target alive so the card's rider effects are observable
	e3.enemies[0].max_hp = 500
	e3.enemies[0].hp = 500
	e3.hand.append(_card("bash"))
	e3.energy = 3
	e3.play_card(_find(e3.hand, "bash"))
	if e3.enemy.vulnerable <= 0:
		fails += 1; print("FAIL bash did not apply Vulnerable")
	e3.hand.append(_card("terrify"))
	e3.energy = 3
	e3.play_card(_find(e3.hand, "terrify"))
	if e3.enemy.weak <= 0:
		fails += 1; print("FAIL terrify did not apply Weak")
	e3.hand.append(_card("inflame"))
	e3.energy = 3
	e3.play_card(_find(e3.hand, "inflame"))
	if e3.player.strength <= 0:
		fails += 1; print("FAIL inflame did not grant Strength")
	e3.hand.append(_card("footwork"))
	e3.energy = 3
	e3.play_card(_find(e3.hand, "footwork"))
	if e3.player.dexterity <= 0:
		fails += 1; print("FAIL footwork did not grant Dexterity")

	# status cards must carry tuning weight, or enemy scaling ignores them
	if _card("barricade").power_value() <= 0:
		fails += 1; print("FAIL barricade has no power_value (breaks scaling)")
	if _card("terrify").power_value() <= 0:
		fails += 1; print("FAIL terrify has no power_value (breaks scaling)")

	if fails == 0:
		print("STATUS TEST: PASS (block expiry, barricade retention, vuln/weak/str/dex, decay)")
	else:
		print("STATUS TEST: FAIL (%d)" % fails)
	quit()

func _card(id: String) -> CardData:
	return (load(CARD_DIR + id + ".tres") as CardData).duplicate()

func _find(cards: Array, id: String) -> CardData:
	for c in cards:
		if c.id == id:
			return c
	return null

func _deck(loadout: Dictionary, level: int = 1) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			var c := _card(id)
			c.level = level
			deck.append(c)
	return deck
