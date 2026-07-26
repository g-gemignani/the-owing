## Title screen. Owns the decision of which save slot is being played, so no other
## screen has to think about slots.
extends Control

func _ready() -> void:
	var col := UI.screen(self, "DECKCRAWL")
	UI.label(col, "A deckbuilding descent. Placeholder art, real systems.")
	UI.spacer(col)

	var latest := _latest_slot()
	if latest >= 0:
		var s := MetaState.slot_summary(latest)
		var run_note: String = "  · run in progress" if bool(s.get("in_run", false)) else ""
		UI.button(col, "Continue  —  slot %d (%d clears, %d gold)%s" % [
			latest + 1, s.get("clears", 0), s.get("gold", 0), run_note],
			func(): _play(latest))
	else:
		UI.button(col, "Continue  —  no save found")

	UI.button(col, "New Game", func(): UI.goto(self, "res://scenes/SaveSlots.tscn"))
	UI.button(col, "Load Game", func(): UI.goto(self, "res://scenes/SaveSlots.tscn"))
	UI.button(col, "Settings", func(): UI.goto(self, "res://scenes/Settings.tscn"))
	UI.spacer(col)
	UI.button(col, "Quit", func(): get_tree().quit())

	var v := UI.label(col, "Cards %d   Relics %d   Dungeons %d   Zones %d" % [
		MetaState.CATALOG.size(), MetaState.RELIC_CATALOG.size(),
		Balance.DUNGEONS.size(), Balance.ZONES.size()])
	v.modulate = Color(1, 1, 1, 0.6)

## Most recently written slot, or -1.
func _latest_slot() -> int:
	var best := -1
	var best_time := -1
	for i in MetaState.SLOT_COUNT:
		var p := MetaState.path_for(i)
		if not FileAccess.file_exists(p):
			continue
		var t := int(FileAccess.get_modified_time(p))
		if t > best_time:
			best_time = t
			best = i
	return best

func _play(s: int) -> void:
	MetaState.slot = s
	if not MetaState.load_game():
		MetaState.new_save()
	GameState.reset_run_progress()
	# resume a dungeon in progress, including a fight mid-turn
	if MetaState.has_saved_run() and GameState.run_from_dict(MetaState.saved_run):
		if not GameState.combat_state.is_empty():
			UI.goto(self, "res://scenes/Combat.tscn")
		else:
			UI.goto(self, GameState.run_scene())
		return
	UI.goto(self, "res://scenes/Overworld.tscn")
