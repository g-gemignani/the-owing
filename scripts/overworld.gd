## Overworld: the world as a list of the places you can travel to.
##
## Rows rather than a map with coordinates — a zone's position relative to another
## zone is not a thing the game models, so drawing one would be inventing fiction the
## rest of the code cannot honour. What a row DOES carry is the zone's own
## establishing shot (D96), which is the part that makes five entries read as five
## places instead of five menu items.
##
## Zones own their card pools, so this screen is also where the player decides what
## they will be able to collect. Saying what KIND of deck a zone builds was tried and
## measured out — see `_pool_line()`.
extends Control

## Slightly wider than the 16:9 shots, so the crop trims the sky rather than the
## sides, and sized against a number that is not a taste: five zones plus the two
## button rows have to fit the shipped 720p frame WITHOUT scrolling on a fresh save.
## At 168x95 with a 10px gap the fifth row was cut in half — five pixels over, and the
## first thing a new player saw was a picture sliced by the bottom of the list.
const THUMB := Vector2(160, 82)
const ROW_GAP := 6.0

var list: VBoxContainer
var news: Label
var stats: Label

func _ready() -> void:
	# D96 rejected a full-bleed painting here, and what it actually rejected was a ZONE
	# SHOT: whichever zone that picks already has a thumbnail in the list below, so the
	# screen drew the same picture twice, and at ZONE_DIM its bright band ran under the
	# sealed rows' prose. Both halves of that objection are about reusing art composed
	# for somewhere else. `bg_world.png` is painted for this screen — a gateway looking
	# out, with nothing beyond the arch that resolves into a place, precisely so it
	# cannot compete with the five establishing shots stood in front of it (D123). The
	# rows still carry the art; this carries the room they are read in.
	var col := UI.screen(self, "The World", "", "world")
	# What happened since you were last here, kept apart from what is always true.
	# These used to be one label, so the first-run explanation arrived welded to the
	# gold count and wrapped onto a second line (D96).
	news = UI.label(col, "")
	news.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	stats = UI.label(col, "")
	list = UI.scroll(col)

	var nav := UI.row(col, 8)
	# A count on a menu entry is the entry's reason to be pressed — the argument that
	# put one on Packs applies to every button here that leads to a collection with a
	# ceiling. It also replaces the summary line that used to restate all four
	# numbers in a row below these buttons.
	UI.button(nav, "Collection (%d/%d)" % [
		MetaState.collection.size(), MetaState.CATALOG.size()],
		func(): UI.goto(self, "res://scenes/Collection.tscn"), 38.0)
	UI.button(nav, "Loadouts", func():
		GameState.manage_only = true
		UI.goto(self, "res://scenes/DeckBuilder.tscn"), 38.0)
	UI.button(nav, "Relics (%d/%d)" % [
		MetaState.relics.size(), MetaState.RELIC_CATALOG.size()],
		func(): UI.goto(self, "res://scenes/Relics.tscn"), 38.0)
	var sealed: int = MetaState.packs.size()
	UI.button(nav, "Packs (%d)" % sealed if sealed > 0 else "Packs",
		func(): UI.goto(self, "res://scenes/Packs.tscn"), 38.0)
	UI.button(nav, "Builds (%d/%d)" % [_builds_done(), Balance.BUILDS.size()],
		func(): UI.goto(self, "res://scenes/Builds.tscn"), 38.0)

	var nav2 := UI.row(col, 8)
	UI.button(nav2, "Settings", func(): UI.goto(self, "res://scenes/Settings.tscn"), 38.0)
	UI.button(nav2, "How this works", func(): UI.goto(self, "res://scenes/Glossary.tscn"), 38.0)
	# Pushed to the far end and sized to its own text. It was a full-width bar across
	# the bottom, which made quitting the loudest thing on the hub. It stays a button
	# and stays unbound to Escape on purpose — `tests/playable_test.gd` lists this
	# screen as having no key exit because leaving the world "must be deliberate",
	# and quiet is not the same as easy to hit by accident.
	UI.hspacer(nav2)
	UI.button(nav2, "Save and quit to title", func():
		MetaState.save_game()
		UI.goto(self, "res://scenes/MainMenu.tscn"), 38.0)
	_refresh()

func _builds_done() -> int:
	var done := 0
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if MetaState.collection.has(c):
				have += 1
		if have == b.cards.size():
			done += 1
	return done

