## Runtime test: the Cards screen's grid view is a screen you can actually use.
##
## A SCENE test, not a `--script` one, for the reason `tooltip_test.gd` gives: every
## claim here is about a built tree. A drop target's `_can_drop_data` is a virtual on a
## node, a double click is an event delivered to a control that exists, and a view
## toggle is a screen torn down and put back up. None of it can be asked of a script.
##
## Four gestures were added at once in D213 and each of them is the ONLY way to do
## something, which is what makes them worth a suite: drag and double-click are the two
## ways a copy goes in, a click on the deck bay is the only way one comes out, and the
## badge is the only route to a fuse price in this view. A silent break in any of them
## leaves a screen that looks finished and cannot build a deck.
extends Node

## Every user:// file this suite may create begins with this. Deleting by "t_" would
## delete the live save of every other suite running beside it.
const SANDBOX := "t_cardgrid_"

var _fails := 0

func _ready() -> void:
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()
	# Three copies of everything and a full purse, because the two things this suite
	# most needs are a card with a SPARE copy to drag and a card that can afford a
	# level. A starter save has neither, and the test would pass by never reaching the
	# code it is about.
	for cid in MetaState.CATALOG:
		for i in 3:
			MetaState.add_card(cid)
	MetaState.gold = 20000

	await _check_grid_builds()
	await _check_double_click_adds()
	await _check_drop_adds()
	await _check_deck_row_removes()
	await _check_drag_refused_when_spent()
	await _check_badge_opens_prices()
	await _check_toggle_rebuilds()
	await _check_ledger_is_read_only()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("CARD GRID TEST: PASS (grid builds, both add gestures work, the bay removes, the badge prices, the toggle rebuilds, a run is read-only)")
	else:
		print("CARD GRID TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)

## Build the Cards screen in the grid view and hand it back with a frame drawn.
func _screen(cards: bool = true) -> Control:
	SettingsState.card_view = cards
	var inst := (load("res://scenes/Collection.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	return inst

func _drop(inst: Control) -> void:
	inst.queue_free()
	await get_tree().process_frame

## Every card face in the grid, as the Buttons that carry the gestures.
##
## Found by the PROMISE in the tooltip, not by "a Button under a card holder": the
## level badge is also a Button under a card holder, so counting those made a grid of
## a hundred cards report a hundred and four.
func _faces(inst: Control) -> Array[Button]:
	var out: Array[Button] = []
	for c in _controls(inst):
		var b := c as Button
		if b == null or b.get_parent() == null or not b.get_parent().has_meta("card_id"):
			continue
		if b.tooltip_text.find("click to see the whole card") != -1:
			out.append(b)
	return out

func _face_for(inst: Control, id: String) -> Button:
	for b in _faces(inst):
		if String(b.get_parent().get_meta("card_id")) == id:
			return b
	return null

func _click(c: Control, double: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.double_click = double
	c.gui_input.emit(ev)

func _some_id() -> String:
	return String(MetaState.collection.keys()[0])

# --- the checks --------------------------------------------------------------

## The grid draws a face per owned card, and the deck bay is on screen beside it.
##
## The count is asserted against the collection rather than against a number, because
## the failure this catches is a filter or a clamp quietly dropping cards — a grid that
## draws thirty of a hundred looks perfectly healthy.
func _check_grid_builds() -> void:
	var inst := await _screen(true)
	var faces := _faces(inst)
	if faces.size() != MetaState.collection.size():
		_fail("grid drew %d faces for %d owned card types" % [
			faces.size(), MetaState.collection.size()])
	if inst.deck_bay == null or not inst.deck_bay.visible:
		_fail("the deck bay is not on screen in the grid view — there is nothing to drag onto")
	await _drop(inst)

## Double-clicking a face puts a copy in the deck, and a SINGLE click does not.
##
## Both halves matter. The single click opens the card, and a version of this that only
## checked the double would pass a screen where every glance at a card also silently
## added it to the deck.
func _check_double_click_adds() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	var b := _face_for(inst, id)
	if b == null:
		_fail("no face for %s in the grid" % id)
		await _drop(inst)
		return
	var before: int = int(inst.selection.get(id, 0))
	_click(b, false)
	await get_tree().process_frame
	if int(inst.selection.get(id, 0)) != before:
		_fail("a single click on %s changed the deck — it should only open the card" % id)
	_click(b, true)
	await get_tree().process_frame
	if int(inst.selection.get(id, 0)) != before + 1:
		_fail("double-clicking %s did not add a copy (%d -> %d)" % [
			id, before, int(inst.selection.get(id, 0))])
	await _drop(inst)

## A card dropped on the deck bay lands in the deck.
##
## Driven through the bay's own `_can_drop_data` / `_drop_data` with the payload the
## face would have produced, so what is tested is the real pair of hooks Godot calls
## and the real dictionary that travels between them — not a shortcut into `_adjust`.
func _check_drop_adds() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	var bay = inst.deck_bay
	var ctx = inst._ctx()
	var payload := CardGrid.drag_payload(id, ctx)
	if payload.is_empty():
		_fail("a card with spare copies refused to be picked up")
		await _drop(inst)
		return
	if not bay._can_drop_data(Vector2.ZERO, payload):
		_fail("the deck bay refused a card")
	if bay._can_drop_data(Vector2.ZERO, {"something_else": 1}):
		_fail("the deck bay accepted something that is not a card")
	var before: int = int(inst.selection.get(id, 0))
	bay._drop_data(Vector2.ZERO, payload)
	await get_tree().process_frame
	if int(inst.selection.get(id, 0)) != before + 1:
		_fail("dropping %s on the deck bay did not add a copy" % id)
	await _drop(inst)

## Clicking a card in the deck bay takes one copy back out — the only way out in this
## view, since the grid has no stepper.
func _check_deck_row_removes() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	inst.selection[id] = 2
	inst._refresh()
	await get_tree().process_frame
	# By NAME, not by the count. The starter deck this screen loads already holds two
	# of something else, so "the row that says 2x" found a different card and the check
	# passed a bay that never removed anything.
	var want: String = CardGrid.card_of(id).name
	var row: Button = null
	for c in _controls(inst.deck_bay):
		var b := c as Button
		if b != null and b.text == "2x  %s" % want:
			row = b
			break
	if row == null:
		_fail("no row in the deck bay for %s, which the deck holds two of" % want)
		await _drop(inst)
		return
	row.pressed.emit()
	await get_tree().process_frame
	if int(inst.selection.get(id, 0)) != 1:
		_fail("clicking the deck bay row left %d copies, expected 1" % int(inst.selection.get(id, 0)))
	await _drop(inst)

## A card whose every copy is already in the deck does not lift.
##
## The rule with no other enforcement point. `_adjust` clamps, so a drop of a spent
## card is harmless — and that is exactly why this has to be checked here: the harm is
## a gesture that visibly starts and then does nothing, which nothing downstream can
## see.
func _check_drag_refused_when_spent() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	inst.selection[id] = MetaState.owned(id)
	var ctx = inst._ctx()
	if not CardGrid.drag_payload(id, ctx).is_empty():
		_fail("a card with every copy already in the deck was allowed to be dragged")
	await _drop(inst)

## The badge on a levelable card opens the priced buttons, and the prices it opens are
## the table view's prices.
##
## The second half is the point. D133 refused to hide a fuse price behind a click, and
## the grid only gets to move the prices because it does not CHANGE them — so the panel
## is checked against `_price_of`, the same function the table row quotes.
func _check_badge_opens_prices() -> void:
	var inst := await _screen(true)
	var id := ""
	for cid in MetaState.collection:
		if MetaState.can_fuse(String(cid)):
			id = String(cid)
			break
	if id == "":
		_fail("no card in a stocked collection can be levelled — the badge can never appear")
		await _drop(inst)
		return
	var badge: Button = null
	var face := _face_for(inst, id)
	if face != null:
		for c in face.get_parent().get_children():
			var b := c as Button
			if b != null and b.text == "LV+":
				badge = b
				break
	if badge == null:
		_fail("no level badge on %s, which can be levelled" % id)
		await _drop(inst)
		return
	var want: Dictionary = inst._price_of(id, 1)
	if badge.tooltip_text.find("%d copies and %d gold" % [
			int(want["copies"]), int(want["gold"])]) == -1:
		_fail("the badge on %s does not quote the +1 price before it is pressed: %s" % [
			id, badge.tooltip_text])
	badge.pressed.emit()
	await get_tree().process_frame
	var priced := 0
	for c in _controls(inst):
		var b := c as Button
		if b != null and b.text.begins_with("+") and b.text.find("gold") != -1:
			priced += 1
	if priced == 0:
		_fail("pressing the level badge on %s opened no priced buttons" % id)
	await _drop(inst)

## Switching the view redraws the screen once, keeps the deck, and puts the other view
## up. Rebuilt-not-refreshed is what this is really guarding: `_build_ui` appends, so a
## toggle that forgot to tear down would draw a second whole screen over the first.
func _check_toggle_rebuilds() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	inst.selection[id] = 2
	var toggle: Button = null
	for c in _controls(inst):
		var b := c as Button
		if b != null and b.text.begins_with("View:"):
			toggle = b
			break
	if toggle == null:
		_fail("no view toggle on the Cards screen — the table view is unreachable")
		await _drop(inst)
		return
	toggle.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if SettingsState.card_view:
		_fail("the view toggle did not change the view")
	if int(inst.selection.get(id, 0)) != 2:
		_fail("switching views lost the deck being built")
	if inst.deck_bay != null and inst.deck_bay.visible:
		_fail("the deck bay is still on screen in the table view, where the stepper is the way in")
	var titles := 0
	for c in _controls(inst):
		if c is Label and (c as Label).text.begins_with("Cards — "):
			titles += 1
	if titles != 1:
		_fail("the screen has %d titles after one view switch — it was drawn over itself" % titles)
	await _drop(inst)
	SettingsState.card_view = true

## Mid-run the grid is a reading and not a place to change anything: no card lifts, and
## the bay takes no drops. The same rule the table view enforces by hiding its stepper.
func _check_ledger_is_read_only() -> void:
	GameState.select_dungeon(Balance.DUNGEONS[0])
	GameState.enter_dungeon(MetaState.build_deck(MetaState.decks.get("Starter", {})))
	var inst := await _screen(true)
	if inst.mode != inst.Mode.LEDGER:
		_fail("a live run did not put the Cards screen in its ledger mode")
	var ctx = inst._ctx()
	var id := _some_id()
	if not CardGrid.drag_payload(id, ctx).is_empty():
		_fail("a card could be dragged out of the collection during a run")
	if inst.deck_bay != null and inst.deck_bay._can_drop_data(Vector2.ZERO, {CardGrid.DRAG_KEY: id}):
		_fail("the deck bay accepted a card during a run, when the deck is already dealt")
	await _drop(inst)
	GameState.reset_run_progress()

func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control:
		out.append(n as Control)
	for child in n.get_children():
		out.append_array(_controls(child))
	return out

## Delete this suite's sandboxed files. Writes are disabled first: a surviving
## MetaState flushes when the engine frees it at exit and re-creates them.
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
