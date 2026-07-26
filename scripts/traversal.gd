## How a dungeon is traversed. Base class + shared contract.
##
## Dungeons can traverse differently (a flooded vault should not navigate like a
## crypt), so traversal is a strategy chosen per DungeonData. Everything else —
## combat, cards, relics, shops, meta — talks only to this interface and never to
## a specific model.
##
## Implementations MUST be pure logic (no UI, no autoloads): the balance simulator
## drives them directly, which is what keeps one generic walker able to measure
## every model instead of needing a bespoke walker each.
##
## Balance contract: every model must spend a comparable attrition budget
## (see Balance.ENCOUNTER_BUDGET). If one model yields 3 fights and another 8,
## "difficulty 4" stops meaning the same thing in different dungeons and the whole
## scaling model decouples.
class_name Traversal
extends RefCounted

## Stored as a raw int in every dungeon .tres, so values may only be APPENDED.
enum Kind { GRAPH, DECK, DICE, ISO }

## Encounter kinds a traversal hands back. Values mirror GameState.NodeType.
## Named Enc, not Node: "Node" would shadow Godot's native class.
enum Enc { COMBAT, ELITE, REST, BOSS, SHOP, EVENT, TREASURE }

var dungeon = null          # DungeonData (untyped to avoid a cyclic dependency)
var pending: Dictionary = {} # the encounter currently being resolved
var cleared: int = 0

# --- interface ---

## Build the dungeon layout. Called once per run.
func generate(p_dungeon) -> void:
	dungeon = p_dungeon

## Choices available right now. Each entry is a Dictionary with at least:
##   {"type": Node, "label": String}
## plus whatever the model's own view needs.
func options() -> Array:
	return []

## Commit to option `i`. Returns the encounter to resolve, or {} if the option was
## handled internally (e.g. paying HP to skip). The view routes on `type`.
func select(i: int) -> Dictionary:
	return {}

## Called once the pending encounter is finished (won, or left in the case of a shop).
func clear_pending() -> void:
	pending = {}
	cleared += 1

## 0..1, for progress display.
func progress() -> float:
	return 0.0

func is_complete() -> bool:
	return false

## Human-readable one-liner for the run's current state.
func status() -> String:
	return ""

## Serialize enough to restore this traversal exactly. Each model owns its own
## format: the base only handles what every model has. Implementations override
## `_save`/`_load` for their own fields.
func save_state() -> Dictionary:
	var d := {"kind": kind(), "pending": pending, "cleared": cleared}
	d.merge(_save())
	return d

func load_state(d: Dictionary) -> void:
	pending = d.get("pending", {})
	cleared = int(d.get("cleared", 0))
	_load(d)

## Which Kind this instance is — needed to rebuild the right model on load.
func kind() -> int:
	return Kind.GRAPH

func _save() -> Dictionary:
	return {}

func _load(_d: Dictionary) -> void:
	pass

## Rebuild a traversal from a saved blob, choosing the model by its stored kind.
static func from_state(d: Dictionary, dungeon_data) -> Traversal:
	var t := make(int(d.get("kind", Kind.GRAPH)))
	t.dungeon = dungeon_data
	t.load_state(d)
	return t

# --- shared helpers ---

## The encounter mix for one run of `dungeon`, so every model costs the player a
## comparable amount. Returns an Array of Node values, boss NOT included.
##
## Takes the dungeon because the mix is now per-place (DungeonData.encounter_mix):
## the same three models still spend the same budget as each other, but a swarm
## dungeon and a treasure dungeon no longer feel like the same walk.
static func standard_encounters(dungeon_data = null) -> Array:
	var mix := {
		"combat": Balance.ENCOUNTER_COMBATS, "elite": Balance.ENCOUNTER_ELITES,
		"rest": Balance.ENCOUNTER_RESTS, "shop": Balance.ENCOUNTER_SHOPS,
		"event": Balance.ENCOUNTER_EVENTS, "treasure": Balance.ENCOUNTER_TREASURES,
	}
	if dungeon_data != null and dungeon_data.has_method("encounter_mix"):
		mix = dungeon_data.encounter_mix()
	var out: Array = []
	for i in int(mix["combat"]):
		out.append(Enc.COMBAT)
	for i in int(mix["elite"]):
		out.append(Enc.ELITE)
	for i in int(mix["rest"]):
		out.append(Enc.REST)
	for i in int(mix["shop"]):
		out.append(Enc.SHOP)
	for i in int(mix["event"]):
		out.append(Enc.EVENT)
	for i in int(mix["treasure"]):
		out.append(Enc.TREASURE)
	return out

static func make(kind: int) -> Traversal:
	match kind:
		Kind.DECK:
			return TraversalDeck.new()
		Kind.DICE:
			return TraversalDice.new()
		Kind.ISO:
			return TraversalIso.new()
		_:
			return TraversalGraph.new()
