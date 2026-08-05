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
## Fights slipped past rather than had. Counts for the whole dungeon, not the floor,
## because the price rises with each one and a fresh floor is not a fresh start — the same
## shape the old deck model's `avoided` had, and for the same reason.
var avoided: int = 0
## How many fights this dungeon offers a slip past, across all its floors. Decided once,
## at generation, because the PRICE of each dodge is solved from the total (see
## `Balance.avoid_cost`) and a price that changed as you resolved encounters would make
## the first slip cheaper the longer you put it off.
##
## Counted here rather than derived from the mix by anyone who needs it: wanderers come
## out of the combat budget and cannot be slipped past, and that subtraction happens in
## `generate` below. Deriving it a second time somewhere else is how the number went
## stale the first time (D99).
var dodgeable: int = 0
var done: bool = false

## Floors, and what is still to be laid out on the ones not yet reached. `plan[i]` is
## the list of Enc values for floor i and `roam[i]` how many of them walk; both are
## consumed by `_build_floor`. Held here rather than generated per floor so the whole
## dungeon's budget is decided once, up front, and cannot drift as you descend.
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
## {"cell": int, "type": Enc, "awake": bool, "design": int, "south": bool}.
## An entry is removed when its fight is won.
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
	# Wanderers come OUT of the combat budget, never on top of it: a dungeon has to
	# cost what its difficulty says (D14), so this decides how much of the budget
	# hunts you rather than how much of it there is.
	var combats := 0
	for e in budget:
		if int(e) == Enc.COMBAT:
			combats += 1
	var roaming := Balance.iso_wanderers_for(combats)
	for i in roaming:
		budget.erase(Enc.COMBAT)

	# Everything left in the budget that STANDS on a tile and can be slipped past. The
	# boss is not in `budget` and can never be dodged; the wanderers were just removed.
	dodgeable = 0
	for e in budget:
		if int(e) == Enc.COMBAT or int(e) == Enc.ELITE:
			dodgeable += 1

	var diff: int = dungeon.difficulty if dungeon != null else 1
	floors = Balance.iso_floors_for(diff)
	# The budget is SPLIT across the floors, not repeated on each. Dealing it round
	# robin after a shuffle keeps every floor mixed — dealing it in order would put
	# all the combats on floor one and all the shops on the last.
	budget.shuffle()
	plan = []
	roam = []
	for f in floors:
		plan.append([])
		roam.append(0)
	for i in budget.size():
		plan[i % floors].append(int(budget[i]))
	for i in roaming:
		roam[i % floors] = int(roam[i % floors]) + 1
	# +1 for the boss, which sits on the last floor and is not in `budget`
	quota = budget.size() + roaming + 1
	_plan_chests(diff)

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
	var n_cells := w * h
	enc.resize(n_cells)
	enc.fill(WALL)
	seen.resize(n_cells)
	seen.fill(0)
	walked.resize(n_cells)
	walked.fill(0)
	room_of.resize(n_cells)
	room_of.fill(-1)

	var style := Balance.iso_style(String(dungeon.id) if dungeon != null else "")
	var rects := _place_rooms(style, Balance.iso_tiles_per_floor(floors))
	rooms = rects.size()
	_connect(rects, int(style["loops"]))
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
	_spawn(int(roam[depth]), carved, dist)
	_cast_fights()
	_cast_chests()
	# Keys go down LAST, so they take the ground nothing else wanted — which is the
	# whole mechanic: a key is somewhere you would not otherwise have walked.
	_place_keys(int(keyplan[depth]) if depth < keyplan.size() else 0, carved)

	content = 0
	for i in enc.size():
		if int(enc[i]) >= 0:
			content += 1

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
	var room_area: int = int(round(float(target) * float(style.get("fill", 0.75))))
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
	for i in out.size():
		var r: Rect2i = out[i]
		for yy in range(r.position.y, r.end.y):
			for xx in range(r.position.x, r.end.x):
				var c: int = yy * w + xx
				enc[c] = EMPTY
				room_of[c] = i
	return out

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
func _connect(rects: Array, loops: int) -> void:
	if rects.size() < 2:
		return
	for i in range(1, rects.size()):
		_dig(_centre(rects[i - 1]), _centre(rects[i]))
	for l in loops:
		var a: int = randi() % rects.size()
		var b: int = randi() % rects.size()
		if a != b:
			_dig(_centre(rects[a]), _centre(rects[b]))

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

