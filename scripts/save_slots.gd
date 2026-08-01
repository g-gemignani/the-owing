## Slot picker used for both New Game and Load Game. One screen rather than two,
## because the only difference is whether an occupied slot is overwritten — and
## that needs a confirmation either way.
extends Control

var list: VBoxContainer
var msg: Label
var pending_new: int = -1

func _ready() -> void:
	var col := UI.screen(self, "Save Slots", "", "ledger")
	msg = UI.label(col, "Pick a slot to load, or start a new game in it.")
	list = UI.scroll(col)
	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/MainMenu.tscn"))
	_refresh()

func _refresh() -> void:
	for c in list.get_children():
		c.queue_free()
	for i in MetaState.SLOT_COUNT:
		var s := MetaState.slot_summary(i)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.sep(4))
		list.add_child(box)

		if not bool(s.get("exists", false)):
			UI.label(box, "Slot %d — empty" % (i + 1))
			UI.button(box, "  Start new game here", func(): _new_game(i), 36.0)
		elif bool(s.get("corrupt", false)):
			UI.label(box, "Slot %d — unreadable save" % (i + 1))
			UI.button(box, "  Delete", func(): _delete(i), 36.0)
			UI.button(box, "  Start new game here (overwrites)", func(): _confirm_new(i), 36.0)
		else:
			UI.label(box, "Slot %d — %d clears, %d gold, %d relics, %d card types (%d copies)%s" % [
				i + 1, s.get("clears", 0), s.get("gold", 0), s.get("relics", 0),
				s.get("types", 0), s.get("copies", 0),
				"   [run in progress]" if bool(s.get("in_run", false)) else ""])
			var r := UI.row(box, 8)
			UI.button(r, "Load", func(): _load(i), 36.0)
			UI.button(r, "Overwrite with new game", func(): _confirm_new(i), 36.0)
			UI.button(r, "Delete", func(): _confirm_delete(i), 36.0)

		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(8))
		box.add_child(gap)

	if pending_new >= 0:
		UI.label(list, "Overwrite slot %d? This cannot be undone." % (pending_new + 1))
		var r2 := UI.row(list, 8)
		UI.button(r2, "Yes, overwrite", func(): _new_game(pending_new), 36.0)
		UI.button(r2, "Cancel", func():
			pending_new = -1
			_refresh(), 36.0)

func _confirm_new(i: int) -> void:
	pending_new = i
	_refresh()

func _confirm_delete(i: int) -> void:
	# deletion is destructive but recoverable only by replaying, so ask once
	msg.text = "Deleting slot %d..." % (i + 1)
	_delete(i)

func _delete(i: int) -> void:
	MetaState.delete_slot(i)
	msg.text = "Slot %d deleted." % (i + 1)
	pending_new = -1
	_refresh()

func _new_game(i: int) -> void:
	# the kit screen performs the actual new_save, so the choice is part of starting
	GameState.pending_new_slot = i
	UI.goto(self, "res://scenes/StarterKit.tscn")

func _load(i: int) -> void:
	MetaState.slot = i
	if not MetaState.load_game():
		msg.text = "Slot %d could not be loaded." % (i + 1)
		return
	GameState.reset_run_progress()
	if MetaState.has_saved_run() and GameState.run_from_dict(MetaState.saved_run):
		UI.goto(self, GameState.resume_scene())
		return
	UI.goto(self, "res://scenes/Overworld.tscn")
