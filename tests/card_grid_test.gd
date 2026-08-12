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
	await _check_preview_offers_levelling()
	await _check_preview_adds_and_removes()
	await _check_badge_shows_when_it_cannot_be_paid()
	await _check_hover_survives_an_add()
	await _check_relics_stay_one_line()
	await _check_toggle_rebuilds()
	await _check_ledger_is_read_only()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("CARD GRID TEST: PASS (grid builds, both add gestures work, the bay removes, the badge prices and is always visible, the hover survives an add, the relics stay one line, the toggle rebuilds, a run is read-only)")
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

## Levelling is reachable from the card PREVIEW, at the table view's prices (D220b).
##
## It used to be reachable from the LV+ badge, which opened a panel of its own. The
## badge is a mark now — 40x14 is unusable with a thumb — so the claim moved with the
## control: the preview a card opens must carry the priced level buttons, and the price
## must still be readable before the click that spends, which is now the card's own
## hover.
##
## Checked against `_price_of`, the same function the table row quotes, because D133
## only allows the prices to MOVE on the understanding that they do not CHANGE. A
## hard-coded figure would pass a grid that priced levelling differently from the table
## beside it.
func _check_preview_offers_levelling() -> void:
	var inst := await _screen(true)
	var id := ""
	for cid in MetaState.collection:
		if MetaState.can_fuse(String(cid)):
			id = String(cid)
			break
	if id == "":
		_fail("no card in a stocked collection can be levelled — levelling can never appear")
		await _drop(inst)
		return
	var face := _face_for(inst, id)
	if face == null:
		_fail("no face for %s in the grid" % id)
		await _drop(inst)
		return
	var want: Dictionary = inst._price_of(id, 1)
	var priced := "%d copies and %d gold" % [int(want["copies"]), int(want["gold"])]
	# Before the click that spends: the card's own hover carries the +1 price now that
	# the badge carries nothing.
	if face.tooltip_text.find(priced) == -1:
		_fail("the face of %s does not quote the +1 price before anything is opened: '%s'" % [
			id, face.tooltip_text])
	# ...and the preview offers it as a button.
	UI.inspect_card(face, CardGrid.card_of(id), null, "", CardGrid.actions_for.bind(id, inst._ctx()))
	await get_tree().process_frame
	var level_btn: Button = null
	for c in _controls(UI._inspecting):
		var b := c as Button
		if b != null and b.text.begins_with("Level +"):
			level_btn = b
			break
	if level_btn == null:
		_fail("the preview of %s offers no level button" % id)
	elif level_btn.text.find("%d copies, %dg" % [int(want["copies"]), int(want["gold"])]) == -1:
		_fail("the preview prices a level as '%s', the table says %s" % [level_btn.text, priced])
	else:
		var before: int = int(MetaState.collection[id]["level"])
		level_btn.pressed.emit()
		await get_tree().process_frame
		if int(MetaState.collection[id]["level"]) <= before:
			_fail("pressing the preview's level button did not level %s" % id)
	if UI._inspecting != null and is_instance_valid(UI._inspecting):
		UI._inspecting.queue_free()
		UI._inspecting = null
	await _drop(inst)

## The preview is the whole control surface for a card: add, remove, and level, and the
## row re-reads itself after every press (D220b).
##
## The row rebuilding is the half worth guarding. Every button on it is a statement
## about what is still possible — "Add a copy" is refused once the deck holds them all —
## and a row captured when the overlay opened would go stale on its own first press.
## That matters most on a phone, where this row is the ONLY way in: drag and double-click
## are gestures a finger cannot do.
func _check_preview_adds_and_removes() -> void:
	var inst := await _screen(true)
	var id := _some_id()
	inst.selection.erase(id)
	inst._refresh()
	await get_tree().process_frame
	var face := _face_for(inst, id)
	UI.inspect_card(face, CardGrid.card_of(id), null, inst._card_note.bind(id),
		CardGrid.actions_for.bind(id, inst._ctx()))
	await get_tree().process_frame

	var add := _preview_button("Add a copy")
	var drop := _preview_button("Take one out")
	if add == null or drop == null:
		_fail("the preview offers add=%s remove=%s — a phone has no other way in" % [add, drop])
	else:
		if not drop.disabled:
			_fail("'Take one out' is pressable with no copies in the deck")
		add.pressed.emit()
		await get_tree().process_frame
		if int(inst.selection.get(id, 0)) != 1:
			_fail("the preview's add button did not put a copy in the deck")
		# the row must have re-read itself: removal is possible now, and it was not
		var drop2 := _preview_button("Take one out")
		if drop2 == null or drop2.disabled:
			_fail("after adding a copy the preview still refuses to take one out — the row is stale")
		# ...and add must refuse once every copy is committed
		var owned: int = MetaState.owned(id)
		for i in owned:
			var a := _preview_button("Add a copy")
			if a != null and not a.disabled:
				a.pressed.emit()
				await get_tree().process_frame
		var spent := _preview_button("Add a copy")
		if spent == null or not spent.disabled:
			_fail("the preview still offers a copy of %s with all %d already in the deck" % [id, owned])
	if UI._inspecting != null and is_instance_valid(UI._inspecting):
		UI._inspecting.queue_free()
		UI._inspecting = null
	await _drop(inst)

