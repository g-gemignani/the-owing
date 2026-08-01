## View for the isometric floor crawl: a window onto the floor, drawn at an angle
## and scrolled to keep you in the middle of it, plus one button per exit.
##
## The geometry is drawn, not tiled: ground is a diamond with a seamless stone material
## projected onto it and rock is a block built from three of those faces. Everything that
## stands on the floor — monsters, furniture, the hero — is a trimmed sprite out of
## `assets/art/iso/`, and every one of those lookups tolerates a missing file, falling
## back to the flat encounter glyphs the other three traversal views use. So this screen
## still answers its original question (is crawling a floor the right feel) on a checkout
## with no art installed at all.
##
## The floor is drawn rather than built out of Controls because a diamond grid is
## not a container layout: a row of rotated Buttons was the alternative, and a
## rotated Button is a hit-testing problem for the sake of a shape. Movement is
## therefore offered three ways — click a lit tile, press its button, or hold a
## direction key — so the screen does not depend on the drawing being pixel-exact.
##
## The ground stopped LOOKING like a grid in D87, while remaining one. Per-tile
## outlines are gone, so tiles at the same tint merge into continuous stone; the
## hero and the wanderers slide between tiles instead of snapping; and WASD walks,
## held or tapped. What did not change is the simulation underneath: one keypress is
## one call to `select()`, one turn, one entry in `steps`. That is deliberate and it
## is the reason the tiles were kept at all — `ISO_MOVES_PER_ENCOUNTER_MAX` is a
## ratio of discrete moves to encounters, and it is what stops a spatial model from
## burying the card game (D14, D79). A continuous world would have nothing to count,
## and "every dungeon costs the same" would stop being measurable.
##
## The camera is load-bearing, not a nicety (D77). A 12x12 plate is 1392x754
## unscaled and the window is 1280x720 with a header and a button row in the same
## column, so the whole floor CANNOT be shown at once — which is the point, because
## a floor you can see all of is a floor with nothing left to discover.
extends Control

## Tile footprint, in unscaled pixels. Twice as wide as it is tall, which is the
## flat 2:1 projection every isometric tileset ships in.
const TILE_W := 116.0
const TILE_H := 58.0
## The window onto the floor. This is what has to fit the screen, not the plate —
## tests/test_layout.gd checks this against the window AND checks that the plate
## is bigger than it, so nobody shrinks ISO_GRID back to where the camera is dead
## code without a test saying so.
const VIEW_W := 1040.0
const VIEW_H := 400.0
## How high a rock block stands, as a fraction of the tile height. Rock used to be a
## flat dark diamond, which on a textured floor reads as "darker ground" rather than
## as a wall — the art check came back looking like a stain on the floor instead of a
## room. A block with a top and two visible faces is what makes a corridor a corridor.
const WALL_LIFT := 0.9
## Where the player sits in the window, as a fraction of its height. Not 0.5: sprites
## are two tiles tall and stand BEHIND their own tile, so a centred camera clipped the
## heads off anything in the row behind the player.
const EYE_Y := 0.62
## Tile TINTS, not tile colours any more: the floor is a stone material drawn through
## these, so each one is "how lit is this bit of ground" rather than a paint choice.
## Ground you have walked reads at full strength; ground you have only looked at is
## dimmer; the edge of what you know is nearly out. That ordering is the fog, and it
## also happens to be the map your own route is drawn on (a model about coverage
## needs to show where you have been).
const TINT_WALKED := Color(0.86, 0.86, 0.92)
const TINT_OPEN := Color(0.52, 0.54, 0.62)
const TINT_FRONTIER := Color(0.20, 0.21, 0.26)
## The three faces of a rock block. Different values on purpose: one flat tint made a
## run of blocks read as a single shapeless mass instead of as separate stones.
const TINT_WALL_TOP := Color(0.46, 0.46, 0.52)
const TINT_WALL_R := Color(0.30, 0.30, 0.35)
const TINT_WALL_L := Color(0.19, 0.19, 0.23)
## How solid a wall standing between the camera and the player is drawn. Low enough to
## see her through, high enough that the wall is still obviously there.
const OCCLUDER_ALPHA := 0.34
const COL_REACH := Color(0.98, 0.78, 0.35)   ## an exit you can walk through now
const COL_YOU := Color(0.55, 0.90, 1.0)
const COL_THREAT := Color(1.0, 0.36, 0.34)   ## something walking, while you can see it

## Standing art, keyed the way `install_iso_art.gd` names it. Loaded once rather than
## per redraw, and every lookup tolerates a missing file: art that has not been
## installed must degrade to the drawn floor, not crash a run.
const ART_DIR := "res://assets/art/iso/"
## On-screen height of each sprite, as a multiple of the tile's height. A sprite is
## anchored by its FEET (the installer trims to the silhouette, so bottom-centre is
## the foot point) which is why only a height is needed here.
const SPRITE_H := {
	"combat": 1.95, "elite": 2.15, "boss": 2.15,
	"shop": 1.9, "rest": 1.9, "event": 1.9, "treasure": 1.7,
	"wander": 1.6,
	# The hero is a person, and the armoured brutes she meets are not: shorter than a
	# combat and taller than a spider is the whole reading, and it has to survive the
	# fact that she is drawn last and so never occluded.
	"hero": 1.95,
}
## Wanderer design count lives in `Balance.ISO_WANDERERS` — the manifest lists one
## painted file per design and cannot preload this script to read it (D122).
const WANDER_DESIGNS := Balance.ISO_WANDERERS

var art := {}          ## role -> Texture2D, or absent
## Which way the hero is facing, in the only two facings her art has: toward the camera
## or away from it. Pure view state, deliberately not saved and not in the model — the
## rules do not care where she is looking, and a resumed run starts her facing the
## player, which is the friendlier of the two. Same test the wanderers use for their own
## facing (`TraversalIso` sets `south` from `dx + dy > 0`).
var face_south := true
## Move buttons are a row of short labels, not reward-card slabs: at card size a
## three-word label sat in the middle of an empty panel and read as a broken
## screen (it did, in the first capture of this view). Widened from 190 to pay for
## the key letter each one now carries.
const MOVE_BUTTON := Vector2(212.0, 46.0)

