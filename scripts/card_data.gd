## Card definition. Data-only Resource — one .tres file per card.
## Upgrade system later: bump `level`, recompute damage/block.
class_name CardData
extends Resource

enum Type { ATTACK, SKILL, POWER }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Stable identity — keys the persistent collection. Matches the .tres stem.
@export var id: String = "hack"
@export var name: String = "Hack"
@export var description: String = "Deal 6 damage."
@export var cost: int = 1
@export var type: Type = Type.ATTACK
@export var rarity: Rarity = Rarity.COMMON
## Duplicate-fusion hook: level scales the numbers below.
@export var level: int = 1

## Was this copy FOUND during a run, rather than brought into it (D299)?
##
## Run-scoped and deliberately NOT `@export`: it is a fact about one copy in one dungeon, not
## about the card, so it must never reach a `.tres` or the collection. `Resource.duplicate()`
## copies stored properties only, which is what keeps a found copy from infecting the catalogue
## instance it was duplicated from — every path that makes a run card sets this itself
## (`GameState.earn_card`, and the run save through `CombatEngine._cards_to_state`).
##
## What reads it is `CombatEngine.setup`, which prices the run against the cards you BROUGHT and
## lets the dungeon's gifts be free. See D238 for the same move on relics and the pillar it
## rewrote.
var found_in_run: bool = false

## This card as the RATCHET prices it: at `Balance.priced_level(level)` (D291).
##
## Returns `self` when nothing is discounted, so the common case — every card at or under the
## cap — allocates nothing and reuses the `power_value` cache already on this instance.
##
## Cached on the level it was built for, because `power_ratio` runs once per fight and the
## simulator runs it hundreds of thousands of times. `duplicate()` here is the same trick
## `level_up_text` has used since D50 to ask a card what it would be at another level.
var _priced_twin: CardData = null
var _priced_twin_for: int = -1

func priced_twin() -> CardData:
	var pl := Balance.priced_level(level)
	if pl >= level:
		return self
	if _priced_twin != null and _priced_twin_for == level:
		return _priced_twin
	var t := duplicate() as CardData
	t.level = pl
	# Belt and braces against recursion: the twin is never asked for its own twin today, and a
	# twin that answered with a further discount would compound the cap every time it was read.
	t._priced_twin = t
	t._priced_twin_for = pl
	_priced_twin = t
	_priced_twin_for = level
	return t
@export var damage: int = 0
@export var block: int = 0
@export var draw: int = 0

@export_group("Mechanics")
## Number of separate hits (each rolls the target's block/Vulnerable separately).
@export var hits: int = 1
## Hit every living enemy instead of only the target.
@export var aoe: bool = false
## Removed from the deck for the rest of the combat once played.
@export var exhaust: bool = false
## Stays in hand at end of turn instead of being discarded.
@export var retain: bool = false
## Damage equal to the player's current Block (ignores the card's own damage).
@export var damage_from_block: bool = false
## Permanent gain per play, for the rest of this combat.
@export var grows: int = 0
@export var heal: int = 0
@export var energy_gain: int = 0
## HP paid to play. Blood-magic style: raw power for a real, immediate cost.
@export var hp_cost: int = 0
## Heal for the damage this card deals.
@export var lifesteal: bool = false
## Bonus damage equal to Strength x this (Heavy Blade lineage).
@export var strength_mult: int = 0
## Double the player's current Block instead of adding a flat amount.
@export var double_block: bool = false

@export_group("Status effects")
## Applied to the target (enemy).
@export var apply_vulnerable: int = 0  # target takes +50% damage while stacked
@export var apply_weak: int = 0        # target deals -25% damage while stacked
## Damage-over-time on the target: ticks at end of turn, then decays.
@export var apply_poison: int = 0
## Retaliation: attackers take this much damage when they hit you.
@export var gain_thorns: int = 0
## Applied to self, and permanent for the rest of the combat.
@export var gain_strength: int = 0     # +damage on every attack
@export var gain_dexterity: int = 0    # +block on every block card
## Legendary power: block stops expiring at end of turn and accumulates instead.
@export var retain_block: bool = false

# --- cards that read the fight -------------------------------------------------
#
# Every card in the game used to be a self-contained arithmetic packet: deal N,
# block N, apply N. Nothing a card did made another card better, so a turn was
# "spend three energy on the biggest numbers" and a deck never became an engine —
# which is the whole thrill of the genre.
#
# These are the smallest vocabulary that fixes that, one per existing build, so a
# build is a set of cards that MULTIPLY each other rather than a shared tag:
#
#   poison    a knife that gets worse the more poison is already in the wound
#   thorns    a strike that scales with the spikes you are wearing
#   status    a hit that lands harder on something already reeling
#   tempo     a card that pays off for being the third one this turn
#   swarm     a kill that gives the energy back, so a good turn keeps going
#   fortress  a guard that is stronger the more you are still holding
#
# Every one of them is priced in `power_value()` below. That is not optional: an
# unpriced mechanic means enemy scaling silently falls behind the decks using it,
# which has already happened twice (poison in D17, AoE in the same pass).

