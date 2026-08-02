## Combat feedback, drawn rather than photographed.
##
## `tools/art_manifest.gd` asks for six sprite sheets in `assets/art/fx/` — eight frames
## of 256x256 each for slash, impact, block_up, poison_cloud, heal and death_dissolve —
## and none of them has ever existed. They are not made here either, on purpose. The
## generator this project drives is a text-to-image model and the constraint that makes
## its output coherent is a style REFERENCE (D90, D100); a reference can hold the hand
## steady across separate pictures and cannot hold a motion together across eight of
## them. What comes back from "8 frames of one slash" is eight slashes. That is the same
## judgement ART_PROMPTS.md already makes about nine-slices: **animations are not
## stills**, and the answer for a computed asset is to compute it (D83).
##
## What a sheet would also have cost is the palette. Everything below takes its VALUE
## from `ArtPalette`, which is sampled from the twelve painted backdrops, so a cut in the
## Crypt is lit like the Crypt and a repaint moves every effect in the game with it —
## the same contract the isometric materials and the enemy plates already run on (D89).
##
## The shape of the file is one drawn node and one particle constructor:
##
## * **`Mark`** — a Control that draws ONE inked primitive (a cut, a shock ring, a ward
##   facet) into whatever box it is given, at whatever progress it is tweened to.
## * **`_particles`** — a configured `CPUParticles2D` that reaps itself; each effect
##   tunes it and calls `_launch`.
##
## Six public functions pose those two. CPU particles rather than GPU: the counts here
## are 10-25 and a headless run has no GPU to ask.
##
## **Nothing here may be load-bearing.** Every entry point is a no-op without a layer
## inside a tree, nothing it spawns is ever read back, and no game state waits on a
## tween — `CombatEngine` has resolved completely before the first of these is called,
## which is what lets `tools/sim_balance.gd` play thousands of fights that never build
## a scene.
class_name Fx
extends RefCounted

## The two pictures a landing hit can leave. Two and not seven: at 0.15s the player can
## tell a cut from a bludgeoning and cannot tell six kinds of cut apart, which is the
## same reasoning that gives the three attack INTENTS one blade between them
## (`Combat.INTENT_ICONS`).
const SLASH := "slash"
const IMPACT := "impact"

# --- how long anything lasts ---------------------------------------------------
#
# All short, for the reason `combat.gd`'s feedback block already states: a card game is
# read, and an animation you have to wait through is worse than none. The two long ones
# are the two that are not in the player's way — a cloud settling and a body coming
# apart both happen while the next card is being chosen.
const T_SLASH := 0.17
const T_IMPACT := 0.28
const T_WARD := 0.34
const T_CLOUD := 0.95
const T_HEAL := 0.85
const T_DEATH := 0.55

## Where each effect sits on the room's five-stop ramp, and what hue it carries there.
##
## Split for `ArtShapes.tinted`'s reason, one medium over: the VALUE is what makes an
## effect belong to the room it is drawn in, and the HUE is what keeps it saying which
## effect it is. A poison cloud that took the Crypt's blue would be a blue cloud.
##
## Steel and dust take no hue of their own at all — they are the ramp itself, because a
## cut is a highlight and dust is the floor of the room in the air. Dust sits above the
## ramp's middle rather than on it: it is the ground CATCHING the light, and taken at the
## value of the ground itself the puff measured invisible against a painted corridor.
const STEEL_V := 0.94
const DUST_V := 0.62
## The blue `_float_number` already prints "+N block" in, and the cool end of the same
## reading the HP bar's Block band uses.
const WARD_HUE := 0.58
const WARD_SAT := 0.45
## Yellow-green, deliberately off the 0.33 the heal number is printed in: the two are
## the effects most likely to be on screen together, on the same creature.
const VENOM_HUE := 0.25
const VENOM_SAT := 0.62
## `Combat.CHIP_GOOD`'s amber — "you did this" — which is also what the energy bloom
## and the target ring are tinted with. A heal is warm; the brief for the missing sheet
## said so and the corner already agrees.
const EMBER_HUE := 0.09
const EMBER_SAT := 0.55

## The side of the soft dot every particle is a copy of, in texture pixels. Mote sizes
## below are fractions of the BOX the effect is drawn in, so a boss's dust is a boss's
## dust; this is only what converts one into the scale factor CPUParticles2D wants.
const DOT_PX := 32.0

