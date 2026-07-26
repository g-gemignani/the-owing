## Global UI scaling + fullscreen. Autoload.
##
## TUNE ONE NUMBER: `UI_SCALE` below (or override at runtime via
## `UITheme.set_scale(x)`). Everything — fonts, buttons, card sizes, spacing —
## derives from it, so the whole interface grows/shrinks together.
extends Node

## The single knob. 1.0 = original size. 1.6 = 60% bigger. Try 1.4-2.0.
const UI_SCALE := 1.6

## Start the game in fullscreen.
const FULLSCREEN := true

# Base (unscaled) sizes; actual sizes are these times the current scale.
const BASE_FONT := 16
const BASE_TITLE_FONT := 22
# Cards are tall because they hold authored rules text. At the old 90px the font
# had to shrink so far to fit a long description that it stopped being readable.
const BASE_CARD := Vector2(150, 132)

## How much a card grows on hover. A resting card shows only its name and cost, so
## this is what makes the rules text readable — it must be big enough to be worth
## the motion, small enough that a hovered card stays on screen.
const CARD_HOVER_SCALE := 1.45
const BASE_REWARD_CARD := Vector2(170, 148)
const BASE_MAP_NODE := Vector2(150, 52)
const BASE_SEPARATION := 8

var scale: float = UI_SCALE
var theme: Theme

func _ready() -> void:
	# SettingsState applies the persisted scale/fullscreen right after this;
	# UI_SCALE here is only the default for a machine with no settings file yet.
	_rebuild_theme()

## Runtime tuning so you don't have to edit code to find a comfortable size:
##   Ctrl+= / Ctrl+-  scale up / down      Ctrl+0  reset
##   F11 toggle fullscreen                 Esc     leave fullscreen
func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_F11:
		_toggle_fullscreen()
	elif k.keycode == KEY_ESCAPE:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	elif k.ctrl_pressed:
		match k.keycode:
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				set_scale(scale + 0.2)
			KEY_MINUS, KEY_KP_SUBTRACT:
				set_scale(scale - 0.2)
			KEY_0:
				set_scale(UI_SCALE)

func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

## Change the UI scale at runtime; rebuilds the theme and reloads the scene.
func set_scale(new_scale: float) -> void:
	set_scale_silent(new_scale)
	if get_tree().current_scene:
		get_tree().reload_current_scene()

## Apply a scale without reloading — for the settings screen, which rebuilds its
## own contents and would lose its state on a reload.
func set_scale_silent(new_scale: float) -> void:
	scale = clampf(new_scale, 0.6, 3.0)
	_rebuild_theme()

## Painted UI frames. Nine-sliced, so the carved border keeps its proportions at
## any button size instead of smearing.
const BUTTON_ART := "res://assets/art/ui_button.png"
const PANEL_ART := "res://assets/art/ui_panel.png"
## Where the frame gives way to parchment, measured off the art itself. Applied at
## 1:1 and deliberately NOT scaled with `scale`: at 1.6 the border would eat a
## 67px button whole and leave three pixels of middle.
const BUTTON_SLICE := {"l": 22, "r": 22, "t": 19, "b": 21}
const PANEL_SLICE := {"l": 38, "r": 19, "t": 49, "b": 57}
## The parchment reads at luminance 0.86. White text on it measures 1.2:1 — flatly
## invisible — so text on a framed button is near-black, at 18:1.
const INK := Color(0.13, 0.09, 0.07)

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
func style_button(b: Button) -> void:
	var art := _frame(BUTTON_ART, BUTTON_SLICE, Color(1, 1, 1),
		float(BUTTON_SLICE["l"]) + 4.0, 10.0)
	if art == null:
		return
	b.add_theme_stylebox_override("normal", art)
	b.add_theme_stylebox_override("hover", _frame(BUTTON_ART, BUTTON_SLICE,
		Color(1.18, 1.14, 1.20), float(BUTTON_SLICE["l"]) + 4.0, 10.0))
	b.add_theme_stylebox_override("pressed", _frame(BUTTON_ART, BUTTON_SLICE,
		Color(0.82, 0.80, 0.86), float(BUTTON_SLICE["l"]) + 4.0, 10.0))
	b.add_theme_stylebox_override("disabled", _frame(BUTTON_ART, BUTTON_SLICE,
		Color(0.55, 0.55, 0.60, 0.75), float(BUTTON_SLICE["l"]) + 4.0, 10.0))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(0.36, 0.32, 0.32))
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, float(min_button_height()))

## The shortest a framed button may be without crushing its own border.
func min_button_height() -> int:
	return int(BUTTON_SLICE["t"]) + int(BUTTON_SLICE["b"]) + 10

func _rebuild_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = font()

	# text has to clear the carved border, which is drawn at a fixed size
	var pad_x: float = float(BUTTON_SLICE["l"]) + 4.0
	var pad_y: float = 10.0
	var art := _frame(BUTTON_ART, BUTTON_SLICE, Color(1, 1, 1), pad_x, pad_y)
	if art != null:
		theme.set_stylebox("normal", "Button", art)
		theme.set_stylebox("hover", "Button",
			_frame(BUTTON_ART, BUTTON_SLICE, Color(1.18, 1.14, 1.20), pad_x, pad_y))
		theme.set_stylebox("pressed", "Button",
			_frame(BUTTON_ART, BUTTON_SLICE, Color(0.82, 0.80, 0.86), pad_x, pad_y))
		theme.set_stylebox("disabled", "Button",
			_frame(BUTTON_ART, BUTTON_SLICE, Color(0.55, 0.55, 0.60, 0.75), pad_x, pad_y))
		theme.set_color("font_color", "Button", INK)
		theme.set_color("font_hover_color", "Button", INK)
		theme.set_color("font_pressed_color", "Button", INK)
		theme.set_color("font_disabled_color", "Button", Color(0.36, 0.32, 0.32))
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

	var panel_art := _frame(PANEL_ART, PANEL_SLICE, Color(1, 1, 1), 18.0, 14.0)
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
