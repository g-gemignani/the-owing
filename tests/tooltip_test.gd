## Runtime test: every tooltip the game writes can actually be hovered.
##
## Written after a play report — "hovering a card in the collection should show
## what it does". The text already existed; it was set on `Label`s, and Label
## defaults to MOUSE_FILTER_IGNORE, so the mouse passed straight through and no
## tooltip ever appeared. Three screens shipped explanations nobody could read.
##
## This is a SCENE, not a `--script` test: mouse_filter is a runtime property of a
## built tree, and autoloads are not registered in headless script runs.
## Run: godot --headless res://tests/TooltipTest.tscn
extends Node

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_tooltip_"

const SCENES := [
	"res://scenes/Collection.tscn",
	"res://scenes/DeckBuilder.tscn",
	"res://scenes/Shop.tscn",
]

## The screens that list cards as ROWS, and so owe the player both ways into the full card
## (D205b). The shop is not one of them any more (D300): it lays its stock out as painted faces at
## reward size, so the whole card is already on the shelf and there is no thumbnail or clipped
## sentence to click through to. Removing it from this list is not dropping the guarantee — the
## guarantee was "you can see the card you are buying", and the shop now answers it by drawing the
## card rather than by promising one behind a 28px picture.
const LIST_SCENES := [
	"res://scenes/Collection.tscn",
	"res://scenes/DeckBuilder.tscn",
]

var _fails := 0

func _ready() -> void:
	# sandbox: a test must never touch the player's save (one previously did)
	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()
	GameState.dungeon_id = Balance.DUNGEONS[0]

	for path in SCENES:
		await _check(path)
	for path in LIST_SCENES:
		await _check_preview_reachable(path)
	# ...and the shop still has to show the card it is selling, by whichever means. Drawn as a
	# real face now, so the check is that a face is there at all.
	await _check_shop_draws_its_stock()
	await _check_unmet_relics_are_dead()
	await _check_locked_powers_are_dead()

	# the collection specifically must explain each card, not just be hoverable
	await _check_collection_explains()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("TOOLTIP TEST: PASS (every tooltip is reachable, every card row opens from picture and text, collection explains each card)")
	else:
		print("TOOLTIP TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _check(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load ", path); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	for c in _controls(inst):
		if c.tooltip_text != "" and c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			_fails += 1
			print("FAIL unreachable tooltip on %s (%s) in %s: %s" % [
				c.name, c.get_class(), path, c.tooltip_text.get_slice("\n", 0)])
	inst.queue_free()
	await get_tree().process_frame

## Every card in every list must be openable from its PICTURE and from its TEXT (D205b).
##
## Same failure shape as the one this suite was written for, one step along. There the
## tooltips existed and could not be hovered; here the preview existed and could only be
## reached from a 28px thumbnail at the far left of the row — not the part anyone is
## reading — and in the shop it could not be reached at all. That was the worst of the
## three to be missing: the only card list where the decision costs gold and cannot be
## undone.
##
## Counted as a PAIR rather than as a total, and that is the whole assertion. Both ways in
## exist for every row or neither does, so a screen that grows a new kind of card row and
## wires only the picture fails here instead of shipping half an affordance. The probe is
## the tooltip text, not a node name or a class: `inspect_thumb` and `inspect_text` both
## promise the player the same thing in words, and that promise is the feature.
const PREVIEW_PROMISE := "click to see the whole card"

## The shop's own half of D205b, after the stall stopped being a table (D300).
##
## The rule has not moved: the one list where a card costs gold and cannot be given back must show
## the player the card. It is answered differently now — the face IS the row — so the check is that
## every item on the shelf carries a real painted card and that none of those faces buys anything
## when pressed. The second half is the reason the first is safe: a card you can read by tapping is
## only an improvement if the tap cannot spend your gold.
func _check_shop_draws_its_stock() -> void:
	var scene := load("res://scenes/Shop.tscn") as PackedScene
	if scene == null:
		return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var faces := 0
	var pressable := 0
	for c in _controls(inst):
		if not c.has_meta("card_id"):
			continue
		faces += 1
		for kid in c.get_children():
			var b := kid as Button
			if b != null and b.pressed.get_connections().size() > 0:
				pressable += 1
	# Guarded, because "0 faces for 0 cards" is the shape this check would pass on for ever if the
	# merchant ever stopped rolling stock in a test save.
	if faces == 0:
		_fails += 1
		print("FAIL the shop drew no card faces at all")
	elif faces != GameState.shop_stock.size():
		_fails += 1
		print("FAIL the shop stocks %d cards and draws %d faces" % [
			GameState.shop_stock.size(), faces])
	if pressable > 0:
		_fails += 1
		print("FAIL %d shop card faces commit when pressed; only the price button may" % pressable)
	inst.queue_free()
	await get_tree().process_frame

