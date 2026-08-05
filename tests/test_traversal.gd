## Headless test: the Traversal contract, applied to every model there is.
##
## The file stayed model-agnostic on purpose after D94 deleted three of the four
## models: the loop below runs over MODELS, and a second traversal rejoins this suite
## by being added to that array rather than by anyone writing a second walker.
## Anything a model must guarantee for combat/meta/balance to keep working is here.
## Run: godot --headless --script tests/test_traversal.gd
extends SceneTree

## Every traversal model in the game. Add a name here and a branch to `_make` and the
## whole contract below runs against it — that is the only wiring a second model needs.
const MODELS := ["ISO"]

## Most of a floor's walkable ground that may be lit before the light field has stopped
## being an axis and become a brighter flat rule (D176). Not a design target — a ceiling on
## a mistake that has already been made once: the first tuning lit 91%.
const LIT_MAX := 0.75

func _make(name: String) -> Traversal:
	match name:
		_: return TraversalIso.new()

## Encounters one run of `did` should cost. The mix is per-dungeon, and every MODEL
## has to spend the same one — that is the contract this test exists for, and it is
## what lets a difficulty rating mean one thing across dungeons and across any way of
## walking them that gets built.
func budget(did: String = "") -> int:
	var dd := Balance.dungeon(did) if did != "" else null
	if dd == null:
		return Balance.ENCOUNTER_COMBATS + Balance.ENCOUNTER_ELITES \
			+ Balance.ENCOUNTER_RESTS + Balance.ENCOUNTER_SHOPS \
			+ Balance.ENCOUNTER_EVENTS + Balance.ENCOUNTER_TREASURES + 1
	var m := dd.encounter_mix()
	var n := 1   # the boss
	for k in m:
		n += int(m[k])
	return n

