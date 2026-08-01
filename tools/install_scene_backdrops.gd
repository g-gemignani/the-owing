## One-shot installer for the painted NON-COMBAT backdrops.
##
## The sibling of `install_backdrops.gd`, which does the same job for the twelve
## dungeon fight arenas. Same reasoning: the filename IS the wiring, so the mapping
## from "what the generator called it" to "what the loader looks for" is written
## down once, checked, and not retyped per file.
##
## Two things this one does that the dungeon installer does not:
##
## * **Strips the letterbox.** `rest.jpg` came back with a baked black frame all
##   round it. Scaled to 1280x720 that frame becomes part of the picture, and a
##   backdrop with black bars in it reads as a broken render, not as art.
## * **Crops to 16:9 rather than squashing.** 1344x768 is 1.75; the game is 1.78.
##   Resizing straight to 1280x720 stretches every face in the image by 2%.
##
## Run: godot --headless --script tools/install_scene_backdrops.gd -- <src_dir>
## Then: godot --headless --import
extends SceneTree

## source basename (without extension) -> scene backdrop id, as ART_ASSETS Tier 5c
## names them and `PixelArt.scene_art()` looks them up. Written as `bg_<id>.png`.
const MAP := {
	"shop": "shop",
	"rest": "rest",
	"event": "event",
	"treasure": "treasure",
	"victory": "victory",
	"defeat": "defeat",
}

## Tier 5d, the four META-screen backdrops, written as `bg_<id>.png` like the six
## above and resolved by the same `PixelArt.scene_art()`. They are a separate table
## for one reason: a missing source in `MAP` prints MISS and fails the run, which is
## right for the six because they were commissioned and delivered as a set — a MISS
## there means the batch is short and you want to know. These four will land one at a
## time, and a table that fails three ways every time one file arrives is a table
## whose exit code stops meaning anything. Queued only when a source is present, the
## same way the title art is (see `BARE_MAP` below and the note on it).
const META_MAP := {
	"table": "table",
	"reliquary": "reliquary",
	"ledger": "ledger",
	"world": "world",
}

## The same for Tier 5b, the ZONE establishing shots, written as `bg_zone_<id>.png`.
##
## The prefix is not decoration. `foundry` is both a zone (`foundry_zone`) and a
## dungeon, and the generator called the zone painting `foundry.png` — installed
## without the prefix it would have overwritten the Foundry's fight arena, and the
## only symptom would have been one dungeon's combat looking like an establishing
## shot. `barrows` is spelled `burrows` at the source, which is the other half of
## why this table exists: neither name can be trusted to match an id.
const ZONE_MAP := {
	"burrows": "barrows",
	"foundry": "foundry_zone",
	"rot": "rot",
	"deeps": "deeps",
	"beyond": "beyond",
}

## And the title art, which takes NO prefix — it is not a `bg_` file. It rides this
## installer because it is the same job (full-bleed 16:9, opaque, letterbox stripped,
## cropped rather than squashed) and because it had no installer at all: it predates
## them, which is how it ended up the one .jpg in `assets/art/` and off the re-roll
## list until D114. Landing here writes `main_menu.png`; `PixelArt.title_art_path()`
## prefers the PNG, so the swap takes effect on install, and the superseded .jpg is
## deleted below rather than left to shadow it.
const BARE_MAP := {
	"main_menu": "main_menu",
	"title": "main_menu",
}

## Files a successful install supersedes: same stem, older extension.
const SUPERSEDES := {
	"main_menu": ["res://assets/art/main_menu.jpg", "res://assets/art/main_menu.jpg.import"],
}

