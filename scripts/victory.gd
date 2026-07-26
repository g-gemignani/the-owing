## Shown when the final dungeon falls. The world had no ending before this.
extends Control

func _ready() -> void:
	var col := UI.screen(self, "The Maw Is Quiet")
	UI.label(col, "You cleared every door anyone had mapped, and then the one nobody had.")
	UI.label(col, "")

	var builds_done := 0
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if MetaState.collection.has(c):
				have += 1
		if have == b.cards.size():
			builds_done += 1
	UI.label(col, "Dungeons cleared: %d / %d" % [MetaState.clear_count(), Balance.DUNGEONS.size()])
	UI.label(col, "Builds completed: %d / %d" % [builds_done, Balance.BUILDS.size()])
	UI.label(col, "Relics found: %d / %d" % [MetaState.relics.size(), MetaState.RELIC_CATALOG.size()])
	UI.label(col, "Card types owned: %d / %d" % [MetaState.collection.size(), MetaState.CATALOG.size()])
	UI.label(col, "Ascension: %d" % MetaState.ascension)
	UI.spacer(col)

	# Ascension keeps the collection and relics but re-locks the world, so the
	# hundred cards have somewhere to go after the last door.
	UI.label(col, "Descend again? Ascension %d makes every enemy stronger and the loot richer. You keep your collection, relics and ropes; the dungeons re-lock." % (MetaState.ascension + 1))
	UI.button(col, "Begin Ascension %d" % (MetaState.ascension + 1), func(): _ascend())
	UI.exit_button(col, "Stay here", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

func _ascend() -> void:
	MetaState.ascension += 1
	Balance.ascension = MetaState.ascension
	MetaState.cleared_dungeons = []
	GameState.reset_run_progress()
	GameState.clear_run()
	MetaState.save_game()
	UI.goto(self, "res://scenes/Overworld.tscn")
