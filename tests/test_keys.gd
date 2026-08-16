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
