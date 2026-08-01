## A Power: an ability the player can fire ONCE PER TURN, every turn, for energy.
##
## Exists because a bad draw used to be a wasted turn, and the only answer the game
## offered was deck consistency. A power puts a floor under the worst hand without
## raising the ceiling on the best one.
##
## Two rules keep it a floor rather than a replacement for the deck:
##
## * **Once per turn.** With three energy and a one-cost power, unlimited firing
##   makes "power, power, power" a legal turn — the power becomes both floor and
##   ceiling, draw stops mattering, and a deckbuilder stops being one.
## * **Priced into the ratio.** Enemy scaling keys off deck power per energy
##   (`Balance.power_ratio`). A power is throughput from OUTSIDE the deck, exactly
##   the hole relics had. Left unpriced it is free strength and breaks the ratchet.
##
## Extends CardData on purpose. A power is a card you always hold, so it inherits
## every mechanic, every level-scaling rule and the whole `power_value()` pricing
## model — and `CombatEngine._resolve()` applies it through the identical code path
## as a card. Nothing can drift between the two, which is the D34 lesson applied
## before the bug instead of after it.
class_name PowerData
extends CardData

## Dungeon clears needed before this power can be bought at all.
@export var unlock_after_clears: int = 0

## Powers level like cards, but with gold only — there are no duplicate copies of
## a power to spend. See Balance.power_upgrade_cost.
##
## An UPPER BOUND, not the track. It used to be the track, authored at 10 for every
## power regardless of whether the power had ten improvements in it, and 44 of the
## 63 power level-ups it sold changed nothing: Bulwark went 8, 8, 9, 9, 9, 10, 10,
## 10, 11, and Foresight read "Draw 1" at all ten levels because nothing in the
## scaling model touched `draw` at all.
@export var max_level: int = 10

## The shorter of what the player was promised and what the power can actually
## deliver. `CardData.level_cap()` is the same rule cards use — inherited rather
## than reimplemented, for the reason in this class's header.
##
## Overriding the CAP rather than only `level_capped()` matters: every `eff_*`
## getter spreads its budget across `level_cap()` steps, so a power that stops at
## 10 has to say 10 there too. Left to the card rule, Bulwark would have spread a
## common's hundred-step budget over a track it can only walk a tenth of, and
## arrived at its last level having collected a tenth of its growth.
func level_cap() -> int:
	return clampi(super(), 1, maxi(1, max_level))

func level_capped() -> int:
	return level_cap()

func at_max() -> bool:
	return level >= level_capped()