# --- the palette ---------------------------------------------------------------

## Ramps already sampled, by dungeon id. `ArtPalette.ramp` reads the backdrop PNG and
## walks its floor band — 45ms for one dungeon, measured — which is nothing once and a
## visible hitch if it happens on the first hit of a fight. Combat asks for it while the
## scene is loading and it is paid once per dungeon per session.
static var _ramps: Dictionary = {}

## The room's own ramp, dark to light. Falls back to `ArtPalette`'s neutral when the
## dungeon has no painting, which is the same one-file-at-a-time contract the rest of
## the art runs on: no backdrop means grey effects, never no effects.
static func palette(dungeon_id: String) -> Array:
	if not _ramps.has(dungeon_id):
		_ramps[dungeon_id] = ArtPalette.ramp([dungeon_id])
	return _ramps[dungeon_id]

# --- the six -------------------------------------------------------------------

## A weapon arc across the target: a bowed cut, revealed head-first and trimmed from
## behind, so what the eye sees is a stroke travelling rather than a shape appearing.
static func slash(layer: Control, rect: Rect2, ramp: Array, force: float = 1.0) -> void:
	if not _ok(layer, rect):
		return
	var m := _mark(layer, rect, Mark.Kind.CUT)
	m.core = ArtPalette.shade(ramp, STEEL_V)
	m.edge = ArtPalette.ink(ramp)
	m.weight = clampf(force, 0.5, 1.6)
	m.flip = randf() < 0.5
	# One tween on `t`; the trim inside `Mark` is what makes the tail catch up with the
	# head exactly at 1.0, so the stroke leaves a clean frame rather than being faded out.
	var tw := m.create_tween()
	tw.tween_property(m, "t", 1.0, T_SLASH)
	tw.tween_callback(m.queue_free)

## A blunt hit: a shock ring thrown out of the point of contact, and the dust it knocks
## off. `force` is how hard, 0..1-ish, and it scales the ring and the count — a 4-point
## chip must not look like a boss landing 40, which is the rule `_flash_hurt` already
## follows for the screen tint.
static func impact(layer: Control, rect: Rect2, ramp: Array, force: float = 1.0) -> void:
	if not _ok(layer, rect):
		return
	var f := clampf(force, 0.35, 1.0)
	var m := _mark(layer, rect, Mark.Kind.SHOCK)
	m.core = ArtPalette.shade(ramp, STEEL_V)
	m.edge = ArtPalette.ink(ramp)
	m.weight = 0.65 + 0.5 * f
	var tw := m.create_tween()
	tw.tween_property(m, "t", 1.0, T_IMPACT)
	tw.tween_callback(m.queue_free)

	# Dust off the lower body, where a struck thing meets the ground: the room's own
	# floor in the air (see DUST_V), not a grey this file picked. The first pass put 4px
	# motes at the value of the ground and the puff was invisible against a painted
	# corridor — size, value and count all moved.
	var side: float = minf(rect.size.x, rect.size.y)
	var p := _particles(layer, Vector2(rect.get_center().x,
		rect.position.y + rect.size.y * 0.74), int(round(12.0 + 12.0 * f)), 0.45)
	p.emission_sphere_radius = side * 0.16
	p.direction = Vector2(0, -1)
	p.spread = 76.0
	p.initial_velocity_min = rect.size.y * 0.45 * f
	p.initial_velocity_max = rect.size.y * 1.25 * f
	p.gravity = Vector2(0, rect.size.y * 2.4)
	p.damping_min = 0.8
	p.damping_max = 2.2
	_sized(p, side, 0.035, 0.085)
	p.color_ramp = _fade(Color(ArtPalette.shade(ramp, DUST_V), 0.9), 0.0, 0.35)
	_launch(p)

## A ward snapping into place: a hexagonal facet that arrives oversized and settles onto
## the body it is guarding. The snap is a scale tween with an overshoot rather than
## anything drawn — "snapping" is a curve, not a picture.
static func block_up(layer: Control, rect: Rect2, ramp: Array) -> void:
	if not _ok(layer, rect):
		return
	var m := _mark(layer, rect, Mark.Kind.WARD)
	m.core = ArtShapes.tinted(ramp, WARD_HUE, WARD_SAT, 0.88)
	m.edge = ArtShapes.tinted(ramp, WARD_HUE, WARD_SAT * 0.7, 0.34)
	m.scale = Vector2(1.35, 1.35)
	m.modulate.a = 0.0
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector2.ONE, T_WARD) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "modulate:a", 1.0, T_WARD * 0.25)
	tw.tween_property(m, "modulate:a", 0.0, T_WARD * 0.55).set_delay(T_WARD * 0.45)
	tw.chain().tween_callback(m.queue_free)

