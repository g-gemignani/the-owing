## View for the isometric floor crawl: the floor drawn at an angle, your torch,
## and one button per door out of the room you are standing in.
##
## Everything here is a PLACEHOLDER: the tiles are drawn diamonds and the rooms
## are marked with the same encounter glyphs the other traversal views use. There
## is no tileset, no wall art and no character sprite yet, on purpose — the point
## of this screen is to find out whether crawling a floor is the right feel before
## anyone draws a floor.
##
## The floor is drawn rather than built out of Controls because a diamond grid is
## not a container layout: a row of rotated Buttons was the alternative, and a
## rotated Button is a hit-testing problem for the sake of a shape. Movement is
## therefore offered twice — click a lit room, or press its button — so the screen
## is playable on a keyboard and does not depend on the drawing being pixel-exact.
extends Control

## Tile footprint, in unscaled pixels. Twice as wide as it is tall, which is the
## flat 2:1 projection every isometric tileset ships in.
## Sized so the whole plate fills the window without scrolling — tests/test_layout.gd
## reads these two numbers and the grid size together and fails if they stop fitting.
const TILE_W := 116.0
const TILE_H := 58.0
## Room colours: contents, cleared, the dark past the torch, and the rock the
## floor is cut out of.
const COL_ROOM := Color(0.30, 0.32, 0.40)
const COL_CLEARED := Color(0.17, 0.18, 0.22)
const COL_DARK := Color(0.12, 0.13, 0.17)
const COL_ROCK := Color(0.06, 0.06, 0.08)
const COL_EDGE := Color(0.55, 0.58, 0.68, 0.7)
const COL_REACH := Color(0.98, 0.78, 0.35)   ## a door you can walk through now
const COL_YOU := Color(0.55, 0.90, 1.0)
## Move buttons are a row of short labels, not reward-card slabs: at card size a
## three-word label sat in the middle of an empty panel and read as a broken
## screen (it did, in the first capture of this view).
const MOVE_BUTTON := Vector2(190.0, 46.0)

var status_label: Label
var log_label: Label      ## what just happened
var hint_label: Label     ## what the floor is asking for now
var floor_view: Control
var moves_box: HBoxContainer

func _ready() -> void:
	_build_ui()
	_refresh()

func _build_ui() -> void:
	# UI.screen gives the zone backdrop, the root margin and the content column, so
	# this screen cannot be the one that forgets the backdrop again (D56).
	var root := UI.screen(self, "")

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)

	# Kept apart from the log on purpose: the log is the last thing the player did
	# and the hint is the state of the floor, and one line trying to be both means
	# every refresh silently erases whichever the player was still reading.
	hint_label = Label.new()
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_color_override("font_color", Color(0.78, 0.80, 0.88))
	root.add_child(hint_label)

	# The floor asks for the exact size its grid needs. A drawn Control has no
	# content to measure, so without this it would report a minimum of zero and the
	# spacers either side would crush it flat — the dice board's bug, which took a
	# screenshot to find (D57).
	floor_view = Control.new()
	floor_view.custom_minimum_size = _floor_size()
	floor_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	floor_view.draw.connect(_draw_floor)
	floor_view.gui_input.connect(_on_floor_input)
	root.add_child(floor_view)

	moves_box = HBoxContainer.new()
	moves_box.alignment = BoxContainer.ALIGNMENT_CENTER
	moves_box.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(moves_box)

	var spacer_bot := Control.new()
	spacer_bot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer_bot)

	var coll := Button.new()
	coll.text = "Collection"
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	root.add_child(coll)
	# same Callable on the button and on Escape, so the two cannot drift apart
	UI.exit_button(root, "Menu", func(): UI.goto(self, "res://scenes/PauseMenu.tscn"))

# --- geometry -----------------------------------------------------------------

func _tile() -> Vector2:
	return Vector2(UITheme.px(TILE_W), UITheme.px(TILE_H))

func _floor_size() -> Vector2:
	var t := _tile()
	var g := _grid()
	return Vector2(float(g.x + g.y) * t.x * 0.5, float(g.x + g.y) * t.y * 0.5 + t.y)

func _grid() -> Vector2i:
	var tv := GameState.traversal as TraversalIso
	return tv.grid() if tv != null else Vector2i(Balance.ISO_GRID, Balance.ISO_GRID)

## Grid cell -> the middle of its diamond, in floor-view coordinates.
func _to_screen(x: int, y: int) -> Vector2:
	var t := _tile()
	var g := _grid()
	return Vector2(
		(float(x - y) + float(g.y)) * t.x * 0.5,
		float(x + y) * t.y * 0.5 + t.y * 0.5)

## The inverse, for clicking on the floor. Rounded to the nearest cell centre,
## which treats each diamond as its bounding box near the corners — close enough
## to pick a room, and the buttons are there for anyone it misjudges.
func _to_cell(p: Vector2) -> Vector2i:
	var t := _tile()
	var g := _grid()
	var fx := (p.x / (t.x * 0.5)) - float(g.y)
	var fy := (p.y - t.y * 0.5) / (t.y * 0.5)
	return Vector2i(int(round((fy + fx) * 0.5)), int(round((fy - fx) * 0.5)))

# --- drawing ------------------------------------------------------------------

