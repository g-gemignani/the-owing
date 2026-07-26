## Global run state. Autoload singleton — survives scene changes (Map <-> Combat).
## Holds the roguelike RUN state: deck, HP, map, position, progress.
## (Persistent META state — card collection, relics, city quests — layers on later.)
extends Node

## Kept in lockstep with Traversal.Node — combat routes on these values.
enum NodeType { COMBAT, ELITE, REST, BOSS, SHOP, EVENT, TREASURE }

const CARD_DIR := "res://resources/cards/"
const ROWS := 6
const ROW_WIDTHS := [2, 3, 3, 3, 2, 1]  # last row = boss

# --- run state ---
var run_deck: Array[CardData] = []
## The power carried into this run, frozen at the level it had on entry — buying a
## level mid-run must not retroactively strengthen a fight already in progress, and
## the run file has to restore exactly what was equipped.
var run_power: PowerData = null
## Cards thinned out of the deck this run, for the rising removal price.
var run_removals: int = 0
var max_hp: int = 60
var hp: int = 60
var dungeon: int = 1        # difficulty; drives enemy scaling + loot rarity
var dungeon_id: String = ""   # which named dungeon (D6); "" before one is chosen
var current_zone: String = ""  # zone being explored on the overworld
## True when the deck builder was opened to edit loadouts, not to start a run.
var manage_only: bool = false

# --- traversal state ---
## The active traversal model for this run (graph, deck, ...). Null outside a run.
var traversal: Traversal = null
var pending: Dictionary = {}     # node the player selected, handed to Combat/Shop
# --- run escrow (D20) ---
## Cards and gold earned during a run are held here, not committed to MetaState,
## until the dungeon's boss falls. Usable immediately *within* the run (the useful
## half of D1) but forfeited on death or abandonment.
##
## Without this, rewards commit per-encounter, which makes the boss an optional
## risk: clear the easy encounters, bank everything, leave. That was a dominant
## strategy, and a dominant strategy is a broken option.
var escrow_cards: Array = []   # card ids
var escrow_gold: int = 0

## Rolled shop inventory for the node being visited, so re-entering cannot reroll
## it. Cleared on leaving the shop and on run reset.
var shop_stock: Array = []
## Name of the relic just awarded, shown once on the deck builder. "" if none.
var last_relic: String = ""
## One-shot message about what the last run secured or cost.
var last_haul: String = ""
## What the last defeat cost, for the screen that reports it. Dying used to print
## a line of text and force a 2.5 second wait before dumping the player on the
## overworld — the moment escrow, ropes and the death penalty all exist to make
## weigh, and it could not be read, let alone dismissed. Empty means "no death to
## report", which is what a fresh boot and every screen test sees.
var last_defeat: Dictionary = {}
## Slot a new game is being started in, handed to the kit-choice screen.
var pending_new_slot: int = 0

func _ready() -> void:
	reset_run_progress()

## Fresh run: back to dungeon 1, full HP, no deck/map yet.
## The deck-builder screen then calls enter_dungeon() to actually start.
## Earn a card during a run: usable now, permanent only if the run is completed.
func earn_card(id: String) -> void:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	if meta == null or not meta.CATALOG.has(id):
		return
	escrow_cards.append(id)
	var c := (load(meta.CATALOG[id]) as CardData).duplicate()
	# joins at the level the collection already has for that card
	c.level = int(meta.collection[id]["level"]) if meta.collection.has(id) else 1
	run_deck.append(c)

## Thin one card out of the run deck. Run-scoped only: the collection is never
## touched, so a removal cannot cost the player something permanent.
##
## Deliberately NOT free power. Balance.power_ratio is power per energy, so cutting
## a weak card raises the ratio and enemies scale to match — the gain is
## consistency, which is exactly what the player is paying for.
func remove_from_run_deck(card: CardData) -> bool:
	if run_deck.size() <= Balance.MIN_DECK_SIZE:
		return false
	var i := run_deck.find(card)
	if i < 0:
		return false
	run_deck.remove_at(i)
	run_removals += 1
	autosave()
	return true

