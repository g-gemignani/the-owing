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
	["IsoRun", "res://scenes/IsoRun.tscn", "iso"],
	# Captured twice on purpose. The iso floor is a model about DISCOVERY, so its
	# opening state — six tiles lit, nothing else known — is the least informative
	# picture of it there is, and it is the one that made the rock look broken (D77).
	# The second capture is the same screen a third of the way through a floor.
	["IsoRunExplored", "res://scenes/IsoRun.tscn", "iso_walked"],
	# The same walked floor, but SAVED AND RELOADED first. Every other row here builds
	# its state live in memory, so for as long as that was the whole list the harness
	# had never once photographed the state a player actually boots into — and D140 is
	# what lives in that gap: two grids that JSON turned into strings, a floor that drew
	# nothing at all, and 39 green suites. Should be indistinguishable from the row
	# above; that is the entire point of the capture.
	["IsoResumed", "res://scenes/IsoRun.tscn", "iso_resumed"],
	# One walked floor per TERRAIN, because the iso materials are not one set of
	# textures — `tools/gen_iso_art.gd` builds four, each sampled from the floor band
	# of the backdrops of the dungeons that use it. Every other capture here enters
	# `DUNGEONS[0]`, which is the Crypt, which is `stone`; so for as long as this list
	# had one iso row, three of the four floors had never been photographed at all and
	# a fault in any of them was invisible to the harness (D122). The dungeons named
	# are one per terrain, and the terrain, not the dungeon, is what is being looked at.
	["IsoEarth", "res://scenes/IsoRun.tscn", "iso_walked", "", "warrens"],
	["IsoMoss", "res://scenes/IsoRun.tscn", "iso_walked", "", "fungal_deep"],
	["IsoSand", "res://scenes/IsoRun.tscn", "iso_walked", "", "drowned_market"],
	["Combat", "res://scenes/Combat.tscn", "combat"],
	# The hand is the one part of the game with three states worth photographing
	# rather than one. At rest the cards hang off the bottom edge on purpose; the
	# other two are what pays for that, and neither exists in a still of the resting
	# screen — which is precisely how a layout gets shipped half-checked (D104).
	["CombatHover", "res://scenes/Combat.tscn", "combat", "hover"],
	["CombatInspect", "res://scenes/Combat.tscn", "combat", "inspect"],
	# A GROUP fight, because `_place_slots` does something to a group that it does not
	# do to a single enemy: it shrinks the flanks (`lerpf(0.88, 1.0, ...)`) and spreads
	# them across the full width, and the flanks are the only enemies that ever stand
	# over the left and right thirds of the backdrop. `tests/test_art.gd` measures the
	# floor and says in its own comments that the number is wrong about half the time
	# and that "whether a specific enemy hovers is a question for tools/screenshots.gd,
	# where you can see it" — so this is that capture (D122). `ember_hound` because it
	# is the one archetype whose spawn count cannot roll: `count_min` and `count_max`
	# are both 2, so this frames the same fight every run instead of a coin flip.
	["CombatGroup", "res://scenes/Combat.tscn", "combat_group"],
	["Shop", "res://scenes/Shop.tscn", "shop"],
	["Encounter", "res://scenes/Encounter.tscn", "event"],
	["Chest", "res://scenes/Chest.tscn", "chest"],
	["Collection", "res://scenes/Collection.tscn", ""],
	["Relics", "res://scenes/Relics.tscn", ""],
	["Packs", "res://scenes/Packs.tscn", "packs"],
	["Powers", "res://scenes/Powers.tscn", ""],
	["Glossary", "res://scenes/Glossary.tscn", ""],
	# Settings was missing from this table until D123 went looking for it. Nothing was
	# wrong with the screen — it simply had never been photographed, so "check the
	# captures" was checking sixteen screens and calling it all of them. That is the
	# same blind spot the three iso terrains had (D122): a harness is only as honest
	# as its list, and an absent row looks exactly like a passing one.
	["Settings", "res://scenes/Settings.tscn", ""],
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
		await _capture(String(shot[0]), String(shot[1]), String(shot[2]),
			String(shot[3]) if shot.size() > 3 else "",
			String(shot[4]) if shot.size() > 4 else "")

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

## Put a built screen into a state the player reaches with the mouse, so it can be
## photographed. Drives the SHIPPED wiring — the card's own `mouse_entered`, the
## card's own inspector call — rather than posing the nodes by hand, because a
## capture of a pose no player can produce is worse than no capture.
func _pose(inst: Node, what: String) -> void:
	var cards := _card_holders(inst)
	if cards.is_empty():
		print("POSE MISS ", what, " — no card on screen")
		return
	# the middle of the fan: the card least likely to be clipped by either corner
	var holder: Control = cards[cards.size() / 2]
	match what:
		"hover":
			for c in holder.get_children():
				if c is Button:
					(c as Button).mouse_entered.emit()
					return
		"inspect":
			var id: String = holder.get_meta("card_id")
			var card := load(MetaState.CATALOG.get(id, "")) as CardData
			if card != null:
				UI.inspect_card(holder, card, inst.eng if "eng" in inst else null)

func _card_holders(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control and (n as Control).has_meta("card_id"):
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_card_holders(c))
	return out

## Delete only what THIS harness wrote. It used to take every `t_*` file in
## `user://`, which is the sandbox prefix the whole test suite shares — so running
## the harness beside a suite deleted the save a live test was in the middle of
## using, and the docstring's "do not run this while tests/run.sh is running" was
## the workaround for it rather than a law of nature. Owning one prefix is cheaper
## than remembering a rule.
const SANDBOX := "t_shots_"

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var doomed: Array[String] = []
	var f := d.get_next()
	while f != "":
		if f.begins_with(SANDBOX):
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

