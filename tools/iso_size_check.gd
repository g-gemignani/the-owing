## Size check for the isometric floor: EVERY archetype in the game, standing next to the hero.
##
## A diagnostic, not shipped. `tools/iso_scale.gd` prints what each creature is drawn at as a
## number; this is the picture that number is a claim about, and the two answer different
## questions. A table cannot say whether a skeleton reads as a person, and 1.05 and 0.78 look
## equally reasonable in a column right up until you see that one of the two paintings is a
## bust cut off at the hip.
##
## Why it exists at all: creature size has now been got wrong three times (D306, D309, D320),
## every time by tuning a number against a sample of two or three creatures. Thirty-five
## archetypes cannot be judged from three, and the failure mode is always the same — the
## sample looked right and the roster did not.
##
## The window fits about nine tiles across, so the roster does not fit in one frame. It comes
## out as PAGES, sorted shortest to tallest, with the hero standing in every one as the
## yardstick. One process per page, because a second capture inside one process hands back the
## first frame's pixels (D155):
##
##   for p in 0 1 2; do
##     godot --rendering-driver opengl3 res://tools/IsoSizeCheck.tscn -- --page $p
##   done
##
## The LAST page to be written also stacks the three floor bands into `IsoSize_all.png`, so
## the whole roster ends up in one picture. It is done there rather than in a fourth process
## because the only thing a stitch needs is for every page to be on disk, and the last writer
## is the one that knows they are.
##
## Needs a real GL context, like tools/screenshots.gd and tools/iso_art_check.gd.
extends Node

const OUT := "user://shots/"
## Creatures per page: two rows of six, which is what the window holds without the back row
## standing on the front row's head.
const PER_PAGE := 12

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	# Same sandbox rule as tools/screenshots.gd: a `t_` prefixed save, and not one byte of it
	# may survive the run (tests/run.sh fails on a leftover `t_*`).
	MetaState.path_prefix = "t_isosize_"
	MetaState.slot = 0
	MetaState.new_save()
	for cid in MetaState.CATALOG:
		MetaState.add_card(cid)
	MetaState.gold = 500

	await _capture()
	print("SHOTS: ", ProjectSettings.globalize_path(OUT))
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

## Every archetype there is, shortest first. Read off the `.tres` files rather than off a
## roster, because a roster is per dungeon and an archetype missing from every pool would
## then be the one nobody ever looks at.
func _roster() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://resources/enemies")
	if d == null:
		return out
	for f in d.get_files():
		var n := String(f)
		if n.ends_with(".tres"):
			out.append(n.get_basename())
	out.sort_custom(func(a, b): return Balance.iso_stature(a) < Balance.iso_stature(b))
	return out

func _capture() -> void:
	var page := 0
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if String(args[i]) == "--page" and i + 1 < args.size():
			page = int(args[i + 1])

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
	var all := _roster()
	var mine: Array = all.slice(page * PER_PAGE, mini((page + 1) * PER_PAGE, all.size()))
	if mine.is_empty():
		print("page %d is past the end of a %d-archetype roster" % [page, all.size()])
		return
	_stage(tv, mine)

	var packed := load("res://scenes/IsoRun.tscn") as PackedScene
	var inst := packed.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "IsoSize_%d.png" % page)
	print("SHOT page %d: %s" % [page, mine])
	for id in mine:
		print("   %-22s stature %.2f" % [String(id), Balance.iso_stature(String(id))])
	inst.queue_free()
	_stitch(int(ceil(float(all.size()) / PER_PAGE)))

## Stack every page's floor band into one image, once they all exist.
##
## The band and not the frame: the HUD, the prompt and the unlit half of the plate are the
## same in all three, and three copies of them in a column push the only thing being compared
## down to a third of the picture.
func _stitch(pages: int) -> void:
	var imgs: Array = []
	for k in pages:
		var f: String = OUT + "IsoSize_%d.png" % k
		if not FileAccess.file_exists(f):
			return
		var im := Image.load_from_file(ProjectSettings.globalize_path(f))
		if im == null:
			return
		imgs.append(im)
	# fractions of the frame, so this survives the capture being taken at another size
	var band_top := 0.20
	var band_h := 0.42
	var w2: int = int(imgs[0].get_width())
	var h2: int = int(round(float(imgs[0].get_height()) * band_h))
	var out := Image.create(w2, h2 * imgs.size(), false, Image.FORMAT_RGBA8)
	for k in imgs.size():
		var im: Image = imgs[k]
		var y0: int = int(round(float(im.get_height()) * band_top))
		out.blit_rect(im, Rect2i(0, y0, w2, h2), Vector2i(0, k * h2))
	out.save_png(OUT + "IsoSize_all.png")
	print("STITCHED %d pages -> IsoSize_all.png" % imgs.size())

## Clear a room, stand the hero at the front of it, and line the page's creatures up behind
## her shortest-first. Writes the model's fields directly on purpose — this is a rig for
## looking at art, not a game state anything is expected to be playable from.
func _stage(tv: TraversalIso, mine: Array) -> void:
	var w: int = tv.w
	var mid: int = int(tv.h / 2) * w + int(w / 2)
	for dy in range(-4, 5):
		for dx in range(-5, 6):
			var c: int = mid + dy * w + dx
			if c >= 0 and c < tv.enc.size():
				tv.enc[c] = TraversalIso.EMPTY
				tv.seen[c] = true
				tv.room_of[c] = 0
				tv.walked[c] = 0
	tv.pos = mid + 3 * w
	tv.walked[tv.pos] = 1
	# Nothing else on the floor: this rig is about ONE comparison and a market stall in the
	# frame is a second thing to look at.
	tv.mons = []
	tv.enemy_of = {}
	tv.chest_of = {}
	tv.sites = []
	tv.shrine = -1
	# Two tiles apart on both axes. At one tile the wide paintings overlap each other and
	# a row meant to compare heights becomes a pile — which is the same reason the floor
	# itself never stands two things on one tile.
	for k in mine.size():
		var col: int = k % 4
		var row: int = int(k / 4)
		var c2: int = mid + (row * 2 - 3) * w + (col * 2 - 3)
		if c2 < 0 or c2 >= tv.enc.size() or c2 == tv.pos:
			continue
		# Stood on TILES rather than sent walking. A wanderer is only drawn while it is in
		# sight and `ISO_SIGHT` is 2, so a row of twelve would be a row of two — and the
		# eight the hero could see would be standing on top of her. A cast tile is drawn
		# wherever it is seen, through the same `_foe_role` lookup and the same sizing.
		tv.enc[c2] = Traversal.Enc.COMBAT
		tv.enemy_of[c2] = String(mine[k])
		tv.seen[c2] = true
