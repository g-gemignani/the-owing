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

## The most cards a hand may ever hold — D120.
##
## `HAND_SIZE` is what a turn DEALS; nothing used to say what a hand could reach.
## Keen Lens adds one every turn, Scholar's Lens two on every third, four cards in
## the catalogue retain, and eleven draw on play, so the hand had no ceiling at all
## and the fan had to keep laying out whatever the engine handed it (D116, D117).
##
## Ten because the fan is already at the edge there: at ten cards a resting name
## slot is 29px against `UI.CARD_NAME_MIN_W` of 34, so the card has stopped being
## able to say its own name and shows its cost and effect symbol instead. Past ten
## the substitute runs out of room too. The number is therefore a LAYOUT number, not
## a difficulty one — see D120 for what the simulator said about that.
##
## A draw into a full hand does not happen and the card STAYS in the draw pile: the
## draw is lost, never spent. Discarding it instead would cycle the deck for free,
## which is a buff to any build that wants its discard back and the opposite of what
## a cap is for. `CombatEngine.draw_cards()` is the one place that enforces this.
const MAX_HAND_SIZE := 10

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
# --- the ratio axis was rescaled by D109, and everything measured against it moved
#
# Levelling used to leave 77% of a card's level-ups doing nothing, and the fix
# (CardData._spread) made growth linear. That took a maxed common from 21 damage to
# 107, and the strongest reachable deck from ratio 6.1 to 31.7.
#
# Every constant below is a SLOPE against ratio or a POINT on it, so none of them
# survived that unchanged. Two ways of moving them were tried and only the second
# one measured:
#
# **A single analytic stretch of the axis did not work.** Mapping each constant
# through one factor satisfied every predicate in tests/test_balance.gd — and made
# the game a walkover. Measured against a HEAD baseline at 120 trials: Barricade at
# the Foundry 24% -> 100% run completion, Thorns at the Abyssal Stair 6% -> 97%, AoE
# at the Drowned Market 42% -> 97%. The suite guards the SHAPE of the curve and the
# shape was intact; what moved was the height, which only the simulator sees. A
# constant that says "measured" has to be measured by the thing that measures play.
#
# **What these are instead.** Anchored on matched-progression cells from that same
# baseline — enemy HP fitted to hold fight LENGTH at the Mid and Thorns anchors,
# enemy damage and pierce fitted as far as the maxed-deck guard allows. Fight
# lengths now land within ~0.5 turns of baseline across every profile and the early
# game is unchanged within noise.
#
# **What is still open, stated plainly.** Fused archetype decks remain easier than
# baseline by a mean of 14 points, worst at Barricade (+67 at the Foundry, +49 at
# the Sunken Vault). The mechanism is not in this file: a Lv15 Cover now grants 20
# Block where it used to grant 10, so a block deck's defensive pool doubled, while
# enemy damage growth is bounded above by the D36 guard that a maxed deck must not
# be punished for its power. Raising DMG_POWER_K to 0.09 or beyond fails that guard;
# raising ESCALATION_PER_TURN to 0.10 was tried and hurt the UNFUSED deck more than
# the fused one (Early at the Foundry 32% -> 8%), which is the wrong trade. Closing
# it belongs in `CardData.power_value`'s Block pricing or in the archetype cards,
# not in another pass over these numbers.

## Only part of the player's throughput goes into damage (the rest into block),
## so HP scaling below 1.0 keeps fight LENGTH roughly flat as decks improve.
## Was 0.5. Fitted to hold fight length at the Mid (Lv15, ratio 6.4) and Thorns
## (Lv15, ratio 7.7) anchors rather than mapped.
const HP_POWER_K := 0.68
## Kept low deliberately: difficulty should come from choosing a deeper dungeon,
## not from the player's own progression. Scaling incoming damage steeply with
## deck power punishes offense-heavy decks that have no extra block to answer it.
##
## Was 0.15. This is the constant the whole retune is pinched by: the mid-game wants
## it HIGHER (block pools doubled and this is what reaches through them) and the
## maxed-deck guard wants it LOWER (at depth, pierce multiplies it against a deck
## that already bled for its own power). Measured ceiling before that guard fails:
## 0.07. 0.060 is the most attrition the guard allows.
const DMG_POWER_K := 0.060
## The knee where further ratio starts to compress, and now a BACKSTOP rather than a
## working part: it sits above the strongest reachable deck (31.7), so nothing a
## player can build is softened.
##
## It used to sit below the reachable maximum, and that is what broke the first
## retune. `soften_ratio` is sqrt, so the wider the raw range the more it eats: at
## the old range it turned 7.1 into 6.1, but at the new one it turned 31.7 into 13.8
## — enemies were being scaled for less than half the deck they were facing.
const POWER_RATIO_CAP := 33.0

## Past this ratio a deck is not "a player with a good build" any more — it is the
## thing the deepest dungeons exist to test. Two rules switch on above it (extra
## enemy HP, and pierce that scales with the deck), and NOTHING below it changes,
## which is what keeps every cell D45 tuned exactly where it was. Chosen as the top
## of the build band, RE-MEASURED after D109 stretched the axis: the archetype decks
## now measure 4.6-11.0 (poison 4.6, barricade 4.6, status 5.6, thorns 7.7, AoE
## 11.0) and fully-relic'd late ones 20.5-31.7. Was 3.0 against a 2.4-4.0 band.
const HIGH_POWER_FLOOR := 11.1
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
##
## The one constant here that is NOT the plain axis map (which would give 0.217).
## `soften_ratio` compresses the top of the range twice over — once in
## `power_ratio`, once in `scaling_ratio` — so above the floor the scaling ratio
## grows slower than the player's raw throughput does, and at the mapped value the
## deepest dungeon's fights measured 3.3 turns against 3.5 at the floor: shortening
## with power, which is exactly the D52 regression. 0.38 is where they stop
## shortening, pinned by the test rather than chosen.
const HP_POWER_K_HIGH := 0.52

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
## Was 1.4 on the old axis.
const RATIO_CEILING_BASE := 1.4
## Set so the deepest dungeon's ceiling clears the maximum achievable ratio with
## room to spare; see MAX_ACHIEVABLE_RATIO and the test that pins the relationship.
## A slope in ratio-per-depth, so D109 multiplied it rather than dividing: was 0.90.
## The deepest dungeon (d8) now ceilings at 33.25 against a reachable 31.7.
const RATIO_CEILING_PER_DEPTH := 4.55

## The strongest ratio a fully-built player can reach: maxed card levels plus a
## full relic set. Measured with tools/sim_balance.gd, not guessed. The deepest
## dungeon must scale past this or the endgame stops resisting.
##
## Re-measured at 31.67 after D109 rebuilt level scaling — the third time this
## constant has moved because the thing it measures moved. A constant whose comment
## says "measured" has to be re-measured, or it becomes the fourth restated number
## in this file to quietly go stale. (6.09 after D75 repriced relics; 4.55 before.)
##
## No longer softened on the way here: POWER_RATIO_CAP is above it by design, so this
## is the deck's raw power per energy. 20 maxed commons, six relics, a maxed power.
## tests/test_upgrade.gd fails if a maxed deck climbs past it.
const MAX_ACHIEVABLE_RATIO := 31.7

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
##
## `eff_cost`, because levelling a rule-only card buys its energy cost down and this
## is the denominator of `power_ratio`. Reading the authored cost here would let a
## maxed Set Stone deck play more per turn than the ratchet had priced it for —
## exactly the unpriced-throughput hole relics and powers each opened once.
static func deck_cost(deck: Array) -> float:
	var c := 0.0
	for card in deck:
		c += card.eff_cost()
	return maxf(1.0, c)

