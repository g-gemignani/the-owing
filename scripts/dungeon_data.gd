## A named dungeon (D6). Data-only Resource, one .tres per dungeon.
##
## This replaces "dungeon = a depth counter" with "dungeon = a place you choose",
## which is also the seam the overworld will plug into later: a city/world node
## just needs to point at a dungeon id.
##
## Each dungeon owns its own enemy roster and card pool, so an exclusive card is
## simply a card that appears in exactly one pool.
class_name DungeonData
extends Resource

@export var id: String = "crypt"
@export var name: String = "The Crypt"
@export var description: String = "Damp stone and old bones."
## Feeds every Balance formula that used to take a raw depth number.
@export var difficulty: int = 1
## How this dungeon is explored (Traversal.Kind). Different places navigate
## differently on purpose; the unlock order doubles as the teaching order.
@export var traversal: int = 0
## Unlocks once this many dungeons have been cleared (0 = available immediately).
@export var unlock_after_clears: int = 0

## Enemy archetype ids that can appear here. Empty = fall back to the tier roster.
@export var enemy_roster: PackedStringArray = PackedStringArray()
## The archetype fought at this dungeon's BOSS node — named, fixed, and announced
## before the run starts.
##
## The boss used to be drawn at random from `enemy_roster`, which meant seven of
## twelve dungeons had no boss archetype in their pool at all: their finale was a
## trash mob with 1.55x HP. Where a boss WAS in the pool it also turned up as a
## normal encounter, spending its signature before the fight that needed it.
##
## Fixing the pairing is what makes choosing a deck a decision: you know the
## Forge-Warden punishes Block before you decide to bring Block.
@export var boss: String = ""
## Card ids that can drop here (rewards and shop stock). Empty = the global pool.
@export var card_pool: PackedStringArray = PackedStringArray()
## Card ids found ONLY here — for UI, so the player can see what a run is for.
@export var exclusive_cards: PackedStringArray = PackedStringArray()

func has_roster() -> bool:
	return enemy_roster.size() > 0

func has_pool() -> bool:
	return card_pool.size() > 0
