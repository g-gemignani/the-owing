## The mouse pointer: the game's own cursor, set once, and swapped for the pressed
## variant while the button is down.
##
## An autoload rather than a screen, for the reason SettingsState and Audio are
## autoloads — this is one DisplayServer-wide setting that outlives every scene
## change. A screen that set it would be deciding for the whole game from inside
## one corner of it, and would have to remember to unset it on the way out.
##
## NOT folded into UITheme, which is the other "how the game looks, set once"
## autoload, for one concrete reason: the press has to be seen even when a Button
## eats the click. UITheme listens on `_unhandled_input` (that is where F11 lives),
## and `_unhandled_input` by definition never runs for an event a Control consumed
## — which is every click that matters here. This listens on `_input`, which the
## viewport dispatches before GUI handling, so the swap happens on the presses the
## player actually makes (D125).
extends Node

const ARROW_ART := "res://assets/art/ui/cursor.png"
const PRESSED_ART := "res://assets/art/ui/cursor_press.png"

## Where the point of the spike is in each file, in pixels.
##
## Godot puts THIS pixel of the image on the mouse position, so it is not
## decoration: a hotspot in the wrong place moves the click away from the thing the
## player was aiming at, and it is the kind of wrong nobody can name — the game
## just feels loose. So it was measured off the two files rather than left at the
## (0, 0) the call defaults to. Both are a slim iron spike lying along the 45°
## diagonal, and both carry a 1px border the generator drew around the frame, so
## the point is emphatically not in the corner:
##
##   `cursor.png`        first ink on the diagonal is (1, 1); the first pixel that
##                       is solid rather than antialiased edge is (2, 2).
##   `cursor_press.png`  the spike is shorter and its point flared, and the leading
##                       edge of the flare crosses the diagonal at (8, 8).
##
## The two DIFFER on purpose. Each hotspot is that image's own point, so the point
## stays nailed to one screen pixel across the click and the spike reads as driving
## in. Give them a shared hotspot and the whole pointer jumps six pixels sideways
## on every mouse-down.
const ARROW_HOTSPOT := Vector2(2, 2)
const PRESSED_HOTSPOT := Vector2(8, 8)

var _arrow: Texture2D = null
var _pressed: Texture2D = null

func _ready() -> void:
	# Headless has no cursor, and neither does a phone — one flag covers both, and
	# skipping the loads keeps the test suite from paying for art it cannot draw.
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CUSTOM_CURSOR_SHAPE):
		return
	# "Use it if it exists", like the backdrops and the button kit: with no file
	# installed the game keeps the system arrow rather than losing its pointer.
	if ResourceLoader.exists(ARROW_ART):
		_arrow = load(ARROW_ART) as Texture2D
	if ResourceLoader.exists(PRESSED_ART):
		_pressed = load(PRESSED_ART) as Texture2D
	# Both up front. Loading the pressed one on the first click would put a disk
	# read inside the frame the player is clicking on.
	_wear(false)

## Godot has no "pressed" cursor shape, so the pressed state is CURSOR_ARROW with a
## different image under it. ARROW is the only shape this game ever asks for —
## nothing sets `mouse_default_cursor_shape` anywhere, checked, including the crawl
## floor, whose tiles are clicked through `_on_floor_input` and never change shape
## — so replacing it replaces the pointer everywhere and nothing else has to know.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_wear(mb.pressed)

## Alt-tabbing away mid-click never delivers the release, which would otherwise
## leave the driven-in spike on screen for the rest of the session.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_wear(false)

func _wear(pressed: bool) -> void:
	var tex: Texture2D = _pressed if pressed else _arrow
	if tex == null:
		return
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_ARROW,
		PRESSED_HOTSPOT if pressed else ARROW_HOTSPOT)
