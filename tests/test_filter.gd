## Headless test: filtering and ordering owned cards.
##
## `CardFilter.apply` is a pure function over ids so it can be tested without
## building a screen, and so the collection and the deck builder cannot end up
## ordering the same cards differently — a duplicated lookup once made the first
## dungeon unplayable, and two independent sorts would be the same mistake.
## Run: godot --headless --script tests/test_filter.gd
extends SceneTree

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	m.new_save()
	# a spread worth sorting: several rarities, costs and levels
	for id in ["hack", "cover", "stave_in", "shoulder", "clear_mind", "set_stone",
			"work_up", "light_on_it"]:
		if m.CATALOG.has(id):
			m.add_card(id)
			m.add_card(id)
	m.collection["hack"]["level"] = 12
	m.collection["stave_in"]["level"] = 4

	var all: Array = CardFilter.apply(m.collection, m.CATALOG, CardFilter.default_state())
	if all.size() != m.collection.size():
		fails += 1
		print("FAIL an unfiltered list dropped cards: %d of %d" % [
			all.size(), m.collection.size()])

	# --- every sort key orders, and reverses ---
	for spec in CardFilter.SORTS:
		var key: String = spec["id"]
		var asc := CardFilter.apply(m.collection, m.CATALOG,
			{"sort": key, "desc": false, "rarity": -1, "type": -1})
		var desc := CardFilter.apply(m.collection, m.CATALOG,
			{"sort": key, "desc": true, "rarity": -1, "type": -1})
		if asc.size() != all.size() or desc.size() != all.size():
			fails += 1; print("FAIL sorting by %s changed how many cards exist" % key)
		if asc.size() > 1 and asc == desc:
			fails += 1; print("FAIL sorting by %s ignores the direction toggle" % key)
		# reversing must be exactly the reverse, or the tiebreak is unstable
		var flipped: Array = desc.duplicate()
		flipped.reverse()
		if asc.size() > 1 and asc != flipped:
			# only a problem when every key is distinct; equal keys tiebreak by id
			var keys := {}
			var distinct := true
			for id2 in asc:
				var k = CardFilter._key_of(id2, key, m.collection, m.CATALOG)
				if keys.has(k):
					distinct = false
				keys[k] = true
			if distinct:
				fails += 1
				print("FAIL sorting by %s is not a stable reversal" % key)

	# --- name sort is actually alphabetical ---
	var by_name := CardFilter.apply(m.collection, m.CATALOG,
		{"sort": "name", "desc": false, "rarity": -1, "type": -1})
	var prev := ""
	for id3 in by_name:
		var nm: String = (load(m.CATALOG[id3]) as CardData).name.to_lower()
		if prev != "" and nm < prev:
			fails += 1; print("FAIL name order broken at %s" % id3); break
		prev = nm

	# --- cost sort is monotonic ---
	var by_cost := CardFilter.apply(m.collection, m.CATALOG,
		{"sort": "cost", "desc": false, "rarity": -1, "type": -1})
	var last := -99
	for id4 in by_cost:
		var c: int = (load(m.CATALOG[id4]) as CardData).cost
		if c < last:
			fails += 1; print("FAIL cost order broken at %s" % id4); break
		last = c

	# --- power sort uses the OWNED level, not the base card ---
	# Strike is at level 12 here, so it must outrank an unlevelled copy of itself.
	var by_power := CardFilter.apply(m.collection, m.CATALOG,
		{"sort": "power", "desc": true, "rarity": -1, "type": -1})
	var plain: Dictionary = m.collection.duplicate(true)
	plain["hack"]["level"] = 1
	var by_power_plain := CardFilter.apply(plain, m.CATALOG,
		{"sort": "power", "desc": true, "rarity": -1, "type": -1})
	if by_power.find("hack") >= by_power_plain.find("hack"):
		fails += 1
		print("FAIL power sort ignores the level actually owned (%d vs %d)" % [
			by_power.find("hack"), by_power_plain.find("hack")])

	# --- filters exclude, and only what they should ---
	for r in CardData.Rarity.keys().size():
		var only := CardFilter.apply(m.collection, m.CATALOG,
			{"sort": "name", "desc": false, "rarity": r, "type": -1})
		for id5 in only:
			if int((load(m.CATALOG[id5]) as CardData).rarity) != r:
				fails += 1
				print("FAIL rarity filter %d let %s through" % [r, id5]); break
	for t in CardData.Type.keys().size():
		var onlyt := CardFilter.apply(m.collection, m.CATALOG,
			{"sort": "name", "desc": false, "rarity": -1, "type": t})
		for id6 in onlyt:
			if int((load(m.CATALOG[id6]) as CardData).type) != t:
				fails += 1
				print("FAIL type filter %d let %s through" % [t, id6]); break

	# a filter that matches nothing must return nothing, not everything
	var impossible := CardFilter.apply(m.collection, m.CATALOG,
		{"sort": "name", "desc": false, "rarity": CardData.Rarity.LEGENDARY,
		"type": CardData.Type.ATTACK})
	for id7 in impossible:
		var cc := load(m.CATALOG[id7]) as CardData
		if int(cc.rarity) != CardData.Rarity.LEGENDARY or int(cc.type) != CardData.Type.ATTACK:
			fails += 1; print("FAIL combined filters are not ANDed"); break

	# --- a card the catalogue no longer knows must never be listed ---
	var haunted: Dictionary = m.collection.duplicate(true)
	haunted["ghost_card"] = {"count": 3, "level": 1}
	var safe := CardFilter.apply(haunted, m.CATALOG, CardFilter.default_state())
	if safe.has("ghost_card"):
		fails += 1; print("FAIL a card with no resource was listed")

	# --- every screen that lists cards must read the SAME function ---
	#
	# There were two, and the assertion existed because they were two: the collection
	# and the deck builder each listed the whole catalogue and either could have grown
	# a private filter. D133 fused them into one script — the player could not tell the
	# screens apart, and neither could this list, which is why it named the same
	# behaviour twice. `deck_builder.gd` is gone; the loop stays a loop because the
	# next screen that lists cards has to join it rather than be forgotten.
	for f in ["res://scripts/collection.gd"]:
		var src := FileAccess.open(f, FileAccess.READ)
		if src == null:
			fails += 1; print("FAIL cannot read %s" % f); continue
		var text := src.get_as_text()
		src.close()
		if text.find("CardFilter.apply") == -1:
			fails += 1
			print("FAIL %s lists cards without the shared filter" % f)
		if text.find("for id in MetaState.collection:") != -1:
			fails += 1
			print("FAIL %s still iterates the raw collection somewhere it lists cards" % f)

	# --- the summary line reports honestly ---
	var st := {"sort": "cost", "desc": true, "rarity": 0, "type": -1}
	var line := CardFilter.summary(3, 9, st)
	if line.find("3") == -1 or line.find("9") == -1 or line.find("cost") == -1:
		fails += 1; print("FAIL summary does not describe the filter: '%s'" % line)

	# --- fuzzy search (D214) -----------------------------------------------------------
	#
	# The tiers first, on cards built here rather than on shipped content: what must hold
	# is that a name beats rules text and a cleaner name match beats a scrappier one, and
	# asserting that against real cards would make renaming one break this suite.
	var exact := _card("Blight Bloom", CardData.Rarity.RARE)
	if CardFilter.match_score(exact, "blight bloom") != CardFilter.SCORE_EXACT:
		fails += 1; print("FAIL the whole name is not the best possible match")
	if CardFilter.match_score(exact, "blight") != CardFilter.SCORE_PREFIX:
		fails += 1; print("FAIL a name that STARTS with the query is not scored as a prefix")
	var ranked := [
		["blight bloom", "the whole name"],
		["bli", "the start of it"],
		["loom", "a word inside it"],
		["blbl", "its initials, fuzzily"],
	]
	var prev_score := 99999
	for r2 in ranked:
		var sc: int = CardFilter.match_score(exact, String(r2[0]))
		if sc < 0:
			fails += 1; print("FAIL '%s' (%s) does not match at all" % [r2[0], r2[1]])
		if sc >= prev_score:
			fails += 1
			print("FAIL '%s' (%s) scores %d, not below the looser match before it (%d)" % [
				r2[0], r2[1], sc, prev_score])
		prev_score = sc
	# ...and nothing matched on rules text may outrank anything matched on a name
	if CardFilter.match_score(exact, "poison") >= prev_score:
		fails += 1; print("FAIL a rules-text hit outranks a name hit")
	if CardFilter.match_score(exact, "zzq") >= 0:
		fails += 1; print("FAIL letters that are not there in order still matched")
	# a fuzzy pass over rules text would match almost anything; it must stay literal
	if CardFilter.match_score(_card("Hack", CardData.Rarity.COMMON), "dmge") >= 0:
		fails += 1; print("FAIL rules text is matched fuzzily, which matches everything")

	# now over the real catalogue, where the point is that a half-remembered name finds
	# the card and a word nobody's name contains still finds what does it
	var deep: Dictionary = {}
	for id8 in ["blight_bloom", "see_it_coming", "hack", "cover", "anvil_stance"]:
		if m.CATALOG.has(id8):
			deep[id8] = {"count": 2, "level": 1}
	var found := func(q: String) -> Array:
		var s2 := CardFilter.default_state()
		s2["query"] = q
		return CardFilter.apply(deep, m.CATALOG, s2)
	for probe in [["blbl", "blight_bloom"], ["seit", "see_it_coming"],
			["  HACK  ", "hack"], ["anvl", "anvil_stance"]]:
		var got: Array = found.call(String(probe[0]))
		if got.is_empty() or got[0] != probe[1]:
			fails += 1
			print("FAIL '%s' should lead with %s, got %s" % [probe[0], probe[1], got])
	var poisons: Array = found.call("poison")
	if not poisons.has("blight_bloom"):
		fails += 1; print("FAIL a word only the rules text carries found nothing: %s" % [poisons])
	if poisons.has("cover"):
		fails += 1; print("FAIL 'poison' matched a card that does not poison")
	if not found.call("qqzz").is_empty():
		fails += 1; print("FAIL a query nothing matches returned cards")
	if found.call("   ").size() != deep.size():
		fails += 1; print("FAIL whitespace alone filtered the list")

	# the search REPLACES the order — sort is only the tiebreak — and it still ANDs with
	# the other filters rather than escaping them
	var by_score := CardFilter.apply(deep, m.CATALOG,
		{"sort": "name", "desc": false, "rarity": -1, "type": -1, "query": "seit"})
	if by_score.is_empty() or by_score[0] != "see_it_coming":
		fails += 1; print("FAIL name order outranked the match: %s" % [by_score])
	var narrowed := CardFilter.apply(deep, m.CATALOG,
		{"sort": "name", "desc": false, "rarity": CardData.Rarity.COMMON, "type": -1,
		"query": "blight"})
	for id9 in narrowed:
		if int((load(m.CATALOG[id9]) as CardData).rarity) != CardData.Rarity.COMMON:
			fails += 1; print("FAIL search let %s past the rarity filter" % id9); break

	# and the readout says the order changed, because the sort control did not
	var searched := CardFilter.summary(2, 9, {"sort": "name", "desc": false, "query": "blig"})
	if searched.find("blig") == -1 or searched.find("match") == -1:
		fails += 1; print("FAIL summary does not mention the search: '%s'" % searched)

	if fails == 0:
		print("FILTER TEST: PASS (sorts, reversal, filters, owned levels, fuzzy search, shared by both screens)")
	else:
		print("FILTER TEST: FAIL (%d)" % fails)
	quit()

## A card to score against, built here rather than loaded: the scoring tiers are a
## property of the matcher, and pinning them to a shipped card would make renaming that
## card fail this suite for no reason.
## Both a damage line and a status line, so the card's rules text is a real sentence:
## "dmge" is a subsequence of "Deal 6 damage" and not a substring of it, which is the
## whole distinction the text match is asserting.
func _card(nm: String, rarity: int) -> CardData:
	var c := CardData.new()
	c.name = nm
	c.rarity = rarity
	c.damage = 6
	c.apply_poison = 2
	return c
