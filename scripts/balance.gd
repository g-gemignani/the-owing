## Single source of truth for tuning (D5). Every balance constant and formula
## lives here so the game and the headless simulator can never drift apart.
class_name Balance
extends RefCounted

enum Tier { NORMAL, ELITE, BOSS }

# --- ascension (New Game+) ---
## Set from the save on load. A static rather than a parameter so every existing
## scaling formula picks it up without changing signatures.
static var ascension: int = 0

## Per-ascension difficulty step. Deliberately gentle: it multiplies an already
## power-scaled curve, so a large step would wall the player instantly.
const ASCENSION_STEP := 0.10

static func ascension_mult() -> float:
	return 1.0 + ASCENSION_STEP * float(maxi(0, ascension))

# --- combat rules ---
const HAND_SIZE := 5
const MAX_ENERGY := 3
const BASE_MAX_HP := 60
const HP_PER_DUNGEON := 10  # max HP gained on clearing a dungeon

## The health bar a player actually has. ONE formula, because the simulator had
## its own and they disagreed about the most important number in the model:
## the game grows max HP with dungeons CLEARED, the sim grew it with the
## difficulty of the dungeon being measured. A player with six clears walking into
## the Crypt has 120 HP; the sim gave that same run 60 and reported the opening of
## the game as roughly twice as dangerous as it is.
static func max_hp_for(clears: int, relic_hp: int = 0) -> int:
	return BASE_MAX_HP + relic_hp + maxi(0, clears) * HP_PER_DUNGEON

# --- upgrade (fusion) caps ---
## Max level per rarity. Caps are derived from drop weight: a rarity that appears
## W/100 as often as a common gets W/100 of the level track, which makes every
## rarity cost roughly the SAME hoarding effort to max out.
## Floored at MIN_MAX_LEVEL so even a legendary is worth fusing at all.
##
## What a level COSTS lives in one place below (fuse_copy_cost / fuse_gold_cost);
## do not restate the numbers here. A stale duplicate of a shared table is what
## made the Crypt unplayable once already.
const MIN_MAX_LEVEL := 5
const COMMON_MAX_LEVEL := 100

## Derived: COMMON 100, UNCOMMON 40, RARE 15, EPIC 5, LEGENDARY 5.
static func max_level(rarity: int) -> int:
	var w: Array = WEIGHTS[Tier.NORMAL]
	var weight: int = w[clampi(rarity, 0, w.size() - 1)]
	var common: int = w[0]
	var derived := int(round(float(COMMON_MAX_LEVEL) * float(weight) / float(common)))
	return maxi(MIN_MAX_LEVEL, derived)

# --- fusion price ---
## Fusing used to be a FLAT 2 copies per level at no gold cost, so power grew
## LINEARLY with copies hoarded and nothing else gated it. A player who banked
## commons walked into a dungeon with a doubled deck and outran the difficulty
## curve. Two brakes, both here:
##
## * copies per level RISE with the level being bought, so the tail costs real
##   hoarding instead of the same two cards forever;
## * gold is spent as well, which puts fusion in direct competition with the shop
##   instead of being free power on the side.
const FUSE_BASE_COPIES := 3
## Levels between each +1 to the copy cost — the curve's STEEPNESS, and the correct
## lever when card income changes (D84). Raising `FUSE_BASE_COPIES` instead would tax
## the fresh save that cannot afford to fuse at all, which is the one place the
## economy was already tight.
##
## Measured, not picked: chests took targeted income from ~1.15 copies of the card
## you are levelling per run to ~2.65. A step of 2 would have cancelled that exactly
## — ten pack openings to buy what three used to buy, which is more clicking for the
## same progression. 4 lets the climb genuinely shorten (Lv15 in ~23 runs against 43,
## Lv40 in ~109 against 169) while keeping a tail worth having.
const FUSE_COPIES_STEP := 4
const FUSE_BASE_GOLD := 20
## Exponent on the gold price. A LINEAR gold cost was measured to stop mattering
## after about four runs: income scales with dungeon depth, so a price that grows
## by a flat step per level is soon rounding error. Superlinear keeps fusion
## competing with the shop for the whole game.
const FUSE_GOLD_EXP := 1.35

## Copies burned to buy the step from `level` to `level + 1`.
static func fuse_copy_cost(level: int) -> int:
	return FUSE_BASE_COPIES + int(floor(float(maxi(1, level) - 1) / float(FUSE_COPIES_STEP)))

## Gold burned for that same step. Shares `rarity_price_mult` with the shop, so
## levelling a card is priced against buying one — but takes NO difficulty, because
## fusion happens between runs. That separation is what let shop prices start
## scaling with depth (D71) without quietly repricing every fusion in the game.
static func fuse_gold_cost(rarity: int, level: int) -> int:
	var growth := pow(float(maxi(1, level)), FUSE_GOLD_EXP)
	return int(round(FUSE_BASE_GOLD * rarity_price_mult(rarity) * growth))

## Copies needed to take a card from level 1 to `level`, walking the cost curve.
static func copies_to_reach(level: int) -> int:
	var total := 1  # the copy you keep
	for l in range(1, maxi(1, level)):
		total += fuse_copy_cost(l)
	return total

## Gold needed for that same climb.
static func gold_to_reach(rarity: int, level: int) -> int:
	var total := 0
	for l in range(1, maxi(1, level)):
		total += fuse_gold_cost(rarity, l)
	return total

# --- deck bounds ---
const MIN_DECK_SIZE := 8
const MAX_DECK_SIZE := 20

# --- player power baseline ---
## Enemies scale against the deck's power PER ENERGY, because that is what the
## player can actually deliver per turn (energy is the binding constraint, not
## deck size or raw card numbers). Two consequences, both deliberate:
##   - a bigger deck of the same cards is not "stronger" (only more consistent)
##   - an expensive card is only stronger if it beats the cost-efficiency curve
## Reference deck (4 Strike @6 dmg + 4 Defend @5 block) with Block valued at
## CardData.BLOCK_VALUE: (4x6 + 4x5x0.65) / 8 energy = 4.625 per energy.
## Recomputed whenever the weighting changes, so the reference deck stays ratio 1.0.
const BASELINE_CARD_POWER := 4.625
## Only part of the player's throughput goes into damage (the rest into block),
## so HP scaling below 1.0 keeps fight LENGTH roughly flat as decks improve.
const HP_POWER_K := 0.5
## Kept low deliberately: difficulty should come from choosing a deeper dungeon,
## not from the player's own progression. Scaling incoming damage steeply with
## deck power punishes offense-heavy decks that have no extra block to answer it.
const DMG_POWER_K := 0.15
const POWER_RATIO_CAP := 4.5  # room for maxed decks; sub-linear card growth keeps this reachable

## Past this ratio a deck is not "a player with a good build" any more — it is the
## thing the deepest dungeons exist to test. Two rules switch on above it (extra
## enemy HP, and pierce that scales with the deck), and NOTHING below it changes,
## which is what keeps every cell D45 tuned exactly where it was. Chosen as the top
## of the build band: the archetype decks measure 2.4-4.0, fully-relic'd late ones
## 4.3-5.9.
const HIGH_POWER_FLOOR := 3.0
## Extra enemy HP per point of ratio above the floor.
##
## Without it, more power made the game EASIER at the top: `HP_POWER_K` at 0.5
## means enemy HP grows at half the rate of your damage, so fights get SHORTER the
## stronger you are — a maxed deck cleared a Maw fight in 4.0 turns against a late
## deck's 5.2, was hit fewer times for it, and finished the last dungeon in the
## game at 100% completion. Raising `HP_POWER_K` itself to 1.0 fixes the top and
## costs the middle everything (measured: Barricade 55% -> 29% at the Foundry, AoE
## 72% -> 6% at the Drowned Market), because it lengthens fights at EVERY ratio and
## escalation then compounds on the decks that were already slow.
const HP_POWER_K_HIGH := 0.5

# --- the ratchet: a dungeon only matches you so far ---
## Enemies used to scale against the player's power with NO upper bound, at every
## depth. Measured at a fixed depth 3: quadrupling deck power made fights 31%
## shorter but cost 68% MORE HP per fight, because incoming damage grew as fast as
## kill speed. Every reward the player earned was confiscated at the door, which is
## why a maxed deck performed WORSE than a merely good one.
##
## Each dungeon now matches the player only up to a ceiling set by its own
## difficulty. Below it, enemies still answer your deck, so a dungeon at the edge
## of your ability stays a fight. Above it, enemy stats stop moving while your
## damage keeps climbing — so you outgrow the Crypt, exactly as you should, and
## difficulty comes from choosing to go deeper.
## The top of the curve must sit ABOVE the strongest deck the game can produce,
## or the deepest content gets outgrown too. Measured: a maxed deck with six
## relics reaches ratio 5.92, while these once topped out at 4.55 — so by
## mid-game the player was above the ceiling of every dungeon and the whole
## back half of the game was a walkover at 100% completion and single-digit HP
## loss. The ratchet is meant to let you outgrow the CRYPT, not the Maw.
const RATIO_CEILING_BASE := 1.4
## Set so the deepest dungeon's ceiling clears the maximum achievable ratio with
## room to spare; see MAX_ACHIEVABLE_RATIO and the test that pins the relationship.
const RATIO_CEILING_PER_DEPTH := 0.90