# --- powers (once-per-turn abilities) ---
const POWER_DIR := "res://resources/powers/"
const POWERS := ["bulwark", "foresight", "scythe", "blight", "expose", "bramble",
	"kindle", "overwhelm", "siphon", "push_on"]


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
	var displaced: float = float(p.eff_cost()) * deck_per_energy
	# a power the player would simply never fire cannot make enemies tougher
	return maxf(0.0, gained - displaced) / (float(MAX_ENERGY) * BASELINE_CARD_POWER)

# --- relics ---
const RELIC_DIR := "res://resources/relics/"
## Relic power is divided by this to convert it into ratio points. Relics are
## permanent and sit outside the deck, so without folding them into the ratio a
## relic collection would outscale enemies exactly the way fusion once did.
const RELIC_POWER_PER_RATIO := 50.0

## What one card drawn is worth, in `CardData.power_value` units.
##
## NOT a new number. It is the figure `CardData.power_value` already charges for a
## card's `draw`, and the figure `RelicData.triggered_power` already charges for
## `Effect.DRAW`. This is the third place it appears, and the other two are literals
## in files D124 was not scoped to touch — so it is named here, where tuning belongs,
## and the duplication is recorded rather than left to be discovered. Two things
## deriving a number from separate copies agree with each other and with nothing else
## (D99), and this constant has already caused exactly that: see below.
const DRAW_VALUE := 1.5

static func relic_power(relics: Array) -> float:
	var p := 0.0
	for r in relics:
		if r is RelicData:
			p += r.flat_power()
			# `extra_draw` is priced HERE, additively, and not as throughput (D124).
			# `flat_power()` deliberately leaves it out because it used to be charged
			# multiplicatively below; that is the half of the pair this decision moved.
			#
			# The rate is the one the game already uses everywhere else draw is
			# charged: a card drawn is worth DRAW_VALUE, and a relic that draws every
			# turn delivers one per turn of a fight. That makes Keen Lens ("draw 1
			# every turn") price at 1 x 1.5 x 4 = 6.0, against Scholar's Lens ("draw 2
			# every third turn") at 2 x 1.5 x 4/3 = 4.0 through `triggered_power` —
			# the stronger relic priced higher, by the same arithmetic, which is what
			# the two formulas failed to do while one was a multiplier.
			p += float(r.extra_draw) * DRAW_VALUE * TARGET_NORMAL_TURNS
	return p

## Relics that grant ENERGY scale everything the deck does, so they act on the ratio
## multiplicatively. Treating them as flat power undervalued them badly: a +1 energy
## relic is a third more actions every turn of every fight.
##
## Draw used to be here too, at `1.0 + 0.08 * draw`, and D124 took it out — the same
## effect was being charged by two formulas that disagreed by a factor of four.
##
## **Draw is not throughput in this game, and the two constants that decide it say so.**
## `HAND_SIZE` is 5 against `MAX_ENERGY` 3, so an average hand already holds more
## cards than the turn can pay for; the binding constraint is energy, and a sixth card
## does not loosen it. What the extra card buys is SELECTION — a better pick out of a
## bigger hand — which is a flat gain per turn, not a percentage of everything. The
## multiplier said otherwise and the difference was not small: Keen Lens plus
## Scholar's Lens took a Mid deck from ratio 6.60 to 7.22, **+9.4% enemy scaling**,
## of which +0.53 was the multiplier and +0.08 the flat term.
##
## Measured, identical decks, only the two relics differing, 400 trials, 4 dungeons
## on each of two carriers: at +9.4% the lenses cost their owner a mean of **12
## points of run completion**, 8 cells of 8 down, worst at the Drowned Market
## (73 -> 47). Priced power exceeded delivered power, which is the pillar violation in
## the opposite direction to the usual one, and it had been open since D120 measured
## it — deliberately, because the driver of the day played draw cards greedily and
## could not have priced them. See D124 for the policy fix that came first.
static func throughput_multiplier(relics: Array, equipped_power = null) -> float:
	var energy := 0
	for r in relics:
		if r is RelicData:
			energy += r.bonus_energy
	# A power that hands back energy every turn scales everything the deck does, so
	# it belongs here rather than in the additive term. Priced additively it read as
	# +0.91 ratio — nearly triple what the identical effect costs on a relic.
	if equipped_power != null:
		energy += equipped_power.energy_gain
	return float(MAX_ENERGY + energy) / float(MAX_ENERGY)

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
## Two changes made it a trade again. It scales with depth — through the dungeon's
## difficulty, not the player's max HP, because a Traversal must never read run
## resources (D13) — and it RISES with each dodge already taken this run, the same
## shape as `removal_price`. The first dodge is the one you want; the last should be
## unaffordable. The target: **dodging every fight a dungeon offers costs
## `AVOID_TOTAL_FRACTION` of the health bar** and arrives at the boss with no gold
## and no rewards.
##
## **That target was missed by half for two years, because the ladder was a fixed
## climb and the staircase changed height under it (D99).** The old constants were
## `6 + depth` per rung with a +0.5 step, tuned so FOUR rungs came to ~70% of the
## bar — four being `ENCOUNTER_COMBATS + ENCOUNTER_ELITES`, the global default mix.
## Two later changes moved the real number and neither touched this: encounter mixes
## became per-dungeon (D84), and the crawl takes wanderers **out** of the combat
## budget (D88) — and a wanderer cannot be slipped past, it walks to you. Measured,
## the crawl offers **two or three** dodges, never four, so the real bill came to
## **25-46%** of the bar and was exactly 25% in six of the twelve dungeons. Dodging
## the whole dungeon cost a quarter of a health bar. `tests/test_traversal.gd`
## asserted the total was at least half a bar and passed, because it computed the
## rung count from the same global constant rather than from the dungeon.
##
## So the ladder is now sized to the staircase: `avoid_cost` takes how many dodges
## the dungeon actually offers and solves for the base that lands the WHOLE ladder
## on the target. A dungeon that offers two charges more per dodge than one that
## offers four, which is the correct answer and the one a fixed rung cannot give.
## `TraversalIso` counts its own dodgeable fights at generation and hands the number
## over; nothing derives it a second time.
##
## `AVOID_STEP` is 1.0, not the old 0.5: the second slip costs twice the first and
## the third three times it. A steeper climb is what keeps the FIRST rung affordable
## while the total still reaches the target on a two-rung ladder — at 0.5 a two-dodge
## dungeon had to charge 28% of the bar up front to reach 70%, past the point where
## anyone would ever use the first one.
const AVOID_TOTAL_FRACTION := 0.70
const AVOID_STEP := 1.0

## What dodging EVERY fight in this dungeon should cost, as a fraction of a health
## bar derived from depth (not from the player, per D13).
static func avoid_budget(difficulty: int) -> float:
	return AVOID_TOTAL_FRACTION * float(BASE_MAX_HP + (maxi(1, difficulty) - 1) * HP_PER_DUNGEON)

