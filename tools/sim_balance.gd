## Headless balance simulator (D5). Auto-plays fights with a greedy policy and
## reports win rates per dungeon tier, so Balance constants can be tuned against
## measured numbers instead of guesses. Uses the real CombatEngine.
## Run: godot --headless --script tools/sim_balance.gd
extends SceneTree

## Trials per cell. Overridable for iteration — a tuning pass needs many runs of
## the report and one at full precision, not fifteen at full precision:
##     godot --headless --script tools/sim_balance.gd -- --trials=120
const DEFAULT_TRIALS := 400
static var TRIALS := DEFAULT_TRIALS

static func _read_trials() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			TRIALS = maxi(10, int(arg.substr(9)))
const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	_read_trials()
	print("=== Balance report (%d trials per cell) ===" % TRIALS)
	print("RUN = full-dungeon completion with persistent HP (the metric that matters).")
	print("Per-fight rates are full-HP diagnostics only.\n")
	for profile in _profiles():
		var deck: Array[CardData] = profile["deck"]
		var prof_power := _power_of(profile)
		var relic_hp0 := 0
		for r0 in profile.get("relics", []):
			relic_hp0 += r0.bonus_max_hp
		print("%s  (%d cards, ratio %.2f, %d clears, %d HP, %d relics, power %s)" % [
			profile["name"], deck.size(),
			Balance.power_ratio(deck, profile.get("relics", []), prof_power),
			int(profile.get("clears", 0)),
			Balance.max_hp_for(int(profile.get("clears", 0)), relic_hp0),
			(profile.get("relics", []) as Array).size(),
			prof_power.name if prof_power != null else "none"])
		for dungeon_id in profile["dungeons"]:
			var dd := Balance.dungeon(dungeon_id)
			var dungeon: int = dd.difficulty if dd != null else 1
			var roster: Array = Array(dd.enemy_roster) if dd != null and dd.has_roster() else []
			var relics: Array = profile.get("relics", [])
			# You cannot be standing in the Maw without having cleared the eight things
			# that open it, so the profile's figure is a FLOOR and the dungeon's own
			# gate is the other half — derived, because a number restated per cell goes
			# stale the first time a zone requirement moves.
			var clears: int = maxi(int(profile.get("clears", 0)),
				Balance.effective_gate(dungeon_id))
			var run := _measure_run(dungeon_id, deck, relics, roster, Policy.SMART,
				TRIALS, clears, _power_of(profile))
			var relic_hp1 := 0
			for r1 in relics:
				relic_hp1 += r1.bonus_max_hp
			var line := "   %-16s d%d %-5s %3dhp RUN %3.0f%% (%.1f fights, %.1f avoided) |" % [
				dd.name if dd != null else dungeon_id, dungeon,
				_kind_name(dd.traversal if dd != null else 0),
				Balance.max_hp_for(clears, relic_hp1),
				run["complete"] * 100.0, run["avg_fights"], run["avg_avoided"]]
			for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
				var r := _measure(deck, dungeon, tier, 1.0, relics, roster, prof_power)
				line += " %s %.0f%%(%.1ft,-%.0f%%hp)" % [
					_tier_short(tier), r["win_rate"] * 100.0, r["avg_turns"], r["hp_lost_pct"] * 100.0]
			print(line)
		print("")
	print("Target: RUN completion ~50-70%% at matched progression; <20%% when over-reaching.")
	_avoid_calibration()
	quit()

## Is paying HP to skip a fight priced, or is it a cheat?
##
## The deck model's whole decision is face-or-dodge, and it went unmeasured for its
## entire existence because the driver only dodged below 35% HP — which a greedy
## player almost never sits at. So the three lines of play are now measured against
## each other. The property that matters is D20's: **a dominant strategy is a
## removed decision.** If ALWAYS-AVOID clears more often than SMART, the price is
## wrong; if it clears far less, dodging is decoration.
const CALIBRATION_TRIALS := 150

