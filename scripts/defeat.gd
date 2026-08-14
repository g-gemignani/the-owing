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
	UI.exit_button(col, "Back to the world", func():
		GameState.last_defeat = {}
		UI.goto(self, "res://scenes/Overworld.tscn"))

func _tier_word(tier: int) -> String:
	match tier:
		Balance.Tier.ELITE: return "elite fight"
		Balance.Tier.BOSS: return "boss fight"
		_: return "fight"
