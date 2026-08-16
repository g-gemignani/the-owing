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
	_the_deck_count_is_the_deck_being_played()
	_the_copy_count_is_the_one_fusion_wants()
	_the_cap_is_the_cards_own()
	_the_price_is_the_cards_own()
	await _the_reward_row_carries_one_note_per_card()
	_a_taken_card_is_marked_found()
	await _taking_a_relic_moves_nothing()

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
	# The COLLECTION's line, found by what it says rather than by where it sits. It was the
	# first line until D322 put the run deck above it, and `begins_with` then failed on a note
	# that was perfectly correct — the assertion was pinning the layout, not the claim.
	if not _line_with(String(st["line"]), "NEW").begins_with("NEW"):
		_fails += 1; print("FAIL an unowned card is not called new: %s" % st["line"])
	if not String(st["tip"]).contains(card.name):
		_fails += 1; print("FAIL the hover does not name the card")
	# ...and the deck line is there, and says zero for a card no run is carrying (D322)
	if not String(st["line"]).contains("Not in your deck"):
		_fails += 1; print("FAIL the note does not say the deck holds none: %s" % st["line"])
	if String(st["short"]) != "deck 0 · NEW":
		_fails += 1; print("FAIL the compact form is wrong for an unowned card: %s" % st["short"])

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

## --- 1b. the deck count is the DECK, and it is not the collection (D322) -----
##
## The note answers two questions that look like one. "Do I already have this" at a shop
## shelf means the deck in your hands; "is this new" means the collection. They move
## independently — a card can be the third copy in a deck you built at the door and still
## be absent from the collection, and a card can sit at four copies in the collection and
## not be in this run at all.
##
## So the test builds a deck that DISAGREES with the collection in both directions, which
## is the only setup where a mixed-up pair of numbers cannot pass by coincidence.
func _the_deck_count_is_the_deck_being_played() -> void:
	var ids: Array = MetaState.CATALOG.keys()
	if ids.size() < 2:
		print("  (info: fewer than two cards in the catalogue; nothing to check)")
		return
	var in_deck := String(ids[0])      # three in the deck, none in the collection
	var in_coll := String(ids[1])      # four in the collection, none in the deck
	MetaState.collection.erase(in_deck)
	MetaState.collection[in_coll] = {"count": 4, "level": 1}
	GameState.escrow_cards = []
	var deck: Array[CardData] = []
	for i in 3:
		deck.append((load(MetaState.CATALOG[in_deck]) as CardData).duplicate() as CardData)
	GameState.run_deck = deck

	# counted by ID: a deck holds distinct resources, so three copies are three objects and
	# `Array.count` on the card itself would answer 1
	if UI.deck_copies(in_deck) != 3:
		_fails += 1
		print("FAIL the deck holds 3 copies and deck_copies says %d" % UI.deck_copies(in_deck))
	if UI.deck_copies(in_coll) != 0:
		_fails += 1
		print("FAIL a card absent from the deck counts %d" % UI.deck_copies(in_coll))

	# in the deck, never owned: the note has to say both, and not average them
	var a: Dictionary = UI.collection_standing(load(MetaState.CATALOG[in_deck]) as CardData)
	if not String(a["line"]).contains("In deck x3"):
		_fails += 1; print("FAIL the note does not count the deck: %s" % a["line"])
	if not String(a["line"]).contains("NEW"):
		_fails += 1
		print("FAIL a card in the deck but not the collection is not NEW: %s" % a["line"])
	if String(a["short"]) != "deck 3 · NEW":
		_fails += 1; print("FAIL compact form for deck-but-unowned: %s" % a["short"])

	# owned, not in the deck: the mirror case, which is what catches the two being swapped
	var b: Dictionary = UI.collection_standing(load(MetaState.CATALOG[in_coll]) as CardData)
	if not String(b["line"]).contains("Not in your deck"):
		_fails += 1; print("FAIL an owned card absent from the deck: %s" % b["line"])
	if not String(b["line"]).contains("Owned x4"):
		_fails += 1; print("FAIL the collection count is lost: %s" % b["line"])
	if String(b["short"]) != "deck 0 · own 4":
		_fails += 1; print("FAIL compact form for owned-but-not-carried: %s" % b["short"])

	# and the hover says the deck too, because on a phone it is the only one that can be read
	if not String(b["tip"]).contains("not in the deck"):
		_fails += 1; print("FAIL the hover does not state the deck")
	GameState.run_deck = []

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
	# The line that ASKS for copies, found by the arrow it asks with. This read `get_slice(1)`
	# — the second line — until D322 added one above it, and the test then parsed the count out
	# of a sentence about the collection. Same lesson as the `begins_with` above: a note is
	# three lines and the assertion cares about one of them, so say which.
	var asked := _first_int(_line_with(line, "→"))
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

