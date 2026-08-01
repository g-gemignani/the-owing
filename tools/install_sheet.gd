## Installer for icon SETS delivered as one gridded sheet.
##
##   godot --headless --script tools/install_sheet.gd -- symbols <sheet.png> [--dry]
##   godot --headless --script tools/install_sheet.gd -- intents <sheet.png>
##   godot --headless --script tools/install_sheet.gd -- powers|nodes|tiles|dice <sheet.png>
##   godot --headless --import
##
## **Why a sheet at all, when `install_cutouts.gd` already installs one file per
## subject.** For these tiers the requirement is not that each icon is good, it is that
## the SET is mutually distinguishable — seven intent telegraphs that all read as "angry
## shape" have failed even if each is individually handsome, and that is the core read
## of the whole combat system (ART.md Tier 1c). Generated one at a time, each request is
## blind to the other six and the third one comes back as a shield again. Generated as
## one image, the model sees the whole set while drawing it, and consistency of hand
## comes free rather than being prompted for.
##
## **The cost is positional assignment, which this project has been bitten by** —
## `PixelArt.enemy_sprite()` hands sprites to archetypes by sort order and needed a
## 12-entry override table to stop bosses inheriting trash-mob faces. The difference
## here is that the order is not implicit: it comes from the same tables in
## `tools/art_manifest.gd` that `ART_PROMPTS.md` prints INTO the prompt, so the order
## asked for and the order installed are one list, and the mapping is printed on every
## run so it can be checked against the sheet rather than trusted.
##
## Cells are matted and trimmed individually, so a subject that is off-centre in its
## cell still lands centred in its file. What that cannot fix is a subject that runs
## OUT of its cell, so a bounding box touching a cell edge is reported: it means the
## generator did not respect the grid and that icon is clipped.
extends SceneTree

const Cut := preload("res://tools/cutout_lib.gd")
## The id lists live in the manifest, which is already the declared source of truth for
## the assets no data file implies. Restating twenty-one symbol names here is the D34
## habit that has cost this project four bugs.
const Manifest := preload("res://tools/art_manifest.gd")

const ART := "res://assets/art/"

## set name -> [canvas size, monochrome?]. The id list comes from `_ids()`.
const SETS := {
	"symbols": [64, true],
	"intents": [96, false],
	"powers": [128, false],
	"nodes": [128, false],
	"tiles": [128, false],
	"dice": [128, false],
}

var _dry := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dry = args.has("--dry")
	var positional: Array[String] = []
	var cols := 0
	var rows := 0
	for a in args:
		var s := String(a)
		if s.begins_with("--cols="):
			cols = int(s.trim_prefix("--cols="))
		elif s.begins_with("--rows="):
			rows = int(s.trim_prefix("--rows="))
		elif not s.begins_with("--"):
			positional.append(s)
	if positional.size() < 2 or not SETS.has(positional[0]):
		print("usage: -- <%s> <sheet.png> [--cols=N] [--rows=N] [--dry]" % "|".join(SETS.keys()))
		quit(2)
		return

	var set_name: String = positional[0]
	var sheet_path: String = positional[1]
	var targets := _ids(set_name)      # ordered [out_path, label]
	var canvas := Vector2i.ONE * int(SETS[set_name][0])
	var mono: bool = bool(SETS[set_name][1])

	var sheet := Cut.load_image(sheet_path)
	if sheet == null:
		print("cannot read %s" % sheet_path)
		quit(2)
		return

	if cols <= 0 and rows <= 0:
		cols = int(ceil(sqrt(float(targets.size()))))
	if cols <= 0:
		cols = int(ceil(float(targets.size()) / float(rows)))
	if rows <= 0:
		rows = int(ceil(float(targets.size()) / float(cols)))
	if cols * rows < targets.size():
		print("a %dx%d grid has %d cells and %s needs %d" % [
			cols, rows, cols * rows, set_name, targets.size()])
		quit(2)
		return

	var cw := sheet.get_width() / cols
	var ch := sheet.get_height() / rows
	print("%s: %d icons from a %dx%d grid of %dx%d cells (sheet %dx%d)" % [
		set_name, targets.size(), cols, rows, cw, ch,
		sheet.get_width(), sheet.get_height()])
	if sheet.get_width() % cols != 0 or sheet.get_height() % rows != 0:
		print("  note: the sheet does not divide evenly; %dx%d px are being ignored at the right/bottom" % [
			sheet.get_width() - cw * cols, sheet.get_height() - ch * rows])

	var wrote := 0
	var failed := 0
	var clipped := 0
	for i in targets.size():
		var rel: String = targets[i][0]
		var label: String = targets[i][1]
		var cx := i % cols
		var cy := i / cols
		var cell := sheet.get_region(Rect2i(cx * cw, cy * ch, cw, ch))
		var note := Cut.cut_mono(cell, canvas) if mono \
			else Cut.cut(cell, canvas, false)
		if note != "":
			print("FAIL  r%dc%d -> %-24s %s" % [cy, cx, rel.get_file(), note])
			failed += 1
			continue
		# A subject touching its own cell edge ran out of the grid the sheet was drawn
		# on, so what landed in the file is a crop, not an icon.
		var box: Rect2i = Cut.last_bbox
		var edge := box.position.x <= 0 or box.position.y <= 0 \
			or box.end.x >= cw or box.end.y >= ch
		var flag := ""
		if edge:
			flag = "  <-- TOUCHES ITS CELL EDGE, probably clipped"
			clipped += 1
		if _dry:
			print("DRY   r%dc%d -> %-26s %-22s %dx%d%s" % [
				cy, cx, rel, label, canvas.x, canvas.y, flag])
			continue
		var to: String = ART + rel
		DirAccess.make_dir_recursive_absolute(Cut.abs_path(to.get_base_dir() + "/"))
		if cell.save_png(Cut.abs_path(to)) != OK:
			print("FAIL  writing %s" % to)
			failed += 1
			continue
		print("  r%dc%d -> %-26s %s%s" % [cy, cx, rel, label, flag])
		wrote += 1

	print("\nwrote %d, failed %d%s" % [wrote, failed,
		", %d touching a cell edge" % clipped if clipped > 0 else ""])
	print("The mapping above is POSITIONAL. Check it against the sheet before committing —")
	print("a set installed one cell out is 21 correct icons on 21 wrong meanings.")
	quit(1 if failed > 0 or clipped > 0 else 0)


## Ordered [relative path, human label] for a set. Same order the prompt asks for,
## because both read this table.
func _ids(set_name: String) -> Array:
	var out: Array = []
	match set_name:
		"symbols":
			for e in Manifest.SYMBOLS:
				out.append(["ui/sym_%s.png" % String(e[0]), String(e[1])])
		"intents":
			for e in Manifest.INTENTS:
				out.append([String(e[0]), String(e[2])])
		"powers":
			for pid in Balance.POWERS:
				var p := Balance.power(pid)
				out.append(["powers/%s.png" % pid, p.name if p != null else pid])
		"nodes":
			for e in Manifest.ENCOUNTERS:
				out.append(["ui/node_%s.png" % String(e[0]), String(e[1])])
		"tiles":
			for e in Manifest.ENCOUNTERS:
				out.append(["ui/tile_%s.png" % String(e[0]), String(e[1])])
		"dice":
			for i in 6:
				out.append(["ui/die_%d.png" % (i + 1), "showing %d" % (i + 1)])
	return out
