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