## The one line of a multi-line note that contains `needle`, or "" if none does. Every
## assertion that wants one claim out of the note goes through this rather than counting
## lines: the note grew a line at the top in D322 and two index-based assertions broke on a
## note that was correct.
func _line_with(text: String, needle: String) -> String:
	for l in text.split("\n"):
		if String(l).contains(needle):
			return String(l)
	return ""


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

	# Every face the panel is about to draw, at the level the collection holds it at. Off
	# `_reward_face`, which is what the panel itself calls — `_roll_rewards` was the old
	# single-card roll and has not existed since the reward became a set (D297), so this loop
	# called a missing function, the script error ended the whole section, and the suite went on
	# printing PASS. A test that aborts silently is worse than no test.
	for bundle in Balance.reward_bundles(GameState.dungeon_id, GameState.run_deck,
			Balance.Tier.NORMAL, GameState.dungeon):
		for cid in bundle.get("cards", []):
			var card: CardData = inst._reward_face(String(cid))
			if card == null:
				continue
			var want: int = int(MetaState.collection[card.id]["level"]) \
				if MetaState.collection.has(card.id) else 1
			if card.level != want:
				_fails += 1
				print("FAIL %s is offered at Lv%d but joins at Lv%d" % [card.id, card.level, want])

	inst._win()
	await get_tree().process_frame
	await get_tree().process_frame

	# One note per offered card, in BOTH places it is now said (D322). The full note rides the
	# card's tooltip, because the sets stack three faces to a column and nine two-line
	# paragraphs do not fit the panel. Under each face is the one-line `short` form, which is
	# the half a phone can read at all — there is no hover on a touchscreen, so until D322 the
	# whole thing was unreachable there.
	var cards := 0
	var notes := 0
	var shorts := 0
	var pressable := 0
	for holder in _controls(inst.reward_box):
		if not holder.has_meta("card_id"):
			continue
		cards += 1
		var face: Button = null
		for c in holder.get_children():
			if c is Button:
				face = c as Button
		if face == null:
			continue
		# The two openings `collection_standing`'s hover can have, and between them they cover
		# every card: one you hold copies of, and one you do not.
		if face.tooltip_text.contains("You own") \
				or face.tooltip_text.contains("is not in your collection"):
			notes += 1
		# D300: a card on this panel is for READING. Every one of them used to take the whole
		# set when pressed, which on a phone meant the second tap that finished reading a card
		# also bought the two beside it that you had not read yet.
		if face.pressed.get_connections().size() > 0:
			pressable += 1
	# The visible one-liners, counted over the whole panel rather than per column: the label is
	# a sibling of the face, not a child of it, so it is not reachable from the holder above.
	for c in _controls(inst.reward_box):
		var lb := c as Label
		if lb != null and lb.text.begins_with("deck ") and lb.text.contains("·"):
			shorts += 1
	if cards == 0:
		_fails += 1; print("FAIL the reward screen offered no cards at all")
	elif notes != cards:
		_fails += 1
		print("FAIL %d cards offered but %d of them say where they stand" % [cards, notes])
	if cards > 0 and shorts != cards:
		_fails += 1
		print("FAIL %d cards offered but %d carry a visible standing line (D322)" % [
			cards, shorts])
	if pressable > 0:
		_fails += 1
		print("FAIL %d of %d reward cards commit when pressed; only the Take button may" % [
			pressable, cards])

	# One Take per set, and one Skip. The set is taken by the control that says so.
	var takes := 0
	var skips := 0
	for c in _controls(inst.reward_box):
		var b := c as Button
		if b == null:
			continue
		if b.text.begins_with("Take these"):
			takes += 1
		elif b.text.begins_with("Skip"):
			skips += 1
	if takes != inst.bundle_offer.size():
		_fails += 1
		print("FAIL %d sets offered but %d Take buttons" % [inst.bundle_offer.size(), takes])
	if skips != 1:
		_fails += 1; print("FAIL %d Skip buttons on the reward panel" % skips)

	# ...and the whole column has to fit the frame it is centred in. The panel is a scroll now
	# (D300), so overflow is reachable rather than lost off the bottom edge — but needing to
	# scroll a reward pick is still a panel that does not fit, and this is the check that says
	# so. Measured against the SCROLL's rect, which is the frame minus the screen padding.
	#
	# It used to be measured against an anchor band, and the band was the bug: a Control is never
	# smaller than its content, so a column too tall grew straight out of its own rectangle
	# instead of clipping, and the Skip button landed on the HP bar.
	var need := 0.0
	for child in inst.reward_box.get_children():
		var c := child as Control
		if c != null:
			need += maxf(c.get_combined_minimum_size().y, c.size.y)
	need += float(inst.reward_box.get_theme_constant("separation")) \
		* maxf(0.0, float(inst.reward_box.get_child_count() - 1))
	var allowed: float = (inst.reward_box.get_parent() as Control).size.y
	if need > allowed:
		_fails += 1
		print("FAIL the reward column needs %.0fpx and the frame allows %.0f" % [need, allowed])
	inst.queue_free()
	await get_tree().process_frame

