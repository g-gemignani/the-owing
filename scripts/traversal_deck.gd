## Dungeon-as-a-deck. The dungeon is a shuffled stack of encounters you draw
## through; the boss is always the bottom card.
##
## Decision texture: each drawn encounter is revealed, then you choose to FACE it
## (fight for the reward) or AVOID it by paying HP. Avoiding trades health for
## tempo and forfeits the loot, so the interesting question is which fights are
## worth their cost — the opposite pressure from the graph, where you commit to a
## route before knowing what is on it.
##
## Knowing what remains (the counts are public) is deliberate: it makes avoiding a
## calculated risk rather than a blind one.
class_name TraversalDeck
extends Traversal

var draw_pile: Array = []   # Node values, boss last
var revealed: int = -1      # currently revealed Node, or -1
var avoided: int = 0
var total: int = 0

func generate(p_dungeon) -> void:
	dungeon = p_dungeon
	cleared = 0
	avoided = 0
	pending = {}
	draw_pile = standard_encounters()
	draw_pile.shuffle()
	draw_pile.append(Enc.BOSS)   # the boss is always the bottom of the stack
	total = draw_pile.size()
	_reveal()

func _reveal() -> void:
	revealed = int(draw_pile[0]) if not draw_pile.is_empty() else -1

func kind() -> int:
	return Kind.DECK

func _save() -> Dictionary:
	return {"draw_pile": draw_pile, "revealed": revealed, "avoided": avoided, "total": total}

func _load(d: Dictionary) -> void:
	draw_pile = []
	for e in d.get("draw_pile", []):
		draw_pile.append(int(e))
	revealed = int(d.get("revealed", -1))
	avoided = int(d.get("avoided", 0))
	total = int(d.get("total", draw_pile.size()))

## Two options on a revealed encounter: face it, or pay HP to skip it.
## The boss cannot be avoided — a run has to end somewhere.
func options() -> Array:
	if revealed < 0:
		return []
	var out: Array = []
	out.append({"type": revealed, "label": "Face it", "action": "face"})
	if revealed == Enc.COMBAT or revealed == Enc.ELITE:
		out.append({
			"type": revealed,
			"label": "Avoid (-%d HP)" % Balance.DECK_AVOID_HP_COST,
			"action": "avoid",
			"hp_cost": Balance.DECK_AVOID_HP_COST,
		})
	return out

func select(i: int) -> Dictionary:
	var opts := options()
	if i < 0 or i >= opts.size():
		return {}
	var opt: Dictionary = opts[i]
	if opt.get("action", "face") == "avoid":
		# handled by the caller (it owns HP); the card is discarded unresolved
		if not draw_pile.is_empty():
			draw_pile.pop_front()
		avoided += 1
		_reveal()
		return {}
	pending = {"type": revealed}
	return pending

func clear_pending() -> void:
	if pending.is_empty():
		return
	if not draw_pile.is_empty():
		draw_pile.pop_front()
	cleared += 1
	pending = {}
	_reveal()

func progress() -> float:
	if total <= 0:
		return 0.0
	return float(cleared + avoided) / float(total)

func is_complete() -> bool:
	return draw_pile.is_empty()

## Public counts of what is left — avoiding should be a calculated risk.
func remaining_counts() -> Dictionary:
	var counts := {}
	for n in draw_pile:
		counts[n] = int(counts.get(n, 0)) + 1
	return counts

func status() -> String:
	var c := remaining_counts()
	var parts: Array[String] = []
	for n in [Enc.COMBAT, Enc.ELITE, Enc.REST, Enc.SHOP, Enc.BOSS]:
		if c.has(n):
			parts.append("%s x%d" % [Balance.NODE_LABEL[n], c[n]])
	return "%d left: %s" % [draw_pile.size(), ", ".join(parts)]