func _avoid_calibration() -> void:
	print("\n=== Avoid calibration (%d trials per cell) ===" % CALIBRATION_TRIALS)
	print("Deck dungeons only — the other models have nothing to dodge.")
	print("A price is right when SMART >= both fixed lines of play.\n")
	for profile in _profiles():
		var deck: Array[CardData] = profile["deck"]
		for dungeon_id in profile["dungeons"]:
			var dd := Balance.dungeon(dungeon_id)
			if dd == null or dd.traversal != Traversal.Kind.DECK:
				continue
			var roster: Array = Array(dd.enemy_roster) if dd.has_roster() else []
			var relics: Array = profile.get("relics", [])
			var cells: Array = []
			for mode in [Policy.ALWAYS_FACE, Policy.SMART, Policy.ALWAYS_AVOID]:
				cells.append(_measure_run(dungeon_id, deck, relics, roster, mode,
					CALIBRATION_TRIALS, maxi(int(profile.get("clears", 0)),
						Balance.effective_gate(dungeon_id)), _power_of(profile)))
			print("   %-18s %-24s face %3.0f%% | smart %3.0f%% (%2.0f%% dodged) | avoid %3.0f%% (%2.0f%% dodged)" % [
				dd.name, profile["name"],
				cells[0]["complete"] * 100.0,
				cells[1]["complete"] * 100.0, cells[1]["avoid_rate"] * 100.0,
				cells[2]["complete"] * 100.0, cells[2]["avoid_rate"] * 100.0])
			if cells[2]["complete"] > cells[1]["complete"] + 0.05:
				print("      ^ ALWAYS-AVOID beats the smart line: the dodge is underpriced")

