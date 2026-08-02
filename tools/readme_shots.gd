## Build the README's screenshot strip from the capture harness's output.
##
## `tools/screenshots.gd` writes 25 PNGs at the shipped 1280x720 into `user://shots/`.
## Those are a DIAGNOSTIC set — one per screen, including the three terrain variants and
## the two combat poses — and committing all of them at full size would put ~8MB of
## near-duplicate pictures in the repo. This picks the handful the README actually shows,
## downsamples them to the width GitHub renders at, and writes them into
## `docs/screenshots/` where the README can reference them.
##
## Kept as a tool rather than done by hand once, for the same reason `ART_ASSETS.md` is
## generated: the pictures in the README are a claim about what the game looks like now,
## and a claim nobody can cheaply re-check is one that quietly goes stale. Re-run both
## steps after anything visual lands.
##
## Output is **WebP at 0.95**, not PNG. These are painted backdrops with soft gradients,
## which is the worst case for a lossless encoder and the best case for a lossy one: the
## same seven pictures are 4.1MB as PNG and 0.6MB as WebP. 0.95 rather than the usual
## 0.85 because half of them are dense UI text at half size, and that is where a lossy
## encoder shows first — checked by decoding one back and reading it, not by trusting the
## number. Nothing in the game loads these; they exist for GitHub, which renders WebP.
##
## Needs a real GL context for step one only; this step is pure image work and runs
## headless:
##   godot --rendering-driver opengl3 res://tools/Screenshots.tscn   # under Xvfb
##   godot --headless --script tools/readme_shots.gd
extends SceneTree

const SRC := "user://shots/"
const DST := "res://docs/screenshots/"

## The hero image spans the README's full content column; the rest sit two to a row in
## a table, so they are rendered at half the width and no more. Both numbers are the
## RENDERED width doubled, so the strip stays sharp on a HiDPI display.
const HERO_W := 1280
const GRID_W := 960
const QUALITY := 0.95

## capture -> width. Deliberately a short list: a README is a shop window, not the
## screenshot harness's index. Each row here earns its place by showing a different
## part of the loop, which is why neither combat pose appears twice and why the three
## extra iso terrains are absent — they differ by texture, and the reader cannot tell
## that is the subject.
##
## The lead image is the BOSS fight, not the group fight it started as: a named finale
## looming over the frame under a header that says BOSS is the one frame that carries
## the whole pitch — a dungeon you chose, with an end you were told about (D143). Two
## ember hounds are a nicer picture of the *layout* and a worse picture of the game.
const WANTED := [
	["CombatBoss", HERO_W],
	["ZoneView", GRID_W],
	["IsoRunExplored", GRID_W],
	["CombatHover", GRID_W],
	["Chest", GRID_W],
	["Collection", GRID_W],
	["Powers", GRID_W],
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var missing: Array[String] = []
	var total := 0
	for row in WANTED:
		var name := String(row[0])
		var want_w := int(row[1])
		var src := SRC + name + ".png"
		if not FileAccess.file_exists(src):
			missing.append(name)
			continue
		var img := Image.load_from_file(ProjectSettings.globalize_path(src))
		if img == null:
			missing.append(name)
			continue
		if img.get_width() > want_w:
			# LANCZOS, not the default bilinear: these are downsamples of text and
			# 1px frame edges, and bilinear turns a carved border into a grey smudge
			# at half size — which would make the frame kit look like the thing it
			# was written to stop looking like (D83).
			var want_h := int(round(float(img.get_height()) * float(want_w) / float(img.get_width())))
			img.resize(want_w, want_h, Image.INTERPOLATE_LANCZOS)
		var out := ProjectSettings.globalize_path(DST + name + ".webp")
		var err := img.save_webp(out, true, QUALITY)
		if err != OK:
			push_error("readme_shots: could not write %s (%d)" % [out, err])
			continue
		total += int(FileAccess.get_file_as_bytes(out).size())
		print("  %-16s %dx%d" % [name, img.get_width(), img.get_height()])
	if not missing.is_empty():
		push_error("readme_shots: no capture for %s — run tools/Screenshots.tscn first"
			% ", ".join(missing))
	print("README SHOTS: %d files, %.1f MB -> %s" % [
		WANTED.size() - missing.size(), float(total) / 1048576.0,
		ProjectSettings.globalize_path(DST)])
	quit(1 if not missing.is_empty() else 0)
