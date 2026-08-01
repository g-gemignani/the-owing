## View for the dungeon-as-a-deck traversal. Shows the revealed encounter, what
## remains in the stack, and the face/avoid choice.
extends Control

var status_label: Label
var reveal_label: Label
var reveal_icon: TextureRect
var log_label: Label
var options_box: HBoxContainer

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
	root.add_theme_constant_override("separation", UITheme.sep(12))
	margin.add_child(root)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)

	var spacer_top := Control.new()
	spacer_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_top)

	reveal_icon = TextureRect.new()
	reveal_icon.custom_minimum_size = Vector2(UITheme.px(64), UITheme.px(64))
	reveal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reveal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(reveal_icon)

	reveal_label = Label.new()
	reveal_label.add_theme_font_size_override("font_size", UITheme.title_font())
	reveal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(reveal_label)

	options_box = HBoxContainer.new()
	options_box.alignment = BoxContainer.ALIGNMENT_CENTER
	options_box.add_theme_constant_override("separation", UITheme.sep(12))
	root.add_child(options_box)

	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_bot)

	var coll := Button.new()
	UITheme.style_button(coll)
	coll.text = "Collection"
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	root.add_child(coll)
	# same Callable on the button and on Escape, so the two cannot drift apart
	UI.exit_button(root, "Menu", func(): UI.goto(self, "res://scenes/PauseMenu.tscn"))

func _refresh() -> void:
	var tv := GameState.traversal as TraversalDeck
	if tv == null:
		log_label.text = "No dungeon in progress."
		call_deferred("_leave")
		return

	var dd := GameState.dungeon_data()
	status_label.text = "%s (d%d)    HP %d/%d    Deck %d    Gold %d    Relics %d" % [
		dd.name if dd != null else "Dungeon", GameState.dungeon,
		GameState.hp, GameState.max_hp, GameState.run_deck.size(),
		MetaState.gold, MetaState.relics.size()]
	UI.hoverable(status_label, "AT RISK: found this run, but only kept if you beat the boss or use an Escape Rope.")
	status_label.text += "    %s    Ropes %d" % [
		GameState.risk_line(), MetaState.item_count("escape_rope")]

	if tv.is_complete():
		reveal_label.text = "The stack is empty."
		call_deferred("_leave")
		return

	reveal_label.text = "Next: %s        (%s)" % [
		Balance.NODE_LABEL.get(tv.revealed, "?"), tv.status()]
	if reveal_icon != null:
		reveal_icon.texture = Icons.for_encounter(tv.revealed)

	for c in options_box.get_children():
		c.queue_free()
	var opts := tv.options()
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := Button.new()
		b.text = o["label"]
		b.custom_minimum_size = UITheme.reward_card_size()
		# cannot pay a cost you do not have
		if int(o.get("hp_cost", 0)) >= GameState.hp:
			b.disabled = true
		else:
			b.pressed.connect(_on_pick.bind(i))
		options_box.add_child(b)

func _on_pick(i: int) -> void:
	var tv := GameState.traversal as TraversalDeck
	if tv == null:
		return
	var opts := tv.options()
	if i >= opts.size():
		return
	var opt: Dictionary = opts[i]
	var cost := int(opt.get("hp_cost", 0))
	var chosen := tv.select(i)
	if chosen.is_empty():
		# avoided: pay the HP here (the traversal never touches run resources)
		GameState.hp = max(1, GameState.hp - cost)
		log_label.text = "Avoided a %s for %d HP." % [
			Balance.NODE_LABEL.get(int(opt.get("type", 0)), "?"), cost]
		_refresh()
		return
	GameState.pending = chosen
	if RunFlow.enter_node(self, chosen, _after_rest):
		_refresh()

func _after_rest() -> void:
	log_label.text = "Rested."
	_refresh()

func _leave() -> void:
	get_tree().change_scene_to_file(RunFlow.leave_run())
