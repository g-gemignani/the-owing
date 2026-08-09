## Runtime test: the search box on the card filter bar (D214).
##
## What the search DOES is `CardFilter.match_score`, and that is a pure function with
## its own checks in `test_filter.gd`. What cannot be asked of a script is whether the
## box survives being typed into. Every other control on that bar rebuilds the bar to
## redraw itself, and a rebuild frees the `LineEdit` — so the first letter would drop
## the focus and the caret, and the second letter would go somewhere else entirely.
## That is a property of a built tree, and it is invisible in any headless assertion
## about the list contents: the list filters correctly either way.
##
## The frame check is here for the same reason it is in `DeckFlowTest`: the bar this
## control was added to is the one the screen's height and width budget is measured
## against (D133), and a new control on it is exactly how that budget goes.
extends Node

## Every user:// file this suite may create begins with this. Deleting by "t_" would
## delete the live save of every other suite running beside it.
const SANDBOX := "t_cardsearch_"

## What `UI.screen`'s margins leave inside a 1280 frame — the width the bar has.
const FRAME := 1248.0

var _fails := 0

func _ready() -> void:
	await get_tree().process_frame
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()
	for cid in MetaState.CATALOG:
		MetaState.add_card(cid)
	CardFilter.state = CardFilter.default_state()

	await _check_typing_filters()
	await _check_the_box_survives_typing()
	await _check_empty_says_so()
	await _check_the_bar_still_fits()

	MetaState.writes_disabled = true
	CardFilter.state = CardFilter.default_state()
	_purge()
	if _fails == 0:
		print("CARD SEARCH TEST: PASS (typing filters, the box keeps focus, an empty result explains itself, the bar fits)")
	else:
		print("CARD SEARCH TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)

## The Cards screen, in the TABLE view: one row per card, so "how many are listed" is a
## child count rather than a walk through a grid of faces.
func _screen() -> Control:
	SettingsState.card_view = false
	var inst := (load("res://scenes/Collection.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	return inst

func _drop(inst: Control) -> void:
	CardFilter.state = CardFilter.default_state()
	inst.queue_free()
	await get_tree().process_frame

## The search box itself, found by its placeholder rather than by position — the bar is
## rebuilt from a builder whose order is a design decision and may change.
func _box(inst: Control) -> LineEdit:
	for c in _controls(inst):
		var le := c as LineEdit
		if le != null and le.placeholder_text == "search":
			return le
	return null

## Type into the box the way the player does: the signal the control emits, so the
## screen's own handler runs. Setting `.text` alone emits nothing and would test the
## assignment rather than the wiring.
func _type(box: LineEdit, text: String) -> void:
	box.text = text
	box.text_changed.emit(text)
	await get_tree().process_frame

func _rows(inst: Control) -> int:
	return (inst.list_box as Node).get_child_count()

# --- the checks --------------------------------------------------------------

## Typing narrows the list, and clearing puts it back. Asserted against the whole
## collection rather than a number, because the failure worth catching is a search that
## filters nothing (every card still listed) or everything (a screen gone blank).
func _check_typing_filters() -> void:
	var inst := await _screen()
	var box := _box(inst)
	if box == null:
		_fail("no search box on the filter bar")
		await _drop(inst)
		return
	var all := _rows(inst)
	if all != MetaState.collection.size():
		_fail("the unfiltered list shows %d of %d cards" % [all, MetaState.collection.size()])

	await _type(box, "blbl")
	var some := _rows(inst)
	if some >= all:
		_fail("a half-remembered name narrowed nothing: %d rows of %d" % [some, all])
	if some == 0:
		_fail("'blbl' matched nothing at all — Blight Bloom is in the catalogue")

	await _type(box, "")
	if _rows(inst) != all:
		_fail("clearing the box left %d rows of %d" % [_rows(inst), all])
	await _drop(inst)

## The box is the SAME control after a keystroke, and it still has the focus.
##
## This is the whole reason `_refresh_list` exists. Instance identity is checked as well
## as focus because a rebuild that happened to re-focus the new box would still lose the
## caret position and anything selected in it.
func _check_the_box_survives_typing() -> void:
	var inst := await _screen()
	var box := _box(inst)
	if box == null:
		_fail("no search box to type into")
		await _drop(inst)
		return
	box.grab_focus()
	var id := box.get_instance_id()
	await _type(box, "bl")
	var after := _box(inst)
	if after == null:
		_fail("the search box is gone after one keystroke")
		await _drop(inst)
		return
	if after.get_instance_id() != id:
		_fail("the search box was rebuilt under the player mid-word")
	if after.text != "bl":
		_fail("the search box lost what was typed into it: '%s'" % after.text)
	if not after.has_focus():
		_fail("the search box lost the focus after one keystroke")
	await _drop(inst)

## An empty result explains itself instead of being an empty box. Both ways of
## emptying the list are checked, because the note has to answer whichever one the
## player used to get there.
func _check_empty_says_so() -> void:
	var inst := await _screen()
	var box := _box(inst)
	if box == null:
		_fail("no search box")
		await _drop(inst)
		return
	await _type(box, "qqzzxx")
	if _rows(inst) == 0:
		_fail("an empty result says nothing at all")
	var said := ""
	for c in inst.list_box.get_children():
		var l := c as Label
		if l != null:
			said = l.text
	if said.find("qqzzxx") == -1:
		_fail("the empty note does not quote what was searched for: '%s'" % said)

	# the same box, reached by a filter rather than by the search
	await _type(box, "")
	CardFilter.state["rarity"] = CardData.Rarity.LEGENDARY
	CardFilter.state["type"] = CardData.Type.SKILL
	inst._refresh()
	await get_tree().process_frame
	var listed := 0
	for id in CardFilter.apply(MetaState.collection, MetaState.CATALOG):
		listed += 1
	if listed == 0 and _rows(inst) == 0:
		_fail("a filter that matches nothing leaves a blank list with no note")
	await _drop(inst)

## The bar has room for one more control. Measured, not eyeballed: this is the row that
## D133 cut to the bone, and the search box was added to it rather than to a new line.
func _check_the_bar_still_fits() -> void:
	var inst := await _screen()
	var box := _box(inst)
	if box == null:
		_fail("no search box")
		await _drop(inst)
		return
	var bar := box.get_parent() as Control
	var want: float = bar.get_combined_minimum_size().x
	if want > FRAME:
		_fail("the filter bar asks for %.0fpx of a %.0fpx frame with the search box on it" % [
			want, FRAME])
	await _drop(inst)

func _controls(n: Node, out: Array[Control] = []) -> Array[Control]:
	var c := n as Control
	if c != null:
		out.append(c)
	for k in n.get_children():
		_controls(k, out)
	return out

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
