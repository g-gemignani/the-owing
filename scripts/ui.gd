## Small builders shared by every menu screen. Exists so screens describe their
## content instead of repeating container/margin/scale boilerplate — and so one
## edit changes the look of all of them once there is art.
class_name UI
extends RefCounted

## Standard screen scaffold. Returns the VBox to fill.
##
## `art` optionally names a full-bleed painted image to use instead of the tiling
## pixel backdrop — for a title screen, where one illustration beats a pattern.
##
## `scene` names a Tier 5c backdrop (`victory`, `defeat`, ...) instead, which gets
## the top-band scrim rather than the title screen's left-hand column, and `zone` a
## Tier 5b establishing shot. All three are "use it if it exists", so a screen keeps
## its pixel pattern until the art lands.
static func screen(root: Control, title: String, art: String = "",
		scene: String = "", foot: bool = false, zone: String = "") -> VBoxContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Backdrop first, so it sits behind everything, and mouse-deaf so it never eats
	# a click meant for a button.
	if art != "" and ResourceLoader.exists(art):
		for node in illustration(art):
			root.add_child(node)
	elif scene != "" and scene_backdrop(root, scene, foot):
		pass
	elif zone != "" and zone_backdrop(root, zone, foot):
		pass
	else:
		# tiling pixel backdrop, themed by wherever the player currently is
		root.add_child(PixelArt.backdrop(_context_zone()))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(col)
	if title != "":
		var t := Label.new()
		t.text = title
		UITheme.style_title(t)
		col.add_child(t)
		# The settings door goes in the band that Label just reserved. Gated on the
		# title for a reason, not for tidiness — see `gear()`.
		gear(root)
	return col

# --- the settings door -------------------------------------------------------
#
# Settings was a text button on three screens out of twenty-one — the title screen,
# the pause menu, and the overworld's second nav row — so changing the volume mid-run
# meant backing out to a hub. It is built HERE, in the one function every menu screen
# already routes through, because a control that has to be added screen by screen is
# a control the next screen somebody writes will not have. That is D95 read forwards
# rather than backwards: a helper whose whole value is uniformity only reaches the
# callers that call it, and the screens that hand-roll the scaffold were the ones that
# quietly missed the last thing added to it.
#
# **It is not a gear, because there is no gear.** `assets/art/ui/` holds 21 painted
# symbols and not one of them is a cog; the nearest by meaning are a die and a coin.
# Dressing "settings" in an unrelated glyph is the positional-assignment hazard of D91
# committed on purpose, so this asks for `ui/sym_gear.png` and, until somebody paints
# one, says the word instead — the same "use it if it exists" contract `divider()` and
# every backdrop follow, where a missing file degrades to the older, plainer thing
# rather than to a hole where a control was.
#
# It deliberately does NOT go through `Icons.MAP`. A row in that table is a claim that
# the painting is on disk — `tests/test_art.gd` walks it and fails on any name that
# resolves to nothing — so adding `"settings"` today would break a suite in order to
# document an absence. The row belongs in the commit that installs the file, which is
# the same commit that stops this fallback being reachable (D115: installing art and
# wiring art are two jobs, and nothing tells you the second one is outstanding).

## Where the corner goes, and the one screen it is never built on.
const SETTINGS_SCENE := "res://scenes/Settings.tscn"

## As tall as the title band, and that is the whole of the placement argument.
##
## Top-right is the brief, and four things already lived there. Measured off the 24
## captures at 1280x720 — the topmost bright row in the right-hand 70px — rather than
## eyeballed:
##
## * **Combat's `Menu` button, y=18.** `combat.gd` scaffolds its own screen and never
##   calls `screen()`, so it never sees this, and that is the right answer rather than
##   a lucky one: `Menu` *is* combat's Escape, a fight is the one screen where a
##   mis-click costs a turn, and combat withdraws its own exit between the killing
##   blow and the reward pick. A second door in the same 40px would be a way out of
##   precisely the state that must not be left.
## * **`iso_run`'s AT RISK frame, y=16**, pinned `SHRINK_END` in its header. That
##   screen passes no title — which is exactly why the gate above is on the title and
##   not on a list of screen names. The corner this control uses is the band the title
##   occupies, and `screen()` only reserves that band when it is given a title; a
##   screen that passes none has reserved nothing, and the corner belongs to whatever
##   it puts there. The crawl reaches Settings through the `Menu` in its foot.
## * **A scroll grabber**, on every screen carrying a list. Glossary's begins at y=58,
##   and 58 is where the title band ends. That clearance is not luck: the title is the
##   first child of the column and nothing can be laid above it.
## * **Nothing at all** on the other eighteen — the topmost right-hand ink is y=124 or
##   lower on every one of them.
##
## So the height is the title's and not a button's, which rules out the carved frame:
## its border is drawn 1:1 and needs `UITheme.min_button_height()` (50px) or it smears
## (D83), and 50px reaches into the scroll. It wears `inspect_thumb`'s treatment
## instead, for `inspect_thumb`'s stated reason — a thin edge that brightens under the
## cursor, rather than a frame that forces every row it sits in to grow. The plate
## under it is not decoration: on the title screen this corner is bare painting
## OUTSIDE the scrim, which measured 3.7:1 against white before anything was laid
## under it (see SCRIM_ALPHA).
const GEAR_SIDE := 34.0

## Escape is untouched by all of this. Nothing here calls `escape()`: a control that
## is on every screen must never become what every screen's Escape does, and
## `exit_button()` stays the one place a screen declares its way out.
static func gear(root: Control) -> Button:
	# The door does not open onto the room it is in. Without this, Settings' own corner
	# would record Settings as the place to return to and Back would reload the screen
	# the player is standing on.
	if root.scene_file_path == SETTINGS_SCENE:
		return null
	# A full-rect holder rather than hand-computed offsets, so the control lands on the
	# same right edge as the content column from the same one pad constant, and moves
	# with it if that constant ever changes. It must be mouse-DEAF for the reason the
	# backdrop is: it covers the whole screen, and a holder that answers the mouse eats
	# every click meant for what is under it.
	var holder := MarginContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(holder)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)

	var b := Button.new()
	b.name = "SettingsGear"
	# So a test can tell this button from the screen's own. `PlayableTest` asks whether
	# a screen presents anything the player can press, and an always-present control
	# makes that question answer itself on every screen at once — the assertion needs
	# to be able to skip this one or it has stopped being able to fail.
	b.set_meta("ui_gear", true)
	var glyph := PixelArt.symbol("gear")
	var pad_x := 4.0 if glyph != null else 10.0
	if glyph != null:
		b.icon = glyph
		b.expand_icon = true
		b.custom_minimum_size = Vector2(UITheme.px(GEAR_SIDE), UITheme.px(GEAR_SIDE))
	else:
		b.text = "Settings"
		b.custom_minimum_size = Vector2(0, UITheme.px(GEAR_SIDE))
	# StyleBoxFlat and not the painted frame, deliberately — see GEAR_SIDE. It is also
	# what keeps this out of `menu_art_test`'s nine-slice check, which measures every
	# button wearing a StyleBoxTexture against the 50px its border needs.
	for state in [["normal", 0.34, 0.72], ["hover", 0.95, 0.88], ["pressed", 0.95, 0.94]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.05, 0.09, float(state[2]))
		sb.border_color = Color(0.74, 0.72, 0.80, float(state[1]))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = UITheme.px(pad_x)
		sb.content_margin_right = UITheme.px(pad_x)
		sb.content_margin_top = UITheme.px(4)
		sb.content_margin_bottom = UITheme.px(4)
		b.add_theme_stylebox_override(String(state[0]), sb)
	b.tooltip_text = "Settings — volume, combat effects, fullscreen. Back returns here."
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func():
		Audio.play("ui_select")
		_settings_from = root.scene_file_path
		goto(root, SETTINGS_SCENE))
	holder.add_child(b)
	return b

