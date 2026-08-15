## Relic — power found inside one run, held outside the deck (Phase 7).
## Data-only Resource, one .tres per relic, same convention as cards and enemies.
##
## **A relic does not persist (D238).** It is found in a run, it leaves with the run,
## and `MetaState` has no way to grant one — `grant_relic` is deleted. What survives is
## `MetaState.relics_seen`, a log of what the character has MET, which carries no power.
##
## Every relic MUST still report a `power_value()`, and the reason changed with D238.
## It used to be priced INTO `Balance.power_ratio`, because permanent power that never
## reaches `deck_power` would otherwise outrun enemy scaling (D5/D10). Relics now reach
## the fight through `CombatEngine.setup`'s `p_untaxed` slot and the priced argument is
## `[]`, so the value is read by the offer, the shop price and the rarity bands instead.
## The pillar is unchanged: persistent power lives in the deck and is priced, found
## power is free and temporary.
class_name RelicData
extends Resource

@export var id: String = "iron_heart"
@export var name: String = "Iron Heart"
@export var description: String = "+15 max HP."
@export var rarity: CardData.Rarity = CardData.Rarity.COMMON

@export_group("Run effects")
@export var bonus_max_hp: int = 0

@export_group("Combat start")
@export var start_block: int = 0
@export var start_strength: int = 0
@export var start_dexterity: int = 0

@export_group("Per turn")
@export var bonus_energy: int = 0
@export var extra_draw: int = 0

@export_group("Rewards")
@export var heal_after_combat: int = 0
@export var gold_percent: int = 0

## Modifiers on the resolve pipeline (D233). Everything above changes a NUMBER; these change a
## RULE, and that is the whole reason they exist.
##
## D230 measured the pool and found 5 relics of 30 that raise what a turn is worth, against 11
## that keep you alive. Lending a run eight free relics moved the escalation from 1.09x to 1.18x
## — arithmetic, not a fault in the exemption. A pool of numbers cannot escalate, because enemy
## scaling is denominated in the same numbers.
##
## Each field is read at exactly one chokepoint, and D204 already forced every consumer of a
## card's numbers through those four functions — `play_cost`, `card_damage`, `card_block` and
## `_resolve`. That is why this is seven fields and not a rewrite.
@export_group("Rule modifiers")
## Every card costs this much less, floored at 0. Read by `play_cost`.
@export var cost_reduction: int = 0
## The first card each turn costs nothing. Read by `play_cost`.
@export var free_first_card: bool = false
## Percent added to every attack's damage. Read by `card_damage`.
@export var damage_pct: int = 0
## Percent added to every card's Block. Read by `card_block`.
@export var block_pct: int = 0
## Single-target attacks hit every living enemy. Read by `_resolve`.
@export var attacks_hit_all: bool = false
## Block is not cleared at the start of your turn. Read by `start_turn`.
@export var block_carries: bool = false
## The first attack each turn resolves a second time. Read by `_resolve`.
@export var repeat_first_attack: bool = false
## Debuffs you apply do not decay on the target. Read by `end_turn`.
@export var debuffs_persist: bool = false
## A debuff aimed at one enemy lands on all of them. Read by `_resolve`.
@export var debuffs_spread: bool = false
## Every kill refunds this much Energy. Read by `_resolve`.
@export var energy_per_kill: int = 0
## Exhausted cards go to the discard pile instead of out of the fight. Read by `_resolve`.
@export var exhaust_returns: bool = false

## The second batch (D257), converting the last relics that moved only a number.
##
## D233's seven and D243's four are all UNCONDITIONAL: hold the relic, get the percent, every turn
## of every fight. That is why the pool ran out of room — a seventh flat `damage_pct` is the sixth
## one with a different number on it, and `breaks_a_rule()` counts it while a player cannot tell
## them apart.
##
## These are conditional or compounding instead, which is what buys escalation the flat ones cannot:
## measured, the whole pool reached `esc` 1.71x against 1.87x for rule-breakers alone, so
## composition had about 9% left in it. A percent that fires only when you are winning, or that
## grows with the kills in a fight, is worth more in fight six than in fight one — and `esc` is
## exactly that ratio.
@export_group("Rule modifiers — conditional")
## Percent added to attacks while exactly one enemy is still standing. Read by `_outgoing`.
@export var lone_damage_pct: int = 0
## Percent added to attacks while you are below half your maximum HP. Read by `_outgoing`.
@export var wounded_damage_pct: int = 0
## Percent added to attacks on the FIRST turn of a fight. Read by `_outgoing`.
@export var opener_damage_pct: int = 0
## Percent added to attacks for each enemy already killed in this fight. Compounds. Read by
## `_outgoing`.
@export var kill_damage_pct: int = 0
## Percent of the damage an attacker deals you that it takes back. Read by `_resolve_enemy`.
@export var retaliate_pct: int = 0
## Percent of an attack's damage healed back to you. Read by `_resolve`.
@export var lifesteal_pct: int = 0
## Block gained for every card played. Read by `_resolve`.
@export var block_per_card: int = 0
## Percent of the Block you still hold at end of turn that heals you. Read by `end_turn`.
@export var block_heals_pct: int = 0