## Green miasma settling: slow, wide motes that drift up out of the body and then sink,
## which is what the gravity here is for — a cloud that only rises is smoke.
static func poison_cloud(layer: Control, rect: Rect2, ramp: Array) -> void:
	if not _ok(layer, rect):
		return
	var side: float = minf(rect.size.x, rect.size.y)
	var p := _particles(layer, rect.get_center(), 20, T_CLOUD)
	p.explosiveness = 0.55       # it seeps rather than bursts
	p.emission_sphere_radius = side * 0.32
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = rect.size.y * 0.10
	p.initial_velocity_max = rect.size.y * 0.30
	p.gravity = Vector2(0, rect.size.y * 0.30)
	p.damping_min = 0.6
	p.damping_max = 1.4
	_sized(p, side, 0.16, 0.34)
	# Faded in, held, then out: a cloud that appears at full strength is a flash, and one
	# that starts leaving the instant it arrives is a haze. And it stops short of opaque —
	# at 0.9 it held the creature's outline hostage for a second, which is the second the
	# player is reading the creature.
	p.color_ramp = _fade(Color(ArtShapes.tinted(ramp, VENOM_HUE, VENOM_SAT, 0.62), 0.78),
		0.12, 0.55)
	_launch(p)

## Warm motes rising. Narrow spread and NEGATIVE gravity: they accelerate away rather
## than arcing over, which is the whole difference between rising and being thrown.
static func heal(layer: Control, rect: Rect2, ramp: Array) -> void:
	if not _ok(layer, rect):
		return
	var side: float = minf(rect.size.x, rect.size.y)
	var p := _particles(layer, Vector2(rect.get_center().x,
		rect.position.y + rect.size.y * 0.66), 16, T_HEAL)
	p.explosiveness = 0.55
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(rect.size.x * 0.30, rect.size.y * 0.16)
	p.direction = Vector2(0, -1)
	p.spread = 14.0
	p.initial_velocity_min = rect.size.y * 0.30
	p.initial_velocity_max = rect.size.y * 0.65
	p.gravity = Vector2(0, -rect.size.y * 0.35)
	_sized(p, side, 0.035, 0.075)
	# The one additive effect here, for `_flash_orb`'s reason: a mote is LIGHT, and
	# alpha-blended warm over a lit corridor is a smudge where additive is a spark. It
	# also cannot dim anything it crosses, which matters for the only effect that fires
	# while the player is reading their own HP.
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	p.color_ramp = _fade(Color(ArtShapes.tinted(ramp, EMBER_HUE, EMBER_SAT, 0.90), 0.95),
		0.0, 0.45)
	_launch(p)