## The strongest ratio a fully-built player can reach: maxed card levels plus a
## full relic set. Measured with tools/sim_balance.gd, not guessed. The deepest
## dungeon must scale past this or the endgame stops resisting.
##
## Re-measured at 6.09 after D75 repriced relics — a constant whose comment says
## "measured" has to be re-measured when the thing it measures moves, or it becomes
## the fourth restated number in this file to quietly go stale.
const MAX_ACHIEVABLE_RATIO := 6.1

## The power level `difficulty` will scale its enemies to match.
static func ratio_ceiling(difficulty: int) -> float:
	return RATIO_CEILING_BASE + RATIO_CEILING_PER_DEPTH * float(maxi(1, difficulty) - 1)

## The ratio enemies actually scale against: the player's, capped by the dungeon.
## Applied inside enemy_max_hp / enemy_damage so no caller can forget it.
static func scaling_ratio(difficulty: int, ratio: float) -> float:
	return soften_ratio(minf(ratio, ratio_ceiling(difficulty)))

## Raw power of a deck, at fused levels. Uses CardData.power_value() so status
## and power cards count toward scaling instead of reading as zero.
static func deck_power(deck: Array) -> float:
	var p := 0.0
	for c in deck:
		p += c.power_value()
	return p

## Total energy needed to play the whole deck (min 1 to avoid divide-by-zero).
static func deck_cost(deck: Array) -> float:
	var c := 0.0
	for card in deck:
		c += card.cost
	return maxf(1.0, c)

# --- powers (once-per-turn abilities) ---
const POWER_DIR := "res://resources/powers/"
const POWERS := ["bulwark", "foresight", "cleave", "blight", "expose", "bramble",
	"kindle", "overwhelm", "siphon", "second_wind"]


# --- resource caches ---------------------------------------------------------
#
# `load()` already returns the SAME instance for a path, so these dictionaries
# change nothing about aliasing — they only skip ResourceLoader's path resolution,
# measured at 0.136 ms per call. Tolerable once, ruinous in a loop:
# `card_pool_for()` performed six of them per call, cost 1.04 ms, and is called on
# every reward, every shop roll and every simulated encounter. The balance
# simulator was spending ninety per cent of its time in resource lookups — a
# reward roll cost ten times an entire simulated fight.
#
# Safe because every one of these is immutable content read straight off disk. The
# only thing given up is picking up a `.tres` edit without restarting, which is not
# something a running game does anyway.
const CARD_DIR := "res://resources/cards/"

static var _res_cache := {}
static var _pool_cache := {}

static func _cached(path: String):
	if _res_cache.has(path):
		return _res_cache[path]
	var r = load(path)
	_res_cache[path] = r
	return r

## A card resource by id, shared. Callers that mutate it — setting a level, a
## growth — must `duplicate()` first, exactly as they had to when this was a bare
## `load()`, because that returned the same shared instance too.
static func card(id: String) -> CardData:
	return _cached(CARD_DIR + id + ".tres") as CardData

## An enemy archetype by id, shared. Loaded once per fight before this existed,
## which was a fifth of combat setup.
static func enemy(id: String) -> EnemyData:
	return _cached(ENEMY_DIR + id + ".tres") as EnemyData

static func event(id: String) -> EventData:
	return _cached(EVENT_DIR + id + ".tres") as EventData

static func power(id: String) -> PowerData:
	return _cached(POWER_DIR + id + ".tres") as PowerData

static func all_powers() -> Array:
	var out: Array = []
	for id in POWERS:
		var p := power(id)
		if p != null:
			out.append(p)
	return out

## Gold to buy a power outright. Priced off rarity like a shop card, then doubled:
## a power is permanent, fires every turn of every fight, and is never drawn — it
## is worth strictly more than one copy of a card of the same rarity.
static func power_price(rarity: int) -> int:
	return card_price(rarity) * 2

## Gold to take a power from `level` to `level + 1`. Reuses the fusion gold curve
## so the two upgrade tracks compete on equal terms rather than one being the
## obvious dump for spare gold.
static func power_upgrade_cost(rarity: int, level: int) -> int:
	return fuse_gold_cost(rarity, level) * 2

## Power throughput folded into the scaling ratio.
##
## Without this term a power would be free strength sitting outside the deck —
## precisely the hole relics had before RELIC_POWER_PER_RATIO — and it would undo
## the difficulty ratchet.
##
## The gain is NOT the power's raw value. Firing it spends energy that would
## otherwise have played a card, so what the player actually gains is the
## DIFFERENCE between the power and the cards it displaces:
##
##     gain per turn = value(power) x reliability - cost x deck value per energy
##
## Pricing it as pure addition (the first attempt here) charged a 6-Block ability
## as +0.39 ratio when its real edge over an average card is nearer +0.06, which
## would have made equipping any power actively harmful. A zero-cost power
## displaces nothing and so is worth its full value.
##
## The reliability premium exists because a power is never drawn, never dead and
## never clogs a hand — the whole reason it is worth having.
const POWER_RELIABILITY := 1.4

static func power_ratio_bonus(p, deck_per_energy: float = BASELINE_CARD_POWER) -> float:
	if p == null:
		return 0.0
	# energy_gain is handled multiplicatively by throughput_multiplier; counting it
	# here as well would charge for the same effect twice
	var gained: float = (p.power_value() - float(p.energy_gain) * 15.0) * POWER_RELIABILITY
	var displaced: float = float(p.cost) * deck_per_energy
	# a power the player would simply never fire cannot make enemies tougher
	return maxf(0.0, gained - displaced) / (float(MAX_ENERGY) * BASELINE_CARD_POWER)

# --- relics ---
const RELIC_DIR := "res://resources/relics/"
## Relic power is divided by this to convert it into ratio points. Relics are
## permanent and sit outside the deck, so without folding them into the ratio a
## relic collection would outscale enemies exactly the way fusion once did.
const RELIC_POWER_PER_RATIO := 50.0

static func relic_power(relics: Array) -> float:
	var p := 0.0
	for r in relics:
		if r is RelicData:
			p += r.flat_power()
	return p

## Relics that grant energy or draw scale everything the deck does, so they act on
## the ratio multiplicatively. Treating them as flat power undervalued them badly:
## a +1 energy relic is a third more actions every turn of every fight.
static func throughput_multiplier(relics: Array, equipped_power = null) -> float:
	var energy := 0
	var draw := 0
	for r in relics:
		if r is RelicData:
			energy += r.bonus_energy
			draw += r.extra_draw
	# A power that hands back energy every turn scales everything the deck does, so
	# it belongs here rather than in the additive term. Priced additively it read as
	# +0.91 ratio — nearly triple what the identical effect costs on a relic.
	if equipped_power != null:
		energy += equipped_power.energy_gain
	var m := float(MAX_ENERGY + energy) / float(MAX_ENERGY)
	m *= 1.0 + 0.08 * float(draw)
	return m

## Beyond the cap, scaling continues at a diminishing rate instead of stopping.
##
## A HARD cap is itself a power-creep bug: once a deck exceeds it, every further
## point of power is free and the endgame becomes trivial. Measured exactly that —
## fully-equipped late decks pinned the cap and cleared the deepest dungeons 100%
## of the time. A square-root tail keeps enemies growing forever without ever
## running away.
static func soften_ratio(r: float) -> float:
	if r <= POWER_RATIO_CAP:
		return maxf(1.0, r)
	return POWER_RATIO_CAP + sqrt(r - POWER_RATIO_CAP)

## Deck power per energy, relative to the starter deck.
## `relics` is an Array[RelicData] the player currently holds (may be empty).
static func power_ratio(deck: Array, relics: Array = [], equipped_power = null) -> float:
	if deck.is_empty():
		return 1.0
	var per_energy := deck_power(deck) / deck_cost(deck)
	var r := per_energy / BASELINE_CARD_POWER
	r += relic_power(relics) / RELIC_POWER_PER_RATIO
	r += power_ratio_bonus(equipped_power, per_energy)
	r *= throughput_multiplier(relics, equipped_power)
	return soften_ratio(r)

# --- enemy scaling ---
## Boss HP is high but its damage bonus is small: a long fight whose per-turn
## damage the player can actually block, rather than an unwinnable race.
## Enemy HP must be high enough that a fight lasts ~4+ turns — an enemy that dies
## in 2 turns only ever attacks once, which makes attrition (the real difficulty)
## disappear. Boss/elite multipliers are modest because the base is already large.
const TIER_HP_MULT := {Tier.NORMAL: 1.0, Tier.ELITE: 1.3, Tier.BOSS: 1.55}
const TIER_DMG_BONUS := {Tier.NORMAL: 0, Tier.ELITE: 1, Tier.BOSS: 2}
const TIER_NAME := {Tier.NORMAL: "Cultist", Tier.ELITE: "Elite", Tier.BOSS: "Dungeon Boss"}

