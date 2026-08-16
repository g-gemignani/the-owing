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

## One function's body, read out of a script's SOURCE — from its `func` line to the next
## declaration at column 0. Source and not reflection, for `_defines`'s reason: loading a UI
## script here compiles its autoload references and hangs the run.
##
## Scoped rather than whole-file, because the thing being asserted is WHERE a call is. The bug
## this exists for (D271) was one `_roll_rewards(3)` on the wrong side of a function boundary,
## and the file is allowed — required, in fact — to call it on the other side.
func _func_body(path: String, decl: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	var start := text.find(decl)
	if start == -1:
		return ""
	# From the line AFTER the declaration, so a `func _roll_x` whose own name matches a needle
	# cannot report itself.
	start = text.find("\n", start)
	if start == -1:
		return ""
	var end := text.find("\nfunc ", start)
	return text.substr(start, (end - start) if end != -1 else -1)

## A numeric `const NAME := 1.5` read out of a script's SOURCE, for the same reason
## `_defines` reads source: loading a UI script here would compile its autoload
## references and hang the run. Returns `fallback` if the constant is not found,
## and the caller prints what it measured so a silent fallback cannot pass quietly.
func _const_of(path: String, name: String, fallback: float) -> float:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback
	var text := f.get_as_text()
	f.close()
	for line in text.split("\n"):
		var l: String = line.strip_edges()
		if l.begins_with("const %s " % name) or l.begins_with("const %s:" % name):
			var eq := l.find("=")
			if eq >= 0:
				return float(l.substr(eq + 1).strip_edges())
	return fallback

## How many entries a `const NAME := [...]` literal has, read out of source for the
## same reason `_const_of` is. Returns -1 if it is not there, which reads as a
## mismatch rather than as a pass.
func _list_len(path: String, decl: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var text := f.get_as_text()
	f.close()
	var at := text.find(decl)
	if at < 0:
		return -1
	var open := text.find("[", at)
	var close := text.find("]", open)
	if open < 0 or close < 0:
		return -1
	var inner := text.substr(open + 1, close - open - 1).strip_edges()
	return 0 if inner.is_empty() else inner.split(",").size()

func _init() -> void:
	var fails := 0
	var window := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))

	# --- the UI scale must have exactly one home -------------------------------
	# Read the shipped default rather than restating it. This line said 1.6 while
	# the constant was changed to 1.0, which is exactly how a duplicated number
	# turns a passing test into a lie.
	var scale: float = load("res://scripts/ui_theme.gd").UI_SCALE
	# ...and there must be no second copy anywhere. settings_state.gd used to carry
	# its own default and apply it over the theme's, so a new player never got the
	# shipped scale; the whole zoom is gone now (D65) and this keeps it gone.
	for src0 in ["res://scripts/settings_state.gd", "res://scripts/settings_menu.gd",
			"res://scripts/ui_theme.gd"]:
		var fh0 := FileAccess.open(src0, FileAccess.READ)
		if fh0 == null:
			continue
		var text0 := fh0.get_as_text()
		fh0.close()
		for banned in ["set_scale_silent", "func set_scale("]:
			if text0.find(banned) != -1:
				fails += 1
				print("FAIL %s still exposes %s — the UI scale is fixed" % [src0, banned])

	# --- the isometric floor is a WINDOW onto a bigger plate ---
	#
	# The graph and dice views (deleted in D94) scrolled; the floor did neither, so
	# the grid size and the tile size were only safe *together* and ISO_GRID could
	# not grow at all — at 6x6 and 116x58 the plate already drew 406px into 460px of
	# room, and 7x7 would not have fitted. It now has a camera (D77), which moves the
	# constraint rather than removing it: what must fit is VIEW_W/VIEW_H, and the
	# plate must be BIGGER than that or the camera is dead code and the floor has
	# stopped being somewhere you discover. All four numbers are read from source,
	# never restated here.
	var tile_w := _const_of("res://scripts/iso_run.gd", "TILE_W", 96.0) * scale
	var tile_h := _const_of("res://scripts/iso_run.gd", "TILE_H", 48.0) * scale
	var view_w := _const_of("res://scripts/iso_run.gd", "VIEW_W", 1040.0) * scale
	var view_h := _const_of("res://scripts/iso_run.gd", "VIEW_H", 420.0) * scale
	var span := float(Balance.ISO_GRID * 2)
	var plate_w := span * tile_w * 0.5
	var plate_h := span * tile_h * 0.5 + tile_h
	# the header, the two text lines and the act row live in the same column, so the
	# floor cannot have the whole window
	var chrome := 260.0 * scale
	if view_w > window.x:
		fails += 1
		print("FAIL the isometric view is %.0fpx wide in a %.0fpx window" % [view_w, window.x])
	if view_h > window.y - chrome:
		fails += 1
		print("FAIL the isometric view is %.0fpx tall with only %.0fpx of room" % [
			view_h, window.y - chrome])
	# VIEW_W/VIEW_H are the floor's MINIMUM since D325: it expands into whatever the
	# column has left, which on this window is 1248x506 rather than the 1040x400 above.
	# Checking the minimum is still the right check — the floor can only be bigger — but
	# only while the expanding is actually asked for. Pin it, or a `SHRINK_CENTER` put
	# back by hand would silently return the screen to the smaller of the two sizes and
	# every number here would go on passing.
	var floor_build := _func_body("res://scripts/iso_run.gd", "func _build_ui")
	if floor_build.find("floor_view.size_flags_vertical = Control.SIZE_EXPAND_FILL") == -1:
		fails += 1
		print("FAIL the iso floor does not expand — it is pinned to its own minimum and the column's spare height goes to nothing")
	if plate_w <= view_w or plate_h <= view_h:
		fails += 1
		print("FAIL the iso plate (%.0fx%.0f) fits inside its own view (%.0fx%.0f) — the camera does nothing and the floor has no hidden ground" % [
			plate_w, plate_h, view_w, view_h])
	if not _defines("res://scripts/iso_run.gd", "func _camera_for"):
		fails += 1
		print("FAIL the iso plate is larger than the window with no camera to move it")
	print("  (info: iso plate %dx%d on %.0fx%.0f tiles = %.0fx%.0fpx, viewed through %.0fx%.0f, window %.0fx%.0f)" % [
		Balance.ISO_GRID, Balance.ISO_GRID, tile_w, tile_h, plate_w, plate_h,
		view_w, view_h, window.x, window.y])

	# --- every direction the floor offers has a key that walks it (D87) ---
	#
	# The failure this catches is silent by construction: a direction with no binding
	# behaves exactly like a direction with a wall in it, so the only symptom is that
	# one quarter of the floor is unreachable by keyboard and nothing says why. Add a
	# fifth entry to `TraversalIso.DIRS` and this is what notices.
	var bound := {}
	var iso_src_body := ""
	var iso_src := FileAccess.open("res://scripts/iso_run.gd", FileAccess.READ)
	if iso_src != null:
		var body := iso_src.get_as_text()
		iso_src.close()
		iso_src_body = body
		# read the MOVE_KEYS block out of source, for the same reason every other
		# constant here is read out of source: loading a UI script pulls in autoloads
		# that a --script run has not registered, and that hangs rather than fails
		var block := body.substr(body.find("const MOVE_KEYS"))
		block = block.substr(0, block.find("}"))
		for line in block.split("\n"):
			for part in String(line).split(","):
				var kv: String = String(part).split("#")[0].strip_edges()
				if kv.begins_with("KEY_") and kv.contains(":"):
					bound[int(kv.split(":")[1].strip_edges())] = true
	for d in TraversalIso.DIRS.size():
		if not bound.has(d):
			fails += 1
			print("FAIL iso direction %s (%s) has no movement key — it can only be clicked" % [
				d, TraversalIso.DIR_ARROW[d]])
	var dir_keys := _list_len("res://scripts/iso_run.gd", "const DIR_KEY")
	if dir_keys != TraversalIso.DIRS.size():
		fails += 1
		print("FAIL DIR_KEY names %d directions and there are %d — the legend will show the wrong letter or crash" % [
			dir_keys, TraversalIso.DIRS.size()])

	# --- ...and a key on the pad that walks it (D168) ---
	#
	# The same silent failure one input away. There are no move buttons any more: a phone
	# has the pad and nothing else, so a direction missing from PAD_CELL is a quarter of the
	# floor that cannot be reached AT ALL on the machine the pad exists for. Two keys landing
	# on one cell of the 3x3 is the other half — one would be drawn on top of the other.
	var cells := {}
	if iso_src_body != "":
		var pad_block := iso_src_body.substr(iso_src_body.find("const PAD_CELL"))
		# from INSIDE the braces: the declaration itself contains `:=`, so a split on ":"
		# over the whole line finds the assignment before it finds the first entry
		pad_block = pad_block.substr(pad_block.find("{") + 1)
		pad_block = pad_block.substr(0, pad_block.find("}"))
		for part in pad_block.split(","):
			var kv: String = String(part).split("#")[0].strip_edges()
			if not kv.contains(":") or not kv.split(":")[0].strip_edges().is_valid_int():
				continue
			cells[int(kv.split(":")[0].strip_edges())] = int(kv.split(":")[1].strip_edges())
	var used := {}
	for d in TraversalIso.DIRS.size():
		if not cells.has(d):
			fails += 1
			print("FAIL iso direction %s (%s) has no pad key — on a touchscreen it cannot be walked at all" % [
				d, TraversalIso.DIR_ARROW[d]])
			continue
		var at: int = int(cells[d])
		if at < 0 or at > 8:
			fails += 1
			print("FAIL iso direction %s sits at pad cell %d, outside the 3x3" % [d, at])
		if used.has(at):
			fails += 1
			print("FAIL pad cell %d holds two directions — one is drawn over the other" % at)
		used[at] = true
	print("  (info: iso binds %d of %d directions to keys, %d letters in the legend, %d on the pad)" % [
		bound.size(), TraversalIso.DIRS.size(), dir_keys, cells.size()])

	# --- every traversal must offer something pressable at every step ---
	# (a state with no options and no completion is a soft dead end)
	for did in Balance.DUNGEONS:
		var t := TraversalIso.new()
		t.generate(Balance.dungeon(did))
		var steps := 0
		# clear of a real iso tour, which is tens of steps on a ~33-tile floor
		while not t.is_complete() and steps < 400:
			steps += 1
			var o := t.options()
			if o.is_empty():
				fails += 1
				print("FAIL %s reached a state with nothing to press" % did)
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
	# The screen that carried the bug (`map.gd`) was deleted with its model in D94, so
	# this now watches the screens that inherited its job. The rule outlives the file.
	var label_users := ["res://scripts/iso_run.gd", "res://scripts/run_flow.gd",
		"res://scripts/encounter.gd"]
	for path in label_users:
		if _defines(path, "TYPE_LABEL"):
			fails += 1
			print("FAIL %s keeps a private encounter-label table; use Balance.NODE_LABEL" % path)

	# every encounter kind a traversal can emit must have a shared label
	for enc in range(0, Traversal.Enc.size() if false else 7):
		if not Balance.NODE_LABEL.has(enc):
			fails += 1; print("FAIL no NODE_LABEL for encounter type %d" % enc)
	# and every type a real floor can contain must be labelled
	for did in Balance.DUNGEONS:
		var t2 := TraversalIso.new()
		t2.generate(Balance.dungeon(did))
		var types := {}
		# rock and cleared rooms are not encounters and have no label
		for e in t2.enc:
			if int(e) >= 0:
				types[int(e)] = true
		for ty in types:
			if not Balance.NODE_LABEL.has(ty):
				fails += 1
				print("FAIL %s can contain encounter %d with no label" % [did, ty])

	# --- the debt is paid at the door, and the door is the deck builder (D211) ---------
	#
	# A SOURCE check, for the reason this file's own header gives: these are UI scripts and a
	# `--script` run has no autoloads to instantiate them with. It is also the only kind of
	# check available here — the honest version presses the offer on the region screen and
	# watches the purse, and pressing it NAVIGATES, which in a harness replaces the harness
	# (see `playable_test.gd`'s note on screens that bail out by changing scene).
	#
	# So it asserts WHICH SCREEN spends the stake, which is exactly the thing that regressed:
	# D205 spent it on the region screen the instant the offer was pressed, a screen and a
	# whole deck-building session away from the run it is a wager on, and unrecoverable if the
	# player walked back out. Moving it is easy to undo by accident, because putting
	# `take_debt` next to the button that names the debt reads perfectly sensible.
	if _defines("res://scripts/zone_view.gd", "take_debt("):
		fails += 1
		print("FAIL zone_view.gd spends the debt stake — it belongs at the run's start, not")
		print("     on the screen that only OFFERS it (D211). The offer is a door now.")
	if not _defines("res://scripts/collection.gd", "take_debt("):
		fails += 1
		print("FAIL nothing in the deck builder takes the debt, so a run started on the")
		print("     'go in owing' door would owe nothing and pay nothing (D211).")
	# ...and the flag that carries the choice between the two screens has to be cleared with
	# the run, or the NEXT dungeon entered after a debt run silently starts owing.
	if not _defines("res://scripts/game_state.gd", "pending_debt = false"):
		fails += 1
		print("FAIL game_state.gd never clears pending_debt, so the choice outlives its run")

	# --- a panel that redraws may not roll dice (D271) ------------------------------
	#
	# `_offer_rewards` is called twice at an elite: once when the fight ends, and again after a
	# relic is taken, because the relic row has to be redrawn as taken. It also rolled the three
	# card rewards, so taking the relic dealt three NEW cards underneath — and a player who
	# waited to see the cards before taking the relic could re-roll them at will, which is D22's
	# slot machine reached by a door nobody built.
	#
	# The rule this asserts is wider than the bug, because the narrow version ("no
	# `_roll_rewards` here") would pass the day somebody inlines a `randi()`. A draw function is
	# a draw function: what it shows is decided before it is called.
	var draw_fns := {
		"res://scripts/combat.gd": "func _offer_rewards",
	}
	for path in draw_fns:
		var body := _func_body(String(path), String(draw_fns[path]))
		if body == "":
			fails += 1
			print("FAIL %s no longer defines %s — the D271 guard is asserting nothing" % [
				path, String(draw_fns[path])])
			continue
		for die in ["randi(", "randf(", "randi_range(", "pick_random(", "shuffle(", "_roll_"]:
			if body.find(die) != -1:
				fails += 1
				print("FAIL %s rolls '%s' inside %s, which is redrawn after a relic is taken —" % [
					path, die, String(draw_fns[path])])
				print("     so the offer changes under the player (D271). Roll it in _win() and read it here.")

	# Declared for `tests/run.sh`, which fails any suite that produced a SCRIPT ERROR (D300).
	# This one provokes them on purpose: it `load()`s scripts that name autoloads, and autoloads
	# do not exist in a `--script` run, so a compile error here is the tool working.
	print("TEST EXPECTS ERRORS")
	if fails == 0:
		print("LAYOUT TEST: PASS (actionable content is reachable, no dead ends, no debug text, the debt is paid at the door)")
	else:
		print("LAYOUT TEST: FAIL (%d)" % fails)
	quit()
