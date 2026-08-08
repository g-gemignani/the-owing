## Isometric dungeon crawl: several floors of rooms and corridors, descended one way,
## with things walking them that you can hear before you see.
##
## The only traversal in the game: every dungeon is one of these (D88), and the three
## models it beat — a node graph you committed a route to, a card draw that revealed one
## encounter and priced the dodge, a dice board you managed overshoot on — were deleted
## in D94 once nothing could reach them.
##
## Decision texture, and why it won: the ground here is SPATIAL and can be re-walked.
## The dungeon is a *building*, the way down is not marked, and the question at every
## step is how much of a floor you strip before you take the stairs you have just found.
##
## Four rules carry that, and each one replaced something that measured fine and did
## not feel like anything (D79):
##
## * **The floor is architecture, not a field.** Rectangular chambers joined by
##   corridors, in a shape that differs per dungeon (`Balance.iso_style`). The old
##   generator grew one organic blob where every tile was the same width, so nothing
##   was a place and nothing was a landmark.
## * **A room is revealed whole the moment you enter it**, while a corridor shows only
##   `Balance.ISO_SIGHT` ahead. A single radius everywhere is what made a dungeon feel
##   like a field; the contrast between a blind corridor and a hall opening up is the
##   whole sensation this model is for.
## * **A dungeon is several floors, descended one way.** Smaller floors, more of them,
##   the boss on the last. The budget is SPLIT across them, so this changes a
##   dungeon's shape and never its cost.
## * **What you walk to is a chest, and what opens it is also on the floor.** A treasure
##   tile is one of D84's chests, with its own tier and its own lock; the keys that open
##   the locked ones lie on the floors as well, placed as far from everything else as the
##   floor allows (D167). So covering ground pays without this model needing a lock of its
##   own. It had one for a while (a sealed dead-end room) and D86 removed it: two locks and
##   two key currencies for one idea.
##
## There is no torch. There was, until D77: a step allowance with an HP overdraft fee
## which never changed what the player could see, and which charged them for the one
## thing this model exists to sell. Greed is paid for in exposure instead — turns
## spent are turns the wanderers also take, fights are loud, and a floor you linger on
## wakes up.
##
## Balance contract: the stair is placed as far from the entrance as the floor allows
## and is hidden until you walk near it, and `options()` orders it LAST while anything
## is unresolved — which is the safe default for a player leaning on the first button
## and what makes the headless walkers spend a floor instead of beelining. Wanderers
## are taken OUT of the combat budget rather than added to it, and floors split that
## budget rather than multiplying it, so a difficulty rating still means one thing.
## `tests/test_traversal.gd` also bounds MOVES per encounter, because a spatial model
## can bury the card game with walking while every encounter count stays perfect.
##
## Pure logic, as the contract in `traversal.gd` requires: it never reads or writes run
## resources. That is what lets one headless walker in `tools/sim_balance.gd` drive it.
class_name TraversalIso
extends Traversal

## Cell contents. Anything >= 0 is an Enc value waiting to be resolved; everything
## below is terrain or a feature.
const WALL := -2    ## not a floor tile: solid rock
const EMPTY := -1   ## walkable ground with nothing on it
const STAIR := -3   ## the way down to the next floor (never on the last one)
## A key lying on the ground, picked up by walking onto it (D167).
##
## Terrain rather than an encounter, and that is what keeps the budget honest: it is
## negative, so it is outside `content` and outside `quota`, and a floor that scatters
## three of them still costs what its difficulty says it costs.
const KEY := -4
## A stone that takes something (D188). Terrain like `KEY`, and negative for the same reason:
## it is outside `content` and outside `quota`, so a floor holding one still costs what its
## difficulty says. Standing on it does nothing; the OPTION beside it is the decision.
const SHRINE := -5

## Grid steps, and the screen direction each one reads as once the floor is drawn
## at an angle. The arrows are the projected directions, not compass ones: a floor
## turned 45 degrees would otherwise tell the player "north" and move them
## down-right.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIR_ARROW := ["↘", "↖", "↙", "↗"]

var w: int = 0
var h: int = 0
## w*h cells: WALL, EMPTY, a feature, or an Enc value.
##
## Packed, not a Variant `Array`, and so are the three grids below. `enc[n] == WALL` is
## the innermost line of every flood over the floor and those floods are most of a
## headless run (D99); a packed array reads an int where a Variant array unboxes one.
##
## They are packed IN MEMORY ONLY. `_save` unpacks the two byte grids back to plain
## Arrays because `JSON.stringify` does not know `PackedByteArray` and silently writes
## `str()` of it — the string `"[1, 0, 1]"` where the reader expects numbers (D140).
## `PackedInt32Array` does round-trip as numbers, so `enc` and `room_of` go as they are.
var enc := PackedInt32Array()
var seen := PackedByteArray()   ## w*h flags: ground you have been near
## w*h bools: ground you have actually STOOD on. Distinct from `seen` because this is
## a model about coverage, and on a floor that is mostly open ground "have I been
## here?" is the question the player is actually asking — when every tile held an
## encounter its contents answered it, and now four exits in a row all read
## "Open ground" unless something tells them apart.
var walked := PackedByteArray()
## w*h ints: which chamber a tile belongs to, or -1 for a corridor. Drives the
## reveal, and is what lets the view tell a hall from a passage.
var room_of := PackedInt32Array()
## cell -> enemy archetype id, for the tiles that hold a fight. Decided when the floor is
## laid out rather than when the fight starts, because the thing STANDING there has to be
## the thing you end up fighting: before this the sprite was an arbitrary index and the
## enemy was rolled at combat setup, so the floor was showing the player a creature that
## had nothing to do with what came next (D85).
var enemy_of: Dictionary = {}
## cell -> pack tier, for the tiles that hold a chest. The same idea one noun over (D172):
## a chest's tier IS its lock (`Balance.chest_lock`), so a tier decided at the lid is a lock
## the player could not have seen from the doorway — and since D167 the answer to a key lock
## is a detour, which is a decision that has to be available BEFORE the turn is spent.
var chest_of: Dictionary = {}
## w*h: 0 for a bare cell, else 1 + an index into this floor's terrain prop list (D176).
##
## PURELY COSMETIC, and that is a rule and not a description. A prop never occupies a tile
## that holds an encounter, a key, the way on or the entrance; it never changes
## walkability; and nothing in `options()`, `_describe` or any flood reads it. The floor
## has spent three decisions teaching the player that what is drawn on a tile is what they
## get — the creature (D85), the chest's tier (D172) — and a decoration that could be
## mistaken for any of that would undo all three at once. What is in the table is ground
## clutter, wall dressing and light; there is deliberately no crate that reads as a chest.
##
## Generated with the floor and saved with it, so a resumed run is the same room. Packed
## for the same reason `enc` is: the view indexes it per tile per frame.
var props := PackedInt32Array()
## One role per chamber, indexed like `room_of` — what that room WAS (D176). Rolled from
## the style's own weights at placement, and read only by the dressing: role is not a
## placement hint for anything, because it has to prove it is free of balance consequence
## before an encounter is ever put anywhere by it.
var room_role: Array = []
## A few sources of light per floor, each {"cell": int, "warm": bool}. Warm ones are fire
## and stand in a room; cold ones come from above and stand where the roof failed.
##
## Placed by the model rather than derived by the view because they are part of the floor:
## a resumed run has to be the same room in the same light, and a view that rolled its own
## would relight the floor on every refresh.
var lights: Array = []
## The cell holding this floor's landmark, or -1, and which of `Balance.ISO_LANDMARKS` it
## is (D177). Rock, always — see `_place_landmark`.
var landmark: int = -1
var landmark_kind: int = 0
## Sealed pockets on this floor (D182), each
## {"mouth": int, "cells": Array[int], "prize": String, "open": bool}.
##
## A pocket is a DEAD END and that is a rule rather than a description: `cells` are all rock
## until it is pushed open, `mouth` is the only one of them that touches walkable ground, and
## every other cell was grown only through rock with no walkable neighbour at all. So the
## floor's connectivity is identical with every pocket sealed and with every pocket open —
## which is what stops the feature from being a skip (D88), and what
## `tests/test_traversal.gd` asserts rather than assumes (D86 asserted the same shape about
## zero generated vaults and was green for a milestone).
##
## Nothing in here is ever required. `_dist_to_unresolved` does not seed from a pocket and
## the unresolved count does not include one, so the greedy walker cannot see a pocket and
## the required path is exactly what it was.
var pockets: Array = []
## This floor's errand, or "" (D184). Decided per DUNGEON at `generate()` like everything
## else, held per floor in `errandplan`, and judged the moment the stairs are taken.
var errand: String = ""
## What the floor has done toward it. Two flags and a count, all of them things the model was
## already in a position to know — the plan's rule for a debt's conditions applies here too:
## if a condition needs new bookkeeping, it is the wrong condition.
var errand_seen: bool = false      ## caught in the open on this floor
## ...and ever, anywhere in this dungeon (D191). A debt asks about the RUN, not the floor, and
## `errand_seen` is reset every time you descend — so the run-scoped fact needs its own flag
## rather than a reader remembering to check before the reset.
var caught_ever: bool = false
var errand_chests: int = 0         ## chests still shut on this floor
var errand_pushed: bool = false    ## a wall pushed on this floor
## Was the errand settled by the descent just taken? Reported exactly as `picked_key` is and
## never saved: a traversal owns no run resources (D13), so the gold is paid by whoever owns
## the purse and this is the only channel that can tell them.
var errand_paid: String = ""
## Did the step just taken answer a toll, and was it right (D186)? "" / "right" / "wrong".
## Reported and never saved, exactly as `picked_key` and `errand_paid` are: the model knows
## what happened and the caller owns the HP.
var toll_result: String = ""
var errandplan: Array = []
## What this dungeon is wearing this time (D187), or "" the first time through.
##
## Set by the CALLER before `generate()`, never read from `MetaState` here: a traversal is
## pure logic and owns no meta state (D13), and the simulator has to be able to measure a
## dungeon in every aspect without pretending to have cleared it. `GameState.build_traversal`
## is the one place that asks how many times this dungeon has been beaten.
var aspect: String = Balance.ASPECT_NONE
## Entered by the back door (D190): the same dungeon, one floor shorter, with the whole budget
## packed into what is left. Set by the caller before `generate()`, like `aspect`.
var deep: bool = false
## What THIS floor is doing, until you take the stairs (D188). "" until a stone is paid.
##
## Deliberately the same vocabulary as `aspect`: `_sight` and `_linger` read whichever of the
## two is set, so a floor state costs no new machinery and inherits the budget-neutrality
## argument the aspects already carry.
var floor_state: String = Balance.ASPECT_NONE
## Which stone on this floor is still unpaid, or -1.
var shrine: int = -1
## Was a stone paid by the step just taken (D188)? Reported and never saved, like
## `picked_key`: the model knows what happened and the caller owns the HP and the purse.
var shrine_paid: String = ""
## What each floor's pockets hold, decided at `generate()` with everything else (D182).
## `pocketplan[i]` is one prize string per pocket on floor i, so the count and the contents
## of every pocket in the dungeon are decided in ONE place — D172's rule, whose scar is a
## chest tier estimated in one place and rolled in another.
var pocketplan: Array = []
## Cells holding an optional SITE — an event standing in the open that the floor never asks
## you to resolve (D185). Kept as its own list rather than inferred from the tiles, because
## the tile of a site and the tile of a budgeted event are the same tile: what separates them
## is whether the dungeon counted it, and that is a fact about the plan, not about the floor.
var sites: Array = []
## Which terrain and which architecture THIS floor came out as. Recorded rather than
## re-derived: since D177 they vary by depth inside one dungeon, and the view, the props
## and a restored save must all agree on one answer. A second derivation is the D34 trap.
var terrain: String = Balance.ISO_TERRAIN_DEFAULT
var style_name: String = Balance.ISO_STYLE_DEFAULT
var pos: int = 0        ## cell the player stands in
var tiles: int = 0      ## walkable tiles on THIS floor
var content: int = 0    ## encounters on this floor's tiles, its stair included
var rooms: int = 0      ## chambers on this floor

## Everything the whole dungeon will ask of you: every floor's encounters, the boss,
## and the wanderers. The progress denominator — NOT the same as `content`, which is
## one floor's worth.
var quota: int = 0
var steps: int = 0        ## turns taken in the dungeon, for the status line
var floor_steps: int = 0  ## turns taken on THIS floor, for the linger rule
## Hunters shaken off rather than fought. Counts for the whole dungeon, not the floor,
## because the price rises with each one and a fresh floor is not a fresh start — the same
## shape the old deck model's `avoided` had, and for the same reason.
var avoided: int = 0
## How many fights this dungeon offers a break-away from, across all its floors. Decided
## once, at generation, because the PRICE of each is solved from the total (see
## `Balance.avoid_cost`) and a price that changed as you resolved encounters would make
## the first one cheaper the longer you put it off.
##
## Since D197 that is simply every fight the dungeon holds: they all walk, so they can all
## come within reach, so they can all be declined. It was the standing fights only, with the
## wanderers subtracted — and counted HERE rather than derived from the mix by whoever needs
## it, because deriving it a second time somewhere else is how the number went stale the
## first time (D99). That reason is unchanged and is why this field still exists.
var dodgeable: int = 0
var done: bool = false

## Floors, and what is still to be laid out on the ones not yet reached. `plan[i]` is the
## list of Enc values floor i STANDS on tiles and `roam[i]` the list it puts on its feet;
## both are consumed by `_build_floor`. Held here rather than generated per floor so the whole
## dungeon's budget is decided once, up front, and cannot drift as you descend.
##
## `roam` holds Enc values and not a count, since D197: every fight walks now, elites
## included, and a count could only ever have said "this many combats".
var floors: int = 1
var depth: int = 0
var plan: Array = []
var roam: Array = []
## What tier each of a floor's chests is, decided up front like everything else here:
## `chestplan[i]` is one tier string per TREASURE in `plan[i]` (D172). Consumed by
## `_cast_chests` when the floor is laid out.
##
## Up front rather than when the chest is entered, for the reason D85 cast the fights up
## front: the floor has to be able to SHOW what is standing on it. A tier rolled at the
## moment the lid is reached cannot be drawn on the tile you are deciding whether to walk
## to, and a lock you cannot see is not a decision, it is a toll.
var chestplan: Array = []
## Keys to scatter on each floor, decided with the rest of the dungeon (D167). Exactly one
## per key-locked chest on that floor (D172) — counted off `chestplan`, not estimated from
## the odds that produced it — and dealt to that same floor, because a floor is re-walkable
## and a floor you have left is not.
var keyplan: Array = []

## Did the step just taken pick a key up off the floor? Read by the view immediately
## after `select()` and never saved: the model has no run resources to add it to (D13),
## so the pickup is REPORTED here exactly as an ambush's HP price is reported on the
## encounter, and whoever owns the keys does the adding.
var picked_key: bool = false

## Things walking the floor. Each is
## {"cell": int, "type": Enc, "design": int, "south": bool, "pen": int}.
## An entry is removed when its fight is won, or when you break away from it.
##
## There is no `awake` any more (D197). Every one of these hunts you from the turn the floor
## is laid down: a monster that had not noticed you was the only thing on this floor that was
## not playing, and it made the first half of every floor a walk rather than a chase.
##
## `pen` is -1 for anything hunting the open floor, or the index of the pocket a guard is
## penned into (D183). A guard is defined by standing between you and a prize, so it hunts
## you exactly as hard as anything else and never leaves the room it is guarding — which is
## how it can both move and still be a wall.
##
## `design` and `south` are for the VIEW and carry no rules: a stable design per
## wanderer so three of them on one floor do not read as one monster cloned, and a
## facing so a thing walking away from you shows you its back. They live here rather
## than in the view because the view is rebuilt on every refresh and a monster's
## identity has to survive that — and a save.
var mons: Array = []

