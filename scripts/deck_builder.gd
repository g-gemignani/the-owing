## Deck builder — assemble the deck for the dungeon you're about to enter (D4).
## Select up to `owned` copies of each collection card, load/save named loadouts,
## then Start. Shown at the beginning of every dungeon (fresh run or after a boss).
extends Control

var selection: Dictionary = {}  # id -> count chosen

var info_label: Label
var decks_box: HBoxContainer
var list_box: VBoxContainer
var filter_box: VBoxContainer
var power_box: HBoxContainer
var name_edit: LineEdit
var start_btn: Button
var msg_label: Label

func _ready() -> void:
	# opened from the overworld to edit loadouts, with no dungeon chosen
	if GameState.dungeon_id == "" and not GameState.manage_only:
		call_deferred("_go_select")
		return
	# start from a saved deck if any (prefer "Starter"), clamped to ownership
	var src := ""
	if MetaState.decks.has("Starter"):
		src = "Starter"
	elif not MetaState.decks.is_empty():
		src = MetaState.decks.keys()[0]
	if src != "":
		_load_deck(src)
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var dd := GameState.dungeon_data()
	var title := "Loadouts"
	if not GameState.manage_only:
		title = "Build deck — %s (difficulty %d)" % [
			dd.name if dd != null else "Dungeon", GameState.dungeon]
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black.
	var root := UI.screen(self, title)

	info_label = Label.new()
	root.add_child(info_label)

	var relic_label := Label.new()
	relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array[String] = []
	for r in MetaState.relic_data():
		names.append("%s (%s)" % [r.name, r.description])
	var prefix := ""
	if GameState.last_relic != "":
		prefix = "NEW RELIC: %s!    " % GameState.last_relic
		GameState.last_relic = ""
	relic_label.text = "%sRelics: %s" % [prefix, ", ".join(names) if not names.is_empty() else "none"]
	root.add_child(relic_label)

	# Who you are building against. A boss you cannot know is a boss you cannot
	# prepare for, and the preparation is the decision this screen exists to ask.
	if not GameState.manage_only and GameState.dungeon_id != "":
		var boss := Balance.boss_of(GameState.dungeon_id)
		if boss != null:
			var warn := Label.new()
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.add_theme_color_override("font_color", Color(0.95, 0.65, 0.45))
			warn.text = "BOSS: %s — %s" % [boss.name, Balance.boss_warning(GameState.dungeon_id)]
			root.add_child(warn)
			UI.hoverable(warn, "%s waits at the end of %s.\n%s" % [
				boss.name, dd.name if dd != null else "this dungeon",
				Balance.boss_warning(GameState.dungeon_id)])

	# Power picker. Sits with the deck because it IS part of the loadout: one
	# ability, chosen per run, firable once every turn.
	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override("separation", UITheme.sep(6))
	root.add_child(power_row)
	var plbl := Label.new()
	plbl.text = "Power:"
	power_row.add_child(plbl)
	power_box = HBoxContainer.new()
	power_box.add_theme_constant_override("separation", UITheme.sep(6))
	power_row.add_child(power_box)
	var manage := Button.new()
	UITheme.style_button(manage)
	manage.text = "Powers..."
	manage.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Powers.tscn"))
	power_row.add_child(manage)

	var decks_row := HBoxContainer.new()
	decks_row.add_theme_constant_override("separation", UITheme.sep(6))
	root.add_child(decks_row)
	var lbl := Label.new()
	lbl.text = "Load:"
	decks_row.add_child(lbl)
	decks_box = HBoxContainer.new()
	decks_box.add_theme_constant_override("separation", UITheme.sep(6))
	decks_row.add_child(decks_box)

	filter_box = VBoxContainer.new()
	root.add_child(filter_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", UITheme.sep(4))
	scroll.add_child(list_box)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", UITheme.sep(6))
	root.add_child(save_row)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "deck name"
	name_edit.custom_minimum_size.x = UITheme.px(200)
	save_row.add_child(name_edit)
	var save_btn := Button.new()
	UITheme.style_button(save_btn)
	save_btn.text = "Save deck"
	save_btn.pressed.connect(_on_save)
	save_row.add_child(save_btn)

	msg_label = Label.new()
	save_row.add_child(msg_label)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(bottom)
	UI.exit_button(bottom, "Back", func():
		var dest := "res://scenes/Overworld.tscn"
		if not GameState.manage_only and GameState.current_zone != "":
			dest = "res://scenes/ZoneView.tscn"
		GameState.manage_only = false
		UI.goto(self, dest))
	var coll_btn := Button.new()
	UITheme.style_button(coll_btn)
	coll_btn.text = "Collection (fuse)"
	coll_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"))
	bottom.add_child(coll_btn)
	start_btn = Button.new()
	UITheme.style_button(start_btn)
	start_btn.text = "Save loadout and leave" if GameState.manage_only else "Start Dungeon"
	start_btn.pressed.connect(_on_start)
	bottom.add_child(start_btn)

func _go_select() -> void:
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _load_deck(deck_name: String) -> void:
	selection = {}
	var lo: Dictionary = MetaState.decks.get(deck_name, {})
	for id in lo:
		selection[id] = min(int(lo[id]), MetaState.owned(id))

func _adjust(id: String, delta: int) -> void:
	var cur: int = selection.get(id, 0)
	var next: int = clampi(cur + delta, 0, MetaState.owned(id))
	if next == 0:
		selection.erase(id)
	else:
		selection[id] = next
	_refresh()

func _refresh() -> void:
	var size := MetaState.loadout_size(selection)
	var valid := MetaState.deck_valid(selection)
	var hint := "OK"
	if size < MetaState.MIN_DECK_SIZE:
		hint = "need %d more" % (MetaState.MIN_DECK_SIZE - size)
	elif size > MetaState.MAX_DECK_SIZE:
		hint = "over cap by %d" % (size - MetaState.MAX_DECK_SIZE)
	info_label.text = "Deck %d  (min %d, max %d)    HP %d/%d    Gold %d    %s" % [
		size, MetaState.MIN_DECK_SIZE, MetaState.MAX_DECK_SIZE,
		GameState.hp, GameState.max_hp, MetaState.gold, hint]
	if start_btn:
		start_btn.disabled = not valid

	# power picker: every owned power, the equipped one marked
	for c in power_box.get_children():
		c.queue_free()
	if MetaState.powers.is_empty():
		var none := Label.new()
		none.text = "none owned"
		power_box.add_child(none)
	for pid in MetaState.powers:
		var pd := Balance.power(pid)
		if pd == null:
			continue
		pd = pd.duplicate()
		pd.level = int(MetaState.powers[pid])
		var pb := Button.new()
		UITheme.style_button(pb)
		var on: bool = pid == MetaState.equipped_power
		pb.text = "%s%s Lv%d" % ["> " if on else "", pd.name, pd.level]
		pb.disabled = on
		UI.hoverable(pb, "%s\n%s\nCost %s, once per turn." % [
			pd.name, pd.effect_text(), "free" if pd.eff_cost() == 0 else "%dE" % pd.eff_cost()])
		pb.pressed.connect(func():
			MetaState.equip_power(pid)
			_refresh())
		power_box.add_child(pb)

	# load buttons for saved decks
	for c in decks_box.get_children():
		c.queue_free()
	for dn in MetaState.decks:
		var lb := Button.new()
		UITheme.style_button(lb)
		lb.text = dn
		lb.pressed.connect(func():
			_load_deck(dn)
			_refresh())
		decks_box.add_child(lb)

	# per-card selectors
	for c in filter_box.get_children():
		c.queue_free()
	UI.card_filter_bar(filter_box, _refresh)

	for c in list_box.get_children():
		c.queue_free()
	for id in CardFilter.apply(MetaState.collection, MetaState.CATALOG):
		var entry: Dictionary = MetaState.collection[id]
		var card := (load(MetaState.CATALOG[id]) as CardData).duplicate()
		card.level = entry["level"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.sep(8))
		list_box.add_child(row)

		# The illustration is the way into the full card — see UI.inspect_thumb. This
		# is the screen where it matters most: you are choosing between cards you own
		# on the strength of one line of text each.
		UI.inspect_thumb(row, card, UITheme.px(28),
			"In this deck: %d copies." % int(selection.get(id, 0)))
		var pic := TextureRect.new()
		pic.texture = Icons.tex(Icons.for_card(card))
		pic.custom_minimum_size = Vector2(UITheme.px(28), UITheme.px(28))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
		var name_lbl := Label.new()
		name_lbl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
		name_lbl.custom_minimum_size.x = UITheme.px(410)
		var stats := ""
		if card.eff_damage() > 0:
			stats += "dmg %d " % card.eff_damage()
		if card.eff_block() > 0:
			stats += "blk %d " % card.eff_block()
		# no empty "()" on a card whose numbers are not damage or block
		var stat_txt := stats.strip_edges()
		name_lbl.text = "%s [%s] Lv%d/%d  owned %d%s" % [
			card.name, CardData.Rarity.keys()[card.rarity], entry["level"],
			MetaState.max_level(id), entry["count"],
			"   (%s)" % stat_txt if stat_txt != "" else ""]
		row.add_child(name_lbl)
		UI.hoverable(row, Icons.card_tooltip(card))

		var minus := Button.new()
		UITheme.style_button(minus, true)
		minus.text = "-"
		minus.custom_minimum_size.x = UITheme.px(40)
		minus.pressed.connect(_adjust.bind(id, -1))
		row.add_child(minus)

		var cnt := Label.new()
		cnt.custom_minimum_size.x = UITheme.px(46)
		cnt.text = "x%d" % int(selection.get(id, 0))
		row.add_child(cnt)

		var plus := Button.new()
		UITheme.style_button(plus, true)
		plus.text = "+"
		plus.custom_minimum_size.x = UITheme.px(40)
		plus.pressed.connect(_adjust.bind(id, 1))
		row.add_child(plus)

func _on_save() -> void:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		msg_label.text = "name required"
		return
	MetaState.save_deck(nm, selection)
	msg_label.text = "saved '%s'" % nm
	_refresh()

func _on_start() -> void:
	if GameState.manage_only:
		# editing loadouts only: nothing to enter
		GameState.manage_only = false
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
		return
	if not MetaState.deck_valid(selection):
		msg_label.text = "deck too small"
		return
	Audio.play("enter")
	GameState.enter_dungeon(MetaState.build_deck(selection))
	GameState.autosave()   # the run exists from here on and can be resumed
	get_tree().change_scene_to_file(GameState.run_scene())
