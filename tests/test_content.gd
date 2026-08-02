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

## UI scripts reference autoloads, which are not registered in a headless
## `--script` run, so some things can only be checked as source text.
func _source_has(path: String, needle: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	return text.find(needle) != -1

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

	# --- every archetype has a plate, and adding one cannot steal another's ---
	#
	# This used to measure "sprite headroom": how many CC0 tiles were left in a shared
	# pool before the next archetype started sharing a face with an existing one. The
	# pool is gone (D89) and so is the whole failure mode — plates are keyed by
	# archetype id and generated from each archetype's own fight data, so a new `.tres`
	# gets its own and steals nobody's. What is left to check is that somebody ran the
	# generator.
	var enemies: int = PixelArt.archetype_ids().size()
	var plated := 0
	for aid in PixelArt.archetype_ids():
		if PixelArt.enemy_art(String(aid)) != null:
			plated += 1
	print("  enemy plates: %d of %d archetypes" % [plated, enemies])
	if plated < enemies:
		fails += 1
		print("FAIL %d archetype(s) have no plate — run tools/gen_enemy_art.gd, then --import" % [
			enemies - plated])
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
		ref.append(load("res://resources/cards/hack.tres"))
		ref.append(load("res://resources/cards/cover.tres"))
	var recomputed: float = Balance.deck_power(ref) / Balance.deck_cost(ref)
	if absf(recomputed - Balance.BASELINE_CARD_POWER) > 0.01:
		fails += 1
		print("FAIL BASELINE_CARD_POWER is %.3f but the reference deck now measures %.3f" % [
			Balance.BASELINE_CARD_POWER, recomputed])

	# --- the project must stay exportable to every platform we target ---
	#
	# Android and iOS can never be BUILT in CI: one needs a JDK and the Android
	# SDK, the other needs macOS, Xcode and a per-developer team ID. What can be
	# guaranteed is that nothing in the repository is what stops them. This is the
	# half that needs no export templates; tests/export_ready.sh does the rest by
	# actually attempting each export.
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		fails += 1; print("FAIL export_presets.cfg is missing or unreadable")
	else:
		var want := {"Linux": false, "Windows": false, "macOS": false,
			"Android": false, "iOS": false}
		for section in cfg.get_sections():
			if not section.ends_with(".options"):
				var nm: String = cfg.get_value(section, "name", "")
				if want.has(nm):
					want[nm] = true
		for nm2 in want:
			if not want[nm2]:
				fails += 1
				print("FAIL no export preset for %s — the platform would have to be set up from scratch" % nm2)

	# arm64 targets (macOS universal, Android, iOS) refuse to export without this
	if not bool(ProjectSettings.get_setting(
			"rendering/textures/vram_compression/import_etc2_astc", false)):
		fails += 1
		print("FAIL import_etc2_astc is off — every arm64 target refuses to export")

	# a hand of cards along the bottom of a 1280x720 layout is unusable in portrait
	var orientation := int(ProjectSettings.get_setting(
		"display/window/handheld/orientation", 0))
	if orientation == 0:
		fails += 1; print("FAIL no handheld orientation set — phones default to portrait")

	# the whole UI is Buttons; without this, touch presses nothing
	if not bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_mouse_from_touch", true)):
		fails += 1; print("FAIL touch does not emulate mouse — no button in the game responds")

	# a finger sends no hover events, so cards must be readable without one
	if not _source_has("res://scripts/ui.gd", "touch_ui"):
		fails += 1
		print("FAIL no touch path in card_button — cards would be unreadable until played")

	# --- the README's numbers are claims, and a claim nobody re-checks goes stale ---
	#
	# The front page carries a `tests-N suites` badge and a "39 suites" row, and the
	# badge is a hand-written string on shields.io — there is no service counting them
	# for us. So the count is asserted HERE, against the same globs `tests/run.sh`
	# actually runs. Add a suite and this fails until the badge is corrected, which is
	# the only mechanism that has ever kept a number in this repo honest (D141).
	var suites := 0
	var td := DirAccess.open("res://tests")
	if td == null:
		fails += 1; print("FAIL cannot open res://tests to count suites")
	else:
		td.list_dir_begin()
		var f := td.get_next()
		while f != "":
			if (f.begins_with("test_") and f.ends_with(".gd")) or f.ends_with("Test.tscn"):
				suites += 1
			f = td.get_next()
		td.list_dir_end()
		var readme := FileAccess.open("res://README.md", FileAccess.READ)
		if readme == null:
			fails += 1; print("FAIL README.md is missing")
		else:
			var text := readme.get_as_text()
			readme.close()
			# both the badge (URL-encoded) and the prose row
			for claim in ["tests-%d%%20suites" % suites, "%d suites" % suites]:
				if text.find(claim) == -1:
					fails += 1
					print("FAIL README does not say '%s' — there are %d suites now" % [
						claim, suites])

	if fails == 0:
		print("CONTENT TEST: PASS (catalogues, ids, references, art capacity, enum pins, baseline, export readiness, README counts)")
	else:
		print("CONTENT TEST: FAIL (%d)" % fails)
	quit()

func _ids_in(dir: String) -> Array:
	var out: Array = []
	for p in PixelArt.list_resources(dir, ".tres"):
		out.append(p.get_file().replace(".tres", ""))
	out.sort()
	return out