func generate(p_dungeon) -> void:
	_invalidate()
	dungeon = p_dungeon
	cleared = 0
	pending = {}
	done = false
	steps = 0
	avoided = 0
	w = Balance.ISO_GRID
	h = Balance.ISO_GRID

	var budget := standard_encounters(dungeon)
	# EVERY fight walks (D197). Nothing in this model waits on a tile to be walked into any
	# more, so the budget is split in two here — what the floor stands still (rests, shops,
	# events, chests, the stair, the boss) and what hunts you — rather than a fraction of the
	# combats being lifted onto their feet. Still out of the same budget and never on top of
	# it: a dungeon has to cost what its difficulty says (D14).
	var hunters: Array = []
	var standing: Array = []
	for e in budget:
		if int(e) == Enc.COMBAT or int(e) == Enc.ELITE:
			hunters.append(int(e))
		else:
			standing.append(int(e))
	budget = standing

	var diff: int = dungeon.difficulty if dungeon != null else 1
	floors = Balance.iso_floors_for(diff)
	# The back door takes a floor off and gives nothing back (D190). The budget below is not
	# touched, so the same encounters are dealt over fewer floors and `iso_tiles_per_floor`
	# divides the same tile allowance fewer ways: a shorter, denser dungeon that costs exactly
	# what its difficulty says. Never below the minimum — a one-floor dungeon has no descent,
	# and descent is the model.
	if deep:
		floors = maxi(Balance.ISO_FLOORS_MIN, floors - Balance.DEEP_ENTRY_FLOORS)
	# The budget is SPLIT across the floors, not repeated on each. Dealing it round
	# robin after a shuffle keeps every floor mixed — dealing it in order would put
	# all the combats on floor one and all the shops on the last.
	budget.shuffle()
	hunters.shuffle()
	plan = []
	roam = []
	for f in floors:
		plan.append([])
		roam.append([])
	for i in budget.size():
		plan[i % floors].append(int(budget[i]))
	# Dealt round robin like the rest, and the elites land wherever they land. There is no
	# longer a reason to keep them off the early floors as landmarks: an elite that walks is
	# not a landmark, it is the thing you can hear coming.
	for i in hunters.size():
		(roam[i % floors] as Array).append(int(hunters[i]))
	# `Walked` puts one more hunter on every floor (D187, rewritten in D197). It is the one
	# aspect that is no longer budget-neutral — there is nothing standing still left to take
	# it from — so it is counted into `quota` and paid for in gold like any other optional
	# difficulty.
	if aspect == Balance.ASPECT_CROWDED:
		for f in floors:
			for k in Balance.ASPECT_EXTRA_WANDERERS:
				(roam[f] as Array).append(Enc.COMBAT)
	var roaming := 0
	for row in roam:
		roaming += (row as Array).size()
	# Everything a hunter can be broken away from — which is now every fight in the dungeon.
	# The boss is not in `budget`, does not walk and can never be declined. Counted after the
	# aspect, because `Balance.avoid_cost` solves the whole ladder from this number and a
	# dungeon wearing `Walked` offers more rungs of it.
	dodgeable = roaming
	# +1 for the boss, which sits on the last floor and is not in `budget`
	quota = budget.size() + roaming + 1
	_plan_chests(diff)
	# Deliberately NOT added to `quota`. A pocket is outside what the dungeon asks of you, so
	# counting one would make a player who finds none unable to reach 1.0 — and not counting
	# one is what keeps "this dungeon costs what its difficulty says" true (D182).
	_plan_pockets()
	# After the pockets, because a floor cannot be asked to find one it does not have (D184).
	_plan_errands()

	_build_floor(0)

## Roll every chest's tier, and then put exactly one key on the floor for every chest whose
## tier is a key lock (D172).
##
## The key count is COUNTED, not estimated. D167 sized it from the sealed weight in
## `pack_tier_odds` — the right answer while the tier was still rolled at the lid, and the
## D34 trap the moment it stopped being: two places deciding how many locks a dungeon has,
## free to disagree. Now the locks are known here, so the answer is the locks themselves.
##
## Which also fixes what the estimate could not. It was clamped to at least one key and at
## most one per chest, so a dungeon that rolled no key lock still scattered a key nobody
## needed, and one that rolled three could be handed two. Both of those are the same defect
## from opposite sides: the player cannot tell a lock they can answer from one they cannot.
## Every key lock on a floor now has its key on that floor, and a floor with no key lock has
## no key on it.
func _plan_chests(diff: int) -> void:
	chestplan = []
	keyplan = []
	for f in floors:
		chestplan.append([])
		keyplan.append(0)
	for f in floors:
		for e in plan[f]:
			if int(e) != Enc.TREASURE:
				continue
			var tier := Balance.roll_pack_tier(Balance.PACK_TREASURE, diff)
			(chestplan[f] as Array).append(tier)
			if Balance.chest_lock(tier) == Balance.CHEST_LOCK_KEY:
				keyplan[f] += 1

## Decide how many pockets each floor has and what is in each of them (D182).
##
## Here, at `generate()`, beside `_plan_chests`, and for the same reason: D172's scar is a
## number estimated in one place while being rolled in another, free to disagree. One place
## decides how many pockets a dungeon holds and what is behind every wall in it, and
## `tests/test_traversal.gd` asserts the planned count equals the placed count on every
## floor — which is the only version of this that cannot drift.
## The per-run cap on guards is enforced HERE, where the whole dungeon is in view (D183). It
## cannot be enforced per floor: three floors each rolling "two thirds guarded" independently
## is a dungeon that sometimes holds five voluntary elites, and every budget assertion in the
## suite would stay green while it did.
## Which floors ask something of you (D184). Rolled with the rest of the dungeon, so a floor's
## ordinance is a fact about the place rather than something that appears when you arrive.
##
## The `pushed` errand is only ever given to a floor that actually HAS a pocket. An ordinance
## nobody can settle is not a hard errand, it is a lie, and the floor knows at planning time
## whether it planned one — which is the whole reason `_plan_pockets` runs first.
func _plan_errands() -> void:
	errandplan = []
	for f in floors:
		if randi() % 100 >= Balance.ERRAND_PCT:
			errandplan.append("")
			continue
		var pool: Array = []
		for e in Balance.ERRANDS:
			if String(e) == Balance.ERRAND_PUSHED \
					and (f >= pocketplan.size() or (pocketplan[f] as Array).is_empty()):
				continue
			pool.append(String(e))
		errandplan.append(String(pool[randi() % pool.size()]) if not pool.is_empty() else "")

func _plan_pockets() -> void:
	pocketplan = []
	var guards := 0
	for f in floors:
		var row: Array = []
		for k in Balance.roll_pocket_count():
			var prize := Balance.roll_pocket_prize()
			var guarded: bool = Balance.pocket_guardable(prize) \
				and guards < Balance.POCKET_GUARDS_PER_RUN \
				and randi() % 100 < Balance.POCKET_GUARD_PCT
			if guarded:
				guards += 1
			# ...and some are shut with a lock rather than hidden behind a mark (D185). A
			# door is a different verb from a crack: you can see it across a room, and it
			# wants the key the floor already scatters rather than a turn spent pushing.
			var lock: String = Balance.POCKET_LOCK_KEY \
				if randi() % 100 < Balance.POCKET_LOCK_PCT else Balance.POCKET_LOCK_NONE
			# ...and some are shut with a QUESTION instead (D186). Exclusive with the lock:
			# a mouth asks for one thing, and a door that also asked a riddle would be two
			# prices for one pocket.
			var toll := ""
			if lock == Balance.POCKET_LOCK_NONE and randi() % 100 < Balance.TOLL_PCT:
				toll = String(Balance.TOLLS[randi() % Balance.TOLLS.size()])
			row.append({"prize": prize, "guard": guarded, "lock": lock, "toll": toll})
		pocketplan.append(row)

## How many of this dungeon's pockets were planned with something standing in them (D183).
## Read by `tests/test_traversal.gd` to check the cap is asserted rather than assumed, and by
## nothing in the game: a count of guards is not a fact the player is told.
func planned_guards() -> int:
	var n := 0
	for row in pocketplan:
		for e in row:
			if bool((e as Dictionary).get("guard", false)):
				n += 1
	return n

## Lay out one floor and stand the player at its entrance. Called by `generate` for
## floor 0 and by `select` on every descent, which is why every per-floor field is
## reset here rather than in `generate`.
func _build_floor(d: int) -> void:
	_invalidate()
	depth = clampi(d, 0, floors - 1)
	floor_steps = 0
	_room_cells = []
	mons = []
	enemy_of = {}
	chest_of = {}
	room_role = []
	lights = []
	pockets = []
	sites = []
	shrine = -1
	floor_state = Balance.ASPECT_NONE
	var n_cells := w * h
	props.resize(n_cells)
	props.fill(0)
	enc.resize(n_cells)
	enc.fill(WALL)
	seen.resize(n_cells)
	seen.fill(0)
	walked.resize(n_cells)
	walked.fill(0)
	room_of.resize(n_cells)
	room_of.fill(-1)

	# What this floor is cut in and made of, decided ONCE and kept, because a dungeon's
	# floors differ from each other since D177 and everything downstream — the props, the
	# view's surface art, a resumed save — has to read the same answer.
	var did := String(dungeon.id) if dungeon != null else ""
	style_name = Balance.iso_style_name(did, depth, floors)
	terrain = Balance.iso_terrain(did, depth, floors)
	var style: Dictionary = Balance.ISO_STYLES[style_name]
	var rects := _place_rooms(style, Balance.iso_tiles_per_floor(floors))
	rooms = rects.size()
	_connect(rects, style)
	var carved: Array = []
	for i in enc.size():
		if int(enc[i]) != WALL:
			carved.append(i)
	tiles = carved.size()

	# The entrance is a CHAMBER tile — you arrive in a room, not in a passage — and of
	# those, the one the floor stretches furthest from, so the stair cannot end up two
	# steps away and the whole floor be skippable by walking into it. At least two
	# exits, because a first move with one option is not a move.
	#
	# This floods from EVERY candidate — around forty per floor, and the single most
	# expensive thing in generation. Deliberately left exact (D99). The cheap answer is
	# a double sweep (flood anywhere, take the furthest tile, flood from that), which
	# costs two floods instead of forty and picks a *different* tile: it would move
	# every entrance in the game, reshape every floor and move every balance number
	# measured against them. A 10%-of-a-run saving is not worth silently regenerating
	# the content. What made it affordable instead is that each flood is now cheap.
	pos = int(carved[0])
	var best := -1
	for c in carved:
		var i := int(c)
		if int(room_of[i]) < 0:
			continue
		var exits := 0
		for n in _neighbours(i):
			if int(enc[n]) != WALL:
				exits += 1
		if exits < 2:
			continue
		var reach := _dist_from(i)
		var ecc := 0
		for j in enc.size():
			if int(reach[j]) > ecc:
				ecc = int(reach[j])
		if ecc > best:
			best = ecc
			pos = i

	# The way on goes in the furthest tile from the entrance, preferring a chamber so
	# arriving at it feels like arriving somewhere. On the last floor that is the boss;
	# on every other it is a stair down.
	var dist := _dist_from(pos)
	var far: int = pos
	var far_room: int = -1
	for c in carved:
		var i := int(c)
		if int(dist[i]) > int(dist[far]):
			far = i
		if int(room_of[i]) >= 0 and (far_room < 0 or int(dist[i]) > int(dist[far_room])):
			far_room = i
	var exit_cell: int = far_room if far_room >= 0 else far
	enc[exit_cell] = Enc.BOSS if depth == floors - 1 else STAIR

	var mine: Array = (plan[depth] as Array).duplicate()
	_place_spread(mine, carved, [pos, exit_cell])
	_spawn((roam[depth] as Array) if depth < roam.size() else [], carved, dist)
	_cast_fights()
	_cast_chests()
	# Keys go down LAST, so they take the ground nothing else wanted — which is the
	# whole mechanic: a key is somewhere you would not otherwise have walked.
	# Pockets are cut from the rock the floor did NOT use, after everything the floor asks
	# of you is already standing on it (D182). Late for two reasons: the tiles must not come
	# out of the floor's own budget, and a mouth has to be chosen against the finished
	# shape — which walls are actually walls, and how far from the entrance each one is.
	_carve_pockets(int(pocketplan[depth].size()) if depth < pocketplan.size() else 0, dist)
	# ...and an optional thing or two standing in the open, off the route (D185).
	_place_sites(carved, dist)
	_place_shrine(carved, dist)
	# Keys go down after the pockets, so a DOOR's key is only placed when the door was
	# actually carved (D185). The count is chest locks plus door locks: one key per lock on
	# the floor, which is D172's invariant with a second kind of lock in it rather than a
	# second key currency beside it. Counting PLANNED doors instead would leave "a key with
	# no lock" whenever carving ran out of dead rock, which is the litter the D167 test was
	# written to catch.
	_place_keys((int(keyplan[depth]) if depth < keyplan.size() else 0)
		+ _locked_mouths(), carved)
	# ...and the dressing goes down after even the pockets, which is what lets its own rule
	# be absolute: nothing decorative can land on a tile that holds something, because by
	# now everything that holds something is already there (D176).
	_dress_floor(carved, dist)

	content = 0
	for i in enc.size():
		if int(enc[i]) >= 0:
			content += 1

	# This floor's ordinance, and the state it is judged on (D184). Counted off the tiles
	# actually laid down rather than off the plan: a chest that found no ground to stand on
	# is a chest the player cannot open, and an errand that asked for it would be unsettleable
	# through no fault of theirs.
	errand = String(errandplan[depth]) if depth < errandplan.size() else ""
	errand_seen = false
	errand_pushed = false
	errand_chests = 0
	for i in enc.size():
		if int(enc[i]) == Enc.TREASURE and not _in_pocket(i):
			errand_chests += 1
	# ...and an errand asking for every lid on a floor with no lids is settled by turning up,
	# which is not an errand. Dropped rather than swapped: the floors that ask are meant to be
	# some of them, and one fewer is the honest outcome.
	if errand == Balance.ERRAND_THOROUGH and errand_chests == 0:
		errand = ""

	walked[pos] = true
	_reveal_around(pos)

# --- generation ---------------------------------------------------------------

## Scatter chambers over the plate, keeping at least one tile of rock between any
## two so walls exist to see. Rejection sampling rather than a grid subdivision,
## because a subdivision gives every floor the same skeleton and the whole point of
## the style table is that two dungeons should not share a skeleton.
##
## A 1-tile margin at the plate edge is deliberate: the view only draws rock that
## walls in known ground, so a chamber flush against the edge would have no wall
## drawn on that side and read as the floor falling away into nothing.
## `target` is the floor's tile budget. Chambers are added until they cover most of it
## (corridors make up the rest), which is what makes floor size fall as floor count
## rises — a four-floor dungeon is four SMALL floors, and that is the whole reason the
## pacing survives being deeper. Fixing the room count instead measured 8.6 moves per
## encounter against a 7.5 ceiling.
func _place_rooms(style: Dictionary, target: int) -> Array:
	var wr: Array = style["w"]
	var hr: Array = style["h"]
	var rr: Array = style["rooms"]
	var floor_min: int = int(rr[0])
	var floor_max: int = int(rr[1])
	# How much of the floor is chamber rather than corridor — per style, because it is the
	# thing the eye reads first. The corridors are dug afterwards so their length cannot be
	# known here; a low `fill` therefore means fewer chambers spread over the same plate,
	# which is exactly what makes a warren corridor-heavy.
	var rubble: float = clampf(float(style.get("rubble", 0.0)), 0.0, 0.5)
	# Grossed UP by whatever the rubble is going to take back out again (D177), so a
	# collapsed floor is the same SIZE as an intact one. Without this a style that eats a
	# fifth of its own chamber area produces a floor a fifth smaller, and floor size is
	# the thing `ISO_MOVES_PER_ENCOUNTER_MAX` is measured against — a purely visual knob
	# would have quietly moved the pacing of every dungeon's bottom floor.
	var room_area: int = int(round(float(target) * float(style.get("fill", 0.75))
		/ maxf(0.5, 1.0 - rubble)))
	var align: int = int(style.get("align", 0))
	var area := 0
	var out: Array = []
	var guard := 0
	while out.size() < floor_max and guard < 400:
		guard += 1
		if out.size() >= floor_min and area >= room_area:
			break
		var rw: int = int(wr[0]) + (randi() % maxi(1, int(wr[1]) - int(wr[0]) + 1))
		var rh: int = int(hr[0]) + (randi() % maxi(1, int(hr[1]) - int(hr[0]) + 1))
		# a long room is as likely to run the other way; without this every gallery
		# dungeon comes out combed in the same direction
		if randi() % 2 == 0:
			var t := rw
			rw = rh
			rh = t
		if rw + 2 >= w or rh + 2 >= h:
			continue
		var x: int = 1 + (randi() % (w - rw - 1))
		var y: int = 1 + (randi() % (h - rh - 1))
		# Snapped to a lattice for the styles that want to look CUT rather than dug.
		# Regularity is a signature that no amount of size variation provides, and it is
		# what finally told `cells` apart from `warren` by eye.
		if align > 1:
			x = clampi(1 + int(round(float(x - 1) / float(align))) * align, 1, maxi(1, w - rw - 1))
			y = clampi(1 + int(round(float(y - 1) / float(align))) * align, 1, maxi(1, h - rh - 1))
		var r := Rect2i(x, y, rw, rh)
		var clash := false
		for o in out:
			if _too_close(r, o):
				clash = true
				break
		if clash:
			continue
		out.append(r)
		area += rw * rh
	# Fewer than two chambers is not a floor. It cannot happen at the shipped sizes on
	# a 12x12 plate, and the contract test asserts it, but a floor with one room would
	# have no corridors and an entrance with no second exit — so fail loudly-ish by
	# carving the plate's middle rather than producing something unwalkable.
	if out.size() < 2:
		out.append(Rect2i(1, int(h / 2) - 1, 3, 2))
		out.append(Rect2i(w - 5, int(h / 2) - 1, 3, 2))
	room_role = []
	for i in out.size():
		var r: Rect2i = out[i]
		for yy in range(r.position.y, r.end.y):
			for xx in range(r.position.x, r.end.x):
				var c: int = yy * w + xx
				enc[c] = EMPTY
				room_of[c] = i
		# What this chamber WAS, rolled from the style's own weights (D176). Assigned at
		# placement rather than afterwards so it is a property of the room and not of
		# whatever ended up standing in it.
		room_role.append(Balance.iso_roll_room_role(style))
		if rubble > 0.0:
			_rubble(r, rubble)
	return out

