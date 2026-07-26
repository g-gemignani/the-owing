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
static var path_prefix := "t_headless_" if DisplayServer.get_name() == "headless" else ""

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
const SAVE_VERSION := 5
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
	"adrenaline": "res://resources/cards/adrenaline.tres",
	"anvil_stance": "res://resources/cards/anvil_stance.tres",
	"bandage": "res://resources/cards/bandage.tres",
	"barricade": "res://resources/cards/barricade.tres",
	"bash": "res://resources/cards/bash.tres",
	"battle_trance": "res://resources/cards/battle_trance.tres",
	"berserker_rage": "res://resources/cards/berserker_rage.tres",
	"bite": "res://resources/cards/bite.tres",
	"black_tide": "res://resources/cards/black_tide.tres",
	"blight_bloom": "res://resources/cards/blight_bloom.tres",
	"blood_price": "res://resources/cards/blood_price.tres",
	"bloodlust": "res://resources/cards/bloodlust.tres",
	"bludgeon": "res://resources/cards/bludgeon.tres",
	"body_slam": "res://resources/cards/body_slam.tres",
	"brace": "res://resources/cards/brace.tres",
	"bramble_armour": "res://resources/cards/bramble_armour.tres",
	"bulwark": "res://resources/cards/bulwark.tres",
	"caltrops": "res://resources/cards/caltrops.tres",
	"cheap_shot": "res://resources/cards/cheap_shot.tres",
	"clear_mind": "res://resources/cards/clear_mind.tres",
	"cleave": "res://resources/cards/cleave.tres",
	"cold_read": "res://resources/cards/cold_read.tres",
	"counterblow": "res://resources/cards/counterblow.tres",
	"creeping_death": "res://resources/cards/creeping_death.tres",
	"cull": "res://resources/cards/cull.tres",
	"cut_and_run": "res://resources/cards/cut_and_run.tres",
	"dagger_throw": "res://resources/cards/dagger_throw.tres",
	"decapitate": "res://resources/cards/decapitate.tres",
	"deep_breath": "res://resources/cards/deep_breath.tres",
	"defend": "res://resources/cards/defend.tres",
	"demon_form": "res://resources/cards/demon_form.tres",
	"dodge_roll": "res://resources/cards/dodge_roll.tres",
	"entrench": "res://resources/cards/entrench.tres",
	"execute": "res://resources/cards/execute.tres",
	"exsanguinate": "res://resources/cards/exsanguinate.tres",
	"feint": "res://resources/cards/feint.tres",
	"finisher": "res://resources/cards/finisher.tres",
	"focus": "res://resources/cards/focus.tres",
	"footwork": "res://resources/cards/footwork.tres",
	"forge_strike": "res://resources/cards/forge_strike.tres",
	"guard": "res://resources/cards/guard.tres",
	"heavy_blade": "res://resources/cards/heavy_blade.tres",
	"heavy_swing": "res://resources/cards/heavy_swing.tres",
	"hex": "res://resources/cards/hex.tres",
	"impervious": "res://resources/cards/impervious.tres",
	"inflame": "res://resources/cards/inflame.tres",
	"iron_lung": "res://resources/cards/iron_lung.tres",
	"iron_wave": "res://resources/cards/iron_wave.tres",
	"iron_will": "res://resources/cards/iron_will.tres",
	"jab": "res://resources/cards/jab.tres",
	"juggernaut": "res://resources/cards/juggernaut.tres",
	"kelp_snare": "res://resources/cards/kelp_snare.tres",
	"last_stand": "res://resources/cards/last_stand.tres",
	"leech": "res://resources/cards/leech.tres",
	"lifedrain": "res://resources/cards/lifedrain.tres",
	"massacre": "res://resources/cards/massacre.tres",
	"molten_core": "res://resources/cards/molten_core.tres",
	"noxious_cloud": "res://resources/cards/noxious_cloud.tres",
	"pandemic": "res://resources/cards/pandemic.tres",
	"perfected_strike": "res://resources/cards/perfected_strike.tres",
	"plague_bearer": "res://resources/cards/plague_bearer.tres",
	"plague_heart": "res://resources/cards/plague_heart.tres",
	"prepared": "res://resources/cards/prepared.tres",
	"pressure": "res://resources/cards/pressure.tres",
	"pummel": "res://resources/cards/pummel.tres",
	"rally": "res://resources/cards/rally.tres",
	"riposte": "res://resources/cards/riposte.tres",
	"riptide": "res://resources/cards/riptide.tres",
	"rot_touch": "res://resources/cards/rot_touch.tres",
	"rupture": "res://resources/cards/rupture.tres",
	"salt_the_wound": "res://resources/cards/salt_the_wound.tres",
	"sanguine_feast": "res://resources/cards/sanguine_feast.tres",
	"scrape": "res://resources/cards/scrape.tres",
	"searing_blow": "res://resources/cards/searing_blow.tres",
	"second_heart": "res://resources/cards/second_heart.tres",
	"second_wind": "res://resources/cards/second_wind.tres",
	"shield_wall": "res://resources/cards/shield_wall.tres",
	"shiv": "res://resources/cards/shiv.tres",
	"shrug_it_off": "res://resources/cards/shrug_it_off.tres",
	"sidestep": "res://resources/cards/sidestep.tres",
	"slash": "res://resources/cards/slash.tres",
	"smiths_fury": "res://resources/cards/smiths_fury.tres",
	"smoke_bomb": "res://resources/cards/smoke_bomb.tres",
	"spiked_guard": "res://resources/cards/spiked_guard.tres",
	"spore_burst": "res://resources/cards/spore_burst.tres",
	"stone_skin": "res://resources/cards/stone_skin.tres",
	"strike": "res://resources/cards/strike.tres",
	"stumble": "res://resources/cards/stumble.tres",
	"survival_instinct": "res://resources/cards/survival_instinct.tres",
	"sword_dance": "res://resources/cards/sword_dance.tres",
	"terrify": "res://resources/cards/terrify.tres",
	"thorn_crown": "res://resources/cards/thorn_crown.tres",
	"twin_strike": "res://resources/cards/twin_strike.tres",
	"undying": "res://resources/cards/undying.tres",
	"venom_fang": "res://resources/cards/venom_fang.tres",
	"virulence": "res://resources/cards/virulence.tres",
	"whetted_edge": "res://resources/cards/whetted_edge.tres",
	"whirlwind": "res://resources/cards/whirlwind.tres",
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
		"cards": {"strike": 5, "defend": 3, "jab": 2, "twin_strike": 2},
	},
	"wall": {
		"name": "Wall", "hint": "Defensive. Points toward Fortress and Thorns.",
		"cards": {"strike": 3, "defend": 5, "guard": 2, "shrug_it_off": 2},
	},
	"cunning": {
		"name": "Cunning", "hint": "Cheap and fast. Points toward Tempo and Swarm.",
		"cards": {"strike": 4, "defend": 3, "shiv": 2, "prepared": 3},
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
var cleared_dungeons: Array = []
var highest_dungeon: int = 1
var gold: int = 0  # persistent currency; earned in combat, partly lost on death

func _ready() -> void:
	# Boot with slot 0 if it exists so a scene opened directly still has state;
	# the menus set `slot` and call load_game()/new_save() explicitly.
	if not load_game():
		new_save()

## `kit` picks the starting collection (see STARTER_KITS).
func new_save(kit: String = "blade") -> void:
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
	highest_dungeon = 1
	gold = 0
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

func mark_cleared(id: String) -> void:
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
		"cleared_dungeons": cleared_dungeons,
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
			d["decks"] = {"Starter": {"strike": 4, "defend": 4}}
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
		collection = {"strike": {"count": 4, "level": 1}, "defend": {"count": 4, "level": 1}}

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
