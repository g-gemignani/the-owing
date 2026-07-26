## Encounter map. StS-style layered node graph. Routes selections into Combat,
## handles Rest inline. Reads/writes GameState so progress survives scene changes.
extends Control


var status_label: Label
var rows_box: VBoxContainer
var scroll: ScrollContainer
## Row the player can act on, so the view can be scrolled to it.
var focus_row: int = -1
var log_label: Label

func _ready() -> void:
	_build_ui()
	_refresh()
	# layout sizes are only known after a frame, so scroll on the next one
	call_deferred("_scroll_to_focus")

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.sep(12))
	root.add_child(header)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(status_label)
	var coll_btn := Button.new()
	coll_btn.text = "Collection"
	coll_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	header.add_child(coll_btn)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/PauseMenu.tscn"))
	header.add_child(menu_btn)

	log_label = Label.new()
	log_label.text = "Select an encounter to enter."
	root.add_child(log_label)

	# scroll so big UI scales still fit on screen
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", UITheme.sep(6))
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)

func _refresh() -> void:
	var dd := GameState.dungeon_data()
	status_label.text = "%s (d%d)    HP %d/%d    Deck %d    Gold %d    Relics %d" % [
		dd.name if dd != null else "Dungeon", GameState.dungeon,
		GameState.hp, GameState.max_hp, GameState.run_deck.size(),
		MetaState.gold, MetaState.relics.size()]
	UI.hoverable(status_label, "AT RISK: found this run, but only kept if you beat the boss or use an Escape Rope.")
	status_label.text += "    AT RISK: %d cards, %d gold    Ropes %d" % [
		GameState.escrow_cards.size(), GameState.escrow_gold,
		MetaState.item_count("escape_rope")]

	for c in rows_box.get_children():
		c.queue_free()

	# No dungeon in progress (e.g. scene opened directly): send the player back
	# rather than rendering a run that does not exist.
	var tv := GameState.traversal as TraversalGraph
	if tv == null:
		log_label.text = "No dungeon in progress — choose a dungeon first."
		call_deferred("_go_to_deck_builder")
		return

	var reach := tv.options()
	focus_row = int(reach[0]["row"]) if not reach.is_empty() else -1
	# render boss row (top) down to first row (bottom)
	for r in range(tv.map.size() - 1, -1, -1):
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", UITheme.sep(12))
		rows_box.add_child(hb)
		for node in tv.map[r]:
			var b := Button.new()
			b.custom_minimum_size = UITheme.map_node_size()
			var mark := ""
			if node["cleared"]:
				mark = " [x]"
			# edge indices were debug noise; show where you are instead
			# Balance.NODE_LABEL is the single source of truth for encounter names.
			# map.gd used to keep its own copy, which silently lost Event and
			# Treasure when those were added — and an unknown key threw mid-render,
			# so every row below it (including the only actionable one) vanished.
			var label: String = Balance.NODE_LABEL.get(int(node["type"]), "?")
			# name the boss on its own node, so the finale is never a surprise
			if int(node["type"]) == GameState.NodeType.BOSS:
				var boss := Balance.boss_of(GameState.dungeon_id)
				if boss != null:
					label = "BOSS: %s" % boss.name
					UI.hoverable(b, "%s\n%s" % [
						boss.name, Balance.boss_warning(GameState.dungeon_id)])
			b.text = "%s%s" % [label, mark]
			var is_reach := false
			for rn in reach:
				if rn["row"] == node["row"] and rn["col"] == node["col"]:
					is_reach = true
			b.disabled = not is_reach
			if is_reach:
				# make the actionable row unmistakable
				b.text = "▶ " + b.text
				Icons.style_card_button(b, 1)
				b.pressed.connect(_on_node_selected.bind(node))
			elif node["cleared"]:
				b.modulate = Color(1, 1, 1, 0.35)
			else:
				b.modulate = Color(1, 1, 1, 0.6)
			hb.add_child(b)

## Bring the actionable row into view.
##
## The map draws the boss at the top and the entrance at the bottom, so at nine
## rows and a large UI scale the only row the player can press starts *below the
## window*. Reported from play as "I can only see a boss and an elite and cannot
## press anything" — the map was fine, it was simply scrolled past.
func _scroll_to_focus() -> void:
	if scroll == null or rows_box == null or focus_row < 0:
		return
	var tv := GameState.traversal as TraversalGraph
	if tv == null:
		return
	# rows are rendered top-down from the boss, so invert the row index
	var child_index: int = (tv.map.size() - 1) - focus_row
	if child_index < 0 or child_index >= rows_box.get_child_count():
		return
	var row := rows_box.get_child(child_index) as Control
	if row == null:
		return
	var target := row.position.y + row.size.y * 0.5 - scroll.size.y * 0.5
	scroll.scroll_vertical = int(maxf(0.0, target))

func _on_node_selected(node: Dictionary) -> void:
	var tv := GameState.traversal as TraversalGraph
	if tv == null:
		return
	# find the option index for this node, then let the traversal commit to it
	var opts := tv.options()
	var idx := -1
	for i in opts.size():
		if opts[i]["row"] == node["row"] and opts[i]["col"] == node["col"]:
			idx = i
	if idx < 0:
		return
	var chosen := tv.select(idx)
	if chosen.is_empty():
		return
	# A rest resolves through an overlay now, so RunFlow calls back once the player
	# has actually chosen. Anything else is still handled inline.
	if RunFlow.enter_node(self, chosen, _after_rest):
		_refresh()
		call_deferred("_scroll_to_focus")

func _after_rest() -> void:
	log_label.text = "Rested."
	_refresh()
	call_deferred("_scroll_to_focus")

func _go_to_deck_builder() -> void:
	var dest := "res://scenes/Overworld.tscn"
	if GameState.dungeon_id != "":
		dest = "res://scenes/DeckBuilder.tscn"
	get_tree().change_scene_to_file(dest)
