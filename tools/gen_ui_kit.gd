## Procedural nine-slice button frames.
##
## A generator, not shipped art in the usual sense: the frame kit is the one part
## of ART_ASSETS that an illustration tool is BAD at. A nine-slice has to survive
## being stretched from 96px to 1240px wide, and the rule that makes that work is
## mechanical — every pixel of the top and bottom strips must be identical along X,
## every pixel of the left and right strips identical along Y, and the middle a
## single flat colour. `ui_button.png` (128x83, hand-generated) breaks all three,
## which is why the main menu drew five horizontal smears with the text riding over
## the top border (D82).
##
## So the frames are computed. The border profile is a function of distance from
## the edge, evaluated per side, which satisfies the stretch rule by construction
## and cannot drift when someone re-exports.
##
## Run: godot --headless --script tools/gen_ui_kit.gd -- [variant]
##      variant is a key of PALETTES; default "stone".
## Then: godot --headless --import   (writes the .import sidecars)
extends SceneTree

const OUT := "res://assets/art/ui/"

## Border thickness in pixels, and the corner radius. These ARE the nine-slice
## margins — `UITheme._button_state` must pass the same numbers, or the frame is
## sliced somewhere other than where it was drawn.
const BORDER := 12
const RADIUS := 10

## Wide frame for text buttons; square frame for the +/- icon buttons, which are
## too narrow for the wide one's corners to fit side by side.
const WIDE := Vector2i(192, 96)
const SMALL := Vector2i(96, 96)

## Card faces. Authored at the size ART_ASSETS asks for, but the border is 14px and
## NOT the 40/40/48/56 that file specs — a card is 150x132 on screen, so a 48px top
## margin plus a 56px bottom one leaves 28px of stretchable middle and draws a frame
## that is mostly frame. `Icons.card_frame` passes these numbers.
const CARD := Vector2i(320, 448)
const CARD_BORDER := 14
const CARD_RADIUS := 12

## The five rarities, as `Icons.RARITY_COLOURS`. Restated here and asserted equal by
## `tests/test_art.gd` rather than imported: this is a `--script` tool and an
## autoload reference makes it unloadable (D19).
const RARITY := [
	Color(0.78, 0.78, 0.80),
	Color(0.45, 0.80, 0.50),
	Color(0.40, 0.62, 0.95),
	Color(0.72, 0.45, 0.92),
	Color(0.98, 0.72, 0.25),
]
## The card face is darker than a button's, because a card carries an illustration
## AND four bands of text over it. At this luminance the white title measures 13:1
## and the painted family art still reads through at 0.55 opacity.
const CARD_FACE := Color(0.075, 0.068, 0.105)

## The carved border, one entry per button state. Shared by both variants: the
## frame is the same stone whatever is set into it, and only the inlay changes.
## `ink` is the outer outline, `top/bottom/left/right` the lit and shadowed faces,
## `inner` the recessed line where the inlay begins.
const FRAME := {
	"normal": {
		"ink": Color(0.043, 0.039, 0.063),
		"top": Color(0.404, 0.365, 0.502),
		"bottom": Color(0.157, 0.141, 0.216),
		"left": Color(0.325, 0.294, 0.404),
		"right": Color(0.216, 0.196, 0.278),
		"inner": Color(0.071, 0.063, 0.098),
	},
	"hover": {
		"ink": Color(0.055, 0.051, 0.086),
		"top": Color(0.588, 0.533, 0.718),
		"bottom": Color(0.220, 0.200, 0.298),
		"left": Color(0.475, 0.435, 0.584),
		"right": Color(0.302, 0.275, 0.384),
		"inner": Color(0.106, 0.098, 0.153),
	},
	# Bevel inverted: the light is now on the bottom and right, which is what a
	# pushed-in plate looks like.
	"pressed": {
		"ink": Color(0.035, 0.031, 0.051),
		"top": Color(0.157, 0.141, 0.216),
		"bottom": Color(0.365, 0.329, 0.451),
		"left": Color(0.196, 0.176, 0.251),
		"right": Color(0.286, 0.259, 0.353),
		"inner": Color(0.051, 0.047, 0.075),
	},
	"disabled": {
		"ink": Color(0.043, 0.043, 0.051),
		"top": Color(0.243, 0.239, 0.267),
		"bottom": Color(0.129, 0.125, 0.145),
		"left": Color(0.204, 0.200, 0.224),
		"right": Color(0.153, 0.149, 0.169),
		"inner": Color(0.071, 0.071, 0.082),
	},
}