## Simulate a full dungeon: walk a random path through the real generated map,
## fighting with persistent HP, resting where offered. Returns completion rate.
## Simulate complete runs of a dungeon, driving the real Traversal model directly.
## Because Traversal is pure logic, ONE walker measures every model — a per-model
## walker would be the first thing to rot when a new model is added.
func _measure_run(dungeon_id: String, deck: Array[CardData], relics: Array = [],
		roster: Array = [], mode: int = Policy.SMART, trials: int = TRIALS,
		clears: int = 0, power: PowerData = null) -> Dictionary:
	var dd := Balance.dungeon(dungeon_id)
	var difficulty: int = dd.difficulty if dd != null else 1
	var completed := 0
	var fights_total := 0
	var avoided_total := 0
	var avoidable_total := 0
	# What fights here have been costing, learned across the trials of this cell and
	# carried between them: a player who has walked this dungeon before knows.
	var cost_est := {}
	var cost_n := {}
	for t in trials:
		var tv := Traversal.make(dd.traversal if dd != null else Traversal.Kind.GRAPH)
		tv.generate(dd)
		var relic_hp := 0
		for r in relics:
			relic_hp += r.bonus_max_hp
		# The same formula the game uses, from the same place. This restated it as
		# "(difficulty - 1) x HP_PER_DUNGEON", but the game grows max HP with
		# dungeons CLEARED — so a player with six clears at the Crypt has 120 HP
		# where the sim gave them 60, and the whole opening of the game was reported
		# as about twice as dangerous as it is. `clears` is now part of the profile:
		# how far along the player is, not how deep the dungeon is.
		var max_hp := Balance.max_hp_for(clears, relic_hp)
		var hp := max_hp
		var gold := 0
		# The deck GROWS during a run. A real player takes a card at nearly every
		# encounter (D1), so by the boss their deck is five to eight cards bigger
		# than the one they walked in with — and the sim fought the finale with the
		# opening deck, all run, every run. That is the single biggest reason it
		# reported bosses as deadlier than they play.
		var run_deck: Array[CardData] = []
		for c0 in deck:
			run_deck.append(c0)
		var reward_level := 1
		for c1 in deck:
			reward_level = maxi(reward_level, c1.level)
		var alive := true
		var fights := 0
		var guard := 0
		while alive and not tv.is_complete() and guard < 60:
			guard += 1
			var opts := tv.options()
			if opts.is_empty():
				break
			for o in opts:
				if String(o.get("action", "")) == "avoid":
					avoidable_total += 1
					break
			var pick := _choose_option(opts, hp, max_hp, cost_est, mode)
			var cost := int(opts[pick].get("hp_cost", 0))
			var was_dodge := String(opts[pick].get("action", "")) == "avoid"
			var node := tv.select(pick)
			# EVERY priced option is paid for, not only the ones that resolve nothing.
			# The iso model charges HP for a step taken after the torch has burnt out,
			# and that step still hands back the encounter in the room it led to —
			# paying only on an empty result measured walking in the dark as free.
			# `avoidable`/`avoided` count dodges specifically, which is what the
			# calibration below reports; a step across explored ground is not one.
			if cost > 0:
				hp = maxi(1, hp - cost)
			if node.is_empty():
				if was_dodge:
					avoided_total += 1
				continue
			match int(node["type"]):
				Traversal.Enc.REST:
					hp = min(max_hp, hp + int(max_hp * Balance.REST_HEAL_FRAC))
					tv.clear_pending()
				Traversal.Enc.TREASURE:
					gold += Balance.TREASURE_GOLD_MIN + randi() % maxi(1,
						Balance.TREASURE_GOLD_MAX - Balance.TREASURE_GOLD_MIN + 1)
					if randi() % 100 < Balance.TREASURE_CARD_CHANCE:
						var found := _reward_card(dungeon_id, reward_level)
						if found != null:
							run_deck.append(found)
					tv.clear_pending()
				Traversal.Enc.EVENT:
					# HP/gold effects only. Card and relic grants are skipped: they
					# would mutate the very deck this profile is measuring.
					var res := _sim_event(hp, max_hp, gold)
					hp = int(res["hp"])
					gold = int(res["gold"])
					tv.clear_pending()
				Traversal.Enc.SHOP:
					# the simulator must price the shop the way the shop does, or the
					# HP curve it reports is measured against a different economy
					var hprice := Balance.heal_price(max_hp, difficulty)
					if gold >= hprice and hp < max_hp:
						gold -= hprice
						hp = min(max_hp, hp + Balance.heal_amount(max_hp))
					tv.clear_pending()
				_:
					var tier := _tier_of_enc(int(node["type"]))
					var enc_kind := int(node["type"])
					var hp_before := hp
					var eng := CombatEngine.new()
					# power AND named boss, both of which the sim used to omit: every
					# player carries an ability firable once a turn, and every dungeon
					# ends on its own boss rather than a roster enemy with boss
					# multipliers (D41). Leaving them out measured a weaker player
					# against a different finale.
					eng.setup(run_deck, hp, max_hp, difficulty, tier, "", relics, roster,
						power, dd.boss if dd != null else "")
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
						var nd: int = int(cost_n.get(enc_kind, 0)) + 1
						var pd: float = float(cost_est.get(enc_kind, 0.0))
						cost_est[enc_kind] = pd + (float(hp_before) - pd) / float(nd)
						cost_n[enc_kind] = nd
					else:
						hp = eng.player.hp
						# the driver's only source of "what does a fight here cost me"
						var n: int = int(cost_n.get(enc_kind, 0)) + 1
						var prev: float = float(cost_est.get(enc_kind, 0.0))
						cost_est[enc_kind] = prev + (float(hp_before - hp) - prev) / float(n)
						cost_n[enc_kind] = n
						gold += Balance.gold_reward(difficulty, tier, randi() % 6)
						var won_card := _reward_card(dungeon_id, reward_level)
						if won_card != null:
							run_deck.append(won_card)
						tv.clear_pending()
		fights_total += fights
		if alive and tv.is_complete():
			completed += 1
	return {
		"complete": float(completed) / float(trials),
		"avg_fights": float(fights_total) / float(trials),
		"avg_avoided": float(avoided_total) / float(trials),
		# of the encounters that COULD be dodged, how many were: 0.0 here for a whole
		# report is the signal that the driver is ignoring the mechanic again
		"avoid_rate": float(avoided_total) / float(maxi(1, avoidable_total)),
	}

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

