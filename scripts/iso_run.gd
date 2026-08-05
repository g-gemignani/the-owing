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
## What the LIGHT FIELD does to a tile, on top of the three tints above (D176).
##
## The tints were doing two jobs at once: they are the fog (have I been here) and they were
## also the only illumination the floor had, which is why the whole screen read at one
## value. State keeps its job — it is the map of your own route and a model about coverage
## needs it — and light is a second multiply on top, from `TraversalIso.light`.
##
## The range is deliberately asymmetric. `LIGHT_LIT` is over 1.0 so a tile with a brazier on
## it is *brighter* than walked stone rather than merely equal to it, which is what makes a
## lit room read as lit; `LIGHT_DIM` is well short of zero because the darkest thing on this
## screen must still be legible ground.
const LIGHT_DIM := 0.72
const LIGHT_LIT := 1.34
## Fire, and daylight a long way up a shaft. The hue is applied only as strongly as the
## light carrying it, so an unlit tile is never tinted by a source three rooms away.
const LIGHT_WARM := Color(1.10, 1.00, 0.84)
const LIGHT_COLD := Color(0.86, 0.95, 1.16)
## How dark the decoration on a tile is against the ground it lies on, and how pale wall
## dressing is against the rock face behind it (D176). Multipliers on the tile's own lit
## tint rather than colours of their own: a prop is the same stone in shadow, and a second
## palette here is a second palette to drift from the first.
const PROP_DARK := 0.62
const PROP_PALE := 1.28
const COL_REACH := Color(0.98, 0.78, 0.35)   ## an exit you can walk through now
const COL_YOU := Color(0.55, 0.90, 1.0)
const COL_THREAT := Color(1.0, 0.36, 0.34)   ## something walking, while you can see it
## What light a chest of each tier stands in — multiplied onto the sprite, so a channel over
## 1.0 brightens (D172).
##
## There is ONE painted chest and three tiers, and the tier is the lock, so the tiers have to
## be told apart at a glance from across a room. A ring on the ground was the first answer
## and it is not enough: a thin outline under a two-tile-tall sprite is read after the sprite,
## if at all. Lighting the object is read WITH it.
##
## The values are `Icons.pack_tier_colour` pushed off 1.0 rather than a second palette:
## gilded burns warm and over-bright, sealed is cool and pale, worn is dimmed and slightly
## drained — the same three readings the chest screen's headline and the pack list use, which
## is the point. Worn is the one that goes DOWN, because "nothing special" has to look like
## nothing special or all three are special.
const TIER_LIGHT := {
	Balance.PACK_WORN: Color(0.82, 0.80, 0.76),
	Balance.PACK_SEALED: Color(0.92, 1.00, 1.16),
	Balance.PACK_GILDED: Color(1.34, 1.06, 0.52),
}

## Standing art, keyed the way `install_iso_art.gd` names it. Loaded once rather than
## per redraw, and every lookup tolerates a missing file: art that has not been
## installed must degrade to the drawn floor, not crash a run.
const ART_DIR := "res://assets/art/iso/"
## Suffix for the mirrored copy of a sprite in `art` and `stand`. Not a file on disk.
const FLIP := "_flip"
## On-screen height of each sprite, as a multiple of the tile's height. A sprite is
## anchored by its FEET — horizontally by its own stand point, measured from the art
## (`IsoFooting.offset`), which is why only a height is needed here.
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
## role -> where that sprite's feet are, as a signed fraction of its own width from the
## middle of the canvas. Measured from the art at load (`IsoFooting.offset`), never typed.
var stand := {}
## The last step taken, kept as a grid vector because FOUR directions have to come out
## of it and two booleans could not.
##
## This was `face_south := (x + y) > 0` and that is half a facing model. The grid's four
## directions project to the four screen DIAGONALS — `x` runs ↘ and `y` runs ↙ (see
## `TraversalIso.DIR_ARROW`) — so that test maps ↘ and ↙ both onto "toward the camera"
## and ↖ and ↗ both onto "away". Walking right and walking left drew the same sprite,
## which is what makes the hero look wrong while a floor is being explored: she never
## turns (D131).
##
## Four facings, two files: `x + y` picks toward-camera against away, and `IsoFooting`
## decides which of the pair is the painting and which is its mirror, from the diagonal each
## file was painted looking along. That decision is NOT the symmetric one this comment used
## to describe ("the larger x is the right-hand one, drawn as painted") — the two paintings
## are one character turned around, so they look at opposite sides of the screen and no
## symmetric rule can suit both pairs (D154).
##
## Pure view state, deliberately not saved and not in the model — the rules do not care
## where she is looking, and a resumed run starts her facing down-right, toward the
## player and toward the side the eye reads first.
var face_step := Vector2i(1, 0)
## One key of the movement pad, and the pad's inset from the corner of the floor window
## (D168).
##
## The pad replaced a ROW of move buttons — one per exit, relabelled and rebuilt on every
## step, so their count and their order changed underneath the finger about to press one.
## That row is what a spatial model should never have had: walking is not a menu of
## choices, it is four directions that are always the same four, and the only thing that
## varies is which of them is rock. So the pad has a fixed size in a fixed place and its
## keys grey out instead of vanishing.
##
## It is drawn INSIDE the floor window rather than under it. The column is full — the
## layout test allows the floor 400px of a 720px frame and the header, the two text lines
## and the footer own the rest — and a pad tall enough for a thumb does not fit in the 46px
## the old row used. Over the floor it costs nothing, and it is where a phone's thumb
## already is.
const PAD_KEY := Vector2(88.0, 66.0)
const PAD_INSET := 18.0
## A contextual button under the floor: the offers that are NOT movement (slipping past a
## fight). Kept as buttons on every platform on purpose — a price you pay in HP is a
## decision and belongs in words, where the pad only says which way.
const ACT_BUTTON := Vector2(300.0, 46.0)

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
## The letter bound to each direction, indexed like `TraversalIso.DIRS`. Shown on the
## keyboard legend under the floor, and in each pad key's tooltip.
const DIR_KEY := ["D", "A", "S", "W"]
## Where each direction sits on the pad, as a cell of a 3x3 grid — the shape of a
## handheld's cross, with the middle empty.
##
## Cross positions, not the four diagonals of the projection they actually walk. The
## diagonal layout was the geometrically honest one and it was tried first: it puts each
## key exactly where its arrow points, and it also puts two keys under the thumb at once,
## because a diamond of four buttons has no gap between adjacent pairs. A cross is the
## shape every player already has a thumb habit for, and the mismatch it leaves — up walks
## you up-and-right — is settled the way D87 settled it for the keyboard: the key carries
## the arrow of where it actually goes, so it is read rather than inferred.
const PAD_CELL := {3: 1, 0: 5, 2: 7, 1: 3}   # dir -> index into the 3x3 grid

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
var acts_box: HBoxContainer   ## the offers that are not movement
var legend_label: Label       ## the key mapping, where there is a keyboard to use it
var pad: GridContainer        ## the movement pad, over the floor
## dir -> its key on the pad, so `_refresh` can grey one out without rebuilding the pad.
## The pad is the one part of this screen that is built ONCE: a control that is freed and
## remade every turn is a control that can move under a finger already on its way down.
var pad_keys: Dictionary = {}
## The pad key being held right now, or -1. Hold-to-walk works off the pad exactly as it
## does off the keyboard — `_process` reads this the same way it reads a held key.
var pad_dir: int = -1

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
				# floor and rock are surfaces, not figures — they have no stand point
				if r != "floor" and r != "rock":
					stand[r] = IsoFooting.offset(tex)
				# The hero is the only art the floor mirrors, and the mirror is a TEXTURE
				# rather than a flipped rect (D154). Built once here: her left-hand facings
				# then draw through exactly the same code as her right-hand ones, with the
				# anchor negated, and no call site has to remember what a negative width does.
				if r == "hero_s" or r == "hero_n":
					var flip := IsoFooting.flipped(tex)
					if flip != null:
						art[r + FLIP] = flip
						stand[r + FLIP] = -float(stand.get(r, 0.0))
	# EVERY terrain's surface, each under its own key, rather than the dungeon's one pair
	# overwriting the generic one. A dungeon's floors no longer share a terrain (D177): the
	# surface turns a floor before the architecture does, so the drawing asks the MODEL what
	# the floor it is looking at is made of (`_surface` below) and a descent changes the
	# ground without reloading anything. A terrain with no art installed simply has no key
	# and falls back to the generic pair, which is what a checkout with no iso art draws.
	for t in Balance.ISO_TERRAINS:
		for pair in ["floor", "rock"]:
			var tpath: String = "%s%s_%s.png" % [ART_DIR, pair, t]
			if ResourceLoader.exists(tpath):
				var ttex := load(tpath) as Texture2D
				if ttex != null:
					art["%s_%s" % [pair, t]] = ttex

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

	_build_pad()

	# The mapping, for the machines that walk with keys. It is a STATIC line, which is the
	# whole difference from the row of move buttons it replaces: it says what the four keys
	# do and never changes, where the buttons said what was adjacent and changed every step.
	# Hidden when the pad is up, because then it is teaching a keyboard that is not there.
	legend_label = Label.new()
	legend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend_label.add_theme_color_override("font_color", FLOOR_INK)
	# Read in the order the hand sits, W A S D, not in the order `TraversalIso.DIRS`
	# happens to be declared in: the legend is for the player, and "D A S W" is a list of
	# four letters where "W A S D" is a shape they already know.
	var legend: Array[String] = []
	for letter in ["W", "A", "S", "D"]:
		var d: int = DIR_KEY.find(letter)
		if d >= 0:
			legend.append("%s %s" % [letter, TraversalIso.DIR_ARROW[d]])
	legend_label.text = "%s     or click a lit tile" % "    ".join(legend)
	root.add_child(legend_label)

	acts_box = HBoxContainer.new()
	acts_box.alignment = BoxContainer.ALIGNMENT_CENTER
	acts_box.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(acts_box)

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
	coll.text = "Cards"   # one screen, one name (D133)
	coll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coll.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	foot.add_child(coll)
	# same Callable on the button and on Escape, so the two cannot drift apart
	var menu := UI.exit_button(foot, "Menu", func(): UI.goto(self, "res://scenes/PauseMenu.tscn"))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## The movement pad: four keys in a cross, in the bottom-left corner of the floor window,
