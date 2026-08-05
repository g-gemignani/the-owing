## The fight reward's collection note: what it claims about the collection has to be
## what the collection would actually do (D174).
##
## Three things, each of which goes wrong silently — a note that quotes the wrong number
## still reads perfectly:
##
## 1. **The arithmetic.** The note promises "3 more copies + 40g → Lv2". `MetaState.fuse`
##    spends `fuse_copy_cost` copies and `can_fuse` refuses to spend the last one, so the
##    number of copies you must OWN is the cost PLUS ONE. Quote the bare cost and the
##    reward screen promises a level that the Collection screen then refuses, at exactly
##    the copy count the player went and earned. The test therefore does not compare the
##    note against a formula — it ADDS the copies the note asked for and requires
##    `MetaState.can_fuse` to say yes, and requires one fewer to say no.
##
## 2. **The level the offer is quoted at.** A reward joins the run deck at the level the
##    collection already holds that card at (`GameState.earn_card`), and the catalogue
##    resource is the level-1 one. A card fused to Lv3 was offered showing its level-1
##    numbers and then dealt its Lv3 damage — D50's drift, on the one screen where the
##    player is choosing between cards on those numbers.
##
## 3. **The cap and the price are the CARD's**, not its rarity's level track and not the
##    flat base price. Both have a wrapper that answers with the wider number, and each
##    has its own section below.
##
## A SCENE, not a `--script` test: `UI.collection_standing` reads two autoloads and
## `ui.gd` names a third, and autoloads do not exist in a headless script run.
## Run: godot --headless res://tests/RewardNoteTest.tscn
extends Node

## Every user:// file this suite may create begins with this. The teardown deletes by
## it rather than by "t_", which would delete the live save of every suite beside it.
const SANDBOX := "t_rewardnote_"

var _fails := 0

