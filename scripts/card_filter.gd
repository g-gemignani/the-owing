## Filtering and ordering for any list of owned cards.
##
## Shared by the collection and the deck builder deliberately. Both screens list the
## same cards for different reasons, and giving each its own sorting would let them
## drift — the way a duplicated encounter-label table once did, and made the first
## dungeon unplayable.
##
## The whole thing is a PURE function over ids plus a state dictionary, so it can be
## tested headlessly without building a screen. The UI is a thin bar on top.
class_name CardFilter
extends RefCounted

## Sort keys, in the order they are offered. `id` is what gets stored in state.
const SORTS := [
	{"id": "name", "label": "Name"},
	{"id": "cost", "label": "Cost"},
	{"id": "rarity", "label": "Rarity"},
	{"id": "level", "label": "Level"},
	{"id": "count", "label": "Owned"},
	{"id": "power", "label": "Power"},
]

## Remembered across screens within a session, so moving from the collection to the
## deck builder does not silently reset what the player asked for.
static var state := {
	"sort": "name",
	"desc": false,
	"rarity": -1,   ## -1 = every rarity
	"type": -1,     ## -1 = every type
	"owned_only": false,
}

static func default_state() -> Dictionary:
	return {"sort": "name", "desc": false, "rarity": -1, "type": -1, "owned_only": false}

## Cards from `collection` that pass the current filter, in the current order.
##
## `collection` is MetaState.collection: id -> {count, level}.
static func apply(collection: Dictionary, catalog: Dictionary,
		st: Dictionary = state) -> Array:
	var out: Array = []
	for id in collection:
		if not catalog.has(id):
			continue   # content renamed or removed; never show a card that cannot load
		var card := load(catalog[id]) as CardData
		if card == null:
			continue
		var rarity: int = int(st.get("rarity", -1))
		if rarity >= 0 and int(card.rarity) != rarity:
			continue
		var type: int = int(st.get("type", -1))
		if type >= 0 and int(card.type) != type:
			continue
		if bool(st.get("owned_only", false)) and int(collection[id]["count"]) <= 0:
			continue
		out.append(id)

	var key: String = String(st.get("sort", "name"))
	var descending: bool = bool(st.get("desc", false))
	out.sort_custom(func(a: String, b: String) -> bool:
		var ka = _key_of(a, key, collection, catalog)
		var kb = _key_of(b, key, collection, catalog)
		if ka == kb:
			return a < b        # stable, alphabetical tiebreak
		return kb < ka if descending else ka < kb)
	return out

## The value a card sorts by. Level and count come from the COLLECTION, everything
## else from the card at the level actually owned — sorting by power has to reflect
## what the player has, not what the base card would do.
static func _key_of(id: String, key: String, collection: Dictionary,
		catalog: Dictionary):
	var entry: Dictionary = collection.get(id, {"count": 0, "level": 1})
	match key:
		"count":
			return int(entry.get("count", 0))
		"level":
			return int(entry.get("level", 1))
	var card := load(catalog[id]) as CardData
	if card == null:
		return id
	match key:
		"cost":
			return int(card.cost)
		"rarity":
			return int(card.rarity)
		"power":
			var c := card.duplicate() as CardData
			c.level = int(entry.get("level", 1))
			return c.power_value()
	return String(card.name).to_lower()

static func sort_label(key: String) -> String:
	for s in SORTS:
		if s["id"] == key:
			return String(s["label"])
	return key

## How the current filter reads, for a status line.
static func summary(shown: int, total: int, st: Dictionary = state) -> String:
	var bits: Array[String] = ["by %s%s" % [
		sort_label(String(st.get("sort", "name"))).to_lower(),
		" desc" if bool(st.get("desc", false)) else ""]]
	if int(st.get("rarity", -1)) >= 0:
		bits.append(CardData.Rarity.keys()[int(st["rarity"])].to_lower())
	if int(st.get("type", -1)) >= 0:
		bits.append(CardData.Type.keys()[int(st["type"])].to_lower())
	var f := ", ".join(bits)
	if shown == total:
		return "%d cards, %s" % [total, f]
	return "%d of %d cards, %s" % [shown, total, f]
