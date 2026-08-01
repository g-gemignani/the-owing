## Gate 2, the "samey test": render one floor from each iso style and terrain, so they
## can be put beside each other and the question answered by looking.
##
## A diagnostic, not shipped. It exists to answer the one question that decides whether
## dropping the other three traversal models is a good idea: **if two dungeons walked on
## the same model are indistinguishable, the model differing was carrying variety that
## nothing has replaced.** No count and no assertion can answer that; only a pair of
## pictures can.
##
## Forces `TraversalIso` onto whichever dungeon it is pointed at, regardless of that
## dungeon's own `traversal` field, so the comparison needs no `.tres` edits and leaves
## nothing behind.
##
## Needs a real GL context, like tools/screenshots.gd:
##   Xvfb :99 -screen 0 1280x720x24 &
##   DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 godot --rendering-driver opengl3 \
##     res://tools/IsoStyles.tscn
## Then put them side by side:
##   godot --headless --script tools/contact_sheet.gd -- --cell=560 --cols=2 \
##     <outdir> <shots>/styles
extends Node

const OUT := "user://shots/styles/"
## Chosen to vary BOTH axes and to hold one of them still: crypt and ossuary share a
## terrain and differ in architecture, which is the harder half of the test — if those
## two are indistinguishable, style alone is not doing the work.
const SUBJECTS := ["crypt", "ossuary", "warrens", "the_maw", "rot_gardens",
	"drowned_market"]
## Steps to walk before capturing. A fresh floor shows one chamber, which is the least
## informative picture of a dungeon there is (D77) — but the walk also has to STOP at the
## stairs. The first version walked a flat 22 steps and caught the Maw five tiles into its
## second floor, which made a four-floor dungeon look like it had no architecture when in
## fact the capture had simply arrived somewhere new. Every subject is now shown its FIRST
## floor, partly explored, which is the only fair comparison.
const WALK := 40
## Stop once this much of the floor is known: enough to see the plan, not so much that
## there is no dark left to show.
const MAPPED_ENOUGH := 0.65

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	MetaState.path_prefix = "t_isostyle_"
	MetaState.slot = 0
	MetaState.new_save()
	for cid in MetaState.CATALOG:
		MetaState.add_card(cid)
	MetaState.gold = 500

	for did in SUBJECTS:
		await _capture(did)
	print("SHOTS: ", ProjectSettings.globalize_path(OUT))
	# writes_disabled BEFORE the purge: MetaState flushes on EXIT_TREE, so a still
	# writable one rewrites the save on the way out and the purge looks like a no-op.
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

func _capture(did: String) -> void:
	var dd := Balance.dungeon(did)
	if dd == null:
		print("MISS ", did)
		return
	GameState.reset_run_progress()
	GameState.select_dungeon(did)
	var deck: Array[CardData] = []
	for cid in MetaState.collection:
		deck.append((load(MetaState.CATALOG[cid]) as CardData).duplicate())
		if deck.size() >= 10:
			break
	GameState.enter_dungeon(deck)
	var z := Balance.zone_of(did)
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]

	# Force the iso model on, whatever this dungeon actually ships with. That is the
	# whole point: the comparison must not require editing twelve .tres files.
	var tv := TraversalIso.new()
	tv.generate(dd)
	GameState.traversal = tv
	for i in WALK:
		if tv.is_complete() or tv.options().is_empty():
			break
		var mapped := 0
		for s in tv.seen:
			if bool(s):
				mapped += 1
		if float(mapped) >= float(maxi(1, tv.tiles)) * MAPPED_ENOUGH:
			break
		if not tv.select(0).is_empty():
			tv.clear_pending()
		if tv.depth != 0:
			break     # it took the stairs; floor 1 is what we came to photograph
	GameState.pending = {}

	var packed := load("res://scenes/IsoRun.tscn") as PackedScene
	var inst := packed.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "%s.png" % did)
	print("SHOT %-16s style=%-10s terrain=%s" % [
		did, String(Balance.ISO_STYLE_OF.get(did, Balance.ISO_STYLE_DEFAULT)),
		Balance.iso_terrain(did)])
	inst.queue_free()
