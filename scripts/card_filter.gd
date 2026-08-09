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

## Search scores, as tiers rather than as one hand-tuned number (D214). The gaps are
## what make the ranking readable: a card whose NAME starts with what you typed can
## never be beaten by one that merely contains it, and nothing matched on its rules
## text can outrank anything matched on its name. `SUBSEQ_CAP` is what keeps that
## true — bonuses on a long query would otherwise push a scattered subsequence past a
## clean substring.
const SCORE_EXACT := 1000
const SCORE_PREFIX := 800
const SCORE_SUBSTRING := 600
const SCORE_SUBSEQ := 400
const SUBSEQ_CAP := 150
const SCORE_TEXT := 100
## What a hit is worth inside a subsequence match: landing on the start of a word, and
## landing straight after the previous hit. Both are the difference between "blbl"
## finding **Bl**ight **Bl**oom and finding it by accident.
const SUBSEQ_WORD := 12
const SUBSEQ_RUN := 8

## Remembered across screens within a session, so moving from the collection to the
## deck builder does not silently reset what the player asked for.
static var state := {
	"sort": "name",
	"desc": false,
	"rarity": -1,   ## -1 = every rarity
	"type": -1,     ## -1 = every type
	"owned_only": false,
	"query": "",    ## fuzzy search text; "" is every card
}

static func default_state() -> Dictionary:
	return {"sort": "name", "desc": false, "rarity": -1, "type": -1,
		"owned_only": false, "query": ""}

## Cards from `collection` that pass the current filter, in the current order.
##
## `collection` is MetaState.collection: id -> {count, level}.
static func apply(collection: Dictionary, catalog: Dictionary,
		st: Dictionary = state) -> Array:
	var query: String = String(st.get("query", "")).strip_edges().to_lower()
	var out: Array = []
	var scores := {}
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
		# Scored once, here, rather than inside the comparator: a sort asks for the same
		# key O(n log n) times, and this one builds a card's rules text to answer.
		if query != "":
			var s := match_score(card, query)
			if s < 0:
				continue
			scores[id] = s
		out.append(id)

	var key: String = String(st.get("sort", "name"))
	var descending: bool = bool(st.get("desc", false))
	# A search REPLACES the order with how well each card matched, and the chosen sort
	# drops to breaking ties. That overrides a control the player set, so `summary()`
	# says so on the readout line — but the alternative is worse: the card you are
	# typing toward sitting fourteenth because its name begins with a W.
	out.sort_custom(func(a: String, b: String) -> bool:
		if query != "":
			var sa: int = scores[a]
			var sb: int = scores[b]
			if sa != sb:
				return sa > sb
		var ka = _key_of(a, key, collection, catalog)
		var kb = _key_of(b, key, collection, catalog)
		if ka == kb:
			return a < b        # stable, alphabetical tiebreak
		return kb < ka if descending else ka < kb)
	return out

## How well `card` answers `query` (already lowercased and trimmed), or -1 for no
## match at all. Public because it is the whole of the search and it is worth testing
## on its own.
##
## Two different kinds of match, deliberately, because one rule cannot serve both
## fields:
##
## * **The NAME is matched fuzzily** — as a subsequence, so "blbl" finds Blight Bloom
##   and "seit" finds See It Coming. That is what makes a search worth typing into: a
##   name half-remembered is the normal case, and the exact spelling of "Anvil Stance"
##   is not something the player owes the game.
## * **The rules TEXT is matched literally**, as a substring, and only after the name
##   has failed. Fuzzy over a sentence matches everything — four letters are a
##   subsequence of almost any rules text — so a fuzzy pass there would quietly turn
##   the search off. Literal, it answers the deckbuilding question the collection
##   exists for: "what do I own that poisons".
##
## It searches `effect_text()`, the sentence printed on the card's face, and NOT
## `description`, which is an authored field no screen in the game displays. A search
## that hits on words the player cannot see is a search that looks broken.
static func match_score(card: CardData, query: String) -> int:
	if query == "":
		return 0
	var name := String(card.name).to_lower()
	if name == query:
		return SCORE_EXACT
	if name.begins_with(query):
		return SCORE_PREFIX
	var at := name.find(query)
	if at > 0:
		# earlier is better, and a hit at the start of a word beats one mid-word
		return SCORE_SUBSTRING + (SUBSEQ_WORD if _is_break(name[at - 1]) else 0) - mini(at, 20)
	var sub := _subsequence_score(name, query)
	if sub >= 0:
		return sub
	if String(card.effect_text()).to_lower().find(query) >= 0:
		return SCORE_TEXT
	return -1

## Greedy left-to-right subsequence match, scored by how COMPACT it is, or -1 if the
## query's letters are not all there in order.
##
## Greedy rather than exhaustive: the first place each letter can land is taken, which
## can score a match lower than the best possible alignment ("bloo" in "Blight Bloom"
## takes the l of Blight before the l of Bloom). Finding the optimum needs a full
## matrix per card per keystroke, and it changes the ORDER of two hits at most —
## neither of which is the card being hidden.
static func _subsequence_score(text: String, query: String) -> int:
	var ti := 0
	var prev := -2
	var first := -1
	var bonus := 0
	for qi in query.length():
		var ch: String = query[qi]
		while ti < text.length() and text[ti] != ch:
			ti += 1
		if ti >= text.length():
			return -1
		if first < 0:
			first = ti
		if ti == prev + 1:
			bonus += SUBSEQ_RUN
		if ti == 0 or _is_break(text[ti - 1]):
			bonus += SUBSEQ_WORD
		prev = ti
		ti += 1
	return SCORE_SUBSEQ + mini(bonus, SUBSEQ_CAP) - mini(first, 20)

## Whether a character ends a word, for the "landed on a word start" bonus. Card names
## carry hyphens and apostrophes as well as spaces (Brood-Mother, All You Have).
static func _is_break(ch: String) -> bool:
	return ch == " " or ch == "-" or ch == "'" or ch == "_"

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
			return int(card.eff_cost())
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
	var bits: Array[String] = []
	# First, because it is the strongest thing acting on the list and the only one that
	# takes the sort control's job away from it. Both are still named: the sort is not
	# ignored, it is what settles cards that matched equally well.
	var query: String = String(st.get("query", "")).strip_edges()
	if query != "":
		bits.append("best match for '%s'" % query)
	bits.append("%s%s" % [
		("by " if query == "" else "then by ") + sort_label(String(st.get("sort", "name"))).to_lower(),
		" desc" if bool(st.get("desc", false)) else ""])
	if int(st.get("rarity", -1)) >= 0:
		bits.append(CardData.rarity_word(int(st["rarity"])).to_lower())
	if int(st.get("type", -1)) >= 0:
		bits.append(CardData.Type.keys()[int(st["type"])].to_lower())
	var f := ", ".join(bits)
	if shown == total:
		return "%s, %s" % [Wording.count(total, "card"), f]
	# Only the total is counted here: "1 of 4 cards" is right, and "1 of 1 cards"
	# cannot happen because the equal case is the branch above (D125).
	return "%d of %s, %s" % [shown, Wording.count(total, "card"), f]
