## Shown when a run ends badly.
##
## Dying was a line of status text on the combat screen followed by
## `await create_timer(2.5)` and a scene change. Escrow (D20), the Escape Rope
## (D21) and the death penalty (D3) exist to make that moment weigh something, and
## the player could not read it, let alone sit with it. This is the reckoning, and
## it waits to be dismissed.
##
## `GameState.last_defeat` is filled by combat.gd. Empty (a fresh boot, or a
## screen test) still produces a usable screen rather than a crash — the rule the
## rest of the screens follow.
extends Control

func _ready() -> void:
	var d: Dictionary = GameState.last_defeat
	var col := UI.screen(self, "You Died", "", "defeat")

	if d.is_empty():
		UI.label(col, "Nothing to report.")
		UI.spacer(col)
		UI.exit_button(col, "Back to the world", func():
			UI.goto(self, "res://scenes/Overworld.tscn"))
		return

	UI.label(col, "%s brought you down in %s (depth %d), on turn %d of a %s." % [
		d.get("killer", "Something"), d.get("dungeon", "the dark"),
		int(d.get("difficulty", 1)), int(d.get("turns", 1)),
		_tier_word(int(d.get("tier", Balance.Tier.NORMAL)))])
	UI.label(col, "")

	# What came home, FIRST (D235). The screen used to open on what was confiscated, and under a
	# design where a lost run is meant to have been worth playing, the first thing it says should
	# be what the run paid. How deep you got is stated beside it, because depth is what set the
	# figure and a percentage with no cause reads as a dice roll.
	var kc := int(d.get("kept_cards", 0))
	var kg := int(d.get("kept_gold", 0))
	var kp := int(d.get("kept_packs", 0))
	var depth := int(d.get("depth", 1))
	var floors := int(d.get("floors", 1))
	UI.label(col, "Carried out, for getting as far as floor %d of %d" % [depth, floors])
	if kc == 0 and kg == 0 and kp == 0:
		UI.label(col, "   nothing — you did not get deep enough to salvage anything")
	else:
		var parts := PackedStringArray()
		if kc > 0:
			parts.append("%d card%s" % [kc, "" if kc == 1 else "s"])
		if kg > 0:
			parts.append("%d gold" % kg)
		if kp > 0:
			parts.append("%d sealed pack%s" % [kp, "" if kp == 1 else "s"])
		UI.label(col, "   %s" % ", ".join(parts))
	UI.hoverable(UI.label(col, "   (the deeper a run gets, the more of it survives losing)"),
		"A run that reaches the bottom brings home half of what it found. One that dies on the first floor brings home almost none of it.")
	UI.label(col, "")

	# ...and what did not. Still stated in full: escrow only means something if the player can see
	# what it cost, and the Rope is only worth carrying if the loss is legible.
	UI.label(col, "Left behind in the dungeon")
	var fc := int(d.get("forfeited_cards", 0))
	var fg := int(d.get("forfeited_gold", 0))
	if fc == 0 and fg == 0:
		UI.label(col, "   nothing — you had not found anything yet")
	else:
		UI.label(col, "   %d card%s and %d gold" % [fc, "" if fc == 1 else "s", fg])
		var fp := int(d.get("forfeited_packs", 0))
		if fp > 0:
			UI.label(col, "   %d sealed pack%s, never opened" % [fp, "" if fp == 1 else "s"])
		UI.hoverable(UI.label(col, "   (an Escape Rope would have carried all of it out)"),
			"Ropes are found in treasures and dropped by bosses. They are never sold.")
	UI.label(col, "")

	# The reassurance is part of the information, and since D235 it is a stronger sentence than it
	# was: dying no longer takes anything out of the collection at all. A player who does not know
	# that reads a loss as having undone the whole game.
	UI.label(col, "Nothing was taken from your collection. You keep your %d gold, your card levels," % MetaState.gold)
	# One number, not two (D247). This said "your relics (0), and every relic you have ever met
	# (7)" — the first half counted an array D238 emptied for good, so the screen whose whole job
	# is to say what a loss did NOT take was opening that reassurance with a zero.
	UI.label(col, "and every relic you have ever met (%d)." % MetaState.relics_seen.size())
	UI.spacer(col)

	# The way back in, on the screen the loss is read on (D292). Without it, going again meant
	# the overworld, the region, the door, the deck builder and the power screen — five screens
	# and a deck to re-assemble, to attempt the thing the player is already looking at. The
	# offer is FIRST, above the way out, because it is the one the screen is arguing for: this
	# is the game that keeps its collection through a death, and a loss it makes cheap to
	# answer is the point of that.
	if GameState.can_go_again():
		var dd := Balance.dungeon(GameState.again_dungeon)
		UI.button(col, "Go again — %s, the same deck" % [
			dd.name if dd != null else "the same door"], func(): _again(), 44.0)
		# What is DIFFERENT about the attempt, said before it is taken, for the reason the
		# boss and the aspect are named on the dungeon row (D41, D187). Two things move: the
		# power is dealt again from three, and the place is now owed something (D285).
		var owed: int = MetaState.grudge_on(GameState.again_dungeon)
		if owed > 0:
			# "it is holding N", not "N are waiting" — `Wording.count` returns the noun already
			# inflected, so any verb after it has to agree with a number this line does not know
			# at write time. The capture is what found it: the screen read "2 relics of yours IS
			# waiting down there", and no assertion in the suite can see a sentence.
			UI.label(col, "   It is owed %s. The enemies are harder for it, and it is holding %s of yours." % [
				Wording.count(owed, "death"),
				Wording.count(owed * Balance.GRUDGE_RELICS_PER, "relic")])
		UI.label(col, "   No debt is taken, and the power is dealt again.")
		# The offer's terms belong to the offer. Without this gap they sat between the two
		# buttons at the same left edge, so the capture read them as conditions on "Back to the
		# world" — which is the one button on this screen they say nothing about.
		UI.spacer(col)

	UI.exit_button(col, "Back to the world", func():
		GameState.last_defeat = {}
		UI.goto(self, "res://scenes/Overworld.tscn"))

## Straight back down. `go_again` rebuilds the whole opening — a fresh run, the same door, the
## same loadout at today's levels — and the Power Pick screen is the next step for the same
## reason it is on the normal path (D253): the run exists and the last thing it asks is what
## you brought to fire.
##
## Reported rather than swallowed if it refuses. `can_go_again` was true when the button was
## drawn, so a false here means the state moved underneath it, and a button that silently does
## nothing is worse than one that is not there.
func _again() -> void:
	if not GameState.go_again():
		UI.goto(self, "res://scenes/Overworld.tscn")
		return
	GameState.last_defeat = {}
	Audio.play("enter")
	get_tree().change_scene_to_file("res://scenes/PowerPick.tscn")

func _tier_word(tier: int) -> String:
	match tier:
		Balance.Tier.ELITE: return "elite fight"
		Balance.Tier.BOSS: return "boss fight"
		_: return "fight"
