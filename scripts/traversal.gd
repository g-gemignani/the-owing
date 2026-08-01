## How a dungeon is traversed. Base class + shared contract.
##
## One model implements it: `TraversalIso`, the isometric crawl every dungeon uses.
## Three others (a node graph, a card draw, a dice board) were built alongside it and
## deleted in D94 — every dungeon had moved onto the iso floor in D88, so they were
## content nobody could reach, and a dead branch of the tree that still had to be kept
## compiling, serialized, screenshotted and asserted on by four test suites.
##
## The base class stays because the contract is worth stating in one place, and because
## everything else — combat, cards, relics, shops, meta — talks to this interface rather
## than to the crawl. A second model would slot in beside the first; until there is one,
## there is no `Kind` to choose between and no dungeon field naming a choice.
##
## Implementations MUST be pure logic (no UI, no autoloads): the balance simulator
## drives them directly, which is what keeps one generic walker able to measure
## a model instead of needing a bespoke walker each.
##
## Balance contract: a model must spend the attrition budget it is given
## (see Balance.ENCOUNTER_BUDGET). If one dungeon yields 3 fights and another 8,
## "difficulty 4" stops meaning the same thing in different dungeons and the whole
## scaling model decouples.
class_name Traversal
extends RefCounted

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
	var d := {"pending": pending, "cleared": cleared}
	d.merge(_save())
	return d

func load_state(d: Dictionary) -> void:
	pending = d.get("pending", {})
	cleared = int(d.get("cleared", 0))
	_load(d)

func _save() -> Dictionary:
	return {}

func _load(_d: Dictionary) -> void:
	pass

## Rebuild a traversal from a saved blob. Callers screen the blob first — a run saved
## on a model that no longer exists is dropped in `GameState.run_from_dict`, not
## reconstructed here into something half-formed.
static func from_state(d: Dictionary, dungeon_data) -> Traversal:
	var t := TraversalIso.new()
	t.dungeon = dungeon_data
	t.load_state(d)
	return t

# --- shared helpers ---

## The encounter mix for one run of `dungeon`, so every dungeon costs the player a
## comparable amount. Returns an Array of Node values, boss NOT included.
##
## Takes the dungeon because the mix is per-place (DungeonData.encounter_mix): every
## dungeon spends the same budget, but a swarm dungeon and a treasure dungeon do not
## feel like the same walk.
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
