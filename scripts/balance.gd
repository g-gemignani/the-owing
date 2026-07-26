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
## Levels between each +1 to the copy cost.
const FUSE_COPIES_STEP := 8
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
## scaling with depth (D70) without quietly repricing every fusion in the game.
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
const RATIO_CEILING_PER_DEPTH := 0.73

## The strongest ratio a fully-built player can reach: maxed card levels plus a
## full relic set. Measured with tools/sim_balance.gd, not guessed. The deepest
## dungeon must scale past this or the endgame stops resisting.
const MAX_ACHIEVABLE_RATIO := 6.0

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

static func power(id: String) -> PowerData:
	return load(POWER_DIR + id + ".tres") as PowerData

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
const RELIC_POWER_PER_RATIO := 70.0

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

## Deck model: HP paid to skip a revealed encounter (and forfeit its reward).
##
## This was a flat 8 HP, and it was a cheat. Nothing had ever measured it, because
## the simulator's driver only dodged below 35% HP and so recorded **0.0 avoids per
## run in every profile** — the deck model's entire decision went unexercised for
## its whole existence. Measured properly (`tools/sim_balance.gd`, avoid
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
const DECK_AVOID_BASE_HP := 6
const DECK_AVOID_PER_DEPTH := 1
const DECK_AVOID_STEP := 0.5

static func deck_avoid_cost(difficulty: int, already_avoided: int) -> int:
	var base := float(DECK_AVOID_BASE_HP + DECK_AVOID_PER_DEPTH * (maxi(1, difficulty) - 1))
	return int(round(base * (1.0 + DECK_AVOID_STEP * float(maxi(0, already_avoided)))))

const NODE_LABEL := {0: "Combat", 1: "Elite", 2: "Rest", 3: "BOSS", 4: "Shop",
	5: "Event", 6: "Treasure"}

## Treasure: gold found, and the chance it also holds a card.
const TREASURE_GOLD_MIN := 25
const TREASURE_GOLD_MAX := 60
const TREASURE_CARD_CHANCE := 55
## Chance a treasure also holds an Escape Rope. Ropes are FOUND, never sold:
## a purchasable exit would let the player buy their way out of every risk, which
## is the farming loop escrow was built to close.
const TREASURE_ROPE_CHANCE := 18
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
	return load(ZONE_DIR + id + ".tres") as ZoneData

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
	return load(BUILD_DIR + id + ".tres") as BuildData

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
	return out

static func dungeon(id: String) -> DungeonData:
	return load(DUNGEON_DIR + id + ".tres") as DungeonData

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

## Map node type chances (percent), rolled per non-boss, non-first row.
const NODE_CHANCE_REST := 14
const NODE_CHANCE_SHOP := 12
const NODE_CHANCE_ELITE := 18
const NODE_CHANCE_EVENT := 12
const NODE_CHANCE_TREASURE := 8

# --- shops (gold sink) ---
## Card prices are DERIVED from drop weight, like upgrade caps: a rarity that
## drops W/100 as often as a common costs sqrt(100/W) times as much. sqrt rather
## than linear on purpose — linear would price a legendary at ~4000g, roughly 20
## runs of income, which reads as unobtainable rather than aspirational.
const SHOP_CARD_OFFERS := 3
## Healing sold as a fraction of max HP.
const SHOP_HEAL_FRAC := 0.35

## Shop prices are quoted in FIGHTS, not in gold (D70).
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
## Quoted in fights like everything else the merchant sells (D70), so thinning
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