## --- 6. the relic band holds still when a relic is taken (D300) -------------
##
## Reported as "choosing a relic moves the buttons around". Taking one used to free every child of
## the panel and build it again without the relic row, so the three sets and the Skip button jumped
## up by the height of the row — under a hand that had just pressed something, on a screen where
## the next press spends the reward.
##
## Measured on the Skip button's own position, before and after, because that is the control the
## complaint is about and a check on "does the code rebuild" would pass the day somebody rebuilds
## it a different way.
func _taking_a_relic_moves_nothing() -> void:
	MetaState.new_save()
	# Deep enough that the relic pool is not empty at zero clears (D223): the gate opens commons
	# straight away, which is all this needs, but a save with nothing to offer would make the
	# whole check vacuous rather than red.
	for did in Balance.DUNGEONS:
		MetaState.clear_counts[did] = 1
	GameState.reset_run_progress()
	GameState.select_dungeon("crypt")
	for id in GameState.card_pool():
		if MetaState.CATALOG.has(id):
			MetaState.collection[id] = {"count": 2, "level": 1}
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var e: Dictionary = MetaState.collection[id]
		for i in int(e["count"]):
			deck.append((load(MetaState.CATALOG[id]) as CardData).duplicate())
	GameState.enter_dungeon(deck)
	GameState.hp = GameState.max_hp
	GameState.pending = {"type": GameState.NodeType.ELITE}
	GameState.combat_state = {}

	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._win()
	await get_tree().process_frame
	await get_tree().process_frame

	if inst.relic_offer.is_empty():
		print("  (info: this elite offered no relic; the band check has nothing to stand on)")
		inst.queue_free()
		await get_tree().process_frame
		return

	var skip: Button = null
	var take: Button = null
	var tiles: Array[Button] = []
	for c in _controls(inst.reward_box):
		var b := c as Button
		if b == null:
			continue
		if b.text.begins_with("Skip"):
			skip = b
		elif b.text in [UI.RELIC_TAKE_IDLE, UI.RELIC_TAKE_READY, UI.RELIC_TAKE_DONE]:
			take = b
		elif b.custom_minimum_size.x == UITheme.px(UI.RELIC_TILE_W):
			tiles.append(b)
	if skip == null:
		_fails += 1; print("FAIL no Skip button on an elite's reward panel"); return
	if take == null:
		_fails += 1; print("FAIL no take button on an elite's relic offer"); return
	if tiles.size() != inst.relic_offer.size():
		_fails += 1
		print("FAIL %d relics offered but %d tiles drawn" % [inst.relic_offer.size(), tiles.size()])
		return

	# The ELITE panel is the tallest this screen ever gets — the sets, the dilution line and Skip,
	# with the relic band and its take button on top — so it is the one that has to be measured.
	# The panel scrolls (D300), so overflow is reachable rather than lost; needing to scroll a
	# reward pick is still a panel that does not fit, and this is where that shows up first.
	var need := 0.0
	for child in inst.reward_box.get_children():
		var c := child as Control
		if c != null:
			need += maxf(c.get_combined_minimum_size().y, c.size.y)
	need += float(inst.reward_box.get_theme_constant("separation")) \
		* maxf(0.0, float(inst.reward_box.get_child_count() - 1))
	var allowed: float = (inst.reward_box.get_parent() as Control).size.y
	if need > allowed:
		_fails += 1
		print("FAIL an elite's reward panel needs %.0fpx and the frame allows %.0f" % [need, allowed])

	# --- D307: a tile SELECTS, and only the button spends the offer -------------
	#
	# Reported off a phone: tap the first relic, tap the second, tap the first again and it was
	# TAKEN — no second reading, no way back. The two-tap gesture remembered "this one has been
	# read" for ever, per tile, so returning to a tile you had read counted as the commit tap.
	#
	# Walked here exactly as it was reported, because the bug needs three presses to appear and
	# any check that presses once would have passed on the broken build.
	if not take.disabled:
		_fails += 1; print("FAIL the take button is live before anything is picked")
	var before: Vector2 = skip.global_position
	tiles[0].emit_signal("pressed")
	await get_tree().process_frame
	if take.disabled:
		_fails += 1; print("FAIL picking a relic left the take button dead")
	if not GameState.run_relics.is_empty():
		_fails += 1; print("FAIL pressing a relic tile took it outright")
	tiles[tiles.size() - 1].emit_signal("pressed")
	await get_tree().process_frame
	tiles[0].emit_signal("pressed")
	await get_tree().process_frame
	if not GameState.run_relics.is_empty():
		_fails += 1
		print("FAIL going back to a relic already read took it (%s)" % str(GameState.run_relics))
	for t in tiles:
		if t.disabled:
			_fails += 1
			print("FAIL a relic tile went dead without the offer being spent")
			break

	# ...and the button does spend it.
	take.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	if skip.global_position != before:
		_fails += 1
		print("FAIL taking a relic moved Skip from %s to %s" % [before, skip.global_position])
	if GameState.run_relics.size() != 1:
		_fails += 1
		print("FAIL the take button took %d relics" % GameState.run_relics.size())
	if not take.disabled:
		_fails += 1; print("FAIL the take button is still live after the offer was spent")
	for t in tiles:
		if not t.disabled:
			_fails += 1
			print("FAIL a relic tile is still live after one was taken")
			break

	# ...and it is ON DISK, now (D300). This is the "I already took that relic and it was offered
	# again" report, and it was never a rolling bug: `relic_offer` excludes `GameState.run_relics`,
	# and the run only holds what it managed to write down. The pick used to be saved when the
	# reward RESOLVED — a set taken or Skip pressed — so a phone that lost the app in between came
	# back with the relic gone from the run and the pool free to deal it again.
	var took: String = String(GameState.run_relics[0]) if not GameState.run_relics.is_empty() else ""
	if took != "" and not _saved_run_relics().has(took):
		_fails += 1
		print("FAIL %s was taken but the written run holds %s" % [took, _saved_run_relics()])
	inst.queue_free()
	await get_tree().process_frame

