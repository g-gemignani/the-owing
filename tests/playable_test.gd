## Integration test: the game is actually PLAYABLE, not merely loadable.
##
## Written after a black screen reached a player. `map.gd` stopped compiling and
## stayed broken for five commits, each of which reported a fully green suite,
## because every existing test either read the file as text or checked
## `load(path) != null` — and `load()` happily returns a Resource for a script
## that failed to parse.
##
## The lesson had already been written down once, in D33: *booting is not
## playability*. It was enforced for one screen. This enforces it for all of them,
## and for every dungeon.
##
## What it asserts, in order of how badly each has bitten:
##
## 1. Every screen instantiates AND offers at least one thing the player can press.
## 2. Every dungeon can be entered, and its traversal view offers a reachable
##    encounter. This is the exact failure that was reported.
## 3. A combat can be played from the first card to victory, through the real
##    scene, not the engine alone.
## 4. A rest resolves and hands control back.
## Run: godot --headless res://tests/PlayableTest.tscn
extends Node

var _fails := 0

func _ready() -> void:
	# Headless defaults to a SQUARE 1280x1280 viewport, so every on-screen check in
	# every scene test has been measuring the wrong window. Use the shipped size.
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	UITheme.set_scale_silent(UITheme.UI_SCALE)   # and the shipped UI scale
	await get_tree().process_frame

	MetaState.path_prefix = "t_playable_"
	MetaState.slot = 0
	MetaState.new_save()

	await _every_screen_is_usable()
	await _every_dungeon_is_enterable()
	await _a_combat_can_be_won()
	await _a_rest_resolves()
	await _every_encounter_can_be_left()
	await _every_screen_has_a_way_out()
	await _the_score_plays()
	await _the_fight_shows_its_state()
	await _dying_is_reported()
	await _the_fight_reacts()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("PLAYABLE TEST: PASS (every screen usable, every dungeon enterable, combat winnable)")
	else:
		print("PLAYABLE TEST: FAIL (%d)" % _fails)
	get_tree().quit()

## --- 1. every screen gives the player something to do -----------------------
##
## A screen that instantiates but presents no enabled control is a dead end, and
## indistinguishable from a crash to whoever is holding the controller.
func _every_screen_is_usable() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}

	for name in _scene_names():
		# The three traversal views run on state only their own kind of dungeon
		# produces. Handing a dice board a graph run is a state the game never
		# creates, and one of them spins forever on it. Stage 2 covers all three
		# properly, once per dungeon, with the state they actually receive.
		if name in ["Map", "DeckRun", "DiceRun"]:
			continue
		var path := "res://scenes/%s.tscn" % name
		var packed := load(path) as PackedScene
		if packed == null:
			_fails += 1; print("FAIL %s does not load" % name); continue
		var inst = packed.instantiate()
		if inst == null:
			_fails += 1; print("FAIL %s does not instantiate" % name); continue
		add_child(inst)
		await get_tree().process_frame
		if not is_inside_tree():
			print("FAIL %s navigated away in _ready — it had no usable state" % name)
			return
		await get_tree().process_frame
		# the root script must have survived instantiation with its behaviour
		var sc = inst.get_script()
		if sc != null and (sc as GDScript).get_instance_base_type() == "":
			_fails += 1; print("FAIL %s root script did not compile" % name)
		var usable := _enabled_buttons(inst)
		if usable == 0:
			_fails += 1
			print("FAIL %s presents nothing the player can press — a dead end" % name)
		_no_scroll_is_crushed(inst, name)
		inst.queue_free()
		await get_tree().process_frame

