## Headless test: collection persistence + fusion + deck build.
## Run: godot --headless --script tests/test_meta.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_meta_"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var Meta = load("res://scripts/meta_state.gd")
	var fails := 0

	var m1 = Meta.new()
	m1.new_save()
	var strike0: int = m1.owned("hack")     # depends on the starting kit
	var total0: int = m1.total_copies()
	m1.add_card("stave_in")
	m1.add_card("hack"); m1.add_card("hack"); m1.add_card("hack")
	if m1.owned("hack") != strike0 + 3:
		fails += 1; print("FAIL strike count %d (expect %d)" % [m1.owned("hack"), strike0 + 3])
	if m1.collection["stave_in"]["count"] != 1: fails += 1; print("FAIL bash count")

	# fusion is bought with gold as well as copies (see Balance.fuse_gold_cost)
	var before_fuse: int = m1.owned("hack")
	if m1.fuse("hack"):
		fails += 1; print("FAIL fused with no gold")
	var price: int = m1.fuse_gold_cost("hack")
	var copy_cost: int = m1.fuse_copy_cost("hack")
	m1.add_gold(price)
	if not m1.fuse("hack"): fails += 1; print("FAIL fuse returned false")
	if m1.gold != 0:
		fails += 1; print("FAIL fusion did not spend the gold: %d left" % m1.gold)
	if m1.owned("hack") != before_fuse - copy_cost:
		fails += 1; print("FAIL post-fuse count %d (expect %d)" % [m1.owned("hack"), before_fuse - copy_cost])
	if m1.collection["hack"]["level"] != 2: fails += 1; print("FAIL post-fuse level")
	m1.save_game()

	# reload in a fresh instance -> must match what was saved
	var m2 = Meta.new()
	if not m2.load_game(): fails += 1; print("FAIL load_game")
	if m2.owned("hack") != m1.owned("hack") or int(m2.collection["hack"]["level"]) != 2:
		fails += 1; print("FAIL persisted strike ", m2.collection["hack"])
	if m2.collection["stave_in"]["count"] != 1: fails += 1; print("FAIL persisted bash")

	# deck build must materialise exactly what is owned
	var deck = m2.build_run_deck()
	if deck.size() != m2.total_copies():
		fails += 1; print("FAIL deck size %d (expect %d)" % [deck.size(), m2.total_copies()])
	# expected value comes from the card model itself (scaling formula may change)
	var ref := (load("res://resources/cards/hack.tres") as CardData).duplicate()
	ref.level = 2
	var want: int = ref.eff_damage()
	ref.level = 1
	var base: int = ref.eff_damage()
	if want <= base: fails += 1; print("FAIL level 2 not stronger than level 1")
	var strike_dmg := -1
	for c in deck:
		if c.id == "hack": strike_dmg = c.eff_damage()
	if strike_dmg != want: fails += 1; print("FAIL leveled strike dmg %d (expect %d)" % [strike_dmg, want])

	# can't fuse when only 1 copy
	if m2.can_fuse("stave_in"): fails += 1; print("FAIL bash should not be fusable")

	# --- opening a sealed pack pays out exactly what the screen promised (D81) ---
	var did: String = Balance.DUNGEONS[0]
	var gold_before: int = m2.gold
	var copies_before: int = m2.total_copies()
	m2.add_pack(Balance.PACK_BOSS, did, Balance.PACK_GILDED, "poison")
	var got: Dictionary = m2.open_pack(0)
	var want_cards: int = Balance.pack_cards(Balance.PACK_GILDED)
	if got.get("cards", []).size() != want_cards:
		fails += 1
		print("FAIL pack held %d cards, promised %d" % [got.get("cards", []).size(), want_cards])
	if m2.total_copies() != copies_before + want_cards:
		fails += 1; print("FAIL opened cards did not reach the collection")
	if m2.gold <= gold_before:
		fails += 1; print("FAIL opening a pack paid no gold")
	# a typed pack contains its build and nothing else — the whole promise of a type
	var poison: Array = Array(Balance.build("poison").cards)
	for cid in got.get("cards", []):
		if not poison.has(cid):
			fails += 1; print("FAIL a poison pack yielded %s" % cid)
	if not m2.packs.is_empty():
		fails += 1; print("FAIL an opened pack is still sealed")
	# an out-of-range index must be refused, not crash or eat a pack
	if not m2.open_pack(7).is_empty():
		fails += 1; print("FAIL opening a pack that is not there returned something")

	# --- the tier cap is the promise a tier makes, so it is asserted directly ----
	# "in common packs you cannot find legendaries" is the requirement; a weight of
	# zero would only make it unlikely, so the CAP filters the pool instead.
	for tier in Balance.PACK_TIERS:
		var cap: int = int(Balance.PACK_TIER_CAP[tier])
		for bid in Balance.BUILDS:
			for cid in Balance.pack_pool(bid, tier):
				var c := Balance.card(cid)
				if c != null and c.rarity > cap:
					fails += 1
					print("FAIL %s %s pack can contain %s (rarity above its cap)" % [
						tier, bid, cid])
	# and no tier/build combination may be empty, or a pack opens into nothing
	for tier2 in Balance.PACK_TIERS:
		for bid2 in Balance.BUILDS:
			if Balance.pack_pool(bid2, tier2).is_empty():
				fails += 1; print("FAIL %s %s pack has nothing to give" % [tier2, bid2])

	# --- opening 200 worn packs must never produce a legendary -------------------
	var m4 = Meta.new()
	m4.path_prefix = SANDBOX + "caps_"
	m4.slot = 0
	m4.new_save()
	m4.writes_disabled = true
	for i in 200:
		m4.add_pack(Balance.PACK_TREASURE, Balance.DUNGEONS[Balance.DUNGEONS.size() - 1],
			Balance.PACK_WORN, Balance.BUILDS[i % Balance.BUILDS.size()])
		for cid in m4.open_pack(0).get("cards", []):
			var c2 := Balance.card(String(cid))
			if c2 != null and c2.rarity > int(Balance.PACK_TIER_CAP[Balance.PACK_WORN]):
				fails += 1
				print("FAIL a worn pack from the deepest dungeon yielded %s" % cid)
				break

	# --- chests: tier decides size and lock, and every vault states itself -------
	# The promise is that a chest is READABLE before it is opened, so every tier must
	# name a lock and every lock a size. A tier with no entry would silently fall
	# back to "worn, open, one pack", which is the failure that looks like content.
	for ctier in Balance.PACK_TIERS:
		if not Balance.CHEST_PACKS.has(ctier):
			fails += 1; print("FAIL chest tier %s holds nothing" % ctier)
		if not Balance.CHEST_LOCK.has(ctier):
			fails += 1; print("FAIL chest tier %s has no lock" % ctier)
	if Balance.chest_lock(Balance.PACK_WORN) != Balance.CHEST_LOCK_NONE:
		fails += 1; print("FAIL the humblest chest is not simply open")
	if Balance.chest_packs(Balance.PACK_GILDED) <= Balance.chest_packs(Balance.PACK_WORN):
		fails += 1; print("FAIL a vault is not worth more than a worn chest")
	# a locked chest must be worth the key: strictly more than the free one
	if Balance.chest_packs(Balance.PACK_SEALED) <= Balance.chest_packs(Balance.PACK_WORN):
		fails += 1; print("FAIL a sealed chest costs a key and pays no more")
	for cond in Balance.VAULTS:
		var txt := Balance.vault_text(cond, Balance.BUILDS[0])
		if txt == "" or not txt.begins_with("opens"):
			fails += 1; print("FAIL vault %s does not say what it wants" % cond)
	# every condition must be distinct, or two of them are the same door
	var seen_txt := {}
	for cond2 in Balance.VAULTS:
		var t2 := Balance.vault_text(cond2, Balance.BUILDS[0])
		if seen_txt.has(t2):
			fails += 1; print("FAIL two vault conditions read identically: %s" % t2)
		seen_txt[t2] = true

	# --- keys are found on the floor, never sold and never dripped --------------
	# the rope rule (D21), for the same reason: a purchasable key turns every locked
	# chest into a gold check, and a gold check is a delay rather than a decision. D167
	# took the other three sources away too — a chest, a fight and an elite each rolled
	# for one — because a key that arrives while you play is not a key you went and got.
	# How MANY is asserted in tests/test_traversal.gd, against the locks the crawl actually
	# rolled — there is no estimate in Balance to check any more (D172). What belongs here is
	# the rule that makes the count meaningful: exactly one tier is a key lock, so "one key
	# per lock" is a sentence about one tier and not about a distribution.
	var key_locks: Array = []
	for tier3 in Balance.PACK_TIERS:
		if Balance.chest_lock(tier3) == Balance.CHEST_LOCK_KEY:
			key_locks.append(tier3)
	if key_locks.size() != 1:
		fails += 1; print("FAIL %d tiers want a key — the floor scatters one key per locked chest and cannot know which" % key_locks.size())
	# a deeper dungeon rolls more of that tier, which is what makes depth carry more keys
	var shallow := Balance.pack_tier_odds(Balance.PACK_TREASURE, 1)
	var deep2 := Balance.pack_tier_odds(Balance.PACK_TREASURE, 12)
	if float(deep2[1]) / maxf(1.0, float(deep2[0] + deep2[1] + deep2[2])) \
			<= float(shallow[1]) / maxf(1.0, float(shallow[0] + shallow[1] + shallow[2])):
		fails += 1; print("FAIL a chest at depth 12 is no likelier to be locked than one at depth 1")
	# and the only place a key comes from is the floor
	for src in ["res://scripts/chest_screen.gd", "res://scripts/combat.gd"]:
		var sf := FileAccess.open(src, FileAccess.READ)
		if sf != null:
			var body := sf.get_as_text()
			sf.close()
			if body.find("GameState.keys +") != -1:
				fails += 1; print("FAIL %s hands out a key — the dungeon floor is the one source (D167)" % src)

	# --- a dungeon's affinity is derived from its own pool, never authored -------
	for did2 in Balance.DUNGEONS:
		var aff := Balance.pack_build_affinity(did2)
		if not (aff in Balance.BUILDS):
			fails += 1; print("FAIL %s has no valid pack affinity" % did2)

	# --- a gate takes more than one kind of evidence (D178) ----------------------
	#
	# Depth in dungeons that beat you counts toward a gate, at a discount and under a cap.
	# Every clause below is a way the second route could be wrong in a direction nobody
	# would notice: paying for the first floor (which every run reaches), paying twice for
	# a dungeon you went on to clear, or paying so well that clears stop mattering — which
	# would walk a starting collection into the Maw at difficulty 8, and D36's ceiling makes
	# that a wall rather than a freedom.
	var mg = Meta.new()
	mg.new_save()
	if mg.gate_credit() != 0:
		fails += 1; print("FAIL a fresh save already has %d gate credit" % mg.gate_credit())
	# arriving on floor 1 is turning up, not evidence
	mg.note_depth(Balance.DUNGEONS[0], 1)
	if mg.gate_credit() != 0:
		fails += 1; print("FAIL reaching floor 1 paid a gate")
	# ...and a made-up dungeon pays nothing at all
	mg.note_depth("no_such_place", 4)
	if mg.depth_records.has("no_such_place"):
		fails += 1; print("FAIL the depth log accepted a dungeon that does not exist")
	# the log keeps the DEEPEST, so a shallower later run cannot take credit away
	mg.note_depth(Balance.DUNGEONS[0], 3)
	mg.note_depth(Balance.DUNGEONS[0], 2)
	if int(mg.depth_records[Balance.DUNGEONS[0]]) != 3:
		fails += 1; print("FAIL a shallower run overwrote a deeper one")
	var want_credit: int = 2 / Balance.GATE_DEPTH_FLOORS_PER_CREDIT
	if mg.gate_credit() != want_credit:
		fails += 1
		print("FAIL two floors below the first is worth %d, expected %d" % [
			mg.gate_credit(), want_credit])
	# clearing it stops it paying: a place you have beaten pays a clear, not a clear AND a
	# discount on the next gate
	mg.mark_cleared(Balance.DUNGEONS[0])
	if mg.gate_credit() != 1:
		fails += 1
		print("FAIL a cleared dungeon still pays depth credit (%d, expected 1)" % mg.gate_credit())
	# the cap holds however deep you go, or depth replaces clears entirely
	for did3 in Balance.DUNGEONS:
		mg.note_depth(did3, 9)
	var capped: int = mg.gate_credit() - mg.clear_count()
	if capped != Balance.GATE_DEPTH_CREDIT_MAX:
		fails += 1
		print("FAIL depth alone is worth %d of a gate, cap is %d" % [
			capped, Balance.GATE_DEPTH_CREDIT_MAX])
	# ...and the cap has to be short of the deepest gate, or the world can be opened
	# without beating anything
	var deepest_gate := 0
	for did4 in Balance.DUNGEONS:
		deepest_gate = maxi(deepest_gate, Balance.effective_gate(did4))
	if Balance.GATE_DEPTH_CREDIT_MAX >= deepest_gate:
		fails += 1
		print("FAIL depth alone (%d) reaches the deepest gate (%d) — clears stop mattering" % [
			Balance.GATE_DEPTH_CREDIT_MAX, deepest_gate])
	# The depth log has to survive a save, or the second route resets every session. And it
	# is filtered on the way in, so this is also the test that the filter does not eat it.
	#
	# `writes_disabled` is a STATIC and the pack block above turned it on to stop its own
	# instance flushing at exit, so it has to be turned back off here — the first version of
	# this assertion reported "the depth log's save would not load back" about a save that was
	# never written, which is a true statement about the wrong thing.
	Meta.writes_disabled = false
	mg.slot = 2
	mg.save_game()
	var mg2 = Meta.new()
	mg2.slot = 2
	if not mg2.load_game():
		fails += 1; print("FAIL the depth log's save would not load back")
	elif mg2.depth_records != mg.depth_records:
		fails += 1
		print("FAIL the depth log came back as %s, was %s" % [
			str(mg2.depth_records), str(mg.depth_records)])
	Meta.writes_disabled = true
	# Depth must not buy STRENGTH. A gate is permission to go somewhere; the permanent
	# max-HP bonus is a reward for finishing, and paying it for depth would be free power
	# from outside the deck — the one thing enemy scaling cannot absorb (the priced-power
	# pillar). Asserted at the SOURCE, the way the key rule above is, because the bug would
	# be one identifier long and would read as a tidy-up in a diff.
	var gs_src := FileAccess.get_file_as_string("res://scripts/game_state.gd")
	if gs_src.find("max_hp_for(") != -1 and gs_src.find("gate_credit") != -1:
		fails += 1
		print("FAIL game_state.gd mentions gate_credit near the HP maths — depth must not buy strength")
	print("  (info: depth credit is %d of a gate at most, %d floors each, deepest gate %d)" % [
		Balance.GATE_DEPTH_CREDIT_MAX, Balance.GATE_DEPTH_FLOORS_PER_CREDIT, deepest_gate])

	# --- debts are observed, never imposed (D191) ---------------------------------
	#
	# The rule that keeps this out of the scaling model is that a debt is a condition OBSERVED
	# during a run, never a modifier ON it — so the assertions are about what settles one and
	# what it pays, and there is deliberately nothing here about the run being different.
	Meta.writes_disabled = false
	var md = Meta.new()
	md.new_save()
	for did5 in Balance.DUNGEONS:
		md.mark_cleared(did5)      # open everything, so the offers can name anywhere
	var offers: Array = md.offer_debts()
	if offers.size() != Balance.DEBT_OFFERS:
		fails += 1
		print("FAIL the table offers %d debts, expected %d" % [
			offers.size(), Balance.DEBT_OFFERS])
	for o in offers:
		var od: Dictionary = o
		if not (String(od.get("kind", "")) in Balance.DEBTS):
			fails += 1; print("FAIL a debt of no known kind is on the table")
		if not (String(od.get("dungeon", "")) in Balance.DUNGEONS):
			fails += 1; print("FAIL a debt names a place that is not a dungeon")
		if Balance.debt_text(String(od["kind"]), String(od["dungeon"])) == "":
			fails += 1; print("FAIL a debt with no words on it")
	# asking again must not re-roll: a table that changed on sight is a slot machine
	var again: Array = md.offer_debts()
	if again != offers:
		fails += 1; print("FAIL the debts on the table changed just for being looked at")
	# take one, and the table clears
	md.take_debt(0)
	if md.debt_taken.is_empty():
		fails += 1; print("FAIL taking a debt left nothing owed")
	if not md.debt_offers.is_empty():
		fails += 1; print("FAIL the table still has debts on it after one was taken")
	md.take_debt(0)
	if md.debt_offers.size() > 0:
		fails += 1; print("FAIL a second debt could be taken while one was owed")
	# ...and it settles only against the run it named
	var took: Dictionary = md.debt_taken.duplicate()
	var place := String(took["dungeon"])
	var wrong := ""
	for did6 in Balance.DUNGEONS:
		if did6 != place:
			wrong = did6
			break
	if md.settle_debt(wrong, true, 9, false) != 0:
		fails += 1; print("FAIL a debt settled against the wrong dungeon")
	var before_credit: int = md.debt_credits
	var paid: int = md.settle_debt(place, true, 9, false)
	if paid <= 0:
		fails += 1; print("FAIL settling the debt paid nothing")
	if md.debt_credits != before_credit + 1:
		fails += 1; print("FAIL settling the debt paid no gate credit")
	if not md.debt_taken.is_empty():
		fails += 1; print("FAIL the debt is still owed after being settled")
	if md.settle_debt(place, true, 9, false) != 0:
		fails += 1; print("FAIL a settled debt paid twice")
	# every kind has to be met by SOMETHING and refused by something, or it is decoration
	for kind in Balance.DEBTS:
		var any_yes := Balance.debt_met(String(kind), place, place, true, 9, false)
		var any_no := Balance.debt_met(String(kind), place, place, false, 0, true)
		if not any_yes:
			fails += 1; print("FAIL '%s' cannot be settled by a perfect run" % kind)
		if any_no:
			fails += 1; print("FAIL '%s' is settled by a run that did nothing" % kind)
	# and the credit reaches the gate, or a debt is a side quest rather than a route
	var mgate = Meta.new()
	mgate.new_save()
	var base_gate: int = mgate.gate_credit()
	mgate.debt_credits = 2
	if mgate.gate_credit() != base_gate + 2:
		fails += 1; print("FAIL debt credit does not reach the gate")
	Meta.writes_disabled = true
	print("  (info: %d debt kinds, %d offered at a time, +1 gate credit and %d gold at d1)" % [
		Balance.DEBTS.size(), Balance.DEBT_OFFERS, Balance.debt_gold(1)])

	if fails == 0:
		print("META TEST: PASS (persistence + fusion + deck build + packs)")
	else:
		print("META TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

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
