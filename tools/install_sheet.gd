## Installer for icon SETS delivered as one gridded sheet.
##
##   godot --headless --script tools/install_sheet.gd -- symbols <sheet.png> [--dry]
##   godot --headless --script tools/install_sheet.gd -- intents <sheet.png>
##   godot --headless --script tools/install_sheet.gd -- powers <sheet.png>
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
##
## **`--cells=` is for the sheet that came back with the right pictures in the wrong
## boxes.** Asked for 21 glyphs and 4 empty cells, a generator will hand back 25
## glyphs — the 21, plus four it invented — and every target after the first insert
## is then reading the cell next door. The set is not wrong and re-rolling it throws
## away 21 good drawings to fix a counting mistake, so instead the caller says which
## source cell each target comes from, in target order:
##
##   ... -- symbols sheet.png --cells=0,1,2,5,6,7,8,11,9,10,13,14,15,16,17,18,19,21,22,23,24
##
## It is a hand-made list read off the sheet by eye, which is why it is an argument
## and not a table in here: the next misaligned sheet is misaligned differently, and
## a stored permutation would be right once and silently wrong afterwards. The
## mapping is printed either way — check it (D112).
##
## **`--only=` is for re-rolling PART of a set**, which is what happens once a sheet
## has landed and two of its twenty-one glyphs turn out to be unreadable. It restricts
## the target list, and the grid is then sized for what is left — so two names means a
## 2x1 sheet, not a 5x5 with twenty-three cells to leave empty. It refuses a name it
## has no target for rather than installing the subset it recognised (D117).
##
## Re-rolling the whole sheet to fix two cells is the alternative and it is worse: the
## reason these tiers are sheets at all is that the SET has to be mutually
## distinguishable, and once nineteen are on disk the survivors are the reference. A
## fresh sheet of twenty-one throws away nineteen good drawings.
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
	# Taller than they are wide, because these are standing figures anchored by their
	# feet — a square canvas would centre a person in it and `iso_run.gd` positions
	# sprites by their bottom edge, so the standing point would float.
	"iso_figures": [0, false],
	"iso_furniture": [0, false],
}

## Non-square canvases, by set name. `SETS` carries one number because every set had
## one until Tier 8; rather than widen four rows that do not need it, the exceptions
## live here.
const TALL := {
	"iso_figures": Vector2i(128, 192),
	"iso_furniture": Vector2i(128, 192),
}

## Sets whose subject STANDS on something, so it is anchored to the bottom of its
## canvas rather than centred in it.
##
## Every set here until Tier 8 was an icon — a symbol, a telegraph, a sigil — and an
## icon is centred, so this file passed `anchor_bottom: false` to `Cut.cut` and had no
## reason to think about it. An isometric figure is not an icon: `iso_run.gd` places
## sprites by their BOTTOM EDGE, so a figure centred on a 128x192 canvas stands on
## empty pixels and hovers by however much margin the trim left above its head.
##
## `install_cutouts.gd` already knew this and passes `true` for the `enemies` family,
## which is why the thirty-five combat plates measure 0.0% empty space below the feet.
## The two tools disagreed only because no bottom-anchored set had ever come in on a
## sheet before (D122).
const FOOTED := ["iso_figures", "iso_furniture"]

