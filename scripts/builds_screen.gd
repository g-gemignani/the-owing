## Build tracker: what archetypes exist, how far along each one is, and *where* the
## missing pieces are.
##
## This screen is what makes the scattering of build cards legible. Without it the
## player only sees a pile of cards; with it, a run has a stated purpose ("two more
## from the Fungal Deep and Poison is finished").
extends Control

func _ready() -> void:
	var col := UI.screen(self, "Builds", "", "table")
	UI.label(col, "Archetypes are spread across dungeons on purpose — no single place can finish one. Cards are only kept if you beat the boss or spend a rope.")
	var list := UI.scroll(col)

	# ordered by how soon they can be finished, so the next goal is at the top
	var ordered: Array = Balance.all_builds()
	ordered.sort_custom(func(a, b):
		return Balance.clears_required_for(a) < Balance.clears_required_for(b))
	for b in ordered:
		var owned: Array[String] = []
		var missing: Array[String] = []
		for cid in b.cards:
			if MetaState.collection.has(cid):
				owned.append(cid)
			else:
				missing.append(cid)

		var title := Label.new()
		title.add_theme_font_size_override("font_size", UITheme.title_font())
		var done := missing.is_empty()
		title.add_theme_color_override("font_color",
			Icons.rarity_colour(4) if done else Color(0.9, 0.9, 0.9))
		var gate: int = Balance.clears_required_for(b)
		var reachable: bool = MetaState.clear_count() >= gate
		title.text = "%s   %d/%d%s" % [b.name, owned.size(), b.cards.size(),
			"   COMPLETE" if done else ("" if reachable else "   (needs %d clears, you have %d)" % [
				gate, MetaState.clear_count()])]
		list.add_child(title)
		UI.label(list, "    %s" % b.description)

		if not missing.is_empty():
			# group the missing cards by where they can actually be found
			var by_place := {}
			for cid in missing:
				var place := _where(cid)
				if not by_place.has(place):
					by_place[place] = []
				var arr: Array = by_place[place]
				arr.append(_card_name(cid))
				by_place[place] = arr
			for place in by_place:
				UI.label(list, "    Missing — %s: %s" % [place, ", ".join(by_place[place])])
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(10))
		list.add_child(gap)

	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

func _card_name(cid: String) -> String:
	if not MetaState.CATALOG.has(cid):
		return cid
	var c := load(MetaState.CATALOG[cid]) as CardData
	return c.name if c != null else cid

## Where a card can be obtained: its exclusive dungeon, or its zone.
func _where(cid: String) -> String:
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		if d != null and cid in d.exclusive_cards:
			var cleared := "cleared" if MetaState.has_cleared(did) else "not yet cleared"
			return "%s (%s)" % [d.name, cleared]
	for z in Balance.all_zones():
		if cid in z.card_pool:
			return "anywhere in %s" % z.name
	return "unknown"
