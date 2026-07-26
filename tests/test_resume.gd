## Headless test: resumable runs (D22).
##
## The assertion that matters is round-trip *identity*, not "it loaded": a restored
## run must present the same choices and a restored fight the same board, or
## quitting becomes a way to reroll a bad situation.
## Run: godot --headless --script tests/test_resume.gd
extends SceneTree

const DIR := "res://resources/cards/"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_resume_"
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://t_test_resume_settings.json"
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()

	# --- every traversal model round-trips through JSON ---
	for kind in [Traversal.Kind.GRAPH, Traversal.Kind.DECK, Traversal.Kind.DICE]:
		for did in Balance.DUNGEONS:
			var dd := Balance.dungeon(did)
			var a := Traversal.make(kind)
			a.generate(dd)
			# advance a few encounters so the state is not just "freshly generated"
			var steps := 0
			while not a.is_complete() and steps < 3:
				steps += 1
				var opts := a.options()
				if opts.is_empty():
					break
				var pick := 0
				for i in opts.size():
					if not opts[i].has("hp_cost"):
						pick = i
						break
				if a.select(pick).is_empty():
					continue
				a.clear_pending()

			# through actual JSON, because that is what the save does — this is
			# where int/float drift shows up
			var blob = JSON.parse_string(JSON.stringify(a.save_state()))
			var b := Traversal.from_state(blob, dd)
			if b.kind() != a.kind():
				fails += 1; print("FAIL kind lost in round-trip (%d)" % kind); break
			if b.is_complete() != a.is_complete():
				fails += 1; print("FAIL completion differs after restore (kind %d)" % kind)
			if b.cleared != a.cleared:
				fails += 1; print("FAIL cleared count differs (kind %d): %d vs %d" % [
					kind, b.cleared, a.cleared])
			var oa := a.options()
			var ob := b.options()
			if oa.size() != ob.size():
				fails += 1; print("FAIL option count differs after restore (kind %d): %d vs %d" % [
					kind, oa.size(), ob.size()]); break
			for i in oa.size():
				if int(oa[i]["type"]) != int(ob[i]["type"]):
					fails += 1; print("FAIL option %d type differs (kind %d)" % [i, kind]); break

	# --- a combat round-trips exactly ---
	var deck: Array[CardData] = []
	for id in ["strike", "strike", "defend", "bash", "twin_strike", "venom_fang", "shiv", "guard"]:
		deck.append((load(DIR + id + ".tres") as CardData).duplicate())
	var e := CombatEngine.new()
	e.setup(deck, 47, 60, 3, Balance.Tier.ELITE, "hexer")
	# play into a messy mid-fight state: statuses, block, spent energy, a used pile
	for c in e.hand.duplicate():
		if e.can_play(c):
			e.play_card(c)
	e.end_turn()
	e.player.poison = 3
	e.player.thorns = 2
	e.enemies[0].vulnerable = 2
	e.enemies[0].block = 4

	var cblob = JSON.parse_string(JSON.stringify(e.save_state()))
	var r := CombatEngine.new()
	r.load_state(cblob, m.CATALOG)

	if r.player.hp != e.player.hp or r.player.block != e.player.block:
		fails += 1; print("FAIL player hp/block differ: %d/%d vs %d/%d" % [
			r.player.hp, r.player.block, e.player.hp, e.player.block])
	if r.player.poison != e.player.poison or r.player.thorns != e.player.thorns:
		fails += 1; print("FAIL player statuses differ")
	if r.energy != e.energy or r.turn != e.turn or r.target != e.target:
		fails += 1; print("FAIL energy/turn/target differ")
	if r.enemies.size() != e.enemies.size():
		fails += 1; print("FAIL enemy count differs")
	else:
		for i in e.enemies.size():
			if r.enemies[i].hp != e.enemies[i].hp \
					or r.enemies[i].vulnerable != e.enemies[i].vulnerable \
					or r.enemies[i].block != e.enemies[i].block:
				fails += 1; print("FAIL enemy %d state differs" % i)
			if (r.archetypes[i] as EnemyData).id != (e.archetypes[i] as EnemyData).id:
				fails += 1; print("FAIL enemy %d archetype differs" % i)
			if int(r.intents[i]["action"]) != int(e.intents[i]["action"]) \
					or int(r.intents[i]["value"]) != int(e.intents[i]["value"]):
				fails += 1; print("FAIL enemy %d intent differs" % i)
	if r.hand.size() != e.hand.size() or r.draw_pile.size() != e.draw_pile.size() \
			or r.discard_pile.size() != e.discard_pile.size():
		fails += 1; print("FAIL pile sizes differ: %d/%d/%d vs %d/%d/%d" % [
			r.hand.size(), r.draw_pile.size(), r.discard_pile.size(),
			e.hand.size(), e.draw_pile.size(), e.discard_pile.size()])
	# the telegraphed incoming damage must match, or the restored fight is easier
	if r.enemy_intent != e.enemy_intent:
		fails += 1; print("FAIL incoming damage differs: %d vs %d" % [r.enemy_intent, e.enemy_intent])
	# card levels and per-combat growth survive
	var lvl_ok := true
	for i in mini(r.draw_pile.size(), e.draw_pile.size()):
		if r.draw_pile[i].level != e.draw_pile[i].level:
			lvl_ok = false
	if not lvl_ok:
		fails += 1; print("FAIL card levels not preserved")

	# --- unknown content in a saved run must be dropped, not crash ---
	var bad := {"kind": Traversal.Kind.GRAPH, "map": [], "current": null}
	var t := Traversal.from_state(bad, Balance.dungeon(Balance.DUNGEONS[0]))
	if t == null:
		fails += 1; print("FAIL empty traversal blob produced null")
	if not t.options().is_empty():
		fails += 1; print("FAIL empty map produced options")

	# --- save format carries the run and reports it in the slot summary ---
	var Meta = load("res://scripts/meta_state.gd")
	Meta.delete_slot(0)
	var mm = Meta.new(); mm.slot = 0; mm.new_save(); mm.save_game()
	var summary: Dictionary = Meta.slot_summary(0)
	if bool(summary.get("in_run", true)):
		fails += 1; print("FAIL fresh save reports a run in progress")
	if int(summary.get("version", 0)) != Meta.SAVE_VERSION:
		fails += 1; print("FAIL slot summary version wrong")
	Meta.delete_slot(0)

	# --- writes are coalesced, and the run lives in its own file ---
	Meta.delete_slot(0)
	var w = Meta.new(); w.slot = 0; w.new_save()
	w.saved_run = {"dungeon_id": Balance.DUNGEONS[0], "dungeon": 1, "hp": 30, "max_hp": 60,
		"deck": [{"id": "strike", "level": 1, "growth": 0}],
		"traversal": {"kind": 0, "map": [], "current": null},
		"escrow_cards": [], "escrow_gold": 0, "combat": {}}
	w.writes_meta = 0
	w.writes_run = 0
	for i in 12:
		w.mark_run_dirty()          # a turn's worth of card plays
	w.flush()
	if w.writes_run != 1:
		fails += 1; print("FAIL 12 marks produced %d run writes (expected 1)" % w.writes_run)
	if w.writes_meta != 0:
		fails += 1; print("FAIL combat rewrote the meta save %d time(s)" % w.writes_meta)
	if not FileAccess.file_exists(Meta.run_path_for(0)):
		fails += 1; print("FAIL run file not written")
	# the meta file must NOT contain the run any more
	var mf := FileAccess.open(Meta.path_for(0), FileAccess.READ)
	if mf != null:
		var mtext := mf.get_as_text()
		mf.close()
		if mtext.find("dungeon_id") != -1:
			fails += 1; print("FAIL run data is still inside the meta save")
	# nothing dirty -> no further writes
	w.writes_run = 0
	w.flush()
	if w.writes_run != 0:
		fails += 1; print("FAIL flush wrote despite nothing being dirty")
	# ending a run removes its file rather than leaving a stale one
	w.saved_run = {}
	w.mark_run_dirty()
	w.flush()
	if FileAccess.file_exists(Meta.run_path_for(0)):
		fails += 1; print("FAIL stale run file left behind after the run ended")
	# deleting a slot takes both files
	w.saved_run = {"dungeon_id": Balance.DUNGEONS[0], "traversal": {"kind": 0}}
	w.mark_run_dirty(); w.flush()
	Meta.delete_slot(0)
	if FileAccess.file_exists(Meta.path_for(0)) or FileAccess.file_exists(Meta.run_path_for(0)):
		fails += 1; print("FAIL delete_slot left a file behind")

	if fails == 0:
		print("RESUME TEST: PASS (round-trip identity; writes coalesced into a separate run file)")
	else:
		print("RESUME TEST: FAIL (%d)" % fails)
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