func _init() -> void:
	var fails := 0

	for model in MODELS:
		var label: String = model
		var enc_total := 0
		var enc_runs := 0
		var budget_total := 0
		for dungeon_id in Balance.DUNGEONS:
			var dd := Balance.dungeon(dungeon_id)
			for trial in 30:
				var tv := _make(label)
				if tv == null:
					fails += 1; print("FAIL %s: no instance built" % label); break
				tv.generate(dd)

				# a fresh run must not already be finished, and must offer choices
				if tv.is_complete():
					fails += 1; print("FAIL %s: complete immediately after generate" % label); break
				if tv.options().is_empty():
					fails += 1; print("FAIL %s: no options at start" % label); break

				# walk it to completion with an always-face policy
				var steps := 0
				var encounters := 0
				var bosses := 0
				var last_was_boss := false
				# An iso dungeon is several floors of rooms now (D79), so a full walk is
				# tens of steps rather than a dozen — this cap is a runaway guard, not a
				# budget. What actually bounds the walking is the moves-per-encounter
				# assertion further down.
				while not tv.is_complete() and steps < 400:
					steps += 1
					var opts := tv.options()
					if opts.is_empty():
						fails += 1
						print("FAIL %s: ran out of options before completing" % label)
						break
					# always pick a "face it" style option so the run progresses
					var pick := 0
					for i in opts.size():
						if not opts[i].has("hp_cost"):
							pick = i
							break
					var node := tv.select(pick)
					if node.is_empty():
						continue  # resolved internally
					if not node.has("type"):
						fails += 1; print("FAIL %s: encounter has no type" % label); break
					var t := int(node["type"])
					if t < 0 or t > Traversal.Enc.TREASURE:
						fails += 1; print("FAIL %s: bad encounter type %d" % [label, t]); break
					encounters += 1
					last_was_boss = t == Traversal.Enc.BOSS
					if last_was_boss:
						bosses += 1
					tv.clear_pending()
					var p := tv.progress()
					if p < 0.0 or p > 1.001:
						fails += 1; print("FAIL %s: progress out of range %.2f" % [label, p]); break

				if not tv.is_complete():
					fails += 1; print("FAIL %s: did not terminate in %d steps" % [label, steps]); break
				if bosses != 1:
					fails += 1; print("FAIL %s: %d bosses in a run (expect 1)" % [label, bosses]); break
				if not last_was_boss:
					fails += 1; print("FAIL %s: run did not END on the boss" % label); break

				# Budget is checked as an AVERAGE below, not per run: a model with
				# stochastic movement (dice) has real variance by design, and the
				# contract is about expected cost, not determinism. A loose per-run
				# bound still catches runaway generation.
				enc_total += encounters
				enc_runs += 1
				budget_total += budget(dungeon_id)
				if encounters > budget(dungeon_id) * 3:
					fails += 1
					print("FAIL %s: runaway run of %d encounters" % [label, encounters])
					break

		# Average encounters per run must match what the dungeons asked for. Compared
		# against the mean of the PER-DUNGEON budgets now that the mix varies by
		# place — the contract was never "every run is nine encounters", it is "a
		# model costs what the dungeon asked for, whichever model it is".
		if enc_runs > 0:
			var avg := float(enc_total) / float(enc_runs)
			var want := float(budget_total) / float(enc_runs)
			if abs(avg - want) > 2.0:
				fails += 1
				print("FAIL %s: averages %.1f encounters, dungeons asked for %.1f (a model must cost what was asked)" % [
					label, avg, want])
			else:
				print("  (info: %s averages %.1f encounters, asked for %.1f)" % [label, avg, want])

	# --- iso specifics ---
	#
	# The floor's budget can leak GEOMETRICALLY — an encounter that finds no tile to
	# stand on makes a dungeon quietly cheaper than its difficulty says, and nothing
	# above would notice, because every assertion up there is about the walk and not
	# the building it was cut from. Since D79 there is a
	# second way to fail that no encounter count can see: a dungeon can be correct and
	# still bury the card game in walking, which is what ISO_MOVES_PER_ENCOUNTER_MAX is
	# for.
	var moves_total := 0.0
	var encs_total := 0.0
	for did4 in Balance.DUNGEONS:
		var dd5 := Balance.dungeon(did4)
		# every dungeon, several times: room placement is rejection-sampled, so one
		# generation per dungeon would miss the shapes that only come up sometimes
		for trial4 in 8:
			var iso := TraversalIso.new()
			iso.generate(dd5)
			var budget4: int = Traversal.standard_encounters(dd5).size() + 1  # + the boss
			if iso.quota != budget4:
				fails += 1
				print("FAIL ISO %s: quota %d for a dungeon that budgeted %d — floors must SPLIT the budget, not multiply it" % [
					did4, iso.quota, budget4])
			if iso.floors != Balance.iso_floors_for(dd5.difficulty if dd5 != null else 1):
				fails += 1
				print("FAIL ISO %s: %d floors" % [did4, iso.floors])
			# --- the floor is a building, not a blob ---
			if iso.rooms < 2:
				fails += 1
				print("FAIL ISO %s: %d chambers — a floor with one room has no corridors and no choice at the door" % [
					did4, iso.rooms])
			# Every carved tile must be reachable from the entrance. Corridors are dug
			# after the rooms are placed, so an off-by-one in the digger strands a whole
			# chamber — which reads in play as a floor that cannot be finished, and in a
			# diff as nothing at all.
			var reach4: Array = iso._dist_from(iso.pos)
			var stranded := 0
			for i in iso.enc.size():
				if int(iso.enc[i]) != TraversalIso.WALL and int(reach4[i]) < 0:
					stranded += 1
			if stranded > 0:
				fails += 1
				print("FAIL ISO %s: %d tiles walled off from the entrance" % [did4, stranded])
			# The entrance must be in a chamber, and must offer a choice like the first
			# row of every other model.
			if int(iso.room_of[iso.pos]) < 0:
				fails += 1; print("FAIL ISO %s: the run opens in a corridor" % did4)
			if int(iso.enc[iso.pos]) != TraversalIso.EMPTY:
				fails += 1; print("FAIL ISO %s: the entrance tile holds something" % did4)
			var doors4 := 0
			for n in iso._neighbours(iso.pos):
				if int(iso.enc[n]) != TraversalIso.WALL:
					doors4 += 1
			if doors4 < 2:
				fails += 1
				print("FAIL ISO %s: the entrance has %d exit(s) — no decision at the door" % [
					did4, doors4])
			# --- every fight on the floor is cast, and cast from the right pool ---
			#
			# The point of casting at generation time is that the creature STANDING there is
			# the creature you fight. An uncast fight silently falls back to combat rolling
			# its own, which looks like nothing and undoes the whole feature — so absence is
			# a failure, not a default.
			var normal_pool: Array = Balance.roster_pool(dd5, Balance.Tier.NORMAL)
			var elite_pool: Array = Balance.roster_pool(dd5, Balance.Tier.ELITE)
			for i in iso.enc.size():
				var e4 := int(iso.enc[i])
				if e4 != Traversal.Enc.COMBAT and e4 != Traversal.Enc.ELITE:
					continue
				var cast4 := String(iso.enemy_of.get(i, ""))
				if cast4 == "":
					fails += 1
					print("FAIL ISO %s: a fight on the floor has no creature cast" % did4)
					continue
				var pool4: Array = normal_pool if e4 == Traversal.Enc.COMBAT else elite_pool
				if not pool4.has(cast4):
					fails += 1
					print("FAIL ISO %s: cast '%s' is not in the tier's roster pool" % [did4, cast4])
				# A boss must never be cast as ordinary furniture: it is named and fixed,
				# and leaking one into a corridor leaks its signature into a trash fight.
				if Balance.ROSTER[Balance.Tier.BOSS].has(cast4):
					fails += 1
					print("FAIL ISO %s: cast a BOSS ('%s') as an ordinary fight" % [did4, cast4])
			for m4 in iso.mons:
				if String(m4.get("enemy", "")) == "":
					fails += 1
					print("FAIL ISO %s: a wanderer has no creature cast" % did4)
				elif not normal_pool.has(String(m4["enemy"])):
					fails += 1
					print("FAIL ISO %s: wanderer cast '%s' is off-roster" % [did4, m4["enemy"]])
			# a wanderer must be ON bare ground, reachable, and never on the entrance
			for m in iso.mons:
				if int(iso.enc[int(m["cell"])]) != TraversalIso.EMPTY:
					fails += 1; print("FAIL ISO %s: a wanderer shares a tile with something" % did4)
				if int(m["cell"]) == iso.pos:
					fails += 1; print("FAIL ISO %s: a wanderer spawned on the entrance" % did4)
				if int(reach4[int(m["cell"])]) < 0:
					fails += 1; print("FAIL ISO %s: a wanderer spawned in a sealed pocket" % did4)

			# --- pacing: walk the whole dungeon and count MOVES, not encounters ---
			#
			var moves := 0
			var got := 0
			while not iso.is_complete() and moves < 400:
				var o4 := iso.options()
				if o4.is_empty():
					fails += 1
					print("FAIL ISO %s: nothing to press" % did4)
					break
				moves += 1
				var stepped := iso.select(0)
				if not stepped.is_empty():
					# Optional content is not what this ratio is about (D185): a site resolved
					# on the way past would make the pacing look better for having more in the
					# way of it. Same exclusion as the two-route measurement below.
					if not bool(stepped.get("optional", false)):
						got += 1
					iso.clear_pending()
			if not iso.is_complete():
				fails += 1
				print("FAIL ISO %s: did not finish in %d moves" % [did4, moves])
			moves_total += float(moves)
			encs_total += float(maxi(1, got))

	# --- two routes, and only one of them is the required path (D179) -----------------
	#
	# `ISO_MOVES_PER_ENCOUNTER_MAX` measures the walk of a player who takes the first ranked
	# option: the REQUIRED path, which must not grow. It says nothing at all about a player
	# who strips a floor, because optional business is deliberately invisible to that
	# ranking — keys are ranked, not required (D167), which is exactly what keeps them out
	# of the number above.
	#
	# So there is a second walker, with its own reported figure and its own ceiling. It
	# ships ALONE, before any optional content exists, so the numbers it establishes are a
	# baseline of the game as it stands and not of a changed one — a baseline measured after
	# the feature it is meant to price has landed is not a baseline.
	#
	# The ceiling is RELATIVE and derived from `ISO_LINGER`: on this floor turns are the
	# currency, a floor wakes every `ISO_LINGER` turns spent on it, and an optional route
	# costing more than `ISO_COMPLETIONIST_ROUSES` extra wakings has stopped being a choice
	# and become a difficulty setting. Deliberately not an absolute per-floor figure, which
	# would have been wrong on the day it was written: the required route already spends 22
	# to 45 turns on a floor depending on how many floors the dungeon has.
	var greedy := {"moves": 0.0, "encs": 0.0, "floors": 0.0}
	var full := {"moves": 0.0, "encs": 0.0, "floors": 0.0}
	var stranded_total := 0
	for didw in Balance.DUNGEONS:
		var ddw := Balance.dungeon(didw)
		for trialw in 6:
			for route in 2:
				var w1 := TraversalIso.new()
				w1.generate(ddw)
				var got1 := _walk(w1, route == 1)
				var into: Dictionary = full if route == 1 else greedy
				into["moves"] = float(into["moves"]) + float(got1["moves"])
				into["encs"] = float(into["encs"]) + float(maxi(1, int(got1["encs"])))
				into["floors"] = float(into["floors"]) + float(maxi(1, w1.floors))
				stranded_total += int(got1.get("stranded", 0))
				if not w1.is_complete():
					fails += 1
					print("FAIL ISO %s: the %s walker did not finish" % [
						didw, "completionist" if route == 1 else "greedy"])
	var greedy_per_floor := float(greedy["moves"]) / maxf(1.0, float(greedy["floors"]))
	var full_per_floor := float(full["moves"]) / maxf(1.0, float(full["floors"]))
	var extra := full_per_floor - greedy_per_floor
	var budget: int = Balance.iso_optional_turn_budget()
	if extra > float(budget):
		fails += 1
		print("FAIL ISO: the optional route costs %.1f extra turns a floor, budget is %d (%d rouse) — exploring is a difficulty setting, not a choice" % [
			extra, budget, Balance.ISO_COMPLETIONIST_ROUSES])
	# ...and it has to cost SOMETHING, or the second walker is measuring the first one and
	# the whole instrument is a green light for anything. The one thing on the floor that is
	# optional today is a key, and covering ground to fetch one is what it costs.
	if extra <= 0.0:
		fails += 1
		print("FAIL ISO: the optional route costs nothing (%.1f turns a floor) — the second walker is not walking a second route" % extra)
	print("  (info: ISO required route %.1f turns a floor, %.1f moves per encounter; optional route %.1f and %.1f — %+.1f turns, budget %d; %d optional destination(s) dropped as unreachable)" % [
		greedy_per_floor, float(greedy["moves"]) / maxf(1.0, float(greedy["encs"])),
		full_per_floor, float(full["moves"]) / maxf(1.0, float(full["encs"])),
		extra, budget, stranded_total])

	var per_enc := moves_total / maxf(1.0, encs_total)
	if per_enc > Balance.ISO_MOVES_PER_ENCOUNTER_MAX:
		fails += 1
		print("FAIL ISO: %.1f moves per encounter, ceiling is %.1f — the walking is burying the card game" % [
			per_enc, Balance.ISO_MOVES_PER_ENCOUNTER_MAX])
	else:
		print("  (info: ISO %.1f moves per encounter, ceiling %.1f)" % [
			per_enc, Balance.ISO_MOVES_PER_ENCOUNTER_MAX])

	# Encounters must be SPREAD, not clumped. A random subset clumps, and three
	# encounters in adjoining tiles read as one room with three doors while the open
	# ground ends up in a corner nobody visits. Farthest-point placement is what turns
	# the extra tiles into travel, so the property it exists for is asserted.
	var iso2 := TraversalIso.new()
	iso2.generate(null)
	var touching := 0
	for i in iso2.enc.size():
		if int(iso2.enc[i]) < 0:
			continue
		for n in iso2._neighbours(i):
			if int(iso2.enc[n]) >= 0:
				touching += 1
	if touching > 0:
		fails += 1
		print("FAIL ISO: %d encounters adjoin another — placement clumped instead of spreading" % touching)
	# Every style in the table has to produce a floor that satisfies everything above,
	# or a dungeon nobody happened to test ships broken. Checked through the styles
	# rather than through the dungeons, so adding a style is covered too.
	for sname in Balance.ISO_STYLES:
		var seen_rooms := 0
		for trial5 in 12:
			var iso3 := TraversalIso.new()
			iso3.dungeon = null
			iso3.w = Balance.ISO_GRID
			iso3.h = Balance.ISO_GRID
			iso3.enc = []
			iso3.room_of = []
			for i in Balance.ISO_GRID * Balance.ISO_GRID:
				iso3.enc.append(TraversalIso.WALL)
				iso3.room_of.append(-1)
			var rects: Array = iso3._place_rooms(Balance.ISO_STYLES[sname], Balance.iso_tiles_per_floor(2))
			seen_rooms += rects.size()
			if rects.size() < 2:
				fails += 1
				print("FAIL ISO style %s: placed %d chambers" % [sname, rects.size()])
		print("  (info: iso style %-10s averages %.1f chambers)" % [
			sname, float(seen_rooms) / 12.0])
	# Style and terrain are looked up by dungeon id with a silent default, so a typo in
	# either table does not fail — it just quietly gives that dungeon the fallback and the
	# variety it was supposed to have goes missing. Both tables are checked against the
	# real dungeon list and against the sets they index.
	for did5 in Balance.ISO_STYLE_OF:
		if not Balance.DUNGEONS.has(did5):
			fails += 1
			print("FAIL ISO: style table names '%s', which is not a dungeon" % did5)
		if not Balance.ISO_STYLES.has(Balance.ISO_STYLE_OF[did5]):
			fails += 1
			print("FAIL ISO: %s wants style '%s', which does not exist" % [
				did5, Balance.ISO_STYLE_OF[did5]])
	for did6 in Balance.ISO_TERRAIN_OF:
		if not Balance.DUNGEONS.has(did6):
			fails += 1
			print("FAIL ISO: terrain table names '%s', which is not a dungeon" % did6)
		if not Balance.ISO_TERRAINS.has(Balance.ISO_TERRAIN_OF[did6]):
			fails += 1
			print("FAIL ISO: %s wants terrain '%s', which is not in ISO_TERRAINS" % [
				did6, Balance.ISO_TERRAIN_OF[did6]])
	# ...and both axes have to actually vary, or the samey test (D81) is being failed
	# silently: twelve dungeons all defaulting to the same pair would pass every
	# assertion above.
	var styles_used := {}
	var terrains_used := {}
	for did7 in Balance.DUNGEONS:
		styles_used[String(Balance.ISO_STYLE_OF.get(did7, Balance.ISO_STYLE_DEFAULT))] = true
		terrains_used[Balance.iso_terrain(did7)] = true
	if styles_used.size() < 3 or terrains_used.size() < 3:
		fails += 1
		print("FAIL ISO: %d styles and %d terrains across 12 dungeons — not enough variety to tell them apart" % [
			styles_used.size(), terrains_used.size()])
	else:
		print("  (info: iso uses %d of %d styles and %d of %d terrains)" % [
			styles_used.size(), Balance.ISO_STYLES.size(),
			terrains_used.size(), Balance.ISO_TERRAINS.size()])
	# --- the dressing: generated must equal drawn, and must never be a lie -----------
	#
	# D86 is the reason every clause here counts something. It asserted "a vault has exactly
	# one way in" and "a vault has a key", both vacuously true, both green for the entire
	# life of a feature that generated ZERO vaults. So every new placeable thing gets two
	# assertions: the properties it must have, AND a non-zero count across a sweep — because
	# a property nothing has is a property nothing can break.
	#
	# The other half is that the dressing must not be able to LIE. The floor has spent three
	# decisions teaching the player that what is drawn on a tile is what they get — the
	# creature (D85), the chest's tier and its lock (D172) — and a decoration sharing a tile
	# with any of that, or sitting where the player is about to stand, would undo all three.
	var props_seen := 0
	var wall_props := 0
	var roles_seen := {}
	var lights_seen := 0
	var landmarks_seen := 0
	var lit_tiles := 0
	var walk_tiles := 0
	var floors_swept := 0
	for did8 in Balance.DUNGEONS:
		var dt := TraversalIso.new()
		dt.generate(Balance.dungeon(did8))
		for f8 in dt.floors:
			dt._build_floor(f8)
			floors_swept += 1
			# every chamber has a role, and it is a role that exists
			if dt.room_role.size() != dt.rooms:
				fails += 1
				print("FAIL %s floor %d: %d chambers and %d roles" % [
					did8, f8 + 1, dt.rooms, dt.room_role.size()])
			for r8 in dt.room_role:
				if not Balance.ISO_ROOM_ROLES.has(String(r8)):
					fails += 1
					print("FAIL %s: chamber role '%s' is not a role" % [did8, r8])
				else:
					roles_seen[String(r8)] = true
			if dt.props.size() != dt.enc.size():
				fails += 1
				print("FAIL %s floor %d: the prop grid is %d cells for a %d-cell floor" % [
					did8, f8 + 1, dt.props.size(), dt.enc.size()])
			for i8 in dt.enc.size():
				var p8 := int(dt.props[i8]) - 1
				if p8 < 0:
					continue
				var kinds8: Array = Balance.iso_props(dt.terrain)
				if p8 >= kinds8.size():
					fails += 1
					print("FAIL %s: a prop indexes %d of %d in the %s set" % [
						did8, p8, kinds8.size(), dt.terrain])
					continue
				var kind8: Dictionary = kinds8[p8]
				# A shape the view cannot draw is an invisible prop — content that goes
				# missing without failing, which is the D86 shape one noun over.
				if not Balance.ISO_PROP_SHAPES.has(String(kind8.get("shape", ""))):
					fails += 1
					print("FAIL %s: prop '%s' wants shape '%s', which nothing draws" % [
						did8, kind8.get("name", "?"), kind8.get("shape", "")])
				var on_wall: bool = String(kind8.get("on", "ground")) == "wall"
				var is_rock8: bool = int(dt.enc[i8]) == TraversalIso.WALL
				if on_wall != is_rock8:
					fails += 1
					print("FAIL %s: %s dressing on %s" % [did8,
						"wall" if on_wall else "ground", "rock" if is_rock8 else "floor"])
				if on_wall:
					wall_props += 1
					continue
				props_seen += 1
				# The two lies. A prop on a tile that holds something is the tile telling
				# the player two things; a prop on the entrance is the one tile a floor
				# should open with nothing on it.
				if int(dt.enc[i8]) != TraversalIso.EMPTY:
					fails += 1
					print("FAIL %s: a prop shares a tile with %d" % [did8, int(dt.enc[i8])])
				if i8 == dt.pos:
					fails += 1
					print("FAIL %s: the entrance tile is dressed" % did8)
			# lights: at least one, on walkable ground, and they actually light something
			if dt.lights.is_empty():
				fails += 1
				print("FAIL %s floor %d: no light on the floor — the flat rule is back" % [
					did8, f8 + 1])
			for l8 in dt.lights:
				var lc8 := int((l8 as Dictionary).get("cell", -1))
				lights_seen += 1
				if lc8 < 0 or lc8 >= dt.enc.size() or int(dt.enc[lc8]) == TraversalIso.WALL:
					fails += 1
					print("FAIL %s: a light stands in rock" % did8)
			# WALKABLE tiles only, because rock takes the light of the floor beside it and
			# counting it would report a floor as better lit than the player can stand in.
			var here_lit := 0
			for i9 in dt.enc.size():
				if int(dt.enc[i9]) != TraversalIso.WALL \
						and dt.light(i9 % dt.w, int(i9 / dt.w)) > 0.0:
					here_lit += 1
			lit_tiles += here_lit
			walk_tiles += dt.tiles
			if here_lit == 0:
				fails += 1
				print("FAIL %s floor %d: the light field is empty" % [did8, f8 + 1])
			# ...and NOT most of it. A floor lit everywhere has no light axis, it has a
			# brighter flat rule — which is what the first tuning of this feature actually
			# shipped: two to four sources at radius three lit 91% of the ground and the
			# whole point of splitting light from state was gone. The band is asserted from
			# both sides so a radius or a source count cannot be raised until the feature
			# stops existing again.
			if float(here_lit) > float(dt.tiles) * LIT_MAX:
				fails += 1
				print("FAIL %s floor %d: %d of %d tiles lit, over the %.0f%% band" % [
					did8, f8 + 1, here_lit, dt.tiles, 100.0 * LIT_MAX])
			# the landmark stands in rock, walls in real ground, and is never on the floor
			if dt.landmark >= 0:
				landmarks_seen += 1
				if int(dt.enc[dt.landmark]) != TraversalIso.WALL:
					fails += 1
					print("FAIL %s: the landmark is standing on walkable ground" % did8)
				var touch8 := 0
				for n8 in dt._neighbours(dt.landmark):
					if int(dt.enc[n8]) != TraversalIso.WALL:
						touch8 += 1
				if touch8 < 2:
					fails += 1
					print("FAIL %s: the landmark walls in %d tiles — nobody will see it" % [
						did8, touch8])
	if props_seen == 0 or wall_props == 0:
		fails += 1
		print("FAIL the dressing generated %d ground props and %d wall props — D86 says count it" % [
			props_seen, wall_props])
	if landmarks_seen < floors_swept:
		fails += 1
		print("FAIL %d of %d floors got a landmark" % [landmarks_seen, floors_swept])
	# ...and the roles have to VARY. Twelve dungeons whose every chamber came out `cell`
	# would satisfy every clause above and be the samey failure (D81) inside one floor.
	if roles_seen.size() < 4:
		fails += 1
		print("FAIL only %d of %d chamber roles ever appear" % [
			roles_seen.size(), Balance.ISO_ROOM_ROLES.size()])
	print("  (info: %d floors dressed: %d ground props, %d wall props, %d roles of %d, %d lights, %d landmarks, %.0f%% of walkable ground lit)" % [
		floors_swept, props_seen, wall_props, roles_seen.size(),
		Balance.ISO_ROOM_ROLES.size(), lights_seen, landmarks_seen,
		100.0 * float(lit_tiles) / maxf(1.0, float(walk_tiles))])

	# --- secret pockets: generated equals opened, and a pocket is a DEAD END (D182) ---
	#
	# D86 is the whole reason this block counts things. It asserted "a vault has exactly one
	# way in" and "a vault has a key" — both vacuously true, both green for the entire life
	# of a feature that generated ZERO vaults. So every clause here comes with a non-zero
	# sweep beside it, and the two properties that matter are checked the expensive way:
	#
	#   * **exactly one way in**, taken from the geometry rather than from the generator's
	#     intent — the mouth is the only cell of a pocket that touches walkable ground;
	#   * **connectivity is identical sealed and open**, which is the assertion that keeps a
	#     pocket from being a SHORTCUT. D88's lesson is that a skip is a difficulty change no
	#     budget assertion can see, so this is the one that lets the feature ship at all.
	var pockets_seen := 0
	var pocket_floors := 0
	var prize_kinds := {}
	var pocket_tiles := 0
	for didp in Balance.DUNGEONS:
		var pt := TraversalIso.new()
		pt.generate(Balance.dungeon(didp))
		for fp in pt.floors:
			pt._build_floor(fp)
			pocket_floors += 1
			# planned equals placed, on every floor. The generator can run out of dead rock
			# to cut into, so a floor may place FEWER than it planned — but never more, and
			# the sweep below is what proves the shortfall is not total.
			var planned: int = (pt.pocketplan[fp] as Array).size() if fp < pt.pocketplan.size() else 0
			if pt.pockets.size() > planned:
				fails += 1
				print("FAIL %s floor %d: %d pockets placed against %d planned" % [
					didp, fp + 1, pt.pockets.size(), planned])
			# connectivity, sealed: every walkable tile reachable from the entrance, and no
			# pocket cell walkable at all
			var sealed_reach := pt._dist_from(pt.pos)
			var sealed_walkable := 0
			for i in pt.enc.size():
				if int(pt.enc[i]) != TraversalIso.WALL:
					sealed_walkable += 1
					if int(sealed_reach[i]) < 0:
						fails += 1
						print("FAIL %s floor %d: a tile is walled off with the pockets sealed" % [
							didp, fp + 1])
			for kp in pt.pockets.size():
				var pk: Dictionary = pt.pockets[kp]
				pockets_seen += 1
				prize_kinds[String(pk["prize"])] = true
				var cellsp: Array = pk["cells"]
				pocket_tiles += cellsp.size()
				if cellsp.size() < Balance.POCKET_TILES_MIN \
						or cellsp.size() > Balance.POCKET_TILES_MAX:
					fails += 1
					print("FAIL %s: a pocket is %d tiles, the band is %d-%d" % [
						didp, cellsp.size(), Balance.POCKET_TILES_MIN,
						Balance.POCKET_TILES_MAX])
				if not (int(pk["mouth"]) in cellsp):
					fails += 1
					print("FAIL %s: a pocket's mouth is not one of its own cells" % didp)
				# sealed means SEALED: every cell is rock until it is pushed
				for c in cellsp:
					if int(pt.enc[int(c)]) != TraversalIso.WALL:
						fails += 1
						print("FAIL %s: a sealed pocket has walkable ground in it" % didp)
				# EXACTLY ONE WAY IN, read off the geometry: only the mouth may touch
				# walkable ground, and it may touch exactly one tile of it.
				for c in cellsp:
					var ci := int(c)
					var touches := 0
					for n in pt._neighbours(ci):
						if int(pt.enc[n]) != TraversalIso.WALL and not (n in cellsp):
							touches += 1
					if ci == int(pk["mouth"]):
						if touches != 1:
							fails += 1
							print("FAIL %s: a pocket's mouth touches %d tiles, not 1 — that is a route, not a dead end" % [
								didp, touches])
						# ...and the one tile it touches must be one the player can REACH and
						# stand on without taking the stairs. A mark you can only get to by
						# descending is a mark nobody can push, and it generated twice: once
						# with the stair as the approach itself, once with the stair as the
						# only route to the approach (the way on is the furthest *chamber*
						# tile, so a corridor dead end can lie beyond it). Both were found by
						# the completionist walker pacing between two tiles for ever.
						var standable := pt._dist_from_avoiding_exit(pt.pos)
						var ok := false
						for n2 in pt._neighbours(ci):
							if int(pt.enc[n2]) != TraversalIso.WALL and not (n2 in cellsp) \
									and not pt._is_exit(n2) and int(standable[n2]) >= 0:
								ok = true
						if not ok:
							fails += 1
							print("FAIL %s: a pocket cannot be reached without taking the stairs — it can never be opened" % didp)
					elif touches != 0:
						fails += 1
						print("FAIL %s: a pocket cell behind the mouth touches walkable ground — a second door" % didp)
			# ...and now open every one of them and check the floor did not change shape.
			# Same walkable count plus the pockets' own tiles, same reachability, and the
			# distance from the entrance to the way on IDENTICAL — which is the clause that
			# says no pocket shortened the route to anything.
			var exit_cell := -1
			for i in pt.enc.size():
				if pt._is_exit(i):
					exit_cell = i
			var was_dist: int = int(sealed_reach[exit_cell]) if exit_cell >= 0 else -1
			var added := 0
			for kp2 in pt.pockets.size():
				added += (pt.pockets[kp2]["cells"] as Array).size()
				pt._open_pocket(kp2)
			var open_reach := pt._dist_from(pt.pos)
			var open_walkable := 0
			for i in pt.enc.size():
				if int(pt.enc[i]) != TraversalIso.WALL:
					open_walkable += 1
					if int(open_reach[i]) < 0:
						fails += 1
						print("FAIL %s floor %d: a tile is walled off with the pockets open" % [
							didp, fp + 1])
			if open_walkable != sealed_walkable + added:
				fails += 1
				print("FAIL %s floor %d: %d walkable sealed + %d pocket tiles != %d open" % [
					didp, fp + 1, sealed_walkable, added, open_walkable])
			if exit_cell >= 0 and int(open_reach[exit_cell]) != was_dist:
				fails += 1
				print("FAIL %s floor %d: the way on is %d steps away with the pockets open and %d with them sealed — a pocket is a SHORTCUT" % [
					didp, fp + 1, int(open_reach[exit_cell]), was_dist])
	if pockets_seen == 0:
		fails += 1
		print("FAIL the generator produced NO pockets across %d floors — D86's exact shape" % pocket_floors)
	if prize_kinds.size() < 3:
		fails += 1
		print("FAIL only %d kind(s) of prize ever appear behind a wall" % prize_kinds.size())
	print("  (info: %d pockets over %d floors, %.1f tiles each, prizes %s)" % [
		pockets_seen, pocket_floors, float(pocket_tiles) / maxf(1.0, float(pockets_seen)),
		str(prize_kinds.keys())])

	# --- the guard is extra attrition and must stay OUTSIDE every price (D183) ---------
	#
	# A guarded pocket is the only thing in the game that can make a run harder than its
	# difficulty rating, so it is the one that needs the most checking. Four separate ways it
	# could be wrong, and every one of them would leave the whole suite green:
	#
	#   * the per-run CAP could be a per-floor roll in disguise, and a lucky sequence would
	#     add five voluntary elites to a dungeon that promised none;
	#   * a guard could land in `dodgeable`, and `Balance.avoid_cost` solves the whole slip
	#     ladder from that count — so every slip in the dungeon would be re-priced by
	#     accident (D99's exact failure: a price and a count deriving from different places,
	#     green for two years);
	#   * a slip could be OFFERED inside a pocket, which prices a decline that should be free;
	#   * the guard could be cast from the wrong pool, or not cast at all, and the silhouette
	#     the player wagered against would not be the creature they met (D85).
	var guards_seen := 0
	var guarded_pockets := 0
	var pockets_total := 0
	for didg in Balance.DUNGEONS:
		var gt := TraversalIso.new()
		gt.generate(Balance.dungeon(didg))
		# The cap, asserted rather than assumed, and read off the PLAN because that is where
		# it is enforced — a per-floor roll would satisfy any per-floor check.
		if gt.planned_guards() > Balance.POCKET_GUARDS_PER_RUN:
			fails += 1
			print("FAIL %s: %d guards planned, the cap is %d" % [
				didg, gt.planned_guards(), Balance.POCKET_GUARDS_PER_RUN])
		guards_seen += gt.planned_guards()
		var elite_pool: Array = Balance.roster_pool(Balance.dungeon(didg), Balance.Tier.ELITE)
		for fg in gt.floors:
			gt._build_floor(fg)
			# `dodgeable` is a DUNGEON-wide count taken from the budget. Cross-checked here
			# against the tiles actually laid down outside the pockets, which is the check
			# D99 did not have: the count and the things it counts must be the same set.
			var mandatory_fights := 0
			for i in gt.enc.size():
				var eg := int(gt.enc[i])
				if (eg == Traversal.Enc.COMBAT or eg == Traversal.Enc.ELITE) \
						and not gt._in_pocket(i):
					mandatory_fights += 1
			pockets_total += gt.pockets.size()
			for kg in gt.pockets.size():
				var pg: Dictionary = gt.pockets[kg]
				if String(pg.get("guard", "")) == "":
					continue
				guarded_pockets += 1
				# cast from the pool combat would have used, and never a boss
				if not elite_pool.has(String(pg["guard"])):
					fails += 1
					print("FAIL %s: a guard is cast '%s', which is not in the elite pool" % [
						didg, pg["guard"]])
				if Balance.ROSTER[Balance.Tier.BOSS].has(String(pg["guard"])):
					fails += 1
					print("FAIL %s: a BOSS is standing in a pocket" % didg)
				# a guard needs somewhere to stand that is not the prize's tile
				if (pg["cells"] as Array).size() < 2:
					fails += 1
					print("FAIL %s: a one-tile pocket was given a guard — it has no between" % didg)
			# Opening every pocket must not change what the dungeon REQUIRES. A guard that
			# quietly displaced a mandatory elite would make the dungeon cheaper for the
			# player who never explores, which is R1 broken from the other direction.
			for kg2 in gt.pockets.size():
				gt._open_pocket(kg2)
			var after_fights := 0
			var guards_on_floor := 0
			for i in gt.enc.size():
				var eg2 := int(gt.enc[i])
				if eg2 != Traversal.Enc.COMBAT and eg2 != Traversal.Enc.ELITE:
					continue
				if gt._in_pocket(i):
					guards_on_floor += 1
					# ...and every guard tile has its creature, moved across from the pocket
					if String(gt.enemy_of.get(i, "")) == "":
						fails += 1
						print("FAIL %s: a guard reached the floor with no creature cast" % didg)
				else:
					after_fights += 1
			if after_fights != mandatory_fights:
				fails += 1
				print("FAIL %s floor %d: %d mandatory fights sealed, %d open — a guard displaced one" % [
					didg, fg + 1, mandatory_fights, after_fights])
			# No slip is ever offered for a guard. Walked over the whole floor rather than
			# sampled: `_compute_options` adds one for EVERY adjacent fight, so suppressing it
			# is a deliberate act and a deliberate act is a thing that can be undone.
			if guards_on_floor > 0:
				for i in gt.enc.size():
					if int(gt.enc[i]) == TraversalIso.WALL:
						continue
					gt.pos = i
					gt._invalidate()
					for o in gt.options():
						if String(o.get("action", "")) != "avoid":
							continue
						if gt._in_pocket(int(o["cell"])):
							fails += 1
							print("FAIL %s: a slip is offered against a guard — a decline that should be free is priced" % didg)
	if guards_seen == 0:
		fails += 1
		print("FAIL no pocket in any dungeon was ever given a guard")
	print("  (info: %d guards planned across %d dungeons, %d of %d placed pockets guarded, cap %d)" % [
		guards_seen, Balance.DUNGEONS.size(), guarded_pockets, pockets_total,
		Balance.POCKET_GUARDS_PER_RUN])
	# ...and not ALL of them. An unguarded pocket has to stay common enough that a mark reads
	# as an invitation rather than a warning.
	if pockets_total > 0 and guarded_pockets == pockets_total:
		fails += 1
		print("FAIL every pocket is guarded — a mark is a warning, not an invitation")

	# --- doors and sites: the other two optional channels (D185) ----------------------
	#
	# A locked mouth reuses the key the floor already scatters, so the thing that can go wrong
	# is arithmetic: a door with no key is a dead end the player was promised a way through,
	# a key with no door is litter. That invariant is checked with the chests above. What is
	# checked here is that both channels EXIST — D86's lesson is that the assertions are
	# worthless without a count beside them — and that a site is genuinely off the route.
	var doors_seen := 0
	var sites_seen := 0
	var site_floors := 0
	var site_off_total := 0
	for didx in Balance.DUNGEONS:
		var xt := TraversalIso.new()
		xt.generate(Balance.dungeon(didx))
		for fx in xt.floors:
			xt._build_floor(fx)
			doors_seen += xt._locked_mouths()
			site_floors += 1
			for sc in xt.sites:
				sites_seen += 1
				var si := int(sc)
				# a site stands in the open, on ground, in a chamber, and never on the entrance
				if int(xt.enc[si]) < 0:
					fails += 1
					print("FAIL %s: a site is not standing on anything" % didx)
				if int(xt.room_of[si]) < 0:
					fails += 1
					print("FAIL %s: a site is down a corridor, where nothing reveals it" % didx)
				if si == xt.pos:
					fails += 1
					print("FAIL %s: a site is standing on the entrance" % didx)
				if xt._in_pocket(si):
					fails += 1
					print("FAIL %s: a site is inside a pocket — that is a prize, not a site" % didx)
				# ...and it is OFF the required route, measured rather than eyeballed
				var exit_x := -1
				for i in xt.enc.size():
					if xt._is_exit(i):
						exit_x = i
				if exit_x >= 0:
					var de := xt._dist_from(xt.pos)
					var dx := xt._dist_from(exit_x)
					var off: int = int(de[si]) + int(dx[si]) - int(de[exit_x])
					site_off_total += off
					if off < Balance.SITE_OFF_PATH:
						fails += 1
						print("FAIL %s: a site sits %d steps off the route, the floor is %d — that is ON the path" % [
							didx, off, Balance.SITE_OFF_PATH])
				# a site must be invisible to the required path, exactly as a pocket is
				if not xt._is_optional(si):
					fails += 1
					print("FAIL %s: a site is being counted as business the dungeon asked for" % didx)
	if doors_seen == 0:
		fails += 1
		print("FAIL no pocket in any dungeon is ever shut with a door")
	if sites_seen == 0:
		fails += 1
		print("FAIL no site is ever placed — the channel generates nothing (D86's shape)")
	print("  (info: %d doors and %d sites over %d floors, sites average %.1f steps off the route)" % [
		doors_seen, sites_seen, site_floors,
		float(site_off_total) / maxf(1.0, float(sites_seen))])

	# --- a toll's answer must be the FLOOR, not a fact (D186) -------------------------
	#
	# The failure this feature exists to avoid is a riddle solved once and pressed ever after,
	# so the assertion is about the answer's SOURCE rather than its value: it must be derived
	# live, it must move when the floor moves, and the option list must never carry it in a
	# fixed position. Plus the usual non-zero count, because a question kind that never gets
	# asked is a question kind that ships untested (D86).
	var tolls_seen := {}
	var toll_mouths := 0
	## kind -> the set of answers it has actually produced. See the constant check below.
	var spread := {}
	for didt in Balance.DUNGEONS:
		var tt := TraversalIso.new()
		tt.generate(Balance.dungeon(didt))
		for ft in tt.floors:
			tt._build_floor(ft)
			for pt2 in tt.pockets:
				var pdt: Dictionary = pt2
				var kindt := String(pdt.get("toll", ""))
				if kindt == "":
					continue
				toll_mouths += 1
				tolls_seen[kindt] = true
				if not Balance.TOLLS.has(kindt):
					fails += 1
					print("FAIL %s: a toll asks '%s', which is not a question" % [didt, kindt])
				# it must say something, in this floor's own voice
				if Balance.toll_text(kindt, tt.terrain) == "":
					fails += 1
					print("FAIL %s: a toll with no words on it" % didt)
				# the choices must contain the answer exactly once, and be sorted — a shuffled
				# list would have to shuffle the same way on a restored run (D22), and sorting
				# is what makes the right answer's POSITION carry no information
				var ans := tt.toll_answer(kindt)
				var ch := tt.toll_choices(kindt)
				if ch.size() < 2:
					fails += 1
					print("FAIL %s: a toll offers %d answers" % [didt, ch.size()])
				var hits := 0
				for v in ch:
					if int(v) == ans:
						hits += 1
				if hits != 1:
					fails += 1
					print("FAIL %s: the right answer appears %d times among the choices" % [
						didt, hits])
				for ci in range(1, ch.size()):
					if int(ch[ci]) <= int(ch[ci - 1]):
						fails += 1
						print("FAIL %s: a toll's answers are not in ascending order" % didt)
				spread.get_or_add(kindt, {})[tt.toll_answer(kindt)] = true
	if toll_mouths == 0:
		fails += 1
		print("FAIL no pocket in any dungeon is ever shut with a toll")
	# Kind coverage is checked over the PLAN across many dungeons, not over the handful of
	# mouths one sweep happens to carve. Placement is scarce — a floor has about one pocket,
	# most are marks or doors — so a per-sweep check on placed tolls failed one run in three
	# while the roll itself was perfectly even. What must be true is that every kind can be
	# asked; how many get cut from a given dungeon is the carving's business.
	var kinds_rolled := {}
	for didk in Balance.DUNGEONS:
		for tk in 8:
			var kt2 := TraversalIso.new()
			kt2.generate(Balance.dungeon(didk))
			for row in kt2.pocketplan:
				for e2 in row:
					var kk := String((e2 as Dictionary).get("toll", ""))
					if kk != "":
						kinds_rolled[kk] = true
	if kinds_rolled.size() < Balance.TOLLS.size():
		fails += 1
		print("FAIL only %d of %d question kinds are ever rolled" % [
			kinds_rolled.size(), Balance.TOLLS.size()])
	# **No question kind may be a CONSTANT.** This is the assertion the whole feature turns
	# on: an answer that is the same wherever and whenever it is asked is a fixed riddle with
	# extra steps, solved once by the player or once by a wiki. Sampled over every kind at
	# every position of a partly-walked floor in every dungeon, because two of the three only
	# start to vary once there is a route behind you — a sweep of FRESH floors reported all
	# three as constant, which was true of the sample and false of the game.
	for didc in Balance.DUNGEONS:
		var ct := TraversalIso.new()
		ct.generate(Balance.dungeon(didc))
		for w2 in 15:
			if ct.is_complete() or ct.options().is_empty():
				break
			if not ct.select(0).is_empty():
				ct.clear_pending()
		var keep := ct.pos
		for i in ct.enc.size():
			if int(ct.enc[i]) == TraversalIso.WALL:
				continue
			ct.pos = i
			for kindc in Balance.TOLLS:
				spread.get_or_add(String(kindc), {})[ct.toll_answer(String(kindc))] = true
		ct.pos = keep
	var flat: Array = []
	for kindc2 in Balance.TOLLS:
		var vals: Dictionary = spread.get(String(kindc2), {})
		if vals.size() < 2:
			fails += 1
			print("FAIL '%s' always answers %s — that is a fixed riddle, not a question about the floor" % [
				kindc2, str(vals.keys())])
		flat.append("%s:%d" % [kindc2, vals.size()])
	print("  (info: %d tolls over 33 floors, %d kinds, distinct answers seen %s)" % [
		toll_mouths, tolls_seen.size(), ", ".join(flat)])

	# --- nothing a run NEEDS is ever behind a wall (D182) -----------------------------
	#
	# If a run can be blocked, gated or softlocked by an unfound pocket it is not a secret,
	# it is a defect — and the generator must not be able to produce the case, which is a
	# stronger claim than `test_softlock.gd` catching it afterwards. Walked with the greedy
	# policy, which never pushes: every dungeon must finish, and the encounter count must be
	# the one the dungeon asked for, with every pocket still sealed.
	for didn in Balance.DUNGEONS:
		var nt := TraversalIso.new()
		nt.generate(Balance.dungeon(didn))
		var nsteps := 0
		var pushed_any := false
		while not nt.is_complete() and nsteps < 600:
			var nopts := nt.options()
			if nopts.is_empty():
				break
			nsteps += 1
			var npick := 0
			for oi in nopts.size():
				if String(nopts[oi].get("action", "")) == "push":
					pushed_any = true
				if not nopts[oi].has("hp_cost") and String(nopts[oi].get("action", "")) != "push":
					npick = oi
					break
			if not nt.select(npick).is_empty():
				nt.clear_pending()
		if not nt.is_complete():
			fails += 1
			print("FAIL %s: could not be finished without pushing a single wall" % didn)
		if nt.cleared < nt.quota - 1:
			fails += 1
			print("FAIL %s: finished with %d of %d cleared and no pocket opened — something required is behind a wall" % [
				didn, nt.cleared, nt.quota])
		# ...and a pocket left sealed must not be counted as business owed. `progress()`
		# clamps at 1.0, so an over-count is invisible; an under-count would read as a
		# dungeon nobody can finish.
		if nt.progress() < 0.999 and nt.is_complete():
			fails += 1
			print("FAIL %s: complete at %.2f progress — the sealed pockets are being counted against the player" % [
				didn, nt.progress()])
		if pushed_any:
			print("  (info: %s offered a push on the required path and the walker declined it)" % didn)

	# --- errands: they must ask for MORE, and never be unsettleable (D184) ------------
	#
	# The dangerous half of this feature is not the reward, it is the CONDITION. The obvious
	# errands all pay a player for declining budgeted content — leave the chests alone, reach
	# the stairs in twenty turns, take no damage — and every one of those is a skip, which
	# D88 says is a difficulty change no budget assertion can see. So the shipped set is
	# checked against that directly: every condition must be settleable by a walker that
	# takes EVERYTHING, and none may be settleable by one that takes less.
	var errands_seen := {}
	var errand_floors := 0
	var errand_settled := 0
	for dide in Balance.DUNGEONS:
		var et := TraversalIso.new()
		et.generate(Balance.dungeon(dide))
		for fe in et.floors:
			if fe < et.errandplan.size() and String(et.errandplan[fe]) != "":
				errands_seen[String(et.errandplan[fe])] = true
			et._build_floor(fe)
			if et.errand == "":
				continue
			errand_floors += 1
			# it must say something, or the status line prints an empty phrase
			if et.errand_line() == "":
				fails += 1
				print("FAIL %s: an errand with no words on it" % dide)
			# ...and it must be settleable on the floor that set it. `pushed` on a floor with
			# no pocket, or `thorough` on a floor with no chest, is not a hard errand, it is
			# an ordinance nobody can discharge.
			if et.errand == Balance.ERRAND_PUSHED and et.pockets.is_empty():
				fails += 1
				print("FAIL %s floor %d: asked for a pocket on a floor that has none" % [
					dide, fe + 1])
			if et.errand == Balance.ERRAND_THOROUGH and et.errand_chests == 0:
				fails += 1
				print("FAIL %s floor %d: asked for every lid on a floor with no lids" % [
					dide, fe + 1])
			# A walker that takes everything settles it; the state it reads is the state the
			# model already keeps.
			et.errand_seen = false
			et.errand_pushed = not et.pockets.is_empty()
			et.errand_chests = 0
			if not et._errand_met():
				fails += 1
				print("FAIL %s: '%s' cannot be settled by a player who does everything" % [
					dide, et.errand])
			else:
				errand_settled += 1
			# ...and a player who does NOTHING must not settle it, or it is a payout for
			# turning up. `unseen` is the exception and deliberately so: it is settled by not
			# being caught, which is care rather than avoidance, and the ambush it dodges is
			# a price that already exists.
			et.errand_pushed = false
			et.errand_chests = 1
			et.errand_seen = true
			if et._errand_met():
				fails += 1
				print("FAIL %s: '%s' settles itself for a player who does nothing" % [
					dide, et.errand])
	if errands_seen.size() < Balance.ERRANDS.size():
		fails += 1
		print("FAIL only %d of %d errands are ever handed out" % [
			errands_seen.size(), Balance.ERRANDS.size()])
	# ...and not every floor, or an ordinance is a checklist entry rather than something a
	# place sometimes asks of you.
	if errand_floors >= 33:
		fails += 1
		print("FAIL every floor carries an errand")
	print("  (info: %d of 33 floors carry an errand, %d kinds, all settleable, %d gold at d1)" % [
		errand_floors, errands_seen.size(), Balance.errand_gold(1)])

	# --- aspects: a place you have cleared is not the same place (D187) ---------------
	#
	# The property that matters is that an aspect changes how a dungeon PLAYS without changing
	# what it costs. Every one of the three is budget-neutral by construction rather than by
	# hope, and this is where that is checked: the encounter budget of a dungeon wearing one
	# must be identical to the same dungeon wearing none.
	var aspect_budget := {}
	for dida in Balance.DUNGEONS:
		var dda := Balance.dungeon(dida)
		var want_q: int = Traversal.standard_encounters(dda).size() + 1
		for asp in [Balance.ASPECT_NONE] + Balance.ASPECTS:
			var at2 := TraversalIso.new()
			at2.aspect = String(asp)
			at2.generate(dda)
			if at2.quota != want_q:
				fails += 1
				print("FAIL %s wearing '%s': quota %d, the dungeon budgeted %d" % [
					dida, asp, at2.quota, want_q])
			aspect_budget[String(asp)] = int(aspect_budget.get(String(asp), 0)) + at2.quota
			# ...and `Walked` must actually put more of it on its feet, or the aspect is a
			# name with nothing behind it.
			if String(asp) == Balance.ASPECT_CROWDED:
				var plain := TraversalIso.new()
				plain.generate(dda)
				var walking := 0
				for r in at2.roam:
					walking += int(r)
					pass
				var still := 0
				for r in plain.roam:
					still += int(r)
				if walking <= still:
					fails += 1
					print("FAIL %s: 'Walked' fields %d wanderers against the plain %d" % [
						dida, walking, still])
	# The rotation has to reach every aspect and start at none, or a player either never sees
	# one or never sees the dungeon as written.
	if Balance.aspect_for(0) != Balance.ASPECT_NONE:
		fails += 1
		print("FAIL a dungeon wears an aspect before it has ever been cleared")
	var rotated := {}
	for n in 12:
		rotated[Balance.aspect_for(n + 1)] = true
	if rotated.size() != Balance.ASPECTS.size():
		fails += 1
		print("FAIL the rotation reaches %d of %d aspects" % [
			rotated.size(), Balance.ASPECTS.size()])
	for a2 in Balance.ASPECTS:
		if Balance.aspect_name(String(a2)) == "" or Balance.aspect_line(String(a2)) == "":
			fails += 1
			print("FAIL aspect '%s' has no name or no words" % a2)
	# ...and each one has to CHANGE something the floor does.
	var dark := TraversalIso.new()
	dark.aspect = Balance.ASPECT_DARK
	if dark._sight() >= Balance.ISO_SIGHT:
		fails += 1; print("FAIL 'Lightless' does not shorten sight")
	var waking := TraversalIso.new()
	waking.aspect = Balance.ASPECT_WAKING
	if waking._linger() >= Balance.ISO_LINGER:
		fails += 1; print("FAIL 'Waking' does not bring the rousing in")
	print("  (info: aspects %s, budget identical in all of them, +%d%% gold)" % [
		str(Balance.ASPECTS), Balance.ASPECT_GOLD_PCT])

	# --- the dressing has to survive being written down (R7) -------------------------
	#
	# It is only looked at, so none of it can change what a resumed run costs — which is
	# exactly why it would go unnoticed. A floor that came back dressed differently is a
	# different ROOM, in a model whose whole subject is remembering where you have been.
	for did9 in Balance.DUNGEONS:
		var pre := TraversalIso.new()
		pre.generate(Balance.dungeon(did9))
		var was_props := Array(pre.props)
		var was_roles: Array = pre.room_role.duplicate()
		var was_lights: Array = pre.lights.duplicate(true)
		var was_lm: int = pre.landmark
		var was_terrain: String = pre.terrain
		var was_style: String = pre.style_name
		var blob9 = JSON.parse_string(JSON.stringify(pre.save_state()))
		var post := TraversalIso.new()
		post.dungeon = Balance.dungeon(did9)
		post.load_state(blob9)
		if Array(post.props) != was_props:
			fails += 1
			print("FAIL %s: the floor came back dressed differently" % did9)
		if post.room_role != was_roles:
			fails += 1
			print("FAIL %s: the chamber roles did not survive the save" % did9)
		if post.lights.size() != was_lights.size():
			fails += 1
			print("FAIL %s: %d lights went in and %d came back" % [
				did9, was_lights.size(), post.lights.size()])
		if post.landmark != was_lm:
			fails += 1
			print("FAIL %s: the landmark moved across a save" % did9)
		if post.terrain != was_terrain or post.style_name != was_style:
			fails += 1
			print("FAIL %s: came back as %s/%s, was %s/%s" % [
				did9, post.style_name, post.terrain, was_style, was_terrain])
		# The light field is DERIVED, not saved — so the test that matters is that it comes
		# back identical anyway. A cache in a save file is a second copy of a fact free to
		# disagree with the first, which is why `_room_cells` is not saved either.
		for i10 in pre.enc.size():
			if absf(pre.light(i10 % pre.w, int(i10 / pre.w))
					- post.light(i10 % post.w, int(i10 / post.w))) > 0.001:
				fails += 1
				print("FAIL %s: the light field came back different" % did9)
				break

	# --- the drift tables have to index real things, and be REACHED (D177) -----------
	#
	# Style and terrain are looked up with a silent default, so a typo does not fail — it
	# quietly hands a floor the fallback and the variety goes missing. The same trap the
	# per-dungeon tables are checked for, one table along, and with the extra clause that
	# matters here: a deep style nothing ever drifts INTO is a style that ships unplayed.
	for s10 in Balance.ISO_STYLE_DEEP:
		if not Balance.ISO_STYLES.has(s10):
			fails += 1
			print("FAIL ISO: the deep table drifts FROM '%s', which is not a style" % s10)
		if not Balance.ISO_STYLES.has(Balance.ISO_STYLE_DEEP[s10]):
			fails += 1
			print("FAIL ISO: %s drifts to '%s', which does not exist" % [
				s10, Balance.ISO_STYLE_DEEP[s10]])
	for t10 in Balance.ISO_TERRAIN_DEEP:
		if not Balance.ISO_TERRAINS.has(t10) \
				or not Balance.ISO_TERRAINS.has(Balance.ISO_TERRAIN_DEEP[t10]):
			fails += 1
			print("FAIL ISO: the deep terrain table names something that is not a terrain")
	# Every style and every terrain must be REACHED by some dungeon at some depth. The old
	# assertion counted `ISO_STYLE_OF` alone and read "4 of 7" the moment three styles
	# arrived that only the drift reaches — which is a table that indexes real things and
	# still ships three of them unplayed.
	var reached_styles := {}
	var reached_terrains := {}
	var drifted := 0
	for did10 in Balance.DUNGEONS:
		var dd10 := Balance.dungeon(did10)
		var fl10: int = Balance.iso_floors_for(dd10.difficulty if dd10 != null else 1)
		var seen_pairs := {}
		for f10 in fl10:
			var st10 := Balance.iso_style_name(did10, f10, fl10)
			var tr10 := Balance.iso_terrain(did10, f10, fl10)
			reached_styles[st10] = true
			reached_terrains[tr10] = true
			seen_pairs["%s/%s" % [st10, tr10]] = true
		# ...and every dungeon has to actually CHANGE as you go down it, or the drift rule
		# is a table nobody reads.
		if seen_pairs.size() < 2:
			fails += 1
			print("FAIL ISO %s: all %d floors read the same — descending goes nowhere" % [
				did10, fl10])
		else:
			drifted += 1
	if reached_styles.size() < Balance.ISO_STYLES.size():
		fails += 1
		print("FAIL ISO: %d of %d styles are ever built — the rest ship unplayed" % [
			reached_styles.size(), Balance.ISO_STYLES.size()])
	print("  (info: %d styles and %d terrains reached across depth; %d of %d dungeons change as you descend)" % [
		reached_styles.size(), reached_terrains.size(), drifted, Balance.DUNGEONS.size()])

	# Every archetype in the game has to land in a family, and the families have to be
	# populated — a derivation that put all 35 in one bucket would give every creature the
	# same silhouette while passing every assertion above, which is the whole thing this
	# feature exists to avoid.
	var fam_count := {}
	for fam in Balance.ISO_FAMILIES:
		fam_count[fam] = 0
	for tier5 in [Balance.Tier.NORMAL, Balance.Tier.ELITE]:
		for eid in Balance.ROSTER[tier5]:
			var fam2 := Balance.iso_family(String(eid))
			if not Balance.ISO_FAMILIES.has(fam2):
				fails += 1
				print("FAIL ISO: '%s' derives family '%s', which is not a family" % [eid, fam2])
			else:
				fam_count[fam2] = int(fam_count[fam2]) + 1
	var empty_fams := 0
	for fam in fam_count:
		if int(fam_count[fam]) == 0:
			empty_fams += 1
	if empty_fams > 0:
		fails += 1
		print("FAIL ISO: %d silhouette famil(y/ies) match no enemy — %s" % [
			empty_fams, str(fam_count)])
	else:
		print("  (info: iso silhouettes %s)" % str(fam_count))
	print("  (info: iso floor %d tiles, %d chambers, %d on it, %d prowling, %d floors)" % [
		iso2.tiles, iso2.rooms, iso2.content, iso2.mons.size(), iso2.floors])

	# --- a dungeon may have its own shape, within reason -----------------------
	#
	# Every dungeon used to draw from one global mix, so twelve dungeons had one
	# rhythm. They differ now — a swarm, a treasure run, a market, a gauntlet — and
	# these are the bounds that keep "difficulty 5" meaning the same thing in all of
	# them. Without them the mix is a back door onto the difficulty curve: a dungeon
	# could quietly halve its fights and keep its rating.
	var shapes := {}
	for did3 in Balance.DUNGEONS:
		var dd4 := Balance.dungeon(did3)
		if dd4 == null:
			continue
		var mix: Dictionary = dd4.encounter_mix()
		var fights: int = int(mix["combat"]) + int(mix["elite"])
		var total := 1
		for k2 in mix:
			total += int(mix[k2])
		shapes[did3] = "%d/%d/%d/%d/%d/%d" % [mix["combat"], mix["elite"], mix["rest"],
			mix["shop"], mix["event"], mix["treasure"]]
		# The band moved with chests (D84): 8-11 was written when a dungeon held one
		# treasure. What it is really protecting is unchanged — a dungeon must not
		# quietly become twice the run its rating claims — so the band tracks the
		# shape rather than being deleted.
		if total < 12 or total > 15:
			fails += 1
			print("FAIL %s runs %d encounters; the band is 12-15" % [did3, total])
		if fights < 3 or fights > 6:
			fails += 1
			print("FAIL %s has %d fights; the band is 3-6" % [did3, fights])
		# ...and the fights must not be DROWNED by the chests. This is the pacing
		# question D84 actually risks: 5 chests and 4 fights is an expedition, 5
		# chests and 2 fights is a shopping trip with monsters in it.
		if float(fights) / float(maxi(1, total)) < 0.28:
			fails += 1
			print("FAIL %s is %.0f%% fights; chests have drowned the card game" % [
				did3, 100.0 * float(fights) / float(maxi(1, total))])
		# something other than fighting has to happen, or the dungeon is a treadmill
		if int(mix["rest"]) + int(mix["shop"]) + int(mix["event"]) + int(mix["treasure"]) < 2:
			fails += 1
			print("FAIL %s is nothing but fights" % did3)
	# ...and they must not all be the same shape, which is the thing being fixed
	var distinct := {}
	for k3 in shapes:
		distinct[shapes[k3]] = true
	if distinct.size() < 6:
		fails += 1
		print("FAIL only %d distinct dungeon shapes across %d dungeons" % [
			distinct.size(), shapes.size()])
	print("  (info: %d distinct shapes across %d dungeons)" % [distinct.size(), shapes.size()])

	# --- the memoized option list must never be stale -------------------------
	#
	# `options()` caches its answer because building it floods the floor and a single
	# step used to do that twice (D99). The cache is dropped by every mutator, and the
	# whole correctness of that rests on "every mutator" being true — a missed
	# invalidation does not crash, it hands the player a list of moves for a floor they
	# have already left, which is the quietest possible bug. So walk real dungeons and
	# compare the cached answer against a freshly computed one at every single step.
	for did3 in Balance.DUNGEONS:
		var mem := TraversalIso.new()
		mem.generate(Balance.dungeon(did3))
		var msteps := 0
		while not mem.is_complete() and msteps < 400:
			msteps += 1
			var cached := mem.options()
			var fresh := mem._compute_options()
			if cached.size() != fresh.size():
				fails += 1
				print("FAIL %s: cached %d options, recomputing gives %d" % [
					did3, cached.size(), fresh.size()])
				break
			var drift := false
			for oi in cached.size():
				var a: Dictionary = cached[oi]
				var b: Dictionary = fresh[oi]
				# Same default on both sides. Using different ones to "also catch a
				# missing key" makes every option without an `hp_cost` differ from
				# itself, which is how this assertion first failed on all twelve.
				if int(a.get("cell", -1)) != int(b.get("cell", -1)) \
						or int(a.get("type", -1)) != int(b.get("type", -1)) \
						or String(a.get("label", "")) != String(b.get("label", "")) \
						or int(a.get("hp_cost", 0)) != int(b.get("hp_cost", 0)) \
						or a.has("hp_cost") != b.has("hp_cost"):
					drift = true
			if drift:
				fails += 1
				print("FAIL %s: the memoized option list is stale at step %d" % [did3, msteps])
				break
			if cached.is_empty():
				break
			var mpick := 0
			for oi in cached.size():
				if not cached[oi].has("hp_cost"):
					mpick = oi
					break
			if not mem.select(mpick).is_empty():
				mem.clear_pending()

	# --- the dodge has to be a trade, not a discount --------------------------
	#
	# It was a flat 8 HP and nothing measured it, because the simulator's driver
	# only dodged below 35% HP and therefore never dodged at all. Measured properly,
	# skipping every avoidable fight beat fighting outright — the Drowned Market
	# went 49% to 87% for the same deck. A dominant strategy is a removed decision
	# (D20), so the price rises with depth and with each dodge already taken.
	#
	# Asserted structurally rather than by simulation: what breaks the mechanic is
	# the TOTAL being small against the health bar you are spending it from.
	#
	# **The rung count comes from a GENERATED dungeon, not from a constant.** This
	# block used to skip anything that was not a deck dungeon, and once D88 moved them
	# all onto the crawl that filter matched nothing and it silently stopped running.
	# D94 removed the filter — and the block then passed for a second wrong reason: it
	# priced a ladder of `ENCOUNTER_COMBATS + ENCOUNTER_ELITES` = 4 rungs, the GLOBAL
	# default mix, while the crawl offers two or three (per-dungeon mixes since D84,
	# and wanderers come out of the combat budget and cannot be slipped past). The real
	# bill was 25-46% of a health bar against an assertion of 50%, and it passed on a
	# number the game never charges (D99). Asking a real traversal how many dodges it
	# lays down is the only version of this that cannot drift again.
	for did in Balance.DUNGEONS:
		var dd2 := Balance.dungeon(did)
		if dd2 == null:
			continue
		var probe := TraversalIso.new()
		probe.generate(dd2)
		var dodgeable: int = probe.dodgeable
		if dodgeable < 1:
			fails += 1
			print("FAIL %s offers no fight to slip past — the crawl's only priced decision is absent" % did)
			continue
		var depth: int = dd2.difficulty
		var bar := float(Balance.BASE_MAX_HP + (depth - 1) * Balance.HP_PER_DUNGEON)
		var total := 0
		var prev := 0
		for i in dodgeable:
			var c: int = Balance.avoid_cost(depth, i, dodgeable)
			if c <= prev:
				fails += 1
				print("FAIL %s: dodge %d costs %d, no more than the one before it (%d)" % [
					did, i + 1, c, prev])
			prev = c
			total += c
		# skipping the whole dungeon must cost most of a health bar...
		if float(total) < bar * 0.5:
			fails += 1
			print("FAIL %s: dodging all %d fights costs %d of %d HP — the dungeon can be skipped on pocket change" % [
				did, dodgeable, total, int(bar)])
		# ...while one dodge stays affordable, or nobody would ever use it
		var first: int = Balance.avoid_cost(depth, 0, dodgeable)
		if float(first) > bar * 0.25:
			fails += 1
			print("FAIL %s: the first dodge costs %d of %d HP, too dear to ever be worth it" % [
				did, first, int(bar)])
		print("  (info: %-16s %d dodges, %d HP total = %.0f%% of a %d HP bar, first %d)" % [
			did, dodgeable, total, 100.0 * float(total) / bar, int(bar), first])
	# --- keys lie on the floor, and walking onto one takes it (D167) -----------
	#
	# Three separate things, and every one of them fails silently. A key that is never
	# PLACED leaves the sealed chests of the whole game unopenable and nothing says so; a
	# key that is placed and never CLEARED off its tile can be walked over for as many as
	# the player has patience for; and `picked_key` is the only channel the model has for
	# reporting a pickup, so if it is not set the view adds nothing and the key vanishes.
	# The one thing that cannot be asserted here is the view's half — see D167 for why the
	# addition lives there (a traversal never touches run resources).
	# Deliberately NOT asserted through the greedy walker every other block here uses.
	# Keys sit off the route on purpose, and a walker that takes the first option beelines
	# for the work and then the stair — three of the twelve dungeons finished without ever
	# standing next to one, which is the mechanic behaving correctly and would have read as
	# a broken placement. So this walks TOWARD a key on purpose, which is also the only way
	# to prove the detour is walkable at all.
	var key_floors := 0
	var key_total := 0
	var lock_total := 0
	for did5 in Balance.DUNGEONS:
		var kt := TraversalIso.new()
		kt.generate(Balance.dungeon(did5))
		var want := 0
		for n in kt.keyplan:
			want += int(n)
		key_total += want
		# --- one key per lock, per FLOOR (D172) ---
		#
		# The invariant that replaced D167's estimate. It is per floor and not per dungeon
		# because the descent is one-way: a key on floor 2 cannot open a chest on floor 1, so
		# a dungeon that balances overall can still be a dungeon whose lock had no answer.
		for f in kt.floors:
			var locks := 0
			for tier5 in kt.chestplan[f]:
				if Balance.chest_lock(String(tier5)) == Balance.CHEST_LOCK_KEY:
					locks += 1
			lock_total += locks
			if int(kt.keyplan[f]) != locks:
				fails += 1
				print("FAIL %s floor %d: %d key-locked chests and %d keys — a lock with no key is a dead end, a key with no lock is litter" % [
					did5, f + 1, locks, int(kt.keyplan[f])])
			if kt.chestplan[f].size() != _count_of(kt.plan[f], TraversalIso.Enc.TREASURE):
				fails += 1
				print("FAIL %s floor %d: %d chests planned and %d tiers rolled for them" % [
					did5, f + 1, _count_of(kt.plan[f], TraversalIso.Enc.TREASURE),
					kt.chestplan[f].size()])
		for f in kt.floors:
			if int(kt.keyplan[f]) <= 0:
				continue
			key_floors += 1
			# Lay that floor out directly. Descending to it would need a walk per floor and
			# would test the walker rather than the placement.
			kt._build_floor(f)
			var keys: Array = []
			for i in kt.enc.size():
				if int(kt.enc[i]) == TraversalIso.KEY:
					keys.append(i)
			# One key per LOCK, and since D185 a floor has two kinds: the key-locked chests
			# `keyplan` counts, and the doors shut over a pocket. Counted off the carved floor
			# rather than off the plan, because carving can run out of dead rock — a door that
			# was planned and not cut must not leave a key behind it, which is the litter half
			# of this invariant.
			var want_keys: int = int(kt.keyplan[f]) + kt._locked_mouths()
			if keys.size() != want_keys:
				fails += 1
				print("FAIL %s floor %d: %d locks (%d chests + %d doors), %d keys on the floor" % [
					did5, f + 1, want_keys, int(kt.keyplan[f]), kt._locked_mouths(),
					keys.size()])
			for kc in keys:
				# In a chamber, or the player is never shown it: a room is revealed whole
				# on entry and a corridor two tiles at a time (D167).
				if int(kt.room_of[int(kc)]) < 0:
					fails += 1
					print("FAIL %s floor %d: a key is down a corridor, where nothing reveals it" % [
						did5, f + 1])
			# ...and it has to be reachable, walking the distance field down to zero.
			var goal: int = int(keys[0])
			var walked_to := false
			var ksteps := 0
			while ksteps < 200:
				ksteps += 1
				var field := kt._dist_from(kt.pos)
				if int(field[goal]) < 0:
					fails += 1
					print("FAIL %s floor %d: the key is walled off from the entrance" % [
						did5, f + 1])
					break
				var kopts := kt.options()
				if kopts.is_empty():
					break
				var pick := -1
				var best := int(field[goal])
				for oi2 in kopts.size():
					if String(kopts[oi2].get("action", "")) == "avoid":
						continue
					var to := int(kopts[oi2]["cell"])
					var d5 := int(kt._dist_from(to)[goal])
					if d5 >= 0 and d5 < best:
						best = d5
						pick = oi2
				if pick < 0:
					break
				var target: int = int(kopts[pick]["cell"])
				var was_key: bool = int(kt.enc[target]) == TraversalIso.KEY
				var got := kt.select(pick)
				if was_key:
					if not kt.picked_key:
						fails += 1
						print("FAIL %s: stepped onto a key and the model reported nothing" % did5)
					if int(kt.enc[target]) == TraversalIso.KEY:
						fails += 1
						print("FAIL %s: the key is still on the tile it was taken from" % did5)
					walked_to = true
				elif kt.picked_key:
					fails += 1
					print("FAIL %s: a step onto bare ground reported a key" % did5)
				if not got.is_empty():
					# A chest reaching the screen must carry the tier the FLOOR was showing,
					# or the lock the player walked to is not the lock they get (D172).
					if int(got.get("type", -1)) == TraversalIso.Enc.TREASURE:
						if not (String(got.get("chest", "")) in Balance.PACK_TIERS):
							fails += 1
							print("FAIL %s: a chest resolved without the tier it was drawn with" % did5)
					kt.clear_pending()
				if walked_to:
					break
			if not walked_to:
				fails += 1
				print("FAIL %s floor %d: could not walk to a key in %d steps" % [
					did5, f + 1, ksteps])
	print("  (info: %d keys for %d locks across %d floors of %d dungeons)" % [
		key_total, lock_total, key_floors, Balance.DUNGEONS.size()])

	# --- a cast tier has to survive being written down (D140's lesson, D172's field) ---
	#
	# `chest_of` is keyed by CELL, and JSON has no integer keys: every one comes back as the
	# string "42". Restored without the conversion it is a dictionary that looks full and
	# answers nothing — every chest in a resumed run would draw and open as Worn, which is
	# the tier that unlocks itself, so a sealed chest would quietly become a free one.
	for did6 in Balance.DUNGEONS:
		var st := TraversalIso.new()
		st.generate(Balance.dungeon(did6))
		var before := {}
		for i in st.enc.size():
			if int(st.enc[i]) == TraversalIso.Enc.TREASURE:
				before[i] = st.chest_at(i % st.w, int(i / st.w))
		if before.is_empty():
			continue
		var blob = JSON.parse_string(JSON.stringify(st.save_state()))
		var back := TraversalIso.new()
		back.dungeon = Balance.dungeon(did6)
		back.load_state(blob)
		for i in before:
			var was := String(before[i])
			var now := back.chest_at(int(i) % back.w, int(int(i) / back.w))
			if was != now:
				fails += 1
				print("FAIL %s: a %s chest came back from the save as %s" % [
					did6, was if was != "" else "(none)", now if now != "" else "(none)"])

	# and depth must matter, or a flat price gets cheaper the deeper you go
	if Balance.avoid_cost(8, 0, 3) <= Balance.avoid_cost(1, 0, 3):
		fails += 1
		print("FAIL the dodge costs no more at depth 8 than at depth 1")
	# ...and so must the LENGTH of the ladder: a dungeon offering two slips has to
	# charge more per slip than one offering four, or the total drifts with the mix,
	# which is the whole of D99.
	if Balance.avoid_cost(4, 0, 2) <= Balance.avoid_cost(4, 0, 4):
		fails += 1
		print("FAIL a two-dodge dungeon charges no more per dodge than a four-dodge one")

	if fails == 0:
		print("TRAVERSAL TEST: PASS (contract holds for %d model(s): termination, one boss, equal budget, priced dodge)" % MODELS.size())
	else:
		print("TRAVERSAL TEST: FAIL (%d)" % fails)
	quit()