## An enemy coming apart, on the kill.
##
## Two halves, and the first is why this one takes the plate's texture: the body is
## dissolved by a shader that discards its own pixels in coarse flakes, top down, with
## the flakes about to go charring to ember first. Fading it out instead is what every
## other death in a card game looks like, and it reads as the sprite being switched off.
## The second half is the shards it sheds, which fall — the only effect here with real
## gravity on it, because it is the only one where something has stopped holding itself
## up.
##
## `tex` may be null (no art at all), and `tint` is whatever the plate was drawing it
## with — a stand-in silhouette is a bright 16x16 sprite held at 0.16, and a ghost that
## dropped that would come apart in the wrong colour. With no texture the shards still
## run: a kill must never be silent.
static func death_dissolve(layer: Control, rect: Rect2, ramp: Array,
		tex: Texture2D = null, tint: Color = Color(1, 1, 1)) -> void:
	if not _ok(layer, rect):
		return
	var ember := ArtShapes.tinted(ramp, EMBER_HUE, EMBER_SAT, 0.85)
	if tex != null:
		var ghost := TextureRect.new()
		ghost.texture = tex
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.modulate = tint
		var mat := ShaderMaterial.new()
		mat.shader = _dissolve_shader()
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("ember", ember)
		ghost.material = mat
		layer.add_child(ghost)
		ghost.position = rect.position - layer.global_position
		ghost.size = rect.size
		var tw := ghost.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mat, "shader_parameter/progress", 1.0, T_DEATH)
		# a small sag, so the body loses its footing before it loses its outline
		tw.tween_property(ghost, "position:y", ghost.position.y + rect.size.y * 0.04,
			T_DEATH)
		# Belt and braces: if the shader ever fails to compile the ghost must still
		# leave, and a fade is a worse death than a dissolve but an infinitely better
		# one than a corpse standing on the floor for the rest of the fight.
		tw.tween_property(ghost, "modulate:a", 0.0, T_DEATH * 0.4).set_delay(T_DEATH * 0.6)
		tw.chain().tween_callback(ghost.queue_free)

	var side: float = minf(rect.size.x, rect.size.y)
	var p := _particles(layer, rect.get_center(), 26, T_DEATH * 1.25)
	p.explosiveness = 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = rect.size * 0.34
	p.direction = Vector2(0, -1)
	p.spread = 100.0
	p.initial_velocity_min = rect.size.y * 0.15
	p.initial_velocity_max = rect.size.y * 0.75
	p.gravity = Vector2(0, rect.size.y * 1.9)
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	_sized(p, side, 0.040, 0.095)
	var g := Gradient.new()
	g.set_color(0, Color(ember, 0.95))
	g.add_point(0.35, Color(ArtPalette.ink(ramp), 0.85))
	g.set_color(g.get_point_count() - 1, Color(ArtPalette.ink(ramp), 0.0))
	p.color_ramp = g
	_launch(p)

# --- the drawn primitive -------------------------------------------------------

