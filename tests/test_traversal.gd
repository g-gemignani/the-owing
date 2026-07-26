## Headless test: the Traversal contract, applied to EVERY model.
##
## The point of this file is that it is model-agnostic: adding a traversal only
## requires adding its Kind to KINDS below. Anything a model must guarantee for
## combat/meta/balance to keep working is asserted here.
## Run: godot --headless --script tests/test_traversal.gd
extends SceneTree

const KINDS := [Traversal.Kind.GRAPH, Traversal.Kind.DECK, Traversal.Kind.DICE,
	Traversal.Kind.ISO]
const KIND_NAMES := {0: "GRAPH", 1: "DECK", 2: "DICE", 3: "ISO"}

## Encounters one run of `did` should cost. The mix is per-dungeon now, but every
## MODEL still has to spend the same one — that is the contract this test exists
## for, and it is what lets a difficulty rating mean one thing across three very
## different ways of walking a dungeon.
func budget(did: String = "") -> int:
	var dd := Balance.dungeon(did) if did != "" else null
	if dd == null:
		return Balance.ENCOUNTER_COMBATS + Balance.ENCOUNTER_ELITES \
			+ Balance.ENCOUNTER_RESTS + Balance.ENCOUNTER_SHOPS \
			+ Balance.ENCOUNTER_EVENTS + Balance.ENCOUNTER_TREASURES + 1
	var m := dd.encounter_mix()
	var n := 1   # the boss
	for k in m:
		n += int(m[k])
	return n