## Price of the next dodge. `dodgeable` is how many this dungeon offers in total —
## ask the traversal, do not re-derive it.
static func avoid_cost(difficulty: int, already_avoided: int, dodgeable: int) -> int:
	var n := maxi(1, dodgeable)
	# sum of (1 + STEP*i) for i in 0..n-1, in units of `base`
	var rungs := float(n) + AVOID_STEP * float(n * (n - 1)) * 0.5
	var base := avoid_budget(difficulty) / rungs
	return maxi(1, int(round(base * (1.0 + AVOID_STEP * float(maxi(0, already_avoided))))))

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
##   roles — weights over ISO_ROOM_ROLES for the chambers this style places (D176). What
##           a style is called should be what most of its rooms ARE, so `cells` is mostly
##           cells and `halls` mostly halls; the minority entries are what stop a floor
##           from being six copies of one room.
const ISO_STYLES := {
	# a honeycomb of small cells cut in ranks, barely linked — you go back the way you came
	"cells": {"rooms": [5, 9], "w": [2, 2], "h": [2, 2], "loops": 0,
		"fill": 0.90, "align": 3,
		"roles": {"cell": 6, "store": 2, "shrine": 1, "sump": 1}},
	# long thin galleries: few rooms, but each one is a walk in itself
	"galleries": {"rooms": [2, 5], "w": [2, 2], "h": [4, 6], "loops": 1,
		"fill": 0.80, "align": 0,
		"roles": {"gallery": 6, "hall": 2, "store": 1, "shrine": 1}},
	# tunnels that double back, with small chambers hung off them
	"warren": {"rooms": [3, 6], "w": [2, 3], "h": [2, 3], "loops": 3,
		"fill": 0.45, "align": 0,
		"roles": {"cell": 3, "store": 3, "sump": 3, "shrine": 1}},
	# few big open halls, so a wanderer is visible across one long before it arrives
	"halls": {"rooms": [2, 4], "w": [3, 5], "h": [3, 4], "loops": 1,
		"fill": 0.85, "align": 0,
		"roles": {"hall": 6, "gallery": 2, "sump": 1, "shrine": 1}},
	# --- the deep readings (D177): where a dungeon's own style ends up ------------
	#
	# Each of these is a NEW KNOB rather than new numbers on the old ones, because that is
	# the lesson `fill` taught: `cells` and `warren` were indistinguishable side by side
	# while they differed only by a tile of room width and a loop count. Two knobs, and
	# both of them change the shape of the walk and not just the shape of a room.
	#
	# rooms with the roof in them: rubble cuts a rectangle into an L or a U, so a chamber
	# has corners you cannot see into from its door
	"collapse": {"rooms": [3, 6], "w": [3, 4], "h": [3, 4], "loops": 3,
		"fill": 0.88, "align": 0, "rubble": 0.22,
		"roles": {"sump": 4, "cell": 3, "gallery": 2, "store": 1}},
	# many small cells hung off ONE arterial corridor: a spine is a different walk from a
	# chain, because every room is a spur and every spur is a decision to leave the road
	"ranks": {"rooms": [5, 8], "w": [2, 2], "h": [2, 3], "loops": 3,
		"fill": 0.86, "align": 2, "spine": true,
		"roles": {"cell": 7, "store": 2, "shrine": 1}},
	# big chambers on the same spine: you come back along the road you left
	"flooded": {"rooms": [3, 5], "w": [3, 4], "h": [3, 4], "loops": 2,
		"fill": 0.88, "align": 0, "spine": true,
		"roles": {"sump": 4, "hall": 3, "gallery": 2, "shrine": 1}},
}
const ISO_STYLE_DEFAULT := "warren"
const ISO_STYLE_OF := {
	"crypt": "cells", "ossuary": "galleries", "warrens": "warren",
	"foundry": "halls", "ember_road": "galleries", "slag_pits": "halls",
	"fungal_deep": "warren", "rot_gardens": "warren", "sunken_vault": "halls",
	"drowned_market": "halls", "abyssal_stair": "galleries", "the_maw": "cells",
}

## Which architecture a dungeon is cut in, BY NAME. Split out from `iso_style` because
## the floor now records the name it was built from and saves it: the props and the
## dressing are picked from it, and a floor that re-derived its own style on load would be
## free to come back dressed as something else.
static func iso_style_name(dungeon_id: String, depth: int = 0, floors: int = 1) -> String:
	var name: String = String(ISO_STYLE_OF.get(dungeon_id, ISO_STYLE_DEFAULT))
	if iso_style_drifts(depth, floors):
		name = String(ISO_STYLE_DEEP.get(name, name))
	return name if ISO_STYLES.has(name) else ISO_STYLE_DEFAULT

static func iso_style(dungeon_id: String, depth: int = 0, floors: int = 1) -> Dictionary:
	return ISO_STYLES[iso_style_name(dungeon_id, depth, floors)]

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

# --- a dungeon's floors need not all be the same place (D177) ------------------
#
# Every floor of a dungeon shared one style and one terrain, so descending changed the
# layout and nothing else: floor 3 of the Ossuary was floor 1 of the Ossuary with
# different rooms in it. Going *somewhere* is what the third and fourth floor of a
# dungeon were missing.
#
# Done as a DRIFT RULE rather than a per-dungeon sequence, and that is the whole design
# decision here. Twelve hand-written sequences would be twelve places for the tables to
# stop indexing real things, and the variety they buy is variety nobody can hold in their
# head; one paired "deeper" reading per style and per terrain gives every dungeon the same
# promise — the bottom of a place is not the top of it — out of two tables the tests can
# check exhaustively.
#
# The two axes shift at DIFFERENT depths, on purpose. The surface changes one floor before
# the architecture does, so the reading is "the ground has changed" and then, a floor
# later, "and so has the building" — two events rather than one, out of the same two
# lookups. A two-floor dungeon gets both at once, which is all a two-floor dungeon has
# room for.
const ISO_STYLE_DEEP := {
	# cut cells give way to cells the roof came into
	"cells": "collapse",
	# a gallery ends where the gallery fell in
	"galleries": "collapse",
	# a warren narrows into ranks of the same thing
	"warren": "ranks",
	# halls end at the one that took the water
	"halls": "flooded",
	# and the deep styles have their own bottoms, so a dungeon deep enough to use one
	# twice does not simply repeat it
	"collapse": "flooded",
	"ranks": "collapse",
	"flooded": "collapse",
}
const ISO_TERRAIN_DEEP := {
	"stone": "earth",   # worked stone gives out into what it was cut through
	"earth": "stone",   # a tunnel breaks into something built
	"moss": "earth",    # the growth stops where the light does
	"sand": "moss",     # silt gives way to what grew in the wet
}

## True on the floors that use the DEEP style — the bottom one.
static func iso_style_drifts(depth: int, floors: int) -> bool:
	return floors > 1 and depth >= floors - 1

## True on the floors that use the DEEP terrain — the bottom one, and the one above it in
## anything with three floors or more, so the surface turns before the architecture does.
static func iso_terrain_drifts(depth: int, floors: int) -> bool:
	if floors <= 1:
		return false
	return depth >= floors - (2 if floors >= 3 else 1)

static func iso_terrain(dungeon_id: String, depth: int = 0, floors: int = 1) -> String:
	var base: String = String(ISO_TERRAIN_OF.get(dungeon_id, ISO_TERRAIN_DEFAULT))
	if iso_terrain_drifts(depth, floors):
		base = String(ISO_TERRAIN_DEEP.get(base, base))
	return base if base in ISO_TERRAINS else ISO_TERRAIN_DEFAULT

# --- what makes one ROOM unlike the next, inside one floor (D176) --------------
#
# Style and terrain are per DUNGEON, so before this the variety was entirely between
# places: sixteen readings across twelve dungeons, and inside any one floor every
# ground tile was the same diamond at one of three tints and every rock the same block.
# The floor read as a board because nothing in it was local. What Diablo's exploration
# feel actually comes from is *incident* — this room has a fallen slab, that one is a
# store with crates stacked in it, that corner has a brazier in it — and incident is
# per-tile decoration, which a discrete grid supports perfectly well (D87 is not
# reopened: the simulation is unchanged, this is all presentation).
#
# Three axes, and they multiply against the two that already existed:
#
#   role  — what a chamber was FOR. Picked from the STYLE's own weights, so a crypt of
#           burial cells produces mostly cells and a foundry mostly halls. It drives
#           dressing and NOTHING else, deliberately: role has to prove it is free of
#           balance consequence before anything is ever placed by it.
#   prop  — a decoration id per cell, purely cosmetic, per TERRAIN so it multiplies the
#           way terrain already does rather than folding into style.
#   light — a few sources per floor, replacing the flat rule where explored-state was
#           doing the job of illumination.