func _refresh() -> void:
	var owned := 0
	for id in MetaState.collection:
		owned += int(MetaState.collection[id]["count"])

	var told: Array[String] = []
	if GameState.last_relic != "":
		told.append("NEW RELIC: %s!" % GameState.last_relic)
		GameState.last_relic = ""
	if GameState.last_haul != "":
		told.append(GameState.last_haul)
		GameState.last_haul = ""
	# explain the world once, the first time it is seen
	if MetaState.hint_once("overworld"):
		told.append("Pick a region, then a dungeon. Cards found inside are only KEPT if you beat its boss. \"How this works\" explains the rest.")
	news.text = "    ".join(told)
	news.visible = not told.is_empty()

	# Only what is always true, and only what is not already on a button below.
	stats.text = "Slot %d    Gold %d    Cleared %d/%d    Cards %d copies    Ropes %d%s" % [
		MetaState.slot + 1, MetaState.gold,
		MetaState.clear_count(), Balance.DUNGEONS.size(),
		owned, MetaState.item_count("escape_rope"),
		"    Ascension %d" % MetaState.ascension if MetaState.ascension > 0 else ""]

	for c in list.get_children():
		c.queue_free()

	for z in Balance.all_zones():
		var unlocked: bool = MetaState.clear_count() >= z.unlock_after_clears
		var cleared := 0
		for did in z.dungeons:
			if MetaState.has_cleared(did):
				cleared += 1

		var row := UI.row(list, 12)
		UI.zone_thumb(row, z.id, THUMB, not unlocked)

		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", UITheme.sep(4))
		row.add_child(box)

		var title := "%s   (%d/%d cleared)" % [z.name, cleared, z.dungeons.size()]
		if not unlocked:
			# What is left to do, not what the total was. The absolute number made
			# the player subtract it from a "Cleared 4/12" printed elsewhere on the
			# same screen; this is the subtraction already done.
			var need: int = z.unlock_after_clears - MetaState.clear_count()
			title = "%s   [sealed — clear %d more dungeon%s]" % [
				z.name, need, "" if need == 1 else "s"]
		UI.button(box, title, (func(): _travel(z.id)) if unlocked else Callable(), 40.0)
		var desc := UI.label(box, z.description)
		if unlocked:
			for line in _pool_line(z):
				UI.label(box, line)
		else:
			# A locked row recedes: four of the five are sealed on a fresh save, and
			# at equal weight they buried the one that could be pressed.
			#
			# Recedes by INK, not by opacity. Dimming the row with `modulate` was
			# tried and photographed: it makes the text translucent, so what it
			# actually reads against is whatever the backdrop is doing behind it, and
			# "Sealed for a reason" landed on the one bright band in the picture. A
			# flat darker font colour is the same recession with no dependency on
			# what is underneath (D96).
			desc.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))

		# The gap belongs to the LIST, not to the text column. Inside the column it
		# only separated rows whose prose was taller than their thumbnail — which is
		# the unlocked ones — and the four sealed rows underneath ran their pictures
		# into a continuous strip.
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(ROW_GAP))
		list.add_child(gap)

## What a zone's pool is worth to you, in the two facts that are actually true of it.
##
## This line used to name the pool's cards, alphabetically, cut off at ten of
## seventeen — which read as "Adrenaline, Anvil Stance, Bash, Berserker Rage, ..."
## and described no deck. Naming the deck instead was tried twice and measured out:
## per-zone build coverage runs 25–40% for the best build with the next two within
## a few points of it, and mechanical concentration rests on two or three cards out
## of twenty. Builds are SCATTERED across zones on purpose (`test_build.gd` enforces
## it), so there is no zone theme to name and any label claiming one would be
## invented (D96).
##
## What is left is true and is what the decision actually turns on: how much of this
## pool you are still missing, and what cannot be got anywhere else.
func _pool_line(z: ZoneData) -> Array[String]:
	var pool: Array[String] = []
	for cid in z.card_pool:
		if cid not in ["hack", "cover"] and cid not in pool:
			pool.append(cid)
	var only: Array[String] = []
	for did in z.dungeons:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		for cid in d.exclusive_cards:
			if cid not in pool:
				pool.append(cid)
			if cid not in only:
				only.append(cid)

	var missing := 0
	for cid in pool:
		if not MetaState.collection.has(cid):
			missing += 1

	var out: Array[String] = []
	out.append("%d cards found here%s" % [pool.size(),
		"" if missing == 0 else " · %d you do not own yet" % missing])
	if not only.is_empty():
		out.append("Only here: %s" % _names(only))
	return out

func _names(ids: Array[String]) -> String:
	var names: Array[String] = []
	for cid in ids:
		if MetaState.CATALOG.has(cid):
			var c := load(MetaState.CATALOG[cid]) as CardData
			if c != null:
				names.append(c.name)
	if names.is_empty():
		return "—"
	if names.size() > 8:
		return "%s, +%d more" % [", ".join(names.slice(0, 8)), names.size() - 8]
	return ", ".join(names)

func _travel(zone_id: String) -> void:
	GameState.current_zone = zone_id
	UI.goto(self, "res://scenes/ZoneView.tscn")
