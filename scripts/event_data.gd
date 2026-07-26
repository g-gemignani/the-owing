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

func result_text(i: int) -> String:
	return choice_results[i] if i < choice_results.size() else ""
