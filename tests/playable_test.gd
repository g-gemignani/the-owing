## Integration test: the game is actually PLAYABLE, not merely loadable.
##
## Written after a black screen reached a player. `map.gd` stopped compiling and
## stayed broken for five commits, each of which reported a fully green suite,
## because every existing test either read the file as text or checked
## `load(path) != null` — and `load()` happily returns a Resource for a script
## that failed to parse.
##
## The lesson had already been written down once, in D33: *booting is not
## playability*. It was enforced for one screen. This enforces it for all of them,
## and for every dungeon.
##
## What it asserts, in order of how badly each has bitten:
##
## 1. Every screen instantiates AND offers at least one thing the player can press.
## 2. Every dungeon can be entered, and its traversal view offers a reachable
##    encounter. This is the exact failure that was reported.
## 3. A combat can be played from the first card to victory, through the real
##    scene, not the engine alone.
## 4. A rest resolves and hands control back.
## Run: godot --headless res://tests/PlayableTest.tscn
extends Node

var _fails := 0

func _ready() -> void:
	# Headless defaults to a SQUARE 1280x1280 viewport, so every on-screen check in
	# every scene test has been measuring the wrong window. Use the shipped size.
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	UITheme.set_scale_silent(UITheme.UI_SCALE)   # and the shipped UI scale
	await get_tree().process_frame

	MetaState.path_prefix = "t_playable_"
	MetaState.slot = 0
	MetaState.new_save()

	await _every_screen_is_usable()
	await _every_dungeon_is_enterable()
	await _a_combat_can_be_won()
	await _a_rest_resolves()
	await _every_encounter_can_be_left()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("PLAYABLE TEST: PASS (every screen usable, every dungeon enterable, combat winnable)")
	else:
		print("PLAYABLE TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## --- 1. every screen gives the player something to do -----------------------
##
## A screen that instantiates but presents no enabled control is a dead end, and
## indistinguishable from a crash to whoever is holding the controller.
func _every_screen_is_usable() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}

	for name in _scene_names():
		# The three traversal views run on state only their own kind of dungeon
		# produces. Handing a dice board a graph run is a state the game never
		# creates, and one of them spins forever on it. Stage 2 covers all three
		# properly, once per dungeon, with the state they actually receive.
		if name in ["Map", "DeckRun", "DiceRun"]:
			continue
		var path := "res://scenes/%s.tscn" % name
		var packed := load(path) as PackedScene
		if packed == null:
			_fails += 1; print("FAIL %s does not load" % name); continue
		var inst = packed.instantiate()
		if inst == null:
			_fails += 1; print("FAIL %s does not instantiate" % name); continue
		add_child(inst)
		await get_tree().process_frame
		if not is_inside_tree():
			print("FAIL %s navigated away in _ready — it had no usable state" % name)
			return
		await get_tree().process_frame
		# the root script must have survived instantiation with its behaviour
		var sc = inst.get_script()
		if sc != null and (sc as GDScript).get_instance_base_type() == "":
			_fails += 1; print("FAIL %s root script did not compile" % name)
		var usable := _enabled_buttons(inst)
		if usable == 0:
			_fails += 1
			print("FAIL %s presents nothing the player can press — a dead end" % name)
		inst.queue_free()
		await get_tree().process_frame

## --- 2. every dungeon can actually be entered -------------------------------
##
## The reported bug exactly: enter the Crypt, get a black screen. Covers all three
## traversal models because the dungeons use all three.
func _every_dungeon_is_enterable() -> void:
	for did in Balance.DUNGEONS:
		_start_a_run(did)
		var scene_path: String = GameState.run_scene()
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fails += 1; print("FAIL %s: %s does not load" % [did, scene_path]); continue
		var inst = packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame

		var sc = inst.get_script()
		if sc != null and (sc as GDScript).get_instance_base_type() == "":
			_fails += 1
			print("FAIL %s: %s did not compile — the player gets a black screen" % [
				did, scene_path])
		elif _enabled_buttons(inst) == 0:
			_fails += 1
			print("FAIL %s: entered the dungeon and there is nothing to click" % did)
		# and the traversal itself must offer somewhere to go
		if GameState.traversal != null and GameState.traversal.options().is_empty():
			_fails += 1; print("FAIL %s offers no reachable encounter" % did)
		inst.queue_free()
		await get_tree().process_frame

## --- 3. a fight can be played to the end through the real screen ------------
func _a_combat_can_be_won() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var eng = inst.eng
	if eng == null:
		_fails += 1; print("FAIL combat started with no engine"); inst.queue_free(); return
	# play greedily: everything affordable, then end the turn, until somebody wins
	var guard := 0
	while not eng.over() and guard < 200:
		guard += 1
		var played := false
		for card in eng.hand.duplicate():
			if eng.can_play(card):
				eng.play_card(card)
				played = true
		if not played or eng.energy <= 0:
			eng.end_turn()
	if guard >= 200:
		_fails += 1; print("FAIL a combat never ended after 200 turns")
	elif not eng.won():
		# losing a fight is legal, but a starter deck should beat a d1 normal
		_fails += 1; print("FAIL a starter deck lost a first-dungeon fight")
	inst.queue_free()
	await get_tree().process_frame