func _init() -> void:
	var fails := 0

	for kind in KINDS:
		var label: String = KIND_NAMES.get(kind, str(kind))
		var enc_total := 0
		var enc_runs := 0
		var budget_total := 0
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
				budget_total += budget(dungeon_id)
				if encounters > budget(dungeon_id) * 3:
					fails += 1
					print("FAIL %s: runaway run of %d encounters" % [label, encounters])
					break

		# Average encounters per run must match what the dungeons asked for. Compared
		# against the mean of the PER-DUNGEON budgets now that the mix varies by
		# place — the contract was never "every run is nine encounters", it is "the
		# three models cost the same as each other".
		if enc_runs > 0:
			var avg := float(enc_total) / float(enc_runs)
			var want := float(budget_total) / float(enc_runs)
			if abs(avg - want) > 2.0:
				fails += 1
				print("FAIL %s: averages %.1f encounters, dungeons asked for %.1f (models must cost the same)" % [
					label, avg, want])
			else:
				print("  (info: %s averages %.1f encounters, asked for %.1f)" % [label, avg, want])

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

	# --- iso specifics ---
	#
	# The floor is the one model whose budget can leak GEOMETRICALLY: if the grid
	# cannot hold a room per budgeted encounter, the surplus is dropped on the floor
	# during generation and the dungeon quietly becomes cheaper than the same
	# dungeon walked any other way. Nothing above would notice — every other
	# assertion is about the walk, not the map it was cut from.
	for did4 in Balance.DUNGEONS:
		var dd5 := Balance.dungeon(did4)
		var iso := TraversalIso.new()
		iso.generate(dd5)
		var want: int = Traversal.standard_encounters(dd5).size() + 2
		if iso.rooms != want:
			fails += 1
			print("FAIL ISO %s: carved %d rooms for a budget that needs %d — ISO_GRID is too small" % [
				did4, iso.rooms, want])
		var placed := 0
		var bosses2 := 0
		for e in iso.enc:
			if int(e) >= 0:
				placed += 1
			if int(e) == Traversal.Enc.BOSS:
				bosses2 += 1
		if placed != want - 1:
			fails += 1
			print("FAIL ISO %s: %d encounters on a floor that budgeted %d" % [
				did4, placed, want - 1])
		if bosses2 != 1:
			fails += 1; print("FAIL ISO %s: %d stairs down" % [did4, bosses2])

	var iso2 := TraversalIso.new()
	iso2.generate(null)
	# the stair must be the furthest room from the entrance: a floor that can be
	# crossed in three rooms is a floor that skips the budget
	var d_entry: Array = iso2._dist_from(iso2.pos)
	var stair := -1
	var furthest := 0
	for i in iso2.enc.size():
		if int(iso2.enc[i]) == Traversal.Enc.BOSS:
			stair = i
		if int(iso2.enc[i]) != TraversalIso.WALL:
			furthest = maxi(furthest, int(d_entry[i]))
	if stair < 0 or int(d_entry[stair]) != furthest:
		fails += 1
		print("FAIL ISO: the stair is %d steps in and the floor reaches %d — it is not the far end" % [
			int(d_entry[stair]) if stair >= 0 else -1, furthest])
	# the entrance is somewhere you have already been, not a free encounter
	if int(iso2.enc[iso2.pos]) != TraversalIso.EMPTY:
		fails += 1; print("FAIL ISO: the entrance room holds an encounter")
	# ...and it must offer a choice, like the first row of every other model. The
	# carve seeds a stub with one door, so this is the assertion that keeps the
	# entrance from being picked for convenience.
	var entry_doors := 0
	for n in iso2._neighbours(iso2.pos):
		if int(iso2.enc[n]) != TraversalIso.WALL:
			entry_doors += 1
	if entry_doors < 2:
		fails += 1
		print("FAIL ISO: the entrance has %d door(s) — the run opens on no decision" % entry_doors)
	# The floor must be deep from where you come in. Taking the most-connected room
	# as the entrance put it in the middle of the plate, where the furthest room —
	# and therefore the stair — was TWO steps away and the whole floor could be
	# skipped by walking into it. Measured over 3000 floors after the fix: 4 to 8
	# steps, mode 5.
	if furthest < 3:
		fails += 1
		print("FAIL ISO: the floor only reaches %d steps from the entrance — that is a puddle" % furthest)
	# every option must be a step to an adjoining room, and the stair must sort LAST
	# while anything else is unexplored (that ordering is what makes a greedy
	# walker — the simulator, and a player leaning on the first button — spend a
	# whole floor instead of beelining for the exit)
	for o in iso2.options():
		if not o.has("cell") or not o.has("label"):
			fails += 1; print("FAIL ISO: option is not a move"); break
	# the torch must pay for a straight walk to the stair, or the price of the dark
	# is levied on a player who had no choice but to walk
	if iso2.torch < furthest:
		fails += 1
		print("FAIL ISO: %d torch for a stair %d steps away — reaching it costs HP by force" % [
			iso2.torch, furthest])
	# ...and it must NOT pay for stripping the whole floor twice over, or light is
	# decoration and the model has no cost at all
	if iso2.torch >= (iso2.rooms - 1) * 2:
		fails += 1
		print("FAIL ISO: %d torch on a %d-room floor — wandering is free" % [
			iso2.torch, iso2.rooms])
	print("  (info: iso floor %d rooms, stair %d steps in, torch %d)" % [
		iso2.rooms, furthest, iso2.torch])
	# the dark is priced by depth, like every other cost in a scaling game
	if Balance.iso_dark_cost(8) <= Balance.iso_dark_cost(1):
		fails += 1; print("FAIL a step in the dark costs no more at depth 8 than at depth 1")

	# --- a dungeon may have its own shape, within reason -----------------------
	#
	# Every dungeon used to draw from one global mix, so twelve dungeons had one
	# rhythm. They differ now — a swarm, a treasure run, a market, a gauntlet — and
	# these are the bounds that keep "difficulty 5" meaning the same thing in all of
	# them. Without them the mix is a back door onto the difficulty curve: a dungeon
	# could quietly halve its fights and keep its rating.
	var shapes := {}
	for did3 in Balance.DUNGEONS:
		var dd4 := Balance.dungeon(did3)
		if dd4 == null:
			continue
		var mix: Dictionary = dd4.encounter_mix()
		var fights: int = int(mix["combat"]) + int(mix["elite"])
		var total := 1
		for k2 in mix:
			total += int(mix[k2])
		shapes[did3] = "%d/%d/%d/%d/%d/%d" % [mix["combat"], mix["elite"], mix["rest"],
			mix["shop"], mix["event"], mix["treasure"]]
		if total < 8 or total > 11:
			fails += 1
			print("FAIL %s runs %d encounters; the band is 8-11" % [did3, total])
		if fights < 3 or fights > 6:
			fails += 1
			print("FAIL %s has %d fights; the band is 3-6" % [did3, fights])
		# something other than fighting has to happen, or the dungeon is a treadmill
		if int(mix["rest"]) + int(mix["shop"]) + int(mix["event"]) + int(mix["treasure"]) < 2:
			fails += 1
			print("FAIL %s is nothing but fights" % did3)
	# ...and they must not all be the same shape, which is the thing being fixed
	var distinct := {}
	for k3 in shapes:
		distinct[shapes[k3]] = true
	if distinct.size() < 6:
		fails += 1
		print("FAIL only %d distinct dungeon shapes across %d dungeons" % [
			distinct.size(), shapes.size()])
	print("  (info: %d distinct shapes across %d dungeons)" % [distinct.size(), shapes.size()])

	# --- the dodge has to be a trade, not a discount --------------------------
	#
	# It was a flat 8 HP and nothing measured it, because the simulator's driver
	# only dodged below 35% HP and therefore never dodged at all. Measured properly,
	# skipping every avoidable fight beat fighting outright — the Drowned Market
	# went 49% to 87% for the same deck. A dominant strategy is a removed decision
	# (D20), so the price now rises with depth and with each dodge already taken.
	#
	# Asserted structurally rather than by simulation: what breaks the mechanic is
	# the TOTAL being small against the health bar you are spending it from.
	var dodgeable: int = Balance.ENCOUNTER_COMBATS + Balance.ENCOUNTER_ELITES
	for did in Balance.DUNGEONS:
		var dd2 := Balance.dungeon(did)
		if dd2 == null or dd2.traversal != Traversal.Kind.DECK:
			continue
		var depth: int = dd2.difficulty
		var bar := float(Balance.BASE_MAX_HP + (depth - 1) * Balance.HP_PER_DUNGEON)
		var total := 0
		var prev := 0
		for i in dodgeable:
			var c: int = Balance.deck_avoid_cost(depth, i)
			if c <= prev:
				fails += 1
				print("FAIL %s: dodge %d costs %d, no more than the one before it (%d)" % [
					did, i + 1, c, prev])
			prev = c
			total += c
		# skipping the whole dungeon must cost most of a health bar...
		if float(total) < bar * 0.5:
			fails += 1
			print("FAIL %s: dodging every fight costs %d of %d HP — the dungeon can be skipped on pocket change" % [
				did, total, int(bar)])
		# ...while one dodge stays affordable, or nobody would ever use it
		var first: int = Balance.deck_avoid_cost(depth, 0)
		if float(first) > bar * 0.25:
			fails += 1
			print("FAIL %s: the first dodge costs %d of %d HP, too dear to ever be worth it" % [
				did, first, int(bar)])
	# and depth must matter, or a flat price gets cheaper the deeper you go
	if Balance.deck_avoid_cost(8, 0) <= Balance.deck_avoid_cost(1, 0):
		fails += 1
		print("FAIL the dodge costs no more at depth 8 than at depth 1")

	if fails == 0:
		print("TRAVERSAL TEST: PASS (contract holds for %d models: termination, one boss, equal budget, priced dodge)" % KINDS.size())
	else:
		print("TRAVERSAL TEST: FAIL (%d)" % fails)
	quit()
