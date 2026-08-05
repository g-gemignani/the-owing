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

## Narrowing, for when the thing being retuned is ONE cell.
##
## The avoid calibration is most of a full run's wall clock, and a price is tuned by
## changing a constant and measuring again. Without a way to ask for one dungeon at a
## time that loop is the whole report, which in practice means the constant gets guessed
## instead — and guessing at prices is what D57 was.
##
##     -- --only=fungal_deep --profile=poison --calibration-only --cal-trials=600
static var ONLY := ""       ## comma-separated dungeon ids; empty = all
static var PROFILE := ""    ## substring of a profile name, case-insensitive
static var REPORT := true   ## --calibration-only turns the per-cell report off
static var CAL_TRIALS := CALIBRATION_TRIALS
## Which ROUTE through a floor the driver walks (D179). `--explore` makes it strip the floor
## — take every optional thing before the stairs — instead of getting on with the dungeon.
##
## A walker counts moves; only the simulator can say what those moves cost in HP and clear
## rate, so the two routes need to be playable HERE and not only in `tests/test_traversal.gd`.
## The flag exists before there is much to explore on purpose: it establishes the baseline
## gap between the two routes for the game as it stands, which is the only number a later
## feature's effect can be measured against.
static var EXPLORE := false

static func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			TRIALS = maxi(10, int(arg.substr(9)))
		elif arg.begins_with("--cal-trials="):
			CAL_TRIALS = maxi(10, int(arg.substr(13)))
		elif arg.begins_with("--only="):
			ONLY = arg.substr(7)
		elif arg.begins_with("--profile="):
			PROFILE = arg.substr(10).to_lower()
		elif arg == "--calibration-only":
			REPORT = false
		# Walk the floor for everything on it rather than for the way down (D179). A route
		# policy and not a narrowing: every cell is still measured, by a different player.
		elif arg == "--explore":
			EXPLORE = true

## Filters are ADDITIVE narrowings of the full report, never a different measurement:
## every cell they let through is measured exactly as it would be in a full run.
static func _wanted(dungeon_id: String, profile_name: String) -> bool:
	if ONLY != "" and not (dungeon_id in ONLY.split(",")):
		return false
	if PROFILE != "" and profile_name.to_lower().find(PROFILE) == -1:
		return false
	return true

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	_read_args()
	if not REPORT:
		_avoid_calibration()
		_print_budget()
		quit()
		return
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
			if not _wanted(dungeon_id, String(profile["name"])):
				continue
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
			var line := "   %-16s d%d %3dhp RUN %3.0f%% (%.1f fights, %.1f avoided) |" % [
				dd.name if dd != null else dungeon_id, dungeon,
				Balance.max_hp_for(clears, relic_hp1),
				run["complete"] * 100.0, run["avg_fights"], run["avg_avoided"]]
			for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
				var r := _measure(deck, dungeon, tier, 1.0, relics, roster, prof_power)
				line += " %s %.0f%%(%.1ft,-%.0f%%hp)" % [
					_tier_short(tier), r["win_rate"] * 100.0, r["avg_turns"], r["hp_lost_pct"] * 100.0]
			print(line)
		print("")
	print("Target: RUN completion ~50-70%% at matched progression; <20%% when over-reaching.")
	# Said out loud, because a report that does not name its route is a report whose numbers
	# cannot be compared with another one (D179). Two runs of this tool differ by a mean of
	# 0.4 points already (D120); a route change is a much larger difference wearing the same
	# clothes, and the header is the only place that can tell them apart afterwards.
	print("Route: %s (%s)" % [
		"explore — takes every optional thing before the stairs" if EXPLORE
			else "stairs — gets on with the dungeon",
		"--explore" if EXPLORE else "pass --explore for the other one"])
	_avoid_calibration()
	_print_budget()
	quit()

## What the run cost, by phase. Anything dominating here is where to look next.
func _print_budget() -> void:
	var total := 0
	for k in _spent:
		total += int(_spent[k])
	if total <= 0:
		return
	print("\n=== where the time went ===")
	var keys: Array = _spent.keys()
	keys.sort_custom(func(a, b): return int(_spent[a]) > int(_spent[b]))
	for k in keys:
		print("   %-12s %7.1f s  %3.0f%%" % [
			k, float(_spent[k]) / 1e6, 100.0 * float(_spent[k]) / float(total)])
	print("   %-12s %7.1f s  (measured phases only)" % ["TOTAL", float(total) / 1e6])