## Does this relic change a RULE rather than a number (D233)?
##
## HERE, beside the fields it reads, and not in `tools/sim_balance.gd` where it lived. That copy
## claimed in its own comment to be *"derived from the modifier fields themselves, so a field added
## later joins without anybody remembering this function"* — and it named seven fields by hand. D243
## added four more (`debuffs_persist`, `debuffs_spread`, `energy_per_kill`, `exhaust_returns`) and
## none of them joined, so `--spoils-rules` measured a "rule-breakers only" pool with six
## rule-breakers missing from it. **A comment that says a thing is derived is not a derivation**
## (D124's family, and D34's).
##
## It cannot be fully derived — `modifier_power()` deliberately excludes `cost_reduction` and
## `free_first_card`, which are priced as throughput in `power_value()`. So two fields are still
## named. The distance between them and the fields they name is now one screen instead of one repo.
##
## **D262 found it blind in the other direction, and this is the third time.** `modifier_power()`
## never reads the trigger arrays, so a relic whose WHOLE identity is a trigger returned false:
## Bone Charm, Field Kit, Lucky Penny and Scholar's Lens all measured as "only a number" while
## carrying no number at all. That is backwards against this file's own definition one screen
## down — *"a trigger is what turns '+2 Strength' into kill something and draw"* — and it is the
## D250 shape exactly, where `changes_a_rule()` skipped `discount_next` for the same reason.
## `trigger_count()` is the term that was missing.
##
## **What it still gets wrong is the OTHER half, and that half is a judgement rather than a bug.**
## Any non-zero `damage_pct` makes `modifier_power()` positive, so the eleven relics that carry one
## flat percent and nothing else are counted here. D257 knew and said so above. Do not read this
## predicate as "the pool has N interesting relics" — measured at D262 the 38 are 11 single flat
## percents, 2 flat energy or draw, 4 pure triggers and 21 conditional rules.
func breaks_a_rule() -> bool:
	return (modifier_power() > 0.0 or cost_reduction > 0 or free_first_card
		or trigger_count() > 0)

## When a triggered effect fires. Relics used to be nine flat stat fields — every
## one of them "+15 max HP" — so a relic changed your numbers but never how you
## played. A trigger is what turns "+2 Strength" into "kill something and draw".
##
## Same shape as EnemyData's conditional rules, deliberately: one proven pattern
## rather than two half-learned ones.
enum Trigger {
	ON_KILL,            ## an enemy dies
	ON_TURN_START,      ## every Nth turn of a fight
	ON_CARDS_PLAYED,    ## the Nth card played within one turn
	ON_HP_BELOW_PCT,    ## the player crosses below threshold% — once per fight
	ON_BLOCK_EXPIRED,   ## Block you did not spend evaporates at turn start
}

## What it does when it fires.
enum Effect {
	DAMAGE_ALL, DRAW, GAIN_BLOCK, GAIN_STRENGTH, HEAL, GAIN_ENERGY,
}

@export_group("Triggered effects")
## Parallel arrays, one entry per effect — same authoring convention as enemy rules.
@export var trigger: PackedInt32Array = PackedInt32Array()
## Meaning depends on the trigger: turn interval, card count, HP percentage.
@export var trigger_threshold: PackedInt32Array = PackedInt32Array()
@export var effect: PackedInt32Array = PackedInt32Array()
@export var effect_value: PackedInt32Array = PackedInt32Array()

func trigger_count() -> int:
	return mini(trigger.size(), mini(effect.size(), effect_value.size()))

func threshold_at(i: int) -> int:
	return trigger_threshold[i] if i < trigger_threshold.size() else 1

