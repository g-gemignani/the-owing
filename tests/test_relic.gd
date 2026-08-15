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
	# The pool no longer excludes what the character OWNS, because nothing is owned any more
	# (D238): a relic is found on a run and leaves with it. What it excludes is what the RUN
	# asking has already picked up, which the caller passes in.
	#
	# The subject is DERIVED from the pool rather than named. It was `iron_heart`, which the D244
	# content pass turned into a damage relic and pushed into a rarity the depth gate seals on a
	# fresh save — so the test failed on a relic doing exactly what it should. A test that names a
	# relic is a test that a retune can break for reasons that have nothing to do with it.
	var pool_now: Array = m.unowned_relics()
	if pool_now.is_empty():
		fails += 1; print("FAIL nothing is in the relic pool at all")
	else:
		var some: String = String(pool_now[0])
		if not (some in m.unowned_relics()):
			fails += 1; print("FAIL the pool is not stable between two reads")
		if some in m.unowned_relics([some]):
			fails += 1; print("FAIL the pool ignored the run's exclude list")

	# --- the depth gate (D223) -------------------------------------------------------
	#
	# Relics had no gate at all: every unowned relic was in the pool from the first
	# elite in the first dungeon, so the collection was a countdown from thirty that
	# emptied at a fixed rate however shallow the play. Reported as "I finished the
	# Ashen Foundry and I already have them all".
	var g = Meta.new()
	g.path_prefix = SANDBOX
	g.slot = 3
	g.new_save()
	# A fresh save can roll commons and nothing else.
	for id in g.RELIC_CATALOG:
		var r := load(g.RELIC_CATALOG[id]) as RelicData
		if r == null:
			continue
		var open: bool = not g.relic_locked(id)
		if open != (r.rarity == CardData.Rarity.COMMON):
			fails += 1
			print("FAIL at zero clears %s (rarity %d) is %s" % [
				id, r.rarity, "open" if open else "sealed"])
	for id in g.unowned_relics():
		var r2 := load(g.RELIC_CATALOG[id]) as RelicData
		if r2 != null and r2.rarity != CardData.Rarity.COMMON:
			fails += 1
			print("FAIL a fresh save can roll %s, which is rarity %d" % [id, r2.rarity])
			break

	# The gate has to be priced in a currency that can EXCEED the game. `clear_count()`
	# is distinct dungeons and stops at twelve, so a threshold past that measured
	# against it would never open for anybody — a softlock wearing a difficulty knob.
	if Balance.RELIC_UNLOCK[CardData.Rarity.LEGENDARY] <= Balance.DUNGEONS.size():
		fails += 1
		print("FAIL the last relics unlock at %d clears, which one pass of the %d dungeons reaches — they are meant to be past the end" % [
			int(Balance.RELIC_UNLOCK[CardData.Rarity.LEGENDARY]), Balance.DUNGEONS.size()])
	g.clear_counts = {}
	for did in Balance.DUNGEONS:
		g.clear_counts[did] = 1
	if g.total_clears() != Balance.DUNGEONS.size():
		fails += 1; print("FAIL total_clears counts %d for one clear of each" % g.total_clears())
	if g.clear_count() > Balance.DUNGEONS.size():
		fails += 1; print("FAIL clear_count exceeded the dungeon list")
	# ...and repeats push it past the end, which `clear_count()` cannot do.
	g.clear_counts[Balance.DUNGEONS[0]] = 9
	if g.total_clears() <= Balance.DUNGEONS.size():
		fails += 1; print("FAIL repeat clears do not raise total_clears")

	# Deep enough and every slot is open — the set must be COMPLETABLE, or the gate is
	# a wall rather than a pace.
	g.clear_counts = {}
	for did in Balance.DUNGEONS:
		g.clear_counts[did] = Balance.RELIC_UNLOCK[CardData.Rarity.LEGENDARY]
	for id in g.RELIC_CATALOG:
		if g.relic_locked(id):
			fails += 1
			print("FAIL %s is still sealed at %d clears" % [id, g.total_clears()])
			break
	if g.unowned_relics().size() != g.RELIC_CATALOG.size():
		fails += 1
		print("FAIL a deep save can roll %d of %d relics" % [
			g.unowned_relics().size(), g.RELIC_CATALOG.size()])

	# Thresholds must be non-decreasing, or a rarer relic opens before a commoner one
	# and the pyramid the screen draws stops meaning anything.
	for i in range(1, Balance.RELIC_UNLOCK.size()):
		if int(Balance.RELIC_UNLOCK[i]) < int(Balance.RELIC_UNLOCK[i - 1]):
			fails += 1
			print("FAIL rarity %d unlocks before rarity %d" % [i, i - 1])

	# A relic already OWNED is never taken away by the gate: the gate is on the roll,
	# not on the holding, so a save made before D223 keeps everything it earned.
	g.relics = []
	g.clear_counts = {}
	if not g.add_relic("keen_lens"):     # rarity 4, sealed at zero clears
		fails += 1; print("FAIL the gate blocked a relic being granted directly")
	if not g.has_relic("keen_lens"):
		fails += 1; print("FAIL a sealed relic could not be held even when awarded")
	g.writes_disabled = true

	# --- relic_bonus sums the right field, over the RUN (D238) ---
	#
	# Its subject moved with the relics: it summed the collection and now sums what the run holds.
	# Asserted through `Balance.relic_field_sum` on a hand-built array, because `relic_bonus` reaches
	# the GameState AUTOLOAD and this suite drives sandboxed instances.
	var ih := load(m.RELIC_CATALOG["iron_heart"]) as RelicData
	if Balance.relic_field_sum([ih], "bonus_max_hp") != ih.bonus_max_hp:
		fails += 1
		print("FAIL relic_field_sum wrong: %d" % Balance.relic_field_sum([ih], "bonus_max_hp"))
	# ...and that `relic_bonus` reads the run and not the collection any more, which is the half a
	# sum over an array cannot show.
	var ms := FileAccess.open("res://scripts/meta_state.gd", FileAccess.READ)
	if ms != null:
		var msrc := ms.get_as_text()
		ms.close()
		if msrc.find("func relic_bonus") != -1 and msrc.find("gs.run_relic_data()") == -1:
			fails += 1
			print("FAIL relic_bonus no longer reads the run's relics (D238)")

	# --- persistence ---
	m.save_game()
	var m2 = Meta.new()
	m2.load_game()
	if not m2.has_relic("iron_heart"):
		fails += 1; print("FAIL relics not persisted")

	# --- relics are NOT lost on death (unlike cards/gold) ---
	#
	# Asserted against `forfeit_escrow` since D235: dying no longer touches the collection at all,
	# so the only thing that could take a banked relic is the escrow settlement, and that is where
	# the claim now has to hold.
	m2.add_gold(200)
	for i in 12:
		m2.add_card("hack")
	var before: int = m2.relics.size()
	var GSr = load("res://scripts/game_state.gd")
	var gr = GSr.new()
	gr.escrow_gold = 50
	gr.run_relics = ["iron_heart"]
	gr.forfeit_escrow(1.0)
	if m2.relics.size() != before:
		fails += 1; print("FAIL a death changed the collection's relics (%d -> %d)" % [
			before, m2.relics.size()])
	# ...and the run's own relics are not salvaged by a deep death either. Half a relic is not a
	# thing, and a relic that came home would be a relic that persists (D238).
	if not gr.run_relics.is_empty() and gr.run_relics.size() != 1:
		fails += 1; print("FAIL forfeit_escrow edited the run's relics")

	# --- the depth gate still paces the pool, and every relic stays REACHABLE (D223, D238) ---
	#
	# `grant_relic` is gone: nothing adds a relic to the collection any more. What the gate governs
	# is what may ENTER the pool, and that is unchanged — so the assertion moves from "granting runs
	# dry" to "the pool grows with depth and eventually holds everything". Draining it by granting
	# was only ever a way to count it.
	var m3 = Meta.new()
	m3.path_prefix = SANDBOX
	m3.slot = 4
	m3.new_save()
	var open_now: int = m3.unowned_relics().size()
	if open_now >= m3.RELIC_CATALOG.size():
		fails += 1
		print("FAIL a fresh save can already roll every relic (%d of %d)" % [
			open_now, m3.RELIC_CATALOG.size()])
	if open_now <= 0:
		fails += 1; print("FAIL a fresh save can roll nothing at all — the gate is a wall")
	# An offer never repeats within one run, which is what the exclude list is for. A duplicate in a
	# choice of three is a choice of two wearing three buttons.
	var offered: Array = m3.relic_offer(Balance.Tier.ELITE, [], 3, [])
	if offered.size() != mini(3, open_now):
		fails += 1; print("FAIL an offer of three returned %d" % offered.size())
	var seen_ids := {}
	for oid in offered:
		if seen_ids.has(oid):
			fails += 1; print("FAIL an offer repeated %s" % oid)
		seen_ids[oid] = true
	# ...and a relic the run already holds is never offered again.
	if not offered.is_empty():
		var held := [String(offered[0])]
		for _k in 12:
			for oid2 in m3.relic_offer(Balance.Tier.ELITE, [], 3, held):
				if String(oid2) in held:
					fails += 1
					print("FAIL offered %s again although the run already holds it" % oid2)

	# ...and the same save, taken deep, opens the rest. Every relic must still be REACHABLE — a
	# gate that permanently withholds one is a broken collection, not a slower one.
	for did in Balance.DUNGEONS:
		m3.clear_counts[did] = Balance.RELIC_UNLOCK[CardData.Rarity.LEGENDARY]
	var rest: int = m3.unowned_relics().size()
	if rest != m3.RELIC_CATALOG.size():
		fails += 1
		print("FAIL a fully-cleared save can still only roll %d of %d relics" % [
			rest, m3.RELIC_CATALOG.size()])
	if m3.sealed_relics() != 0:
		fails += 1
		print("FAIL %d relics are still sealed at full depth" % m3.sealed_relics())

	# --- sealed and rollable partition the catalogue, and nothing else filters either (D247) ---
	#
	# `sealed_relics` used to skip what the character owned as well as what the depth gate held
	# back, which was a no-op once D238 emptied `relics` and the wrong question before it. Stated
	# as a sum so the two counts cannot drift: every relic is either offerable now or waiting on
	# depth, and no third state is allowed to appear.
	var m3b = Meta.new()
	m3b.path_prefix = SANDBOX
	m3b.slot = 5
	m3b.new_save()
	if m3b.sealed_relics() + m3b.unowned_relics().size() != m3b.RELIC_CATALOG.size():
		fails += 1
		print("FAIL sealed (%d) + rollable (%d) is not the whole catalogue (%d)" % [
			m3b.sealed_relics(), m3b.unowned_relics().size(), m3b.RELIC_CATALOG.size()])

	# --- no screen counts the collection's relics (D247) ---
	#
	# The bug this guards was invisible for eight decisions: D238 made relics run-scoped and left
	# `MetaState.relics` behind as an empty array that still answers `.size()`, so five screens
	# went on printing "Relics (0/30)", "Relics found: 0 / 30", "Relics 0" and "0 relic(s)" and
	# every one of them looked like working code. Grepped rather than played, because the failure
	# is a plausible number on a screen and no assertion about behaviour can see it.
	#
	# The permanent count is `relics_seen` (D235) — what the character has MET, the only part of a
	# relic that survives a run. `relics` itself stays in the file for migration, so the ban is on
	# COUNTING it, not on the name.
	var d3 := DirAccess.open("res://scripts/")
	if d3 == null:
		fails += 1; print("FAIL scripts/ is unreadable")
	else:
		for fn in d3.get_files():
			if not fn.ends_with(".gd"):
				continue
			var fh := FileAccess.open("res://scripts/" + fn, FileAccess.READ)
			if fh == null:
				continue
			var src := fh.get_as_text()
			fh.close()
			if src.find("MetaState.relics.size()") != -1:
				fails += 1
				print("FAIL scripts/%s counts MetaState.relics, which is empty since D238 — use relics_seen" % fn)

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
	# **No relic may be a bare stat line.** That was the original complaint (D40): nine flat fields,
	# every one of them "+15 max HP", so a relic changed your numbers and never how you played.
	#
	# The count of TRIGGERED relics used to carry this, at a floor of five. It no longer can. D257
	# converted eight triggered relics into rule modifiers, which is the same complaint answered a
	# better way — and the old guard read that as a regression, because it was counting one
	# particular ANSWER rather than the property. **A guard on the implementation fails when the
	# implementation improves.** So it now asks the question directly, of every relic.
	var bare_stats: Array = []
	var rule_count := 0
	for id2 in MetaState.RELIC_CATALOG:
		var r2 := load(String(MetaState.RELIC_CATALOG[id2])) as RelicData
		if r2 == null:
			continue
		if r2.breaks_a_rule():
			rule_count += 1
			continue
		# Energy and draw are not rules, but they multiply everything the deck does — which is the
		# reason `power_value` prices them apart from the flat fields. A relic doing one of those
		# is not a stat line either.
		#
		# `trigger_count() > 0` used to be a third clause HERE, and that was the tell (D262). This
		# suite knew a trigger is not a stat line while `breaks_a_rule()` did not, so four pure
		# triggers reached this branch and were waved through one line later — the definition
		# lived in two places and the two disagreed, which is what D250 moved `changes_a_rule()`
		# onto `CardData` to stop. The term is in the predicate now, so this clause is gone.
		if r2.bonus_energy > 0 or r2.extra_draw > 0:
			continue
		bare_stats.append(r2.id)
	if not bare_stats.is_empty():
		fails += 1
		print("FAIL %d relics only move a number: %s" % [bare_stats.size(), ", ".join(bare_stats)])
	# ...and rule-breakers must stay the bulk of the pool, which is what the escalation rides on
	# (D233/D243/D257). Measured at 36 of 38 once the predicate could see triggers (D262); the
	# floor is a majority. Read the number with D262's caveat: the predicate counts a single flat
	# `damage_pct` as a rule, so 36 is a ceiling on how interesting the pool is, not a reading of it.
	if rule_count * 2 <= MetaState.RELIC_CATALOG.size():
		fails += 1
		print("FAIL only %d of %d relics break a rule — a pool of numbers cannot escalate" % [
			rule_count, MetaState.RELIC_CATALOG.size()])
	if triggered < 1:
		fails += 1; print("FAIL no relic fires on a trigger — the trigger machinery has no subject")

	# --- they actually fire, at the moment they claim ---
	var Engine_ = load("res://scripts/combat_engine.gd")

	# ON_KILL: Bone Charm draws when something dies
	var e1 = Engine_.new()
	e1.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "", [load(relic_dir + "bone_charm.tres")])
	for foe in e1.enemies:
		foe.hp = 1
	e1.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 1}
	var killer := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
	killer.damage = 999
	e1.hand.append(killer)
	# Measured with the killer already in hand, so the arithmetic below is the whole
	# of it: -1 for the card played, +1 from the relic, net nothing.
	#
	# This used to take the count BEFORE the append and call the same net-zero result
	# a pass, which is the assertion written backwards — it demanded the relic draw
	# NOTHING. It passed for two reasons at once, and neither was the relic firing:
	# a redundant second `start_turn()` (setup already deals a hand) drew the 10-card
	# deck dry, so there was nothing left to draw, and it left the hand at ten, which
	# since D120 is the cap and refuses the draw on its own. Both preconditions are
	# now asserted rather than assumed, because a draw test whose pile is empty and
	# whose hand is full is a test of nothing.
	var hand_before: int = e1.hand.size()
	if e1.draw_pile.is_empty():
		fails += 1; print("FAIL nothing left in the draw pile for Bone Charm to draw")
	if hand_before >= Balance.MAX_HAND_SIZE:
		fails += 1; print("FAIL the hand is at the D120 cap (%d) before the kill — no draw could land" % hand_before)
	e1.play_card(killer)
	if e1.hand.size() != hand_before:
		fails += 1; print("FAIL Bone Charm did not draw on a kill (hand %d -> %d)" % [
			hand_before, e1.hand.size()])

	# The next two are about the ENGINE's trigger machinery, so they BUILD their relic instead of
	# loading one. They used to name Eternal Furnace and Reliquary Heart, and D257 converted both to
	# rule modifiers — which left the checks red for a reason that had nothing to do with the
	# machinery they guard, and left `ON_HP_BELOW_PCT` with no catalogue subject at all.
	#
	# A test of a mechanism should not be able to be broken by a content decision. `RelicData` is a
	# plain Resource, so the subject costs four lines and outlives every retune.

	# ON_TURN_START: fires on the 3rd turn and NOT on the 1st.
	var furnace := RelicData.new()
	furnace.id = "t_furnace"
	furnace.trigger = PackedInt32Array([RelicData.Trigger.ON_TURN_START])
	furnace.trigger_threshold = PackedInt32Array([3])
	furnace.effect = PackedInt32Array([RelicData.Effect.DAMAGE_ALL])
	furnace.effect_value = PackedInt32Array([6])
	var e2 = Engine_.new()
	e2.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "", [furnace])
	e2.start_turn()                       # turn 1: must NOT fire
	if e2.last_relic_text.strip_edges() != "":
		fails += 1; print("FAIL an every-3rd-turn relic fired on turn 1: '%s'" % e2.last_relic_text)
	e2.turn = 2
	e2.start_turn()                       # turn 3
	if e2.last_relic_text.strip_edges() == "":
		fails += 1; print("FAIL an every-3rd-turn relic did not fire on turn 3")

	# ON_HP_BELOW_PCT: fires once, not every turn thereafter.
	var heart := RelicData.new()
	heart.id = "t_heart"
	heart.trigger = PackedInt32Array([RelicData.Trigger.ON_HP_BELOW_PCT])
	heart.trigger_threshold = PackedInt32Array([50])
	heart.effect = PackedInt32Array([RelicData.Effect.GAIN_STRENGTH])
	heart.effect_value = PackedInt32Array([3])
	var e3 = Engine_.new()
	e3.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "", [heart])
	e3.start_turn()
	e3.player.hp = 10                     # well under 50%
	e3.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 1}
	e3._resolve_enemy(0)
	var after_first: int = e3.player.strength
	if after_first <= 0:
		fails += 1; print("FAIL a below-half-HP relic did not fire below half HP")
	e3._resolve_enemy(0)
	if e3.player.strength != after_first:
		fails += 1; print("FAIL a once-per-fight relic fired twice")
	# and the spent state survives a save
	var st = e3.save_state()
	var e4 = Engine_.new()
	e4.load_state(st, Meta_.CATALOG, [heart])
	if str(e4.relic_fired) != str(e3.relic_fired):
		fails += 1; print("FAIL spent relic triggers not persisted")

	fails += _check_conditional_modifiers()
	fails += _check_untaxed(relic_dir)
	fails += _simulator_reads_every_relic_field()
	fails += _simulator_plays_every_trigger_and_effect()

	if fails == 0:
		print("RELIC TEST: PASS (ownership, persistence, scaling, effects, death-safety, untaxed slot, simulator parity)")
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