## An unmet relic is greyed out AND dead (D308).
##
## Two halves, and the second is the one that fails silently. A tile that is only DIMMED still
## takes a press, and answering it with "there is nothing here" teaches the player to press it
## again — so the check is `disabled`, not the colour. The met half is asserted beside it, or the
## whole thing passes on a screen where nothing can be pressed at all.
func _check_unmet_relics_are_dead() -> void:
	# One met relic and the rest not, so both halves of the screen exist in one capture. Deep
	# enough that the pool is not all sealed, which would leave nothing to meet.
	MetaState.new_save()
	for did in Balance.DUNGEONS:
		MetaState.clear_counts[did] = 1
	var met := String(MetaState.RELIC_CATALOG.keys()[0])
	MetaState.note_relic_seen(met)

	var scene := load("res://scenes/Relics.tscn") as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load the Relics screen"); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var live := 0
	var dead := 0
	for c in _controls(inst):
		var b := c as Button
		if b == null or b.custom_minimum_size.x != UITheme.px(UI.RELIC_TILE_W):
			continue
		if b.disabled:
			dead += 1
		else:
			live += 1
	if dead == 0:
		_fails += 1
		print("FAIL every relic tile is pressable — an unmet one has nothing to show")
	if live != 1:
		_fails += 1
		print("FAIL %d relic tiles are live against 1 relic met" % live)
	inst.queue_free()
	await get_tree().process_frame

## A locked power is greyed and dead, and only the one button levels anything (D312).
##
## The same pair the Relics screen is checked on, for the same reason: gold does not buy a power,
## the place that holds it does, so a locked tile has nothing behind a press. And a tile must not
## be able to SPEND — the level button is the only control on the screen that acts, which is D307's
## rule applied to the second screen that grew a wall of tiles.
func _check_locked_powers_are_dead() -> void:
	MetaState.new_save()
	MetaState.gold = 5000
	var held := String(Balance.POWERS[0])
	MetaState.powers = {held: 1}

	var scene := load("res://scenes/Powers.tscn") as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load the Powers screen"); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var live := 0
	var dead := 0
	for c in _controls(inst):
		var b := c as Button
		if b == null or b.custom_minimum_size.x != UITheme.px(UI.RELIC_TILE_W):
			continue
		if b.disabled:
			dead += 1
		else:
			live += 1
	if dead == 0:
		_fails += 1
		print("FAIL every power tile is pressable — a locked one has nothing to show")
	if live != 1:
		_fails += 1
		print("FAIL %d power tiles are live against 1 power held" % live)

	# Pressing the held tile reads it and arms the button, and takes no gold doing it.
	var gold_was: int = MetaState.gold
	for c in _controls(inst):
		var b := c as Button
		if b != null and not b.disabled \
				and b.custom_minimum_size.x == UITheme.px(UI.RELIC_TILE_W):
			b.emit_signal("pressed")
			break
	await get_tree().process_frame
	if MetaState.gold != gold_was:
		_fails += 1; print("FAIL pressing a power tile spent gold")
	if inst.picked != held:
		_fails += 1; print("FAIL pressing a power tile did not select it")
	if inst.up_btn.disabled:
		_fails += 1; print("FAIL the level button is dead with a levellable power picked")
	# ...and the line says what the level BUYS, which is the whole of the report.
	if not inst.reader.text.contains("would buy"):
		_fails += 1
		print("FAIL the reader does not say what the next level buys: %s" % inst.reader.text)
	inst.queue_free()
	await get_tree().process_frame

func _check_preview_reachable(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		return          # `_check` above has already reported the load failure
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var from_picture := 0
	var from_text := 0
	for c in _controls(inst):
		if c.tooltip_text.find(PREVIEW_PROMISE) == -1:
			continue
		if c is Label:
			from_text += 1
		elif c is Button:
			from_picture += 1
	if from_picture == 0 or from_text == 0:
		_fails += 1
		print("FAIL %s offers the card preview from %d pictures and %d text cells — a card list has to offer both" % [
			path, from_picture, from_text])
	elif from_picture != from_text:
		_fails += 1
		print("FAIL %s wired %d pictures but %d text cells: some row offers only one way in" % [
			path, from_picture, from_text])
	else:
		# ...and one of them is CLICKED, because everything above this line is still only
		# evidence: a tooltip that promises the whole card, on a Label that can be hit. The
		# promise and the delivery are two different things, and the version of this suite
		# that only counted tooltips would have passed a handler connected to the wrong
		# mouse button, or to nothing at all. Emitting the event runs the real chain —
		# `inspect_text`'s filter, `inspect_card`, the overlay it parents onto the screen.
		var probe: Label = null
		for c in _controls(inst):
			if c is Label and c.tooltip_text.find(PREVIEW_PROMISE) != -1:
				probe = c as Label
				break
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		probe.gui_input.emit(ev)
		await get_tree().process_frame
		if UI._inspecting == null or not is_instance_valid(UI._inspecting):
			_fails += 1
			print("FAIL clicking the card text in %s promised the whole card and opened nothing" % path)
		else:
			UI._inspecting.queue_free()
			UI._inspecting = null
			await get_tree().process_frame
	inst.queue_free()
	await get_tree().process_frame

func _check_collection_explains() -> void:
	var inst := (load("res://scenes/Collection.tscn") as PackedScene).instantiate()
	add_child(inst)
	await get_tree().process_frame
	var explained := 0
	for c in _controls(inst):
		# a card row names the card and says what it does, so it is longer than a label
		if c.tooltip_text.find("Level ") != -1 and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			explained += 1
	var owned: int = MetaState.collection.size()
	if explained < owned:
		_fails += 1
		print("FAIL collection explains %d of %d owned card types on hover" % [explained, owned])
	inst.queue_free()
	await get_tree().process_frame

func _controls(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control:
		out.append(n as Control)
	for child in n.get_children():
		out.append_array(_controls(child))
	return out

## Delete this test's sandboxed files. Deleting is not enough on its own — a
## surviving MetaState flushes when the engine frees it at exit and re-creates
## them, which is why writes are disabled first.
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
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