## Rest node healing, as a fraction of max HP. Must stay well below the damage a
## player accumulates over a few fights, or resting erases all attrition.
const REST_HEAL_FRAC := 0.18

# --- traversal (shared budget across models) ---
## Every traversal model must cost the player a comparable amount, or "difficulty
## 4" means different things in different dungeons. Models build their layout from
## these counts (plus one boss) rather than inventing their own mix.
const ENCOUNTER_COMBATS := 3
const ENCOUNTER_ELITES := 1
const ENCOUNTER_RESTS := 1
const ENCOUNTER_SHOPS := 1
const ENCOUNTER_EVENTS := 1
const ENCOUNTER_TREASURES := 1

## HP paid to slip past an encounter (and forfeit its reward).
##
## Named for the deck model that introduced it until D94; the crawl inherited the
## mechanic in D88 and now owns it outright, so the name no longer says "deck".
##
## This was a flat 8 HP, and it was a cheat. Nothing had ever measured it, because
## the simulator's driver only dodged below 35% HP and so recorded **0.0 avoids per
## run in every profile** — the decision went unexercised for its whole existence. Measured properly (`tools/sim_balance.gd`, avoid
## calibration), skipping every avoidable fight was strictly better than fighting:
## the Drowned Market went from 49% completion to 87% for the same deck, because 8
## HP is a rounding error against a fight that costs 17-31% of a health bar, and a
## flat cost gets *cheaper* with depth while fights get dearer.
##
## Two changes make it a trade again. It scales with depth — through the dungeon's
## difficulty, not the player's max HP, because a Traversal must never read run
## resources (D13) — and it RISES with each dodge already taken this run, the same
## shape as `removal_price`. The first dodge is the one you want; the fourth should
## be unaffordable. Tuned so dodging every fight in a dungeon costs ~70% of the
## health bar and arrives at the boss with no gold and no rewards.
const AVOID_BASE_HP := 6
const AVOID_PER_DEPTH := 1
const AVOID_STEP := 0.5

static func avoid_cost(difficulty: int, already_avoided: int) -> int:
	var base := float(AVOID_BASE_HP + AVOID_PER_DEPTH * (maxi(1, difficulty) - 1))
	return int(round(base * (1.0 + AVOID_STEP * float(maxi(0, already_avoided)))))

## Iso model: the floor is a place, most of it is empty, and something else is
## walking it.
##
## The three models deleted in D94 priced *choosing*. This one's ground is spatial and
## can be re-walked, so the thing that needs a cost is WALKING — without one an
## isometric floor is a node graph plus a pathfinding chore, because there would never
## be a reason not to strip every tile.
##
## That cost used to be a torch: a step allowance with an HP overdraft fee (D77
## removed it). It never affected what the player could see, which made "light"
## a costume on a move counter, and it charged the player for the one thing this
## model exists to sell — looking around. The cost is now **wanderers**: greed
## means more turns on the floor, and every turn on the floor is a turn the things
## living on it also take. Danger scales with exploration instead of a tax on it.
##
## **A dungeon is now several small floors of rooms, not one big field (D79).** The
## floor used to be one organic blob of ~30 tiles: no rooms, no halls, no corridors,
## every tile the same width, and two thirds of it holding literally nothing. It
## measured fine and it did not feel like exploring anything, because nothing was a
## *place* and there was nothing to find.
##
## The size question was settled by arithmetic before any of it was built, and the
## arithmetic changed the design twice. A card battler's loop is short decision →
## fight → reward, so the number that matters is **moves per encounter** (~5 on the
## old floor). Splitting one dungeon's budget across three 30-tile floors gives ~15,
## which buries the card game. Hence:
##
## * more floors that are each SMALLER, not more of the same size; and
## * one-way descent, because making every floor a round trip costs ~8 on its own.
##
## `ISO_MOVES_PER_ENCOUNTER_MAX` is that budget written down, and
## tests/test_traversal.gd fails if a measured greedy walk exceeds it. It is the
## replacement for eyeballing floor sizes.
const ISO_GRID := 12
const ISO_MOVES_PER_ENCOUNTER_MAX := 7.5
## Walkable tiles in a whole DUNGEON, divided among however many floors it has — which
## is why a four-floor dungeon has four small floors and not four of the same size.
##
## Measured rather than picked: a greedy tour costs about 0.75 moves per tile, and the
## budget is ~9.2 encounters, so ~78 tiles lands near 6.5 moves per encounter with
## headroom under the ceiling. Fixing the ROOM COUNT instead (the first attempt) gave
## 53-tile floors holding three encounters each and measured 8.6 — a floor can be
## beautifully built and still be too big for the game it is in.
const ISO_TILES_PER_DUNGEON := 130

## Tiles one floor should come to. Rooms are placed until they cover most of it and
## corridors make up the rest, so this is a target rather than an exact count.
static func iso_tiles_per_floor(floors: int) -> int:
	return int(round(float(ISO_TILES_PER_DUNGEON) / float(maxi(1, floors))))
## Steps of vision down a corridor. A ROOM is revealed whole the moment you set foot
## in it (TraversalIso._reveal_around) — that contrast is the point: corridors are
## blind and chambers open up. A uniform radius everywhere was what made a floor feel
## like a field rather than a building.
const ISO_SIGHT := 2

## How many floors a dungeon has, by its difficulty. Deeper dungeons are deeper
## places; the encounter budget is split across them, so this changes the SHAPE of a
## dungeon and not its cost.
const ISO_FLOORS_MIN := 2
const ISO_FLOORS_MAX := 4
const ISO_DEPTH_PER_FLOOR := 3

static func iso_floors_for(difficulty: int) -> int:
	var extra: int = int(floor(float(maxi(1, difficulty) - 1) / float(ISO_DEPTH_PER_FLOOR)))
	return clampi(ISO_FLOORS_MIN + extra, ISO_FLOORS_MIN, ISO_FLOORS_MAX)

## Architecture, per dungeon. This is what replaces "the traversal model differs" as
## the reason two dungeons do not feel alike: rooms come in different counts, sizes
## and connectedness, so a crypt of burial cells does not walk like a gallery or a
## warren. Unlisted dungeons get ISO_STYLE_DEFAULT.
##
##   rooms — bounds on the chamber count. NOT the count itself: rooms are placed until
##           the floor's tile target is met, so a style of small cells naturally needs
##           more of them than a style of big halls to fill the same floor
##   w / h — chamber size range (in tiles); the longer side is flipped at random, so a
##           gallery dungeon is not combed in one direction
##   loops — extra corridors beyond the spanning path; 0 is a tree (every dead end
##           costs a double walk), more is a place you can circle round in
##   fill  — what fraction of the floor is CHAMBER rather than corridor, and the single
##           most visible knob here. Gate 2 (six floors rendered side by side) found
##           `cells` and `warren` indistinguishable while they differed only by a tile of
##           room width and a loop count; room-versus-corridor is what the eye actually
##           reads, so 0.9 is a honeycomb of cells and 0.5 is tunnels with the odd chamber
##   align — snap chamber origins to this lattice. Regularity is a signature no amount of
##           size variation gives you: burial cells are cut in ranks, a warren is not
const ISO_STYLES := {
	# a honeycomb of small cells cut in ranks, barely linked — you go back the way you came
	"cells": {"rooms": [5, 9], "w": [2, 2], "h": [2, 2], "loops": 0,
		"fill": 0.90, "align": 3},
	# long thin galleries: few rooms, but each one is a walk in itself
	"galleries": {"rooms": [2, 5], "w": [2, 2], "h": [4, 6], "loops": 1,
		"fill": 0.80, "align": 0},
	# tunnels that double back, with small chambers hung off them
	"warren": {"rooms": [3, 6], "w": [2, 3], "h": [2, 3], "loops": 3,
		"fill": 0.45, "align": 0},
	# few big open halls, so a wanderer is visible across one long before it arrives
	"halls": {"rooms": [2, 4], "w": [3, 5], "h": [3, 4], "loops": 1,
		"fill": 0.85, "align": 0},
}
const ISO_STYLE_DEFAULT := "warren"
const ISO_STYLE_OF := {
	"crypt": "cells", "ossuary": "galleries", "warrens": "warren",
	"foundry": "halls", "ember_road": "galleries", "slag_pits": "halls",
	"fungal_deep": "warren", "rot_gardens": "warren", "sunken_vault": "halls",
	"drowned_market": "halls", "abyssal_stair": "galleries", "the_maw": "cells",
}

static func iso_style(dungeon_id: String) -> Dictionary:
	var name: String = String(ISO_STYLE_OF.get(dungeon_id, ISO_STYLE_DEFAULT))
	return ISO_STYLES.get(name, ISO_STYLES[ISO_STYLE_DEFAULT])

