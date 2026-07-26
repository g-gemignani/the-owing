## Headless test: builds must be gated behind clearing several dungeons.
##
## The design rule: no deck archetype may be assembled by farming a single place.
## Because run earnings are escrowed (D20), obtaining a dungeon-exclusive card means
## beating that dungeon's boss (or spending a rope on it) — so scattering a build's
## defining cards across dungeons is what turns collection into a set of goals.
## Without this test, one content edit could quietly re-collapse a build.
## Run: godot --headless --script tests/test_build.gd
extends SceneTree

const MIN_DUNGEONS := 3
const MIN_ZONES := 2

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_build_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_build_settings.json"
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	var builds := Balance.all_builds()

	if builds.size() < 5:
		fails += 1; print("FAIL only %d builds defined" % builds.size())

	for b in builds:
		# every card a build names must exist
		for c in b.cards:
			if not m.CATALOG.has(c):
				fails += 1; print("FAIL build %s names unknown card %s" % [b.id, c])
		if b.cards.size() < 6:
			fails += 1; print("FAIL build %s has only %d cards" % [b.id, b.cards.size()])
		if b.name.strip_edges() == "" or b.description.strip_edges() == "":
			fails += 1; print("FAIL build %s missing name/description" % b.id)

		# the gating rule: several dungeons, in more than one zone
		var needed: Array = Balance.dungeons_required_for(b)
		if needed.size() < MIN_DUNGEONS:
			fails += 1
			print("FAIL build %s is gated behind only %d dungeon(s) %s — farmable in one place" % [
				b.id, needed.size(), needed])
		var zones := {}
		for did in needed:
			var z := Balance.zone_of(did)
			if z != null:
				zones[z.id] = true
		if zones.size() < MIN_ZONES:
			fails += 1
			print("FAIL build %s spans only %d zone(s) — not a journey" % [b.id, zones.size()])
		print("  (info: %-9s %2d cards, gated behind %d dungeons across %d zones)" % [
			b.id, b.cards.size(), needed.size(), zones.size()])

	# --- no single dungeon may complete any build on its own ---
	for did in Balance.DUNGEONS:
		var pool := Balance.card_pool_for(did)
		for b in builds:
			var have := 0
			for c in b.cards:
				if c in pool:
					have += 1
			if have == b.cards.size():
				fails += 1
				print("FAIL dungeon %s alone completes build %s" % [did, b.id])

	# --- and no single zone either ---
	for z in Balance.all_zones():
		var pool := {}
		for did in z.dungeons:
			for c in Balance.card_pool_for(did):
				pool[c] = true
		for b in builds:
			var have := 0
			for c in b.cards:
				if pool.has(c):
					have += 1
			if have == b.cards.size():
				fails += 1
				print("FAIL zone %s alone completes build %s" % [z.id, b.id])

	# --- builds should cover most of the card set, or archetypes are decoration ---
	var covered := {}
	for b in builds:
		for c in b.cards:
			covered[c] = true
	var pct := float(covered.size()) / float(m.CATALOG.size()) * 100.0
	print("  (info: builds name %d of %d cards, %.0f%%)" % [covered.size(), m.CATALOG.size(), pct])
	if pct < 50.0:
		fails += 1; print("FAIL builds cover only %.0f%% of cards" % pct)

	# --- every build must be *finishable*: its gate dungeons must be reachable ---
	for b in builds:
		var deepest := 0
		for did in Balance.dungeons_required_for(b):
			var d := Balance.dungeon(did)
			deepest = maxi(deepest, d.unlock_after_clears)
		if deepest > Balance.DUNGEONS.size() - 1:
			fails += 1; print("FAIL build %s needs a dungeon that can never unlock" % b.id)

	# --- builds must be TIERED: a player a few clears in needs a goal they can
	#     actually finish. Found by playing: every build once required 6-8 clears,
	#     so the whole mid-game had no achievable objective.
	var by_clears: Array = []
	for b in builds:
		by_clears.append({"id": b.id, "clears": Balance.clears_required_for(b)})
	by_clears.sort_custom(func(a, b2): return int(a["clears"]) < int(b2["clears"]))
	for e in by_clears:
		print("  (info: %-9s completable after %d clears)" % [e["id"], e["clears"]])
	var early := 0
	var mid := 0
	for e in by_clears:
		if int(e["clears"]) <= 3:
			early += 1
		if int(e["clears"]) <= 5:
			mid += 1
	if early < 2:
		fails += 1; print("FAIL only %d build(s) completable within 3 clears — no early goal" % early)
	if mid < 4:
		fails += 1; print("FAIL only %d build(s) completable within 5 clears — mid-game has no goal" % mid)
	# and at least one should stay a long-term chase
	if int(by_clears[by_clears.size() - 1]["clears"]) < 6:
		fails += 1; print("FAIL no build is a late-game goal")

	# --- every gate must be satisfiable by the dungeons open before it ---
	# (a gate needing N clears when fewer than N dungeons are reachable is a wall)
	for did in Balance.DUNGEONS:
		var need: int = Balance.effective_gate(did)
		var open_before := 0
		for other in Balance.DUNGEONS:
			if Balance.effective_gate(other) <= need and other != did:
				open_before += 1
		if need > open_before:
			fails += 1
			print("FAIL %s needs %d clears but only %d dungeons open by then" % [
				did, need, open_before])

	# --- the effective gate must never understate the real requirement ---
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		var z := Balance.zone_of(did)
		if Balance.effective_gate(did) < d.unlock_after_clears:
			fails += 1; print("FAIL effective gate below dungeon gate for %s" % did)
		if z != null and Balance.effective_gate(did) < z.unlock_after_clears:
			fails += 1; print("FAIL effective gate below zone gate for %s" % did)

	if fails == 0:
		print("BUILD TEST: PASS (%d builds, gated behind %d+ dungeons in %d+ zones, and properly tiered)" % [
			builds.size(), MIN_DUNGEONS, MIN_ZONES])
	else:
		print("BUILD TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

## Remove this test's sandboxed files so a test run leaves no residue in the
## player's data directory.
func _cleanup_sandbox() -> void:
	# stop any surviving instance from re-writing what we are about to delete
	load("res://scripts/meta_state.gd").writes_disabled = true
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
