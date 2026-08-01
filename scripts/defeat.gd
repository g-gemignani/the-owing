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

	# What the run was carrying. This is the number escrow exists to make hurt, so
	# it is stated first and in full, not summarised.
	UI.label(col, "Left behind in the dungeon")
	var fc := int(d.get("forfeited_cards", 0))
	var fg := int(d.get("forfeited_gold", 0))
	if fc == 0 and fg == 0:
		UI.label(col, "   nothing — you had not found anything yet")
	else:
		UI.label(col, "   %d card%s and %d gold, earned on this run" % [
			fc, "" if fc == 1 else "s", fg])
		var fp := int(d.get("forfeited_packs", 0))
		if fp > 0:
			UI.label(col, "   %d sealed pack%s, never opened" % [fp, "" if fp == 1 else "s"])
		UI.hoverable(UI.label(col, "   (an Escape Rope would have carried these out)"),
			"Ropes are found in treasures and dropped by bosses. They are never sold.")
	UI.label(col, "")

	# ...and what dying cost on top of it, which is a different thing and was
	# previously run together with the above in one sentence.
	UI.label(col, "Taken from your collection")
	var pg := int(d.get("penalty_gold", 0))
	var pc: Array = d.get("penalty_cards", [])
	if pg == 0 and pc.is_empty():
		UI.label(col, "   nothing")
	else:
		if pg > 0:
			UI.label(col, "   %d banked gold" % pg)
		if not pc.is_empty():
			UI.label(col, "   %s" % ", ".join(pc))
	UI.label(col, "")

	# The reassurance is part of the information: relics and levels are the axis
	# that survives death, and a player who does not know that reads a loss as
	# having undone the whole game.
	UI.label(col, "You keep your relics (%d), your card levels, and %d gold." % [
		MetaState.relics.size(), MetaState.gold])
	UI.spacer(col)
	UI.exit_button(col, "Back to the world", func():
		GameState.last_defeat = {}
		UI.goto(self, "res://scenes/Overworld.tscn"))

func _tier_word(tier: int) -> String:
	match tier:
		Balance.Tier.ELITE: return "elite fight"
		Balance.Tier.BOSS: return "boss fight"
		_: return "fight"