## +N damage for each Poison stack already on the target.
@export var damage_per_poison: int = 0
## +N damage for each point of Thorns you are wearing.
@export var damage_per_thorns: int = 0
## +N damage if the target is Vulnerable or Weak.
@export var bonus_vs_debuffed: int = 0
## From your Nth card this turn onward, this card is worth `combo_bonus` more.
## 0 disables. The count includes this card, so `combo_at = 3` means "your third".
@export var combo_at: int = 0
@export var combo_bonus: int = 0
## Killing something with this card refunds one energy, once.
@export var energy_on_kill: bool = false
## +N Block for each OTHER card still in your hand.
@export var block_per_card_in_hand: int = 0

# --- cards that read the OTHER CARDS (D204) ------------------------------------
#
# D66 taught a card to read the FIGHT: the poison already in the wound, the spikes
# you are wearing, the third card of the turn. What it could not do is make a card
# read ANOTHER CARD, so for a hundred cards the only way to author a new one was to
# pick an existing shape and move its number. Grouped by the axes the engine reads,
# the catalogue had four plain-Block cards, three plain-damage, three damage+grows,
# four flat-Strength, six AoE-poison and five heal-attacks — twenty cards whose
# whole difference from a neighbour was a scalar and a rarity.
#
# `test_distinct.gd` passed on every one of them, and it was right to: none is
# strictly dominated, because each is bigger than the one below it. Domination is
# the wrong instrument for this. "Never the wrong pick" is not "worth picking" — a
# reward screen offering Brace, Sidestep and Survival Instinct is three sizes of
# the same decision, and the deckbuilder has nothing to build.
#
# These are the second vocabulary, and the axis they all share is that the card is
# worth what the REST of your turn is worth. Two shapes, and a build needs both:
#
#   ENABLERS  spend a card to make the next one better
#     empower_next     the swing after this one lands harder
#     discount_next    the card after this one is cheaper
#     exhaust_hand     burn the hand, to be collected by the payoffs below
#
#   PAYOFFS   read what you have already spent this turn or this fight
#     per_card_played    the fourth card of a turn is worth more than the first
#     per_exhausted      everything you have burned this combat is ammunition
#     damage_per_debuff  scales with the stack, where bonus_vs_debuffed was a flag
#     damage_per_energy  spend what is left of the turn in one hit
#     bonus_if_hand_empty  the last card in your hand
#     block_per_thorns   turns the thorns you are wearing into a shield
#     repeat_previous    do the last thing again
#
# Every one is priced in `power_value()` below, and the same rule applies as in D17
# and D66: an unpriced mechanic means enemy scaling falls behind the decks using it.
# `test_mechanics.gd` asserts the price of each, by stripping the field and checking
# the number moves.

## The next Attack you play THIS TURN deals +N. Spent by the next damaging card, and
## the granting card's own damage is computed before it lands, so an attack can
## empower the one after it without empowering itself.
@export var empower_next: int = 0
## The next card you play THIS TURN costs N less. Never below 0.
@export var discount_next: int = 0
## +N per card played BEFORE this one this turn, to damage and to Block alike.
##
## Not `combo_at`, which is a threshold — a card that turns on at your third and is
## flat after it. This is linear, so a chain of cheap cards keeps feeding it, and the
## 0-cost cards nobody built around become the setup for the card at the end.
@export var per_card_played: int = 0
## +N per stack of Vulnerable or Weak on the target, damage only.
## The scaling half of `bonus_vs_debuffed`, which pays a flat bonus for any stack at
## all and so cannot tell one Vulnerable from six.
@export var damage_per_debuff: int = 0
## +N per card exhausted this combat, to damage and to Block alike. Counts what THIS
## card is about to exhaust as well, or the face would under-report itself.
@export var per_exhausted: int = 0
## Exhaust every other card in your hand. A cost that is also the ammunition for
## `per_exhausted` — the pair is the build.
@export var exhaust_hand: bool = false
## Resolve the card you played immediately before this one again, for free. Does not
## chain: a repeat cannot repeat.
@export var repeat_previous: bool = false
## Spend all the Energy left after paying for this card, and deal `damage_per_energy`
## for each point spent. The X-cost payoff for everything that gives Energy back.
@export var spend_all_energy: bool = false
@export var damage_per_energy: int = 0
## +N if this card empties your hand, to damage and to Block alike. The mirror of
## `block_per_card_in_hand`: one pays you for holding cards, this one for spending
## them, and a deck cannot chase both.
@export var bonus_if_hand_empty: int = 0
## +N Block per point of Thorns you are wearing. Lets a thorns deck convert what it
## has already built into a guard, instead of buying Block a second time.
@export var block_per_thorns: int = 0

## The player-facing word for a rarity, for cards, relics and powers alike.
##
## The enum key was being printed straight into labels — "Abyssal Gift [RARE] Lv1/15"
## shouts an identifier at someone who never asked what an enum is — and every call
## site had indexed `Rarity.keys()` itself and picked its own casing, so the same
## value read three different ways. This is the one owner (D115). It derives the word
## from the keys rather than holding a table of its own, because a private copy of a
## shared classification is the D34 bug in better clothes — the mistake
## `Icons.card_family` documents — and a sixth rarity would silently miss a table.
##
## Title Case, and no louder than that: rarity is carried by colour first
## (`Icons.RARITY_COLOURS`), so the word only has to name the tier, not announce it.
## Call sites writing a lowercase status line say `.to_lower()` themselves — that is
## their own typography, and the vocabulary is still owned here.
static func rarity_word(rarity: int) -> String:
	var keys := Rarity.keys()
	return String(keys[clampi(rarity, 0, keys.size() - 1)]).capitalize()

