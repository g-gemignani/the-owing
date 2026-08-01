## What a run actually pays in CARD COPIES, which is the currency fusion spends.
##
## Levelling needs copies of the SAME card, so total cards earned is the wrong
## number to reason about: across a 20-card dungeon pool, volume barely moves any
## single card. This tool reports the metric that decides the fusion curve —
## expected copies per run of the card you are actually trying to level — for the
## fight-reward channel and the pack channel separately.
##
##     godot --headless --script tools/pack_income.gd
extends SceneTree

const RUNS := 4000

## Packs per run, overridable so a proposed pack count can be priced before it is
## built: `--headless --script tools/pack_income.gd -- --packs=10`.
var packs_per_run: Array = []

func _init() -> void:
	packs_per_run = [Balance.PACK_ELITE, Balance.PACK_BOSS]
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--packs="):
			var n: int = maxi(1, int(String(a).split("=")[1]))
			# the extra chests are ordinary ones; elites and the boss stay one each
			packs_per_run = [Balance.PACK_ELITE, Balance.PACK_BOSS]
			for i in maxi(0, n - 2):
				packs_per_run.append(Balance.PACK_TREASURE)
	print("packs per run: %d" % packs_per_run.size())
	print("=== card income per completed run (%d runs per dungeon) ===" % RUNS)
	print("%-20s %8s %8s %8s   %s" % ["dungeon", "fights", "packs", "cards", "best single card / run"])
	var totals := {"fight": 0.0, "pack": 0.0}
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd == null:
			continue
		var counts := {}
		var fight_cards := 0
		var pack_cards := 0
		for r in RUNS:
			# fight rewards: one card per fight, from the dungeon pool
			var fights: int = 4 + randi() % 3
			for f in fights:
				var id := _roll(Balance.card_pool_for(did),
					Balance.reward_weights(Balance.Tier.NORMAL, dd.difficulty))
				if id != "":
					counts[id] = int(counts.get(id, 0)) + 1
					fight_cards += 1
			# chests: each rolls a tier, and the tier decides how many packs are in
			# it and whether the run could open it at all
			var chests: int = int(dd.encounter_mix()["treasure"])
			var kinds: Array = packs_per_run.duplicate()
			for ci in chests:
				var ctier := Balance.roll_pack_tier(Balance.PACK_TREASURE, dd.difficulty)
				# a locked chest is not always opened; a vault least of all
				var lock := Balance.chest_lock(ctier)
				if lock == Balance.CHEST_LOCK_KEY and randi() % 100 > 70:
					continue
				if lock == Balance.CHEST_LOCK_VAULT and randi() % 100 > 45:
					continue
				for pi in Balance.chest_packs(ctier):
					kinds.append(Balance.PACK_TREASURE)
			for kind in kinds:
				var tier := Balance.roll_pack_tier(kind, dd.difficulty)
				var bid := Balance.roll_pack_build(did)
				var pool: Array = Balance.pack_pool(bid, tier)
				var w: Array = Balance.pack_weights(dd.difficulty, tier)
				for i in Balance.pack_cards(tier):
					var id2 := _roll(pool, w)
					if id2 != "":
						counts[id2] = int(counts.get(id2, 0)) + 1
						pack_cards += 1
		var best_id := ""
		var best := 0
		for id in counts:
			if int(counts[id]) > best:
				best = int(counts[id]); best_id = id
		var c := Balance.card(best_id)
		print("%-20s %8.1f %8.1f %8.1f   %.2f  (%s)" % [
			dd.name, float(fight_cards) / RUNS, float(pack_cards) / RUNS,
			float(fight_cards + pack_cards) / RUNS, float(best) / RUNS,
			c.name if c != null else best_id])
		totals["fight"] += float(fight_cards) / RUNS
		totals["pack"] += float(pack_cards) / RUNS

	var n := float(Balance.DUNGEONS.size())
	print("\nmean per run: %.1f from fights, %.1f from packs" % [
		totals["fight"] / n, totals["pack"] / n])
	print("\n=== runs to level ONE card, at the best-card rate above ===")
	for lv in [5, 10, 15, 25, 40]:
		print("  level %3d: %4d copies" % [lv, Balance.copies_to_reach(lv)])
	quit()

func _roll(pool: Array, weights: Array) -> String:
	if pool.is_empty():
		return ""
	var w: Array = []
	for cid in pool:
		var c := Balance.card(cid)
		w.append(weights[clampi(c.rarity if c != null else 0, 0, weights.size() - 1)])
	return pool[Balance.weighted_pick(w)]