## Surface, per dungeon — and deliberately a SEPARATE axis from architecture. Style says
## what shape the place is; terrain says what it is made of. Keeping them apart is what
## makes the variety multiply: four styles against four terrains is sixteen readings out
## of eight constants, where folding surface into style would have given four.
##
## The names are art roles, resolved to `floor_<t>` / `rock_<t>` by
## `tools/install_iso_art.gd` and picked up by `iso_run.gd`. A dungeon whose terrain has
## no art installed falls back to the plain `floor`/`rock` pair, and a floor with no art
## at all still draws — see the fallbacks in `iso_run.gd`.
const ISO_TERRAINS := ["stone", "earth", "moss", "sand"]
const ISO_TERRAIN_DEFAULT := "stone"
const ISO_TERRAIN_OF := {
	# worked stone: crypts, foundries, the long stair
	"crypt": "stone", "ossuary": "stone", "foundry": "stone",
	"abyssal_stair": "stone",
	# dug earth: tunnels, ash roads, slag, and the organic cave at the bottom
	"warrens": "earth", "ember_road": "earth", "slag_pits": "earth",
	"the_maw": "earth",
	# overgrown: stone walls the floor has been reclaimed under
	"fungal_deep": "moss", "rot_gardens": "moss",
	# silted: drowned places that drained
	"sunken_vault": "sand", "drowned_market": "sand",
}

static func iso_terrain(dungeon_id: String) -> String:
	return String(ISO_TERRAIN_OF.get(dungeon_id, ISO_TERRAIN_DEFAULT))

## Which enemies a dungeon can field at a tier, bosses excluded — the same pool
## `CombatEngine._spawn_enemies` rolls from, in one place so the two cannot disagree.
##
## It matters that they agree. The iso model now decides WHICH enemy stands on a tile at
## generation time rather than leaving it to the fight (D85), so if this pool differed
## from the one combat would have used, the model would be quietly changing the enemy
## distribution — which is the D72/D74/D77 failure over again, a tool measuring something
## other than the game.
static func roster_pool(dungeon_data, tier: int) -> Array:
	var roster: Array = []
	if dungeon_data != null and dungeon_data.has_method("has_roster") and dungeon_data.has_roster():
		roster = Array(dungeon_data.enemy_roster)
	if roster.is_empty():
		roster = Array(ROSTER.get(tier, ROSTER[Tier.NORMAL]))
	var pool: Array = roster.filter(func(x): return not (x in ROSTER[Tier.BOSS]))
	return pool if not pool.is_empty() else roster

## What an enemy LOOKS like on the floor, derived from what it does in a fight rather
## than from a hand-kept table — so a new archetype gets a silhouette for free and can
## never be forgotten.
##
## The point is that the silhouette is the first tier of information: read at a distance
## it tells you the *shape* of the fight you are choosing, and only the name (once you
## have met it) tells you which creature. Three readings, because three is what the art
## supports and what a glance can actually distinguish:
##
##   swarm  — comes in numbers, so the danger is being surrounded
##   brute  — tough, or relentless: it will simply keep hitting you
##   caster — frail, and spends its turns setting something up
##
## The thresholds were read off the roster rather than guessed, and the first guess was
## wrong in a way worth recording. `rule_count() > 0` looked like the mark of a caster and
## is nothing of the kind: reactive behaviour was given to enemies across the board (D38),
## so it is nearly universal and put **all 35 archetypes in one family**. Attack frequency
## is barely better — almost every single-spawn enemy alternates attack and utility, so it
## sits at 0.50-0.67 for nine of ten of them.
##
## What actually separates them is **toughness**: brutes measure `hp_mult` 1.00-1.15 and
## casters 0.85-0.90, with `crypt_hound` the one frail thing that nonetheless just attacks,
## which the frequency clause catches. Measured split across both rosters: swarm 8,
## brute 6, caster 4.
##
## `count_max` and not `spawn_count()`: the latter rolls, and a creature's silhouette
## cannot be allowed to change between one look and the next.
const ISO_FAMILIES := ["swarm", "brute", "caster"]
const ISO_FAMILY_DEFAULT := "brute"
const ISO_BRUTE_HP := 1.0
const ISO_BRUTE_FREQ := 0.9

static func iso_family(enemy_id: String) -> String:
	var e := enemy(enemy_id)
	if e == null:
		return ISO_FAMILY_DEFAULT
	if e.count_max > 1:
		return "swarm"
	if e.hp_mult >= ISO_BRUTE_HP or e.attack_frequency() >= ISO_BRUTE_FREQ:
		return "brute"
	return "caster"

## A fight is loud. Wanderers this many steps away wake up and start hunting, which
## is what couples the battle system to the space: WHERE you choose to fight matters,
## and clearing a room next to a sleeping thing is a decision rather than free.
const ISO_NOISE := 6
## Steps on one floor after which everything on it knows you are there. Pressure that
## rises with greed, and — unlike spawning extra monsters — it cannot inflate the
## encounter budget, because it wakes what is already counted.
const ISO_LINGER := 22

## Wanderers come OUT of the combat budget, they are not added to it: a dungeon
## must cost what its difficulty says it costs (D14), so the choice here is how
## much of the budget hunts you rather than how much there is. Half, floored at
## one, so every floor has something on it and the elites stay put as landmarks.
const ISO_WANDER_FRACTION := 0.5
## Steps at which a wanderer notices you and starts pathing. Past it they drift.
## This is the dial that decides how much of the combat budget a careful player
## can actually evade, and therefore whether ISO still costs what GRAPH costs —
## tuned against tools/sim_balance.gd, not chosen.
const ISO_WANDER_SENSE := 5

## What being caught in the open costs, before the fight even starts.
##
## Without this the model has no attrition of its own. The torch used to supply it
## and D77 deleted the torch, which left wanderers carrying the whole cost of greed
## while being — mechanically — budget combats that walked. Same count, same tiers,
## same fights: the Warrens measured 100% completion at every deck in the report,
## against 81% for the Ossuary sitting at the same difficulty.
##
## So a wanderer that reaches you takes the initiative, and that is priced. It is the
## torch's HP cost paid for the opposite thing: the torch charged you for walking, which
## is what this model exists to sell, while this charges you for being caught, which is the
## part a careful player can actually avoid.
##
## **A FRACTION of the health bar, not a flat number (D88).** It was `9 + 2×(depth-1)` for
## as long as one dungeon used this model, and that constant was fitted to make that one
## dungeon land where a difficulty-2 dungeon should. Applied to all twelve it was a
## depth-scaling tax stacked on dungeons already scaled for depth, and it did not fail
## gently: the Foundry at d3 with an Early deck paid ~26 HP of a 80-point bar before any
## fight started and measured **0%**, while the Abyssal Stair fell to 4%.
##
## A flat cost cannot be right at both 60 HP and 220 HP — it is a third of the opening bar
## and a rounding error by the endgame — and depth-scaling it only moves which end is
## wrong. A percentage is the same *decision* at every point on the curve, which is what
## this price is supposed to be: the cost of being careless, not a toll that grows.
## Floored so it never rounds to nothing.
const ISO_AMBUSH_PCT := 7.0
const ISO_AMBUSH_MIN_HP := 3

static func iso_ambush_cost(max_hp: int) -> int:
	return maxi(ISO_AMBUSH_MIN_HP, int(round(float(maxi(1, max_hp)) * ISO_AMBUSH_PCT / 100.0)))

static func iso_wanderers_for(combats: int) -> int:
	if combats <= 0:
		return 0
	# Rounds up at the half, not down. Flooring gave ONE wanderer for the three-combat
	# mix that nine of the twelve dungeons use, and one thing moving on a 27-tile floor
	# is a floor that is still basically empty — the whole point of the open ground is
	# that something is using it too.
	return maxi(1, int(round(float(combats) * ISO_WANDER_FRACTION)))

const NODE_LABEL := {0: "Combat", 1: "Elite", 2: "Rest", 3: "BOSS", 4: "Shop",
	5: "Event", 6: "Treasure"}

## Gold in a chest. It also holds sealed packs, always (D80) — the coin flip that
## used to decide whether a card appeared is gone, because a pack is carried out
## rather than added to the deck, so it cannot dilute the run and does not need to
## be rationed to protect it.
##
## PER CHEST, and a dungeon now holds four to six of them (D84), so this fell from
## 25-60 when it was the only chest in the run. Left alone it would have been a 5x
## gold inflation, and the simulator buys healing at shops with that gold — the
## chests would have quietly made every run easier while looking like a card
## change.
##
## Halved a second time after measuring: even at 10-25 the run came out +2.3 points
## easier on average and pushed four deep cells above the 50-70% target band (the
## endgame Maw 57% -> 72%), because the simulator spends gold on healing at shops
## and the deep cells are the ones where a heal decides the run. At 6-14 a run's
## total chest gold lands near where a single treasure used to leave it, so the
## chests pay in PACKS and difficulty stays where it was tuned.
const TREASURE_GOLD_MIN := 6
const TREASURE_GOLD_MAX := 14
## Chance a treasure also holds an Escape Rope. Ropes are FOUND, never sold:
## a purchasable exit would let the player buy their way out of every risk, which
## is the farming loop escrow was built to close.
const TREASURE_ROPE_CHANCE := 18
# --- sealed packs (D80) ------------------------------------------------------
#
# A second reward channel, deliberately NOT the combat one. A card taken after a
# fight joins the run deck, which is the decision D46 built: taking it dilutes what
# you draw, and measurement says that is a real trade — a poison deck in the Fungal
# Deep and an AoE deck in the Drowned Market both do BETTER with a deck that never
# grows. Replacing that with packs would have deleted the decision and cost the back
# half of the game 10-25 points of completion.
#
# Packs sit where the game was flat instead: a treasure was gold and a coin-flip
# card, a boss was a relic. Both now also yield something SEALED, which is carried
# out at risk with everything else and opened on the overworld — the screen that had
# no moment in it at all. Being an object rather than a number is the point: "three
# unopened packs, lost if you die here" reads where "4 cards and 140 gold" does not.
const PACK_TREASURE := "treasure"
const PACK_ELITE := "elite"
const PACK_BOSS := "boss"