## Is paying HP to skip a fight priced, or is it a cheat?
##
## The old deck model's whole decision was face-or-dodge, and it went unmeasured for its
## entire existence because the driver only dodged below 35% HP — which a greedy
## player almost never sits at. So the three lines of play are now measured against
## each other. The property that matters is D20's: **a dominant strategy is a
## removed decision.** If ALWAYS-AVOID clears more often than SMART, the price is
## wrong; if it clears far less, dodging is decoration.
##
## The default trial count; `--cal-trials=` overrides it into `CAL_TRIALS`.
const CALIBRATION_TRIALS := 150

func _avoid_calibration() -> void:
	print("\n=== Avoid calibration (%d trials per cell) ===" % CAL_TRIALS)
	print("Any dungeon that prices a skip — asked of the dungeon, not assumed.")
	print("A price is right when SMART >= both fixed lines of play.\n")
	var t_cal := Time.get_ticks_usec()
	for profile in _profiles():
		var deck: Array[CardData] = profile["deck"]
		for dungeon_id in profile["dungeons"]:
			if not _wanted(dungeon_id, String(profile["name"])):
				continue
			var dd := Balance.dungeon(dungeon_id)
			# Ask the DUNGEON whether it prices a skip, rather than naming the model that
			# used to. This filtered on `Kind.DECK`, and when D88 moved every dungeon onto
			# the isometric crawl it silently matched nothing — the calibration printed its
			# header and no rows, so the check that a dodge is not a dominant strategy
			# (D20) went dark at exactly the moment a new model inherited the mechanic.
			# A harness that selects by name goes quiet when the name changes; one that
			# selects by behaviour follows the behaviour. The names are gone now (D94) and
			# this reads the same, which is the point.
			if dd == null:
				continue
			# Walked, not peeked: the old deck model revealed a dodgeable card immediately,
			# but a spatial model only offers one once you are standing next to a fight, so
			# checking the opening options alone would answer "no" for the model that now
			# owns the mechanic.
			var probe := TraversalIso.new()
			probe.generate(dd)
			var prices_a_skip := false
			for _s in 40:
				if probe.is_complete():
					break
				var pos_opts := probe.options()
				if pos_opts.is_empty():
					break
				for po in pos_opts:
					if String(po.get("action", "")) == "avoid":
						prices_a_skip = true
						break
				if prices_a_skip:
					break
				if not probe.select(0).is_empty():
					probe.clear_pending()
			if not prices_a_skip:
				continue
			var roster: Array = Array(dd.enemy_roster) if dd.has_roster() else []
			var relics: Array = profile.get("relics", [])
			var cells: Array = []
			for mode in [Policy.ALWAYS_FACE, Policy.SMART, Policy.ALWAYS_AVOID]:
				cells.append(_measure_run(dungeon_id, deck, relics, roster, mode,
					CAL_TRIALS, maxi(int(profile.get("clears", 0)),
						Balance.effective_gate(dungeon_id)), _power_of(profile)))
			print("   %-18s %-24s face %3.0f%% | smart %3.0f%% (%2.0f%% dodged) | avoid %3.0f%% (%2.0f%% dodged)" % [
				dd.name, profile["name"],
				cells[0]["complete"] * 100.0,
				cells[1]["complete"] * 100.0, cells[1]["avoid_rate"] * 100.0,
				cells[2]["complete"] * 100.0, cells[2]["avoid_rate"] * 100.0])
			if cells[2]["complete"] > cells[1]["complete"] + 0.05:
				print("      ^ ALWAYS-AVOID beats the smart line: the dodge is underpriced")
			# The other direction, which went unreported until D99 and is a different
			# fault with a different owner. Dodging costs HP and forfeits the reward, and
			# the reward joins the run deck — so at depth, where a fight is dear in HP but
			# the boss is decided by deck power, declining fights can be right on HP and
			# wrong on the run. `cost_est` only knows HP, so SMART cannot see that trade
			# and degenerates toward always-avoid exactly where the loot matters most.
			# That is the DRIVER's ceiling, not the price's: printed rather than tuned
			# away, because raising FACE_BIAS until this line disappears would be fitting
			# the policy to the scoreboard.
			elif cells[0]["complete"] > cells[1]["complete"] + 0.05:
				print("      ^ ALWAYS-FACE beats the smart line: the driver is over-dodging (it prices HP, not loot)")
	_tick("avoid_calibration", t_cal)

