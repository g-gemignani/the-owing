## Headless test: the content pipeline itself, so the game can be expanded safely.
##
## Adding a card, an enemy or a dungeon touches a `.tres` file AND a hand-written
## catalogue in GDScript. Nothing used to check the two agreed, so a forgotten
## catalogue line meant a finished piece of content silently did not exist, and a
## typo'd id meant a dungeon quietly referenced nothing. Neither shows up as an
## error — the game just has less in it than you think.
##
## This suite exists so that expansion fails loudly. Everything it checks is a
## thing that has ALREADY gone wrong once in this project.
## Run: godot --headless --script tests/test_content.gd
extends SceneTree

## Below this many spare sprites, the next enemy added silently shares a face
## with an existing one.
const SPRITE_HEADROOM_MIN := 3

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()

	# --- catalogues must match what is on disk, in BOTH directions ---
	#
	# An orphan is finished content nobody can reach; a ghost is a catalogue entry
	# whose file was renamed or deleted, which fails at load with no clue why.
	for spec in [
			["cards", "res://resources/cards/", m.CATALOG.keys()],
			["relics", "res://resources/relics/", m.RELIC_CATALOG.keys()],
			["powers", "res://resources/powers/", Balance.POWERS],
			["dungeons", "res://resources/dungeons/", Balance.DUNGEONS],
			["zones", "res://resources/zones/", Balance.ZONES],
			["builds", "res://resources/builds/", Balance.BUILDS]]:
		var label: String = spec[0]
		var on_disk := _ids_in(spec[1])
		var catalogued := {}
		for id in spec[2]:
			catalogued[id] = true
		for id in on_disk:
			if not catalogued.has(id):
				fails += 1
				print("FAIL %s/%s.tres exists but is in no catalogue — unreachable content" % [
					label, id])
		for id in catalogued:
			if not (id in on_disk):
				fails += 1
				print("FAIL %s catalogue names '%s', which has no file" % [label, id])

	# --- every id inside a resource matches its filename ---
	# A mismatch makes lookups miss in one direction only, which is the worst kind.
	for id in _ids_in("res://resources/cards/"):
		var c := load("res://resources/cards/%s.tres" % id) as CardData
		if c != null and c.id != id:
			fails += 1; print("FAIL card file '%s' declares id '%s'" % [id, c.id])
	for id in _ids_in("res://resources/enemies/"):
		var e := load("res://resources/enemies/%s.tres" % id) as EnemyData
		if e != null and e.id != id:
			fails += 1; print("FAIL enemy file '%s' declares id '%s'" % [id, e.id])

	# --- cross-references are plain strings and fail silently when wrong ---
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		for cid in Array(d.card_pool) + Array(d.exclusive_cards):
			if not m.CATALOG.has(cid):
				fails += 1; print("FAIL dungeon %s references missing card '%s'" % [did, cid])
		var foes: Array = Array(d.enemy_roster)
		if d.boss != "":
			foes.append(d.boss)
		for eid in foes:
			if not ResourceLoader.exists(Balance.ENEMY_DIR + eid + ".tres"):
				fails += 1; print("FAIL dungeon %s references missing enemy '%s'" % [did, eid])
	for zid in Balance.ZONES:
		var z := Balance.zone(zid)
		if z == null:
			continue
		for did2 in Array(z.dungeons):
			if not (did2 in Balance.DUNGEONS):
				fails += 1; print("FAIL zone %s references missing dungeon '%s'" % [zid, did2])
	for bid in Balance.BUILDS:
		var b := Balance.build(bid)
		if b == null:
			continue
		for cid2 in Array(b.cards):
			if not m.CATALOG.has(cid2):
				fails += 1; print("FAIL build %s references missing card '%s'" % [bid, cid2])
	# every dungeon must belong to exactly one zone, or it is unreachable in the UI
	var placed := {}
	for zid2 in Balance.ZONES:
		var z2 := Balance.zone(zid2)
		if z2 == null:
			continue
		for did3 in Array(z2.dungeons):
			if placed.has(did3):
				fails += 1; print("FAIL dungeon %s is in two zones" % did3)
			placed[did3] = zid2
	for did4 in Balance.DUNGEONS:
		if not placed.has(did4):
			fails += 1; print("FAIL dungeon %s belongs to no zone — unreachable" % did4)

	# --- art capacity: the next enemy must not silently share a face ---
	var enemies: int = PixelArt.archetype_ids().size()
	var sprites: int = PixelArt.enemy_sprites().size()
	var pinned: int = PixelArt.OVERRIDES.size()
	var headroom: int = (sprites - pinned) - (enemies - pinned)
	print("  sprite headroom: %d (%d archetypes, %d sprites, %d pinned)" % [
		headroom, enemies, sprites, pinned])
	if headroom < SPRITE_HEADROOM_MIN:
		fails += 1
		print("FAIL only %d spare enemy sprites — add art before adding archetypes" % headroom)
	var card_headroom: int = PixelArt.CARD_TILES.size() - m.CATALOG.size()
	print("  card art headroom: %d" % card_headroom)
	if card_headroom < 0:
		fails += 1; print("FAIL more cards than card illustrations")

	# --- enum ordinals are PERSISTED, so they may only ever be appended to ---
	#
	# Enemy patterns store these as raw ints in .tres, and spent relic triggers go
	# into save files. Inserting a value silently rewrites every existing enemy and
	# every save. Pinned here so a reorder fails a test instead of shipping.
	for pin in [["EnemyData.Action.ATTACK", EnemyData.Action.ATTACK, 0],
			["EnemyData.Action.SUNDER", EnemyData.Action.SUNDER, 5],
			["EnemyData.Action.DRAIN", EnemyData.Action.DRAIN, 7],
			["EnemyData.Trigger.SELF_HP_BELOW_PCT", EnemyData.Trigger.SELF_HP_BELOW_PCT, 0],
			["EnemyData.Trigger.EVERY_N_TURNS", EnemyData.Trigger.EVERY_N_TURNS, 4],
			["RelicData.Trigger.ON_KILL", RelicData.Trigger.ON_KILL, 0],
			["RelicData.Trigger.ON_BLOCK_EXPIRED", RelicData.Trigger.ON_BLOCK_EXPIRED, 4],
			["RelicData.Effect.DAMAGE_ALL", RelicData.Effect.DAMAGE_ALL, 0],
			["RelicData.Effect.GAIN_ENERGY", RelicData.Effect.GAIN_ENERGY, 5],
			["CardData.Rarity.LEGENDARY", CardData.Rarity.LEGENDARY, 4]]:
		if int(pin[1]) != int(pin[2]):
			fails += 1
			print("FAIL %s is now %d, was %d — existing .tres and saves refer to the old number" % [
				pin[0], int(pin[1]), int(pin[2])])

	# --- a hand-computed constant that silently rots ---
	#
	# BASELINE_CARD_POWER is the reference deck's power per energy, written out by
	# hand. Every scaling number in the game is relative to it, so if card pricing
	# changes and this is not recomputed, the whole curve drifts with no error.
	var ref: Array = []
	for i in 4:
		ref.append(load("res://resources/cards/strike.tres"))
		ref.append(load("res://resources/cards/defend.tres"))
	var recomputed: float = Balance.deck_power(ref) / Balance.deck_cost(ref)
	if absf(recomputed - Balance.BASELINE_CARD_POWER) > 0.01:
		fails += 1
		print("FAIL BASELINE_CARD_POWER is %.3f but the reference deck now measures %.3f" % [
			Balance.BASELINE_CARD_POWER, recomputed])

	if fails == 0:
		print("CONTENT TEST: PASS (catalogues, ids, references, art capacity, enum pins, baseline)")
	else:
		print("CONTENT TEST: FAIL (%d)" % fails)
	quit()

func _ids_in(dir: String) -> Array:
	var out: Array = []
	for p in PixelArt.list_resources(dir, ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	return out
