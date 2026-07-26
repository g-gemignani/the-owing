## View for the dice-board traversal: the track, your token, and the two dice.
extends Control

var status_label: Label
var log_label: Label
var board_box: HBoxContainer
var board_scroll: ScrollContainer
var dice_box: HBoxContainer

func _ready() -> void:
	_build_ui()
	_refresh()
	call_deferred("_scroll_to_token")

## Keep the player's token on screen as the track scrolls past the window.
func _scroll_to_token() -> void:
	var tv := GameState.traversal as TraversalDice
	if tv == null or board_scroll == null or board_box == null:
		return
	var i: int = clampi(tv.pos, 0, board_box.get_child_count() - 1)
	var cell := board_box.get_child(i) as Control
	if cell == null:
		return
	board_scroll.scroll_horizontal = int(maxf(0.0,
		cell.position.x + cell.size.x * 0.5 - board_scroll.size.x * 0.5))

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(12))
	margin.add_child(root)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)

	var spacer_a := Control.new()
	spacer_a.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_a)

	board_scroll = ScrollContainer.new()
	board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(board_scroll)
	var scroll := board_scroll
	board_box = HBoxContainer.new()
	board_box.add_theme_constant_override("separation", UITheme.sep(4))
	scroll.add_child(board_box)

	dice_box = HBoxContainer.new()
	dice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_box.add_theme_constant_override("separation", UITheme.sep(12))
	root.add_child(dice_box)

	var spacer_b := Control.new()
	spacer_b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_b)

	var coll := Button.new()
	coll.text = "Collection"
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	root.add_child(coll)
	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/PauseMenu.tscn"))
	root.add_child(menu_btn)

func _refresh() -> void:
	var tv := GameState.traversal as TraversalDice
	if tv == null:
		log_label.text = "No dungeon in progress."
		call_deferred("_leave")
		return

	var dd := GameState.dungeon_data()
	status_label.text = "%s (d%d)    HP %d/%d    Deck %d    Gold %d    %s" % [
		dd.name if dd != null else "Dungeon", GameState.dungeon,
		GameState.hp, GameState.max_hp, GameState.run_deck.size(),
		MetaState.gold, tv.status()]
	UI.hoverable(status_label, "AT RISK: found this run, but only kept if you beat the boss or use an Escape Rope.")
	status_label.text += "    AT RISK: %d cards, %d gold    Ropes %d" % [
		GameState.escrow_cards.size(), GameState.escrow_gold,
		MetaState.item_count("escape_rope")]

	if tv.is_complete():
		call_deferred("_leave")
		return

	# the whole board is visible: overshoot should be a judgement, not a surprise
	for c in board_box.get_children():
		c.queue_free()
	for i in tv.track.size():
		# each space is an icon plus a marker, so the board reads at a glance
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(UITheme.px(56), 0)
		var pic := TextureRect.new()
		pic.texture = Icons.for_encounter(int(tv.track[i]))
		pic.custom_minimum_size = Vector2(UITheme.px(40), UITheme.px(40))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if i < tv.pos:
			pic.modulate = Color(1, 1, 1, 0.35)      # already passed
		cell.add_child(pic)
		var tag := Label.new()
		tag.text = "^you" if i == tv.pos else ""
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(tag)
		board_box.add_child(cell)

	for c in dice_box.get_children():
		c.queue_free()
	var opts := tv.options()
	for i in opts.size():
		var b := Button.new()
		b.text = opts[i]["label"]
		b.custom_minimum_size = UITheme.reward_card_size()
		b.pressed.connect(_on_pick.bind(i))
		dice_box.add_child(b)

func _on_pick(i: int) -> void:
	var tv := GameState.traversal as TraversalDice
	if tv == null:
		return
	var chosen := tv.select(i)
	if chosen.is_empty():
		return
	GameState.pending = chosen
	if RunFlow.enter_node(self, chosen, _after_rest):
		_refresh()
		call_deferred("_scroll_to_token")

func _after_rest() -> void:
	log_label.text = "Rested."
	_refresh()
	call_deferred("_scroll_to_token")

func _leave() -> void:
	get_tree().change_scene_to_file(RunFlow.leave_run())