# --- pack tiers (D81) --------------------------------------------------------
#
# A pack has a TIER, which is how good it is allowed to be, and a BUILD, which is
# what is inside it. Both are decided where it is found and both are printed on it
# before it is opened.
#
# The tier exists so that a pack found in the first dungeon cannot hand out a
# legendary. Without a cap, "where you found it" stopped meaning anything the
# moment packs stopped rolling on the dungeon pool.
const PACK_WORN := "worn"
const PACK_SEALED := "sealed"
const PACK_GILDED := "gilded"
const PACK_TIERS := [PACK_WORN, PACK_SEALED, PACK_GILDED]
## The best rarity each tier may contain. This is the whole promise of a tier.
const PACK_TIER_CAP := {
	PACK_WORN: CardData.Rarity.RARE,
	PACK_SEALED: CardData.Rarity.EPIC,
	PACK_GILDED: CardData.Rarity.LEGENDARY,
}
const PACK_TIER_CARDS := {PACK_WORN: 2, PACK_SEALED: 3, PACK_GILDED: 4}
const PACK_TIER_GOLD := {PACK_WORN: 10, PACK_SEALED: 18, PACK_GILDED: 30}
const PACK_TIER_NAME := {PACK_WORN: "Worn", PACK_SEALED: "Sealed", PACK_GILDED: "Gilded"}

## How likely each tier is, by where the pack came from and how deep that was.
##
## A treasure at depth 1 is nearly always worn; a boss is never worn, because the
## thing a boss leaves behind should not be the thing a chest leaves behind. Depth
## is what moves the odds, so descending is what upgrades your packs — the same
## axis every other reward in the game is priced on.
static func pack_tier_odds(kind: String, dungeon: int) -> Array:
	var d: int = maxi(1, dungeon)
	match kind:
		PACK_BOSS:
			return [0, maxi(1, 60 - 6 * d), 40 + 6 * d]
		PACK_ELITE:
			return [maxi(0, 45 - 5 * d), 55, maxi(1, 5 * d)]
		_:
			# the gilded coefficient is what decides how often a VAULT is met, since
			# a chest's tier is also its lock (D84). At 2 it produced 0.6 vaults per
			# run at the deepest dungeon and none at all above depth 2 — too rare to
			# be a mechanic the player learns to play around.
			return [maxi(5, 80 - 6 * d), 20 + 4 * d, maxi(0, 3 * (d - 2))]

static func roll_pack_tier(kind: String, dungeon: int) -> String:
	return PACK_TIERS[weighted_pick(pack_tier_odds(kind, dungeon))]

## The build a dungeon tends to yield packs for, derived from how many of that
## build's cards sit in its own card pool.
##
## DERIVED, not authored: a `pack_build` field on 12 dungeon resources would be the
## D34 duplication trap again — the affinity would silently stop matching the pool
## the first time a card list changed. This way it cannot drift, and adding a
## poison card to the Rot Gardens makes the Rot Gardens more of a poison dungeon
## without anyone remembering to say so.
static var _affinity_cache := {}
static func pack_build_affinity(dungeon_id: String) -> String:
	if _affinity_cache.has(dungeon_id):
		return _affinity_cache[dungeon_id]
	var pool: Array = card_pool_for(dungeon_id)
	var best: String = BUILDS[0]
	var best_n := -1
	for bid in BUILDS:
		var b := build(bid)
		if b == null:
			continue
		var n := 0
		for cid in b.cards:
			if pool.has(cid):
				n += 1
		if n > best_n:
			best_n = n
			best = bid
	_affinity_cache[dungeon_id] = best
	return best

## Which build's pack this is. The dungeon's own affinity is weighted so it takes
## about 57% of packs found there: farming a dungeon for an archetype WORKS without
## the drop being a foregone conclusion, and the overworld choice becomes the way
## you aim at a deck — the only lever the player has over what a pack contains.
##
## MEASURED, not picked (`tools/pack_income.gd`). At the first weight tried, a third
## of packs, typed packs paid FEWER copies of any single card than the untyped ones
## they replaced — spread across seven builds they broadened the collection instead
## of deepening it, which is the opposite of aiming. The weight is what turns "many
## cards" into "copies of the card you are levelling".
const PACK_AFFINITY_WEIGHT := 8
static func roll_pack_build(dungeon_id: String) -> String:
	var affinity := pack_build_affinity(dungeon_id)
	var weights: Array = []
	for bid in BUILDS:
		weights.append(PACK_AFFINITY_WEIGHT if bid == affinity else 1)
	return BUILDS[weighted_pick(weights)]

## What can come out: that build's cards, minus anything above the tier's cap.
##
## The build list is the pool, NOT the dungeon's — intersecting the two was tried
## and measured at 1-3 cards per dungeon, which is not a pack, it is a guarantee.
## So the two reward channels split cleanly: a fight reward is the dungeon's cards,
## a pack is the archetype's, and the tier cap is what keeps a first-dungeon chest
## from paying out the back half of the catalogue.
static func pack_pool(build_id: String, tier: String) -> Array:
	var b := build(build_id)
	if b == null:
		return []
	var cap: int = int(PACK_TIER_CAP.get(tier, CardData.Rarity.RARE))
	var out: Array = []
	for cid in b.cards:
		var c := card(cid)
		if c != null and c.rarity <= cap:
			out.append(cid)
	return out

## Deeper packs are worth more, on the same curve the rest of the economy uses.
static func pack_gold(dungeon: int, tier: String) -> int:
	var base: float = float(PACK_TIER_GOLD.get(tier, 10))
	return int(round(base + pow(float(maxi(1, dungeon)), GOLD_DEPTH_EXP)))

static func pack_cards(tier: String) -> int:
	return int(PACK_TIER_CARDS.get(tier, 2))

## Rarity weights for what is inside. A gilded pack rolls on boss odds — the finale
## should feel like the finale when it is opened, three screens later.
static func pack_weights(dungeon: int, tier: String) -> Array:
	return reward_weights(Tier.BOSS if tier == PACK_GILDED else Tier.NORMAL, dungeon)

## What the pack calls itself, e.g. "Gilded pack — The Long Death".
static func pack_title(tier: String, build_id: String) -> String:
	var b := build(build_id)
	return "%s pack — %s" % [PACK_TIER_NAME.get(tier, "Worn"),
		b.name if b != null else build_id]

## Pick an index from a weight array. Shared by every pack roll so a zero-weight
## entry is impossible to pick in one place rather than three.
static func weighted_pick(weights: Array) -> int:
	var total := 0
	for w in weights:
		total += maxi(0, int(w))
	if total <= 0:
		return 0
	var roll := randi() % total
	for i in weights.size():
		roll -= maxi(0, int(weights[i]))
		if roll < 0:
			return i
	return weights.size() - 1

# --- chests and their locks (D84) --------------------------------------------
#
# A treasure is a CHEST now, and a chest has the same three tiers a pack does. The
# tier decides three things at once: how many packs are inside, and what it wants
# before it opens.
#
# The point is not more reward, it is that walking somewhere has to BUY something.
# D79 capped moves per encounter because a spatial model can bury the card game;
# the answer is not fewer steps but steps that were a decision — a detour for a key
# is walking that bought something, and the ceiling is really policing the other
# kind.
const CHEST_PACKS := {PACK_WORN: 1, PACK_SEALED: 2, PACK_GILDED: 3}
## What each tier wants before it opens. Worn chests are simply open.
const CHEST_LOCK_NONE := "none"
const CHEST_LOCK_KEY := "key"
const CHEST_LOCK_VAULT := "vault"
const CHEST_LOCK := {
	PACK_WORN: CHEST_LOCK_NONE,
	PACK_SEALED: CHEST_LOCK_KEY,
	PACK_GILDED: CHEST_LOCK_VAULT,
}
static func chest_packs(tier: String) -> int:
	return int(CHEST_PACKS.get(tier, 1))

static func chest_lock(tier: String) -> String:
	return String(CHEST_LOCK.get(tier, CHEST_LOCK_NONE))

## Keys are found, never bought — the same rule ropes follow, and for the same
## reason: a purchasable key turns every locked chest into a gold check, and a gold
## check is not a decision, it is a delay.
const KEY_CHEST_CHANCE := 45
const KEY_FIGHT_CHANCE := 22
const KEY_ELITE_CHANCE := 60

