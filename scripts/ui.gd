## Small builders shared by every menu screen. Exists so screens describe their
## content instead of repeating container/margin/scale boilerplate — and so one
## edit changes the look of all of them once there is art.
class_name UI
extends RefCounted

## Standard screen scaffold. Returns the VBox to fill.
##
## `art` optionally names a full-bleed painted image to use instead of the tiling
## pixel backdrop — for a title screen, where one illustration beats a pattern.
static func screen(root: Control, title: String, art: String = "") -> VBoxContainer:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Backdrop first, so it sits behind everything, and mouse-deaf so it never eats
	# a click meant for a button.
	if art != "" and ResourceLoader.exists(art):
		for node in illustration(art):
			root.add_child(node)
	else:
		# tiling pixel backdrop, themed by wherever the player currently is
		root.add_child(PixelArt.backdrop(_context_zone()))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(col)
	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", UITheme.title_font())
		col.add_child(t)
	return col

## A full-bleed painted backdrop: the image, plus a scrim that keeps text legible.
## Returns the layers in draw order.
##
## Two things differ from the pixel backdrops:
##
## * **LINEAR filtering.** project.godot forces NEAREST globally, which is right
##   for pixel art and turns a smooth illustration into jagged edges.
## * **A gradient scrim.** Measured on the title art: white text over the button
##   area sat at 3.7:1 contrast, under the 4.5:1 needed to read comfortably, with
##   highlights bright enough to swallow a glyph entirely. The scrim is darkest
##   behind the menu column and fades out across the image, so the art still shows
##   where nothing is written on it. A flat dim would have muddied the whole thing
##   to fix one corner.
## Held FLAT across the text column before it fades. A pure linear fade left the
## right-hand end of the column at only 0.2 opacity, so a bright cloud there sat at
## 1.4:1 against white text — fine on average, illegible exactly where a glyph
## landed. Averages do not read text; worst pixels do.
const SCRIM_ALPHA := 0.82   ## opacity behind the text column
const SCRIM_HOLD := 0.42    ## width fraction held at full opacity
const SCRIM_END := 0.72     ## width fraction at which the scrim is gone
## Menu content is kept inside SCRIM_HOLD, so text never strays past the cover.
const MENU_WIDTH := 0.40

