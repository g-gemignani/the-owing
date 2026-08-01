## Generates one combat plate per enemy archetype, into `assets/art/enemies/`.
##
## The hook has been there since the painted backdrops landed: `PixelArt.enemy_art(id)`
## is keyed by archetype id, `combat.gd` prefers it over the pixel sprite, and it draws
## an empty footprint box while the file is missing so the frame can be composed before
## anything exists. Nothing was ever put in the directory. This fills it.
##
## ## Why these replace CC0 sprites that are perfectly legal
##
## Licence is not the problem here — Kenney's CC0 is about as clean as it gets. The
## problem is ART.md's opening diagnosis, which a capture of the combat screen shows
## exactly: 35 archetypes and 12 named bosses share **41 unlabelled 16x16 tiles assigned
## by sort order**, and a 16x16 tile scaled to 240px in front of a painted crypt reads
## as a black pixelated cross. A boss is whichever tile the index landed on, and adding
## an archetype reshuffles everyone downstream of it.
##
## ## The silhouette is derived from the fight, not chosen
##
## `Balance.iso_family` already sorts archetypes into swarm / brute / caster **from
## their own data**, with the stated reason that a new archetype then gets a silhouette
## for free and can never be forgotten. This extends that rather than inventing a
## parallel scheme: family picks the body plan, `hp_mult` widens it, `dmg_mult` grows
## the weapon, `block_amount` armours it, `count_max` puts more of them on the plate,
## and the id's hash breaks ties. No table of names anywhere — add
## `resources/enemies/wraith.tres` and it gets a plate shaped by what it does.
##
## Scales are measured from the CATALOGUE's own spread, not from constants picked by
## eye. The first version divided by guessed numbers and every archetype landed between
## 0.00 and 0.34: a derivation that produced no visible difference, which is worse than
## a lookup table because it looks principled.
##
## ## What the first pass got wrong, since it was thrown away for it
##
## Filled silhouettes with no waist and no gap between the legs. A shape that runs from
## shoulder to floor at constant width is a **coffin** whatever you draw on top of it,
## and nineteen brutes came out as coffins with antennae. Two fixes, and they are the
## whole difference: the head is clear of the shoulder line with a neck, and the legs
## are separate shapes with air between them. `ArtShapes.measure` now reports the waist
## ratio so a slab cannot pass unnoticed again.
##
## Run: godot --headless --script tools/gen_enemy_art.gd
## Then: godot --headless --import
extends SceneTree

const OUT := "res://assets/art/enemies/"
## Bigger than the iso markers: this is the arena, where an enemy is drawn at 38% of a
## 720px frame and a boss at 1.34x that. Feet flush with the bottom edge — combat stands
## every enemy on one line (`PixelArt.STAND_LINE`), so padding underneath makes it hover.
const W := 200
const H := 280

# --- driver --------------------------------------------------------------------

## Where a value sits within the catalogue's own range. A stat every archetype shares
## carries no information, so it maps to the middle rather than dividing by zero.
static func _span(v: float, low: float, high: float) -> float:
	if high - low < 0.0001:
		return 0.5
	return clampf((v - low) / (high - low), 0.0, 1.0)

## Which dungeons can field this archetype, by the pool combat itself rolls from.
func _homes(aid: String) -> Array:
	var out: Array = []
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(String(did))
		if dd == null:
			continue
		for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE]:
			if aid in Balance.roster_pool(dd, tier):
				out.append(String(did))
				break
	# bosses are filtered out of every roster pool by design, so fall back to the
	# dungeon that names one, and to everywhere for anything unplaced
	if out.is_empty():
		for did2 in Balance.DUNGEONS:
			var boss := Balance.boss_of(String(did2))
			if boss != null and String(boss.id) == aid:
				out.append(String(did2))
	if out.is_empty():
		out = ArtPalette.all_dungeons()
	out.sort()
	return out

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ids: Array = []
	for p in PixelArt.list_resources("res://resources/enemies/", ".tres"):
		ids.append(String(p).get_file().replace(".tres", ""))
	ids.sort()

	var lo := {}
	var hi := {}
	for aid0 in ids:
		var e0 := Balance.enemy(String(aid0))
		if e0 == null:
			continue
		var stats := {"hp": e0.hp_mult, "dmg": e0.dmg_mult, "block": float(e0.block_amount)}
		for k in stats:
			var v: float = float(stats[k])
			lo[k] = minf(float(lo.get(k, v)), v)
			hi[k] = maxf(float(hi.get(k, v)), v)

	print("=== enemy plates: %d archetypes ===" % ids.size())
	print("catalogue spread: hp %.2f-%.2f  dmg %.2f-%.2f  block %.0f-%.0f" % [
		lo["hp"], hi["hp"], lo["dmg"], hi["dmg"], lo["block"], hi["block"]])
	print("waist = mid-height width / shoulder width; near 1.0 is a slab, not a figure\n")
	print("%-18s %-7s %-5s %-5s %-4s %-6s %s" % [
		"id", "family", "bulk", "blade", "n", "waist", "lit by"])

	var wrote := 0
	var ramps := {}
	var worst := 0.0
	var worst_id := ""
	for aid in ids:
		var e := Balance.enemy(String(aid))
		if e == null:
			continue
		var fam := Balance.iso_family(String(aid))
		var homes := _homes(String(aid))
		var key := ",".join(homes)
		# one ramp per set of homes, cached: most archetypes share a dungeon list, and
		# sampling twelve 1280x720 backdrops per enemy is minutes of work for an answer
		# that is already on the desk
		if not ramps.has(key):
			ramps[key] = ArtPalette.ramp(homes)
		var ramp: Array = ramps[key]

		var bulk := _span(e.hp_mult, lo["hp"], hi["hp"])
		var blade := _span(e.dmg_mult, lo["dmg"], hi["dmg"])
		var plates := _span(float(e.block_amount), lo["block"], hi["block"])
		var jitter: float = float(absi(String(aid).hash()) % 1000) / 1000.0

		var polys: Array = []
		match fam:
			"swarm": polys = ArtShapes.swarm(bulk, blade, e.count_max)
			"caster": polys = ArtShapes.caster(bulk, blade, plates)
			_: polys = ArtShapes.brute(bulk, blade, plates)

		# a hue band per family so kin read as kin, the id's hash placing it inside that
		# band so no two archetypes are the same colour by accident
		var band: float = {"swarm": 0.88, "brute": 0.02, "caster": 0.66}.get(fam, 0.02)
		var hue: float = fposmod(band + (jitter - 0.5) * 0.10, 1.0)
		var sat: float = 0.24 + 0.14 * jitter
		var img := ArtShapes.render(polys, [], W, H, ramp, hue, sat, fam == "caster", 2.5)
		if img.save_png(ProjectSettings.globalize_path(OUT + String(aid) + ".png")) != OK:
			print("   FAILED %s" % aid)
			continue
		wrote += 1
		var m := ArtShapes.measure(img)
		if float(m[2]) > worst:
			worst = float(m[2])
			worst_id = String(aid)
		print("%-18s %-7s %-5.2f %-5.2f %-4d %-6.2f %s" % [
			aid, fam, bulk, blade, e.count_max, m[2],
			homes[0] if homes.size() == 1 else "%d dungeons" % homes.size()])

	print("\n%d plates written to %s" % [wrote, OUT])
	print("widest waist ratio: %s at %.2f  (a coffin measures ~1.00)" % [worst_id, worst])
	print("Run `godot --headless --import` to write the .import sidecars.")
	quit(0)
