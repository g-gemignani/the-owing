## Headless balance simulator (D5). Auto-plays fights with a greedy policy and
## reports win rates per dungeon tier, so Balance constants can be tuned against
## measured numbers instead of guesses. Uses the real CombatEngine.
## Run: godot --headless --script tools/sim_balance.gd
extends SceneTree

const TRIALS := 400
const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	print("=== Balance report (%d trials per cell) ===" % TRIALS)
	print("RUN = full-dungeon completion with persistent HP (the metric that matters).")
	print("Per-fight rates are full-HP diagnostics only.\n")
	for profile in _profiles():
		var deck: Array[CardData] = profile["deck"]
		print("%s  (%d cards, power %.0f, avg %.1f, ratio %.2f)" % [
			profile["name"], deck.size(), Balance.deck_power(deck),
			Balance.deck_power(deck) / Balance.deck_cost(deck),
			Balance.power_ratio(deck, profile.get("relics", []))])
		for dungeon_id in profile["dungeons"]:
			var dd := Balance.dungeon(dungeon_id)
			var dungeon: int = dd.difficulty if dd != null else 1
			var roster: Array = Array(dd.enemy_roster) if dd != null and dd.has_roster() else []
			var relics: Array = profile.get("relics", [])
			var run := _measure_run(dungeon_id, deck, relics, roster)
			var line := "   %-16s d%d %-5s RUN %3.0f%% (%.1f fights, %.1f avoided) |" % [
				dd.name if dd != null else dungeon_id, dungeon,
				_kind_name(dd.traversal if dd != null else 0),
				run["complete"] * 100.0, run["avg_fights"], run["avg_avoided"]]
			for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
				var r := _measure(deck, dungeon, tier, 1.0, relics, roster)
				line += " %s %.0f%%(%.1ft,-%.0f%%hp)" % [
					_tier_short(tier), r["win_rate"] * 100.0, r["avg_turns"], r["hp_lost_pct"] * 100.0]
			print(line)
		print("")
	print("Target: RUN completion ~50-70%% at matched progression; <20%% when over-reaching.")
	quit()

## Simulate a full dungeon: walk a random path through the real generated map,
## fighting with persistent HP, resting where offered. Returns completion rate.
## Simulate complete runs of a dungeon, driving the real Traversal model directly.
## Because Traversal is pure logic, ONE walker measures every model — a per-model
## walker would be the first thing to rot when a new model is added.
func _measure_run(dungeon_id: String, deck: Array[CardData], relics: Array = [],
		roster: Array = []) -> Dictionary:
	var dd := Balance.dungeon(dungeon_id)
	var difficulty: int = dd.difficulty if dd != null else 1
	var completed := 0
	var fights_total := 0
	var avoided_total := 0
	for t in TRIALS:
		var tv := Traversal.make(dd.traversal if dd != null else Traversal.Kind.GRAPH)
		tv.generate(dd)
		var relic_hp := 0
		for r in relics:
			relic_hp += r.bonus_max_hp
		var max_hp := Balance.BASE_MAX_HP + relic_hp + (difficulty - 1) * Balance.HP_PER_DUNGEON
		var hp := max_hp
		var gold := 0
		var alive := true
		var fights := 0
		var guard := 0
		while alive and not tv.is_complete() and guard < 60:
			guard += 1
			var opts := tv.options()
			if opts.is_empty():
				break
			var pick := _choose_option(opts, hp, max_hp)
			var cost := int(opts[pick].get("hp_cost", 0))
			var node := tv.select(pick)
			if node.is_empty():
				# an option resolved internally (e.g. paying HP to avoid an encounter)
				hp = maxi(1, hp - cost)
				avoided_total += 1
				continue
			match int(node["type"]):
				Traversal.Enc.REST:
					hp = min(max_hp, hp + int(max_hp * Balance.REST_HEAL_FRAC))
					tv.clear_pending()
				Traversal.Enc.TREASURE:
					gold += Balance.TREASURE_GOLD_MIN + randi() % maxi(1,
						Balance.TREASURE_GOLD_MAX - Balance.TREASURE_GOLD_MIN + 1)
					tv.clear_pending()
				Traversal.Enc.EVENT:
					# HP/gold effects only. Card and relic grants are skipped: they
					# would mutate the very deck this profile is measuring.
					var res := _sim_event(hp, max_hp, gold)
					hp = int(res["hp"])
					gold = int(res["gold"])
					tv.clear_pending()
				Traversal.Enc.SHOP:
					var hprice := Balance.heal_price(max_hp)
					if gold >= hprice and hp < max_hp:
						gold -= hprice
						hp = min(max_hp, hp + Balance.heal_amount(max_hp))
					tv.clear_pending()
				_:
					var tier := _tier_of_enc(int(node["type"]))
					var eng := CombatEngine.new()
					eng.setup(deck, hp, max_hp, difficulty, tier, "", relics, roster)
					var g2 := 0
					while not eng.over() and g2 < 200:
						g2 += 1
						_take_turn(eng)
						if eng.over():
							break
						eng.end_turn()
					fights += 1
					if eng.lost():
						alive = false
					else:
						hp = eng.player.hp
						gold += Balance.gold_reward(difficulty, tier, randi() % 6)
						tv.clear_pending()
		fights_total += fights
		if alive and tv.is_complete():
			completed += 1
	return {
		"complete": float(completed) / TRIALS,
		"avg_fights": float(fights_total) / TRIALS,
		"avg_avoided": float(avoided_total) / TRIALS,
	}