## Where a Settings opened from the corner has to come back to.
##
## Settings decides its own exit today — the title screen, or the pause menu if a run
## is live — which was a complete answer while it was reachable from exactly those two
## places. Opened from anywhere, "back" has to mean the screen that opened it.
##
## So the corner records that screen and `settings_menu.gd` CONSUMES the record: one
## press, one return. Consuming is what stops the two routes interfering. The three
## old text buttons record nothing, so a Settings reached through one of them reads an
## empty string and falls back to the rule it has always used; and a path left over
## from an earlier press cannot answer for a later visit that did not set one.
##
## A static, like `_escape_owner` above, because it has to survive the scene change it
## exists to describe. It holds a `scene_file_path` and not a node, which is the same
## caution that entry states in its own words: a static holding a screen outlives the
## screen. A screen built in code with no `.tscn` records the empty string and gets
## the fallback, which is the honest answer rather than a guess.
static var _settings_from := ""

## Take the recorded screen, and forget it.
static func settings_return() -> String:
	var from := _settings_from
	_settings_from = ""
	return from

## A full-bleed painted backdrop: the image, plus a scrim that keeps text legible.
## Returns the layers in draw order.
##
## Two things differ from the pixel backdrops:
##
## * **LINEAR filtering.** project.godot forces NEAREST globally, which is right
##   for pixel art and turns a smooth illustration into jagged edges.
## * **A gradient scrim.** Measured on the title art: white text over the button
##   area sat at 3.7:1 contrast, under the 4.5:1 needed to read comfortably, with
##   highlights bright enough to swallow a glyph entirely. The scrim is darkest
##   behind the menu column and fades out across the image, so the art still shows
##   where nothing is written on it. A flat dim would have muddied the whole thing
##   to fix one corner.
## Held FLAT across the text column before it fades. A pure linear fade left the
## right-hand end of the column at only 0.2 opacity, so a bright cloud there sat at
## 1.4:1 against white text — fine on average, illegible exactly where a glyph
## landed. Averages do not read text; worst pixels do.
const SCRIM_ALPHA := 0.82   ## opacity behind the text column
const SCRIM_HOLD := 0.42    ## width fraction held at full opacity
const SCRIM_END := 0.72     ## width fraction at which the scrim is gone
## Menu content is kept inside SCRIM_HOLD, so text never strays past the cover.
const MENU_WIDTH := 0.40

## The same idea for a screen that is not the title screen — the shop, an event, a
## rest — but turned through ninety degrees.
##
## The title screen's scrim is a left-hand COLUMN, because a menu is a column. These
## screens are not: their prose runs the full width and stops about halfway down,
## and the buttons below it carry their own opaque frames now. Reusing the column
## scrim here blacked out the left two thirds of the painting, which is where the
## merchant and the shrine are, and left nothing covered that needed covering.
##
## So the scrim is a top BAND. Below it the art is only dimmed, which is the half
## these three paintings put their subject in.
const SCENE_DIM := 0.25     ## flat darkening over the whole image
const SCENE_HOLD := 0.42    ## height fraction held at full scrim
const SCENE_END := 0.66     ## height fraction at which the scrim is gone

## And an optional second band rising from the bottom, for a screen that puts PROSE
## below the fold. Only the victory screen does: everything else down there is a
## button, and a button carries its own opaque frame.
##
## Measured, not chosen. Under dim alone, the bottom of these six backdrops sits at
## 1.3–1.5:1 against white — which is invisible, and is fine while nothing is written
## on it. Victory's last line lands at 80% height directly over the doorway light and
## measured 1.3:1. At this alpha it measures 3.9:1.
const SCENE_FOOT_ALPHA := 0.72
const SCENE_FOOT_HOLD := 0.80   ## height fraction below which it is at full alpha
const SCENE_FOOT_START := 0.62  ## height fraction at which it begins to come in

## The scrim along the bottom of a card's PICTURE band. There used to be an alpha
## beside these — the illustration ran the whole face at 55% behind the rules text,
## and the scrim held that text legible over it. The card is two parts now (D104):
## nothing is written over the picture, so it runs at full strength, and the scrim's
## remaining job is the join — stopping a bright patch of painting from meeting the
## name strip on a hard line, and backing the two numerals in the lower corners.
## Measured down the picture band, not the card.
const CARD_SCRIM_ALPHA := 0.62
const CARD_SCRIM_START := 0.58   ## height fraction at which the scrim begins
const CARD_SCRIM_HOLD := 0.92    ## height fraction below which it is at full alpha

static var _card_scrim_tex: GradientTexture2D = null

static func _card_scrim() -> GradientTexture2D:
	if _card_scrim_tex != null:
		return _card_scrim_tex
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_offset(1, CARD_SCRIM_START)
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(CARD_SCRIM_HOLD, Color(0, 0, 0, CARD_SCRIM_ALPHA))
	grad.add_point(1.0, Color(0, 0, 0, CARD_SCRIM_ALPHA))
	_card_scrim_tex = GradientTexture2D.new()
	_card_scrim_tex.gradient = grad
	_card_scrim_tex.width = 1
	_card_scrim_tex.height = 128
	_card_scrim_tex.fill_from = Vector2(0, 0)
	_card_scrim_tex.fill_to = Vector2(0, 1)
	return _card_scrim_tex

## Zone establishing shots take a heavier flat dim than the scene backdrops do.
## Not a taste difference — a layout one. A shop or an event puts its prose in the
## top half and buttons below it, so a top band covers everything that is written.
## The zone screen is a SCROLLING LIST: dungeon names, boss warnings and card lines
## run from the title to the bottom of the frame, so there is no part of the picture
## that text does not cross, and the only thing that helps everywhere is the dim.
## At 0.60 the worst pixel under the lower rows measures 3.3:1.
const ZONE_DIM := 0.60

## Put a painted scene backdrop behind `root`'s contents. Returns false if that
## scene has no art yet, in which case the caller keeps whatever it had.
##
## Inserted at the FRONT of the child list rather than appended: these screens
## build their own margin container first, and a backdrop added after it draws
## over the entire screen.
static func scene_backdrop(root: Control, scene: String, foot: bool = false) -> bool:
	return _painted_backdrop(root, PixelArt.scene_art(scene), foot)

## The same treatment for a zone establishing shot, which lives in its own namespace
## (`bg_zone_<id>`) because `foundry` names both a zone and a dungeon.
static func zone_backdrop(root: Control, zone_id: String, foot: bool = false) -> bool:
	return _painted_backdrop(root, PixelArt.zone_art(zone_id), foot, ZONE_DIM)

static func _painted_backdrop(root: Control, tex: Texture2D, foot: bool,
		dim: float = SCENE_DIM) -> bool:
	if tex == null:
		return false
	var layers := illustration("", SCENE_HOLD, SCENE_END, dim, tex, true)
	if foot:
		layers.append(_foot_scrim())
	for i in layers.size():
		root.add_child(layers[i])
		root.move_child(layers[i], i)
	return true

## One zone's establishing shot, cropped to a fixed-size thumbnail for a list row.
##
## The same `bg_zone_<id>.png` the zone screen uses full-bleed. It exists so a list
## of PLACES reads as places: five zones drawn as five identical full-width bars are
## a menu, and the world screen was the only navigation screen in the game with no
## art on it at all (D97).
##
## No scrim and no contrast measurement, unlike every other use of this art — a
## thumbnail sits BESIDE its text, never under it, which is the one arrangement where
## the question does not arise. `dim` is for a zone the player cannot enter yet: the
## picture stays, in shadow, because a darkened place reads as a sealed door where a
## greyed-out bar reads as a broken widget.
##
## Falls back to the zone's tiling pixel pattern if nobody has painted it, on the
## same "use it if it exists" rule as the backdrops above.
const THUMB_DIM := Color(0.34, 0.36, 0.46)