var _dry := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	_dry = args.has("--dry")
	var positional: Array[String] = []
	var cols := 0
	var rows := 0
	var cells: Array[int] = []
	var only: Array[String] = []
	for a in args:
		var s := String(a)
		if s.begins_with("--only="):
			for n in s.trim_prefix("--only=").split(",", false):
				only.append(String(n).get_file().get_basename())
		elif s.begins_with("--cols="):
			cols = int(s.trim_prefix("--cols="))
		elif s.begins_with("--rows="):
			rows = int(s.trim_prefix("--rows="))
		elif s.begins_with("--cells="):
			for c in s.trim_prefix("--cells=").split(",", false):
				cells.append(int(c))
		elif not s.begins_with("--"):
			positional.append(s)
	if positional.size() < 2 or not SETS.has(positional[0]):
		print("usage: -- <%s> <sheet.png> [--only=a,b] [--cols=N] [--rows=N] [--cells=i,j,k...] [--dry]" % "|".join(SETS.keys()))
		quit(2)
		return

	var set_name: String = positional[0]
	var sheet_path: String = positional[1]
	var targets := _ids(set_name)      # ordered [out_path, label]
	if not only.is_empty():
		var kept: Array = []
		var unknown := only.duplicate()
		for t in targets:
			var stem := String(t[0]).get_file().get_basename()
			if only.has(stem):
				kept.append(t)
				unknown.erase(stem)
		# Refused, not ignored: a typo in `--only` would otherwise install a SUBSET of
		# what was asked for and report success, which is the same silent-partial
		# failure the whole positional contract is guarded against.
		if not unknown.is_empty():
			print("--only names %s, which %s has no target for. Valid: %s" % [
				", ".join(unknown), set_name,
				", ".join(targets.map(func(t): return String(t[0]).get_file().get_basename()))])
			quit(2)
			return
		targets = kept
		print("--only: %d of %s's targets, so the grid below is sized for those" % [
			targets.size(), set_name])
	var canvas: Vector2i = TALL.get(set_name, Vector2i.ONE * int(SETS[set_name][0]))
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
	if not cells.is_empty():
		# Refused rather than padded or truncated: a permutation one entry short is a
		# whole set shifted by one from that point on, which is the exact failure this
		# argument exists to undo.
		if cells.size() != targets.size():
			print("--cells lists %d cells and %s needs %d, in target order" % [
				cells.size(), set_name, targets.size()])
			quit(2)
			return
		for c in cells:
			if c < 0 or c >= cols * rows:
				print("--cells names cell %d, which is outside a %dx%d grid" % [c, cols, rows])
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
		var src: int = cells[i] if not cells.is_empty() else i
		var cx := src % cols
		var cy := src / cols
		var cell := sheet.get_region(Rect2i(cx * cw, cy * ch, cw, ch))
		var note := Cut.cut_mono(cell, canvas) if mono \
			else Cut.cut(cell, canvas, set_name in FOOTED)
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
		# Two columns, one row per figure: LEFT faces the camera (`_s`), RIGHT is the
		# same figure from behind (`_n`). Emitted as a pair because the reader is
		# row-major like every other sheet here, so the caller passes `--cols=2`.
		"iso_figures":
			out.append(["iso/hero_s.png", "hero, facing you"])
			out.append(["iso/hero_n.png", "hero, from behind"])
			for fam in Balance.ISO_FAMILIES:
				out.append(["iso/mon_%s_s.png" % fam, "%s, facing you" % fam])
				out.append(["iso/mon_%s_n.png" % fam, "%s, from behind" % fam])
			for i in Balance.ISO_WANDERERS:
				out.append(["iso/wander_%d_s.png" % i, "wanderer %d, facing you" % i])
				out.append(["iso/wander_%d_n.png" % i, "wanderer %d, from behind" % i])
		# The three fight tiers come FIRST, so the three that have to read as escalating
		# sit next to each other on the sheet and are drawn against each other.
		"iso_furniture":
			for e in [["combat", "ordinary fight"], ["elite", "harder fight"],
					["boss", "the floor's boss"], ["shop", "merchant's stall"],
					["rest", "campfire"], ["event", "rune-stone"],
					["treasure", "shut chest"]]:
				out.append(["iso/%s.png" % String(e[0]), String(e[1])])
	# `nodes`, `tiles` and `dice` used to be here — the graph map's icons, the dice
	# track's, and six die faces. All three models went in D94 and the manifest stopped
	# asking for the art in D111. An installer for files nothing loads is a way to
	# spend an afternoon painting a screen that does not exist.
	return out