## --- 4. a rest resolves and returns control ---------------------------------
func _a_rest_resolves() -> void:
	_start_a_run("crypt")
	var inst = (load(GameState.run_scene()) as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame

	var resolved := [false]
	var node := {"type": GameState.NodeType.REST, "row": 0, "col": 0, "cleared": false}
	GameState.hp = 10
	RunFlow.enter_node(inst, node, func(): resolved[0] = true)
	await get_tree().process_frame
	# a rest is a choice now, so it must put a choice on screen
	if _enabled_buttons(inst) == 0:
		_fails += 1; print("FAIL resting presents no options")
	# take the first offered option and confirm control comes back
	for b in _buttons(inst):
		if not b.disabled and String(b.text).begins_with("Recover"):
			b.pressed.emit()
			break
	await get_tree().process_frame
	if not resolved[0]:
		_fails += 1; print("FAIL resting never handed control back to the map")
	if GameState.hp <= 10:
		_fails += 1; print("FAIL resting did not heal")
	inst.queue_free()
	await get_tree().process_frame

## --- 5. every encounter can be entered AND left ------------------------------
##
## The gap that let a broken shop reach a player: screens were checked in
## isolation and dungeons were checked as enterable, but nothing walked a run
## through an encounter and back out. A screen whose exit is unreachable — or
## which fails to clear its node, so the map keeps offering it — looks exactly
## like "I entered and now I cannot continue".
func _every_encounter_can_be_left() -> void:
	var types := {
		GameState.NodeType.SHOP: "res://scenes/Shop.tscn",
		GameState.NodeType.EVENT: "res://scenes/Encounter.tscn",
		GameState.NodeType.TREASURE: "res://scenes/Encounter.tscn",
	}
	for did in ["crypt", "ossuary", "ember_road"]:   # graph, deck, dice
		for t in types:
			_start_a_run(did)
			var tv = GameState.traversal
			if tv.options().is_empty():
				_fails += 1; print("FAIL %s offers nothing to enter" % did); continue
			# take a real option and make it the encounter under test
			var node = tv.select(0)
			node["type"] = t
			GameState.pending = node
			GameState.shop_stock = []

			var inst = (load(types[t]) as PackedScene).instantiate()
			add_child(inst)
			await get_tree().process_frame
			await get_tree().process_frame

			# there must be a way out, and it must be ON SCREEN
			var vp := get_viewport().get_visible_rect()
			var exits := 0
			var offscreen := 0
			for b in _buttons(inst):
				if b.disabled or not b.visible:
					continue
				if b.pressed.get_connections().is_empty():
					continue
				exits += 1
				if not vp.intersects(b.get_global_rect()):
					offscreen += 1
			if exits == 0:
				_fails += 1
				print("FAIL %s in %s offers no working button — the run is stuck" % [
					Balance.NODE_LABEL.get(t, "?"), did])
			elif offscreen == exits:
				_fails += 1
				print("FAIL every button in %s (%s) is off screen at %dx%d" % [
					Balance.NODE_LABEL.get(t, "?"), did, int(vp.size.x), int(vp.size.y)])
			inst.queue_free()
			await get_tree().process_frame

			# ...and leaving must actually release the node, or the map re-offers it
			GameState.clear_node(GameState.pending)
			if tv.options().is_empty() and int(node["type"]) != GameState.NodeType.BOSS:
				_fails += 1
				print("FAIL %s: after a %s the run has nowhere left to go" % [
					did, Balance.NODE_LABEL.get(t, "?")])

# --- helpers -----------------------------------------------------------------

## A legal run, ready to play: a real deck, a real map, a real power.
func _start_a_run(dungeon_id: String) -> void:
	MetaState.new_save()
	GameState.reset_run_progress()
	GameState.select_dungeon(dungeon_id)
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var e: Dictionary = MetaState.collection[id]
		for i in int(e["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(e["level"])
			deck.append(c)
	GameState.enter_dungeon(deck)
	GameState.hp = GameState.max_hp
	# Screens bail out by NAVIGATING when their state is missing — ZoneView with no
	# zone calls change_scene_to_file, which in a harness replaces the test scene
	# itself and hangs the await forever. Every screen therefore gets plausible
	# state, the same way the game would have given it some.
	var z := Balance.zone_of(dungeon_id)
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]
	GameState.last_relic = ""

func _scene_names() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://scenes/")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tscn"):
			out.append(f.replace(".tscn", ""))
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out

func _enabled_buttons(n: Node) -> int:
	var count := 0
	for b in _buttons(n):
		if not b.disabled:
			count += 1
	return count

func _purge() -> void:
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
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