func _draw_floor() -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var t := _tile()
	var g := tv.grid()
	var reach := {}
	for o in tv.options():
		reach[int(o["cell"])] = true

	# Back to front, so a room nearer the viewer overlaps the one behind it.
	for y in g.y:
		for x in g.x:
			var i: int = y * g.x + x
			var e := tv.cell(x, y)
			var seen := tv.lit(x, y)
			# The rock is drawn too, flat and nearly black. Only the lit rooms were
			# drawn at first, and three diamonds floating in an empty window did not
			# read as a floor at all — the picture needs the ground the rooms are cut
			# out of to be a picture of anywhere.
			var is_rock: bool = e == TraversalIso.WALL or (not seen and not tv.frontier(x, y))
			var centre := _to_screen(x, y)
			var quad := PackedVector2Array([
				centre + Vector2(0, -t.y * 0.5), centre + Vector2(t.x * 0.5, 0),
				centre + Vector2(0, t.y * 0.5), centre + Vector2(-t.x * 0.5, 0)])
			var fill := COL_ROCK
			if not is_rock:
				fill = COL_DARK
				if seen:
					fill = COL_CLEARED if e == TraversalIso.EMPTY else COL_ROOM
			floor_view.draw_colored_polygon(quad, fill)
			if is_rock:
				continue    # rock gets no outline: it is not somewhere you can go
			var edge := COL_REACH if reach.has(i) else COL_EDGE
			var width := UITheme.px(3.0) if reach.has(i) else UITheme.px(1.0)
			floor_view.draw_polyline(quad + PackedVector2Array([quad[0]]), edge, width)
			# what is in the room, once the torch has been near enough to see it
			if seen and e >= 0:
				var tex := Icons.for_encounter(e)
				if tex != null:
					var s: float = minf(t.x * 0.42, t.y * 0.8)
					floor_view.draw_texture_rect(tex,
						Rect2(centre - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), false)
			if i == tv.pos:
				# the token: a marker standing ON the tile, not painted onto it
				floor_view.draw_circle(centre - Vector2(0, t.y * 0.3), t.y * 0.2, COL_YOU)

func _on_floor_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var c := _to_cell(mb.position)
	var g := tv.grid()
	if c.x < 0 or c.y < 0 or c.x >= g.x or c.y >= g.y:
		return
	var target: int = c.y * g.x + c.x
	var opts := tv.options()
	for i in opts.size():
		if int(opts[i]["cell"]) == target:
			_on_pick(i)
			return

# --- state --------------------------------------------------------------------

func _refresh() -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		log_label.text = "No dungeon in progress."
		call_deferred("_leave")
		return

	var dd := GameState.dungeon_data()
	status_label.text = "%s (d%d)    HP %d/%d    Deck %d    Gold %d    %s" % [
		dd.name if dd != null else "Dungeon", GameState.dungeon,
		GameState.hp, GameState.max_hp, GameState.run_deck.size(),
		MetaState.gold, tv.status()]
	UI.hoverable(status_label, "AT RISK: found this run, but only kept if you beat the boss or use an Escape Rope.")
	status_label.text += "    AT RISK: %d cards, %d gold    Ropes %d" % [
		GameState.escrow_cards.size(), GameState.escrow_gold,
		MetaState.item_count("escape_rope")]

	if tv.is_complete():
		call_deferred("_leave")
		return

	if floor_view != null:
		floor_view.custom_minimum_size = _floor_size()
		floor_view.queue_redraw()

	for c in moves_box.get_children():
		c.queue_free()
	var opts := tv.options()
	var stair_found := false
	for i in opts.size():
		var o: Dictionary = opts[i]
		var b := Button.new()
		b.text = o["label"]
		b.custom_minimum_size = Vector2(UITheme.px(MOVE_BUTTON.x), UITheme.px(MOVE_BUTTON.y))
		if int(o["type"]) == GameState.NodeType.BOSS:
			stair_found = true
			# the finale is named before it is entered, on every model (D41)
			var boss := Balance.boss_of(GameState.dungeon_id)
			if boss != null:
				b.text = "%s  BOSS: %s" % [TraversalIso.DIR_ARROW[int(o["dir"])], boss.name]
				UI.hoverable(b, "%s\n%s" % [
					boss.name, Balance.boss_warning(GameState.dungeon_id)])
		b.pressed.connect(_on_pick.bind(i))
		moves_box.add_child(b)

	var hint := "The torch shows the next room and no further. The way down is somewhere on this floor."
	if stair_found:
		hint = "The way down is right there. Anything you leave up here, you leave behind."
	elif tv.torch <= 0:
		hint = "The torch is out. Every step costs blood now."
	hint_label.text = hint

func _on_pick(i: int) -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var opts := tv.options()
	if i < 0 or i >= opts.size():
		return
	var opt: Dictionary = opts[i]
	var cost := int(opt.get("hp_cost", 0))
	var chosen := tv.select(i)
	if cost > 0:
		# Walking in the dark is charged here, not in the traversal, for the same
		# reason the deck model's dodge is: the model is pure logic and never reads
		# or writes run HP. It can never be lethal — a floor can *require* a step,
		# so a price that could kill would be a trap with no way out.
		GameState.hp = maxi(1, GameState.hp - cost)
		Audio.play("hurt")
	if chosen.is_empty():
		# a step onto ground already cleared
		if cost > 0:
			log_label.text = "You feel your way through the dark. -%d HP." % cost
		else:
			log_label.text = "You cross a room you have already been through."
		GameState.autosave()
		_refresh()
		return
	GameState.pending = chosen
	if RunFlow.enter_node(self, chosen, _after_rest):
		_refresh()

func _after_rest() -> void:
	log_label.text = "Rested."
	_refresh()

func _leave() -> void:
	get_tree().change_scene_to_file(RunFlow.leave_run())