## Movement keys, bound SCREEN-relative (D87).
##
## The four grid directions project to the four screen DIAGONALS, never to up or
## right (see `TraversalIso.DIR_ARROW`), so there is no key here that walks straight
## up the screen and there cannot be one. Each key is bound to the most-that-way of
## the four available: W is the up-and-right diagonal, S the down-and-left one, and
## the ring of keys maps onto the ring of diagonals clockwise from there.
##
## Clockwise versus anticlockwise is a genuine coin-flip — ↗ and ↖ are equally "up",
## so no argument picks one. It is therefore resolved by SHOWING it rather than by
## choosing well: every move button carries its key letter next to its arrow, so the
## mapping is read off the screen in the first two steps instead of guessed at. Bind
## these grid-relative instead and W walks you down-right, which is the complaint
## every isometric game with a rotated keyboard gets.
const MOVE_KEYS := {
	KEY_W: 3, KEY_UP: 3,        # ↗
	KEY_D: 0, KEY_RIGHT: 0,     # ↘
	KEY_S: 2, KEY_DOWN: 2,      # ↙
	KEY_A: 1, KEY_LEFT: 1,      # ↖
}
## The letter shown on each direction's button, indexed like `TraversalIso.DIRS`.
const DIR_KEY := ["D", "A", "S", "W"]

## How long one step takes to walk, in seconds.
##
## This is a pace limit, not a flourish. A step is a TURN — the wanderers move when
## you move — so hold-to-walk at the OS key-repeat rate would spend a floor's worth
## of exposure in a second and a half without a single decision in it, which is
## precisely the greed the torch was removed to charge for (D77). Walking is animated
## so that it *takes* this long, and the next held step cannot start until this one
## has finished. Clicking a tile costs exactly the same turn it always did.
const STEP_TIME := 0.13

## Scroll offset applied to every drawn tile, recomputed per redraw. Kept as state
## because the click handler has to undo exactly what the draw applied.
var cam := Vector2.ZERO

## The walk in progress, 0 at the tile left behind and 1 at the tile arrived in.
## 1.0 means standing still, which is the state everything else is written against.
var walk_t := 1.0
## Where the step started, in PLATE coordinates.
var walk_from := Vector2.ZERO
## dest cell -> the offset back to where that monster stood, in plate coordinates.
## Wanderers slide with the player because they step when she does; a monster that
## only just came into sight is absent here and simply appears, which is correct.
var walk_mons := {}
## May a held key roll straight into another step when this one lands? False after
## anything that deserves a beat: a descent, a fight, or something new in sight.
var walk_more := false

## The header used to be nine statistics concatenated into ONE Label, and it failed
## twice over (D114). Mechanically: an unbounded run-on overflows 1280x720 at some
## content length and always did, wrapping in the middle of "AT RISK: 0 cards, 0 gold"
## — a Label breaks at a space and cannot tell a separator from a space inside a
## phrase. Editorially: the dungeon's name, the tile count and the thing the entire run
## is staked on were the same size in the same grey, which is a debug print, not a HUD.
##
## So the header is three tiers of importance and every fact is its OWN Label inside a
## flow container. A row that runs out of width now breaks BETWEEN facts, because there
## is nothing inside one left to break — which is what makes it safe for the longest
## dungeon name and the biggest numbers instead of tuned until one capture fits.
var vitals_box: HFlowContainer   ## tier 1: where you are, and whether you are alive
var floor_box: HFlowContainer    ## tier 3: the floor's bookkeeping
var risk_frame: PanelContainer   ## tier 2: the only framed thing up there
var risk_label: Label
var ropes_label: Label
var log_label: Label      ## what just happened
var hint_label: Label     ## what the floor is asking for now
var floor_view: Control
var moves_box: HBoxContainer

## Header ink. The tiers differ by SIZE and by colour, not by position alone, so the
## reading order survives a row wrapping.
const STAT_INK := Color(0.93, 0.93, 0.97)
const FLOOR_INK := Color(0.70, 0.72, 0.82)
## HP is the one vital with a state. Below a third of a bar it stops being bookkeeping
## and becomes the next decision, so it is the only chip that changes colour.
const HURT_INK := Color(1.0, 0.46, 0.42)
const HURT_AT := 3        ## hp * HURT_AT <= max_hp
## The at-risk frame, lit and unlit. Everything found this run is forfeit unless the
## boss falls or a rope is spent, so it gets the emphasis — but it is DIM while the
## escrow is empty, because an alarm that is on from the first step of every run is
## wallpaper by the third and stops being read at all.
const RISK_LIT := Color(1.0, 0.78, 0.42)
const RISK_COLD := Color(0.70, 0.72, 0.80)

## The two states of that frame, built once. Swapped by `_refresh`.
var risk_sb_lit: StyleBoxFlat
var risk_sb_cold: StyleBoxFlat

func _ready() -> void:
	_load_art()
	_build_ui()
	_refresh()

## Every sprite the floor can draw, loaded once. A role with no file on disk is simply
## absent from `art`, and `_sprite` falls back to the encounter glyph the other three
## traversal views use — so a half-installed art set looks unfinished rather than
## taking a run down with it.
func _load_art() -> void:
	var roles: Array = ["floor", "rock", "combat", "elite", "boss", "shop", "rest",
		"event", "treasure", "hero_s", "hero_n"]
	for i in WANDER_DESIGNS:
		roles.append("wander_%d_s" % i)
		roles.append("wander_%d_n" % i)
	for fam in Balance.ISO_FAMILIES:
		roles.append("mon_%s_s" % fam)
		roles.append("mon_%s_n" % fam)
	for r in roles:
		var path: String = ART_DIR + String(r) + ".png"
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				art[r] = tex
	# The dungeon's own surface overwrites the generic pair, so the drawing code keeps
	# asking for "floor" and "rock" and never learns that terrain exists. A terrain with
	# no art installed simply leaves the generic pair in place.
	var terrain := Balance.iso_terrain(GameState.dungeon_id)
	for pair in ["floor", "rock"]:
		var tpath: String = "%s%s_%s.png" % [ART_DIR, pair, terrain]
		if ResourceLoader.exists(tpath):
			var ttex := load(tpath) as Texture2D
			if ttex != null:
				art[pair] = ttex

