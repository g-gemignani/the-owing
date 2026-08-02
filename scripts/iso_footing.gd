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
## The art is bottom-anchored with no bottom pad, so this band is boots, hooves, chest feet
## or the base of a stall — and nothing higher. Wider than this and the band starts
## collecting the parts of a shape that hang OVER the ground rather than rest on it.
const STAND_BAND := 0.08
## Alpha at or above which a pixel is the figure rather than the shadow it casts. The soft
## blob a painted subject sits in is wider than the subject and off to one side, and it
## drags a plain alpha-weighted centroid several percent with it.
const STAND_SOLID := 200


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
		var sum_x := 0.0
		var weight := 0.0
		for y in range(h - rows, h):
			var base: int = y * w * 4
			for x in w:
				var a: int = data[base + x * 4 + 3]
				if a >= cut:
					sum_x += float(a) * (float(x) + 0.5)
					weight += float(a)
		if weight > 0.0:
			return sum_x / weight / float(w) - 0.5
	return 0.0


## Where `tex` goes if it stands at the middle of the tile at `centre`, drawn `height` px
## tall on a tile of size `t`, with its own stand point `dx` (from `offset`).
##
## `mirrored` belongs here rather than at the call site because the flip reflects the stand
## point along with everything else: the rect has to be laid out for the mirrored foot and
## then turned inside out, and doing those two steps in the wrong order moves the figure by
## twice its offset instead of leaving it still. A negative WIDTH is what flips a
## `draw_texture_rect`.
##
## Whichever way it faces, the sprite column at `0.5 + dx` lands on `centre.x` — which is
## the invariant `tests/test_art.gd` checks, in those terms.
static func rect(tex: Texture2D, centre: Vector2, t: Vector2, height: float,
		dx: float = 0.0, mirrored: bool = false) -> Rect2:
	var w: float = height * float(tex.get_width()) / float(tex.get_height())
	# feet slightly forward of the tile's exact centre, so the figure stands in the
	# diamond rather than balancing on its back corner
	var foot := centre + Vector2(0, t.y * 0.16)
	var d: float = -dx if mirrored else dx
	var r := Rect2(foot - Vector2(w * (0.5 + d), height), Vector2(w, height))
	if mirrored:
		return Rect2(r.position.x + r.size.x, r.position.y, -r.size.x, r.size.y)
	return r
