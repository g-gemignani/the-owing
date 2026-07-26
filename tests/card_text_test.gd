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
	# Headless defaults to a SQUARE 1280x1280 viewport. Every geometry check below
	# would otherwise be measured against 560 pixels of vertical slack the player
	# never has — the same trap PlayableTest documents, walked into again the moment
	# this test started measuring rects instead of only font sizes.
	get_window().size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	await get_tree().process_frame

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

	# --- the hand is a fan, and it fits ------------------------------------------
	#
	# Every one of these was broken at some point while building the layout, each
	# time found only by rendering it and looking: cards running off the bottom edge,
	# the vitals line overflowing its box and passing under the leftmost card, and the
	# rightmost card tucking behind the power orb. A still image cannot keep them
	# fixed, so the rects are measured.
	var vp := get_viewport().get_visible_rect()
	var cards := _cards(inst)
	if cards.size() < 3:
		_fails += 1; print("FAIL only %d cards in hand to measure" % cards.size())
	var rots := {}
	var lowest_y := -1.0e9
	var middle_y := 0.0
	for k in cards.size():
		var holder: Control = cards[k]
		var r := holder.get_global_rect()
		if r.position.y < 0.0 or r.end.y > vp.size.y + 1.0:
			_fails += 1
			print("FAIL card %s spans y %.0f-%.0f, outside a %.0f-tall frame" % [
				holder.get_meta("card_id"), r.position.y, r.end.y, vp.size.y])
		if r.position.x < 0.0 or r.end.x > vp.size.x + 1.0:
			_fails += 1
			print("FAIL card %s spans x %.0f-%.0f, outside a %.0f-wide frame" % [
				holder.get_meta("card_id"), r.position.x, r.end.x, vp.size.x])
		rots[snappedf(holder.rotation, 0.001)] = true
		if k == 0 or k == cards.size() - 1:
			lowest_y = maxf(lowest_y, r.position.y)
		if k == cards.size() / 2:
			middle_y = r.position.y
	# a fan, not a row: the cards are tilted, and the middle of it rides higher
	if rots.size() < 3:
		_fails += 1; print("FAIL the hand is not fanned — %d distinct angles" % rots.size())
	if middle_y >= lowest_y:
		_fails += 1
		print("FAIL the hand has no arc: middle card at y %.0f, outer at y %.0f" % [
			middle_y, lowest_y])
	# Everything in the bottom band has to be ON the screen. `PRESET_BOTTOM_LEFT`
	# puts a box's TOP edge on the bottom of the frame, so the entire HUD and both
	# controls rendered below it — and nothing in the suite noticed, because every
	# check was about cards. D33's lesson ("actionable content must be on screen")
	# applied to the widgets that were not there when it was written.
	for named in [["the vitals", inst.status_label], ["the buffs line", inst.buffs_label],
			["the piles", inst.piles_label], ["the log", inst.log_label],
			["the power", inst.power_btn], ["End Turn", inst.end_btn],
			["the Menu button", inst.menu_btn], ["the place name", inst.place_label]]:
		var widget: Control = named[1]
		if widget == null:
			_fails += 1; print("FAIL %s does not exist" % named[0]); continue
		if not widget.visible:
			continue
		var wr := widget.get_global_rect()
		if wr.position.y < -1.0 or wr.end.y > vp.size.y + 1.0 \
				or wr.position.x < -1.0 or wr.end.x > vp.size.x + 1.0:
			_fails += 1
			print("FAIL %s is off screen: %.0f,%.0f to %.0f,%.0f in a %.0fx%.0f frame" % [
				named[0], wr.position.x, wr.position.y, wr.end.x, wr.end.y,
				vp.size.x, vp.size.y])

	# ...and the hand must not run under the things parked in both bottom corners
	for zone in [["the vitals", inst.status_label], ["End Turn", inst.end_btn],
			["the power orb", inst.power_btn]]:
		var other: Control = zone[1]
		if other == null or not other.visible:
			continue
		var orect := other.get_global_rect()
		for holder2 in cards:
			if (holder2 as Control).get_global_rect().intersects(orect):
				_fails += 1
				print("FAIL card %s overlaps %s" % [holder2.get_meta("card_id"), zone[0]])
				break

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