## Put the roof back in one corner of a chamber, turning a rectangle into an L or a U.
##
## A CORNER BITE and not speckle, deliberately. Scattering single tiles of rock through a
## room reads as a broken floor rather than as a collapse, and it fragments the chamber
## into pockets the digger then has to find its way back into. One rectangle out of one
## corner gives the shape the style is named for and leaves the rest of the room in one
## piece — the corner you cannot see into from the door is the whole point.
##
## The centre is never taken: `_connect` digs to it, and while `_dig` would simply re-open
## the tile, a room whose middle is rock is a room whose corridor arrives in its wall.
func _rubble(r: Rect2i, frac: float) -> void:
	if r.size.x < 2 or r.size.y < 2:
		return
	# Not every room, or "collapsed" stops being a reading and becomes the floor plan.
	if randi() % 4 == 0:
		return
	var want: int = maxi(1, int(round(float(r.size.x * r.size.y) * frac)))
	# The bite is as square as the room allows, so it eats a corner rather than shaving
	# a side off — a one-tile strip off an edge is invisible at this tile size.
	var bw: int = clampi(int(ceil(sqrt(float(want)))), 1, r.size.x - 1)
	var bh: int = clampi(int(ceil(float(want) / float(bw))), 1, r.size.y - 1)
	var corner := randi() % 4
	var ox: int = r.position.x if corner % 2 == 0 else r.end.x - bw
	var oy: int = r.position.y if corner < 2 else r.end.y - bh
	var mid := _centre(r)
	for yy in range(oy, oy + bh):
		for xx in range(ox, ox + bw):
			if xx == mid.x and yy == mid.y:
				continue
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var c: int = yy * w + xx
			enc[c] = WALL
			# ...and it stops belonging to the room, or the reveal would open a room
			# whole including the rock in it and `room_cells` would hand the view tiles
			# that are not floor.
			room_of[c] = -1

## True if `a` grown by one tile overlaps `b` — i.e. the two rooms would touch or
## merge. Written out rather than using Rect2i.intersects on a grown rect, because
## whether that call counts a shared border is exactly the kind of detail that
## silently fuses two chambers into one L-shaped blob.
func _too_close(a: Rect2i, b: Rect2i) -> bool:
	return a.position.x - 1 < b.end.x and b.position.x < a.end.x + 1 \
		and a.position.y - 1 < b.end.y and b.position.y < a.end.y + 1

## Join the chambers: a spanning path first so the floor is certainly connected, then
## `loops` extra links. The loop count is what makes a style feel different to walk —
## zero is a tree where every dead end costs a double walk, three is somewhere you can
## come round behind a thing that is chasing you.
## A style with `spine` set is joined the other way (D177): one arterial corridor across
## the plate, and every chamber a spur off it. That is a different WALK, not a different
## room — on a chain every room leads to the next, so the floor is a rope you pull along;
## off a spine every room is a decision to leave the road and come back to it. It is also
## what makes `ranks` read as ranks: ten small cells in a chain is a warren, and ten small
## cells hung off one corridor is a barracks.
func _connect(rects: Array, style: Dictionary) -> void:
	if rects.size() < 2:
		return
	var loops: int = int(style.get("loops", 0))
	if bool(style.get("spine", false)):
		# Along the plate's long axis, one tile off the middle so it is not a mirror line —
		# a corridor exactly down the centre of a square plate makes both halves the same
		# picture. On a square grid the axis is chosen per floor, so a spine dungeon is not
		# combed one way for its whole depth.
		var across: bool = randi() % 2 == 0
		var lane: int = int(h / 2) + (randi() % 3) - 1 if across else int(w / 2) + (randi() % 3) - 1
		lane = clampi(lane, 1, (h if across else w) - 2)
		var a0 := Vector2i(1, lane) if across else Vector2i(lane, 1)
		var a1 := Vector2i(w - 2, lane) if across else Vector2i(lane, h - 2)
		_dig(a0, a1)
		for r in rects:
			var mid := _centre(r)
			_dig(mid, Vector2i(mid.x, lane) if across else Vector2i(lane, mid.y))
	else:
		for i in range(1, rects.size()):
			_dig(_centre(rects[i - 1]), _centre(rects[i]))
	for l in loops:
		var a: int = randi() % rects.size()
		var b: int = randi() % rects.size()
		if a != b:
			_dig(_centre(rects[a]), _centre(rects[b]))
	_ensure_connected()

## Dig whatever the passes above left stranded back onto the floor.
##
## The spanning chain could never strand anything, so nothing needed this until two styles
## arrived that can (D177): rubble cuts a chamber into pieces, and a spine reaches a room's
## centre without reaching a corner the rubble separated from it. `tests/test_traversal.gd`
## asserts every carved tile is reachable from the entrance, so the failure mode is a red
## test rather than an unfinishable floor — but the honest fix is to join the floor up, not
## to stop making shapes that can come apart.
##
## Joins rather than deletes, deliberately. Filling a stranded pocket back in would be
## cheaper and would shrink the floor, and floor size is what the pacing bound is measured
## against.
func _ensure_connected() -> void:
	var guard := 0
	while guard < 8:
		guard += 1
		var start := -1
		for i in enc.size():
			if int(enc[i]) != WALL:
				start = i
				break
		if start < 0:
			return
		var reach := _dist_from(start)
		var orphan := -1
		for i in enc.size():
			if int(enc[i]) != WALL and int(reach[i]) < 0:
				orphan = i
				break
		if orphan < 0:
			return
		# Straight at the nearest tile of the main body. `_dig` only turns rock into floor,
		# so this cannot cut through a chamber's `room_of` and cannot delete anything.
		var best := -1
		var best_d := 1 << 30
		var ox: int = orphan % w
		var oy: int = int(orphan / w)
		for i in enc.size():
			if int(reach[i]) < 0:
				continue
			var d: int = absi(i % w - ox) + absi(int(i / w) - oy)
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			return
		_dig(Vector2i(ox, oy), Vector2i(best % w, int(best / w)))

func _centre(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + int(r.size.x / 2), r.position.y + int(r.size.y / 2))

## An L-shaped corridor, one tile wide, with the corner on a coin flip. Corridors are
## dug THROUGH whatever they cross, including chambers — a passage that clips the
## corner of a room is a doorway, and those extra connections are welcome.
##
## Only WALL becomes EMPTY: a corridor must never overwrite a chamber tile's
## `room_of`, or a room would lose part of itself from the reveal and open up in
## pieces as you walked across it.
func _dig(a: Vector2i, b: Vector2i) -> void:
	var at := a
	if randi() % 2 == 0:
		while at.x != b.x:
			at.x += signi(b.x - at.x)
			_open(at)
		while at.y != b.y:
			at.y += signi(b.y - at.y)
			_open(at)
	else:
		while at.y != b.y:
			at.y += signi(b.y - at.y)
			_open(at)
		while at.x != b.x:
			at.x += signi(b.x - at.x)
			_open(at)

func _open(p: Vector2i) -> void:
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
		return
	var c: int = p.y * w + p.x
	if int(enc[c]) == WALL:
		enc[c] = EMPTY

## Scatter `mine` across the floor by farthest-point placement: each encounter goes on
## the free tile whose nearest already-placed piece of content is furthest away.
##
## The reason this is not a shuffle-and-take: a random subset clumps, and three
## encounters in adjoining tiles read as one room with three doors while the open
## ground ends up in a corner nobody visits. Ties go to the lowest cell so a floor
## stays a function of its seed.
func _place_spread(mine: Array, carved: Array, occupied: Array) -> void:
	mine.shuffle()
	var anchors: Array = occupied.duplicate()
	for e in mine:
		# distance to the NEAREST anchor for every tile at once. Asking _dist_from per
		# anchor per candidate is the same answer at O(tiles x anchors x cells) per
		# encounter, which is a third of a second per floor and hundreds of floors in
		# the contract test — a multi-source flood is one pass.
		var gap := _dist_to_any(anchors)
		var pick := -1
		var pick_gap := -1
		for c in carved:
			var i := int(c)
			if int(enc[i]) != EMPTY:
				continue
			if int(gap[i]) > pick_gap:
				pick_gap = int(gap[i])
				pick = i
		if pick < 0:
			break   # cannot happen while the floor fits its share; see test_traversal
		enc[pick] = int(e)
		anchors.append(pick)

## Scatter this floor's keys, as far from everything already on it as the floor allows.
##
## The same spread `_place_spread` uses, and deliberately the LAST thing placed, so a key
## lands in the ground the encounters left over — a dead-end cell, the far corner of a
## chamber nothing else is in. That is what makes fetching one cost turns, which on this
## floor is the only currency there is (the wanderers step whenever you do).
##
## Bare ground only, and never a tile a wanderer is standing on: two things on one tile is
## a picture the view cannot draw, the same rule `_spawn` follows.
##
## And a CHAMBER, preferring one over a corridor by more than distance can outweigh. This
## is the second rule of the floor read forwards (`_reveal_around`): a room is revealed
## whole the moment you set foot in it, and a corridor shows you two tiles. So a key in a
## room is a decision — you walk in, you see it across the floor, you decide whether the
## turns are worth it — and the same key in a blind dead-end is a tile the player never
## learns exists. The far corner of a hall is the shape this wants; the end of a passage
## nobody has a reason to enter is not.
func _place_keys(count: int, carved: Array) -> void:
	if count <= 0:
		return
	var taken := {}
	for m in mons:
		taken[int(m["cell"])] = true
	# Everything already placed is an anchor to get away from — the entrance, the way on,
	# every encounter, and every wanderer.
	var anchors: Array = [pos]
	for i in enc.size():
		var e := int(enc[i])
		if e >= 0 or e == STAIR:
			anchors.append(i)
	for c in taken:
		anchors.append(int(c))
	for k in count:
		var gap := _dist_to_any(anchors)
		var pick := -1
		var pick_score := -1
		for c in carved:
			var i := int(c)
			if int(enc[i]) != EMPTY or taken.has(i):
				continue
			# A chamber tile beats every corridor tile outright, however far away the
			# corridor is: the grid is 12x12, so one floor's worth of distance cannot
			# reach the bonus.
			var score: int = int(gap[i]) + (1000 if int(room_of[i]) >= 0 else 0)
			if score > pick_score:
				pick_score = score
				pick = i
		if pick < 0:
			return   # a floor with no bare ground left; the chest simply stays shut
		enc[pick] = KEY
		anchors.append(pick)

# --- secret pockets (D182) ------------------------------------------------------

## Cut `count` sealed pockets out of the rock this floor did not use.
##
## The dead-end property is built in rather than checked afterwards, and the construction is
## the whole design:
##
## * the **mouth** is a rock cell with exactly ONE walkable neighbour — so there is one way
##   in and it is the tile you pushed;
## * every other cell is grown only through rock with **no walkable neighbour at all** — so
##   no cell of the pocket can become a second door;
## * pockets may not touch each other, or two would merge into a route between two mouths.
##
## Together those mean the floor's connectivity is *identical* sealed and open. That is what
## keeps a pocket from being a skip, and it is asserted in `tests/test_traversal.gd` beside a
## non-zero generated count — D86 asserted exactly this shape about zero generated vaults and
## stayed green for a milestone.
##
## Mouths are ranked by distance from the entrance, furthest first, so a pocket is a detour
## rather than something you fall into on the way past. `dist_from_entry` is the field the
## caller already has.
func _carve_pockets(count: int, dist_from_entry: PackedInt32Array) -> void:
	if count <= 0 or dist_from_entry.size() != enc.size():
		return
	# Every rock cell that could be a mouth: exactly one walkable neighbour, off the plate
	# edge (the view only draws rock that walls in known ground, and an edge cell has no
	# wall drawn on its far side), and not the landmark, which is already spoken for.
	# Where the player can get to without descending. One flood, and the reason it is needed
	# at all is that the way on is NOT always the furthest tile — it prefers the furthest
	# chamber tile, so a corridor dead end can lie beyond it.
	var reach_no_exit := _dist_from_avoiding_exit(pos)
	var cands: Array = []
	for i in enc.size():
		if int(enc[i]) != WALL or i == landmark:
			continue
		var x := i % w
		var y := int(i / w)
		if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
			continue
		var touching := 0
		var far := -1
		var standable := false
		for n in _neighbours(i):
			if int(enc[n]) != WALL:
				touching += 1
				far = maxi(far, int(dist_from_entry[n]))
				# ...and the ONE tile you would have to stand on to push has to be a tile you
				# can actually get to and stand on WITHOUT taking the stairs (D182).
				#
				# Two ways it can fail and both generate a mark nobody in the world can push.
				# The approach may BE the way on — a step onto a stair descends before any
				# push is offered. Or the only route to it may run THROUGH the way on, which
				# happens because the stair is placed on the furthest *chamber* tile and a
				# corridor dead end can lie beyond it.
				#
				# The completionist walker found both, and found them the same way: pacing
				# between two tiles for ever, because the field said "there" and there could
				# not be reached. That is the D74 deadlock for a fourth time, and again the
				# cause is an unreachable destination being seeded as a goal.
				if not _is_exit(n) and int(reach_no_exit[n]) >= 0:
					standable = true
		if touching == 1 and far >= 0 and standable:
			cands.append({"cell": i, "far": far})
	# Furthest from the entrance first, ties by cell so a floor stays a function of its seed.
	cands.sort_custom(func(a, b):
		if int(a["far"]) != int(b["far"]):
			return int(a["far"]) > int(b["far"])
		return int(a["cell"]) < int(b["cell"]))
	var taken := {}
	var prizes: Array = (pocketplan[depth] as Array).duplicate()
	for c in cands:
		if pockets.size() >= count:
			break
		var mouth := int(c["cell"])
		if _pocket_touches(mouth, taken):
			continue
		var want: int = Balance.POCKET_TILES_MIN \
			+ (randi() % maxi(1, Balance.POCKET_TILES_MAX - Balance.POCKET_TILES_MIN + 1))
		var cells := _grow_pocket(mouth, want, taken)
		if cells.is_empty():
			continue
		for cc in cells:
			taken[int(cc)] = true
		var spec: Dictionary = prizes[pockets.size()] if pockets.size() < prizes.size() \
			else {"prize": Balance.POCKET_NOTHING, "guard": false}
		# A one-tile pocket cannot be guarded: the guard stands BETWEEN you and the prize,
		# and one tile has no between. Dropping the guard rather than the pocket, because a
		# pocket is worth having either way and the cap counts what was PLANNED — a floor
		# that quietly kept a guard's allowance without placing one would make the cap read
		# tighter than it is.
		var guard_id := ""
		if bool(spec.get("guard", false)) and cells.size() >= 2:
			# Cast from exactly the pool combat would have used, at generation, so the
			# silhouette the player looks at before committing is the creature they fight
			# (R8/D85). Held on the pocket rather than in `enemy_of`, because the tile is
			# still rock: it moves into `enemy_of` when the wall goes in.
			var pool := Balance.roster_pool(dungeon, Balance.Tier.ELITE)
			if not pool.is_empty():
				guard_id = String(pool[randi() % pool.size()])
		pockets.append({"mouth": mouth, "cells": cells,
			"prize": String(spec.get("prize", Balance.POCKET_NOTHING)),
			"guard": guard_id,
			"lock": String(spec.get("lock", Balance.POCKET_LOCK_NONE)),
			"toll": String(spec.get("toll", "")),
			"missed": false,
			"open": false})

## Grow a pocket back from its mouth through dead rock, up to `want` cells.
##
## "Dead rock" is the load-bearing phrase: a cell only joins if it has no walkable neighbour
## and touches no other pocket. That is what makes the result a dead end without a second
## pass to check it — a cell with a walkable neighbour would be a second door, and a cell
## touching another pocket would join the two into a corridor between their mouths.
func _grow_pocket(mouth: int, want: int, taken: Dictionary) -> Array:
	var cells: Array = [mouth]
	var frontier: Array = [mouth]
	while cells.size() < want and not frontier.is_empty():
		var cur := int(frontier.pop_front())
		for raw in _neighbours(cur):
			if cells.size() >= want:
				break
			var nb := int(raw)
			if int(enc[nb]) != WALL or nb in cells or taken.has(nb) or nb == landmark:
				continue
			# no walkable neighbour of its own, and not beside somebody else's pocket
			var dead := true
			for raw2 in _neighbours(nb):
				var nn := int(raw2)
				if int(enc[nn]) != WALL or (taken.has(nn) and not (nn in cells)):
					dead = false
					break
			if not dead:
				continue
			var x: int = nb % w
			var y: int = int(nb / w)
			if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
				continue
			cells.append(nb)
			frontier.append(nb)
	return cells