func can_remove_from_run_deck() -> bool:
	return run_deck.size() > Balance.MIN_DECK_SIZE

func earn_gold(n: int) -> void:
	escrow_gold += maxi(0, n)

## Gold the player can actually spend right now: banked plus at-risk.
func available_gold() -> int:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	var banked: int = meta.gold if meta else 0
	return banked + escrow_gold

## Spend from the at-risk pool first, so a purchase never eats banked gold that
## the player could otherwise have walked away with.
func spend_gold(n: int) -> bool:
	if n <= 0 or available_gold() < n:
		return false
	var from_escrow: int = mini(escrow_gold, n)
	escrow_gold -= from_escrow
	var rest: int = n - from_escrow
	if rest > 0:
		var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
		if meta == null or not meta.spend_gold(rest):
			escrow_gold += from_escrow   # roll back rather than half-charge
			return false
	return true

## Boss cleared: everything earned this run becomes permanent.
func commit_escrow() -> Dictionary:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	var result := {"cards": escrow_cards.size(), "gold": escrow_gold}
	if meta != null:
		for id in escrow_cards:
			meta.add_card(id)
		if escrow_gold > 0:
			meta.add_gold(escrow_gold)
	escrow_cards = []
	escrow_gold = 0
	return result

## Died or walked away: the run's earnings are lost.
func forfeit_escrow() -> Dictionary:
	var result := {"cards": escrow_cards.size(), "gold": escrow_gold}
	escrow_cards = []
	escrow_gold = 0
	return result

# --- run persistence (D22) ---
## Serialized combat, when the player quit mid-fight. Empty otherwise.
var combat_state: Dictionary = {}

func has_run() -> bool:
	return dungeon_id != "" and traversal != null

## The whole run, small enough to live inside the normal save.
func run_to_dict() -> Dictionary:
	if not has_run():
		return {}
	return {
		"dungeon_id": dungeon_id, "dungeon": dungeon, "zone": current_zone,
		"hp": hp, "max_hp": max_hp,
		"deck": CombatEngine._cards_to_state(run_deck),
		"power": run_power.id if run_power != null else "",
		"power_level": run_power.level if run_power != null else 1,
		"removals": run_removals,
		"traversal": traversal.save_state(),
		"escrow_cards": escrow_cards, "escrow_gold": escrow_gold,
		"shop_stock": shop_stock,
		"combat": combat_state,
	}

func run_from_dict(d: Dictionary) -> bool:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	if meta == null or d.is_empty():
		return false
	var did := String(d.get("dungeon_id", ""))
	if not (did in Balance.DUNGEONS):
		return false   # the dungeon was renamed or removed
	dungeon_id = did
	dungeon = int(d.get("dungeon", 1))
	current_zone = String(d.get("zone", ""))
	max_hp = int(d.get("max_hp", Balance.BASE_MAX_HP))
	hp = clampi(int(d.get("hp", max_hp)), 1, max_hp)
	run_deck = CombatEngine._cards_from_state(d.get("deck", []), meta.CATALOG)
	run_removals = int(d.get("removals", 0))
	run_power = null
	var pid := String(d.get("power", ""))
	if pid != "":
		var p := Balance.power(pid)
		if p != null:
			run_power = p.duplicate()
			run_power.level = int(d.get("power_level", 1))
	escrow_cards = []
	for id in d.get("escrow_cards", []):
		if meta.CATALOG.has(id):
			escrow_cards.append(id)
	escrow_gold = maxi(0, int(d.get("escrow_gold", 0)))
	shop_stock = d.get("shop_stock", [])
	combat_state = d.get("combat", {})
	traversal = Traversal.from_state(d.get("traversal", {}), dungeon_data())
	# a restored run with no deck is unplayable; treat it as absent
	if run_deck.is_empty():
		clear_run()
		return false
	return true

