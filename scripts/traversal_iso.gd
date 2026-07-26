## Isometric floor crawl. The dungeon is a floor of rooms seen at an angle, and
## you walk it a room at a time by torchlight.
##
## Decision texture: this is the only model where the ground is SPATIAL and can be
## re-walked. The graph makes you commit to a route before you can see what is on
## it; the deck reveals one encounter and prices the dodge; the dice make you
## manage overshoot. Here you can see the rooms next to you and nothing past them,
## you may go back the way you came, and **the stair down is not marked** — it is
## somewhere on the floor. So a run is a question of coverage: how much of the
## floor do you strip before you take the stairs you have just found?
##
## Two rules are what make that a decision rather than a chore:
##
## * **Every room holds something.** There are no empty corridors to pad the
##   floor, so a route is a plan and not a stroll to a marked exit.
## * **Light runs out.** The torch pays for a tidy tour of the whole floor. It
##   does not pay for crossing explored ground twice more to come back for the
##   last treasure. Past that, every step costs HP — the mirror image of the deck
##   model's priced dodge (`Balance.deck_avoid_cost`): there you pay to see *less*
##   of a dungeon, here you pay to see *more* of one.
##
## Balance contract: the stair is placed as far from the entrance as the floor
## allows and is hidden until the torch reaches it, so a player cannot beeline
## past the encounter budget the other three models spend. `options()` also orders
## the stair LAST while any room is unexplored, which is both the safe default for
## a player leaning on the first choice and what makes the headless walkers spend
## a full floor.
##
## Pure logic, like every model: it never reads or writes run resources. The HP
## price of a step in the dark is reported on the option as `hp_cost` and paid by
## whoever owns the HP, exactly as the deck model's dodge is.
class_name TraversalIso
extends Traversal

## Cell contents. Anything >= 0 is an Enc value waiting to be resolved.
const WALL := -2    ## not a room: solid rock
const EMPTY := -1   ## a room with nothing left in it

## Grid steps, and the screen direction each one reads as once the floor is drawn
## at an angle. The arrows are the projected directions, not compass ones: a floor
## turned 45 degrees would otherwise tell the player "north" and move them
## down-right.
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIR_ARROW := ["↘", "↖", "↙", "↗"]

var w: int = 0
var h: int = 0
var enc: Array = []    ## w*h cells: WALL, EMPTY, or an Enc value
var seen: Array = []    ## w*h bools: rooms the torch has shown you
var pos: int = 0        ## cell the player stands in
var torch: int = 0      ## steps of light left
var rooms: int = 0      ## walkable rooms on the floor, for progress
var done: bool = false

func generate(p_dungeon) -> void:
	dungeon = p_dungeon
	cleared = 0
	pending = {}
	done = false
	w = Balance.ISO_GRID
	h = Balance.ISO_GRID
	enc = []
	seen = []
	for i in w * h:
		enc.append(WALL)
		seen.append(false)

	# one room per budgeted encounter, plus the entrance and the stair
	var budget := standard_encounters(dungeon)
	var carved := _carve(budget.size() + 2)
	rooms = carved.size()

	# The entrance has to satisfy two things at once, and picking it badly costs one
	# of them:
	#
	# * **It branches.** The carve seeds from the middle of the grid and grows
	#   outward, so the seed room is usually a stub with ONE door — and a first move
	#   with a single option is not a move, it is a corridor with a button on it.
	#   Every other model opens on a choice.
	# * **The floor is deep from it.** Simply taking the room with the MOST doors
	#   gives the hub in the middle of the plate, and from the middle the furthest
	#   room is two steps away: the stair goes two steps from the entrance and the
	#   whole floor can be skipped by walking into it. Measured, and it is the
	#   difference between a floor and a puddle.
	#
	# So: of the rooms with at least two doors, the one the floor stretches furthest
	# from. Ties go to the lowest cell so a floor is a function of its seed alone.
	pos = int(carved[0])
	var best := -1
	for c in carved:
		var i := int(c)
		var doors := 0
		for n in _neighbours(i):
			if int(enc[n]) != WALL:
				doors += 1
		if doors < 2:
			continue
		var reach := _dist_from(i)
		var ecc := 0
		for j in enc.size():
			if int(enc[j]) != WALL:
				ecc = maxi(ecc, int(reach[j]))
		if ecc > best:
			best = ecc
			pos = i

	# The stair goes in the furthest room from the entrance. A floor you could
	# cross in three rooms would cost a fraction of what the graph, deck and dice
	# cost, and "difficulty 2" would stop meaning one thing.
	var dist := _dist_from(pos)
	var far: int = pos
	for c in carved:
		if int(dist[int(c)]) > int(dist[far]):
			far = int(c)
	enc[far] = Enc.BOSS

	budget.shuffle()
	var k := 0
	for c in carved:
		var i := int(c)
		if i == pos or i == far:
			continue
		if k >= budget.size():
			break   # cannot happen while the grid fits the budget; see test_traversal
		enc[i] = int(budget[k])
		k += 1

	torch = Balance.iso_torch_for(rooms)
	_reveal_around(pos)

