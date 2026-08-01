## Interface sizes + fullscreen. Autoload.
##
## Every size in the game derives from the constants below, at a FIXED scale. There
## used to be a zoom (Ctrl +/-/0, a settings slider, a persisted value), and it was
## redundant: `project.godot` sets `stretch/mode = "canvas_items"` against a
## 1280x720 base, so the engine already scales the entire canvas to whatever the
## window is. Measured, because this is the sort of thing that gets assumed:
##
##     window 1280x720  -> viewport 1280x720 units
##     window  640x360  -> viewport 1280x720 units
##     window 1920x1080 -> viewport 1280x720 units
##     window 1024x768  -> viewport 1280x960 units   (aspect "expand")
##
## So shrinking the window already shrinks the interface, and fullscreen already
## fills the display. A second multiplier on top of that could only disagree with
## the layout it was laid out for — and did: the same knob is what put the map's
## only actionable row off screen (D33) and what a restated default silently
## overrode for every new player (D53).
##
## The layout is designed at 1280x720. F11 toggles fullscreen; nothing else resizes.
extends Node

const UI_SCALE := 1.0

## Start the game in fullscreen.
const FULLSCREEN := true

# Base (unscaled) sizes; actual sizes are these times the current scale.
const BASE_FONT := 16
const BASE_TITLE_FONT := 22
# A PORTRAIT card, in two parts: the illustration on top, the name and rules text
# below it — the shape Slay the Spire and Hearthstone both use, and the shape a
# card has to be for the picture to be a picture rather than a wash behind words.
#
# The width is unchanged from the old 150x132. The fan's arithmetic is all in
# widths (step, overlap, the reserves either side), so keeping it means the hand
# still lays out the same and only the vertical budget moved. What pays for the
# extra height is that the card no longer has to fit on screen whole: see
# Combat.HAND_PEEK.
const BASE_CARD := Vector2(150, 214)

## The bands, top to bottom, as fractions of the card's HEIGHT. They have to sum
## to less than 1: what is left over is the rules text, which is the one region
## that must absorb whatever the others do not use.
const CARD_ART_BAND := 0.47     ## the illustration, from the top edge down
const CARD_NAME_BAND := 0.13    ## the name strip directly beneath it
## Border inset, as a fraction of the card's WIDTH — never its height, or a tall
## card would get a fat top and bottom margin and a thin one at the sides.
const CARD_PAD := 0.055

## How much a card grows on hover. The rules text is on the card at all times now,
## so this is no longer what makes it exist — it is what makes it comfortable, and
## what lifts a card in hand clear of the screen edge it is hanging over.
const CARD_HOVER_SCALE := 1.45
const BASE_REWARD_CARD := Vector2(172, 246)
const BASE_MAP_NODE := Vector2(150, 52)
const BASE_SEPARATION := 8

## Fixed. Read by every size helper below; there is no setter, deliberately.
var scale: float = UI_SCALE
var theme: Theme

func _ready() -> void:
	_rebuild_theme()

##   F11  toggle fullscreen        Esc  back / pause
func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11:
		_toggle_fullscreen()
	elif k.keycode == KEY_ESCAPE:
		# Escape means "the way out of this screen" — the very Callable the screen's
		# own Back/Menu button runs, registered through `UI.exit_button`. Leaving
		# fullscreen is only the fallback, for a screen that declares no exit (the
		# hub screens); F11 toggles it either way.
		if not UI.run_escape():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

## Painted UI frames. Nine-sliced, so the carved border keeps its proportions at
## any button size instead of smearing.
const BUTTON_ART := "res://assets/art/ui_button.png"
const PANEL_ART := "res://assets/art/ui_panel.png"
## Where the frame gives way to parchment, measured off the art itself. Applied at
## 1:1 and deliberately NOT scaled with `scale`: scaled up it would eat a button
## whole and leave a few pixels of middle. min_button_height() keeps buttons taller
## than their own border regardless of the scale in force.
const BUTTON_SLICE := {"l": 22, "r": 22, "t": 19, "b": 21}
const PANEL_SLICE := {"l": 38, "r": 19, "t": 49, "b": 57}
## The parchment reads at luminance 0.86. White text on it measures 1.2:1 — flatly
## invisible — so text on a framed button is near-black, at 18:1.
const INK := Color(0.13, 0.09, 0.07)
## And the reverse, for a frame with a DARK inlay. Which of the two a button gets is
## measured off its own art by `ink_for()`, not decided here: the kit can be light
## or dark, and hardcoding one of them is exactly how white-on-parchment happened.
const PALE := Color(0.949, 0.914, 0.831)

