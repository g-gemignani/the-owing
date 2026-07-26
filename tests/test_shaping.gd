## Headless test: in-run deck shaping and reward tension (D46).
##
## A run used to only ever ADD cards — `earn_card` appends and nothing removed —
## so surviving longer made your deck steadily less consistent, and the reward
## screen's "take one of three" was an automatic click because taking was free.
## Run: godot --headless --script tests/test_shaping.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = "t_test_shaping_"
	Meta_.writes_disabled = false
	var fails := 0
	var gs = load("res://scripts/game_state.gd").new()

	# --- removal thins the run deck and nothing else ---
	gs.run_deck = _deck(14)
	var before: int = gs.run_deck.size()
	var victim = gs.run_deck[3]
	if not gs.remove_from_run_deck(victim):
		fails += 1; print("FAIL could not remove a card from a 14-card deck")
	if gs.run_deck.size() != before - 1:
		fails += 1; print("FAIL deck is %d after one removal" % gs.run_deck.size())
	if gs.run_removals != 1:
		fails += 1; print("FAIL removal was not counted")
	# only ONE copy goes, not every copy of that card
	var same := 0
	for c in gs.run_deck:
		if c.id == victim.id:
			same += 1
	if same == 0 and before > 8:
		fails += 1; print("FAIL removing one copy took them all")

	# --- it can never strand the player below a legal deck ---
	var guard := 0
	while gs.can_remove_from_run_deck() and guard < 100:
		gs.remove_from_run_deck(gs.run_deck[0])
		guard += 1
	if gs.run_deck.size() < Balance.MIN_DECK_SIZE:
		fails += 1
		print("FAIL thinned to %d, below the legal minimum %d" % [
			gs.run_deck.size(), Balance.MIN_DECK_SIZE])
	if gs.remove_from_run_deck(gs.run_deck[0]):
		fails += 1; print("FAIL removed a card at the minimum deck size")

	# --- removing something not in the deck must fail, not corrupt ---
	var stranger := (load(CARD_DIR + "bash.tres") as CardData).duplicate()
	var size_before: int = gs.run_deck.size()
	if gs.remove_from_run_deck(stranger):
		fails += 1; print("FAIL removed a card that was never in the deck")
	if gs.run_deck.size() != size_before:
		fails += 1; print("FAIL deck changed size on a failed removal")

	# --- thinning is RUN-scoped: the collection must be untouched ---
	var m = Meta_.new()
	m.new_save()
	var owned_before: int = m.total_copies()
	var gs2 = load("res://scripts/game_state.gd").new()
	gs2.run_deck = _deck(14)
	gs2.remove_from_run_deck(gs2.run_deck[0])
	if m.total_copies() != owned_before:
		fails += 1; print("FAIL a run removal changed the permanent collection")

	# --- and it is not free power ---
	#
	# power_ratio is power per ENERGY, so cutting a weak card raises the ratio and
	# enemies scale to match. The player is buying consistency, not strength.
	var mixed: Array[CardData] = []
	for i in 8:
		mixed.append(load(CARD_DIR + "strike.tres") as CardData)
	for i in 4:
		mixed.append(load(CARD_DIR + "defend.tres") as CardData)
	var full: float = Balance.power_ratio(mixed)
	var thinned: Array[CardData] = mixed.duplicate()
	thinned.remove_at(thinned.size() - 1)   # drop a Defend, the weaker card
	if Balance.power_ratio(thinned) <= full:
		fails += 1
		print("FAIL thinning does not raise the scaling ratio — it would be free power")

	# --- the price rises, so each cut is a harder call than the last ---
	var prev := -1
	for n in 5:
		var price: int = Balance.removal_price(n)
		if price <= prev:
			fails += 1; print("FAIL removal price does not rise at removal %d" % n)
		prev = price
	if Balance.removal_price(0) <= 0:
		fails += 1; print("FAIL the first removal is free")
	# it must compete with the other things gold buys, not dwarf them
	if Balance.removal_price(0) > Balance.card_price(CardData.Rarity.RARE) * 3:
		fails += 1; print("FAIL removal costs more than three rare cards")

	# --- dilution is real, and the number quoted to the player says so ---
	if Balance.draw_interval(20) <= Balance.draw_interval(10):
		fails += 1; print("FAIL a bigger deck does not draw each card less often")
	# an 8-card deck at hand size 5 should cycle in under two turns
	if Balance.draw_interval(Balance.MIN_DECK_SIZE) > 2.0:
		fails += 1
		print("FAIL the minimum deck reads as slow: %.1f turns" % Balance.draw_interval(Balance.MIN_DECK_SIZE))

	# --- removals survive a save, or a reload refunds every cut already paid for ---
	#
	# run_to_dict() returns nothing unless a run is actually live, so this needs a
	# real one: a dungeon selected and a map generated, not just a deck assigned.
	var gs3 = load("res://scripts/game_state.gd").new()
	gs3.select_dungeon(Balance.DUNGEONS[0])
	gs3.run_deck = _deck(14)
	gs3.generate_map()          # has_run() needs a traversal, not just a deck
	gs3.hp = 40
	gs3.max_hp = 60
	gs3.remove_from_run_deck(gs3.run_deck[0])
	gs3.remove_from_run_deck(gs3.run_deck[0])
	if not gs3.has_run():
		fails += 1; print("FAIL the test could not set up a live run")
	var blob: Dictionary = gs3.run_to_dict()
	if int(blob.get("removals", -1)) != 2:
		fails += 1
		print("FAIL removals not written to the run save: %s" % str(blob.get("removals")))
	if int(blob.get("deck", []).size()) != gs3.run_deck.size():
		fails += 1; print("FAIL the thinned deck is not what gets saved")

	if fails == 0:
		print("SHAPING TEST: PASS (thinning, floors, run-scoped, priced, dilution, persistence)")
	else:
		print("SHAPING TEST: FAIL (%d)" % fails)
	_cleanup()
	quit()

func _deck(n: int) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in n:
		var id := "strike" if i % 2 == 0 else "defend"
		out.append((load(CARD_DIR + id + ".tres") as CardData).duplicate())
	return out

func _cleanup() -> void:
	load("res://scripts/meta_state.gd").writes_disabled = true
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with("t_"):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
