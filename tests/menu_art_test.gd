## Runtime test: the title screen's painted backdrop is legible.
##
## A scene test, not a `--script` one, for two reasons: the backdrop layers only
## exist once the menu has been built, and reading UI.* from a script run pulls in
## the UITheme autoload, which is not registered there — the compile error is
## silent and the suite still reports a pass.
##
## What it guards: white menu text over a generated illustration measured 3.7:1
## contrast before a scrim was added, under the 4.5:1 needed to read comfortably,
## with highlights bright enough to swallow a glyph outright.
## Run: godot --headless res://tests/MenuArtTest.tscn
extends Node

var _fails := 0

func _ready() -> void:
	MetaState.path_prefix = "t_menuart_"

	var inst := (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- the backdrop is the illustration, layered under a scrim ---
	var layers: Array[TextureRect] = []
	for c in inst.get_children():
		if c is TextureRect:
			layers.append(c as TextureRect)
	if layers.size() < 2:
		_fails += 1
		print("FAIL title screen has %d backdrop layers, expected art + scrim" % layers.size())
	for t in layers:
		if t.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
			_fails += 1
			print("FAIL backdrop layer is not LINEAR — smooth art goes jagged under NEAREST")
		if t.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			_fails += 1
			print("FAIL backdrop layer eats mouse input meant for the menu")

	# --- the menu stays inside the part of the scrim held at full opacity ---
	if UI.MENU_WIDTH > UI.SCRIM_HOLD:
		_fails += 1
		print("FAIL menu is %.2f wide but the scrim only covers %.2f" % [
			UI.MENU_WIDTH, UI.SCRIM_HOLD])
	var col: VBoxContainer = _first_vbox(inst)
	if col == null:
		_fails += 1
		print("FAIL no menu column found")
	else:
		var frac: float = col.size.x / maxf(1.0, get_viewport().get_visible_rect().size.x)
		if frac > UI.SCRIM_HOLD + 0.01:
			_fails += 1
			print("FAIL menu column spans %.0f%% of the screen, past the scrim's %.0f%%" % [
				frac * 100.0, UI.SCRIM_HOLD * 100.0])

	# --- worst-pixel contrast, because averages do not read text ---
	var img := Image.load_from_file("res://assets/art/main_menu.jpg")
	if img == null:
		_fails += 1
		print("FAIL cannot read the title art to check contrast")
	else:
		var w := img.get_width()
		var h := img.get_height()
		var worst := 0.0
		for y in range(0, h, 3):
			for x in range(0, int(float(w) * UI.MENU_WIDTH), 3):
				var c := img.get_pixel(x, y)
				var lum: float = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				worst = maxf(worst, lum * (1.0 - UI.SCRIM_ALPHA))
		var contrast: float = 1.05 / (worst + 0.05)
		print("  worst-pixel contrast for white menu text: %.1f:1" % contrast)
		if contrast < 4.5:
			_fails += 1
			print("FAIL title art contrast %.1f:1, need 4.5:1 — raise UI.SCRIM_ALPHA" % contrast)

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("MENU ART TEST: PASS (layered, LINEAR, menu inside the scrim, legible)")
	else:
		print("MENU ART TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _first_vbox(n: Node) -> VBoxContainer:
	if n is VBoxContainer:
		return n as VBoxContainer
	for c in n.get_children():
		var r := _first_vbox(c)
		if r != null:
			return r
	return null

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
