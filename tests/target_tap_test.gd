## Runtime test: a press on an enemy selects it, and the rest of the screen still works.
##
## The bug this exists for (D326): `enemy_box` is a full-rect layer BEHIND the layout
## column, and the column is a `MarginContainer` — which defaults to `MOUSE_FILTER_PASS`.
## PASS forwards an event to that container's own ANCESTORS. It does not let the event
## reach anything drawn behind it. So a full-screen layout container sat over every enemy
## on the screen and ate every press meant for one, on desktop and on a phone alike, for
## the three weeks between the fight being framed head-on and this test.
##
## Nothing said so. The engine auto-targets a living enemy and moves on when it dies, so
## a one-enemy fight plays perfectly and a group fight just hits whoever the engine chose.
## The only symptom is that choosing does not work, and a player has to try it to find out.
##
## **The events are pushed at the VIEWPORT, not at the button.** `Button.emit_signal(
## "pressed")` proves the handler is connected and proves nothing about whether a press
## can reach it, which is the entire question.
##
## A mouse press AND a screen touch, because the report was that one platform works and
## the other does not. The two are different claims: a mouse press is the desktop, and a
## touch is the `emulate_mouse_from_touch` conversion this whole UI stands on (the same
## reasoning as `touch_scroll_test.gd`, which pushes only the converted form).
##
## Run at two frame shapes, because the blocker is a full-rect node and a layout that
## clears the enemies at 1280x720 can cover them at a phone's aspect.
##
## Run: godot --headless res://tests/TargetTapTest.tscn
extends Node

## Every user:// file this suite may create begins with this.
const SANDBOX := "t_targettap_"

## Desktop, and a landscape phone. `window/handheld/orientation` is sensor-landscape,
## so the second is the shape the game actually opens in on a handset.
const SHAPES := [Vector2i(1280, 720), Vector2i(854, 400)]

var _fails := 0

func _ready() -> void:
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()

	for shape in SHAPES:
		await _a_press_on_an_enemy_selects_it(shape)
		await _the_rest_of_the_screen_is_still_reachable(shape)

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("TARGET TAP TEST: PASS (every enemy takes a press, and so does everything else)")
	else:
		print("TARGET TAP TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)

## A fight with three of one archetype, so there is something to CHOOSE between. The
## archetype is forced through `pending.enemy`, which is the key the iso floor already
## uses to make the tile you walked into and the fight you get the same creature (D85).
func _a_fight(shape: Vector2i, archetype: String) -> Node:
	get_window().size = shape
	MetaState.new_save()
	GameState.reset_run_progress()
	GameState.select_dungeon("crypt")
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var e: Dictionary = MetaState.collection[id]
		for i in int(e["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(e["level"])
			deck.append(c)
	GameState.enter_dungeon(deck)
	GameState.hp = GameState.max_hp
	var z := Balance.zone_of("crypt")
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]
	GameState.pending = {"type": GameState.NodeType.COMBAT, "enemy": archetype}
	GameState.combat_state = {}
	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	return inst

## A press and a release at one point, through the viewport's own picking.
func _press(at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		get_viewport().push_input(ev, true)
		await get_tree().process_frame

## The same gesture as a finger makes. Pushed as a touch and NOT as a mouse event, so
## the `emulate_mouse_from_touch` conversion this whole UI stands on is inside the claim.
func _touch(at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventScreenTouch.new()
		ev.index = 0
		ev.pressed = down
		ev.position = at
		get_viewport().push_input(ev, true)
		await get_tree().process_frame

## The report, and the whole point of the file.
func _a_press_on_an_enemy_selects_it(shape: Vector2i) -> void:
	var inst = await _a_fight(shape, "plague_rat")
	var eng = inst.eng
	if eng == null:
		_fail("%s: the fight has no engine" % str(shape))
		inst.queue_free()
		return
	if eng.enemies.size() < 2:
		_fail("%s: a targeting test needs more than one enemy, got %d" % [
			str(shape), eng.enemies.size()])
	# Back to front, and the target is cleared between presses: starting from a valid
	# target and ending on one proves nothing when the two can be the same enemy.
	#
	# Both event kinds, because the report was that one platform works and the other does
	# not. A finger arrives as `InputEventScreenTouch` and this project turns it into a
	# mouse press (`emulate_mouse_from_touch`), so the two are separate claims: the mouse
	# is the desktop and the emulation together, the touch is the conversion as well.
	for i in range(eng.enemies.size() - 1, -1, -1):
		var hit: Button = (inst.enemy_plates[i] as Control).get_meta("hit")
		var at: Vector2 = hit.get_global_rect().get_center()
		for how in ["a mouse press", "a finger"]:
			eng.target = -1
			if how == "a finger":
				await _touch(at)
			else:
				await _press(at)
			if eng.target != i:
				_fail("%s: %s on the middle of enemy %d selected %d — %s" % [
					str(shape), how, i, eng.target, _over(inst, at, i)])
	inst.queue_free()
	await get_tree().process_frame

## What the fix must not cost. A container told to IGNORE the mouse still has its
## CHILDREN picked, and this is the assertion that says so out loud — the fix looks like
## it turns the whole layout column off, and the reason it does not is a Godot rule
## nobody should have to remember.
func _the_rest_of_the_screen_is_still_reachable(shape: Vector2i) -> void:
	var inst = await _a_fight(shape, "cultist")
	var wanted := {
		"Menu": inst.menu_btn,
		"End Turn": inst.end_btn,
		"the power orb": inst.power_btn,
	}
	for card in inst.card_widgets.keys():
		wanted["a card in hand"] = inst.card_widgets[card]
		break
	for what in wanted:
		var c: Control = wanted[what]
		if c == null or not c.is_visible_in_tree():
			_fail("%s: %s is not on the screen" % [str(shape), what])
			continue
		var at: Vector2 = c.get_global_rect().get_center()
		var picked := _picked(inst, at)
		if picked != c and not c.is_ancestor_of(picked) and not picked.is_ancestor_of(c):
			_fail("%s: a press on %s lands on %s instead" % [str(shape), what, picked.name])
	inst.queue_free()
	await get_tree().process_frame

## The topmost control that would take a press at this point: the same walk the engine
## does — children in reverse order first, then the node itself, skipping anything set
## to IGNORE.
func _picked(n: Node, at: Vector2) -> Control:
	var kids := n.get_children()
	kids.reverse()
	for k in kids:
		var found := _picked(k, at)
		if found != null:
			return found
	var c := n as Control
	if c != null and c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and c.get_global_rect().has_point(at):
		return c
	return null

## Everything sitting over an enemy that is not the enemy, for the failure message. A
## bare "it selected the wrong one" sends the reader back to the debugger; the name of
## the node that took the press is the answer.
func _over(inst: Node, at: Vector2, i: int) -> String:
	var slot: Control = inst.enemy_plates[i]
	var out: Array[String] = []
	_collect(inst, at, slot, out)
	return "over it: " + (", ".join(out) if not out.is_empty() else "nothing")

func _collect(n: Node, at: Vector2, skip: Control, out: Array[String]) -> void:
	var c := n as Control
	if c != null and c != skip and not skip.is_ancestor_of(c) \
			and c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE \
			and c.get_global_rect().has_point(at):
		out.append("%s (%s, filter %d)" % [c.name, c.get_class(), c.mouse_filter])
	for k in n.get_children():
		_collect(k, at, skip, out)

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var doomed: Array[String] = []
	var f := d.get_next()
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
