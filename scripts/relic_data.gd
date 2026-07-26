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
	return v

## Total worth of the relic, for display and future relic pricing.
func power_value() -> float:
	return flat_power() + bonus_energy * 45.0 + extra_draw * 14.0