## Rarity as the bracketed tag that follows a name in a list row. Thin on purpose: the
## brackets are several screens agreeing on one convention, and that convention is the
## part that drifted, so it gets an owner too.
static func rarity_badge(rarity: int) -> String:
	return "[%s]" % rarity_word(rarity)

## What this card does RIGHT NOW, generated from its effective numbers.
##
## The `description` field is authored text baked at level 1, so a fused card lied:
## a level-40 Bash still read "Deal 10 damage." on its face while dealing 38, and
## disagreed with its own hover text, which was generated. Anything shown to the
## player is built from the same getters the engine uses, so the two cannot drift.
##
## Terse on purpose — this goes on the card face. Icons.card_tooltip() is the long
## form for hovering.
##
## `live_damage` / `live_block` are what the card would produce in the fight going
## on right now — Strength, Dexterity, Weak and per-combat growth already applied
## by `CombatEngine.card_damage()` / `card_block()`. Pass -1 (the default) for a
## card at rest, in the collection or a shop, where none of that exists yet.
##
## Cards used to show their level-scaled numbers everywhere, which meant Strength
## did not appear on the one surface the player reads before committing energy.
func effect_text(live_damage: int = -1, live_block: int = -1) -> String:
	var dmg := live_damage if live_damage >= 0 else eff_damage()
	var blk := live_block if live_block >= 0 else eff_block()
	var live := live_damage >= 0 or live_block >= 0
	var parts: Array[String] = []
	if dmg > 0:
		var d := "Deal %d damage" % dmg
		if hits > 1:
			d += " x%d" % hits
		if aoe:
			d += " to all"
		# in a fight the number already includes these, so they read as the reason
		# for it rather than as something still to be added
		if live and damage_from_block:
			d += " (your Block)"
		if live and strength_mult > 0:
			d += " (with Strength)"
		parts.append(d)
	# ...but a card whose damage is currently zero still has to say what it does,
	# or a Block-scaling card reads as blank on the turn you have no Block
	if damage_from_block and (not live or dmg <= 0):
		parts.append("Deal damage equal to Block")
	if strength_mult > 0 and (not live or dmg <= 0):
		parts.append("+%d damage per Strength" % strength_mult)
	# The conditional half of a card always states its RULE, even when the live
	# number already includes it: "Deal 17" tells you what happens now, "+1 per
	# Poison" tells you why, and the second is what makes it a card you build around.
	if damage_per_poison > 0:
		parts.append("+%d per Poison" % damage_per_poison)
	if damage_per_thorns > 0:
		parts.append("+%d per Thorns" % damage_per_thorns)
	if bonus_vs_debuffed > 0:
		parts.append("+%d vs debuffed" % bonus_vs_debuffed)
	if combo_at > 0 and combo_bonus > 0:
		parts.append("+%d from card %d" % [combo_bonus, combo_at])
	if energy_on_kill:
		parts.append("+1 Energy on kill")
	if block_per_card_in_hand > 0:
		parts.append("+%d Block per card held" % block_per_card_in_hand)
	# D204: cards that read the other cards. Same rule as the block above — the live
	# number already contains these, and the SENTENCE is what makes it a card you plan
	# a turn around, so both are printed. Payoffs first, then the enablers, then the
	# costs, because that is the order the player resolves them in.
	#
	# TERSE, and measurably so: `tests/CardTextTest.tscn` shrinks a face to fit a
	# 116px card and fails below 14px, and the first draft of these lines wrote Sanguine
	# Feast down to 11px — a card that solved its own overflow by becoming unreadable.
	# The full sentences live in `Icons.card_tooltip`, which is the long form and has a
	# whole hover to spend. "this turn" in particular is dropped here and stated there:
	# it is true of every one of these and costs nine characters on each.
	if per_card_played > 0:
		parts.append("+%d per earlier card" % per_card_played)
	if damage_per_debuff > 0:
		parts.append("+%d per debuff stack" % damage_per_debuff)
	# The cap is on the face, not only in the hover: a rule line that reads "+2 per
	# exhausted" against a live number that stopped climbing four cards ago is a card
	# disagreeing with itself, which is the whole of D50.
	if per_exhausted > 0:
		parts.append("+%d per exhausted (max %d)" % [per_exhausted, Balance.EXHAUST_TALLY_CAP])
	# One clause, not two. "+6 per Energy spent" plus "Spends all your Energy" says the
	# same thing twice and was most of the overflow.
	if damage_per_energy > 0:
		parts.append("Spend all Energy: +%d each" % damage_per_energy)
	elif spend_all_energy:
		parts.append("Spends all your Energy")
	if bonus_if_hand_empty > 0:
		parts.append("+%d on an empty hand" % bonus_if_hand_empty)
	if block_per_thorns > 0:
		parts.append("+%d Block per Thorns" % block_per_thorns)
	if empower_next > 0:
		parts.append("Next Attack +%d" % empower_next)
	if discount_next > 0:
		parts.append("Next card -%dE" % discount_next)
	if repeat_previous:
		parts.append("Repeat your last card")
	if exhaust_hand:
		parts.append("Burn your hand")
	# "Lifesteal" rather than a sentence, and it is the genre's own word: `Glossary`
	# exists to teach the vocabulary, and spending 21 characters of a 116px card face
	# re-explaining a keyword it already defines is what pushed Sanguine Feast under the
	# readability floor. The full sentence is still in the hover.
	if lifesteal:
		parts.append("Lifesteal")
	if double_block:
		parts.append("Double Block")
	if blk > 0:
		parts.append("Gain %d Block" % blk)
	if eff_heal() > 0:
		parts.append("Heal %d" % eff_heal())
	if energy_gain > 0:
		parts.append("+%d Energy" % energy_gain)
	if eff_draw() > 0:
		parts.append("Draw %d" % eff_draw())
	if eff_vulnerable() > 0:
		parts.append("Vulnerable %d" % eff_vulnerable())
	if eff_weak() > 0:
		parts.append("Weak %d" % eff_weak())
	if eff_poison() > 0:
		parts.append("Poison %d" % eff_poison())
	if eff_strength() > 0:
		parts.append("+%d Strength" % eff_strength())
	if eff_dexterity() > 0:
		parts.append("+%d Dexterity" % eff_dexterity())
	if eff_thorns() > 0:
		parts.append("+%d Thorns" % eff_thorns())
	if retain_block:
		parts.append("Block stops expiring")
	if grows > 0:
		parts.append("Grows +%d per play" % grows)
	if eff_hp_cost() > 0:
		parts.append("Costs %d HP" % eff_hp_cost())
	if retain:
		parts.append("Retain")
	if exhaust:
		parts.append("Exhaust")
	if parts.is_empty():
		# a mechanic nobody has taught this function about: fall back rather than
		# show a blank card
		return description
	return ". ".join(parts) + "."