## Every relic FIELD the game reads, the simulator must read too (D180).
##
## `heal_after_combat` was applied in `combat.gd` and nowhere in `sim_balance.gd`, so
## Healing Idol measured as strictly worse than no relic at all: it costs ratio points,
## which raise enemy scaling, and returned nothing against a metric that is pure
## attrition. The tool was pricing a relic it could not deliver.
##
## The subjects are DISCOVERED from `RelicData`'s own property list rather than listed
## here, because a hand-kept list of fields is guarded nowhere new — the mistake D89
## documents for the art check, and the reason that one now walks `assets/`. Add a
## field to the resource and forget the simulator, and this fails on the next run.
## The id of an enemy that always spawns more than one of itself.
##
## Discovered from the catalogue, never named: a test that names an enemy is a test a retune breaks
## for reasons that have nothing to do with it (D180, D243). "" if none exists, which the caller
## reports rather than passes.
func _swarm_archetype() -> String:
	var d := DirAccess.open(Balance.ENEMY_DIR)
	if d == null:
		return ""
	d.list_dir_begin()
	var f := d.get_next()
	var found := ""
	while f != "":
		if f.ends_with(".tres"):
			var a := load(Balance.ENEMY_DIR + f) as EnemyData
			if a != null and a.count_min >= 2:
				found = a.id
				break
		f = d.get_next()
	d.list_dir_end()
	return found

