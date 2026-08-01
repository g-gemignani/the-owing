## Dev harness for inspecting a live scene headlessly.
##
## Sandboxed: an earlier version ran against the real save and destroyed a
## player's in-progress run when MetaState flushed on exit. A debugging tool must
## never be able to write to real player data.
extends Node
func _ready() -> void:
	MetaState.path_prefix = "t_debug_"
	MetaState.slot = 0
	MetaState.new_save()
	GameState.select_dungeon("crypt")
	GameState.run_deck = MetaState.build_deck({"hack": 6, "cover": 6, "stave_in": 4, "reap": 4})
	GameState.generate_map()
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	var sc: Control = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	var sizes := {}
	var total := 0.0
	for h in sc.hand_box.get_children():
		var c := h as Control
		sizes[str(c.size.round())] = int(sizes.get(str(c.size.round()), 0)) + 1
		total += c.size.x
	print("HAND %d cards | distinct sizes: %d %s | row width %.0f | viewport %.0f" % [
		sc.hand_box.get_child_count(), sizes.size(), sizes, total,
		get_viewport().get_visible_rect().size.x])
	get_tree().quit()