## The inlay: the flat middle the text sits on. This is what decides the ink
## colour, and `UITheme.ink_for()` measures it off the file rather than assuming.
const FACES := {
	# Dark carved slate, in the violet the backdrops and the title art are lit in.
	# Sits on top of a painted backdrop instead of punching bright bars through it.
	"stone": {
		"normal": Color(0.105, 0.095, 0.145),
		"hover": Color(0.176, 0.161, 0.239),
		"pressed": Color(0.071, 0.063, 0.098),
		"disabled": Color(0.098, 0.098, 0.110),
	},
	# The current look, done properly: warm parchment, near-black ink.
	"parchment": {
		"normal": Color(0.867, 0.820, 0.706),
		"hover": Color(0.933, 0.894, 0.784),
		"pressed": Color(0.757, 0.710, 0.604),
		"disabled": Color(0.706, 0.698, 0.678),
	},
}

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var variant: String = args[0] if args.size() > 0 else "stone"
	if not FACES.has(variant):
		print("unknown variant %s; have %s" % [variant, FACES.keys()])
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var wrote := 0
	for state in FRAME:
		var pal: Dictionary = (FRAME[state] as Dictionary).duplicate()
		pal["face"] = (FACES[variant] as Dictionary)[state]
		var suffix := "" if state == "normal" else "_" + String(state)
		wrote += _write("frame_button%s.png" % suffix, WIDE, pal)
		if state == "normal":
			wrote += _write("frame_button_small.png", SMALL, pal)

	# --- card faces ----------------------------------------------------------
	#
	# One shared frame plus one per rarity. `Icons.card_frame` looks for the rarity
	# file first and falls back to the shared one, so a rarity nobody has drawn
	# still gets a card rather than the flat 2px border.
	var card_pal: Dictionary = (FRAME["normal"] as Dictionary).duplicate()
	card_pal["face"] = CARD_FACE
	wrote += _write_card("frame_card.png", card_pal, Color(0, 0, 0, 0))
	for r in RARITY.size():
		wrote += _write_card("frame_card_rarity_%d.png" % r, card_pal, RARITY[r])

	print("gen_ui_kit: wrote %d files from palette '%s' to %s" % [wrote, variant, OUT])
	quit(0)

func _write_card(name: String, pal: Dictionary, inlay: Color) -> int:
	var img := _frame(CARD.x, CARD.y, pal, CARD_BORDER, CARD_RADIUS, inlay)
	var path := ProjectSettings.globalize_path(OUT + name)
	if img.save_png(path) != OK:
		print("  FAILED %s" % name)
		return 0
	print("  %s %dx%d" % [name, CARD.x, CARD.y])
	return 1

func _write(name: String, size: Vector2i, pal: Dictionary) -> int:
	var img := _frame(size.x, size.y, pal, BORDER, RADIUS, Color(0, 0, 0, 0))
	var path := ProjectSettings.globalize_path(OUT + name)
	if img.save_png(path) != OK:
		print("  FAILED %s" % name)
		return 0
	print("  %s %dx%d" % [name, size.x, size.y])
	return 1

## One frame. `t` is depth from the nearest edge, following the rounded corner, and
## the shading is a function of it — so the top strip varies only with y, the left
## strip only with x, and the middle not at all.
func _frame(w: int, h: int, pal: Dictionary, border: int, radius: int,
		inlay: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var face: Color = pal["face"]
	for y in range(h):
		for x in range(w):
			var dx := float(mini(x, w - 1 - x))
			var dy := float(mini(y, h - 1 - y))
			var t := minf(dx, dy)
			var a := 1.0
			if dx < radius and dy < radius:
				# inside the corner box: shape and depth both follow the arc
				var d := sqrt(pow(float(radius) - dx, 2.0) + pow(float(radius) - dy, 2.0))
				a = clampf(float(radius) - d + 0.5, 0.0, 1.0)
				t = float(radius) - d
			if t >= float(border):
				img.set_pixel(x, y, face)
				continue
			var side: String
			if dy <= dx:
				side = "top" if y < h / 2 else "bottom"
			else:
				side = "left" if x < w / 2 else "right"
			var c := _profile(t, pal, side, face, border, inlay)
			c.a = a
			img.set_pixel(x, y, c)
	return img

## The border, outside in: two pixels of ink, a lit bevel edge, the stone face,
## then a recessed line where the inlay begins.
func _profile(t: float, pal: Dictionary, side: String, face: Color,
		border: int, inlay: Color) -> Color:
	var ink: Color = pal["ink"]
	var stone: Color = pal[side]
	if t < 2.0:
		return ink
	if t < 3.0:
		# the bevel: the light sides catch, the dark sides fall away
		if side == "top" or side == "left":
			return stone.lightened(0.22)
		return stone.darkened(0.18)
	# The rarity band: a coloured line set INTO the stone rather than a tint over
	# the whole frame. Rarity has to be readable at a glance across a hand of seven
	# overlapping cards, and a tinted frame is only legible next to another one.
	if inlay.a > 0.0 and t >= 4.0 and t < 7.0:
		if side == "top" or side == "left":
			return inlay
		return inlay.darkened(0.25)
	if t < float(border) - 5.0:
		return stone
	if t < float(border) - 4.0:
		return pal["inner"]
	# Eases from the recessed line into the inlay, and lands exactly ON the face
	# colour at t == border. It has to land exactly, or the middle of the frame and
	# the strip that abuts it are different colours and the seam shows as a box.
	return (pal["inner"] as Color).lerp(face, (t - (float(border) - 4.0)) / 4.0)