## Walk a whole dungeon and report what it cost (D179).
##
## Two policies out of one function on purpose. Writing the second walker separately is how
## the two drift into measuring different games — a difference in the guard, in what counts
## as an encounter, or in whether `clear_pending` is called would show up as a difference in
## the numbers and be read as a fact about the routes.
##
## `completionist` takes every OPTIONAL thing on the floor before it will use the stairs.
## Today that set is exactly the keys: they are ranked but not counted as unresolved
## business, which is what keeps them out of the required path's measurement and is
## therefore precisely what the second route is for. Anything Track B adds joins this
## function's `_optional_cells` and nothing else changes.
func _walk(iso: TraversalIso, completionist: bool) -> Dictionary:
	var moves := 0
	var encs := 0
	# Optional destinations the walker has stood on and been unable to act on.
	#
	# This is a runaway guard with a real subject rather than a fudge. Standing on a target
	# that nothing consumes is the D74 deadlock's whole shape — the field says "here", here
	# achieves nothing, and the ranking bounces the walker between two tiles for ever. It bit
	# once for a genuine generator defect (a mouth whose only approach was the stair, now
	# impossible), and a driver that can hang on the next one is a driver that reports a
	# feature as broken pacing. A target that could not be acted on when reached is dropped
	# for the rest of the floor, and the count is reported so a silent blacklist cannot hide
	# a second defect.
	var dead_ends := {}
	var stranded := 0
	var floor_now := iso.depth
	while not iso.is_complete() and moves < 600:
		var opts := iso.options()
		if opts.is_empty():
			break
		var pick := 0
		if completionist:
			var here := iso.pos
			var was_target: bool = here in _optional_cells(iso)
			pick = _completionist_pick(iso, opts, dead_ends)
			# Answering a toll is acting on the tile just as pushing is (D186); only a step
			# that did neither means the destination could not be used.
			var acted := String(opts[pick].get("action", "")) in ["push", "answer"]
			if was_target and not acted:
				dead_ends[here] = true
				stranded += 1
		moves += 1
		var got := iso.select(pick)
		if not got.is_empty():
			# Optional resolutions do not count toward the encounter denominator (D185). They
			# are not what `ISO_MOVES_PER_ENCOUNTER_MAX` is a ratio of, and counting one makes
			# the pacing look better for having more content in the way of it.
			if not bool(got.get("optional", false)):
				encs += 1
			iso.clear_pending()
		if iso.depth != floor_now:
			floor_now = iso.depth
			dead_ends = {}      # a new floor, and none of the old marks are on it
	return {"moves": moves, "encs": encs, "stranded": stranded}