func _setup(need: String, dungeon: String = "") -> void:
	GameState.reset_run_progress()
	var did: String = Balance.DUNGEONS[0]
	match need:
		# deepest dungeon, or the capture only ever shows worn chests: a vault
		# cannot roll at depth 1 and that is exactly the screen worth looking at
		"chest": did = Balance.DUNGEONS[Balance.DUNGEONS.size() - 1]
	# A row that names its own dungeon overrides both. Refused rather than ignored if
	# the id is not real: falling back to `DUNGEONS[0]` would hand back a picture of
	# the Crypt under a filename saying `IsoEarth`, which is worse than no capture —
	# the whole point of these rows is that the terrain is the subject.
	if dungeon != "":
		if not (dungeon in Balance.DUNGEONS):
			push_error("screenshots: '%s' is not a dungeon id" % dungeon)
			return
		did = dungeon
	GameState.select_dungeon(did)
	GameState.enter_dungeon(_run_state())

	# This used to FORCE a traversal model per capture, because `_dungeon_with` fell
	# back to the first dungeon when nothing matched and, once every dungeon became iso
	# (D88), that fallback handed the graph view a `TraversalIso` it could not cast —
	# the harness hung on shot five with no error and no output, twenty-two minutes of
	# software-GL render producing four files. D94 deleted the three unreachable views,
	# so entering the dungeon builds the only traversal there is and no forcing is left
	# to do. Restore the forcing, not the fallback, if a second model is ever added.
	var z := Balance.zone_of(did)
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]
	match need:
		"combat":
			GameState.pending = {"type": GameState.NodeType.COMBAT, "row": 1, "col": 0, "cleared": false}
			GameState.combat_state = {}
		# `enemy` is the forced-archetype key `combat.gd` already reads (it is how the
		# iso floor makes the tile you saw and the fight you get the same creature,
		# D85), so this poses a group WITHOUT a second code path in the scene.
		"combat_group":
			GameState.pending = {"type": GameState.NodeType.COMBAT, "row": 1, "col": 0,
				"cleared": false, "enemy": "ember_hound"}
			GameState.combat_state = {}
		"shop":
			GameState.pending = {"type": GameState.NodeType.SHOP, "row": 1, "col": 0, "cleared": false}
			GameState.shop_stock = []
		"event":
			GameState.pending = {"type": GameState.NodeType.EVENT, "row": 1, "col": 0, "cleared": false}
		"chest":
			GameState.pending = {"type": GameState.NodeType.TREASURE, "row": 1, "col": 0, "cleared": false}
			# a key in hand, so the sealed-chest branch can actually be photographed
			GameState.keys = 2
		"iso_walked", "iso_resumed":
			# Walk the floor before the screen is built, resolving whatever is stepped
			# on so the walk keeps going. Uses the model's own first option, which is
			# the one that gets on with the floor, so the capture shows a plausible
			# route rather than a random smear.
			var tv := GameState.traversal
			for i in 14:
				if tv == null or tv.is_complete() or tv.options().is_empty():
					break
				if not tv.select(0).is_empty():
					tv.clear_pending()
			GameState.pending = {}
			# Then throw that away and rebuild it from a save, through real
			# `JSON.stringify`/`parse_string` — not a `duplicate()` of the dictionary,
			# because the whole class of fault this row exists for is a type that
			# survives being copied and does not survive being written down (D140).
			if need == "iso_resumed":
				var blob = JSON.parse_string(JSON.stringify(GameState.run_to_dict()))
				if not GameState.run_from_dict(blob):
					push_error("screenshots: the run would not resume from its own save")
		"packs":
			# Packs renders an empty state with nothing sealed, which is a real screen
			# but not the one worth looking at. Give it one of each kind.
			MetaState.add_pack(Balance.PACK_BOSS, Balance.DUNGEONS[0],
				Balance.PACK_GILDED, "poison")
			MetaState.add_pack(Balance.PACK_ELITE, Balance.DUNGEONS[mini(1, Balance.DUNGEONS.size() - 1)],
				Balance.PACK_SEALED, "fortress")
			MetaState.add_pack(Balance.PACK_TREASURE, Balance.DUNGEONS[0],
				Balance.PACK_WORN, "swarm")
		"defeat":
			# Defeat renders "Nothing to report." on an empty dictionary, which is
			# correct behaviour and a useless capture. Give it a real death.
			GameState.last_defeat = {
				"dungeon": "The Crypt", "difficulty": 1, "killer": "Crypt Hound",
				"tier": Balance.Tier.NORMAL, "turns": 6,
				"forfeited_cards": 3, "forfeited_gold": 140,
				"penalty_gold": 25, "penalty_cards": ["hack"],
				"forfeited_packs": 2,
			}
		_:
			GameState.pending = {"type": GameState.NodeType.COMBAT, "row": 1, "col": 0, "cleared": false}

func _capture(name: String, path: String, need: String, after: String = "",
		dungeon: String = "") -> void:
	_setup(need, dungeon)
	var packed := load(path) as PackedScene
	if packed == null:
		print("MISS ", name)
		return
	var inst := packed.instantiate()
	add_child(inst)
	# three frames: one to build, one to lay out, one to draw the laid-out tree
	for i in 4:
		await get_tree().process_frame
	if after != "":
		_pose(inst, after)
		for i in 3:
			await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + name + ".png")
	print("SHOT ", name)
	inst.queue_free()
	await get_tree().process_frame
