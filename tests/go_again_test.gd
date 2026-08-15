## Runtime test: the way straight back down after a death (D292).
##
## A SCENE test rather than a `--script` one, and not by preference. `go_again` rebuilds a
## whole run opening — the door, the loadout at today's levels, the grudge relics, the power
## offer, the generated floor — and every one of those reaches MetaState through
## `/root/MetaState`, which a `--script` run does not have. A unit test of this would be a
## test of the three lines that do not need one.
##
## The assertion that matters is the SECOND one. Both teardowns — `reset_run_progress` and
## `clear_run` — have already run by the time the Defeat screen is drawn, and between them they
## throw away the dungeon and the deck. The feature is exactly "these three fields survive
## that", so a test that recorded them and read them back without the teardown in between
## would pass on a build where the button never appears.
## Run: godot --headless res://tests/GoAgainTest.tscn
extends Node

const SANDBOX := "t_goagain_"

var _fails := 0

func _ready() -> void:
	# One frame first: the root is still adding THIS node during `_ready`.
	await get_tree().process_frame
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()

	_records()
	_survives_the_teardown()
	_restarts()
	_refuses()
	await _the_button()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("GO AGAIN TEST: PASS (recorded, survives both teardowns, restarts, refuses, and the button is on the screen)")
	else:
		print("GO AGAIN TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## A run of the smallest legal deck, started the way the deck builder starts one.
func _open_a_run(id: String = "crypt") -> Dictionary:
	var loadout := _starter_loadout()
	GameState.reset_run_progress()
	GameState.select_dungeon(id)
	GameState.enter_dungeon(MetaState.build_deck(loadout))
	return loadout

## Whatever the save actually holds, taken up to a legal deck. Derived rather than written
## out, because `MIN_DECK_SIZE` moves (D293) and a hand-listed twelve would quietly become an
## illegal deck and fail this suite for the wrong reason.
func _starter_loadout() -> Dictionary:
	var out := {}
	var n := 0
	for id in MetaState.collection:
		var take: int = mini(MetaState.owned(id), Balance.MIN_DECK_SIZE - n)
		if take <= 0:
			continue
		out[id] = take
		n += take
		if n >= Balance.MIN_DECK_SIZE:
			break
	return out

func _records() -> void:
	var loadout := _open_a_run()
	if GameState.again_dungeon != "crypt":
		_fails += 1; print("FAIL the door was not recorded: '%s'" % GameState.again_dungeon)
	var want := 0
	for id in loadout:
		want += int(loadout[id])
	var got := 0
	for id in GameState.again_loadout:
		got += int(GameState.again_loadout[id])
	if got != want:
		_fails += 1; print("FAIL the loadout was recorded as %d cards, not %d" % [got, want])

## The one that would catch a regression. Both teardowns, in the order `combat.gd::_lose`
## runs them, and the offer has to be alive on the far side.
func _survives_the_teardown() -> void:
	_open_a_run()
	GameState.reset_run_progress()
	GameState.clear_run()
	if GameState.dungeon_id != "":
		_fails += 1; print("FAIL the teardown did not clear the run, so this proves nothing")
	if not GameState.can_go_again():
		_fails += 1; print("FAIL can_go_again is false after the teardown the Defeat screen runs behind")

func _restarts() -> void:
	_open_a_run()
	GameState.hp = 3
	GameState.escrow_gold = 250
	GameState.escrow_cards = ["hack"]
	GameState.reset_run_progress()
	GameState.clear_run()
	var purse: int = MetaState.gold
	if not GameState.go_again():
		_fails += 1; print("FAIL go_again refused a run it had just recorded")
		return
	if GameState.dungeon_id != "crypt":
		_fails += 1; print("FAIL the retry opened '%s' rather than the same door" % GameState.dungeon_id)
	if GameState.run_deck.size() < Balance.MIN_DECK_SIZE:
		_fails += 1; print("FAIL the retry built %d cards, under the legal floor" % GameState.run_deck.size())
	if GameState.hp != GameState.max_hp:
		_fails += 1; print("FAIL the retry started on %d of %d HP" % [GameState.hp, GameState.max_hp])
	if GameState.escrow_gold != 0 or not GameState.escrow_cards.is_empty():
		_fails += 1; print("FAIL the retry carried the dead run's escrow")
	if GameState.traversal == null:
		_fails += 1; print("FAIL the retry generated no floor")
	# No debt, and this is the half that costs the player money if it goes wrong. A retry that
	# re-took the door's wager would spend the purse on a screen that promises to save a walk.
	if MetaState.gold != purse:
		_fails += 1; print("FAIL the retry moved the purse: %d -> %d" % [purse, MetaState.gold])
	if GameState.pending_debt:
		_fails += 1; print("FAIL the retry is still carrying a pending debt")
	# ...and the power offer is dealt again rather than inherited (D245).
	if GameState.power_offer.is_empty():
		_fails += 1; print("FAIL the retry dealt no power offer")

func _refuses() -> void:
	# A door that is no longer open. An Ascension re-locks every dungeon, and a retry that
	# ignored the gate would walk a starting collection into difficulty 8.
	#
	# The deepest door has to be OPENED first, and asserted open, or this proves nothing: on a
	# fresh save the Maw is locked already, so "locked dungeons are refused" would pass against
	# a `can_go_again` that had never learned to ask. That is the vacuous-invariant trap D86
	# was written about, and the first version of this block walked straight into it.
	var cleared: Array = MetaState.cleared_dungeons.duplicate()
	var depths: Dictionary = MetaState.depth_records.duplicate()
	MetaState.cleared_dungeons = []
	for did in Balance.DUNGEONS:
		if did != Balance.final_dungeon():
			MetaState.cleared_dungeons.append(did)
	_open_a_run(Balance.final_dungeon())
	GameState.reset_run_progress()
	GameState.clear_run()
	if not GameState.can_go_again():
		_fails += 1; print("FAIL the deepest door was not open even with every other one cleared")
	# BOTH, because a gate takes depth in places that beat you as well as clears (D178) —
	# emptying only the clears would leave the door open on depth credit.
	MetaState.cleared_dungeons = []
	MetaState.depth_records = {}
	if GameState.can_go_again():
		_fails += 1; print("FAIL a re-locked dungeon is still offered")
	MetaState.cleared_dungeons = cleared
	MetaState.depth_records = depths

	# A deck the collection can no longer build. `build_deck` clamps to what is owned and
	# hands back a SHORTER deck rather than failing, so nothing here throws — the only thing
	# that can catch it is the size rule.
	_open_a_run()
	GameState.reset_run_progress()
	GameState.clear_run()
	var kept: Dictionary = MetaState.collection.duplicate(true)
	MetaState.collection = {}
	if GameState.can_go_again():
		_fails += 1; print("FAIL an unbuildable loadout is still offered")
	MetaState.collection = kept
	if not GameState.can_go_again():
		_fails += 1; print("FAIL putting the collection back did not put the offer back")

	# Nothing played at all. A fresh boot has no run to repeat.
	GameState.again_dungeon = ""
	GameState.again_loadout = {}
	if GameState.can_go_again():
		_fails += 1; print("FAIL a session with no run behind it is offered a retry")

## The affordance itself, on the screen, both ways round (D205b: test the click, not the
## promise). Presence alone would pass on a button that is always there, so the screen is
## built twice — once where the retry is available and once where it is not.
func _the_button() -> void:
	_open_a_run()
	GameState.reset_run_progress()
	GameState.clear_run()
	GameState.last_defeat = {"dungeon": "The Crypt", "difficulty": 1, "killer": "A Cultist",
		"tier": Balance.Tier.NORMAL, "turns": 4, "depth": 1, "floors": 2}

	var with_offer := await _defeat_buttons()
	if not with_offer.has(true):
		_fails += 1; print("FAIL the Defeat screen has no Go again button when one is available")
	else:
		var wired := false
		for b in with_offer[true]:
			if not (b as Button).pressed.get_connections().is_empty():
				wired = true
		if not wired:
			_fails += 1; print("FAIL the Go again button is on the screen and connected to nothing")

	GameState.again_dungeon = ""
	GameState.again_loadout = {}
	var without := await _defeat_buttons()
	if without.has(true):
		_fails += 1; print("FAIL the Defeat screen offers a retry with no run behind it")
	GameState.last_defeat = {}

## Build Defeat.tscn and return {true: [the Go again buttons]} — a dictionary rather than an
## array so "none of them" and "the screen failed to build" cannot read the same.
func _defeat_buttons() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	get_tree().root.add_child(vp)
	var scr := (load("res://scenes/Defeat.tscn") as PackedScene).instantiate() as Control
	vp.add_child(scr)
	await get_tree().process_frame
	var out := {}
	for b in _walk(scr):
		if b.text.begins_with("Go again"):
			if not out.has(true):
				out[true] = []
			out[true].append(b)
	vp.queue_free()
	return out

func _walk(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with(SANDBOX):
			d.remove(f)