## Route policy.
##
## The old version reached for Avoid only below 35% HP, and measured **0.0 avoids
## per run in every profile** — so the deck model's entire decision (face this
## encounter, or pay HP to skip it and forfeit the loot) was never exercised, and
## `DECK_AVOID_HP_COST` had never been calibrated against anything. That is the
## same class of blind spot as the pure-debuff cards the sim never played and the
## poison-only cards it could not value: a mechanic the driver ignores reads as a
## mechanic that does not matter.
##
## A player does not decide this on a percentage. They decide it on *what fights
## have been costing them*: dodge when the fight is dearer than the dodge, and eat
## the dodge when the fight might kill. `cost_est` is exactly that knowledge —
## running average HP lost per encounter type, learned across the trials of this
## cell, which is the same thing as a player who has been here before.
##
## `mode` exists so the tool can measure the two degenerate lines of play as well:
## if "always_avoid" beats "smart", the price is a cheat and the mechanic is broken
## in the D20 sense (a dominant strategy is a removed decision).
enum Policy { SMART, ALWAYS_FACE, ALWAYS_AVOID }

## Only dodge a fight that costs meaningfully more than the dodge: the loot, and
## the gold that buys healing later, is worth some HP. 1.0 would dodge on a tie.
const FACE_BIAS := 1.35
## A fight whose *average* cost is this close to what is left is a coin flip, and
## paying a known price beats rolling for it.
const LETHAL_MARGIN := 1.6