## Value of one point of Block relative to one point of damage.
## Fields that are ONLY a quantity. Every other effect field on this class changes a RULE.
##
## Stated as the short list of exceptions rather than the long list of mechanics, and the direction is
## the point: a field added later is a rule-changer BY DEFAULT. A new mechanic is far more likely to
## be a rule than a number, and guessing wrong only costs the top rarity band a card it could have
## skipped.
const PLAIN_NUMBERS := ["damage", "block", "draw"]

## Bookkeeping and identity, which are not effects at all.
const NOT_EFFECTS := ["id", "name", "description", "cost", "type", "rarity", "level",
	"unlock_after_clears", "max_level", "growth"]

## Does this card change a RULE, rather than only move a number? (D250)
##
## **One owner, because there were two and they disagreed.** `tools/rerarify.gd` used this to decide
## which card may take the top rarity band, and `tests/test_rarity.gd` used its own copy to assert
## that every legendary changes something. Both were the same hand-written list of eight fields, and
## both knew nothing of the conditional mechanics D66 and D204 added — so a power whose whole identity
## is `discount_next` read as "only numbers", got passed over for the top band, and produced a
## LEGENDARY band weaker than the EPIC band under it with nothing failing.
##
## Fixing one copy then made them disagree about `grows`, which is the D34 shape arriving on schedule:
## the tool called Drilled a rule-changer and the suite called it numbers. So the definition lives
## here, beside the fields it reads, and is DERIVED from the property list rather than listed.
func changes_a_rule() -> bool:
	for prop in get_property_list():
		var pname: String = String(prop["name"])
		if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if pname in NOT_EFFECTS or pname in PLAIN_NUMBERS:
			continue
		var v: Variant = get(pname)
		if v is bool and bool(v):
			return true
		if (v is int or v is float) and float(v) != 0.0:
			return true
	return false

const BLOCK_VALUE := 0.65

## What hitting every enemy is worth. Average living enemies is only ~1.3: groups
## exist but most encounters are single-target, so AoE is worth far less than
## "effect x enemies". Applies to damage AND to debuffs, because `_resolve()`
## spreads both.
const AOE_SPREAD := 1.35

# --- levelling: every level a player buys must move a number ------------------
#
# It did not. Measured across the whole game before this rewrite: 3,559 of the
# 4,640 card level-ups (77%) and 44 of the 63 power level-ups changed nothing at
# all, and eight cards — Focus, Read Ahead, See It Coming, Kick, Abyssal Gift,
# Ram, Double Down, Set Stone — changed nothing at ANY level. Commons were the
# worst at 86% dead, so the cards a player levels first were the ones that lied
# most.
#
# The old shape was `base + round(base * rate * sqrt(level - 1))`: a curve picked
# for feel and then handed to integer rounding, which eats every step smaller
# than half a point. A common card's ENTIRE track was +15 damage spread over 99
# levels, so 84 of them landed on the number below. Statuses were worse: +5 over
# a hundred levels.
#
# This cannot be retuned, only rebuilt, because the constraint is arithmetic: a
# track can never be longer than the number of integer steps it has to give. So
# both halves move.
#
#   * growth is at least +1 per level BY CONSTRUCTION (`_spread`), not by tuning
#   * a card that cannot pay for a long track gets a short one (`level_cap`)
#
# What it costs, stated plainly rather than buried: growth is now LINEAR in level
# where it used to be sub-linear, so a maxed common Hack deals ~107 instead of
# 21. That ceiling is five times the old one and the entire difficulty ratchet
# was re-measured against it — see D109.

