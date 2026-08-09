## Runtime test: a finger can move every list in the game (D225).
##
## Reported from a phone: "on Android I cannot scroll on that screen." There is no
## wheel on a phone, so a drag is the only gesture there is, and this game cannot use
## the engine's own touch-drag path on `ScrollContainer` — the whole UI is built on
## `emulate_mouse_from_touch`, and a list of buttons consumes the press before the
## container ever sees a drag begin.
##
## A SCENE test because every claim here is about input reaching a built tree, and the
## events are MOUSE events on purpose: that is what a tap and a swipe arrive as once
## the emulation this game depends on has had them.
##
## `UI.DragScroll` disables itself off a touchscreen, which a headless run is, so each
## check turns it back on explicitly. The platform gate is one line; the gesture is the
## part that can break.
extends Node

## Every user:// file this suite may create begins with this.
const SANDBOX := "t_touchscroll_"

var _fails := 0

func _ready() -> void:
	await get_tree().process_frame
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()

	await _check_a_drag_scrolls(false)
	await _check_a_drag_scrolls(true)
	await _check_a_tap_does_not_scroll()
	await _check_a_drag_outside_is_not_ours()
	_check_every_scroll_has_one()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("TOUCH SCROLL TEST: PASS (a drag moves a list of buttons, a tap does not, and every UI.scroll carries the handler)")
	else:
		print("TOUCH SCROLL TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)

## A list of 40 rows in a 300px frame, with the handler live.
func _list(with_buttons: bool) -> Array:
	var vp := SubViewport.new()
	vp.size = Vector2i(400, 300)
	vp.handle_input_locally = true
	get_tree().root.add_child(vp)
	var host := Control.new()
	host.size = Vector2(400, 300)
	vp.add_child(host)
	var col := UI.scroll(host)
	var sc := col.get_parent() as ScrollContainer
	sc.size = Vector2(400, 300)
	for i in 40:
		var row: Control = Button.new() if with_buttons else Label.new()
		if row is Button:
			(row as Button).text = "row %d" % i
		else:
			(row as Label).text = "row %d" % i
		row.custom_minimum_size.y = 40
		col.add_child(row)
	for k in sc.get_children():
		if k is UI.DragScroll:
			(k as Node).set_process_input(true)
	await get_tree().process_frame
	await get_tree().process_frame
	return [vp, sc]

func _drop(vp: SubViewport) -> void:
	vp.queue_free()
	await get_tree().process_frame

## Dragging up moves the list down by the same distance — over plain rows, and over the
## BUTTONS that are the reason the engine's own handling cannot be relied on here.
func _check_a_drag_scrolls(with_buttons: bool) -> void:
	var pair := await _list(with_buttons)
	var vp: SubViewport = pair[0]
	var sc: ScrollContainer = pair[1]
	var what := "buttons" if with_buttons else "labels"
	if sc.get_v_scroll_bar().max_value <= sc.size.y:
		_fail("the %s list does not overflow, so this check is measuring nothing" % what)
		await _drop(vp)
		return
	await _swipe(vp, Vector2(200, 150), 160.0)
	if sc.scroll_vertical < 150 or sc.scroll_vertical > 170:
		_fail("a 160px drag over %s moved the list %d" % [what, sc.scroll_vertical])
	await _drop(vp)

## ...and a tap does not. A hand is never perfectly still, and a list that scrolls on a
## 3px wobble is a screen whose every button feels like it is refusing presses.
func _check_a_tap_does_not_scroll() -> void:
	var pair := await _list(true)
	var vp: SubViewport = pair[0]
	var sc: ScrollContainer = pair[1]
	await _swipe(vp, Vector2(200, 150), 3.0)
	if sc.scroll_vertical != 0:
		_fail("a 3px wobble scrolled the list by %d" % sc.scroll_vertical)
	await _drop(vp)

## A gesture that starts somewhere else is not this list's to follow — otherwise two
## lists on one screen both move, and so does the one behind a menu.
func _check_a_drag_outside_is_not_ours() -> void:
	var pair := await _list(true)
	var vp: SubViewport = pair[0]
	var sc: ScrollContainer = pair[1]
	sc.position = Vector2(0, 150)
	sc.size = Vector2(400, 150)
	await get_tree().process_frame
	await _swipe(vp, Vector2(200, 40), 100.0)   # above the list
	if sc.scroll_vertical != 0:
		_fail("a drag that began outside the list scrolled it by %d" % sc.scroll_vertical)
	await _drop(vp)

## Every screen gets the handler from `UI.scroll` and none of them has to remember it —
## which is the point of it living there, and the thing that would rot if a screen ever
## hand-rolled its own ScrollContainer again.
func _check_every_scroll_has_one() -> void:
	var missing: Array[String] = []
	for path in ["res://scripts/powers_screen.gd", "res://scripts/collection.gd",
			"res://scripts/overworld.gd", "res://scripts/glossary.gd",
			"res://scripts/zone_view.gd", "res://scripts/save_slots.gd",
			"res://scripts/packs_screen.gd", "res://scripts/builds_screen.gd"]:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_fail("cannot read %s" % path)
			continue
		var text := f.get_as_text()
		f.close()
		if text.find("ScrollContainer.new()") != -1:
			missing.append(path)
	if not missing.is_empty():
		_fail("these build their own ScrollContainer and miss the drag handler: %s" % [missing])

## Press, move in steps, release — the shape a real swipe arrives in.
func _swipe(vp: SubViewport, from: Vector2, distance: float) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	vp.push_input(down)
	await get_tree().process_frame
	var steps: int = maxi(1, int(distance / 20.0))
	for i in range(1, steps + 1):
		var to: Vector2 = from - Vector2(0, distance * float(i) / float(steps))
		var mm := InputEventMouseMotion.new()
		mm.position = to
		mm.global_position = to
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		vp.push_input(mm)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = from - Vector2(0, distance)
	up.global_position = up.position
	vp.push_input(up)
	await get_tree().process_frame

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