## Which step a player stripping the floor takes: toward the nearest optional thing while
## any is left, and the model's own first suggestion once none is.
##
## Never a slip past — declining a fight is a different decision and it belongs to the
## dodge calibration, not to the route measurement. And never the way on while optional
## business remains: descent is one-way, so a floor left behind is a floor gone, and a
## walker that took the stairs early would be measuring the required path with extra steps.
func _completionist_pick(iso: TraversalIso, opts: Array, dead_ends: Dictionary = {}) -> int:
	# A wall you are already standing next to is the cheapest optional thing there is, so it
	# is taken before anything is walked toward. It also has to be taken EXPLICITLY: a push
	# is ranked below the stairs on purpose (D182), so a walker that only ever sorted by the
	# model's own order would never push at all and would silently be the greedy walker
	# again — which is the shape of D124, an instrument whose policy cannot hold the thing
	# being measured.
	for i in opts.size():
		# ...but never a DOOR. Neither walker models the key economy — keys are a run resource
		# and a traversal owns none (D13) — so a walker that unlocked one would be measuring a
		# route the player cannot take for free (D185). Locked pockets are therefore absent
		# from both route numbers, and their generated-equals-opened is checked structurally
		# instead of through a walk.
		if String(opts[i].get("action", "")) == "push" \
				and not bool(opts[i].get("needs_key", false)):
			return i
		# A toll IS answerable by this walker, and only with the right number (D186). That is
		# not cheating: the answer is a fact about the floor the player is standing on, and a
		# player paying attention has it too. Guessing would measure a coin flip instead of a
		# route.
		if String(opts[i].get("action", "")) == "answer" \
				and int(opts[i]["say"]) == iso.toll_answer(
					String(iso.pockets[int(opts[i]["pocket"])].get("toll", ""))):
			return i
	var targets: Array = []
	for t in _optional_cells(iso):
		if not dead_ends.has(int(t)):
			targets.append(int(t))
	if targets.is_empty():
		return 0
	# Routed the way the PLAYER can route, which means the way on is a wall to this flood.
	# `_dist_to_any` walks every walkable tile, so its shortest path to something beyond the
	# stairs runs *through* the stairs — a route the walker then refuses to take, one step at
	# a time, for ever. The oscillation is the D74 deadlock again and the cause is again a
	# field that promises a route the mover cannot use.
	var field := _dist_to_any_walkable(iso, targets)
	var best := -1
	var best_d := 1 << 30
	for i in opts.size():
		var o: Dictionary = opts[i]
		if String(o.get("action", "")) == "avoid":
			continue
		var cell := int(o["cell"])
		if iso._is_exit(cell):
			continue
		var d := int(field[cell])
		if d >= 0 and d < best_d:
			best_d = d
			best = i
	return best if best >= 0 else 0

