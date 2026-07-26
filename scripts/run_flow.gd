## Shared routing for "the player committed to an encounter". Both traversal views
## use it, so a new traversal model does not have to re-derive how a rest heals or
## which scene a shop opens.
class_name RunFlow
extends RefCounted

## Resolve the chosen encounter. Returns true if it was handled inline (the view
## should refresh itself); false means a scene change is underway.
static func enter_node(view: Node, node: Dictionary, on_resolved: Callable = Callable()) -> bool:
	var t: int = int(node.get("type", GameState.NodeType.COMBAT))
	match t:
		GameState.NodeType.REST:
			# A rest used to be a free heal — no decision in it at all. Now it is
			# the run's other chance to shape the deck, so recovering costs the
			# thinning and vice versa.
			Audio.play("ui_confirm")
			_rest_choice(view, node, on_resolved)
			return false
		GameState.NodeType.EVENT, GameState.NodeType.TREASURE:
			Audio.play("treasure" if t == GameState.NodeType.TREASURE else "event")
			GameState.pending = node
			GameState.autosave()
			view.get_tree().change_scene_to_file("res://scenes/Encounter.tscn")
			return false
		GameState.NodeType.SHOP:
			Audio.play("ui_open")
			GameState.pending = node
			GameState.shop_stock = []  # fresh inventory per visit
			GameState.autosave()
			view.get_tree().change_scene_to_file("res://scenes/Shop.tscn")
			return false
		_:  # COMBAT, ELITE, BOSS
			Audio.play("enter")
			GameState.pending = node
			GameState.autosave()
			view.get_tree().change_scene_to_file("res://scenes/Combat.tscn")
			return false

## Offer the two things a rest can be. Presented as an overlay so all three
## traversal views get it without any of them knowing how it works.
static func _rest_choice(view: Node, node: Dictionary, on_resolved: Callable) -> void:
	var heal := int(GameState.max_hp * Balance.REST_HEAL_FRAC)
	var host := view as Control
	if host == null:
		_finish_rest(node, on_resolved)
		return

	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.82)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 100
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(veil)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	veil.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(col)

	var t := Label.new()
	t.text = "A place to stop"
	t.add_theme_font_size_override("font_size", UITheme.title_font())
	col.add_child(t)
	UI.label(col, "HP %d/%d · deck %d cards, one card seen every %.1f turns" % [
		GameState.hp, GameState.max_hp, GameState.run_deck.size(),
		Balance.draw_interval(GameState.run_deck.size())])

	UI.button(col, "Recover  —  heal %d HP" % heal, func():
		GameState.hp = mini(GameState.max_hp, GameState.hp + heal)
		veil.queue_free()
		_finish_rest(node, on_resolved))

	# A plain branch, not a ternary wrapping a multi-line lambda: the clever version
	# did not parse, and would not have been readable if it had.
	if GameState.can_remove_from_run_deck():
		UI.button(col, "Sharpen  —  remove a card from this run", func():
			UI.card_picker(host, GameState.run_deck, "Leave which card behind?",
				func(card):
					GameState.remove_from_run_deck(card)
					veil.queue_free()
					_finish_rest(node, on_resolved)))
	else:
		UI.button(col, "Sharpen  —  deck already at the minimum")

	UI.button(col, "Move on", func():
		veil.queue_free()
		_finish_rest(node, on_resolved))

static func _finish_rest(node: Dictionary, on_resolved: Callable) -> void:
	GameState.clear_node(node)
	GameState.autosave()
	if on_resolved.is_valid():
		on_resolved.call()

## Where to go when a run ends or was never started.
static func leave_run() -> String:
	if GameState.dungeon_id != "":
		return "res://scenes/DeckBuilder.tscn"
	return "res://scenes/Overworld.tscn"