## Route policy: rest when hurt, avoid a fight when badly hurt and it is offered.
## Resolve an event the way a reasonable player would: take the cheapest option
## that does not cost HP if one exists, else accept the HP cost.
func _sim_event(hp: int, max_hp: int, gold: int) -> Dictionary:
	var pool := Balance.EVENTS
	var e := load(Balance.EVENT_DIR + pool[randi() % pool.size()] + ".tres") as EventData
	if e == null or e.choice_count() == 0:
		return {"hp": hp, "gold": gold}
	var best := -1
	var best_cost := 1 << 30
	for i in e.choice_count():
		if gold + e.gold_delta(i) < 0:
			continue
		var hp_cost: int = -(e.hp_delta(i) + int(round(max_hp * e.hp_percent(i) / 100.0)))
		if hp_cost < best_cost:
			best_cost = hp_cost
			best = i
	if best < 0:
		return {"hp": hp, "gold": gold}
	var dh: int = e.hp_delta(best) + int(round(max_hp * e.hp_percent(best) / 100.0))
	return {
		"hp": clampi(hp + dh, 1, max_hp),
		"gold": maxi(0, gold + e.gold_delta(best)),
	}

func _choose_option(opts: Array, hp: int, max_hp: int) -> int:
	var frac := float(hp) / float(maxi(1, max_hp))
	# take a rest or shop if it is on offer and we are damaged
	for i in opts.size():
		var t := int(opts[i].get("type", 0))
		if t == Traversal.Enc.TREASURE:
			return i   # free value, always worth landing on
		if frac < 0.6 and (t == Traversal.Enc.REST or t == Traversal.Enc.SHOP):
			return i
	# badly hurt: pay HP to skip a fight rather than risk it
	if frac < 0.35:
		for i in opts.size():
			if opts[i].has("hp_cost") and int(opts[i]["hp_cost"]) < hp - 5:
				return i
	# otherwise prefer facing it, choosing randomly among non-avoid options
	var faceable: Array = []
	for i in opts.size():
		if not opts[i].has("hp_cost"):
			faceable.append(i)
	if faceable.is_empty():
		return 0
	return int(faceable[randi() % faceable.size()])

func _kind_name(kind: int) -> String:
	match kind:
		Traversal.Kind.DECK: return "deck"
		Traversal.Kind.DICE: return "dice"
		_: return "graph"

func _tier_of_enc(enc: int) -> int:
	if enc == Traversal.Enc.ELITE:
		return Balance.Tier.ELITE
	elif enc == Traversal.Enc.BOSS:
		return Balance.Tier.BOSS
	return Balance.Tier.NORMAL

func _tier_for(GS, node_type: int) -> int:
	if node_type == GS.NodeType.ELITE:
		return Balance.Tier.ELITE
	elif node_type == GS.NodeType.BOSS:
		return Balance.Tier.BOSS
	return Balance.Tier.NORMAL

func _tier_short(tier: int) -> String:
	match tier:
		Balance.Tier.ELITE: return "E"
		Balance.Tier.BOSS: return "B"
		_: return "N"

