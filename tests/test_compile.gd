## Headless test: every script in the project actually compiles.
##
## This exists because a broken run view (`map.gd`, deleted with its model in D94)
## shipped and survived FIVE commits, each reporting a green suite, while every graph
## dungeon in the game was a black screen. Three separate things let that happen:
##
## 1. `godot --headless --import` does NOT compile scripts. It reported zero
##    errors the whole time.
## 2. `load()` on a script that failed to parse still returns a non-null Resource,
##    so the export test's `if load(path) == null` check passed happily.
## 3. No test loaded the traversal scripts at all — `test_layout.gd` inspects them
##    as TEXT, which cannot notice that they no longer parse.
##
## `get_instance_base_type()` is the honest probe: it is empty when the script did
## not compile. (`can_instantiate()` is not — it answers false for perfectly good
## scripts.) This runs in about a second and would have caught it instantly.
## Run: godot --headless --script tests/test_compile.gd
extends SceneTree

const DIRS := ["res://scripts/", "res://tests/", "res://tools/"]

func _init() -> void:
	var fails := 0
	var checked := 0

	for dir in DIRS:
		for path in _scripts_in(dir):
			var sc := load(path) as GDScript
			checked += 1
			if sc == null:
				fails += 1
				print("FAIL %s could not be loaded at all" % path)
				continue
			# empty base type == the parser gave up on this file
			if sc.get_instance_base_type() == "":
				fails += 1
				print("FAIL %s does not compile" % path)

	# Scenes are the other half: a .tscn whose root script is broken instantiates
	# into a node with no behaviour, which is exactly the black screen that was
	# reported. Checking the scene rather than the script catches a scene that
	# points at a script that no longer exists, too.
	for path in _scenes_in("res://scenes/"):
		checked += 1
		var packed := load(path) as PackedScene
		if packed == null:
			fails += 1
			print("FAIL scene %s does not load" % path)
			continue
		var state := packed.get_state()
		var broken := false
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) != "script":
				continue
			var sc2 = state.get_node_property_value(0, i)
			if sc2 == null or (sc2 as GDScript).get_instance_base_type() == "":
				broken = true
		if broken:
			fails += 1
			print("FAIL scene %s has a root script that does not compile" % path)

	print("  checked %d scripts and scenes" % checked)
	if fails == 0:
		print("COMPILE TEST: PASS (every script and scene root compiles)")
	else:
		print("COMPILE TEST: FAIL (%d)" % fails)
	quit()

func _scripts_in(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(dir + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _scenes_in(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tscn"):
			out.append(dir + f)
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
