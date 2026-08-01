## Generates everything that STANDS on the isometric floor: the hero, the three monster
## families, the wanderers and the four pieces of furniture.
##
## Replaces the downloaded figure packs (D89), which could not be committed — the
## monsters had no licence file at all and the hero's store page says "prototyping,
## **non-commercial** use", which is a hard limit rather than an unknown.
##
## ## The creatures are the same creatures the arena draws
##
## `ArtShapes.brute/caster/swarm` are shared with `tools/gen_enemy_art.gd`, and that is
## a rule rather than a saving. A wanderer crossing a hall IS the fight it will become
## (D85 casts the enemy when the floor is laid out), so the thing you see coming and the
## thing you meet have to be the same creature. Two copies of those tables would drift
## the moment one screen got a tweak.
##
## The furniture is local to this file, because a market stall and a campfire only ever
## appear on a floor.
##
## ## Facing
##
## `_s` faces the camera and carries eyes; `_n` is the same silhouette without them.
## That is the whole difference and it is enough — a shape with eyes is looking at you.
## The eyes are punched OUT of the silhouette rather than drawn on, because a hole reads
## at any size and against any floor where a light mark competes with the rim light.
##
## Run: godot --headless --script tools/gen_iso_markers.gd
## Then: godot --headless --import
extends SceneTree

const OUT := "res://assets/art/iso/"
## Portrait, feet flush with the bottom edge — `iso_run._footed_rect` anchors by
## bottom-centre, so padding under the feet makes everything hover by exactly that much.
## Smaller than the arena plates: these are drawn about two tiles tall.
const W := 128
const H := 176

# --- furniture -----------------------------------------------------------------

## A market stall: a peaked awning over a counter. Chosen over a coin or a purse
## because the silhouette has to work at a glance across a dark floor, and a roofline
## does that where a small round thing does not.
static func _stall() -> Array:
	return [
		[Vector2(0.08, 0.44), Vector2(0.50, 0.14), Vector2(0.92, 0.44),
		 Vector2(0.92, 0.52), Vector2(0.08, 0.52)],
		ArtShapes.taper(0.19, 0.52, 1.0, 0.030, 0.030),
		ArtShapes.taper(0.81, 0.52, 1.0, 0.030, 0.030),
		[Vector2(0.12, 0.70), Vector2(0.88, 0.70), Vector2(0.88, 0.84), Vector2(0.12, 0.84)],
		# goods on the counter, so the shape is not an empty frame
		ArtShapes.ellipse(0.34, 0.655, 0.075, 0.050),
		[Vector2(0.56, 0.70), Vector2(0.70, 0.70), Vector2(0.66, 0.60), Vector2(0.60, 0.60)],
	]

## A fire in a ring of stones. Several tongues, not one — a single triangle is a traffic
## cone, which is exactly what the first attempt produced.
static func _fire() -> Array:
	var out: Array = [ArtShapes.ellipse(0.5, 0.93, 0.34, 0.070)]
	# Wide and overlapping. Drawn narrow they are three spikes on a saucer, which reads
	# as crystals or grass — a flame needs its tongues to merge into one mass low down
	# and separate only near the tips.
	for i in 3:
		var cx: float = 0.34 + 0.16 * float(i)
		var top: float = 0.32 + 0.15 * absf(float(i) - 1.0)
		out.append([Vector2(cx - 0.145, 0.93), Vector2(cx - 0.055, top + 0.14),
			Vector2(cx - 0.010, top), Vector2(cx + 0.055, top + 0.17),
			Vector2(cx + 0.145, 0.93)])
	# logs crossing under it, which is what says "somebody made this"
	out.append(ArtShapes.taper(0.5, 0.86, 0.965, 0.20, 0.055, -0.10))
	out.append(ArtShapes.taper(0.5, 0.86, 0.965, 0.20, 0.055, 0.10))
	return out

## A standing rune stone: a leaning slab with a broken top and a notch out of one side,
## because a plain rectangle reads as a door and not as a monument. An event is the one
## node that is not a thing you use, so it is the one shape here that is architecture.
static func _rune() -> Array:
	return [
		[Vector2(0.30, 0.22), Vector2(0.46, 0.10), Vector2(0.58, 0.16),
		 Vector2(0.70, 0.11), Vector2(0.76, 1.0), Vector2(0.24, 1.0)],
		# a smaller stone leaning against it, for the same reason
		[Vector2(0.14, 0.62), Vector2(0.28, 0.54), Vector2(0.34, 1.0), Vector2(0.10, 1.0)],
	]

## A chest: body, domed lid, lock plate and feet. The dome and the feet are what stop it
## reading as a plain box, which is all the first attempt managed.
static func _chest() -> Array:
	return [
		[Vector2(0.16, 0.52), Vector2(0.84, 0.52), Vector2(0.86, 0.94), Vector2(0.14, 0.94)],
		[Vector2(0.14, 0.53), Vector2(0.20, 0.34), Vector2(0.34, 0.26),
		 Vector2(0.66, 0.26), Vector2(0.80, 0.34), Vector2(0.86, 0.53)],   # domed lid
		[Vector2(0.43, 0.46), Vector2(0.57, 0.46), Vector2(0.57, 0.66), Vector2(0.43, 0.66)],
		[Vector2(0.14, 0.94), Vector2(0.26, 0.94), Vector2(0.26, 1.0), Vector2(0.14, 1.0)],
		[Vector2(0.74, 0.94), Vector2(0.86, 0.94), Vector2(0.86, 1.0), Vector2(0.74, 1.0)],
	]