static func illustration(path: String) -> Array[Control]:
	var art := TextureRect.new()
	art.texture = load(path) as Texture2D
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	# COVER, not tile: it is one picture, and letterboxing a title screen reads
	# as a bug rather than a choice.
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0, SCRIM_ALPHA))
	grad.set_offset(1, SCRIM_HOLD)
	grad.set_color(1, Color(0, 0, 0, SCRIM_ALPHA))
	grad.add_point(SCRIM_END, Color(0, 0, 0, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 256
	gtex.height = 1
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(1, 0)

	var scrim := TextureRect.new()
	scrim.texture = gtex
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var layers: Array[Control] = [art, scrim]
	return layers

## Which zone's backdrop suits the current screen: the run's zone if there is one,
## else the zone being browsed, else the opening zone.
static func _context_zone() -> String:
	if GameState.dungeon_id != "":
		var z := Balance.zone_of(GameState.dungeon_id)
		if z != null:
			return z.id
	if GameState.current_zone != "":
		return GameState.current_zone
	return Balance.ZONES[0] if Balance.ZONES.size() > 0 else "barrows"

static func label(parent: Node, text: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

static func button(parent: Node, text: String, on_press: Callable = Callable(),
		height: float = 42.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, UITheme.button_height(height))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	else:
		b.disabled = true
	UITheme.style_button(b)
	parent.add_child(b)
	return b

static func row(parent: Node, separation: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", UITheme.sep(separation))
	parent.add_child(h)
	return h

static func spacer(parent: Node) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c

static func scroll(parent: Node) -> VBoxContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UITheme.sep(6))
	s.add_child(col)
	return col

## A labelled 0-100 slider row (placeholder-friendly).
static func slider(parent: Node, text: String, value: float, lo: float, hi: float,
		step: float, on_change: Callable) -> HSlider:
	var h := row(parent, 10)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = UITheme.px(220)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size.x = UITheme.px(280)
	h.add_child(s)
	var v := Label.new()
	v.custom_minimum_size.x = UITheme.px(90)
	v.text = str(snappedf(value, step))
	h.add_child(v)
	s.value_changed.connect(func(nv):
		v.text = str(snappedf(nv, step))
		on_change.call(nv))
	return s

## A card: rarity-framed, with its illustration behind the text and its *meaningful*
## effect symbol in front.
##
## Layered deliberately. The illustration is arbitrary art from an unlabelled sheet,
## so it is pushed to the back at low opacity where it adds identity without making a
## claim; the symbol (attack / block / poison / ...) is derived from the card's real
## effects and stays legible in front. Text is never competed with.

## Attach a tooltip and guarantee it can actually be reached by the mouse.
##
## Label, and most non-interactive Controls, default to MOUSE_FILTER_IGNORE, so a
## `tooltip_text` set directly on one is never shown — the collection, deck builder
## and shop all had card descriptions written that no hover could surface.
##
## Pass the *row*, not the label: hovering anywhere over an entry should explain it.
## Children left on IGNORE fall through to this control, and a child Button with no
## tooltip of its own inherits this one by walking up the tree.
static func hoverable(control: Control, text: String) -> void:
	control.tooltip_text = text
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_STOP

## Filter and sort controls for a list of owned cards.
##
## One builder used by both the collection and the deck builder, so the two cannot
## end up offering different orderings of the same cards. Calls `on_change` after
## mutating CardFilter.state; the screen just re-runs its own refresh.
static func card_filter_bar(parent: Node, on_change: Callable) -> void:
	var st: Dictionary = CardFilter.state

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITheme.sep(6))
	parent.add_child(bar)

	var lbl := Label.new()
	lbl.text = "Sort"
	bar.add_child(lbl)

	var sort := OptionButton.new()
	for i in CardFilter.SORTS.size():
		sort.add_item(String(CardFilter.SORTS[i]["label"]), i)
		if CardFilter.SORTS[i]["id"] == st.get("sort", "name"):
			sort.select(i)
	sort.item_selected.connect(func(i: int):
		CardFilter.state["sort"] = CardFilter.SORTS[i]["id"]
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(sort)

	# direction is a toggle rather than two more menu entries: it applies to
	# whichever key is chosen
	var dir := Button.new()
	UITheme.style_button(dir)
	dir.text = "desc" if bool(st.get("desc", false)) else "asc"
	dir.pressed.connect(func():
		CardFilter.state["desc"] = not bool(CardFilter.state.get("desc", false))
		Audio.play("ui_click")
		on_change.call())
	UI.hoverable(dir, "Reverse the order")
	bar.add_child(dir)

	var rl := Label.new()
	rl.text = "   Rarity"
	bar.add_child(rl)
	var rarity := OptionButton.new()
	rarity.add_item("All", 0)
	for r in CardData.Rarity.keys().size():
		rarity.add_item(String(CardData.Rarity.keys()[r]).capitalize(), r + 1)
	rarity.select(int(st.get("rarity", -1)) + 1)
	rarity.item_selected.connect(func(i: int):
		CardFilter.state["rarity"] = i - 1
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(rarity)

	var tl := Label.new()
	tl.text = "   Type"
	bar.add_child(tl)
	var type := OptionButton.new()
	type.add_item("All", 0)
	for t in CardData.Type.keys().size():
		type.add_item(String(CardData.Type.keys()[t]).capitalize(), t + 1)
	type.select(int(st.get("type", -1)) + 1)
	type.item_selected.connect(func(i: int):
		CardFilter.state["type"] = i - 1
		Audio.play("ui_select")
		on_change.call())
	bar.add_child(type)

	var clear := Button.new()
	UITheme.style_button(clear)
	clear.text = "Clear"
	clear.pressed.connect(func():
		CardFilter.state = CardFilter.default_state()
		Audio.play("ui_back")
		on_change.call())
	bar.add_child(clear)

## A modal list of the run deck, for anything that acts on one card.
##
## An overlay rather than a screen, so it works identically from a shop, a rest and
## any traversal view without one of them having to know how to route back.
static func card_picker(host: Control, deck: Array, title: String,
		on_pick: Callable) -> Control:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.82)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 100
	veil.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it is clickable
	host.add_child(veil)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	veil.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(8))
	margin.add_child(col)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", UITheme.title_font())
	col.add_child(t)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UITheme.sep(6))
	grid.add_theme_constant_override("v_separation", UITheme.sep(6))
	scroll.add_child(grid)

	var size := UITheme.card_size() * 0.8
	for c in deck:
		card_button(grid, c, size, func(): 
			veil.queue_free()
			on_pick.call(c))

	var cancel := Button.new()
	cancel.text = "Never mind"
	cancel.custom_minimum_size = Vector2(0, UITheme.px(40))
	cancel.pressed.connect(func():
		Audio.play("ui_back")
		veil.queue_free())
	col.add_child(cancel)
	return veil

## `live` is the CombatEngine when this card is being shown inside a fight, and
## null everywhere else. With it, the face and the hover both quote the damage and
## Block the card would actually produce this turn — Strength and Dexterity are
## otherwise invisible on the only surface the player reads before spending energy.
static func card_button(parent: Node, card: CardData, size: Vector2,
		on_press: Callable, label: String = "", live: CombatEngine = null) -> Button:
	# A plain Control, NOT a Container. PanelContainer overrides its children's
	# anchors and takes its own size from their minimum sizes — and a Button's
	# minimum size grows with its wrapped description, so every card ended up a
	# different size and the sizes shifted as the hand changed. A Control holder
	# with an explicit size and anchored children makes every card identical.
	var holder := Control.new()
	holder.set_meta("card_id", card.id)   # so tests can measure a card's real bounds
	holder.custom_minimum_size = size
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(holder)

	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", Icons.card_style(card.rarity, 0.16))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(frame)

	# illustration: behind the text, faint, deaf to the mouse
	var art := PixelArt.card_art(card.id)
	if art != null:
		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.modulate = Icons.rarity_colour(card.rarity)
		pic.modulate.a = 0.22
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(pic)

	# The button carries no text. It used to render everything through `Button.text`
	# with `clip_text`, which silently cut descriptions off mid-word — a Button draws
	# one text block at one size and cannot give the name and the rules text different
	# treatment. Text lives in Labels layered on top; the button is only the hit area.
	var b := Button.new()
	b.flat = true
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	# both surfaces read the same two numbers, so the face and the hover cannot
	# disagree about what the card is about to do
	var live_dmg: int = live.card_damage(card) if live != null else -1
	var live_blk: int = live.card_block(card) if live != null else -1
	b.tooltip_text = Icons.card_tooltip(card, live_dmg, live_blk)
	holder.add_child(b)

	# NO containers inside the card. A VBox/HBox honours its children's *minimum*
	# sizes, and an autowrapping Label's minimum width is one character — so the
	# title got squeezed to 8px, wrapped to 441px tall, and shoved the description
	# clean off the bottom of a 211px card. Every region is placed by hand against
	# the card's known size, so nothing can be pushed anywhere.
	# Three stacked bands. The cost badge and effect symbol get a share of the card's
	# WIDTH, never its height: sizing them off head_h drove the title's width
	# negative on a squeezed hand, which made the fit pass give up and clip instead.
	var pad := roundf(size.x * 0.06)
	var inner := Vector2(size.x - pad * 2.0, size.y - pad * 2.0)
	var badge_w := roundf(inner.x * 0.22)
	var badge_h := roundf(inner.y * 0.18)
	var title_h := roundf(inner.y * 0.26)

	var cost := _card_label(holder, str(card.cost), Color(1.0, 0.86, 0.45))
	_place(cost, pad, pad, badge_w, badge_h)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var sym := Icons.tex(Icons.for_card(card))
	if sym != null:
		var s := TextureRect.new()
		s.texture = sym
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(s)
		_place(s, size.x - pad - badge_w, pad, badge_w, badge_h)

	var title := _card_label(holder, label if label != "" else card.name,
		Color(0.96, 0.96, 0.96))
	var title_w := inner.x

	var desc_y := pad + badge_h + title_h
	var desc_h := size.y - pad - desc_y
	# generated, not the authored line: a fused card must not misreport itself
	var desc := _card_label(holder, card.effect_text(live_dmg, live_blk), Color(0.86, 0.84, 0.80))
	_place(desc, pad, desc_y, inner.x, desc_h)

	# Shrink to fit rather than clip. Card text is authored, so its length varies
	# far more than the fixed card does; a card that cuts its own rules text off is
	# unplayable in a way a slightly smaller font is not.
	#
	# Two layouts, because fitting a long description into a hand-sized card drove
	# the font down to 12px on the wordiest card. At rest a card shows only its name
	# and cost, which lets the name use the whole face at a comfortable size; hover
	# enlarges the card and reveals the rules text.
	var body := UITheme.font()
	fit_label(cost, Vector2(badge_w, badge_h), body, 7)
	fit_label(desc, Vector2(inner.x, desc_h), int(body * 0.85), 7)

	# The headline number, always on the face — never only on hover.
	#
	# At rest a card shows its name and its cost and nothing else, which is fine for
	# reading a hand at a glance and useless for the thing that changes: with 4
	# Strength every attack is worth more, and a player could not see that anywhere
	# without hovering each card in turn. Damage in red, Block in blue, both if the
	# card does both. In a fight these are the live numbers.
	var headline := ""
	if live_dmg > 0 or (live_dmg < 0 and card.eff_damage() > 0):
		headline = str(live_dmg if live_dmg >= 0 else card.eff_damage())
		if card.hits > 1:
			headline += "x%d" % card.hits
	var shield := ""
	if live_blk > 0 or (live_blk < 0 and card.eff_block() > 0):
		shield = str(live_blk if live_blk >= 0 else card.eff_block())
	var value_labels: Array[Label] = []
	var value_h := 0.0
	if headline != "" or shield != "":
		value_h = badge_h
		if headline != "":
			var v := _card_label(holder, headline, Color(1.0, 0.55, 0.45))
			value_labels.append(v)
			_place(v, pad, size.y - pad - value_h, inner.x * 0.5, value_h)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			fit_label(v, Vector2(inner.x * 0.5, value_h), body, 7)
		if shield != "":
			var s2 := _card_label(holder, shield, Color(0.62, 0.80, 1.0))
			value_labels.append(s2)
			_place(s2, pad + inner.x * 0.5, size.y - pad - value_h, inner.x * 0.5, value_h)
			s2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fit_label(s2, Vector2(inner.x * 0.5, value_h), body, 7)

	var rest_y := pad + badge_h
	var rest_h := size.y - pad - rest_y - value_h
	_place(title, pad, rest_y, title_w, rest_h)
	fit_label(title, Vector2(title_w, rest_h), UITheme.title_font(), 7)
	var rest_px: int = title.get_theme_font_size("font_size")
	_place(title, pad, pad + badge_h, title_w, title_h)
	fit_label(title, Vector2(title_w, title_h), body, 7)
	var open_px: int = title.get_theme_font_size("font_size")

	var show_all := func(open: bool) -> void:
		desc.visible = open
		# The number strip exists because a resting card shows only a name. Once the
		# card is open its rules text carries the same number, and leaving the strip
		# up costs the description the room it needs — measured at 11px, which
		# CardTextTest calls unreadable and is right to.
		for vl in value_labels:
			vl.visible = not open
		if open:
			_place(title, pad, pad + badge_h, title_w, title_h)
			title.add_theme_font_size_override("font_size", open_px)
		else:
			_place(title, pad, rest_y, title_w, rest_h)
			title.add_theme_font_size_override("font_size", rest_px)
	show_all.call(false)
	holder.set_meta("show_all", show_all)   # so tests can drive both states

	# Re-read the live numbers without rebuilding the widget. The combat screen
	# diffs its hand instead of destroying it every action (that is what allows a
	# card to animate at all), so a buff landing mid-turn has to be able to change
	# what the cards already on screen claim to do.
	holder.set_meta("relabel", func(live2: CombatEngine) -> void:
		var d2: int = live2.card_damage(card) if live2 != null else -1
		var b2: int = live2.card_block(card) if live2 != null else -1
		desc.text = card.effect_text(d2, b2)
		b.tooltip_text = Icons.card_tooltip(card, d2, b2)
		if value_labels.size() > 0 and d2 >= 0 and headline != "":
			var head := str(d2)
			if card.hits > 1:
				head += "x%d" % card.hits
			value_labels[0].text = head
		if b2 > 0 and shield != "":
			value_labels[value_labels.size() - 1].text = str(b2))

	# Grow from the bottom edge: a hand sits along the bottom of the screen, so a
	# card that grew from its centre would push its own text off-screen.
	holder.pivot_offset = Vector2(size.x * 0.5, size.y)
	var open_card := func(open: bool) -> void:
		show_all.call(open)
		holder.scale = Vector2.ONE * (UITheme.CARD_HOVER_SCALE if open else 1.0)
		holder.z_index = 10 if open else 0
		# A fanned hand stores where each card sits at rest ("fan" meta, set by the
		# combat screen). Opening one straightens it and lifts it clear of its
		# neighbours, the way you pull a card out of a real hand to read it — without
		# that, an enlarged card in a fan is still half-covered by the next one.
		var fan: Dictionary = holder.get_meta("fan", {})
		if not fan.is_empty():
			var home: Vector2 = fan.get("pos", holder.position)
			if open:
				holder.rotation = 0.0
				holder.position = home - Vector2(0.0, float(fan.get("lift", 0.0)))
			else:
				holder.rotation = float(fan.get("rot", 0.0))
				holder.position = home

	if touch_ui():
		# TOUCH: a finger has no hover, so reading a card and committing to it must
		# be two separate taps. Otherwise the only way to find out what a card does
		# is to play it, which is exactly backwards — and the hover-to-enlarge that
		# makes a card readable at all would never fire on a phone.
		#
		# Deliberately ONE handler that owns both taps, rather than a reveal handler
		# racing the caller's own. Deciding whether a tap counts by relying on the
		# order two signals were connected in would break the first time somebody
		# moved a line.
		holder.set_meta("preview", open_card)
		b.pressed.connect(func():
			if _previewed != b:
				_close_preview()
				_previewed = b
				open_card.call(true)
				Audio.play("ui_select")
				return                    # first tap only reveals
			_close_preview()              # second tap on the same card commits
			if on_press.is_valid():
				Audio.play("card_play")
				on_press.call())
	else:
		if on_press.is_valid():
			b.pressed.connect(func(): Audio.play("card_play"))
			b.pressed.connect(on_press)
		b.mouse_entered.connect(func(): open_card.call(true))
		b.mouse_exited.connect(func(): open_card.call(false))
	return b

## True where there is a touchscreen and no mouse: phones and tablets.
static func touch_ui() -> bool:
	return DisplayServer.is_touchscreen_available() and not OS.has_feature("pc")

## The card currently held open by a tap, so tapping a different one closes it.
static var _previewed: Button = null

static func _close_preview() -> void:
	if _previewed != null and is_instance_valid(_previewed):
		var h := _previewed.get_parent()
		if h != null and h.has_meta("preview"):
			(h.get_meta("preview") as Callable).call(false)
	_previewed = null

## A card's text layer: wrapped, centred, deaf to the mouse, and clipped as a
## last-resort backstop so a mis-measurement can never spill over the frame.
static func _card_label(holder: Control, text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour)
	holder.add_child(l)
	return l

## Pin a child to an exact rectangle inside a non-container parent.
static func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)
	c.custom_minimum_size = Vector2.ZERO