## Simulate a full dungeon: walk a random path through the real generated map,
## fighting with persistent HP, resting where offered. Returns completion rate.
## Simulate complete runs of a dungeon, driving the real Traversal directly.
## Because Traversal is pure logic, ONE walker measures every dungeon through the
## same interface — a per-model walker would be the first thing to rot when a second
## model is added, which is why this one stayed generic after D94 left only the crawl.
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
		var tv := TraversalIso.new()
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
		# The iso floor is mostly open ground now (D77), so a run is tens of MOVES for
		# the same handful of fights. At 60 this truncated every iso run mid-floor and
		# reported the model as costing a third of its budget.
		while alive and not tv.is_complete() and guard < 400:
			guard += 1
			var opts := tv.options()
			if opts.is_empty():
				break
			for o in opts:
				if String(o.get("action", "")) == "avoid":
					avoidable_total += 1
					break
			var pick := _choose_option(opts, hp, max_hp, cost_est, mode, tv)
			var cost := int(opts[pick].get("hp_cost", 0))
			var was_dodge := String(opts[pick].get("action", "")) == "avoid"
			var node := tv.select(pick)
			# EVERY priced option is paid for, not only the ones that resolve nothing.
			# This was found through the iso model, which used to charge HP for a step
			# taken after its torch burnt out while still handing back the encounter in
			# the room it led to, so paying only on an empty result measured walking in
			# the dark as free. The torch is gone (D77) and the deck's dodge is once
			# again the only priced option, but the rule stays general on purpose.
			# `avoidable`/`avoided` count dodges specifically, which is what the
			# calibration below reports; a step across open ground is not one.
			if cost > 0:
				hp = maxi(1, hp - cost)
			# Being caught in the open is priced too, and it is priced on the ENCOUNTER
			# rather than on the option — a wanderer decides to reach you after the move
			# is chosen, so there is nothing on the option to read. Paid before the fight
			# is simulated, or the ambush would be a number the report never feels.
			if bool(node.get("ambush", false)):
				hp = maxi(1, hp - Balance.iso_ambush_cost(max_hp))
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
					# The sealed pack a treasure yields (D80) is deliberately NOT modelled:
					# it does not join the run deck, so it cannot change the odds of the
					# run this profile is measuring. It is meta reward, which is exactly
					# what made it the safe place to put more cards.
					tv.clear_pending()
				Traversal.Enc.EVENT:
					# HP/gold effects only. Card and relic grants are skipped: they
					# would mutate the very deck this profile is measuring.
					var t_ev := Time.get_ticks_usec()
					var res := _sim_event(hp, max_hp, gold)
					_tick("events", t_ev)
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
					var t_su := Time.get_ticks_usec()
					# The traversal's own choice of creature is honoured here for the same
					# reason the named boss and the equipped power are: whatever the game
					# passes to CombatEngine, the sim has to pass too. The iso model casts
					# its fights at generation time (D85), and a sim that kept rolling its
					# own would be measuring a different enemy distribution than the one
					# being played — the D72/D74/D77 mistake for a fourth time.
					eng.setup(run_deck, hp, max_hp, difficulty, tier,
						String(node.get("enemy", "")), relics, roster,
						power, dd.boss if dd != null else "")
					_tick("fight_setup", t_su)
					var t_fi := Time.get_ticks_usec()
					var g2 := 0
					while not eng.over() and g2 < 200:
						g2 += 1
						_take_turn(eng)
						if eng.over():
							break
						eng.end_turn()
					_tick("fight_play", t_fi)
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
						var t_rw := Time.get_ticks_usec()
						var won_card := _reward_card(dungeon_id, reward_level)
						_tick("rewards", t_rw)
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
	var e := Balance.event(String(pool[randi() % pool.size()]))
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
## per run in every profile** — so the old deck model's entire decision (face this
## encounter, or pay HP to skip it and forfeit the loot) was never exercised, and
## the avoid price had never been calibrated against anything. That is the
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