## Everything the floor draws. `hue` keeps a figure from dissolving into the ground it
## stands on; `glow` marks what is meant to be a light source rather than lit by one.
const CAST := {
	"hero":       {"plan": "hero",   "hue": 0.085, "sat": 0.40, "glow": false},
	"mon_swarm":  {"plan": "swarm",  "hue": 0.90,  "sat": 0.30, "glow": false},
	"mon_brute":  {"plan": "brute",  "hue": 0.02,  "sat": 0.28, "glow": false},
	"mon_caster": {"plan": "caster", "hue": 0.68,  "sat": 0.32, "glow": true},
	"shop":       {"plan": "stall",  "hue": 0.10,  "sat": 0.34, "glow": false},
	"rest":       {"plan": "fire",   "hue": 0.06,  "sat": 0.52, "glow": true},
	"event":      {"plan": "rune",   "hue": 0.58,  "sat": 0.18, "glow": false},
	"treasure":   {"plan": "chest",  "hue": 0.11,  "sat": 0.38, "glow": false},
	# tier fallbacks, for a tile whose enemy was never cast (a save from before D85) —
	# the brute plan, because an unknown fight should look like a fight
	"combat":     {"plan": "brute",  "hue": 0.02,  "sat": 0.24, "glow": false},
	"elite":      {"plan": "brute",  "hue": 0.97,  "sat": 0.34, "glow": false},
	"boss":       {"plan": "brute",  "hue": 0.90,  "sat": 0.42, "glow": false},
}

## The hero is drawn on the caster's plan — a person in a travelling cloak — at full
## bulk and with no staff, which is what `blade = 0` removes. She is told apart from a
## caster by hue and by being the only warm figure on the floor, not by anatomy.
static func _plan(name: String) -> Array:
	match name:
		"hero": return ArtShapes.caster(1.0, 0.0, 0.0)
		"caster": return ArtShapes.caster(0.5, 0.6, 0.5)
		"brute": return ArtShapes.brute(0.6, 0.6, 0.5)
		"swarm": return ArtShapes.swarm(0.5, 0.5, 3)
		"stall": return _stall()
		"fire": return _fire()
		"rune": return _rune()
		"chest": return _chest()
	return ArtShapes.brute(0.6, 0.6, 0.5)

## Where the eyes go on each plan, as a fraction of canvas height.
const EYE_Y := {"hero": 0.105, "caster": 0.105, "brute": 0.115, "swarm": 0.50}

static func _render(entry: Dictionary, ramp: Array, south: bool) -> Image:
	var plan := String(entry["plan"])
	var holes: Array = []
	if south and EYE_Y.has(plan):
		var ey: float = float(EYE_Y[plan])
		holes = [ArtShapes.ellipse(0.455, ey, 0.019, 0.015, 12),
			ArtShapes.ellipse(0.545, ey, 0.019, 0.015, 12)]
	return ArtShapes.render(_plan(plan), holes, W, H, ramp,
		float(entry["hue"]), float(entry["sat"]), bool(entry["glow"]), 2.0)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# One ramp for every marker, from ALL the painted dungeons rather than one terrain:
	# the same hero and the same brute stand on all four floors, so a figure tuned to the
	# Warrens would be wrong in the Sunken Vault.
	var ramp := ArtPalette.ramp(ArtPalette.all_dungeons())
	print("=== iso markers (%d dungeons sampled) ===" % ArtPalette.all_dungeons().size())
	print("%-16s %-6s %-6s %s" % ["file", "cover", "foot", "waist"])

	var wrote := 0
	for role in CAST:
		var r := String(role)
		var entry: Dictionary = CAST[role]
		if r.begins_with("mon_") or r == "hero":
			wrote += _save(_render(entry, ramp, true), "%s_s" % r)
			wrote += _save(_render(entry, ramp, false), "%s_n" % r)
		else:
			wrote += _save(_render(entry, ramp, true), r)

	# Four wanderer designs: the three families plus a second brute, so three things
	# prowling one floor do not read as one monster cloned. Deliberately the SAME shapes
	# the cast monsters use — a wanderer is a fight that moves.
	var designs := ["mon_swarm", "mon_brute", "mon_caster", "mon_brute"]
	for i in designs.size():
		var entry2: Dictionary = CAST[designs[i]].duplicate()
		entry2["hue"] = fposmod(float(entry2["hue"]) + 0.07 * float(i), 1.0)
		wrote += _save(_render(entry2, ramp, true), "wander_%d_s" % i)
		wrote += _save(_render(entry2, ramp, false), "wander_%d_n" % i)

	print("\n%d files written to %s" % [wrote, OUT])
	print("Run `godot --headless --import` to write the .import sidecars.")
	quit(0)

func _save(img: Image, name: String) -> int:
	if img.save_png(ProjectSettings.globalize_path(OUT + name + ".png")) != OK:
		print("   FAILED %s" % name)
		return 0
	var m := ArtShapes.measure(img)
	print("%-16s %5.1f%% %5d  %.2f" % [name + ".png", m[0], m[1], m[2]])
	return 1