## Gain per level for the numbers a card LEADS with (damage, block, heal), as a
## multiple of the base and floored at one point per level.
##
## Ascends steeply with rarity because the tracks descend the other way (common
## 100 levels, legendary 5). At a fixed base these land maxed values of
## 107 / 123 / 136 / 143 / 157 — rarer still ends up stronger.
##
## What is gone is the maxed MULTIPLIER ladder the old model advertised (3.5x
## rising to 5.0x). With a +1 floor a common's 99 levels are worth +99 on their
## own, and no shorter track can be a bigger multiple of the same base. Absolute
## maxed power is what ascends now, which is what "grinding commons must not beat
## a legendary" always actually meant.
const LEVEL_RATE_BY_RARITY := [0.17, 0.50, 1.55, 5.70, 6.30]

## Statuses are the one axis that CANNOT take a point per level. A stack is a
## multiplier on every later action, so 100 Vulnerable is not a strong card — it
## is a fight that is over before it starts. These are a budget for the WHOLE
## track rather than a rate, and a card whose only axis is a status gets a track
## short enough to spend it (`level_cap`) instead of a long one that mostly does
## nothing.
const STATUS_BUDGET_BY_RARITY := [4, 5, 6, 7, 8]

## Same reasoning, harder. An extra card drawn is the most valuable single point
## in the game, so these budgets are tiny and the tracks they buy are two or three
## levels long. Short and honest beats a hundred levels of "Draw 1".
const DRAW_BUDGET_BY_RARITY := [1, 1, 2, 2, 3]

## How hard the surplus above one-point-per-level leans on the early levels.
##
## 1.0 is a straight line, 0.5 is the old sqrt. 0.5 measured badly on SHORT tracks:
## a nine-step power track gives its first level sqrt(1/9) = a third of the entire
## budget, which took Overwhelm from 7 damage to 38 on the single cheapest upgrade
## in its track and made every level after it a disappointment. 0.8 keeps early
## levels the better buy without that cliff (Overwhelm 7 -> 23 -> ... -> 105), and
## on a hundred-step common track the difference is invisible either way.
const FRONTLOAD_EXP := 0.8

## Spread `budget` points across a `cap`-long track; return the value at `level`.
##
## Two regimes, and the first is the whole point of the rewrite:
##
##   budget >= steps   every step is at least +1 (the linear term) and the surplus
##                     is front-loaded, so early levels still feel bigger than late
##                     ones. Everything a card leads with is in this regime, because
##                     `_headline_budget` floors the budget at one per step.
##   budget <  steps   there is not enough to go round, so it spreads evenly and
##                     some levels do not move THIS number. Only ever reached by a
##                     card's secondary numbers — `level_cap` guarantees the card's
##                     best axis is always in the first regime, so the CARD still
##                     improves even on a level where its status does not.
##
## The linear term is not a stylistic choice: two reals a whole point apart cannot
## round to the same integer, which is exactly the guarantee the old sqrt curve
## could not make.
static func _spread(base: int, budget: int, level: int, cap: int) -> int:
	var steps := maxi(1, cap - 1)
	var k := clampi(level - 1, 0, steps)
	if k == 0 or budget <= 0:
		return maxi(0, base)
	if budget >= steps:
		var surplus := float(budget - steps) * pow(float(k) / float(steps), FRONTLOAD_EXP)
		return base + k + int(round(surplus))
	return base + int(round(float(budget) * float(k) / float(steps)))

func _headline_budget(base: int) -> int:
	if base <= 0:
		return 0
	var rate: float = LEVEL_RATE_BY_RARITY[clampi(rarity, 0, LEVEL_RATE_BY_RARITY.size() - 1)]
	var steps := maxi(1, level_cap() - 1)
	# the floor is what makes the level land; the rate is what makes a big card
	# grow like a big card instead of converging on every other card of its rarity
	return maxi(steps, int(round(float(base) * rate * float(steps))))

func _status_budget(base: int) -> int:
	if base <= 0:
		return 0
	return int(STATUS_BUDGET_BY_RARITY[clampi(rarity, 0, STATUS_BUDGET_BY_RARITY.size() - 1)])

func _draw_budget() -> int:
	if draw <= 0:
		return 0
	return int(DRAW_BUDGET_BY_RARITY[clampi(rarity, 0, DRAW_BUDGET_BY_RARITY.size() - 1)])

## HP paid can be bought down, never away: blood magic that costs nothing is not
## blood magic, and `power_value` prices the cost it would be removing.
func _hp_cost_budget() -> int:
	return maxi(0, hp_cost - 1)

## The biggest stack this card applies or gains. Statuses share one budget, so the
## track only has to be long enough for the largest of them.
func _max_status() -> int:
	return maxi(maxi(maxi(apply_vulnerable, apply_weak), maxi(apply_poison, gain_thorns)),
		maxi(gain_strength, gain_dexterity))

## The LAST RESORT axis, and the reason Set Stone has a level track at all.
##
## Set Stone is `retain_block` and nothing else: no damage, no block, no status, no
## draw — literally no number for a level to move, and it was selling four of them.
## Energy is the one thing every card has. It is only opened for cards with nothing
## else to grow, because a card that got both cheaper AND bigger every level would
## quietly double-dip on `power_ratio`, which is power PER ENERGY.
##
## A card comes down to 1 energy; a card already at 1 can reach 0.
func _cost_budget() -> int:
	if cost <= 0 or damage > 0 or block > 0 or heal > 0 \
			or _max_status() > 0 or draw > 0 or hp_cost > 0:
		return 0
	return maxi(cost - 1, 1)