## What a chamber was for. Six because that is how many distinct dressings the drawing
## can actually tell apart at this tile size; the names are the register of
## `resources/events/` rather than another game's nouns (D98/D127).
const ISO_ROOM_ROLES := ["cell", "hall", "gallery", "store", "sump", "shrine"]
const ISO_ROOM_ROLE_DEFAULT := "cell"

## How a role dresses itself: what fraction of its tiles carry ground clutter, what
## fraction of the rock around it carries wall dressing, and how much it wants a light.
##
## `light` is a WEIGHT, not a probability — the floor places a fixed few sources and
## these decide which chambers get them, so a shrine outbids a hall and a cell never
## wins. A sump is dark on purpose: the one role whose reading is "the light did not
## reach here" cannot also be the room with a brazier in it.
## Raised about half again on a real capture (D176): at the first rates a 15-tile view of
## the Maw held one prop, and one mark in a frame is not local incident, it is a blemish.
## What keeps the numbers honest is the SPREAD between them rather than their size — a store
## at three times a gallery is the reading, and both being large would make every room busy,
## which is the flat floor again with clutter on it.
const ISO_ROOM_DRESSING := {
	"cell":    {"ground": 0.20, "wall": 0.24, "light": 0.0},
	"hall":    {"ground": 0.13, "wall": 0.10, "light": 1.0},
	"gallery": {"ground": 0.12, "wall": 0.30, "light": 0.4},
	"store":   {"ground": 0.44, "wall": 0.12, "light": 0.3},
	"sump":    {"ground": 0.38, "wall": 0.08, "light": 0.0},
	"shrine":  {"ground": 0.22, "wall": 0.18, "light": 2.4},
}
## Corridors have no role — they are dug, not placed — so they dress at one low rate.
## Low because a passage is where the contrast comes from: a corridor with as much in it
## as a store is a floor with no store in it.
const ISO_PROP_CORRIDOR := 0.10

## What lies about on each surface. One list per terrain, four entries each, so the
## multiply against style stays honest — and `on` decides whether a prop is ground
## clutter or wall dressing, because a prop must NEVER change walkability. If it looks
## blocking it is on rock, not on floor.
##
## `shape` is the drawing; `name` is what it is. The names are not shown to the player
## and are not meant to be: a prop that carried information the player could act on
## would be the D85 lie one noun over — the floor teaches "the thing on the tile is what
## you get", so nothing decorative may resemble interactive art. That is why there is no
## crate that looks like a chest and no figure that looks like a fight in this table.
const ISO_PROPS := {
	"stone": [
		{"name": "cracked flags", "shape": "cracks", "on": "ground"},
		{"name": "a fallen slab", "shape": "slab", "on": "ground"},
		{"name": "stacked bone", "shape": "pile", "on": "ground"},
		{"name": "an iron ring", "shape": "ring", "on": "wall"},
	],
	"earth": [
		{"name": "spoil", "shape": "pile", "on": "ground"},
		{"name": "scree", "shape": "scatter", "on": "ground"},
		{"name": "a dropped beam", "shape": "slab", "on": "ground"},
		{"name": "roots", "shape": "growth", "on": "wall"},
	],
	"moss": [
		{"name": "a growth patch", "shape": "growth", "on": "ground"},
		{"name": "fungal clusters", "shape": "pile", "on": "ground"},
		{"name": "wet flags", "shape": "cracks", "on": "ground"},
		{"name": "hanging matter", "shape": "growth", "on": "wall"},
	],
	"sand": [
		{"name": "a silt drift", "shape": "drift", "on": "ground"},
		{"name": "dry weed", "shape": "growth", "on": "ground"},
		{"name": "tidewrack", "shape": "scatter", "on": "ground"},
		{"name": "a crusted ring", "shape": "ring", "on": "wall"},
	],
}
## Every `shape` any prop names. `iso_run.gd` has one drawing per entry and
## `tests/test_traversal.gd` asserts the table names nothing the view cannot draw —
## a prop with an unknown shape is an invisible prop, which is exactly the kind of
## content that goes missing without failing (D86's shape).
const ISO_PROP_SHAPES := ["cracks", "slab", "pile", "ring", "growth", "drift", "scatter"]

static func iso_props(terrain: String) -> Array:
	return ISO_PROPS.get(terrain, ISO_PROPS[ISO_TERRAIN_DEFAULT])

## Roll a chamber's role off a style's own weights. A style with no `roles` entry gets
## the default rather than a crash, and the default is `cell` because it is the role
## whose dressing is quietest — an unlisted style should look plain, not look wrong.
static func iso_roll_room_role(style: Dictionary) -> String:
	var weights: Dictionary = style.get("roles", {})
	var total := 0
	for r in weights:
		if r in ISO_ROOM_ROLES:
			total += maxi(0, int(weights[r]))
	if total <= 0:
		return ISO_ROOM_ROLE_DEFAULT
	var roll := randi() % total
	# Iterated over ISO_ROOM_ROLES rather than over the weights dictionary, so the
	# order is the constant's and not a dictionary's insertion order — the same reason
	# D22 wants option order to be a function of state alone.
	for r in ISO_ROOM_ROLES:
		var wt: int = maxi(0, int(weights.get(r, 0)))
		if wt <= 0:
			continue
		if roll < wt:
			return r
		roll -= wt
	return ISO_ROOM_ROLE_DEFAULT

## Lights per floor, and how far one reaches.
##
## This is the single biggest change to how the screen reads, and it is a fix rather than
## an addition: the floor was lit by `TINT_WALKED` / `TINT_OPEN` / `TINT_FRONTIER`, which
## is *have I been here* doing the job of *is there light here*. One rule for both is why
## the whole floor read at one value. State stays — it is the map of your own route, and a
## model about coverage needs it — but it is a small modulation now, and the light field
## carries the range.
##
## One to three at radius two, and these numbers were MEASURED rather than picked, because
## the first guess (two to four at radius three) lit 91% of the ground across a 33-floor
## sweep. That is not a light field, it is a brighter flat rule — the exact thing being
## fixed, in warmer paint. `tests/test_traversal.gd` asserts the coverage band from both
## sides now: a floor with no lit tile has lost the feature, and a floor where everything is
## lit never had it.
##
## The floor of one rather than two is deliberate as well. A dungeon floor that happens to
## have nothing burning on it is what makes the lit ones read as lit, and the same argument
## the plan makes about a floor with no secret on it applies to a floor with no fire.
const ISO_LIGHTS_MIN := 1
const ISO_LIGHTS_MAX := 3
const ISO_LIGHT_RADIUS := 2
## Walkable tiles a floor needs before it can hold another source.
##
## A COUNT alone is wrong and the coverage assertion caught it, on the one floor small
## enough to show it: floor sizes run 26 to 65 tiles, and three sources at radius two lit
## 26 of the Abyssal Stair's 34 — 76%, over the band, on a floor that is mostly corridor so
## every source funnels down it. Density is the thing being tuned, not a number of braziers,
## so the count is capped by area and the band is left where it is.
const ISO_TILES_PER_LIGHT := 20

## How many sources a floor of `tiles` walkable cells gets. Always at least one: a floor lit
## by nothing sits at one flat value, which is what the light field exists to end.
static func iso_lights_for(tiles: int) -> int:
	return clampi(int(tiles / ISO_TILES_PER_LIGHT), 1, ISO_LIGHTS_MAX)