static func zone_thumb(parent: Node, zone_id: String, size: Vector2,
		dim: bool = false) -> Control:
	var tex := PixelArt.zone_art(zone_id)
	var tr: TextureRect
	if tex != null:
		tr = TextureRect.new()
		tr.texture = tex
		# COVER: the shots are 16:9 and the row is not, so one axis has to be cropped.
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# LINEAR for the same reason illustration() uses it — project.godot forces
		# NEAREST globally, which is right for pixel art and jagged on a painting.
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		tr = PixelArt.backdrop(zone_id)
	tr.custom_minimum_size = Vector2(UITheme.px(size.x), UITheme.px(size.y))
	tr.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		tr.modulate = THUMB_DIM
	parent.add_child(tr)
	return tr

## The band rising from the bottom. Same construction as the top one, upside down.
static func _foot_scrim() -> Control:
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0, 0.0))
	grad.set_offset(1, SCENE_FOOT_START)
	grad.set_color(1, Color(0, 0, 0, 0.0))
	grad.add_point(SCENE_FOOT_HOLD, Color(0, 0, 0, SCENE_FOOT_ALPHA))
	grad.add_point(1.0, Color(0, 0, 0, SCENE_FOOT_ALPHA))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 1
	gtex.height = 256
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	var s := TextureRect.new()
	s.texture = gtex
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s.stretch_mode = TextureRect.STRETCH_SCALE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func illustration(path: String, hold: float = SCRIM_HOLD,
		end: float = SCRIM_END, dim: float = 0.0,
		tex: Texture2D = null, vertical: bool = false) -> Array[Control]:
	var art := TextureRect.new()
	art.texture = tex if tex != null else load(path) as Texture2D
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	# COVER, not tile: it is one picture, and letterboxing a title screen reads
	# as a bug rather than a choice.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0, SCRIM_ALPHA))
	grad.set_offset(1, hold)
	grad.set_color(1, Color(0, 0, 0, SCRIM_ALPHA))
	grad.add_point(end, Color(0, 0, 0, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 1 if vertical else 256
	gtex.height = 256 if vertical else 1
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)

	var scrim := TextureRect.new()
	scrim.texture = gtex
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var layers: Array[Control] = [art]
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, dim)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layers.append(shade)
	layers.append(scrim)
	return layers

## Which zone's backdrop suits the current screen: the run's zone if there is one,
## else the zone being browsed, else the opening zone.
static func _context_zone() -> String:
	if GameState.dungeon_id != "":
		var z := Balance.zone_of(GameState.dungeon_id)
		if z != null:
			return z.id
	if GameState.current_zone != "":
		return GameState.current_zone
	return Balance.ZONES[0] if Balance.ZONES.size() > 0 else "barrows"

## Counted nouns ("1 clear" / "4 clears") are `Wording.count()`, not a method here —
## `UI` names the `UITheme` autoload, which puts it out of reach of every `--script`
## test, and half the text in the game is written by code those tests call (D19, D125).

static func label(parent: Node, text: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

## How wide a button is when it is in a column and nothing narrows it (D116).
##
## Read it the way `UITheme.button_height` is read: a designed size, not a ceiling.
## A label that needs more room still takes more room, so no text is ever clipped to
## hold this number — which is why it is a minimum and not the max width Godot does
## not have.
##
## Chosen by photographing the whole set at 1280x720 twice, at 480 and at 320. Both
## fix the banner; 320 is the better `Back` and the worse menu — the title screen's
## `Continue` line is about 335px of text, so at 320 it came out wider than the four
## buttons under it and the one column in the game that was deliberately sized went
## ragged. At 480 every screen's column is uniform and the title menu is within a
## couple of dozen pixels of the 512 it has always been (its column is pinned to
## `MENU_WIDTH` to keep the labels on the scrim). The game's own reference for what a
## button looks like is the overworld's nav rows and the packs' `Open`, which sit at
## 100–200 because a row's neighbours size them; a column has no neighbours, so it
## needs this.
const BUTTON_WIDTH := 480.0

static func button(parent: Node, text: String, on_press: Callable = Callable(),
		height: float = 42.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UITheme.button_height(height))
	# A button in a COLUMN has nothing beside it to take the slack, and a
	# VBoxContainer hands its full width to whatever it holds — so `Back` came out
	# 1244px wide on Relics, Packs, Powers, Glossary, Collection and the shop, which
	# made the least important control on each screen the largest thing on it. In a
	# ROW the neighbours already do this job (the overworld's nav bars, the packs'
	# `Open`, combat's `Menu`), so rows are left exactly as they are.
	#
	# Set BEFORE the caller gets the button back, deliberately: a screen that wants
	# another width writes over this line instead of passing a flag. `packs_screen`
	# already does it for the 140px `Open`, and a parameter nobody sets is a
	# parameter that will be set wrongly once.
	if parent is VBoxContainer:
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.custom_minimum_size.x = UITheme.px(BUTTON_WIDTH)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	else:
		b.disabled = true
	UITheme.style_button(b)
	parent.add_child(b)
	return b

static func row(parent: Node, separation: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UITheme.sep(separation))
	parent.add_child(h)
	return h

static func spacer(parent: Node) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

## The same, turned sideways: eats the slack in a row so what follows sits right.
static func hspacer(parent: Node) -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

## The carved rule between two sections of a screen.
##
## `ui/divider.png` was generated with the rest of the frame kit and read by nothing
## (D125) — the D115 gap, where a file on disk is not a file in the game and no test
## can fail. It is wired here rather than into `screen()`, because a rule under every
## title would be decoration on twenty screens that have one section each; what the
## asset is FOR is a screen with two, and Settings is the one that has them.
##
## Tiled rather than stretched: the strip is 128px of a repeating profile, and
## stretching it across a 1240px column would smear the cut into a gradient — the
## nine-slice lesson (D83) in one axis. Falls back to the plain vertical gap the
## screens used before, on the same "use it if it exists" contract as the backdrops,
## so a tree without the file looks exactly as it did.
static func divider(parent: Node) -> Control:
	var tex := PixelArt.ui_kit("divider")
	if tex == null:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(16))
		parent.add_child(gap)
		return gap
	var rule := TextureRect.new()
	rule.texture = tex
	rule.stretch_mode = TextureRect.STRETCH_TILE
	rule.custom_minimum_size = Vector2(0, UITheme.px(tex.get_height()))
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return rule

static func scroll(parent: Node) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UITheme.sep(6))
	s.add_child(col)
	return col

## A labelled 0-100 slider row (placeholder-friendly).
static func slider(parent: Node, text: String, value: float, lo: float, hi: float,
		step: float, on_change: Callable) -> HSlider:
	var h := row(parent, 10)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = UITheme.px(220)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = UITheme.px(280)
	h.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = UITheme.px(90)
	v.text = _slider_value(value, step)
	h.add_child(v)
	s.value_changed.connect(func(nv):
		v.text = _slider_value(nv, step)
		on_change.call(nv))
	return s

## The number beside the slider, in the precision its STEP implies.
##
## `str(snappedf(100.0, 5))` is "100.0", so Settings read "Master volume 100.0" — a
## decimal point shown because the value is carried as a float, not because anything
## about the setting is fractional. All three sliders in the game are whole numbers
## (0..100 by 5) and every one of them was reading like debug output (D125).
##
## Decided by the STEP and not by the value, which is the bit worth keeping. A slider
## that genuinely moves in halves must still print its half, and asking the value
## instead would flip such a row between "1" and "1.5" as the grabber moves — a string
## that changes width inside a fixed 90px label, which is the D95 defect wearing a
## different hat. A step of 0 means the caller wants no snapping at all, so it is
## treated as fractional rather than rounded away.
static func _slider_value(value: float, step: float) -> String:
	var v := snappedf(value, step)
	if step > 0.0 and is_equal_approx(step, roundf(step)):
		return str(int(roundf(v)))
	return str(v)