## The generated kit's border thickness (`tools/gen_ui_kit.gd` BORDER) and the
## padding that clears it. These are nine-slice margins in TEXTURE pixels, so they
## have to match where the art was actually drawn — slicing a 12px border at 28
## eats 16px of the flat middle and stretches the border instead, which is the
## squashed-frame failure the old numbers produced on a 50px button.
const KIT_SLICE := 12
## Padding is measured from the button edge, so it has to clear the 12px border
## before it buys any gap: at 16 the text sat 4px off the carved edge and read as
## clipped on the deck builder's short buttons.
const KIT_PAD_X := 22.0
const KIT_PAD_Y := 8.0

## How big a control's own icon may draw, in layout pixels. ONE number, because a
## checkbox and a slider handle sit in the same list at the same eye level and any
## difference between them reads as one of the two being wrong (D113).
##
## A nine-slice is authored at 2x and costs nothing for it — the slice margins scale
## with the frame. A theme ICON is not: Godot blits it at its own pixel size, so the
## 64x64 the asset list asks for (2x of 32, for the 1440p and 4K scale-ups) draws as a
## 64px block in a 1280x720 row built for a 16px font. It ate the row: the label
## started under the tile and the first letter of "Fullscreen" was painted over by an
## opaque stone corner (D107). Capping rather than shrinking the files keeps the
## resolution the scale-up needs, and keeps the decision in the one place that knows
## how big a row is.
const CONTROL_ICON := 26.0

## Which ink reads on this frame, measured off the middle of the art itself.
##
## Sampled from the flat inlay (the centre 30%), which is the only part text is
## ever drawn over. Cached: this decodes an image, and `style_button` is called a
## few hundred times on the deck builder.
static var _ink_cache: Dictionary = {}
static func ink_for(tex: Texture2D) -> Color:
	if tex == null:
		return INK
	var key := tex.resource_path
	if _ink_cache.has(key):
		return _ink_cache[key]
	var ink := INK
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var tot := 0.0
		var n := 0
		for y in range(int(h * 0.35), maxi(int(h * 0.65), int(h * 0.35) + 1)):
			for x in range(int(w * 0.35), maxi(int(w * 0.65), int(w * 0.35) + 1)):
				tot += img.get_pixel(x, y).get_luminance()
				n += 1
		ink = INK if tot / maxf(1.0, float(n)) > 0.5 else PALE
	_ink_cache[key] = ink
	return ink

## The painted frame kit ART.md specifies, wired so dropping a file in turns it on.
##
## Only `ui_button.png` and `ui_panel.png` had code behind them; the other 22 files
## in the kit would have sat on disk doing nothing. Each of these is "use it if it
## exists, otherwise keep exactly what ships today", so the kit can arrive one file
## at a time instead of as a single all-or-nothing swap.
## A nine-slice from the kit, or null if nobody has drawn it yet.
func kit_frame(name: String, l: int, r: int, top: int, bot: int,
		pad_x: float = 12.0, pad_y: float = 8.0) -> StyleBox:
	var tex := PixelArt.ui_kit(name)
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = l
	sb.texture_margin_right = r
	sb.texture_margin_top = top
	sb.texture_margin_bottom = bot
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

