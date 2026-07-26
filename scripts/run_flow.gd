## Shared routing for "the player committed to an encounter". Both traversal views
## use it, so a new traversal model does not have to re-derive how a rest heals or
## which scene a shop opens.
class_name RunFlow
extends RefCounted

## Resolve the chosen encounter. Returns true if it was handled inline (the view
## should refresh itself); false means a scene change is underway.
static func enter_node(view: Node, node: Dictionary) -> bool:
	var t: int = int(node.get("type", GameState.NodeType.COMBAT))
	match t:
		GameState.NodeType.REST:
			Audio.play("ui_confirm")
			var heal := int(GameState.max_hp * Balance.REST_HEAL_FRAC)
			GameState.hp = min(GameState.max_hp, GameState.hp + heal)
			GameState.clear_node(node)
			GameState.autosave()
			return true
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

## Where to go when a run ends or was never started.
static func leave_run() -> String:
	if GameState.dungeon_id != "":
		return "res://scenes/DeckBuilder.tscn"
	return "res://scenes/Overworld.tscn"