## Decide WHICH enemy every fight on this floor is, now rather than when it starts.
##
## Drawn from exactly the pool `CombatEngine` would have rolled from (`Balance.roster_pool`
## at the tile's own tier), so the enemy distribution is unchanged — this moves *when* the
## choice happens, not *what* gets chosen. That is what lets the sprite standing on a tile
## be honest without repricing anything (D85).
##
## Bosses are left out on purpose: a dungeon's finale is named and fixed, and combat
## already resolves it from `DungeonData.boss`.
func _cast_fights() -> void:
	var normal := Balance.roster_pool(dungeon, Balance.Tier.NORMAL)
	var elite := Balance.roster_pool(dungeon, Balance.Tier.ELITE)
	for i in enc.size():
		var e := int(enc[i])
		if e == Enc.COMBAT and not normal.is_empty():
			enemy_of[i] = String(normal[randi() % normal.size()])
		elif e == Enc.ELITE and not elite.is_empty():
			enemy_of[i] = String(elite[randi() % elite.size()])
	for m in mons:
		if String(m.get("enemy", "")) == "" and not normal.is_empty():
			m["enemy"] = String(normal[randi() % normal.size()])

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

## Put this floor's wanderers on it, in the far half. Spawning them anywhere would
## sometimes drop one on the entrance, which is a fight before the first decision —
## the one thing every model guarantees you do not get.
func _spawn(count: int, carved: Array, dist_from_entry: Array) -> void:
	if count <= 0:
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
	for k in count:
		mons.append({
			"cell": int(far_enough[k % far_enough.size()]),
			"type": Enc.COMBAT,
			"awake": false,
			# vary by floor as well as by index, or every floor fields the same two
			"design": (k + depth) % 4,
			"south": true,
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
		if d >= 0 and d <= Balance.ISO_SIGHT:
			seen[j] = true

# --- the floor takes its turn --------------------------------------------------

## Wake every wanderer within earshot of `cell`. A fight is loud, so where you choose
## to have one is a decision: clearing a room next to something asleep is no longer
## free. This is the one place the battle system reaches back into the space.
func _rouse(cell: int, radius: int) -> void:
	var dist := _dist_from(cell)
	for m in mons:
		var d := int(dist[int(m["cell"])])
		if d >= 0 and d <= radius:
			m["awake"] = true

## Every wanderer steps once. Awake ones close on the player; the rest drift.
##
## A wanderer never steps ONTO the player: it holds its ground and is returned as the
## one that caught you. Sharing the tile would mean drawing a monster under the player
## and, worse, one standing on a tile the player is about to fight something else in —
## the tile's own encounter resolves first, and the wanderer is still there after,
## adjacent, waiting.
##
## Returns the index of the wanderer now engaging the player, or -1.
func _floor_turn(field: PackedInt32Array = PackedInt32Array()) -> int:
	var engaging := -1
	var dist := field if field.size() == enc.size() else _dist_from(pos)
	for k in mons.size():
		var m: Dictionary = mons[k]
		var here := int(m["cell"])
		var away := int(dist[here])
		if away >= 0 and away <= Balance.ISO_WANDER_SENSE:
			m["awake"] = true
		if away == 0:
			# You walked onto it. This is the other half of contact and it has to be
			# checked FIRST: the awake branch below only closes distance when there is
			# distance to close, so at zero a wanderer fell through to the drift branch
			# and stepped politely aside. A greedy walker then chased it round the floor
			# for ever, because the thing blocking the way on was the thing it could
			# never catch — 12 runs in 360, the D74 deadlock wearing a new hat.
			if engaging < 0:
				engaging = k
			continue
		var target := -1
		if bool(m["awake"]):
			# one step closer, chosen off the player's own distance field so a wanderer
			# follows the floor round corners instead of pressing into rock
			var bestd := away
			for n in _neighbours(here):
				if int(enc[n]) == WALL:
					continue
				var dn := int(dist[n])
				if dn >= 0 and dn < bestd:
					bestd = dn
					target = n
		else:
			var cand: Array = []
			for n in _neighbours(here):
				if int(enc[n]) != WALL and n != pos:
					cand.append(n)
			if not cand.is_empty():
				target = int(cand[randi() % cand.size()])
		if target == pos:
			# it has reached you: it stays where it is and the fight is the result
			if engaging < 0:
				engaging = k
			continue
		if target >= 0:
			# Facing, for the view only. Both grid axes point AWAY from the viewer on
			# screen (x is ↘, y is ↙, per DIR_ARROW), so a step whose components sum
			# positive is a step toward the camera and shows the thing's front.
			var dx := target % w - here % w
			var dy := int(target / w) - int(here / w)
			m["south"] = (dx + dy) > 0
			m["cell"] = target
	return engaging

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
		if e >= 0 and e != Enc.BOSS:
			others += 1
	others += mons.size()   # a wanderer is unfinished business too
	var goal := _dist_to_unresolved(others > 0)

	var out: Array = []
	for d in DIRS.size():
		var n := _step(pos, DIRS[d])
		if n < 0 or int(enc[n]) == WALL:
			continue
		var e := int(enc[n])
		var rank := 1                          # a step across open ground
		if e >= 0 and e != Enc.BOSS:
			rank = 0                           # something to do
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
		# ...and, for a fight, the option of not having it. See `_slip_cost`.
		if e == Enc.COMBAT or e == Enc.ELITE:
			var cost := _slip_cost()
			out.append({
				"type": e,
				"label": "%s  Slip past %s (-%d HP%s)" % [DIR_ARROW[d],
					String(Balance.NODE_LABEL.get(e, "?")), cost,
					", rising" if avoided > 0 else ""],
				"cell": n,
				"dir": d,
				"resolves": false,
				"action": "avoid",
				"hp_cost": cost,
				# Ranked BELOW even the way down, so the first button is never "skip the
				# game". A player leaning on it faces everything, which is also what makes
				# the headless walkers measure the full budget (D14).
				"order": 3000000 + n,
			})
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out

## What squeezing past a fight costs, instead of having it.
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
	if e == Enc.TREASURE and chest_of.has(n):
		# The tier IS the lock, so naming it names what the chest wants (D172).
		return "%s chest" % Balance.PACK_TIER_NAME.get(String(chest_of[n]), "Worn")
	if e >= 0:
		return String(Balance.NODE_LABEL.get(e, "?"))
	if not bool(seen[n]):
		return "Into the dark"
	if bool(walked[n]):
		return "Back the way you came"
	return "Open ground"

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
	if i < 0 or i >= opts.size():
		return {}
	var o: Dictionary = opts[i]
	var target := int(o["cell"])
	var was := int(enc[target])

	# The stairs are not a move across the floor, they are the end of it: descending
	# replaces everything, so nothing below this line would mean anything.
	if was == STAIR:
		steps += 1
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

	# Slipping past: you take the tile and the fight does not happen. The HP price is
	# reported on the option and paid by whoever owns the HP (D13), exactly as the deck
	# model's dodge is — this method only clears the ground and counts it.
	if String(o.get("action", "")) == "avoid":
		enc[pos] = EMPTY
		enemy_of.erase(pos)
		avoided += 1
		# One flood, used twice. Clearing the tile above cannot change it: only WALL
		# blocks a step, and this tile was already walkable.
		var field0 := _dist_from(pos)
		_reveal_around(pos, field0)
		_floor_turn(field0)
		return {}

	var field := _dist_from(pos)
	_reveal_around(pos, field)
	# Greed wakes the floor. Not extra monsters — that would inflate the encounter
	# budget — just the ones already counted, which is pressure that cannot cheat.
	if floor_steps == Balance.ISO_LINGER:
		_rouse(pos, w * h)
	var caught := _floor_turn(field)

	if int(enc[pos]) >= 0:
		pending = {"type": int(enc[pos]), "cell": pos}
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
		var m: Dictionary = mons[caught]
		# `ambush` is a PRICE, reported and not applied: a traversal never touches run
		# resources (D13), exactly as the old deck model reported its dodge and let the
		# caller pay. Whoever owns the HP charges Balance.iso_ambush_cost.
		pending = {"type": int(m["type"]), "cell": pos, "mon": caught, "ambush": true}
		if String(m.get("enemy", "")) != "":
			pending["enemy"] = String(m["enemy"])
		return pending
	return {}

func clear_pending() -> void:
	_invalidate()
	if pending.is_empty():
		return
	var cell: int = int(pending.get("cell", pos))
	var kind_of := int(pending.get("type", Enc.COMBAT))
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
	cleared += 1
	pending = {}
	# A fight is loud. Anything else — a shop, a rest, a chest — is not.
	if kind_of == Enc.COMBAT or kind_of == Enc.ELITE:
		_rouse(cell, Balance.ISO_NOISE)

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
		"keyplan": keyplan, "chestplan": chestplan}

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
	roam = []
	for r in d.get("roam", []):
		roam.append(int(r))
	while roam.size() < floors:
		roam.append(0)
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
			"awake": bool(md.get("awake", false)),
			"design": int(md.get("design", 0)),
			"south": bool(md.get("south", true)),
			"enemy": String(md.get("enemy", "")),
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
		if d >= 0 and d <= Balance.ISO_SIGHT:
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
