## Drives the real game classes the way a player would, and reports friction.
## Not a test — a diagnostic. Run: godot --headless --script tools/playthrough.gd
extends SceneTree

var notes: Array[String] = []

func _init() -> void:
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new(); m.new_save()
	print("=== NEW GAME ===")
	print("collection: %s" % [m.collection])
	print("ropes: %d   gold: %d" % [m.item_count("escape_rope"), m.gold])

	# what can the player actually do first?
	var open: Array = []  # openable dungeon labels
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		var z := Balance.zone_of(did)
		var zone_ok: bool = m.clear_count() >= z.unlock_after_clears
		if zone_ok and m.dungeon_unlocked(d):
			open.append("%s(d%d)" % [d.name, d.difficulty])
	print("openable dungeons at start: %s" % [open])
	if open.size() < 1:
		notes.append("BLOCKER: no dungeon is openable on a fresh save")
	if open.size() == 1:
		notes.append("first choice is forced (only one dungeon open) — fine as a tutorial, but there is no decision")

	# deck building on a fresh save
	var sel := {}
	for id in m.collection: sel[id] = m.collection[id]["count"]
	print("starter deck size %d (min %d, max %d) valid=%s" % [
		m.loadout_size(sel), Balance.MIN_DECK_SIZE, Balance.MAX_DECK_SIZE, m.deck_valid(sel)])
	if m.loadout_size(sel) == Balance.MIN_DECK_SIZE:
		notes.append("starter deck is exactly the legal minimum: the deck builder offers no real choice on run 1")
	if m.fusable_levels("strike") == 0:
		notes.append("cannot fuse anything on a fresh save (needs %d copies) — fusion is invisible until several runs in" % (Balance.MIN_KEEP + 2))

	# play through dungeons in unlock order, greedily
	var clears := 0
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		var z := Balance.zone_of(did)
		if m.clear_count() < z.unlock_after_clears or not m.dungeon_unlocked(d):
			continue
		# attempt it repeatedly, as a player would, and report the rate
		var attempts := 25
		var wins := 0
		var last := {}
		for i in attempts:
			var t := _run(m, d)
			if t["result"] == "CLEARED":
				wins += 1
				last = t
		var rate := float(wins) / float(attempts) * 100.0
		print("%-18s d%-2d %-6s  cleared %3.0f%% of %d attempts" % [
			d.name, d.difficulty, _kind(d.traversal), rate, attempts])
		if rate < 25.0:
			notes.append("%s (d%d) clears only %.0f%% of attempts with the best available deck — a wall at this point in progression" % [d.name, d.difficulty, rate])
		var r := last if wins > 0 else _run(m, d)
		if wins > 0:
			m.mark_cleared(d.id)
			m.grant_relic(Balance.Tier.BOSS)
			clears += 1
			for c in r["gained"]: m.add_card(c)
			m.add_gold(int(r["gold"]))
	print()
	print("after playing everything reachable: %d clears, %d card types, %d relics, %d gold" % [
		m.clear_count(), m.collection.size(), m.relics.size(), m.gold])

	# build progress — the stated goal
	print()
	print("=== BUILD PROGRESS ===")
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if m.collection.has(c): have += 1
		var need := Balance.dungeons_required_for(b)
		var uncleared: Array = []
		for did in need:
			if not m.has_cleared(did): uncleared.append(did)
		print("%-9s %2d/%2d cards   still need: %s" % [b.id, have, b.cards.size(), uncleared])

	# reachability of the deepest content
	print()
	print("=== GATES ===")
	for z in Balance.all_zones():
		print("%-14s opens at %d clears (have %d)" % [z.name, z.unlock_after_clears, m.clear_count()])
	if m.clear_count() < 8:
		notes.append("Beyond the Stair needs 8 clears; a greedy playthrough reached %d — the last zone may be unreachable in practice" % m.clear_count())

	print()
	print("=== FRICTION NOTES ===")
	for n in notes: print(" - " + n)
	quit()

## Prefer free value, then healing when hurt, else a fight.
func _choose(opts: Array, hp: int, max_hp: int) -> int:
	var frac := float(hp) / float(maxi(1, max_hp))
	for i in opts.size():
		if int(opts[i].get("type", 0)) == Traversal.Enc.TREASURE:
			return i
	if frac < 0.65:
		for i in opts.size():
			var t := int(opts[i].get("type", 0))
			if t == Traversal.Enc.REST or t == Traversal.Enc.SHOP:
				return i
	for i in opts.size():
		if not opts[i].has("hp_cost"):
			return i
	return 0

func _kind(k: int) -> String:
	return ["map","deck","dice","iso"][k] if k < 4 else "?"

