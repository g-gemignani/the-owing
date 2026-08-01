## In-run menu.
##
## There is deliberately no free "abandon" here. Leaving a dungeon with what you
## found requires an Escape Rope, which is found and never sold — so retreat is a
## resource decision rather than a menu click. Without one, the only ways out are
## the boss or death.
##
## Quitting to the title keeps the run: it is serialized into the save and resumed
## from Continue, including a fight in progress. That is what makes the rope
## meaningful — quitting is not an escape from a bad situation, only a pause.
extends Control

enum Confirm { NONE, ROPE, QUIT }
var confirming: int = Confirm.NONE

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var col := UI.screen(self, "Paused")
	var dd := GameState.dungeon_data()
	UI.label(col, "%s    HP %d/%d    %d gold banked" % [
		dd.name if dd != null else "No dungeon", GameState.hp, GameState.max_hp, MetaState.gold])
	var ropes := MetaState.item_count("escape_rope")
	if GameState.in_run():
		UI.label(col, "At risk in this run: %s — secured by beating the boss, or by using an Escape Rope." % [
			GameState.risk_line().trim_prefix("AT RISK: ")])
	UI.label(col, "Escape Ropes held: %d" % ropes)
	UI.spacer(col)

	match confirming:
		Confirm.ROPE:
			# the rope is the only thing that carries a sealed pack out of a run you
			# are not going to finish, so it has to be named in the choice
			UI.label(col, "Use an Escape Rope? You keep everything found here (%s), but the dungeon stays uncleared — no relic, no unlock." % [
				GameState.risk_line().trim_prefix("AT RISK: ")])
			var r := UI.row(col, 8)
			UI.button(r, "Use the rope", func(): _use_rope(), 38.0)
			UI.exit_button(r, "Keep going", func(): _cancel(), 38.0)
			return
		Confirm.QUIT:
			var warn := "Quit to the title?"
			if GameState.has_run():
				warn += " Your run is saved — Continue picks it up exactly where you left off, mid-fight included."
			UI.label(col, warn)
			var q := UI.row(col, 8)
			UI.button(q, "Quit to title", func(): _quit(), 38.0)
			UI.exit_button(q, "Stay", func(): _cancel(), 38.0)
			return

	if GameState.in_run():
		# back into the fight if one is in progress — pausing mid-combat must not
		# drop the player onto the map with the encounter half-fought
		UI.exit_button(col, "Resume", func(): UI.goto(self, GameState.resume_scene()))
	else:
		UI.exit_button(col, "Back to the world", func(): UI.goto(self, "res://scenes/Overworld.tscn"))
	UI.button(col, "Collection", func(): UI.goto(self, "res://scenes/Collection.tscn"))
	UI.button(col, "Settings", func(): UI.goto(self, "res://scenes/Settings.tscn"))

	if GameState.in_run():
		if ropes > 0:
			UI.button(col, "Use Escape Rope and leave  (%d held)" % ropes, func():
				confirming = Confirm.ROPE
				_build())
		else:
			UI.button(col, "No Escape Rope — the way out is the boss, or death")
	UI.spacer(col)
	UI.button(col, "Save and quit to title", func():
		confirming = Confirm.QUIT
		_build())

func _cancel() -> void:
	confirming = Confirm.NONE
	_build()

## The rope is the paid-for exit: earnings are kept, the dungeon is NOT cleared,
## so no relic, no unlock and no permanent max-HP.
func _use_rope() -> void:
	if not MetaState.use_item("escape_rope"):
		_cancel()
		return
	Audio.play("leave")
	var kept := GameState.commit_escrow()
	GameState.last_haul = "Escaped with %d cards and %d gold. The dungeon remains." % [
		kept["cards"], kept["gold"]]
	GameState.clear_run()
	GameState.reset_run_progress()
	MetaState.save_game()   # explicit full write
	UI.goto(self, "res://scenes/Overworld.tscn")

func _quit() -> void:
	# the run rides along inside the save, so nothing is discarded here
	MetaState.save_game()
	UI.goto(self, "res://scenes/MainMenu.tscn")