func _build_ui() -> void:
	# UI.screen gives the zone backdrop, the root margin and the content column, so
	# this screen cannot be the one that forgets the backdrop again (D56).
	var root := UI.screen(self, "")

	# Two deliberate rows rather than one line, and no taller than the one line was
	# once it had wrapped: the header shares 720px with the floor viewport and the
	# button row, and the floor is already the thinnest thing on the screen.
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.sep(2))
	root.add_child(header)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UITheme.sep(14))
	header.add_child(top)

	vitals_box = HFlowContainer.new()
	vitals_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vitals_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vitals_box.add_theme_constant_override("h_separation", UITheme.sep(18))
	top.add_child(vitals_box)

	# The at-risk figure is the only framed thing in the header, pinned to the far end
	# of the top row where the eye lands second. It carries the rope count inside the
	# same frame because a rope is the only answer to it, and because the two are
	# otherwise read a second apart at opposite ends of a line.
	#
	# `SHRINK_END` against a flow container is also what makes the pinning safe: an
	# HFlowContainer asks for the width of its WIDEST chip, not the sum, so the frame
	# can never be pushed off the right edge by a long line of vitals — the vitals wrap
	# under themselves instead.
	risk_frame = PanelContainer.new()
	risk_frame.size_flags_horizontal = Control.SIZE_SHRINK_END
	risk_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	risk_sb_lit = _risk_style(Color(0.34, 0.10, 0.09, 0.82), Color(0.92, 0.44, 0.30, 0.90))
	risk_sb_cold = _risk_style(Color(0.14, 0.15, 0.21, 0.60), Color(0.42, 0.44, 0.52, 0.60))
	top.add_child(risk_frame)
	UI.hoverable(risk_frame, "AT RISK: found this run, but only kept if you beat the boss or use an Escape Rope.")

	var stake := HBoxContainer.new()
	stake.add_theme_constant_override("separation", UITheme.sep(14))
	risk_frame.add_child(stake)
	risk_label = Label.new()
	risk_label.add_theme_font_size_override("font_size", UITheme.title_font())
	stake.add_child(risk_label)
	ropes_label = Label.new()
	ropes_label.add_theme_font_size_override("font_size", UITheme.title_font())
	stake.add_child(ropes_label)

	floor_box = HFlowContainer.new()
	floor_box.add_theme_constant_override("h_separation", UITheme.sep(16))
	header.add_child(floor_box)
	UI.hoverable(floor_box, "This floor: how deep you are, how much of its encounter quota you have cleared, and how much of its ground you have seen.")

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
	floor_view.custom_minimum_size = _view_size()
	floor_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# the plate is larger than this window on purpose, so the overhang is cut off
	# rather than painted over the header and the buttons
	floor_view.clip_contents = true
	# The painted art is smooth, and project.godot sets NEAREST globally for the pixel
	# assets — which aliases a downscaled 256px sprite badly (ART_ASSETS.md's rule).
	# REPEAT is what lets a tile's UVs run outside 0..1 so each diamond can show a
	# different patch of the seamless stone instead of the floor reading as wallpaper.
	floor_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	floor_view.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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

	# Collection and Menu SIDE BY SIDE, not stacked (D114). Two full-width bars cost
	# 100px of a 720px frame between them, and captured at the shipped size rather than
	# on a taller desktop, Menu was sliced in half by the bottom edge — the column had
	# been overflowing for as long as the header wrapped. Neither button is pressed
	# often enough on this screen to have earned the whole width, and nothing here is
	# allowed to take the missing height off the floor viewport.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(foot)

	var coll := Button.new()
	UITheme.style_button(coll)
	coll.text = "Collection"
	coll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	foot.add_child(coll)
	# same Callable on the button and on Escape, so the two cannot drift apart
	var menu := UI.exit_button(foot, "Menu", func(): UI.goto(self, "res://scenes/PauseMenu.tscn"))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## The at-risk frame in one of its two states. Local to this screen rather than in
## UITheme: it is one HUD element with a lit and an unlit face, not a style the rest
## of the game shares.
func _risk_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = UITheme.px(12)
	sb.content_margin_right = UITheme.px(12)
	sb.content_margin_top = UITheme.px(2)
	sb.content_margin_bottom = UITheme.px(2)
	return sb

# --- geometry -----------------------------------------------------------------

func _tile() -> Vector2:
	return Vector2(UITheme.px(TILE_W), UITheme.px(TILE_H))

## The whole diamond plate, most of which is off-window at any moment.
func _plate_size() -> Vector2:
	var t := _tile()
	var g := _grid()
	return Vector2(float(g.x + g.y) * t.x * 0.5, float(g.x + g.y) * t.y * 0.5 + t.y)

## The window onto it.
func _view_size() -> Vector2:
	return Vector2(UITheme.px(VIEW_W), UITheme.px(VIEW_H))

func _grid() -> Vector2i:
	var tv := GameState.traversal as TraversalIso
	return tv.grid() if tv != null else Vector2i(Balance.ISO_GRID, Balance.ISO_GRID)

## Grid cell -> the middle of its diamond, in PLATE coordinates (camera not yet
## applied). Everything drawn adds `cam`; everything clicked subtracts it.
func _to_plate(x: int, y: int) -> Vector2:
	var t := _tile()
	var g := _grid()
	return Vector2(
		(float(x - y) + float(g.y)) * t.x * 0.5,
		float(x + y) * t.y * 0.5 + t.y * 0.5)

## Where the camera has to sit to keep `cell` in the middle of the window.
##
## Deliberately NOT clamped to the plate. Clamping is the right move for a board the
## player can see all of, and wrong here for two reasons the first capture showed
## plainly: a diamond plate's bounding box has four empty corners, so clamping near
## an edge pushed the player token off to one side of the window with dead space
## opposite it; and past the edge of what you have explored there is nothing to keep
## in view anyway. Centring always means the floor scrolls under a token that stays
## put, which is what makes a big floor read as movement rather than as a map.
## Takes a PLATE position rather than a cell, so a step can be half-taken. That is the
## whole of what makes walking continuous here: the hero and the camera are derived
## from the same interpolated point, so she stays nailed to `EYE_Y` and the floor
## slides under her, exactly as it does when she is standing still.
func _camera_for(at: Vector2) -> Vector2:
	var view := _view_size()
	return Vector2(view.x * 0.5, view.y * EYE_Y) - at

## Where the player is right now in plate coordinates: the cell centre when standing,
## the point between two cells while a step is being taken.
func _eye_plate(tv: TraversalIso) -> Vector2:
	var g := tv.grid()
	var to := _to_plate(tv.pos % g.x, int(tv.pos / g.x))
	if walk_t >= 1.0:
		return to
	# linear, deliberately. An ease on each step reads fine once and stutters the
	# moment steps are chained, which is the case hold-to-walk makes ordinary.
	return walk_from.lerp(to, walk_t)