## How many levels this card actually has to sell.
##
## Rarity still sets the LONGEST a track may be — `Balance.max_level`, derived from
## drop weight, common 100 down to legendary 5, unchanged. What is new is the
## ceiling under it: a card can only be as long as it has improvements, so a card
## with no number to grow stops early rather than selling empty levels.
##
## Anything with damage, block or heal fills its whole rarity track, because
## `_headline_budget` floors that budget at one point per step. Everything else is
## as long as its budget: Expose (2 Vulnerable, uncommon) sells five levels, Focus
## (Draw 1, common) sells one, Set Stone sells two.
var _cap_cache := -1
var _cap_cache_rarity := -1

func level_cap() -> int:
	if _cap_cache_rarity == rarity and _cap_cache > 0:
		return _cap_cache
	var track: int = Balance.max_level(rarity)
	var cap := track
	if damage <= 0 and block <= 0 and heal <= 0:
		var budget := maxi(_status_budget(_max_status()), _draw_budget())
		budget = maxi(budget, _hp_cost_budget())
		budget = maxi(budget, _cost_budget())
		cap = clampi(1 + budget, 1, track)
	_cap_cache_rarity = rarity
	_cap_cache = cap
	return cap

## What levelling this card to `target_level` actually buys: "dmg 9→10, blk 5→6".
## Empty when nothing measurable changes.
##
## Fusion spends copies AND gold (D35), and the Collection quoted only the price —
## the player was asked to make an economic decision against the shop with the
## benefit side of it missing. Generated by asking a copy of the card at the new
## level, through the same getters the engine resolves with, so the preview cannot
## promise a number the card will not deliver (D50, again).
func level_up_text(target_level: int) -> String:
	if target_level <= level:
		return ""
	var after := duplicate() as CardData
	after.level = target_level
	var parts: Array[String] = []
	for pair in [
			["dmg", eff_damage(), after.eff_damage()],
			["blk", eff_block(), after.eff_block()],
			["heal", eff_heal(), after.eff_heal()],
			["draw", eff_draw(), after.eff_draw()],
			["poison", eff_poison(), after.eff_poison()],
			["vuln", eff_vulnerable(), after.eff_vulnerable()],
			["weak", eff_weak(), after.eff_weak()],
			["str", eff_strength(), after.eff_strength()],
			["dex", eff_dexterity(), after.eff_dexterity()],
			["thorns", eff_thorns(), after.eff_thorns()]]:
		var before: int = pair[1]
		var now: int = pair[2]
		if now > before:
			parts.append("%s %d→%d" % [pair[0], before, now])
	# ...and the two that improve by getting SMALLER. Left out, a Set Stone level
	# read as buying nothing, which is the exact bug this whole pass is about.
	for pair2 in [
			["energy", eff_cost(), after.eff_cost()],
			["hp cost", eff_hp_cost(), after.eff_hp_cost()]]:
		var before2: int = pair2[1]
		var now2: int = pair2[2]
		if now2 < before2:
			parts.append("%s %d→%d" % [pair2[0], before2, now2])
	return ", ".join(parts)

func eff_damage() -> int:
	return _spread(damage, _headline_budget(damage), level, level_cap())

func eff_block() -> int:
	return _spread(block, _headline_budget(block), level, level_cap())

func eff_heal() -> int:
	return _spread(heal, _headline_budget(heal), level, level_cap())

func eff_vulnerable() -> int:
	return _spread(apply_vulnerable, _status_budget(apply_vulnerable), level, level_cap())

func eff_weak() -> int:
	return _spread(apply_weak, _status_budget(apply_weak), level, level_cap())

func eff_strength() -> int:
	return _spread(gain_strength, _status_budget(gain_strength), level, level_cap())

func eff_dexterity() -> int:
	return _spread(gain_dexterity, _status_budget(gain_dexterity), level, level_cap())

func eff_poison() -> int:
	return _spread(apply_poison, _status_budget(apply_poison), level, level_cap())

func eff_thorns() -> int:
	return _spread(gain_thorns, _status_budget(gain_thorns), level, level_cap())

func eff_draw() -> int:
	return _spread(draw, _draw_budget(), level, level_cap())

# --- the two numbers a level makes SMALLER ------------------------------------
#
# Everything above is a number going up. These two go down, and they exist because
# a card whose whole identity is a rule — Set Stone, Ram, Double Down — has nothing
# to grow, and was selling levels that bought nothing at all. `_spread` is reused
# unchanged: it returns how much of the budget has been SPENT by this level, and
# the cost is what is left.

## HP paid to play, bought down toward 1.
func eff_hp_cost() -> int:
	return maxi(0, hp_cost - _spread(0, _hp_cost_budget(), level, level_cap()))

## Energy cost. Only ever moves for cards with no number of their own — see
## `_cost_budget`. Every read of a card's price must come through here, or a
## levelled card charges the player one number and shows another (D50).
func eff_cost() -> int:
	return maxi(0, cost - _spread(0, _cost_budget(), level, level_cap()))

## Runtime-only: accumulated bonus from `grows`, reset each combat.
var growth: int = 0

## Damage of one hit, including any growth accumulated this combat.
func hit_damage() -> int:
	return eff_damage() + growth

## Tuning value of this card, used by Balance.power_ratio so enemy scaling keeps
## pace with status/power cards. Without this, a strong effect card would read as
## "0 power" and the difficulty curve would silently fall behind.
## Memoised per instance, keyed on the level it was computed at.
##
## `power_ratio` sums this over the whole deck at the start of every fight, which
## measured 31% of combat setup — for a number that cannot change unless the card
## levels up. Everything below reads static fields and `level`; nothing reads the
## per-combat `growth`, so the level is the whole key.
var _power_cache := -1.0
var _power_cache_level := -1

