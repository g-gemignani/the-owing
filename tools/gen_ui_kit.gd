## Procedural nine-slice frames and tileable strips.
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
## **A tileable strip is the same rule in one axis** (D114). A divider, a slider
## groove, a scrollbar well and an HP fill are all laid end to end along their long
## side, and a repeat shows no seam only if every line along that side is the same
## line — which also means the first and last line match, and which also means the
## thing survives being STRETCHED rather than tiled, since `StyleBoxTexture` and
## `TextureProgressBar` do that by default. `_strip()` takes one line of pixels and
## copies it, so the property is structural rather than checked afterwards. Anything
## a strip wants to say has to be said across its short axis: a lit lip, a shadowed
## wall, a rib. Not a diagonal hatch, however much a doomed slice of HP wants one.
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

## The dropdown wears the BUTTON's border, 12px and unchanged — but `UITheme` slices
## it 32/32/28/28, which is where ART_ASSETS says the art is cut and not a number this
## file gets to choose. That is survivable and only because of where the carve stops:
## everything past 12px deep is flat face, so a cut anywhere in 12..32 lands on one
## colour and the strips stay constant. Drawing a 28px-deep carve to "fill" the margin
## is what would break — a 30px OptionButton cannot fit 56px of border and would squash
## it, which is the D83 failure with new numbers.
const DROPDOWN := Vector2i(192, 96)

## Control chrome that is laid end to end rather than sliced: a carved rule between
## sections, HSlider's groove, VScrollBar's well. Short axis is the carve; the long
## axis is one line repeated (D114). The two grooves are 24px across and get the SAME
## profile, one turned 90° — a groove is a groove, and the painted grabbers that ride
## in them (`slider_grabber`, `scrollbar_grabber`) are the same object twice too.
const DIVIDER := Vector2i(128, 16)
const SLIDER_TRACK := Vector2i(128, 24)
const SCROLLBAR_TRACK := Vector2i(24, 128)
## How much of the strip is transparent at each edge. The slider groove floats in the
## middle of the 24px band Godot draws it in; the scrollbar well IS the band.
const SLIDER_INSET := 4
const SCROLLBAR_INSET := 0

## The HP/Block bar: one nine-slice housing plus three fills tiled along it. Thinner
## border than the button because the housing is 48px tall at 1:1 and a 12px carve top
## and bottom would leave 24px of well to put a bar in.
const BAR_FRAME := Vector2i(256, 48)
const BAR_BORDER := 10
const BAR_RADIUS := 8
const BAR_FILL := Vector2i(32, 48)

## Three fills, and they exist as three files so they can be told apart on a 24px-tall
## bar at the edge of vision. So they are separated three ways at once: by hue (blood,
## blood, steel), by luminance (measured 0.16, 0.28, 0.58 through the body of each
## strip — every step at least 1.7x the last, so the order survives greyscale and a dim
## monitor), and the loss slice additionally by RIBS, which is the only kind of texture
## a tileable strip may carry.
##
## The hues are combat's own: `Combat._float_number` prints HP loss in a warm red and
## "+N block" in a cold blue, and the hurt veil is Color(0.7, 0.05, 0.05). Restated
## here at bar luminance rather than imported, for the D19 reason the rarity table
## above is restated — this is a `--script` tool and an autoload reference kills it.
const BAR := {
	"hp_fill": Color(0.72, 0.16, 0.18),
	"hp_loss": Color(0.28, 0.13, 0.14),
	"block_fill": Color(0.42, 0.60, 0.86),
}

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

	# --- control chrome ------------------------------------------------------
	#
	# The dropdown takes the button's frame with the PRESSED face set into it: an
	# OptionButton is not a thing you push, it is a slot showing what is currently
	# chosen, and one step darker than a button is what a slot looks like. It also
	# keeps the face dark, which the installed `dropdown_arrow.png` needs — the
	# chevron is pale carved stone and would vanish on a parchment plaque.
	#
	# NOTE for whoever owns `scripts/ui_theme.gd`: that file paints OptionButton's
	# text with the INK constant the moment this file exists, and INK is near-black,
	# chosen back when the kit was parchment. On the stone variant that is near-black
	# on near-black — the exact mistake D83 fixed for Button by measuring instead.
	# It wants `ink_for(PixelArt.ui_kit("dropdown"))`, not a constant.
	var drop: Dictionary = (FRAME["normal"] as Dictionary).duplicate()
	drop["face"] = (FACES[variant] as Dictionary)["pressed"]
	wrote += _save("dropdown.png",
		_frame(DROPDOWN.x, DROPDOWN.y, drop, BORDER, RADIUS, Color(0, 0, 0, 0)))
	wrote += _save("divider.png", _strip(DIVIDER.x, _divider_line(DIVIDER.y), false))
	wrote += _save("slider_track.png",
		_strip(SLIDER_TRACK.x, _groove_line(SLIDER_TRACK.y, SLIDER_INSET), false))
	wrote += _save("scrollbar_track.png",
		_strip(SCROLLBAR_TRACK.y, _groove_line(SCROLLBAR_TRACK.x, SCROLLBAR_INSET), true))

	# --- the vitals bar ------------------------------------------------------
	#
	# The housing is the pressed palette all the way through: a bar is a trough cut
	# into the frame, so its light is on the bottom and its middle is the recessed
	# line's own colour rather than a face sitting proud of it.
	var well: Dictionary = (FRAME["pressed"] as Dictionary).duplicate()
	well["face"] = well["inner"]
	wrote += _save("bar_frame.png",
		_frame(BAR_FRAME.x, BAR_FRAME.y, well, BAR_BORDER, BAR_RADIUS, Color(0, 0, 0, 0)))
	for key in BAR:
		wrote += _save("bar_%s.png" % key,
			_strip(BAR_FILL.x, _fill_line(BAR[key], key == "hp_loss"), false))

	print("gen_ui_kit: wrote %d files from palette '%s' to %s" % [wrote, variant, OUT])
	quit(0)