# --- vault conditions --------------------------------------------------------
#
# A gilded chest asks the RUN to prove something instead of asking for an item.
# Generated from state rather than written down, because a written riddle is solved
# once and is a lever ever after, and a roguelike is replayed hundreds of times.
# Every condition here is knowable before the door is reached and actionable when
# it is — the two properties that separate a puzzle from a coin toss.
const VAULT_UNHURT := "unhurt"
const VAULT_RICH := "rich"
const VAULT_ARMED := "armed"
const VAULT_THIN := "thin"
const VAULT_LADEN := "laden"
const VAULTS := [VAULT_UNHURT, VAULT_RICH, VAULT_ARMED, VAULT_THIN, VAULT_LADEN]
const VAULT_HP_FRAC := 0.7
const VAULT_GOLD := 150
const VAULT_THIN_SLACK := 3
const VAULT_LADEN_PACKS := 3

static func vault_text(cond: String, build_id: String = "") -> String:
	match cond:
		VAULT_RICH:
			return "opens for the solvent: carry %d gold" % VAULT_GOLD
		VAULT_ARMED:
			var b := build(build_id)
			# "a %s card" reads as "a The Long Death card" — build names carry their
			# own article, so the sentence has to be built around them
			return "opens for the committed: a card from %s in your deck" % [
				b.name if b != null else "some archetype"]
		VAULT_THIN:
			return "opens for the disciplined: a deck of %d cards or fewer" % [
				MIN_DECK_SIZE + VAULT_THIN_SLACK]
		VAULT_LADEN:
			return "opens for the greedy: %d sealed packs already carried" % VAULT_LADEN_PACKS
		_:
			return "opens for the untouched: above %d%% of your health" % [
				int(round(VAULT_HP_FRAC * 100.0))]

## Chance a cleared boss yields a rope on top of its relic.
const BOSS_ROPE_CHANCE := 35

# --- events ---
const EVENT_DIR := "res://resources/events/"
const EVENTS := ["shrine", "gambler", "old_soldier", "cursed_hoard", "wounded_scout", "collapsed_arch", "whispering_door", "dead_merchant", "mirror_pool", "iron_maiden", "gambling_ghost", "bloodied_altar", "forgotten_library", "starving_thing", "weeping_statue", "coin_press", "two_doors", "old_bargain", "supply_cache", "hollow_choir"]

## Rough threat of a dungeon's roster, independent of its difficulty rating.
##
## Exists because roster choice repeatedly overrode the difficulty number: a
## roster of hard hitters made difficulty 3 harder than 6, and a 1.1-damage
## archetype made the *first* dungeon harder than the two after it. A number lets
## a test catch the inversion instead of a playthrough noticing it later.
static func roster_threat(dungeon_id: String) -> float:
	var d := dungeon(dungeon_id)
	if d == null or not d.has_roster():
		return 1.0
	var total := 0.0
	var n := 0
	for aid in d.enemy_roster:
		var a := load(ENEMY_DIR + aid + ".tres") as EnemyData
		if a == null:
			continue
		var t := a.dmg_mult + a.hp_mult * 0.4
		t *= 1.0 + 0.12 * float(maxi(0, a.count_max - 1))   # more bodies, more pressure
		# a debuffing archetype multiplies everything after it
		for act in a.pattern:
			if int(act) == EnemyData.Action.DEBUFF_VULN or int(act) == EnemyData.Action.DEBUFF_WEAK:
				t *= 1.08
				break
		total += t
		n += 1
	return total / float(maxi(1, n))

# --- dungeons (D6) ---
const DUNGEON_DIR := "res://resources/dungeons/"
## Ordered registry. The overworld will later choose from these by id.
const DUNGEONS := ["crypt", "ossuary", "warrens", "foundry", "ember_road", "slag_pits", "fungal_deep", "rot_gardens", "sunken_vault", "drowned_market", "abyssal_stair", "the_maw"]

# --- zones (themed clusters of dungeons that share a card pool) ---
const ZONE_DIR := "res://resources/zones/"
const ZONES := ["barrows", "foundry_zone", "rot", "deeps", "beyond"]

static func zone(id: String) -> ZoneData:
	return _cached(ZONE_DIR + id + ".tres") as ZoneData

static func all_zones() -> Array:
	var out: Array = []
	for id in ZONES:
		var z := zone(id)
		if z != null:
			out.append(z)
	return out

## The zone a dungeon belongs to, or null.
# --- builds (deck archetypes) ---
const BUILD_DIR := "res://resources/builds/"
const BUILDS := ["poison", "thorns", "strength", "fortress", "swarm", "tempo", "vampire"]

static func build(id: String) -> BuildData:
	return _cached(BUILD_DIR + id + ".tres") as BuildData

static func all_builds() -> Array:
	var out: Array = []
	for id in BUILDS:
		var b := build(id)
		if b != null:
			out.append(b)
	return out

## Clears actually required to open a dungeon: its own gate or its zone's,
## whichever is higher. Displaying only the dungeon's own number would understate
## the requirement whenever the zone is the real blocker.
## The final dungeon: clearing it completes a world and offers the next ascension.
## The named boss of a dungeon, or null. Fixed per dungeon so the player can plan
## for it — a boss whose identity is a surprise cannot be prepared for, and the
## preparation IS the decision the deck screen is asking for.
static func boss_of(dungeon_id: String) -> EnemyData:
	var d := dungeon(dungeon_id)
	if d == null or d.boss == "":
		return null
	return load(ENEMY_DIR + d.boss + ".tres") as EnemyData

## One-line warning of what the boss does, built from its rules so it can never
## drift from the fight itself.
static func boss_warning(dungeon_id: String) -> String:
	var b := boss_of(dungeon_id)
	if b == null:
		return ""
	var says: Array[String] = []
	for i in b.rule_count():
		var t: int = b.rule_trigger[i]
		var a: int = b.rule_action[i]
		var n: int = b.rule_threshold[i]
		var when := ""
		match t:
			EnemyData.Trigger.SELF_HP_BELOW_PCT: when = "below %d%% HP" % n
			EnemyData.Trigger.PLAYER_BLOCK_ABOVE: when = "if you hold %d+ Block" % n
			EnemyData.Trigger.PLAYER_HP_BELOW_PCT: when = "when you drop under %d%%" % n
			EnemyData.Trigger.CARDS_PLAYED_ABOVE: when = "if you play %d+ cards a turn" % n
			EnemyData.Trigger.EVERY_N_TURNS: when = "every %d turns" % n
		var does := ""
		match a:
			EnemyData.Action.SUNDER: does = "strikes through Block"
			EnemyData.Action.ENRAGE: does = "enrages"
			EnemyData.Action.DRAIN: does = "drains and heals"
			EnemyData.Action.EMPOWER: does = "grows stronger"
			EnemyData.Action.DEFEND: does = "shields itself"
			EnemyData.Action.DEBUFF_VULN: does = "makes you Vulnerable"
			EnemyData.Action.DEBUFF_WEAK: does = "weakens you"
			_: does = "attacks"
		# String.capitalize() title-cases every word ("Below 50% Hp"); only the
		# first letter should change.
		var lead := when.substr(0, 1).to_upper() + when.substr(1)
		says.append("%s it %s" % [lead, does])
	return "; ".join(says) + "." if not says.is_empty() else ""

static func final_dungeon() -> String:
	return DUNGEONS[DUNGEONS.size() - 1]

static func effective_gate(dungeon_id: String) -> int:
	var d := dungeon(dungeon_id)
	var z := zone_of(dungeon_id)
	return maxi(d.unlock_after_clears if d != null else 0,
		z.unlock_after_clears if z != null else 0)

## Clears needed before every gate dungeon of this build is open.
static func clears_required_for(b: BuildData) -> int:
	var worst := 0
	for did in dungeons_required_for(b):
		worst = maxi(worst, effective_gate(did))
	return worst

## Dungeons that are the ONLY source of some card in this build. Clearing them is
## what completing the build actually requires.
static func dungeons_required_for(b: BuildData) -> Array:
	var needed: Array = []
	for did in DUNGEONS:
		var d := dungeon(did)
		if d == null:
			continue
		for c in d.exclusive_cards:
			if c in b.cards and not did in needed:
				needed.append(did)
	return needed

static func zone_of(dungeon_id: String) -> ZoneData:
	for z in all_zones():
		if dungeon_id in z.dungeons:
			return z
	return null

## Cards obtainable in a dungeon: its zone's themed pool plus its own exclusives.
static func card_pool_for(dungeon_id: String) -> Array:
	if _pool_cache.has(dungeon_id):
		return _pool_cache[dungeon_id]
	var out: Array = []
	var z := zone_of(dungeon_id)
	if z != null:
		for c in z.card_pool:
			if not c in out:
				out.append(c)
	var d := dungeon(dungeon_id)
	if d != null:
		for c in d.card_pool:
			if not c in out:
				out.append(c)
	_pool_cache[dungeon_id] = out
	return out

static func dungeon(id: String) -> DungeonData:
	return _cached(DUNGEON_DIR + id + ".tres") as DungeonData

static func all_dungeons() -> Array:
	var out: Array = []
	for id in DUNGEONS:
		var d := dungeon(id)
		if d != null:
			out.append(d)
	return out

