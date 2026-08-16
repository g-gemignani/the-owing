## Headless test: the key currency (D315).
##
## A key is the only run resource the crawl PICKS UP off the floor, and the only one the
## model reports rather than holds: `TraversalIso` sets `picked_key` on itself and the view
## adds it, because a traversal owns no run resources (D13). That split is the whole reason
## this suite exists — a reported thing is only paid if the caller reaches the line that pays
## it, and for one release it did not.
##
## The bug it locks out: the payment sat inside the crawl's "this step resolved nothing"
## branch, next to the sentence announcing the pickup. Every other outcome of a step returns
## before that branch. So a key taken on a step that also started a fight went off the floor
## and into nothing, and the player walked to a locked chest holding a key they had watched
## themselves pick up.
##
## Run: godot --headless --script tests/test_keys.gd
extends SceneTree

## How many floors to lay before giving up on finding one with a key on it. Keys are placed
## per key-lock, and not every dungeon rolls one on its first floor.
const TRIES := 40

## Runs per dungeon for the supply sweep. Every floor of every run is laid out and read, so
## this is the suite's whole cost — six is ~90 floors per dungeon, which met every case the
## assertions below look for.
const RUNS_PER_DUNGEON := 6

func _init() -> void:
	var fails := 0

	# --- a key picked up on the same step as an ambush must still be a key ---
	#
	# Built rather than waited for: this is a collision of two things the floor does on one
	# turn, and a random walk finds it eventually and not on demand. The floor is real — a
	# generated one, with a real key on it — and only the two positions are placed.
	var staged := 0
	for did in Balance.DUNGEONS:
		if staged > 0:
			break
		for t in TRIES:
			var iso := TraversalIso.new()
			iso.generate(Balance.dungeon(did))
			var w := iso.grid().x
			# a key with somewhere to stand beside it, and somewhere else for a hunter
			var key_cell := -1
			var stand := -1
			var lurk := -1
			for i in iso.enc.size():
				if int(iso.enc[i]) != TraversalIso.KEY:
					continue
				var bare: Array = []
				for d in TraversalIso.DIRS:
					var n := i + int(d.x) + int(d.y) * w
					if n < 0 or n >= iso.enc.size():
						continue
					# the step across the grid edge wraps in the index and not on the floor
					if absi((i % w) - (n % w)) > 1:
						continue
					if int(iso.enc[n]) == TraversalIso.EMPTY:
						bare.append(n)
				if bare.size() >= 2:
					key_cell = i
					stand = int(bare[0])
					lurk = int(bare[1])
					break
			if key_cell < 0:
				continue
			# One hunter, standing next to the key. Everything else is cleared away so the
			# encounter that comes back can only be this one.
			iso.pos = stand
			iso.mons = [{
				"cell": lurk, "type": Traversal.Enc.COMBAT, "design": 0, "south": true,
				"pen": -1,
			}]
			var pick := -1
			var opts := iso.options()
			for k in opts.size():
				if int(opts[k].get("cell", -1)) == key_cell:
					pick = k
					break
			if pick < 0:
				continue
			var got: Dictionary = iso.select(pick)
			if not iso.picked_key:
				# not the staging we asked for; try another floor rather than assert on it
				continue
			staged += 1
			if got.is_empty():
				# The hunter did not reach — the collision this suite is about did not
				# happen, so there is nothing to assert here. Keep looking.
				staged = 0
				continue
			if int(iso.enc[key_cell]) != TraversalIso.EMPTY:
				fails += 1
				print("FAIL %s: the key tile is still a key after being picked up" % did)
			if not bool(got.get("ambush", false)):
				fails += 1
				print("FAIL %s: the step returned an encounter that is not the ambush: %s" % [
					did, got])
			break
	if staged == 0:
		fails += 1
		print("FAIL could not stage a key pickup that a hunter walks into — either keys "
			+ "stopped being placed or the floor stopped closing on the player")

	# --- and the view must pay it before the step becomes anything else ---
	#
	# The model half above proves the collision is reachable; nothing in a `--script` run can
	# drive `iso_run.gd`, which needs the autoloads. So the crawl's half is asserted on its
	# SOURCE: the line that adds the key must come before every early return in `_on_pick`,
	# and each of those returns is guarded by `if chosen.is_empty():`. Put the payment after
	# one of them and it is unreachable on exactly the turns that matter.
	var src := FileAccess.get_file_as_string("res://scripts/iso_run.gd")
	if src == "":
		fails += 1
		print("FAIL cannot read scripts/iso_run.gd")
	else:
		var body := src.substr(src.find("func _on_pick"))
		var end := body.find("\nfunc ")
		if end > 0:
			body = body.substr(0, end)
		var pay := body.find("GameState.keys += 1")
		var gate := body.find("if chosen.is_empty():")
		if pay < 0:
			fails += 1
			print("FAIL nothing in _on_pick adds a picked-up key to the run")
		elif gate >= 0 and pay > gate:
			fails += 1
			print("FAIL the key is paid inside a `chosen.is_empty()` branch — a key taken "
				+ "on a step that starts a fight is lost (D315)")

	# --- one key on the floor for every lock on it, and both KINDS of lock counted ---
	#
	# A key opens two different things, and they were built a milestone apart: a key-locked
	# chest (D172) and a sealed door (D185). One currency, two demands, and the supply is a
	# single addition in `_lay_floor` — `keyplan[depth] + _locked_mouths()` — which is the
	# shape a third demand gets added beside and nobody remembers to add to. So the count is
	# asserted against what the floor actually STANDS UP, not against the plan that asked for
	# it: chests read off `chest_of`, doors read off the carved `pockets`, keys read off `enc`.
	# Planned-versus-placed is where D172 went wrong the first time.
	#
	# Measured before this was written: 1,650 floors, 284 of them holding both kinds at once,
	# up to four locks on one floor, and not one floor short.
	var short := 0
	var floors_seen := 0
	var both_kinds := 0
	for did in Balance.DUNGEONS:
		for r in RUNS_PER_DUNGEON:
			var t := TraversalIso.new()
			t.generate(Balance.dungeon(did))
			for f in t.floors:
				t._build_floor(f)
				floors_seen += 1
				var chests := 0
				for cell in t.chest_of:
					if Balance.chest_lock(String(t.chest_of[cell])) == Balance.CHEST_LOCK_KEY:
						chests += 1
				var doors := 0
				for p in t.pockets:
					if String((p as Dictionary).get("lock", "")) == Balance.POCKET_LOCK_KEY:
						doors += 1
				if chests > 0 and doors > 0:
					both_kinds += 1
				var supply := 0
				var walk := t._dist_from(t.pos)
				for i in t.enc.size():
					if int(t.enc[i]) != TraversalIso.KEY:
						continue
					supply += 1
					# A key behind the lock it opens is worse than no key: the floor looks
					# solvable and is not. `carved` excludes the pockets, which is what keeps
					# this true — assert it rather than trust it.
					if int(walk[i]) < 0:
						fails += 1
						print("FAIL %s floor %d: a key sits where the floor cannot walk" % [
							did, f + 1])
				if supply < chests + doors:
					short += 1
					if short <= 3:
						print("FAIL %s floor %d: %d keys for %d locks (%d chests, %d doors)" % [
							did, f + 1, supply, chests + doors, chests, doors])
	if short > 0:
		fails += 1
		print("FAIL %d of %d floors cannot open everything they lock" % [short, floors_seen])
	if both_kinds == 0:
		fails += 1
		print("FAIL no floor in the sample held a chest lock and a door at once — the "
			+ "assertion above never met the case it exists for")

	# --- and the supply is only right while those two are the only spenders ---
	#
	# The check the addition itself cannot do. `_lay_floor` counts chest locks and doors
	# because those are what spend a key today; a third spender added anywhere else would take
	# from a supply nobody raised, and every floor would come up one short with no test red.
	# So the spenders are enumerated here, and adding one is required to fail this until
	# `_place_keys`'s count has grown to match.
	const SPENDERS := ["res://scripts/iso_run.gd", "res://scripts/chest_screen.gd"]
	var sd := DirAccess.open("res://scripts")
	if sd == null:
		fails += 1
		print("FAIL cannot open res://scripts")
	else:
		for f in sd.get_files():
			var path := "res://scripts/" + String(f)
			if not path.ends_with(".gd"):
				continue
			var text := FileAccess.get_file_as_string(path)
			if not text.contains("GameState.keys -= "):
				continue
			if not (path in SPENDERS):
				fails += 1
				print(("FAIL %s spends a key, and the floor's key count does not know about "
					+ "it — raise the count in TraversalIso._lay_floor, then add the file "
					+ "here (D316)") % path)

	# --- a key is part of the run, so it must survive being saved with it ---
	#
	# A key is carried across a scene change and across quitting the game, and the chest that
	# wants it is several screens away from the floor it was found on. Written half here;
	# the reading half is asserted on the source, because `run_from_dict` fetches
	# `/root/MetaState` and there are no autoloads in a `--script` run.
	var GS = load("res://scripts/game_state.gd")
	var g = GS.new()
	g.dungeon_id = String(Balance.DUNGEONS[0])
	g.traversal = TraversalIso.new()
	g.traversal.generate(Balance.dungeon(g.dungeon_id))
	g.keys = 3
	var d: Dictionary = g.run_to_dict()
	if int(d.get("keys", -1)) != 3:
		fails += 1
		print("FAIL keys are not written into the run save: %s" % d.get("keys", "absent"))
	var gs_src := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	var restore := gs_src.substr(gs_src.find("func run_from_dict"))
	var restore_end := restore.find("\nfunc ")
	if restore_end > 0:
		restore = restore.substr(0, restore_end)
	if not restore.contains('d.get("keys"'):
		fails += 1
		print("FAIL run_from_dict does not restore keys — a key found before a quit is gone")

	if fails == 0:
		print("KEYS TEST: PASS (a key survives the turn it is taken on, and the save)")
	else:
		print("KEYS TEST: FAIL (%d)" % fails)
	quit()
