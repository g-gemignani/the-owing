## One-shot installer for painted dungeon backdrops.
##
## Takes generated images with human filenames and puts them where
## `PixelArt.battle_art()` will actually find them: `assets/art/bg_<dungeon_id>.png`
## at the shipped 1280x720.
##
## Every target id is checked against `Balance.DUNGEONS` before anything is written.
## The filename IS the wiring here — a backdrop named `bg_rot_gardgens.png` (the
## source file carried that typo) silently loads nothing and the dungeon keeps its
## 16x16 fallback tile, which is indistinguishable from "the art was never made".
##
## Run: godot --headless --script tools/install_backdrops.gd -- <src_dir>
##
## **It installs what the directory HAS, not what the table lists.** It used to walk
## the table and print MISS for every row the folder did not answer, which was right
## exactly once — for the single delivery of nine that the table was written from.
## A re-roll is one or three files, and against the old loop that read as six failures
## and an exit code of 1 (D122). The end-of-run report is what catches an incomplete
## set, and it reads `Balance.DUNGEONS` rather than this table, so nothing is lost by
## letting a partial folder be a partial folder.
extends SceneTree

## source basename (without extension) -> dungeon id, for the ones that DIFFER. A file
## already named for its dungeon needs no row here and never did: the fallback below
## is identity, checked against `Balance.DUNGEONS` like everything else. This table is
## the record of one batch of human filenames, not the list of what may be installed —
## a re-roll should just be called `abyssal_stair.png` and skip it entirely.
const MAP := {
	"foundry": "foundry",
	"ember road": "ember_road",
	"slag pits": "slag_pits",
	"fungal deep": "fungal_deep",
	"rot gardgens": "rot_gardens",      # source typo; the id is the truth
	"sunken vault": "sunken_vault",
	"drowned market": "drowned_market",
	"maw": "the_maw",
	"abyssal stairs": "abyssal_stair",   # source is plural; the id is singular
}

const OUT_DIR := "res://assets/art/"
const W := 1280
const H := 720

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0] if args.size() > 0 else ""
	if src == "":
		print("usage: -- <src_dir>")
		quit(2)
		return
	if not src.ends_with("/"):
		src += "/"

	var sources := _sources(src)
	if sources.is_empty():
		print("no .png in %s" % src)
		quit(2)
		return

	var wrote := 0
	var failed := 0
	for base in sources:
		# The table first, then the file's own name. An unlisted basename that IS a
		# dungeon id is the normal case for anything generated after the first batch.
		var did: String = MAP.get(base, base)
		if not (did in Balance.DUNGEONS):
			print("FAIL '%s' names no dungeon — add a row to MAP or rename the file. Refusing to guess." % base)
			failed += 1
			continue
		var from: String = src + String(base) + ".png"
		var img := Image.load_from_file(from)
		if img == null:
			print("FAIL could not read %s" % from)
			failed += 1
			continue
		var was := "%dx%d" % [img.get_width(), img.get_height()]
		if img.get_width() != W or img.get_height() != H:
			# LANCZOS: these are smooth paintings, not pixel art
			img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		var to: String = OUT_DIR + "bg_" + did + ".png"
		var err := img.save_png(to)
		if err != OK:
			print("FAIL writing %s (%d)" % [to, err])
			failed += 1
			continue
		print("  bg_%-16s %s -> %dx%d" % [did + ".png", was, W, H])
		wrote += 1

	# Report what is STILL missing, so a partial delivery cannot read as a complete one.
	var missing: Array[String] = []
	for did in Balance.DUNGEONS:
		if not FileAccess.file_exists(OUT_DIR + "bg_" + did + ".png"):
			missing.append(did)
	print("read %d source(s), wrote %d, failed %d" % [sources.size(), wrote, failed])
	if missing.is_empty():
		print("every dungeon now has a painted backdrop")
	else:
		print("STILL MISSING (%d): %s" % [missing.size(), ", ".join(missing)])
	quit(1 if failed > 0 else 0)

## Every .png basename in the folder, sorted. Sorted so the log reads the same twice
## running — `DirAccess` hands files back in whatever order the filesystem stored them,
## and a mapping report you cannot diff against the last run is a report nobody checks.
func _sources(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		print("cannot open %s" % dir_path)
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.to_lower().ends_with(".png"):
			out.append(f.get_basename())
		f = d.get_next()
	out.sort()
	return out
