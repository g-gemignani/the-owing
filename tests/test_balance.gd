## Headless test: balance invariants (D5). These guard the *shape* of the curve,
## not specific win rates — run sim_balance.gd for measured rates.
## Run: godot --headless --script tests/test_balance.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0

	# --- ratio is deck-SIZE invariant: energy is the constraint, not card count ---
	var small := _deck({"hack": 4, "cover": 4})
	var big := _deck({"hack": 8, "cover": 8})
	if abs(Balance.power_ratio(small) - Balance.power_ratio(big)) > 0.001:
		fails += 1; print("FAIL ratio not size-invariant: %.3f vs %.3f" % [
			Balance.power_ratio(small), Balance.power_ratio(big)])

	# --- starter deck defines the baseline (ratio 1.0) ---
	if abs(Balance.power_ratio(small) - 1.0) > 0.001:
		fails += 1; print("FAIL starter ratio != 1.0: %.3f" % Balance.power_ratio(small))

	# --- fusing (higher level) raises the ratio ---
	var lv1 := _deck({"hack": 4, "cover": 4}, 1)
	var lv3 := _deck({"hack": 4, "cover": 4}, 3)
	if Balance.power_ratio(lv3) <= Balance.power_ratio(lv1):
		fails += 1; print("FAIL fusion does not raise ratio")

	# --- ratio is capped ---
	var huge := _deck({"hack": 4, "cover": 4}, 30)
	if Balance.power_ratio(huge) > Balance.POWER_RATIO_CAP + 0.001:
		fails += 1; print("FAIL ratio cap breached ", Balance.power_ratio(huge))

	# --- enemy stats rise monotonically with dungeon depth and tier ---
	for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
		for d in range(1, 8):
			var hp_a := Balance.enemy_max_hp(d, tier, 1.0)
			var hp_b := Balance.enemy_max_hp(d + 1, tier, 1.0)
			if hp_b <= hp_a:
				fails += 1; print("FAIL hp not rising with depth (tier %d, d%d)" % [tier, d])
			var dm_a := Balance.enemy_damage(d, tier, 1.0, 0)
			var dm_b := Balance.enemy_damage(d + 1, tier, 1.0, 0)
			if dm_b < dm_a:
				fails += 1; print("FAIL damage falling with depth (tier %d, d%d)" % [tier, d])
	for d in range(1, 6):
		var n := Balance.enemy_max_hp(d, Balance.Tier.NORMAL, 1.0)
		var e := Balance.enemy_max_hp(d, Balance.Tier.ELITE, 1.0)
		var b := Balance.enemy_max_hp(d, Balance.Tier.BOSS, 1.0)
		if not (n < e and e < b):
			fails += 1; print("FAIL tier HP ordering at d%d: %d/%d/%d" % [d, n, e, b])

	# --- enemy stats rise with player power, so progression can't trivialize ---
	for tier in [Balance.Tier.NORMAL, Balance.Tier.BOSS]:
		var weak_hp := Balance.enemy_max_hp(3, tier, 1.0)
		var strong_hp := Balance.enemy_max_hp(3, tier, 2.5)
		if strong_hp <= weak_hp:
			fails += 1; print("FAIL hp does not track player power")
		var weak_dm := Balance.enemy_damage(3, tier, 1.0, 0)
		var strong_dm := Balance.enemy_damage(3, tier, 2.5, 0)
		if strong_dm <= weak_dm:
			fails += 1; print("FAIL damage does not track player power (invulnerability risk)")

	# --- the ratchet: getting stronger must FEEL stronger ---
	#
	# This replaces a guard on the ratio between DMG_POWER_K and HP_POWER_K. That
	# guard encoded the old design, in which enemies matched the player without
	# limit at every depth — measured at depth 3 as quadrupling deck power costing
	# 68% MORE HP per fight. The property that actually matters is attrition, so
	# test attrition directly rather than the constants that happen to produce it.
	for d in [1, 3, 6]:
		var weak_loss := _hp_lost_per_fight(d, 1.0)
		var strong_loss := _hp_lost_per_fight(d, Balance.POWER_RATIO_CAP)
		if strong_loss >= weak_loss:
			fails += 1
			print("FAIL power is punished at d%d: starter loses %.1f HP/fight, maxed loses %.1f" % [
				d, weak_loss, strong_loss])
	# --- the curve must not flatline (D45) ---
	#
	# Measured before this guard existed: every profile past mid-game cleared every
	# dungeon at 100% losing single-digit HP, because Block scales linearly with
	# deck power while enemy damage cannot. Roughly 80% of the content had no
	# resistance left in it, and nothing in the suite noticed.
	if Balance.ratio_ceiling(_deepest()) < Balance.MAX_ACHIEVABLE_RATIO:
		fails += 1
		print("FAIL deepest ceiling %.2f is under the strongest reachable deck %.2f — it gets outgrown" % [
			Balance.ratio_ceiling(_deepest()), Balance.MAX_ACHIEVABLE_RATIO])
	var maxed_loss := _hp_lost_per_fight(_deepest(), Balance.MAX_ACHIEVABLE_RATIO)
	if maxed_loss < 5.0:
		fails += 1
		print("FAIL the deepest dungeon costs a maxed deck %.1f HP a fight — no resistance left" % maxed_loss)
	# and Block alone must never be a complete answer at depth
	if Balance.pierce_fraction(_deepest()) <= 0.0:
		fails += 1
		print("FAIL nothing at depth bypasses Block, so a block deck takes zero damage")
	# ...while the first dungeon stays answerable with a shield
	if Balance.pierce_fraction(1) > 0.05:
		fails += 1; print("FAIL the tutorial dungeon already pierces Block")

	# --- and the endgame must not go soft again as power keeps climbing (D52) ---
	#
	# D45's guard asks whether a MAXED deck still loses HP at depth, and it passed
	# while the deepest dungeon was cleared 100% of the time by every late profile.
	# The reason it passed is the reason the plateau existed: past the build band,
	# more power made the deepest floor EASIER, because enemy HP grew at half the
	# rate of the player's damage, so fights got shorter and fewer hits landed. The
	# property to pin is therefore the SHAPE of the curve at depth, not one point on
	# it — attrition may flatten, but it must never turn back downwards.
	# Fight LENGTH is the mechanism, so length is what gets asserted. Attrition per
	# fight is the wrong probe here: it kept rising the whole time the plateau
	# existed (pierce alone lifts it), while the runs themselves were free, because
	# a shorter fight simply hands out fewer opportunities to be hit. Verified by
	# reverting HP_POWER_K_HIGH to 0 — the HP-loss version of this check passed.
	var floor_turns := _fight_turns(_deepest(), Balance.HIGH_POWER_FLOOR)
	for r in [4.0, 5.0, Balance.MAX_ACHIEVABLE_RATIO]:
		var turns := _fight_turns(_deepest(), r)
		if turns < floor_turns - 0.05:
			fails += 1
			print("FAIL fights in the deepest dungeon SHORTEN with power: %.1f turns at ratio %.1f vs %.1f at the floor — every point of power buys fewer hits taken" % [
				turns, r, floor_turns])
	# the shallow end must keep the opposite property, or this undid the ratchet
	if _hp_lost_per_fight(1, Balance.MAX_ACHIEVABLE_RATIO) >= _hp_lost_per_fight(1, 1.0):
		fails += 1
		print("FAIL the tutorial dungeon no longer gets easier as you grow — the ratchet is gone")

	# ...but depth must still be dangerous: a maxed deck cannot walk the deepest floor
	var deepest := _deepest()
	if Balance.ratio_ceiling(deepest) < Balance.POWER_RATIO_CAP:
		fails += 1
		print("FAIL deepest dungeon (d%d) stops scaling at %.2f, below the power cap %.2f" % [
			deepest, Balance.ratio_ceiling(deepest), Balance.POWER_RATIO_CAP])
	# and difficulty must come from depth: deeper hurts more at equal power
	for r in [1.0, Balance.POWER_RATIO_CAP]:
		if _hp_lost_per_fight(deepest, r) <= _hp_lost_per_fight(1, r):
			fails += 1; print("FAIL depth is not the difficulty axis at ratio %.1f" % r)

	# --- and power must pay at the BOSS too, which is where it did not (D300) ---
	#
	# The pillar is *"HP lost per fight must fall as you get stronger, at any fixed depth"*, and
	# `_hp_lost_per_fight` below has always asked it of `Tier.NORMAL`. The boss is the fight that
	# decides a run, and it is the tier where the property inverted: `tier_hp_power_k(BOSS)` was
	# 1.00, which makes boss HP scale exactly with the player's output, so turns-to-kill was FLAT
	# at 38.8 from ratio 2 to ratio 14 while turns-to-die fell 4.4 to 2.1. **A stronger deck killed
	# no faster and died twice as fast.**
	#
	# Stated as a pure comparison of `enemy_max_hp` against the ratio, because a deck's output is
	# proportional to its ratio by construction — so `hp / ratio` IS turns-to-kill, up to a
	# constant that cancels. No model of a deck is needed and none can go stale.
	# Swept across the range real decks reach rather than two points, because
	# `HP_POWER_K_HIGH` adds a second term above `HIGH_POWER_FLOOR` and a pair straddling it
	# reports whatever the pair happened to bracket: at ratio 12 this passed at k=0.85 and at
	# ratio 18 the same constant fails. The price audit puts live profiles between 1 and 18.
	for d in [1, 3, 5, 8]:
		for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
			var t_lo := float(Balance.enemy_max_hp(d, tier, 2.0)) / 2.0
			for r_any in [4.0, 6.0, 9.0, 12.0, 15.0, 18.0]:
				var r := float(r_any)
				var t_hi := float(Balance.enemy_max_hp(d, tier, r)) / r
				# Strict below `HIGH_POWER_FLOOR`; a bounded regression is allowed above it,
				# because D52 put `HP_POWER_K_HIGH` there ON PURPOSE to stop the endgame going
				# soft, and that term is tier-blind. **The allowance is what makes this a check
				# on the tier constant rather than a demand that D52 be deleted** — at
				# `tier_hp_power_k(BOSS)` = 1.00 the boss ran 20% over and still fails it.
				var allow := 1.10 if r > Balance.HIGH_POWER_FLOOR else 1.0
				if t_hi / t_lo >= allow:
					fails += 1
					print("FAIL at d%d a %s takes %.0f%% LONGER to kill at ratio %.0f than at ratio 2 — getting stronger buys nothing at this tier (D300)" % [
						d, Balance.TIER_NAME[tier], (t_hi / t_lo - 1.0) * 100.0, r])
					break

	# --- the dungeon answers only part of your fusing (D291) ---
	#
	# The shape, not one point on it. A grind that pays nothing until a threshold and then
	# everything is the fault this replaces, so what gets asserted is that it pays SMOOTHLY and
	# that it stops paying without limit.
	for lv in [1, 5, Balance.PRICED_LEVEL_FULL]:
		if Balance.priced_level(lv) != lv:
			fails += 1
			print("FAIL Lv%d is discounted: the first %d levels must be priced in full, or a new player is scaled for growth they have not had (D36)" % [
				lv, Balance.PRICED_LEVEL_FULL])
	var last := 0
	for lv in range(1, 101):
		var pl := Balance.priced_level(lv)
		if pl < last:
			fails += 1
			print("FAIL priced_level went backwards at Lv%d: %d after %d" % [lv, pl, last])
			break
		if pl > lv:
			fails += 1
			print("FAIL Lv%d is priced ABOVE itself, at %d" % [lv, pl])
			break
		# Two levels of slack at the boundary, not none: the discount is `round((lv - cap) * share)`
		# and at a half share the first level above the cap rounds to nothing. That is the integer
		# arithmetic doing what it must, not the rule failing — the claim is that the discount
		# ARRIVES, and it has to be asserted somewhere it can.
		if lv >= Balance.PRICED_LEVEL_FULL + 2 and pl >= lv:
			fails += 1
			print("FAIL Lv%d is priced at %d — nothing above the cap is discounted" % [lv, pl])
			break
		last = pl

	# What the player actually gets: delivered power per energy over priced power per energy.
	var free_at := func(lv: int) -> float:
		var d: Array[CardData] = []
		for i in 14:
			var fc := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
			fc.level = mini(lv, fc.level_cap())
			d.append(fc)
		var pd := Balance.priced_deck(d)
		return (Balance.deck_power(d) / Balance.deck_cost(d)) \
			/ maxf(0.001, Balance.deck_power(pd) / Balance.deck_cost(pd))
	if abs(free_at.call(Balance.PRICED_LEVEL_FULL) - 1.0) > 0.001:
		fails += 1
		print("FAIL a deck at the cap is already getting free strength: %.2fx" % free_at.call(Balance.PRICED_LEVEL_FULL))
	if free_at.call(40) <= 1.05:
		fails += 1
		print("FAIL fusing to Lv40 buys %.2fx — the grind still pays nothing, which is what D291 exists to fix" % free_at.call(40))
	# ...and BOUNDED. D230's yardstick: eight free relics moved escalation 1.09x to 1.18x, so free
	# strength on the whole deck belongs nearer 1.5x than 3x. A share of 0 would fail here, which
	# is the flat cap D291 measured and rejected for rising without limit.
	if free_at.call(100) > 2.5:
		fails += 1
		print("FAIL a maxed deck fights as if %.2fx stronger than it is priced — that is a difficulty change wearing a grind reward's clothes" % free_at.call(100))

	# Pricing the POWER at the capped level and the cost at the real one would raise the ratio
	# rather than lower it, because `deck_cost` is the divisor. Both halves, or neither.
	var fused: Array[CardData] = []
	for i in 14:
		var fu := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		fu.level = 40
		fused.append(fu)
	var priced_view := Balance.priced_deck(fused)
	if Balance.deck_cost(priced_view) < Balance.deck_cost(fused) - 0.001:
		fails += 1
		print("FAIL the priced view is CHEAPER to play than the real deck — only the power was capped")
	# ...and that `power_ratio` divides by the priced view rather than the real one. Asserted as
	# SOURCE, which is what this file already does for the simulator, because the behavioural
	# version cannot be written: `power_ratio` prices whatever deck it is handed, so there is no
	# way to hand it an un-capped one to compare against, and a threshold between the right answer
	# and the wrong one would be a number nobody could defend.
	#
	# It is worth the source assertion because the mutation is INVISIBLE on most cards. Only a
	# rule-only card buys its energy cost down with level (`CardData._cost_budget`), so on a deck
	# of Hack — which is what the behavioural checks above use — capping the power and not the
	# cost changes nothing at all and every one of them passes.
	var balsrc := FileAccess.open("res://scripts/balance.gd", FileAccess.READ)
	if balsrc == null:
		fails += 1; print("FAIL balance.gd is missing")
	else:
		var bal := balsrc.get_as_text()
		balsrc.close()
		if bal.find("deck_power(priced) / deck_cost(priced)") == -1:
			fails += 1
			print("FAIL power_ratio does not divide by the PRICED cost — levelling buys a rule-only card's energy down, so pricing one half raises the ratio instead of lowering it (D291)")
	# and the view must not have mutated the deck it was taken from
	for fu in fused:
		if fu.level != 40:
			fails += 1
			print("FAIL priced_deck mutated the cards it was given")
			break

	# --- a run is priced on what you BROUGHT, not on what it gave you (D299) ---
	#
	# Behavioural rather than a source grep, because the rule lives in one line of
	# `CombatEngine.setup` and the failure is silent: pricing the whole deck again produces a
	# harder game that looks exactly like a tuning change.
	var brought: Array[CardData] = []
	for i in 12:
		var hb := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		hb.level = 10
		brought.append(hb)
	var e_base := CombatEngine.new()
	e_base.setup(brought, 100, 100, 3, Balance.Tier.NORMAL)
	var base_ratio := e_base.ratio

	# Six strong cards FOUND must not move the number the enemies scale against...
	var grown: Array[CardData] = brought.duplicate()
	for i in 6:
		var hf := (load(CARD_DIR + "heavy_swing.tres") as CardData).duplicate()
		hf.level = 40
		hf.found_in_run = true
		grown.append(hf)
	var e_found := CombatEngine.new()
	e_found.setup(grown, 100, 100, 3, Balance.Tier.NORMAL)
	if abs(e_found.ratio - base_ratio) > 0.001:
		fails += 1
		print("FAIL a found card moved the priced ratio: %.3f -> %.3f (D299)" % [
			base_ratio, e_found.ratio])

	# ...and the same six BROUGHT must, or the ratchet has been switched off rather than aimed.
	for c in grown:
		c.found_in_run = false
	var e_owned := CombatEngine.new()
	e_owned.setup(grown, 100, 100, 3, Balance.Tier.NORMAL)
	if e_owned.ratio <= base_ratio + 0.001:
		fails += 1
		print("FAIL bringing six strong cards did not raise the priced ratio — the ratchet is off, not aimed")

	# A deck of nothing but found cards cannot happen, but an empty priced set would divide by
	# `deck_cost`'s floor and price a whole deck as one card.
	var all_found: Array[CardData] = []
	for i in 12:
		var ha := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		ha.level = 10
		ha.found_in_run = true
		all_found.append(ha)
	var e_all := CombatEngine.new()
	e_all.setup(all_found, 100, 100, 3, Balance.Tier.NORMAL)
	if abs(e_all.ratio - base_ratio) > 0.001:
		fails += 1
		print("FAIL an all-found deck priced at %.3f rather than falling back to %.3f" % [
			e_all.ratio, base_ratio])

	# The marker has to survive the run save, or quitting and resuming re-prices the rewards.
	var state := CombatEngine._cards_to_state(all_found)
	if state.is_empty() or not bool(state[0].get("found", false)):
		fails += 1
		print("FAIL the run save does not record which cards were found (D299)")

	# --- the simulator must model the player the game actually gives you --------
	#
	# Three of these were silently false, and together they made the tool report a
	# game roughly twice as dangerous as the one being played:
	#
	#   * max HP grew with the DIFFICULTY of the dungeon measured, where the game
	#     grows it with dungeons CLEARED — 60 HP at the Crypt for a player who
	#     really has 120;
	#   * the equipped Power was never passed, so every run was measured without the
	#     ability every save carries;
	#   * the dungeon's named boss was never passed, so the finale was a roster
	#     enemy wearing boss multipliers (the very bug D41 fixed in the game);
	#   * and the deck never grew, so the boss was always fought with the opening
	#     deck rather than the five-to-eight cards richer one a real run arrives at.
	#
	# Asserted as source, because a tool cannot be unit-tested into honesty and the
	# failure mode is silence: every one of these produced plausible numbers.
	var simsrc := FileAccess.open("res://tools/sim_balance.gd", FileAccess.READ)
	if simsrc == null:
		fails += 1; print("FAIL the balance simulator is missing")
	else:
		var sim := simsrc.get_as_text()
		simsrc.close()
		if sim.find("Balance.BASE_MAX_HP +") != -1:
			fails += 1
			print("FAIL the simulator restates the max-HP formula; call Balance.max_hp_for")
		for needed in [["_power_of(profile)", "the equipped Power"],
				["dd.boss", "the dungeon's named boss"],
				["_reward_card(", "cards won during the run"],
				["Balance.effective_gate(", "the clears a dungeon requires"],
				# D238. This row used to demand `_worn_relics(` — the helper that dressed every
				# profile in the relics its clears had paid for (D208), because a boss dropped one
				# per clear and relics were never lost. Relics do not persist any more, so that
				# guarantee is gone and dressing a profile in them would model a player the game
				# cannot produce. What must be modelled instead is ARRIVAL, which is `--spoils=`.
				["SPOILS", "relics arriving DURING a run rather than owned before it"],
				# ...and the untaxed slot, which is the whole of why the escalation is free.
				["p_untaxed", "relics reaching the fight without raising enemy scaling"]]:
			if sim.find(String(needed[0])) == -1:
				fails += 1
				print("FAIL the simulator does not model %s" % needed[1])
		# ...and that the priced slot is EMPTY at the call. `p_untaxed` present in the file while
		# `relics` is still passed as priced would satisfy the check above and scale the enemies to
		# the relics anyway — the same silent pass D180's first guard had, where writing ABOUT the
		# fix satisfied a check meant to see the code do it.
		if sim.find("String(node.get(\"enemy\", \"\")), [], roster,") == -1:
			fails += 1
			print("FAIL the simulator still prices relics into enemy scaling (D238)")
		if sim.find("func _worn_relics") != -1:
			fails += 1
			print("FAIL _worn_relics is back — profiles must not wear relics they cannot own (D238)")
		# D276, and the same shape as the two above: the tool must make the decision the GAME makes,
		# and the failure mode is a report that reads fine. The reward screen lays out
		# `REWARD_CARD_OFFERS` cards with a Skip under them. The driver took one at random and kept
		# it, so a third of the cards it accepted were ones the screen calls "WEAKER than what you
		# hold". Asserting the CALL rather than the function, because `_choose_card` present in the
		# file while the call site still asks `_reward_card` directly is D180's silent pass again —
		# the fix written down and not wired up.
		# The call moved from `_choose_card` to `_choose_bundle` when the reward became a bundle of
		# cards rather than one (D297). The ASSERTION is unchanged in what it is about: the driver
		# must choose its reward against the deck that would take it. Only the name of the thing
		# doing the choosing moved, and a guard that kept the old name would have gone quiet on the
		# exact turn the surface it guards was rewritten — which is D88's harness selecting by name.
		if sim.find("_choose_bundle(dungeon_id, reward_level, run_deck)") == -1:
			fails += 1
			print("FAIL the simulator does not choose its card reward against the run deck (D276, D297)")
		# ...and that it takes the WHOLE bundle. A driver that appended one card of the two would
		# be measuring half a reward, and the deck-growth number is the one this change exists for.
		if sim.find("for wc in won:") == -1:
			fails += 1
			print("FAIL the simulator does not take the whole bundle it chose (D297)")

		# --- every profile must be a deck the game can actually be brought (D208, D297) ---
		#
		# D208's rule, made mechanical: *"is this profile a player the game can produce?"* It cost
		# 42 cells a mean of +17 points the last time it was answered by hand, and the failure is
		# silent — a 20-card starting deck under a cap of 14 measures fine and models nobody.
		#
		# Parsed out of the source rather than by running the tool, because `_profiles()` is an
		# instance method on a SceneTree script and this suite cannot instantiate one. The regex
		# reads the same `_deck({...})` literals a reader does; a profile written some other way
		# would go unchecked, which is why the count of what it FOUND is asserted too — a pattern
		# that silently matches nothing is the vacuous guard D86 was written about.
		var found := 0
		var re := RegEx.create_from_string("_deck\\(\\{([^}]*)\\}")
		var num := RegEx.create_from_string(":\\s*(\\d+)")
		for m in re.search_all(sim):
			found += 1
			var n := 0
			for q in num.search_all(m.get_string(1)):
				n += int(q.get_string(1))
			if n > Balance.MAX_DECK_SIZE:
				fails += 1
				print("FAIL a simulator profile brings %d cards, over MAX_DECK_SIZE %d — it models a player the deck builder would refuse (D208)" % [
					n, Balance.MAX_DECK_SIZE])
		if found < 15:
			fails += 1
			print("FAIL only %d profile decks found in the simulator — the guard has stopped matching them" % found)

	# --- reward must climb at least as fast as risk ---
	#
	# Once a strong deck can outgrow a shallow dungeon, a flat reward curve makes
	# farming the easiest floor strictly optimal. Measured before the fix: d1 -> d8
	# was 10x the HP lost for 1.8x the gold.
	var shallow_gold := _run_gold(1)
	var deep_gold := _run_gold(deepest)
	if deep_gold < shallow_gold * 3:
		fails += 1
		print("FAIL depth pays too little: d1 %dg vs d%d %dg (farming the shallows wins)" % [
			shallow_gold, deepest, deep_gold])

	# --- attrition must exist: fights long enough for the enemy to attack more
	#     than once, and resting must not erase several fights of damage.
	#     (Regression: normals once died in 2 turns for ~3 HP while rest healed 18.)
	var floor_hp := Balance.MIN_FIGHT_TURNS * Balance.BASELINE_TURN_DAMAGE
	for d in range(1, 5):
		var nhp := Balance.enemy_max_hp(d, Balance.Tier.NORMAL, 1.0)
		if nhp < floor_hp:
			fails += 1; print("FAIL normal enemy too fragile at d%d: %d < %.0f (fights end before attrition)" % [
				d, nhp, floor_hp])
	if Balance.REST_HEAL_FRAC > 0.25:
		fails += 1; print("FAIL rest heal too large -> erases attrition")

	# --- scaling must never plateau ---
	#
	# A hard ratio cap is itself a power-creep bug: past it, every further point of
	# player power is free. Measured exactly that — fully-equipped late decks pinned
	# the old cap and cleared the deepest dungeons 100% of the time.
	var prev_r := 0.0
	# straddle the knee wherever it currently sits: a literal list stopped doing
	# that the moment POWER_RATIO_CAP moved past 6.0, and then asserted that a
	# DESCENDING sequence ascended
	var knee: float = Balance.POWER_RATIO_CAP
	for raw in [1.0, knee * 0.25, knee * 0.5, knee, knee + 0.5, knee * 1.5,
			knee * 2.5, knee * 5.0]:
		var soft: float = Balance.soften_ratio(raw)
		if soft <= prev_r:
			fails += 1; print("FAIL scaling plateaus at raw ratio %.1f (%.2f)" % [raw, soft])
		prev_r = soft
	# below the cap it must be untouched, or early balance shifts
	if abs(Balance.soften_ratio(2.0) - 2.0) > 0.001:
		fails += 1; print("FAIL softening altered a below-cap ratio")
	# and the tail must stay diminishing, not runaway
	var a := Balance.soften_ratio(Balance.POWER_RATIO_CAP + 1.0)
	var b := Balance.soften_ratio(Balance.POWER_RATIO_CAP + 4.0)
	if (b - a) >= 3.0:
		fails += 1; print("FAIL softened tail grows too fast (runaway scaling)")
	# Below its ceiling a dungeon still answers the player; above it, deliberately
	# not. Beyond the power cap the answer is ascension, which multiplies enemy
	# stats outside the ceiling — not an ever-rising floor of enemy HP.
	var mid_ceiling: float = Balance.ratio_ceiling(5)
	if Balance.enemy_max_hp(5, Balance.Tier.BOSS, mid_ceiling) \
			<= Balance.enemy_max_hp(5, Balance.Tier.BOSS, 1.0):
		fails += 1; print("FAIL a dungeon does not scale to the player below its ceiling")
	if Balance.enemy_max_hp(5, Balance.Tier.BOSS, mid_ceiling + 3.0) \
			!= Balance.enemy_max_hp(5, Balance.Tier.BOSS, mid_ceiling):
		fails += 1; print("FAIL a dungeon keeps scaling past its ceiling (no ratchet)")

	# --- block must be priced below damage ---
	#
	# Damage does double duty: it removes enemy HP and thereby shortens the fight,
	# which prevents damage in turn. Block only mitigates, and escalation makes a
	# long fight a worse fight. Pricing them equally charged block-heavy decks for
	# power that never shortened a fight.
	if CardData.BLOCK_VALUE >= 1.0:
		fails += 1; print("FAIL block is priced at or above damage (%.2f)" % CardData.BLOCK_VALUE)
	if CardData.BLOCK_VALUE < 0.4:
		fails += 1; print("FAIL block priced so low that defensive decks are undercharged")
	# adding block must raise the ratio LESS than adding the same amount of damage
	var base_deck := _deck({"hack": 4, "cover": 4})
	var plus_dmg := _deck({"hack": 5, "cover": 4})
	var plus_blk := _deck({"hack": 4, "cover": 5})
	var r_base: float = Balance.power_ratio(base_deck)
	var r_dmg: float = Balance.power_ratio(plus_dmg)
	var r_blk: float = Balance.power_ratio(plus_blk)
	if not (r_dmg > r_blk and r_blk > r_base * 0.99):
		fails += 1
		print("FAIL block/damage pricing wrong: base %.3f, +block %.3f, +damage %.3f" % [
			r_base, r_blk, r_dmg])

	# --- a strictly stronger loadout must scale to a higher ratio, never lower ---
	# (an "endgame" profile once measured WORSE than a weaker one; it turned out to
	# be a different, worse deck rather than a stronger one, but the check is cheap)
	var lv1_deck := _deck({"hack": 4, "cover": 4, "stave_in": 2}, 1)
	var lv40_deck := _deck({"hack": 4, "cover": 4, "stave_in": 2}, 40)
	if Balance.power_ratio(lv40_deck) <= Balance.power_ratio(lv1_deck):
		fails += 1; print("FAIL levelling the same deck did not raise its ratio")
	var relic := load(Balance.RELIC_DIR + "iron_heart.tres") as RelicData
	if relic != null and Balance.power_ratio(lv40_deck, [relic]) <= Balance.power_ratio(lv40_deck):
		fails += 1; print("FAIL adding a relic did not raise the ratio")

	# --- deck bounds sane ---
	if Balance.MIN_DECK_SIZE >= Balance.MAX_DECK_SIZE:
		fails += 1; print("FAIL deck bounds inverted")

	if fails == 0:
		print("BALANCE TEST: PASS (ratio invariants, monotonic scaling, no invulnerability)")
	else:
		print("BALANCE TEST: FAIL (%d)" % fails)
	quit()