## Reward rarity weights, shifted toward rarer cards as the dungeon gets harder.
## This is the "deeper dungeon, better loot" rule: the tier table sets the shape,
## difficulty tilts it. Weights are shifted, not replaced, so a hard dungeon still
## drops commons — it just stops being *mostly* commons.
static func reward_weights(tier: int, difficulty: int) -> Array:
	var base: Array = WEIGHTS[tier]
	var tilt := clampf(0.12 * float(maxi(0, difficulty - 1)) + 0.05 * float(ascension), 0.0, 0.9)
	var out: Array = []
	for i in base.size():
		# rarity index 0 loses weight, higher indices gain it
		var rarity_bias := float(i) / float(maxi(1, base.size() - 1))  # 0..1
		var f := (1.0 - tilt) + tilt * rarity_bias * 3.0
		out.append(maxi(1, int(round(float(base[i]) * f))))
	return out

# --- enemy archetypes ---
## Which archetypes can appear per tier. Bosses stay single-target for now.
const ENEMY_DIR := "res://resources/enemies/"
const ROSTER := {
	Tier.NORMAL: ["cultist", "hexer", "rat_swarm", "bone_picker", "grave_moth",
		"crypt_hound", "plague_rat", "spore_thing", "slag_wretch", "drowned_thrall"],
	Tier.ELITE: ["brute", "warden", "hexer", "pale_acolyte", "bog_lurker",
		"forge_hound", "rot_priest", "tomb_guard"],
	Tier.BOSS: ["abyss_horror", "bellows_master", "brood_mother", "cinder_knight", "deep_warden", "false_step", "grave_sexton", "last_vendor", "marrow_abbot", "mycelial_lord", "the_gardener", "warden"],
}

## Multi-enemy encounters split the tier's HP and damage budget across the group.
## A premium is added back because focus-firing shrinks incoming damage every time
## one dies, which otherwise makes a group strictly easier than a single enemy of
## the same total stats.
const MULTI_DMG_PREMIUM := 0.08   # per extra enemy
const MULTI_HP_PREMIUM := 0.10    # per extra enemy

static func multi_dmg_factor(count: int) -> float:
	return 1.0 + MULTI_DMG_PREMIUM * float(maxi(0, count - 1))

static func multi_hp_factor(count: int) -> float:
	return 1.0 + MULTI_HP_PREMIUM * float(maxi(0, count - 1))

# --- enemy status effects (elites/bosses only) ---
## Every Nth turn an elite/boss also applies a debuff, so higher tiers threaten
## the player's plan and not just their HP bar.
## Kept deliberately mild: debuffs multiply damage over every remaining turn, so
## they compound hard in the long fights that elites and bosses already produce.
const ENEMY_DEBUFF_PERIOD := 4
const ENEMY_VULNERABLE_STACKS := 1
const ENEMY_WEAK_STACKS := 1

## Minimum turns a basic fight should last. An enemy that dies in 2 turns only
## ever attacks once, which silently removes attrition from the whole game.
const MIN_FIGHT_TURNS := 3
## Rough baseline damage a starter deck delivers per turn (energy x power, with
## part of the budget going to block instead of damage).
const BASELINE_TURN_DAMAGE := MAX_ENERGY * BASELINE_CARD_POWER * 0.7

## Target fight length for a basic enemy, in turns. Enemy HP is derived from it:
## the player splits ~3 energy between block and damage, so only part of their
## throughput kills. Deriving HP from a turn budget keeps fight pacing stable
## instead of drifting whenever another constant changes.
const TARGET_NORMAL_TURNS := 4.0
## Share of the energy budget a player can commit to damage while still defending.
const OFFENSE_SHARE := 0.5

static func enemy_max_hp(dungeon: int, tier: int, ratio: float) -> int:
	# damage a baseline deck lands per turn while also blocking
	var dps := MAX_ENERGY * BASELINE_CARD_POWER * OFFENSE_SHARE
	var base := dps * TARGET_NORMAL_TURNS + dungeon * 5.0
	base *= float(TIER_HP_MULT[tier])
	var sr := scaling_ratio(dungeon, ratio)
	base *= 1.0 + HP_POWER_K * (sr - 1.0) \
		+ HP_POWER_K_HIGH * maxf(0.0, sr - HIGH_POWER_FLOOR)
	base *= ascension_mult()
	return int(round(base))

## Enemy attack for turn `turn` (1-based). `roll` in [0,3] keeps randomness
## caller-side.
##
## Structural note: without escalation, defending is a dominant strategy. Block is
## ~5 per energy, so 3 energy absorbs ~15 — a player who simply blocks every turn
## takes zero damage and wins slowly, and no amount of tuning the base number
## changes that, because there is no cost to stalling. ESCALATION makes each extra
## turn more dangerous than the last, so the player must actually race: block only
## what they must, and commit the rest to ending the fight. It is also what makes
## persistent block (Barricade) valuable rather than merely convenient.
static func enemy_damage(dungeon: int, tier: int, ratio: float, roll: int, turn: int = 1) -> int:
	var d := 7.5 + roll + 0.6 * dungeon
	d += float(TIER_DMG_BONUS[tier])
	d *= 1.0 + DMG_POWER_K * (scaling_ratio(dungeon, ratio) - 1.0)
	d *= minf(ESCALATION_MAX, 1.0 + ESCALATION_PER_TURN * float(maxi(0, turn - 1)))
	d *= ascension_mult()
	return int(round(d))

## Enemy damage grows this much per turn elapsed (compounding pressure), up to
## ESCALATION_MAX. The cap matters: stronger decks face more enemy HP, so their
## fights run longer, and uncapped escalation would punish progression — the
## exact inversion this curve is supposed to avoid.
## SUNDER bypasses Block, so it must hit for LESS than a normal swing — otherwise
## it is strictly better than attacking and the enemy should simply always use it.
## Measured at full damage: block-heavy builds fell from 74% to 32% run completion
## and AoE decks from 92% to 32%. It is meant to punish over-blocking, not to
## delete defensive play.
const SUNDER_DAMAGE_FRAC := 0.55

## Share of an enemy attack that ignores Block, rising with dungeon depth.
##
## Without this the difficulty curve flatlines, and no tuning constant fixes it.
## Block scales LINEARLY with deck power, while enemy damage scales as
## 1 + DMG_POWER_K x (ratio - 1) — sublinear for any K below 1, which is the whole
## point of the ratchet. So once a deck's throughput passes the enemy's, block
## absorbs everything: measured 0 net damage per turn at ratio 5, at every K from
## 0.15 to 0.75. Raising K to 1.0 only flips it back to punishing progression.
## The system is a knife edge between "block wins entirely" and "power is punished".
##
## Pressure that Block cannot answer is what breaks the tie, and the game already
## had it in SUNDER and poison — just on too few archetypes to matter. Depth now
## carries it directly: the shallow floors are answerable with a shield, the deep
## ones are not, which is also what makes them read as deeper.
## Depth alone was not enough, and the reason is the same argument one step
## further. Pierce exists because Block scales with the player's power and enemy
## damage does not. A pierce fraction fixed per depth is itself a constant, so the
## same arithmetic catches up with it: at the Maw a deck at ratio 5 blocked
## everything the remaining 78% could throw, and every late profile measured 100%
## completion — the plateau DESIGN.md had recorded as an open gap.
##
## So it rises with the deck as well, THROUGH `scaling_ratio` — which is capped by
## the dungeon's own ceiling. That is what keeps this consistent with the D36
## ratchet instead of undoing it: the Crypt's ceiling is 1.4, so no amount of
## growth makes the Crypt pierce you, and you outgrow it exactly as intended. The
## Maw has no cap below what a player can reach, so it answers back.
##
## Multiplying the depth term (rather than adding) keeps depth 1 at exactly zero
## however strong you are: the tutorial dungeon must stay answerable with a shield,
## which is what teaches Block in the first place.
const PIERCE_AT_DEPTH_1 := 0.0
const PIERCE_PER_DEPTH := 0.032
## How fast it rises above HIGH_POWER_FLOOR. Below that floor this changes nothing,
## and that threshold is what makes it safe to add: block builds are the decks
## pierce punishes twice — once for being blocked through, again because their slow
## fights pay it every turn — and a Barricade deck sits at 2.4. Measured: scaling
## from ratio 1 instead took Barricade run completion from 59% to 31%, which
## deletes an archetype in order to fix the endgame.
const PIERCE_PER_RATIO := 0.5

## Fraction of a hit that goes straight to HP: depth, raised by how far past
## `HIGH_POWER_FLOOR` the deck has grown — capped by the dungeon, as ever.
static func pierce_fraction(dungeon: int, ratio: float = 1.0) -> float:
	var depth := PIERCE_AT_DEPTH_1 + PIERCE_PER_DEPTH * float(maxi(1, dungeon) - 1)
	var excess := maxf(0.0, scaling_ratio(dungeon, ratio) - HIGH_POWER_FLOOR)
	return clampf(depth * (1.0 + PIERCE_PER_RATIO * excess), 0.0, 0.5)