## Would a pocket starting here sit against one that already exists?
func _pocket_touches(cell: int, taken: Dictionary) -> bool:
	if taken.has(cell):
		return true
	for n in _neighbours(cell):
		if taken.has(n):
			return true
	return false

## Which pocket a cell belongs to, or -1. The one place anything asks that question, so the
## rules that hang off it — no slip inside a pocket, nothing in one counted against the
## dungeon's budget — cannot be applied to two different sets of tiles.
func _pocket_of(cell: int) -> int:
	for k in pockets.size():
		if cell in (pockets[k]["cells"] as Array):
			return k
	return -1

## Is this cell inside a pocket that has been opened? What `select` asks before it decides
## whether the thing it just resolved was part of what the dungeon asked for.
func _in_pocket(cell: int) -> bool:
	return _pocket_of(cell) >= 0

## Is anything on this cell outside what the dungeon asked of you (D181, D185)?
##
## ONE predicate, asked by every rule that has to treat optional content as invisible: the
## field the greedy walker steers by, the count that decides whether the stairs are offered,
## the flag that keeps `cleared` honest, and the slip suppression. Two definitions of
## "optional" is how a feature ends up half in the budget — which is the D34 trap wearing the
## one word this whole batch turns on.
func _is_optional(cell: int) -> bool:
	return _pocket_of(cell) >= 0 or cell in sites

## Push the wall in: the pocket becomes floor, whatever is in it is put there, and the whole
## thing is revealed at once (D182).
##
## Revealed WHOLE deliberately. `_reveal_around` opens a chamber the moment you set foot in
## it and gives a corridor two tiles; a pocket is exempt from both until it is pushed, and
## then arrives complete — so opening one *feels* like a room arriving rather than like a
## corridor being extended. It stays known for the rest of the floor.
##
## `tiles` grows with it, because `tiles` is what the status line's "mapped" is measured
## against and a floor that quietly gained four tiles it does not count would read as more
## explored than it is.
func _open_pocket(k: int) -> void:
	if k < 0 or k >= pockets.size():
		return
	var p: Dictionary = pockets[k]
	if bool(p["open"]):
		return
	_invalidate()
	p["open"] = true
	var cells: Array = p["cells"]
	for c in cells:
		enc[int(c)] = EMPTY
	tiles += cells.size()
	# The prize goes on the cell FURTHEST from the mouth, so a pocket is walked into rather
	# than reached into. A one-tile pocket has nowhere else to put it.
	var seat := int(cells[cells.size() - 1])
	# ...and the guard on the cell before it, which is what "between you and the prize" means
	# on a grid (D183). It is revealed WITH the pocket and the wager is still made with full
	# information: you see it standing over the prize before you decide to come in.
	#
	# It WALKS, since D197 — nothing in this dungeon stands still — but it is penned to the
	# pocket and never comes out. A guard that left would stop being a guard: the prize behind
	# it would be free to anyone who opened the wall and waited. Penned, it still has to be
	# got past, and on three or four tiles there is no getting past it — which is the same
	# decision D183 wrote, now with the guard taking the first swing.
	var guard := String(p.get("guard", ""))
	if guard != "" and cells.size() >= 2:
		mons.append({
			"cell": int(cells[cells.size() - 2]),
			"type": Enc.ELITE,
			"design": (k + depth) % 4,
			"south": true,
			"enemy": guard,
			"pen": k,
		})
	match String(p["prize"]):
		Balance.POCKET_CHEST:
			enc[seat] = Enc.TREASURE
			chest_of[seat] = Balance.POCKET_CHEST_TIER
		Balance.POCKET_KEY:
			enc[seat] = KEY
		Balance.POCKET_SITE:
			enc[seat] = Enc.EVENT
		_:
			pass    # a room, and a story about it. See `_describe`.
	for c in cells:
		seen[int(c)] = true
	_room_cells = []
	_build_light()

## Has this floor's ordinance been settled (D184)?
##
## Every clause reads state the model was already keeping. That is the constraint the plan
## puts on a debt's conditions and it applies just as hard here: a condition needing new
## bookkeeping is the wrong condition, because bookkeeping kept only for one feature is
## bookkeeping that goes stale the first time something else moves.
func _errand_met() -> bool:
	match errand:
		Balance.ERRAND_THOROUGH:
			return errand_chests == 0
		Balance.ERRAND_UNSEEN:
			return not errand_seen
		Balance.ERRAND_PUSHED:
			return errand_pushed
	return false

## What this floor is asking, or "" — for the status line. Says the ordinance and never
## whether it is currently met: an errand that ticked itself green as you walked would turn
## a thing you are doing into a checklist you are filling in.
func errand_line() -> String:
	return Balance.errand_text(errand) if errand != "" else ""

## The answer to a toll, worked out from the floor RIGHT NOW (D186).
##
## Never stored on the pocket and never written into the save. That is the whole defence
## against the fixed-riddle trap: there is nothing to memorise and nothing a wiki could hold,
## because the number is a fact about where the player is standing at the moment they are
## asked. Two of the three even change as you walk.
func toll_answer(kind: String) -> int:
	match kind:
		Balance.TOLL_EXITS:
			# Ways out of the chamber you are standing in — a chamber tile that adjoins
			# something walkable outside the room. A corridor has no room, and answers 0,
			# which is true and is its own small joke.
			var r := int(room_of[pos])
			if r < 0:
				return 0
			var n := 0
			for c in room_cells(r):
				for nb in _neighbours(int(c)):
					if int(enc[nb]) != WALL and int(room_of[nb]) != r:
						n += 1
			return n
		Balance.TOLL_PROWLING:
			return mons.size()
		Balance.TOLL_TRODDEN:
			var n2 := 0
			for nb in _neighbours(pos):
				if int(enc[nb]) != WALL and bool(walked[nb]):
					n2 += 1
			return n2
	return 0

## The three numbers a toll offers, in ASCENDING order (D186).
##
## Ascending rather than shuffled, deliberately. A shuffled list would have to be shuffled the
## same way every time the options are rebuilt — D22 requires a restored run to present the
## same list in the same order — and a per-floor seed for that is state to save and get wrong.
## Sorted by value, the position of the right answer carries no information at all, which is
## the property the shuffle was for.
func toll_choices(kind: String) -> Array:
	var a := toll_answer(kind)
	var out: Array = []
	for v in [a - 1, a, a + 1, a + 2]:
		if v >= 0 and not (v in out):
			out.append(v)
		if out.size() >= 3:
			break
	out.sort()
	return out

## Doors on this floor that want a key (D185). The other half of `keyplan`'s arithmetic.
func _locked_mouths() -> int:
	var n := 0
	for p in pockets:
		if String((p as Dictionary).get("lock", "")) == Balance.POCKET_LOCK_KEY:
			n += 1
	return n

## Stand an optional thing or two in the open, off the route (D185).
##
## OFF THE ROUTE is the whole placement rule and it is measured rather than eyeballed: a site
## goes on bare chamber ground at least `SITE_OFF_PATH` steps off the shortest line between
## the entrance and the way on. A site standing ON that line is not optional content, it is a
## budgeted encounter the budget forgot about — you would walk into it on the way past, and it
## would cost a turn and a decision the dungeon never priced.
##
## In a CHAMBER for the reason a key is (D167): a room is revealed whole the moment you set
## foot in it and a corridor gives you two tiles, so a site in a room is a thing you see
## across the floor and decide about, and the same site down a blind passage is a tile the
## player never learns exists.
func _place_sites(carved: Array, dist_from_entry: PackedInt32Array) -> void:
	sites = []
	if randi() % 100 >= Balance.SITE_PCT:
		return
	var exit_cell := -1
	for i in enc.size():
		if _is_exit(i):
			exit_cell = i
	if exit_cell < 0 or dist_from_entry.size() != enc.size():
		return
	# Distance to the way on as well, so "on the shortest line" is exactly
	# `to_entry + to_exit == the whole route`, and anything larger is ground the required
	# path does not cross.
	var to_exit := _dist_from(exit_cell)
	var span := int(dist_from_entry[exit_cell])
	if span <= 0:
		return
	# Never a tile something is already standing on. Two things on one tile is a picture the
	# view cannot draw, and it is the same rule `_spawn` and `_place_keys` follow.
	var taken := {}
	for m in mons:
		taken[int(m["cell"])] = true
	var best := -1
	var best_off := -1
	for c in carved:
		var i := int(c)
		if int(enc[i]) != EMPTY or i == pos or int(room_of[i]) < 0 or taken.has(i):
			continue
		var de := int(dist_from_entry[i])
		var dx := int(to_exit[i])
		if de < 0 or dx < 0:
			continue
		var off := de + dx - span
		if off < Balance.SITE_OFF_PATH:
			continue
		# ...and never against something else. `_place_spread` keeps the budgeted encounters
		# apart because three in adjoining tiles read as one room with three doors and leave
		# the open ground in a corner nobody visits; a site dropped beside one is that same
		# clump, and being outside the budget does not make it look any different.
		var crowded := false
		for nb in _neighbours(i):
			if int(enc[nb]) >= 0 or _is_exit(nb) or int(enc[nb]) == KEY:
				crowded = true
				break
		if crowded:
			continue
		if off > best_off:
			best_off = off
			best = i
	if best < 0:
		return
	enc[best] = Enc.EVENT
	sites.append(best)


##
## Derived from the floor rather than rolled and stored, so it is the same answer every time
## the options are rebuilt — D22 wants a restored run to present the same list, and a state
## rolled at the moment of asking would give a different one on every refresh.
func _shrine_offer() -> String:
	if shrine < 0:
		return Balance.ASPECT_NONE
	return String(Balance.ASPECTS[(shrine + depth) % Balance.ASPECTS.size()])

## Stand a stone on the floor, off the route, the way a site is (D188).
##
## Off the route for the same reason and by the same measure: a stone ON the line between the
## entrance and the way on is a decision the player is walked into rather than one they went
## to, and this one costs HP.
func _place_shrine(carved: Array, dist_from_entry: PackedInt32Array) -> void:
	shrine = -1
	if randi() % 100 >= Balance.SHRINE_PCT or dist_from_entry.size() != enc.size():
		return
	var exit_cell := -1
	for i in enc.size():
		if _is_exit(i):
			exit_cell = i
	if exit_cell < 0:
		return
	var to_exit := _dist_from(exit_cell)
	var span := int(dist_from_entry[exit_cell])
	if span <= 0:
		return
	var taken := {}
	for m in mons:
		taken[int(m["cell"])] = true
	var best := -1
	var best_off := -1
	for c in carved:
		var i := int(c)
		if int(enc[i]) != EMPTY or i == pos or int(room_of[i]) < 0 or taken.has(i):
			continue
		var de := int(dist_from_entry[i])
		var dx := int(to_exit[i])
		if de < 0 or dx < 0:
			continue
		var off := de + dx - span
		if off < Balance.SITE_OFF_PATH:
			continue
		var crowded := false
		for nb in _neighbours(i):
			if int(enc[nb]) >= 0 or _is_exit(nb) or int(enc[nb]) == KEY:
				crowded = true
				break
		if crowded:
			continue
		if off > best_off:
			best_off = off
			best = i
	if best < 0:
		return
	enc[best] = SHRINE
	shrine = best

## Pockets on this floor nobody has pushed open yet (D182).
##
## Exists so the view can tell the player *at the stairs* that the floor still holds
## something, and only when it is true. Descent is one-way, so a pocket you did not find is
## gone the moment you take the stairs — that is the whole decision the feature is for, and
## without this line it is a decision only a player who already knows the system can make.
## It says a count and never a place: the skill being asked for is noticing.
func unfound_pockets() -> int:
	var n := 0
	for p in pockets:
		if not bool((p as Dictionary)["open"]):
			n += 1
	return n

## Is this cell an unopened pocket's mouth that the player can currently make out?
##
## Only from an ADJACENT tile, which is half the feel: finding pockets means covering ground
## rather than reading a map, and it is a skill that improves with play instead of with a
## wiki. Rejected on the way here: a per-step chance to find one, and a search action that
## costs a turn on any tile — both charge for walking, which is the thing this model exists
## to sell (D77), and the second makes optimal play "search all 130 tiles".
func mark_visible(cell: int) -> bool:
	for p in pockets:
		var pd: Dictionary = p
		if bool(pd["open"]) or int(pd["mouth"]) != cell:
			continue
		if String(pd.get("lock", "")) == Balance.POCKET_LOCK_KEY:
			continue        # a door is not a mark; see `door_visible`
		for n in _neighbours(cell):
			if n == pos:
				return true
	return false

## Is this cell a shut DOOR the player can currently see (D185)?
##
## A door is visible wherever the wall is — across a room, from the doorway, from anywhere
## `seen` reaches — and that is the whole difference between the two ways a pocket is shut. A
## mark asks you to *notice*, so it is legible only from the tile beside it. A door asks you
## to *bring something*, which is a decision you can only make if you can see it from far
## enough away to still be holding the key when you arrive.
func door_visible(cell: int) -> bool:
	if cell < 0 or cell >= enc.size() or not bool(seen[cell]):
		return false
	for p in pockets:
		var pd: Dictionary = p
		if bool(pd["open"]) or int(pd["mouth"]) != cell:
			continue
		return String(pd.get("lock", "")) == Balance.POCKET_LOCK_KEY
	return false

# --- the dressing: everything on the floor that is only there to be looked at -----
#
# One pass, called last, and everything in it obeys the same two rules: it never lands on a
# tile that holds something, and nothing anywhere else in this file reads it. That is what
# makes Track A free of balance consequence by construction rather than by assertion —
# `options()`, every flood, `_describe` and the budget are all written before this runs and
# none of them looks at `props`, `room_role`, `lights` or `landmark`.

## Clutter the floor, light it, and give it one thing worth remembering (D176, D177).
func _dress_floor(carved: Array, dist_from_entry: PackedInt32Array) -> void:
	var kinds: Array = Balance.iso_props(terrain)
	var ground: Array = []
	var wall: Array = []
	for k in kinds.size():
		if String((kinds[k] as Dictionary).get("on", "ground")) == "wall":
			wall.append(k)
		else:
			ground.append(k)

	# Ground clutter, on bare floor only. The entrance is exempt: the first thing the
	# player ever sees on a floor is the tile they are standing on, and it should be the
	# one tile with nothing on it.
	for c in carved:
		var i := int(c)
		if int(enc[i]) != EMPTY or i == pos or ground.is_empty():
			continue
		if randf() >= _dress_rate(int(room_of[i]), "ground"):
			continue
		props[i] = 1 + int(ground[randi() % ground.size()])

	# Wall dressing, on the rock that walls a chamber in. Rock away from known ground is
	# never drawn at all (see `_walls_known_ground` in the view), so dressing it would be
	# work nobody sees; the rate is taken from the room the rock adjoins, which is what
	# makes a gallery's walls busy and a hall's plain.
	if not wall.is_empty():
		for i in enc.size():
			if int(enc[i]) != WALL:
				continue
			# Never on a sealed pocket, and above all never on its mouth (D182). The mark on
			# a mouth is the one piece of wall dressing the player is meant to ACT on, so a
			# decorative ring hanging beside it — or worse, on it — is the D85 lie in the one
			# place the whole feature depends on being readable at a glance.
			if _pocket_of(i) >= 0:
				continue
			var beside := -2
			for n in _neighbours(i):
				if int(enc[n]) != WALL:
					beside = int(room_of[n])
					break
			if beside == -2:
				continue    # rock in the middle of rock
			if randf() >= _dress_rate(beside, "wall"):
				continue
			props[i] = 1 + int(wall[randi() % wall.size()])

	_place_lights()
	_build_light()
	_place_landmark(dist_from_entry)

## How densely a tile dresses itself, from the role of the room it belongs to — or the one
## flat corridor rate for a tile that belongs to none.
func _dress_rate(room: int, which: String) -> float:
	if room < 0 or room >= room_role.size():
		return Balance.ISO_PROP_CORRIDOR
	var d: Dictionary = Balance.ISO_ROOM_DRESSING.get(String(room_role[room]), {})
	return float(d.get(which, Balance.ISO_PROP_CORRIDOR))

