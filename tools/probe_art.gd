## Probe an image pack: reports whether the art has a real alpha channel, and the
## tight bounding box of its visible pixels.
##
## A diagnostic, not shipped. Wiring downloaded art blind is how you end up drawing
## 256x512 white rectangles onto a dark floor and calling it a monster.
##
## Run: godot --headless --script tools/probe_art.gd -- <file-or-dir> [...]
extends SceneTree

const ALPHA_CUT := 0.02

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if DirAccess.dir_exists_absolute(a):
			var d := DirAccess.open(a)
			var files := d.get_files()
			files.sort()
			for f in files:
				if f.to_lower().ends_with(".png"):
					_probe(a.path_join(f))
		else:
			_probe(a)
	quit()

func _probe(path: String) -> void:
	var img := Image.new()
	if img.load(path) != OK:
		print("FAIL load ", path)
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# corner alpha tells us whether transparency exists at all
	var corner := img.get_pixel(0, 0)
	var opaque_px := 0
	var near_white := 0
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	# sample on a grid for speed on 1024x1024, exact enough for a bounding box
	var step: int = maxi(1, int(maxi(w, h) / 512))
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			if c.a > ALPHA_CUT:
				opaque_px += 1
				if c.r > 0.93 and c.g > 0.93 and c.b > 0.93:
					near_white += 1
				minx = mini(minx, x); maxx = maxi(maxx, x)
				miny = mini(miny, y); maxy = maxi(maxy, y)
	var cover := 100.0 * float(opaque_px) / float(maxi(1, (w / step) * (h / step)))
	var whitefrac := 100.0 * float(near_white) / float(maxi(1, opaque_px))
	print("%-46s %4dx%-4d corner_a=%.2f opaque=%5.1f%% nearwhite=%5.1f%% bbox=(%d,%d)-(%d,%d)" % [
		path.get_file(), w, h, corner.a, cover, whitefrac, minx, miny, maxx, maxy])