## One oversized feature per floor, and its job is ORIENTATION (D177). "I came in past the
## big shaft" is a sentence a place produces and a board does not — and a floor whose
## camera shows a third of it at a time needs something to steer by that is not the map.
##
## It stands in ROCK, never on floor, so it costs nothing to walk and cannot be confused
## with anything interactive: the same rule the props follow, for the same reason. Which
## also means the drawing is a rock block with something done to it, which is why there are
## four and not forty — each one has to read at a glance from across a dark room.
const ISO_LANDMARKS := ["shaft", "dome", "stair", "stack"]
## What each one is, for the docs and for anyone reading a save. Not shown to the player:
## a landmark that named itself in the log would be the game telling you what you are
## looking at, which is the opposite of learning a place.
const ISO_LANDMARK_NAME := {
	"shaft": "a shaft with daylight a long way up it",
	"dome": "a dome that came down",
	"stair": "a stair going nowhere",
	"stack": "bone stacked to the roof",
}

# --- secret pockets: a hidden place with something in it (D182) ------------------
#
# The dungeon had exactly one thing to do: walk to the boss. This is the first optional
# thing on the floor, and every constant here exists to keep it optional in the one sense
# that matters — **it must not change what a dungeon costs.**
#
# The scope is decided and narrow, and the narrowness is the whole reason it can ship
# without touching the attrition model: **a pocket is a sealed dead end with a reward in
# it, never a route.** It never connects two parts of the floor, never offers a second way
# out, and never shortens the way to anything. A shortcut would let a player reach the
# stairs past content, and D88's lesson is that a skip is a difficulty change no budget
# assertion can see. A pocket with one door has no route through it, so there is nothing
# for it to skip.
#
# What it does cost is TURNS, and turns are the floor's real currency: the wanderers step
# whenever you do, and a floor rouses at `ISO_LINGER`. So a detour is priced even though
# no assertion in the suite is watching it — which is exactly why the second walker of
# D179 exists and why its budget is written in rouses.
#
# Two things it must NOT come out of. Pocket tiles are carved from the rock LEFT OVER after
# the floor is built, not from `ISO_TILES_PER_DUNGEON` — coming out of that figure would
# silently shrink every room in the game. And a pocket's contents are outside `quota`, so
# opening one cannot flatter `progress()` either.
const POCKET_TILES_MIN := 1
const POCKET_TILES_MAX := 4
## How many pockets a floor gets: 0, 1 or 2, weighted. **Not one guaranteed per floor** —
## a floor with none is what makes a mark mean something when it appears, and a mark that
## appears every floor is a checklist entry.
const POCKET_COUNT_WEIGHTS := [2, 6, 2]

## What is behind the wall. Four kinds, and the fourth is deliberately worth nothing.
##
## `nothing` is not a tax and not an oversight: if every mark pays, pushing stops being a
## discovery and becomes a vending machine. A pocket holding a room and no more is what
## makes the paying ones land. It is the smallest weight for the same reason — pushing has
## to stay correct on average, or the feature is content players learn to refuse.
const POCKET_CHEST := "chest"
const POCKET_KEY := "key"
const POCKET_SITE := "site"
const POCKET_NOTHING := "nothing"
const POCKET_PRIZES := [POCKET_CHEST, POCKET_KEY, POCKET_SITE, POCKET_NOTHING]
## Trimmed from [5, 3, 3, 2] on a `tools/pack_income.gd` reading, which is the check the plan
## asks for and the one that has to be believed rather than celebrated. At the first weights a
## run that found every pocket could add 3.1 packs to the 2 it already pays, and the pack
## channel went **21.0 to 28.5 card copies a run — 36%**. Free reward at that scale changes
## how fast the collection grows, which changes everything downstream of it; a big jump is a
## reason to lower the tier or the count, never a success. At 3 the ceiling is +2.3 packs and
## 26.0, a 24% rise — and it IS a ceiling: it needs a run that finds every pocket, which costs
## about sixteen turns a floor (D179's second walker measures it), and then beats every vault,
## which a Gilded does not grant for free. Trimming further would leave the chest prize
## meaningless, which is the other way to break the feature.
const POCKET_PRIZE_WEIGHTS := [3, 3, 3, 2]

## A pocket's chest is always the top tier, and that is a DESIGN choice with a mechanical
## reason behind it.
##
## Design: the tier ladder already exists and a Gilded is currently just a lucky roll. A
## pocket is the natural place for one to be *earned by looking* rather than rolled.
##
## Mechanical: Gilded is the VAULT lock, which asks the run to prove something rather than
## asking for an item (D84). A Sealed chest in a pocket would want a key, and there is no
## key promised for it — `keyplan` is one key per key-locked chest on the OPEN floor (D172),
## and a pocket cannot join that count without making an unfound pocket into a key the
## player was owed. So the pocket's chest asks for nothing it cannot be given.
const POCKET_CHEST_TIER := PACK_GILDED

# --- the guard on the prize (D183) ----------------------------------------------
#
# A pocket should usually be DEFENDED. Something is in there with the reward, and it is an
# elite: that is what makes finding one an event rather than a pickup, and what stops the
# reward from being free.
#
# It is also the one thing in this whole batch that makes a run **harder than its difficulty
# rating**, so it is the one with the most conditions attached. An optional fight on top of
# the budget is legitimate — it is the mirror of the slip-past, which prices a voluntary
# *reduction* in attrition — but only under all three of:
#
#   * **seen before committed.** The guard is revealed with the pocket, drawn as the
#     silhouette of the creature you will actually fight, and the fight does not start until
#     you walk into it. An ambush for pushing a wall is a trap, and a trap turns exploring
#     from a decision into a punishment.
#   * **declinable at zero cost.** You may turn round and leave. There is deliberately NO
#     slip option inside a pocket: the slip exists to get *past* something, and there is
#     nothing beyond a guard but the prize and the way back, so walking out is the decline
#     and it is already free.
#   * **capped per run.** Uncapped, a lucky floor sequence could add five elites to a
#     dungeon whose rating promised none of them, while every budget assertion stayed green.
#
# And one thing it must never touch: `dodgeable`. `Balance.avoid_cost` solves the whole slip
# ladder from the COUNT of dodgeable fights (D99's fix), so a voluntary elite landing in that
# count would silently re-price every slip in the dungeon. Guards are not in `budget`, which
# is where the count comes from, and `tests/test_traversal.gd` checks the tiles against the
# count rather than trusting that.
const POCKET_GUARD_PCT := 66
## Guarded pockets a whole dungeon may hold. Three, against the two to four floors a dungeon
## has, so a run can meet one or two and never a gauntlet.
const POCKET_GUARDS_PER_RUN := 3

## Can this prize be worth standing over? A pocket holding nothing but a room is never
## guarded: a guard on nothing is pure punishment, and the point of the empty pocket is that
## it costs you only the turns you spent looking.
static func pocket_guardable(prize: String) -> bool:
	return prize != POCKET_NOTHING