## A button in the open preview, by the text the player reads.
func _preview_button(text: String) -> Button:
	if UI._inspecting == null or not is_instance_valid(UI._inspecting):
		return null
	for c in _controls(UI._inspecting):
		var b := c as Button
		if b != null and b.text == text:
			return b
	return null

## A card that CANNOT be levelled today still shows the badge, greyed, with the reason
## on it (D215).
##
## The badge is the only levelling control in this view, and it used to appear only on
## cards whose price was already met — so a player holding one copy of everything saw a
## grid with no levelling anywhere and no reason to believe the game had any. Reported
## as "it is not clear how to evolve a card". The card is starved here rather than found
## in that state, because a stocked collection is exactly the one where every card can
## be levelled and the bug is invisible.
func _check_badge_shows_when_it_cannot_be_paid() -> void:
	var id := _some_id()
	var gold := MetaState.gold
	var had: int = MetaState.collection[id]["count"]
	MetaState.gold = 0
	var inst := await _screen(true)
	var badge := _badge_for(inst, id)
	var face := _face_for(inst, id)
	if badge == null:
		_fail("no level badge on %s once it cannot be afforded — the mechanic is invisible" % id)
	elif badge.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		# A mark that answers to a press is a 40x14 target again, and on a phone a tap
		# that lands on it must reach the card face underneath (D220b).
		_fail("the level mark on %s is still swallowing input" % id)
	# The reason moved off the mark and onto the card, which is where a mouse looks and
	# where the tap now goes. Asserted on the FACE, or this check would go vacuous the
	# moment the mark stopped carrying a tooltip.
	var why: String = MetaState.fuse_blocked_reason(id)
	if face == null:
		_fail("no face for %s to carry the blocked reason" % id)
	else:
		if why != "" and face.tooltip_text.find(why) == -1:
			_fail("the face of blocked %s does not say why: '%s'" % [id, face.tooltip_text])
		if face.tooltip_text.find("LV+") == -1:
			_fail("the face of blocked %s does not say what the level would buy" % id)
		var blocked_btn := ""
		UI.inspect_card(face, CardGrid.card_of(id), null, "",
			CardGrid.actions_for.bind(id, inst._ctx()))
		await get_tree().process_frame
		for c in _controls(UI._inspecting):
			var b := c as Button
			if b != null and b.text.begins_with("Level up"):
				blocked_btn = b.text
				if not b.disabled:
					_fail("the preview offers a level of %s it cannot sell" % id)
		if blocked_btn == "":
			_fail("the preview of blocked %s says nothing about levelling at all" % id)
		elif why != "" and blocked_btn.find(why) == -1:
			_fail("the preview's blocked level button does not say why: '%s'" % blocked_btn)
		if UI._inspecting != null and is_instance_valid(UI._inspecting):
			UI._inspecting.queue_free()
			UI._inspecting = null
	await _drop(inst)
	MetaState.gold = gold
	MetaState.collection[id]["count"] = had