## --- 2. every dungeon can actually be entered -------------------------------
##
## The reported bug exactly: enter the Crypt, get a black screen. Covers all three
## traversal models because the dungeons use all three.
func _every_dungeon_is_enterable() -> void:
	for did in Balance.DUNGEONS:
		_start_a_run(did)
		var scene_path: String = GameState.run_scene()
		var packed := load(scene_path) as PackedScene
		if packed == null:
			_fails += 1; print("FAIL %s: %s does not load" % [did, scene_path]); continue
		var inst = packed.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame

		var sc = inst.get_script()
		if sc != null and (sc as GDScript).get_instance_base_type() == "":
			_fails += 1
			print("FAIL %s: %s did not compile — the player gets a black screen" % [
				did, scene_path])
		elif _enabled_buttons(inst) == 0:
			_fails += 1
			print("FAIL %s: entered the dungeon and there is nothing to click" % did)
		# and the traversal itself must offer somewhere to go
		if GameState.traversal != null and GameState.traversal.options().is_empty():
			_fails += 1; print("FAIL %s offers no reachable encounter" % did)
		# ...and the map/board/deck it built must be on screen and not 0px
		_no_scroll_is_crushed(inst, did)
		inst.queue_free()
		await get_tree().process_frame

## --- 3. a fight can be played to the end through the real screen ------------
func _a_combat_can_be_won() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var eng = inst.eng
	if eng == null:
		_fails += 1; print("FAIL combat started with no engine"); inst.queue_free(); return
	# play greedily: everything affordable, then end the turn, until somebody wins
	var guard := 0
	while not eng.over() and guard < 200:
		guard += 1
		var played := false
		for card in eng.hand.duplicate():
			if eng.can_play(card):
				eng.play_card(card)
				played = true
		if not played or eng.energy <= 0:
			eng.end_turn()
	if guard >= 200:
		_fails += 1; print("FAIL a combat never ended after 200 turns")
	elif not eng.won():
		# losing a fight is legal, but a starter deck should beat a d1 normal
		_fails += 1; print("FAIL a starter deck lost a first-dungeon fight")
	else:
		# Mid-fight the screen offers a way out, because the fight is serialized and
		# Resume returns to this turn. Between the killing blow and the reward pick
		# it must NOT: the encounter is not cleared until the reward is taken, so
		# stepping out there and coming back would offer the same fight again.
		if not UI.has_escape():
			_fails += 1; print("FAIL a fight in progress cannot be left")
		inst._win()
		await get_tree().process_frame
		if UI.has_escape() or not inst.menu_btn.disabled:
			_fails += 1
			print("FAIL combat can be left between the kill and the reward — the fight is re-offerable")
	inst.queue_free()
	await get_tree().process_frame

