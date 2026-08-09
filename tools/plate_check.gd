## Composite every painted cutout over flat magenta and write one sheet per family.
##
## A diagnostic, not shipped. It exists because of the one sentence D199 had to learn the
## hard way and D218 had to learn again: **a cutout can only be judged against something
## brighter than it.** `combat.gd` draws an enemy over a dark painted corridor, so a hole in
## a chest reads as shadow and a bite out of a wing reads as a wing that shape. Put the same
## alpha on flat magenta and it is a window.
##
## This is the check that was missing. D195 fixed eight enclosed pockets, D199 repainted six
## eaten plates, and both times the damage was found because somebody happened to be looking
## at the right picture — there was no picture the project produced on purpose. The moth's
## wings, the forge-hound's hind leg and the brood-mother's abdomen survived both passes and
## shipped, and were reported by a player, not by a tool.
##
##   godot --headless --script tools/plate_check.gd            # every family
##   godot --headless --script tools/plate_check.gd -- enemies
##   godot --headless --script tools/plate_check.gd -- --cell=440 grave_moth forge_hound
##
## Output: user://plates/<family>.png, printed as a real path on exit. Look at it. Anything
## magenta INSIDE a silhouette is damage; magenta around it is the cutout doing its job.
##
## Pair it with `tools/refill_pockets.gd`, which lists candidates and can restore the ones
## that still carry paint. This tool decides nothing and measures nothing — it is the eye.
extends SceneTree

const OUT := "user://plates/"
const FAMILIES := ["enemies", "relics", "powers", "cards"]
## Big enough that a bite the size of a finger is obvious. At 220 the forge-hound's severed
## hind leg reads as a shadow between two legs; at 380 it is plainly a gap.
const CELL := 380
const COLS := 5

## `--paired` draws each plate TWICE: as shipped over magenta, and again with its alpha
## ignored. That second panel is the whole painting the generator delivered, because the
## pipeline only ever wrote the alpha channel (D218) — so the pair answers, in one look, the
## only question that matters about a suspect plate: **is this shape missing, or was it never
## drawn?**
##
## It exists because that question was answered wrong twice from the magenta panel alone. The
## Deep Warden holds two tridents and the shipped plate has both heads cut off; the Drowned
## Thrall's left arm is severed. Both were called "painted drips" on the strength of the
## magenta render, and both are complete in the paint underneath — a restore away, and
## instead they shipped twice more (D221).
var paired := false

func _init() -> void:
	var cell := CELL
	var families: Array[String] = []
	var only: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cell="):
			cell = maxi(64, int(a.substr(7)))
		elif a == "--paired":
			paired = true
		elif a in FAMILIES:
			families.append(a)
		elif not a.begins_with("--"):
			only.append(a)
	if families.is_empty():
		families.assign(FAMILIES)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for fam in families:
		_sheet(fam, cell, only)
	print("SHEETS: %s" % ProjectSettings.globalize_path(OUT))
	quit()

func _sheet(family: String, cell: int, only: Array[String]) -> void:
	var dir := "res://assets/art/%s/" % family
	var d := DirAccess.open(ProjectSettings.globalize_path(dir))
	if d == null:
		return
	var names: Array[String] = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.to_lower().ends_with(".png") \
				and (only.is_empty() or f.get_basename() in only):
			names.append(f)
		f = d.get_next()
	names.sort()
	if names.is_empty():
		return
	# In paired mode each plate takes two cells side by side, so half as many fit per row.
	var per: int = 2 if paired else 1
	var cols: int = maxi(1, mini(COLS, names.size() * per) / per)
	var rows := int(ceil(float(names.size()) / float(cols)))
	var sheet := Image.create(cols * cell * per, rows * cell, false, Image.FORMAT_RGBA8)
	# Pure magenta, and pure on purpose: it is the one hue none of this art uses, which is
	# the same reasoning D200 keyed the source sheets on.
	sheet.fill(Color(1, 0, 1, 1))
	for i in names.size():
		var tex := load(dir + names[i]) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var s := minf(float(cell) / float(img.get_width()),
			float(cell) / float(img.get_height()))
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)),
			Image.INTERPOLATE_LANCZOS)
		var ox := (i % cols) * cell * per + int((cell - img.get_width()) / 2.0)
		var oy := int(i / cols) * cell + int((cell - img.get_height()) / 2.0)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(ox, oy))
		if not paired:
			continue
		# ...and the same pixels with the alpha thrown away. `blit_rect` rather than
		# `blend_rect`, or the panel would composite over magenta again and show nothing.
		var bare := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				bare.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
		sheet.blit_rect(bare, Rect2i(Vector2i.ZERO, bare.get_size()),
			Vector2i(ox + cell, oy))
	var path := OUT + family + ".png"
	if sheet.save_png(ProjectSettings.globalize_path(path)) != OK:
		print("FAILED writing %s" % path)
		return
	print("  %-8s %2d plates, %dx%d" % [family, names.size(), cols, rows])