## A relic carrying exactly one field, for the checks below. Built rather than loaded, so a retune
## of the catalogue cannot change what these are measuring.
func _one_field(field: String, value) -> RelicData:
	var r := RelicData.new()
	r.id = "t_" + field
	r.set(field, value)
	return r

## The eight conditional modifiers (D257): each fires when it says, and NOT otherwise.
##
## Every one is measured as a DIFFERENCE against the same fight without the relic, so none of these
## depends on a card's damage, an enemy's HP or a difficulty constant staying where it is today.
##
## The four damage conditions additionally assert that the FACE matches the HIT. That is not
## belt-and-braces: `damage_pct` shipped applied in `card_damage` alone, so the card advertised 8 and
## dealt 6, and every test written for D50 passed because they all read the face (D233). A condition
## evaluated in one path and not the other is the same bug wearing a different field name.
func _check_conditional_modifiers() -> int:
	var fails := 0
	var Engine_ = load("res://scripts/combat_engine.gd")

	# --- the four conditional damage percents ---
	#
	# `hack` at a fixed damage, so the comparison is about the relic and nothing else.
	var setups := [
		# field, value, description, arrange(engine), should_fire
		["lone_damage_pct", 60, "one enemy left", "lone", true],
		["lone_damage_pct", 60, "two enemies left", "crowd", false],
		["wounded_damage_pct", 70, "below half HP", "hurt", true],
		["wounded_damage_pct", 70, "above half HP", "healthy", false],
		["opener_damage_pct", 90, "turn 1", "opener", true],
		["opener_damage_pct", 90, "turn 2", "later", false],
		["kill_damage_pct", 30, "after a kill", "killed", true],
		["kill_damage_pct", 30, "before any kill", "opener", false],
	]
	for s in setups:
		var field: String = String(s[0])
		var when: String = String(s[2])
		var arrange: String = String(s[3])
		var should: bool = bool(s[4])
		var plain_dmg := _staged_damage(Engine_, arrange, null)
		var with_dmg := _staged_damage(Engine_, arrange, _one_field(field, s[1]))
		if plain_dmg["face"] <= 0:
			fails += 1
			print("FAIL the staged fight for '%s' dealt no damage — this check cannot see its subject" % when)
			continue
		var fired: bool = with_dmg["face"] > plain_dmg["face"]
		if fired != should:
			fails += 1
			print("FAIL %s %s at '%s' (%d vs %d without it)" % [
				field, "did not fire" if should else "fired", when,
				with_dmg["face"], plain_dmg["face"]])
		# The face and the hit, on the same swing.
		if with_dmg["face"] != with_dmg["hit"]:
			fails += 1
			print("FAIL %s: the card face says %d and the hit lands %d at '%s' — D50 from the other side" % [
				field, with_dmg["face"], with_dmg["hit"], when])

	# --- retaliate_pct: the attacker takes a share of what it dealt ---
	for r_pct in [0, 60]:
		var er = Engine_.new()
		er.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "",
			[] if r_pct == 0 else [_one_field("retaliate_pct", r_pct)])
		er.start_turn()
		er.player.block = 0
		var foe: Combatant = er.enemies[0]
		var foe_hp_before: int = foe.hp
		er.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 20}
		er._resolve_enemy(0)
		var taken: int = foe_hp_before - foe.hp
		if r_pct == 0 and taken != 0:
			fails += 1; print("FAIL an enemy lost %d HP attacking a player with no retaliation" % taken)
		if r_pct == 60 and taken <= 0:
			fails += 1; print("FAIL retaliate_pct did not hurt the attacker")

	# --- lifesteal_pct: an attack heals a share of what it dealt ---
	for l_pct in [0, 50]:
		var el = Engine_.new()
		el.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "",
			[] if l_pct == 0 else [_one_field("lifesteal_pct", l_pct)])
		el.start_turn()
		el.player.hp = 40
		var killer2 := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		killer2.damage = 12
		el.hand.append(killer2)
		el.energy = 9
		el.play_card(killer2)
		var healed: int = el.player.hp - 40
		if l_pct == 0 and healed != 0:
			fails += 1; print("FAIL an attack healed %d with no lifesteal relic held" % healed)
		if l_pct == 50 and healed <= 0:
			fails += 1; print("FAIL lifesteal_pct healed nothing on a landed attack")

	# --- block_per_card: every card played, attack or not ---
	#
	# The card is APPENDED and is a pure attack, so it grants no Block of its own and both runs play
	# the identical card. Reading `hand[0]` instead compared two random draws and reported the
	# difference between two different cards as the relic's doing.
	var block_gained := {}
	for b in [0, 3]:
		var eb = Engine_.new()
		eb.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "",
			[] if b == 0 else [_one_field("block_per_card", b)])
		eb.player.block = 0
		eb.energy = 9
		var plain_attack := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
		plain_attack.block = 0
		eb.hand.append(plain_attack)
		eb.play_card(plain_attack)
		block_gained[b] = eb.player.block
	if int(block_gained[0]) != 0:
		fails += 1
		print("FAIL a plain attack granted %d Block with no relic held" % int(block_gained[0]))
	if int(block_gained[3]) <= 0:
		fails += 1
		print("FAIL block_per_card gave nothing on a played card")

	# --- block_heals_pct: the wall you finish the turn behind mends you ---
	for h in [0, 50]:
		var eh = Engine_.new()
		eh.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, "",
			[] if h == 0 else [_one_field("block_heals_pct", h)])
		eh.start_turn()
		eh.player.hp = 40
		eh.player.block = 20
		# Nothing may reach the player, or the heal and the hit are measured together.
		for i in eh.enemies.size():
			eh.intents[i] = {"action": EnemyData.Action.DEFEND, "value": 1}
		eh.end_turn()
		var mended: int = eh.player.hp - 40
		if h == 0 and mended != 0:
			fails += 1; print("FAIL the player healed %d at end of turn with no relic held" % mended)
		if h == 50 and mended <= 0:
			fails += 1; print("FAIL block_heals_pct mended nothing behind 20 Block")
	return fails