func _run(m, d: DungeonData) -> Dictionary:
	var deck: Array[CardData] = m.build_deck(_best_loadout(m))
	if deck.size() < Balance.MIN_DECK_SIZE:
		notes.append("cannot field a legal deck for %s" % d.name)
		return {"result": "NO DECK", "deck": deck.size(), "fights": 0, "hp": 0, "gained": [], "gold": 0}
	var tv := Traversal.make(d.traversal)
	tv.generate(d)
	var max_hp: int = Balance.BASE_MAX_HP + int(m.clear_count()) * Balance.HP_PER_DUNGEON \
		+ int(m.relic_bonus("bonus_max_hp"))
	var hp := max_hp
	var gained: Array = []
	var gold := 0
	var fights := 0
	var guard := 0
	var pool: Array = Balance.card_pool_for(d.id)
	while not tv.is_complete() and guard < 40:
		guard += 1
		var opts := tv.options()
		if opts.is_empty():
			notes.append("%s: ran out of options mid-run (traversal %s)" % [d.name, _kind(d.traversal)])
			break
		# route choice matters as much as card play: blindly taking the first option
		# meant never steering toward a Rest, which killed runs the simulator clears
		var pick := _choose(opts, hp, max_hp)
		# whatever the option costs is paid by the caller, because a traversal never
		# reads run resources: the deck model's dodge and the iso model's step in the
		# dark both arrive this way
		hp = maxi(1, hp - int(opts[pick].get("hp_cost", 0)))
		var node := tv.select(pick)
		if node.is_empty(): continue
		var t := int(node["type"])
		match t:
			Traversal.Enc.REST:
				hp = mini(max_hp, hp + int(max_hp * Balance.REST_HEAL_FRAC)); tv.clear_pending()
			Traversal.Enc.SHOP, Traversal.Enc.EVENT, Traversal.Enc.TREASURE:
				if t == Traversal.Enc.TREASURE: gold += 40
				tv.clear_pending()
			_:
				var tier := Balance.Tier.NORMAL
				if t == Traversal.Enc.ELITE: tier = Balance.Tier.ELITE
				elif t == Traversal.Enc.BOSS: tier = Balance.Tier.BOSS
				var e := CombatEngine.new()
				e.setup(deck, hp, max_hp, d.difficulty, tier, "", m.relic_data(),
					Array(d.enemy_roster))
				var g := 0
				while not e.over() and g < 150:
					g += 1
					_turn(e)
					if e.over(): break
					e.end_turn()
				fights += 1
				if e.lost():
					return {"result": "DIED", "deck": deck.size(), "fights": fights,
						"hp": 0, "gained": [], "gold": 0}
				hp = e.player.hp
				gold += Balance.gold_reward(d.difficulty, tier, 3)
				if not pool.is_empty(): gained.append(pool[randi() % pool.size()])
				tv.clear_pending()
	return {"result": "CLEARED" if tv.is_complete() else "STALLED",
		"deck": deck.size(), "fights": fights, "hp": hp, "gained": gained, "gold": gold}

## Reasonable player loadout: everything owned, capped at MAX_DECK_SIZE, best first.
func _best_loadout(m) -> Dictionary:
	var ids: Array = m.collection.keys()
	ids.sort_custom(func(a, b):
		var ca := load(m.CATALOG[a]) as CardData
		var cb := load(m.CATALOG[b]) as CardData
		return ca.power_value() / maxf(1.0, ca.cost) > cb.power_value() / maxf(1.0, cb.cost))
	var out := {}
	var total := 0
	for id in ids:
		if total >= Balance.MAX_DECK_SIZE: break
		var take: int = mini(int(m.collection[id]["count"]), Balance.MAX_DECK_SIZE - total)
		out[id] = take
		total += take
	return out

## Mirrors the simulator's turn policy. The first version of this harness blocked
## only at a 45% threshold and died in the first dungeon, which said nothing about
## balance and everything about the policy — a weak driver makes a diagnostic lie.
func _turn(e: CombatEngine) -> void:
	# permanent powers first: they pay off every remaining turn
	var again := true
	while again and not e.over():
		again = false
		for c in e.hand.duplicate():
			if e.can_play(c) and (c.retain_block or c.eff_strength() > 0 or c.eff_dexterity() > 0):
				e.play_card(c); again = true; break
	# cheap draw
	again = true
	while again and not e.over():
		again = false
		for c in e.hand.duplicate():
			if e.can_play(c) and c.draw > 0:
				e.play_card(c); again = true; break
	# finish it if a single card can
	for c in e.hand.duplicate():
		if e.can_play(c) and e.enemy != null \
				and e.enemy.predicted_damage(e.player.outgoing_damage(c.hit_damage())) >= e.enemy.hp:
			e.play_card(c)
			return
	# poison early: unavoidable damage, and poison-only cards are invisible to a
	# damage-per-energy ranking
	for c in e.hand.duplicate():
		if e.can_play(c) and c.eff_poison() > 0 and e.enemy != null \
				and e.enemy.poison < c.eff_poison() * 2:
			e.play_card(c); break
	# buy off the incoming hit, tolerating small chip damage
	var tolerance := 0.08 * float(e.player.max_hp)
	again = true
	while again and not e.over():
		again = false
		var incoming := e.player.predicted_damage(e.enemy.outgoing_damage(e.enemy_intent))
		if float(incoming) <= tolerance:
			break
		var best := _best(e, false)
		if best != null:
			e.play_card(best); again = true
	# spend the rest on damage
	again = true
	while again and not e.over():
		again = false
		var d := _best(e, true)
		if d != null:
			e.play_card(d); again = true

func _best(e: CombatEngine, want_damage: bool) -> CardData:
	var best: CardData = null
	var bv := 0.0
	for c in e.hand:
		if not e.can_play(c):
			continue
		var amt: int = (c.hit_damage() * maxi(1, c.hits)) if want_damage else c.eff_block()
		if amt <= 0:
			continue
		var v := float(amt) / maxf(1.0, float(c.cost))
		if v > bv:
			bv = v
			best = c
	return best
