## Collection screen — the meta/training layer UI. View owned cards, fuse duplicates
## to raise level (spends copies). Reached from the Map between encounters.
extends Control

var list_box: VBoxContainer
var info_label: Label

func _ready() -> void:
	_build_ui()
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(root)

	var title := Label.new()
	title.text = "Collection — fusing spends copies AND gold; both prices rise with level"
	title.add_theme_font_size_override("font_size", UITheme.title_font())
	root.add_child(title)

	info_label = Label.new()
	root.add_child(info_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", UITheme.sep(6))
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_box)

	var back := Button.new()
	# return to wherever makes sense: the map if a dungeon is active, else the deck builder
	var dest := "res://scenes/Overworld.tscn"
	if GameState.in_run():
		dest = GameState.run_scene()
	elif GameState.dungeon_id != "":
		dest = "res://scenes/DeckBuilder.tscn"
	back.text = "Back"
	back.pressed.connect(func(): get_tree().change_scene_to_file(dest))
	root.add_child(back)

func _refresh() -> void:
	var total := 0
	for id in MetaState.collection:
		total += MetaState.collection[id]["count"]
	info_label.text = "%d cards owned (min %d to run a dungeon), %d types    Gold %d" % [
		total, Balance.MIN_KEEP, MetaState.collection.size(), MetaState.gold]

	for c in list_box.get_children():
		c.queue_free()

	for id in MetaState.collection:
		var entry: Dictionary = MetaState.collection[id]
		var card := (load(MetaState.CATALOG[id]) as CardData).duplicate()
		card.level = entry["level"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.sep(10))
		list_box.add_child(row)

		# illustration first, then the symbol that actually states what it does
		var art := TextureRect.new()
		art.texture = PixelArt.card_art(card.id)
		art.custom_minimum_size = Vector2(UITheme.px(28), UITheme.px(28))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Icons.rarity_colour(card.rarity)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
		var pic := TextureRect.new()
		pic.texture = Icons.tex(Icons.for_card(card))
		pic.custom_minimum_size = Vector2(UITheme.px(32), UITheme.px(32))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
		var lbl := Label.new()
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
		lbl.custom_minimum_size = Vector2(UITheme.px(500), 0)
		var stats := ""
		if card.eff_damage() > 0:
			stats += "dmg %d " % card.eff_damage()
		if card.eff_block() > 0:
			stats += "blk %d " % card.eff_block()
		var cap: int = MetaState.max_level(id)
		lbl.text = "%s  [%s]  Lv%d/%d  x%d   (%s)" % [
			card.name, CardData.Rarity.keys()[card.rarity], entry["level"], cap,
			entry["count"], stats.strip_edges()]
		row.add_child(lbl)
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
				f.text = "+%d  (-%dx, -%dg)" % [step, price["copies"], price["gold"]]
				f.pressed.connect(_on_fuse.bind(id, step))
				row.add_child(f)
		else:
			var blocked := Button.new()
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