## The card under the cursor is still enlarged after a copy goes into the deck (D215).
##
## Adding rebuilds the grid, and Godot only works out what the mouse is over when the
## mouse MOVES — so the card just double-clicked came back at rest with the cursor still
## on it, and stayed flat until the player moved or clicked again. They reported it as
## the enlarge getting stuck.
##
## Driven through real motion events rather than by calling the hover handler, because
## the fix is precisely that the ENGINE's idea of what is hovered is put right: setting
## the scale by hand passes a test like this and leaves a card that never shrinks.
func _check_hover_survives_an_add() -> void:
	# Its own SubViewport, with input handled locally: the pointer has to be somewhere
	# definite for any of this to mean anything, and pushing motion at the headless
	# window's viewport does not reach the screen's controls.
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.handle_input_locally = true
	get_tree().root.add_child(vp)
	SettingsState.card_view = true
	var inst := (load("res://scenes/Collection.tscn") as PackedScene).instantiate() as Control
	vp.add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	# A face the pointer can actually reach: the grid is a hundred cards inside a scroll,
	# and one that is off the bottom of the frame is clipped — the hit test still says
	# the cursor is inside its rect, and the engine quite rightly disagrees.
	var face := _visible_face(inst, Rect2(Vector2.ZERO, Vector2(vp.size)))
	if face == null:
		_fail("no card face inside the frame to hover")
		vp.queue_free()
		await get_tree().process_frame
		return
	var id := String(face.get_parent().get_meta("card_id"))
	var at: Vector2 = face.get_global_rect().get_center()
	_motion(vp, at)
	await get_tree().process_frame
	var grown: float = (face.get_parent() as Control).scale.x
	if grown <= 1.0:
		_fail("hovering a card face does not enlarge it — this suite cannot see the bug it is for")
		vp.queue_free()
		await get_tree().process_frame
		return

	_click(face, true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var back := _face_for(inst, id)
	if back == null:
		_fail("the card left the grid when a copy went into the deck")
		vp.queue_free()
		await get_tree().process_frame
		return
	if back == face:
		_fail("the grid was not rebuilt, so this check is no longer testing anything")
	if not is_equal_approx((back.get_parent() as Control).scale.x, grown):
		_fail("the card under the cursor came back flat after an add (scale %.2f, want %.2f)" % [
			(back.get_parent() as Control).scale.x, grown])

	# ...and it must still let go. A card enlarged without the engine agreeing it is
	# hovered never gets its `mouse_exited`, and stays big for the rest of the session.
	var other: Button = null
	for f in _faces(inst):
		if f != back:
			other = f
			break
	if other != null:
		_motion(vp, other.get_global_rect().get_center())
		await get_tree().process_frame
		if (back.get_parent() as Control).scale.x > 1.0:
			_fail("the card stayed enlarged after the cursor jumped to another one")
	vp.queue_free()
	await get_tree().process_frame

## The relics line is one clipped line with the detail on its hover (D215).
##
## It used to print every relic's full description inline and wrap, which is four rows
## of text on the screen with the least height in the game and was reported as the
## relics taking too much space. Checked with a large handful owned, because two relics
## wrap to one line and the bug does not exist yet.
func _check_relics_stay_one_line() -> void:
	var had: Array = GameState.run_relics.duplicate()
	for rid in MetaState.RELIC_CATALOG:
		# The RUN's relics, not the collection's (D238). The Cards screen reports what the run in
		# progress is carrying, because that is the part that changes what the rest of the deck is
		# worth — and nothing is carried in the collection any more.
		if GameState.run_relics.size() >= 10:
			break
		if not GameState.run_relics.has(rid):
			GameState.run_relics.append(rid)
	var inst := await _screen(true)
	var line: Label = null
	for c in _controls(inst):
		var l := c as Label
		if l != null and l.text.find("Relics (") != -1:
			line = l
			break
	if line == null:
		_fail("the Cards screen no longer says which relics are carried")
	else:
		if not line.clip_text or line.autowrap_mode != TextServer.AUTOWRAP_OFF:
			_fail("the relics line wraps again — it is a header, not a paragraph")
		if line.get_line_count() > 1:
			_fail("the relics line is %d lines tall" % line.get_line_count())
		var first := load(MetaState.RELIC_CATALOG[GameState.run_relics[0]]) as RelicData
		if first != null:
			if line.text.find(first.description) != -1:
				_fail("a relic's description is inline on the header again")
			if line.tooltip_text.find(first.description) == -1:
				_fail("the relics line does not explain itself on hover: '%s'" % line.tooltip_text)
	await _drop(inst)
	GameState.run_relics = had

## The first card face wholly inside `frame`, so a gesture aimed at it lands.
func _visible_face(inst: Control, frame: Rect2) -> Button:
	for b in _faces(inst):
		if frame.encloses(b.get_global_rect()):
			return b
	return null

## The LV+ MARK on a given card, or null.
##
## A Label since D220b, not a Button: at 40x14 it was the smallest target on the screen
## and unusable with a thumb, so it stopped answering to anything and taps now fall
## through it to the card face. Looked up by text rather than by class, because what
## this suite is about is whether the player can SEE that the card can be levelled.
func _badge_for(inst: Control, id: String) -> Label:
	var face := _face_for(inst, id)
	if face == null:
		return null
	for c in face.get_parent().get_children():
		var l := c as Label
		if l != null and l.text == "LV+":
			return l
	return null

## Move the real pointer, so the engine updates what it thinks is hovered.
func _motion(vp: Viewport, to: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = to
	m.global_position = to
	vp.push_input(m)

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
	# The deck panel is beside BOTH views now (D215), narrower in the table one — where
	# the row is measured to the pixel and 180 is what there is room for.
	if inst.deck_bay == null or not inst.deck_bay.visible:
		_fail("the deck panel is missing from the table view")
	elif inst.deck_bay.size.x > UITheme.px(CardGrid.PANEL_W_TABLE) + 1.0:
		_fail("the deck panel is %.0fpx in the table view, where the row leaves room for %.0f" % [
			inst.deck_bay.size.x, UITheme.px(CardGrid.PANEL_W_TABLE)])
	else:
		# ...and the row beside it still fits. This is the assertion that catches a panel
		# widened later: the overflow is silent, and the price is a clipped fuse price.
		var widest := 0.0
		for c in _controls(inst):
			var h := c as HBoxContainer
			if h == null or h.get_child_count() < 4:
				continue
			if h.get_combined_minimum_size().x > h.size.x + 1.0 and h.size.x > widest:
				widest = h.size.x
				_fail("a table row wants %.0fpx and has %.0f beside the deck panel" % [
					h.get_combined_minimum_size().x, h.size.x])
				break
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
