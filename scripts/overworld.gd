## Overworld: the world as a list of zones you travel between.
##
## Deliberately laid out as rows rather than a map with coordinates — the layout
## is the part that will be replaced by art, while the structure (which zones
## exist, what gates them, what they hold) is the part that has to be right now.
## Zones already own their card pools, so this screen is where the player decides
## what kind of deck they are going to be able to build.
extends Control

var list: VBoxContainer
var header: Label

func _ready() -> void:
	var col := UI.screen(self, "The World")
	header = UI.label(col, "")
	list = UI.scroll(col)

	var nav := UI.row(col, 8)
	UI.button(nav, "Collection", func(): UI.goto(self, "res://scenes/Collection.tscn"), 38.0)
	UI.button(nav, "Loadouts", func():
		GameState.manage_only = true
		UI.goto(self, "res://scenes/DeckBuilder.tscn"), 38.0)
	UI.button(nav, "Relics", func(): UI.goto(self, "res://scenes/Relics.tscn"), 38.0)
	UI.button(nav, "Builds", func(): UI.goto(self, "res://scenes/Builds.tscn"), 38.0)
	UI.button(nav, "Settings", func(): UI.goto(self, "res://scenes/Settings.tscn"), 38.0)
	UI.button(nav, "How this works", func(): UI.goto(self, "res://scenes/Glossary.tscn"), 38.0)
	# completion, so there is a number to finish
	var builds_done := 0
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if MetaState.collection.has(c):
				have += 1
		if have == b.cards.size():
			builds_done += 1
	var done := UI.label(col, "Cleared %d/%d dungeons · %d/%d builds · %d/%d relics · %d/%d cards%s" % [
		MetaState.clear_count(), Balance.DUNGEONS.size(),
		builds_done, Balance.BUILDS.size(),
		MetaState.relics.size(), MetaState.RELIC_CATALOG.size(),
		MetaState.collection.size(), MetaState.CATALOG.size(),
		"   ·   Ascension %d" % MetaState.ascension if MetaState.ascension > 0 else ""])
	done.modulate = Color(1, 1, 1, 0.75)
	UI.button(col, "Save and quit to title", func():
		MetaState.save_game()
		UI.goto(self, "res://scenes/MainMenu.tscn"), 38.0)
	_refresh()

func _refresh() -> void:
	var owned := 0
	for id in MetaState.collection:
		owned += int(MetaState.collection[id]["count"])
	var prefix := ""
	if GameState.last_relic != "":
		prefix = "NEW RELIC: %s!    " % GameState.last_relic
		GameState.last_relic = ""
	# explain the world once, the first time it is seen
	if MetaState.hint_once("overworld"):
		prefix += "Pick a region, then a dungeon. Cards found inside are only KEPT if you beat its boss. \"How this works\" explains the rest.    "
	if GameState.last_haul != "":
		prefix += GameState.last_haul + "    "
		GameState.last_haul = ""
	header.text = "%sSlot %d    Cleared %d/%d    Gold %d    Cards %d types / %d copies    Relics %d    Ropes %d" % [
		prefix, MetaState.slot + 1, MetaState.clear_count(), Balance.DUNGEONS.size(),
		MetaState.gold, MetaState.collection.size(), owned, MetaState.relics.size(),
		MetaState.item_count("escape_rope")]

	for c in list.get_children():
		c.queue_free()

	for z in Balance.all_zones():
		var unlocked: bool = MetaState.clear_count() >= z.unlock_after_clears
		var cleared := 0
		for did in z.dungeons:
			if MetaState.has_cleared(did):
				cleared += 1

		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.sep(4))
		list.add_child(box)

		var title := "%s   (%d/%d cleared)" % [z.name, cleared, z.dungeons.size()]
		if not unlocked:
			title = "%s   [sealed — clear %d dungeons to open]" % [z.name, z.unlock_after_clears]
		UI.button(box, title, (func(): _travel(z.id)) if unlocked else Callable(), 40.0)
		UI.label(box, "    %s" % z.description)
		if unlocked:
			UI.label(box, "    Deck cards found here: %s" % _pool_names(z))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(10))
		box.add_child(gap)

func _pool_names(z: ZoneData) -> String:
	var names: Array[String] = []
	for cid in z.card_pool:
		if cid in ["strike", "defend"]:
			continue
		if MetaState.CATALOG.has(cid):
			var c := load(MetaState.CATALOG[cid]) as CardData
			if c != null:
				names.append(c.name)
	if names.is_empty():
		return "basics only"
	if names.size() > 10:
		return "%s, +%d more" % [", ".join(names.slice(0, 10)), names.size() - 10]
	return ", ".join(names)

func _travel(zone_id: String) -> void:
	GameState.current_zone = zone_id
	UI.goto(self, "res://scenes/ZoneView.tscn")