## A kit icon, scaled down if it is bigger than `max_side` layout pixels.
##
## `icon_max_width` would be the right tool and only Button has it. A slider draws its
## grabber at the texture's own size, full stop, so the only lever on an HSlider is the
## size of the texture you hand it — which is why this resamples instead of setting a
## constant. Kept OUT of `kit_frame`'s path: a nine-slice must never be pre-scaled,
## because its slice margins are in texture pixels and resampling moves the border out
## from under them.
##
## Returns the texture untouched when it already fits, so nothing is resampled for the
## sake of it, and null when the file is absent — same contract as `PixelArt.ui_kit`,
## so the caller's `!= null` gate still means "the art is installed".
func kit_icon(name: String, max_side: float) -> Texture2D:
	var tex := PixelArt.ui_kit(name)
	if tex == null:
		return null
	var side := maxf(float(tex.get_width()), float(tex.get_height()))
	if side <= max_side:
		return tex
	var img := tex.get_image()
	if img == null:
		return tex
	if img.is_compressed():
		img.decompress()
	var k := max_side / side
	img.resize(maxi(1, int(round(tex.get_width() * k))),
		maxi(1, int(round(tex.get_height() * k))), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

## A button state: its own painted file if one exists, else today's tinted frame.
##
## `small` picks the square frame, for the +/- icon buttons the deck builder builds:
## the wide frame's two corners are 24px of the 36px those buttons are, so it draws
## as corner-corner with no face between them.
func _button_state(state: String, tint: Color, pad_x: float, pad_y: float,
		small: bool = false) -> StyleBox:
	var base := "frame_button_small" if small else "frame_button" + state
	var painted := kit_frame(base, KIT_SLICE, KIT_SLICE, KIT_SLICE, KIT_SLICE,
		KIT_PAD_X if not small else 6.0, KIT_PAD_Y)
	if painted != null:
		return painted
	return _frame(BUTTON_ART, BUTTON_SLICE, tint, pad_x, pad_y)

## The texture a button will actually be dressed in, or null if none is installed.
func _button_texture(small: bool = false) -> Texture2D:
	var tex := PixelArt.ui_kit("frame_button_small" if small else "frame_button")
	if tex != null:
		return tex
	return load(BUTTON_ART) as Texture2D

func _frame(path: String, slice: Dictionary, tint: Color,
		pad_x: float, pad_y: float) -> StyleBox:
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = slice["l"]
	sb.texture_margin_right = slice["r"]
	sb.texture_margin_top = slice["t"]
	sb.texture_margin_bottom = slice["b"]
	sb.modulate_color = tint
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

## Dress a button in the painted frame.
##
## Applied as per-button OVERRIDES rather than through the global Theme: a Theme
## carrying these styleboxes was verified not to resolve — a Button under it still
## reported the engine default, while the same theme's font size resolved fine.
## Overrides were verified to work, so they are what ships.
##
## Also enforces a height that fits the carved border. The border is drawn 1:1 at
## 40px, and four screens had 31px inline buttons that would have squashed it.
## `small` asks for the square icon frame — the +/- buttons, which are 40px wide
## and cannot wear a frame whose two corners are 24px of that.
##
## It is a PARAMETER and not something measured off the button, because there is
## nothing to measure yet: almost every call site in the game styles the button
## and then sets its text, so a `b.text.length()` test sees "" and calls every
## button in the game small. That shipped for one screenshot and put the text of
## seven deck-builder buttons underneath their own border.
func style_button(b: Button, small: bool = false) -> void:
	var pad_x := float(BUTTON_SLICE["l"]) + 4.0
	var art := _button_state("", Color(1, 1, 1), pad_x, 10.0, small)
	if art == null:
		return
	b.add_theme_stylebox_override("normal", art)
	b.add_theme_stylebox_override("hover",
		_button_state("_hover", Color(1.18, 1.14, 1.20), pad_x, 10.0, small))
	b.add_theme_stylebox_override("pressed",
		_button_state("_pressed", Color(0.82, 0.80, 0.86), pad_x, 10.0, small))
	b.add_theme_stylebox_override("disabled",
		_button_state("_disabled", Color(0.55, 0.55, 0.60, 0.75), pad_x, 10.0, small))
	var ink := ink_for(_button_texture(small))
	b.add_theme_color_override("font_color", ink)
	b.add_theme_color_override("font_hover_color", ink)
	b.add_theme_color_override("font_pressed_color", ink)
	b.add_theme_color_override("font_disabled_color", ink.lerp(Color(0.5, 0.5, 0.5), 0.55))
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, float(min_button_height()))

## The shortest a framed button may be without crushing its own border. The border
## is drawn 1:1, so this does NOT shrink with the UI scale.
func min_button_height() -> int:
	return int(BUTTON_SLICE["t"]) + int(BUTTON_SLICE["b"]) + 10

