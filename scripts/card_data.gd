## Card definition. Data-only Resource — one .tres file per card.
## Upgrade system later: bump `level`, recompute damage/block.
class_name CardData
extends Resource

enum Type { ATTACK, SKILL, POWER }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## Stable identity — keys the persistent collection. Matches the .tres stem.
@export var id: String = "strike"
@export var name: String = "Strike"
@export var description: String = "Deal 6 damage."
@export var cost: int = 1
@export var type: Type = Type.ATTACK
@export var rarity: Rarity = Rarity.COMMON
## Duplicate-fusion hook: level scales the numbers below.
@export var level: int = 1
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
	if lifesteal:
		parts.append("Heal for damage dealt")
	if double_block:
		parts.append("Double Block")
	if blk > 0:
		parts.append("Gain %d Block" % blk)
	if eff_heal() > 0:
		parts.append("Heal %d" % eff_heal())
	if energy_gain > 0:
		parts.append("+%d Energy" % energy_gain)
	if draw > 0:
		parts.append("Draw %d" % draw)
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
	if hp_cost > 0:
		parts.append("Costs %d HP" % hp_cost)
	if retain:
		parts.append("Retain")
	if exhaust:
		parts.append("Exhaust")
	if parts.is_empty():
		# a mechanic nobody has taught this function about: fall back rather than
		# show a blank card
		return description
	return ". ".join(parts) + "."

## Effective numbers after level scaling.
##
## Scaling is deliberately SUB-LINEAR (sqrt). Upgrade tracks run to 100 levels for
## commons, and a linear +3/level would put a maxed Strike at ~300 damage — far
## past anything enemy scaling can answer, so the whole curve would collapse.
## sqrt keeps a maxed card ~3-4x its base: a long grind whose early levels feel
## big and whose late levels are incremental, which is also the RPG feel we want.
## Gain per level, BY RARITY. Rarer cards gain more per level because their level
## tracks are shorter (caps derive from drop weight: common 100, legendary 5).
## With one flat gain the scaling was inverted — a maxed common reached 3.5x while
## a maxed legendary reached only 1.5x, i.e. grinding commons beat every legendary.
## These values are chosen so the MAXED multiplier ascends with rarity instead:
## common 3.5x, uncommon 3.8x, rare 4.2x, epic 4.6x, legendary 5.0x.
## Value of one point of Block relative to one point of damage.
const BLOCK_VALUE := 0.65

const LEVEL_GAIN_BY_RARITY := [0.251, 0.448, 0.855, 1.80, 2.00]
## Status magnitudes grow more slowly than raw numbers (a stack multiplies every
## later action), but follow the same rarity logic.
const STATUS_GAIN_BY_RARITY := [0.5, 0.7, 1.0, 1.6, 1.8]

func level_gain() -> float:
	return float(LEVEL_GAIN_BY_RARITY[clampi(rarity, 0, LEVEL_GAIN_BY_RARITY.size() - 1)])

func status_gain() -> float:
	return float(STATUS_GAIN_BY_RARITY[clampi(rarity, 0, STATUS_GAIN_BY_RARITY.size() - 1)])

func _growth(base: int, level: int) -> int:
	if base <= 0 or level <= 1:
		return maxi(0, base)
	return base + int(round(base * level_gain() * sqrt(float(level - 1))))

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
	return ", ".join(parts)

func eff_damage() -> int:
	return _growth(damage, level)

func eff_block() -> int:
	return _growth(block, level)

## Status magnitudes grow far more slowly than raw numbers: a stack is a
## multiplier on every later action, so it compounds much harder than +N damage.
func _status_growth(base: int, level: int) -> int:
	if base <= 0:
		return 0
	return base + int(round(sqrt(float(maxi(0, level - 1))) * status_gain()))

func eff_vulnerable() -> int:
	return _status_growth(apply_vulnerable, level)

func eff_weak() -> int:
	return _status_growth(apply_weak, level)

func eff_strength() -> int:
	return _status_growth(gain_strength, level)

func eff_dexterity() -> int:
	return _status_growth(gain_dexterity, level)

func eff_poison() -> int:
	return _status_growth(apply_poison, level)

func eff_thorns() -> int:
	return _status_growth(gain_thorns, level)

func eff_heal() -> int:
	return _growth(heal, level)

## Runtime-only: accumulated bonus from `grows`, reset each combat.
var growth: int = 0

## Damage of one hit, including any growth accumulated this combat.
func hit_damage() -> int:
	return eff_damage() + growth

## Tuning value of this card, used by Balance.power_ratio so enemy scaling keeps
## pace with status/power cards. Without this, a strong effect card would read as
## "0 power" and the difficulty curve would silently fall behind.
func power_value() -> float:
	# multi-hit and AoE multiply the damage a single card delivers
	var dmg := float(eff_damage()) * float(maxi(1, hits))
	if aoe:
		# Average living enemies is only ~1.3: groups exist but most encounters are
		# single-target, so AoE is worth far less than "damage x enemies".
		dmg *= 1.35
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
	# Block is priced BELOW damage on purpose. Damage does double duty: it removes
	# enemy HP *and* thereby shortens the fight, which prevents damage in turn.
	# Block only mitigates, and with escalation a longer fight is a worse fight.
	# Pricing them equally charged block-heavy decks for power that never shortened
	# a fight — measured as a stronger endgame deck winning LESS than a weaker one
	# (51% vs 73%) while its fights ran 50% longer.
	var v := dmg + float(eff_block()) * BLOCK_VALUE
	# ~4 other cards in a typical hand, at the same discount Block gets everywhere
	v += float(block_per_card_in_hand) * 4.0 * BLOCK_VALUE
	# debuffs are worth roughly the damage they enable/prevent over their duration
	v += eff_vulnerable() * 2.0
	v += eff_weak() * 2.0
	# Permanent self-buffs compound: +1 Strength is +1 on EVERY attack for the rest
	# of the fight, so they price well above the same number of one-off damage.
	## Calibrated against measured run completion, not intuition: at 6.0/5.0 the
	## priced power of buff decks inflated without their real power changing, so
	## enemy scaling ran past them (thorns builds fell 69% -> 46%).
	v += eff_strength() * 4.5
	v += eff_dexterity() * 4.0
	v += draw * 1.5
	# Poison ignores Block, but it is back-loaded and wasted when a fight ends
	# early, so it prices below the same number of immediate damage.
	v += eff_poison() * 2.0
	v += eff_thorns() * 2.2   # conditional: only pays when the enemy attacks you
	v += eff_heal() * 0.8
	v += energy_gain * 15.0        # an extra card this turn
	v += grows * 5.0               # compounds over a fight
	if double_block:
		v += 12.0
	v -= hp_cost * 1.2          # a real cost, priced against it
	if retain:
		v += 3.0
	if exhaust:
		v *= 0.65                  # one use per combat is a real cost
	# Persistent block compounds, but keep the premium modest: this value feeds
	# enemy scaling, and over-valuing an effect makes enemies hit harder than the
	# deck can actually answer.
	if retain_block:
		v += 12.0
	return v