## Stage a fight in the named state and return what one `hack` says it will do and what it does.
##
## The arrangements are the CONDITIONS the D257 relics read, each set up the way a fight actually
## reaches it rather than by poking the field the relic tests.
func _staged_damage(Engine_, arrange: String, relic) -> Dictionary:
	var e = Engine_.new()
	# A SWARM archetype, so `lone`, `crowd` and `killed` have more than one enemy to arrange. The
	# default roll can hand back a single foe, and three of the eight arrangements cannot be built
	# on one. Discovered from the catalogue rather than named, so a retune of who swarms cannot
	# quietly reduce this to a single-enemy fight that silently passes.
	e.setup(_starter_deck(), 100, 100, 1, Balance.Tier.NORMAL, _swarm_archetype(),
		[] if relic == null else [relic])
	# NO `start_turn()` here. `setup` already calls it (combat_engine.gd:219), so the fight opens on
	# turn 1 — calling it again put every arrangement on turn 2 and made `opener_damage_pct` look
	# broken when it was the test standing in the wrong turn.
	e.energy = 9
	match arrange:
		"lone":
			# Every enemy but the first already dead.
			for i in range(1, e.enemies.size()):
				e.enemies[i].hp = 0
		"crowd":
			# Needs two alive, and a one-enemy encounter cannot show the difference.
			if e.enemies.size() < 2:
				return {"face": 0, "hit": 0}
		"hurt":
			e.player.hp = 10
		"healthy":
			e.player.hp = e.player.max_hp
		"opener":
			pass                    # setup left us on turn 1
		"later":
			e.start_turn()          # turn 2
			e.energy = 9
		"killed":
			# A real kill, so `kills_this_combat` is moved by the engine and not by the test.
			if e.enemies.size() < 2:
				return {"face": 0, "hit": 0}
			var finisher := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
			finisher.damage = 999
			finisher.aoe = false
			e.enemies[0].hp = 1
			e.hand.append(finisher)
			e.play_card(finisher)
			e.retarget()
	var probe := (load(CARD_DIR + "hack.tres") as CardData).duplicate()
	probe.damage = 10
	probe.aoe = false
	e.hand.append(probe)
	var target: Combatant = e.current_target()
	if target == null:
		return {"face": 0, "hit": 0}
	# Enough HP that the hit is never clipped by the corpse.
	target.hp = 9999
	target.block = 0
	var face: int = e.card_damage(probe)
	var before: int = target.hp
	e.play_card(probe)
	return {"face": face, "hit": before - target.hp}