## Carve a connected region of `want` rooms, preferring to extend the room just
## cut. A purely random pick would open one round hall (every room adjacent to
## every other, so no route is longer than another); always extending the newest
## room would draw a single corridor, where every dead end costs a double walk.
## Seven-in-ten favours the newest room, which gives a floor with a spine, a
## couple of branches, and the odd loop.
func _carve(want: int) -> Array:
	var out: Array = []
	var taken := {}
	var start: int = int(h / 2) * w + int(w / 2)
	out.append(start)
	taken[start] = true
	var guard := 0
	while out.size() < want and guard < w * h * 20:
		guard += 1
		var from: int = int(out[out.size() - 1]) if randi() % 10 < 7 else int(out[randi() % out.size()])
		if _grow_from(from, out, taken):
			continue
		# that room is boxed in by rooms already carved: grow anywhere that is not
		var grew := false
		for c in out:
			if _grow_from(int(c), out, taken):
				grew = true
				break
		if not grew:
			break   # the whole grid is carved
	for c in out:
		enc[int(c)] = EMPTY
	return out

func _grow_from(from: int, out: Array, taken: Dictionary) -> bool:
	var cand := _neighbours(from)
	cand.shuffle()
	for n in cand:
		if not taken.has(n):
			taken[n] = true
			out.append(n)
			return true
	return false

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

## Steps from `start` to every room, -1 for rock and anything unreachable.
func _dist_from(start: int) -> Array:
	var dist: Array = []
	for i in enc.size():
		dist.append(-1)
	if int(enc[start]) == WALL:
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

## Steps from every room to the nearest room that still holds something. Used to
## order a step across cleared ground by whether it actually goes anywhere.
##
## While there is still floor to explore, the stair room is neither a destination
## NOR a way through. Counting a route through it was a deadlock: on a floor where
## the short way round was through the stair, "one step closer" pointed at a room
## the ordering then refused to enter, and a greedy walker paced between the two
## for ever. It is also simply untrue — nobody walks through the boss to reach a
## shop. Blocking it cannot cut the floor in two, because the stair is placed at
## the furthest room from the entrance, and a furthest room can never be the only
## way to anywhere: whatever was behind it would be further still.
func _dist_to_unresolved(skip_boss: bool) -> Array:
	var dist: Array = []
	var queue: Array = []
	for i in enc.size():
		dist.append(-1)
	for i in enc.size():
		var e := int(enc[i])
		if e < 0:
			continue
		if skip_boss and e == Enc.BOSS:
			continue
		dist[i] = 0
		queue.append(i)
	while not queue.is_empty():
		var cur: int = int(queue.pop_front())
		for n in _neighbours(cur):
			var e2 := int(enc[n])
			if e2 == WALL or int(dist[n]) >= 0:
				continue
			if skip_boss and e2 == Enc.BOSS:
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	return dist

## Torchlight: the room you are in and every room adjoining it.
func _reveal_around(i: int) -> void:
	seen[i] = true
	for n in _neighbours(i):
		if int(enc[n]) != WALL:
			seen[n] = true

# --- interface ---

