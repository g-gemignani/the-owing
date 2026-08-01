## Art check for the isometric floor: forces one of EVERY role onto one floor, in
## sight, and renders it.
##
## A diagnostic, not shipped. It exists because a normal capture cannot prove the art
## is wired: the fog hides most of the floor by design, the greedy walk used for the
## explored capture clears whatever it finds, and a role whose file failed to install
## falls back to a flat glyph — so "I did not see a market stall" has three innocent
## explanations and one real one. This puts every sprite on screen at once, at the
## real tile size, so scale, footing and facing can all be judged in a single look.
##
## Needs a real GL context, like tools/screenshots.gd. Under a bare Xvfb:
##   Xvfb :99 -screen 0 1280x720x24 &
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --rendering-driver opengl3 \
##     res://tools/IsoArtCheck.tscn
extends Node

const OUT := "user://shots/"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	# Same sandbox rule as tools/screenshots.gd: a `t_` prefixed save, and not one
	# byte of it may survive the run (tests/run.sh fails on a leftover `t_*`).
	MetaState.path_prefix = "t_isoart_"
	MetaState.slot = 0
	MetaState.new_save()
	for cid in MetaState.CATALOG:
		MetaState.add_card(cid)
	MetaState.gold = 500

	await _capture()
	print("SHOTS: ", ProjectSettings.globalize_path(OUT))
	# writes_disabled BEFORE the purge: MetaState flushes on EXIT_TREE, so a still
	# writable one simply rewrites the save on the way out and the purge looks like it
	# did nothing at all.
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

func _capture() -> void:
	GameState.reset_run_progress()
	GameState.select_dungeon("warrens")
	var deck: Array[CardData] = []
	for cid in MetaState.collection:
		deck.append((load(MetaState.CATALOG[cid]) as CardData).duplicate())
		if deck.size() >= 8:
			break
	GameState.enter_dungeon(deck)

	var tv := GameState.traversal as TraversalIso
	if tv == null:
		print("NOT ISO — the warrens is not on the iso model any more")
		return
	_stage(tv)

	var packed := load("res://scenes/IsoRun.tscn") as PackedScene
	var inst := packed.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "IsoArtCheck.png")
	print("SHOT IsoArtCheck")
	inst.queue_free()

## Put the player in the middle of the plate, carve a generous open area around them,
## light all of it, and lay one of every encounter plus four wanderers where they can
## all be seen. Writes the model's fields directly on purpose — this is a rig for
## looking at art, not a game state anything is expected to be playable from.
func _stage(tv: TraversalIso) -> void:
	var w: int = tv.w
	var mid: int = int(tv.h / 2) * w + int(w / 2)
	# a 7x5 open room, so nothing is hidden behind rock. Staged as ONE chamber so the
	# room-reveal path is what lit it, the same as in play.
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			var c: int = mid + dy * w + dx
			if c >= 0 and c < tv.enc.size():
				tv.enc[c] = TraversalIso.EMPTY
				tv.seen[c] = true
				tv.room_of[c] = 0
				tv.walked[c] = dy >= 1     # a strip of trodden ground, to show the tint
	tv.pos = mid + 2 * w      # stand at the front so everything is behind/around
	tv.walked[tv.pos] = true

	# one of each, spread along two rows
	var roles := [Traversal.Enc.COMBAT, Traversal.Enc.ELITE, Traversal.Enc.BOSS,
		Traversal.Enc.SHOP, Traversal.Enc.REST, Traversal.Enc.EVENT,
		Traversal.Enc.TREASURE]
	for i in roles.size():
		var col: int = i % 4
		var row: int = int(i / 4)
		var c2: int = mid + (row - 2) * w + (col - 2)
		if c2 >= 0 and c2 < tv.enc.size():
			tv.enc[c2] = int(roles[i])
			tv.seen[c2] = true

	# One wanderer per silhouette family, plus one facing away, so all three readings and
	# both facings are in a single frame. Cast explicitly rather than left to the roster:
	# this rig exists to prove the FAMILY art is wired, and a random roster draw might
	# hand out three of the same kind.
	var by_family := {}
	for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE]:
		for eid in Balance.ROSTER[tier]:
			var fam := Balance.iso_family(String(eid))
			if not by_family.has(fam):
				by_family[fam] = String(eid)
	tv.mons = []
	var fams: Array = Balance.ISO_FAMILIES
	for k in 4:
		var c3: int = mid + 1 * w + (k - 2)
		if c3 == tv.pos:
			c3 += 1
		var fam2: String = String(fams[k % fams.size()])
		tv.mons.append({"cell": c3, "type": Traversal.Enc.COMBAT, "awake": true,
			"design": k, "south": k % 2 == 0,
			"enemy": String(by_family.get(fam2, ""))})
	# ...and the two stationary fights get cast too, so the tile art and the wanderer art
	# can be compared against each other in the same picture.
	for i in tv.enc.size():
		var e := int(tv.enc[i])
		if e == Traversal.Enc.COMBAT:
			tv.enemy_of[i] = String(by_family.get("brute", ""))
		elif e == Traversal.Enc.ELITE:
			tv.enemy_of[i] = String(by_family.get("swarm", ""))
	# The stairs are DRAWN rather than sprited — there is no stair art in any pack — so
	# this rig is the only place they can be judged against the sprites they share a floor
	# with.
	var stair: int = mid + 2 * w - 3
	if stair >= 0 and stair < tv.enc.size():
		tv.seen[stair] = true
		tv.room_of[stair] = 0
		tv.enc[stair] = TraversalIso.STAIR
	tv.floors = 2
	tv.depth = 0
	tv.content = roles.size()
	tv.quota = tv.content + tv.mons.size()