func _ready() -> void:
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()

	_the_note_states_the_four_cases()
	_the_copy_count_is_the_one_fusion_wants()
	_the_cap_is_the_cards_own()
	_the_price_is_the_cards_own()
	await _the_reward_row_carries_one_note_per_card()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("REWARD NOTE TEST: PASS (the note matches the collection, and offers quote their level)")
	else:
		print("REWARD NOTE TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## A card with a real level track, chosen from the catalogue rather than named: a
## hardcoded id is a test that goes vacuous the first time a card is renamed.
func _probe_id() -> String:
	for id in MetaState.CATALOG.keys():
		var c := load(MetaState.CATALOG[id]) as CardData
		if c == null:
			continue
		if MetaState.max_level(id) >= 3 and c.level_up_text(2) != "":
			return id
	return ""

## --- 1. the four things the note can say ------------------------------------
func _the_note_states_the_four_cases() -> void:
	var id := _probe_id()
	if id == "":
		_fails += 1; print("FAIL no catalogue card has a level track to test"); return
	var card := (load(MetaState.CATALOG[id]) as CardData).duplicate() as CardData

	# unowned
	MetaState.collection.erase(id)
	var st: Dictionary = UI.collection_standing(card)
	if not String(st["line"]).begins_with("NEW"):
		_fails += 1; print("FAIL an unowned card is not called new: %s" % st["line"])
	if not String(st["tip"]).contains(card.name):
		_fails += 1; print("FAIL the hover does not name the card")

	# owned, short of the copies for the next level
	MetaState.collection[id] = {"count": 1, "level": 1}
	st = UI.collection_standing(card)
	if not String(st["line"]).contains("Owned x1"):
		_fails += 1; print("FAIL a single owned copy is not counted: %s" % st["line"])
	if not String(st["line"]).contains("Lv2"):
		_fails += 1; print("FAIL the note does not name the next level: %s" % st["line"])
	if not String(st["line"]).contains(card.level_up_text(2)):
		_fails += 1; print("FAIL the note does not say what the level buys: %s" % st["line"])

	# owned, with the copies and the gold already in hand
	MetaState.gold = 100000
	MetaState.collection[id] = {"count": MetaState.fuse_copy_cost(id) + 1, "level": 1}
	st = UI.collection_standing(card)
	if not String(st["line"]).contains("now"):
		_fails += 1; print("FAIL a card ready to level does not say so: %s" % st["line"])

	# at the cap
	MetaState.collection[id] = {"count": 4, "level": MetaState.max_level(id)}
	st = UI.collection_standing(card)
	if not String(st["line"]).contains("cap"):
		_fails += 1; print("FAIL a maxed card does not say it is maxed: %s" % st["line"])

	# copies taken this run are named separately, because dying erases them (D20)
	MetaState.collection[id] = {"count": 2, "level": 1}
	GameState.escrow_cards = [id]
	st = UI.collection_standing(card)
	if not String(st["line"]).contains("this run"):
		_fails += 1; print("FAIL a copy taken this run is not distinguished: %s" % st["line"])
	if String(st["line"]).contains("Owned x3"):
		_fails += 1; print("FAIL an at-risk copy is counted as owned: %s" % st["line"])
	GameState.escrow_cards = []

## --- 2. the number of copies it asks for is the number fusion wants ---------
##
## Not "is the formula right" — the formula is what is under test. The note's own number
## is read out of its text, added to the collection, and fusion is asked.
func _the_copy_count_is_the_one_fusion_wants() -> void:
	var id := _probe_id()
	if id == "":
		return
	var card := (load(MetaState.CATALOG[id]) as CardData).duplicate() as CardData
	MetaState.gold = 100000
	# a fat collection, so MIN_KEEP is never what refuses the fuse
	for other in MetaState.CATALOG.keys():
		if other != id:
			MetaState.collection[other] = {"count": 4, "level": 1}
	MetaState.collection[id] = {"count": 1, "level": 1}

	var line := String(UI.collection_standing(card)["line"])
	var asked := _first_int(line.get_slice("\n", 1))
	if asked <= 0:
		_fails += 1; print("FAIL the note asks for no copies at all: %s" % line); return

	MetaState.collection[id]["count"] = 1 + asked - 1
	if MetaState.can_fuse(id):
		_fails += 1
		print("FAIL fusion is possible one copy BELOW what the note asked for (%d)" % asked)
	MetaState.collection[id]["count"] = 1 + asked
	if not MetaState.can_fuse(id):
		_fails += 1
		print("FAIL the %d copies the note asked for do not buy the level: %s" % [
			asked, MetaState.fuse_blocked_reason(id)])

func _first_int(s: String) -> int:
	var digits := ""
	for i in s.length():
		var ch := s[i]
		if ch >= "0" and ch <= "9":
			digits += ch
		elif digits != "":
			break
	return int(digits) if digits != "" else 0

## --- 3. the cap it quotes is the card's, not its rarity's ---------------------
##
## A card whose whole effect is a status or a draw stops improving long before its
## rarity's level track runs out — 25 of the 100 cards, `read_ahead` finished at Lv2
## against a track of 100. Quote the track and the note tells a player to go and earn
## copies for 98 levels that do not exist.
func _the_cap_is_the_cards_own() -> void:
	var id := ""
	var eff := 0
	var track := 0
	for k in MetaState.CATALOG.keys():
		var c := load(MetaState.CATALOG[k]) as CardData
		if c != null and c.level_cap() < Balance.max_level(c.rarity):
			id = k
			eff = c.level_cap()
			track = Balance.max_level(c.rarity)
			break
	if id == "":
		print("  (info: no card's own cap is below its rarity track; nothing to check)")
		return
	var card := (load(MetaState.CATALOG[id]) as CardData).duplicate() as CardData
	MetaState.collection[id] = {"count": 1, "level": 1}
	var line := String(UI.collection_standing(card)["line"])
	if not line.contains("of %d" % eff):
		_fails += 1
		print("FAIL %s stops at Lv%d and the note does not say so: %s" % [id, eff, line])
	if line.contains("of %d" % track):
		_fails += 1
		print("FAIL %s is quoted at its rarity's track of %d: %s" % [id, track, line])

## --- 4. and so is the price, before the first copy is owned -------------------
##
## `MetaState.fuse_gold_cost` answers with the flat base price for a card that is not in
## the collection yet, which is right for a wrapper that has no entry to read and wrong
## for a screen offering the card: an unowned uncommon was quoted at 20g and priced at 52
## the moment it was taken.
func _the_price_is_the_cards_own() -> void:
	var id := ""
	for k in MetaState.CATALOG.keys():
		var c := load(MetaState.CATALOG[k]) as CardData
		if c != null and Balance.fuse_gold_cost(c.rarity, 1) != Balance.FUSE_BASE_GOLD:
			id = k
			break
	if id == "":
		print("  (info: every rarity fuses at the base price; nothing to check)")
		return
	var card := (load(MetaState.CATALOG[id]) as CardData).duplicate() as CardData
	MetaState.collection.erase(id)
	var line := String(UI.collection_standing(card)["line"])
	var want := "%dg" % Balance.fuse_gold_cost(card.rarity, 1)
	if not line.contains(want):
		_fails += 1
		print("FAIL an unowned %s is not quoted at %s: %s" % [id, want, line])

## --- 5. the real screen: one note per offered card, quoted at its own level --
func _the_reward_row_carries_one_note_per_card() -> void:
	MetaState.new_save()
	GameState.reset_run_progress()
	GameState.select_dungeon("crypt")
	# Every card this dungeon can drop is held at Lv3, so whatever the roll picks the
	# offer has to come back at Lv3 — a check that cannot be passed by a lucky pool.
	for id in GameState.card_pool():
		if MetaState.CATALOG.has(id):
			MetaState.collection[id] = {"count": 2, "level": 3}
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var e: Dictionary = MetaState.collection[id]
		for i in int(e["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(e["level"])
			deck.append(c)
	GameState.enter_dungeon(deck)
	GameState.hp = GameState.max_hp
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}

	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	for card in inst._roll_rewards(3):
		var want: int = int(MetaState.collection[card.id]["level"]) \
			if MetaState.collection.has(card.id) else 1
		if card.level != want:
			_fails += 1
			print("FAIL %s is offered at Lv%d but joins at Lv%d" % [card.id, card.level, want])

	inst._win()
	await get_tree().process_frame
	var cards := 0
	var notes := 0
	for holder in _controls(inst.reward_box):
		if holder.has_meta("card_id"):
			cards += 1
		var l := holder as Label
		if l != null and (l.text.contains("Owned x") or l.text.begins_with("NEW")):
			notes += 1
	if cards == 0:
		_fails += 1; print("FAIL the reward screen offered no cards at all")
	elif notes != cards:
		_fails += 1
		print("FAIL %d cards offered but %d of them say where they stand" % [cards, notes])
	inst.queue_free()
	await get_tree().process_frame

func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control:
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_controls(c))
	return out

func _purge() -> void:
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
	for name in doomed:
		DirAccess.remove_absolute("user://%s" % name)