func _simulator_reads_every_relic_field() -> int:
	var fails := 0
	# CODE ONLY, comments stripped — and this is not fastidiousness, it is the whole
	# assertion. The first version matched raw text and PASSED with the bug reinstated,
	# because the doc comment above the fix says "heal_after_combat" in prose. A guard
	# that a comment can satisfy is satisfied by writing about the thing instead of
	# doing it, which is the exact failure it exists to catch.
	var sim := _code_of("res://tools/sim_balance.gd")
	var engine := _code_of("res://scripts/combat_engine.gd")
	if sim == "" or engine == "":
		print("FAIL could not read the simulator or the engine"); return 1
	# Fields the ENGINE consumes need no mention in the tool: the tool hands it the
	# same relic array the game does, so anything the engine reads is already played.
	# What has to appear in the tool is the rest — the run-scoped effects, which live
	# outside any fight and which only the run loop can apply.
	# The four triggered-effect arrays are ONE mechanism, authored in parallel and read
	# together, and the engine reaches `trigger_threshold` through `threshold_at()`
	# rather than by name — so a bare text match calls it unread and reports a field the
	# engine plays on every fight. Grouped, so the group is covered when the engine
	# reads any of it. This is a real seam, not a convenience: they cannot be applied
	# separately, and `relic_data.gd` says so where it declares them.
	const TRIGGER_GROUP := ["trigger", "trigger_threshold", "effect", "effect_value"]
	var group_in_engine := false
	for g in TRIGGER_GROUP:
		if engine.find(g) != -1:
			group_in_engine = true
	var proto := RelicData.new()
	for p in proto.get_property_list():
		var name: String = String(p["name"])
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if name in ["id", "name", "description", "rarity"]:
			continue   # identity, not an effect
		if group_in_engine and name in TRIGGER_GROUP:
			continue   # played inside the fight, via threshold_at() for one of them
		if engine.find(name) != -1:
			continue   # consumed inside the fight, which the tool already runs
		if sim.find(name) == -1:
			fails += 1
			print("FAIL relic field '%s' is applied by the game but never by tools/sim_balance.gd — the simulator prices it in power_ratio and never delivers it" % name)
	return fails