# --- debts: pick what you owe (D191) ---------------------------------------------
#
# A hub-level contract: three offered, you take one, it names a PLACE and a CONDITION. This is
# the piece that makes the campaign feel chosen rather than walked, because the player decides
# which dungeon is next by deciding which debt to take — and of everything in the plan it is
# the closest fit to the game's own title and voice.
#
# Two constraints, and the first is the one that keeps it out of the scaling model. **A debt
# may never be a card-pool or difficulty MODIFIER on the run, only a condition OBSERVED during
# it.** A modifier would reopen every scaling question the ratchet exists to close; an
# observation cannot, because the run is exactly the run it would have been.
#
# And **every condition must be checkable from state the run already tracks.** If a condition
# needs new bookkeeping it is the wrong condition — bookkeeping kept for one feature is
# bookkeeping that goes stale the first time another one moves. The three here read: did you
# beat it, how deep did you get, and were you ever caught in the open. All three were already
# being written down for something else.
#
# It pays the GATE CURRENCY (D178) and gold. Paying the gate is what makes it a route through
# the world rather than a side quest: a debt settled is a door opened somewhere.
const DEBT_SETTLE := "settle"
const DEBT_DEEP := "deep"
const DEBT_UNSEEN := "unseen"
const DEBTS := [DEBT_SETTLE, DEBT_DEEP, DEBT_UNSEEN]
const DEBT_TEXT := {
	DEBT_SETTLE: "Go to %s and finish it.",
	DEBT_DEEP: "Go to %s and get to the bottom of it, whatever it costs you.",
	DEBT_UNSEEN: "Go to %s and finish it without once being caught in the open.",
}
## How many are on the table at once. Three, because two is a coin and four is a list.
const DEBT_OFFERS := 3
const DEBT_GOLD := 40
const DEBT_GOLD_PER_DIFF := 15

static func debt_text(kind: String, dungeon_id: String) -> String:
	var d := dungeon(dungeon_id)
	return String(DEBT_TEXT.get(kind, "%s")) % (d.name if d != null else dungeon_id)

static func debt_gold(difficulty: int) -> int:
	return DEBT_GOLD + DEBT_GOLD_PER_DIFF * maxi(0, difficulty - 1)

## Was this debt settled by a run that ended like this?
##
## Pure, and given only facts the run already had: whether the boss fell, how deep it got, and
## whether anything ever caught it in the open. No state of its own, so there is nothing here
## to keep in step with anything.
static func debt_met(kind: String, dungeon_id: String, ran: String, cleared: bool,
		deepest: int, caught: bool) -> bool:
	if ran != dungeon_id:
		return false
	match kind:
		DEBT_SETTLE:
			return cleared
		DEBT_DEEP:
			var d := dungeon(dungeon_id)
			return deepest >= iso_floors_for(d.difficulty if d != null else 1)
		DEBT_UNSEEN:
			return cleared and not caught
	return false

# --- back doors: the twelve dungeons as a graph, not a list (D190) ---------------
#
# Clearing a dungeon opens a **deep entry** into a connected one: you go in further down, and
# the place is shorter and denser for it. Structurally this is the strongest answer to "the
# world is a ladder", because it turns twelve doors into a graph with edges instead of a list
# with an index.
#
# **It is also a direct assault on R1**, and the plan gives two honest ways to do it. This is
# the one it prefers: the deep entry keeps the WHOLE budget, compressed into fewer floors —
# more per floor, the same total. The other way is a shorter, harder run with a difficulty
# rating of its own, which is a new content type needing its own sim sweep and its own place
# on the curve. Compression needs neither, because nothing about the dungeon's cost changes:
# `quota` is identical, the tile budget is per DUNGEON and simply divides fewer ways, and
# "difficulty 5" keeps meaning exactly one thing.
#
# Connected means IN THE SAME REGION, and it is derived rather than authored. A hand-written
# adjacency table would be a second statement of which places sit near which — the zones
# already say that, and two tables saying one thing is D34.
const DEEP_ENTRY_FLOORS := 1

## Can this dungeon be entered by the back door — has anything else in its region been beaten?
##
## Deliberately not "has THIS one been beaten". A back door is a way in that somebody else's
## clear opened; requiring the dungeon's own clear would make it a replay option, which is
## what aspects are for (D187).
static func deep_entry_open(dungeon_id: String, cleared: Array) -> bool:
	var z := zone_of(dungeon_id)
	if z == null:
		return false
	for other in z.dungeons:
		if String(other) != dungeon_id and String(other) in cleared:
			return true
	return false

# --- floor states: a stone that takes something (D188) ---------------------------
#
# A shrine standing on the floor that changes the whole of it until you descend. The plan
# calls this the highest-variance-per-line-of-code feature in the whole batch and also the one
# most likely to blow up the simulator, so it is built LAST and built out of machinery that is
# already priced.
#
# Every state here is an ASPECT (D187) applied mid-floor by choice instead of at the door by
# clear count. That is not a shortcut, it is the argument: those three readings are already
# known to be budget-neutral, already have a test that generates every dungeon in every one of
# them, and already bend numbers the floor was reading anyway. A fourth mechanism for "the
# floor is different now" would be a second definition of the same idea, which is D34.
#
# What makes it a DECISION rather than a gift is that it is paid for in the one currency the
# floor has that the budget does not count — HP now, against gold when you leave. And it is
# declinable: walking past a stone costs nothing at all, which is the same rule every optional
# thing in this batch follows.
const SHRINE_PCT := 30
## What it asks, as a percentage of the health bar. The D88 shape rather than a flat number.
const SHRINE_HP_PCT := 8.0
const SHRINE_HP_MIN := 3
## And what it pays when you finally take the stairs.
const SHRINE_GOLD := 26
const SHRINE_GOLD_PER_DIFF := 9

static func shrine_hp_cost(max_hp: int) -> int:
	return maxi(SHRINE_HP_MIN, int(round(float(maxi(1, max_hp)) * SHRINE_HP_PCT / 100.0)))

static func shrine_gold(difficulty: int) -> int:
	return SHRINE_GOLD + SHRINE_GOLD_PER_DIFF * maxi(0, difficulty - 1)

## What a stone offers, in the register of the events. It names the STATE, because the whole
## point is that the player knows what they are buying before they pay for it.
const SHRINE_LINE := {
	ASPECT_WAKING: "Put your hand on it and the floor will stir. It pays for the trouble.",
	ASPECT_DARK: "Put your hand on it and the light goes out of this floor. It pays for the trouble.",
	ASPECT_CROWDED: "Put your hand on it and more of this floor gets up. It pays for the trouble.",
}

static func shrine_line(state: String) -> String:
	return String(SHRINE_LINE.get(state, ""))

# --- aspects: a place you have cleared should not be the same place (D187) -------
#
# Twelve dungeons, and the twelfth clear of one is the first clear with different rooms in
# it. An aspect is a named, visible variation a dungeon reopens with once it has been beaten:
# the cheapest way to make the back half of a collection worth playing without writing a
# thirteenth dungeon.
#
# **Rotated by clear count, not rolled.** The plan is explicit and the reason is that a
# variation you cannot plan around is a variation you can only be surprised by — and this
# game shows you the difficulty and names the boss before you commit (D41). You are told what
# the Ossuary is like this time, on the row you press.
#
# Every aspect here is BUDGET-NEUTRAL by construction, which is what lets them ship without
# re-opening the attrition model:
#
#   waking   — the floor rouses sooner. Pressure out of `ISO_LINGER`, which wakes what is
#              already counted rather than adding anything (the same argument that made
#              linger the answer to greed in the first place, D77).
#   dark     — sight drops to one. It changes what you KNOW, not what is there.
#   crowded  — one more wanderer and one fewer thing standing still. The plan's own
#              suggestion, and it is neutral by arithmetic: wanderers come OUT of the combat
#              budget (D14), so this moves a fight rather than adding one.
#
# And it is PRICED. An aspect that adds difficulty adds reward, or it is a tax on replaying —
# which is the opposite of the point. The pay is gold, on top of the diminishing repeat payout
# (D69), because gold is the channel optional difficulty is allowed to pay in.
const ASPECT_NONE := ""
const ASPECT_WAKING := "waking"
const ASPECT_DARK := "dark"
const ASPECT_CROWDED := "crowded"
const ASPECTS := [ASPECT_WAKING, ASPECT_DARK, ASPECT_CROWDED]
const ASPECT_NAME := {
	ASPECT_WAKING: "Waking",
	ASPECT_DARK: "Lightless",
	ASPECT_CROWDED: "Walked",
}
const ASPECT_LINE := {
	ASPECT_WAKING: "it wakes sooner than it should",
	ASPECT_DARK: "the light is out of it; you will see one step",
	ASPECT_CROWDED: "more of it is walking, and less of it is waiting",
}
## What each one does to the numbers the floor already has.
const ASPECT_LINGER_PCT := 55     ## waking: ISO_LINGER falls to this
const ASPECT_SIGHT := 1           ## dark: ISO_SIGHT becomes this
const ASPECT_EXTRA_WANDERERS := 1 ## crowded: this many more, taken from the standing fights
## Extra gold, as a percentage, for clearing a dungeon wearing one.
const ASPECT_GOLD_PCT := 25