## One option per door out of this room. Ordered so the first is always the one
## that gets on with the floor: an unexplored room if one adjoins, otherwise a
## step toward the nearest one, and the stair only once nothing else is left.
func options() -> Array:
	if done:
		return []
	var others := 0
	for i in enc.size():
		var e := int(enc[i])
		if e >= 0 and e != Enc.BOSS:
			others += 1
	var goal := _dist_to_unresolved(others > 0)
	var diff: int = dungeon.difficulty if dungeon != null else 1
	var dark: int = Balance.iso_dark_cost(diff) if torch <= 0 else 0

	var out: Array = []
	for d in DIRS.size():
		var n := _step(pos, DIRS[d])
		if n < 0 or int(enc[n]) == WALL:
			continue
		var e := int(enc[n])
		var rank := 1                       # a step across ground already cleared
		if e >= 0 and e != Enc.BOSS:
			rank = 0                        # a room with something in it
		elif e == Enc.BOSS:
			rank = 0 if others == 0 else 2  # the stair: last, until it is all there is
		var what: String = String(Balance.NODE_LABEL.get(e, "?")) if e >= 0 else "Cleared"
		var label := "%s  %s" % [DIR_ARROW[d], what]
		if dark > 0:
			label += "   (-%d HP: the torch is out)" % dark
		var away: int = int(goal[n])
		var opt := {
			"type": e,
			"label": label,
			"cell": n,
			"dir": d,
			"resolves": e >= 0,
			# rank first, then how much closer this step gets to the work left, then
			# the cell itself so the order is a function of state alone — a restored
			# run has to present the same list in the same order (D22).
			"order": rank * 10000 + (away if away >= 0 else 99) * 100 + n,
		}
		if dark > 0:
			opt["hp_cost"] = dark
		out.append(opt)
	out.sort_custom(func(a, b): return int(a["order"]) < int(b["order"]))
	return out

## Walk through the chosen door. Returns the encounter in that room, or {} for a
## step onto ground already cleared.
##
## Any `hp_cost` on the option is NOT applied here — a traversal never touches run
## resources (D13). The caller pays it, the same as the deck model's dodge, and
## unlike that dodge it is charged on moves that DO resolve an encounter too.
func select(i: int) -> Dictionary:
	var opts := options()
	if i < 0 or i >= opts.size():
		return {}
	var o: Dictionary = opts[i]
	pos = int(o["cell"])
	torch = maxi(0, torch - 1)
	_reveal_around(pos)
	if not bool(o["resolves"]):
		return {}
	pending = {"type": int(enc[pos]), "cell": pos}
	return pending

func clear_pending() -> void:
	if pending.is_empty():
		return
	var cell: int = int(pending.get("cell", pos))
	if int(enc[cell]) == Enc.BOSS:
		done = true
	enc[cell] = EMPTY
	cleared += 1
	pending = {}

func progress() -> float:
	if rooms <= 1:
		return 0.0
	return float(cleared) / float(rooms - 1)

func is_complete() -> bool:
	return done

func status() -> String:
	return "%d/%d rooms   torch %d" % [cleared, maxi(1, rooms - 1), torch]

func kind() -> int:
	return Kind.ISO

func _save() -> Dictionary:
	return {"w": w, "h": h, "enc": enc, "seen": seen, "pos": pos,
		"torch": torch, "rooms": rooms, "done": done}

func _load(d: Dictionary) -> void:
	w = int(d.get("w", Balance.ISO_GRID))
	h = int(d.get("h", Balance.ISO_GRID))
	# JSON has no ints and no typed arrays: every cell comes back as a float
	enc = []
	for e in d.get("enc", []):
		enc.append(int(e))
	seen = []
	for s in d.get("seen", []):
		seen.append(bool(s))
	while seen.size() < enc.size():
		seen.append(false)
	pos = clampi(int(d.get("pos", 0)), 0, maxi(0, enc.size() - 1))
	torch = int(d.get("torch", 0))
	rooms = int(d.get("rooms", 0))
	done = bool(d.get("done", false))

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

## A room the torch has not reached that adjoins one it has: a doorway into the
## dark. Drawn so the player can see the floor continues without being told what
## is on it.
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