## The step a player stripping the floor takes, or -1 if there is nothing optional left and
## the route question has no opinion (D179).
##
## Toward the nearest optional thing, and never onto the stairs while one remains: descent is
## one-way, so a floor left behind is a floor gone, and a driver that took the stairs early
## would be playing the required route with a few extra steps in it.
##
## Optional means what `tests/test_traversal.gd`'s second walker means by it — today, a key,
## which is ranked but not required (D167). The two definitions being the same is what lets
## the walk measurement and this report be talking about one route.
func _explore_pick(opts: Array, tv: TraversalIso) -> int:
	var targets: Array = []
	for i in tv.enc.size():
		if int(tv.enc[i]) == TraversalIso.KEY:
			targets.append(i)
	if targets.is_empty():
		return -1
	var field: PackedInt32Array = tv._dist_to_any(targets)
	var best := -1
	var best_d := 1 << 30
	for i in opts.size():
		var o: Dictionary = opts[i]
		if String(o.get("action", "")) == "avoid":
			continue
		var cell := int(o["cell"])
		if int(tv.enc[cell]) == TraversalIso.STAIR:
			continue
		var d := int(field[cell])
		if d >= 0 and d < best_d:
			best_d = d
			best = i
	return best

## Only dodge a fight that costs meaningfully more than the dodge: the loot, and
## the gold that buys healing later, is worth some HP. 1.0 would dodge on a tie.
const FACE_BIAS := 1.35
## A fight whose *average* cost is this close to what is left is a coin flip, and
## paying a known price beats rolling for it — but only when the price is the
## cheaper of the two. See `_choose_option`.
const LETHAL_MARGIN := 1.6

