## Where a sprite stands on an isometric tile, and how big it is drawn there.
##
## Split out of `iso_run.gd` for one reason: that file references autoloads, so it cannot
## be loaded in a headless `--script` run at all (the autoload trap D19 documents), and
## this is the part of it that has to be *asserted* rather than looked at. Nothing here
## knows about the floor, the fog or the model — a texture, a tile size and a point.
##
## ## The stand point is measured, not tabulated
##
## `iso_run.gd` used to draw every figure bottom-CENTRE, on the reasoning that the
## installer trims each source to its own silhouette so the middle of the canvas is the
## foot point. The trim is real and the conclusion does not follow: `cutout_lib.place`
## centres the *bounding box*, and a painted figure's bounding box is its widest part — a
## cloak, a swung axe, a market awning — not the patch of ground it touches. Across the 23
## iso figures the stand point sits up to 34 px off the middle of a 128 px canvas, which is
## a fifth of a tile.
##
## The hero is where it showed. Hers is the only art the game MIRRORS — the left-hand
## facings are the right-hand painting flipped (D131) — so her stand point is reflected on
## every turn, and 8 px of error becomes a 16 px slide across the tile between walking
## down-right and walking down-left. Two of her four facings looked off-centre and two
## looked fine, which is exactly what a mirrored anchor error looks like.
##
## A table of 23 offsets would be wrong the first time anything is repainted, and wrong
## silently. So it is read off the art, once, at load.
class_name IsoFooting
extends RefCounted

## How deep into a sprite to look for the ground it stands on, as a fraction of the canvas.
##
## Deep enough to contain the WHOLE STANCE, which is the correction D154 makes to D149. At
## 8% the band held only the hero's front boot — her rear boot's sole sits 22 rows higher,
## because a foot placed behind is further up the screen in this projection — so she was
## anchored on one foot and her body hung 13 px off the tile, swinging 26 px between her two
## mirrored facings. Her rear sole enters at 12%, and 15% clears it on every figure in the
## set while still stopping well below the knees.
const STAND_BAND := 0.15
## Alpha at or above which a pixel is the figure rather than the shadow it casts. The soft
## blob a painted subject sits in is wider than the subject and off to one side, and it
## drags a plain alpha-weighted centroid several percent with it.
const STAND_SOLID := 200
## How much of the contact band's weight to trim off each end before taking its middle.
##
## The stance point is the MIDDLE of what touches the ground, not the average of it: a mean
## follows whichever foot has more pixels at the bottom of the band, which is how the hero
## ended up anchored on one boot. A plain min-to-max midpoint fixes that and then follows a
## single stray pixel instead — a tail, a dangling strap, one lit speck of floor — and it
## moved three of the wanderers by 15-20 px between neighbouring band depths. Trimming a
## tenth of the weight off each side is stable across every depth from 12% to 18%.
const STAND_TRIM := 0.10
## The furthest from its own middle a sprite may be anchored, as a fraction of its width.
##
## Every figure in the set measures inside this; what it catches is the art that is not a
## standing figure at all. `combat.png` is a sword lying across its frame, and its lowest
## point is the blade tip in one corner — measured honestly at 27% of the width, which would
## hang the whole sword up and to the right of the tile it marks. A marker whose contact
## point is that far out is better read as an object centred on its tile.
const STAND_MAX := 0.12


