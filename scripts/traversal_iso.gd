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
## * **What you walk to is a chest.** A treasure tile is one of D84's chests, with its
##   own tier, its own lock and the run's own keys — so covering ground pays without this
##   model needing a lock of its own. It had one for a while (a sealed dead-end room) and
##   D86 removed it: two locks and two key currencies for one idea.
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

## Grid steps, and the screen direction each one reads as once the floor is drawn
## at an angle. The arrows are the projected directions, not compass ones: a floor
## turned 45 degrees would otherwise tell the player "north" and move them
## down-right.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIR_ARROW := ["↘", "↖", "↙", "↗"]

var w: int = 0
var h: int = 0
var enc: Array = []     ## w*h cells: WALL, EMPTY, a feature, or an Enc value
var seen: Array = []    ## w*h bools: ground you have been near
## w*h bools: ground you have actually STOOD on. Distinct from `seen` because this is
## a model about coverage, and on a floor that is mostly open ground "have I been
## here?" is the question the player is actually asking — when every tile held an
## encounter its contents answered it, and now four exits in a row all read
## "Open ground" unless something tells them apart.
var walked: Array = []
## w*h ints: which chamber a tile belongs to, or -1 for a corridor. Drives the
## reveal, and is what lets the view tell a hall from a passage.
var room_of: Array = []
## cell -> enemy archetype id, for the tiles that hold a fight. Decided when the floor is
## laid out rather than when the fight starts, because the thing STANDING there has to be
## the thing you end up fighting: before this the sprite was an arbitrary index and the
## enemy was rolled at combat setup, so the floor was showing the player a creature that
## had nothing to do with what came next (D85).
var enemy_of: Dictionary = {}
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
var done: bool = false

## Floors, and what is still to be laid out on the ones not yet reached. `plan[i]` is
## the list of Enc values for floor i and `roam[i]` how many of them walk; both are
## consumed by `_build_floor`. Held here rather than generated per floor so the whole
## dungeon's budget is decided once, up front, and cannot drift as you descend.
var floors: int = 1
var depth: int = 0
var plan: Array = []
var roam: Array = []

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

	_build_floor(0)

## Lay out one floor and stand the player at its entrance. Called by `generate` for
## floor 0 and by `select` on every descent, which is why every per-floor field is
## reset here rather than in `generate`.
func _build_floor(d: int) -> void:
	depth = clampi(d, 0, floors - 1)
	floor_steps = 0
	mons = []
	enemy_of = {}
	enc = []
	seen = []
	walked = []
	room_of = []
	for i in w * h:
		enc.append(WALL)
		seen.append(false)
		walked.append(false)
		room_of.append(-1)

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
func _dist_from(start: int) -> Array:
	var dist: Array = []
	for i in enc.size():
		dist.append(-1)
	if start < 0 or start >= enc.size() or int(enc[start]) == WALL:
		return dist
	dist[start] = 0
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: int = int(queue.pop_front())
		for n in _neighbours(cur):
			if int(enc[n]) != WALL and int(dist[n]) < 0:
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
	return dist

## Steps from every tile to the nearest of `sources`. One flood from all of them at
## once, which is the same answer as a BFS per source without multiplying by how many
## there are.
func _dist_to_any(sources: Array) -> Array:
	var dist: Array = []
	for i in enc.size():
		dist.append(-1)
	var queue: Array = []
	for s in sources:
		var i := int(s)
		if i >= 0 and i < enc.size() and int(enc[i]) != WALL and int(dist[i]) < 0:
			dist[i] = 0
			queue.append(i)
	while not queue.is_empty():
		var cur: int = int(queue.pop_front())
		for n in _neighbours(cur):
			if int(enc[n]) != WALL and int(dist[n]) < 0:
				dist[n] = int(dist[cur]) + 1
				queue.append(n)
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
func _dist_to_unresolved(skip_exit: bool) -> Array:
	var dist: Array = []
	var queue: Array = []
	for i in enc.size():
		dist.append(-1)
	for i in enc.size():
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
		queue.append(i)
	for m in mons:
		var c := int(m["cell"])
		if int(dist[c]) < 0 and int(enc[c]) != WALL:
			dist[c] = 0
			queue.append(c)
	while not queue.is_empty():
		var cur: int = int(queue.pop_front())
		for n in _neighbours(cur):
			if int(enc[n]) == WALL or int(dist[n]) >= 0:
				continue
			if skip_exit and _is_exit(n):
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	return dist

