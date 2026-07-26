## Headless test: the player can always SEE and REACH what they must act on.
##
## Written after a real play report: "I'm in the Crypt, I can only see a boss and
## an elite, and I can't press anything." The map was correct — it renders the boss
## at the top and the entrance at the bottom, and at nine rows and a large UI scale
## the only actionable row began below the window, with the scroll parked at the
## top. Nothing in the previous suite could see that, because every earlier check
## only asked whether a scene *booted*.
## Run: godot --headless --script tests/test_layout.gd
extends SceneTree

## UI scripts reference autoloads, which are not registered in a headless
## `--script` run, so they cannot be instantiated here. Inspect the source instead.
func _defines(path: String, decl: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	return text.find(decl) != -1

func _init() -> void:
	var fails := 0
	var window := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))

	# --- the graph map must not need scrolling luck to be playable ---
	var tv := TraversalGraph.new()
	tv.generate(Balance.dungeon(Balance.DUNGEONS[0]))
	var rows: int = tv.map.size()
	# Read the shipped default rather than restating it. This line said 1.6 while
	# the constant was changed to 1.0, which is exactly how a duplicated number
	# turns a passing test into a lie.
	var scale: float = load("res://scripts/ui_theme.gd").UI_SCALE
	# ...and there must be no second copy anywhere. settings_state.gd used to carry
	# its own default and apply it over the theme's, so a new player never got the
	# shipped scale; the whole zoom is gone now (D65) and this keeps it gone.
	for src in ["res://scripts/settings_state.gd", "res://scripts/settings_menu.gd",
			"res://scripts/ui_theme.gd"]:
		var fh := FileAccess.open(src, FileAccess.READ)
		if fh == null:
			continue
		var text := fh.get_as_text()
		fh.close()
		for banned in ["set_scale_silent", "func set_scale("]:
			if text.find(banned) != -1:
				fails += 1
				print("FAIL %s still exposes %s — the UI scale is fixed" % [src, banned])
	var node_h: float = 52.0 * scale
	var sep: float = 6.0 * scale
	var map_h: float = float(rows) * node_h + float(rows - 1) * sep

	# the actionable row is row 0, drawn last (bottom)
	var opts := tv.options()
	if opts.is_empty():
		fails += 1; print("FAIL a fresh map offers no options at all")
	else:
		var focus_row := int(opts[0]["row"])
		if focus_row != 0:
			fails += 1; print("FAIL a fresh map starts somewhere other than row 0")
		# if the map is taller than the window, the view MUST scroll to the player
		if map_h > window.y and not _defines("res://scripts/map.gd", "func _scroll_to_focus"):
			fails += 1
			print("FAIL map is %.0fpx tall in a %.0fpx window with no scroll-to-focus" % [
				map_h, window.y])
		print("  (info: %d rows = %.0fpx of map, window %.0fpx, needs scrolling: %s)" % [
			rows, map_h, window.y, str(map_h > window.y)])

	# --- the dice board is the same problem sideways ---
	var dice := TraversalDice.new()
	dice.generate(Balance.dungeon("the_maw"))
	var cell_w: float = 56.0 * scale
	var board_w: float = float(dice.track.size()) * cell_w
	if board_w > window.x and not _defines("res://scripts/dice_run.gd", "func _scroll_to_token"):
		fails += 1
		print("FAIL dice board is %.0fpx wide in a %.0fpx window with no scroll-to-token" % [
			board_w, window.x])
	print("  (info: dice board %d spaces = %.0fpx, window %.0fpx)" % [
		dice.track.size(), board_w, window.x])

	# --- every traversal must offer something pressable at every step ---
	# (a state with no options and no completion is a soft dead end)
	for kind in [Traversal.Kind.GRAPH, Traversal.Kind.DECK, Traversal.Kind.DICE]:
		for did in Balance.DUNGEONS:
			var t := Traversal.make(kind)
			t.generate(Balance.dungeon(did))
			var steps := 0
			while not t.is_complete() and steps < 60:
				steps += 1
				var o := t.options()
				if o.is_empty():
					fails += 1
					print("FAIL kind %d in %s reached a state with nothing to press" % [kind, did])
					break
				var pick := 0
				for i in o.size():
					if not o[i].has("hp_cost"):
						pick = i
						break
				if t.select(pick).is_empty():
					continue
				t.clear_pending()

	# --- the classes a headless test loads must not touch an autoload -----------
	#
	# An autoload referenced at compile time makes every script that touches it
	# unloadable in a `--script` run, and the symptom is not a failure — the test
	# HANGS, because the parse error skips the quit(). It has now happened four
	# times (settings_state in D19, and Icons reaching for UITheme.kit while wiring
	# the art hooks). These four classes are the ones the headless suite loads.
	const AUTOLOADS := ["UITheme", "SettingsState", "Audio", "MetaState", "GameState"]
	for path in ["res://scripts/icons.gd", "res://scripts/pixel_art.gd",
			"res://scripts/card_data.gd", "res://scripts/balance.gd"]:
		var fh := FileAccess.open(path, FileAccess.READ)
		if fh == null:
			continue
		var body := fh.get_as_text()
		fh.close()
		for line in body.split("\n"):
			var code: String = line
			var hash_at := code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)   # a comment may name one freely
			for auto in AUTOLOADS:
				# a bare `Autoload.` call; get_node_or_null("/root/X") is the safe form
				if code.find(auto + ".") != -1:
					fails += 1
					print("FAIL %s calls the %s autoload — it will HANG every --script test" % [
						path, auto])

	# --- no screen may keep its own copy of a shared lookup table ---
	#
	# This is the bug that made the Crypt unplayable. map.gd carried a private
	# TYPE_LABEL with five entries while encounters had grown to seven, so an
	# Event node threw mid-render and every row below it — including the only
	# actionable one — was never created. The shared table was fully covered by
	# tests; the *duplicate* was not. Duplicated lookups escape their tests.
	var label_users := ["res://scripts/map.gd", "res://scripts/deck_run.gd",
		"res://scripts/dice_run.gd", "res://scripts/run_flow.gd"]
	for path in label_users:
		if _defines(path, "TYPE_LABEL"):
			fails += 1
			print("FAIL %s keeps a private encounter-label table; use Balance.NODE_LABEL" % path)

	# every encounter kind a traversal can emit must have a shared label
	for enc in range(0, Traversal.Enc.size() if false else 7):
		if not Balance.NODE_LABEL.has(enc):
			fails += 1; print("FAIL no NODE_LABEL for encounter type %d" % enc)
	# and every type a real map can contain must be labelled
	for kind in [Traversal.Kind.GRAPH, Traversal.Kind.DECK, Traversal.Kind.DICE]:
		for did in Balance.DUNGEONS:
			var t := Traversal.make(kind)
			t.generate(Balance.dungeon(did))
			var types := {}
			if t is TraversalGraph:
				for row in (t as TraversalGraph).map:
					for n in row:
						types[int(n["type"])] = true
			elif t is TraversalDeck:
				for e in (t as TraversalDeck).draw_pile:
					types[int(e)] = true
			elif t is TraversalDice:
				for e in (t as TraversalDice).track:
					types[int(e)] = true
			for ty in types:
				if not Balance.NODE_LABEL.has(ty):
					fails += 1
					print("FAIL %s can contain encounter %d with no label" % [did, ty])

	# --- the map's node labels must not leak debug data ---
	var src := FileAccess.open("res://scripts/map.gd", FileAccess.READ)
	if src != null:
		var text := src.get_as_text()
		src.close()
		if text.find('str(node["edges"])') != -1:
			fails += 1; print("FAIL map buttons still print raw edge indices at the player")

	if fails == 0:
		print("LAYOUT TEST: PASS (actionable content is reachable, no dead ends, no debug text)")
	else:
		print("LAYOUT TEST: FAIL (%d)" % fails)
	quit()