## The inverse, for clicking on the floor. Rounded to the nearest cell centre,
## which treats each diamond as its bounding box near the corners — close enough
## to pick a tile, and the buttons are there for anyone it misjudges.
func _to_cell(p: Vector2) -> Vector2i:
	var t := _tile()
	var g := _grid()
	var q := p - cam
	var fx := (q.x / (t.x * 0.5)) - float(g.y)
	var fy := (q.y - t.y * 0.5) / (t.y * 0.5)
	return Vector2i(int(round((fy + fx) * 0.5)), int(round((fy - fx) * 0.5)))

# --- drawing ------------------------------------------------------------------

## Is this block standing between the camera and the player, close enough to hide her?
##
## On this projection both grid axes run away from the viewer, so `x + y` IS depth: a
## bigger sum is nearer the camera. Only blocks within a couple of tiles are faded, or
## a whole quadrant of the dungeon would go translucent and the floor would stop
## reading as solid.
func _occludes_player(x: int, y: int, tv: TraversalIso) -> bool:
	var g := tv.grid()
	var px: int = tv.pos % g.x
	var py: int = int(tv.pos / g.x)
	if x + y <= px + py:
		return false
	return absi(x - px) <= 2 and absi(y - py) <= 2

## Does this cell touch ground the player knows about? Used to decide whether a
## piece of rock is a wall worth drawing or just unexplored nothing. Diagonals count,
## so an outside corner does not come out notched.
func _walls_known_ground(tv: TraversalIso, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if tv.lit(x + dx, y + dy) or tv.frontier(x + dx, y + dy):
				return true
	return false

func _draw_floor() -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var t := _tile()
	var g := tv.grid()
	var reach := {}
	for o in tv.options():
		reach[int(o["cell"])] = true
	var threats := tv.threats()
	cam = _camera_for(_eye_plate(tv))
	var window := Rect2(Vector2.ZERO, _view_size()).grow(maxf(t.x, t.y))
	## rock standing between the camera and the player, drawn last and translucent
	var near_walls: Array = []

	# TWO passes, and the split is load-bearing. Ground first, everything that stands
	# on it second — because a sprite is taller than its tile, so drawing each tile
	# with its own contents let the next row's floor slice the legs off whatever was
	# standing behind it. Ground is flat and cannot occlude anything; standing art is
	# ordered back to front among itself and gets it right.
	for y in g.y:
		for x in g.x:
			var i: int = y * g.x + x
			var centre := _to_plate(x, y) + cam
			if not window.has_point(centre):
				continue    # off-window: the plate is a good deal larger than the view
			var e := tv.cell(x, y)
			var seen := tv.lit(x, y)
			var is_rock: bool = e == TraversalIso.WALL or (not seen and not tv.frontier(x, y))
			# Rock is drawn ONLY where it walls in ground you know about. Painting every
			# unknown cell was right on a 6x6 plate, where it read as the stone the rooms
			# were cut out of; on a 12x12 plate it is 130-odd black diamonds and the
			# capture came back as one enormous dark polygon filling the window with a
			# few grey tiles adrift in it. Hugging the explored edge gives the same "cut
			# out of stone" reading with a shape that grows as the floor is learned,
			# which is the thing this model is for.
			if is_rock:
				continue    # rock is a BLOCK, drawn in the standing pass below
			var quad := _diamond(centre, t)
			var tint := TINT_FRONTIER
			if seen:
				tint = TINT_WALKED if tv.trodden(x, y) else TINT_OPEN
			_draw_ground(quad, x, y, tint, "floor")
			# Only the tiles you can step into are outlined (D87). Every tile used to
			# carry a hairline, and on a floor of seamless stone that hairline WAS the
			# grid — the one thing left saying "this ground is made of cells" once the
			# material and the blocks were doing their job. Without it neighbouring tiles
			# at the same tint merge into continuous stone and the fog does the
			# delineating, which is what it was always drawing anyway. The reach
			# highlight stays because it is an affordance, not a lattice: at most four
			# of them, and clicking is still a way to move.
			if reach.has(i):
				floor_view.draw_polyline(quad + PackedVector2Array([quad[0]]),
					COL_REACH, UITheme.px(3.0))

	# Pass 2: everything with height, back to front — walls AND standing art together,
	# because they occlude each other. A wall in front of a monster has to be able to
	# hide its legs, which cannot happen if all the walls are drawn in the flat pass.
	for y in g.y:
		for x in g.x:
			var i2: int = y * g.x + x
			var c2 := _to_plate(x, y) + cam
			if not window.has_point(c2):
				continue
			var e2 := tv.cell(x, y)
			var rock2: bool = e2 == TraversalIso.WALL \
				or (not tv.lit(x, y) and not tv.frontier(x, y))
			if rock2:
				if _walls_known_ground(tv, x, y):
					# A block between the camera and the player is held back for the
					# last pass, where it is drawn translucent OVER her. Painting it
					# normally and then painting her on top made her look like she was
					# standing on the wall rather than behind it — which on a floor of
					# one-tile corridors is most of the time, because the tile in front
					# of you is usually stone.
					if _occludes_player(x, y, tv):
						near_walls.append(Vector2i(x, y))
					else:
						_draw_wall(c2, t, x, y)
				continue
			if not tv.lit(x, y):
				continue
			if e2 == TraversalIso.STAIR:
				_draw_stair(c2, t)
				continue
			# the furniture and the things that wait for you
			if e2 >= 0:
				var role := _role_of(e2)
				# A fight is drawn as the SILHOUETTE of the creature actually standing
				# there, not as a generic slab per encounter tier. `_role_of` stays as the
				# fallback for a tile with no cast enemy and for a save from before the
				# floor knew what it was showing.
				var cast := tv.enemy_at(x, y)
				if cast != "" and art.has("mon_%s_s" % Balance.iso_family(cast)):
					role = "mon_%s_s" % Balance.iso_family(cast)
				if role != "":
					_draw_standing(role, c2, t, 1.0, _size_key_for(e2))
			# a wanderer, only while it is actually in sight — deliberately NOT sticky
			# like the terrain is, so the floor behind you is known ground with unknown
			# things on it
			if threats.has(i2):
				var m: Dictionary = threats[i2]
				var face: String = "s" if bool(m["south"]) else "n"
				var mrole := "wander_%d_%s" % [int(m["design"]) % WANDER_DESIGNS, face]
				var mcast := String(m.get("enemy", ""))
				if mcast != "":
					var famrole := "mon_%s_%s" % [Balance.iso_family(mcast), face]
					if art.has(famrole):
						mrole = famrole
				_draw_standing(mrole, c2 + _mon_slide(i2), t, 1.0, "wander")

	# The player goes LAST, over everything, deliberately breaking the depth order the
	# pass above is careful about. Correct depth put a rock block between the camera and
	# the player whenever one stood in the row in front, and hid them behind it — which
	# is realistic and unplayable. Being able to see where you are outranks being
	# occluded correctly by a wall you are standing behind.
	_draw_you(_eye_plate(tv) + cam, t)

	# ...and the near-side rock goes over her, at a third strength. So the wall is still
	# there, she is still legibly *behind* it, and you can see where you are — which is
	# the whole reason the depth order gets bent here at all.
	for p in near_walls:
		var pv: Vector2i = p
		_draw_wall(_to_plate(pv.x, pv.y) + cam, t, pv.x, pv.y,
			Color(1, 1, 1, OCCLUDER_ALPHA))

## The tile's diamond, in draw order top / right / bottom / left.
func _diamond(centre: Vector2, t: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		centre + Vector2(0, -t.y * 0.5), centre + Vector2(t.x * 0.5, 0),
		centre + Vector2(0, t.y * 0.5), centre + Vector2(-t.x * 0.5, 0)])