## Which aspect a dungeon wears on its next visit, from how many times it has been beaten.
##
## Nothing until it has been cleared once — a first visit is the dungeon as written, and a
## variation before the player has seen the original is a variation of nothing.
static func aspect_for(times_cleared: int) -> String:
	if times_cleared <= 0:
		return ASPECT_NONE
	return String(ASPECTS[(times_cleared - 1) % ASPECTS.size()])

static func aspect_name(a: String) -> String:
	return String(ASPECT_NAME.get(a, ""))

static func aspect_line(a: String) -> String:
	return String(ASPECT_LINE.get(a, ""))

# --- errands: a reason to cross a floor (D184) ----------------------------------
#
# A floor-scoped ordinance, judged when you take the stairs. The cheapest way to make one
# floor feel unlike the last, because it changes *how you walk* without changing what is on
# the floor — and it fits the game's own subject: the title is a debt and an errand is a
# small one.
#
# **Every condition here asks for MORE, never less, and that is a hard rule rather than a
# theme.** The obvious errands all pull the other way — "leave the chests alone", "reach the
# stairs in twenty turns", "take no damage" — and every one of them pays a player for
# declining budgeted content. That is a SKIP, and D88's whole lesson is that a skip is a
# difficulty change no budget assertion can see: the encounter count stays perfect while the
# dungeon quietly costs less than its rating says. An errand that pays for self-denial would
# have been a difficulty dial wearing a quest marker.
#
# So the three shipped conditions are things a careful player was going to do anyway, paid
# for doing them well:
#
#   thorough — open every chest on the floor. Budgeted content, taken rather than left.
#   unseen   — descend without being caught in the open. Care, not avoidance: the ambush
#              price already exists and this pays for not paying it.
#   pushed   — open a pocket on this floor. Optional content, already priced in turns.
#
# Reward is GOLD, which is the pack/gold channel the plan reserves for optional content: a
# run-deck card would re-open the dilution question D80/D81 closed, and a relic would be free
# strength outside the deck. Failing one costs nothing at all — an errand is never a
# run-ender, so there is no version of this that can end a run badly.
const ERRAND_THOROUGH := "thorough"
const ERRAND_UNSEEN := "unseen"
const ERRAND_PUSHED := "pushed"
const ERRANDS := [ERRAND_THOROUGH, ERRAND_UNSEEN, ERRAND_PUSHED]
## What each one says, in the register of `resources/events/`: plain words, concrete nouns,
## and never the word "quest".
const ERRAND_TEXT := {
	ERRAND_THOROUGH: "Leave no lid shut on this floor.",
	ERRAND_UNSEEN: "Go down off this floor without being caught in the open.",
	ERRAND_PUSHED: "This floor is holding something back. Find it.",
}
## Which floors carry one. Not every floor: an ordinance on all of them is a checklist, and
## the point is that a floor sometimes asks something of you and sometimes does not.
const ERRAND_PCT := 55
## Gold for settling one, scaled by depth the way every other payout is.
const ERRAND_GOLD := 18
const ERRAND_GOLD_PER_DIFF := 7

static func errand_gold(difficulty: int) -> int:
	return ERRAND_GOLD + ERRAND_GOLD_PER_DIFF * maxi(0, difficulty - 1)

static func errand_text(id: String) -> String:
	return String(ERRAND_TEXT.get(id, ""))

## How often a pocket is shut with a LOCK instead of hidden behind a mark (D185).
##
## Two ways in, and they ask for different things on purpose. A mark is *noticing*: it is only
## legible from the tile beside it, and pushing costs a turn. A door is *bringing something*:
## it can be seen across a room and it wants the key the floor already scatters (D167).
##
## Reusing that key rather than inventing a second currency is the whole of B1's instruction,
## and D34 is why: two things deriving "how many locks does this floor have" from different
## places is how the first dungeon became unplayable. The floor counts its locks — chests and
## doors together — and puts down exactly that many keys. So a key is now a real decision as
## well as a detour: it opens the sealed chest you can see, or the door you can see, and on a
## floor holding both it does not open both.
const POCKET_LOCK_PCT := 30
const POCKET_LOCK_NONE := ""
const POCKET_LOCK_KEY := "key"

# --- sites: optional business standing in the open (D185) ------------------------
#
# A pocket is content you have to *find*. A site is content you can see and may simply walk
# past: a thing standing in a room, off the route, that the floor never asks you to resolve.
#
# It is an EVENT, and deliberately not a new resource. `EventData` already has choices,
# results, hp/gold/card/relic deltas and `starts_fight`; what was missing was a placement
# channel and a rule about the budget, and those are both here rather than in a parallel
# class. The rule: a site is outside `quota`, invisible to the field the greedy walker steers
# by, and placed on ground the required path does not cross — so it costs turns and nothing
# else, which is the only currency optional content is allowed to spend (D181).
const SITE_PCT := 45
## How far off the required path a site has to stand, in steps. One is not "off the path", it
## is "on the path"; three would not fit on a 12x12 plate beside everything else.
const SITE_OFF_PATH := 2

# --- tolls: a question whose answer is the floor (D186) --------------------------
#
# The third way a pocket can be shut, and the trap it has to avoid is obvious and fatal: **a
# riddle with a fixed answer is solved by the player once, or by a wiki, and is a keypress
# ever after.** Twenty riddles would be twenty keypresses. A roguelike is replayed hundreds
# of times, so a puzzle that can be memorised is furniture.
#
# So the answer is DERIVED FROM THE FLOOR, live, every time it is asked — never written down
# and never stored on the pocket. Every kind here is a tiny function over state the model
# already keeps, and every one is a question about *attention* rather than about knowledge:
# how many ways out of the room you are standing in, how much of the ground around you you
# have already trodden, how many things are walking this floor. Knowing the mechanic tells
# you nothing about the answer, which is the property a fixed riddle cannot have.
#
# It shuts a POCKET rather than barring the route, and that is what keeps it free. Something
# barring the way would be an encounter the budget never paid for — mandatory content that
# arrived through the back door. A toll on a pocket mouth bars only the optional thing behind
# it, so declining to answer costs exactly nothing.
## Raised from 22 on a coverage reading: at 22 a sweep of all twelve dungeons produced three
## or four tolls in total, and the assertion that every question kind actually gets asked
## failed one run in three. A kind that is rolled but never placed is a kind that ships
## untested, which is D86's shape — so the rate is the one that makes the sweep see them all.
const TOLL_PCT := 35
const TOLL_EXITS := "exits"
const TOLL_PROWLING := "prowling"
const TOLL_TRODDEN := "trodden"
const TOLLS := [TOLL_EXITS, TOLL_PROWLING, TOLL_TRODDEN]
## What each one asks. One phrasing per kind, spoken in a voice per terrain, so three
## functions produce twelve readings — the shape the plan asks for, where the CONTENT is the
## question kind and the flavour is what makes two of them not sound alike.
const TOLL_ASK := {
	TOLL_EXITS: "how many ways lead out of this room",
	TOLL_PROWLING: "how many things walk this floor",
	TOLL_TRODDEN: "how many of the four squares about you have felt your foot",
}
const TOLL_VOICE := {
	"stone": "A voice out of the wall, dry as a ledger: %s?",
	"earth": "Something under the earth asks, and does not repeat itself: %s?",
	"moss": "The growth shifts, and the question comes through it: %s?",
	"sand": "A whisper of silt, and a question with it: %s?",
}
## What a wrong answer costs, as a fraction of the health bar — the same shape
## `ISO_AMBUSH_PCT` uses and for the same reason (D88): a flat number is a third of the
## opening bar and a rounding error by the endgame.
##
## And the toll shuts for the rest of the floor when it is missed, which is the real price.
## Without that, answering is free: you would try each option in turn and the question would
## be a delay rather than a wager.
const TOLL_WRONG_PCT := 5.0
const TOLL_WRONG_MIN := 2