const ESCALATION_PER_TURN := 0.06
const ESCALATION_MAX := 1.6

# Map node type chances (percent) lived here, rolled per non-boss, non-first row.
# Retired in D84: the graph model rolled node types from five fixed percentages while
# taking its SIZE from the encounter mix, so the two disagreed and only the size
# responded when a dungeon's shape changed. Every model derived its weights from the
# mix after that — the single source of truth — and the graph itself went in D94.

# --- shops (gold sink) ---
## Card prices are DERIVED from drop weight, like upgrade caps: a rarity that
## drops W/100 as often as a common costs sqrt(100/W) times as much. sqrt rather
## than linear on purpose — linear would price a legendary at ~4000g, roughly 20
## runs of income, which reads as unobtainable rather than aspirational.
const SHOP_CARD_OFFERS := 3
## Healing sold as a fraction of max HP.
const SHOP_HEAL_FRAC := 0.35

## Shop prices are quoted in FIGHTS, not in gold (D71).
##
## They used to be flat numbers — a common was 40 gold in the Crypt and 40 gold in
## the Maw — while income scales with `GOLD_DEPTH_EXP`. Measured over 400 generated
## Crypt maps, a first-run player reached the merchant holding a median of 20 gold
## against a cheapest item of 40, and could buy NOTHING on 74% of visits. At d8 the
## same 40 was less than one fight's takings. Pricing in fights makes a purchase
## cost the same amount of *play* at every depth, and cannot drift from the income
## curve because it is computed from it.
const SHOP_COMMON_IN_FIGHTS := 2.0
const SHOP_HEAL_IN_FIGHTS := 2.5
const SHOP_REMOVAL_IN_FIGHTS := 3.0
const SHOP_REMOVAL_STEP_IN_FIGHTS := 2.0
## The roll that stands for an average fight when pricing. `gold_reward` takes a
## 0-5 roll; the midpoint is what a price should be measured against.
const GOLD_AVG_ROLL := 2

## What one average fight pays at this depth. The unit every shop price is quoted in.
static func fight_income(difficulty: int) -> int:
	return gold_reward(maxi(1, difficulty), Tier.NORMAL, GOLD_AVG_ROLL)

## How much rarer, and therefore pricier, `rarity` is than a common.
##
## ONE copy of this. `card_price` and `fuse_gold_cost` each carried their own
## `sqrt(common / weight)`, with a comment on the second saying it was deliberately
## the same as the first — which is the D34 restated-table shape, and it is what
## made pricing cards by depth risk silently repricing fusion. Now depth is an
## argument to the shop price and fusion simply does not take one.
static func rarity_price_mult(rarity: int) -> float:
	var w: Array = WEIGHTS[Tier.NORMAL]
	var weight: float = float(w[clampi(rarity, 0, w.size() - 1)])
	return sqrt(float(w[0]) / maxf(1.0, weight))

## Middle of the difficulty range, derived from the dungeons that exist.
##
## The reference depth for anything bought OUTSIDE a dungeon (powers), which has no
## run to take a difficulty from. `tests/test_shop.gd` already reasoned this way —
## it measures legendary affordability at mid depth, noting that pricing the rarest
## card against the poorest floor calls every legendary unobtainable. That was the
## right instinct applied to the test instead of to the price.
static func mid_difficulty() -> int:
	var deepest := 1
	for did in DUNGEONS:
		var dd := dungeon(did)
		if dd != null:
			deepest = maxi(deepest, dd.difficulty)
	return maxi(1, deepest / 2)

## Gold for a card at the depth it is being sold at.
##
## `difficulty <= 0` means "no dungeon context" and prices at mid depth, so a
## caller that legitimately has no run (the powers screen) is not silently given
## first-dungeon prices.
static func card_price(rarity: int, difficulty: int = 0) -> int:
	var d: int = difficulty if difficulty > 0 else mid_difficulty()
	return int(round(rarity_price_mult(rarity) * SHOP_COMMON_IN_FIGHTS
		* float(fight_income(d))))

static func heal_price(max_hp: int, difficulty: int = 0) -> int:
	var d: int = difficulty if difficulty > 0 else mid_difficulty()
	# Priced per point restored, so a bigger pool still costs more to top up: at
	# BASE_MAX_HP a full salve costs SHOP_HEAL_IN_FIGHTS fights exactly.
	var per_hp := SHOP_HEAL_IN_FIGHTS * float(fight_income(d)) / float(heal_amount(BASE_MAX_HP))
	return int(round(float(heal_amount(max_hp)) * per_hp))

static func heal_amount(max_hp: int) -> int:
	return int(round(max_hp * SHOP_HEAL_FRAC))

# --- in-run deck shaping (D46) ---
## A run used to only ever ADD cards: earn_card appends and nothing removes, so
## surviving longer made your deck steadily less consistent. Thinning is the other
## direction, and it is priced so it competes with buying and healing.
##
## The price rises per removal within a run: the first cut is the obvious one, and
## each after it should be a harder call than the last.
## Quoted in fights like everything else the merchant sells (D71), so thinning
## stays a real choice against a card and a heal at every depth instead of being
## unaffordable in the Crypt and loose change in the Maw.
static func removal_price(already_removed: int, difficulty: int = 0) -> int:
	var d: int = difficulty if difficulty > 0 else mid_difficulty()
	var fights := SHOP_REMOVAL_IN_FIGHTS \
		+ SHOP_REMOVAL_STEP_IN_FIGHTS * float(maxi(0, already_removed))
	return int(round(fights * float(fight_income(d))))

## How often a deck of this size shows you any particular card, in turns.
##
## Dilution is real — a bigger deck draws each card less often — but it was
## completely invisible, so taking every reward was an automatic click rather than
## a decision. This is the number the reward screen quotes.
static func draw_interval(deck_size: int) -> float:
	return float(maxi(1, deck_size)) / float(maxi(1, HAND_SIZE))

# --- rewards ---
const TIER_GOLD_MULT := {Tier.NORMAL: 1, Tier.ELITE: 2, Tier.BOSS: 4}

## Reward must climb at least as fast as risk, or the optimal play is to farm the
## easiest dungeon forever.
##
## This became urgent the moment enemies stopped matching the player without limit
## (see RATIO_CEILING_BASE). Once a strong deck can outgrow the Crypt, a LINEAR
## gold curve made grinding it strictly optimal: measured d1 -> d8 as 10x the HP
## lost per fight for 1.8x the gold. Superlinear depth pay keeps going deeper the
## rational choice as well as the interesting one. The exponent is set so mid-depth
## income is roughly unchanged — the fusion prices were tuned against it.
const GOLD_DEPTH_EXP := 1.8

static func gold_reward(dungeon: int, tier: int, roll: int) -> int:
	var base := 4.0 + pow(float(maxi(1, dungeon)), GOLD_DEPTH_EXP) + float(roll)
	return int(round(base)) * int(TIER_GOLD_MULT[tier])

## What a dungeon still pays once you have already cleared it.
##
## The measured problem was not that the middle of the game was too easy — the D36
## ratchet MEANS to let you outgrow a place. It was that outgrowing one was
## rewarded: re-clearing a dungeon you beat at 100% was the safest income in the
## game, so the rational play was to farm the flat middle instead of risking the
## next depth. A playthrough read 92% / 68% / 100% / 28% / 100% x5 / 8% / 8% / 16%
## — a wall, a five-dungeon plateau, then a wall.
##
## Depth is left alone. What changes is the payout for ground already taken: the
## first clear pays in full, and repeats fall away fast. Going back is still
## allowed (a build's cards live in specific places, and you may need one), it is
## simply no longer the efficient way to get stronger.
const REPEAT_REWARD_FLOOR := 0.25
const REPEAT_REWARD_STEP := 0.45

static func repeat_reward_mult(times_cleared: int) -> float:
	if times_cleared <= 0:
		return 1.0
	return maxf(REPEAT_REWARD_FLOOR, pow(REPEAT_REWARD_STEP, float(times_cleared)))

## Reward rarity weights by tier (index = CardData.Rarity).
const WEIGHTS := {
	Tier.NORMAL: [100, 40, 15, 5, 1],
	Tier.ELITE: [40, 60, 40, 15, 3],
	Tier.BOSS: [10, 30, 50, 30, 10],
}

# --- death penalty (D3, retuned by D20) ---
## Cards permanently lost on death, by dungeon difficulty. Retuned downward when
## run-escrow landed: forfeiting everything earned in the run is now the main
## sting, so stacking the old full card loss on top was double punishment.
static func cards_lost_on_death(dungeon: int) -> int:
	return maxi(1, int(ceil(float(dungeon) / 2.0)))


## Floor on total collection size. DERIVED from MIN_DECK_SIZE, never a loose
## number: if the collection can fall below the minimum legal deck, the player
## cannot build a deck, cannot enter a dungeon, and therefore cannot earn cards —
## an unrecoverable softlock. Any future sink on the collection must respect this.
const MIN_KEEP := MIN_DECK_SIZE
static func gold_loss_fraction(dungeon: int) -> float:
	return clampf(0.25 + 0.1 * (dungeon - 1), 0.25, 0.8)