func power_value() -> float:
	if _power_cache_level == level and _power_cache >= 0.0:
		return _power_cache
	_power_cache_level = level
	_power_cache = _power_value_uncached()
	return _power_cache

func _power_value_uncached() -> float:
	# multi-hit and AoE multiply the damage a single card delivers
	var dmg := float(eff_damage()) * float(maxi(1, hits))
	if aoe:
		dmg *= AOE_SPREAD
	if damage_from_block:
		dmg += 8.0   # scales off Block rather than its own number
	if strength_mult > 0:
		dmg += 3.0 * float(strength_mult)   # assumes a modest Strength stack
	if lifesteal:
		dmg *= 1.5   # damage that is also healing
	# Conditional damage, priced at what it is worth ON AVERAGE rather than at its
	# ceiling. A deck built for one of these sees it often; a deck that happens to
	# hold the card sees it never, and pricing the ceiling would charge both.
	# Calibrated against measured run completion, not intuition — the first guess of
	# "~4 stacks" was the D17 poison mistake again: a deck BUILT for these holds far
	# more than a deck that happens to draw the card. Thorns decks sit on 8-14 and
	# poison decks on 6-10, and at 2.0 the thorns build's completion jumped from 40%
	# to 69% while its priced ratio FELL — power delivered without being charged for.
	dmg += 3.5 * float(damage_per_poison)
	dmg += 5.0 * float(damage_per_thorns)
	dmg += 0.6 * float(bonus_vs_debuffed)      # roughly the uptime of a debuff
	if combo_at > 0:
		# only pays from the Nth card on, and a 3-energy turn rarely reaches 4
		dmg += float(combo_bonus) * (0.6 if combo_at <= 3 else 0.35)
	if energy_on_kill:
		dmg += 6.0                              # a conditional slice of energy_gain
	# --- D204: what the REST of the turn is worth -----------------------------
	#
	# Averages again, for the reason the block above gives, and deliberately
	# conservative multiples rather than ceilings. The ceiling of `per_card_played`
	# is a nine-card turn; charging every deck that holds the card for a turn almost
	# none of them will assemble is the D17 mistake pointing the other way.
	#
	# ~1.6 cards land before a given card in a three-energy turn once there is cheap
	# setup to feed it. A debuff deck sits on 3-5 stacks and they decay, so this prices
	# under poison's 3.5. An X-cost card played at one energy spends the other two.
	#
	# `per_exhausted` is the one priced against a HARD ceiling rather than an average,
	# and that is the whole reason `Balance.EXHAUST_TALLY_CAP` exists: an exhaust deck
	# sits AT its cap for most of a fight, so an average is the wrong shape of estimate
	# — the honest number is the ceiling, discounted only for the turns before it gets
	# there. Two thirds of the cap. Uncapped there was no right answer at all: the card
	# was worth more on turn five than on turn three and `power_value` is one number.
	dmg += 2.2 * float(damage_per_debuff)
	dmg += 2.0 * float(damage_per_energy)
	# Damage on a LATER card, worth slightly less than damage now: it needs an attack
	# to follow it, and a turn that ends first wasted the whole thing.
	dmg += 0.8 * float(empower_next)
	# Three of the D204 axes pay a card's OWN currency — damage on an attack, Block on
	# a skill (see CombatEngine.card_block_bonus) — so which rate they are charged at
	# depends on the card holding them. Charging Block at the damage rate is not a
	# rounding error: Block is priced at 0.65 for a measured reason, and inflating a
	# guard's price makes enemies hit harder than the deck it inflated can answer,
	# which is the failure D124 caught in the other direction.
	var shared := 1.6 * float(per_card_played) \
		+ float(per_exhausted) * float(Balance.EXHAUST_TALLY_CAP) * 0.67 \
		+ 0.35 * float(bonus_if_hand_empty)   # conditional on a hand you emptied
	# Block is priced BELOW damage on purpose. Damage does double duty: it removes
	# enemy HP *and* thereby shortens the fight, which prevents damage in turn.
	# Block only mitigates, and with escalation a longer fight is a worse fight.
	# Pricing them equally charged block-heavy decks for power that never shortened
	# a fight — measured as a stronger endgame deck winning LESS than a weaker one
	# (51% vs 73%) while its fights ran 50% longer.
	#
	# **0.65 was measured against and kept (D285).** Lowering it to 0.50 does help the decks it
	# should — at the Foundry over 200 trials, Barricade 17% to 24%, Mid 24% to 32%, AoE 44% to
	# 54%, Exhaust 61% to 74%, with nothing falling. It cannot be taken, and the reason is worth
	# more than the change: this number is the numerator of `Balance.BASELINE_CARD_POWER`, which is
	# the DIVISOR of every ratio in the game. Move it and the reference deck moves, so every power
	# is re-priced against a cheaper deck — `bulwark` stops raising the ratio at all, which is the
	# unpriced-throughput hole the whole ratchet exists to close.
	#
	# The guards bracket it tightly: 0.62 passes, 0.60 fails on a damage power at 1.604 against a
	# 1.6 cap, and 0.50 opens the Bulwark hole. 0.62 is reachable and buys nothing measurable.
	# **Block cannot be re-priced on its own** — it is one number wearing two jobs, and separating
	# them is the change that would make this tunable.
	var v := dmg + float(eff_block()) * BLOCK_VALUE
	# ~4 other cards in a typical hand, at the same discount Block gets everywhere
	v += float(block_per_card_in_hand) * 4.0 * BLOCK_VALUE
	# ...and the shared D204 axes at whichever rate the card actually pays in.
	v += shared * (1.0 if damage > 0 or hits > 1 or damage_per_energy > 0 else BLOCK_VALUE)
	# A discount is Energy, and Energy is priced at 15 a point (`energy_gain` below) —
	# but a discount is only worth anything if there is a card after it worth playing,
	# and it can never take a cost below zero, so it prices at two thirds of the real
	# thing rather than at parity.
	v += float(discount_next) * 10.0
	# One more resolution of whatever you played last, free. Priced against the deck
	# baseline rather than against its ceiling: the ceiling is the biggest card in the
	# deck and the average is an ordinary one.
	if repeat_previous:
		v += 14.0
	# Burning your hand was priced as a cost (-4.0) and that is the wrong sign, which
	# the pricing model itself said out loud: Cull came out at 1.2 power — a hair above
	# the "every card must be priced" floor, and straight through it the moment anything
	# else about the card moved. A number that fragile is a modelling error, not a tight
	# balance.
	#
	# It is not a cost, because of WHAT gets burned. A hand-burner is played when the
	# cards it destroys are worth less than what it grants — that is the decision, and it
	# is available every turn — so in practice it spends cards the turn had no use for and
	# hands back a payoff. Charging it as a loss made `power_ratio` read an exhaust deck
	# as weaker than a plain one, so enemy scaling under-reacted to the build: the D17
	# unpriced-mechanic failure, arrived at by over-charging the enabler instead of
	# forgetting the payoff. Priced as the mild enabler it is, at `retain`'s premium.
	if exhaust_hand:
		v += 2.0
	# Thorns decks sit on 8-14 (see the note above), at the Block discount.
	v += float(block_per_thorns) * 8.0 * BLOCK_VALUE
	# debuffs are worth roughly the damage they enable/prevent over their duration
	var debuff := eff_vulnerable() * 2.0 + eff_weak() * 2.0
	# Permanent self-buffs compound: +1 Strength is +1 on EVERY attack for the rest
	# of the fight, so they price well above the same number of one-off damage.
	## Calibrated against measured run completion, not intuition: at 6.0/5.0 the
	## priced power of buff decks inflated without their real power changing, so
	## enemy scaling ran past them (thorns builds fell 69% -> 46%).
	v += eff_strength() * 4.5
	v += eff_dexterity() * 4.0
	# A card in hand, priced as a third of the Energy that would let you play it
	# (`energy_gain`, 15 below). It was 1.5 — a TENTH of an energy — and that was not a
	# conservative estimate, it was a hole: the only card in the catalogue that does
	# nothing but draw scored 2.9, below Stumble, which is a card whose whole text is
	# that it is bad (D224). Draw is not free power, and the discount off Energy is the
	# honest part of the old number: a drawn card still has to be paid for, and a hand
	# you cannot afford to empty is a hand that drew nothing. A third, not a tenth.
	v += eff_draw() * 5.0
	# Poison ignores Block, but it is back-loaded and wasted when a fight ends
	# early, so it prices below the same number of immediate damage.
	debuff += eff_poison() * 2.0
	# `aoe` spreads DEBUFFS as well as damage — see `_resolve()` in combat_engine,
	# which builds its debuff target list from every living enemy. Only the damage
	# half was ever charged for it, so a mass-poison card was priced as though it
	# hit one enemy and enemy scaling under-reacted to the decks built around it.
	# Blight Bloom, Pandemic, Hex, Noxious Cloud and Plague Bearer are all AoE with
	# no damage at all, which is to say they were priced entirely on the half of
	# the rule that did not apply to them.
	v += debuff * (AOE_SPREAD if aoe else 1.0)
	v += eff_thorns() * 2.2   # conditional: only pays when the enemy attacks you
	v += eff_heal() * 0.8
	v += energy_gain * 15.0        # an extra card this turn
	v += grows * 5.0               # compounds over a fight
	if double_block:
		v += 12.0
	# a real cost, priced against it — and levels buy it DOWN, so the levelled
	# number is what has to be charged or the discount arrives unpriced
	v -= eff_hp_cost() * 1.2
	if retain:
		v += 3.0
	if exhaust:
		v *= 0.65                  # one use per combat is a real cost
	# Persistent Block compounds, and this is the one card in the game that rewrites a
	# RULE rather than a number: every point of Block you fail to spend stops being
	# waste and starts being a wall. Priced at 30 rather than 12 (D224).
	#
	# The old comment argued the premium down because this value feeds enemy scaling
	# and over-valuing an effect makes enemies hit harder than the deck can answer.
	# That reasoning is sound and it was applied to the wrong side: under-valuing it
	# meant a Barricade deck fought enemies scaled for a deck it was not, and the
	# rarity ladder — which reads this number — called the game's biggest rule change
	# a rare. Measured on the simulator rather than argued: see D224 for the before and
	# after, and re-measure here rather than re-deriving if it moves again.
	if retain_block:
		v += 30.0
	return v