static func toll_wrong_cost(max_hp: int) -> int:
	return maxi(TOLL_WRONG_MIN, int(round(float(maxi(1, max_hp)) * TOLL_WRONG_PCT / 100.0)))

static func toll_text(kind: String, terrain: String) -> String:
	var voice := String(TOLL_VOICE.get(terrain, TOLL_VOICE[ISO_TERRAIN_DEFAULT]))
	return voice % String(TOLL_ASK.get(kind, "what"))

static func roll_pocket_count() -> int:
	return weighted_pick(POCKET_COUNT_WEIGHTS)

static func roll_pocket_prize() -> String:
	return String(POCKET_PRIZES[weighted_pick(POCKET_PRIZE_WEIGHTS)])

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

## How many distinct wanderer designs the floor draws. It lived in `iso_run.gd`, which
## is the screen that USES it, and that was the right home while the screen was the
## only thing that cared. It moved here when `tools/art_manifest.gd` had to list one
## painted file per design: the manifest cannot preload a view script, because a view
## reaches for the autoloads and `--script` runs have none, so the choice was a second
## copy of the number or one that both can read. A second copy is the D34 bug, and its
## shape here would be a painted `wander_4_s.png` that nothing ever loads.
##
## It sits beside `ISO_FAMILIES` because it is the same kind of fact: how many of a
## thing the isometric floor knows about. `iso_run.gd` indexes with `design % this`.
const ISO_WANDERERS := 4
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

## How much MORE of a floor's turns the optional route may spend than the required one
## (D179), expressed in rouses rather than in turns — because turns are what the floor
## charges and `ISO_LINGER` is the price list.
##
## The plan asked for the completionist ceiling to be *derived, not picked*, and this is the
## derivation: a floor wakes up every `ISO_LINGER` turns you spend on it, and an optional
## route that costs more than one extra waking has stopped being a choice and become a
## difficulty setting. It is RELATIVE to the required path deliberately. An absolute
## per-floor number would have been wrong on the day it was written — the greedy route
## already spends 22 to 45 turns on a floor depending on how many floors the dungeon has —
## and it would go stale the first time floor sizes moved.
const ISO_COMPLETIONIST_ROUSES := 1

## Turns per floor the optional route may add on top of the required one.
static func iso_optional_turn_budget() -> int:
	return ISO_LINGER * ISO_COMPLETIONIST_ROUSES

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
##
## They are also found in exactly ONE place: lying on the dungeon floor, where you have to
## walk to them (D167). They used to drip out of chests (45%), fights (22%) and elites
## (60%), and three passive sources add up to a currency that accumulates while you play
## rather than one you go and get — the first locked chest of a run was opened with a key
## the previous chest handed over, which is a lock that only ever asks whether you have
## been here long enough.
##
## How many a dungeon scatters is not a number in this file. There was one — an estimate off
## the sealed weight below — and D172 deleted it: the crawl rolls every chest's tier when it
## lays the floor out, so it KNOWS how many locks it made, and one key per lock is an answer
## no estimate can improve on. See `TraversalIso._plan_chests`.

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

# --- more than one way to earn a gate (D178) -----------------------------------
#
# The world was a ladder, and it was a ladder because of ONE number. Both
# `DungeonData.unlock_after_clears` and `ZoneData.unlock_after_clears` compare against
# `MetaState.clear_count()`, so every gate in the game asked the same question and every
# clear was interchangeable: nothing you did was remembered except how many times you did it.
#
# Two changes, and the small one turned out to be nearly done already. **Gating at the zone
# and opening every door inside it** (the plan's cheapest-largest-effect move) is worth
# exactly one dungeon here: the Deeps already opened all three of theirs at 6 clears and the
# Barrows all three at 0, and only the Slag Pits sat one clear behind its own region. It is
# still made true — a region opening as a region is a rule worth being able to state — but it
# is not what made the world linear.
#
# What made it linear is the currency. So: **a gate takes evidence you have been down there,
# and a clear is not the only kind.** Floors descended in dungeons you did NOT beat count,
# at a discount, which gives a player who keeps dying a way forward that is not farming the
# Crypt eleven times — and, because depth is earned in a *place*, it makes the order you
# take the world in a thing you can choose.
#
# Three constraints, all of them from the plan's C7 and D36:
#
# * **Discounted, so a clear is still the better answer.** Three floors of somewhere you
#   died is one clear's worth of evidence, and a dungeon is two to four floors, so a full
#   dive that ends badly is worth about a third of finishing one.
# * **Capped, so it cannot replace clears.** Without a ceiling a player could dive and die
#   their way to the Maw with no clears at all, arrive at difficulty 8 with a starting
#   collection, and D36's ceiling would make that a wall rather than a freedom. Three is
#   deliberately less than the deepest gate: the Maw still wants five real clears.
# * **Only from dungeons you have not cleared.** Otherwise the deep dungeons you have
#   already beaten keep paying for gates you passed long ago, which is not a second route,
#   it is a bonus.
const GATE_DEPTH_FLOORS_PER_CREDIT := 3
const GATE_DEPTH_CREDIT_MAX := 3

## Gate credit earned by going deep without coming back, from `MetaState.depth_records`
## (dungeon id -> deepest floor NUMBER reached, 1-based).
##
## Counts floors BEYOND the first, because arriving on floor 1 is entering the door, not
## evidence of anything — every run does it, so counting it would hand every player a
## credit per dungeon for turning up.
static func depth_credit(depth_records: Dictionary, cleared: Array) -> int:
	return mini(GATE_DEPTH_CREDIT_MAX,
		depth_credit_floors(depth_records, cleared) / GATE_DEPTH_FLOORS_PER_CREDIT)

## The raw floors behind that credit, for the screens that have to SHOW the second route —
## an alternative the player cannot see does not exist as far as they are concerned.
##
## `depth_credit` is derived FROM this rather than repeating the sum: two places counting the
## same thing is D34, and the shape it would take here is a screen promising a credit the
## gate does not grant.
static func depth_credit_floors(depth_records: Dictionary, cleared: Array) -> int:
	var floors := 0
	for did in depth_records:
		if String(did) in cleared or not (String(did) in DUNGEONS):
			continue
		floors += maxi(0, int(depth_records[did]) - 1)
	return floors

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
##
## Was 0.5, on an axis whose excess above the floor topped out at 2.8. It now tops
## out near 20, and left alone this pinned the clamp at 0.5 — half of every hit
## going straight through Block — and cost a maxed deck 74 HP a fight at depth 6
## against a starter's 34. A slope against ratio, so D109 scaled it down with the
## axis; the remainder of the maxed-deck budget went to DMG_POWER_K instead, which
## reaches mid-game block pools that pierce at depth cannot.
const PIERCE_PER_RATIO := 0.020

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
