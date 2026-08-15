## Headless test: the boss signatures (D295) — the one thing a boss does that no number can say.
##
## Every assertion here DISCOVERS its subject. `EnemyData.signature_fields()` walks the property
## list, and this suite walks the whole enemy catalogue, so a field added later is a field this
## file already asks about. The alternative was tried three times in this project and failed three
## times the same way: D89's art list, D180's relic list and D250's rule-changer list were each a
## hand-kept list of what to check, and each went blind the moment somebody added a subject.
##
## For a signature the silence is total. A new field would be authored on a boss, honoured
## nowhere, shown to the player as a promise on the dungeon row, and every test in the tree would
## stay green — the fight would simply not do the thing the row said it would.
## Run: godot --headless --script tests/test_signature.gd
extends SceneTree

const SANDBOX := "t_test_signature_"

func _init() -> void:
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	Meta_.writes_disabled = true
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0

	var fields := EnemyData.signature_fields()
	if fields.size() < 4:
		fails += 1
		print("FAIL only %d signature fields discovered — the group has stopped being found" % fields.size())

	# --- every boss carries exactly one, and nothing else carries any ---
	#
	# Both halves, and the second is the one that matters. `count_max` lets an archetype spawn
	# three of itself; three copies each taking an Energy is not a signature, it is a softlock.
	var bosses := {}
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null and dd.boss != "":
			bosses[dd.boss] = did
	if bosses.size() != Balance.DUNGEONS.size():
		fails += 1; print("FAIL %d dungeons name %d distinct bosses" % [
			Balance.DUNGEONS.size(), bosses.size()])

	var used := {}
	for eid in _all_enemy_ids():
		var e := Balance.enemy(eid)
		if e == null:
			continue
		var carried: Array[String] = []
		for f in fields:
			var v = e.get(f)
			if (v is bool and v) or (not (v is bool) and int(v) != 0):
				carried.append(f)
		if bosses.has(eid):
			if carried.size() != 1:
				fails += 1; print("FAIL %s is a boss carrying %d signatures, not 1: %s" % [
					eid, carried.size(), carried])
			else:
				used[carried[0]] = int(used.get(carried[0], 0)) + 1
		elif not carried.is_empty():
			fails += 1; print("FAIL %s is not a boss and carries %s" % [eid, carried])

	# --- a hand cap may not go under the opening draw ---
	#
	# Above it, the cap takes only cards the player was holding and the knob dials. Below it, it
	# eats the base draw every turn and becomes the draw tax this group deleted for being a cliff:
	# measured, a cap of 4 against `HAND_SIZE` 5 cost the Draw build 61 points at the Sunken Vault
	# where a cap of 6 cost about 10. The boundary is the mechanism, so the boundary is asserted.
	for eid in bosses:
		var eb := Balance.enemy(eid)
		if eb != null and eb.sig_hand_cap > 0 and eb.sig_hand_cap < Balance.HAND_SIZE:
			fails += 1
			print("FAIL %s caps the hand at %d, under HAND_SIZE %d — that is a draw tax, not a ceiling" % [
				eid, eb.sig_hand_cap, Balance.HAND_SIZE])

	# --- every field is actually AUTHORED on somebody ---
	#
	# A field nobody uses is a rule the engine pays for and the player never meets. The reverse
	# of the discovery above, and the reason both are here: one catches a field the game reads
	# and nothing authors, the other a field somebody authors and the game does not read.
	for f in fields:
		if not used.has(f):
			fails += 1; print("FAIL %s is a signature no boss carries" % f)

	# --- every signature says something ---
	for eid in bosses:
		var e := Balance.enemy(eid)
		if e == null:
			continue
		if e.signature_text() == "":
			fails += 1; print("FAIL %s has a signature and no sentence for it" % eid)
		if not Balance.boss_warning(bosses[eid]).contains(e.signature_text().substr(1)):
			fails += 1; print("FAIL %s's row does not name what its fight will do" % bosses[eid])

	fails += _honoured()
	fails += _only_at_the_boss()
	fails += _survivable()

	if fails == 0:
		print("SIGNATURE TEST: PASS (%d fields, %d bosses, every one authored, honoured, named and survivable)" % [
			fields.size(), bosses.size()])
	else:
		print("SIGNATURE TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit(1 if fails > 0 else 0)

## A deck of plain cards, enough to play with.
func _deck(n: int = 20) -> Array[CardData]:
	var out: Array[CardData] = []
	for i in n:
		out.append((load("res://resources/cards/hack.tres") as CardData).duplicate())
	return out

## Set up a boss fight against `eid`, forced, so the signature is the only variable.
func _fight(eid: String) -> CombatEngine:
	var eng := CombatEngine.new()
	eng.setup(_deck(), 200, 200, 3, Balance.Tier.BOSS, eid, [], [], null, eid)
	return eng

## Each field must MOVE something the player can feel. Driven off the discovered list, so a
## field with no case here fails loudly rather than being skipped — which is the whole
## difference between this and a hand-written list of seven checks.
func _honoured() -> int:
	var fails := 0
	var plain := CombatEngine.new()
	plain.setup(_deck(), 200, 200, 3, Balance.Tier.BOSS, "cultist", [], [], null, "cultist")
	for f in EnemyData.signature_fields():
		var boss := ""
		for eid in _all_enemy_ids():
			var e := Balance.enemy(eid)
			if e != null:
				var v = e.get(f)
				if (v is bool and v) or (not (v is bool) and int(v) != 0):
					boss = eid
					break
		if boss == "":
			continue   # already reported above as unauthored
		var eng := _fight(boss)
		var moved := false
		match f:
			"sig_energy_tax":
				moved = eng.energy < plain.energy
			"sig_draw_tax":
				moved = eng.hand.size() < plain.hand.size()
			"sig_hand_cap":
				moved = eng.hand_cap() < plain.hand_cap()
			"sig_cards_per_turn":
				# Play until something refuses, and then ask WHAT refused. The first version of
				# this ran the hand empty and indexed `hand[0]` off the end, so the check errored
				# rather than asserting — and it was the one mutation of seven that did not fail
				# when the rule was deleted. **A check that can run out of subject reports the
				# same pass as a rule that works.**
				#
				# So: enough cards to outlast the cap, energy that cannot be the reason, and the
				# loop leaves the hand non-empty. Stopping with cards still in hand is the rule;
				# stopping with an empty hand is the hand.
				eng.draw_cards(6)
				var played := 0
				while played < 10 and eng.hand.size() > 1:
					eng.energy = 99
					if not eng.can_play(eng.hand[0]):
						break
					eng.play_card(eng.hand[0])
					played += 1
				moved = played < 10 and eng.hand.size() > 1
			"sig_block_worth_pct":
				var g := (load("res://resources/cards/cover.tres") as CardData).duplicate()
				moved = eng.card_block(g) < plain.card_block(g)
			"sig_exhaust_first":
				var before := eng.discard_pile.size()
				eng.energy = 99
				eng.play_card(eng.hand[0])
				moved = eng.discard_pile.size() == before   # it went out of the fight, not to the pile
			_:
				fails += 1
				print("FAIL %s is a signature this suite does not know how to check — add a case" % f)
				continue
		if not moved:
			fails += 1; print("FAIL %s is authored on %s and changes nothing in the fight" % [f, boss])
	return fails

## A signature is a BOSS's. The same archetype met as trash must play by the ordinary rules,
## because `count_max` would otherwise let three of them stack one.
func _only_at_the_boss() -> int:
	var fails := 0
	var eng := CombatEngine.new()
	eng.setup(_deck(), 200, 200, 3, Balance.Tier.NORMAL, "warden", [], [], null, "")
	if eng.hand_cap() != Balance.MAX_HAND_SIZE:
		fails += 1
		print("FAIL a boss archetype met as trash still capped the hand: %d" % eng.hand_cap())
	if not eng.signature.is_empty():
		fails += 1; print("FAIL a NORMAL fight carries a signature")
	return fails

## No signature may hand the player a turn they cannot take. An empty hand or no Energy is not
## a hard turn — it is a turn the player watches, and a fight the player watches is the one
## thing this whole group must not be able to produce.
func _survivable() -> int:
	var fails := 0
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd == null or dd.boss == "":
			continue
		var eng := _fight(dd.boss)
		for _turn in 12:
			if eng.energy < 1:
				fails += 1
				print("FAIL %s leaves a turn with no Energy" % dd.boss)
				break
			if eng.hand.is_empty():
				fails += 1
				print("FAIL %s leaves a turn with no cards in hand" % dd.boss)
				break
			if not eng.can_play(eng.hand[0]):
				fails += 1
				print("FAIL %s opens a turn with nothing the player can play" % dd.boss)
				break
			eng.end_turn()
			eng.start_turn()
	return fails

## Every archetype on disk, not a list of them. The same walker `tests/test_reactive.gd` uses,
## and for the same reason: an archetype added later has to be a subject of this suite without
## anybody remembering to add it.
func _all_enemy_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://resources/enemies/")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tres"):
			out.append(f.replace(".tres", ""))
	return out

func _cleanup_sandbox() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with(SANDBOX):
			d.remove(f)
