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
				if not iso.select(0).is_empty():
					got += 1
					iso.clear_pending()
			if not iso.is_complete():
				fails += 1
				print("FAIL ISO %s: did not finish in %d moves" % [did4, moves])
			moves_total += float(moves)
			encs_total += float(maxi(1, got))

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
	for did5 in Balance.DUNGEONS:
		var kt := TraversalIso.new()
		kt.generate(Balance.dungeon(did5))
		var want := 0
		for n in kt.keyplan:
			want += int(n)
		if want <= 0:
			fails += 1
			print("FAIL %s holds chests and scatters no key at all" % did5)
			continue
		key_total += want
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
			if keys.size() != int(kt.keyplan[f]):
				fails += 1
				print("FAIL %s floor %d: %d keys planned, %d on the floor" % [
					did5, f + 1, int(kt.keyplan[f]), keys.size()])
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
					kt.clear_pending()
				if walked_to:
					break
			if not walked_to:
				fails += 1
				print("FAIL %s floor %d: could not walk to a key in %d steps" % [
					did5, f + 1, ksteps])
	print("  (info: %d keys across %d floors of %d dungeons)" % [
		key_total, key_floors, Balance.DUNGEONS.size()])

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