## --- 4. a rest resolves and returns control ---------------------------------
func _a_rest_resolves() -> void:
	_start_a_run("crypt")
	var inst = (load(GameState.run_scene()) as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame

	var resolved := [false]
	var node := {"type": GameState.NodeType.REST, "row": 0, "col": 0, "cleared": false}
	GameState.hp = 10
	RunFlow.enter_node(inst, node, func(): resolved[0] = true)
	await get_tree().process_frame
	# a rest is a choice now, so it must put a choice on screen
	if _enabled_buttons(inst) == 0:
		_fails += 1; print("FAIL resting presents no options")
	# take the first offered option and confirm control comes back
	for b in _buttons(inst):
		if not b.disabled and String(b.text).begins_with("Recover"):
			b.pressed.emit()
			break
	await get_tree().process_frame
	if not resolved[0]:
		_fails += 1; print("FAIL resting never handed control back to the map")
	if GameState.hp <= 10:
		_fails += 1; print("FAIL resting did not heal")
	inst.queue_free()
	await get_tree().process_frame

## --- 5. every encounter can be entered AND left ------------------------------
##
## The gap that let a broken shop reach a player: screens were checked in
## isolation and dungeons were checked as enterable, but nothing walked a run
## through an encounter and back out. A screen whose exit is unreachable — or
## which fails to clear its node, so the map keeps offering it — looks exactly
## like "I entered and now I cannot continue".
func _every_encounter_can_be_left() -> void:
	var types := {
		GameState.NodeType.SHOP: "res://scenes/Shop.tscn",
		GameState.NodeType.EVENT: "res://scenes/Encounter.tscn",
		GameState.NodeType.TREASURE: "res://scenes/Encounter.tscn",
	}
	for did in ["crypt", "ossuary", "ember_road"]:   # graph, deck, dice
		for t in types:
			_start_a_run(did)
			var tv = GameState.traversal
			if tv.options().is_empty():
				_fails += 1; print("FAIL %s offers nothing to enter" % did); continue
			# take a real option and make it the encounter under test
			var node = tv.select(0)
			node["type"] = t
			GameState.pending = node
			GameState.shop_stock = []

			var inst = (load(types[t]) as PackedScene).instantiate()
			add_child(inst)
			await get_tree().process_frame
			await get_tree().process_frame

			# there must be a way out, and it must be ON SCREEN
			var vp := get_viewport().get_visible_rect()
			var exits := 0
			var offscreen := 0
			for b in _buttons(inst):
				if b.disabled or not b.visible:
					continue
				if b.pressed.get_connections().is_empty():
					continue
				exits += 1
				if not vp.intersects(b.get_global_rect()):
					offscreen += 1
			if exits == 0:
				_fails += 1
				print("FAIL %s in %s offers no working button — the run is stuck" % [
					Balance.NODE_LABEL.get(t, "?"), did])
			elif offscreen == exits:
				_fails += 1
				print("FAIL every button in %s (%s) is off screen at %dx%d" % [
					Balance.NODE_LABEL.get(t, "?"), did, int(vp.size.x), int(vp.size.y)])
			inst.queue_free()
			await get_tree().process_frame

			# ...and leaving must actually release the node, or the map re-offers it
			GameState.clear_node(GameState.pending)
			if tv.options().is_empty() and int(node["type"]) != GameState.NodeType.BOSS:
				_fails += 1
				print("FAIL %s: after a %s the run has nowhere left to go" % [
					did, Balance.NODE_LABEL.get(t, "?")])

## --- 6. every screen has a way out, and Escape takes it ----------------------
##
## Escape used to leave fullscreen on every screen in the game, and Combat had no
## exit control at all — the longest scene was the only one you could not leave.
## Both are one registration now (`UI.exit_button` binds the button and the key to
## the same Callable), so what needs pinning is that each screen actually makes it.
## An exit that exists only as a button is an exit that a player who pressed
## Escape did not find.
##
## The screens listed here declare none ON PURPOSE, and the test says so, because
## "no exit" and "forgot the exit" look identical from the outside.
const NO_EXIT := {
	"MainMenu": "the root screen: there is nothing behind it",
	"Overworld": "the hub; the way out is Save and quit, which must be deliberate",
	"Encounter": "an event is a decision, and every event has a cost-free option",
}

func _every_screen_has_a_way_out() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	for name in _scene_names():
		var path := "res://scenes/%s.tscn" % name
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		if name in ["Map", "DeckRun", "DiceRun"]:
			# same reason as stage 1: these need their own kind of run state
			_start_a_run(_a_dungeon_using(name))
			if GameState.run_scene() != path:
				continue
		var inst = packed.instantiate()
		UI.clear_escape(self)   # so a leftover registration cannot answer for this screen
		add_child(inst)
		await get_tree().process_frame
		if not is_inside_tree():
			return
		await get_tree().process_frame
		var declared := UI.has_escape()
		if NO_EXIT.has(name):
			if declared:
				_fails += 1
				print("FAIL %s declares an Escape action but is listed as deliberately having none" % name)
		elif not declared:
			_fails += 1
			print("FAIL %s offers no way out — Escape does nothing on it" % name)
		inst.queue_free()
		await get_tree().process_frame

## --- 7. the score plays, and on the bus its slider drives --------------------
##
## test_art.gd checks the files and the tables from source. This is the half that
## needs a running engine: that a track is actually playing, that it is on the
## Music bus (a track on SFX would make the Music slider a placeholder again, the
## exact bug this replaced), and that a fight against a boss sounds different from
## the corridor outside it.
func _the_score_plays() -> void:
	Audio.play_music("dungeon")
	await get_tree().process_frame
	if Audio.current_score() != "dungeon":
		_fails += 1; print("FAIL asked for the dungeon score and nothing is playing")
	if Audio.music_bus() != "Music":
		_fails += 1
		print("FAIL the score plays on the %s bus, so the Music slider does nothing" % Audio.music_bus())

	GameState.pending = {"type": GameState.NodeType.BOSS}
	var boss := Audio.score_for("Combat")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	var normal := Audio.score_for("Combat")
	if boss == normal:
		_fails += 1; print("FAIL a boss fight sounds exactly like a normal one")
	if Audio.score_for("SomeScreenNobodyListed") == "":
		_fails += 1; print("FAIL an unlisted screen gets no score — new screens would be silent")

## No ScrollContainer may be squeezed to nothing on an axis its content needs.
##
## Written after the dice board turned out to be **0px tall in the shipped window**.
## `dice_run.gd` left both scroll modes at AUTO, and a ScrollContainer reports a
## minimum size of 0 on any axis it can scroll — so the `SIZE_EXPAND_FILL` spacers
## around it took every pixel. Sixteen track cells were built on every refresh and
## none of them had anywhere to be drawn.
##
## Every check in this suite passed throughout: the scene loads, its script compiles,
## its buttons are enabled and pressable, and `test_layout.gd` confirms the
## scroll-to-token function exists by reading the file as text. What none of them
## asked was whether the content had a **size**. This is D47 again — booting is not
## playability — and the generalisation is deliberate: the same shape would hide the
## map, the shop stock or the collection just as silently.
func _no_scroll_is_crushed(n: Node, where: String) -> void:
	for sc in _scrolls(n):
		if not sc.is_visible_in_tree():
			continue
		for content in sc.get_children():
			var c := content as Control
			if c == null:
				continue
			var need := c.get_combined_minimum_size()
			var have := sc.size
			if need.y > 0.0 and have.y <= 0.0:
				_fails += 1
				print("FAIL %s: a scroll area is 0px TALL holding %.0fpx of content — invisible" % [
					where, need.y])
			if need.x > 0.0 and have.x <= 0.0:
				_fails += 1
				print("FAIL %s: a scroll area is 0px WIDE holding %.0fpx of content — invisible" % [
					where, need.x])

func _scrolls(n: Node) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	if n is ScrollContainer:
		out.append(n as ScrollContainer)
	for c in n.get_children():
		out.append_array(_scrolls(c))
	return out

## --- 8. the fight shows the state the player is reasoning about ---------------
##
## Three things were being asked for and not shown: how deep the draw pile is
## (while the reward screen quotes draw intervals and the shop sells thinning),
## which cards are affordable (the only way to find out was to click and be
## refused), and more than one line of what just happened.
func _the_fight_shows_its_state() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame

	var eng = inst.eng
	if eng == null:
		_fails += 1; print("FAIL combat started with no engine"); inst.queue_free(); return

	var piles := String(inst.piles_label.text)
	if piles.find(str(eng.draw_pile.size())) == -1 or piles.find(str(eng.discard_pile.size())) == -1:
		_fails += 1
		print("FAIL the fight does not show the draw and discard piles (says '%s')" % piles)

	# Strength must be legible AND on the cards. This is the reported bug: the buff
	# applied, and nothing the player was looking at changed.
	eng.player.strength = 4
	inst._refresh()
	await get_tree().process_frame
	if not inst.buffs_label.visible or String(inst.buffs_label.text).find("Strength") == -1:
		_fails += 1
		print("FAIL 4 Strength is not stated anywhere on the combat screen")
	var buffed := false
	for card in eng.hand:
		if card.eff_damage() <= 0:
			continue
		var shown: String = eng.card_text(card)
		if shown.find(str(eng.card_damage(card))) == -1:
			_fails += 1
			print("FAIL a card in hand does not show what it would deal with Strength")
		if eng.card_damage(card) > card.eff_damage():
			buffed = true
	if not buffed:
		_fails += 1; print("FAIL no attack card in hand reflected Strength at all")

	# an unaffordable card must look different from an affordable one
	eng.energy = 0
	inst._refresh()
	await get_tree().process_frame
	var dimmed := 0
	for holder in inst.hand_box.get_children():
		if (holder as Control).modulate.a < 0.9:
			dimmed += 1
	if dimmed == 0 and not eng.hand.is_empty():
		_fails += 1
		print("FAIL with no energy left, every card still looks playable")

	# the log keeps more than the last thing that happened
	inst._log("one")
	inst._log("two")
	if String(inst.log_label.text).find("one") == -1:
		_fails += 1; print("FAIL the combat log still shows only the last line")
	inst.queue_free()
	await get_tree().process_frame

## --- 9. dying is reported, not flashed past -----------------------------------
##
## Death used to be one line of status text and `await create_timer(2.5)` before
## the player was moved on. Escrow, ropes and the death penalty all exist to make
## that moment weigh; it has to be readable, and dismissed by the player.
func _dying_is_reported() -> void:
	GameState.last_defeat = {
		"dungeon": "The Crypt", "difficulty": 1, "killer": "Crypt Hound",
		"tier": Balance.Tier.NORMAL, "turns": 6,
		"forfeited_cards": 3, "forfeited_gold": 140,
		"penalty_gold": 25, "penalty_cards": ["strike"],
	}
	UI.clear_escape(self)
	var inst = (load("res://scenes/Defeat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var text := _all_text(inst)
	for needed in ["Crypt Hound", "The Crypt", "3", "140", "25"]:
		if text.find(needed) == -1:
			_fails += 1
			print("FAIL the defeat screen never mentions '%s'" % needed)
	if _enabled_buttons(inst) == 0:
		_fails += 1; print("FAIL the defeat screen cannot be dismissed")
	if not UI.has_escape():
		_fails += 1; print("FAIL Escape does nothing on the defeat screen")
	inst.queue_free()
	GameState.last_defeat = {}
	await get_tree().process_frame

	# ...and combat must actually route there rather than waiting on a timer
	var src := FileAccess.open("res://scripts/combat.gd", FileAccess.READ)
	if src != null:
		var t := src.get_as_text()
		src.close()
		if t.find("Defeat.tscn") == -1:
			_fails += 1; print("FAIL losing a fight does not lead to the defeat screen")
		if t.find("create_timer") != -1:
			_fails += 1
			print("FAIL combat still waits on a timer instead of letting the player read the result")

## --- 10. the fight reacts to what happens in it -------------------------------
##
## Nothing in this game moved: `_refresh()` freed the enemy row and the whole hand
## and built them again on every action, so HP numbers jumped, nothing flashed, and
## a played card blinked out of existence. You cannot tween between two states when
## one of them has been deleted.
##
## The load-bearing assertion is the third one. Damage numbers and flashes are
## visible enough that their absence gets noticed; **widgets surviving a refresh**
## is invisible, and a future edit that goes back to rebuilding would silently take
## every animation with it while leaving the screen looking correct in a still.
func _the_fight_reacts() -> void:
	_start_a_run("crypt")
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var inst = (load("res://scenes/Combat.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var eng = inst.eng
	if eng == null:
		_fails += 1; print("FAIL combat started with no engine"); inst.queue_free(); return

	# feedback must never be able to swallow a click meant for a card
	if inst.fx_layer.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fails += 1; print("FAIL the effects layer can intercept the mouse")
	if inst.hurt_veil.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fails += 1; print("FAIL the hurt flash can intercept the mouse")

	# a card that stays in hand must keep its node across a refresh
	var keeper = null
	for card in eng.hand:
		if not eng.can_play(card):
			keeper = card
			break
	if keeper == null and eng.hand.size() > 1:
		keeper = eng.hand[eng.hand.size() - 1]
	var node_before = inst.card_widgets.get(keeper) if keeper != null else null
	inst._refresh()
	await get_tree().process_frame
	var node_after = inst.card_widgets.get(keeper) if keeper != null else null
	if keeper == null:
		_fails += 1; print("FAIL no card in hand to check for widget reuse")
	elif node_before == null or node_after != node_before:
		_fails += 1
		print("FAIL the hand is rebuilt rather than updated — nothing can animate between two states")

	# playing a damaging card must float a number and take the card out of the hand
	var attack = null
	for card in eng.hand:
		if eng.can_play(card) and eng.card_damage(card) > 0:
			attack = card
			break
	if attack == null:
		_fails += 1; print("FAIL no affordable attack in the opening hand")
	else:
		var fx_before: int = inst.fx_layer.get_child_count()
		var hand_before: int = eng.hand.size()
		inst._on_card_pressed(attack)
		await get_tree().process_frame
		if inst.fx_layer.get_child_count() <= fx_before:
			_fails += 1
			print("FAIL dealing damage shows nothing — no number, no reaction")
		else:
			# and it has to actually MOVE: a label parked on the spot is the same
			# static screen with extra steps, which is exactly what a tween that was
			# never started looks like
			var floater: Control = null
			for c in inst.fx_layer.get_children():
				if c is Label:
					floater = c
			if floater == null:
				_fails += 1; print("FAIL the damage number is not a label that can move")
			else:
				var y0: float = floater.position.y
				await get_tree().create_timer(0.15).timeout
				if is_instance_valid(floater) and floater.position.y >= y0:
					_fails += 1
					print("FAIL the damage number does not move — the tween never ran")
		if eng.hand.size() != hand_before - 1:
			_fails += 1; print("FAIL the played card is still in hand")
		if inst.card_widgets.has(attack):
			_fails += 1; print("FAIL the played card's widget was never released")
		# hand_box holds real cards only: the flown-out one is reparented, not left
		if inst.hand_box.get_child_count() != eng.hand.size():
			_fails += 1
			print("FAIL hand_box holds %d widgets for %d cards" % [
				inst.hand_box.get_child_count(), eng.hand.size()])

	# and being hit must register on the screen, not only in the log
	inst.hurt_veil.color.a = 0.0
	var before := {"player": eng.player.hp + 12, "block": eng.player.block}
	inst._show_deltas(before)
	await get_tree().process_frame
	if inst.hurt_veil.color.a <= 0.0:
		_fails += 1; print("FAIL taking 12 damage does not register anywhere on screen")
	inst.queue_free()
	await get_tree().process_frame

func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += String((n as Label).text) + "\n"
	if n is Button:
		out += String((n as Button).text) + "\n"
	for c in n.get_children():
		out += _all_text(c)
	return out

func _a_dungeon_using(scene_name: String) -> String:
	for did in Balance.DUNGEONS:
		GameState.select_dungeon(did)
		if GameState.run_scene().ends_with("%s.tscn" % scene_name):
			return did
	return "crypt"

# --- helpers -----------------------------------------------------------------

## A legal run, ready to play: a real deck, a real map, a real power.
func _start_a_run(dungeon_id: String) -> void:
	MetaState.new_save()
	GameState.reset_run_progress()
	GameState.select_dungeon(dungeon_id)
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var e: Dictionary = MetaState.collection[id]
		for i in int(e["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(e["level"])
			deck.append(c)
	GameState.enter_dungeon(deck)
	GameState.hp = GameState.max_hp
	# Screens bail out by NAVIGATING when their state is missing — ZoneView with no
	# zone calls change_scene_to_file, which in a harness replaces the test scene
	# itself and hangs the await forever. Every screen therefore gets plausible
	# state, the same way the game would have given it some.
	var z := Balance.zone_of(dungeon_id)
	GameState.current_zone = z.id if z != null else Balance.ZONES[0]
	GameState.last_relic = ""

func _scene_names() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://scenes/")
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".tscn"):
			out.append(f.replace(".tscn", ""))
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n as Button)
	for c in n.get_children():
		out.append_array(_buttons(c))
	return out

func _enabled_buttons(n: Node) -> int:
	var count := 0
	for b in _buttons(n):
		if not b.disabled:
			count += 1
	return count

func _purge() -> void:
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
