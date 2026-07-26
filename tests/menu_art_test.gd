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
	# Headless defaults to a square 1280x1280 viewport; measure the shipped window.
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	MetaState.path_prefix = "t_menuart_"
	MetaState.slot = 0
	MetaState.new_save()
	# Screens with no state bail out by NAVIGATING, which in a harness replaces the
	# test scene and hangs the await forever. Give them a live run first.
	GameState.reset_run_progress()
	GameState.select_dungeon(Balance.DUNGEONS[0])
	var d0: Array[CardData] = []
	for cid in MetaState.collection:
		for i in int(MetaState.collection[cid]["count"]):
			d0.append((load(MetaState.CATALOG[cid]) as CardData).duplicate())
	GameState.enter_dungeon(d0)
	var z0 := Balance.zone_of(Balance.DUNGEONS[0])
	GameState.current_zone = z0.id if z0 != null else Balance.ZONES[0]
	GameState.pending = {"type": GameState.NodeType.SHOP, "row": 1, "col": 0, "cleared": false}
	GameState.shop_stock = []

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

	await _painted_ui_is_legible()
	await _battle_backdrops_are_legible()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("MENU ART TEST: PASS (title scrim, painted buttons, battle backdrops, all legible)")
	else:
		print("MENU ART TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## --- painted button frames (D48) -------------------------------------------
##
## The parchment in the button art measures 0.86 luminance. White text on it is
## 1.2:1 — flatly invisible — so the ink must be dark. And the carved border is
## drawn 1:1 at 40px, so a button shorter than that squashes its own frame; four
## screens had 31px inline buttons when the art first went in.
func _painted_ui_is_legible() -> void:
	if not ResourceLoader.exists(UITheme.BUTTON_ART):
		_fails += 1; print("FAIL button art missing: %s" % UITheme.BUTTON_ART); return
	if not ResourceLoader.exists(UITheme.PANEL_ART):
		_fails += 1; print("FAIL panel art missing")

	# ink against the measured parchment
	var ink: Color = UITheme.INK
	var ink_l: float = 0.2126 * ink.r + 0.7152 * ink.g + 0.0722 * ink.b
	var img := Image.load_from_file(UITheme.BUTTON_ART)
	var parch := 0.0
	if img != null:
		var w := img.get_width()
		var h := img.get_height()
		var tot := 0.0
		var n := 0
		for y in range(int(h * 0.35), int(h * 0.65)):
			for x in range(int(w * 0.35), int(w * 0.65)):
				var c := img.get_pixel(x, y)
				tot += (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * c.a
				n += 1
		parch = tot / maxf(1.0, float(n))
	var contrast: float = (parch + 0.05) / (ink_l + 0.05)
	print("  button ink on parchment: %.1f:1" % contrast)
	if contrast < 4.5:
		_fails += 1
		print("FAIL button text is %.1f:1 on the parchment — need 4.5:1" % contrast)

	# the nine-slice must not exceed the shortest button any screen builds
	var need: int = UITheme.min_button_height()
	for name in ["MainMenu", "Overworld", "DeckBuilder", "Collection", "Shop",
			"Powers", "SaveSlots", "Encounter"]:
		var path := "res://scenes/%s.tscn" % name
		if not ResourceLoader.exists(path):
			continue
		var inst = (load(path) as PackedScene).instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		var framed := 0
		var short := 0
		for b in _buttons(inst):
			if not b.visible:
				continue
			if b.get_theme_stylebox("normal") is StyleBoxTexture:
				framed += 1
				if b.size.y < float(need) - 0.5:
					short += 1
		if framed == 0:
			_fails += 1; print("FAIL %s has no painted buttons at all" % name)
		if short > 0:
			_fails += 1
			print("FAIL %s has %d buttons under %dpx — the carved frame squashes" % [
				name, short, need])
		inst.queue_free()
		await get_tree().process_frame

## --- battle backdrops -------------------------------------------------------
func _battle_backdrops_are_legible() -> void:
	var painted := 0
	for did in Balance.DUNGEONS:
		var art := PixelArt.battle_art(did)
		if art == null:
			continue
		painted += 1
		var img := Image.load_from_file("res://assets/art/bg_%s.png" % did)
		if img == null:
			_fails += 1; print("FAIL %s backdrop unreadable" % did); continue
		# white combat text sits across the top; check the worst pixel there,
		# after the dim the backdrop is drawn with
		var w := img.get_width()
		var h := img.get_height()
		var worst := 0.0
		# only where text actually sits: the held part of the scrim band
		for y in range(0, int(h * PixelArt.BATTLE_SCRIM_HOLD), 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				# art * dim, then the text-band scrim fading out across the band
				var fy: float = float(y) / float(h)
				var a: float = PixelArt.BATTLE_SCRIM
				if fy > PixelArt.BATTLE_SCRIM_HOLD:
					var t: float = (fy - PixelArt.BATTLE_SCRIM_HOLD) \
						/ (PixelArt.BATTLE_SCRIM_BAND - PixelArt.BATTLE_SCRIM_HOLD)
					a = PixelArt.BATTLE_SCRIM * maxf(0.0, 1.0 - clampf(t, 0.0, 1.0))
				var l: float = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) \
					* PixelArt.BATTLE_DIM * (1.0 - a)
				worst = maxf(worst, l)
		var contrast: float = 1.05 / (worst + 0.05)
		print("  %s backdrop: worst-pixel contrast for white text %.1f:1" % [did, contrast])
		if contrast < 3.0:
			_fails += 1
			print("FAIL %s backdrop is too bright behind the combat text (%.1f:1)" % [
				did, contrast])
	if painted == 0:
		_fails += 1; print("FAIL no dungeon has a painted battle backdrop")

	# and it must be LINEAR, or a painted image aliases under the global NEAREST
	var bd := PixelArt.battle_backdrop("crypt", Balance.ZONES[0])
	var art_layer: TextureRect = null
	for c2 in bd.get_children():
		if c2 is TextureRect and (c2 as TextureRect).texture is CompressedTexture2D:
			art_layer = c2
	if art_layer == null:
		_fails += 1; print("FAIL battle backdrop has no painted layer")
	elif art_layer.texture_filter != CanvasItem.TEXTURE_FILTER_LINEAR:
		_fails += 1; print("FAIL battle backdrop is not LINEAR-filtered")
	if bd.get_child_count() < 3:
		_fails += 1; print("FAIL battle backdrop has no text scrim bands")
	if bd != null:
		bd.free()
	# a dungeon with no art must still get something rather than a black screen
	var fallback := PixelArt.battle_backdrop("no_such_dungeon", Balance.ZONES[0])
	if fallback == null:
		_fails += 1; print("FAIL a dungeon without art gets no backdrop at all")
	else:
		fallback.free()

func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out

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