## built once and never rebuilt (D168).
##
## Bottom-LEFT because that is where a pad goes on the machine this exists for, and because
## the floor is scrolled to keep the player at the middle of the window — the corner is the
## part of the view with the least in it. Anchored to the corner rather than laid out in the
## column, so it costs the floor no height at all.
##
## Only added to the tree when it is going to be shown. A hidden pad is a cheap thing to
## carry, but it is also four buttons sitting over the floor that swallow clicks meant for
## the tiles underneath them, and `visible = false` is a promise the next edit can break by
## accident.
func _build_pad() -> void:
	pad_keys = {}
	if not UI.pad_visible():
		return
	pad = GridContainer.new()
	pad.columns = 3
	pad.add_theme_constant_override("h_separation", UITheme.sep(6))
	pad.add_theme_constant_override("v_separation", UITheme.sep(6))
	# Only the four keys take a press. The grid and its five empty cells are 260x200 of
	# floor otherwise gone deaf, and clicking a lit tile is a way to move on this screen
	# too — the pad must not quietly delete it from its own corner.
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The pad's own size is what the anchors position, so it is measured before it is
	# placed: three keys and two gaps each way.
	var key := Vector2(UITheme.px(PAD_KEY.x), UITheme.px(PAD_KEY.y))
	var span := Vector2(key.x * 3.0 + float(UITheme.sep(6)) * 2.0,
		key.y * 3.0 + float(UITheme.sep(6)) * 2.0)
	var by_cell := {}
	for d in PAD_CELL:
		by_cell[int(PAD_CELL[d])] = int(d)
	for c in 9:
		if not by_cell.has(c):
			# the four corners and the middle: spacers, so the cross keeps its shape
			var gap := Control.new()
			gap.custom_minimum_size = key
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pad.add_child(gap)
			continue
		var d: int = int(by_cell[c])
		var b := Button.new()
		UITheme.style_button(b, true)
		b.custom_minimum_size = key
		b.text = TraversalIso.DIR_ARROW[d]
		b.add_theme_font_size_override("font_size", UITheme.title_font())
		# Never takes focus: a pad key that keeps focus would then answer to Enter and
		# Space as well, which on this screen means walking without meaning to.
		b.focus_mode = Control.FOCUS_NONE
		# Held, not clicked. `pressed` fires on release, and hold-to-walk needs to know the
		# finger is still down — so the step is taken on the way DOWN and `pad_dir` is what
		# `_process` reads to roll into the next one.
		b.button_down.connect(func():
			pad_dir = d
			_step_dir(d))
		b.button_up.connect(func():
			if pad_dir == d:
				pad_dir = -1)
		UI.hoverable(b, "%s   (or the %s key). Hold to keep walking." % [
			TraversalIso.DIR_ARROW[d], DIR_KEY[d]])
		pad.add_child(b)
		pad_keys[d] = b
	floor_view.add_child(pad)
	pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pad.offset_left = UITheme.px(PAD_INSET)
	pad.offset_top = -span.y - UITheme.px(PAD_INSET)
	pad.offset_right = pad.offset_left + span.x
	pad.offset_bottom = -UITheme.px(PAD_INSET)

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
			var tints := PackedColorArray([tint, tint, tint, tint])
			if seen:
				# State per TILE, light per CORNER (D176). The state tint keeps its hard
				# edges — it is the map of your own route and a blurred route is not one —
				# and the light is interpolated across the diamond, which is what stops the
				# light field from redrawing the grid D87 deleted. See `_draw_ground`.
				#
				# The frontier is deliberately left out of the multiply: it is the edge of
				# what you know rather than ground you can see the light on, and it is the
				# constant D89 warns about — 0.20 through a 0.72 floor is 0.14, which is
				# where "nearly out" becomes "black". A constant has to survive the
				# transform applied to it, and the cheapest way for this one to survive is
				# not to be transformed.
				tint = TINT_WALKED if tv.trodden(x, y) else TINT_OPEN
				tints = _corner_tints(tv, x, y, tint)
			_draw_ground(quad, x, y, tints, _surface(tv, "floor"))
			# ...and whatever is lying on it. Ground clutter only, drawn UNDER everything
			# that stands on the tile, because it is part of the floor and not a thing on it.
			if seen:
				_draw_prop(tv.prop_shape(x, y), centre, t, _lit(tv, x, y, tint), x, y)
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
					if i2 == tv.landmark:
						# The one oversized thing on the floor (D177). It stands in rock, so
						# it is drawn here, in the pass that owns height — and it is NEVER
						# held back as an occluder, because a landmark is a bearing and a
						# bearing you can only see at a third strength is not one. The player
						# is drawn after this pass regardless, so she is still on top of it.
						_draw_landmark(c2, t, x, y, tv)
					elif _occludes_player(x, y, tv):
						near_walls.append(Vector2i(x, y))
					else:
						_draw_wall(c2, t, x, y, Color(1, 1, 1), tv)
				continue
			if not tv.lit(x, y):
				continue
			if e2 == TraversalIso.STAIR:
				_draw_stair(c2, t)
				continue
			if e2 == TraversalIso.KEY:
				_draw_key(c2, t)
				continue
			if e2 == TraversalIso.SHRINE:
				_draw_shrine(c2, t)
				continue
			# the furniture and the things that wait for you
			if e2 >= 0:
				# A chest is lit by its own tier, and states its lock on the ground it stands
				# on, before the step that reaches it is taken (D172). The light goes down
				# first, under the sprite: it is a property of the chest, not a badge over it.
				var chest_tier := ""
				if e2 == TraversalIso.Enc.TREASURE:
					chest_tier = tv.chest_at(x, y)
					_draw_chest_lock(c2, t, chest_tier)
				var role := _role_of(e2)
				# A fight is drawn as the SILHOUETTE of the creature actually standing
				# there, not as a generic slab per encounter tier. `_role_of` stays as the
				# fallback for a tile with no cast enemy and for a save from before the
				# floor knew what it was showing.
				var cast := tv.enemy_at(x, y)
				if cast != "" and art.has("mon_%s_s" % Balance.iso_family(cast)):
					role = "mon_%s_s" % Balance.iso_family(cast)
				if role != "":
					_draw_standing(role, c2, t, 1.0, _size_key_for(e2),
						TIER_LIGHT.get(chest_tier, Color(1, 1, 1)))
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
			Color(1, 1, 1, OCCLUDER_ALPHA), tv)

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
##
## `tv` is what the block asks how lit it is and what is nailed to it (D176). Optional so
## the tool renders in `tools/` can draw a bare block, and because a null model has to
## degrade to the old flat stone rather than to no wall at all. `lift` scales the block's
## height, which is how a landmark is drawn as the same masonry standing taller (D177).
func _draw_wall(centre: Vector2, t: Vector2, x: int, y: int,
		wash: Color = Color(1, 1, 1), tv: TraversalIso = null,
		lift_mult: float = 1.0) -> void:
	var lift := Vector2(0, -t.y * WALL_LIFT * lift_mult)
	var top := centre + Vector2(0, -t.y * 0.5)
	var right := centre + Vector2(t.x * 0.5, 0)
	var bottom := centre + Vector2(0, t.y * 0.5)
	var left := centre + Vector2(-t.x * 0.5, 0)
	var tex: Texture2D = art.get(_surface(tv, "rock"))
	# Rock takes the light of the brightest floor beside it (TraversalIso._build_light), so
	# a wall beside a brazier is masonry in firelight rather than a black edge to a lit room.
	if tv != null:
		wash = wash * _lit(tv, x, y, Color(1, 1, 1))
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
	# Wall dressing goes on the right-hand face, which is the lit one of the two and the one
	# a 2:1 projection gives the most area to. On the face rather than on the top, because a
	# ring or a run of roots is a thing on a WALL — put on the top it reads as litter on a
	# ledge the player might be able to stand on.
	if tv != null:
		var shape := tv.prop_shape(x, y)
		if shape != "":
			_draw_wall_prop(shape, centre + Vector2(t.x * 0.25, -t.y * 0.25)
				+ lift * 0.5, t, Color(TINT_WALL_R) * wash)
		# ...and a mark, if this is a wall with something behind it and the player is close
		# enough to make it out (D182).
		var cell_here: int = y * tv.grid().x + x
		if tv.mark_visible(cell_here):
			_draw_mark(centre + Vector2(t.x * 0.25, -t.y * 0.25) + lift * 0.5, t, wash)
		elif tv.door_visible(cell_here):
			_draw_door(centre + Vector2(t.x * 0.25, -t.y * 0.25) + lift * 0.5, t, wash)

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

