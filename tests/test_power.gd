## Headless test: player Powers (D37) — once-per-turn abilities bought with gold.
##
## Guards the two traps this system exists to avoid:
##   * a power is throughput OUTSIDE the deck, so it must raise enemy scaling or it
##     is free strength and the difficulty ratchet stops working;
##   * it must fire ONCE per turn, or "power, power, power" becomes a legal turn and
##     draw stops mattering.
## Run: godot --headless --script tests/test_power.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_power_"

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0

	# --- every catalogued power loads and is coherent ---
	for id in Balance.POWERS:
		var p := Balance.power(id)
		if p == null:
			fails += 1; print("FAIL power %s does not load" % id); continue
		if p.id != id:
			fails += 1; print("FAIL power %s has id %s" % [id, p.id])
		if p.cost < 0 or p.cost > Balance.MAX_ENERGY:
			fails += 1; print("FAIL power %s costs %d of %d energy" % [id, p.cost, Balance.MAX_ENERGY])
		if p.description.strip_edges() == "":
			fails += 1; print("FAIL power %s has no description" % id)
		if p.power_value() <= 0.0:
			fails += 1; print("FAIL power %s prices at zero — it would be free strength" % id)
		if p.level_capped() < 2:
			fails += 1; print("FAIL power %s cannot be levelled" % id)

	# --- the offer is one per DUNGEON, and re-opening the deck builder cannot re-deal it (D252) ---
	#
	# Neither half of the D252 bug was visible to this suite, and both were real: the offer was rolled
	# by the deck-builder SCREEN, which is reachable from the overworld, the pause menu and the crawl,
	# so walking out and back in dealt three new powers. An offer you can re-draw is a choice of all
	# of them with extra steps.
	#
	# Split deliberately between BEHAVIOUR and WIRING. `power_offer` is asserted for real; where it is
	# rolled from cannot be, because `select_dungeon` reaches meta through
	# `get_node_or_null("/root/MetaState")` and a `--script` run has no autoloads — building the two
	# nodes needs `call_deferred` and a frame, which this suite's `_init` cannot await. So the wiring
	# is read off the source, the way `test_relic.gd` and `test_death.gd` already do.
	var m4 = Meta_.new()
	m4.path_prefix = SANDBOX
	m4.slot = 6
	m4.new_save()
	var offer: Array = m4.power_offer(3)
	var open_ids: Array = []
	for pid2 in Balance.POWERS:
		if m4.power_available(String(pid2)):
			open_ids.append(String(pid2))
	if offer.size() != mini(3, open_ids.size()):
		fails += 1
		print("FAIL a fresh save offered %d powers of %d open" % [offer.size(), open_ids.size()])
	var dupes := {}
	for pid3 in offer:
		if dupes.has(pid3):
			fails += 1; print("FAIL the offer repeated %s" % pid3)
		dupes[pid3] = true
		if not (String(pid3) in open_ids):
			fails += 1; print("FAIL offered %s, which this save's depth has not opened" % pid3)

	# --- the offer is weighted by the DECK it will be carried with (D256) ---
	#
	# Flat, three powers were drawn with no reference to the twenty cards the player had just
	# committed to, so a pure-Block deck was as likely to be handed an attack lens as a defensive one.
	# The tilt is `relic_offer`'s (D234), pointed at `Balance.power_affinity`.
	#
	# Measured on the DRAW and not on the affinity function, deliberately. D254 shipped two guards
	# that passed with their subject deleted, and a check that `power_affinity` returns a sensible
	# number is exactly that shape: it can be perfect while `power_offer` never calls it. So the two
	# decks are dealt real offers and the offers are counted.
	#
	# The two decks and the two poles are DISCOVERED, never named. A test that names a card is a test
	# a retune breaks for reasons that have nothing to do with it (D180, D243).
	var m5 = Meta_.new()
	m5.path_prefix = SANDBOX
	m5.slot = 8
	m5.new_save()
	# Every power open, so the pool holds both poles. A fresh save has cleared nothing and sees only
	# commons, and a pool with no defensive power in it cannot show a tilt either way.
	m5.cleared_dungeons = Balance.DUNGEONS.duplicate()

	var pure_atk: CardData = null
	var pure_def: CardData = null
	for f in (DirAccess.get_files_at(CARD_DIR) if DirAccess.dir_exists_absolute(CARD_DIR) else []):
		if not String(f).ends_with(".tres"):
			continue
		var c := load(CARD_DIR + String(f)) as CardData
		if c == null:
			continue
		var cl := Balance.deck_lean([c])
		if float(cl["attack"]) > 0.8 and pure_atk == null:
			pure_atk = c
		if float(cl["defence"]) > 0.8 and pure_def == null:
			pure_def = c
	if pure_atk == null or pure_def == null:
		fails += 1
		print("FAIL the catalogue no longer holds a card that is >80%% attack and one >80%% defence — this check has stopped being able to build two opposed decks")
	else:
		var atk_deck: Array = []
		var def_deck: Array = []
		for _i in 12:
			atk_deck.append(pure_atk)
			def_deck.append(pure_def)
		# Which of the powers lean which way, by the same function the draw uses — and read off
		# `m5`, whose gates are open, NOT off `open_ids`, which belongs to the fresh save above and
		# holds four commons. Classifying against the wrong save leaves most of what is dealt
		# uncounted, so the tilt shows up at a fraction of its size and the guard nearly misses it.
		var atk_powers := {}
		var def_powers := {}
		for pid5 in Balance.POWERS:
			if not m5.power_available(String(pid5)):
				continue
			var pw := Balance.power(String(pid5))
			var pl := Balance.deck_lean([pw])
			var a := float(pl["attack"])
			var d := float(pl["defence"])
			if a + d <= 0.0:
				continue        # neutral — draw, energy, status. Keeps its base weight by design.
			if a > d:
				atk_powers[String(pid5)] = true
			else:
				def_powers[String(pid5)] = true
		if atk_powers.is_empty() or def_powers.is_empty():
			fails += 1
			print("FAIL the power set holds %d attack-leaning and %d defence-leaning powers — a tilt cannot be measured against a pool with one pole" % [
				atk_powers.size(), def_powers.size()])
		else:
			# Counted over many deals rather than one. The tilt is AFFINITY_TILT = 1.5, which makes a
			# matched power about twice as likely as a mismatched one — a nudge, so one offer of three
			# proves nothing and is not asked to.
			const DEALS := 400
			var atk_seen := 0     # attack-leaning powers dealt to the attack deck
			var def_seen := 0     # attack-leaning powers dealt to the block deck
			for _d in DEALS:
				for oid in m5.power_offer(3, atk_deck):
					if atk_powers.has(String(oid)):
						atk_seen += 1
				for oid2 in m5.power_offer(3, def_deck):
					if atk_powers.has(String(oid2)):
						def_seen += 1
			# A MARGIN and not a bare `>`. Measured at 1.9x over five runs (806/418, 775/404, 800/408,
			# 766/402, 771/390) against 105/132 with the weighting cut out, so 1.3 sits clear of the
			# noise at one end and well under the effect at the other — and a tilt quietly weakened to
			# a fifth of its size still fails here, which a bare `>` would let through.
			if float(atk_seen) < float(def_seen) * 1.3:
				fails += 1
				print("FAIL over %d deals the attack deck was offered %d attack powers and the block deck %d — the offer is not reading the deck" % [
					DEALS, atk_seen, def_seen])
			# ...and it stays a NUDGE. A hard filter would hand a block deck nothing but Block and
			# turn a choice of three into a choice of one, which is the failure `relic_affinity`'s
			# own comment names. Both poles must still be reachable from both decks.
			if def_seen == 0:
				fails += 1
				print("FAIL the block deck was offered no attack power in %d deals — the tilt has become a filter" % DEALS)
		# The flat draw survives, because every tool and six suites call `power_offer(3)` with no
		# deck and must keep getting an unweighted one.
		var flat: Array = m5.power_offer(3)
		if flat.size() != 3:
			fails += 1
			print("FAIL a deckless offer returned %d powers — the no-deck path is what the tools use" % flat.size())

	# WIRING: rolled by the run, displayed by the screen, never the other way round — and carried
	# through the save, so a resumed run remembers what it was dealt. All four are read off the
	# source, because none is reachable from a bare instance: `select_dungeon` needs the autoload
	# lookup and `run_to_dict` returns {} without a traversal.
	var gsrc := FileAccess.open("res://scripts/game_state.gd", FileAccess.READ)
	if gsrc != null:
		var gtxt := gsrc.get_as_text()
		gsrc.close()
		# Rolled by `enter_dungeon` and NOT by `select_dungeon` (D256): the offer is weighted by the
		# deck, and `select_dungeon` runs a screen before the deck exists. Both halves are asserted,
		# because rolling in the earlier place would still pass a test that only looked at the later
		# one — and a run must not be dealt two offers.
		var ent := gtxt.find("func enter_dungeon")
		var entn := gtxt.find("\nfunc ", ent + 10)
		if gtxt.substr(ent, maxi(0, entn - ent)).find("power_offer = meta.power_offer") == -1:
			fails += 1
			print("FAIL enter_dungeon does not roll the power offer — it is the only seam that has the deck (D256)")
		var sel := gtxt.find("func select_dungeon")
		var nxt := gtxt.find("\nfunc ", sel + 10)
		var body := gtxt.substr(sel, maxi(0, nxt - sel))
		if body.find("meta.power_offer") != -1:
			fails += 1
			print("FAIL select_dungeon rolls the power offer — that is before the deck is chosen (D256)")
		if body.find("power_offer = []") == -1:
			fails += 1
			print("FAIL select_dungeon does not clear the power offer — swapping dungeons would carry the last one's three")
		for half in [["run_to_dict", "written into"], ["run_from_dict", "read back out of"]]:
			var at := gtxt.find("func %s" % String(half[0]))
			var to := gtxt.find("\nfunc ", at + 10)
			if at >= 0 and gtxt.substr(at, maxi(0, to - at)).find("power_offer") == -1:
				fails += 1
				print("FAIL the power offer is never %s the run — a resumed run forgets its terms" % [
					String(half[1])])
	var csrc := FileAccess.open("res://scripts/collection.gd", FileAccess.READ)
	if csrc != null:
		var ctxt := csrc.get_as_text()
		csrc.close()
		if ctxt.find("MetaState.power_offer(") != -1:
			fails += 1
			print("FAIL the deck builder rolls its own power offer — re-opening it would re-deal (D252)")

	# --- the clears gate is DERIVED from rarity, and rises with it (D255) ---
	#
	# It was a hand-set field on each of the thirty files while `rarity` is written from
	# `power_value()` by `rerarify` — so the two drifted and nothing said so: Short Change came out
	# LEGENDARY, the second-strongest power in the set, behind a gate of 2 clears, while Hold Fast
	# waited 10 as a middling RARE. **The gate said one thing about a power's strength and the price
	# said another, off the same catalogue.**
	#
	# Asserted on the TABLE rather than per power, because that is where the fact now lives. A test
	# that walked the thirty files would be asserting the derivation had happened rather than that it
	# is right.
	for r2 in range(1, CardData.Rarity.size()):
		if Balance.POWER_UNLOCK[r2] < Balance.POWER_UNLOCK[r2 - 1]:
			fails += 1
			print("FAIL %s opens before %s (%d clears vs %d) — a rarer power must not arrive sooner" % [
				CardData.rarity_badge(r2), CardData.rarity_badge(r2 - 1),
				int(Balance.POWER_UNLOCK[r2]), int(Balance.POWER_UNLOCK[r2 - 1])])
	# COMMON at zero, or a new character reaches the Power Pick screen with nothing on it: the offer
	# falls back to everything UNLOCKED when the save owns too few to fill three (D245).
	if Balance.POWER_UNLOCK[CardData.Rarity.COMMON] != 0:
		fails += 1
		print("FAIL commons are gated — a zero-clear save would be offered no power at all")
	var fresh = Meta_.new()
	fresh.path_prefix = SANDBOX
	fresh.slot = 7
	fresh.new_save()
	if fresh.power_offer(3).size() < 3:
		fails += 1
		print("FAIL a fresh save is offered %d powers, not three" % fresh.power_offer(3).size())
	# ...and every power is reachable eventually, which is what a gate must never break (D223's rule
	# for relics, and the reason the deepest gate is checked against the campaign's own length).
	if int(Balance.POWER_UNLOCK[CardData.Rarity.LEGENDARY]) > Balance.DUNGEONS.size():
		fails += 1
		print("FAIL the deepest power gate (%d) is past a full clear of the game (%d dungeons)" % [
			int(Balance.POWER_UNLOCK[CardData.Rarity.LEGENDARY]), Balance.DUNGEONS.size()])
	# The field is gone, and a hand-set one would silently win over the table if it came back.
	var pdsrc := FileAccess.open("res://scripts/power_data.gd", FileAccess.READ)
	if pdsrc != null:
		var pdtxt := pdsrc.get_as_text()
		pdsrc.close()
		if pdtxt.find("@export var unlock_after_clears") != -1:
			fails += 1
			print("FAIL PowerData declares unlock_after_clears again — the gate is derived from rarity (D255)")

	# --- the Power Pick falls back to the procedural glyph (D254) ---
	#
	# The screen shipped with three empty circles. Two guards were tried before this one and both
	# were weak, which is the part worth recording:
	#
	#   * A scene check that every offered circle carries an icon passed while the fallback was
	#     deleted — a fresh save is offered Bulwark, Foresight and Scythe, and all three ARE painted.
	#     **A guard over a random sample of three tests the sample.**
	#   * A catalogue check that every power resolves to *some* icon was VACUOUS: `Icons.tex` is
	#     procedural and never returns null, so the condition could not fail. It read like a real
	#     assertion and asserted nothing.
	#
	# What can actually go wrong is the screen not ASKING for the fallback — which is exactly what
	# the first version did, falling back to a drawn letter instead. So that is what is checked, off
	# the source, the way `test_relic.gd` and D252's own wiring checks do.
	var ppsrc := FileAccess.open("res://scripts/power_pick.gd", FileAccess.READ)
	if ppsrc != null:
		var pptxt := ppsrc.get_as_text()
		ppsrc.close()
		if pptxt.find("Icons.for_card") == -1:
			fails += 1
			print("FAIL the Power Pick has no procedural fallback — 20 of the 30 powers have no painting, so their circles would be empty (D254)")

	# --- a power must raise the scaling ratio (else the ratchet leaks) ---
	var deck := _starter()
	var bare: float = Balance.power_ratio(deck)
	for id in Balance.POWERS:
		var p := Balance.power(id)
		var withp: float = Balance.power_ratio(deck, [], p)
		if withp <= bare:
			fails += 1
			print("FAIL %s is free strength: ratio %.3f vs %.3f" % [id, withp, bare])
		# ...but no single power may dwarf the deck it supplements
		if withp > bare * 1.6:
			fails += 1
			print("FAIL %s dominates the deck: ratio %.3f vs %.3f" % [id, withp, bare])
	# levelling a power must also be priced in
	var lv1 := Balance.power("scythe")
	var lv5 := Balance.power("scythe").duplicate()
	lv5.level = 5
	if Balance.power_ratio(deck, [], lv5) <= Balance.power_ratio(deck, [], lv1):
		fails += 1; print("FAIL levelling a power does not raise the ratio")

	# --- ONCE per turn, and it costs energy ---
	var eng = load("res://scripts/combat_engine.gd").new()
	var scythe := Balance.power("scythe")
	eng.setup(deck, 60, 60, 3, Balance.Tier.NORMAL, "", [], [], scythe)
	eng.start_turn()
	var energy_before: int = eng.energy
	if not eng.can_use_power():
		fails += 1; print("FAIL power unusable on a fresh turn")
	if eng.use_power() == "":
		fails += 1; print("FAIL use_power did nothing")
	if eng.energy != energy_before - scythe.cost:
		fails += 1; print("FAIL power did not spend energy: %d -> %d" % [energy_before, eng.energy])
	if eng.can_use_power():
		fails += 1; print("FAIL power is firable twice in one turn")
	if eng.use_power() != "":
		fails += 1; print("FAIL second use_power in a turn was allowed")
	# ...and it comes back next turn
	eng.end_turn()
	if not eng.can_use_power() and not eng.over():
		fails += 1; print("FAIL power did not refresh at the start of the next turn")

	# --- it actually does something: Scythe must hit every enemy ---
	var eng2 = load("res://scripts/combat_engine.gd").new()
	eng2.setup(deck, 60, 60, 3, Balance.Tier.NORMAL, "", [], [], Balance.power("scythe"))
	eng2.start_turn()
	var hp_before: Array = []
	for e in eng2.enemies:
		hp_before.append(e.hp)
	eng2.use_power()
	for i in eng2.enemies.size():
		if eng2.enemies[i].hp >= hp_before[i]:
			fails += 1; print("FAIL Scythe did not damage enemy %d" % i); break

	# --- energy it cannot pay for ---
	var eng3 = load("res://scripts/combat_engine.gd").new()
	eng3.setup(deck, 60, 60, 3, Balance.Tier.NORMAL, "", [], [], Balance.power("overwhelm"))
	eng3.start_turn()
	eng3.energy = 0
	if eng3.can_use_power():
		fails += 1; print("FAIL power firable with no energy")
	# an HP cost must never be lethal, same rule as a card
	var eng4 = load("res://scripts/combat_engine.gd").new()
	eng4.setup(deck, 60, 60, 3, Balance.Tier.NORMAL, "", [], [], Balance.power("push_on"))
	eng4.start_turn()
	eng4.player.hp = 3
	if eng4.can_use_power():
		fails += 1; print("FAIL a power with an HP cost can kill its owner")

	# --- economy: buy, level, equip ---
	var m = Meta_.new()
	m.new_save()
	if m.power_data() == null:
		fails += 1; print("FAIL a new save has no power — nobody would discover the mechanic")
	var target := "overwhelm"
	m.gold = 0
	if m.buy_power(target):
		fails += 1; print("FAIL bought a power with no gold")
	m.gold = 999999
	m.cleared_dungeons = Balance.DUNGEONS.duplicate()   # clear the unlock gate
	if not m.buy_power(target):
		fails += 1; print("FAIL cannot buy an unlocked power with ample gold")
	if m.buy_power(target):
		fails += 1; print("FAIL bought the same power twice")
	var before_gold: int = m.gold
	if not m.upgrade_power(target):
		fails += 1; print("FAIL cannot level an owned power")
	if m.gold >= before_gold:
		fails += 1; print("FAIL levelling a power spent no gold")
	if int(m.powers[target]) != 2:
		fails += 1; print("FAIL power level is %d after one upgrade" % int(m.powers[target]))
	# the cap holds
	for i in 200:
		m.upgrade_power(target)
	var cap: int = Balance.power(target).level_capped()
	if int(m.powers[target]) != cap:
		fails += 1; print("FAIL power level %d exceeds cap %d" % [int(m.powers[target]), cap])
	# equipping something you do not own must fail
	if m.equip_power("no_such_power"):
		fails += 1; print("FAIL equipped a power that does not exist")
	if not m.equip_power(target):
		fails += 1; print("FAIL cannot equip an owned power")

	# --- persistence ---
	m.save_game()
	var m2 = Meta_.new()
	m2.load_game()
	if m2.equipped_power != target:
		fails += 1; print("FAIL equipped power not persisted: %s" % m2.equipped_power)
	if int(m2.powers.get(target, 0)) != cap:
		fails += 1; print("FAIL power level not persisted")
	var loaded = m2.power_data()
	if loaded == null or loaded.level != cap:
		fails += 1; print("FAIL power_data does not carry the saved level")

	# a save that names a power the player does not own must not carry it into a run
	var m3 = Meta_.new()
	m3.new_save()
	m3.powers = {}
	m3.equipped_power = "scythe"
	if m3.power_data() != null:
		fails += 1; print("FAIL an unowned power still equips")

	if fails == 0:
		print("POWER TEST: PASS (once per turn, priced into scaling, buy/level/equip, persistence)")
	else:
		print("POWER TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

func _starter() -> Array[CardData]:
	var deck: Array[CardData] = []
	for i in 4:
		deck.append(load(CARD_DIR + "hack.tres") as CardData)
		deck.append(load(CARD_DIR + "cover.tres") as CardData)
	return deck

## Remove this test's sandboxed files so a test run leaves no residue in the
## player's data directory.
func _cleanup_sandbox() -> void:
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
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