func _write_card(name: String, pal: Dictionary, inlay: Color) -> int:
	return _save(name, _frame(CARD.x, CARD.y, pal, CARD_BORDER, CARD_RADIUS, inlay))

func _write(name: String, size: Vector2i, pal: Dictionary) -> int:
	return _save(name, _frame(size.x, size.y, pal, BORDER, RADIUS, Color(0, 0, 0, 0)))

## Writes one image and reports it at the size it actually came out, which is the
## number ART_ASSETS is checked against.
func _save(name: String, img: Image) -> int:
	var path := ProjectSettings.globalize_path(OUT + name)
	if img.save_png(path) != OK:
		print("  FAILED %s" % name)
		return 0
	print("  %s %dx%d" % [name, img.get_width(), img.get_height()])
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

## One tileable strip, built from ONE line of pixels repeated along its long axis.
##
## `line` is the profile across the SHORT axis — one colour per row for a horizontal
## strip, one per column when `vertical`. Copying it is what makes the file tileable:
## column x and column x+1 are the same pixels, so the seam a repeat would show does
## not exist, and neither does the smear a stretch would produce (D114). Nothing here
## can accidentally break that, which is the whole reason the strips are computed
## alongside the frames instead of painted.
func _strip(long: int, line: Array, vertical: bool) -> Image:
	var n := line.size()
	var img := Image.create(n if vertical else long, long if vertical else n,
		false, Image.FORMAT_RGBA8)
	for i in n:
		for j in long:
			img.set_pixel(i if vertical else j, j if vertical else i, line[i])
	return img

## A carved channel: the near wall in shadow, the far lip catching the light.
##
## The pressed palette, because that IS the inversion a recess needs — light on the
## bottom and right is what the pushed-in button state already means. `inset` lines at
## each end stay transparent so the groove floats in its band instead of painting a
## bar the full height of the control.
func _groove_line(n: int, inset: int) -> Array:
	var p: Dictionary = FRAME["pressed"]
	var span := n - inset * 2
	var out: Array = []
	for i in n:
		if i < inset or i >= n - inset:
			out.append(Color(0, 0, 0, 0))
			continue
		var d := i - inset
		var t: int = mini(d, span - 1 - d)
		if t == 0:
			out.append(p["ink"])
		elif t == 1:
			out.append((p["top"] as Color).darkened(0.30) if d * 2 < span
				else (p["bottom"] as Color).lightened(0.12))
		else:
			# The floor of the channel, in shadow under the near wall and lifting toward
			# the lit lip. Lighter than the screen behind it, which is the wrong way round
			# for a recess and is nonetheless the only way it reads: the game clears to
			# 0.07 and a groove darker than that is a hole in a black wall — the first cut
			# of both tracks drew as two hairlines with nothing between them. The painted
			# grabbers that ride in these are mid-grey stone, so a floor at that level is
			# also what matches the chrome already installed.
			var f: float = clampf(float(d - 2) / maxf(1.0, float(span - 5)), 0.0, 1.0)
			var shade: Color = (p["inner"] as Color).lerp(p["left"], 0.30)
			out.append(shade.lerp(p["left"], f))
	return out

## The rule between sections: a cut, a lit lower lip, and nothing else.
##
## Alpha-blended to transparent at both edges rather than drawn on a plate, because a
## divider sits over whatever the screen already has behind it — a painted backdrop
## most of the time — and a 128x16 opaque bar across that is a scar, not a rule.
func _divider_line(n: int) -> Array:
	var p: Dictionary = FRAME["normal"]
	var ink: Color = p["ink"]
	var lit: Color = p["top"]
	var out: Array = []
	for y in n:
		var c := Color(0, 0, 0, 0)
		# the cut, two solid pixels with a soft shoulder above it
		if y == n / 2 - 3:
			c = Color(ink.r, ink.g, ink.b, 0.25)
		elif y == n / 2 - 2:
			c = Color(ink.r, ink.g, ink.b, 0.65)
		elif y == n / 2 - 1 or y == n / 2:
			c = ink
		elif y == n / 2 + 1:
			c = Color(lit.r, lit.g, lit.b, 0.85)
		elif y == n / 2 + 2:
			c = Color(lit.r, lit.g, lit.b, 0.40)
		elif y == n / 2 + 3:
			c = Color(ink.r, ink.g, ink.b, 0.18)
		out.append(c)
	return out

## One bar fill: a lit meniscus at the top, the body, and shadow where it meets the
## housing's floor. `ribbed` scores it — the loss slice is the same blood as the HP
## beside it and has to read as damaged at a glance, and horizontal ribs are the only
## texture that survives being tiled and stretched along the bar (D114).
func _fill_line(base: Color, ribbed: bool) -> Array:
	var out: Array = []
	var n := BAR_FILL.y
	for y in n:
		var f := float(y) / float(n - 1)
		var c: Color = base.lightened(0.34 * (1.0 - smoothstep(0.0, 0.30, f)))
		c = c.darkened(0.30 * smoothstep(0.55, 1.0, f))
		if ribbed and (y + 5) % 8 < 2:
			c = c.darkened(0.45)
		out.append(c)
	return out
