## Slay-the-Spire style layered node graph (the original model, now behind the
## Traversal interface). Decision texture: pick a branch, trading node types
## against each other with imperfect foresight.
class_name TraversalGraph
extends Traversal

## Rows are DERIVED from the shared encounter budget, not hardcoded: the graph
## visits exactly one node per row, so row count *is* this model's encounter count.
## Hardcoding it silently broke the budget contract the moment new encounter types
## were added to the mix.
static func rows(dungeon_data = null) -> int:
	return Traversal.standard_encounters(dungeon_data).size() + 1  # +1 for the boss row

var map: Array = []            # map[row] = Array of node dicts
var current: Variant = null    # {row, col} of the node just cleared, or null at start

## Width of row `r`: alternating 2/3 lanes, narrowing to a single boss.
static func row_width(r: int, total: int) -> int:
	if r == total - 1:
		return 1
	if r == total - 2:
		return 2
	return 2 + (r % 2)

func generate(p_dungeon) -> void:
	dungeon = p_dungeon
	map = []
	current = null
	cleared = 0
	pending = {}
	var total := rows(dungeon)
	_weigh(dungeon)
	for r in total:
		var row: Array = []
		for col in row_width(r, total):
			row.append({"type": _roll_type(r, total), "row": r, "col": col, "edges": [], "cleared": false})
		map.append(row)
	# connect each node to 1-2 nodes in the next row
	for r in total - 1:
		var cur: Array = map[r]
		var nxt: Array = map[r + 1]
		var last := nxt.size() - 1
		for i in cur.size():
			var t := int(round(float(i) / max(1, cur.size() - 1) * last))
			var targets := {t: true}
			if (i + r) % 2 == 0:
				targets[clampi(t + 1, 0, last)] = true
			else:
				targets[clampi(t - 1, 0, last)] = true
			cur[i]["edges"] = targets.keys()
		# guarantee every next-row node is reachable
		for j in nxt.size():
			var has := false
			for i in cur.size():
				if j in cur[i]["edges"]:
					has = true
			if not has:
				var src := int(round(float(j) / max(1, last) * (cur.size() - 1)))
				cur[src]["edges"].append(j)

## Node-type weights taken from the dungeon's own encounter mix.
##
## This used to be five fixed percentages with COMBAT as the fallback, while the
## map's SIZE came from the mix — two sources of truth for one shape (the D34
## trap). It survived only because the mix sat near 8 for every dungeon. When
## chests took it to 13 (D84) the graph grew four rows and filled them with the
## fallback: measured at 7.2 fights per run against a mix that asks for 4, which
## made the graph model 2 points harder while the dice model got 5 easier — the
## equal-cost pillar (D14) broken by a generator that was never reading the mix.
var _weights: Array = []
var _types: Array = []

func _weigh(dungeon_data) -> void:
	var mix: Dictionary = {
		"combat": Balance.ENCOUNTER_COMBATS, "elite": Balance.ENCOUNTER_ELITES,
		"rest": Balance.ENCOUNTER_RESTS, "shop": Balance.ENCOUNTER_SHOPS,
		"event": Balance.ENCOUNTER_EVENTS, "treasure": Balance.ENCOUNTER_TREASURES,
	}
	if dungeon_data != null and dungeon_data.has_method("encounter_mix"):
		mix = dungeon_data.encounter_mix()
	_types = [Enc.COMBAT, Enc.ELITE, Enc.REST, Enc.SHOP, Enc.EVENT, Enc.TREASURE]
	_weights = [int(mix["combat"]), int(mix["elite"]), int(mix["rest"]),
		int(mix["shop"]), int(mix["event"]), int(mix["treasure"])]

func _roll_type(r: int, total: int) -> int:
	if r == total - 1:
		return Enc.BOSS
	if r == 0:
		return Enc.COMBAT
	if _weights.is_empty():
		return Enc.COMBAT
	return int(_types[Balance.weighted_pick(_weights)])

func kind() -> int:
	return Kind.GRAPH

func _save() -> Dictionary:
	# the map is plain dictionaries already, so it round-trips through JSON as-is
	return {"map": map, "current": current}

func _load(d: Dictionary) -> void:
	map = d.get("map", [])
	current = d.get("current", null)
	# JSON turns every number into a float; the row/col arithmetic needs ints
	for r in map.size():
		for node in map[r]:
			node["type"] = int(node["type"])
			node["row"] = int(node["row"])
			node["col"] = int(node["col"])
			node["cleared"] = bool(node["cleared"])
			var edges: Array = []
			for e in node["edges"]:
				edges.append(int(e))
			node["edges"] = edges
	if current != null and current is Dictionary:
		current = {"row": int(current["row"]), "col": int(current["col"])}

## Reachable nodes in the next row (or the first row at the start).
func options() -> Array:
	if map.is_empty() or is_complete():
		return []
	if current == null:
		return map[0].duplicate()
	var node: Dictionary = map[current["row"]][current["col"]]
	var out: Array = []
	if current["row"] + 1 < map.size():
		for j in node["edges"]:
			out.append(map[current["row"] + 1][j])
	return out

func select(i: int) -> Dictionary:
	var opts := options()
	if i < 0 or i >= opts.size():
		return {}
	pending = opts[i]
	return pending

func clear_pending() -> void:
	if pending.is_empty():
		return
	map[pending["row"]][pending["col"]]["cleared"] = true
	current = {"row": pending["row"], "col": pending["col"]}
	cleared += 1
	pending = {}

func progress() -> float:
	if current == null:
		return 0.0
	return float(int(current["row"]) + 1) / float(maxi(1, map.size()))

func is_complete() -> bool:
	if current == null:
		return false
	return int(current["row"]) == map.size() - 1 \
		and map[current["row"]][current["col"]]["cleared"]

func status() -> String:
	var row := (int(current["row"]) + 1) if current != null else 0
	return "Depth %d/%d" % [row, map.size()]
