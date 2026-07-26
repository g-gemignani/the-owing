## Headless test: dungeon identity (D6) — definitions, unlocks, exclusive pools,
## roster overrides, difficulty-tilted loot.
## Run: godot --headless --script tests/test_dungeon.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new()
	m.new_save()

	# --- every registered dungeon loads and is coherent ---
	var seen_pool := {}
	var difficulties: Array = []
	for id in Balance.DUNGEONS:
		var d := Balance.dungeon(id)
		if d == null:
			fails += 1; print("FAIL dungeon missing: %s" % id); continue
		if d.id != id:
			fails += 1; print("FAIL dungeon id mismatch: %s vs %s" % [d.id, id])
		if d.difficulty < 1:
			fails += 1; print("FAIL %s bad difficulty" % id)
		if d.name.strip_edges() == "" or d.description.strip_edges() == "":
			fails += 1; print("FAIL %s missing name/description" % id)
		difficulties.append(d.difficulty)
		# rosters must reference real archetypes
		for a in d.enemy_roster:
			if load(Balance.ENEMY_DIR + a + ".tres") == null:
				fails += 1; print("FAIL %s references unknown enemy %s" % [id, a])
		# pools must reference real cards. Count against the UNION pool (zone theme
		# + dungeon extras), since that is what can actually drop there.
		for c in d.card_pool:
			if not m.CATALOG.has(c):
				fails += 1; print("FAIL %s references unknown card %s" % [id, c])
		for c in Balance.card_pool_for(id):
			seen_pool[c] = int(seen_pool.get(c, 0)) + 1
		# exclusives must be in this dungeon's own pool
		for c in d.exclusive_cards:
			if not (c in d.card_pool):
				fails += 1; print("FAIL %s claims exclusive %s not in its pool" % [id, c])

	# --- difficulty rises across the registry (it is an ordered progression) ---
	for i in range(1, difficulties.size()):
		if int(difficulties[i]) < int(difficulties[i - 1]):
			fails += 1; print("FAIL dungeon difficulty not ascending at %d" % i)

	# --- every dungeon belongs to exactly one zone ---
	for id in Balance.DUNGEONS:
		var owners := 0
		for z in Balance.all_zones():
			if id in z.dungeons:
				owners += 1
		if owners != 1:
			fails += 1; print("FAIL dungeon %s belongs to %d zones (expect 1)" % [id, owners])
	# --- and every zone lists only real dungeons ---
	for z in Balance.all_zones():
		if z.dungeons.is_empty():
			fails += 1; print("FAIL zone %s has no dungeons" % z.id)
		for did in z.dungeons:
			if not (did in Balance.DUNGEONS):
				fails += 1; print("FAIL zone %s lists unknown dungeon %s" % [z.id, did])
		for cid in z.card_pool:
			if not m.CATALOG.has(cid):
				fails += 1; print("FAIL zone %s references unknown card %s" % [z.id, cid])
	# --- zone unlocks must be reachable in order ---
	var zprev := -1
	for z in Balance.all_zones():
		if z.unlock_after_clears < zprev:
			fails += 1; print("FAIL zone unlocks not ascending at %s" % z.id)
		zprev = z.unlock_after_clears
		if z.unlock_after_clears > Balance.DUNGEONS.size():
			fails += 1; print("FAIL zone %s can never unlock" % z.id)

	# --- an "exclusive" card must really appear in exactly one pool ---
	for id in Balance.DUNGEONS:
		var d := Balance.dungeon(id)
		for c in d.exclusive_cards:
			if int(seen_pool.get(c, 0)) != 1:
				fails += 1; print("FAIL %s is not exclusive: in %d pools" % [c, seen_pool.get(c, 0)])

	# --- every card in the game should be obtainable somewhere ---
	for cid in m.CATALOG:
		if not seen_pool.has(cid):
			print("  WARN card %s is in no dungeon pool (unobtainable)" % cid)

	# --- unlocks gate on clears ---
	var first := Balance.dungeon(Balance.DUNGEONS[0])
	if not m.dungeon_unlocked(first):
		fails += 1; print("FAIL first dungeon locked on a fresh save")
	var gated: DungeonData = null
	for id in Balance.DUNGEONS:
		var d := Balance.dungeon(id)
		if d.unlock_after_clears > 0:
			gated = d
			break
	if gated == null:
		fails += 1; print("FAIL no dungeon is gated at all")
	else:
		if m.dungeon_unlocked(gated):
			fails += 1; print("FAIL gated dungeon unlocked with 0 clears")
		for i in gated.unlock_after_clears:
			m.mark_cleared(Balance.DUNGEONS[i])
		if not m.dungeon_unlocked(gated):
			fails += 1; print("FAIL gated dungeon still locked after %d clears" % gated.unlock_after_clears)

	# --- clears are persistent and deduplicated ---
	var n: int = m.clear_count()
	m.mark_cleared(Balance.DUNGEONS[0])   # already cleared
	if m.clear_count() != n:
		fails += 1; print("FAIL duplicate clear counted")
	m.save_game()
	var m2 = Meta.new()
	m2.load_game()
	if m2.clear_count() != n:
		fails += 1; print("FAIL clears not persisted (%d vs %d)" % [m2.clear_count(), n])

	# --- loot tilts toward rarer cards as difficulty rises ---
	for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
		var easy: Array = Balance.reward_weights(tier, 1)
		var hard: Array = Balance.reward_weights(tier, 6)
		var easy_share := float(easy[4]) / float(_sum(easy))
		var hard_share := float(hard[4]) / float(_sum(hard))
		if hard_share <= easy_share:
			fails += 1; print("FAIL tier %d: legendary share does not rise with difficulty" % tier)
		# commons must still exist — the tilt shifts, it does not replace
		if hard[0] <= 0:
			fails += 1; print("FAIL tier %d: commons eliminated at high difficulty" % tier)
	# boss in the hardest dungeon should be a genuinely good chance at epic+
	var boss_hard: Array = Balance.reward_weights(Balance.Tier.BOSS, 6)
	var top_share := float(int(boss_hard[3]) + int(boss_hard[4])) / float(_sum(boss_hard))
	if top_share < 0.2:
		fails += 1; print("FAIL deep boss epic+legendary share only %.0f%%" % (top_share * 100))

	# --- a dungeon's roster actually drives who spawns ---
	var d_crypt := Balance.dungeon("crypt")
	var deck := _deck({"strike": 4, "defend": 4})
	var allowed := Array(d_crypt.enemy_roster)
	for t in 40:
		var eng := CombatEngine.new()
		eng.setup(deck, 60, 60, d_crypt.difficulty, Balance.Tier.NORMAL, "", [], allowed)
		var who: String = eng.archetypes[0].id
		if not (who in allowed):
			fails += 1; print("FAIL spawned %s outside the dungeon roster" % who); break

	# --- roster threat must stay in a band ---
	#
	# Difficulty already scales enemy HP and damage, so roster threat is a
	# multiplier on top and does NOT need to rise with difficulty. What it must not
	# do is swing far enough to override the difficulty rating — that produced a
	# difficulty-3 dungeon harder than a 6, and a first dungeon harder than the two
	# after it. So: bound the band, and keep the opening dungeon gentle.
	var threats: Array = []
	for did in Balance.DUNGEONS:
		var t: float = Balance.roster_threat(did)
		threats.append(t)
		if t < 0.9 or t > 1.9:
			fails += 1; print("FAIL %s roster threat %.2f outside the sane band" % [did, t])
	var lo := 99.0
	var hi := 0.0
	var sum := 0.0
	for t in threats:
		lo = minf(lo, t)
		hi = maxf(hi, t)
		sum += t
	var mean := sum / float(maxi(1, threats.size()))
	if hi / maxf(0.1, lo) > 1.6:
		fails += 1; print("FAIL threat spread %.2f-%.2f is too wide (roster overrides difficulty)" % [lo, hi])
	# the first dungeon is the tutorial: it must not be above average threat
	var first_threat: float = Balance.roster_threat(Balance.DUNGEONS[0])
	if first_threat > mean:
		fails += 1
		print("FAIL first dungeon threat %.2f is above the average %.2f — the opening is not the gentlest" % [
			first_threat, mean])
	print("  (info: roster threat %.2f-%.2f, mean %.2f, first dungeon %.2f)" % [
		lo, hi, mean, first_threat])

	if fails == 0:
		print("DUNGEON TEST: PASS (definitions, unlocks, exclusives, rosters, loot tilt)")
	else:
		print("DUNGEON TEST: FAIL (%d)" % fails)
	quit()

func _sum(a: Array) -> int:
	var t := 0
	for v in a:
		t += int(v)
	return t

func _deck(loadout: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			deck.append((load(CARD_DIR + id + ".tres") as CardData).duplicate())
	return deck
