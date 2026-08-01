## Global run state. Autoload singleton — survives scene changes (IsoRun <-> Combat).
## Holds the roguelike RUN state: deck, HP, floor, position, progress.
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
## The active traversal for this run (the iso crawl). Null outside a run.
var traversal: Traversal = null
## What the crawl's model number was in saves written before D94 deleted the other
## three models. Read once, on resume, to tell a restorable run from a stale one.
const LEGACY_ISO_KIND := 3
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
## Sealed packs found this run (D80): {"kind": ..., "dungeon": ...}, unopened.
##
## At risk with everything else, which is most of the point — an unopened pack is a
## stake you can see, where "4 cards and 140 gold" is a sentence you read.
var escrow_packs: Array = []

## Relics found in this run, held on the same terms as everything else.
##
## An elite drops one (D68). Granting it straight into MetaState would reopen the
## exact hole escrow was built to close: kill the elite, die on purpose, keep the
## relic — the D20 abandon exploit with a different noun. Relics are still never
## LOST once banked; they are simply not banked until the boss falls or a rope is
## spent.
var escrow_relics: Array = []  # relic ids

## Keys found this run, spent on locked chests (D84).
##
## Run-scoped and NOT in escrow: a key is a tool for opening things here, not a
## reward to carry home, so dying loses it the same way it loses the floor you were
## standing on. Keeping keys between runs would turn the first chest of every run
## into a formality.
var keys: int = 0

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
	var result := {"cards": escrow_cards.size(), "gold": escrow_gold,
		"relics": escrow_relics.size(), "packs": escrow_packs.size()}
	if meta != null:
		for id in escrow_cards:
			meta.add_card(id)
		if escrow_gold > 0:
			meta.add_gold(escrow_gold)
		for rid in escrow_relics:
			meta.add_relic(rid)
		for p in escrow_packs:
			meta.add_pack(String(p.get("kind", Balance.PACK_TREASURE)),
				String(p.get("dungeon", "")))
	escrow_cards = []
	escrow_gold = 0
	escrow_relics = []
	escrow_packs = []
	return result

## Died or walked away: the run's earnings are lost.
func forfeit_escrow() -> Dictionary:
	var result := {"cards": escrow_cards.size(), "gold": escrow_gold,
		"relics": escrow_relics.size(), "packs": escrow_packs.size()}
	escrow_cards = []
	escrow_gold = 0
	escrow_relics = []
	escrow_packs = []
	return result

## A sealed pack, found in a treasure or left by an elite or a boss. Carried out
## or lost with everything else.
##
## The tier and the build are rolled HERE, where the pack is found, not on the
## overworld where it is opened (D81). Two reasons: the label can then state what
## is inside before the player decides whether to risk carrying it home, and a
## pack that rolled its contents at opening time would quietly reroll on every
## load, which is the same bug shops had before `shop_stock` was frozen.
## `tier_of` forces the tier instead of rolling one: a chest's packs inherit the
## chest's tier, or a Sealed Chest hands out Gilded packs and the tier printed on
## the lid means nothing.
func earn_pack(kind: String, dungeon_of: String = "", tier_of: String = "") -> void:
	var did: String = dungeon_of if dungeon_of != "" else dungeon_id
	escrow_packs.append({
		"kind": kind,
		"dungeon": did,
		"tier": tier_of if tier_of in Balance.PACK_TIERS else Balance.roll_pack_tier(kind, dungeon),
		"build": Balance.roll_pack_build(did),
	})

## What the run stands to lose, as the run screens state it.
##
## One function because there were four copies of this string — one per traversal
## screen, back when there were four (D94) — and packs (D80) had to be added to all
## of them: a thing that can be forfeited but is never shown
## while it is at risk is not really in escrow, it is just a surprise on the
## Defeat screen. Relics are named here too, for the same reason.
func risk_line() -> String:
	var parts: Array[String] = ["%d cards" % escrow_cards.size(), "%d gold" % escrow_gold]
	if not escrow_relics.is_empty():
		parts.append("%d relic%s" % [escrow_relics.size(),
			"" if escrow_relics.size() == 1 else "s"])
	if not escrow_packs.is_empty():
		parts.append("%d pack%s" % [escrow_packs.size(),
			"" if escrow_packs.size() == 1 else "s"])
	var line := "AT RISK: " + ", ".join(parts)
	# keys are NOT at risk in the same sense — they are spent here or wasted — but a
	# locked chest you cannot open because you did not know you had a key is the
	# kind of thing the player is never supposed to discover afterwards
	if keys > 0:
		line += "    Keys %d" % keys
	return line