## Put the floor's few lights in the rooms that want one.
##
## Weighted by role and taken WITHOUT replacement, so two braziers never end up in the same
## chamber — the axis this exists for is "some of the floor is lit and some is not", and two
## sources in one room spends both on the same reading. A floor whose rooms all weigh zero
## still gets one, at the entrance, because a floor with no light at all sits at one flat
## value and that is the thing being fixed.
func _place_lights() -> void:
	lights = []
	# Capped by how much floor there is to light, then rolled inside that. Area first,
	# because a count alone put three sources on a 34-tile floor and lit 76% of it.
	var room_for: int = Balance.iso_lights_for(tiles)
	var want: int = mini(room_for, Balance.ISO_LIGHTS_MIN
		+ (randi() % maxi(1, Balance.ISO_LIGHTS_MAX - Balance.ISO_LIGHTS_MIN + 1)))
	var pool: Array = []
	for r in room_role.size():
		var wt: float = float((Balance.ISO_ROOM_DRESSING.get(
			String(room_role[r]), {}) as Dictionary).get("light", 0.0))
		if wt > 0.0:
			pool.append({"room": r, "weight": wt})
	while lights.size() < want and not pool.is_empty():
		var total := 0.0
		for p in pool:
			total += float(p["weight"])
		var roll := randf() * total
		var take := 0
		for k in pool.size():
			roll -= float((pool[k] as Dictionary)["weight"])
			if roll <= 0.0:
				take = k
				break
		var room: int = int((pool[take] as Dictionary)["room"])
		pool.remove_at(take)
		var cell := _light_seat(room)
		if cell < 0:
			continue
		# Fire in a room somebody used, daylight where the roof failed. Two hues rather
		# than one because a floor lit entirely from braziers is a floor at one colour
		# temperature, which is the flat reading again in warmer paint.
		var role := String(room_role[room])
		lights.append({"cell": cell, "warm": role != "sump" and role != "gallery"})
	if lights.is_empty():
		lights.append({"cell": pos, "warm": true})

## Where in a chamber a light stands: as near its middle as a bare tile allows, so the
## pool of light is the room's and not a corner's.
func _light_seat(room: int) -> int:
	var cells := room_cells(room)
	if cells.is_empty():
		return -1
	var cx := 0.0
	var cy := 0.0
	for c in cells:
		cx += float(int(c) % w)
		cy += float(int(int(c) / w))
	cx /= float(cells.size())
	cy /= float(cells.size())
	var best := -1
	var best_d := 1.0e9
	for c in cells:
		var i := int(c)
		if int(enc[i]) != EMPTY or i == pos:
			continue
		var dx := float(i % w) - cx
		var dy := float(int(i / w)) - cy
		var d := dx * dx + dy * dy
		if d < best_d:
			best_d = d
			best = i
	return best

## The light field: how lit every tile is, and by what colour. Derived from `lights`, so it
## is rebuilt rather than saved — a cache in a save file is a second copy of a fact that can
## disagree with the first, which is the reason `_room_cells` is not saved either.
##
## Four floods at most, once per floor build. Entrance selection already runs about forty
## (D99), so this is inside the noise of what generation costs; `tools/bench_iso.gd` is the
## instrument if that ever stops being true (R15).
func _build_light() -> void:
	var n := enc.size()
	_light = PackedFloat32Array()
	_light.resize(n)
	_light.fill(0.0)
	_light_hue = PackedFloat32Array()
	_light_hue.resize(n)
	_light_hue.fill(0.0)
	for l in lights:
		var src := int((l as Dictionary).get("cell", -1))
		if src < 0 or src >= n or int(enc[src]) == WALL:
			continue
		var hue: float = 1.0 if bool((l as Dictionary).get("warm", true)) else -1.0
		var field := _dist_from(src)
		for i in n:
			var d := int(field[i])
			if d < 0 or d > Balance.ISO_LIGHT_RADIUS:
				continue
			var v: float = 1.0 - float(d) / float(Balance.ISO_LIGHT_RADIUS + 1)
			if v > _light[i]:
				_light[i] = v
				_light_hue[i] = hue
	# Rock takes the light of the brightest floor tile beside it. A flood only walks
	# walkable ground, so without this a brazier would light the room and leave the wall it
	# stands against black — which reads as a hole rather than as masonry.
	var lit_rock := PackedFloat32Array()
	lit_rock.resize(n)
	var hue_rock := PackedFloat32Array()
	hue_rock.resize(n)
	for i in n:
		if int(enc[i]) != WALL:
			continue
		for nb in _neighbours(i):
			if int(enc[nb]) != WALL and _light[nb] > lit_rock[i]:
				lit_rock[i] = _light[nb]
				hue_rock[i] = _light_hue[nb]
	for i in n:
		if int(enc[i]) == WALL and lit_rock[i] > 0.0:
			_light[i] = lit_rock[i]
			_light_hue[i] = hue_rock[i]

## The one oversized thing per floor, standing in the rock (D177).
##
## Placed on the rock tile that walls in the most known-able ground, and among ties the one
## FURTHEST from the entrance — so it is a thing you walk toward and then past, which is
## what makes it usable as a bearing. Never adjacent to the entrance itself, for the same
## reason: a landmark you can see from the door tells you nothing about where you have got
## to.
func _place_landmark(dist_from_entry: PackedInt32Array) -> void:
	landmark = -1
	if dist_from_entry.size() != enc.size():
		return
	var best_score := -1
	var best_far := -1
	for i in enc.size():
		if int(enc[i]) != WALL:
			continue
		var touch := 0
		var far := -1
		for n in _neighbours(i):
			if int(enc[n]) == WALL:
				continue
			touch += 1
			far = maxi(far, int(dist_from_entry[n]))
		if touch < 2 or far < 3:
			continue
		if touch > best_score or (touch == best_score and far > best_far):
			best_score = touch
			best_far = far
			landmark = i
	# Which one it is varies with depth, so descending a dungeon does not walk past the
	# same statue four times. Derived rather than rolled: it is the one piece of the
	# dressing a player might navigate by, and a floor that came back from a save with a
	# different landmark on it would have moved their bearing.
	landmark_kind = (depth + maxi(0, landmark)) % Balance.ISO_LANDMARKS.size()

## Decide WHICH enemy every fight on this floor is, now rather than when it starts.
##
## Drawn from exactly the pool `CombatEngine` would have rolled from (`Balance.roster_pool`
## at the tile's own tier), so the enemy distribution is unchanged — this moves *when* the
## choice happens, not *what* gets chosen. That is what lets the sprite standing on a tile
## be honest without repricing anything (D85).
##
## Bosses are left out on purpose: a dungeon's finale is named and fixed, and combat
## already resolves it from `DungeonData.boss`.
##
## It no longer casts anything onto a TILE, because since D197 no fight stands on one. The
## `enemy_of` map it used to fill is still read — `enemy_at` answers off it, and a run saved
## before D197 comes back with fights on its tiles and has to keep drawing them — it simply
## has nothing on this floor to put in it.
func _cast_fights() -> void:
	var normal := Balance.roster_pool(dungeon, Balance.Tier.NORMAL)
	var elite := Balance.roster_pool(dungeon, Balance.Tier.ELITE)
	# Each hunter off the roster its tier names. An elite cast from the normal pool would be a
	# normal fight wearing an elite's HP multiplier — the one thing this function exists to
	# stop.
	for m in mons:
		if String(m.get("enemy", "")) != "":
			continue
		var pool: Array = elite if int(m["type"]) == Enc.ELITE else normal
		if pool.is_empty():
			pool = normal
		if not pool.is_empty():
			m["enemy"] = String(pool[randi() % pool.size()])

## Hand this floor's chests the tiers rolled for them in `_plan_chests`.
##
## Paired by cell order, which is arbitrary and does not need to be anything else: the tiers
## for one floor all came out of the same roll, so which of two chests is the sealed one is
## not a fact the generator has an opinion about. What matters is that the pairing is done
## HERE and saved, so the tile keeps its tier for the life of the floor — the same reason
## `_cast_fights` exists rather than a roll at combat setup (D85).
##
## A floor with more chests than the plan gave tiers to cannot happen while `_place_spread`
## places what it is handed; the fallback rolls one rather than leaving a chest with no tier,
## because a tierless chest reaches the screen as "Worn" and would quietly unlock itself.
func _cast_chests() -> void:
	var tiers: Array = (chestplan[depth] as Array).duplicate() if depth < chestplan.size() else []
	var at := 0
	for i in enc.size():
		if int(enc[i]) != Enc.TREASURE:
			continue
		if at < tiers.size():
			chest_of[i] = String(tiers[at])
			at += 1
		else:
			chest_of[i] = Balance.roll_pack_tier(Balance.PACK_TREASURE,
				dungeon.difficulty if dungeon != null else 1)

## Put this floor's hunters on it, in the far half. Spawning them anywhere would
## sometimes drop one on the entrance, which is a fight before the first decision —
## the one thing every model guarantees you do not get. It matters more since D197 than it
## did when they slept: a hunter starts walking toward you on the turn the floor is built,
## so where it starts is the only head start the player is given.
##
## `kinds` is one Enc value per hunter (COMBAT or ELITE), not a count: since D197 the elites
## walk too, and the tier decides which roster the creature is cast from.
func _spawn(kinds: Array, carved: Array, dist_from_entry: Array) -> void:
	if kinds.is_empty():
		return
	var reach := 0
	for c in carved:
		reach = maxi(reach, int(dist_from_entry[int(c)]))
	# Bare ground only. A wanderer standing on a shop or a stair is a picture of two
	# things on one tile, and the fallback has to keep that rule too — which is why it
	# relaxes the DISTANCE and not the tile.
	var far_enough: Array = []
	var anywhere: Array = []
	for c in carved:
		var i := int(c)
		if int(enc[i]) != EMPTY:
			continue
		anywhere.append(i)
		if int(dist_from_entry[i]) * 2 >= reach:
			far_enough.append(i)
	if far_enough.is_empty():
		far_enough = anywhere
	if far_enough.is_empty():
		return
	far_enough.shuffle()
	for k in kinds.size():
		mons.append({
			"cell": int(far_enough[k % far_enough.size()]),
			"type": int(kinds[k]),
			# vary by floor as well as by index, or every floor fields the same two
			"design": (k + depth) % 4,
			"south": true,
			"pen": -1,
		})

# --- geometry ------------------------------------------------------------------

func _neighbours(i: int) -> Array:
	var out: Array = []
	for d in DIRS:
		var n := _step(i, d)
		if n >= 0:
			out.append(n)
	return out

## Cell `d` away from `i`, or -1 off the edge of the grid.
func _step(i: int, d: Vector2i) -> int:
	var x: int = i % w + d.x
	var y: int = int(i / w) + d.y
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x


## Steps from `start` to every tile, -1 for rock and anything unreachable.
##
## Three BFS functions live here and all three are written the same deliberate way,
## because between them they are most of a headless run (D99): a `PackedInt32Array`
## rather than a `Array` of Variants, a read cursor rather than `pop_front` — which
## shifts the whole queue on a Godot Array and turned every flood into O(n²) — and the
## four neighbours stepped inline rather than through `_neighbours`, which allocated a
## fresh Array for every cell visited. `_neighbours` is still there for the callers
## that want the list; it just has no business inside a flood.
func _dist_from(start: int) -> PackedInt32Array:
	var n_cells := enc.size()
	var dist := PackedInt32Array()
	dist.resize(n_cells)
	dist.fill(-1)
	if start < 0 or start >= n_cells or int(enc[start]) == WALL:
		return dist
	dist[start] = 0
	var queue := PackedInt32Array()
	queue.resize(n_cells)
	queue[0] = start
	var head := 0
	var tail := 1
	while head < tail:
		var cur := queue[head]
		head += 1
		var d1 := dist[cur] + 1
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var step: Vector2i = DIRS[k]
			var nx: int = cx + step.x
			var ny: int = cy + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb: int = ny * w + nx
			if int(enc[nb]) == WALL or dist[nb] >= 0:
				continue
			dist[nb] = d1
			queue[tail] = nb
			tail += 1
	return dist

## How far you can see down a corridor, this time (D187). `Lightless` cuts it to one step,
## which changes what you KNOW about the floor and nothing about what is on it.
func _sight() -> int:
	if aspect == Balance.ASPECT_DARK or floor_state == Balance.ASPECT_DARK:
		return Balance.ASPECT_SIGHT
	return Balance.ISO_SIGHT

## How many turns on one floor before its hunters take two steps to your one (D187, D197).
## `Waking` brings it in, which is pressure out of a rule that hurries what is already
## counted rather than adding anything to the floor.
func _linger() -> int:
	if aspect != Balance.ASPECT_WAKING and floor_state != Balance.ASPECT_WAKING:
		return Balance.ISO_LINGER
	return maxi(4, int(round(float(Balance.ISO_LINGER)
		* float(Balance.ASPECT_LINGER_PCT) / 100.0)))


##
## The way on is a one-way door, not a corridor: `select` descends the moment you step onto
## it. So anything whose only route runs through it is unreachable in play, however connected
## the floor looks — which matters to `_carve_pockets`, because a mark behind the stairs is a
## mark nobody can push (D182). The same fact `_dist_to_unresolved` encodes for its own
## field, stated once here rather than a third time inline.
func _dist_from_avoiding_exit(start: int) -> PackedInt32Array:
	var n_cells := enc.size()
	var dist := PackedInt32Array()
	dist.resize(n_cells)
	dist.fill(-1)
	if start < 0 or start >= n_cells or int(enc[start]) == WALL:
		return dist
	dist[start] = 0
	var queue := PackedInt32Array()
	queue.resize(n_cells)
	queue[0] = start
	var head := 0
	var tail := 1
	while head < tail:
		var cur := queue[head]
		head += 1
		var d1 := dist[cur] + 1
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var step: Vector2i = DIRS[k]
			var nx: int = cx + step.x
			var ny: int = cy + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb: int = ny * w + nx
			if int(enc[nb]) == WALL or dist[nb] >= 0 or _is_exit(nb):
				continue
			dist[nb] = d1
			queue[tail] = nb
			tail += 1
	return dist

## Steps from every tile to the nearest of `sources`. One flood from all of them at
## once, which is the same answer as a BFS per source without multiplying by how many
## there are.
func _dist_to_any(sources: Array) -> PackedInt32Array:
	var n_cells := enc.size()
	var dist := PackedInt32Array()
	dist.resize(n_cells)
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n_cells)
	var head := 0
	var tail := 0
	for s in sources:
		var i := int(s)
		if i >= 0 and i < n_cells and int(enc[i]) != WALL and dist[i] < 0:
			dist[i] = 0
			queue[tail] = i
			tail += 1
	while head < tail:
		var cur := queue[head]
		head += 1
		var d1 := dist[cur] + 1
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var step: Vector2i = DIRS[k]
			var nx: int = cx + step.x
			var ny: int = cy + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb: int = ny * w + nx
			if int(enc[nb]) == WALL or dist[nb] >= 0:
				continue
			dist[nb] = d1
			queue[tail] = nb
			tail += 1
	return dist

## Steps from every tile to the nearest piece of unfinished business: content on the
## ground and wanderers.
## Used to order a step across open ground by whether it actually goes anywhere, which
## matters far more than it did on a floor with no open ground, because most options
## are steps that resolve nothing.
##
## Seeding the wanderers here is not cosmetic: leaving them out re-created the D74
## deadlock exactly. The way on was refused because something was still out there, and
## with nothing else unresolved every option scored `away = -1`, so the ordering fell
## back to cell index and a greedy walker paced between two tiles for ever. It failed
## 12 runs in 360 — the same shape, the same rate, the same reason. **A thing that
## blocks the exit has to be findable.**
##
## While there is business left, the way on is neither a destination NOR a route
## through. Counting a route through it was its own deadlock: where the short way round
## ran through the stair, "one step closer" pointed at a tile the ranking then refused
## to enter. It is also simply untrue — nobody walks through the boss to reach a shop.
## That cannot cut the floor in two, because the way on sits at the furthest tile from
## the entrance and a furthest tile can never be the only route to anywhere: whatever
## was behind it would be further still.
func _dist_to_unresolved(skip_exit: bool) -> PackedInt32Array:
	var n_cells := enc.size()
	var dist := PackedInt32Array()
	dist.resize(n_cells)
	dist.fill(-1)
	var queue := PackedInt32Array()
	queue.resize(n_cells)
	var head := 0
	var tail := 0
	for i in n_cells:
		var e := int(enc[i])
		var is_work: bool = e >= 0 and e != Enc.BOSS
		# ...but nothing inside a pocket is work (D182). This is the single line that keeps
		# the whole feature off the required path: the greedy walker steers by this field, so
		# a chest in an opened pocket seeding it would make the walker fetch it, and
		# `ISO_MOVES_PER_ENCOUNTER_MAX` — which measures the REQUIRED path — would start
		# reporting the optional one. It is also why an opened pocket does not stop the
		# stairs from being offered.
		if is_work and _is_optional(i):
			is_work = false
		# ...and once there is nothing else, the way on IS the work. Leaving this out was
		# the D74 deadlock for the third time: with the floor stripped, no tile seeded the
		# field, every option scored `away = -1`, the ordering fell back to cell index and
		# the walker paced between two tiles for ever. Twice now the lesson has been "a
		# thing that blocks the exit has to be findable"; this is its mirror — **the exit
		# has to be findable too.**
		if not skip_exit and _is_exit(i):
			is_work = true
		if not is_work:
			continue
		dist[i] = 0
		queue[tail] = i
		tail += 1
	for m in mons:
		# ...and a penned guard seeds nothing, exactly as the prize it stands over does not
		# (D182): the greedy walker steers by this field, and a guard in it would drag the
		# required path into every pocket the floor happens to have opened.
		if int(m.get("pen", -1)) >= 0:
			continue
		var c := int(m["cell"])
		if dist[c] < 0 and int(enc[c]) != WALL:
			dist[c] = 0
			queue[tail] = c
			tail += 1
	while head < tail:
		var cur := queue[head]
		head += 1
		var d1 := dist[cur] + 1
		var cx := cur % w
		var cy := cur / w
		for k in 4:
			var step: Vector2i = DIRS[k]
			var nx: int = cx + step.x
			var ny: int = cy + step.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nb: int = ny * w + nx
			if int(enc[nb]) == WALL or dist[nb] >= 0:
				continue
			if skip_exit and _is_exit(nb):
				continue
			dist[nb] = d1
			queue[tail] = nb
			tail += 1
	return dist

