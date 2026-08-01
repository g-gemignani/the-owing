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
# There is no `traversal` field. Dungeons once named one of four models here; every
# one of them picked the iso crawl in D88 and the other three were deleted in D94, so
# the field was a choice with one option. What makes a place navigate differently is
# now its floor — size, shape, roster, encounter mix — not a model number.
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
## The shape of a run here. -1 means "use the default in Balance".
##
## Every dungeon used to draw from ONE global mix — 3 combats, 1 elite, 1 rest,
## 1 shop, 1 event, 1 treasure — so the Crypt and the Maw had identical rhythms and
## twelve dungeons were one dungeon with different wallpaper and bigger numbers.
## A dungeon can now be a swarm, a gauntlet, a treasure run or a market town.
##
## `tests/test_traversal.gd` keeps them comparable: the total stays within a couple
## of encounters of the default and no dungeon is all fights or no fights, because
## the difficulty rating has to keep meaning something across all twelve.
@export var enc_combats: int = -1
@export var enc_elites: int = -1
@export var enc_rests: int = -1
@export var enc_shops: int = -1
@export var enc_events: int = -1
@export var enc_treasures: int = -1

## How many of each encounter this dungeon holds, defaults filled in.
func encounter_mix() -> Dictionary:
	return {
		"combat": enc_combats if enc_combats >= 0 else Balance.ENCOUNTER_COMBATS,
		"elite": enc_elites if enc_elites >= 0 else Balance.ENCOUNTER_ELITES,
		"rest": enc_rests if enc_rests >= 0 else Balance.ENCOUNTER_RESTS,
		"shop": enc_shops if enc_shops >= 0 else Balance.ENCOUNTER_SHOPS,
		"event": enc_events if enc_events >= 0 else Balance.ENCOUNTER_EVENTS,
		"treasure": enc_treasures if enc_treasures >= 0 else Balance.ENCOUNTER_TREASURES,
	}

@export var card_pool: PackedStringArray = PackedStringArray()
## Card ids found ONLY here — for UI, so the player can see what a run is for.
@export var exclusive_cards: PackedStringArray = PackedStringArray()

func has_roster() -> bool:
	return enemy_roster.size() > 0

func has_pool() -> bool:
	return card_pool.size() > 0