## Height for a button whose design calls for `base` unscaled pixels.
##
## Never shorter than the carved border needs. Callers used to write
## `px(40)` directly, which was 64px at scale 1.6 and fine — and 40px at scale 1.0,
## which squashed the frame. One helper so lowering the default scale cannot quietly
## break every button in the game again.
func button_height(base: float) -> float:
	return maxf(px(base), float(min_button_height()))

func _rebuild_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = font()

	# text has to clear the carved border, which is drawn at a fixed size
	var pad_x: float = float(BUTTON_SLICE["l"]) + 4.0
	var pad_y: float = 10.0
	var art := _button_state("", Color(1, 1, 1), pad_x, pad_y)
	if art != null:
		theme.set_stylebox("normal", "Button", art)
		theme.set_stylebox("hover", "Button",
			_button_state("_hover", Color(1.18, 1.14, 1.20), pad_x, pad_y))
		theme.set_stylebox("pressed", "Button",
			_button_state("_pressed", Color(0.82, 0.80, 0.86), pad_x, pad_y))
		theme.set_stylebox("disabled", "Button",
			_button_state("_disabled", Color(0.55, 0.55, 0.60, 0.75), pad_x, pad_y))
		var tink := ink_for(_button_texture())
		theme.set_color("font_color", "Button", tink)
		theme.set_color("font_hover_color", "Button", tink)
		theme.set_color("font_pressed_color", "Button", tink)
		theme.set_color("font_disabled_color", "Button",
			tink.lerp(Color(0.5, 0.5, 0.5), 0.55))
		# a button must stay taller than its own border, or the frame collapses
		theme.set_constant("minimum_character_width", "Button", 1)
	else:
		# no art: the old flat frame, so the game still runs from a bare checkout
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.12, 0.16)
		sb.border_color = Color(0.46, 0.40, 0.34)
		sb.set_border_width_all(maxi(2, int(round(2 * scale))))
		sb.set_corner_radius_all(0)
		sb.content_margin_left = round(10 * scale)
		sb.content_margin_right = round(10 * scale)
		sb.content_margin_top = round(6 * scale)
		sb.content_margin_bottom = round(6 * scale)
		theme.set_stylebox("normal", "Button", sb)
		var hover := sb.duplicate() as StyleBoxFlat
		hover.bg_color = Color(0.24, 0.20, 0.24)
		theme.set_stylebox("hover", "Button", hover)
		var pressed := sb.duplicate() as StyleBoxFlat
		pressed.bg_color = Color(0.09, 0.08, 0.11)
		theme.set_stylebox("pressed", "Button", pressed)
		var disabled := sb.duplicate() as StyleBoxFlat
		disabled.bg_color = Color(0.12, 0.12, 0.14)
		disabled.border_color = Color(0.24, 0.24, 0.28)
		theme.set_stylebox("disabled", "Button", disabled)

	# --- the rest of the kit: each one silently on the moment its file exists ---
	var dropdown := kit_frame("dropdown", 32, 32, 28, 28, 14.0, 10.0)
	if dropdown != null:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, "OptionButton", dropdown)
		# MEASURED off the art, not assumed. This was a hardcoded `INK`, chosen when
		# the kit was parchment and harmless for as long as `dropdown.png` did not
		# exist — the whole block is skipped while the file is absent. The moment the
		# file landed (D115) it became near-black text on a face of luminance 0.067:
		# 1.27:1, which is not low contrast, it is invisible. It would have taken the
		# three filter dropdowns and the settings dropdowns out together.
		#
		# Compensating in the ART was the wrong lever and was rejected: a paler
		# dropdown face would then have swallowed `dropdown_arrow.png`, which is a
		# pale carved-stone chevron. The frame is right; the ink was guessed.
		theme.set_color("font_color", "OptionButton", ink_for(PixelArt.ui_kit("dropdown")))
	var arrow := PixelArt.ui_kit("dropdown_arrow")
	if arrow != null:
		theme.set_icon("arrow", "OptionButton", arrow)
	var track := kit_frame("slider_track", 8, 8, 8, 8, 0.0, 0.0)
	if track != null:
		theme.set_stylebox("slider", "HSlider", track)
	# 48x48 as installed, which drew nearly twice the checkbox beside it in the same
	# settings list. Capped to the same number they now share (D113).
	var grabber := kit_icon("slider_grabber", CONTROL_ICON * scale)
	if grabber != null:
		theme.set_icon("grabber", "HSlider", grabber)
		theme.set_icon("grabber_highlight", "HSlider", grabber)
	var bar := kit_frame("scrollbar_track", 8, 8, 8, 8, 0.0, 0.0)
	if bar != null:
		theme.set_stylebox("scroll", "VScrollBar", bar)
	var thumb := kit_frame("scrollbar_grabber", 8, 8, 8, 8, 0.0, 0.0)
	if thumb != null:
		theme.set_stylebox("grabber", "VScrollBar", thumb)
		theme.set_stylebox("grabber_highlight", "VScrollBar", thumb)
	var checked := PixelArt.ui_kit("checkbox_on")
	var unchecked := PixelArt.ui_kit("checkbox_off")
	if checked != null and unchecked != null:
		theme.set_icon("checked", "CheckBox", checked)
		theme.set_icon("unchecked", "CheckBox", unchecked)
		# On "CheckBox" and NOT on "Button": a control reads a theme constant off its
		# own type before its base type, so this reaches every checkbox state without
		# capping the icon on the relic, power and card-thumbnail buttons, which are
		# deliberately bigger than a tick.
		theme.set_constant("icon_max_width", "CheckBox", int(round(CONTROL_ICON * scale)))
		theme.set_constant("h_separation", "CheckBox", int(round(10 * scale)))
		# The states have to come from ONE family, and the missing one was `hover_pressed`.
		# A checkbox is a TOGGLE: checked, it draws `pressed`, and hovering a checked box
		# asks for `hover_pressed` — which nothing set, on either type. So it fell through
		# to the engine's default, an empty box with no content margin, and hovering a
		# ticked row did not light it, it DELETED the frame. The 22px of padding that
		# frame was carrying went with it, sliding the label left, under an icon that had
		# not moved. That is the "text hidden by the checkbox" (D107).
		var states := {
			"normal": "normal", "hover": "hover", "pressed": "pressed",
			"hover_pressed": "hover", "disabled": "disabled", "focus": "focus",
		}
		for st in states:
			var from: String = states[st]
			if not theme.has_stylebox(from, "Button"):
				continue
			var sb := theme.get_stylebox(from, "Button")
			theme.set_stylebox(st, "CheckBox", sb)
			# Every toggle in the game has the same hole, not just the checkboxes.
			if not theme.has_stylebox(st, "Button"):
				theme.set_stylebox(st, "Button", sb)
	var tip := kit_frame("frame_tooltip", 24, 24, 24, 24, 10.0, 8.0)
	if tip != null:
		theme.set_stylebox("panel", "TooltipPanel", tip)

	var panel_art := kit_frame("frame_panel", 64, 64, 64, 64, 18.0, 14.0)
	if panel_art == null:
		panel_art = _frame(PANEL_ART, PANEL_SLICE, Color(1, 1, 1), 18.0, 14.0)
	if panel_art != null:
		theme.set_stylebox("panel", "PanelContainer", panel_art)
	else:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(0.07, 0.06, 0.09)
		theme.set_stylebox("panel", "PanelContainer", panel)
	get_tree().root.theme = theme
	if get_tree().root.get_viewport() != null:
		RenderingServer.set_default_clear_color(Color(0.07, 0.06, 0.09))

# --- helpers used by the scenes ---
func font() -> int:
	return int(round(BASE_FONT * scale))

func title_font() -> int:
	return int(round(BASE_TITLE_FONT * scale))

func sep(base: int = BASE_SEPARATION) -> int:
	return int(round(base * scale))

func card_size() -> Vector2:
	return BASE_CARD * scale

func reward_card_size() -> Vector2:
	return BASE_REWARD_CARD * scale

func map_node_size() -> Vector2:
	return BASE_MAP_NODE * scale

func px(base: float) -> float:
	return base * scale

## Apply the root margin so content isn't flush against screen edges.
func pad(control: Control) -> void:
	var m := int(round(16 * scale))
	control.add_theme_constant_override("margin_left", m)
	control.add_theme_constant_override("margin_top", m)
	control.add_theme_constant_override("margin_right", m)
	control.add_theme_constant_override("margin_bottom", m)
