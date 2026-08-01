## Persistent META state. Autoload — survives death and app restarts (saved to disk).
## The card COLLECTION: id -> {count, level}. Duplicates accumulate; fuse for power.
## This is the RPG progression layer, separate from the roguelike run (GameState).
extends Node

const SAVE_PATH := "user://save.json"        # slot 0 keeps the original path
const SLOT_COUNT := 3
## Which slot is being played. Set by the menus before loading or saving.
var slot: int = 0

## Prefix for save paths. Tests set this so they cannot write over a real save —
## they previously shared the player's files and clobbered their settings and slots.
##
## Defaults to a sandbox under `--headless`. The game is never played headless, so
## anything running that way is a test or a throwaway diagnostic, and every one of
## those that forgot to set a prefix wrote to the player's real save: settings were
## corrupted once, an in-progress run destroyed once, and the collection changed
## under a tool a third time. Opting IN to real paths (`path_prefix = ""` after
## boot) is a deliberate act; opting out was too easy to forget.
##
## One sandbox for every headless process is only safe while they run one at a time.
## `tests/run.sh` runs suites concurrently, so it hands each one its own name in
## DECKCRAWL_SANDBOX; without that, two suites share `t_headless_save_0.json` and
## whichever writes second decides what the first one reads back. A suite that sets
## `path_prefix` itself still wins — this is the floor, not the policy.
static var _sandbox := OS.get_environment("DECKCRAWL_SANDBOX")
static var path_prefix := (
	("t_%s_" % _sandbox if _sandbox != "" else "t_headless_")
	if DisplayServer.get_name() == "headless" else "")

static func path_for(s: int) -> String:
	if path_prefix != "":
		return "user://%ssave_%d.json" % [path_prefix, s]
	return SAVE_PATH if s <= 0 else "user://save_%d.json" % s

func save_file() -> String:
	return path_for(slot)

## Lightweight slot description for the load/save menus, without disturbing the
## state currently in memory.
static func slot_summary(s: int) -> Dictionary:
	var p := path_for(s)
	if not FileAccess.file_exists(p):
		return {"exists": false}
	var f := FileAccess.open(p, FileAccess.READ)
	if not f:
		return {"exists": false}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY or not d.has("collection"):
		return {"exists": true, "corrupt": true}
	var copies := 0
	for id in d.get("collection", {}):
		copies += int(d["collection"][id].get("count", 0))
	return {
		"exists": true, "corrupt": false,
		"gold": int(d.get("gold", 0)),
		"relics": (d.get("relics", []) as Array).size(),
		"clears": (d.get("cleared_dungeons", []) as Array).size(),
		"types": (d.get("collection", {}) as Dictionary).size(),
		"copies": copies,
		"version": int(d.get("version", 0)),
		"in_run": not (d.get("run", {}) as Dictionary).is_empty()
			or FileAccess.file_exists(run_path_for(s)),
	}