## Power of the triggered effects, in CardData.power_value units.
##
## This MUST be priced or a triggered relic is free strength sitting outside the
## deck — exactly the hole that RELIC_POWER_PER_RATIO exists to close, and the same
## mistake that made powers read as +0.9 ratio on the first attempt.
##
## Everything is valued PER FIGHT, using how often the trigger realistically fires
## in a fight of Balance.TARGET_NORMAL_TURNS.
func triggered_power() -> float:
	var v := 0.0
	for i in trigger_count():
		var fires := _expected_fires(i)
		var unit := 0.0
		match effect[i]:
			Effect.DAMAGE_ALL:
				unit = float(effect_value[i]) * 1.35   # AoE premium, as CardData prices it
			Effect.DRAW:
				# The card rate (D224), not the old 1.5. `_expected_fires` already says
				# how OFTEN this happens, so the unit here has to be what one drawn card
				# is worth and nothing else — the same number `CardData` pays for it.
				unit = float(effect_value[i]) * 5.0
			Effect.GAIN_BLOCK:
				unit = float(effect_value[i]) * CardData.BLOCK_VALUE
			Effect.GAIN_STRENGTH:
				unit = float(effect_value[i]) * 4.5
			Effect.HEAL:
				unit = float(effect_value[i]) * 0.8
			Effect.GAIN_ENERGY:
				unit = float(effect_value[i]) * 15.0
		v += unit * fires
	return v

## How many times a trigger is expected to fire in one fight. Deliberately
## conservative: over-pricing a relic makes enemies scale past what the deck can
## actually answer, which is how thorns builds once fell from 69% to 46%.
func _expected_fires(i: int) -> float:
	var turns := float(Balance.TARGET_NORMAL_TURNS)
	match trigger[i]:
		Trigger.ON_KILL:
			return 1.3            # average living enemies per encounter
		Trigger.ON_TURN_START:
			return turns / maxf(1.0, float(threshold_at(i)))
		Trigger.ON_CARDS_PLAYED:
			# roughly one trigger per turn if the threshold is within a turn's plays
			return turns if threshold_at(i) <= 3 else turns * 0.5
		Trigger.ON_HP_BELOW_PCT:
			return 0.5            # once per fight at most, and not every fight
		Trigger.ON_BLOCK_EXPIRED:
			return turns * 0.5    # only when Block goes unspent
	return 1.0

## Flat power, in the same units as CardData.power_value. Excludes energy and
## draw on purpose: those raise throughput *multiplicatively* (see
## Balance.throughput_multiplier), and folding them in additively badly
## undervalues them — +1 of 3 energy is +33% of everything the deck does.
func flat_power() -> float:
	var v := 0.0
	v += bonus_max_hp * 0.5
	v += start_block * 0.8   # block is worth less than damage (CardData.BLOCK_VALUE)
	v += start_strength * 4.5
	v += start_dexterity * 4.0
	v += heal_after_combat * 1.5
	v += gold_percent * 0.3
	v += triggered_power()
	v += modifier_power()
	return v