## The untaxed slot: `setup`'s `p_untaxed` must deliver a relic's EFFECT while keeping its power
## out of `power_ratio` (D230). Both halves, because either one alone is a different bug that
## looks like this one working — effect with no exemption is the pillar still applying, and
## exemption with no effect is a relic that does nothing for free.
##
## It matters that this is tested at all: nothing in the GAME passes `p_untaxed` yet, so its only
## caller is `tools/sim_balance.gd --spoils=`, and an argument exercised by one tool run by hand
## is exactly the seam that rots before D226 step 3 arrives to use it.
func _check_untaxed(relic_dir: String) -> int:
	var fails := 0
	var Engine_ = load("res://scripts/combat_engine.gd")
	# A relic whose effect is visible on turn one with no dice in it, so a failure here is the slot
	# and never the roll. DISCOVERED rather than named: this was Kite Shield for its 8 start Block
	# until D244 made Kite Shield a percentage, and a percentage of the zero Block a fresh combat
	# starts with is zero — the check failed on a relic working correctly. Walk the catalogue for
	# anything that still puts a number on the board at setup.
	var shield: RelicData = null
	var dd2 := DirAccess.open(relic_dir)
	if dd2 != null:
		dd2.list_dir_begin()
		var fn := dd2.get_next()
		while fn != "":
			if fn.ends_with(".tres"):
				var cand := load(relic_dir + fn) as RelicData
				if cand != null and (cand.start_block > 0 or cand.start_strength > 0
						or cand.start_dexterity > 0):
					shield = cand
					break
			fn = dd2.get_next()
		dd2.list_dir_end()
	if shield == null:
		print("  (info: no relic puts a stat on the board at combat start; untaxed slot checked on energy)")
		return _check_untaxed_energy(relic_dir)

	var bare = Engine_.new()
	bare.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist")
	var taxed = Engine_.new()
	taxed.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist", [shield])
	var free = Engine_.new()
	free.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist", [], [], null, "", [shield])

	# 1. Owning it raises enemy scaling. If this stops being true the pillar has gone and the
	#    comparison below is measuring nothing.
	if not (taxed.ratio > bare.ratio):
		fails += 1
		print("FAIL a relic in p_relics did not raise the ratio: bare %.3f, taxed %.3f" % [
			bare.ratio, taxed.ratio])
	# 2. Being lent it does not. Exact equality: `power_ratio` is deterministic on its inputs
	#    and the two calls differ only in which argument the relic went into.
	if not is_equal_approx(free.ratio, bare.ratio):
		fails += 1
		print("FAIL p_untaxed raised the ratio: bare %.3f, untaxed %.3f (it must be free)" % [
			bare.ratio, free.ratio])
	# 3. ...and it still does its job. `start_block` is applied in `setup` from `relics`, so this
	#    is the assertion that `p_untaxed` actually joined that array.
	if free.player.block != taxed.player.block:
		fails += 1
		print("FAIL a lent relic did not apply: taxed gave %d block, untaxed gave %d" % [
			taxed.player.block, free.player.block])
	if free.player.block <= bare.player.block and free.player.strength <= bare.player.strength \
			and free.player.dexterity <= bare.player.dexterity:
		fails += 1
		print("FAIL a lent relic put nothing on the board (block %d, str %d, dex %d)" % [
			free.player.block, free.player.strength, free.player.dexterity])
	return fails

