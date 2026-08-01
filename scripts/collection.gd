## Collection screen — the meta/training layer UI. View owned cards, fuse duplicates
## to raise level (spends copies). Reached from the Map between encounters.
extends Control

var list_box: VBoxContainer
var filter_box: VBoxContainer
var info_label: Label

func _ready() -> void:
	_build_ui()
	_refresh()

func _build_ui() -> void:
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black.
	var root := UI.screen(self,
		"Collection — fusing spends copies AND gold; both prices rise with level")

	info_label = Label.new()
	root.add_child(info_label)

	# the bar lives in its own box so a filter change can rebuild just the controls
	filter_box = VBoxContainer.new()
	root.add_child(filter_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UITheme.sep(6))
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	# return to wherever makes sense: the map if a dungeon is active, else the deck builder
	var dest := "res://scenes/Overworld.tscn"
	if GameState.in_run():
		# resume_scene, not run_scene: the collection is reachable from the pause
		# menu DURING a fight now, and returning to the map with a fight still
		# saved would leave the player able to walk into a different node and be
		# handed the old fight back
		dest = GameState.resume_scene()
	elif GameState.dungeon_id != "":
		dest = "res://scenes/DeckBuilder.tscn"
	UI.exit_button(root, "Back", func(): UI.goto(self, dest))

func _refresh() -> void:
	# MetaState already knows the total; recounting it here was a second copy of the
	# same sum, and the kind of loop that gets mistaken for a listing loop later.
	var total: int = MetaState.total_copies()

	for c in filter_box.get_children():
		c.queue_free()
	UI.card_filter_bar(filter_box, _refresh)

	var shown: Array = CardFilter.apply(MetaState.collection, MetaState.CATALOG)
	info_label.text = "%d cards owned (min %d to run a dungeon)    Gold %d    %s" % [
		total, Balance.MIN_KEEP, MetaState.gold,
		CardFilter.summary(shown.size(), MetaState.collection.size())]

	for c in list_box.get_children():
		c.queue_free()

	for id in shown:
		var entry: Dictionary = MetaState.collection[id]
		var card := (load(MetaState.CATALOG[id]) as CardData).duplicate()
		card.level = entry["level"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.sep(10))
		list_box.add_child(row)

		# What one more level buys, quoted to the inspector as well as to the row: the
		# fuse buttons below price the next level, and the card being priced is
		# exactly the thing this screen never showed you.
		var cap0: int = MetaState.max_level(id)
		var gain0: String = card.level_up_text(int(entry["level"]) + 1)
		var note := ""
		if gain0 != "" and int(entry["level"]) < cap0:
			note = "Level %d of %d.\nOne more level: %s" % [
				int(entry["level"]), cap0, gain0]

		# The illustration is the way into the full card — see UI.inspect_thumb — then
		# the symbol that states what it does.
		UI.inspect_thumb(row, card, UITheme.px(28), note)
		var pic := TextureRect.new()
		pic.texture = Icons.tex(Icons.for_card(card))
		pic.custom_minimum_size = Vector2(UITheme.px(32), UITheme.px(32))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
		var lbl := Label.new()
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
		lbl.custom_minimum_size.x = UITheme.px(500)
		var stats := ""
		if card.eff_damage() > 0:
			stats += "dmg %d " % card.eff_damage()
		if card.eff_block() > 0:
			stats += "blk %d " % card.eff_block()
		# no empty "()" on a card whose numbers are not damage or block
		var stat_txt := stats.strip_edges()
		lbl.text = "%s  [%s]  Lv%d/%d  x%d%s" % [
			card.name, CardData.Rarity.keys()[card.rarity], entry["level"], cap0,
			entry["count"], "   (%s)" % stat_txt if stat_txt != "" else ""]
		row.add_child(lbl)
		# What the next level BUYS. The buttons have always quoted the price; the
		# benefit was left for the player to infer, which is not a decision anyone
		# can make well against a shop that states its prices AND its goods.
		if gain0 != "" and int(entry["level"]) < cap0:
			var next := Label.new()
			next.custom_minimum_size.x = UITheme.px(220)
			next.add_theme_color_override("font_color", Color(0.72, 0.86, 0.68))
			next.text = "next: %s" % gain0
			row.add_child(next)
			UI.hoverable(next, "What one more level gives this card. Level %d of %d." % [
				int(entry["level"]) + 1, cap0])
		# on the row, so hovering the art or the fuse buttons explains the card too
		UI.hoverable(row, Icons.card_tooltip(card))

		if MetaState.can_fuse(id) and MetaState.hint_once("first_fuse"):
			info_label.text = "Fusing spends copies AND gold: deck width and purse traded for power."
		if MetaState.can_fuse(id):
			# bulk options: maxing a common is 99 levels, which is not 99 clicks
			var possible: int = MetaState.fusable_levels(id)
			for step in _bulk_steps(possible):
				var price := _price_of(id, step)
				var f := Button.new()
				UITheme.style_button(f)
				f.text = "+%d  (-%dx, -%dg)" % [step, price["copies"], price["gold"]]
				var target: int = int(entry["level"]) + step
				var buys: String = card.level_up_text(target)
				UI.hoverable(f, "To level %d: %s\nCosts %d copies and %d gold." % [
					target, buys if buys != "" else "no change to its numbers",
					price["copies"], price["gold"]])
				f.pressed.connect(_on_fuse.bind(id, step))
				row.add_child(f)
		else:
			var blocked := Button.new()
			UITheme.style_button(blocked)
			blocked.text = MetaState.fuse_blocked_reason(id)
			blocked.disabled = true
			row.add_child(blocked)

## Which bulk buttons to offer. Prices rise per level, so a "+10" is no longer ten
## times the "+1" price and each button has to quote its own total.
func _bulk_steps(possible: int) -> Array[int]:
	var steps: Array[int] = [1]
	if possible >= 10:
		steps.append(10)
	if possible > 10:
		steps.append(possible)
	elif possible > 1:
		steps.append(possible)
	return steps

## Total copies and gold for the next `count` levels of a card.
func _price_of(id: String, count: int) -> Dictionary:
	var entry: Dictionary = MetaState.collection[id]
	var card := load(MetaState.CATALOG[id]) as CardData
	var rarity: int = card.rarity if card else 0
	var level := int(entry["level"])
	var copies := 0
	var gold := 0
	for i in count:
		copies += Balance.fuse_copy_cost(level + i)
		gold += Balance.fuse_gold_cost(rarity, level + i)
	return {"copies": copies, "gold": gold}

func _on_fuse(id: String, times: int = 1) -> void:
	var gained := MetaState.fuse_many(id, times)
	if gained > 0:
		Audio.play("fuse")
		info_label.text = "Fused %s: +%d level(s).   Gold left %d" % [id, gained, MetaState.gold]
		_refresh()
