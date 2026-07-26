## Relic inventory. Read-only: relics are earned, never spent, so this screen's
## job is to make the run's accumulated character legible.
extends Control

func _ready() -> void:
	var col := UI.screen(self, "Relics")
	var owned := MetaState.relic_data()
	UI.label(col, "%d of %d relics found." % [owned.size(), MetaState.RELIC_CATALOG.size()])
	var list := UI.scroll(col)
	for r in owned:
		UI.label(list, "%s  [%s]" % [r.name, CardData.Rarity.keys()[r.rarity]])
		UI.label(list, "    %s" % r.description)
	if owned.is_empty():
		UI.label(list, "None yet. Clear a dungeon boss to earn one.")
	# what is still out there, without spoiling the effects
	var missing := MetaState.unowned_relics()
	if not missing.is_empty():
		UI.label(list, "")
		UI.label(list, "Still undiscovered: %d" % missing.size())
	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))