## Steps from every tile to the nearest of `sources`, treating the way on as solid.
##
## A local flood rather than `TraversalIso._dist_to_any`, because what differs is the walker's
## POLICY — it will not step onto a stair while it still wants something on this floor — and a
## policy does not belong in the model. Descent is one-way, so for this walker the stair is a
## wall like any other.
func _dist_to_any_walkable(iso: TraversalIso, sources: Array) -> PackedInt32Array:
	var n := iso.enc.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue: Array = []
	for s in sources:
		var i := int(s)
		if i >= 0 and i < n and int(iso.enc[i]) != TraversalIso.WALL and dist[i] < 0 \
				and not iso._is_exit(i):
			dist[i] = 0
			queue.append(i)
	var head := 0
	while head < queue.size():
		var cur := int(queue[head])
		head += 1
		for raw in iso._neighbours(cur):
			var nb := int(raw)
			if int(iso.enc[nb]) == TraversalIso.WALL or dist[nb] >= 0 or iso._is_exit(nb):
				continue
			dist[nb] = dist[cur] + 1
			queue.append(nb)
	return dist

## Everything on this floor a player may take and the required path does not ask them to.
## One list, so the second walker and anything that later prices it agree on what "optional"
## means — two definitions of that is how a route measurement stops measuring the route.
func _optional_cells(iso: TraversalIso) -> Array:
	var out: Array = []
	for i in iso.enc.size():
		if int(iso.enc[i]) == TraversalIso.KEY:
			out.append(i)
		# Anything sitting in a pocket the walker has already opened (D182). It is invisible
		# to the model's own field on purpose — `_dist_to_unresolved` does not seed from a
		# pocket, which is what keeps the required path unchanged — so the optional route has
		# to seed from it here or the walker would open a pocket and walk away from it.
		elif int(iso.enc[i]) >= 0 and iso._in_pocket(i):
			out.append(i)
	# ...and the FLOOR BESIDE an unopened mouth, not the mouth itself: a mouth is rock, and
	# a flood over walkable tiles cannot route to it. Standing next to it is what makes the
	# push available.
	for p in iso.pockets:
		var pd: Dictionary = p
		if bool(pd["open"]) or String(pd.get("lock", "")) == Balance.POCKET_LOCK_KEY \
				or bool(pd.get("missed", false)):
			continue        # a door this walker will not open, or a toll it has already lost
		for n in iso._neighbours(int(pd["mouth"])):
			if int(iso.enc[n]) != TraversalIso.WALL:
				out.append(n)
	# ...and the optional things standing in the open, which need no pushing at all (D185).
	for sc in iso.sites:
		if int(iso.enc[int(sc)]) >= 0:
			out.append(int(sc))
	return out

## How many of `want` are in `row`. One line, and it exists because the same count is
## needed twice in the assertion that uses it and an inline loop in a print argument is
## how the two drift apart.
func _count_of(row: Array, want: int) -> int:
	var n := 0
	for e in row:
		if int(e) == want:
			n += 1
	return n