## A block of rock: the top face lifted by WALL_LIFT, plus the two faces that face the
## camera. The two sides get different tints — one catches what light there is and one
## does not — because with a single flat tint a run of blocks reads as one shapeless
## mass rather than as separate stones.
##
## Faces are parallelograms, so the same exact UV trick as the floor applies: four
## corners to the four corners of the material, no seam and no distortion.
## `wash` multiplies all three faces, which is how a sealed vault is drawn: the same
## stone block in a warmer colour, so it reads as masonry that belongs to the dungeon
## rather than as a UI marker sitting on top of it.
func _draw_wall(centre: Vector2, t: Vector2, x: int, y: int,
		wash: Color = Color(1, 1, 1)) -> void:
	var lift := Vector2(0, -t.y * WALL_LIFT)
	var top := centre + Vector2(0, -t.y * 0.5)
	var right := centre + Vector2(t.x * 0.5, 0)
	var bottom := centre + Vector2(0, t.y * 0.5)
	var left := centre + Vector2(-t.x * 0.5, 0)
	var tex: Texture2D = art.get("rock")
	var square := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	# left face, then right face, then the top — painter's order within one block
	var faces := [
		[PackedVector2Array([left + lift, bottom + lift, bottom, left]), TINT_WALL_L],
		[PackedVector2Array([bottom + lift, right + lift, right, bottom]), TINT_WALL_R],
		[PackedVector2Array([top + lift, right + lift, bottom + lift, left + lift]), TINT_WALL_TOP],
	]
	for f in faces:
		var poly: PackedVector2Array = f[0]
		var tint: Color = Color(f[1]) * wash
		if tex == null:
			floor_view.draw_colored_polygon(poly, tint * 0.5)
		else:
			floor_view.draw_colored_polygon(poly, tint, square, tex)

## The way down: a hole, drawn as the *inverse* of a wall block — nested diamonds
## stepping down into the dark, with a lit lip.
##
## Deliberately the loudest thing the floor draws, and the first attempt was not. A dark
## hole on dark stone is nearly invisible, which is exactly wrong for **the single tile
## the whole floor is a search for**: everything else here can be missed and found later,
## and this is the one the player is looking for. There is no stair art in any pack, so
## the weight has to come from contrast.
func _draw_stair(centre: Vector2, t: Vector2) -> void:
	var mouth := _diamond(centre, t * 0.94)
	floor_view.draw_colored_polygon(mouth, Color(0.05, 0.05, 0.07))
	# three steps down, each smaller and darker, so it reads as depth and not as a stain
	for s in 3:
		var k: float = 0.72 - 0.18 * float(s)
		var v: float = 0.045 - 0.012 * float(s)
		floor_view.draw_colored_polygon(
			_diamond(centre + Vector2(0, t.y * (0.05 + 0.05 * float(s))), t * k),
			Color(v, v, v * 1.3))
	floor_view.draw_polyline(mouth + PackedVector2Array([mouth[0]]),
		Color(0.96, 0.82, 0.42, 0.95), UITheme.px(3.0))

## One ground diamond, with the stone material projected onto it.
##
## The material is a flat seamless top-down texture, not a pre-drawn iso tile, so the
## projection is done here: the diamond's four corners map to the four corners of the
## unit square, which IS an isometric view of a square tile and is exact rather than
## approximate (a diamond is a parallelogram, so the affine UV interpolation across
## the two triangles has no seam).
##
## Each tile is offset into the material by an irrational-ish per-cell amount so the
## floor does not read as wallpaper. Integer offsets would have been useless — the
## material is seamless, so shifting by a whole period gives the identical patch back.
func _draw_ground(quad: PackedVector2Array, x: int, y: int, tint: Color, role: String) -> void:
	var tex: Texture2D = art.get(role)
	if tex == null:
		floor_view.draw_colored_polygon(quad, tint * 0.5)
		return
	var off := Vector2(
		fposmod(float(x) * 0.37 + float(y) * 0.11, 1.0),
		fposmod(float(y) * 0.41 + float(x) * 0.17, 1.0))
	var uvs := PackedVector2Array([
		Vector2(0, 0) + off, Vector2(1, 0) + off,
		Vector2(1, 1) + off, Vector2(0, 1) + off])
	floor_view.draw_colored_polygon(quad, tint, uvs, tex)

## Which SPRITE_H entry a tile's art is sized by. The silhouette says what kind of fight
## it is and the size says how big a fight — so an elite swarm is spiders drawn large
## rather than a different creature, and the two readings stay independent.
func _size_key_for(e: int) -> String:
	match e:
		TraversalIso.Enc.ELITE: return "elite"
		TraversalIso.Enc.BOSS: return "boss"
		TraversalIso.Enc.COMBAT: return "combat"
	return ""

## Encounter value -> the art role that represents it. Kept apart from the drawing so
## the mapping reads as content wiring rather than as a branch inside a loop.
func _role_of(e: int) -> String:
	match e:
		TraversalIso.Enc.COMBAT: return "combat"
		TraversalIso.Enc.ELITE: return "elite"
		TraversalIso.Enc.BOSS: return "boss"
		TraversalIso.Enc.SHOP: return "shop"
		TraversalIso.Enc.REST: return "rest"
		TraversalIso.Enc.EVENT: return "event"
		TraversalIso.Enc.TREASURE: return "treasure"
	return ""

