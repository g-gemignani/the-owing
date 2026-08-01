## Contact sheet builder — packs a directory of PNGs into one grid image so a pile of
## art can be judged at a glance instead of opened file by file.
##
## A diagnostic, not shipped. Exists because "which of these 26 monsters reads at tile
## size?" is unanswerable one file at a time, and this repo has a standing rule that
## art direction is judged by looking (D56).
##
## Run: godot --headless --script tools/contact_sheet.gd -- <outdir> <dir> [dir...]
extends SceneTree

const DEFAULT_CELL := 128   ## each thumbnail is drawn into a CELL x CELL box
const DEFAULT_COLS := 8
const PAD := 6

static var cell := DEFAULT_CELL
static var cols := DEFAULT_COLS

func _init() -> void:
	var args: Array = []
	# `--cell=420 --cols=2` for comparing whole screens rather than sprites: at 128 a
	# 1280x720 capture is too small to judge a floor plan by.
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--cell="):
			cell = maxi(32, int(s.substr(7)))
		elif s.begins_with("--cols="):
			cols = maxi(1, int(s.substr(7)))
		else:
			args.append(s)
	if args.size() < 2:
		print("usage: contact_sheet.gd -- [--cell=N] [--cols=N] <outdir> <dir> [dir...]")
		quit(1)
		return
	var outdir: String = args[0]
	DirAccess.make_dir_recursive_absolute(outdir)
	for i in range(1, args.size()):
		_sheet(args[i], outdir)
	quit()

func _sheet(dir: String, outdir: String) -> void:
	var files := _pngs(dir)
	if files.is_empty():
		print("EMPTY ", dir)
		return
	files.sort_custom(_natural_less)
	var rows := int(ceil(float(files.size()) / float(cols)))
	var sheet := Image.create(cols * (cell + PAD) + PAD, rows * (cell + PAD) + PAD,
		false, Image.FORMAT_RGBA8)
	# a mid grey, so both dark art and light art are visible against it
	sheet.fill(Color(0.22, 0.22, 0.26, 1.0))
	for i in files.size():
		var img := Image.new()
		if img.load(files[i]) != OK:
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		# fit inside the cell, preserving aspect — these packs mix 256x512 with 1024x1024
		var s: float = minf(float(cell) / float(img.get_width()),
			float(cell) / float(img.get_height()))
		var w := maxi(1, int(float(img.get_width()) * s))
		var h := maxi(1, int(float(img.get_height()) * s))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		var col := i % cols
		var row := int(i / cols)
		var at := Vector2i(PAD + col * (cell + PAD) + (cell - w) / 2,
			PAD + row * (cell + PAD) + (cell - h) / 2)
		# blend, NOT blit: blit_rect COPIES alpha, so every transparent pixel punched a
		# hole through the backing colour and the first sheet came out looking like a
		# grid of white boxes — which nearly got read as "this art has no alpha".
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, Vector2i(w, h)), at)
	var name := dir.trim_suffix("/").get_file()
	var path := outdir.path_join("sheet_%s.png" % name)
	sheet.save_png(path)
	print("SHEET %-28s %2d files -> %s" % [name, files.size(), path])
	for i in files.size():
		print("   %2d %s" % [i, files[i].get_file()])

func _pngs(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		print("NODIR ", dir)
		return out
	for f in d.get_files():
		if f.to_lower().ends_with(".png"):
			out.append(dir.path_join(f))
	return out

## "boss_10" must sort after "boss_9", which a plain string compare gets wrong.
func _natural_less(a: String, b: String) -> bool:
	return _key(a) < _key(b)

func _key(p: String) -> String:
	var f := p.get_file()
	var out := ""
	var num := ""
	for i in f.length():
		var c := f[i]
		if c >= "0" and c <= "9":
			num += c
		else:
			if num != "":
				out += num.pad_zeros(6)
				num = ""
			out += c
	if num != "":
		out += num.pad_zeros(6)
	return out