## Cells of each chamber, built on first use and thrown away with the floor.
##
## `_reveal_around` scanned the whole grid for room members on every step to answer
## "which tiles share my room" — a floor's rooms do not move, so it was re-deriving a
## constant 80 times a run (D99). Not serialized: it is derived from `room_of`, and a
## cache in a save file is a second copy of a fact that can disagree with the first.
var _room_cells: Array = []

## How lit every cell is (0..1) and by what colour (+1 warm, -1 cold), built from `lights`
## with the floor and thrown away with it. Derived, so not serialized — for the same reason
## `_room_cells` is not: a cached fact in a save file is a second copy free to disagree with
## the first.
var _light := PackedFloat32Array()
var _light_hue := PackedFloat32Array()

## Memo for `options()`. See the note there; `_opts_valid` is cleared by every mutator.
var _opts_cache: Array = []
var _opts_valid: bool = false

func room_cells(r: int) -> PackedInt32Array:
	if _room_cells.is_empty() and rooms > 0:
		var buckets: Array = []
		for k in rooms:
			buckets.append([])
		for j in room_of.size():
			var rr := int(room_of[j])
			if rr >= 0 and rr < rooms:
				(buckets[rr] as Array).append(j)
		for k in rooms:
			_room_cells.append(PackedInt32Array(buckets[k]))
	if r < 0 or r >= _room_cells.size():
		return PackedInt32Array()
	return _room_cells[r]

func _is_exit(i: int) -> bool:
	var e := int(enc[i])
	return e == STAIR or e == Enc.BOSS

## What you can make out from where you stand. **A chamber is revealed whole**; a
## corridor gives you `Balance.ISO_SIGHT` steps and no more. That contrast is the
## point — the old uniform radius made every floor feel like the same field, and this
## is what gives a dungeon the moment where a hall opens up in front of you.
## `field` is `_dist_from(i)` when the caller already has it. Every step of a walk
## reveals from the tile just entered AND moves the wanderers off the player's own
## distance field, which is the same flood computed twice — two of the three floods a
## step used to run (D99).
func _reveal_around(i: int, field: PackedInt32Array = PackedInt32Array()) -> void:
	seen[i] = true
	var r := int(room_of[i])
	if r >= 0:
		for j in room_cells(r):
			seen[j] = true
	var dist := field if field.size() == enc.size() else _dist_from(i)
	for j in enc.size():
		var d := int(dist[j])
		if d >= 0 and d <= _sight():
			seen[j] = true

# --- the floor takes its turn --------------------------------------------------

## Every hunter on the floor steps toward the player. Every one of them, every turn (D197).
##
## There is no sleeping and no drifting left. A monster that had not noticed you yet was the
## only thing on this floor not playing the game, and it made the first two thirds of every
## floor a walk with scenery on it: the wanderers were three quarters asleep at any moment,
## the standing fights never moved at all, and the whole model's promise — *this is a place
## and something else is using it* — was kept for about six turns of a forty-turn floor.
##
## And nothing ever holds its ground. Where a step toward the player is not available — the
## way is rock, or another hunter is already in it — it takes any step it can rather than
## waiting for the geometry to improve. The rule is worth the jitter it sometimes costs: a
## thing that stops moving reads as a thing that has lost interest, and none of these have.
##
## A hunter never steps ONTO the player: it holds its ground and is returned as the one that
## caught you. Sharing the tile would mean drawing a monster under the player and, worse, one
## standing on a tile the player is about to fight something else in — the tile's own
## encounter resolves first, and the hunter is still there after, adjacent, waiting.
##
## Nor onto each other. It did not matter while most of them were asleep in separate rooms;
## with every one of them steering for the same tile it matters every turn, because `threats`
## is keyed by cell and a pile of four monsters was drawn as one.
##
## Returns the index of the hunter now engaging the player, or -1.
func _floor_turn(field: PackedInt32Array = PackedInt32Array()) -> int:
	var engaging := -1
	var dist := field if field.size() == enc.size() else _dist_from(pos)
	# Where everything is, so nothing walks through anything else. Rebuilt per turn rather
	# than kept, because `mons` is edited from four other places and a cached occupancy grid
	# is a second copy of a fact (D34).
	var taken := {}
	for m in mons:
		taken[int(m["cell"])] = true
	# How hurried the floor is. Read once: a floor does not speed up halfway through its own
	# turn, and asking per monster would let the first mover cross the threshold for the rest.
	var steps_each := Balance.iso_hunter_steps(floor_steps, _linger())
	for k in mons.size():
		var m: Dictionary = mons[k]
		for _s in steps_each:
			if int(dist[int(m["cell"])]) == 0:
				# You walked onto it. This is the other half of contact and it has to be
				# checked FIRST: the chase below only closes distance when there is distance
				# to close, so at zero a hunter fell through to the sidestep and stepped
				# politely out of the way. A greedy walker then chased it round the floor for
				# ever, because the thing blocking the way on was the thing it could never
				# catch — 12 runs in 360, the D74 deadlock wearing a new hat.
				if engaging < 0:
					engaging = k
				break
			var target := _hunt_step(m, dist, taken)
			if target == pos:
				# it has reached you: it stays where it is and the fight is the result
				if engaging < 0:
					engaging = k
				break
			if target < 0:
				break        # boxed in by rock and its own kind; nowhere at all to put a foot
			var here := int(m["cell"])
			# Facing, for the view only. Both grid axes point AWAY from the viewer on
			# screen (x is ↘, y is ↙, per DIR_ARROW), so a step whose components sum
			# positive is a step toward the camera and shows the thing's front.
			var dx := target % w - here % w
			var dy := int(target / w) - int(here / w)
			m["south"] = (dx + dy) > 0
			# ...and WHICH of the two toward-camera diagonals, because the sprite is drawn
			# looking along one of them and mirrored for the other. A step's horizontal
			# travel on screen is `(dx - dy)`, so that sign IS "to the right" — the same
			# arithmetic the projection itself uses, rather than a second opinion about it.
			#
			# `south` alone was enough while every figure was symmetric: mirroring a
			# bilaterally symmetric painting produces the same pixels, so the model never had
			# to say which way a thing was turned. Directional art makes it a real question.
			m["east"] = (dx - dy) > 0
			taken.erase(here)
			taken[target] = true
			m["cell"] = target
	return engaging

## Where one hunter puts its foot: the player's tile if it has reached them, the neighbour
## that closes the most distance if there is one, otherwise any neighbour at all, otherwise
## -1 for a thing with nowhere to go.
##
## The chase is steered off the PLAYER's own distance field rather than off a straight line,
## which is what makes a hunter follow the floor round a corner instead of pressing into the
## rock between it and you. `dist` is that field; it is already computed once per turn by the
## caller, and computing it per monster was 40% of a headless run before D99.
func _hunt_step(m: Dictionary, dist: PackedInt32Array, taken: Dictionary) -> int:
	var here := int(m["cell"])
	var pen := int(m.get("pen", -1))
	var bestd := int(dist[here])
	var target := -1
	var loose: Array = []
	for n in _neighbours(here):
		if int(enc[n]) == WALL:
			continue
		# A guard walks its pocket and never leaves it (D183, D197). Checked before the
		# player's tile is, so a guard whose pocket the player is standing beside does not
		# lunge out of the room it exists to hold.
		if pen >= 0 and _pocket_of(n) != pen:
			continue
		if n == pos:
			return pos
		if taken.has(n):
			continue
		var dn := int(dist[n])
		if dn >= 0 and dn < bestd:
			bestd = dn
			target = n
		loose.append(n)
	if target >= 0:
		return target
	# Nothing closes the gap, so take a step anyway. Deterministic on state alone — the
	# lowest free neighbour, not a random one — because D22 wants a restored run to behave
	# identically, and a coin flip here would make the floor move differently on reload.
	if loose.is_empty():
		return -1
	loose.sort()
	return int(loose[0])

# --- interface ---

## One option per exit from this tile. Ordered so the first is always the one that
## gets on with the floor: an unresolved encounter if one adjoins, otherwise a step
## toward the nearest piece of business, and the way down only once nothing else is
## left.
##
## **Memoized.** Building the list floods the floor, and a single step used to do it
## twice: once for the caller to choose from, once inside `select` to resolve the index
## it was handed. The cache is dropped by every method that touches state — `generate`,
## `_build_floor`, `select`, `clear_pending`, `load_state` — and nothing outside this
## class mutates a floor, so "dirty on every mutator" is the whole invariant.
## `tests/test_traversal.gd` walks a dungeon comparing each cached answer against a
## freshly computed one, because a stale option list is a wrong move made silently.
##
## The returned Array is the cache itself, not a copy: every caller treats it as
## read-only, and a shallow copy would protect the list while still sharing the
## dictionaries inside it, which is false comfort at a real cost.
func options() -> Array:
	if _opts_valid:
		return _opts_cache
	_opts_cache = _compute_options()
	_opts_valid = true
	return _opts_cache

## Drop the memo. Call from anything that changes what a step could be.
func _invalidate() -> void:
	_opts_valid = false

func _compute_options() -> Array:
	if done:
		return []
	# No floor means no exits. A blob with no `enc` reaches here from a restore — the
	# grid dimensions default while the cells do not, so `_step` hands back an index
	# into an empty array and every caller sees an engine error instead of "no run".
	if enc.size() < w * h:
		return []
	var others := 0
	for i in enc.size():
		var e := int(enc[i])
		# The same exclusion as `_dist_to_unresolved`, and it has to be the same or the two
		# disagree about what the floor still owes: this count is what decides whether the
		# way on is ranked last, so a chest in an opened pocket would hold the stairs back
		# and turn optional content into a gate (D182).
		if e >= 0 and e != Enc.BOSS and not _is_optional(i):
			others += 1
	# A hunter is unfinished business too — but a penned guard is not, for the same reason
	# nothing else in a pocket is (D182): it would hold the stairs back over content the
	# dungeon never asked for.
	for m in mons:
		if int(m.get("pen", -1)) < 0:
			others += 1
	var goal := _dist_to_unresolved(others > 0)

	var out: Array = []
	for d in DIRS.size():
		var n := _step(pos, DIRS[d])
		if n < 0 or int(enc[n]) == WALL:
			continue
		var e := int(enc[n])
		var rank := 1                          # a step across open ground
		if e >= 0 and e != Enc.BOSS:
			# ...but only if the DUNGEON asked for it. Optional content ranks as plain ground
			# (D185): rank 0 means "this is the business of the floor", and a site the budget
			# never paid for is not. Leaving it at 0 put optional encounters at the head of
			# the list, so the greedy walker resolved every site it passed and the required
			# path's moves-per-encounter fell from 7.1 to 6.5 — a pacing number improved by
			# counting content the number is not about.
			rank = 0 if not _is_optional(n) else 1
		elif e == KEY:
			# A key underfoot is something to do, so it leads the list — but it is NOT
			# counted as unresolved business below, which is what keeps the stairs where
			# they are and the measured walk where D79 pinned it. Ranked, not required.
			rank = 0
		elif _is_exit(n):
			rank = 0 if others == 0 else 2     # the way on: last, until it is all there is
		var away: int = int(goal[n])
		out.append({
			"type": e,
			"label": "%s  %s" % [DIR_ARROW[d], _describe(n)],
			"cell": n,
			"dir": d,
			# Only a real encounter resolves. The stairs are handled inside `select`
			# and hand back {}, which is what keeps descending invisible to RunFlow —
			# nothing outside this model needs to learn a new node type.
			"resolves": e >= 0,
			# rank first, then how much closer this step gets to the work left, then the
			# cell itself so the order is a function of state alone — a restored run has
			# to present the same list in the same order (D22).
			"order": rank * 1000000 + (away if away >= 0 else 9999) * 1000 + n,
		})

	# ...and, for a hunter that has come within reach, the option of not fighting it. See
	# `_slip_cost`. This is where the crawl's priced decline moved when nothing was left
	# standing on a tile to squeeze past (D197): the fights come to you now, so declining one
	# is something you do to a thing beside you rather than to a tile in front of you.
	#
	# NEVER a penned guard (D183). It is the same suppression the tile version needed and both
	# of its reasons survive intact. It makes no sense in a dead end: the decline exists to get
	# *past* something, and a guard cannot follow you out of its own pocket — walking away is
	# the decline and it is already free. And it would be priced from `dodgeable`, which solves
	# the whole ladder from a count the guard is not in (D99), so offering it would charge the
	# ladder's price for a rung the ladder never counted.
	for k in mons.size():
		var m: Dictionary = mons[k]
		if int(m.get("pen", -1)) >= 0:
			continue
		var mc := int(m["cell"])
		var md := -1
		for d4 in DIRS.size():
			if _step(pos, DIRS[d4]) == mc:
				md = d4
		if md < 0:
			continue
		var mt := int(m["type"])
		var cost := _slip_cost()
		out.append({
			"type": mt,
			"label": "%s  Break away from the %s (-%d HP%s)" % [DIR_ARROW[md],
				String(Balance.NODE_LABEL.get(mt, "?")).to_lower(), cost,
				", rising" if avoided > 0 else ""],
			"cell": mc,
			"dir": md,
			"resolves": false,
			"action": "avoid",
			"mon": k,
			"hp_cost": cost,
			# Ranked BELOW even the way down, so the first button is never "skip the game". A
			# player leaning on it faces everything, which is also what makes the headless
			# walkers measure the full budget (D14).
			"order": 3000000 + mc,
		})

	# ...a stone you may put your hand on (D188). Ranked with the pushes, dead last, for the
	# same reason: it is optional, the greedy walker presses index 0, and anything a stone
	# could outrank would put an optional decision into the number that measures the required
	# route.
	if shrine >= 0 and floor_state == Balance.ASPECT_NONE:
		# Standing ON it counts as being at it (D188). The first version only offered the
		# option from an adjacent tile, so a player who walked onto the stone could not use
		# it and had to step off and back — a decision made unreachable by arriving at it.
		var reach_dirs: Array = [-1] if pos == shrine else []
		for d3 in DIRS.size():
			if _step(pos, DIRS[d3]) == shrine:
				reach_dirs.append(d3)
		for d3 in reach_dirs:
			out.append({
				"type": SHRINE,
				"label": "%s  Put your hand on the stone" % (
					DIR_ARROW[int(d3)] if int(d3) >= 0 else "  "),
				"cell": shrine,
				"dir": d3,
				"resolves": false,
				"action": "shrine",
				"state": _shrine_offer(),
				"order": 22000000 + shrine,
			})

	# ...and a wall with a mark on it, which is a fifth kind of option: not a step, not a
	# fight, and not the way on (D182).
	#
	# Ordered DEAD LAST, below even the slip, and the number is deliberately far above every
	# other order this function can produce rather than merely bigger than the tiers above.
	# The first attempt put it between the stairs and the slip at 2.5M, which is *wrong* by
	# arithmetic nobody would spot by reading: a step whose goal is unreachable scores
	# `1 * 1000000 + 9999 * 1000`, so on any tile whose route to the remaining work runs
	# through the way on, the push outranked every step — and the contract walker, which
	# presses the first option without a price on it, started pushing walls and then paced
	# between two tiles for ever once they were all open. **A rank has to be safe against the
	# largest value the tiers below it can reach, not against their nominal order.**
	#
	# Being last is also right on its own terms: the greedy walker presses index 0, so
	# anything a push could outrank would put the optional route into the number that
	# measures the required one.
	for k in pockets.size():
		var p: Dictionary = pockets[k]
		if bool(p["open"]):
			continue
		var m := int(p["mouth"])
		for d2 in DIRS.size():
			if _step(pos, DIRS[d2]) != m:
				continue
			var toll := String(p.get("toll", ""))
			if toll != "":
				# A missed toll stays missed for the rest of the floor: without that, the
				# question is a delay rather than a wager — you would answer each number in
				# turn until one worked (D186).
				if bool(p.get("missed", false)):
					continue
				for v in toll_choices(toll):
					out.append({
						"type": WALL,
						"label": "%s  Answer: %d" % [DIR_ARROW[d2], int(v)],
						"cell": m,
						"dir": d2,
						"resolves": false,
						"action": "answer",
						"pocket": k,
						"say": int(v),
						# Ordered by the ANSWER, so the right one is never in a fixed
						# position and the ordering is a function of state alone (D22).
						"order": 21000000 + int(v) * 100 + m,
					})
				continue
			var locked: bool = String(p.get("lock", "")) == Balance.POCKET_LOCK_KEY
			out.append({
				"type": WALL,
				"label": "%s  %s" % [DIR_ARROW[d2],
					"Unlock the door" if locked else "Push at the mark"],
				"cell": m,
				"dir": d2,
				"resolves": false,
				"action": "push",
				# A door reports that it WANTS a key and never checks for one: the model owns
				# no run resources (D13), so the caller reads this, spends the key and only
				# then calls `select` — the same contract the slip's `hp_cost` has had since
				# the deck model. The headless walkers do not model keys at all, so they
				# simply decline these; see D185 for what that costs the measurement.
				"needs_key": locked,
				"pocket": k,
				"order": 20000000 + m,
			})
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out