## One inked shape, posed by whatever spawned it. Three kinds, one `_draw`, because they
## are three uses of the same two operations — a filled polygon under a stroked outline
## — and three Controls with three scripts would be three places to keep the ink
## consistent.
##
## `t` is progress, 0..1, and setting it redraws. WARD does not read it: its whole
## motion is the scale tween, so it draws once and costs nothing per frame.
class Mark:
	extends Control
	enum Kind {CUT, SHOCK, WARD}

	var kind: int = Kind.CUT
	var core: Color = Color(1, 1, 1)
	var edge: Color = Color(0, 0, 0)
	## Heavier hit, bigger mark. Applied to width and radius, never to duration: a slow
	## effect is a slow game, however hard the hit was.
	var weight: float = 1.0
	var flip: bool = false
	var t: float = 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		match kind:
			Kind.CUT: _draw_cut()
			Kind.SHOCK: _draw_shock()
			Kind.WARD: _draw_ward()

	## A bowed chord across the box. The head runs ahead of `t` and the tail chases it,
	## so the stroke is longest in the middle of its life and gone at the end of it.
	func _draw_cut() -> void:
		var head := clampf(t * 1.35, 0.0, 1.0)
		var tail := clampf(t * 1.9 - 0.9, 0.0, 1.0)
		if head - tail <= 0.02:
			return
		var a := Vector2(-0.10, 0.86) * size
		var b := Vector2(1.10, 0.14) * size
		if flip:
			a.x = size.x - a.x
			b.x = size.x - b.x
		# the bow is perpendicular to the chord, so mirroring the ends mirrors the curve
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * size.y * 0.26
		var thick: float = maxf(2.0, size.x * 0.05) * weight
		# The ink goes down first and wider, then the bright core over it. That order is
		# the whole of ART.md's "painted, INKED illustration" at this scale.
		draw_colored_polygon(_stroke(a, mid, b, tail, head, thick * 1.9),
			Color(edge, 0.55))
		draw_colored_polygon(_stroke(a, mid, b, tail, head, thick), core)

	## The outline of a tapered stroke along a quadratic curve, as one closed polygon:
	## the two rails, the second reversed.
	func _stroke(a: Vector2, m: Vector2, b: Vector2, tail: float, head: float,
			thick: float) -> PackedVector2Array:
		var n := 16
		var fwd := PackedVector2Array()
		var back := PackedVector2Array()
		for i in n:
			var f := float(i) / float(n - 1)
			var u := lerpf(tail, head, f)
			var p := _bezier(a, m, b, u)
			var d := (_bezier(a, m, b, minf(1.0, u + 0.02))
				- _bezier(a, m, b, maxf(0.0, u - 0.02))).normalized()
			# tapered to nothing at both ends, and heavier at the leading edge — a cut
			# is thickest where the blade is, not in the middle of where it has been
			var hw := thick * sin(PI * f) * (0.45 + 0.55 * u)
			fwd.append(p + d.orthogonal() * hw)
			back.append(p - d.orthogonal() * hw)
		back.reverse()
		fwd.append_array(back)
		return fwd

	func _bezier(a: Vector2, m: Vector2, b: Vector2, u: float) -> Vector2:
		return a.lerp(m, u).lerp(m.lerp(b, u), u)

	## An expanding ellipse, thinning as it goes: the shock leaving the point of
	## contact. Squashed, because the ring is spreading across a body seen head-on and
	## a perfect circle reads as a bubble in front of it.
	func _draw_shock() -> void:
		var e := ease(t, 0.35)               # fast out of the gate, then coasting
		var c := size * 0.5
		# The SMALLER side, not the width. The player has no figure on this screen, so
		# their own hits land on the HP bar — a 256x44 box, where a radius taken off the
		# width draws a ring three times taller than the thing it is about.
		var span: float = minf(size.x, size.y)
		var rx: float = lerpf(span * 0.14, span * 0.58 * weight, e)
		var w: float = maxf(1.5, lerpf(span * 0.055, span * 0.010, e))
		# Alpha on `t`, radius on the EASED t: the ring must be at full strength while it
		# is small and travelling, which is when the hit reads. Fading on `e` took it to
		# a third of its ink within one frame of landing.
		var a := 0.85 * (1.0 - t * t)
		draw_polyline(_ring(c, rx, rx * 0.76), Color(core, a), w, true)
		# a second, slower ring so the shock has depth rather than being one hoop
		draw_polyline(_ring(c, rx * 0.58, rx * 0.44), Color(edge, a * 0.7), w * 0.7, true)

	## A hexagonal facet with a faint fill: a plate of something interposed, not an
	## outline drawn on the air. Two rings of it, the inner one inked, for the same
	## reason the cut has a rail under it.
	func _draw_ward() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.46
		var outer := _hex(c, r * 0.92, r * 1.06)
		draw_colored_polygon(outer, Color(core, 0.13))
		draw_polyline(_closed(outer), core, maxf(2.0, r * 0.055), true)
		draw_polyline(_closed(_hex(c, r * 0.62, r * 0.72)), Color(edge, 0.8),
			maxf(1.0, r * 0.03), true)

	func _hex(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in 6:
			var ang: float = -PI * 0.5 + TAU * float(i) / 6.0
			out.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
		return out

	func _ring(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in 25:
			var ang: float = TAU * float(i) / 24.0
			out.append(c + Vector2(cos(ang) * rx, sin(ang) * ry))
		return out

	func _closed(pts: PackedVector2Array) -> PackedVector2Array:
		var out := pts.duplicate()
		out.append(pts[0])
		return out

# --- the plumbing --------------------------------------------------------------

## A layer worth drawing on, and a box worth drawing in. The second half is not
## paranoia: a Control has no rect until the frame after it is laid out, and combat's
## first refresh runs before that (see `_on_bar_resized`).
static func _ok(layer: Control, rect: Rect2) -> bool:
	if layer == null or not is_instance_valid(layer) or not layer.is_inside_tree():
		return false
	return rect.size.x >= 4.0 and rect.size.y >= 4.0

## A `Mark` placed over `rect` and pivoting about its middle, so a scale tween grows it
## from the centre of the thing it is about.
static func _mark(layer: Control, rect: Rect2, kind: int) -> Mark:
	var m := Mark.new()
	m.kind = kind
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(m)
	m.position = rect.position - layer.global_position
	m.size = rect.size
	m.pivot_offset = rect.size * 0.5
	return m

## The common half of every burst: a one-shot emitter at a point, in global space so its
## motes are not dragged around by anything, already parented. The caller tunes it and
## calls `_launch`; nothing emits until then, because CPUParticles2D reads most of these
## once at the moment a particle is born.
static func _particles(layer: Control, at: Vector2, count: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot()
	# The project forces NEAREST project-wide, and every mote here is an UPSCALE of a
	# 32px dot — unfiltered, a soft puff of dust arrives as a staircase of squares. Same
	# correction the painted enemies, the chips and the reticle all make.
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(1, count)
	p.lifetime = maxf(0.05, life)
	p.explosiveness = 0.9
	p.randomness = 0.5
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	layer.add_child(p)
	p.position = at - layer.global_position
	return p

## Fire, and free once the last mote is dead. The tween belongs to the emitter, so
## nothing outlives the screen it was drawn on.
static func _launch(p: CPUParticles2D) -> void:
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime * 1.6 + 0.1)
	tw.tween_callback(p.queue_free)

## Mote diameter as a fraction of the box the effect is drawn in, converted into the
## texture scale CPUParticles2D actually wants. Written this way round so the numbers at
## the call sites are readable — 0.04 is "a twenty-fifth of the creature" — and so a
## boss's dust is a boss's dust.
##
## The floor is not decoration. The player has no figure on this screen, so their own
## effects are drawn on the HP bar, whose short side is a third of a creature's — and a
## fraction that reads on a boss is three pixels there. A mote under about five pixels is
## a mote nobody sees.
const MOTE_MIN := 5.0
const MOTE_MIN_MAX := 11.0

static func _sized(p: CPUParticles2D, side: float, lo: float, hi: float) -> void:
	p.scale_amount_min = maxf(side * lo, MOTE_MIN) / DOT_PX
	p.scale_amount_max = maxf(side * hi, MOTE_MIN_MAX) / DOT_PX

## A colour that fades out, and optionally in and then holds. `fade_in` is where along
## the life the mote reaches full strength (0 = born there) and `hold` is where it starts
## leaving again.
##
## The hold is what a cloud needs and a spark does not. Without it every mote is at full
## strength for one instant of its life and translucent for the rest, which measured as a
## green HAZE over a poisoned creature rather than as anything settling on it.
static func _fade(c: Color, fade_in: float = 0.0, hold: float = 0.0) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c, 0.0) if fade_in > 0.0 else c)
	if fade_in > 0.0:
		g.add_point(fade_in, c)
	if hold > fade_in:
		g.add_point(hold, c)
	g.set_color(g.get_point_count() - 1, Color(c, 0.0))
	return g