func clear_run() -> void:
	traversal = null
	dungeon_id = ""
	combat_state = {}
	shop_stock = []

## Mark the run as needing a write. Called wherever progress could be lost —
## encounter boundaries and every combat action. Writes are coalesced, so a whole
## turn of card plays costs one file write instead of a dozen.
func autosave() -> void:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	if meta != null:
		meta.mark_run_dirty()

## Write now. For moments where losing the last second would matter: death, a
## boss kill, using a rope, quitting.
func flush_save() -> void:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	if meta != null:
		meta.flush()

## Cards obtainable in the current dungeon (zone theme + dungeon exclusives).
func card_pool() -> Array:
	if dungeon_id == "":
		return []
	return Balance.card_pool_for(dungeon_id)

## The DungeonData for the run in progress, or null.
func dungeon_data() -> DungeonData:
	return Balance.dungeon(dungeon_id) if dungeon_id != "" else null

func reset_run_progress() -> void:
	run_deck = []
	run_power = null
	run_removals = 0
	# relics can raise the run's max HP (Phase 7)
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	var relic_hp: int = meta.relic_bonus("bonus_max_hp") if meta else 0
	# permanent max-HP from dungeons already cleared (progression, kept on death)
	var clears: int = meta.clear_count() if meta else 0
	max_hp = Balance.BASE_MAX_HP + relic_hp + clears * Balance.HP_PER_DUNGEON
	hp = max_hp
	dungeon = 1
	dungeon_id = ""
	current_zone = ""
	manage_only = false
	traversal = null
	shop_stock = []
	escrow_cards = []
	escrow_gold = 0
	combat_state = {}

## Choose which named dungeon to attempt (D6). Sets difficulty from its data.
func select_dungeon(id: String) -> void:
	dungeon_id = id
	var d := Balance.dungeon(id)
	dungeon = d.difficulty if d != null else 1

## Start the selected dungeon with a chosen deck (D4: per-dungeon deck).
func enter_dungeon(deck: Array[CardData]) -> void:
	run_deck = deck
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	run_power = meta.power_data() if meta != null else null
	generate_map()

## Advance to the next dungeon after a boss (HP/heal handled by caller).
## Called after clearing a dungeon's boss. Recomputed rather than incremented so
## a relic or clear earned mid-run counts immediately.
func refresh_max_hp() -> void:
	var meta := (get_node_or_null("/root/MetaState") if is_inside_tree() else null)
	var relic_hp: int = meta.relic_bonus("bonus_max_hp") if meta else 0
	var clears: int = meta.clear_count() if meta else 0
	max_hp = Balance.BASE_MAX_HP + relic_hp + clears * Balance.HP_PER_DUNGEON
	hp = max_hp

## Build the traversal for the selected dungeon. Model comes from its data.
func generate_map() -> void:
	var d := dungeon_data()
	traversal = Traversal.make(d.traversal if d != null else Traversal.Kind.GRAPH)
	traversal.generate(d)

## Choices available right now (empty outside a run).
func options() -> Array:
	return traversal.options() if traversal != null else []

func in_run() -> bool:
	return traversal != null and not traversal.is_complete()

## Scene that renders the active traversal model.
func run_scene() -> String:
	var d := dungeon_data()
	var kind: int = d.traversal if d != null else Traversal.Kind.GRAPH
	match kind:
		Traversal.Kind.DECK: return "res://scenes/DeckRun.tscn"
		Traversal.Kind.DICE: return "res://scenes/DiceRun.tscn"
		_: return "res://scenes/Map.tscn"

## Where picking the run back up goes: into the fight if one is in progress
## (D22 serializes it), otherwise the traversal view. Continue, loading a slot and
## the pause menu all ask here — the rule was written out three times, which is
## how two of them come to disagree.
func resume_scene() -> String:
	if not combat_state.is_empty():
		return "res://scenes/Combat.tscn"
	return run_scene()

func clear_node(_node: Dictionary) -> void:
	if traversal != null:
		traversal.clear_pending()