## What shaking a hunter off costs, instead of fighting it.
##
## Reuses the already-tuned price (`Balance.avoid_cost`) rather than
## inventing one, including its rising shape: the first slip is the one you want, the
## last should be unaffordable. Deliberately the SAME number, because it is the same
## decision — D88 moved every dungeon onto this model, and the deck's dodge was the thing
## that made a deck dungeon cost what it cost.
##
## `dodgeable` goes with it because the price is solved from the whole ladder: a dungeon
## offering two slips charges more for each than one offering four. Passing the count
## rather than letting Balance guess it is the fix for D99, where the price was sized for
## four rungs the crawl has never once offered.
##
## Why it had to exist here at all: measured over the twelve dungeons, graph runs met 4.5-5.1
## fights of their budget, dice runs 3.5-4.1, deck runs 4.9 plus 1.1 dodged — and iso met
## **5.9-6.0, because iso is the only model with nothing to skip.** A route can miss a node,
## an overshoot can miss a space, a dodge can buy a miss; stripping a floor misses nothing.
## So one dungeon's budget delivered a full extra fight the moment it became isometric, and
## the Foundry fell from 63% to 8% on an Early deck. A spatial model needs a spatial way to
## decline, or "every model costs the same" stops being true at the only place it matters.
func _slip_cost() -> int:
	var diff: int = dungeon.difficulty if dungeon != null else 1
	return Balance.avoid_cost(diff, avoided, dodgeable)

## What a step reads as. Bare ground gets three different names because a row of
## identical "Open ground" buttons is a choice with no information in it: is there
## anything there, have I been there, and if not, do I even know what I am walking
## into?
func _describe(n: int) -> String:
	var e := int(enc[n])
	match e:
		STAIR:
			return "Stairs down"
		KEY:
			return "A key"
		SHRINE:
			return "A standing stone"
	if e == Enc.TREASURE and chest_of.has(n):
		# The tier IS the lock, so naming it names what the chest wants (D172).
		return "%s chest" % Balance.PACK_TIER_NAME.get(String(chest_of[n]), "Worn")
	if e >= 0:
		return String(Balance.NODE_LABEL.get(e, "?"))
	# Ground that was rock until you pushed at it. Named, because a pocket that reads as
	# ordinary open floor is a pocket the player cannot tell they have already found — and
	# on a re-walked floor that is the difference between a decision and a guess.
	if _in_pocket(n):
		return "Into the pocket"
	if not bool(seen[n]):
		return "Into the dark"
	if bool(walked[n]):
		return "Back the way you came"
	return "Open ground"

## The floor takes its turn after something the player did standing still — a push, an
## answer, a hand on the stone, a break-away. Returns the ambush to resolve, or {}.
##
## One function rather than the four copies this used to be. They had drifted apart once
## already (the push flooded after opening the pocket, the others before) and every one of
## them had to be edited when the linger rule changed, which is exactly the shape of bug the
## crawl keeps paying for: the same six lines written out per caller.
func _floor_moves(field: PackedInt32Array) -> Dictionary:
	var caught := _floor_turn(field)
	return _catch(caught) if caught >= 0 else {}

## The encounter a hunter that has reached you resolves into. The one place it is built, for
## all four standing turns and the walk.
func _catch(caught: int) -> Dictionary:
	var m: Dictionary = mons[caught]
	# `ambush` is a PRICE, reported and not applied: a traversal never touches run resources
	# (D13). Caught in the open is also the one thing the `unseen` errand asks you to avoid
	# (D184), and the model is what knows it happened.
	errand_seen = true
	caught_ever = true
	pending = {"type": int(m["type"]), "cell": pos, "mon": caught, "ambush": true}
	if String(m.get("enemy", "")) != "":
		pending["enemy"] = String(m["enemy"])
	# A guard is a pocket's business, not the dungeon's (D182/D183), whether you walked into
	# it or it reached you.
	if int(m.get("pen", -1)) >= 0:
		pending["optional"] = true
	return pending

## Put `count` more hunters on a floor that is already being walked (D197). Only the stone's
## `crowded` state does this; everything else a floor fields is dealt at `generate`.
##
## Placed as far from the player as the floor allows rather than in the far half, because
## "the far half" is measured from an entrance the player may be standing nowhere near — and
## a monster that materialised beside them would be a price with no decision in it.
func _spawn_late(count: int, dist_from_player: PackedInt32Array) -> void:
	var taken := {}
	for m in mons:
		taken[int(m["cell"])] = true
	var normal := Balance.roster_pool(dungeon, Balance.Tier.NORMAL)
	for k in count:
		var far := -1
		var far_d := 0
		for i in enc.size():
			if int(enc[i]) != EMPTY or taken.has(i) or _in_pocket(i):
				continue
			var d := int(dist_from_player[i])
			if d > far_d:
				far_d = d
				far = i
		if far < 0:
			return
		taken[far] = true
		mons.append({
			"cell": far, "type": Enc.COMBAT, "design": (mons.size() + depth) % 4,
			"south": true, "pen": -1,
			"enemy": String(normal[randi() % normal.size()]) if not normal.is_empty() else "",
		})
		# It is a fight the dungeon did not ask for, so the dungeon now asks for it: the aspect
		# is priced in gold rather than being budget-neutral (D197), and a quota that did not
		# count it would let `progress()` read 1.0 with something still walking.
		quota += 1
		dodgeable += 1

## Walk one tile. Returns the encounter to resolve, or {} for a step that was handled
## here — open ground, or a descent.
##
## The order matters and is the one classic roguelikes use: you move, the floor moves,
## then we see what you are standing in. If the tile you entered holds an encounter,
## THAT is what resolves — a wanderer that caught you the same turn keeps its place
## beside you and is what you meet on the way out.
func select(i: int) -> Dictionary:
	var opts := options()
	_invalidate()
	picked_key = false
	errand_paid = ""
	toll_result = ""
	shrine_paid = ""
	if i < 0 or i >= opts.size():
		return {}
	var o: Dictionary = opts[i]
	var target := int(o["cell"])
	var was := int(enc[target])

	# Pushing at a mark is a turn spent where you stand: the wall goes in, the pocket
	# arrives, and you have not moved (D182). Walking into it is the NEXT decision, which is
	# the point — the guard, when there is one, is looked at before it is met.
	# Putting your hand on the stone is a turn spent where you stand (D188). The floor changes
	# for the rest of itself, the HP price is REPORTED for the caller to pay, and the gold is
	# owed until the stairs — which is what makes it a wager rather than a purchase: you are
	# betting that you can still get off this floor once it has changed.
	if String(o.get("action", "")) == "shrine":
		steps += 1
		floor_steps += 1
		floor_state = String(o.get("state", Balance.ASPECT_NONE))
		shrine_paid = floor_state
		enc[shrine] = EMPTY
		shrine = -1
		var lit := _dist_from(pos)
		_reveal_around(pos, lit)
		# ...and one more of the floor gets up, on a floor that asked for it (D197). The only
		# state a stone sets that has to DO something at the moment it is set: `dark` and
		# `waking` are read back out of `floor_state` by `_sight` and `_linger`, but a hunter
		# that does not exist cannot be conjured by a lookup.
		if floor_state == Balance.ASPECT_CROWDED:
			_spawn_late(Balance.ASPECT_EXTRA_WANDERERS, lit)
		return _floor_moves(lit)

	# Answering a toll is a turn spent where you stand, exactly as a push is (D186). Right,
	# and the pocket opens; wrong, and it shuts for the floor and the price is REPORTED for
	# the caller to pay — a traversal never touches run HP (D13).
	if String(o.get("action", "")) == "answer":
		steps += 1
		floor_steps += 1
		var pk: Dictionary = pockets[int(o["pocket"])]
		var right: bool = int(o["say"]) == toll_answer(String(pk.get("toll", "")))
		toll_result = "right" if right else "wrong"
		if right:
			_open_pocket(int(o["pocket"]))
			errand_pushed = true
		else:
			pk["missed"] = true
		var asked := _dist_from(pos)
		_reveal_around(pos, asked)
		return _floor_moves(asked)

	# Breaking away: the thing that has come for you loses you, and the fight does not happen.
	# The HP price is reported on the option and paid by whoever owns the HP (D13), exactly as
	# the deck model's dodge was — this method only takes the hunter off the floor and counts
	# it. This is the crawl's priced decline, and since D197 it is the only kind there is: the
	# old version squeezed past a fight STANDING on a tile, and no fight stands on a tile.
	#
	# A turn spent where you stand, not a step. Which is most of what makes it a decision —
	# everything else on the floor closes one tile while you are shaking this one off.
	if String(o.get("action", "")) == "avoid":
		steps += 1
		floor_steps += 1
		var shed := int(o.get("mon", -1))
		if shed >= 0 and shed < mons.size():
			mons.remove_at(shed)
		avoided += 1
		var field0 := _dist_from(pos)
		_reveal_around(pos, field0)
		return _floor_moves(field0)

	if String(o.get("action", "")) == "push":
		steps += 1
		floor_steps += 1
		_open_pocket(int(o["pocket"]))
		errand_pushed = true
		# One flood, used twice, exactly as the break-away does — and taken AFTER the opening,
		# so the reveal and the hunters both see the floor the push just made, the guard the
		# push just released included.
		var pushed := _dist_from(pos)
		_reveal_around(pos, pushed)
		return _floor_moves(pushed)

	# The stairs are not a move across the floor, they are the end of it: descending
	# replaces everything, so nothing below this line would mean anything.
	if was == STAIR:
		steps += 1
		# The errand is settled HERE, in the last instant the floor that set it still exists
		# (D184). Reported and not paid: a traversal owns no run resources (D13), so the gold
		# is the view's to add, exactly as a key pickup is.
		errand_paid = errand if _errand_met() else ""
		# A floor state lasts until you leave the floor, and the stone's gold is owed at the
		# same moment (D188). Reported on the descent for the caller to pay, exactly as the
		# errand is — and reported BEFORE `_build_floor`, which resets it.
		shrine_paid = floor_state
		floor_state = Balance.ASPECT_NONE
		_build_floor(depth + 1)
		return {}

	pos = target
	steps += 1
	floor_steps += 1
	walked[pos] = true

	# A key is picked up by standing on it, and the tile is bare ground afterwards. The
	# turn still happens in full below — the floor moves, and a wanderer can catch you on
	# the tile you bent down in.
	if was == KEY:
		enc[pos] = EMPTY
		picked_key = true

	var field := _dist_from(pos)
	_reveal_around(pos, field)
	var caught := _floor_turn(field)

	if int(enc[pos]) >= 0:
		pending = {"type": int(enc[pos]), "cell": pos}
		# Whatever is in a pocket is OUTSIDE what the dungeon asked for (D182), and the flag
		# rides out on the encounter so `clear_pending` can decline to count it. Without it
		# a pocket's chest would add to `cleared` against a `quota` that never included it,
		# and `progress()` would read a floor as further along than it is — silently,
		# because it clamps at 1.0.
		if _is_optional(pos):
			pending["optional"] = true
		# The archetype the floor has been SHOWING the player, handed on so the fight is
		# the creature they walked up to. A tile with no cast enemy (a shop, a rest, the
		# boss) simply omits it and the caller rolls as it always did.
		if enemy_of.has(pos):
			pending["enemy"] = String(enemy_of[pos])
		# ...and the tier the floor has been showing, for the same reason: the chest screen
		# must open the chest the player walked to, not roll a fresh one at the lid (D172).
		if chest_of.has(pos):
			pending["chest"] = String(chest_of[pos])
		return pending
	if caught >= 0:
		# `ambush` is a PRICE, reported and not applied: a traversal never touches run
		# resources (D13), exactly as the old deck model reported its dodge and let the
		# caller pay. Whoever owns the HP charges Balance.iso_ambush_cost. Built by the same
		# helper the standing turns use, so a guard caught here is flagged optional exactly as
		# one caught while you pushed at a wall is — that flag decides whether the fight counts
		# against `quota`, and getting it right in three places and wrong in the fourth is how
		# `progress()` would quietly read past 1.0 on a floor with a pocket in it.
		return _catch(caught)
	return {}

func clear_pending() -> void:
	_invalidate()
	if pending.is_empty():
		return
	var cell: int = int(pending.get("cell", pos))
	var kind_of := int(pending.get("type", Enc.COMBAT))
	# A pocket's contents are not part of the dungeon's quota, so resolving one does not
	# count toward it (D182). Everything else about it is normal: the tile clears, the fight
	# is still loud, the chest still opens.
	var optional := bool(pending.get("optional", false))
	if pending.has("mon"):
		var k := int(pending["mon"])
		if k >= 0 and k < mons.size():
			mons.remove_at(k)
	else:
		if int(enc[cell]) == Enc.BOSS:
			done = true
		enc[cell] = EMPTY
		# the tile is bare ground now, so nothing stands on it and nothing is buried in it
		enemy_of.erase(cell)
		chest_of.erase(cell)
	if not optional:
		cleared += 1
		if kind_of == Enc.TREASURE:
			errand_chests = maxi(0, errand_chests - 1)
	pending = {}
	# A fight used to be LOUD, and winning one woke everything within earshot. Nothing on this
	# floor is asleep any more (D197), so noise had nothing left to do: the rule it encoded —
	# where you choose to fight is a decision — is now true of every turn rather than of the
	# turns after a fight.

## Never reaches 1.0 on a dungeon whose wanderers you slipped past, which is correct: you
## left something down there. `is_complete` is what
## ends a run, not this.
func progress() -> float:
	if quota <= 0:
		return 0.0
	# A fight slipped past is business settled, not business outstanding — the same
	# reading the old deck model took of a dodge.
	return clampf(float(cleared + avoided) / float(quota), 0.0, 1.0)

func is_complete() -> bool:
	return done

func status() -> String:
	var mapped := 0
	for s in seen:
		if bool(s):
			mapped += 1
	# Terse because it used to have to fit one header row beside HP, deck, gold and the
	# at-risk totals, and a longer wording pushed that row onto a second line. That
	# constraint is gone: the crawl gives every fact its own Label and wraps BETWEEN
	# facts now, at any content length (D115). What survives of the old note is only that
	# this is still a pre-joined string the header has to split back apart to lay out.
	# The parts belong here the way `GameState.risk_parts()` does (D116) — but `status()`
	# is the `Traversal` seam's virtual, so that accessor is the base class's to declare,
	# and adding it on this override alone would leave the next model free to name it
	# something else. Rewording the phrases is a separate decision either way: it changes
	# what the crawl says about itself.
	var out := "Floor %d/%d   %d/%d cleared   %d/%d mapped" % [
		depth + 1, floors, cleared, maxi(1, quota), mapped, maxi(1, tiles)]
	if mons.size() > 0:
		out += "   %d prowling" % mons.size()
	return out