## Turns a normal fight lasts at this depth and deck power. The player's damage
## grows with the ratio; the question is whether the enemy's HP keeps up.
func _fight_turns(dungeon: int, ratio: float) -> float:
	var hp := float(Balance.enemy_max_hp(dungeon, Balance.Tier.NORMAL, ratio))
	var throughput: float = Balance.BASELINE_CARD_POWER * float(Balance.MAX_ENERGY) * ratio
	return hp / maxf(1.0, throughput * Balance.OFFENSE_SHARE)

## HP the player loses clearing one normal fight.
##
## Models BLOCK, which the first version of this helper did not — and that omission
## is exactly why the difficulty curve was able to flatline unnoticed. A deck spends
## roughly half its throughput on Block, Block scales linearly with deck power, and
## enemy damage deliberately does not. Ignore Block and the numbers say the deepest
## dungeon costs 58 HP a fight; include it and the truth was zero.
func _hp_lost_per_fight(dungeon: int, ratio: float) -> float:
	var hp := Balance.enemy_max_hp(dungeon, Balance.Tier.NORMAL, ratio)
	var dmg := float(Balance.enemy_damage(dungeon, Balance.Tier.NORMAL, ratio, 0))
	var throughput: float = Balance.BASELINE_CARD_POWER * float(Balance.MAX_ENERGY) * ratio
	var turns: float = float(hp) / maxf(1.0, throughput * Balance.OFFENSE_SHARE)
	# the share of a hit Block cannot touch, plus whatever Block fails to cover
	var pierced: float = dmg * Balance.pierce_fraction(dungeon, ratio)
	# Not all of a deck's Block is available when it is needed: you hold what you
	# drew, not what you wanted. Calibrated against tools/sim_balance.gd, where a
	# starter deck loses ~8% of 60 HP per fight in the Crypt — assuming perfect
	# allocation the model said zero, which is how this helper first "proved" that
	# a starter deck takes no damage.
	const BLOCK_EFFICIENCY := 0.65
	var block: float = throughput * (1.0 - Balance.OFFENSE_SHARE) \
		/ CardData.BLOCK_VALUE * BLOCK_EFFICIENCY
	var per_turn: float = pierced + maxf(0.0, (dmg - pierced) - block)
	return turns * per_turn

## Gold from a typical clear: eight normals, an elite, a boss.
func _run_gold(dungeon: int) -> int:
	var g := 8 * Balance.gold_reward(dungeon, Balance.Tier.NORMAL, 3)
	g += Balance.gold_reward(dungeon, Balance.Tier.ELITE, 3)
	g += Balance.gold_reward(dungeon, Balance.Tier.BOSS, 3)
	return g

## Difficulty of the deepest dungeon that exists.
func _deepest() -> int:
	var d := 1
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null:
			d = maxi(d, dd.difficulty)
	return d

func _deck(loadout: Dictionary, level: int = 1) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			var c := (load(CARD_DIR + id + ".tres") as CardData).duplicate()
			c.level = level
			deck.append(c)
	return deck