func _choose_option(opts: Array, hp: int, max_hp: int, cost_est: Dictionary,
		mode: int = Policy.SMART) -> int:
	var frac := float(hp) / float(maxi(1, max_hp))
	# take a rest or shop if it is on offer and we are damaged
	for i in opts.size():
		var t := int(opts[i].get("type", 0))
		if t == Traversal.Enc.TREASURE:
			return i   # free value, always worth landing on
		if frac < 0.6 and (t == Traversal.Enc.REST or t == Traversal.Enc.SHOP):
			return i

	# A dodge, not merely a priced option: the iso model prices MOVEMENT once its
	# torch is out, and this policy is about declining a fight.
	var avoid := -1
	for i in opts.size():
		if String(opts[i].get("action", "")) == "avoid":
			avoid = i
	if avoid >= 0:
		var cost := int(opts[avoid]["hp_cost"])
		var affordable := cost < hp        # never pay a price that kills you
		var enc := int(opts[avoid].get("type", 0))
		var expected: float = float(cost_est.get(enc, -1.0))
		match mode:
			Policy.ALWAYS_AVOID:
				if affordable:
					return avoid
			Policy.ALWAYS_FACE:
				pass
			_:
				if affordable and expected >= 0.0:
					if expected * LETHAL_MARGIN >= float(hp):
						return avoid          # facing this might end the run
					if expected > float(cost) * FACE_BIAS:
						return avoid          # the dodge is simply cheaper

	# otherwise face it, choosing randomly among the non-avoid options
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
		Traversal.Kind.ISO: return "iso"
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
		"clears": 0, "power_level": 1,
		"deck": _deck({"strike": 4, "defend": 4}),
		"dungeons": ["crypt", "ossuary", "warrens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Early (rewards added)",
		"clears": 1, "power_level": 1,
		"deck": _deck({"strike": 5, "defend": 4, "bash": 2, "iron_wave": 2}),
		"dungeons": ["crypt", "warrens", "foundry"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Mid (fused Lv15)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"strike": 5, "defend": 4, "bash": 3, "iron_wave": 3, "clear_mind": 2}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Status build (Lv15)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"strike": 5, "defend": 4, "bash": 2, "terrify": 2, "inflame": 2, "footwork": 1}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Barricade build (Lv15, legend Lv5)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"strike": 5, "defend": 6, "footwork": 2, "iron_wave": 3}, 15) + _deck({"barricade": 1}, 5),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Poison build (Lv15)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"strike": 3, "defend": 4, "venom_fang": 3, "rupture": 3, "noxious_cloud": 1, "smoke_bomb": 2}, 15),
		"dungeons": ["fungal_deep", "rot_gardens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "AoE build (Lv15)",
		"clears": 5, "power_level": 2,
		"deck": _deck({"strike": 2, "defend": 4, "cleave": 3, "whirlwind": 2, "hex": 1, "shrug_it_off": 3}, 15),
		"dungeons": ["rot_gardens", "drowned_market"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Thorns build (Lv15)",
		"clears": 5, "power_level": 2,
		"deck": _deck({"strike": 3, "defend": 4, "riposte": 3, "caltrops": 2, "juggernaut": 1, "iron_will": 2, "survival_instinct": 2}, 15),
		"dungeons": ["slag_pits", "abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Maxed commons (Lv100)",
		"clears": 6, "power_level": 3,
		"deck": _deck({"strike": 8, "defend": 8, "iron_wave": 4}, 100),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Relic build (Lv15 + 4 relics)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"strike": 5, "defend": 5, "bash": 3, "iron_wave": 3}, 15),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "ancient_battery"]),
	})
	out.append({
		"name": "Late (Lv40 + 6 relics)",
		"clears": 8, "power_level": 3,
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
		"clears": 10, "power_level": 4,
		"deck": _deck({"strike": 4, "defend": 4, "bash": 3, "iron_wave": 3, "heavy_blade": 3,
			"shrug_it_off": 3}, 100),
		"dungeons": ["abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "giants_marrow",
			"bulwark_plate", "eternal_furnace", "warlords_banner"]),
	})
	out.append({
		"name": "Deep (fused Lv40)",
		"clears": 6, "power_level": 3,
		"deck": _deck({"strike": 6, "defend": 5, "bash": 4, "iron_wave": 3, "clear_mind": 2}, 40),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	return out

## One reward card from this dungeon's pool, at the level the player's cards sit at.
## Rarity is tilted by depth exactly as the reward screen tilts it.
func _reward_card(dungeon_id: String, level: int) -> CardData:
	var dd := Balance.dungeon(dungeon_id)
	var pool: Array = Balance.card_pool_for(dungeon_id)
	if pool.is_empty():
		return null
	var wtbl: Array = Balance.reward_weights(Balance.Tier.NORMAL,
		dd.difficulty if dd != null else 1)
	var loaded: Array = []
	var weights: Array = []
	var total := 0
	for id in pool:
		var c := load(CARD_DIR + id + ".tres") as CardData
		if c == null:
			continue
		loaded.append(c)
		var w: int = wtbl[clampi(c.rarity, 0, wtbl.size() - 1)]
		weights.append(w)
		total += w
	if loaded.is_empty():
		return null
	var roll := randi() % maxi(1, total)
	for i in loaded.size():
		roll -= int(weights[i])
		if roll < 0:
			var pick := (loaded[i] as CardData).duplicate() as CardData
			pick.level = level
			return pick
	var last := (loaded[loaded.size() - 1] as CardData).duplicate() as CardData
	last.level = level
	return last

## The ability the player carries. Every save has one — the starter kit grants
## Bulwark — and the sim measured runs without it: less throughput than the player
## has, and a lower ratio than they are scaled against.
func _power_of(profile: Dictionary) -> PowerData:
	var id := String(profile.get("power", "bulwark"))
	if id == "":
		return null
	var pd := Balance.power(id)
	if pd == null:
		return null
	pd = pd.duplicate()
	pd.level = int(profile.get("power_level", 1))
	return pd

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
		relics: Array = [], roster: Array = [], power: PowerData = null) -> Dictionary:
	var wins := 0
	var turns_total := 0
	var hp_lost_total := 0
	var max_hp := int(Balance.max_hp_for(dungeon - 1) * hp_mult)
	for t in TRIALS:
		var eng := CombatEngine.new()
		eng.setup(deck, max_hp, max_hp, dungeon, tier, "", relics, roster, power)
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