## An elite yielded a relic. Held at risk until the boss falls.
func earn_relic(id: String) -> void:
	if id != "" and not (id in escrow_relics):
		escrow_relics.append(id)

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
		"escrow_relics": escrow_relics, "escrow_packs": escrow_packs,
		"keys": keys,
		"shop_stock": shop_stock,
		"combat": combat_state,
	}

## Can this build rebuild that saved traversal?
##
## A run saved on one of the three models deleted in D94 describes a board that no
## longer exists — restoring it onto the crawl would rebuild half a dungeon out of
## keys the crawl never reads, and hand the player a broken run rather than an error.
## Those saves stamp the model number; the crawl was 3 and now writes none at all, so
## anything else is a deleted model and the run goes.
##
## Static, and separate from `run_from_dict`, so a headless test can ask it: the
## function it guards needs autoloads under /root and a `--script` test has none.
static func traversal_is_current(tstate: Dictionary) -> bool:
	return int(tstate.get("kind", LEGACY_ISO_KIND)) == LEGACY_ISO_KIND

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
	# a relic renamed or removed since the save is simply dropped, like a card
	escrow_relics = []
	for rid in d.get("escrow_relics", []):
		if meta.RELIC_CATALOG.has(rid):
			escrow_relics.append(rid)
	escrow_packs = []
	for p in d.get("escrow_packs", []):
		# a pack from a dungeon that no longer exists cannot be opened, so drop it
		# here rather than let it sit in the collection forever
		if p is Dictionary and String(p.get("dungeon", "")) in Balance.DUNGEONS:
			# tier and build must survive the round trip: they were rolled where the
			# pack was found, and rebuilding the dict without them silently
			# downgraded every carried pack to worn on resume
			var did2 := String(p.get("dungeon", ""))
			var tier2 := String(p.get("tier", Balance.PACK_WORN))
			var bid2 := String(p.get("build", ""))
			escrow_packs.append({
				"kind": String(p.get("kind", Balance.PACK_TREASURE)),
				"dungeon": did2,
				"tier": tier2 if tier2 in Balance.PACK_TIERS else Balance.PACK_WORN,
				"build": bid2 if bid2 in Balance.BUILDS else Balance.roll_pack_build(did2),
			})
	keys = maxi(0, int(d.get("keys", 0)))
	shop_stock = d.get("shop_stock", [])
	combat_state = d.get("combat", {})
	var tstate: Dictionary = d.get("traversal", {})
	if not traversal_is_current(tstate):
		clear_run()
		return false
	traversal = Traversal.from_state(tstate, dungeon_data())
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
	max_hp = Balance.max_hp_for(clears, relic_hp)
	hp = max_hp
	dungeon = 1
	dungeon_id = ""
	current_zone = ""
	manage_only = false
	traversal = null
	shop_stock = []
	escrow_cards = []
	escrow_gold = 0
	escrow_relics = []
	escrow_packs = []
	keys = 0
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
	max_hp = Balance.max_hp_for(clears, relic_hp)
	hp = max_hp

## Build the traversal for the selected dungeon. Every dungeon is an iso crawl; what
## differs between them is the floor it generates, which comes from the dungeon's data.
func generate_map() -> void:
	var d := dungeon_data()
	traversal = TraversalIso.new()
	traversal.generate(d)

## Choices available right now (empty outside a run).
func options() -> Array:
	return traversal.options() if traversal != null else []

func in_run() -> bool:
	return traversal != null and not traversal.is_complete()

## Scene that renders the run. Still a function rather than a constant at the call
## sites: it is the one place that decides, and the callers below already ask it.
func run_scene() -> String:
	return "res://scenes/IsoRun.tscn"

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
