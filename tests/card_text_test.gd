## Runtime test: no card ever hides its own text.
##
## Written after a play report — "text of cards while playing in an encounter are
## overflowing and cannot be seen". Cards rendered everything through `Button.text`
## with `clip_text = true`, so a description longer than the frame was silently cut
## off mid-word. Nothing in the suite could see it: the scene booted, the buttons
## worked, only the words were missing.
##
## A SCENE, not a `--script` test: line counts only exist once a tree has been laid
## out, and autoloads are absent in headless script runs.
## Run: godot --headless res://tests/CardTextTest.tscn
extends Node

var _fails := 0

func _ready() -> void:
	MetaState.path_prefix = "t_cardtext_"
	MetaState.slot = 0
	MetaState.new_save()

	# Every card in the game, not just a starter hand: the longest description is
	# what breaks, and a starter deck contains none of them.
	await _check_every_card()
	await _check_live_hand()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("CARD TEXT TEST: PASS (no card clips its name or rules text)")
	else:
		print("CARD TEXT TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _check_every_card() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var box := HBoxContainer.new()
	host.add_child(box)

	var ids: Array = MetaState.CATALOG.keys()
	var size := UITheme.card_size()
	# the narrowest a card ever gets: a full hand squeezed to the window width
	var narrow: float = Icons.fit_card_width(
		10, size.x, float(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 1280)) - UITheme.px(40),
		float(UITheme.sep()))
	for id in ids:
		var card := load(MetaState.CATALOG[id]) as CardData
		if card == null:
			continue
		UI.card_button(box, card, Vector2(narrow, size.y), Callable())
	await get_tree().process_frame
	await get_tree().process_frame

	var smallest := 999
	var worst := ""
	var checked := 0
	for holder in _cards(box):
		checked += 1
		var id: String = holder.get_meta("card_id")
		# resting: name and cost only, which is all the player sees until they hover
		_hover(holder, false)
		await get_tree().process_frame
		_measure(holder, "%s resting @%dpx" % [id, int(narrow)])
		if _labels(holder).any(func(l): return l.text == card_desc(id) and l.visible):
			_fails += 1; print("FAIL %s shows its rules text while resting" % id)
		# hovered: the full rules text, at the size the hover is there to provide
		_hover(holder, true)
		await get_tree().process_frame
		_measure(holder, "%s hovered @%dpx" % [id, int(narrow)])
		var showed := false
		for l in _labels(holder):
			if not l.visible or l.text == "":
				continue
			if l.text == card_desc(id):
				showed = true
			var px: float = l.get_theme_font_size("font_size") * UITheme.CARD_HOVER_SCALE
			if px < float(smallest):
				smallest = int(px)
				worst = l.text
		if not showed and card_desc(id) != "":
			_fails += 1; print("FAIL %s does not reveal its rules text on hover" % id)
		_hover(holder, false)
	print("  worst case hovered at a %dpx-wide card: %dpx effective for \"%s\"" % [
		int(narrow), smallest, worst])
	# a floor on readability: shrink-to-fit must not solve overflow by vanishing
	if smallest < 14:
		_fails += 1; print("FAIL hovered text is only %dpx, too small to read" % smallest)
	if checked < ids.size():
		_fails += 1; print("FAIL only %d cards built of %d" % [checked, ids.size()])
	host.queue_free()
	await get_tree().process_frame