## The one texture every particle in the game is a copy of: a soft round dot, built
## once. Procedural for the file's whole reason — a 16px blurred circle is not a
## painting, it is a footnote to one, and shipping a PNG for it would put a file on the
## art manifest that nobody could ever judge.
static var _dot_tex: Texture2D = null

static func _dot() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var n := int(DOT_PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := (Vector2(float(x) + 0.5, float(y) + 0.5) - Vector2(n, n) * 0.5).length() \
				/ (float(n) * 0.5)
			# A solid core with a soft edge, NOT a gradient to the middle. Squaring the
			# falloff put every mote's opacity in its last few pixels, and twenty of them
			# over a creature came out as a tint rather than as a cloud.
			var a := smoothstep(0.0, 0.55, 1.0 - d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

## The dissolve, as a shader rather than as frames — which is this whole file's argument
## in its smallest form. The threshold is per CELL, not per pixel, so what comes off is
## flakes; it is tilted by `UV.y` so the top goes first and the feet last; and the band
## of cells about to go is pushed toward ember, so the body chars along the edge that is
## eating it instead of simply having holes.
static var _shader: Shader = null

static func _dissolve_shader() -> Shader:
	if _shader != null:
		return _shader
	_shader = Shader.new()
	_shader.code = """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ember : source_color = vec4(1.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.02) { discard; }
	// Two noises, not one. On the cell grid alone the body comes apart into tidy
	// squares, which reads as a rendering fault rather than as a death; the fine term
	// is what ragged their edges.
	float cell = fract(sin(dot(floor(UV * 38.0), vec2(41.31, 289.17))) * 43758.5453);
	float fine = fract(sin(dot(floor(UV * 240.0), vec2(77.07, 131.53))) * 24634.6345);
	float n = cell * 0.78 + fine * 0.22;
	float k = progress * 1.45 - 0.35 * UV.y;
	if (n < k) { discard; }
	c.rgb = mix(c.rgb, ember.rgb, (1.0 - smoothstep(k, k + 0.14, n)) * 0.75);
	COLOR = c;
}
"""
	return _shader