## The horizontal point a sprite stands on, as a signed fraction of its own width from the
## middle of the canvas (+ is to the right). 0.0 for anything unreadable, which puts the
## sprite back where it was drawn before any of this existed.
static func offset(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var img := tex.get_image()
	if img == null:
		return 0.0
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return 0.0
	# `get_data` rather than `get_pixel`: this runs for every sprite the floor can draw,
	# on the frame the screen opens, and a per-pixel call for the same bytes costs an
	# order of magnitude more for nothing.
	var data := img.get_data()
	var rows: int = maxi(1, int(round(float(h) * STAND_BAND)))
	# Solid pixels first. A figure whose whole contact band is soft — the painted swarms
	# are a haze where they meet the floor — is measured on the haze rather than given up
	# on, because a wrong-by-a-little anchor beats no anchor.
	for cut in [STAND_SOLID, 8]:
		var column := PackedFloat32Array()
		column.resize(w)
		var weight := 0.0
		for y in range(h - rows, h):
			var base: int = y * w * 4
			for x in w:
				var a: int = data[base + x * 4 + 3]
				if a >= cut:
					column[x] += float(a)
					weight += float(a)
		if weight <= 0.0:
			continue
		# The middle of the trimmed span: walk in from each side until a tenth of the
		# contact weight is behind you, and take the point halfway between where you stop.
		var edge: float = weight * STAND_TRIM
		var lo := 0
		var run := 0.0
		while lo < w - 1 and run + column[lo] <= edge:
			run += column[lo]
			lo += 1
		var hi := w - 1
		run = 0.0
		while hi > 0 and run + column[hi] <= edge:
			run += column[hi]
			hi -= 1
		var mid: float = (float(lo) + float(hi) + 1.0) * 0.5
		return clampf(mid / float(w) - 0.5, -STAND_MAX, STAND_MAX)
	return 0.0


## Which screen diagonal each painted hero is LOOKING along, as a grid step.
##
## Four facings come from two paintings by mirroring (D131), and the rule for which of the
## four gets the mirror was "the one with the larger x is the right-hand one of the pair, so
## draw it as painted". That rule is not merely mis-tuned, it cannot be right: `hero_s` and
## `hero_n` are the same character from the front and from behind, which means the character
## turned around between them, which means **the two paintings look at opposite sides of the
## screen.** A single "unmirrored is the right-hand one" therefore holds for exactly one of
## the two pairs and is backwards for the other, whichever way the art happens to face. One
## of the four facings was always wrong (D154).
##
## So it is a fact about the files instead, and it is checkable by eye: the face inside
## `hero_s`'s hood is turned to the viewer's LEFT, so she is painted walking down-left, and
## the back view is the same character turned 180° — up-right. Repaint her and this is the
## line to change; nothing else in the drawing code has an opinion about facing.
const HERO_PAINTED := {
	"hero_s": Vector2i(0, 1),    # ↙, toward the camera and to the left
	"hero_n": Vector2i(0, -1),   # ↗, away and to the right — the same character, turned
}


## Which hero painting a step wants: toward the camera or away.
static func hero_role(step: Vector2i) -> String:
	return "hero_s" if (step.x + step.y) > 0 else "hero_n"


## Whether that painting has to be flipped to look along `step`. Each pair has exactly two
## members and one of them is what was painted, so anything else is the mirror.
static func hero_mirrored(step: Vector2i) -> bool:
	var painted: Vector2i = HERO_PAINTED.get(hero_role(step), Vector2i(1, 0))
	return step != painted


## Where `tex` goes if it stands at the middle of the tile at `centre`, drawn `height` px
## tall on a tile of size `t`, with its own stand point `dx` (from `offset`).
##
## No mirroring here, and that is the point (D154). This used to take a `mirrored` flag and
## express the flip as a rect with a NEGATIVE WIDTH, on the understanding that a negative
## width means "draw this flipped, from the right edge leftwards". Half of that is true:
## `draw_texture_rect` does flip, and it draws from `position` RIGHTWARDS by the absolute
## width — so a rect built with its right edge as the position put the hero a full sprite
## width to the side of her own tile, on exactly the two facings that were mirrored. Two
## rounds of anchor arithmetic were spent on a symptom of that.
##
## Mirroring is done to the TEXTURE now (`flipped`), once, at load. A flipped texture takes
## the ordinary positive rect and the ordinary anchor, negated — no engine behaviour to
## remember and nothing left for a call site to get backwards.
##
## The sprite column at `0.5 + dx` lands on `centre.x`, which is the invariant
## `tests/test_art.gd` checks, in those terms.
static func rect(tex: Texture2D, centre: Vector2, t: Vector2, height: float,
		dx: float = 0.0) -> Rect2:
	var w: float = height * float(tex.get_width()) / float(tex.get_height())
	# feet slightly forward of the tile's exact centre, so the figure stands in the
	# diamond rather than balancing on its back corner
	var foot := centre + Vector2(0, t.y * 0.16)
	return Rect2(foot - Vector2(w * (0.5 + dx), height), Vector2(w, height))


## --- the gait ---------------------------------------------------------------------
##
## How far a walking figure rises at the top of its step, as a fraction of a tile's height.
##
## ONE arc per step rather than a repeating sine, and that is the whole design. The model
## moves one tile per turn, so a step IS the unit of the gait: `sin(PI * walk_t)` is zero at
## both ends by construction, so the feet are on the ground at the moment of arrival no
## matter what this amplitude is or what `iso_run.STEP_TIME` becomes. An amplitude tuned
## until the landing happens to look right is one that stops being right the next time
## either number is touched — and a figure whose feet go through the floor on arrival is the
## single most visible thing this screen can get wrong.
##
## It lives here rather than in `iso_run.gd` for the reason the rest of this file does: that
## script references autoloads and cannot be loaded in a `--script` run at all, so anything
## in it can be looked at but not asserted. `tests/test_art.gd` pins both ends of the arc.
const GAIT_LIFT := 0.07
## How much a figure extends as it rises, as a fraction of its height.
##
## This was a SQUASH — compression peaking at the two moments the foot is down — and the
## test below rejected it, correctly. A step ends at `walk_t` exactly 1.0 and the next
## begins at exactly 0.0, with the standing pose in between, so an effect that peaks at the
## ends is at full strength one frame either side of an unscaled figure: she pops 4.5%
## shorter the instant a key goes down, every step. Nothing about the amplitude fixes that;
## the phase is what is wrong.
##
## An effect on this arc can only be continuous if it is zero where the lift is zero, which
## leaves the rise itself to carry it. So she EXTENDS as she comes up, which is the same
## shape the lift already has and reads as a stride reaching rather than as a wobble.
const GAIT_STRETCH := 0.025


## The vertical offset of a figure `walk_t` of the way through a step, on a tile of size `t`.
## Zero while standing still (`walk_t` >= 1), which is the state every other measurement on
## this screen is written against.
static func gait_lift(t: Vector2, walk_t: float) -> Vector2:
	if walk_t >= 1.0 or walk_t < 0.0:
		return Vector2.ZERO
	return Vector2(0.0, -t.y * GAIT_LIFT * sin(PI * walk_t))


## The height multiplier that goes with it. Applied to a rect that is anchored by its FEET
## (`rect` above), so the extension happens upward from the ground rather than outward around
## the middle — the feet stay where they are and the figure reaches.
static func gait_stretch(walk_t: float) -> float:
	if walk_t >= 1.0 or walk_t < 0.0:
		return 1.0
	return 1.0 + GAIT_STRETCH * sin(PI * walk_t)


## `tex` mirrored left-to-right, as a texture in its own right. Null if it cannot be read,
## which the caller treats as "no mirrored art" and falls back to the unflipped file.
static func flipped(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	img.flip_x()
	return ImageTexture.create_from_image(img)