## The real combat screen, so the sizes the player actually sees are the ones tested.
func _check_live_hand() -> void:
	# a real fight, not just the scene: the hand only exists once the engine is set up
	GameState.select_dungeon(Balance.DUNGEONS[0])
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var entry: Dictionary = MetaState.collection[id]
		for i in int(entry["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(entry["level"])
			deck.append(c)
	GameState.enter_dungeon(deck)
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var scene := load("res://scenes/Combat.tscn") as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load Combat.tscn"); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var seen := 0
	for holder in _cards(inst):
		seen += 1
		_hover(holder, false)
		await get_tree().process_frame
		_measure(holder, "live combat resting: %s" % holder.get_meta("card_id"))
		_hover(holder, true)
		await get_tree().process_frame
		_measure(holder, "live combat hovered: %s" % holder.get_meta("card_id"))
		_hover(holder, false)
	if seen == 0:
		_fails += 1; print("FAIL combat rendered no card text at all")

	# --- the number has to be readable WITHOUT hovering ---------------------------
	#
	# A resting card shows its name and its cost, and the rules text only appears on
	# hover. That made Strength invisible in the place it matters: with a buff up,
	# every attack is worth more and nothing on screen changed until you moused over
	# each card in turn. The face now carries the headline number, and in a fight it
	# is the live one.
	var eng2 = inst.eng
	if eng2 == null:
		_fails += 1; print("FAIL combat has no engine to read")
	else:
		eng2.player.strength = 6
		inst._refresh()
		await get_tree().process_frame
		var checked := 0
		for holder in _cards(inst):
			var card_id: String = holder.get_meta("card_id")
			var card: CardData = null
			for c in eng2.hand:
				if c.id == card_id:
					card = c
					break
			if card == null or card.eff_damage() <= 0:
				continue
			checked += 1
			var want := str(eng2.card_damage(card))
			_hover(holder, false)
			await get_tree().process_frame
			var on_face := _labels(holder).any(func(l): return l.visible and l.text.begins_with(want))
			if not on_face:
				_fails += 1
				print("FAIL %s does not show the %s damage it would deal until you hover it" % [
					card_id, want])
			if want == str(card.eff_damage()):
				_fails += 1
				print("FAIL 6 Strength changed nothing about what %s claims to do" % card_id)
		if checked == 0:
			_fails += 1; print("FAIL no attack card was in hand to check")
	# the real signal, not the helper: a layout that only responds to the test is
	# a layout the player never sees change
	for holder in _cards(inst):
		var btn: Button = null
		for c in holder.get_children():
			if c is Button:
				btn = c
		if btn == null:
			_fails += 1; print("FAIL card has no button to hover"); break
		btn.mouse_entered.emit()
		await get_tree().process_frame
		if holder.scale.x <= 1.0:
			_fails += 1; print("FAIL hovering does not enlarge the card")
		if not _labels(holder).any(func(l): return l.visible and l.text.length() > 6):
			_fails += 1; print("FAIL hovering reveals no rules text")
		btn.mouse_exited.emit()
		await get_tree().process_frame
		if holder.scale.x != 1.0:
			_fails += 1; print("FAIL card stays enlarged after the mouse leaves")
		break
	inst.queue_free()
	await get_tree().process_frame

## Two distinct failures, both of which read as "I cannot see the text":
## the label clips (fewer lines drawn than the text needs), or the label is drawn
## outside the card frame it belongs to. The original bug was the first; raising the
## font to fix it silently produces the second.
##
## Measured in LOCAL coordinates. A hovered card is scaled, and global rects mix a
## scaled position with an unscaled size, which reports overflow that is not there.
func _measure(holder: Control, tag: String) -> void:
	var frame := Rect2(Vector2.ZERO, holder.size)
	for l in _labels(holder):
		if l.text == "" or not l.visible:
			continue
		if l.get_visible_line_count() < l.get_line_count():
			_fails += 1
			print("FAIL clipped [%s] %d of %d lines at %dpx: %s" % [
				tag, l.get_visible_line_count(), l.get_line_count(),
				l.get_theme_font_size("font_size"), l.text])
		var r := l.get_rect()
		if r.position.x < frame.position.x - 1.0 or r.position.y < frame.position.y - 1.0 \
				or r.end.x > frame.end.x + 1.0 or r.end.y > frame.end.y + 1.0:
			_fails += 1
			print("FAIL overflows card [%s] label %s vs card %s: %s" % [
				tag, r, frame, l.text])

## Drive the card's own hover handler, so the test exercises the shipped wiring
## rather than a reimplementation of it.
func _hover(holder: Control, open: bool) -> void:
	var cb: Callable = holder.get_meta("show_all")
	cb.call(open)

## What the card actually puts on its face. Generated from the effective numbers,
## not the authored `description`, which is baked at level 1 and lied about any
## fused card — see tests/test_card_truth.gd.
func card_desc(id: String) -> String:
	var c := load(MetaState.CATALOG[id]) as CardData
	return c.effect_text() if c != null else ""

func _cards(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control and (n as Control).has_meta("card_id"):
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_cards(c))
	return out

func _labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out

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