## Shrink a Label's font until every line it wraps to is actually visible.
##
## Godot has no shrink-to-fit: a Label either overflows its box or clips. Card
## descriptions are authored text of wildly varying length inside a fixed frame, so
## one font size is guaranteed to cut the long ones off.
##
## The loop asks the Label itself rather than predicting it. Two attempts at
## predicting with `Font.get_multiline_string_size()` were both wrong — it breaks on
## word boundaries while AUTOWRAP_WORD_SMART also breaks inside long words, and it
## ignores the `line_spacing` theme constant — and each miss showed up as text the
## player could not read. `get_visible_line_count()` is the same measurement the
## renderer uses, so agreeing with it cannot drift.
static func fit_label(l: Label, avail: Vector2, max_px: int, min_px: int) -> void:
	if avail.x <= 0.0 or avail.y <= 0.0:
		l.add_theme_font_size_override("font_size", maxi(min_px, 1))
		return
	l.size = avail
	var px := max_px
	while px > min_px:
		l.add_theme_font_size_override("font_size", px)
		if l.get_visible_line_count() >= l.get_line_count():
			return
		px -= 1
	l.add_theme_font_size_override("font_size", px)

static func goto(node: Node, path: String) -> void:
	node.get_tree().change_scene_to_file(path)

# --- the way out of a screen -------------------------------------------------
#
# Escape used to leave fullscreen, which is not what that key means anywhere
# else, and Combat had no exit control at all — the longest scene in the game was
# the only one you could not leave. A screen now declares its exit ONCE, with
# `exit_button()`, which builds the button AND binds the key to the same
# Callable. Two independent ways out is the D34 label table again, in navigation.
## The Callable lives ON the node rather than in a static, and this holds only a
## pointer to the node. A static Callable capturing a screen outlives that screen:
## it corrupted the heap at engine shutdown, and because every scene test writes to
## a pipe, the abort ate the buffered "PASS" line and three green tests reported as
## failures. Metadata dies with the node it belongs to.
const ESCAPE_META := "ui_escape"
static var _escape_owner: Node = null