func _is_exit(i: int) -> bool:
	var e := int(enc[i])
	return e == STAIR or e == Enc.BOSS

## What you can make out from where you stand. **A chamber is revealed whole**; a
## corridor gives you `Balance.ISO_SIGHT` steps and no more. That contrast is the
## point — the old uniform radius made every floor feel like the same field, and this
## is what gives a dungeon the moment where a hall opens up in front of you.
func _reveal_around(i: int) -> void:
	seen[i] = true
	var r := int(room_of[i])
	if r >= 0:
		for j in enc.size():
			if int(room_of[j]) == r:
				seen[j] = true
	var dist := _dist_from(i)
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
func _floor_turn() -> int:
	var engaging := -1
	var dist := _dist_from(pos)
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
func options() -> Array:
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
## fourth should be unaffordable. Deliberately the SAME number, because it is the same
## decision — D88 moved every dungeon onto this model, and the deck's dodge was the thing
## that made a deck dungeon cost what it cost.
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
	return Balance.avoid_cost(diff, avoided)

## What a step reads as. Bare ground gets three different names because a row of
## identical "Open ground" buttons is a choice with no information in it: is there
## anything there, have I been there, and if not, do I even know what I am walking
## into?
func _describe(n: int) -> String:
	var e := int(enc[n])
	match e:
		STAIR:
			return "Stairs down"
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

	# Slipping past: you take the tile and the fight does not happen. The HP price is
	# reported on the option and paid by whoever owns the HP (D13), exactly as the deck
	# model's dodge is — this method only clears the ground and counts it.
	if String(o.get("action", "")) == "avoid":
		enc[pos] = EMPTY
		enemy_of.erase(pos)
		avoided += 1
		_reveal_around(pos)
		_floor_turn()
		return {}

	_reveal_around(pos)
	# Greed wakes the floor. Not extra monsters — that would inflate the encounter
	# budget — just the ones already counted, which is pressure that cannot cheat.
	if floor_steps == Balance.ISO_LINGER:
		_rouse(pos, w * h)
	var caught := _floor_turn()

	if int(enc[pos]) >= 0:
		pending = {"type": int(enc[pos]), "cell": pos}
		# The archetype the floor has been SHOWING the player, handed on so the fight is
		# the creature they walked up to. A tile with no cast enemy (a shop, a rest, the
		# boss) simply omits it and the caller rolls as it always did.
		if enemy_of.has(pos):
			pending["enemy"] = String(enemy_of[pos])
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
		# the tile is bare ground now, so it has no enemy standing on it either
		enemy_of.erase(cell)
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
	# Kept terse deliberately: this shares one header line with HP, deck, gold and the
	# at-risk totals, and an earlier wording pushed that line onto a second row.
	var out := "Floor %d/%d   %d/%d cleared   %d/%d mapped" % [
		depth + 1, floors, cleared, maxi(1, quota), mapped, maxi(1, tiles)]
	if mons.size() > 0:
		out += "   %d prowling" % mons.size()
	return out

func _save() -> Dictionary:
	return {"w": w, "h": h, "enc": enc, "seen": seen, "walked": walked,
		"room_of": room_of, "pos": pos, "tiles": tiles, "content": content,
		"rooms": rooms, "quota": quota, "steps": steps, "floor_steps": floor_steps, "avoided": avoided,
		"done": done, "mons": mons, "enemy_of": enemy_of,
		"floors": floors, "depth": depth, "plan": plan, "roam": roam}

func _load(d: Dictionary) -> void:
	w = int(d.get("w", Balance.ISO_GRID))
	h = int(d.get("h", Balance.ISO_GRID))
	# JSON has no ints and no typed arrays: every cell comes back as a float
	enc = []
	for e in d.get("enc", []):
		enc.append(int(e))
	seen = _bools(d.get("seen", []), enc.size())
	walked = _bools(d.get("walked", []), enc.size())
	room_of = []
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

func _bools(src, want: int) -> Array:
	var out: Array = []
	for s in src:
		out.append(bool(s))
	while out.size() < want:
		out.append(false)
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