## What the run file on disk says this run is carrying. Read back rather than trusted, because the
## whole point of the check above is the gap between the two.
func _saved_run_relics() -> Array:
	if not FileAccess.file_exists(MetaState.run_file()):
		return []
	var f := FileAccess.open(MetaState.run_file(), FileAccess.READ)
	if f == null:
		return []
	var blob = JSON.parse_string(f.get_as_text())
	f.close()
	if not (blob is Dictionary):
		return []
	var run = blob.get("run", {})
	return run.get("run_relics", []) if run is Dictionary else []

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

## A card the run is GIVEN must be marked found, or the ratchet prices it (D299).
##
## Here rather than in `test_balance.gd`, which owns the pricing rule itself: that suite runs
## headless and `GameState.earn_card` reaches MetaState through `/root`, so a `--script` test
## watches it return early and assert nothing. The rule has two halves — the engine must not
## price a found card, and the game must actually mark one — and only a tree can see the second.
func _a_taken_card_is_marked_found() -> void:
	var id: String = MetaState.CATALOG.keys()[0]
	var before: int = GameState.run_deck.size()
	GameState.earn_card(id)
	if GameState.run_deck.size() != before + 1:
		_fails += 1
		print("FAIL earn_card did not add a card")
		return
	var got: CardData = GameState.run_deck[before]
	if not got.found_in_run:
		_fails += 1
		print("FAIL a card the run was given is not marked found — the ratchet will price it (D299)")
	# ...and the deck it was added to must still hold cards that are NOT marked, or the
	# assertion above would pass on a build that marked everything and priced nothing.
	var brought := 0
	for c in GameState.run_deck:
		if not c.found_in_run:
			brought += 1
	if brought == 0:
		_fails += 1
		print("FAIL every card in the run deck reads as found — nothing is left to price")
	# Put the run back exactly as it was. `earn_card` writes to the LIVE autoload, and the
	# layout checks further down this file measure a panel whose height depends on the deck
	# size — the dilution line quotes it. Leaving the card in moved the Skip button five
	# pixels and failed an assertion about relics, which is a fault in this test rather than
	# in the screen. **A check that mutates shared state has to hand it back.**
	GameState.run_deck.remove_at(before)
	if not GameState.escrow_cards.is_empty():
		GameState.escrow_cards.remove_at(GameState.escrow_cards.size() - 1)