## Register what Escape does on this screen. The owner is remembered so a stale
## action cannot fire on the screen that replaced it: once the old scene is freed
## or removed from the tree, the registration stops answering.
static func escape(owner: Node, action: Callable) -> void:
	if action.is_valid():
		owner.set_meta(ESCAPE_META, action)
	elif owner.has_meta(ESCAPE_META):
		owner.remove_meta(ESCAPE_META)
	_escape_owner = owner

## Withdraw the exit — for a screen that reaches a state it must not be left in,
## like Combat between the killing blow and the reward pick.
static func clear_escape(owner: Node) -> void:
	escape(owner, Callable())

## Does the screen on screen right now offer a way out?
static func has_escape() -> bool:
	return is_instance_valid(_escape_owner) and _escape_owner.is_inside_tree() \
		and _escape_owner.has_meta(ESCAPE_META)

## Take it. False means this screen declared none, and the caller decides what
## Escape should mean instead.
static func run_escape() -> bool:
	if not has_escape():
		return false
	var action: Callable = _escape_owner.get_meta(ESCAPE_META)
	if not action.is_valid():
		return false
	action.call()
	return true

## A button that is also what Escape does.
static func exit_button(parent: Node, text: String, action: Callable,
		height: float = 42.0) -> Button:
	escape(parent, action)
	return button(parent, text, action, height)
