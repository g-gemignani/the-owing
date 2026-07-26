## Relic — persistent character progression, held outside the deck (Phase 7).
## Data-only Resource, one .tres per relic, same convention as cards and enemies.
##
## Relics are permanent power that never appears in `deck_power`, so every relic
## MUST report a `power_value()`: `Balance.power_ratio` folds it in, otherwise
## collecting relics would silently outrun enemy scaling (see D5/D10).
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
				unit = float(effect_value[i]) * 1.5
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
	return v

## Total worth of the relic, for display and future relic pricing.
func power_value() -> float:
	return flat_power() + bonus_energy * 45.0 + extra_draw * 14.0