## Player profiles: representative decks at different progression stages.
func _profiles() -> Array:
	var out: Array = []

	out.append({
		"name": "Starter (fresh run)",
		"deck": _deck({"strike": 4, "defend": 4}),
		"dungeons": ["crypt", "ossuary", "warrens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Early (rewards added)",
		"deck": _deck({"strike": 5, "defend": 4, "bash": 2, "iron_wave": 2}),
		"dungeons": ["crypt", "warrens", "foundry"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Mid (fused Lv15)",
		"deck": _deck({"strike": 5, "defend": 4, "bash": 3, "iron_wave": 3, "clear_mind": 2}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Status build (Lv15)",
		"deck": _deck({"strike": 5, "defend": 4, "bash": 2, "terrify": 2, "inflame": 2, "footwork": 1}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Barricade build (Lv15, legend Lv5)",
		"deck": _deck({"strike": 5, "defend": 6, "footwork": 2, "iron_wave": 3}, 15) + _deck({"barricade": 1}, 5),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Poison build (Lv15)",
		"deck": _deck({"strike": 3, "defend": 4, "venom_fang": 3, "rupture": 3, "noxious_cloud": 1, "smoke_bomb": 2}, 15),
		"dungeons": ["fungal_deep", "rot_gardens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "AoE build (Lv15)",
		"deck": _deck({"strike": 2, "defend": 4, "cleave": 3, "whirlwind": 2, "hex": 1, "shrug_it_off": 3}, 15),
		"dungeons": ["rot_gardens", "drowned_market"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Thorns build (Lv15)",
		"deck": _deck({"strike": 3, "defend": 4, "riposte": 3, "caltrops": 2, "juggernaut": 1, "iron_will": 2, "survival_instinct": 2}, 15),
		"dungeons": ["slag_pits", "abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Maxed commons (Lv100)",
		"deck": _deck({"strike": 8, "defend": 8, "iron_wave": 4}, 100),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Relic build (Lv15 + 4 relics)",
		"deck": _deck({"strike": 5, "defend": 5, "bash": 3, "iron_wave": 3}, 15),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "ancient_battery"]),
	})
	out.append({
		"name": "Late (Lv40 + 6 relics)",
		"deck": _deck({"strike": 4, "defend": 4, "bash": 3, "iron_wave": 3, "heavy_blade": 3,
			"shrug_it_off": 3}, 40),
		"dungeons": ["drowned_market", "abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "giants_marrow",
			"bulwark_plate", "eternal_furnace"]),
	})
	out.append({
		# Deliberately the SAME deck as "Late" at a higher level with a superset of
		# its relics: a strictly stronger loadout, so its win rate must not be lower.
		"name": "Endgame (Late deck, Lv100)",
		"deck": _deck({"strike": 4, "defend": 4, "bash": 3, "iron_wave": 3, "heavy_blade": 3,
			"shrug_it_off": 3}, 100),
		"dungeons": ["abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "giants_marrow",
			"bulwark_plate", "eternal_furnace", "warlords_banner"]),
	})
	out.append({
		"name": "Deep (fused Lv40)",
		"deck": _deck({"strike": 6, "defend": 5, "bash": 4, "iron_wave": 3, "clear_mind": 2}, 40),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	return out

func _relics(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var r := load(Balance.RELIC_DIR + id + ".tres") as RelicData
		if r != null:
			out.append(r)
	return out

func _deck(loadout: Dictionary, level: int = 1) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			var c := (load(CARD_DIR + id + ".tres") as CardData).duplicate()
			c.level = level
			deck.append(c)
	return deck

func _measure(deck: Array[CardData], dungeon: int, tier: int, hp_mult: float,
		relics: Array = [], roster: Array = []) -> Dictionary:
	var wins := 0
	var turns_total := 0
	var hp_lost_total := 0
	var max_hp := int((Balance.BASE_MAX_HP + (dungeon - 1) * Balance.HP_PER_DUNGEON) * hp_mult)
	for t in TRIALS:
		var eng := CombatEngine.new()
		eng.setup(deck, max_hp, max_hp, dungeon, tier, "", relics, roster)
		var guard := 0
		while not eng.over() and guard < 200:
			guard += 1
			_take_turn(eng)
			if eng.over():
				break
			eng.end_turn()
		if eng.won():
			wins += 1
		turns_total += eng.turn
		hp_lost_total += max_hp - eng.player.hp
	return {
		"win_rate": float(wins) / TRIALS,
		"avg_turns": float(turns_total) / TRIALS,
		# HP lost as a fraction of max: if this is ~0, attrition is broken and
		# individual fights are meaningless regardless of win rate.
		"hp_lost_pct": float(hp_lost_total) / TRIALS / max_hp,
	}

## Greedy policy: finish the enemy if possible; otherwise block when the
## Turn policy, modelled on how a competent player actually sequences a turn:
## powers first (they pay off every later turn), then finish the enemy if lethal
## is available, then buy off the incoming hit with block, then convert whatever
## energy is left into damage or a debuff.
func _take_turn(eng: CombatEngine) -> void:
	_pick_target(eng)
	_play_powers(eng)
	_play_draw(eng)
	if _try_lethal(eng):
		return
	_block_incoming(eng)
	_spend_rest(eng)

## Focus-fire the enemy closest to death: every kill permanently removes its
## share of incoming damage, which matters far more than spreading damage.
func _pick_target(eng: CombatEngine) -> void:
	var best := -1
	var best_hp := 1 << 30
	for i in eng.enemies.size():
		var e: Combatant = eng.enemies[i]
		if e.is_dead():
			continue
		if e.hp < best_hp:
			best_hp = e.hp
			best = i
	if best >= 0:
		eng.set_target(best)

func _play_powers(eng: CombatEngine) -> void:
	var again := true
	while again and not eng.over():
		again = false
		for c in eng.hand.duplicate():
			if eng.can_play(c) and (c.retain_block or c.eff_strength() > 0 or c.eff_dexterity() > 0):
				eng.play_card(c); again = true; break

func _play_draw(eng: CombatEngine) -> void:
	var again := true
	while again and not eng.over():
		again = false
		for c in eng.hand.duplicate():
			if eng.can_play(c) and c.draw > 0:
				eng.play_card(c); again = true; break

## True if the enemy can be killed with the energy in hand this turn.
func _try_lethal(eng: CombatEngine) -> bool:
	var total := 0
	var budget := eng.energy
	var plan: Array[CardData] = []
	# greedy by damage per energy
	var pool := eng.hand.duplicate()
	pool.sort_custom(func(a, b):
		return float(a.eff_damage()) / maxf(1.0, a.cost) > float(b.eff_damage()) / maxf(1.0, b.cost))
	for c in pool:
		if c.eff_damage() > 0 and c.cost <= budget:
			budget -= c.cost
			plan.append(c)
			var foe0 := eng.current_target()
			if foe0 != null:
				total += foe0.predicted_damage(eng.player.outgoing_damage(c.eff_damage()))
	var foe := eng.current_target()
	if foe == null or total < foe.hp:
		return false
	for c in plan:
		if eng.over():
			break
		eng.play_card(c)
	return eng.over()

## Spend block cards until the incoming hit is (nearly) neutralized. With a
## retain_block power, bank a cushion instead but stop before stalling the fight.
func _block_incoming(eng: CombatEngine) -> void:
	# Eat small hits: spending a whole card to prevent a trivial amount of damage
	# is worse than landing that damage on the enemy.
	var tolerance := 0.08 * eng.player.max_hp
	var target := 0
	if eng.player.retain_block:
		target = 2 * eng.enemy_intent
		tolerance = 0.0
	var again := true
	while again and not eng.over():
		again = false
		var incoming := eng.player.predicted_damage(eng.enemy.outgoing_damage(eng.enemy_intent))
		if incoming <= tolerance and eng.player.block >= target:
			return
		# Weak cuts every future enemy hit, so against a real threat it beats
		# blocking a single one. (Pure-debuff cards have no damage/block and would
		# otherwise never be selected at all.)
		for c in eng.hand.duplicate():
			if eng.can_play(c) and c.eff_weak() > 0 and eng.enemy.weak == 0 and incoming > tolerance:
				eng.play_card(c); again = true; break
		if again:
			continue
		var best := _best_by_value(eng, false)
		if best != null:
			eng.play_card(best); again = true

## Convert leftover energy into damage, or into a Vulnerable setup if that is
## worth more than a single hit (only when the enemy will survive the turn).
func _spend_rest(eng: CombatEngine) -> void:
	var again := true
	while again and not eng.over():
		again = false
		for c in eng.hand.duplicate():
			if eng.can_play(c) and c.eff_vulnerable() > 0 and eng.enemy.vulnerable == 0 \
					and eng.enemy.hp > eng.player.outgoing_damage(c.eff_damage()) * 2:
				eng.play_card(c); again = true; break
		if again:
			continue
		var best := _best_by_value(eng, true)
		if best != null:
			eng.play_card(best); again = true
			continue
		# nothing to attack with: bank block if any remains affordable
		var blk := _best_by_value(eng, false)
		if blk != null:
			eng.play_card(blk); again = true

## Best affordable card by (damage or block) per energy spent.
func _best_by_value(eng: CombatEngine, want_damage: bool) -> CardData:
	var best: CardData = null
	var best_val := 0.0
	for c in eng.hand:
		if not eng.can_play(c):
			continue
		var amount: int = c.eff_damage() if want_damage else c.eff_block()
		if amount <= 0:
			continue
		var val := float(amount) / maxf(1.0, float(c.cost))
		if val > best_val:
			best_val = val
			best = c
	return best
