## Headless test: conditional enemy behaviour (D38).
##
## Enemies used to be clockwork — `pattern[turn % n]`, blind to the player's HP,
## the player's Block, their own HP and everything else. Every fight was solvable
## once and then repeated forever, and a boss was a normal enemy with 1.55x HP.
##
## The property that matters most here is HONESTY: the intent shown to the player
## must be the action that resolves. A reactive enemy whose telegraph can change
## after the player commits is not a puzzle, it is a coin flip.
## Run: godot --headless --script tests/test_reactive.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"
const Engine_ := preload("res://scripts/combat_engine.gd")

func _init() -> void:
	var fails := 0

	# --- rule tables must be coherent, or a rule silently never fires ---
	var reactive := 0
	for id in _all_enemy_ids():
		var e := load("res://resources/enemies/%s.tres" % id) as EnemyData
		if e == null:
			fails += 1; print("FAIL enemy %s does not load" % id); continue
		var n := e.rule_count()
		if n == 0:
			continue
		reactive += 1
		# Rules belong on single-spawn archetypes. Three copies of an enemy that
		# empowers itself on a drumbeat compound into difficulty the dungeon rating
		# knows nothing about: a rat swarm doing exactly that was measured dropping
		# AoE decks from 92% to 32% run completion.
		if e.count_max > 1:
			fails += 1
			print("FAIL %s spawns up to %d and carries %d rules — they stack" % [
				id, e.count_max, n])
		# every parallel array must cover every rule, or _rule_field silently
		# substitutes a default and the authored value is lost
		for arr_name in ["rule_trigger", "rule_threshold", "rule_action", "rule_value", "rule_once"]:
			var arr: PackedInt32Array = e.get(arr_name)
			if arr.size() != n:
				fails += 1
				print("FAIL %s.%s has %d entries for %d rules" % [id, arr_name, arr.size(), n])
		for i in n:
			if e.rule_trigger[i] < 0 or e.rule_trigger[i] > EnemyData.Trigger.EVERY_N_TURNS:
				fails += 1; print("FAIL %s rule %d has unknown trigger" % [id, i])
			if e.rule_action[i] < 0 or e.rule_action[i] > EnemyData.Action.DRAIN:
				fails += 1; print("FAIL %s rule %d has unknown action" % [id, i])
			if e.rule_trigger[i] == EnemyData.Trigger.EVERY_N_TURNS and e.rule_threshold[i] <= 0:
				fails += 1; print("FAIL %s rule %d ticks every 0 turns" % [id, i])
	if reactive < 5:
		fails += 1; print("FAIL only %d archetypes react to anything" % reactive)

	# --- every boss must have a signature, or the climax is just a big cultist ---
	for bid in Balance.ROSTER[Balance.Tier.BOSS]:
		var b := load("res://resources/enemies/%s.tres" % bid) as EnemyData
		if b == null or b.rule_count() == 0:
			fails += 1; print("FAIL boss %s has no signature behaviour" % bid)

	# --- rules fire ONLY when their condition holds ---
	var warden := load("res://resources/enemies/warden.tres") as EnemyData
	var quiet := {"self_hp": 100, "self_max_hp": 100, "player_hp": 60, "player_max_hp": 60,
		"player_block_last_turn": 0, "cards_played_last_turn": 0}
	if warden.rule_for(1, quiet, []) != -1:
		fails += 1; print("FAIL Warden sunders a player holding no Block")
	var turtled := quiet.duplicate()
	turtled["player_block_last_turn"] = 40
	if warden.rule_for(1, turtled, []) < 0:
		fails += 1; print("FAIL Warden ignores a heavily blocking player")

	# --- a once-only rule fires once ---
	var knight := load("res://resources/enemies/cinder_knight.tres") as EnemyData
	var hurt := quiet.duplicate()
	hurt["self_hp"] = 10
	var idx: int = knight.rule_for(1, hurt, [])
	if idx < 0:
		fails += 1; print("FAIL Cinder Knight does not enrage below half HP")
	elif knight.rule_for(2, hurt, [idx]) == idx:
		fails += 1; print("FAIL a once-only rule fires again after being spent")

	# --- THE telegraph must not lie ---
	#
	# The intent is chosen at the top of the player's turn and resolved at the end
	# of it. Rules therefore read the COMPLETED turn, never the one in progress —
	# otherwise blocking after seeing "hit 9" could silently turn it into a SUNDER.
	var eng = Engine_.new()
	eng.setup(_deck(), 80, 80, 3, Balance.Tier.BOSS, "warden")
	eng.start_turn()
	var told: Dictionary = eng.intents[0].duplicate()
	var told_text: String = eng.intent_text(0)
	eng.player.gain_block(60)             # player reacts AFTER seeing the intent
	eng.player.hp = 5                     # and their HP changes too
	if eng.intents[0]["action"] != told["action"] or eng.intents[0]["value"] != told["value"]:
		fails += 1; print("FAIL the telegraphed intent changed after it was shown")
	var hp_before: int = eng.player.hp
	eng.end_turn()
	# what landed must match what was promised
	if told["action"] == EnemyData.Action.SUNDER and eng.player.hp >= hp_before:
		fails += 1; print("FAIL a telegraphed SUNDER did not go through Block")
	if told_text == "?" :
		fails += 1; print("FAIL intent text has no wording for the chosen action")

	# --- SUNDER ignores Block; a normal attack does not ---
	var e1 = Engine_.new()
	e1.setup(_deck(), 80, 80, 3, Balance.Tier.BOSS, "warden")
	e1.start_turn()
	e1.intents[0] = {"action": EnemyData.Action.SUNDER, "value": 10}
	e1.player.gain_block(100)
	var before_hp: int = e1.player.hp
	e1._resolve_enemy(0)
	if e1.player.hp >= before_hp:
		fails += 1; print("FAIL SUNDER was stopped by Block")
	# At depth 1 nothing pierces, so Block is a complete answer there...
	var e2 = Engine_.new()
	e2.setup(_deck(), 80, 80, 1, Balance.Tier.BOSS, "warden")
	e2.start_turn()
	e2.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 10}
	e2.player.gain_block(100)
	var before2: int = e2.player.hp
	e2._resolve_enemy(0)
	if e2.player.hp != before2:
		fails += 1; print("FAIL a normal attack punched through Block in the first dungeon")

	# ...but deeper down a share of every hit goes straight to HP (D45), and that
	# share must still be far smaller than a SUNDER, or SUNDER stops being special.
	var e2b = Engine_.new()
	e2b.setup(_deck(), 80, 80, 8, Balance.Tier.BOSS, "warden")
	e2b.start_turn()
	e2b.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 40}
	e2b.player.gain_block(500)
	var before2b: int = e2b.player.hp
	e2b._resolve_enemy(0)
	var normal_through: int = before2b - e2b.player.hp
	if normal_through <= 0:
		fails += 1; print("FAIL nothing pierces Block at the deepest depth")
	var e2c = Engine_.new()
	e2c.setup(_deck(), 80, 80, 8, Balance.Tier.BOSS, "warden")
	e2c.start_turn()
	e2c.intents[0] = {"action": EnemyData.Action.SUNDER, "value": 40}
	e2c.player.gain_block(500)
	var before2c: int = e2c.player.hp
	e2c._resolve_enemy(0)
	var sunder_through: int = before2c - e2c.player.hp
	if sunder_through <= normal_through * 2:
		fails += 1
		print("FAIL SUNDER (%d through Block) is barely worse than a normal hit (%d)" % [
			sunder_through, normal_through])

	# --- SUNDER must TRADE damage for bypassing Block ---
	# At full damage it is strictly better than attacking, so an enemy would simply
	# always use it. Measured: block builds fell 74% -> 32% run completion.
	if Balance.SUNDER_DAMAGE_FRAC >= 1.0:
		fails += 1; print("FAIL SUNDER is not a trade: %.2f" % Balance.SUNDER_DAMAGE_FRAC)

	# --- no enemy may heal itself every single turn ---
	# A rule that both fires on a permanent condition and heals is a stalemate, not
	# pressure: deep_warden draining below 60% HP locked whole fights.
	for id2 in _all_enemy_ids():
		var ed := load("res://resources/enemies/%s.tres" % id2) as EnemyData
		if ed == null:
			continue
		for i2 in ed.rule_count():
			var permanent: bool = ed.rule_trigger[i2] == EnemyData.Trigger.SELF_HP_BELOW_PCT \
				or ed.rule_trigger[i2] == EnemyData.Trigger.PLAYER_HP_BELOW_PCT
			var heals: bool = ed.rule_action[i2] == EnemyData.Action.DRAIN
			if permanent and heals and ed._rule_field(ed.rule_once, i2, 0) != 1:
				fails += 1
				print("FAIL %s heals every turn once a lasting condition holds" % id2)

	# --- DRAIN heals the enemy, so stalling is losing ---
	var e3 = Engine_.new()
	e3.setup(_deck(), 80, 80, 3, Balance.Tier.BOSS, "deep_warden")
	e3.start_turn()
	e3.enemies[0].hp = maxi(1, e3.enemies[0].max_hp / 2)
	var foe_hp: int = e3.enemies[0].hp
	e3.intents[0] = {"action": EnemyData.Action.DRAIN, "value": 12}
	e3._resolve_enemy(0)
	if e3.enemies[0].hp <= foe_hp:
		fails += 1; print("FAIL DRAIN did not heal the enemy")

	# --- the state rules read is tracked correctly ---
	var e4 = Engine_.new()
	e4.setup(_deck(), 80, 80, 3, Balance.Tier.NORMAL, "cultist")
	e4.start_turn()
	var played := 0
	for c in e4.hand.duplicate():
		if e4.play_card(c) != "":
			played += 1
	if e4.cards_played_this_turn != played:
		fails += 1; print("FAIL cards played this turn: %d, counted %d" % [
			played, e4.cards_played_this_turn])
	var held: int = e4.player.block
	e4.end_turn()
	if e4.cards_played_last_turn != played:
		fails += 1; print("FAIL last turn's card count was not carried over")
	if e4.player_block_last_turn != held:
		fails += 1; print("FAIL the Block the enemies faced was not recorded")
	if e4.cards_played_this_turn != 0:
		fails += 1; print("FAIL the per-turn card counter did not reset")

	# --- a fight in progress survives being saved and reloaded ---
	var e5 = Engine_.new()
	e5.setup(_deck(), 80, 80, 3, Balance.Tier.BOSS, "cinder_knight")
	e5.start_turn()
	e5.enemies[0].hp = 5                      # provoke the once-only enrage
	e5._roll_intent(0)
	var state := e5.save_state()
	var e6 = Engine_.new()
	e6.load_state(state, MetaState.CATALOG, [])
	if str(e6.rules_fired) != str(e5.rules_fired):
		fails += 1; print("FAIL spent rules not persisted: %s vs %s" % [
			e6.rules_fired, e5.rules_fired])
	if e6.cards_played_last_turn != e5.cards_played_last_turn \
			or e6.player_block_last_turn != e5.player_block_last_turn:
		fails += 1; print("FAIL rule context not persisted across a save")

	if fails == 0:
		print("REACTIVE TEST: PASS (honest telegraph, conditions, boss signatures, persistence)")
	else:
		print("REACTIVE TEST: FAIL (%d)" % fails)
	quit()

func _all_enemy_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://resources/enemies/")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tres"):
			out.append(f.replace(".tres", ""))
		f = d.get_next()
	d.list_dir_end()
	return out

func _deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 5:
		deck.append(load(CARD_DIR + "hack.tres") as CardData)
		deck.append(load(CARD_DIR + "cover.tres") as CardData)
	return deck
