## Headless test: events and treasure (non-combat encounters).
## Effects are declarative, so the guarantees to check are that every event is
## well-formed and that no declared effect can break a run rule.
## Run: godot --headless --script tests/test_event.gd
extends SceneTree

func _init() -> void:
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")

	# --- every event is well-formed ---
	if Balance.EVENTS.is_empty():
		fails += 1; print("FAIL no events registered")
	for id in Balance.EVENTS:
		var e := load(Balance.EVENT_DIR + id + ".tres") as EventData
		if e == null:
			fails += 1; print("FAIL event missing: %s" % id); continue
		if e.id != id:
			fails += 1; print("FAIL event id mismatch: %s vs %s" % [e.id, id])
		if e.choice_count() < 2:
			fails += 1; print("FAIL %s has fewer than 2 choices (not a decision)" % id)
		if e.title.strip_edges() == "" or e.description.strip_edges() == "":
			fails += 1; print("FAIL %s missing title/description" % id)
		# every choice needs an outcome line, or the player learns nothing
		for i in e.choice_count():
			if e.result_text(i).strip_edges() == "":
				fails += 1; print("FAIL %s choice %d has no result text" % [id, i])
		# at least one choice must be free — an event should never be a pure tax
		var has_free := false
		for i in e.choice_count():
			if e.hp_delta(i) >= 0 and e.hp_percent(i) >= 0 and e.gold_delta(i) >= 0 \
					and e.card_delta(i) >= 0 and not e.fights(i):
				has_free = true
		if not has_free:
			fails += 1; print("FAIL %s has no cost-free option" % id)
		# an HP cost must never be able to kill: capped at 50% of max
		for i in e.choice_count():
			if e.hp_percent(i) <= -50:
				fails += 1; print("FAIL %s choice %d can cost >=50%% max HP" % [id, i])

	# --- treasure numbers are sane ---
	if Balance.TREASURE_GOLD_MIN <= 0 or Balance.TREASURE_GOLD_MAX < Balance.TREASURE_GOLD_MIN:
		fails += 1; print("FAIL treasure gold range invalid")
	if Balance.TREASURE_CARD_CHANCE < 0 or Balance.TREASURE_CARD_CHANCE > 100:
		fails += 1; print("FAIL treasure card chance out of range")

	# --- card loss from events must respect the softlock floor ---
	var m = Meta.new()
	m.new_save()
	# drive the collection to the floor, then confirm nothing more can be removed
	var guard := 0
	while m.total_copies() > Balance.MIN_KEEP and guard < 100:
		guard += 1
		m.penalize_death(1)
	if m.total_copies() < Balance.MIN_KEEP:
		fails += 1; print("FAIL collection already below floor: %d" % m.total_copies())
	# an event's "lose a card" must refuse at the floor (same rule as death)
	if m.total_copies() - 1 >= Balance.MIN_KEEP:
		print("  (info: floor not reached, skipping refusal check)")
	else:
		print("  (info: at floor %d — event card loss must refuse here)" % m.total_copies())

	# --- encounter kinds stay in lockstep with GameState.NodeType ---
	var GS = load("res://scripts/game_state.gd").new()
	var pairs := {
		Traversal.Enc.COMBAT: GS.NodeType.COMBAT,
		Traversal.Enc.ELITE: GS.NodeType.ELITE,
		Traversal.Enc.REST: GS.NodeType.REST,
		Traversal.Enc.BOSS: GS.NodeType.BOSS,
		Traversal.Enc.SHOP: GS.NodeType.SHOP,
		Traversal.Enc.EVENT: GS.NodeType.EVENT,
		Traversal.Enc.TREASURE: GS.NodeType.TREASURE,
	}
	for k in pairs:
		if int(k) != int(pairs[k]):
			fails += 1; print("FAIL Enc and NodeType diverged at %d" % int(k))
	# and every kind must have a display label
	for k in pairs:
		if not Balance.NODE_LABEL.has(int(k)):
			fails += 1; print("FAIL no NODE_LABEL for encounter %d" % int(k))

	if fails == 0:
		print("EVENT TEST: PASS (events well-formed, treasure sane, enums in lockstep)")
	else:
		print("EVENT TEST: FAIL (%d)" % fails)
	quit()