## The light a chest stands in, and what it wants, drawn on the ground under it (D172).
##
## The tier IS the lock (`Balance.chest_lock`), so drawing the tier draws the lock and the
## reading comes out for free. Three things carry it, at three distances:
##
## * **A pool of light** in the tier's colour, which is what makes the tile findable across a
##   room. Filled diamonds at falling alpha rather than one outline, because a hairline ring
##   under a two-tile-tall sprite is read after the sprite if it is read at all.
## * **The sprite lit by the same colour** (`TIER_LIGHT`, applied by the caller), which is
##   what makes the CHEST the thing you recognise rather than a marker beside it.
## * **The key silhouette**, at half size, for a key lock only — and it is the same drawing
##   the floor uses for a key lying on it. That is deliberate: "this wants that" is a sentence
##   a picture can say and a colour cannot.
##
## A worn chest gets the sprite's dimming and nothing on the ground. A pool of light under
## every chest in the game would mean nothing under any of them, and "nothing here to solve"
## is exactly what an unlocked chest should look like from a distance.
func _draw_chest_lock(centre: Vector2, t: Vector2, tier: String) -> void:
	if tier == "":
		return
	var lock := Balance.chest_lock(tier)
	if lock == Balance.CHEST_LOCK_NONE:
		return
	# SATURATED, not the ink itself. `Icons.pack_tier_colour` is a colour for text on a dark
	# panel, and walked stone is already pale (TINT_WALKED) — sealed's parchment grey laid on
	# it at low alpha is grey on grey. Squaring each channel pushes the hue away from white
	# without inventing a second palette to drift from the first.
	var ink := Icons.pack_tier_colour(tier)
	var pool := Color(minf(1.0, ink.r * ink.r * 1.2), minf(1.0, ink.g * ink.g * 1.2),
		minf(1.0, ink.b * ink.b * 1.2))
	# Three filled diamonds, widest and faintest first: a pool with a hot middle, which on a
	# 2:1 projection is what light lying on a floor looks like. Drawn on the ground pass's
	# tile, so it never covers the chest — the sprite goes down after it.
	for step in 3:
		var r: float = 0.92 - 0.24 * float(step)
		var a: float = 0.14 + 0.12 * float(step)
		floor_view.draw_colored_polygon(_diamond(centre, t * r),
			Color(pool.r, pool.g, pool.b, a))
	_ground_ring(centre, t, 0.44, Color(pool.r, pool.g, pool.b, 0.72))
	if lock == Balance.CHEST_LOCK_KEY:
		# In FRONT of the chest, on the near lip of the diamond, so the sprite's feet do
		# not stand on it and the two shapes read as two things.
		_draw_key(centre + Vector2(0, t.y * 0.30), t, 0.5, 0.95)

## A key lying on the ground: a shaft with a bow at one end and two teeth at the other,
## on a patch of ground it has caught the light of.
##
## Drawn rather than a sprite, like the stair and for the same reason — there is no key in
## any art pack — and it has the stair's problem in reverse. The stair must be the loudest
## thing on the floor because it is what the floor is a search FOR; a key is small, and a
## small dark object on dark stone is nothing. So the shape sits inside a lit patch: the
## glow says "there is something here" from across a room, and the silhouette says what.
## It is deliberately NOT drawn at sprite height — a key stands on nothing, and lifting it
## to eye level would read as a floating icon rather than as an object on the ground.
##
## `scale` and `alpha` exist for the one other caller: a key-locked chest draws this at half
## size on its own tile to say what it wants (D172). Same drawing, deliberately — the mark on
## the lock and the thing lying in the far room are the same object, and one function is what
## keeps them looking like it. The lit patch is dropped when it is a marker: the glow's job is
## to be noticed from across a room, and a chest has already been noticed.
func _draw_key(centre: Vector2, t: Vector2, scale: float = 1.0, alpha: float = 1.0) -> void:
	if scale >= 1.0:
		_ground_ring(centre, t, 0.24, Color(1.0, 0.86, 0.42, 0.42 * alpha))
		floor_view.draw_colored_polygon(_diamond(centre, t * 0.34),
			Color(1.0, 0.84, 0.40, 0.20 * alpha))
	var gold := Color(1.0, 0.88, 0.52, alpha)
	var wide := UITheme.px(3.0) * maxf(0.6, scale)
	var thin := UITheme.px(2.5) * maxf(0.6, scale)
	# Along the tile's long axis, so it lies on the diamond rather than across it.
	var half := t.x * 0.16 * scale
	var lift := -t.y * 0.06 * scale
	var a := centre + Vector2(-half, lift + t.y * 0.05 * scale)
	var b := centre + Vector2(half, lift - t.y * 0.05 * scale)
	floor_view.draw_line(a, b, gold, wide)
	# the bow: a ring at the near end, which is what makes the shape read as a key
	var bow := a + (a - b).normalized() * t.x * 0.045 * scale
	floor_view.draw_arc(bow, t.x * 0.05 * scale, 0.0, TAU, 14, gold, thin)
	# two teeth off the far end, at right angles to the shaft
	var along := (b - a).normalized()
	var side := Vector2(-along.y, along.x) * t.y * 0.11 * scale
	for f in [0.62, 0.86]:
		var root: Vector2 = a + (b - a) * float(f)
		floor_view.draw_line(root, root + side, gold, thin)

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
##
## `tints` is FOUR colours, one per corner, not one for the tile — and that is what keeps
## the light field from undoing D87 (D176). The first version multiplied one flat tint per
## tile, and a capture of the Warrens showed why that is wrong: light falls off in whole
## steps, so every tile came out a different flat value and the hairline grid the per-tile
## outlines were deleted for was back, drawn in illumination instead of in lines. Shading
## per CORNER — each corner being the light averaged over the four tiles that meet at it —
## makes two neighbours share the pair of colours along their shared edge, so the floor is
## continuous again and the light is a gradient across stone rather than a mosaic.
func _draw_ground(quad: PackedVector2Array, x: int, y: int, tints: PackedColorArray,
		role: String) -> void:
	var tex: Texture2D = art.get(role)
	if tex == null:
		var flat := PackedColorArray()
		for c in tints:
			flat.append(Color(c) * 0.5)
		floor_view.draw_polygon(quad, flat)
		return
	var off := Vector2(
		fposmod(float(x) * 0.37 + float(y) * 0.11, 1.0),
		fposmod(float(y) * 0.41 + float(x) * 0.17, 1.0))
	var uvs := PackedVector2Array([
		Vector2(0, 0) + off, Vector2(1, 0) + off,
		Vector2(1, 1) + off, Vector2(0, 1) + off])
	floor_view.draw_polygon(quad, tints, uvs, tex)