## A sprite standing ON a tile: anchored by its feet at the middle of the diamond,
## which works without a per-file offset table because the installer trims each source
## to its own silhouette (so bottom-centre IS the foot point).
##
## Falls back to the flat encounter glyph the other three traversal views use, so an
## uninstalled art set reads as unfinished instead of invisible.
func _draw_standing(role: String, centre: Vector2, t: Vector2, alpha: float,
		size_key: String = "") -> void:
	var tex: Texture2D = art.get(role)
	var key: String = size_key if size_key != "" else role
	if tex == null:
		var glyph := Icons.for_encounter(_enc_of(role))
		if glyph != null:
			var s: float = minf(t.x * 0.42, t.y * 0.8)
			floor_view.draw_texture_rect(glyph,
				Rect2(centre - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), false)
		return
	floor_view.draw_texture_rect(tex, _footed_rect(tex, centre, t, key), false,
		Color(1, 1, 1, alpha))

## Where a sprite goes if its feet are at the middle of `centre`'s tile, sized by
## SPRITE_H. Shared by the standing art and by the player, so the hero cannot end up
## standing on a subtly different spot than the monster next to her.
func _footed_rect(tex: Texture2D, centre: Vector2, t: Vector2, key: String) -> Rect2:
	var h: float = t.y * float(SPRITE_H.get(key, 1.8))
	var w: float = h * float(tex.get_width()) / float(tex.get_height())
	# feet slightly forward of the tile's exact centre, so the figure stands in the
	# diamond rather than balancing on its back corner
	var foot := centre + Vector2(0, t.y * 0.16)
	return Rect2(foot - Vector2(w * 0.5, h), Vector2(w, h))

## The reverse of `_role_of`, for the glyph fallback only.
func _enc_of(role: String) -> int:
	match role:
		"elite": return TraversalIso.Enc.ELITE
		"boss": return TraversalIso.Enc.BOSS
		"shop": return TraversalIso.Enc.SHOP
		"rest": return TraversalIso.Enc.REST
		"event": return TraversalIso.Enc.EVENT
		"treasure": return TraversalIso.Enc.TREASURE
	return TraversalIso.Enc.COMBAT

## The player: the hero sprite, footed on her tile exactly like a monster is, over a
## ring of light on the ground.
##
## The ring is NOT decoration and is drawn whether or not the sprite exists. A lone
## figure on a floor of textured stone, at a size where she is two tiles tall and the
## window is scrolling under her, is genuinely hard to pick out — and knowing where you
## are is the one thing this screen cannot fail at. Being findable beats being pure.
##
## If the hero art is not installed the ring keeps its old companion, a lantern-bright
## pip, so an empty `assets/art/iso/` still gives a playable, legible marker rather than
## a floor with nobody on it.
func _draw_you(centre: Vector2, t: Vector2) -> void:
	# offset to the same place the feet land, not to the tile's exact centre, so the ring
	# closes around the boots instead of trailing a hoop's worth of floor in front of them
	_ground_ring(centre + Vector2(0, t.y * 0.04), t, 0.30,
		Color(COL_YOU.r, COL_YOU.g, COL_YOU.b, 0.55))
	var tex: Texture2D = art.get("hero_s" if face_south else "hero_n")
	if tex != null:
		floor_view.draw_texture_rect(tex, _footed_rect(tex, centre, t, "hero"), false)
		return
	# no hero installed: the pip is what the eye tracks while the floor scrolls underneath
	floor_view.draw_circle(centre - Vector2(0, t.y * 0.30), t.y * 0.17,
		Color(0.05, 0.07, 0.10, 0.85))
	floor_view.draw_circle(centre - Vector2(0, t.y * 0.32), t.y * 0.13, COL_YOU)

