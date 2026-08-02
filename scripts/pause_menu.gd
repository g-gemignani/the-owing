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
	# The one screen in the D123 pass that asked for no new painting. Pause is only
	# reachable inside a run, so there is always a zone, and all five zone shots are
	# installed — art already on disk that this screen was not reading, which is the
	# D115 defect rather than a missing-file one. It is also the right picture: you
	# stopped where you are, and where you are is that zone. D96's objection to a zone
	# shot was that the Overworld already draws the same one as a thumbnail in the list
	# under it; nothing on this screen draws a zone. `UI.screen()` falls back to the
	# procedural pattern if there is no zone, so quitting to here without a run is safe.
	var z := Balance.zone_of(GameState.dungeon_id)
	var col := UI.screen(self, "Paused", "", "", false, z.id if z != null else "")
	var dd := GameState.dungeon_data()
	UI.label(col, "%s    HP %d/%d    %d gold banked" % [
		dd.name if dd != null else "No dungeon", GameState.hp, GameState.max_hp, MetaState.gold])
	var ropes := MetaState.item_count("escape_rope")
	# The parts, joined into this screen's own sentences, rather than `risk_line()` with
	# its prefix trimmed back off. A reader that undoes its writer's formatting is wrong
	# the moment the writer rewords, and silently: `trim_prefix` on a string that no
	# longer starts that way returns it whole (D116). Both sentences want the same list.
	var risked := ", ".join(GameState.risk_parts())
	if GameState.in_run():
		UI.label(col, "At risk in this run: %s — secured by beating the boss, or by using an Escape Rope." % [risked])
	# Keys belong on the "held" line and not in the sentence above, which promises the
	# boss or a rope will secure everything it names. A key is secured by neither — it is
	# spent on this floor or wasted when the run ends — and it rode the tail of that
	# sentence until D116. It still has to be stated, or a player pauses in front of a
	# locked chest with no way to find out whether they can open it.
	var held := "Escape Ropes held: %d" % ropes
	var keys_held := GameState.keys_phrase()
	if keys_held != "":
		held += "    " + keys_held
	UI.label(col, held)
	UI.spacer(col)

	match confirming:
		Confirm.ROPE:
			# the rope is the only thing that carries a sealed pack out of a run you
			# are not going to finish, so it has to be named in the choice — and only
			# what it actually carries, which keys never were
			UI.label(col, "Use an Escape Rope? You keep everything found here (%s), but the dungeon stays uncleared — no relic, no unlock." % [risked])
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
	GameState.last_haul = "Escaped with %s and %d gold. The dungeon remains." % [
		Wording.count(int(kept["cards"]), "card"), kept["gold"]]
	GameState.clear_run()
	GameState.reset_run_progress()
	MetaState.save_game()   # explicit full write
	UI.goto(self, "res://scenes/Overworld.tscn")

func _quit() -> void:
	# the run rides along inside the save, so nothing is discarded here
	MetaState.save_game()
	UI.goto(self, "res://scenes/MainMenu.tscn")