## A card: rarity-framed, with its illustration behind the text and its *meaningful*
## effect symbol in front.
##
## Layered deliberately. The illustration is arbitrary art from an unlabelled sheet,
## so it is pushed to the back at low opacity where it adds identity without making a
## claim; the symbol (attack / block / poison / ...) is derived from the card's real
## effects and stays legible in front. Text is never competed with.

## Attach a tooltip and guarantee it can actually be reached by the mouse.
##
## Label, and most non-interactive Controls, default to MOUSE_FILTER_IGNORE, so a
## `tooltip_text` set directly on one is never shown — the collection, deck builder
## and shop all had card descriptions written that no hover could surface.
##
## Pass the *row*, not the label: hovering anywhere over an entry should explain it.
## Children left on IGNORE fall through to this control, and a child Button with no
## tooltip of its own inherits this one by walking up the tree.
static func hoverable(control: Control, text: String) -> void:
	control.tooltip_text = text
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_STOP

## Filter and sort controls for a list of owned cards.
##
## One builder used by both the collection and the deck builder, so the two cannot
## end up offering different orderings of the same cards. Calls `on_change` after
## mutating CardFilter.state; the screen just re-runs its own refresh.
static func card_filter_bar(parent: Node, on_change: Callable) -> void:
	var st: Dictionary = CardFilter.state

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITheme.sep(6))
	parent.add_child(bar)

	var lbl := Label.new()
	lbl.text = "Sort"
	bar.add_child(lbl)

	var sort := OptionButton.new()
	for i in CardFilter.SORTS.size():
		sort.add_item(String(CardFilter.SORTS[i]["label"]), i)
		if CardFilter.SORTS[i]["id"] == st.get("sort", "name"):
			sort.select(i)
	sort.item_selected.connect(func(i: int):
		CardFilter.state["sort"] = CardFilter.SORTS[i]["id"]
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(sort)

	# direction is a toggle rather than two more menu entries: it applies to
	# whichever key is chosen
	var dir := Button.new()
	UITheme.style_button(dir)
	dir.text = "desc" if bool(st.get("desc", false)) else "asc"
	dir.pressed.connect(func():
		CardFilter.state["desc"] = not bool(CardFilter.state.get("desc", false))
		Audio.play("ui_click")
		on_change.call())
	UI.hoverable(dir, "Reverse the order")
	bar.add_child(dir)

	var rl := Label.new()
	rl.text = "   Rarity"
	bar.add_child(rl)
	var rarity := OptionButton.new()
	rarity.add_item("All", 0)
	for r in CardData.Rarity.keys().size():
		rarity.add_item(CardData.rarity_word(r), r + 1)
	rarity.select(int(st.get("rarity", -1)) + 1)
	rarity.item_selected.connect(func(i: int):
		CardFilter.state["rarity"] = i - 1
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(rarity)

	var tl := Label.new()
	tl.text = "   Type"
	bar.add_child(tl)
	var type := OptionButton.new()
	type.add_item("All", 0)
	for t in CardData.Type.keys().size():
		type.add_item(String(CardData.Type.keys()[t]).capitalize(), t + 1)
	type.select(int(st.get("type", -1)) + 1)
	type.item_selected.connect(func(i: int):
		CardFilter.state["type"] = i - 1
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(type)

	var clear := Button.new()
	UITheme.style_button(clear)
	clear.text = "Clear"
	clear.pressed.connect(func():
		CardFilter.state = CardFilter.default_state()
		Audio.play("ui_back")
		on_change.call())
	bar.add_child(clear)

## A modal list of the run deck, for anything that acts on one card.
##
## An overlay rather than a screen, so it works identically from a shop, a rest and
## any traversal view without one of them having to know how to route back.
static func card_picker(host: Control, deck: Array, title: String,
		on_pick: Callable) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.82)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 100
	veil.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it is clickable
	host.add_child(veil)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	veil.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(8))
	margin.add_child(col)

	var t := Label.new()
	t.text = title
	UITheme.style_title(t)
	col.add_child(t)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UITheme.sep(6))
	grid.add_theme_constant_override("v_separation", UITheme.sep(6))
	scroll.add_child(grid)

	var size := UITheme.card_size() * 0.8
	for c in deck:
		card_button(grid, c, size, func(): 
			veil.queue_free()
			on_pick.call(c))

	var cancel := Button.new()
	cancel.text = "Never mind"
	# Built by hand rather than through `button()` because it carries its own sound,
	# so it needs the column rule of D116 restated: this is a lone control in a
	# full-width VBox, and left alone it draws a 1244px bar across the picker.
	cancel.custom_minimum_size = Vector2(UITheme.px(BUTTON_WIDTH), UITheme.px(40))
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cancel.pressed.connect(func():
		Audio.play("ui_back")
		veil.queue_free())
	col.add_child(cancel)
	return veil

## The narrowest name strip that is still a name strip — D117.
##
## The fan gives a resting card `step = (room - card) / (n - 1)` of visible width and
## `fit_name` below turns that into a name slot of `step - 2*pad`. At the hand size a
## real build reaches — 11 cards, from HAND_SIZE plus Keen Lens plus Scholar's Lens
## plus a fused See It Coming — the step is 41-42px, so the slot is 25-26px, and
## `fit_label` buys the fit by shrinking the type: names came out at 7-9px, "Two
## Quick" at 7px over two lines, against the 14px floor CardTextTest enforces on
## card text. Inside its slot, legally, and unreadable at arm's length.
##
## The number is measured, not chosen. Every one of the 100 card names was fitted
## into the 28px-tall strip at every slot width, and the width at which each one
## first holds 14px recorded: 22px for the shortest name in the game ("Jab"), 119px
## for the longest ("Something Worse"), median 69px. Read the other way, that curve
## says how much of the deck a given slot can still name:
##
##     slot 86px (a 5-card hand)   76 of 100 names at >= 14px
##     slot 52px (7 cards)         26
##     slot 43px (8 cards)         ~18
##     slot 36px (9 cards)         13
##     slot 34px                   13
##     slot 33px                    9
##     slot 30px (10 cards)         5
##
## Ten is the ceiling now (`Balance.MAX_HAND_SIZE`, D120), so the 25px slot an
## eleven-card hand used to produce is unreachable and is no longer listed.
##
## Below this much slot the card shows its cost and its effect symbol instead. A 30px
## strip cannot hold a name at a legible size, but it holds a cost numeral and a ~28px
## glyph comfortably, and since D116 that glyph is painted art that states what the
## card actually does rather than the 16x16 CC0 tile that read as noise. "Attack,
## costs 1" at a glance beats four legible letters of a name; this is a better read of
## a crowded hand, not a consolation prize for one.
##
## The switch is per-card, because the fan hands every card its own visible width and
## only the topmost one gets the whole face.
##
## **37, not the 34 this started at, and the number is a patch on a wrong shape.**
## D117 set it where the curve crosses one name in ten. That left a NINE-card hand at
## a 36px slot — just above the line — so the swap did not fire and its names rendered
## at **7px**, the exact defect the swap exists to prevent. Nine was always reachable
## and D120's cap made it the *modal* large hand, because a card's own draw resolves
## while that card is still in hand, so playing a draw card out of nine leaves nine.
## 37 closes that case, measured.
##
## It does not close the next one, and nobody should mistake this for finished: an
## EIGHT-card hand has a 43px slot, above 37, and still cannot name 82 of the 100
## cards at the floor. A single width threshold cannot fix that, because the thing
## being tested is per-NAME — "Jab" needs 22px and "Something Worse" needs 119 — and
## every width picked here will be right for some names and wrong for the rest.
## The honest rule is a floor on the RENDERED size: swap when the fitter would have to
## take this card's own name below what can be read. That changes the five-card hand
## for long-named cards, which is a visible design decision and not a bug fix, so it
## is written down here rather than taken (D120).
const CARD_NAME_MIN_W := 37.0