func _choose_option(opts: Array, hp: int, max_hp: int, cost_est: Dictionary,
		mode: int = Policy.SMART, tv: TraversalIso = null) -> int:
	var frac := float(hp) / float(maxi(1, max_hp))
	# The route comes FIRST, before the fight-or-dodge question, because it is a different
	# question: this decides where to walk, and everything below decides what to do about
	# what is standing there (D179). A player stripping a floor still faces and dodges the
	# way the policy below says — they simply do not leave until they have taken everything.
	#
	# `tv` is optional so the calibration probe can keep asking without one; without it the
	# driver cannot see past its own four options and there is no detour to take, which is
	# the honest degradation rather than a silent half-policy.
	if EXPLORE and tv != null:
		var detour := _explore_pick(opts, tv)
		if detour >= 0:
			return detour
	# take a rest or shop if it is on offer and we are damaged
	for i in opts.size():
		var t := int(opts[i].get("type", 0))
		if t == Traversal.Enc.TREASURE:
			return i   # free value, always worth landing on
		if frac < 0.6 and (t == Traversal.Enc.REST or t == Traversal.Enc.SHOP):
			return i

	# A dodge, not merely a priced option: this policy is about declining a fight,
	# and the iso model once priced plain MOVEMENT (D77 removed it).
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
					# Facing this might end the run — but a dodge dearer than the fight
					# does not save you from that, it just spends the same HP and forfeits
					# the loot as well. The `cost < expected` half of this test was
					# missing, and while the dodge was underpriced (D99) it never bit:
					# every dodge was cheaper than every fight, so the guard was free.
					# Repricing exposed it — at the Sunken Vault the driver was paying 23
					# of its last 30 HP to skip a fight averaging 20, and SMART came in 14
					# points BELOW never dodging at all. A harness is only evidence if its
					# driver is as competent as the thing it judges (D26).
					if expected * LETHAL_MARGIN >= float(hp) and float(cost) < expected:
						return avoid          # cheaper AND it might otherwise end the run
					if expected > float(cost) * FACE_BIAS:
						return avoid          # the dodge is simply cheaper

	# Otherwise face it. A random pick among the non-avoid options is right when those
	# options are ENCOUNTERS — it stops the driver quietly favouring whatever each
	# model happens to list first, which is how a policy becomes a measurement of an
	# ordering. It is WRONG when the options are merely directions, and the iso floor
	# is now mostly open ground (D77): a uniform random step is a drunkard's walk, and
	# a drunkard does not reliably reach the far corner of a 30-tile floor. It
	# measured the Warrens at a flat 72% for every deck in the report — starter and
	# fully-relic'd alike, every fight won, HP barely touched — because a quarter of
	# runs simply never found the stair inside the move guard. A model-agnostic
	# failure that looked exactly like difficulty.
	#
	# So: choose randomly among the options that resolve something, and when none do,
	# take the model's own first suggestion rather than a coin flip. A model that only
	# ever offers encounters — as the three deleted in D94 did — makes `resolving` and
	# `faceable` the same list, so this stays right for anything added later.
	var faceable: Array = []
	var resolving: Array = []
	for i in opts.size():
		if opts[i].has("hp_cost"):
			continue
		faceable.append(i)
		if int(opts[i].get("type", -1)) >= 0:
			resolving.append(i)
	if faceable.is_empty():
		return 0
	if resolving.is_empty():
		return int(faceable[0])
	return int(resolving[randi() % resolving.size()])

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
		"deck": _deck({"hack": 4, "cover": 4}),
		"dungeons": ["crypt", "ossuary", "warrens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Early (rewards added)",
		"clears": 1, "power_level": 1,
		"deck": _deck({"hack": 5, "cover": 4, "stave_in": 2, "shoulder": 2}),
		"dungeons": ["crypt", "warrens", "foundry"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Mid (fused Lv15)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 4, "stave_in": 3, "shoulder": 3, "clear_mind": 2}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Status build (Lv15)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 4, "stave_in": 2, "put_the_fear": 2, "work_up": 2, "light_on_it": 1}, 15),
		"dungeons": ["warrens", "foundry", "ember_road"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Barricade build (Lv15, legend Lv5)",
		"clears": 3, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 6, "light_on_it": 2, "shoulder": 3}, 15) + _deck({"set_stone": 1}, 5),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Poison build (Lv15)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"hack": 3, "cover": 4, "venom_fang": 3, "split": 3, "noxious_cloud": 1, "smoke_bomb": 2}, 15),
		"dungeons": ["fungal_deep", "rot_gardens"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "AoE build (Lv15)",
		"clears": 5, "power_level": 2,
		"deck": _deck({"hack": 2, "cover": 4, "reap": 3, "clear_the_room": 2, "hex": 1, "take_it": 3}, 15),
		"dungeons": ["rot_gardens", "drowned_market"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Thorns build (Lv15)",
		"clears": 5, "power_level": 2,
		"deck": _deck({"hack": 3, "cover": 4, "riposte": 3, "sharp_ground": 2, "bristle": 1, "iron_will": 2, "survival_instinct": 2}, 15),
		"dungeons": ["slag_pits", "abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Maxed commons (Lv100)",
		"clears": 6, "power_level": 3,
		"deck": _deck({"hack": 8, "cover": 8, "shoulder": 4}, 100),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Relic build (Lv15 + 4 relics)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 5, "stave_in": 3, "shoulder": 3}, 15),
		"dungeons": ["warrens", "foundry", "sunken_vault"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "ancient_battery"]),
	})
	out.append({
		# D124. Twelve profiles and not one draw relic between them, and of the eleven
		# cards that draw exactly two appeared anywhere in the table — so when D120
		# capped the hand at ten, this report called it a no-op while instrumented
		# counters put the cap's bite at 35% of turns and 77% of fights for a build
		# like this one. A tool that cannot play the build cannot price it, and a
		# temporary subclass that measures once and is deleted leaves the same hole
		# behind. This row exists so draw can never go unmeasured again.
		#
		# Both lenses, because they are the two relics whose price is in question:
		# Keen Lens is +1 every turn, Scholar's Lens is +2 on every third. Seven of the
		# seventeen cards draw as well, across every shape draw comes in — In and Out
		# and Take It draw while they hit or block, Clear Mind draws while it buffs
		# (which is why `_play_powers` and not `_play_draw` is what plays it), and
		# Read Ahead is one of only two cards in the game whose sole effect is draw.
		#
		# It is a DECK first and a demonstration second. The first attempt was eleven
		# cards of draw and defence around four attackers, and it cleared 0% of both
		# dungeons with normal fights running 13 turns — a row that reads zero measures
		# nothing, and what it measured was the deck being unplayable, not draw being
		# mispriced. This one keeps Mid's attacking spine (5 Hack, 2 Stave In) and pays
		# for its draw out of the block slots, which is the trade a player actually
		# makes. It lands at ratio 6.39 against Mid's 6.60, so the two are comparable.
		#
		# Three dungeons, because a row that reads 100% measures nothing either and the
		# band moved under this decision's own feet: over three 400-trial runs the
		# Foundry sits at 96-98%, the Sunken Vault at 66-77%, the Drowned Market 52. The
		# Foundry is kept anyway — saturated as a *level*, it is the cell that carried
		# the whole policy finding (44 -> 97 on the fix alone), and a row that has moved
		# 53 points once is worth watching.
		"name": "Draw build (Lv15 + 2 lenses)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 3, "stave_in": 2, "in_and_out": 3,
			"take_it": 1, "clear_mind": 2, "read_ahead": 1}, 15),
		"dungeons": ["foundry", "sunken_vault", "drowned_market"],
		"hp_mult": 1.0,
		"relics": _relics(["keen_lens", "scholars_lens"]),
	})
	out.append({
		"name": "Late (Lv40 + 6 relics)",
		"clears": 8, "power_level": 3,
		"deck": _deck({"hack": 4, "cover": 4, "stave_in": 3, "shoulder": 3, "dead_weight": 3,
			"take_it": 3}, 40),
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
		"deck": _deck({"hack": 4, "cover": 4, "stave_in": 3, "shoulder": 3, "dead_weight": 3,
			"take_it": 3}, 100),
		"dungeons": ["abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
		"relics": _relics(["iron_heart", "kite_shield", "whetstone", "giants_marrow",
			"bulwark_plate", "eternal_furnace", "warlords_banner"]),
	})
	out.append({
		"name": "Deep (fused Lv40)",
		"clears": 6, "power_level": 3,
		"deck": _deck({"hack": 6, "cover": 5, "stave_in": 4, "shoulder": 3, "clear_mind": 2}, 40),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
	})
	return out

## One reward card from this dungeon's pool, at the level the player's cards sit at.
## Rarity is tilted by depth exactly as the reward screen tilts it.
##
## The table is built ONCE per dungeon. Rolling it used to load every card in the
## pool every time — nineteen resource lookups at 0.12 ms each, so a single reward
## cost 2.3 ms against 0.35 ms for an entire simulated fight, and the tool spent
## most of its life in ResourceLoader rather than in the game.
static var _reward_tables := {}

## Where the tool's own time goes, printed at the end of a report. Added after a
## round of optimisation guessed wrong twice: caching the content accessors won 350x
## on one call and 3x overall, which means the guess about what dominated was off.
## A profiler that ships with the tool is cheaper than re-deriving this every time.
static var _spent := {}

static func _tick(bucket: String, from: int) -> void:
	_spent[bucket] = int(_spent.get(bucket, 0)) + (Time.get_ticks_usec() - from)

func _reward_table(dungeon_id: String) -> Dictionary:
	if _reward_tables.has(dungeon_id):
		return _reward_tables[dungeon_id]
	var dd := Balance.dungeon(dungeon_id)
	var wtbl: Array = Balance.reward_weights(Balance.Tier.NORMAL,
		dd.difficulty if dd != null else 1)
	var ids: Array = []
	var weights: Array = []
	var total := 0
	for id in Balance.card_pool_for(dungeon_id):
		var c := Balance.card(id)
		if c == null:
			continue
		ids.append(id)
		var w: int = wtbl[clampi(c.rarity, 0, wtbl.size() - 1)]
		weights.append(w)
		total += w
	var table := {"ids": ids, "weights": weights, "total": total}
	_reward_tables[dungeon_id] = table
	return table

func _reward_card(dungeon_id: String, level: int) -> CardData:
	var table := _reward_table(dungeon_id)
	var ids: Array = table["ids"]
	if ids.is_empty():
		return null
	var weights: Array = table["weights"]
	var roll := randi() % maxi(1, int(table["total"]))
	var pick: int = ids.size() - 1
	for i in ids.size():
		roll -= int(weights[i])
		if roll < 0:
			pick = i
			break
	var card := Balance.card(String(ids[pick])).duplicate() as CardData
	card.level = level
	return card

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
	# A THIRD of the run trials. These columns are a full-HP indicator, not the
	# metric that decides anything — the report says so itself — and at parity they
	# cost as much as the run simulation they sit beside. A hundred fights pins a
	# win rate to a few points, which is all this column is read to that precision.
	var trials: int = maxi(40, TRIALS / 3)
	for t in trials:
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
		"win_rate": float(wins) / trials,
		"avg_turns": float(turns_total) / trials,
		# HP lost as a fraction of max: if this is ~0, attrition is broken and
		# individual fights are meaningless regardless of win rate.
		"hp_lost_pct": float(hp_lost_total) / trials / max_hp,
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

## No turn the rules can produce plays this many cards; reaching it means the
## play policy has found a loop rather than a strong hand.
const PLAY_GUARD := 400

func _play_powers(eng: CombatEngine) -> void:
	var again := true
	# guard: a zero-cost card that draws returns via the discard, so "play
	# everything you can" is a closed loop and `over()` never comes. Cards are
	# bounded so this cannot fire (tests/test_degenerate.gd), and it stays because
	# the simulator is run by hand — a hang here costs a person, not CI.
	var guard := 0
	while again and not eng.over() and guard < PLAY_GUARD:
		guard += 1
		again = false
		for c in eng.hand.duplicate():
			if eng.can_play(c) and (c.retain_block or c.eff_strength() > 0 or c.eff_dexterity() > 0):
				eng.play_card(c); again = true; break

## Draw, played before the rest of the turn so what it finds can be planned with.
##
## The rule here was "play every draw card you can afford, always", and that is not a
## player, it is a compulsion. D120 caught it from the far side: capping the hand at
## ten measured as a *buff* for draw builds, because a smaller hand meant fewer draw
## cards to burn energy on, so fights ran shorter (Draw-heavy at the Foundry, 7.8
## turns to 6.3) and less escalation damage landed. A policy that over-draws makes
## draw look worthless, and nothing measured against it can price a draw relic —
## which is why D120 left the lenses' known mispricing open rather than "fixing" it.
##
## `_draw_is_worth_it` is the whole of the change. It is deliberately not a solver:
## the rest of this driver is three greedy passes and a policy smarter than the one
## it shares a file with would be measuring a player nobody is.
func _play_draw(eng: CombatEngine) -> void:
	var again := true
	# guard: a zero-cost card that draws returns via the discard, so "play
	# everything you can" is a closed loop and `over()` never comes. Cards are
	# bounded so this cannot fire (tests/test_degenerate.gd), and it stays because
	# the simulator is run by hand — a hang here costs a person, not CI.
	var guard := 0
	while again and not eng.over() and guard < PLAY_GUARD:
		guard += 1
		again = false
		for c in eng.hand.duplicate():
			if eng.can_play(c) and c.eff_draw() > 0 and _draw_is_worth_it(eng, c):
				eng.play_card(c); again = true; break

## Is this card worth playing FOR ITS DRAW right now? (D124)
##
## Two tests, and neither is a solver:
##
##   * The cards it fetches must have somewhere to land. `_resolve()` runs before
##     `hand.erase()`, so a draw card is still in its own hand while it draws: at
##     `MAX_HAND_SIZE` every one of them is refused, the card is spent and the
##     energy is simply gone (D120's `draw_cards`).
##   * Paid draw is worth energy only when the HAND is the bottleneck rather than
##     the energy. A hand that can already spend every point this turn has nothing
##     to do with more cards, and `end_turn()` discards the hand, so a card drawn
##     and not played is thrown away rather than banked for next turn. This
##     subsumes "is there energy left after paying for it": a hand cannot spend less
##     than the nothing that would be left.
##
## Free draw skips the second test — no energy spent, no trade to weigh.
##
## **The first version of this exempted every card with a BODY from the second test**
## — play In and Out for its 4 damage, Take It for its 7 Block, and let the draw be a
## rider — on the reasoning that only a card whose sole effect is draw is a purchase.
## It sounded principled and it left the test with no subject: instrumented over a
## draw-heavy profile it evaluated **1,498 draw plays and refused none of them**.
## Every card in the catalogue whose only effect is draw (Read Ahead, See It Coming)
## costs **zero**, and every paid draw card has a body — Clear Mind is not even a
## pure draw card, it grants Dexterity, so `_play_powers` takes it before this pass
## ever sees it. An invariant about the members of a set says nothing until something
## checks the set is not empty (D86), and that exemption emptied the set.
##
## So the test applies to Take It and In and Out too, and that is the honest reading
## of what it says: a card is not played at the top of the turn *merely because it
## draws*. Nothing is stranded by holding one back — `_try_lethal`, `_block_incoming`
## and `_spend_rest` all pick on merit and all re-read the hand after every play, so
## a rider worth its energy is still played, just later and for the right reason.
##
## Measured against the greedy rule on identical code, ten cells over five decks that
## hold draw cards, 400 trials: mean run completion **68.6 -> 72.8**, with the Draw
## build at the Foundry 47/46 -> 96/96 and normal fights there falling from 7.4 turns
## to 4.6. It costs one cell — see the note on `_block_incoming`'s tolerance below.
func _draw_is_worth_it(eng: CombatEngine, c: CardData) -> bool:
	if eng.hand.size() >= Balance.MAX_HAND_SIZE:
		return false
	if c.eff_cost() <= 0:
		return true
	return _energy_the_rest_of_the_hand_can_use(eng, c) < eng.energy - c.eff_cost()

## What the rest of the hand could already spend this turn. Costs are summed rather
## than fitted to a knapsack because the question is whether the hand REACHES the
## energy, not which cards fill it — and which cards fill it is decided by the passes
## below, on merit, which is the whole point of not deciding it here.
func _energy_the_rest_of_the_hand_can_use(eng: CombatEngine, skip: CardData) -> int:
	var total := 0
	for c in eng.hand:
		if c != skip:
			total += c.eff_cost()
	return total

## True if the enemy can be killed with the energy in hand this turn.
func _try_lethal(eng: CombatEngine) -> bool:
	var total := 0
	var budget := eng.energy
	var plan: Array[CardData] = []
	# greedy by damage per energy
	var pool := eng.hand.duplicate()
	pool.sort_custom(func(a, b):
		return float(a.eff_damage()) / maxf(1.0, a.eff_cost()) > float(b.eff_damage()) / maxf(1.0, b.eff_cost()))
	for c in pool:
		if c.eff_damage() > 0 and c.eff_cost() <= budget:
			budget -= c.eff_cost()
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
##
## FOUND BY D124, NOT FIXED BY IT. `tolerance` is 8% of MAX HP, so at the Sunken
## Vault this pass deliberately eats up to 9.6 damage a turn rather than spend a
## card on it — and at 120 HP over five fights that adds up. It never showed,
## because the old `_play_draw` played every block card that also drew before this
## pass could decline to. Gating draw (above) hands the decision back to the pass
## whose job it is, and the Draw build at the Sunken Vault falls 86/86 -> 71/65
## while its fights shorten from 9.0 turns to 5.6. That is a tolerance calibrated
## against a driver that was over-blocking for other reasons, and re-pitching it is
## a policy change of its own with its own recalibration; it is recorded here rather
## than folded into a decision about draw.
func _block_incoming(eng: CombatEngine) -> void:
	# Eat small hits: spending a whole card to prevent a trivial amount of damage
	# is worse than landing that damage on the enemy.
	var tolerance := 0.08 * eng.player.max_hp
	var target := 0
	if eng.player.retain_block:
		target = 2 * eng.enemy_intent
		tolerance = 0.0
	var again := true
	# guard: a zero-cost card that draws returns via the discard, so "play
	# everything you can" is a closed loop and `over()` never comes. Cards are
	# bounded so this cannot fire (tests/test_degenerate.gd), and it stays because
	# the simulator is run by hand — a hang here costs a person, not CI.
	var guard := 0
	while again and not eng.over() and guard < PLAY_GUARD:
		guard += 1
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
	# guard: a zero-cost card that draws returns via the discard, so "play
	# everything you can" is a closed loop and `over()` never comes. Cards are
	# bounded so this cannot fire (tests/test_degenerate.gd), and it stays because
	# the simulator is run by hand — a hang here costs a person, not CI.
	var guard := 0
	while again and not eng.over() and guard < PLAY_GUARD:
		guard += 1
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
		var val := float(amount) / maxf(1.0, float(c.eff_cost()))
		if val > best_val:
			best_val = val
			best = c
	return best
