## Tabletop dice board. The dungeon is a track of spaces; you roll dice and move.
##
## Decision texture: you roll TWO dice and must spend one of them. Moving skips
## the spaces you pass over, so the question is never "may I move" but "which
## overshoot can I afford" — a 3 might vault you past a Rest you needed, while a 1
## might drop you onto the Elite you were trying to clear at full health.
##
## Rolling two and choosing one is deliberate: pure dice movement removes agency,
## which is the standard failure of this model. Choosing between two outcomes (and
## seeing the whole board) keeps the decision with the player.
class_name TraversalDice
extends Traversal

const DIE_FACES := 3   # d3: small numbers keep overshoot legible
const DICE_ROLLED := 2

var track: Array = []      # Enc per space; last space is the boss
var pos: int = -1          # -1 = at the entrance, not yet on the board
var dice: Array = []       # currently rolled values
var boss_cleared := false

func generate(p_dungeon) -> void:
	dungeon = p_dungeon
	cleared = 0
	pending = {}
	pos = -1
	boss_cleared = false

	# The board is longer than the encounter budget because movement skips spaces.
	# Length is derived from the budget and the average roll so the number of
	# LANDINGS lands near the shared budget — otherwise this model would be
	# cheaper or dearer than the graph and difficulty would stop meaning one thing.
	var budget := standard_encounters(dungeon)
	var avg_roll := float(DIE_FACES + 1) / 2.0
	var length := int(round(float(budget.size()) * avg_roll))
	track = []
	for i in length:
		track.append(budget[randi() % budget.size()])
	track.append(Enc.BOSS)
	_roll()

func _roll() -> void:
	dice = []
	for i in DICE_ROLLED:
		dice.append(1 + randi() % DIE_FACES)

func _last() -> int:
	return track.size() - 1

func kind() -> int:
	return Kind.DICE

func _save() -> Dictionary:
	return {"track": track, "pos": pos, "dice": dice, "boss_cleared": boss_cleared}

func _load(d: Dictionary) -> void:
	track = []
	for e in d.get("track", []):
		track.append(int(e))
	pos = int(d.get("pos", -1))
	dice = []
	for e in d.get("dice", []):
		dice.append(int(e))
	boss_cleared = bool(d.get("boss_cleared", false))
	if dice.is_empty() and not is_complete():
		_roll()   # never restore into a state with no options

## One option per die: move that many spaces and resolve whatever you land on.
## Movement is clamped to the boss space, so a run always ends there.
func options() -> Array:
	if is_complete():
		return []
	var out: Array = []
	for i in dice.size():
		var d := int(dice[i])
		var dest: int = mini(pos + d, _last())
		var skipped: int = maxi(0, dest - pos - 1)
		out.append({
			"type": int(track[dest]),
			"label": "Move %d → %s%s" % [
				d, Balance.NODE_LABEL.get(int(track[dest]), "?"),
				"  (skip %d)" % skipped if skipped > 0 else ""],
			"die": d,
			"dest": dest,
			"skipped": skipped,
		})
	return out

func select(i: int) -> Dictionary:
	var opts := options()
	if i < 0 or i >= opts.size():
		return {}
	pos = int(opts[i]["dest"])
	pending = {"type": int(track[pos])}
	return pending

func clear_pending() -> void:
	if pending.is_empty():
		return
	if int(pending["type"]) == Enc.BOSS:
		boss_cleared = true
	cleared += 1
	pending = {}
	_roll()

func progress() -> float:
	if track.is_empty():
		return 0.0
	return float(maxi(0, pos)) / float(_last())

func is_complete() -> bool:
	return boss_cleared

func status() -> String:
	return "Space %d/%d   dice: %s" % [maxi(0, pos), _last(), str(dice)]

## Upcoming spaces, for the board view.
func upcoming(count: int) -> Array:
	var out: Array = []
	for i in range(maxi(0, pos), mini(track.size(), maxi(0, pos) + count)):
		out.append({"index": i, "type": int(track[i]), "current": i == pos})
	return out