## `live` is the CombatEngine when this card is being shown inside a fight, and
## null everywhere else. With it, the face and the hover both quote the damage and
## Block the card would actually produce this turn — Strength and Dexterity are
## otherwise invisible on the only surface the player reads before spending energy.
static func card_button(parent: Node, card: CardData, size: Vector2,
		on_press: Callable, label: String = "", live: CombatEngine = null) -> Button:
	# A plain Control, NOT a Container. PanelContainer overrides its children's
	# anchors and takes its own size from their minimum sizes — and a Button's
	# minimum size grows with its wrapped description, so every card ended up a
	# different size and the sizes shifted as the hand changed. A Control holder
	# with an explicit size and anchored children makes every card identical.
	var holder := Control.new()
	holder.set_meta("card_id", card.id)   # so tests can measure a card's real bounds
	holder.custom_minimum_size = size
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)

	var frame := Panel.new()
	# painted frame if the kit has one for this rarity, else the flat rarity border
	var painted_frame := Icons.card_frame(card.rarity)
	frame.add_theme_stylebox_override("panel",
		painted_frame if painted_frame != null else Icons.card_style(card.rarity, 0.16))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)

	# The card is TWO PARTS, and every rectangle below is measured off these three
	# numbers: the picture on top, the name strip under it, and the rules text
	# taking whatever is left. The art used to be full-bleed behind the words at 55%
	# alpha, which is a different thing — a wash, not an illustration — and it meant
	# the picture and the text were always fighting for the same pixels.
	var pad := roundf(size.x * UITheme.CARD_PAD)
	var inner := Vector2(size.x - pad * 2.0, size.y - pad * 2.0)
	var art_h := roundf(size.y * UITheme.CARD_ART_BAND)
	var name_h := roundf(size.y * UITheme.CARD_NAME_BAND)
	var text_y := pad + art_h + name_h
	var text_h := size.y - pad - text_y
	# The cost badge and effect symbol get a share of the card's WIDTH, never its
	# height: sizing them off a band drove the title's width negative on a squeezed
	# hand, which made the fit pass give up and clip instead.
	var badge_w := roundf(inner.x * 0.26)
	var badge_h := roundf(size.y * 0.095)

	# --- the picture band ----------------------------------------------------
	# id first, then the card's effect family — see PixelArt.painted_card_art
	var art := PixelArt.card_art(card.id, Icons.card_family(card))
	if art != null:
		# Two different pictures wearing one call. A PAINTED family illustration is a
		# real picture at 320x240 (4:3) and fills the band edge to edge. The CC0
		# fallback is a 16x16 atlas slice — an icon, not an illustration — so it is
		# centred at its own aspect and tinted by rarity, on the band's dark backing.
		# Blowing a 16px icon up to fill the band would be sixteen-fold mush.
		var painted := PixelArt.painted_card_art(card.id, Icons.card_family(card)) != null
		# A clipping window, because STRETCH_KEEP_ASPECT_COVERED deliberately
		# overflows its box on the short axis and would otherwise paint over the
		# name and the rules text below it.
		var win := Control.new()
		win.clip_contents = true
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(win)
		_place(win, pad, pad, inner.x, art_h)

		var bed := ColorRect.new()
		bed.color = Color(0.06, 0.05, 0.08)
		bed.set_anchors_preset(Control.PRESET_FULL_RECT)
		bed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(bed)

		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(pic)
		if painted:
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			# `set_anchors_AND_OFFSETS_preset`, and the difference is the whole
			# illustration. `set_anchors_preset` leaves the offsets alone by default,
			# which means it preserves the control's CURRENT rect — and a control
			# created two lines ago has a rect of 0x0, so it anchors to the full band
			# and stays zero-sized forever. The bed and the scrim either side of this
			# call escape it only because they are preset BEFORE `add_child`, when
			# there is no parent rect to preserve against (D121).
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		else:
			# An EMBLEM in the band, not a picture filling it. KEEP_ASPECT_CENTERED
			# scales to FIT the box it is given, so handing the fallback the whole band
			# scaled a 16x16 sprite to 101px — a 6x blow-up of sixteen pixels, which the
			# first render showed as exactly the mush this branch exists to avoid. Give
			# it a smaller box and it stays legible; NEAREST keeps it pixel art rather
			# than a smear, which is what it is.
			var side := roundf(art_h * 0.62)
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pic.modulate = Icons.rarity_colour(card.rarity)
			_place(pic, roundf((inner.x - side) * 0.5), roundf((art_h - side) * 0.5),
				side, side)

		# How far up its own level track this card has come, as LIGHT over the picture
		# rather than a repaint of it (D132). Added, not blended, so the overlay's black
		# is invisible and only its glow lands; tinted to the rarity so the same three
		# files serve all five. Above the illustration and BELOW the scrim, because the
		# scrim's job — keeping the corner numerals readable — has to outrank it.
		var fx := PixelArt.level_overlay("card", card.level, card.level_cap())
		if fx != null:
			# the dark halo first, in normal blending: additive light on bright paint
			# saturates to white and loses the rarity tint exactly where it is loudest,
			# so the paint is darkened just where the light is about to land (D138)
			var shade := PixelArt.level_overlay_halo("card", card.level, card.level_cap())
			if shade != null:
				var dim := TextureRect.new()
				dim.texture = shade
				dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				dim.stretch_mode = TextureRect.STRETCH_SCALE
				dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
				win.add_child(dim)
				dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var glow := TextureRect.new()
			glow.texture = fx
			glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glow.stretch_mode = TextureRect.STRETCH_SCALE
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var add := CanvasItemMaterial.new()
			add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			glow.material = add
			glow.modulate = Icons.rarity_colour(card.rarity)
			win.add_child(glow)
			glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# A scrim along the BOTTOM of the picture only. The old one covered the whole
		# card because the text was over the whole card; now it exists to stop a
		# bright patch of illustration meeting the name strip on a hard line, and to
		# give the corner numerals something to sit on.
		var s3 := TextureRect.new()
		s3.texture = _card_scrim()
		s3.set_anchors_preset(Control.PRESET_FULL_RECT)
		s3.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s3.stretch_mode = TextureRect.STRETCH_SCALE
		s3.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		s3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(s3)

	# --- the text band -------------------------------------------------------
	# Its own dark panel, not a gradient over a picture. The rules text is on the
	# card at all times now, so its background has to be a guarantee rather than a
	# hope about how dark the bottom of the illustration came out.
	var bay := Panel.new()
	var bay_sb := StyleBoxFlat.new()
	bay_sb.bg_color = Color(0.07, 0.06, 0.09, 0.94)
	bay_sb.set_corner_radius_all(0)
	bay_sb.border_color = Icons.rarity_colour(card.rarity)
	bay_sb.border_width_top = 1
	bay_sb.border_color.a = 0.55
	bay.add_theme_stylebox_override("panel", bay_sb)
	bay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bay)
	_place(bay, pad, pad + art_h, inner.x, size.y - pad - (pad + art_h))

	# The button carries no text. It used to render everything through `Button.text`
	# with `clip_text`, which silently cut descriptions off mid-word — a Button draws
	# one text block at one size and cannot give the name and the rules text different
	# treatment. Text lives in Labels layered on top; the button is only the hit area.
	var b := Button.new()
	b.flat = true
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	# both surfaces read the same two numbers, so the face and the hover cannot
	# disagree about what the card is about to do
	var live_dmg: int = live.card_damage(card) if live != null else -1
	var live_blk: int = live.card_block(card) if live != null else -1
	b.tooltip_text = Icons.card_tooltip(card, live_dmg, live_blk)
	holder.add_child(b)

	# NO containers inside the card. A VBox/HBox honours its children's *minimum*
	# sizes, and an autowrapping Label's minimum width is one character — so the
	# title got squeezed to 8px, wrapped to 441px tall, and shoved the description
	# clean off the bottom of a 211px card. Every region is placed by hand against
	# the card's known size, so nothing can be pushed anywhere.
	var cost := _card_label(holder, str(card.eff_cost()), Color(1.0, 0.86, 0.45))
	# The bed is kept rather than dropped because a crowded card narrows this badge to
	# what the next card leaves of it, and the plate has to move with the numeral —
	# see `lay_rest` and CARD_NAME_MIN_W.
	var cost_bed := _badge_bed(holder, pad, pad, badge_w, badge_h)
	_place(cost, pad, pad, badge_w, badge_h)

	var sym := Icons.tex(Icons.for_card(card))
	if sym != null:
		var s := TextureRect.new()
		s.texture = sym
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(s)
		_place(s, size.x - pad - badge_w, pad, badge_w, badge_h)

	var title := _card_label(holder, label if label != "" else card.name,
		Color(0.96, 0.96, 0.96))
	# The one piece of text on a card that is NOT in the body face. The name is the
	# card's identity, and in a fanned hand it is the only thing a resting card shows
	# (D97) — so it is the one place on the face where telling two cards apart at a
	# glance matters more than reading a sentence.
	var name_face := UITheme.display_face()
	if name_face != null:
		title.add_theme_font_override("font", name_face)
	var title_w := inner.x

	# generated, not the authored line: a fused card must not misreport itself
	var desc := _card_label(holder, card.effect_text(live_dmg, live_blk), Color(0.86, 0.84, 0.80))
	_place(desc, pad + roundf(pad * 0.5), text_y, inner.x - pad, text_h - roundf(pad * 0.5))

	# Shrink to fit rather than clip. Card text is authored, so its length varies
	# far more than the fixed card does; a card that cuts its own rules text off is
	# unplayable in a way a slightly smaller font is not.
	#
	# ONE layout, unlike the old card. The rules text used to appear only on hover
	# because there was nowhere to put it: it shared the face with the name, and
	# fitting both drove the wordiest card to 12px. It now has a band of its own, so
	# it is on the card at rest and on hover and in every menu — which is the whole
	# point of the shape, and what makes a hand readable without touching the mouse.
	var body := UITheme.font()
	# The cost badge at a given width, in one place because it is laid out three times:
	# here, narrowed when the fan crowds this card past CARD_NAME_MIN_W, and back to
	# full when the card is opened. Numeral and plate always move together.
	var lay_cost := func(w2: float) -> void:
		_place(cost_bed, pad, pad, w2, badge_h)
		_place(cost, pad, pad, w2, badge_h)
		fit_label(cost, Vector2(w2, badge_h), body, 7)
	lay_cost.call(badge_w)
	fit_label(desc, Vector2(inner.x - pad, text_h - roundf(pad * 0.5)), int(body * 0.92), 7)

	# The headline number, in the PICTURE's bottom corners.
	#
	# Damage in red on the left, Block in blue on the right, both if the card does
	# both, and in a fight these are the live numbers — with 4 Strength every attack
	# is worth more, and that has to be visible without hovering each card in turn.
	#
	# They sit over the illustration rather than under the rules text because of
	# where the card is when it matters: a card in hand hangs off the bottom of the
	# screen (Combat.HAND_PEEK), so anything in the bottom corners is exactly what
	# the player cannot see. The picture band is always above the edge.
	var headline := ""
	if live_dmg > 0 or (live_dmg < 0 and card.eff_damage() > 0):
		headline = str(live_dmg if live_dmg >= 0 else card.eff_damage())
		if card.hits > 1:
			headline += "x%d" % card.hits
	var shield := ""
	if live_blk > 0 or (live_blk < 0 and card.eff_block() > 0):
		shield = str(live_blk if live_blk >= 0 else card.eff_block())
	var value_labels: Array[Label] = []
	if headline != "" or shield != "":
		var vy := pad + art_h - badge_h
		var vw := roundf(inner.x * 0.42)
		if headline != "":
			var v := _card_label(holder, headline, Color(1.0, 0.55, 0.45))
			value_labels.append(v)
			_badge_bed(holder, pad, vy, vw, badge_h)
			_place(v, pad, vy, vw, badge_h)
			fit_label(v, Vector2(vw, badge_h), body, 7)
		if shield != "":
			var s2 := _card_label(holder, shield, Color(0.62, 0.80, 1.0))
			value_labels.append(s2)
			_badge_bed(holder, size.x - pad - vw, vy, vw, badge_h)
			_place(s2, size.x - pad - vw, vy, vw, badge_h)
			fit_label(s2, Vector2(vw, badge_h), body, 7)

	var rest_y := pad + art_h
	var rest_h := name_h
	# What the name strip shows instead of a name once the fan has squeezed it past
	# CARD_NAME_MIN_W: the same effect glyph as the corner badge, drawn big in the
	# strip where the name was. Built here and hidden, rather than moved from the
	# corner, so that opening the card is still a matter of showing the whole face
	# instead of putting a symbol back where it came from.
	#
	# `sym` is null only if a card's effect has neither painted art nor a fallback
	# glyph, which no card in the catalogue currently is. When it happens there is
	# nothing better to show than the name, however small — a tiny name identifies a
	# card and an empty strip does not — so `crowd == null` keeps today's behaviour.
	var crowd: TextureRect = null
	if sym != null:
		crowd = TextureRect.new()
		crowd.texture = sym
		crowd.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crowd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crowd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crowd.visible = false
		holder.add_child(crowd)
		# a starting box only; `lay_rest` re-places it into the width that actually
		# survives the fan on the frame it is first shown
		_place(crowd, pad, rest_y, inner.x, rest_h)
	# The RESTING title takes a width that can shrink; the open one always gets the
	# whole face. In a hand the neighbour to the right is drawn on top of this card
	# and hides its right-hand edge — and the name is the only thing a resting card
	# shows, so the name was precisely what was being covered: a captured five-card
	# hand read "Smith's Fu / Prepare / Bludgeo / Bite / Shiv" (D97). The fan is the
	# only thing that knows how much of a card survives, so it tells the card, through
	# `fit_name` below. Everywhere else — rewards, the shop, the deck lists — nothing
	# overlaps and the default stays the full face.
	#
	# The two mutable pieces live in metas rather than in locals because a GDScript
	# lambda captures a local BY VALUE, and both closures below have to see the same
	# current width.
	holder.set_meta("rest_w", title_w)
	holder.set_meta("open", false)
	var lay_rest := func() -> void:
		var w: float = holder.get_meta("rest_w")
		# The swap, and the ONLY place it is decided: a resting state, per card, off the
		# width this card was handed. The fan gives its topmost card the whole face, so
		# the last card in a hand keeps its name however crowded the hand is, and every
		# surface that does not overlap cards at all never comes near the threshold.
		if crowd != null and w < UITheme.px(CARD_NAME_MIN_W):
			title.visible = false
			crowd.visible = true
			# Both of the two things left have to be inside the strip the player can
			# actually see, which is why the cost badge narrows: at 150px wide the badge
			# is 35px and runs past a 41px step, under the next card. Symmetric with the
			# glyph below it, so the pair reads as one column.
			lay_cost.call(minf(badge_w, w))
			_place(crowd, pad, rest_y, w, rest_h)
			return
		title.visible = true
		if crowd != null:
			crowd.visible = false
		lay_cost.call(badge_w)
		_place(title, pad, rest_y, w, rest_h)
		fit_label(title, Vector2(w, rest_h), body, 7)
	_place(title, pad, rest_y, title_w, rest_h)
	fit_label(title, Vector2(title_w, rest_h), body, 7)
	var open_px: int = title.get_theme_font_size("font_size")

	# Opening a card no longer REVEALS anything — the picture, the name, the numbers
	# and the rules text are all on the face at every size. What it still does is
	# give the name back the width its right-hand neighbour is covering, which is
	# the D97 defect and is unchanged by the new shape.
	var show_all := func(open: bool) -> void:
		holder.set_meta("open", open)
		if open:
			# The whole face, including everything the resting state may have swapped
			# out: an opened card is lifted clear of its neighbours, so it is never
			# short of width and the D117 substitution has no business here.
			title.visible = true
			if crowd != null:
				crowd.visible = false
			lay_cost.call(badge_w)
			_place(title, pad, rest_y, title_w, rest_h)
			title.add_theme_font_size_override("font_size", open_px)
		else:
			# re-fit rather than restore a remembered size: the resting width can have
			# changed since, because the fan re-measures every time the hand changes
			lay_rest.call()
	show_all.call(false)
	holder.set_meta("show_all", show_all)   # so tests can drive both states
	# How the fan tells a card how much of itself is not under the next one. A hovered
	# card is lifted clear of its neighbours, so the open layout is left alone.
	holder.set_meta("fit_name", func(visible_w: float) -> void:
		var w := clampf(visible_w - pad * 2.0, pad, title_w)
		if is_equal_approx(w, float(holder.get_meta("rest_w"))):
			return
		holder.set_meta("rest_w", w)
		if not bool(holder.get_meta("open")):
			lay_rest.call())
	holder.set_meta("name_label", title)   # so tests can measure what a resting hand shows
	# ...and what it shows INSTEAD when the strip is too narrow for a name (D117).
	# Exposed as well as the name because "the name is hidden" has to be a testable
	# statement about what replaced it: a check that skips a hidden name goes silently
	# vacuous at exactly the hand size it was written for.
	holder.set_meta("cost_label", cost)
	if crowd != null:
		holder.set_meta("crowd_symbol", crowd)

	# Re-read the live numbers without rebuilding the widget. The combat screen
	# diffs its hand instead of destroying it every action (that is what allows a
	# card to animate at all), so a buff landing mid-turn has to be able to change
	# what the cards already on screen claim to do.
	holder.set_meta("relabel", func(live2: CombatEngine) -> void:
		var d2: int = live2.card_damage(card) if live2 != null else -1
		var b2: int = live2.card_block(card) if live2 != null else -1
		desc.text = card.effect_text(d2, b2)
		b.tooltip_text = Icons.card_tooltip(card, d2, b2)
		if value_labels.size() > 0 and d2 >= 0 and headline != "":
			var head := str(d2)
			if card.hits > 1:
				head += "x%d" % card.hits
			value_labels[0].text = head
		if b2 > 0 and shield != "":
			value_labels[value_labels.size() - 1].text = str(b2))

	# Grow from the bottom edge: a hand sits along the bottom of the screen, so a
	# card that grew from its centre would push its own text off-screen.
	holder.pivot_offset = Vector2(size.x * 0.5, size.y)
	var open_card := func(open: bool) -> void:
		show_all.call(open)
		holder.scale = Vector2.ONE * (UITheme.CARD_HOVER_SCALE if open else 1.0)
		holder.z_index = 10 if open else 0
		# A fanned hand stores where each card sits at rest ("fan" meta, set by the
		# combat screen). Opening one straightens it and lifts it clear of its
		# neighbours, the way you pull a card out of a real hand to read it — without
		# that, an enlarged card in a fan is still half-covered by the next one.
		var fan: Dictionary = holder.get_meta("fan", {})
		if not fan.is_empty():
			var home: Vector2 = fan.get("pos", holder.position)
			if open:
				holder.rotation = 0.0
				holder.position = home - Vector2(0.0, float(fan.get("lift", 0.0)))
			else:
				holder.rotation = float(fan.get("rot", 0.0))
				holder.position = home

	if touch_ui():
		# TOUCH: a finger has no hover, so reading a card and committing to it must
		# be two separate taps. Otherwise the only way to find out what a card does
		# is to play it, which is exactly backwards — and the hover-to-enlarge that
		# makes a card readable at all would never fire on a phone.
		#
		# Deliberately ONE handler that owns both taps, rather than a reveal handler
		# racing the caller's own. Deciding whether a tap counts by relying on the
		# order two signals were connected in would break the first time somebody
		# moved a line.
		holder.set_meta("preview", open_card)
		b.pressed.connect(func():
			if _previewed != b:
				_close_preview()
				_previewed = b
				open_card.call(true)
				Audio.play("ui_select")
				return                    # first tap only reveals
			_close_preview()              # second tap on the same card commits
			if on_press.is_valid():
				Audio.play("card_play")
				on_press.call())
	else:
		if on_press.is_valid():
			b.pressed.connect(func(): Audio.play("card_play"))
			b.pressed.connect(on_press)
		b.mouse_entered.connect(func(): open_card.call(true))
		b.mouse_exited.connect(func(): open_card.call(false))

	# RIGHT-CLICK holds the card up at full size, anywhere a card is drawn: in hand
	# mid-fight, in a reward pick, in a shop. Hover already enlarges it, but a hover
	# ends the moment you look away from it — you cannot hover a card and read an
	# enemy's intent at the same time, and comparing two cards means holding one in
	# your head. This is the same gesture as the collection's, so there is one thing
	# to learn: see `inspect_card`.
	b.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		b.accept_event()
		inspect_card(b, card, live))
	return b

