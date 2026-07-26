## A zone of the world: a themed cluster of dungeons that share a card pool.
##
## Zones are the layer the overworld will render as regions. They exist so card
## availability is *geographic*: a poison deck is something you go somewhere to
## build, not something you roll into anywhere. A dungeon's obtainable cards are
## the union of its zone's pool and its own pool, so zone pools carry the theme
## and dungeon pools carry the exclusives.
class_name ZoneData
extends Resource

@export var id: String = "barrows"
@export var name: String = "The Hollow Barrows"
@export var description: String = "Where everyone starts, and most things end."
## Dungeon ids belonging to this zone, in intended order.
@export var dungeons: PackedStringArray = PackedStringArray()
## Cards obtainable anywhere in this zone (the zone's theme).
@export var card_pool: PackedStringArray = PackedStringArray()
## Zone unlocks once this many dungeons (anywhere) have been cleared.
@export var unlock_after_clears: int = 0