## A ring lying ON the ground, `r` of a tile across. Flattened 2:1 like every other
## shape on this floor, because a true circle stops reading as a patch of lit floor the
## moment there is a figure standing in it — it becomes a hoop the figure is inside.
## `draw_arc` can only give the circle, hence the polyline.
func _ground_ring(centre: Vector2, t: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a: float = TAU * float(i) / 32.0
		pts.append(centre + Vector2(cos(a) * t.x * r, sin(a) * t.y * r))
	floor_view.draw_polyline(pts, col, UITheme.px(2.5), true)

# --- walking -------------------------------------------------------------------
#
# All of this is PRESENTATION. The model still takes one discrete step per call to
# `select()`, `steps` still counts them one for one, and the moves-per-encounter
# ceiling `tests/test_traversal.gd` enforces is untouched — a walk is the same turn
# it always was, drawn over STEP_TIME seconds instead of instantly. That separation
# is the whole reason the grid was kept when the *look* of the grid was dropped
# (D87): a continuous world would have had no move to count, and the pillar that
# every traversal model costs the same is measured in moves.

## How far a monster drawn at `cell` should be slid back toward where it came from.
##
## It is drawn at its DESTINATION tile's turn in the depth sort and offset from there,
## so for the length of one step it can be up to a tile out of order with the blocks
## around it. The honest alternative is re-sorting the standing pass by interpolated
## depth every frame, which costs a sort per redraw to fix an error that lasts an
## eighth of a second and is one tile wide.
func _mon_slide(cell: int) -> Vector2:
	if walk_t >= 1.0 or not walk_mons.has(cell):
		return Vector2.ZERO
	var from: Vector2 = walk_mons[cell]
	return from.lerp(Vector2.ZERO, walk_t)

func _process(delta: float) -> void:
	if walk_t >= 1.0:
		return
	walk_t = minf(1.0, walk_t + delta / STEP_TIME)
	if floor_view != null:
		floor_view.queue_redraw()
	if walk_t >= 1.0 and walk_more:
		var d := _dir_held()
		if d >= 0:
			_step_dir(d)

## Start animating the step just taken. Everything here is derived from a snapshot
## caught before `select()` ran, because the model has already moved by the time this
## is called and there is nothing left in it saying where anyone stood.
func _begin_walk(tv: TraversalIso, from_cell: int, from_depth: int,
		from_threats: Dictionary) -> void:
	walk_mons = {}
	walk_t = 1.0
	# A descent is not a walk across a floor, it is a different floor. Sliding the
	# camera from a cell on the old one to a cell on the new one would draw a line
	# between two places that are not next to each other.
	if tv.depth != from_depth or tv.pos == from_cell:
		return
	var g := tv.grid()
	walk_from = _to_plate(from_cell % g.x, int(from_cell / g.x))
	walk_t = 0.0

	# Match each wanderer now in sight to where it stood a moment ago. There is no id
	# on a monster, so this goes by design and type within one step — which is exact
	# whenever it matters, because a wanderer moves at most one tile per turn and two
	# of the same design standing within a tile of each other are, visibly, the same
	# thing twice. A monster with no match simply appears, which is what a monster
	# stepping into sight is supposed to do.
	var used := {}
	for c in tv.threats():
		var m: Dictionary = tv.threats()[c]
		for oc in from_threats:
			if used.has(oc):
				continue
			var o: Dictionary = from_threats[oc]
			if int(o["design"]) != int(m["design"]) or int(o["type"]) != int(m["type"]):
				continue
			if absi(int(oc) % g.x - int(c) % g.x) + absi(int(int(oc) / g.x) - int(int(c) / g.x)) > 1:
				continue
			used[oc] = true
			walk_mons[c] = _to_plate(int(oc) % g.x, int(int(oc) / g.x)) \
				- _to_plate(int(c) % g.x, int(int(c) / g.x))
			break

## The direction of a movement key being held right now, or -1. Insertion order
## decides ties, so W/Up wins over the rest — arbitrary, and only reachable by
## holding two directions at once.
func _dir_held() -> int:
	for k in MOVE_KEYS:
		if Input.is_key_pressed(k):
			return int(MOVE_KEYS[k])
	return -1

## Walk one step in a grid direction, if there is an exit that way.
func _step_dir(d: int) -> void:
	if walk_t < 1.0:
		return
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var opts := tv.options()
	for i in opts.size():
		if int(opts[i]["dir"]) == d:
			_on_pick(i)
			return
	# Nothing that way. Worth a line rather than silence — a key that does nothing
	# reads as a key that is not bound.
	log_label.text = "Solid rock that way."

func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	# `echo` is the OS key-repeat, and it is dropped on purpose: repeat arrives far
	# faster than STEP_TIME and would spend turns at the keyboard's rate rather than
	# the walk's. Holding a key still walks — `_process` picks it up when the current
	# step lands, which paces it.
	if k == null or not k.pressed or k.echo or not MOVE_KEYS.has(k.keycode):
		return
	get_viewport().set_input_as_handled()
	_step_dir(int(MOVE_KEYS[k.keycode]))

func _on_floor_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if walk_t < 1.0:
		return    # a step is in progress; the turn it belongs to is already spent
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

## Break `TraversalIso.status()` back into its phrases.
##
## The model hands back a string already glued together with runs of spaces, and that
## gluing is the whole defect: nothing downstream can then break the line anywhere except
## inside a phrase. Splitting on the runs gives each fact back its own Label.
##
## `GameState.risk_line()` had the same shape and no longer needs this — it hands over
## `risk_parts()` now (D116). `status()` was left joined on purpose rather than half
## migrated with it: it is a virtual on the `Traversal` seam (`scripts/traversal.gd`), so
## a parts accessor is the base class's to declare or every future model gets to invent
## its own name for it, and the seam is a wider change than one screen's header.
##
## Runs of two or more, so a phrase's own single spaces survive.
func _phrases(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in line.split("  ", false):
		var s: String = String(p).strip_edges()
		if s != "":
			out.append(s)
	return out

## Lay `parts` out along one header row, reusing the Labels already in it.
##
## A pool rather than the free-and-rebuild `moves_box` uses: the header
## is rewritten on every step, and a step is a TURN, so freeing Labels leaves a frame in
## which the container has both the old set and the new one — a flicker on the one line
## the player reads constantly. Extra Labels are hidden, and a hidden child is not laid
## out, so a row whose fact count varies (a floor with nothing prowling, a run with no
## keys) closes up cleanly.
func _fill_row(box: Container, parts: PackedStringArray, size: int, ink: Color) -> void:
	while box.get_child_count() < parts.size():
		var made := Label.new()
		made.add_theme_font_size_override("font_size", size)
		box.add_child(made)
	for i in box.get_child_count():
		var lbl := box.get_child(i) as Label
		lbl.visible = i < parts.size()
		if lbl.visible:
			lbl.text = parts[i]
			# re-asserted every time, so a chip that went red last step goes back
			lbl.add_theme_color_override("font_color", ink)

func _refresh_header(tv: TraversalIso) -> void:
	var dd := GameState.dungeon_data()
	_fill_row(vitals_box, PackedStringArray([
		"%s (d%d)" % [dd.name if dd != null else "Dungeon", GameState.dungeon],
		"HP %d/%d" % [GameState.hp, GameState.max_hp],
		"Deck %d" % GameState.run_deck.size(),
		"Gold %d" % MetaState.gold]), UITheme.title_font(), STAT_INK)
	if GameState.hp * HURT_AT <= GameState.max_hp:
		(vitals_box.get_child(1) as Label).add_theme_color_override("font_color", HURT_INK)

	# One string, read straight: `risk_line()` is now nothing but the escrow facts, so
	# there is no tail to split off and move (D116). It stays ONE Label rather than one
	# per phrase, unlike the two rows either side of it: the frame is what marks the
	# escrow total as a single thing, and a total broken across two rows inside one frame
	# would read as two alarms rather than as one that wrapped.
	risk_label.text = GameState.risk_line()
	ropes_label.text = "Ropes %d" % MetaState.item_count("escape_rope")
	# Lit only when there is something in escrow, and GameState is asked rather than
	# told: deciding that here out of the four lists is a second definition of "at risk"
	# living a file away from the one that prints it, free to drift the next time
	# something becomes forfeitable (D34, D116).
	var staked := GameState.at_risk()
	risk_frame.add_theme_stylebox_override("panel", risk_sb_lit if staked else risk_sb_cold)
	var stake_ink := RISK_LIT if staked else RISK_COLD
	risk_label.add_theme_color_override("font_color", stake_ink)
	ropes_label.add_theme_color_override("font_color", stake_ink.darkened(0.18))

	var below := _phrases(tv.status())
	# Keys go with the floor's bookkeeping, not inside a frame that means "this can be
	# taken off you": they are spent on this floor or wasted, never forfeited. This used
	# to be done by stripping them off the tail of `risk_line()`; GameState hands them
	# over as their own phrase now, and says there why they are not in that sentence at
	# all any more (D116).
	var held := GameState.keys_phrase()
	if held != "":
		below.append(held)
	_fill_row(floor_box, below, UITheme.font(), FLOOR_INK)

func _refresh() -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		log_label.text = "No dungeon in progress."
		call_deferred("_leave")
		return

	_refresh_header(tv)

	if tv.is_complete():
		call_deferred("_leave")
		return

	if floor_view != null:
		floor_view.custom_minimum_size = _view_size()
		# also set here, not only in the draw, so a click that arrives before the
		# first redraw is converted with a camera that exists
		cam = _camera_for(_eye_plate(tv))
		floor_view.queue_redraw()

	for c in moves_box.get_children():
		c.queue_free()
	var opts := tv.options()
	var stair_found := false
	for i in opts.size():
		var o: Dictionary = opts[i]
		var d: int = int(o["dir"])
		var b := Button.new()
		var label: String = o["label"]
		b.custom_minimum_size = Vector2(UITheme.px(MOVE_BUTTON.x), UITheme.px(MOVE_BUTTON.y))
		if int(o["type"]) == GameState.NodeType.BOSS:
			stair_found = true
			# the finale is named before it is entered, on every model (D41)
			var boss := Balance.boss_of(GameState.dungeon_id)
			if boss != null:
				label = "%s  BOSS: %s" % [TraversalIso.DIR_ARROW[d], boss.name]
				UI.hoverable(b, "%s\n%s" % [
					boss.name, Balance.boss_warning(GameState.dungeon_id)])
		# The key letter sits on the button rather than in a legend, because the
		# keyboard mapping is a 45-degree rotation nobody can infer (D87) — this is
		# where it gets taught, in the two steps it takes to read one.
		b.text = "%s %s" % [DIR_KEY[d], label]
		if int(o["type"]) != GameState.NodeType.BOSS:
			UI.hoverable(b, "Or press %s. Hold it to keep walking." % DIR_KEY[d])
		b.pressed.connect(_on_pick.bind(i))
		moves_box.add_child(b)

	# The hint is the state of the floor, most urgent first. Something in sight outranks
	# the way down: the stairs will still be there in three turns and the thing walking
	# toward you will be somewhere else. A sealed vault comes next, because it is the one
	# thing on the floor with no button next to it and so the one that needs explaining.
	var near := tv.threats().size()
	var last: bool = tv.depth == tv.floors - 1
	var hint := "A room opens up as you enter it; a passage shows you nothing. The way down is somewhere on this floor."
	if near > 0:
		hint = "Something is moving nearby. It takes a step whenever you do." if near == 1 \
			else "%d things are moving nearby. They take a step whenever you do." % near
	elif stair_found:
		hint = "The way down is right there. Anything you leave up here, you leave behind." if last \
			else "Stairs down, right there. This floor keeps whatever you do not take now."
	elif tv.mons.size() > 0:
		hint = "Something else is walking this floor. You cannot hear it from here."
	elif not last:
		hint = "A room opens up as you enter it; a passage shows you nothing. The stairs down are somewhere on this floor."
	hint_label.text = hint

func _on_pick(i: int) -> void:
	var tv := GameState.traversal as TraversalIso
	if tv == null:
		return
	var opts := tv.options()
	if i < 0 or i >= opts.size():
		return
	var was_seen := tv.lit(int(opts[i]["cell"]) % tv.grid().x, int(int(opts[i]["cell"]) / tv.grid().x))
	# read before select(), which is what changes them
	var was_kind := int(opts[i]["type"])
	var from_floor := tv.depth
	# Snapshot for the walk animation: once select() runs, nothing in the model says
	# where anyone was standing a moment ago.
	var from_cell := tv.pos
	var from_threats := tv.threats()
	# Turn to face the step BEFORE taking it: `dir` indexes TraversalIso.DIRS, and a step
	# whose grid components sum positive goes down the screen (x is ↘ and y is ↙, per
	# DIR_ARROW) — the same test TraversalIso uses to face a wanderer.
	var step: Vector2i = TraversalIso.DIRS[int(opts[i]["dir"])]
	face_south = (step.x + step.y) > 0
	# Slipping past a fight is priced on the OPTION, so it is read before the move and paid
	# here — the model reports a price and never touches run HP (D13), the same contract the
	# old deck model's dodge always had. Clamped so it can never itself be lethal.
	var slip := int(opts[i].get("hp_cost", 0)) if String(opts[i].get("action", "")) == "avoid" else 0
	var chosen := tv.select(i)
	if slip > 0:
		GameState.hp = maxi(1, GameState.hp - slip)
		Audio.play("hurt")
		log_label.text = "You squeeze past it. -%d HP." % slip
		GameState.autosave()
		_refresh()
		return
	if chosen.is_empty():
		# Four different things a step that resolves nothing can be. Descending and
		# picking up a key both come back as {} — they are handled inside the model so
		# that RunFlow never has to learn a node type that is not an encounter — so this
		# is the only place they can be reported to the player at all.
		if tv.depth != from_floor:
			log_label.text = "You take the stairs down to floor %d." % (tv.depth + 1)
		elif not was_seen:
			log_label.text = "You press on into the dark."
		else:
			log_label.text = "You cross ground you have already walked."
		# A held key rolls into the next step only across ground that resolved nothing,
		# on the same floor, with nothing NEW in sight. Anything else earns a stop: the
		# player who walked into a corridor and found something there has a decision in
		# front of them, and continuing to walk through it because a key is still down
		# is the one way this feature could cost them a run.
		walk_more = tv.depth == from_floor and tv.threats().size() <= from_threats.size()
		_begin_walk(tv, from_cell, from_floor, from_threats)
		GameState.autosave()
		_refresh()
		return
	walk_more = false
	if bool(chosen.get("ambush", false)):
		# Paid here rather than in the traversal, for the same reason the old deck model's
		# dodge is: the model is pure logic and never reads or writes run HP. Clamped
		# so it can never itself be lethal — a wanderer can corner you on a floor with
		# one way out, and a price with no counterplay that kills is a trap.
		var bite := Balance.iso_ambush_cost(GameState.max_hp)
		GameState.hp = maxi(1, GameState.hp - bite)
		log_label.text = "It was on you before you saw it. -%d HP." % bite
		Audio.play("hurt")
	GameState.pending = chosen
	if RunFlow.enter_node(self, chosen, _after_rest):
		_refresh()

func _after_rest() -> void:
	log_label.text = "Rested."
	_refresh()

func _leave() -> void:
	get_tree().change_scene_to_file(RunFlow.leave_run())