static func delete_slot(s: int) -> void:
	for p in [path_for(s), run_path_for(s)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
## Bump when the save shape changes, and add a step to _migrate().
## Saves written before versioning existed have no "version" key and read as 0.
const SAVE_VERSION := 8
## The run lives in its own file beside the meta save. They change at wildly
## different rates — meta only when the player gains something permanent, the run
## on every card played — so writing them together meant rewriting the whole
## collection to record a single turn. Separating them also isolates damage: a
## truncated run file cannot take the permanent save down with it.
const FLUSH_SECONDS := 0.75

var _meta_dirty := false
var _run_dirty := false
var _since_write := 0.0
## Counters, for benchmarking and for the tests that assert writes are coalesced.
var writes_meta := 0
var writes_run := 0

static func run_path_for(s: int) -> String:
	if path_prefix != "":
		return "user://%ssave_%d.run.json" % [path_prefix, s]
	return "user://save.run.json" if s <= 0 else "user://save_%d.run.json" % s

func run_file() -> String:
	return run_path_for(slot)

## Mark state as needing a write. Writes are coalesced by _process rather than
## issued per mutation: a combat turn can touch state a dozen times.
func mark_meta_dirty() -> void:
	_meta_dirty = true

func mark_run_dirty() -> void:
	_run_dirty = true

func _process(delta: float) -> void:
	if not (_meta_dirty or _run_dirty):
		return
	_since_write += delta
	if _since_write >= FLUSH_SECONDS:
		flush()

## Set by a test at teardown. An instance that outlives the test still flushes
## when the engine frees it at exit — which re-created the sandbox file *after*
## cleanup had deleted it. Nothing may write once teardown has begun.
static var writes_disabled := false

## Write whatever is dirty, now.
func flush() -> void:
	if writes_disabled:
		return
	_since_write = 0.0
	if _meta_dirty:
		_write_meta()
	if _run_dirty:
		_write_run()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush()

## All cards that can exist. id -> resource path. Add new cards here.
const CATALOG := {
	"abyssal_gift": "res://resources/cards/abyssal_gift.tres",
	"kick": "res://resources/cards/kick.tres",
	"anvil_stance": "res://resources/cards/anvil_stance.tres",
	"bandage": "res://resources/cards/bandage.tres",
	"set_stone": "res://resources/cards/set_stone.tres",
	"stave_in": "res://resources/cards/stave_in.tres",
	"see_it_coming": "res://resources/cards/see_it_coming.tres",
	"red_mind": "res://resources/cards/red_mind.tres",
	"bite": "res://resources/cards/bite.tres",
	"black_tide": "res://resources/cards/black_tide.tres",
	"blight_bloom": "res://resources/cards/blight_bloom.tres",
	"old_debt": "res://resources/cards/old_debt.tres",
	"bloodlust": "res://resources/cards/bloodlust.tres",
	"all_you_have": "res://resources/cards/all_you_have.tres",
	"ram": "res://resources/cards/ram.tres",
	"brace": "res://resources/cards/brace.tres",
	"bramble_armour": "res://resources/cards/bramble_armour.tres",
	"bulwark": "res://resources/cards/bulwark.tres",
	"sharp_ground": "res://resources/cards/sharp_ground.tres",
	"cheap_shot": "res://resources/cards/cheap_shot.tres",
	"clear_mind": "res://resources/cards/clear_mind.tres",
	"reap": "res://resources/cards/reap.tres",
	"cold_read": "res://resources/cards/cold_read.tres",
	"counterblow": "res://resources/cards/counterblow.tres",
	"creeping_death": "res://resources/cards/creeping_death.tres",
	"cull": "res://resources/cards/cull.tres",
	"in_and_out": "res://resources/cards/in_and_out.tres",
	"thrown_iron": "res://resources/cards/thrown_iron.tres",
	"decapitate": "res://resources/cards/decapitate.tres",
	"deep_breath": "res://resources/cards/deep_breath.tres",
	"cover": "res://resources/cards/cover.tres",
	"something_worse": "res://resources/cards/something_worse.tres",
	"give_ground": "res://resources/cards/give_ground.tres",
	"double_down": "res://resources/cards/double_down.tres",
	"execute": "res://resources/cards/execute.tres",
	"exsanguinate": "res://resources/cards/exsanguinate.tres",
	"feint": "res://resources/cards/feint.tres",
	"last_word": "res://resources/cards/last_word.tres",
	"focus": "res://resources/cards/focus.tres",
	"light_on_it": "res://resources/cards/light_on_it.tres",
	"forge_strike": "res://resources/cards/forge_strike.tres",
	"guard": "res://resources/cards/guard.tres",
	"dead_weight": "res://resources/cards/dead_weight.tres",
	"heavy_swing": "res://resources/cards/heavy_swing.tres",
	"hex": "res://resources/cards/hex.tres",
	"shut_out": "res://resources/cards/shut_out.tres",
	"work_up": "res://resources/cards/work_up.tres",
	"iron_lung": "res://resources/cards/iron_lung.tres",
	"shoulder": "res://resources/cards/shoulder.tres",
	"iron_will": "res://resources/cards/iron_will.tres",
	"jab": "res://resources/cards/jab.tres",
	"bristle": "res://resources/cards/bristle.tres",
	"kelp_snare": "res://resources/cards/kelp_snare.tres",
	"last_stand": "res://resources/cards/last_stand.tres",
	"leech": "res://resources/cards/leech.tres",
	"lifedrain": "res://resources/cards/lifedrain.tres",
	"massacre": "res://resources/cards/massacre.tres",
	"molten_core": "res://resources/cards/molten_core.tres",
	"noxious_cloud": "res://resources/cards/noxious_cloud.tres",
	"pandemic": "res://resources/cards/pandemic.tres",
	"drilled": "res://resources/cards/drilled.tres",
	"plague_bearer": "res://resources/cards/plague_bearer.tres",
	"plague_heart": "res://resources/cards/plague_heart.tres",
	"read_ahead": "res://resources/cards/read_ahead.tres",
	"pressure": "res://resources/cards/pressure.tres",
	"keep_hitting": "res://resources/cards/keep_hitting.tres",
	"rally": "res://resources/cards/rally.tres",
	"riposte": "res://resources/cards/riposte.tres",
	"riptide": "res://resources/cards/riptide.tres",
	"rot_touch": "res://resources/cards/rot_touch.tres",
	"split": "res://resources/cards/split.tres",
	"salt_the_wound": "res://resources/cards/salt_the_wound.tres",
	"sanguine_feast": "res://resources/cards/sanguine_feast.tres",
	"scrape": "res://resources/cards/scrape.tres",
	"grinding_down": "res://resources/cards/grinding_down.tres",
	"second_heart": "res://resources/cards/second_heart.tres",
	"stitch": "res://resources/cards/stitch.tres",
	"shield_wall": "res://resources/cards/shield_wall.tres",
	"nick": "res://resources/cards/nick.tres",
	"take_it": "res://resources/cards/take_it.tres",
	"sidestep": "res://resources/cards/sidestep.tres",
	"gash": "res://resources/cards/gash.tres",
	"smiths_fury": "res://resources/cards/smiths_fury.tres",
	"smoke_bomb": "res://resources/cards/smoke_bomb.tres",
	"spiked_guard": "res://resources/cards/spiked_guard.tres",
	"spore_burst": "res://resources/cards/spore_burst.tres",
	"stone_skin": "res://resources/cards/stone_skin.tres",
	"hack": "res://resources/cards/hack.tres",
	"stumble": "res://resources/cards/stumble.tres",
	"survival_instinct": "res://resources/cards/survival_instinct.tres",
	"sword_dance": "res://resources/cards/sword_dance.tres",
	"put_the_fear": "res://resources/cards/put_the_fear.tres",
	"thorn_crown": "res://resources/cards/thorn_crown.tres",
	"two_quick": "res://resources/cards/two_quick.tres",
	"undying": "res://resources/cards/undying.tres",
	"venom_fang": "res://resources/cards/venom_fang.tres",
	"virulence": "res://resources/cards/virulence.tres",
	"whetted_edge": "res://resources/cards/whetted_edge.tres",
	"clear_the_room": "res://resources/cards/clear_the_room.tres",
	"wither": "res://resources/cards/wither.tres",
}

## All relics that can exist. id -> resource path (Phase 7).
const RELIC_CATALOG := {
	"ancient_battery": "res://resources/relics/ancient_battery.tres",
	"balanced_grip": "res://resources/relics/balanced_grip.tres",
	"bone_charm": "res://resources/relics/bone_charm.tres",
	"bulwark_plate": "res://resources/relics/bulwark_plate.tres",
	"chipped_whetstone": "res://resources/relics/chipped_whetstone.tres",
	"coin_purse": "res://resources/relics/coin_purse.tres",
	"crown_of_thorns": "res://resources/relics/crown_of_thorns.tres",
	"duelists_glove": "res://resources/relics/duelists_glove.tres",
	"eternal_furnace": "res://resources/relics/eternal_furnace.tres",
	"field_kit": "res://resources/relics/field_kit.tres",
	"giants_marrow": "res://resources/relics/giants_marrow.tres",
	"healing_idol": "res://resources/relics/healing_idol.tres",
	"hearth_stone": "res://resources/relics/hearth_stone.tres",
	"iron_heart": "res://resources/relics/iron_heart.tres",
	"iron_ration": "res://resources/relics/iron_ration.tres",
	"keen_lens": "res://resources/relics/keen_lens.tres",
	"kite_shield": "res://resources/relics/kite_shield.tres",
	"leather_wrap": "res://resources/relics/leather_wrap.tres",
	"lucky_penny": "res://resources/relics/lucky_penny.tres",
	"merchants_seal": "res://resources/relics/merchants_seal.tres",
	"padded_vest": "res://resources/relics/padded_vest.tres",
	"reliquary_heart": "res://resources/relics/reliquary_heart.tres",
	"scholars_lens": "res://resources/relics/scholars_lens.tres",
	"surgeons_thread": "res://resources/relics/surgeons_thread.tres",
	"tin_cup": "res://resources/relics/tin_cup.tres",
	"tower_shield": "res://resources/relics/tower_shield.tres",
	"warlords_banner": "res://resources/relics/warlords_banner.tres",
	"weighted_soles": "res://resources/relics/weighted_soles.tres",
	"whetstone": "res://resources/relics/whetstone.tres",
	"worn_boots": "res://resources/relics/worn_boots.tres",
}

## Consumables: persistent one-use items. A dictionary rather than Resources
## while there is only one — promote to `resources/items/*.tres` when there are
## several, the way cards and relics already are.
const CONSUMABLES := {
	"escape_rope": {
		"name": "Escape Rope",
		"desc": "Leave a dungeon at once and keep everything you found. Consumed on use.",
	},
}

## Starting kits. A fresh save used to be exactly 4 Strike + 4 Defend — precisely
## the legal minimum deck size — so run 1 offered no deckbuilding decision, and
## fusion stayed invisible until ~10 copies had accumulated. Each kit is 12 cards
## leaning toward a different archetype, which makes the first choice the same
## choice the game is about, gives the deck builder slack, and puts 3+ copies of
## something in hand so fusion is live immediately.
##
## A dictionary while there are three; promote to resources if it grows.
const STARTER_KITS := {
	"blade": {
		"name": "Blade", "hint": "Aggressive. Points toward Tempo and Strength.",
		"cards": {"hack": 5, "cover": 3, "jab": 2, "two_quick": 2},
	},
	"wall": {
		"name": "Wall", "hint": "Defensive. Points toward Fortress and Thorns.",
		"cards": {"hack": 3, "cover": 5, "guard": 2, "take_it": 2},
	},
	"cunning": {
		"name": "Cunning", "hint": "Cheap and fast. Points toward Tempo and Swarm.",
		"cards": {"hack": 4, "cover": 3, "nick": 2, "read_ahead": 3},
	},
}

## Copies spent on the FIRST level-up. The price rises with level and is paid in
## gold as well — see Balance.fuse_copy_cost / fuse_gold_cost. Kept as the cheapest
## possible step so UI and tests have a lower bound to talk about.
const FUSE_COST := Balance.FUSE_BASE_COPIES
# Balance-owned knobs (see scripts/balance.gd) re-exposed for UI convenience.
const MIN_KEEP := Balance.MIN_KEEP
const MIN_DECK_SIZE := Balance.MIN_DECK_SIZE
const MAX_DECK_SIZE := Balance.MAX_DECK_SIZE

# collection[id] = {"count": int, "level": int}
var collection: Dictionary = {}
# decks[name] = {id: count} — saved deck loadouts, reusable per dungeon (D4)
var decks: Dictionary = {}
## Owned relic ids. Persistent and NOT lost on death — relics are the character
## progression axis, distinct from the card collection (which death can shrink).
var relics: Array = []
## Ids of dungeons cleared at least once — drives unlocks and permanent max-HP.
## id -> count of persistent one-use items.
var consumables: Dictionary = {}

# --- powers (D37) ---
## Owned powers: id -> level. A power is bought once with gold, then levelled with
## gold; there are no duplicate copies to spend, so this is the meta layer's second
## progression axis alongside fusion.
var powers: Dictionary = {}
## The one power taken into a run. "" means none equipped.
var equipped_power: String = ""
## Which starting kit was chosen, and which one-time hints have been shown.
var starter_kit: String = "blade"
var seen_hints: Array = []
## New Game+ level: raises difficulty globally once the world has been cleared.
var ascension: int = 0
## Sealed packs waiting to be opened, each {"kind", "dungeon", "tier", "build"}.
## Tier and build are decided where the pack was found, never here. They are
## banked (past escrow) but deliberately NOT yet resolved: the opening is the moment
## the overworld did not have, and a pack that resolved itself on arrival would be a
## line of text again.
var packs: Array = []

var cleared_dungeons: Array = []
## How many times each dungeon has been cleared, for the diminishing repeat payout
## (D69). The set above answers "is it unlocked"; this answers "how well trodden".
var clear_counts: Dictionary = {}
var highest_dungeon: int = 1
var gold: int = 0  # persistent currency; earned in combat, partly lost on death

func _ready() -> void:
	# Boot with slot 0 if it exists so a scene opened directly still has state;
	# the menus set `slot` and call load_game()/new_save() explicitly.
	#
	# The fallback fills memory but does NOT write, because booting is not playing.
	# Writing here put a starter save on disk before the player had chosen anything,
	# and two things followed. `_latest_slot()` found slot 0 on a FRESH INSTALL, so
	# the main menu offered "Continue — slot 1 (0 clears, 0 gold)" to somebody who
	# had never played and its "no save found" branch could never be reached. And
	# every headless run left a save behind — a test, or any tool in `tools/`, which
	# is what `tests/run.sh`'s stray check kept reporting from suites that never
	# mention MetaState at all. Both callers that mean it (main_menu `_play`,
	# starter_kit) persist explicitly, which is what the line above always claimed.
	if not load_game():
		new_save("blade", false)

## `kit` picks the starting collection (see STARTER_KITS). `persist` writes the result
## to disk; pass false for a caller that only needs the state in memory and has not
## established that the player is starting a game.
func new_save(kit: String = "blade", persist: bool = true) -> void:
	starter_kit = kit if STARTER_KITS.has(kit) else "blade"
	collection = {}
	var loadout := {}
	for id in STARTER_KITS[starter_kit]["cards"]:
		var n: int = int(STARTER_KITS[starter_kit]["cards"][id])
		collection[id] = {"count": n, "level": 1}
		loadout[id] = n
	decks = {"Starter": loadout}
	saved_run = {}
	seen_hints = []
	relics = []
	consumables = {"escape_rope": 1}   # one rope to learn what it is for
	# One power from the start, at level 1: the mechanic has to be visible in the
	# first fight or nobody discovers it. The rest are bought.
	powers = {"bulwark": 1}
	equipped_power = "bulwark"
	cleared_dungeons = []
	clear_counts = {}
	packs = []
	highest_dungeon = 1
	gold = 0
	if persist:
		save_game()

## Spend gold. Returns false (and changes nothing) if the player cannot afford it.
func spend_gold(n: int) -> bool:
	if n <= 0 or gold < n:
		return false
	gold -= n
	save_game()
	return true

# --- one-time hints (onboarding) ---
## True the first time an id is asked about; false forever after. Used to explain a
## system the moment the player first meets it, rather than up front.
func hint_once(id: String) -> bool:
	if id in seen_hints:
		return false
	seen_hints.append(id)
	mark_meta_dirty()
	return true

# --- powers ---
## The equipped power as a levelled resource, ready for the engine. null if none.
func power_data() -> PowerData:
	if equipped_power == "" or not powers.has(equipped_power):
		return null
	var p := Balance.power(equipped_power)
	if p == null:
		return null
	p = p.duplicate()
	p.level = int(powers[equipped_power])
	return p

func owns_power(id: String) -> bool:
	return powers.has(id)

## Gated on clears so powers arrive across the campaign rather than all at once.
func power_available(id: String) -> bool:
	var p := Balance.power(id)
	return p != null and clear_count() >= p.unlock_after_clears

func power_price(id: String) -> int:
	var p := Balance.power(id)
	return Balance.power_price(p.rarity) if p != null else 0

func buy_power(id: String) -> bool:
	if owns_power(id) or not power_available(id) or not (id in Balance.POWERS):
		return false
	var price := power_price(id)
	if gold < price:
		return false
	gold -= price
	powers[id] = 1
	if equipped_power == "":
		equipped_power = id
	mark_meta_dirty()
	return true

func power_upgrade_price(id: String) -> int:
	var p := Balance.power(id)
	if p == null or not powers.has(id):
		return 0
	return Balance.power_upgrade_cost(p.rarity, int(powers[id]))

func can_upgrade_power(id: String) -> bool:
	var p := Balance.power(id)
	if p == null or not powers.has(id):
		return false
	if int(powers[id]) >= p.level_capped():
		return false
	return gold >= power_upgrade_price(id)

func upgrade_power(id: String) -> bool:
	if not can_upgrade_power(id):
		return false
	gold -= power_upgrade_price(id)
	powers[id] = int(powers[id]) + 1
	mark_meta_dirty()
	return true

func equip_power(id: String) -> bool:
	if id != "" and not owns_power(id):
		return false
	equipped_power = id
	mark_meta_dirty()
	return true

# --- consumables ---
func item_count(id: String) -> int:
	return int(consumables.get(id, 0))

func add_item(id: String, n: int = 1) -> void:
	if not CONSUMABLES.has(id):
		return
	consumables[id] = item_count(id) + maxi(1, n)
	mark_meta_dirty()

func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	consumables[id] = item_count(id) - 1
	if int(consumables[id]) <= 0:
		consumables.erase(id)
	mark_meta_dirty()
	return true

# --- dungeons (D6) ---
func has_cleared(id: String) -> bool:
	return id in cleared_dungeons

## How many times this dungeon has been beaten before the run being paid out.
func times_cleared(id: String) -> int:
	return int(clear_counts.get(id, 0))

## Bank a pack carried out of a run. Tier and build were decided where it was
## found; an old save that predates them (v7) gets the humblest possible pack.
func add_pack(kind: String, dungeon_id: String, tier: String = Balance.PACK_WORN,
		build_id: String = "") -> void:
	if not (dungeon_id in Balance.DUNGEONS):
		return
	if not (tier in Balance.PACK_TIERS):
		tier = Balance.PACK_WORN
	if not (build_id in Balance.BUILDS):
		build_id = Balance.roll_pack_build(dungeon_id)
	packs.append({"kind": kind, "dungeon": dungeon_id, "tier": tier, "build": build_id})
	mark_meta_dirty()

## Open the pack at `index`: its cards join the collection, its coins the purse.
##
## Rolls from the BUILD's card list, capped at the tier's best allowed rarity — so
## a worn pack cannot contain a legendary however deep it was found, and a poison
## pack contains poison cards wherever it was found (D81). The dungeon is still
## remembered, and still sets the gold, because depth is what a pack is worth.
##
## Returns what came out, for the screen to show.
func open_pack(index: int) -> Dictionary:
	if index < 0 or index >= packs.size():
		return {}
	var p: Dictionary = packs[index]
	var kind := String(p.get("kind", Balance.PACK_TREASURE))
	var did := String(p.get("dungeon", ""))
	var tier := String(p.get("tier", Balance.PACK_WORN))
	var build_id := String(p.get("build", ""))
	var dd := Balance.dungeon(did)
	var difficulty: int = dd.difficulty if dd != null else 1
	var pool: Array = Balance.pack_pool(build_id, tier).filter(
		func(cid): return CATALOG.has(cid))
	var got: Array[String] = []
	if not pool.is_empty():
		var wtbl: Array = Balance.pack_weights(difficulty, tier)
		var weights: Array = []
		for cid in pool:
			var c := Balance.card(cid)
			weights.append(wtbl[clampi(c.rarity if c != null else 0, 0, wtbl.size() - 1)])
		for i in Balance.pack_cards(tier):
			var id: String = pool[Balance.weighted_pick(weights)]
			add_card(id)
			got.append(id)
	var coins := Balance.pack_gold(difficulty, tier)
	add_gold(coins)
	packs.remove_at(index)
	save_game()
	return {"kind": kind, "dungeon": did, "tier": tier, "build": build_id,
		"cards": got, "gold": coins}

## Open every pack at once, because "several packs a run" turns one button into a
## chore. Returns one combined result plus the per-pack ones, so the screen can
## show the whole haul without eleven separate reveals.
func open_all_packs() -> Dictionary:
	var all_cards: Array[String] = []
	var coins := 0
	var opened: Array = []
	while not packs.is_empty():
		var got := open_pack(0)
		if got.is_empty():
			break
		opened.append(got)
		all_cards.append_array(got.get("cards", []))
		coins += int(got.get("gold", 0))
	return {"cards": all_cards, "gold": coins, "packs": opened}

func mark_cleared(id: String) -> void:
	clear_counts[id] = int(clear_counts.get(id, 0)) + 1
	if id != "" and not has_cleared(id):
		cleared_dungeons.append(id)
	save_game()

func clear_count() -> int:
	return cleared_dungeons.size()

## A dungeon unlocks once enough others have been cleared.
func dungeon_unlocked(d: DungeonData) -> bool:
	return d != null and clear_count() >= d.unlock_after_clears

# --- relics (Phase 7) ---
func has_relic(id: String) -> bool:
	return id in relics

func add_relic(id: String) -> bool:
	if not RELIC_CATALOG.has(id) or has_relic(id):
		return false
	relics.append(id)
	save_game()
	return true

## Loaded RelicData for everything owned, for effects and for enemy scaling.
func relic_data() -> Array:
	var out: Array = []
	for id in relics:
		var r := load(RELIC_CATALOG[id]) as RelicData
		if r != null:
			out.append(r)
	return out

## Relic ids the player does not own yet (the grant pool).
func unowned_relics() -> Array:
	var out: Array = []
	for id in RELIC_CATALOG:
		if not has_relic(id):
			out.append(id)
	return out

## Grant a random unowned relic, rarity-weighted by encounter tier. "" if none left.
## Roll a relic WITHOUT taking it. Split out so an elite's drop can go into escrow
## (D68) — granting it immediately would let a player kill the elite, die on
## purpose and keep it, which is the D20 abandon exploit with a different noun.
func pick_relic(tier: int) -> String:
	var pool: Array = unowned_relics()
	if pool.is_empty():
		return ""
	var wtbl: Array = Balance.WEIGHTS[tier]
	var weights: Array = []
	var total := 0
	for id in pool:
		var r := load(RELIC_CATALOG[id]) as RelicData
		var w: int = wtbl[clampi(r.rarity if r else 0, 0, wtbl.size() - 1)]
		weights.append(w)
		total += w
	var roll := randi() % maxi(1, total)
	for i in pool.size():
		roll -= int(weights[i])
		if roll < 0:
			return pool[i]
	return pool[0]

func grant_relic(tier: int) -> String:
	var pool: Array = unowned_relics()
	if pool.is_empty():
		return ""
	var wtbl: Array = Balance.WEIGHTS[tier]
	var weights: Array = []
	var total := 0
	for id in pool:
		var r := load(RELIC_CATALOG[id]) as RelicData
		var w: int = wtbl[clampi(r.rarity if r else 0, 0, wtbl.size() - 1)]
		weights.append(w)
		total += w
	var roll := randi() % maxi(1, total)
	for i in pool.size():
		roll -= int(weights[i])
		if roll < 0:
			add_relic(pool[i])
			return pool[i]
	add_relic(pool[0])
	return pool[0]

## Summed relic bonuses, for run setup and rewards.
func relic_bonus(field: String) -> int:
	var n := 0
	for r in relic_data():
		n += int(r.get(field))
	return n

func add_gold(n: int) -> void:
	gold = max(0, gold + n)
	mark_meta_dirty()

## Reward earned in a run -> permanent collection (D1: also added to run deck by caller).
func add_card(id: String) -> void:
	if not CATALOG.has(id):
		push_warning("add_card: unknown id %s" % id)
		return
	if collection.has(id):
		collection[id]["count"] += 1
	else:
		collection[id] = {"count": 1, "level": 1}
	mark_meta_dirty()

## Fusion: spend FUSE_COST copies to raise this card's level. All copies share the level.
## Max level for a card, by rarity (see Balance.max_level).
func max_level(id: String) -> int:
	if not CATALOG.has(id):
		return Balance.MIN_MAX_LEVEL
	var c := load(CATALOG[id]) as CardData
	return Balance.max_level(c.rarity if c else 0)

func at_max_level(id: String) -> bool:
	return collection.has(id) and collection[id]["level"] >= max_level(id)

## Copies this card's next level-up costs.
func fuse_copy_cost(id: String) -> int:
	if not collection.has(id):
		return Balance.FUSE_BASE_COPIES
	return Balance.fuse_copy_cost(int(collection[id]["level"]))

## Gold this card's next level-up costs.
func fuse_gold_cost(id: String) -> int:
	if not collection.has(id) or not CATALOG.has(id):
		return Balance.FUSE_BASE_GOLD
	var c := load(CATALOG[id]) as CardData
	return Balance.fuse_gold_cost(c.rarity if c else 0, int(collection[id]["level"]))

func can_fuse(id: String) -> bool:
	if not collection.has(id) or at_max_level(id):
		return false
	var cost := fuse_copy_cost(id)
	if collection[id]["count"] <= cost:
		return false  # must keep at least one copy of the card itself
	if gold < fuse_gold_cost(id):
		return false
	# Fusion consumes copies, so it must never shrink the collection below the
	# smallest legal deck — otherwise no deck can be built, no dungeon entered,
	# and no cards earned: an unrecoverable softlock.
	return total_copies() - cost >= Balance.MIN_KEEP

## Why fusion is unavailable, for the UI. "" when it is available.
func fuse_blocked_reason(id: String) -> String:
	if not collection.has(id):
		return "not owned"
	if at_max_level(id):
		return "max level"
	var cost := fuse_copy_cost(id)
	if collection[id]["count"] <= cost:
		return "need %d+ copies" % (cost + 1)
	var price := fuse_gold_cost(id)
	if gold < price:
		return "need %dg (have %d)" % [price, gold]
	if total_copies() - cost < Balance.MIN_KEEP:
		return "collection would drop below %d cards" % Balance.MIN_KEEP
	return ""

## Fuse repeatedly, stopping at the level cap, the copy floor, or `times`.
## Returns how many levels were actually gained.
##
## Exists because levelling one step per click meant up to 99 clicks to max a
## common — the grind is meant to be in *earning* copies, not in pressing a button.
func fuse_many(id: String, times: int) -> int:
	var gained := 0
	while gained < times and fuse(id):
		gained += 1
	return gained

## Levels this card could still gain right now, given copies, gold and the cap.
##
## Walked step by step rather than divided: the copy price rises with level and the
## gold price rises faster, so no single division describes the run of affordable
## steps any more.
func fusable_levels(id: String) -> int:
	if not collection.has(id) or not CATALOG.has(id):
		return 0
	var c := load(CATALOG[id]) as CardData
	var rarity: int = c.rarity if c else 0
	var cap := max_level(id)
	var level := int(collection[id]["level"])
	var copies := int(collection[id]["count"])
	var total := total_copies()
	var purse := gold
	var n := 0
	while level + n < cap:
		var cc := Balance.fuse_copy_cost(level + n)
		var gc := Balance.fuse_gold_cost(rarity, level + n)
		if copies - cc < 1 or total - cc < Balance.MIN_KEEP or purse < gc:
			break
		copies -= cc
		total -= cc
		purse -= gc
		n += 1
	return n

func fuse(id: String) -> bool:
	if not can_fuse(id):
		return false
	gold -= fuse_gold_cost(id)
	collection[id]["count"] -= fuse_copy_cost(id)
	collection[id]["level"] += 1
	mark_meta_dirty()
	return true

## Build a run deck from the collection: `count` copies of each card at its level.
func build_run_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in collection:
		var path: String = CATALOG.get(id, "")
		if path == "":
			continue
		var lvl: int = collection[id]["level"]
		for i in collection[id]["count"]:
			var c := (load(path) as CardData).duplicate()
			c.level = lvl
			deck.append(c)
	return deck

# --- deck loadouts (D4): assemble a deck per dungeon from owned cards ---
func owned(id: String) -> int:
	return collection[id]["count"] if collection.has(id) else 0

func loadout_size(loadout: Dictionary) -> int:
	var n := 0
	for id in loadout:
		n += min(int(loadout[id]), owned(id))  # clamp to what's owned
	return n

func deck_valid(loadout: Dictionary) -> bool:
	var n := loadout_size(loadout)
	return n >= MIN_DECK_SIZE and n <= MAX_DECK_SIZE

func save_deck(deck_name: String, loadout: Dictionary) -> void:
	# store only positive, owned selections
	var clean := {}
	for id in loadout:
		var n: int = min(int(loadout[id]), owned(id))
		if n > 0:
			clean[id] = n
	decks[deck_name] = clean
	mark_meta_dirty()

func delete_deck(deck_name: String) -> void:
	decks.erase(deck_name)
	mark_meta_dirty()

## Materialize a loadout into actual CardData (copies at the collection's level).
## Clamps each id to currently-owned count (a saved deck may outlive lost cards).
func build_deck(loadout: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		if not CATALOG.has(id) or not collection.has(id):
			continue
		var n: int = min(int(loadout[id]), owned(id))
		var lvl: int = collection[id]["level"]
		for i in n:
			var c := (load(CATALOG[id]) as CardData).duplicate()
			c.level = lvl
			deck.append(c)
	return deck

# --- death penalty (D3): lose gold + cards, scaled by dungeon difficulty ---
func total_copies() -> int:
	var t := 0
	for id in collection:
		t += collection[id]["count"]
	return t

func _is_attack(id: String) -> bool:
	var c := load(CATALOG[id]) as CardData
	return c != null and c.damage > 0

## Pick one random removable copy's card id, or "" if nothing may be removed.
## Protects: minimum collection size, and the last remaining attack card.
func _pick_losable_card() -> String:
	if total_copies() <= MIN_KEEP:
		return ""
	var attack_copies := 0
	for id in collection:
		if _is_attack(id):
			attack_copies += collection[id]["count"]
	var pool: Array = []  # flat, weighted by count
	for id in collection:
		if _is_attack(id) and attack_copies <= 1:
			continue  # never strip the last attack
		for i in collection[id]["count"]:
			pool.append(id)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

## Apply death penalty for dying in the given dungeon tier.
## Returns {gold_lost:int, cards_lost:[String names]} for the UI.
func penalize_death(dungeon: int) -> Dictionary:
	var result := {"gold_lost": 0, "cards_lost": []}
	# gold: lose a fraction that grows with dungeon difficulty
	var frac := Balance.gold_loss_fraction(dungeon)
	var gl := int(round(gold * frac))
	gold -= gl
	result["gold_lost"] = gl
	# cards: lose a (retuned) number of random copies, respecting floors
	for i in Balance.cards_lost_on_death(dungeon):
		var id := _pick_losable_card()
		if id == "":
			break
		var c := load(CATALOG[id]) as CardData
		result["cards_lost"].append(c.name if c else id)
		collection[id]["count"] -= 1
		if collection[id]["count"] <= 0:
			collection.erase(id)
	save_game()
	return result

# --- persistence ---
## The in-progress run, so a dungeon can be resumed. Fetched by path because
## MetaState must stay loadable in headless `--script` runs.
func _run_blob() -> Dictionary:
	var gs := (get_node_or_null("/root/GameState") if is_inside_tree() else null)
	return gs.run_to_dict() if gs != null else saved_run

## Run blob as loaded from disk, before GameState consumes it.
var saved_run: Dictionary = {}

func has_saved_run() -> bool:
	return not saved_run.is_empty()
## Write everything immediately. Kept as the explicit "save now" entry point.
func save_game() -> void:
	_meta_dirty = true
	_run_dirty = true
	flush()

func _write_meta() -> void:
	var data := {
		"version": SAVE_VERSION,
		"collection": collection, "decks": decks, "relics": relics,
		"consumables": consumables, "powers": powers, "equipped_power": equipped_power,
		"starter_kit": starter_kit, "seen_hints": seen_hints, "ascension": ascension,
		"cleared_dungeons": cleared_dungeons, "clear_counts": clear_counts,
		"packs": packs,
		"highest_dungeon": highest_dungeon, "gold": gold,
	}
	var f := FileAccess.open(save_file(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		writes_meta += 1
	_meta_dirty = false

func _write_run() -> void:
	var blob := _run_blob()
	if blob.is_empty():
		# no run in progress: remove the file rather than leaving a stale one
		if FileAccess.file_exists(run_file()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(run_file()))
	else:
		var f := FileAccess.open(run_file(), FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify({"version": SAVE_VERSION, "run": blob}))
			f.close()
			writes_run += 1
	_run_dirty = false

func load_game() -> bool:
	if not FileAccess.file_exists(save_file()):
		return false
	var f := FileAccess.open(save_file(), FileAccess.READ)
	if not f:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("collection"):
		push_warning("save unreadable; starting fresh")
		return false

	var from_version := int(parsed.get("version", 0))
	if from_version > SAVE_VERSION:
		# a newer build wrote this; refuse rather than silently dropping fields
		push_warning("save is from a newer version (%d > %d); not loading" % [
			from_version, SAVE_VERSION])
		return false
	if from_version < SAVE_VERSION:
		_backup_save(text, from_version)
		parsed = _migrate(parsed, from_version)

	_apply(parsed)
	if from_version < SAVE_VERSION:
		save_game()   # rewrite in the current shape
	return true

## Keep a copy before migrating, so a bad migration is recoverable.
func _backup_save(text: String, from_version: int) -> void:
	var path := "%s.v%d.bak" % [save_file(), from_version]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()

## Bring an older save up to the current shape. Each step is additive and
## idempotent: missing keys get defaults, unknown ids are dropped on apply.
func _migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data.duplicate(true)
	if from_version < 8:
		# v7 packs have no tier and no build (D81). Nothing to compute here: the
		# loader normalises a missing tier to worn and rolls a build from where the
		# pack was found, which is the same answer this migration could give.
		pass
	if from_version < 7:
		# v6 predates sealed packs (D80). Nothing to carry: a save from before they
		# existed cannot have earned any, and the loader defaults the field to empty.
		# The bump is here so the log of save shapes stays complete — a version that
		# only some changes bump is a version nobody can reason from.
		pass
	if from_version < 6:
		# v5 knew only WHETHER a dungeon was cleared. The repeat payout (D69) needs
		# how often, and an existing player should not be charged for history the
		# save never recorded: every cleared dungeon counts as cleared exactly once,
		# so their next visit is the first repeat rather than the fifth.
		var counts := {}
		for did in d.get("cleared_dungeons", []):
			counts[String(did)] = 1
		d["clear_counts"] = counts
	if from_version < 5:
		# v4 predates powers. Grant the same starter every new save gets, so an
		# existing player is not worse off than someone starting today.
		if not d.has("powers"):
			d["powers"] = {"bulwark": 1}
		if not d.has("equipped_power"):
			d["equipped_power"] = "bulwark"
	if from_version < 4:
		# v3 and earlier kept the run inside the meta file; it is read from there
		# on load and written to the separate run file from now on.
		if not d.has("run"):
			d["run"] = {}
	if from_version < 2:
		# v1 predates consumables; grant the starting rope so an existing save is
		# not worse off than a new one.
		if not d.has("consumables"):
			d["consumables"] = {"escape_rope": 1}
	if from_version < 1:
		# v0 predates relics, saved decks, dungeon clears and gold.
		if not d.has("relics"):
			d["relics"] = []
		if not d.has("decks"):
			d["decks"] = {"Starter": {"hack": 4, "cover": 4}}
		if not d.has("cleared_dungeons"):
			d["cleared_dungeons"] = []
		if not d.has("gold"):
			d["gold"] = 0
	d["version"] = SAVE_VERSION
	return d

## Load validated state out of a (migrated) dictionary. Unknown ids are dropped
## here rather than in migration, so renaming content cannot corrupt a save.
func _apply(parsed: Dictionary) -> void:
	# JSON numbers load as float -> coerce counts/levels back to int
	collection = {}
	for id in parsed["collection"]:
		if not CATALOG.has(id):
			continue   # content was renamed or removed
		var e = parsed["collection"][id]
		collection[id] = {"count": int(e["count"]), "level": int(e["level"])}
	if collection.is_empty():
		collection = {"hack": {"count": 4, "level": 1}, "cover": {"count": 4, "level": 1}}

	decks = {}
	for dn in parsed.get("decks", {}):
		var lo := {}
		for id in parsed["decks"][dn]:
			if CATALOG.has(id):
				lo[id] = int(parsed["decks"][dn][id])
		decks[dn] = lo

	relics = []
	for id in parsed.get("relics", []):
		if RELIC_CATALOG.has(id) and not id in relics:
			relics.append(id)

	powers = {}
	for id in parsed.get("powers", {}):
		if id in Balance.POWERS:
			powers[id] = maxi(1, int(parsed["powers"][id]))
	equipped_power = String(parsed.get("equipped_power", ""))
	if not powers.has(equipped_power):
		# an unowned or renamed power must not travel into a run
		equipped_power = powers.keys()[0] if not powers.is_empty() else ""

	consumables = {}
	for id in parsed.get("consumables", {}):
		if CONSUMABLES.has(id):
			var n := int(parsed["consumables"][id])
			if n > 0:
				consumables[id] = n

	cleared_dungeons = []
	for id in parsed.get("cleared_dungeons", []):
		if id in Balance.DUNGEONS and not id in cleared_dungeons:
			cleared_dungeons.append(id)
	# unknown ids dropped here rather than in migration, so renaming a dungeon can
	# never corrupt a save (D15)
	packs = []
	for p in parsed.get("packs", []):
		# a pack from renamed content cannot be opened; dropped on load, never in
		# migration, so renaming a dungeon can never corrupt a save (D15)
		if p is Dictionary and String(p.get("dungeon", "")) in Balance.DUNGEONS:
			# an unknown tier or a retired build is normalised, not dropped: the
			# pack is still a real thing the player earned, and a save that
			# silently eats rewards is worse than one that downgrades them
			var tier := String(p.get("tier", Balance.PACK_WORN))
			var bid := String(p.get("build", ""))
			var did := String(p.get("dungeon", ""))
			packs.append({
				"kind": String(p.get("kind", Balance.PACK_TREASURE)),
				"dungeon": did,
				"tier": tier if tier in Balance.PACK_TIERS else Balance.PACK_WORN,
				"build": bid if bid in Balance.BUILDS else Balance.roll_pack_build(did),
			})
	clear_counts = {}
	for id in parsed.get("clear_counts", {}):
		if id in Balance.DUNGEONS:
			clear_counts[id] = maxi(0, int(parsed["clear_counts"][id]))

	highest_dungeon = int(parsed.get("highest_dungeon", 1))
	gold = maxi(0, int(parsed.get("gold", 0)))
	# v3 and earlier stored the run inside the meta file; v4 has its own file
	starter_kit = String(parsed.get("starter_kit", "blade"))
	seen_hints = parsed.get("seen_hints", [])
	ascension = maxi(0, int(parsed.get("ascension", 0)))
	Balance.ascension = ascension   # static, so scaling formulas need no new args
	saved_run = parsed.get("run", {})
	if FileAccess.file_exists(run_file()):
		var rf := FileAccess.open(run_file(), FileAccess.READ)
		if rf:
			var rd = JSON.parse_string(rf.get_as_text())
			rf.close()
			if typeof(rd) == TYPE_DICTIONARY:
				saved_run = rd.get("run", {})