const OUT_DIR := "res://assets/art/"
const W := 1280
const H := 720
## A letterbox bar is a SOLID BLOCK OF ONE COLOUR, and all three of these say so:
## dark, flat across its width, and the same colour as the outermost row itself.
## Each one alone gets a different image wrong.
##
## * Darkness alone cropped 73 rows of painting off `event.jpg`, whose cavern
##   ceiling measures 0.07 — the same as its own top rows.
## * Flatness alone missed `treasure.png` entirely: its bars carry enough dither to
##   measure a 0.018 range, three times what `rest.jpg`'s clean black frame does.
## * Same-as-the-edge alone would have eaten the top 80 rows of `shop.jpg`, whose
##   dark stonework drifts by less than 0.01 over that distance.
##
## Together they hold on all six sources, and each threshold has a picture behind
## it rather than a round number.
const BAR_MEAN := 0.10     ## darker than any painted content in this set
const BAR_RANGE := 0.030   ## flat across the row, dither allowed
const BAR_DRIFT := 0.012   ## and the same colour as the outermost row

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
	var jobs: Array = []
	for base in MAP:
		jobs.append([base, "bg_" + String(MAP[base])])
	for base2 in ZONE_MAP:
		jobs.append([base2, "bg_zone_" + String(ZONE_MAP[base2])])
	# The title art is optional in any given batch, and so is every other job here —
	# a missing source prints MISS and counts a failure. That is right for the six
	# scene backdrops, which are a set, and wrong for this one, which is normally
	# absent. Only queue it when a source is actually present.
	for base3 in BARE_MAP:
		for ext in [".jpg", ".jpeg", ".png"]:
			if FileAccess.file_exists(src + base3 + ext):
				jobs.append([base3, String(BARE_MAP[base3])])
				break
	# Same rule, same reason, for the four meta-screen backdrops — see `META_MAP`.
	for base4 in META_MAP:
		for ext2 in [".jpg", ".jpeg", ".png"]:
			if FileAccess.file_exists(src + base4 + ext2):
				jobs.append([base4, "bg_" + String(META_MAP[base4])])
				break
	for job in jobs:
		var base: String = job[0]
		var stem: String = job[1]
		var img := Image.new()
		var path := ""
		for ext in [".jpg", ".jpeg", ".png"]:
			if FileAccess.file_exists(src + base + ext):
				path = src + base + ext
				break
		if path == "":
			print("MISS  no source for '%s'" % base)
			failed += 1
			continue
		if img.load(path) != OK:
			print("FAIL  cannot read %s" % path)
			failed += 1
			continue

		var box := _content_rect(img)
		if box != Rect2i(0, 0, img.get_width(), img.get_height()):
			print("      %s: letterbox stripped, content %s of %dx%d" % [
				base, box, img.get_width(), img.get_height()])
		img = img.get_region(_to_aspect(box, float(W) / float(H)))
		img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		var out := ProjectSettings.globalize_path(OUT_DIR + stem + ".png")
		if img.save_png(out) != OK:
			print("FAIL  cannot write %s" % out)
			failed += 1
			continue
		print("OK    %s.png  <- %s" % [stem, path.get_file()])
		wrote += 1
		# An older file with the same stem and a different extension is not harmless:
		# it is a second answer to "where is the title art", and whichever the loader
		# picks, somebody is looking at the wrong picture.
		for dead in SUPERSEDES.get(stem, []):
			if FileAccess.file_exists(String(dead)):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(String(dead)))
				print("      removed superseded %s" % String(dead).get_file())

	print("install_scene_backdrops: %d written, %d failed" % [wrote, failed])
	quit(1 if failed > 0 else 0)

## The picture inside the baked black bars.
func _content_rect(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	# Each scan calibrates against its OWN outermost line, so a top bar and a bottom
	# bar of different colours are both found.
	var top := 0
	var top_ref := _row_mean(img, 0, w)
	while top < h and _bar_row(img, top, w, top_ref):
		top += 1
	var bot := h - 1
	var bot_ref := _row_mean(img, h - 1, w)
	while bot > top and _bar_row(img, bot, w, bot_ref):
		bot -= 1
	var left := 0
	var left_ref := _col_mean(img, 0, h)
	while left < w and _bar_col(img, left, h, left_ref):
		left += 1
	var right := w - 1
	var right_ref := _col_mean(img, w - 1, h)
	while right > left and _bar_col(img, right, h, right_ref):
		right -= 1
	if right <= left or bot <= top:
		return Rect2i(0, 0, w, h)
	return Rect2i(left, top, right - left + 1, bot - top + 1)

func _row_mean(img: Image, y: int, w: int) -> float:
	var tot := 0.0
	var n := 0
	for x in range(0, w, 4):
		tot += img.get_pixel(x, y).get_luminance()
		n += 1
	return tot / maxf(1.0, float(n))

func _col_mean(img: Image, x: int, h: int) -> float:
	var tot := 0.0
	var n := 0
	for y in range(0, h, 4):
		tot += img.get_pixel(x, y).get_luminance()
		n += 1
	return tot / maxf(1.0, float(n))

func _bar_row(img: Image, y: int, w: int, ref: float) -> bool:
	var tot := 0.0
	var lo := 1.0
	var hi := 0.0
	var n := 0
	for x in range(0, w, 4):
		var l := img.get_pixel(x, y).get_luminance()
		tot += l
		lo = minf(lo, l)
		hi = maxf(hi, l)
		n += 1
	var mean: float = tot / maxf(1.0, float(n))
	return mean < BAR_MEAN and hi - lo < BAR_RANGE and absf(mean - ref) < BAR_DRIFT

func _bar_col(img: Image, x: int, h: int, ref: float) -> bool:
	var tot := 0.0
	var lo := 1.0
	var hi := 0.0
	var n := 0
	for y in range(0, h, 4):
		var l := img.get_pixel(x, y).get_luminance()
		tot += l
		lo = minf(lo, l)
		hi = maxf(hi, l)
		n += 1
	var mean: float = tot / maxf(1.0, float(n))
	return mean < BAR_MEAN and hi - lo < BAR_RANGE and absf(mean - ref) < BAR_DRIFT

## The largest centred sub-rect of `box` at the given aspect. Crops the long axis
## rather than scaling it, so nothing in the picture changes shape.
func _to_aspect(box: Rect2i, aspect: float) -> Rect2i:
	var have := float(box.size.x) / float(box.size.y)
	if absf(have - aspect) < 0.001:
		return box
	if have > aspect:
		var nw := int(round(float(box.size.y) * aspect))
		return Rect2i(box.position.x + (box.size.x - nw) / 2, box.position.y, nw, box.size.y)
	var nh := int(round(float(box.size.x) / aspect))
	return Rect2i(box.position.x, box.position.y + (box.size.y - nh) / 2, box.size.x, nh)
