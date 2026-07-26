## Headless test: balance invariants (D5). These guard the *shape* of the curve,
## not specific win rates — run sim_balance.gd for measured rates.
## Run: godot --headless --script tests/test_balance.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0

	# --- ratio is deck-SIZE invariant: energy is the constraint, not card count ---
	var small := _deck({"strike": 4, "defend": 4})
	var big := _deck({"strike": 8, "defend": 8})
	if abs(Balance.power_ratio(small) - Balance.power_ratio(big)) > 0.001:
		fails += 1; print("FAIL ratio not size-invariant: %.3f vs %.3f" % [
			Balance.power_ratio(small), Balance.power_ratio(big)])

	# --- starter deck defines the baseline (ratio 1.0) ---
	if abs(Balance.power_ratio(small) - 1.0) > 0.001:
		fails += 1; print("FAIL starter ratio != 1.0: %.3f" % Balance.power_ratio(small))

	# --- fusing (higher level) raises the ratio ---
	var lv1 := _deck({"strike": 4, "defend": 4}, 1)
	var lv3 := _deck({"strike": 4, "defend": 4}, 3)
	if Balance.power_ratio(lv3) <= Balance.power_ratio(lv1):
		fails += 1; print("FAIL fusion does not raise ratio")

	# --- ratio is capped ---
	var huge := _deck({"strike": 4, "defend": 4}, 30)
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
	# ...but depth must still be dangerous: a maxed deck cannot walk the deepest floor
	var deepest := 1
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null:
			deepest = maxi(deepest, dd.difficulty)
	if Balance.ratio_ceiling(deepest) < Balance.POWER_RATIO_CAP:
		fails += 1
		print("FAIL deepest dungeon (d%d) stops scaling at %.2f, below the power cap %.2f" % [
			deepest, Balance.ratio_ceiling(deepest), Balance.POWER_RATIO_CAP])
	# and difficulty must come from depth: deeper hurts more at equal power
	for r in [1.0, Balance.POWER_RATIO_CAP]:
		if _hp_lost_per_fight(deepest, r) <= _hp_lost_per_fight(1, r):
			fails += 1; print("FAIL depth is not the difficulty axis at ratio %.1f" % r)

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
	for raw in [1.0, 2.0, 4.0, Balance.POWER_RATIO_CAP, 6.0, 9.0, 15.0, 40.0]:
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
	var base_deck := _deck({"strike": 4, "defend": 4})
	var plus_dmg := _deck({"strike": 5, "defend": 4})
	var plus_blk := _deck({"strike": 4, "defend": 5})
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
	var lv1_deck := _deck({"strike": 4, "defend": 4, "bash": 2}, 1)
	var lv40_deck := _deck({"strike": 4, "defend": 4, "bash": 2}, 40)
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

## HP the player loses clearing one normal fight: how long the fight runs times
## what lands each turn. The single number that says whether power feels good.
func _hp_lost_per_fight(dungeon: int, ratio: float) -> float:
	var hp := Balance.enemy_max_hp(dungeon, Balance.Tier.NORMAL, ratio)
	var dmg := Balance.enemy_damage(dungeon, Balance.Tier.NORMAL, ratio, 0)
	var out: float = Balance.BASELINE_CARD_POWER * float(Balance.MAX_ENERGY) * ratio
	return (float(hp) / maxf(1.0, out)) * float(dmg)

## Gold from a typical clear: eight normals, an elite, a boss.
func _run_gold(dungeon: int) -> int:
	var g := 8 * Balance.gold_reward(dungeon, Balance.Tier.NORMAL, 3)
	g += Balance.gold_reward(dungeon, Balance.Tier.ELITE, 3)
	g += Balance.gold_reward(dungeon, Balance.Tier.BOSS, 3)
	return g

func _deck(loadout: Dictionary, level: int = 1) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			var c := (load(CARD_DIR + id + ".tres") as CardData).duplicate()
			c.level = level
			deck.append(c)
	return deck
