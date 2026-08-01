## Headless test: relics (Phase 7) — ownership, persistence, scaling, effects.
## Run: godot --headless --script tests/test_relic.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_relic_"

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")
	var m = Meta.new()
	m.new_save()

	# --- every catalogued relic loads and is meaningful ---
	for id in m.RELIC_CATALOG:
		var r := load(m.RELIC_CATALOG[id]) as RelicData
		if r == null:
			fails += 1; print("FAIL relic missing: %s" % id); continue
		if r.id != id:
			fails += 1; print("FAIL relic id mismatch: %s vs %s" % [r.id, id])
		if r.power_value() <= 0.0:
			fails += 1; print("FAIL %s has no power_value (breaks enemy scaling)" % id)
		if r.description.strip_edges() == "":
			fails += 1; print("FAIL %s has no description" % id)

	# --- flat_power must exclude throughput, power_value must include it ---
	var battery := load(m.RELIC_CATALOG["ancient_battery"]) as RelicData
	if battery.flat_power() != 0.0:
		fails += 1; print("FAIL energy relic leaks into flat_power: %.1f" % battery.flat_power())
	if battery.power_value() <= 0.0:
		fails += 1; print("FAIL energy relic has no total worth")

	# --- throughput scales multiplicatively ---
	if abs(Balance.throughput_multiplier([]) - 1.0) > 0.001:
		fails += 1; print("FAIL empty throughput multiplier != 1")
	var mult: float = Balance.throughput_multiplier([battery])
	var want: float = float(Balance.MAX_ENERGY + 1) / float(Balance.MAX_ENERGY)
	if abs(mult - want) > 0.001:
		fails += 1; print("FAIL energy multiplier %.3f (expect %.3f)" % [mult, want])

	# --- relics raise the enemy scaling ratio ---
	var deck := _deck({"hack": 4, "cover": 4})
	var base_ratio: float = Balance.power_ratio(deck)
	var with_relic: float = Balance.power_ratio(deck, [battery])
	if with_relic <= base_ratio:
		fails += 1; print("FAIL relics do not raise ratio (%.2f vs %.2f)" % [with_relic, base_ratio])

	# --- ownership rules ---
	if not m.add_relic("iron_heart"):
		fails += 1; print("FAIL could not add relic")
	if m.add_relic("iron_heart"):
		fails += 1; print("FAIL duplicate relic accepted")
	if m.add_relic("not_a_relic"):
		fails += 1; print("FAIL unknown relic accepted")
	if not m.has_relic("iron_heart"):
		fails += 1; print("FAIL has_relic false after add")
	if "iron_heart" in m.unowned_relics():
		fails += 1; print("FAIL owned relic still in unowned pool")

	# --- relic_bonus sums the right field ---
	var ih := load(m.RELIC_CATALOG["iron_heart"]) as RelicData
	if m.relic_bonus("bonus_max_hp") != ih.bonus_max_hp:
		fails += 1; print("FAIL relic_bonus wrong: %d" % m.relic_bonus("bonus_max_hp"))

	# --- persistence ---
	m.save_game()
	var m2 = Meta.new()
	m2.load_game()
	if not m2.has_relic("iron_heart"):
		fails += 1; print("FAIL relics not persisted")

	# --- relics are NOT lost on death (unlike cards/gold) ---
	m2.add_gold(200)
	for i in 12:
		m2.add_card("hack")
	var before: int = m2.relics.size()
	for i in 5:
		m2.penalize_death(4)
	if m2.relics.size() != before:
		fails += 1; print("FAIL death removed relics (%d -> %d)" % [before, m2.relics.size()])

	# --- grant_relic hands out unowned relics, then runs dry ---
	var m3 = Meta.new()
	m3.new_save()
	var granted := {}
	for i in m3.RELIC_CATALOG.size():
		var got: String = m3.grant_relic(Balance.Tier.BOSS)
		if got == "":
			fails += 1; print("FAIL grant returned empty while relics remained"); break
		if granted.has(got):
			fails += 1; print("FAIL granted duplicate relic: %s" % got); break
		granted[got] = true
	if m3.grant_relic(Balance.Tier.BOSS) != "":
		fails += 1; print("FAIL granted a relic when all are owned")

	# --- engine applies relic effects ---
	var kite := load(m.RELIC_CATALOG["kite_shield"]) as RelicData
	var whet := load(m.RELIC_CATALOG["whetstone"]) as RelicData
	# DISCOVERED, not named. This line loaded "scholars_lens" by id until that relic
	# was redesigned off `extra_draw` (D95) and the assertion broke — a harness that
	# selects by name goes quiet, or falls over, the moment the name changes. Ask the
	# catalogue which relic actually grants the draw instead.
	var lens: RelicData = null
	for rid in m.RELIC_CATALOG:
		var r := load(m.RELIC_CATALOG[rid]) as RelicData
		if r != null and r.extra_draw > 0:
			lens = r
			break
	# ...and say so if nobody does. An assertion about the members of a set proves
	# nothing until something checks the set is not empty: with no draw relic in the
	# catalogue the hand-size check below would pass by having nothing to test.
	if lens == null:
		fails += 1; print("FAIL no relic grants extra_draw — the hand-size check is vacuous")
	var relics: Array = [battery, kite, whet]
	if lens != null:
		relics.append(lens)
	var eng := CombatEngine.new()
	eng.setup(deck, 60, 60, 1, Balance.Tier.NORMAL, "cultist", relics)
	if eng.energy != Balance.MAX_ENERGY + 1:
		fails += 1; print("FAIL energy relic not applied: %d" % eng.energy)
	if lens != null and eng.hand.size() != Balance.HAND_SIZE + lens.extra_draw:
		fails += 1; print("FAIL draw relic not applied: %d cards" % eng.hand.size())
	if eng.player.strength < whet.start_strength:
		fails += 1; print("FAIL start_strength not applied")
	if eng.player.block < kite.start_block:
		fails += 1; print("FAIL start_block not applied: %d" % eng.player.block)

	# start_block must re-apply next turn (block otherwise expires)
	eng.end_turn()
	if eng.player.block < kite.start_block:
		fails += 1; print("FAIL start_block not re-applied after turn: %d" % eng.player.block)

	# no relics -> baseline energy and hand
	var plain := CombatEngine.new()
	plain.setup(deck, 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	if plain.energy != Balance.MAX_ENERGY or plain.hand.size() != Balance.HAND_SIZE:
		fails += 1; print("FAIL baseline changed without relics")

	# --- triggered relics (D40) ---
	#
	# Relics were nine flat stat fields, every one of them "+15 max HP": they
	# changed your numbers, never how you played. Triggers fix that, but a trigger
	# is throughput OUTSIDE the deck, so the same trap applies as with powers —
	# unpriced, it is free strength and the difficulty ratchet stops working.
	var triggered := 0
	var relic_dir := "res://resources/relics/"
	var dd := DirAccess.open(relic_dir)
	dd.list_dir_begin()
	var rf := dd.get_next()
	var starter := _starter_deck()
	var bare: float = Balance.power_ratio(starter)
	while rf != "":
		if rf.ends_with(".tres"):
			var r := load(relic_dir + rf) as RelicData
			if r != null and r.trigger_count() > 0:
				triggered += 1
				# parallel arrays must all cover every effect, or threshold_at()
				# quietly substitutes a default and the authored value is lost
				for nm in ["trigger", "trigger_threshold", "effect", "effect_value"]:
					var arr: PackedInt32Array = r.get(nm)
					if arr.size() != r.trigger_count():
						fails += 1
						print("FAIL %s.%s has %d entries for %d effects" % [
							r.id, nm, arr.size(), r.trigger_count()])
				for i in r.trigger_count():
					if r.trigger[i] < 0 or r.trigger[i] > RelicData.Trigger.ON_BLOCK_EXPIRED:
						fails += 1; print("FAIL %s effect %d has unknown trigger" % [r.id, i])
					if r.effect[i] < 0 or r.effect[i] > RelicData.Effect.GAIN_ENERGY:
						fails += 1; print("FAIL %s effect %d has unknown effect" % [r.id, i])
					if r.trigger[i] == RelicData.Trigger.ON_TURN_START and r.threshold_at(i) <= 0:
						fails += 1; print("FAIL %s ticks every 0 turns" % r.id)
				if r.triggered_power() <= 0.0:
					fails += 1
					print("FAIL %s has triggers but prices at 0 — free strength" % r.id)
				if Balance.power_ratio(starter, [r]) <= bare:
					fails += 1
					print("FAIL %s does not raise the scaling ratio" % r.id)
				# ...and no single relic may dwarf the deck it supplements
				if Balance.power_ratio(starter, [r]) > bare * 1.6:
					fails += 1
					print("FAIL %s dominates: ratio %.2f vs %.2f" % [
						r.id, Balance.power_ratio(starter, [r]), bare])
		rf = dd.get_next()
	dd.list_dir_end()
	if triggered < 5:
		fails += 1; print("FAIL only %d relics do anything conditional" % triggered)

	# --- they actually fire, at the moment they claim ---
	var Engine_ = load("res://scripts/combat_engine.gd")

	# ON_KILL: Bone Charm draws when something dies
	var e1 = Engine_.new()
	e1.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "", [load(relic_dir + "bone_charm.tres")])
	e1.start_turn()
	var hand_before: int = e1.hand.size()
	for foe in e1.enemies:
		foe.hp = 1
	e1.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 1}
	var killer := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
	killer.damage = 999
	e1.hand.append(killer)
	e1.play_card(killer)
	if e1.hand.size() != hand_before:   # -1 for the card played, +1 from the relic
		fails += 1; print("FAIL Bone Charm did not draw on a kill (hand %d -> %d)" % [
			hand_before, e1.hand.size()])

	# ON_TURN_START: Eternal Furnace hits everything every 3rd turn, and only then
	var e2 = Engine_.new()
	e2.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "",
		[load(relic_dir + "eternal_furnace.tres")])
	e2.start_turn()                       # turn 1: must NOT fire
	if e2.last_relic_text.find("to all") != -1:
		fails += 1; print("FAIL Eternal Furnace fired on turn 1")
	e2.turn = 2
	e2.start_turn()                       # turn 3
	if e2.last_relic_text.find("to all") == -1:
		fails += 1; print("FAIL Eternal Furnace did not fire on turn 3: '%s'" % e2.last_relic_text)

	# ON_HP_BELOW_PCT: Reliquary Heart fires once, not every turn thereafter
	var e3 = Engine_.new()
	e3.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "",
		[load(relic_dir + "reliquary_heart.tres")])
	e3.start_turn()
	e3.player.hp = 10                     # well under 50%
	e3.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 1}
	e3._resolve_enemy(0)
	var after_first: int = e3.player.strength
	if after_first <= 0:
		fails += 1; print("FAIL Reliquary Heart did not fire below half HP")
	e3._resolve_enemy(0)
	if e3.player.strength != after_first:
		fails += 1; print("FAIL a once-per-fight relic fired twice")
	# and the spent state survives a save
	var st = e3.save_state()
	var e4 = Engine_.new()
	e4.load_state(st, Meta_.CATALOG, [load(relic_dir + "reliquary_heart.tres")])
	if str(e4.relic_fired) != str(e3.relic_fired):
		fails += 1; print("FAIL spent relic triggers not persisted")

	if fails == 0:
		print("RELIC TEST: PASS (ownership, persistence, scaling, effects, death-safety)")
	else:
		print("RELIC TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

func _deck(loadout: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			deck.append((load(CARD_DIR + id + ".tres") as CardData).duplicate())
	return deck

## Remove this test's sandboxed files so a test run leaves no residue in the
## player's data directory.
func _cleanup_sandbox() -> void:
	# stop any surviving instance from re-writing what we are about to delete
	load("res://scripts/meta_state.gd").writes_disabled = true
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))


func _starter_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 5:
		deck.append((load(CARD_DIR + "hack.tres") as CardData).duplicate())
		deck.append((load(CARD_DIR + "cover.tres") as CardData).duplicate())
	return deck
