## HP + block + status effects. Player and enemies both use it.
class_name Combatant
extends RefCounted

const VULNERABLE_MULT := 1.5
const WEAK_MULT := 0.75

var name: String = "Fighter"
var hp: int = 50
var max_hp: int = 50
var block: int = 0

# Decaying debuffs (one stack expires per turn).
var vulnerable: int = 0
var weak: int = 0
# Permanent buffs for the rest of the combat.
var strength: int = 0
var dexterity: int = 0
## Damage-over-time: ticks at end of turn, then loses a stack.
var poison: int = 0
## Retaliation dealt to anything that attacks this combatant.
var thorns: int = 0
## Legendary effect: block is kept between turns and accumulates.
var retain_block: bool = false

## Outgoing damage after this combatant's own modifiers.
func outgoing_damage(base: int) -> int:
	if base <= 0:
		return 0
	var d := float(base + strength)
	if weak > 0:
		d *= WEAK_MULT
	return maxi(0, int(round(d)))

## Block actually gained, after this combatant's own modifiers.
func outgoing_block(base: int) -> int:
	if base <= 0:
		return 0
	return maxi(0, base + dexterity)

## Take a hit. `amount` is the attacker's already-modified output; this applies
## the *defender's* vulnerability, then block absorption.
func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	var incoming := amount
	if vulnerable > 0:
		incoming = int(round(incoming * VULNERABLE_MULT))
	var remaining := incoming - block
	block = max(0, block - incoming)
	if remaining > 0:
		hp = max(0, hp - remaining)

## Damage this combatant would suffer from `amount` right now (for UI/AI intent).
func predicted_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var incoming := amount
	if vulnerable > 0:
		incoming = int(round(incoming * VULNERABLE_MULT))
	return max(0, incoming - block)

func gain_block(amount: int) -> void:
	block += max(0, amount)

## Called at the start of this combatant's turn. Block normally expires here —
## that is the core defensive tension. `retain_block` (a legendary power) turns
## block into a resource that accumulates across turns instead.
func begin_turn() -> void:
	if not retain_block:
		block = 0

## Called at the end of this combatant's turn: decaying debuffs tick down.
## End of turn: poison bites (ignoring block, by design), then debuffs decay.
## Returns the poison damage dealt, for the log.
func end_turn() -> int:
	var dot := 0
	if poison > 0:
		dot = poison
		hp = max(0, hp - dot)
		poison -= 1
	vulnerable = max(0, vulnerable - 1)
	weak = max(0, weak - 1)
	return dot

## `status_text()` used to live here — "Blk 5 Psn 3 Vuln 2 Weak 1 Str 2 Dex 1", built for
## the little enemy plates and abbreviated because there was no icon to use. All seven
## have a painted symbol now, so the plates draw chips (`Combat._fill_chips`), and it had
## exactly ONE caller in the tree: the plate. Grepped `*.gd`, `*.tscn` and the docs before
## touching it, because a string some callers render as art and others as text is worse
## than either — there were no other callers, no test read it and nothing logged it.
##
## It is gone rather than kept as a fallback because keeping it would have left a second
## hand-kept list of the same seven statuses that nothing reads, drifting from the one in
## `Combat.STATUS_CHIPS` — the shape D111 is about. Its abbreviations moved into that
## table's `abbrev` column, which is what the plates still print when a symbol is missing,
## so nothing about the degraded reading changed.

func save_state() -> Dictionary:
	return {
		"name": name, "hp": hp, "max_hp": max_hp, "block": block,
		"vulnerable": vulnerable, "weak": weak, "strength": strength,
		"dexterity": dexterity, "poison": poison, "thorns": thorns,
		"retain_block": retain_block,
	}

func load_state(d: Dictionary) -> void:
	name = String(d.get("name", name))
	hp = int(d.get("hp", hp))
	max_hp = int(d.get("max_hp", max_hp))
	block = int(d.get("block", 0))
	vulnerable = int(d.get("vulnerable", 0))
	weak = int(d.get("weak", 0))
	strength = int(d.get("strength", 0))
	dexterity = int(d.get("dexterity", 0))
	poison = int(d.get("poison", 0))
	thorns = int(d.get("thorns", 0))
	retain_block = bool(d.get("retain_block", false))

func is_dead() -> bool:
	return hp <= 0
