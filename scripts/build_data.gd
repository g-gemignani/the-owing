## A named deck archetype ("build") and the cards that define it.
##
## Builds exist so card collection has a *goal shape*. Their defining cards are
## deliberately scattered across dungeons in different zones, which means finishing
## a build requires clearing several places — and because run earnings are escrowed
## (D20), "obtaining" a card really does mean beating that dungeon's boss or
## spending a rope on it.
##
## `test_build.gd` enforces the scattering, so a later content edit cannot quietly
## collapse a build into a single farmable dungeon.
class_name BuildData
extends Resource

@export var id: String = "poison"
@export var name: String = "The Long Death"
@export var description: String = "Damage that ignores armour and cannot be blocked."
## Cards that define the archetype. Order is not meaningful.
@export var cards: PackedStringArray = PackedStringArray()