## Hold ONE card up at a size you can actually read, over whatever screen you are
## on. The single answer to "what does this card do, exactly" — in a fight, in the
## collection, in the deck builder, at a fuse price — because those were four
## different answers before: hover in combat, a tooltip on a list row in the
## collection, a tooltip on a different list row in the deck builder, and nothing
## at all next to a fuse button that was about to change the card's numbers.
##
## `note` is the caller's one line of context — what a level buys, what a fuse
## costs — so the screen that knows it does not have to build its own panel to say
## it. `live` quotes the numbers this card would produce THIS turn, and is null
## outside a fight.
##
## Right-click opens it on any card face; the collection and deck builder put it on
## a left click too, because a list row has no card to right-click and an invisible
## gesture is not a feature.
static func inspect_card(anchor: Node, card: CardData, live: CombatEngine = null,
		note: String = "") -> Control:
	if card == null:
		return null
	# The OUTERMOST Control above this card, not `current_scene`. They are the same
	# node in the game — the combat screen is a Control and it is the current scene —
	# and they are not the same node in the screenshot harness, which parents a
	# screen under a plain Node and would have got a null host and no overlay. Hanging
	# it off the screen's own root also means it dies with the screen, so an
	# inspector left open across a scene change cannot outlive what it was showing.
	var host: Control = null
	var walk := anchor
	while walk != null:
		if walk is Control:
			host = walk as Control
		walk = walk.get_parent()
	if host == null or not is_instance_valid(host):
		return null
	# One at a time. Right-clicking a second card while the first is up replaces it
	# rather than stacking two veils nobody can dismiss in the right order.
	if _inspecting != null and is_instance_valid(_inspecting):
		_inspecting.queue_free()

	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.86)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 200          # above card_picker's veil, which is 100
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(veil)
	_inspecting = veil
	Audio.play("ui_select")

	var close := func() -> void:
		if is_instance_valid(veil):
			veil.queue_free()
		_inspecting = null
	# Anywhere off the card closes it. A modal whose only exit is a small button is
	# a modal players learn to dread, and this one is opened by accident often
	# enough — a right-click is one slip away from a left-click.
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed:
			Audio.play("ui_back")
			close.call())

	# Big enough to read the wordiest card without squinting, bounded so it cannot
	# outgrow a short window: the layout is designed at 1280x720 and the inspector
	# has to survive being opened on the smallest of them.
	var vp := host.get_viewport_rect().size
	var tall := minf(UITheme.px(360.0), vp.y * 0.74)
	var big := Vector2(tall * (UITheme.BASE_CARD.x / UITheme.BASE_CARD.y), tall)
	var face := card_button(veil, card, big, Callable(), "", live)
	var holder := face.get_parent() as Control
	holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# The veil is a ColorRect, not a container, so nothing is going to size this for
	# us — and the card's frame and hit area are both PRESET_FULL_RECT against the
	# holder, so a holder left at zero would draw every label in the right place
	# inside an invisible frame.
	holder.size = big
	holder.position = Vector2(roundf(vp.x * 0.5 - big.x * 0.5),
		roundf(vp.y * 0.5 - big.y * 0.5) - UITheme.px(14))
	# The inspector is not a hand: nothing overlaps it, so the name gets the whole
	# face, and no hover may shrink or lift what the player deliberately opened.
	(holder.get_meta("show_all") as Callable).call(true)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Everything the face cannot fit: rarity, cost, level, and the per-rule prose
	# that the card's own text compresses into a phrase.
	var side := _card_label(veil, Icons.card_tooltip(card,
		live.card_damage(card) if live != null else -1,
		live.card_block(card) if live != null else -1), Color(0.86, 0.84, 0.80))
	side.clip_text = false
	side.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var side_w := minf(UITheme.px(320.0), vp.x * 0.30)
	_place(side, holder.position.x + big.x + UITheme.px(20), holder.position.y,
		side_w, big.y)
	side.add_theme_font_size_override("font_size", UITheme.font())

	if note != "":
		var n := _card_label(veil, note, Color(0.72, 0.86, 0.68))
		n.clip_text = false
		n.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_place(n, holder.position.x - side_w - UITheme.px(20), holder.position.y,
			side_w, big.y)
		n.add_theme_font_size_override("font_size", UITheme.font())

	var hint := _card_label(veil, "Click anywhere to close", Color(0.62, 0.60, 0.66))
	_place(hint, 0.0, holder.position.y + big.y + UITheme.px(10), vp.x, UITheme.px(26))
	hint.add_theme_font_size_override("font_size", UITheme.font())
	return veil

