## A dungeon event: flavour text plus 2-3 choices with declarative effects.
## Data-only Resource, same convention as cards/enemies/relics/dungeons.
##
## Effects are declared, not scripted, so an event cannot quietly break run rules
## (no negative gold, no death by event, no dropping the collection below the
## softlock floor — those are enforced centrally when applied).
class_name EventData
extends Resource

@export var id: String = "shrine"
@export var title: String = "A Quiet Shrine"
@export var description: String = "Something old is listening."

## Parallel arrays: one entry per choice. Kept flat because Godot's inspector
## handles arrays of resources poorly and this stays readable in a .tres.
@export var choice_labels: PackedStringArray = PackedStringArray()
@export var choice_results: PackedStringArray = PackedStringArray()
## Effects per choice.
@export var hp_deltas: PackedInt32Array = PackedInt32Array()
@export var gold_deltas: PackedInt32Array = PackedInt32Array()
## Percent of max HP, applied in addition to hp_deltas (for scaling costs).
@export var hp_percent_deltas: PackedInt32Array = PackedInt32Array()
## 1 = grant a random card from the dungeon pool, -1 = lose a random owned copy.
@export var card_deltas: PackedInt32Array = PackedInt32Array()
## 1 = grant a random unowned relic.
@export var relic_grants: PackedInt32Array = PackedInt32Array()
## 1 = the choice starts an elite fight instead of resolving.
@export var starts_fight: PackedInt32Array = PackedInt32Array()

func choice_count() -> int:
	return choice_labels.size()

func _at(arr: PackedInt32Array, i: int) -> int:
	return int(arr[i]) if i < arr.size() else 0

func hp_delta(i: int) -> int: return _at(hp_deltas, i)
func hp_percent(i: int) -> int: return _at(hp_percent_deltas, i)
func gold_delta(i: int) -> int: return _at(gold_deltas, i)
func card_delta(i: int) -> int: return _at(card_deltas, i)
func relic_grant(i: int) -> int: return _at(relic_grants, i)
func fights(i: int) -> bool: return _at(starts_fight, i) == 1

## What this choice actually does to the purse, at this depth (D224).
##
## Authored `gold_deltas` are flat numbers and this game's economy is not: one fight
## pays 7 gold in the Crypt and 69 in the Maw, and every price in the game is quoted in
## fights for exactly that reason. A flat number is fine for a small favour and wrong
## for the most valuable thing anything can hand over — a relic, which no merchant has
## ever stocked, which death does not take, and which one of these events was selling
## for 60 gold flat: most of a whole shallow run's income, and a fifth of one fight's
## at the bottom of the game.
##
## So a choice that BUYS a relic — grants one, and charges gold for it — is priced from
## `Balance.relic_price` and the authored number is only the sign. Choices that pay in
## HP, in a card or in an elite fight are untouched: those currencies scale with the
## player already, which is what `hp_percent_deltas` is for.
func gold_cost(i: int, difficulty: int = 0) -> int:
	if relic_grant(i) > 0 and gold_delta(i) < 0:
		return -Balance.relic_price(difficulty)
	return gold_delta(i)

## The choice as it should be READ, with any price substituted in.
##
## A label carrying a `%d` is one whose number is derived rather than authored; the
## rest are returned as written. This exists because the price and the words for it
## must come from one place — the version of this that did not have it printed
## "(-60 gold)" on a button that took 1440.
func label(i: int, difficulty: int = 0) -> String:
	var t: String = choice_labels[i] if i < choice_labels.size() else ""
	return (t % absi(gold_cost(i, difficulty))) if t.find("%d") >= 0 else t

func result_text(i: int) -> String:
	return choice_results[i] if i < choice_results.size() else ""
