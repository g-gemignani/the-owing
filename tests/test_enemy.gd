## Headless test: enemy archetypes, patterns, multi-enemy encounters, targeting.
## Run: godot --headless --script tests/test_enemy.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0

	# --- every rostered archetype loads and is sane ---
	var seen := {}
	for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
		for id in Balance.ROSTER[tier]:
			var a := load(Balance.ENEMY_DIR + id + ".tres") as EnemyData
			if a == null:
				fails += 1; print("FAIL archetype missing: %s" % id); continue
			seen[id] = true
			if a.pattern.is_empty():
				fails += 1; print("FAIL %s has empty pattern" % id)
			if a.count_min < 1 or a.count_max < a.count_min:
				fails += 1; print("FAIL %s bad count range" % id)
			if a.hp_mult <= 0.0 or a.dmg_mult <= 0.0:
				fails += 1; print("FAIL %s non-positive mult" % id)
			if a.attack_frequency() <= 0.0 or a.attack_frequency() > 1.0:
				fails += 1; print("FAIL %s bad attack frequency" % id)
			# compensation offsets utility turns but must never fully cancel them
			var comp: float = a.damage_compensation()
			var full: float = 1.0 / a.attack_frequency()
			if comp < 1.0 or comp > full + 0.001:
				fails += 1; print("FAIL %s compensation out of range: %.2f (full=%.2f)" % [id, comp, full])
	if seen.size() < 3:
		fails += 1; print("FAIL roster too small")

	# --- pattern cycles ---
	var c := load(Balance.ENEMY_DIR + "cultist.tres") as EnemyData
	var n: int = c.pattern.size()
	if c.action_for_turn(1) != c.action_for_turn(1 + n):
		fails += 1; print("FAIL pattern does not cycle")

	# --- multi-enemy spawns respect count bounds ---
	var rat := load(Balance.ENEMY_DIR + "rat_swarm.tres") as EnemyData
	if rat.count_max < 2:
		fails += 1; print("FAIL rat_swarm is not a group archetype")
	for t in 60:
		var got: int = rat.spawn_count()
		if got < rat.count_min or got > rat.count_max:
			fails += 1; print("FAIL spawn_count out of bounds: %d" % got); break

	# --- encounter HP budget is split, not multiplied, across a group ---
	var deck := _deck({"strike": 4, "defend": 4})
	var single := CombatEngine.new()
	single.setup(deck, 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	var group := CombatEngine.new()
	group.setup(deck, 60, 60, 1, Balance.Tier.NORMAL, "rat_swarm")
	if group.enemies.size() < 2:
		fails += 1; print("FAIL group did not spawn multiple enemies")
	var single_hp := single.enemies[0].max_hp
	var group_hp := 0
	for e in group.enemies:
		group_hp += e.max_hp
	# group total should be near the single-enemy budget (archetype mults aside),
	# never a multiple of it
	if group_hp > single_hp * 2:
		fails += 1; print("FAIL group HP is a multiple of budget: %d vs %d" % [group_hp, single_hp])

	# --- targeting ---
	if group.enemies.size() >= 2:
		if not group.set_target(1):
			fails += 1; print("FAIL could not target living enemy")
		if group.current_target() != group.enemies[1]:
			fails += 1; print("FAIL target not applied")
		# killing the target retargets automatically
		group.enemies[1].hp = 0
		var t2 := group.current_target()
		if t2 == null or t2.is_dead():
			fails += 1; print("FAIL retarget picked a dead enemy")
		if group.set_target(1):
			fails += 1; print("FAIL targeted a dead enemy")
		# not won until ALL are dead
		if group.won():
			fails += 1; print("FAIL won() with living enemies remaining")
		for e in group.enemies:
			e.hp = 0
		if not group.won():
			fails += 1; print("FAIL won() false with all enemies dead")

	# --- enemy actions resolve ---
	var warden := CombatEngine.new()
	warden.setup(deck, 200, 200, 1, Balance.Tier.BOSS, "warden")
	var w: Combatant = warden.enemies[0]
	# force each action and check the effect
	warden.intents[0] = {"action": EnemyData.Action.DEFEND, "value": 9}
	warden.end_turn()
	if w.block <= 0:
		fails += 1; print("FAIL DEFEND gave no block")
	warden.intents[0] = {"action": EnemyData.Action.EMPOWER, "value": 3}
	var str_before: int = w.strength
	warden.end_turn()
	if w.strength <= str_before:
		fails += 1; print("FAIL EMPOWER gave no strength")
	warden.intents[0] = {"action": EnemyData.Action.DEBUFF_VULN, "value": 2}
	warden.end_turn()
	if warden.player.vulnerable <= 0:
		fails += 1; print("FAIL DEBUFF_VULN did not apply")
	warden.intents[0] = {"action": EnemyData.Action.DEBUFF_WEAK, "value": 2}
	warden.end_turn()
	if warden.player.weak <= 0:
		fails += 1; print("FAIL DEBUFF_WEAK did not apply")

	# --- intents are telegraphed for every action kind ---
	for a in [EnemyData.Action.ATTACK, EnemyData.Action.DEBUFF_VULN,
			EnemyData.Action.DEBUFF_WEAK, EnemyData.Action.DEFEND, EnemyData.Action.EMPOWER]:
		warden.intents[0] = {"action": a, "value": 5}
		if warden.intent_text(0) == "" or warden.intent_text(0) == "?":
			fails += 1; print("FAIL no intent text for action %d" % a)

	# --- enemy_intent counts only attacks, and only from the living ---
	var e2 := CombatEngine.new()
	e2.setup(deck, 60, 60, 1, Balance.Tier.NORMAL, "rat_swarm")
	for i in e2.intents.size():
		e2.intents[i] = {"action": EnemyData.Action.DEFEND, "value": 5}
	if e2.enemy_intent != 0:
		fails += 1; print("FAIL non-attack intents counted as damage: %d" % e2.enemy_intent)
	for i in e2.intents.size():
		e2.intents[i] = {"action": EnemyData.Action.ATTACK, "value": 5}
	var all_alive: int = e2.enemy_intent
	e2.enemies[0].hp = 0
	if e2.enemy_intent >= all_alive:
		fails += 1; print("FAIL dead enemy still contributes damage")

	if fails == 0:
		print("ENEMY TEST: PASS (archetypes, patterns, group budget, targeting, actions)")
	else:
		print("ENEMY TEST: FAIL (%d)" % fails)
	quit()

func _deck(loadout: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			deck.append((load(CARD_DIR + id + ".tres") as CardData).duplicate())
	return deck
