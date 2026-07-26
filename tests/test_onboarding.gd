## Headless test: the first-run experience and the endgame.
##
## Everything here was found by playing: the opening offered one dungeon and a deck
## of exactly the legal minimum, fusion was invisible for several runs, nothing
## explained any mechanic, and clearing the world did nothing.
## Run: godot --headless --script tests/test_onboarding.gd
extends SceneTree

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_onboarding_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_onboarding_settings.json"
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")

	# --- the opening must be a real choice ---
	var m = Meta.new(); m.new_save()
	var open := 0
	for did in Balance.DUNGEONS:
		if Balance.effective_gate(did) == 0:
			open += 1
	if open < 2:
		fails += 1; print("FAIL only %d dungeon(s) open on a fresh save — no first decision" % open)
	# and those openers should differ, or the choice is cosmetic
	var kinds := {}
	var gated_builds := {}
	for did in Balance.DUNGEONS:
		if Balance.effective_gate(did) != 0:
			continue
		var d := Balance.dungeon(did)
		kinds[d.traversal] = true
		for c in d.exclusive_cards:
			for b in Balance.all_builds():
				if c in b.cards:
					gated_builds[b.id] = true
	if kinds.size() < 2:
		fails += 1; print("FAIL every opening dungeon uses the same traversal")
	if gated_builds.size() < 2:
		fails += 1; print("FAIL opening dungeons gate cards for only %d build(s)" % gated_builds.size())
	print("  (info: %d dungeons open at start, %d traversal kinds, gating %d builds)" % [
		open, kinds.size(), gated_builds.size()])

	# --- every starter kit must be playable AND leave deckbuilding slack ---
	if MetaState_kits(m).size() < 3:
		fails += 1; print("FAIL fewer than 3 starter kits")
	for kid in MetaState_kits(m):
		var k = Meta.new(); k.new_save(kid)
		var sel := {}
		for id in k.collection:
			sel[id] = k.collection[id]["count"]
		var total: int = k.total_copies()
		if not k.deck_valid(sel):
			fails += 1; print("FAIL kit %s cannot field a legal deck" % kid)
		if total <= Balance.MIN_DECK_SIZE:
			fails += 1
			print("FAIL kit %s gives %d cards, the legal minimum is %d — no deckbuilding choice" % [
				kid, total, Balance.MIN_DECK_SIZE])
		# Fusion costs gold as well as copies, so a fresh 0-gold save must NOT be
		# able to fuse — power now comes after a run, not before one.
		for id in k.collection:
			if k.can_fuse(id):
				fails += 1
				print("FAIL kit %s can fuse %s on a 0-gold save: power before play" % [kid, id])
				break
		# but one dungeon's takings must unlock it, or the mechanic is unreachable
		var purse := Balance.gold_reward(1, Balance.Tier.BOSS, 0)
		k.add_gold(purse)
		var fusable := 0
		for id in k.collection:
			if k.can_fuse(id):
				fusable += 1
		if fusable < 1:
			fails += 1
			print("FAIL kit %s still cannot fuse after a first boss (%dg)" % [kid, purse])
		# and each kit must actually differ
		print("  (info: kit %-8s %2d copies, %d fusable)" % [kid, total, fusable])
	var sigs := {}
	for kid in MetaState_kits(m):
		var k2 = Meta.new(); k2.new_save(kid)
		var sig := ""
		for id in k2.collection.keys():
			sig += "%s:%d," % [id, int(k2.collection[id]["count"])]
		if sigs.has(sig):
			fails += 1; print("FAIL kits %s and %s are identical" % [kid, sigs[sig]])
		sigs[sig] = kid

	# --- hints fire once and persist ---
	var h = Meta.new(); h.new_save()
	if not h.hint_once("x"):
		fails += 1; print("FAIL first hint did not fire")
	if h.hint_once("x"):
		fails += 1; print("FAIL hint fired twice")
	h.save_game()
	var h2 = Meta.new(); h2.load_game()
	if h2.hint_once("x"):
		fails += 1; print("FAIL hints not persisted across save/load")

	# --- ascension: scales enemies, sweetens loot, and persists ---
	Balance.ascension = 0
	var hp0 := Balance.enemy_max_hp(3, Balance.Tier.NORMAL, 1.0)
	var dm0 := Balance.enemy_damage(3, Balance.Tier.NORMAL, 1.0, 1)
	var w0: Array = Balance.reward_weights(Balance.Tier.BOSS, 3)
	Balance.ascension = 3
	var hp3 := Balance.enemy_max_hp(3, Balance.Tier.NORMAL, 1.0)
	var dm3 := Balance.enemy_damage(3, Balance.Tier.NORMAL, 1.0, 1)
	var w3: Array = Balance.reward_weights(Balance.Tier.BOSS, 3)
	if hp3 <= hp0 or dm3 <= dm0:
		fails += 1; print("FAIL ascension does not raise difficulty (%d/%d -> %d/%d)" % [hp0, dm0, hp3, dm3])
	if float(w3[4]) / float(_sum(w3)) <= float(w0[4]) / float(_sum(w0)):
		fails += 1; print("FAIL ascension does not improve loot — pure punishment")
	if float(hp3) / float(hp0) > 1.6:
		fails += 1; print("FAIL ascension step too steep: %.2fx at level 3" % (float(hp3) / float(hp0)))
	Balance.ascension = 0

	var a = Meta.new(); a.new_save()
	a.ascension = 2
	a.save_game()
	var a2 = Meta.new(); a2.load_game()
	if a2.ascension != 2:
		fails += 1; print("FAIL ascension not persisted")
	if Balance.ascension != 2:
		fails += 1; print("FAIL loading a save did not apply its ascension to scaling")
	Balance.ascension = 0

	# --- there is an ending, and it is reachable ---
	var last := Balance.final_dungeon()
	if last == "":
		fails += 1; print("FAIL no final dungeon defined")
	if Balance.effective_gate(last) > Balance.DUNGEONS.size() - 1:
		fails += 1; print("FAIL the final dungeon can never unlock")
	if not ResourceLoader.exists("res://scenes/Victory.tscn"):
		fails += 1; print("FAIL no victory screen")
	if not ResourceLoader.exists("res://scenes/Glossary.tscn"):
		fails += 1; print("FAIL no glossary screen")
	if not ResourceLoader.exists("res://scenes/StarterKit.tscn"):
		fails += 1; print("FAIL no starter-kit screen")

	# --- tooltips must be generated for every card, and say something ---
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		var tip := Icons.card_tooltip(c)
		if tip.length() < 20 or tip.find("\n") == -1:
			fails += 1; print("FAIL card %s has a useless tooltip" % id)

	for i in Meta.SLOT_COUNT:
		Meta.delete_slot(i)

	if fails == 0:
		print("ONBOARDING TEST: PASS (real first choice, kits with slack, hints, glossary, ascension, ending)")
	else:
		print("ONBOARDING TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

func MetaState_kits(m) -> Array:
	return m.STARTER_KITS.keys()

func _sum(a: Array) -> int:
	var t := 0
	for v in a:
		t += int(v)
	return t

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
