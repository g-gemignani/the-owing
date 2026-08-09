## Runtime test: the saved-deck controls on the collection screen (D212).
##
## The rules underneath — the cap, the rename, the clamp — are `test_deck.gd`'s, and
## they are unit-testable. What is not is the WIRING: which deck the rename and delete
## buttons are aimed at, whether the name field follows a load, whether the picker
## still points at the deck after it has been renamed, and whether the row those
## controls sit on still fits the frame with the cap full. Every one of those is a
## property of a built tree, so this is a SCENE test — a `--script` run has no
## autoloads to build the screen with.
##
## The layout half is here because the cap and the picker were BOTH chosen off a
## measurement (a chip per deck asked for 1705px inside a 1248px frame), and a
## measurement that lives only in a design note is one nothing re-takes.
## Run: godot --headless res://tests/DeckFlowTest.tscn
extends Node

## Every user:// file this suite may create begins with this. The teardown deletes by
## it rather than by "t_", which would delete the live save of every other suite
## running at the same time.
const SANDBOX := "t_deckflow_"

## What `UI.screen` leaves inside a 1280 frame once its margins are taken — the width
## anything on that screen actually has. Stated once, used by both bar checks.
const FRAME := 1248.0

var _fails := 0

func _ready() -> void:
	# One frame first: the root is still adding THIS node during `_ready`, and adding a
	# viewport to a parent that is mid-setup is refused outright.
	await get_tree().process_frame
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()
	for id in MetaState.CATALOG.keys().slice(0, 20):
		MetaState.add_card(id)

	await _flow()
	await _fits()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("DECK FLOW TEST: PASS (load, rename, delete, save, cap, and the bar still fits)")
	else:
		print("DECK FLOW TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## A screen of its own, built in a 1280x720 viewport so a layout check measures the
## frame the game ships rather than whatever the headless window happens to be.
func _screen() -> Control:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	get_tree().root.add_child(vp)
	var scr := (load("res://scenes/Collection.tscn") as PackedScene).instantiate() as Control
	vp.add_child(scr)
	return scr

func _flow() -> void:
	MetaState.decks = {"Starter": {"hack": 4, "cover": 4}, "Second": {"hack": 3}}
	var scr := _screen()
	await get_tree().process_frame

	# boots on Starter, with the name field and the picker both saying so
	_eq(scr.loaded_deck, "Starter", "boots on Starter")
	_eq(scr.name_edit.text, "Starter", "boot fills the name field")
	_eq(scr.deck_names[scr.deck_pick.selected], "Starter", "boot points the picker")

	# picking a deck loads it, and takes the rename/delete target with it
	scr._on_deck_picked(scr.deck_names.find("Second"))
	_eq(scr.loaded_deck, "Second", "picking loads")
	_eq(scr.name_edit.text, "Second", "picking refills the name field")
	_eq(str(scr.selection.get("hack", 0)), "3", "picking replaces the selection")

	# item 0 is the prompt, not a deck: it must not unload anything
	scr._on_deck_picked(0)
	_eq(scr.loaded_deck, "Second", "the prompt is not a choice")
	_eq(scr.deck_names[scr.deck_pick.selected], "Second", "the prompt puts the picker back")

	# rename keeps the deck's place in the list, and the picker follows it
	scr.name_edit.text = "Second Wind"
	scr._on_rename()
	_eq(scr.loaded_deck, "Second Wind", "rename moves the target")
	_eq(str(MetaState.decks.keys()), '["Starter", "Second Wind"]', "rename keeps the order")
	_eq(scr.deck_names[scr.deck_pick.selected], "Second Wind", "picker follows the rename")

	# a name another deck holds is refused, and that other deck is untouched
	scr.name_edit.text = "Starter"
	scr._on_rename()
	_eq(str(MetaState.decks.keys()), '["Starter", "Second Wind"]', "rename onto a taken name")

	# delete is undone by saving under the same name, which is why it does not confirm
	scr.name_edit.text = "Second Wind"
	scr._on_delete_deck()
	_eq(str(MetaState.decks.has("Second Wind")), "false", "delete removes it")
	_eq(scr.loaded_deck, "", "delete clears the target")
	_eq(str(scr.rename_btn.disabled), "true", "rename is dead with nothing loaded")
	_eq(str(scr.delete_btn.disabled), "true", "delete is dead with nothing loaded")
	scr._on_save()
	_eq(str(MetaState.decks.get("Second Wind", {})), '{ "hack": 3 }', "save puts it back")
	_eq(scr.loaded_deck, "Second Wind", "save aims the buttons at what it saved")

	# at the cap a new name is refused and an existing one is not
	while MetaState.decks.size() < Balance.MAX_DECKS:
		MetaState.save_deck("filler%d" % MetaState.decks.size(), {"hack": 2})
	scr.name_edit.text = "one too many"
	scr._on_save()
	_eq(str(MetaState.decks.size()), str(Balance.MAX_DECKS), "the cap holds")
	_eq(str(MetaState.decks.has("one too many")), "false", "nothing stored past the cap")
	scr.name_edit.text = "Starter"
	scr._on_save()
	_eq(scr.msg_label.text, "saved 'Starter'", "overwriting still works at the cap")

	scr.get_parent().queue_free()

## The kit bar and the save bar, at the cap, with every name as long as a name may be.
##
## The deck half of the kit row is measured APART from the power picker, because the
## two are independent and only one of them is this feature's. Ten owned powers ask
## for 1426px on their own and blow the row regardless of what decks do — a real
## defect, and not one a deck cap can fix or should be blamed for.
func _fits() -> void:
	MetaState.decks = {}
	for i in Balance.MAX_DECKS:
		MetaState.decks["W".repeat(Balance.MAX_DECK_NAME - 1) + str(i)] = {"hack": 4, "cover": 4}
	MetaState.powers = {"bulwark": 1, "foresight": 1}
	MetaState.equipped_power = "bulwark"
	var scr := _screen()
	await get_tree().process_frame
	await get_tree().process_frame

	var kit := scr.deck_pick.get_parent() as Control
	var powers: float = (scr.power_box as Control).get_combined_minimum_size().x
	var deck_side: float = kit.get_combined_minimum_size().x - powers
	if deck_side > FRAME:
		_fails += 1
		print("FAIL the saved-deck controls ask for %.0fpx of a %.0fpx frame at the cap of %d" % [
			deck_side, FRAME, Balance.MAX_DECKS])
	# The picker's whole job is a width that does not grow with the list. One deck and
	# the cap must measure the same, or the cap is back to being a layout promise.
	var full: float = (scr.deck_pick as Control).size.x
	MetaState.decks = {"one": {"hack": 4, "cover": 4}}
	scr._refresh()
	await get_tree().process_frame
	if absf((scr.deck_pick as Control).size.x - full) > 1.0:
		_fails += 1
		print("FAIL the deck picker is %.0fpx with one deck and %.0fpx at the cap" % [
			(scr.deck_pick as Control).size.x, full])

	# the bar that commits — leave, start/builds, name, save, rename, delete
	var bar := scr.name_edit.get_parent() as Control
	var want: float = bar.get_combined_minimum_size().x
	if want > FRAME:
		_fails += 1
		print("FAIL the save bar asks for %.0fpx of a %.0fpx frame" % [want, FRAME])

	scr.get_parent().queue_free()

func _eq(got: String, want: String, what: String) -> void:
	if got != want:
		_fails += 1
		print("FAIL %s: got '%s', want '%s'" % [what, got, want])

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