## `seen` and `walked` go out as plain Arrays, NOT as the `PackedByteArray` they are in
## memory: `JSON.stringify` has no case for that type and falls through to `str()`, so
## the save gets a quoted `"[1, 0, 1]"` and the load gets back a String (D140).
func _save() -> Dictionary:
	return {"w": w, "h": h, "enc": enc,
		"seen": Array(seen), "walked": Array(walked),
		"room_of": room_of, "pos": pos, "tiles": tiles, "content": content,
		"rooms": rooms, "quota": quota, "steps": steps, "floor_steps": floor_steps,
		"avoided": avoided, "dodgeable": dodgeable,
		"done": done, "mons": mons, "enemy_of": enemy_of, "chest_of": chest_of,
		"floors": floors, "depth": depth, "plan": plan, "roam": roam,
		"keyplan": keyplan, "chestplan": chestplan,
		# The dressing (D176/D177). It is only looked at, so none of it can change what a
		# resumed run costs — but a floor that came back dressed differently would be a
		# different ROOM, and this is a model whose whole subject is remembering where you
		# have been. `props` is a PackedInt32Array, which round-trips as numbers; the two
		# byte grids above do not, which is the D140 scar.
		"props": props, "room_role": room_role, "lights": lights,
		"landmark": landmark, "landmark_kind": landmark_kind,
		"terrain": terrain, "style_name": style_name,
		# Pockets are RUN state, not dressing: which walls have a mark behind them, what is
		# behind each, and which ones you have already pushed (D182). A resumed run that
		# re-rolled them would hand the player back a floor they had already stripped, and
		# one that forgot which were open would seal a room they are standing in.
		"pockets": pockets, "pocketplan": pocketplan, "sites": sites,
		# The errand and its progress are run state: a resumed floor has to still be owed the
		# same thing, and has to remember that you were already caught once on it (D184).
		"aspect": aspect, "deep": deep, "caught_ever": caught_ever, "floor_state": floor_state, "shrine": shrine,
		"errand": errand, "errandplan": errandplan, "errand_seen": errand_seen,
		"errand_chests": errand_chests, "errand_pushed": errand_pushed}

func _load(d: Dictionary) -> void:
	w = int(d.get("w", Balance.ISO_GRID))
	h = int(d.get("h", Balance.ISO_GRID))
	# JSON has no ints and no typed arrays: every cell comes back as a float
	enc = PackedInt32Array()
	for e in d.get("enc", []):
		enc.append(int(e))
	seen = _bools(d.get("seen", []), enc.size())
	walked = _bools(d.get("walked", []), enc.size())
	room_of = PackedInt32Array()
	for r in d.get("room_of", []):
		room_of.append(int(r))
	while room_of.size() < enc.size():
		room_of.append(-1)
	pos = clampi(int(d.get("pos", 0)), 0, maxi(0, enc.size() - 1))
	tiles = int(d.get("tiles", 0))
	content = int(d.get("content", 0))
	rooms = int(d.get("rooms", 0))
	quota = int(d.get("quota", content))
	steps = int(d.get("steps", 0))
	floor_steps = int(d.get("floor_steps", 0))
	avoided = int(d.get("avoided", 0))
	dodgeable = int(d.get("dodgeable", 0))
	_room_cells = []
	_invalidate()
	done = bool(d.get("done", false))
	floors = maxi(1, int(d.get("floors", 1)))
	depth = clampi(int(d.get("depth", 0)), 0, floors - 1)
	plan = []
	for f in d.get("plan", []):
		var row: Array = []
		for e in f:
			row.append(int(e))
		plan.append(row)
	while plan.size() < floors:
		plan.append([])
	# `roam` holds a list of Enc values per floor since D197, where it used to hold a count of
	# combats. A save from before that comes back as numbers, and the honest reading of an old
	# "2" is two combats — which is what it laid out then and what it lays out now.
	roam = []
	for r in d.get("roam", []):
		var row: Array = []
		if r is Array:
			for e in r:
				row.append(int(e))
		else:
			for k in maxi(0, int(r)):
				row.append(Enc.COMBAT)
		roam.append(row)
	while roam.size() < floors:
		roam.append([])
	# A save written before keys were on the floor has no `keyplan`, and zeroes are the
	# right answer for it: the floors it already laid out have no keys on them either, so
	# a resumed run is short of keys rather than restored into a floor it never had.
	keyplan = []
	for k in d.get("keyplan", []):
		keyplan.append(maxi(0, int(k)))
	while keyplan.size() < floors:
		keyplan.append(0)
	# Same story one field over: a save from before the tiers were cast up front has no
	# `chestplan`, and an empty row is what `_cast_chests` handles by rolling — which is
	# what that save's chests were going to do at the lid anyway.
	chestplan = []
	for f in d.get("chestplan", []):
		var tiers: Array = []
		for t in f:
			if String(t) in Balance.PACK_TIERS:
				tiers.append(String(t))
		chestplan.append(tiers)
	while chestplan.size() < floors:
		chestplan.append([])
	mons = []
	for m in d.get("mons", []):
		var md: Dictionary = m
		mons.append({
			"cell": int(md.get("cell", 0)),
			"type": int(md.get("type", Enc.COMBAT)),
			"design": int(md.get("design", 0)),
			"south": bool(md.get("south", true)),
			# A save from before this existed has no facing beyond `south`. False is the
			# unmirrored painting, which is what every such save was already drawing.
			"east": bool(md.get("east", false)),
			"enemy": String(md.get("enemy", "")),
			# A save from before D197 has no pen and no guards among its `mons` at all — its
			# guards are still standing on tiles as ELITE encounters, which resolve exactly as
			# they did. -1 is the right answer for every monster such a save holds.
			"pen": int(md.get("pen", -1)),
		})
	# JSON has no integer keys: every cell comes back as the STRING "42". Restoring this
	# without the conversion leaves a dictionary that looks full and answers nothing,
	# because every lookup is by int — a save would silently lose every creature on the
	# floor and the sprites would all fall back to the generic brute.
	enemy_of = {}
	var raw = d.get("enemy_of", {})
	if raw is Dictionary:
		for k in raw:
			enemy_of[int(String(k))] = String(raw[k])
	# The same conversion, and the same silence without it: a chest whose tier is filed under
	# the string "42" is a chest the floor draws as worn and the screen opens as worn, having
	# been sealed until the run was saved.
	chest_of = {}
	var raw_chests = d.get("chest_of", {})
	if raw_chests is Dictionary:
		for k in raw_chests:
			if String(raw_chests[k]) in Balance.PACK_TIERS:
				chest_of[int(String(k))] = String(raw_chests[k])
	# A chest on this floor with no tier is one from a save that predates them, or one whose
	# tier failed to survive the blob. Cast now rather than at the lid, so the tile the player
	# is looking at is the chest they will get.
	for i in enc.size():
		if int(enc[i]) == Enc.TREASURE and not chest_of.has(i):
			chest_of[i] = Balance.roll_pack_tier(Balance.PACK_TREASURE,
				dungeon.difficulty if dungeon != null else 1)

	# --- the dressing back out of the save (D176/D177) -------------------------------
	#
	# A save from before any of this existed gets a bare floor rather than a redressed one,
	# and that is the correct answer twice over: the run it belongs to was played on a bare
	# floor, and re-rolling the dressing on load is exactly the thing `_save` writes it down
	# to prevent. The one field that IS re-derived is the light field, because it is a
	# function of `lights` and nothing else.
	props = PackedInt32Array()
	for p in d.get("props", []):
		props.append(maxi(0, int(p)))
	while props.size() < enc.size():
		props.append(0)
	room_role = []
	for r in d.get("room_role", []):
		room_role.append(String(r) if String(r) in Balance.ISO_ROOM_ROLES
			else Balance.ISO_ROOM_ROLE_DEFAULT)
	while room_role.size() < rooms:
		room_role.append(Balance.ISO_ROOM_ROLE_DEFAULT)
	lights = []
	for l in d.get("lights", []):
		var ld: Dictionary = l
		var lc := int(ld.get("cell", -1))
		if lc >= 0 and lc < enc.size():
			lights.append({"cell": lc, "warm": bool(ld.get("warm", true))})
	landmark = int(d.get("landmark", -1))
	if landmark < 0 or landmark >= enc.size() or int(enc[landmark]) != WALL:
		landmark = -1
	landmark_kind = posmod(int(d.get("landmark_kind", 0)), Balance.ISO_LANDMARKS.size())
	# Which surface and which architecture this floor was BUILT as, not what the tables say
	# today: the drift rule is a function of depth (D177), and a save whose floor was laid
	# out under a different table has to come back looking like the floor it was.
	terrain = String(d.get("terrain", ""))
	if not (terrain in Balance.ISO_TERRAINS):
		terrain = Balance.iso_terrain(String(dungeon.id) if dungeon != null else "",
			depth, floors)
	style_name = String(d.get("style_name", ""))
	if not Balance.ISO_STYLES.has(style_name):
		style_name = Balance.iso_style_name(String(dungeon.id) if dungeon != null else "",
			depth, floors)
	# Pockets back out of the save (D182). A blob from before they existed simply has none,
	# which is the right answer: that floor was laid out without any, and its rock has
	# nothing behind it. Every cell is checked against the grid on the way in for the reason
	# every id in `MetaState._apply` is — a pocket indexing off the end of a smaller floor
	# would be an option pointing at a cell that is not there.
	pockets = []
	for pk in d.get("pockets", []):
		var pd: Dictionary = pk
		var cells: Array = []
		for c in pd.get("cells", []):
			var ci := int(c)
			if ci >= 0 and ci < enc.size():
				cells.append(ci)
		var mouth := int(pd.get("mouth", -1))
		if cells.is_empty() or mouth < 0 or mouth >= enc.size():
			continue
		var prize := String(pd.get("prize", Balance.POCKET_NOTHING))
		# The guard is an archetype id and is checked against the ROSTER on the way in, the
		# way every other cast creature is: a save naming a creature this build no longer has
		# would otherwise put an unfightable thing in front of the prize.
		var guard := String(pd.get("guard", ""))
		if guard != "" and not (guard in Balance.roster_pool(dungeon, Balance.Tier.ELITE)):
			guard = ""
		var lock := String(pd.get("lock", Balance.POCKET_LOCK_NONE))
		pockets.append({"mouth": mouth, "cells": cells,
			"prize": prize if prize in Balance.POCKET_PRIZES else Balance.POCKET_NOTHING,
			"guard": guard,
			"lock": lock if lock == Balance.POCKET_LOCK_KEY else Balance.POCKET_LOCK_NONE,
			"toll": String(pd.get("toll", "")) if String(pd.get("toll", "")) in Balance.TOLLS
				else "",
			"missed": bool(pd.get("missed", false)),
			"open": bool(pd.get("open", false))})
	# The aspect is part of WHICH VISIT this run is, so it is saved rather than re-derived: a
	# clear banked mid-session would otherwise change the dungeon under a resumed run.
	deep = bool(d.get("deep", false))
	caught_ever = bool(d.get("caught_ever", false))
	aspect = String(d.get("aspect", Balance.ASPECT_NONE))
	if not (aspect in Balance.ASPECTS):
		aspect = Balance.ASPECT_NONE
	# A floor state is run state and outlives a quit: a player who paid a stone and saved must
	# come back to the floor they bought, not the one they walked in on (D188).
	floor_state = String(d.get("floor_state", Balance.ASPECT_NONE))
	if not (floor_state in Balance.ASPECTS):
		floor_state = Balance.ASPECT_NONE
	shrine = int(d.get("shrine", -1))
	if shrine < 0 or shrine >= enc.size() or int(enc[shrine]) != SHRINE:
		shrine = -1
	sites = []
	for sc in d.get("sites", []):
		var si := int(sc)
		if si >= 0 and si < enc.size():
			sites.append(si)
	errandplan = []
	for e in d.get("errandplan", []):
		errandplan.append(String(e) if String(e) in Balance.ERRANDS else "")
	while errandplan.size() < floors:
		errandplan.append("")
	errand = String(d.get("errand", ""))
	if not (errand in Balance.ERRANDS):
		errand = ""
	errand_seen = bool(d.get("errand_seen", false))
	errand_pushed = bool(d.get("errand_pushed", false))
	errand_chests = maxi(0, int(d.get("errand_chests", 0)))
	pocketplan = []
	for row in d.get("pocketplan", []):
		var prizes: Array = []
		for pz in row:
			var e: Dictionary = pz
			var pzn := String(e.get("prize", ""))
			if pzn in Balance.POCKET_PRIZES:
				var lk := String(e.get("lock", Balance.POCKET_LOCK_NONE))
				var tl := String(e.get("toll", ""))
				prizes.append({"prize": pzn, "guard": bool(e.get("guard", false)),
					"lock": lk if lk == Balance.POCKET_LOCK_KEY else Balance.POCKET_LOCK_NONE,
					"toll": tl if tl in Balance.TOLLS else ""})
		pocketplan.append(prizes)
	while pocketplan.size() < floors:
		pocketplan.append([])
	_build_light()

	# The tile you stand on is ground you have seen and stood on — that is true of every
	# healthy save already, so this costs one idempotent reveal, and it is what a save
	# whose flags were flattened by the D140 bug comes back on. Those saves have no
	# exploration left to recover; without this they resume onto an entirely unlit floor,
	# which is a blank screen rather than a dungeon. With it the player is back in a lit
	# room, having lost only the map behind them.
	if enc.size() > 0:
		walked[pos] = 1
		_reveal_around(pos)

## One grid of flags back out of a save, at exactly `want` cells whatever the blob holds.
##
## Three shapes reach here and all three have shipped:
##
## * an Array of numbers — what `_save` writes now;
## * a String — what it wrote between D99 and D140, because `JSON.stringify` fell
##   through to `str(PackedByteArray)`. It is valid JSON in its own right, so it is
##   parsed rather than dropped and an affected save keeps its explored floor;
## * anything else, including a missing key — zeroed.
##
## It never iterates a String directly. `for s in "[1, 0]"` walks CHARACTERS, and
## `bool("[")` is not a conversion GDScript has: it raised at the first cell, which
## aborted this function mid-loop and returned a grid of length ZERO. That is what
## turned a bad save into a broken screen rather than a dim one — `lit()` and
## `trodden()` index this per tile per frame, so every draw was an out-of-bounds read
## and the floor came up empty (D140).
func _bools(src, want: int) -> PackedByteArray:
	var out := PackedByteArray()
	var rows = src
	if rows is String:
		rows = JSON.parse_string(rows)
	if rows is Array or rows is PackedByteArray or rows is PackedInt32Array:
		for s in rows:
			if out.size() >= want:
				break
			out.append(1 if int(s) != 0 else 0)
	while out.size() < want:
		out.append(0)
	return out

# --- for the view -------------------------------------------------------------

func grid() -> Vector2i:
	return Vector2i(w, h)

func cell(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return WALL
	return int(enc[y * w + x])

func lit(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return bool(seen[y * w + x])

## Ground you have stood on, as opposed to ground you have only looked at.
func trodden(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return bool(walked[y * w + x])

## The archetype standing on this tile, or "" if it holds no fight. The view turns it into
## a silhouette through `Balance.iso_family`.
func enemy_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return ""
	return String(enemy_of.get(y * w + x, ""))

## The tier of the chest on this tile, or "" if it holds no chest. The view draws the lock
## from it and the hint line names it, so what a chest wants is answerable from the doorway.
func chest_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return ""
	return String(chest_of.get(y * w + x, ""))

## Which decoration lies on this tile, as one of `Balance.ISO_PROP_SHAPES`, or "" for a bare
## one (D176). The shape and not the whole entry: the view has one drawing per shape and
## needs nothing else, and returning a Dictionary per tile per frame would allocate 144
## times a redraw for a string.
func prop_shape(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return ""
	var p := int(props[y * w + x]) - 1
	if p < 0:
		return ""
	var kinds: Array = Balance.iso_props(terrain)
	if p >= kinds.size():
		return ""
	return String((kinds[p] as Dictionary).get("shape", ""))

## How lit this tile is, 0 (only whatever the floor has) to 1 (a source is standing on it).
func light(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= w or y >= h or _light.size() != enc.size():
		return 0.0
	return _light[y * w + x]

## What colour that light is: +1 for fire, -1 for daylight from above, 0 for neither.
func light_hue(x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= w or y >= h or _light_hue.size() != enc.size():
		return 0.0
	return _light_hue[y * w + x]

## What the chamber at this tile WAS, or "" for a corridor (D176). The view dresses by it;
## nothing else reads it.
func room_role_at(x: int, y: int) -> String:
	var r := chamber(x, y)
	if r < 0 or r >= room_role.size():
		return ""
	return String(room_role[r])

## Which chamber a tile belongs to, or -1 for a corridor. The view uses it to tell a
## hall from a passage.
func chamber(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return int(room_of[y * w + x])

## Cells holding a wanderer you can currently SEE, as
## {cell: {"type": Enc, "design": int, "south": bool}}. Deliberately not sticky,
## unlike terrain: the map is remembered and the monsters are not, so the floor behind
## you is known ground with unknown things on it.
func threats() -> Dictionary:
	var out := {}
	var dist := _dist_from(pos)
	for m in mons:
		var c := int(m["cell"])
		var d := int(dist[c])
		if d >= 0 and d <= _sight():
			out[c] = {"type": int(m["type"]), "design": int(m.get("design", 0)),
				"south": bool(m.get("south", true)),
				"enemy": String(m.get("enemy", ""))}
	return out

## A tile you have not been near that adjoins one you have: the edge of what you know.
## Drawn so the player can see the floor continues without being told what is on it.
func frontier(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var i := y * w + x
	if int(enc[i]) == WALL or bool(seen[i]):
		return false
	for n in _neighbours(i):
		if int(enc[n]) != WALL and bool(seen[n]):
			return true
	return false