## The same three claims, checked on `bonus_energy` instead of a combat-start stat.
##
## Needed because D244 turned every flat start-of-combat relic into a percentage, and a percentage
## has nothing to multiply on turn one. Energy is the other effect `setup` applies directly, so it is
## the fallback that keeps the slot covered rather than letting the check quietly return 0.
func _check_untaxed_energy(relic_dir: String) -> int:
	var fails := 0
	var Engine_ = load("res://scripts/combat_engine.gd")
	var battery := load(relic_dir + "ancient_battery.tres") as RelicData
	if battery == null or battery.bonus_energy <= 0:
		print("FAIL no energy relic either — the untaxed slot cannot be checked")
		return 1
	var bare = Engine_.new()
	bare.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist")
	var taxed = Engine_.new()
	taxed.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist", [battery])
	var free = Engine_.new()
	free.setup(_starter_deck(), 80, 80, 1, Balance.Tier.NORMAL, "cultist", [], [], null, "", [battery])
	if not (taxed.ratio > bare.ratio):
		fails += 1
		print("FAIL a relic in p_relics did not raise the ratio: bare %.3f, taxed %.3f" % [
			bare.ratio, taxed.ratio])
	if not is_equal_approx(free.ratio, bare.ratio):
		fails += 1
		print("FAIL p_untaxed raised the ratio: bare %.3f, untaxed %.3f (it must be free)" % [
			bare.ratio, free.ratio])
	if free.energy <= bare.energy:
		fails += 1
		print("FAIL a lent energy relic gave no energy (%d, bare %d)" % [
			free.energy, bare.energy])
	return fails