## The card currently held up by `inspect_card`, so a second one replaces it.
static var _inspecting: Control = null

## The collection, the deck builder and the fuse prices are LISTS — one text row
## per card, because thirty rows of card faces is a screen you scroll forever. A
## row has no card face to right-click, so the row's own thumbnail becomes the way
## in: click the picture, get the card. Same size and same place as the plain
## TextureRect it replaces, so no row got wider to gain the affordance.
static func inspect_thumb(parent: Node, card: CardData, side: float,
		note: String = "") -> Button:
	var b := Button.new()
	b.icon = PixelArt.card_art(card.id, Icons.card_family(card))
	b.expand_icon = true
	b.custom_minimum_size = Vector2(side, side)
	b.self_modulate = Icons.rarity_colour(card.rarity)
	b.tooltip_text = "%s — click to see the whole card" % card.name
	# It has to LOOK pressable. The first version was `flat = true`, which is the
	# plain TextureRect it replaced wearing a click handler — the affordance existed
	# only in the tooltip, and a gesture you have to hover to discover is the thing
	# this helper's own docstring says not to ship. Not `UITheme.style_button`,
	# which forces a minimum height and would make every row in the list taller: a
	# thin rarity-coloured edge that brightens under the cursor, at 28px.
	var edge := Icons.rarity_colour(card.rarity)
	for state in [["normal", 0.34, 0.10], ["hover", 0.95, 0.26], ["pressed", 0.95, 0.40]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(edge.r, edge.g, edge.b, float(state[2]))
		sb.border_color = Color(edge.r, edge.g, edge.b, float(state[1]))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.set_content_margin_all(2)
		b.add_theme_stylebox_override(String(state[0]), sb)
	b.pressed.connect(func(): inspect_card(b, card, null, note))
	parent.add_child(b)
	return b

## True where there is a touchscreen and no mouse: phones and tablets.
static func touch_ui() -> bool:
	return DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")

## The card currently held open by a tap, so tapping a different one closes it.
static var _previewed: Button = null

static func _close_preview() -> void:
	if _previewed != null and is_instance_valid(_previewed):
		var h := _previewed.get_parent()
		if h != null and h.has_meta("preview"):
			(h.get_meta("preview") as Callable).call(false)
	_previewed = null

## A card's text layer: wrapped, centred, deaf to the mouse, and clipped as a
## last-resort backstop so a mis-measurement can never spill over the frame.
static func _card_label(holder: Control, text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour)
	holder.add_child(l)
	return l

## A dark plate under a numeral that sits ON the illustration. Without it a cost
## or a damage figure lands on whatever the painting happens to put in that corner,
## and one bright patch makes the most important number on the card unreadable.
static func _badge_bed(holder: Control, x: float, y: float, w: float, h: float) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.03, 0.06, 0.72)
	sb.set_corner_radius_all(int(h * 0.5))
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(p)
	_place(p, x, y, w, h)
	return p

