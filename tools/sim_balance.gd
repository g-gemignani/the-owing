## Headless balance simulator (D5). Auto-plays fights with a greedy policy and
## reports win rates per dungeon tier, so Balance constants can be tuned against
## measured numbers instead of guesses. Uses the real CombatEngine.
## Run: godot --headless --script tools/sim_balance.gd
extends SceneTree

## Trials per cell. Overridable for iteration — a tuning pass needs many runs of
## the report and one at full precision, not fifteen at full precision:
##     godot --headless --script tools/sim_balance.gd -- --trials=120
const DEFAULT_TRIALS := 400

## How many untaxed relics a run is handed as it walks. See `--spoils=`.
static var SPOILS := 0

## Print each cell twice and the gap between them. See `--noise`.
static var NOISE := false

## Percentile of an already-SORTED array, by nearest rank. Nearest rather than interpolated
## because two of the three subjects are integer counts (fights survived) and an interpolated
## 6.5 fights is a run nobody had.
static func _pct(sorted_vals: Array, p: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var i := clampi(int(round(p * float(sorted_vals.size() - 1))), 0, sorted_vals.size() - 1)
	return float(sorted_vals[i])
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
static var CALIBRATE := true  ## --no-calibration turns the avoid block off
static var CAL_TRIALS := CALIBRATION_TRIALS
## Which ROUTE through a floor the driver walks (D179, D183).
##
## A walker counts moves; only the simulator can say what those moves cost in HP and clear
## rate, so the routes have to be playable HERE and not only in `tests/test_traversal.gd`.
##
## THREE of them, not two, and the third is the whole reason the guarded pocket can be priced
## at all (D183). Without it the sim cannot play the feature and would report a confident
## nothing about it, which is D124 exactly — an instrument whose policy could not hold the
## thing being measured. The three together are what say whether the wager is priced: if
## fighting every guard beats running for the stairs on clear rate, the reward is too high or
## the elites too soft; if it is catastrophic, nobody will push a wall twice.
const ROUTE_STAIRS := 0    ## get on with the dungeon
const ROUTE_EXPLORE := 1   ## push every wall, but decline every guard
const ROUTE_GUARDS := 2    ## push every wall and fight what is standing there
static var ROUTE := ROUTE_STAIRS

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
			ROUTE = ROUTE_EXPLORE
		# ...and the same player, willing to fight what is standing over the prize (D183).
		# Separate from the flag above because the two numbers only mean something as a pair:
		# what the guards cost is the difference between them.
		elif arg == "--explore-guards":
			ROUTE = ROUTE_GUARDS
		# The mirror of --calibration-only, and the reason it exists: the calibration is
		# 80% of a full run's wall clock (306s of 385s, measured), so a difficulty sweep
		# that only reads run-completion pays four times over for a block it never looks
		# at. Skipping it is a NARROWING like the filters above — every cell still
		# measured exactly as it would be in a full run.
		elif arg == "--no-calibration":
			CALIBRATE = false
		# Measure every selected cell TWICE and print the gap between the two readings
		# (D229). The tool does not seed its RNG, so a delta smaller than this gap is
		# weather — D120 measured a mean of 0.4 points with one cell swinging 15, and every
		# number the fun block adds has its own band that nobody has measured yet. Narrow
		# with --only= first; this doubles the wall clock.
		elif arg == "--noise":
			NOISE = true
		# Hand every run N relics as it walks, exempt from enemy scaling, and see what the
		# escalation does (D226 step 0b, D230). A MEASUREMENT, not a design: no content is
		# written, nothing in the game passes `p_untaxed`, and the flag is the whole change.
		# If `esc` barely moves at 5, untaxed in-run power is not the lever D226 thinks it is
		# and four steps of that plan are aimed at the wrong system.
		elif arg.begins_with("--spoils="):
			SPOILS = clampi(int(arg.substr(9)), 0, 12)
		elif arg.begins_with("--difficulty="):
			Balance.difficulty = clampi(int(arg.substr(13)), 0, Balance.DIFFICULTIES.size() - 1)
		# Raw multiplier overrides, for SWEEPING candidate rungs before any of them are
		# written into the table (D175). Not a play mode: these bypass the named ladder
		# on purpose, so the report header prints whatever is actually in force rather
		# than a rung name that may not describe it.
		elif arg.begins_with("--dhp="):
			Balance.hp_mult_override = maxf(0.1, float(arg.substr(6)))
		elif arg.begins_with("--ddmg="):
			Balance.dmg_mult_override = maxf(0.1, float(arg.substr(7)))
		elif arg.begins_with("--dratio="):
			Balance.ratio_mult_override = maxf(0.1, float(arg.substr(9)))

## Which player this report measured, in words (D179, D183).
##
## Printed because a report that does not name its route is a report whose numbers cannot be
## compared with another one. Two runs of this tool differ by a mean of 0.4 points already
## (D120); a route change is a much larger difference wearing the same clothes, and the header
## is the only place that can tell them apart afterwards.
static func _route_line() -> String:
	match ROUTE:
		ROUTE_EXPLORE:
			return "explore — pushes every wall, declines every guard (--explore)"
		ROUTE_GUARDS:
			return "explore and fight — pushes every wall and takes on what is standing there (--explore-guards)"
	return "stairs — gets on with the dungeon (--explore / --explore-guards for the others)"

## What difficulty the report was measured at, for the header. Prints the raw
## multipliers rather than only the rung name, because `--dhp`/`--ddmg` can put
## numbers in force that no rung describes.
static func _difficulty_line() -> String:
	return "Difficulty: %s (enemy HP x%.2f, enemy damage x%.2f, scaling ratio x%.2f)%s" % [
		Balance.difficulty_name(),
		Balance.difficulty_hp_mult(), Balance.difficulty_dmg_mult(),
		Balance.difficulty_ratio_mult(),
		"  [swept, not a shipped rung]" if not (
			is_nan(Balance.hp_mult_override) and is_nan(Balance.dmg_mult_override)
			and is_nan(Balance.ratio_mult_override)) else ""]

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
	print(_difficulty_line())
	print("RUN = full-dungeon completion with persistent HP (the metric that matters).")
	print("Per-fight rates are full-HP diagnostics only.")
	# Named here rather than left to be inferred, because four of these have no precedent in
	# this tool and one of them (esc) is the acceptance test for a whole design (D226/D229).
	print("fun  = esc: median last-fight damage-per-turn / first-fight, per run — the escalation.")
	print("       hp: end-of-run HP percentiles, a death counted as 0, so p10=0 means the")
	print("           bottom decile died. fights: p10-p90 of fights survived.")
	print("       div: mean Jaccard distance between consecutive runs' final decks.")
	print("       real/forced/solved: share of card choices with a live runner-up / only one")
	print("           legal play / a best play worth 3x the next. DIAGNOSTIC, not pass/fail.")
	if SPOILS > 0:
		print("--spoils=%d: every run is lent up to %d relics as it walks, EXEMPT from enemy" % [
			SPOILS, SPOILS])
		print("           scaling. A measurement of untaxed in-run power (D226 step 0b), not a design.")
	if NOISE:
		print("--noise: every cell measured twice; believe no delta smaller than the gap.")
	print("")
	for profile in _profiles():
		var deck: Array[CardData] = profile["deck"]
		var prof_power := _power_of(profile)
		var relic_hp0 := 0
		for r0 in profile.get("relics", []):
			relic_hp0 += r0.bonus_max_hp
		print("%s  (%d cards, ratio %.2f, %d clears, %d HP, %d relics, power %s)%s" % [
			profile["name"], deck.size(),
			Balance.power_ratio(deck, profile.get("relics", []), prof_power),
			int(profile.get("clears", 0)),
			Balance.max_hp_for(int(profile.get("clears", 0)), relic_hp0),
			(profile.get("relics", []) as Array).size(),
			prof_power.name if prof_power != null else "none",
			# Said out loud, because relics-below-clears is now a FAULT everywhere else
			# (D208) and a row that is allowed to look like the bug has to announce that
			# it is deliberate. Otherwise the next reader fixes it back.
			"  [instrument: fixed relic set]" if bool(profile.get("fixed_relics", false))
				else ""])
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
			print(_fun_line(run))
			# The gap between two readings of the SAME cell, which is the only thing that says
			# whether a delta in the numbers above is a change or the weather (D229). Only the
			# run is re-measured: the tier diagnostics are not part of the fun block and cost
			# three quarters of the cell.
			if NOISE:
				var run2 := _measure_run(dungeon_id, deck, relics, roster, Policy.SMART,
					TRIALS, clears, _power_of(profile))
				print(_fun_line(run2))
				print("      noise  RUN %+.0f pts | esc %+.2fx | hpP50 %+.0f%% | div %+.3f | real %+.0f pts" % [
					(run2["complete"] - run["complete"]) * 100.0,
					run2["escalation"] - run["escalation"],
					(run2["hp_p50"] - run["hp_p50"]) * 100.0,
					run2["divergence"] - run["divergence"],
					(run2["dd_real"] - run["dd_real"]) * 100.0])
		print("")
	# 50-70 until D197, when the floor stopped letting anything stand still and the game was
	# asked to be meaner than it was. The band moved with the intent, not to fit the numbers:
	# a run this deck is matched to should fail about half the time.
	print("Target: RUN completion ~40-60%% at matched progression; <15%% when over-reaching.")
	# Said out loud, because a report that does not name its route is a report whose numbers
	# cannot be compared with another one (D179). Two runs of this tool differ by a mean of
	# 0.4 points already (D120); a route change is a much larger difference wearing the same
	# clothes, and the header is the only place that can tell them apart afterwards.
	print("Route: %s" % _route_line())
	if CALIBRATE:
		_avoid_calibration()
	else:
		print("\n(avoid calibration skipped: --no-calibration)")
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
## The fun block for one cell (D229), on its own line under the difficulty line.
##
## Separate line rather than more columns on the first one: the difficulty line is already 120
## characters and these four numbers answer a different question. They are printed for every
## cell from the day they exist, because a diagnostic behind a flag is a diagnostic nobody reads
## — and the whole reason this block exists is that forty-six suites and this tool could all
## report a healthy game that nobody wanted to play twice.
func _fun_line(run: Dictionary) -> String:
	# `esc` is the MEDIAN of the runs that had an escalation to measure, and `n` says how many
	# that was. A ratio averaged over runs that never landed damage is a number about the
	# driver, not the deck (D124).
	return "      fun    esc %.2fx(n%d) | hp p10/p50/p90 %.0f/%.0f/%.0f%% | fights %.0f-%.0f | div %.2f | real %.0f%% forced %.0f%% solved %.0f%%" % [
		run["escalation"], int(run["esc_n"]),
		run["hp_p10"] * 100.0, run["hp_p50"] * 100.0, run["hp_p90"] * 100.0,
		run["fights_p10"], run["fights_p90"],
		run["divergence"],
		run["dd_real"] * 100.0, run["dd_forced"] * 100.0, run["dd_solved"] * 100.0]

func _measure_run(dungeon_id: String, deck: Array[CardData], relics: Array = [],
		roster: Array = [], mode: int = Policy.SMART, trials: int = TRIALS,
		clears: int = 0, power: PowerData = null) -> Dictionary:
	var dd := Balance.dungeon(dungeon_id)
	var difficulty: int = dd.difficulty if dd != null else 1
	var completed := 0
	var fights_total := 0
	var avoided_total := 0
	var avoidable_total := 0
	# --- the fun block (D229) --------------------------------------------------------------
	# Per-TRIAL, because the four numbers here are about the shape of a run and the report has
	# only ever kept means. A mean cannot tell one coin-flip cell from two populations.
	var hp_left: Array = []       # end-of-run HP as a fraction of max; a death is 0.0
	var fights_seen: Array = []   # fights survived, which separates dying on the boss from floor 1
	var esc_ratios: Array = []    # last fight's damage-per-turn over the first fight's
	var deck_sigs: Array = []     # the SET of card ids each run finished with
	_dd_reset()
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
		# What the floor has lent this run so far (D230). Empty unless `--spoils=` is set, and
		# thrown away with the trial — which is the whole model: found power that leaves.
		var spoils: Array = []
		# Damage per turn in this run's FIRST fight and its most recent one. The ratio of the
		# two is the escalation this run actually delivered — the Dungeon Run feeling as one
		# number, and the acceptance test for every step of D226.
		var dpt_first := -1.0
		var dpt_last := -1.0
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
					# `spoils` goes in the UNTAXED slot: its effects apply, and `power_ratio`
					# is computed against `relics` alone, so the enemies do not scale to it.
					# That exemption is the entire experiment (D230).
					eng.setup(run_deck, hp, max_hp, difficulty, tier,
						String(node.get("enemy", "")), relics, roster,
						power, dd.boss if dd != null else "", spoils)
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
					# Read off the same tally the game reads (D204). `_t` skips a zero, so a
					# fight that landed nothing has no `damage` key at all — hence `.get`.
					var ft := eng.fight_tally()
					var f_turns := maxi(1, int(ft.get(Balance.TALLY_TURNS, 1)))
					var f_dpt := float(int(ft.get(Balance.TALLY_DAMAGE, 0))) / float(f_turns)
					if f_dpt > 0.0:
						if dpt_first < 0.0:
							dpt_first = f_dpt
						dpt_last = f_dpt
					if eng.lost():
						alive = false
						var nd: int = int(cost_n.get(enc_kind, 0)) + 1
						var pd: float = float(cost_est.get(enc_kind, 0.0))
						cost_est[enc_kind] = pd + (float(hp_before) - pd) / float(nd)
						cost_n[enc_kind] = nd
					else:
						hp = eng.player.hp
						# Relic: heal after victory (D180). `combat.gd:_win()` does exactly
						# this and the sim did not, so Healing Idol measured as WORSE than
						# nothing — it costs ratio points, which raise enemy scaling, and
						# returned no HP against the one metric (run completion) that is
						# pure attrition. Applied before the cost estimate below, because
						# what a fight here costs is what it costs AFTER the heal; that is
						# the number the driver is deciding on.
						# Between-fights relic effects read the FULL set, spoils included, or a
						# lent Healing Idol would be the D180 bug reintroduced by the flag that
						# is supposed to measure past it.
						var all_relics: Array = relics.duplicate()
						all_relics.append_array(spoils)
						var heal := Balance.relic_field_sum(all_relics, "heal_after_combat")
						if heal > 0:
							hp = mini(max_hp, hp + heal)
						# The floor pays for the fight (D230). One per win until the budget is
						# spent, which front-loads them relative to a real dungeon where only
						# elites and pockets pay — deliberately, because this is measuring the
						# CEILING of untaxed power and a stingier schedule measures a schedule.
						if SPOILS > 0 and spoils.size() < SPOILS:
							var pool := _spoils_pool()
							if not pool.is_empty():
								spoils.append(pool[randi() % pool.size()])
						# the driver's only source of "what does a fight here cost me"
						var n: int = int(cost_n.get(enc_kind, 0)) + 1
						var prev: float = float(cost_est.get(enc_kind, 0.0))
						cost_est[enc_kind] = prev + (float(hp_before - hp) - prev) / float(n)
						cost_n[enc_kind] = n
						# Relic: gold percentage (D180). Modelled for completeness and
						# because the field exists; the report does not read `gold`, so
						# this changes no number today. Written anyway so the next thing
						# that DOES read it is not quietly measuring a game without
						# Merchant's Seal in it.
						var g := Balance.gold_reward(difficulty, tier, randi() % 6)
						g += int(round(float(g)
							* float(Balance.relic_field_sum(relics, "gold_percent")) / 100.0))
						gold += g
						var t_rw := Time.get_ticks_usec()
						var won_card := _reward_card(dungeon_id, reward_level)
						_tick("rewards", t_rw)
						if won_card != null:
							run_deck.append(won_card)
						tv.clear_pending()
		fights_total += fights
		var won_run := alive and tv.is_complete()
		if won_run:
			completed += 1
		# A death is 0.0 rather than the HP it died holding, which is none: the point of the
		# spread is that p10 = 0 reads as "the bottom decile died" without a second column.
		hp_left.append((float(hp) / float(maxi(1, max_hp))) if won_run else 0.0)
		fights_seen.append(float(fights))
		# Only a run that had at least two fights HAS an escalation, and a run that never
		# landed damage has no ratio at all rather than a ratio of zero. Excluded rather than
		# defaulted, because a default would drag the mean toward a number nobody measured.
		if dpt_first > 0.0 and dpt_last > 0.0 and fights >= 2:
			esc_ratios.append(dpt_last / dpt_first)
		var sig := {}
		for c2 in run_deck:
			sig[c2.id] = true
		deck_sigs.append(sig)
	hp_left.sort()
	fights_seen.sort()
	esc_ratios.sort()
	# Divergence over CONSECUTIVE pairs, not all of them: every pair is 80,000 comparisons at
	# 400 trials for a number that reads the same off 400. Jaccard on the id SET, so a run that
	# took the same ten cards in a different order is correctly not a different run.
	var div_sum := 0.0
	var div_n := 0
	for i in maxi(0, deck_sigs.size() - 1):
		var a: Dictionary = deck_sigs[i]
		var b: Dictionary = deck_sigs[i + 1]
		var inter := 0
		for k in a:
			if b.has(k):
				inter += 1
		var uni: int = a.size() + b.size() - inter
		if uni > 0:
			div_sum += 1.0 - float(inter) / float(uni)
			div_n += 1
	return {
		"complete": float(completed) / float(trials),
		"avg_fights": float(fights_total) / float(trials),
		"avg_avoided": float(avoided_total) / float(trials),
		# of the encounters that COULD be dodged, how many were: 0.0 here for a whole
		# report is the signal that the driver is ignoring the mechanic again
		"avoid_rate": float(avoided_total) / float(maxi(1, avoidable_total)),
		# --- the fun block (D229). Diagnostic, none of it pass/fail: a fun metric with a
		# threshold becomes a thing that gets tuned toward instead of a thing that gets read.
		"escalation": (esc_ratios[esc_ratios.size() / 2] as float) if not esc_ratios.is_empty() else 0.0,
		"esc_n": esc_ratios.size(),
		"hp_p10": _pct(hp_left, 0.10),
		"hp_p50": _pct(hp_left, 0.50),
		"hp_p90": _pct(hp_left, 0.90),
		"fights_p10": _pct(fights_seen, 0.10),
		"fights_p90": _pct(fights_seen, 0.90),
		"divergence": (div_sum / float(div_n)) if div_n > 0 else 0.0,
		"dd_real": float(_dd_real) / float(maxi(1, _dd_calls)),
		"dd_forced": float(_dd_forced) / float(maxi(1, _dd_calls)),
		"dd_solved": float(_dd_solved) / float(maxi(1, _dd_calls)),
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
	# A wall already within reach is the cheapest optional thing on the floor, and it has to
	# be taken EXPLICITLY: a push is ranked dead last on purpose (D182), so a driver that
	# only ever trusted the model's own order would never push once and would silently be
	# the stairs policy wearing the explore flag — D124's shape exactly.
	for i in opts.size():
		# Never a DOOR: this driver does not model the key economy either, so unlocking one
		# would price a route the player cannot take for free (D185).
		if String(opts[i].get("action", "")) == "push" \
				and not bool(opts[i].get("needs_key", false)):
			return i
		# A toll is answered with the right number, never guessed: the answer is a fact about
		# the floor the driver is standing on, so a competent player has it too, and guessing
		# would put a coin flip inside a clear-rate measurement (D186/D26).
		if String(opts[i].get("action", "")) == "answer" \
				and int(opts[i]["say"]) == tv.toll_answer(
					String(tv.pockets[int(opts[i]["pocket"])].get("toll", ""))):
			return i
	var targets: Array = []
	for i in tv.enc.size():
		if int(tv.enc[i]) == TraversalIso.KEY:
			targets.append(i)
		elif int(tv.enc[i]) >= 0 and tv._in_pocket(i):
			# The prize behind a wall this run has already pushed — and the ONE line that
			# separates the two explore routes (D183). A guard is declinable at zero cost, so
			# declining it is simply not making it a destination: the explorer looks at what is
			# standing there, turns round, and keeps the turns they spent looking. What the
			# guards cost is then the difference between the two reports.
			if ROUTE == ROUTE_GUARDS or not _guard_between(tv, i):
				targets.append(i)
	# ...and the floor BESIDE an unopened mouth, because a mouth is rock and no flood over
	# walkable ground can route to it. Standing there is what offers the push.
	for p in tv.pockets:
		var pd: Dictionary = p
		if bool(pd["open"]) or String(pd.get("lock", "")) == Balance.POCKET_LOCK_KEY \
				or bool(pd.get("missed", false)):
			continue
		for raw in tv._neighbours(int(pd["mouth"])):
			if int(tv.enc[int(raw)]) != TraversalIso.WALL:
				targets.append(int(raw))
	for sc in tv.sites:
		if int(tv.enc[int(sc)]) >= 0:
			targets.append(int(sc))     # an optional thing standing in the open (D185)
	if targets.is_empty():
		return -1
	var field := _explore_field(tv, targets)
	var best := -1
	var best_d := 1 << 30
	for i in opts.size():
		var o: Dictionary = opts[i]
		if String(o.get("action", "")) == "avoid":
			continue
		var cell := int(o["cell"])
		if tv._is_exit(cell):
			continue
		var d := int(field[cell])
		if d >= 0 and d < best_d:
			best_d = d
			best = i
	return best

## Is something still standing in the pocket this cell belongs to?
##
## Asked of the POCKET rather than of the tile in front, because a pocket is a dead end: if a
## guard is alive anywhere in it, it is between the explorer and everything deeper. Once it is
## beaten its tile is bare ground and the prize is free, which is what makes the fight a
## purchase rather than a toll.
func _guard_between(tv: TraversalIso, cell: int) -> bool:
	var k := tv._pocket_of(cell)
	if k < 0:
		return false
	for c in (tv.pockets[k]["cells"] as Array):
		if int(tv.enc[int(c)]) == Traversal.Enc.ELITE:
			return true
	return false

## Steps to the nearest optional thing, with the way on treated as solid.
##
## Descent is one-way, so a route through the stairs is a route this driver cannot take —
## and a field that offers one makes it pace between two tiles until the move guard trips,
## which reads in the report as a dungeon nobody can finish. The same flood
## `tests/test_traversal.gd`'s second walker uses, for the same reason; it lives in both
## because it is a property of the POLICY, not of the model.
func _explore_field(tv: TraversalIso, sources: Array) -> PackedInt32Array:
	var n := tv.enc.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue: Array = []
	for s in sources:
		var i := int(s)
		if i >= 0 and i < n and int(tv.enc[i]) != TraversalIso.WALL and dist[i] < 0 \
				and not tv._is_exit(i):
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := int(queue[head])
		head += 1
		for raw in tv._neighbours(cur):
			var nb := int(raw)
			if int(tv.enc[nb]) == TraversalIso.WALL or dist[nb] >= 0 or tv._is_exit(nb):
				continue
			dist[nb] = dist[cur] + 1
			queue.append(nb)
	return dist

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
	if ROUTE != ROUTE_STAIRS and tv != null:
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
		# Bramble Armour rather than Survival Instinct (D204): the thorns build's own
		# payoff, and the row has to hold the mechanic or it cannot price it.
		"deck": _deck({"hack": 3, "cover": 4, "riposte": 3, "sharp_ground": 2, "bristle": 1, "iron_will": 2, "bramble_armour": 2}, 15),
		"dungeons": ["slag_pits", "abyssal_stair", "the_maw"],
		"hp_mult": 1.0,
	})
	# --- the two archetypes D204 created, and the reason they are here at all ------
	#
	# AGENTS.md states the rule these rows exist to satisfy: check that a profile
	# actually HOLDS the thing you changed. D124 is the standing example — twelve
	# profiles with no draw relic between them reported "no measurable effect" for a
	# hand cap that fires on 77% of a real draw build's fights. A combo mechanic is
	# worse in that respect than a relic, because its whole value is in the sequence: a
	# deck that holds one enabler and no payoff measures it at zero and looks like proof.
	out.append({
		"name": "Combo build (Lv15)",
		"clears": 5, "power_level": 2,
		# Enablers AND payoffs, in the same deck, at a ratio a player would actually
		# assemble. The cheap cards are the point rather than filler — they are what
		# Grinding Down and Last Word are counting.
		"deck": _deck({"nick": 3, "jab": 2, "read_ahead": 2, "whetted_edge": 2,
			"grinding_down": 2, "rally": 2, "last_word": 1, "cover": 2}, 15),
		"dungeons": ["foundry", "sunken_vault", "drowned_market"],
		"hp_mult": 1.0,
	})
	out.append({
		"name": "Exhaust build (Lv15)",
		"clears": 5, "power_level": 2,
		# Cull is the engine: it burns the hand, and the three payoffs are paid by the
		# count. The 0-cost exhausting cards feed the same tally on their way past.
		# ONE epic, matching its peers. The first draft held two Red Minds, and an epic at
		# Lv15 is near its own cap (`LEVEL_RATE_BY_RARITY` is 5.70 there): a traced Maw boss
		# fight had it hitting for 190 a card while `per_exhausted` had contributed nothing
		# at all, and the row cleared d8 at 98% on five clears. That was a deck two rarities
		# richer than the Thorns and AoE rows it is read beside — the profile was the finding,
		# not the cards, and a row that is not the player it claims to be answers a question
		# nobody asked.
		# No Lifedrain, deliberately, even though the exhaust BUILD names it. The Vampire
		# row below is what that card belongs to for measuring purposes: lifesteal turns out
		# to be the strongest axis in the instrument by a distance, and one copy of it in
		# here is one variable too many. This row exists to answer what `per_exhausted` and
		# `exhaust_hand` are worth, so it holds those and nothing that would answer for them.
		"deck": _deck({"hack": 3, "cover": 3, "cull": 2, "red_mind": 1, "decapitate": 1,
			"focus": 2, "see_it_coming": 1, "kick": 1, "bandage": 2}, 15),
		"dungeons": ["slag_pits", "sunken_vault", "the_maw"],
		"hp_mult": 1.0,
	})
	out.append({
		# NOT a D204 archetype, and that is why it is here. The Exhaust row above was
		# drafted holding two Lifedrains and cleared d8 at 98% on five clears; a traced
		# boss fight showed why, and it was nothing to do with `per_exhausted` — a 1-cost
		# lifesteal card at Lv15 was landing 91 damage and healing 91 of it, twice a turn.
		# `leech`, `exsanguinate` and `sanguine_feast` have all been in the catalogue for
		# a hundred decisions and `Balance.BUILDS` has named a vampire build the whole
		# time, and there has never been a row that holds one. The finding belongs to
		# lifesteal, so it gets its own row rather than living inside somebody else's.
		"name": "Vampire build (Lv15)",
		"clears": 5, "power_level": 2,
		"deck": _deck({"hack": 3, "cover": 4, "leech": 3, "lifedrain": 2, "bite": 2,
			"iron_lung": 1, "second_heart": 1}, 15),
		"dungeons": ["sunken_vault", "drowned_market", "the_maw"],
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
		# D180, and it is D124's finding a second time in a different noun. The relic
		# catalogue splits into flat numbers (+max HP, start with Block, +gold%) and the
		# eleven that FIRE on something, and the report held ten relics of which nine
		# were flat. Measured over the whole table before this row existed:
		#
		#     ON_KILL           2 relics in the catalogue, 0 ever fired in a report
		#     ON_CARDS_PLAYED   2, 0
		#     ON_HP_BELOW_PCT   2, 0
		#     ON_BLOCK_EXPIRED  1, 0
		#     ON_TURN_START     4, 2
		#
		# Four of the five trigger kinds never fired once, while every one of those
		# relics is charged for in `power_ratio` — enemies scale up for a strength the
		# tool had never watched anybody deliver. That is precisely the shape of the
		# hand-kept-list bug the art check had (D89): the coverage was whatever the
		# profiles happened to hold, and nothing asked what they missed.
		#
		# One relic per trigger kind, chosen so each fires on a DIFFERENT condition
		# rather than stacking one:
		#   crown_of_thorns  ON_KILL           - needs a multi-enemy fight to matter
		#   bone_charm       ON_KILL           - the draw half of the same trigger
		#   duelists_glove   ON_CARDS_PLAYED   - needs a hand that empties
		#   field_kit        ON_CARDS_PLAYED   - the draw half again
		#   reliquary_heart  ON_HP_BELOW_PCT   - needs the fight to actually go badly
		#   weighted_soles   ON_BLOCK_EXPIRED  - needs Block left unspent
		#   lucky_penny      ON_TURN_START     - the only ENERGY grant in the catalogue
		#
		# Lucky Penny is here on the EFFECT axis rather than the trigger axis, and that
		# distinction is the second half of the coverage finding: `Trigger` and `Effect`
		# are separate enums and covering one says nothing about the other. With the
		# five triggers covered, `GAIN_ENERGY` was still 1 in the catalogue and 0
		# measured — and energy is the constraint `power_ratio` is defined against, so
		# of all the gaps that was the one least affordable to leave.
		#
		# Surgeon's Thread is deliberately LEFT OUT of this row: it is a second
		# ON_HP_BELOW_PCT and pairing it with Reliquary Heart would measure the two
		# together and neither alone. It is carried by the between-fights row below
		# instead. Seven relics is a late-game loadout, so deck and clears match `Late`.
		#
		# The dungeons are the two where these can show their work: a roster that spawns
		# groups (so ON_KILL has more than one thing to kill) and one deep enough that
		# HP actually falls far enough to cross a threshold.
		"name": "Triggered relics (Lv40 + 6)",
		"clears": 8, "power_level": 3,
		"deck": _deck({"hack": 6, "cover": 4, "stave_in": 4, "shoulder": 3,
			"black_tide": 3}, 40),
		# The Maw was here and came out at 3% with the driver dodging 1.6 of its fights —
		# "a row that reads zero measures nothing", the same trap the Draw profile above
		# records. These seven relics carry no `bonus_max_hp` between them, so this is a
		# ratio-19 deck on a 140 HP bar: it over-reaches two dungeons earlier than the
		# `Late` row does, and the informative cells are shallower than its ratio suggests.
		"dungeons": ["warrens", "sunken_vault", "drowned_market"],
		"hp_mult": 1.0,
		"relics": _relics(["crown_of_thorns", "bone_charm", "duelists_glove",
			"field_kit", "reliquary_heart", "weighted_soles", "lucky_penny"]),
		# Exempt from the progression dressing (D208): this row is an INSTRUMENT, not a
		# player. Its whole value is that the seven relics in it are the only ones in it —
		# the paragraph above turns on "these seven carry no `bonus_max_hp` between them",
		# and topping it up to eight would put max HP into the one row built to prove a
		# trigger fires without one. What it measures is a relic; what it costs is that its
		# clears figure describes a player who would be wearing more.
		"fixed_relics": true,
	})
	out.append({
		# The other half of D180: a relic whose whole effect is between fights. Healing
		# Idol measured as strictly WORSE than no relic at all until `_measure_run`
		# learned to apply `heal_after_combat`, because it costs ratio points — which
		# raise enemy scaling — and returned nothing against a metric that is pure
		# attrition across five or six fights. This row is what keeps that honest: it is
		# the only profile whose strength is invisible inside a single fight, so every
		# per-fight column will read the same as an unrelic'd deck and only RUN moves.
		"name": "Between-fights relics (Lv15)",
		"clears": 4, "power_level": 2,
		"deck": _deck({"hack": 5, "cover": 5, "stave_in": 3, "shoulder": 3}, 15),
		"dungeons": ["foundry", "sunken_vault"],
		"hp_mult": 1.0,
		"relics": _relics(["healing_idol", "surgeons_thread", "iron_ration"]),
		# Exempt for the same reason as the row above (D208), and more sharply: the claim
		# in this comment is that every per-fight column reads like an unrelic'd deck and
		# only RUN moves. One flat relic from the ladder falsifies that sentence, and the
		# sentence is the check — it is how a reader can tell the heal is being delivered
		# between fights rather than smuggled in inside one.
		"fixed_relics": true,
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
	# Every row is dressed in the relics its clears have already paid for (D208). Applied
	# here rather than written into each row so that a profile added later cannot forget:
	# the omission this fixes was in eleven of fifteen rows, which is what a rule kept by
	# hand looks like once there are enough of them.
	for p in out:
		if bool(p.get("fixed_relics", false)):
			continue
		p["relics"] = _worn_relics(int(p.get("clears", 0)), p.get("relics", []))
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

## Every relic in the catalogue, for `--spoils=`. Loaded once: the flag draws from it per fight
## and `load()` on thirty resources per draw dominated the run before this was cached.
##
## The WHOLE catalogue, deliberately — not the depth-gated pool `MetaState.unowned_relics()`
## serves. This measurement asks what untaxed power does to a run, and gating the draw by clears
## would answer a different question with the same flag while looking like the same one.
var _spoil_pool: Array = []

func _spoils_pool() -> Array:
	if not _spoil_pool.is_empty():
		return _spoil_pool
	# `MetaState.RELIC_CATALOG` is the one list of what relics exist, and it maps id -> path, so
	# the path is read from it rather than rebuilt out of `RELIC_DIR` — a second way of naming
	# the same file is the D34 shape, and this tool has been bitten by it (D34 itself).
	for id in MetaState.RELIC_CATALOG:
		var r := load(String(MetaState.RELIC_CATALOG[id])) as RelicData
		if r != null:
			_spoil_pool.append(r)
	return _spoil_pool

func _relics(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var r := load(Balance.RELIC_DIR + id + ".tres") as RelicData
		if r != null:
			out.append(r)
	return out

## The relics a player standing here would already be WEARING (D208).
##
## D180 fixed how relics are *applied* and left untouched how many the profiles hold. Every
## boss beaten hands one out — `combat.gd` calls `MetaState.grant_relic(Tier.BOSS)` on the
## clear, unconditionally — and relics are permanent, explicitly not lost on death. So a
## player with eight clears wears at least eight relics, and this table held rows of three,
## five and six clears with **none at all**.
##
## The two halves of one progression disagreed inside a single profile: `clears` was already
## growing the HP bar through `Balance.max_hp_for`, so the report paid the player for their
## clears in hit points and took the relics those same clears handed them back off again.
##
## A FLOOR and not an estimate. Elites drop into escrow too and a repeat clear grants again,
## so a real player at this depth wears more than this; one per distinct clear is the count
## that cannot be argued down. Erring low keeps the fix from being a gift.
func _worn_relics(clears: int, held: Array) -> Array:
	var out: Array = held.duplicate()
	var ids := {}
	for r in out:
		ids[String(r.id)] = true
	for id in _relic_ladder():
		if out.size() >= clears:
			break
		if ids.has(id):
			continue
		var r := load(Balance.RELIC_DIR + String(id) + ".tres") as RelicData
		if r != null:
			out.append(r)
			ids[id] = true
	return out

## The ORDER relics arrive in, rolled once against the boss table's own weights.
##
## Read out of `MetaState.RELIC_CATALOG` rather than restated here — the catalogue is the
## only list of what the game can actually hand out, and a hand-kept copy is the D89/D180
## coverage bug lying in wait for the thirty-first relic. MetaState is an autoload, so a
## headless `--script` run has no instance of it; the constant is read off the GDScript
## itself, which is the same list by the same name.
##
## Seeded, so two runs of this report measure the same player rather than differing by
## whatever the loadout roll did (D120's noise floor is 0.4 points; a different relic set is
## a much larger difference wearing the same clothes). Drawn WITHOUT replacement and taken
## from the front, so a deeper profile's set contains a shallower one's: relics accumulate,
## and a ladder that did not nest could hand Endgame a weaker set than Late and break the
## monotonicity `tests/test_balance.gd` checks for.
const RELIC_LADDER_SEED := 4180
static var _ladder: Array = []

static func _relic_ladder() -> Array:
	if not _ladder.is_empty():
		return _ladder
	var ms := load("res://scripts/meta_state.gd") as GDScript
	var catalog: Dictionary = ms.get_script_constant_map().get("RELIC_CATALOG", {})
	var pool: Array = catalog.keys()
	pool.sort()                       # the roll decides the order, not the file system
	var rng := RandomNumberGenerator.new()
	rng.seed = RELIC_LADDER_SEED
	var wtbl: Array = Balance.WEIGHTS[Balance.Tier.BOSS]
	var guard := 0
	while not pool.is_empty() and guard < 200:
		guard += 1
		var weights: Array = []
		var total := 0
		for id in pool:
			var r := load(String(catalog[id])) as RelicData
			var w: int = int(wtbl[clampi(r.rarity if r != null else 0, 0, wtbl.size() - 1)])
			weights.append(w)
			total += w
		var roll := rng.randi_range(0, maxi(1, total) - 1)
		var pick: int = pool.size() - 1
		for i in pool.size():
			roll -= int(weights[i])
			if roll < 0:
				pick = i
				break
		_ladder.append(String(pool[pick]))
		pool.remove_at(pick)
	return _ladder

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
	if eng.play_cost(c) <= 0:
		return true
	return _energy_the_rest_of_the_hand_can_use(eng, c) < eng.energy - eng.play_cost(c)

## What the rest of the hand could already spend this turn. Costs are summed rather
## than fitted to a knapsack because the question is whether the hand REACHES the
## energy, not which cards fill it — and which cards fill it is decided by the passes
## below, on merit, which is the whole point of not deciding it here.
func _energy_the_rest_of_the_hand_can_use(eng: CombatEngine, skip: CardData) -> int:
	var total := 0
	for c in eng.hand:
		if c != skip:
			total += int(_live_cost(eng, c))
	return total

## True if the enemy can be killed with the energy in hand this turn.
func _try_lethal(eng: CombatEngine) -> bool:
	var total := 0
	var budget := eng.energy
	var plan: Array[CardData] = []
	# greedy by damage per energy
	var pool := eng.hand.duplicate()
	pool.sort_custom(func(a, b):
		return float(eng.card_damage(a)) / _live_cost(eng, a) \
			> float(eng.card_damage(b)) / _live_cost(eng, b))
	# The plan is priced against the CURRENT board, so a card that gets better for
	# being played third (`per_card_played`, `empower_next`) is undercounted here. That
	# is the safe direction and deliberately left alone: this pass only decides whether
	# to COMMIT to lethal, so undercounting declines a kill that would have worked,
	# while overcounting spends the whole hand and blocks nothing.
	for c in pool:
		var live_cost := _live_cost(eng, c)
		if eng.card_damage(c) > 0 and live_cost <= float(budget):
			budget -= int(live_cost)
			plan.append(c)
			var foe0 := eng.current_target()
			if foe0 != null:
				total += foe0.predicted_damage(eng.card_damage(c))
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
					and eng.enemy.hp > eng.card_damage(c) * 2:
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
## What a card is worth, and what it costs, IF PLAYED RIGHT NOW.
##
## Every pass in this driver used to read `eff_damage()` / `eff_block()` / `eff_cost()`
## — the card's authored numbers — and that made this instrument blind to every
## conditional mechanic in the game, the D66 axes as well as the D204 ones. Split read
## as 4 damage into a target holding six Poison; Grinding Down read as 3 on the fifth
## card of a turn; Stave In read as a 1-cost 3-damage bargain and then swallowed the
## whole pool. A deck built on any of them measured as weak, and the reason was not the
## deck: the player driving it could not see what it was holding.
##
## That is D124 restated — an instrument that cannot play the build cannot price it —
## and it is the reason these two functions exist rather than a fourth inlined copy of
## `eff_damage()`. `card_damage` and `card_block` are the same functions the card FACE
## reads, so the driver now sees exactly what a player would see, and `Balance` owns the
## rule that an X-cost card costs the turn rather than its authored 1.
func _live_value(eng: CombatEngine, c: CardData, want_damage: bool) -> int:
	return eng.card_damage(c) if want_damage else eng.card_block(c)

func _live_cost(eng: CombatEngine, c: CardData) -> float:
	# `play_cost` for the discount, `card_energy_cost` for the X card. Both matter: a
	# discounted card that still prices at its authored cost is passed over, and an X
	# card that prices at 1 is picked first and ends the turn.
	if c.spend_all_energy:
		return maxf(1.0, Balance.card_energy_cost(c))
	return maxf(1.0, float(eng.play_cost(c)))

## A hand-burner is played LAST, or not at all.
##
## `exhaust_hand` prices its own payoff off the hand it is about to destroy, so
## `_best_by_value` reads Cull as the most Block per energy anything in the hand offers
## and opens every single turn with it — burning the cards the rest of the turn was
## going to be made of. That is not a player, it is the same compulsion `_draw_is_worth_it`
## documents one screen up.
##
## Measured before this guard, at 120 trials: the Exhaust build's NORMAL fights at the
## Slag Pits ran 8.9 turns and won 78%, against 4.5 turns and 100% for the Thorns build
## in the same dungeon on the same progression. The deck was not weak. The driver was
## throwing it away, and would have reported that as a verdict on the cards.
##
## The rule is a COMPARISON, and the first draft of it was not. "Never while anything else
## is affordable" swung the policy the whole way to the other end: with three energy and a
## hand of 0- and 1-cost cards something is always affordable, so Cull went from being
## played every turn to never being played at all, and the row reported an exhaust build
## whose enabler had not fired once. A guard that turns a mechanic off measures the same
## nothing as a policy that abuses it.
##
## So: burn only if the burner out-values the best thing it would destroy. That is the
## judgement a person makes at the card, it can go either way on the same hand, and it is
## the same "on merit, and re-read after every play" standard the passes below hold
## everything else to.
func _burn_is_worth_it(eng: CombatEngine, c: CardData) -> bool:
	if not c.exhaust_hand:
		return true
	var best_lost := 0
	for other in eng.hand:
		if other != c and eng.can_play(other):
			best_lost = maxi(best_lost, maxi(eng.card_damage(other), eng.card_block(other)))
	return maxi(eng.card_damage(c), eng.card_block(c)) >= best_lost

## Decision density (D229). This function is where the driver chooses WHICH card, so it is the
## one place in the tool that can say whether a choice existed. It already scores every legal
## play and keeps only the winner; the runner-up is thrown away, and the gap between the two is
## the whole measurement.
##
## Counted per CALL rather than per turn, because a turn asks this question more than once —
## once for damage, once for block, once per pass of `_spend_rest` — and each of those is a
## separate choice among the hand. Reset by `_measure_run` at the start of a cell and read at
## the end of it, so the number belongs to the run fights and not to the per-tier diagnostics
## `_measure` plays afterwards.
##
## Three buckets, because "no decision" has two different causes and only one of them is a
## complaint about the CARDS:
##   * forced  — one legal play, or none. Nothing was chosen. A hand problem, not a card problem.
##   * solved  — the best play is worth 3x the next. The turn plays itself.
##   * real    — the best two are within 25%. This is the number that should go up.
## The remainder is the ordinary middle and is not reported: it is whatever is left.
var _dd_forced := 0
var _dd_solved := 0
var _dd_real := 0
var _dd_calls := 0

func _dd_reset() -> void:
	_dd_forced = 0
	_dd_solved = 0
	_dd_real = 0
	_dd_calls = 0

func _best_by_value(eng: CombatEngine, want_damage: bool) -> CardData:
	var best: CardData = null
	var best_val := 0.0
	var second_val := 0.0
	var legal := 0
	for c in eng.hand:
		if not eng.can_play(c) or not _burn_is_worth_it(eng, c):
			continue
		var amount: int = _live_value(eng, c, want_damage)
		if amount <= 0:
			continue
		var val := float(amount) / _live_cost(eng, c)
		legal += 1
		if val > best_val:
			second_val = best_val
			best_val = val
			best = c
		elif val > second_val:
			second_val = val
	# A call with NOTHING legal is not a decision that went badly, it is a question that did not
	# apply: this function is asked separately for damage and for block, and a hand holding no
	# block card at all answers the block question with zero candidates. Counting those as
	# "forced" inflated the share to 62% on the first run of this block and would have been read
	# as "most turns have no decision in them", which is a claim about the CARDS made out of an
	# artifact of how the driver asks. Excluded from the denominator entirely.
	if legal == 0:
		return best
	_dd_calls += 1
	if legal == 1:
		_dd_forced += 1
	elif second_val <= 0.0 or best_val >= second_val * 3.0:
		_dd_solved += 1
	elif best_val <= second_val * 1.25:
		_dd_real += 1
	return best
