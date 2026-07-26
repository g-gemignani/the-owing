## Runtime test: every tooltip the game writes can actually be hovered.
##
## Written after a play report — "hovering a card in the collection should show
## what it does". The text already existed; it was set on `Label`s, and Label
## defaults to MOUSE_FILTER_IGNORE, so the mouse passed straight through and no
## tooltip ever appeared. Three screens shipped explanations nobody could read.
##
## This is a SCENE, not a `--script` test: mouse_filter is a runtime property of a
## built tree, and autoloads are not registered in headless script runs.
## Run: godot --headless res://tests/TooltipTest.tscn
extends Node

const SCENES := [
	"res://scenes/Collection.tscn",
	"res://scenes/DeckBuilder.tscn",
	"res://scenes/Shop.tscn",
]

var _fails := 0

func _ready() -> void:
	# sandbox: a test must never touch the player's save (one previously did)
	MetaState.path_prefix = "t_tooltip_"
	MetaState.slot = 0
	MetaState.new_save()
	GameState.dungeon_id = Balance.DUNGEONS[0]

	for path in SCENES:
		await _check(path)

	# the collection specifically must explain each card, not just be hoverable
	await _check_collection_explains()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("TOOLTIP TEST: PASS (every tooltip is reachable; collection explains each card)")
	else:
		print("TOOLTIP TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _check(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load ", path); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	for c in _controls(inst):
		if c.tooltip_text != "" and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			_fails += 1
			print("FAIL unreachable tooltip on %s (%s) in %s: %s" % [
				c.name, c.get_class(), path, c.tooltip_text.get_slice("\n", 0)])
	inst.queue_free()
	await get_tree().process_frame

func _check_collection_explains() -> void:
	var inst := (load("res://scenes/Collection.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	var explained := 0
	for c in _controls(inst):
		# a card row names the card and says what it does, so it is longer than a label
		if c.tooltip_text.find("Level ") != -1 and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			explained += 1
	var owned: int = MetaState.collection.size()
	if explained < owned:
		_fails += 1
		print("FAIL collection explains %d of %d owned card types on hover" % [explained, owned])
	inst.queue_free()
	await get_tree().process_frame

func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control:
		out.append(n as Control)
	for child in n.get_children():
		out.append_array(_controls(child))
	return out

## Delete this test's sandboxed files. Deleting is not enough on its own — a
## surviving MetaState flushes when the engine frees it at exit and re-creates
## them, which is why writes are disabled first.
func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