## Pin a child to an exact rectangle inside a non-container parent.
static func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	c.custom_minimum_size = Vector2.ZERO

## Shrink a Label's font until every line it wraps to is actually visible.
##
## Godot has no shrink-to-fit: a Label either overflows its box or clips. Card
## descriptions are authored text of wildly varying length inside a fixed frame, so
## one font size is guaranteed to cut the long ones off.
##
## The loop asks the Label itself rather than predicting it. Two attempts at
## predicting with `Font.get_multiline_string_size()` were both wrong — it breaks on
## word boundaries while AUTOWRAP_WORD_SMART also breaks inside long words, and it
## ignores the `line_spacing` theme constant — and each miss showed up as text the
## player could not read. `get_visible_line_count()` is the same measurement the
## renderer uses, so agreeing with it cannot drift.
static func fit_label(l: Label, avail: Vector2, max_px: int, min_px: int) -> void:
	if avail.x <= 0.0 or avail.y <= 0.0:
		l.add_theme_font_size_override("font_size", maxi(min_px, 1))
		return
	l.size = avail
	var px := max_px
	while px > min_px:
		l.add_theme_font_size_override("font_size", px)
		if l.get_visible_line_count() >= l.get_line_count():
			return
		px -= 1
	l.add_theme_font_size_override("font_size", px)

static func goto(node: Node, path: String) -> void:
	node.get_tree().change_scene_to_file(path)

# --- the way out of a screen -------------------------------------------------
#
# Escape used to leave fullscreen, which is not what that key means anywhere
# else, and Combat had no exit control at all — the longest scene in the game was
# the only one you could not leave. A screen now declares its exit ONCE, with
# `exit_button()`, which builds the button AND binds the key to the same
# Callable. Two independent ways out is the D34 label table again, in navigation.
## The Callable lives ON the node rather than in a static, and this holds only a
## pointer to the node. A static Callable capturing a screen outlives that screen:
## it corrupted the heap at engine shutdown, and because every scene test writes to
## a pipe, the abort ate the buffered "PASS" line and three green tests reported as
## failures. Metadata dies with the node it belongs to.
const ESCAPE_META := "ui_escape"
static var _escape_owner: Node = null

## Register what Escape does on this screen. The owner is remembered so a stale
## action cannot fire on the screen that replaced it: once the old scene is freed
## or removed from the tree, the registration stops answering.
static func escape(owner: Node, action: Callable) -> void:
	if action.is_valid():
		owner.set_meta(ESCAPE_META, action)
	elif owner.has_meta(ESCAPE_META):
		owner.remove_meta(ESCAPE_META)
	_escape_owner = owner

## Withdraw the exit — for a screen that reaches a state it must not be left in,
## like Combat between the killing blow and the reward pick.
static func clear_escape(owner: Node) -> void:
	escape(owner, Callable())

## Does the screen on screen right now offer a way out?
static func has_escape() -> bool:
	return is_instance_valid(_escape_owner) and _escape_owner.is_inside_tree() \
		and _escape_owner.has_meta(ESCAPE_META)

## Take it. False means this screen declared none, and the caller decides what
## Escape should mean instead.
static func run_escape() -> bool:
	if not has_escape():
		return false
	var action: Callable = _escape_owner.get_meta(ESCAPE_META)
	if not action.is_valid():
		return false
	action.call()
	return true

## A button that is also what Escape does.
static func exit_button(parent: Node, text: String, action: Callable,
		height: float = 42.0) -> Button:
	escape(parent, action)
	return button(parent, text, action, height)
