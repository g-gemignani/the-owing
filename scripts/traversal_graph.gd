## Slay-the-Spire style layered node graph (the original model, now behind the
## Traversal interface). Decision texture: pick a branch, trading node types
## against each other with imperfect foresight.
class_name TraversalGraph
extends Traversal

## Rows are DERIVED from the shared encounter budget, not hardcoded: the graph
## visits exactly one node per row, so row count *is* this model's encounter count.
## Hardcoding it silently broke the budget contract the moment new encounter types
## were added to the mix.
static func rows() -> int:
	return Traversal.standard_encounters().size() + 1  # +1 for the boss row

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
	var total := rows()
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

func _roll_type(r: int, total: int) -> int:
	if r == total - 1:
		return Enc.BOSS
	if r == 0:
		return Enc.COMBAT
	var roll := randi() % 100
	if roll < Balance.NODE_CHANCE_REST:
		return Enc.REST
	roll -= Balance.NODE_CHANCE_REST
	if roll < Balance.NODE_CHANCE_SHOP:
		return Enc.SHOP
	roll -= Balance.NODE_CHANCE_SHOP
	if roll < Balance.NODE_CHANCE_EVENT:
		return Enc.EVENT
	roll -= Balance.NODE_CHANCE_EVENT
	if roll < Balance.NODE_CHANCE_TREASURE:
		return Enc.TREASURE
	roll -= Balance.NODE_CHANCE_TREASURE
	if roll < Balance.NODE_CHANCE_ELITE:
		return Enc.ELITE
	return Enc.COMBAT

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
