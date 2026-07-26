## Screenshot harness — boots every screen at the shipped 1280x720 and writes a PNG.
##
## A diagnostic, not shipped. Exists because art direction cannot be judged from
## code: "the combat screen is busy" is an opinion until you can put two captures
## side by side. Same boot sequence as tests/menu_art_test.gd, for the same
## reasons — screens with no state NAVIGATE away, which in a harness replaces the
## harness itself, so a live run has to be faked before any scene is instanced.
##
## **Do not run this while `tests/run.sh` is running.** The purge at the end removes
## every `t_*` file in `user://`, which is exactly the sandbox a scene test is using —
## doing both at once made CardTextTest and PlayableTest fail with nothing wrong in
## either of them.
##
## Needs a real GL context (this is a render, not a simulation), so it cannot run
## under --headless. Under a bare Xvfb, force software GL:
##   LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -s "-screen 0 1280x720x24" \
##     godot --rendering-driver opengl3 res://tools/Screenshots.tscn
## Output: user://shots/*.png (printed as a real path on exit).
extends Node

const OUT := "user://shots/"

## scene -> what state it needs before it will render anything.
const SHOTS := [
	["MainMenu", "res://scenes/MainMenu.tscn", ""],
	["Overworld", "res://scenes/Overworld.tscn", ""],
	["ZoneView", "res://scenes/ZoneView.tscn", "zone"],
	["DeckBuilder", "res://scenes/DeckBuilder.tscn", ""],
	["Map", "res://scenes/Map.tscn", "graph"],
	["DeckRun", "res://scenes/DeckRun.tscn", "deck"],
	["DiceRun", "res://scenes/DiceRun.tscn", "dice"],
	["IsoRun", "res://scenes/IsoRun.tscn", "iso"],
	["Combat", "res://scenes/Combat.tscn", "combat"],
	["Shop", "res://scenes/Shop.tscn", "shop"],
	["Encounter", "res://scenes/Encounter.tscn", "event"],
	["Collection", "res://scenes/Collection.tscn", ""],
	["Relics", "res://scenes/Relics.tscn", ""],
	["Powers", "res://scenes/Powers.tscn", ""],
	["Glossary", "res://scenes/Glossary.tscn", ""],
	["Victory", "res://scenes/Victory.tscn", "combat"],
	["Defeat", "res://scenes/Defeat.tscn", "defeat"],
]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	MetaState.path_prefix = "t_shots_"
	MetaState.slot = 0
	MetaState.new_save()
	# a generous collection, so the browse screens are not all empty states
	for cid in MetaState.CATALOG:
		MetaState.add_card(cid)
	MetaState.gold = 500

	# One screen per process when a name is given (`-- Combat`): a screen that hangs
	# then costs one capture instead of every capture after it.
	var only: PackedStringArray = OS.get_cmdline_user_args()
	for shot in SHOTS:
		if only.size() > 0 and not only.has(String(shot[0])):
			continue
		await _capture(String(shot[0]), String(shot[1]), String(shot[2]))

	print("SHOTS: ", ProjectSettings.globalize_path(OUT))
	# Same sandbox rule as the test suite: no `t_*` file may survive the run —
	# `tests/run.sh` fails on a leftover one, and this harness writes the same kind.
	#
	# `writes_disabled` MUST be set before the purge, not after. MetaState flushes on
	# NOTIFICATION_EXIT_TREE, so a still-writable MetaState simply rewrites the save
	# on the way out and the purge looks like it silently did nothing. (It did: the
	# first version of this set a misremembered `writes_enabled` and leaked every run.)
	MetaState.writes_disabled = true
	_purge()
	get_tree().quit()

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var doomed: Array[String] = []
	var f := d.get_next()
	while f != "":
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))

## The run deck. Deliberately does NOT reset progress: `reset_run_progress()` clears
## `dungeon_id`, and as an argument to `enter_dungeon()` it ran AFTER
## `select_dungeon()` — so Combat saw no dungeon and fell back to the tiling zone
## backdrop instead of the painted one. The capture looked like missing art.
func _run_state() -> Array[CardData]:
	var deck: Array[CardData] = []
	for cid in MetaState.collection:
		for i in int(MetaState.collection[cid]["count"]):
			deck.append((load(MetaState.CATALOG[cid]) as CardData).duplicate())
	return deck

func _dungeon_with(model: int) -> String:
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null and dd.traversal == model:
			return did
	return Balance.DUNGEONS[0]

func _setup(need: String) -> void:
	GameState.reset_run_progress()
	var did: String = Balance.DUNGEONS[0]
	match need:
		"deck": did = _dungeon_with(Traversal.Kind.DECK)
		"dice": did = _dungeon_with(Traversal.Kind.DICE)
		"iso": did = _dungeon_with(Traversal.Kind.ISO)
	GameState.select_dungeon(did)
	GameState.enter_dungeon(_run_state())
	var z := Balance.zone_of(did)
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]
	match need:
		"combat":
			GameState.pending = {"type": GameState.NodeType.COMBAT, "row": 1, "col": 0, "cleared": false}
			GameState.combat_state = {}
		"shop":
			GameState.pending = {"type": GameState.NodeType.SHOP, "row": 1, "col": 0, "cleared": false}
			GameState.shop_stock = []
		"event":
			GameState.pending = {"type": GameState.NodeType.EVENT, "row": 1, "col": 0, "cleared": false}
		"defeat":
			# Defeat renders "Nothing to report." on an empty dictionary, which is
			# correct behaviour and a useless capture. Give it a real death.
			GameState.last_defeat = {
				"dungeon": "The Crypt", "difficulty": 1, "killer": "Crypt Hound",
				"tier": Balance.Tier.NORMAL, "turns": 6,
				"forfeited_cards": 3, "forfeited_gold": 140,
				"penalty_gold": 25, "penalty_cards": ["strike"],
			}
		_:
			GameState.pending = {"type": GameState.NodeType.COMBAT, "row": 1, "col": 0, "cleared": false}

func _capture(name: String, path: String, need: String) -> void:
	_setup(need)
	var packed := load(path) as PackedScene
	if packed == null:
		print("MISS ", name)
		return
	var inst := packed.instantiate()
	add_child(inst)
	# three frames: one to build, one to lay out, one to draw the laid-out tree
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("SHOT ", name)
	inst.queue_free()
	await get_tree().process_frame
