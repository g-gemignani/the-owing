## Headless test: the Traversal contract, applied to EVERY model.
##
## The point of this file is that it is model-agnostic: adding a traversal only
## requires adding its Kind to KINDS below. Anything a model must guarantee for
## combat/meta/balance to keep working is asserted here.
## Run: godot --headless --script tests/test_traversal.gd
extends SceneTree

const KINDS := [Traversal.Kind.GRAPH, Traversal.Kind.DECK, Traversal.Kind.DICE]
const KIND_NAMES := {0: "GRAPH", 1: "DECK", 2: "DICE"}

## Encounters one run should cost, shared by every model.
func budget() -> int:
	return Balance.ENCOUNTER_COMBATS + Balance.ENCOUNTER_ELITES \
		+ Balance.ENCOUNTER_RESTS + Balance.ENCOUNTER_SHOPS \
		+ Balance.ENCOUNTER_EVENTS + Balance.ENCOUNTER_TREASURES + 1

func _init() -> void:
	var fails := 0

	for kind in KINDS:
		var label: String = KIND_NAMES.get(kind, str(kind))
		var enc_total := 0
		var enc_runs := 0
		for dungeon_id in Balance.DUNGEONS:
			var dd := Balance.dungeon(dungeon_id)
			for trial in 30:
				var tv := Traversal.make(kind)
				if tv == null:
					fails += 1; print("FAIL %s: make() returned null" % label); break
				tv.generate(dd)

				# a fresh run must not already be finished, and must offer choices
				if tv.is_complete():
					fails += 1; print("FAIL %s: complete immediately after generate" % label); break
				if tv.options().is_empty():
					fails += 1; print("FAIL %s: no options at start" % label); break

				# walk it to completion with an always-face policy
				var steps := 0
				var encounters := 0
				var bosses := 0
				var last_was_boss := false
				while not tv.is_complete() and steps < 100:
					steps += 1
					var opts := tv.options()
					if opts.is_empty():
						fails += 1
						print("FAIL %s: ran out of options before completing" % label)
						break
					# always pick a "face it" style option so the run progresses
					var pick := 0
					for i in opts.size():
						if not opts[i].has("hp_cost"):
							pick = i
							break
					var node := tv.select(pick)
					if node.is_empty():
						continue  # resolved internally
					if not node.has("type"):
						fails += 1; print("FAIL %s: encounter has no type" % label); break
					var t := int(node["type"])
					if t < 0 or t > Traversal.Enc.TREASURE:
						fails += 1; print("FAIL %s: bad encounter type %d" % [label, t]); break
					encounters += 1
					last_was_boss = t == Traversal.Enc.BOSS
					if last_was_boss:
						bosses += 1
					tv.clear_pending()
					var p := tv.progress()
					if p < 0.0 or p > 1.001:
						fails += 1; print("FAIL %s: progress out of range %.2f" % [label, p]); break

				if not tv.is_complete():
					fails += 1; print("FAIL %s: did not terminate in %d steps" % [label, steps]); break
				if bosses != 1:
					fails += 1; print("FAIL %s: %d bosses in a run (expect 1)" % [label, bosses]); break
				if not last_was_boss:
					fails += 1; print("FAIL %s: run did not END on the boss" % label); break

				# Budget is checked as an AVERAGE below, not per run: a model with
				# stochastic movement (dice) has real variance by design, and the
				# contract is about expected cost, not determinism. A loose per-run
				# bound still catches runaway generation.
				enc_total += encounters
				enc_runs += 1
				if encounters > budget() * 3:
					fails += 1
					print("FAIL %s: runaway run of %d encounters" % [label, encounters])
					break

		# average encounters per run must match the shared budget
		if enc_runs > 0:
			var avg := float(enc_total) / float(enc_runs)
			if abs(avg - float(budget())) > 2.0:
				fails += 1
				print("FAIL %s: averages %.1f encounters, budget %d (models must cost the same)" % [
					label, avg, budget()])
			else:
				print("  (info: %s averages %.1f encounters, budget %d)" % [label, avg, budget()])

	# --- graph specifics: every layer reachable, boss reachable ---
	var g := TraversalGraph.new()
	for t in 30:
		g.generate(null)
		var frontier: Array = []
		for col in g.map[0].size():
			frontier.append(col)
		for r in range(g.map.size() - 1):
			var nxt: Array = []
			for col in frontier:
				for e in g.map[r][col]["edges"]:
					if not e in nxt:
						nxt.append(e)
			if nxt.is_empty():
				fails += 1; print("FAIL GRAPH: dead end at row %d" % r); break
			frontier = nxt

	# --- dice specifics ---
	var di := TraversalDice.new()
	di.generate(null)
	if int(di.track[di.track.size() - 1]) != Traversal.Enc.BOSS:
		fails += 1; print("FAIL DICE: boss is not the final space")
	if di.options().size() != TraversalDice.DICE_ROLLED:
		fails += 1; print("FAIL DICE: expected %d dice options" % TraversalDice.DICE_ROLLED)
	# every option must move forward, and never past the boss
	for o in di.options():
		if int(o["dest"]) <= di.pos:
			fails += 1; print("FAIL DICE: option does not advance")
		if int(o["dest"]) > di.track.size() - 1:
			fails += 1; print("FAIL DICE: option moves past the board")
	# a roll of the maximum from the last-but-one space must still land on the boss
	di.pos = di.track.size() - 2
	di.dice = [TraversalDice.DIE_FACES]
	var only := di.options()
	if only.is_empty() or int(only[0]["type"]) != Traversal.Enc.BOSS:
		fails += 1; print("FAIL DICE: overshoot does not clamp onto the boss")

	# --- deck specifics ---
	var d := TraversalDeck.new()
	d.generate(null)
	# boss must be the bottom card
	if int(d.draw_pile[d.draw_pile.size() - 1]) != Traversal.Enc.BOSS:
		fails += 1; print("FAIL DECK: boss is not the bottom card")
	# counts must describe the real pile
	var sum := 0
	for k in d.remaining_counts():
		sum += int(d.remaining_counts()[k])
	if sum != d.draw_pile.size():
		fails += 1; print("FAIL DECK: remaining_counts disagrees with pile")
	# avoiding must consume the card without resolving it
	var before: int = d.draw_pile.size()
	var avoid_idx := -1
	var opts := d.options()
	for i in opts.size():
		if opts[i].has("hp_cost"):
			avoid_idx = i
	if avoid_idx >= 0:
		var r2 := d.select(avoid_idx)
		if not r2.is_empty():
			fails += 1; print("FAIL DECK: avoid returned an encounter to resolve")
		if d.draw_pile.size() != before - 1:
			fails += 1; print("FAIL DECK: avoid did not discard the card")
	# the boss can never be avoided
	while d.draw_pile.size() > 1:
		d.draw_pile.pop_front()
	d._reveal()
	for o in d.options():
		if o.has("hp_cost"):
			fails += 1; print("FAIL DECK: boss can be avoided")

	if fails == 0:
		print("TRAVERSAL TEST: PASS (contract holds for %d models: termination, one boss, equal budget)" % KINDS.size())
	else:
		print("TRAVERSAL TEST: FAIL (%d)" % fails)
	quit()
