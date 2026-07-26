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
extends SceneTree

## source basename (without extension) -> dungeon id
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

	var wrote := 0
	var failed := 0
	for base in MAP:
		var did: String = MAP[base]
		if not (did in Balance.DUNGEONS):
			print("FAIL '%s' is not a dungeon id — refusing to write bg_%s.png" % [did, did])
			failed += 1
			continue
		var from: String = src + String(base) + ".png"
		if not FileAccess.file_exists(from):
			print("MISS %s" % from)
			failed += 1
			continue
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
	print("wrote %d, failed %d" % [wrote, failed])
	if missing.is_empty():
		print("every dungeon now has a painted backdrop")
	else:
		print("STILL MISSING (%d): %s" % [missing.size(), ", ".join(missing)])
	quit(1 if failed > 0 else 0)