# --- the light, the surface, and the things lying about (D176/D177) --------------

## Which surface art this FLOOR is made of. The model records what it was built as rather
## than the view re-deriving it, because a dungeon's floors differ from each other now
## (D177) and two derivations of one fact is the D34 trap. Falls through to the generic
## pair for a terrain with no art installed, and for a null model.
func _surface(tv: TraversalIso, pair: String) -> String:
	if tv == null:
		return pair
	var role := "%s_%s" % [pair, tv.terrain]
	return role if art.has(role) else pair

## The four corner colours of one ground diamond: the tile's own state tint, lit by the
## average of the light at the four tiles meeting at each corner (D176).
##
## `_diamond` draws top / right / bottom / left, and on a 2:1 projection those are the
## lattice points shared with (x-1,y-1), (x+1,y-1), (x+1,y+1) and (x-1,y+1) respectively —
## each corner belongs to four tiles, and averaging over all four is what makes two
## neighbours agree on the pair of colours along the edge they share.
func _corner_tints(tv: TraversalIso, x: int, y: int, base: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var sum := 0.0
		var hue := 0.0
		for q in [Vector2i(0, 0), Vector2i(d.x, 0), Vector2i(0, d.y), d]:
			sum += tv.light(x + q.x, y + q.y)
			hue += tv.light_hue(x + q.x, y + q.y)
		out.append(_lit_by(base, sum * 0.25, hue))
	return out

## A tile's colour once the light field has had its say (D176).
##
## Two multiplies on the state tint, both from `TraversalIso`: how much light reaches this
## tile, and what colour that light is. The hue is scaled by the intensity as well, so a
## tile no source reaches is dimmer but not tinted — a floor washed warm three rooms from
## the nearest brazier would be a floor lit by nothing, which is the flat reading again.
func _lit(tv: TraversalIso, x: int, y: int, base: Color) -> Color:
	if tv == null:
		return base
	return _lit_by(base, tv.light(x, y), tv.light_hue(x, y))

## The same multiply, from an intensity and a hue the caller already has. Split out for
## `_corner_tints`, which averages both over four tiles before applying them once.
func _lit_by(base: Color, v: float, hue: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	var k: float = lerpf(LIGHT_DIM, LIGHT_LIT, v)
	var wash := Color(1, 1, 1)
	if hue > 0.0:
		wash = Color(1, 1, 1).lerp(LIGHT_WARM, v)
	elif hue < 0.0:
		wash = Color(1, 1, 1).lerp(LIGHT_COLD, v)
	return Color(base.r * k * wash.r, base.g * k * wash.g, base.b * k * wash.b, base.a)

## Ground clutter: what is lying on this tile, drawn on the diamond itself (D176).
##
## Drawn rather than sprited, on the precedent the stair, the key and the chest's pool of
## light already set: there is no prop in any art pack, these are shapes rather than
## silhouettes, and D89's finding was precise about which half of that divide code wins —
## seamless materials came out better computed, creatures did not. Ground clutter at 116x58
## is nearer a material than a creature. It also keeps `ART_ASSETS.md` closed at 310/310/0
## instead of opening a sixteen-file shopping list for marks a player reads at a glance.
##
## Every shape is a MULTIPLY of the tile's own lit tint, never a colour of its own, so a
## prop is in the same light as the ground it lies on and there is no second palette here to
## drift from the first. And every one of them is deliberately unlike the interactive art:
## nothing here is a box, a figure, or a thing standing up at sprite height, because the
## floor's whole contract is that what stands on a tile is what you get (D85, D172).
##
## `x`/`y` seed the variation, the way `_draw_ground` seeds its UVs — the same shape has to
## look slightly different on two tiles or a store of six crates reads as wallpaper.
func _draw_prop(shape: String, centre: Vector2, t: Vector2, tint: Color,
		x: int, y: int) -> void:
	if shape == "":
		return
	var dark := Color(tint.r * PROP_DARK, tint.g * PROP_DARK, tint.b * PROP_DARK, 1.0)
	var jit := fposmod(float(x) * 0.61 + float(y) * 0.29, 1.0) - 0.5
	var jit2 := fposmod(float(y) * 0.53 + float(x) * 0.37, 1.0) - 0.5
	var off := Vector2(t.x * 0.16 * jit, t.y * 0.16 * jit2)
	match shape:
		"cracks":
			# Two or three hairlines along the tile's long axis. The one shape that says
			# "this floor is old" without adding an object to it.
			for k in 3:
				var f: float = -0.26 + 0.26 * float(k)
				var a := centre + off + Vector2(-t.x * 0.30, t.y * (f + 0.10 * jit))
				var b := centre + off + Vector2(t.x * 0.28, t.y * (f - 0.08 * jit2))
				floor_view.draw_line(a, b, Color(dark.r, dark.g, dark.b, 0.55),
					UITheme.px(1.6))
		"slab":
			# A fallen slab: a small diamond lying flat, with one lifted edge so it reads as
			# something ON the floor rather than a stain in it. The lit edge is a HAIRLINE
			# and the face is darker than the ground — the same rule the pile learned, from
			# the same capture, where a slab drawn pale read as a sheet of paper.
			var quad := _diamond(centre + off + Vector2(0, t.y * 0.06), t * 0.42)
			floor_view.draw_colored_polygon(quad, Color(dark.r, dark.g, dark.b, 0.90))
			floor_view.draw_line(quad[3], quad[0],
				Color(tint.r, tint.g, tint.b, 0.70), UITheme.px(1.6))
		"pile":
			# A heap: three small diamonds stacked back to front, each a little higher and a
			# little paler, which at this size is what a pile of anything looks like.
			#
			# Every value here stays BELOW the ground it lies on, and that is the whole
			# lesson of the first attempt. Four diamonds ending at 1.10 of the floor's tint
			# came out, in a capture of the Warrens, as a stack of white paper lying next to
			# the hero — brighter than anything else on the screen, hard-edged, and reading
			# as an object the player might be able to pick up. A heap on a dark floor is
			# dark: it is read by its SHAPE, and the shape only reads if it is not competing
			# with the hero and the chest for the brightest thing in the frame.
			for k in 3:
				var s: float = 0.24 - 0.05 * float(k)
				var up: float = -t.y * (0.01 + 0.05 * float(k))
				var side: float = t.x * 0.08 * (jit if k % 2 == 0 else jit2)
				var pale: float = PROP_DARK + 0.07 * float(k)
				floor_view.draw_colored_polygon(
					_diamond(centre + off + Vector2(side, up + t.y * 0.10), t * s),
					Color(tint.r * pale, tint.g * pale, tint.b * pale, 0.92))
		"growth":
			# Patches: soft blobs pushed to the tile's edges, so growth reads as coming IN
			# from the walls rather than as something planted in the middle of the room.
			for k in 3:
				var ang: float = TAU * (float(k) / 3.0 + 0.13 * jit)
				var at := centre + Vector2(cos(ang) * t.x * 0.28, sin(ang) * t.y * 0.28)
				floor_view.draw_circle(at, t.y * (0.12 + 0.05 * jit2),
					Color(dark.r * 0.9, dark.g * 1.05, dark.b * 0.85, 0.62))
		"drift":
			# Silt: two shallow wedges lying along the tile, pale rather than dark, because
			# what has drifted is lighter than the floor it drifted over.
			for k in 2:
				var pale2 := Color(tint.r * PROP_PALE, tint.g * PROP_PALE,
					tint.b * PROP_PALE, 0.34 + 0.14 * float(k))
				var wedge := PackedVector2Array([
					centre + off + Vector2(-t.x * (0.34 - 0.10 * float(k)), t.y * 0.04),
					centre + off + Vector2(0, -t.y * (0.14 - 0.05 * float(k))),
					centre + off + Vector2(t.x * (0.30 - 0.10 * float(k)), t.y * 0.06),
					centre + off + Vector2(0, t.y * (0.16 - 0.04 * float(k)))])
				floor_view.draw_colored_polygon(wedge, pale2)
		"scatter":
			# Debris: six small marks. The quietest entry in the table on purpose — it is
			# what a corridor gets, and a corridor with as much in it as a store is a floor
			# with no store in it.
			for k in 6:
				var a2: float = TAU * (float(k) / 6.0 + 0.21 * jit2)
				var r2: float = t.x * (0.10 + 0.16 * fposmod(float(k) * 0.37 + jit, 1.0))
				floor_view.draw_circle(
					centre + Vector2(cos(a2) * r2, sin(a2) * r2 * 0.5),
					UITheme.px(1.8), Color(dark.r, dark.g, dark.b, 0.72))
		"ring":
			# An iron ring set in the floor. Drawn here as well as on a wall face because a
			# terrain lists a prop as wall dressing and the ground pass never asks — the
			# table is what decides, and a shape the drawing cannot render is an invisible
			# prop (`tests/test_traversal.gd` asserts the table names nothing unknown).
			_draw_prop_ring(centre + off, t * 0.5, dark)

## The wall-face version of a prop: the same table, on the vertical (D176).
##
## A separate function rather than a flag, because a face is not a diamond — a shape drawn
## for the ground and reused on a wall comes out lying down on it. Only the shapes that make
## sense hanging are drawn; the rest simply do not appear on rock, which is why the props
## table says which of the two each entry is.
func _draw_wall_prop(shape: String, at: Vector2, t: Vector2, face: Color) -> void:
	var pale := Color(face.r * PROP_PALE, face.g * PROP_PALE, face.b * PROP_PALE, 0.95)
	var dark := Color(face.r * PROP_DARK, face.g * PROP_DARK, face.b * PROP_DARK, 0.85)
	match shape:
		"ring":
			floor_view.draw_arc(at, t.y * 0.16, 0.0, TAU, 16, pale, UITheme.px(2.2))
			floor_view.draw_line(at + Vector2(0, -t.y * 0.16),
				at + Vector2(0, -t.y * 0.30), pale, UITheme.px(2.0))
		"growth":
			# Hanging matter: three strands off the top of the face.
			for k in 3:
				var sx: float = t.x * (0.10 * float(k) - 0.10)
				floor_view.draw_line(at + Vector2(sx, -t.y * 0.34),
					at + Vector2(sx + t.x * 0.02, t.y * (0.02 + 0.08 * float(k))),
					Color(dark.r * 0.9, dark.g * 1.08, dark.b * 0.85, 0.70),
					UITheme.px(2.0))
		"cracks":
			for k in 2:
				floor_view.draw_line(at + Vector2(-t.x * 0.10, -t.y * (0.30 - 0.14 * float(k))),
					at + Vector2(t.x * 0.10, t.y * (0.06 + 0.08 * float(k))),
					Color(dark.r, dark.g, dark.b, 0.60), UITheme.px(1.6))
		"slab", "pile", "scatter", "drift":
			# Ground shapes, and they stay on the ground. Nothing drawn: the props table
			# marks these `ground`, so reaching here means a floor was dressed by a table
			# that changed under it, and a wall with a heap of bones stuck to it at
			# eye level is a worse answer than a plain wall.
			pass

## The mark on a wall with something behind it (D182).
##
## A crack running the height of the face, with a draught of paler stone bleeding out of it —
## a hairline would be missed and a glowing sigil would be the game pointing at the answer.
## The reading has to be *this stone is not like the rest of it*, which is a difference in
## texture rather than a badge, and it has to survive being seen for exactly as long as the
## player stands beside it.
##
## Deliberately NOT in the reach colour or any UI ink. `COL_REACH` says "you can step here"
## and a mark says the opposite — there is a wall here and it can be pushed. Drawn in the
## wall's own light for the reason a landmark is (D177): a feature in its own palette reads
## as a marker laid over the floor rather than as part of the building.
func _draw_mark(at: Vector2, t: Vector2, wash: Color) -> void:
	var pale := Color(TINT_WALL_TOP.r * wash.r * 1.42, TINT_WALL_TOP.g * wash.g * 1.42,
		TINT_WALL_TOP.b * wash.b * 1.34, 0.95)
	var dark := Color(TINT_WALL_L.r * wash.r * 0.7, TINT_WALL_L.g * wash.g * 0.7,
		TINT_WALL_L.b * wash.b * 0.7, 0.95)
	# The crack: three segments that do not line up, because a straight line reads as
	# masonry and a jointed one reads as a failure in it.
	var top := at + Vector2(-t.x * 0.02, -t.y * 0.40)
	var mid := at + Vector2(t.x * 0.04, -t.y * 0.12)
	var low := at + Vector2(-t.x * 0.01, t.y * 0.14)
	floor_view.draw_line(top, mid, dark, UITheme.px(3.0))
	floor_view.draw_line(mid, low, dark, UITheme.px(2.4))
	# ...and the draught out of it, offset so the crack still reads as the darker of the two.
	floor_view.draw_line(top + Vector2(t.x * 0.02, 0), mid + Vector2(t.x * 0.02, 0),
		pale, UITheme.px(1.6))
	floor_view.draw_line(mid + Vector2(t.x * 0.02, 0), low + Vector2(t.x * 0.02, 0),
		pale, UITheme.px(1.4))

## A shut door in a wall face, with a keyhole in it (D185).
##
## Loud where the mark is quiet, and that is the difference between the two ways a pocket is
## shut. A mark asks you to notice, so it is a crack you can only read from beside it. A door
## asks you to bring something, so it has to be legible from across a room — otherwise the
## decision it offers (go and get the key, or spend it on the chest you can also see) is one
## the player never gets to make.
##
## Drawn in the KEY's gold rather than the wall's stone, because it is the one thing on a wall
## that answers a question the header is also answering ("you have one" / "you do not"), and
## the two have to look like they are about the same object — the same argument that made the
## chest's lock draw the key silhouette (D172).
func _draw_door(at: Vector2, t: Vector2, wash: Color) -> void:
	var gold := Color(0.86 * wash.r, 0.72 * wash.g, 0.36 * wash.b, 0.95)
	var dark := Color(TINT_WALL_L.r * wash.r * 0.55, TINT_WALL_L.g * wash.g * 0.55,
		TINT_WALL_L.b * wash.b * 0.55, 0.95)
	# The leaf: a tall panel set into the face, darker than the stone around it.
	var leaf := PackedVector2Array([
		at + Vector2(-t.x * 0.11, -t.y * 0.40),
		at + Vector2(t.x * 0.11, -t.y * 0.29),
		at + Vector2(t.x * 0.11, t.y * 0.16),
		at + Vector2(-t.x * 0.11, t.y * 0.05)])
	floor_view.draw_colored_polygon(leaf, dark)
	floor_view.draw_polyline(leaf + PackedVector2Array([leaf[0]]), gold, UITheme.px(2.0))
	# ...and the keyhole, which is the whole message.
	floor_view.draw_circle(at + Vector2(t.x * 0.05, -t.y * 0.09), UITheme.px(2.4), gold)

## A standing stone: a slab set upright in the ground, with a worn hollow in it (D188).
##
## Drawn rather than sprited, on the same precedent as the stair, the key and the door — there
## is no shrine in any art pack, and this is a shape rather than a silhouette (D89). Taller
## than anything else the floor draws flat, because it is the one piece of terrain that is a
## DECISION: it has to be visible from across a room or the choice it offers is one the player
## walks past without knowing it was there.
func _draw_shrine(centre: Vector2, t: Vector2) -> void:
	var stone := Color(0.62, 0.60, 0.66)
	var lit := Color(0.80, 0.78, 0.84)
	# a shadow on the ground, so it reads as standing rather than lying
	floor_view.draw_colored_polygon(_diamond(centre + Vector2(0, t.y * 0.06), t * 0.42),
		Color(0.05, 0.05, 0.08, 0.45))
	var slab := PackedVector2Array([
		centre + Vector2(-t.x * 0.13, -t.y * 0.06),
		centre + Vector2(-t.x * 0.10, -t.y * 0.86),
		centre + Vector2(t.x * 0.10, -t.y * 0.80),
		centre + Vector2(t.x * 0.13, t.y * 0.02)])
	floor_view.draw_colored_polygon(slab, stone)
	floor_view.draw_polyline(slab + PackedVector2Array([slab[0]]), lit, UITheme.px(2.0))
	# the hollow: what has been worn into it by whatever has been done here before
	floor_view.draw_circle(centre + Vector2(0, -t.y * 0.46), t.x * 0.045,
		Color(0.18, 0.17, 0.22))

## An iron ring lying in the floor.
func _draw_prop_ring(centre: Vector2, t: Vector2, ink: Color) -> void:
	floor_view.draw_arc(centre, t.y * 0.30, 0.0, TAU, 16, Color(ink.r, ink.g, ink.b, 0.85),
		UITheme.px(2.0))

## The one landmark on the floor: a rock block standing much taller than its neighbours,
## with one mark on it that says which it is (D177).
##
## Built out of `_draw_wall` rather than beside it, so a landmark is the same masonry in the
## same light as the wall it stands in — a feature drawn in its own palette would read as a
## UI marker on the floor, which is the mistake `_draw_chest_lock` avoided by lighting the
## chest instead of ringing it.
##
## Four kinds and no more, because each one has to be read at a glance from the far side of
## a dark room, and because it is drawn: there is no landmark in any art pack, and a
## silhouette is the half of the divide code loses (D89).
func _draw_landmark(centre: Vector2, t: Vector2, x: int, y: int, tv: TraversalIso) -> void:
	var kind: String = String(Balance.ISO_LANDMARKS[
		tv.landmark_kind % Balance.ISO_LANDMARKS.size()])
	var tall := 2.1 if kind != "dome" else 1.35
	_draw_wall(centre, t, x, y, Color(1, 1, 1), tv, tall)
	var cap := centre + Vector2(0, -t.y * WALL_LIFT * tall)
	var wash := _lit(tv, x, y, Color(1, 1, 1))
	match kind:
		"shaft":
			# Daylight a long way up. Three nested diamonds brightening upward on the cap,
			# and a pale column above it — the one thing on the floor that emits rather than
			# reflects, which is what makes it visible from further than anything else.
			for k in 3:
				var s: float = 0.86 - 0.24 * float(k)
				var a: float = 0.16 + 0.20 * float(k)
				floor_view.draw_colored_polygon(_diamond(cap, t * s),
					Color(0.86, 0.92, 1.0, a))
			var beam := PackedVector2Array([
				cap + Vector2(-t.x * 0.20, 0), cap + Vector2(t.x * 0.20, 0),
				cap + Vector2(t.x * 0.09, -t.y * 1.5), cap + Vector2(-t.x * 0.09, -t.y * 1.5)])
			floor_view.draw_colored_polygon(beam, Color(0.80, 0.88, 1.0, 0.13))
		"dome":
			# A dome that came down: a low mound of masonry, deliberately SHORTER than the
			# other three, because the reading is a roof at head height rather than a tower.
			#
			# FILLED, and inside the block's own footprint. Drawn first as three nested arcs
			# it came out of a capture of the Ossuary as a grey wireframe rainbow hanging in
			# the dark air beside a wall — a UI marker on the floor, which is exactly what
			# `_draw_chest_lock` avoided by lighting the chest instead of ringing it. A
			# landmark has to be MASS in the same stone and the same light as the wall it
			# stands in, or it is a decal.
			for k in 3:
				var r: float = t.x * (0.36 - 0.09 * float(k))
				var seat := cap + Vector2(0, t.y * (0.06 - 0.10 * float(k)))
				var arc := PackedVector2Array()
				for s in 13:
					var a3: float = PI + PI * float(s) / 12.0
					arc.append(seat + Vector2(cos(a3) * r, sin(a3) * r * 0.5))
				arc.append(seat + Vector2(r, 0))
				arc.append(seat + Vector2(-r, 0))
				var v3: float = 0.86 + 0.10 * float(k)
				floor_view.draw_colored_polygon(arc,
					Color(TINT_WALL_TOP.r * wash.r * v3, TINT_WALL_TOP.g * wash.g * v3,
						TINT_WALL_TOP.b * wash.b * v3, 1.0))
		"stair":
			# A stair going nowhere: the way down's drawing inverted — steps RISING off the
			# block and stopping. Deliberately the same shape as the stair, because that is
			# the joke and because a player who reads it as a stair and walks over to it
			# learns something about the place rather than losing a turn (it stands in rock,
			# so there is nothing to walk onto).
			for k in 4:
				var up := cap + Vector2(t.x * 0.06 * float(k), -t.y * 0.15 * float(k))
				var v5: float = 1.0 + 0.08 * float(k)
				floor_view.draw_colored_polygon(_diamond(up, t * (0.66 - 0.12 * float(k))),
					Color(TINT_WALL_TOP.r * wash.r * v5, TINT_WALL_TOP.g * wash.g * v5,
						TINT_WALL_TOP.b * wash.b * v5, 1.0))
		"stack":
			# Bone stacked to the roof: a column of small diamonds. The tightest repetition
			# on the floor, which is what makes it read as *counted* rather than as rubble.
			#
			# In the WALL's tints and not in white. At 0.72-1.02 of full white it came out of
			# the style sheet as a stack of paper floating over a dark block — the same
			# defect as the pile, and worse here because a landmark is the one thing on the
			# floor a player might navigate by. Bone is pale for stone, not pale for a
			# screen: a step above the block top is enough to read as a different material.
			for k in 6:
				var v4: float = 1.28 + 0.06 * float(k)
				floor_view.draw_colored_polygon(
					_diamond(cap + Vector2(t.x * 0.03 * (1 if k % 2 == 0 else -1),
						-t.y * 0.12 * float(k)), t * 0.30),
					Color(TINT_WALL_TOP.r * wash.r * v4, TINT_WALL_TOP.g * wash.g * v4,
						TINT_WALL_TOP.b * wash.b * v4 * 0.94, 1.0))

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

## A sprite standing ON a tile: anchored by its feet at the middle of the diamond.
##
## Falls back to the flat encounter glyph the other three traversal views use, so an
## uninstalled art set reads as unfinished instead of invisible.
##
## `tint` multiplies the art, and channels above 1.0 are how a chest is LIT rather than
## stained (D172): one painted chest has to read as three tiers, and multiplying down only
## ever gives a darker version of the same object. Applied to the glyph fallback too, so a
## checkout with no iso art installed still tells the tiers apart.
func _draw_standing(role: String, centre: Vector2, t: Vector2, alpha: float,
		size_key: String = "", tint: Color = Color(1, 1, 1)) -> void:
	var tex: Texture2D = art.get(role)
	var key: String = size_key if size_key != "" else role
	var ink := Color(tint.r, tint.g, tint.b, alpha)
	if tex == null:
		var glyph := Icons.for_encounter(_enc_of(role))
		if glyph != null:
			var s: float = minf(t.x * 0.42, t.y * 0.8)
			floor_view.draw_texture_rect(glyph,
				Rect2(centre - Vector2(s * 0.5, s * 0.5), Vector2(s, s)), false, ink)
		return
	floor_view.draw_texture_rect(tex, _footed_rect(tex, centre, t, key, role), false, ink)

## Where a sprite goes if it stands at the middle of `centre`'s tile: the size table here,
## the geometry and the stand point in `IsoFooting`. Shared by the standing art and by the
## player, so the hero cannot end up standing on a subtly different spot than the monster
## next to her.
func _footed_rect(tex: Texture2D, centre: Vector2, t: Vector2, key: String,
		role: String) -> Rect2:
	return IsoFooting.rect(tex, centre, t, t.y * float(SPRITE_H.get(key, 1.8)),
		float(stand.get(role, 0.0)))

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
## Which of the four hero draws the current facing resolves to. Exists for the art check,
## which has no other way to say in its own output WHICH state it photographed — and a
## capture that cannot name its state is how three rounds of facing bugs got signed off
## (D155).
func hero_art_name() -> String:
	var role := IsoFooting.hero_role(face_step)
	if IsoFooting.hero_mirrored(face_step) and art.has(role + FLIP):
		role += FLIP
	return role if art.has(role) else "(no art: ring and pip)"

func _draw_you(centre: Vector2, t: Vector2) -> void:
	# offset to the same place the feet land, not to the tile's exact centre, so the ring
	# closes around the boots instead of trailing a hoop's worth of floor in front of them
	_ground_ring(centre + Vector2(0, t.y * 0.04), t, 0.30,
		Color(COL_YOU.r, COL_YOU.g, COL_YOU.b, 0.55))
	# Which painting, and whether it is the mirrored copy: both come from `IsoFooting`, which
	# knows which diagonal each file was painted looking along. The rule that used to live
	# here — unmirrored for whichever of the pair had the larger x — was wrong for one facing
	# of the four no matter what the art did (D154).
	var role := IsoFooting.hero_role(face_step)
	if IsoFooting.hero_mirrored(face_step) and art.has(role + FLIP):
		role += FLIP
	var tex: Texture2D = art.get(role)
	if tex != null:
		floor_view.draw_texture_rect(tex, _footed_rect(tex, centre, t, "hero", role), false)
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

## The direction being held right now, or -1 — a pad key under a finger or a movement key
## under a hand, which hold-to-walk cannot tell apart and should not.
##
## The pad wins, because it can only be held deliberately. Among the keys, insertion order
## decides ties, so W/Up wins over the rest — arbitrary, and only reachable by holding two
## directions at once.
func _dir_held() -> int:
	if pad_dir >= 0:
		return pad_dir
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
	# reads as a key that is not bound. And worth the sound for the same reason, which is
	# the sound of a locked door: `ui_denied` is a thud with no ring in it.
	Audio.play("ui_denied")
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
## A pool rather than the free-and-rebuild `acts_box` uses: the header
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
	# What this floor is asking of you, in the row that already carries the floor's
	# bookkeeping rather than in new chrome (D184). It says the ordinance and never whether
	# it is currently met: an errand that ticked itself green as you walked would turn a thing
	# you are doing into a checklist you are filling in.
	var asked := tv.errand_line()
	if asked != "":
		below.append(asked)
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

	var opts := tv.options()
	# What each direction is: the first option that walks that way, which is the walk
	# itself — a slip past is ranked below everything and is never the first (D88).
	var by_dir := {}
	for i in opts.size():
		var d: int = int(opts[i]["dir"])
		if not by_dir.has(d) and String(opts[i].get("action", "")) != "avoid":
			by_dir[d] = i
	# The way on, adjacent: the boss on the last floor, a stair on every other. Both,
	# because the test was `type == BOSS` alone and a stair's `type` is the STAIR terrain
	# value, never a node type — so "Stairs down, right there" was a line the game could
	# not print, on every floor but the last (D168).
	var stair_found := false
	## The tier of a chest you are standing next to, or "". What it wants is readable from
	## here now that the tier is cast when the floor is laid out (D172).
	var chest_next := ""
	for i in opts.size():
		var cell: int = int(opts[i]["cell"])
		if int(opts[i]["type"]) == GameState.NodeType.BOSS \
				or tv.cell(cell % tv.grid().x, int(cell / tv.grid().x)) == TraversalIso.STAIR:
			stair_found = true
		if int(opts[i]["type"]) == GameState.NodeType.TREASURE:
			# A LOCKED one wins if two are adjacent: the unlocked chest needs nothing said
			# about it, and the locked one is the whole reason this line exists.
			var here := tv.chest_at(cell % tv.grid().x, int(cell / tv.grid().x))
			if chest_next == "" or (Balance.chest_lock(chest_next) == Balance.CHEST_LOCK_NONE
					and Balance.chest_lock(here) != Balance.CHEST_LOCK_NONE):
				chest_next = here

	# The pad greys out rather than shrinking: a direction with rock in it is a key you
	# can see and cannot press, which is a fact about the floor. A row of buttons that
	# came and went could not say that — it just had one fewer button.
	for d in pad_keys:
		var b := pad_keys[d] as Button
		var walkable: bool = by_dir.has(int(d))
		b.disabled = not walkable
		# A held key that greys out mid-hold never emits `button_up`, so hold-to-walk would
		# keep asking for a direction that is now rock. Released here instead.
		if not walkable and pad_dir == int(d):
			pad_dir = -1
		# Lit when there is something that way worth the step, so the pad carries the
		# reading the labels used to: an encounter, a chest, a key, the way down.
		var notable: bool = walkable and int(opts[int(by_dir[int(d)])]["type"]) >= 0
		if walkable and not notable:
			var cell: int = int(opts[int(by_dir[int(d)])]["cell"])
			notable = tv.cell(cell % tv.grid().x, int(cell / tv.grid().x)) \
				in [TraversalIso.STAIR, TraversalIso.KEY]
		b.add_theme_color_override("font_color", COL_REACH if notable else STAT_INK)

	# Everything on offer that is NOT a direction. One kind so far: paying HP to squeeze
	# past a fight instead of having it. These keep their words because the price is the
	# whole decision, and they sit UNDER the floor where a decision is read, not on the pad
	# where the thumb is.
	for c in acts_box.get_children():
		c.queue_free()
	for i in opts.size():
		if String(opts[i].get("action", "")) != "avoid":
			continue
		var act := Button.new()
		UITheme.style_button(act)
		act.custom_minimum_size = Vector2(UITheme.px(ACT_BUTTON.x), UITheme.px(ACT_BUTTON.y))
		act.text = String(opts[i]["label"])
		act.focus_mode = Control.FOCUS_NONE
		act.pressed.connect(_on_pick.bind(i))
		UI.hoverable(act, "Take the tile without the fight. The price rises with each one.")
		acts_box.add_child(act)

	# The legend teaches the keyboard, so it goes where the pad is not.
	legend_label.visible = pad == null

	# The hint is the state of the floor, most urgent first. Something in sight outranks
	# the way down: the stairs will still be there in three turns and the thing walking
	# toward you will be somewhere else. A locked chest comes next, because it is the one
	# thing adjacent to you that asks for something you may not have.
	var near := tv.threats().size()
	var last: bool = tv.depth == tv.floors - 1
	## Is the player standing next to a mark nobody has pushed yet? Outranks everything except
	## something moving, because it is the one thing on this screen that is only visible from
	## where they are standing and is gone the moment they walk on (D182).
	var mark_here := false
	var door_here := false
	var asked_here := ""
	for o in tv.options():
		if String(o.get("action", "")) == "shrine":
			asked_here = Balance.shrine_line(String(o.get("state", "")))
			continue
		if String(o.get("action", "")) == "answer":
			# The question itself, in this floor's own voice (D186). It goes on the hint line
			# rather than in a screen of its own because the answer is a fact about the room
			# the player is looking at — putting it behind a modal would hide the thing being
			# asked about.
			asked_here = Balance.toll_text(
				String(tv.pockets[int(o["pocket"])].get("toll", "")), tv.terrain)
			continue
		if String(o.get("action", "")) != "push":
			continue
		if bool(o.get("needs_key", false)):
			door_here = true
		else:
			mark_here = true
	var hint := "A room opens up as you enter it; a passage shows you nothing. The way down is somewhere on this floor."
	if near > 0:
		hint = "Something is moving nearby. It takes a step whenever you do." if near == 1 \
			else "%d things are moving nearby. They take a step whenever you do." % near
	elif asked_here != "":
		hint = asked_here
	elif door_here:
		# The same sentence a sealed chest gets, and for the same reason (D172): the drawing
		# says a key is wanted and only the header knows whether one is being carried.
		hint = ("A door, and it wants a key. You have one." if GameState.keys > 0
			else "A door, and it wants a key you do not have. There is one on this floor, off the path.")
	elif mark_here:
		hint = "The stone beside you is not like the rest of it. Push, and see."
	elif chest_next != "":
		# In words as well as on the tile, because the drawing says a key is wanted and
		# only the header knows whether you are holding one (D172). This is the whole point
		# of casting the tier up front: the sentence exists BEFORE the turn is spent.
		match Balance.chest_lock(chest_next):
			Balance.CHEST_LOCK_KEY:
				hint = ("A sealed chest, and it wants a key. You have one." if GameState.keys > 0
					else "A sealed chest, and it wants a key you do not have. There is one on this floor, off the path.")
			Balance.CHEST_LOCK_VAULT:
				hint = "A gilded chest: a vault. It asks something of the run rather than for a key, and it reads you at the lid."
			_:
				hint = "A worn chest, unlocked. The lid lifts at a touch."
	elif stair_found:
		hint = "The way down is right there. Anything you leave up here, you leave behind." if last \
			else "Stairs down, right there. This floor keeps whatever you do not take now."
		# ...and at the stairs, whether the floor still holds something (D182). Only when it
		# is TRUE, and it says a count and never a place: descent is one-way, so a pocket you
		# did not find is gone the moment you take these stairs, and that is the whole
		# decision the feature exists for. Without this line a hidden system is content for
		# players who already know it is there; with it, it is a visible choice and the skill
		# being asked for is still noticing.
		var left := tv.unfound_pockets()
		if left > 0:
			hint += "  This floor still holds something you have not found."
		# The finale is NAMED before it is entered, on every model (D41). That used to be the
		# job of the move button standing in for the boss tile; the pad has no words on it, so
		# the naming moved here — which is also the line the player is already reading.
		if last:
			var boss := Balance.boss_of(GameState.dungeon_id)
			if boss != null:
				hint = "%s is through there. %s  Anything you leave up here, you leave behind." % [
					boss.name, Balance.boss_warning(GameState.dungeon_id)]
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
	face_step = step
	# A boot on stone, on every step, from the one place every step goes through — including
	# the ones that end in a fight, a chest or a staircase, because the foot lands before the
	# thing at the other end of it happens. The crawl was silent until D173, which is an odd
	# thing to be able to say about the screen the player spends the most time on: it played
	# a sound when something HAPPENED and nothing at all when they moved, so walking down an
	# empty corridor was thirty seconds of score and no game. `Audio` jitters this harder
	# than anything else it plays (JITTER_BY_EVENT), because it is heard the most.
	Audio.play("step")
	# Slipping past a fight is priced on the OPTION, so it is read before the move and paid
	# here — the model reports a price and never touches run HP (D13), the same contract the
	# old deck model's dodge always had. Clamped so it can never itself be lethal.
	var slip := int(opts[i].get("hp_cost", 0)) if String(opts[i].get("action", "")) == "avoid" else 0
	# Read BEFORE the move, because after it the option list has been rebuilt and the pocket
	# is open (D182).
	var pushing: bool = String(opts[i].get("action", "")) == "push"
	# A door WANTS a key and the model never checks for one: it reports the requirement and
	# this is where it is paid, exactly as the slip's HP price is (D13/D185). Refused rather
	# than failed silently — and refused BEFORE `select`, because the model would open the
	# door regardless and there is no putting a pocket back.
	if pushing and bool(opts[i].get("needs_key", false)):
		if GameState.keys <= 0:
			Audio.play("ui_denied")
			log_label.text = "The door is locked, and you have no key. There is one on this floor, off the path."
			return
		GameState.keys -= 1
	var chosen := tv.select(i)
	if tv.shrine_paid != "":
		# The stone takes HP now and pays gold when you leave (D188). Both reported by the
		# model and paid here, exactly as the errand's gold and the toll's price are (D13).
		if String(opts[i].get("action", "")) == "shrine":
			var ask := Balance.shrine_hp_cost(GameState.max_hp)
			GameState.hp = maxi(1, GameState.hp - ask)
			Audio.play("buff")
			log_label.text = "%s -%d HP, and this floor is not what it was." % [
				Balance.aspect_name(tv.shrine_paid), ask]
		else:
			var owed_st := Balance.shrine_gold(GameState.dungeon)
			GameState.earn_gold(owed_st)
			Audio.play("gold")
			log_label.text = "Down to floor %d. The stone settles: +%d gold." % [
				tv.depth + 1, owed_st]
		GameState.autosave()
		if chosen.is_empty():
			_refresh()
			return
	elif tv.toll_result != "":
		# A toll is answered where you stand, and the price for missing is reported by the
		# model and paid here (D13/D186). Clamped so it can never itself be lethal: an errand
		# is never a run-ender and neither is a question.
		if tv.toll_result == "right":
			Audio.play("enter")
			log_label.text = "Right. Whatever was holding the wall lets go of it."
		else:
			var wrong := Balance.toll_wrong_cost(GameState.max_hp)
			GameState.hp = maxi(1, GameState.hp - wrong)
			Audio.play("hurt")
			log_label.text = "Wrong. -%d HP, and it does not ask twice." % wrong
		GameState.autosave()
		if chosen.is_empty():
			_refresh()
			return
	elif pushing:
		# The one sound in the crawl that is stone moving rather than a foot landing: `enter`
		# is what a floor arriving sounds like, and this is a floor arriving.
		Audio.play("enter")
		log_label.text = "The lock turns, and the door goes back." \
			if bool(opts[i].get("needs_key", false)) \
			else "The stone gives. There is a space behind it."
		GameState.autosave()
		if chosen.is_empty():
			_refresh()
			return
		# ...unless something caught you while your back was turned, which is what a turn
		# spent not moving is for.
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
		#
		# The key is also PAID here. The model is pure logic and owns no run resources
		# (D13), so it reports the pickup on itself and this is the one line that adds it,
		# exactly as an ambush's HP price is reported there and charged here.
		if tv.picked_key:
			GameState.keys += 1
			Audio.play("treasure")
			log_label.text = "A key, down here where nothing else is. You take it."
		elif tv.errand_paid != "":
			# The floor's ordinance, settled, and PAID here: the model reports and the caller
			# pays, exactly as it does for a key (D13/D184). Gold rather than a card, because
			# a run-deck card would re-open the dilution question D80/D81 closed and a relic
			# would be free strength from outside the deck.
			var owed := Balance.errand_gold(GameState.dungeon)
			GameState.earn_gold(owed)
			Audio.play("gold")
			log_label.text = "Down to floor %d. The floor is settled with you: +%d gold." % [
				tv.depth + 1, owed]
		elif tv.depth != from_floor:
			# The one movement in the crawl that is not a step: stone dragging and a floor
			# arriving somewhere below. `enter` is the run-entry sound and this is the same
			# event — going down is going down, and it should not have two voices.
			Audio.play("enter")
			log_label.text = "You take the stairs down to floor %d." % (tv.depth + 1)
		elif not was_seen:
			log_label.text = "You press on into the dark."
		else:
			log_label.text = "You cross ground you have already walked."
		# A held key rolls into the next step only across ground that resolved nothing,
		# on the same floor, with nothing NEW in sight. Anything else earns a stop: the
		# player who walked into a corridor and found something there has a decision in
		# front of them, and continuing to walk through it because a key is still down
		# is the one way this feature could cost them a run. Picking something up is one
		# of those stops — a thing that happened deserves the beat it takes to read.
		walk_more = tv.depth == from_floor and not tv.picked_key \
			and tv.threats().size() <= from_threats.size()
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