## And every TRIGGER and EFFECT kind must be held by some profile (D180).
##
## The companion to the field check, and a different failure: the fields can all be
## wired while no profile in the table actually carries a relic that fires. Measured
## before this guard existed — four of the five trigger kinds never fired once in a
## full report, and `GAIN_ENERGY` was 1 in the catalogue and 0 measured, on the one
## resource the whole `power_ratio` axis is defined against.
##
## This is D124's finding in a second noun: a tool that cannot play the build cannot
## price it. Both enums are walked from `RelicData` rather than restated.
func _simulator_plays_every_trigger_and_effect() -> int:
	var fails := 0
	var sim := _read("res://tools/sim_balance.gd")
	if sim == "":
		return 1
	# The relic ids the profile table actually hands out.
	var held := {}
	var re := RegEx.new()
	re.compile('_relics\\(\\[([^\\]]*)\\]')
	for m in re.search_all(sim):
		for piece in m.get_string(1).split(","):
			var s: String = piece.strip_edges().replace('"', "").strip_edges()
			if s != "":
				held[s] = true
	var seen_trigger := {}
	var seen_effect := {}
	var have_trigger := {}
	var have_effect := {}
	var dir := DirAccess.open("res://resources/relics/")
	if dir == null:
		print("FAIL could not open the relic directory"); return 1
	dir.list_dir_begin()
	var fn := dir.get_next()
	while fn != "":
		if fn.ends_with(".tres"):
			var rid := fn.replace(".tres", "")
			var r := load("res://resources/relics/%s.tres" % rid) as RelicData
			if r != null:
				for t in r.trigger:
					have_trigger[int(t)] = true
					if held.has(rid):
						seen_trigger[int(t)] = true
				for e in r.effect:
					have_effect[int(e)] = true
					if held.has(rid):
						seen_effect[int(e)] = true
		fn = dir.get_next()
	dir.list_dir_end()
	for t in have_trigger:
		if not seen_trigger.has(t):
			fails += 1
			print("FAIL no simulator profile holds a relic that fires on %s — the trigger is priced and never measured" % (
				RelicData.Trigger.keys()[t] if t < RelicData.Trigger.keys().size() else str(t)))
	for e in have_effect:
		if not seen_effect.has(e):
			fails += 1
			print("FAIL no simulator profile holds a relic whose effect is %s — the effect is priced and never measured" % (
				RelicData.Effect.keys()[e] if e < RelicData.Effect.keys().size() else str(e)))
	return fails

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

## A file with its whole-line comments removed, so a name mentioned in prose cannot
## stand in for a name the code actually reads.
##
## Whole-line only, deliberately. Stripping trailing `# ...` would have to know whether
## the hash is inside a string literal, and getting that wrong would delete real code
## and turn this into a guard that fails for reasons that have nothing to do with
## relics. Every doc block in this project is whole-line, which is the case that matters.
func _code_of(path: String) -> String:
	var out := PackedStringArray()
	for line in _read(path).split("\n"):
		if not String(line).strip_edges().begins_with("#"):
			out.append(line)
	return "\n".join(out)