## Power of the rule modifiers (D233), in the same units as everything above.
##
## These rates are DERIVED where a derivation exists and estimated where none does, and the
## estimates are stated as estimates. Rarity is written from `power_value()` by
## `tools/rerarify.gd` (D224/D225), so a wrong rate here does not produce a mispriced relic
## quietly — it produces a relic in the wrong rarity band, which the rarity suite reports.
##
## `cost_reduction` and `free_first_card` are excluded and priced in `power_value()` instead,
## for the reason `bonus_energy` is: they raise throughput MULTIPLICATIVELY, and folding a
## multiplier in additively badly undervalues it.
func modifier_power() -> float:
	var v := 0.0
	# Derived: a percent of damage is worth that percent of what a card's damage is worth, and
	# CardData prices one point of damage at 1.0. A reference attack of ~6 damage makes +10%
	# worth 0.6 of a point.
	v += float(damage_pct) * 0.6
	# The same, scaled by CardData.BLOCK_VALUE (0.65), which is what block is worth against
	# damage in this game.
	v += float(block_pct) * 0.6 * CardData.BLOCK_VALUE
	# Derived from CardData.AOE_SPREAD (1.35): making every attack an AoE is the same premium
	# the card catalogue already pays for one, so it is priced as +35% damage.
	if attacks_hit_all:
		v += 35.0 * 0.6
	# ESTIMATE. One attack a turn resolves twice, and a turn plays about three cards of which
	# roughly two are attacks, so it is worth about half a turn's attack damage — call it +25%.
	if repeat_first_attack:
		v += 25.0 * 0.6
	# ESTIMATE. Unspent Block is what carries, and a turn that spends all of it carries nothing.
	# Priced as 6 points of block a turn, which is under half a defensive card.
	if block_carries:
		v += 6.0 * CardData.BLOCK_VALUE * float(Balance.TARGET_NORMAL_TURNS) * 0.4
	# ESTIMATE. A stack that never decays is worth roughly the whole fight's worth of re-applying
	# it: about half the debuff cards a status deck would otherwise spend. Priced at two stacks
	# a turn held rather than re-bought.
	if debuffs_persist:
		v += 2.0 * float(Balance.TARGET_NORMAL_TURNS) * 1.5
	# Derived from CardData.AOE_SPREAD, the same way `attacks_hit_all` is: spreading a debuff is
	# the AoE premium applied to the status half of a card.
	if debuffs_spread:
		v += 35.0 * 0.6 * CardData.BLOCK_VALUE
	# ESTIMATE, and priced off GAIN_ENERGY's own rate (15.0 a point) times the kills a fight
	# realistically has — the same 1.3 `_expected_fires` uses for ON_KILL.
	v += float(energy_per_kill) * 15.0 * 1.3
	# ESTIMATE. An exhaust deck's cost is that its engine burns down; returning the cards is
	# worth about the cards it saves, at CardData's 5.0 a card, for two or three a fight.
	if exhaust_returns:
		v += 2.5 * 5.0

	# --- the conditional batch (D257) -------------------------------------------------------
	#
	# Every one is `damage_pct`'s derived rate of 0.6 a point, SCALED BY HOW OFTEN IT FIRES. That
	# is the D243 lesson priced in from the start: compounding the percentages there changed
	# nothing because only two relics carried the field and each relic is unique per run, so the
	# arithmetic was right and had no subjects. **Count how often it fires before you price it.**
	#
	# The fractions are ESTIMATES against a fight of `Balance.TARGET_NORMAL_TURNS`, and they are
	# the honest kind: a wrong one files the relic in the wrong rarity band, which the rarity suite
	# reports, rather than shipping a mispriced relic quietly (D224/D225).

	# One enemy left is the back half of a multi-enemy fight and the whole of a single-enemy one.
	v += float(lone_damage_pct) * 0.6 * 0.45
	# Below half HP is where a run spends its late fights and almost none of its early ones — which
	# is also why this one is worth more than the fraction suggests, and why the fraction and not
	# the rate carries the discount.
	v += float(wounded_damage_pct) * 0.6 * 0.30
	# One turn of about five.
	v += float(opener_damage_pct) * 0.6 * 0.20
	# Compounds, so the average over a fight is roughly half the final stack, and the stack is the
	# 1.3 kills `_expected_fires` already uses for ON_KILL.
	v += float(kill_damage_pct) * 0.6 * 0.65
	# Priced off what it DEALS, not off the percent. An enemy landing about 8 a turn over five turns
	# is 40 damage passing through, and CardData prices one point of damage at 1.0 — so a point of
	# this percent is 0.4 of a point of card damage.
	v += float(retaliate_pct) * 0.4
	# A fight's worth of the player's damage is roughly an encounter's enemy HP, ~40, and healing is
	# CardData's 0.8 a point: 0.4 of a point per percent.
	v += float(lifesteal_pct) * 0.32
	# Three cards a turn for a fight, at CardData.BLOCK_VALUE.
	v += float(block_per_card) * 3.0 * float(Balance.TARGET_NORMAL_TURNS) * CardData.BLOCK_VALUE
	# Block still standing at end of turn is the block that was not spent — the same quantity
	# `block_carries` is priced on, so the same 6 a turn, healed at 0.8 a point.
	v += float(block_heals_pct) / 100.0 * 6.0 * float(Balance.TARGET_NORMAL_TURNS) * 0.8
	return v

## Total worth of the relic, for display and for relic pricing.
##
## `extra_draw` is a card EVERY TURN for the whole run, where `CardData`'s `draw` is a
## card once. At the card's new rate of 5 a card (D224) and a fight of about five
## turns, that is 25 — it was 14, set against a per-card rate of 1.5 that made a
## drawn card a tenth of an energy. The two have to move together or a relic and a
## card that do the same thing are priced from different books.
## `cost_reduction` and `free_first_card` sit here with `bonus_energy` because all three are
## throughput multipliers. Cost reduction is the strongest of the three: +1 energy buys one more
## card of average cost, while -1 on every card buys one more card AND makes the expensive ones
## reachable, so it is priced above it. `free_first_card` is the same effect restricted to one
## card a turn, and the card it frees is the one the player chooses, so it is not a third of it.
func power_value() -> float:
	return flat_power() + bonus_energy * 45.0 + extra_draw * 25.0 		+ cost_reduction * 55.0 + (35.0 if free_first_card else 0.0)
