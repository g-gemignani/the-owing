## Shop node (Phase 8) — the gold sink. Sells cards (into the permanent collection
## AND the current run deck, matching reward semantics D1) and healing for the
## current run. Inventory is rolled once per visit and stored on GameState so
## leaving and returning cannot reroll it.
extends Control

const CARD_DIR := "res://resources/cards/"
## Fallback stock when the dungeon defines no pool.
const DEFAULT_STOCK := ["hack", "cover", "stave_in", "shoulder", "clear_mind",
	"put_the_fear", "work_up", "light_on_it", "set_stone"]

var status_label: Label
var msg_label: Label
var stock_box: VBoxContainer

func _ready() -> void:
	if GameState.shop_stock.is_empty():
		GameState.shop_stock = _roll_stock()
	_build_ui()
	_refresh()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.scene_backdrop(self, "shop")
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(root)

	var title := Label.new()
	title.text = "Merchant"
	title.add_theme_font_size_override("font_size", UITheme.title_font())
	root.add_child(title)

	status_label = Label.new()
	root.add_child(status_label)

	msg_label = Label.new()
	root.add_child(msg_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	stock_box = VBoxContainer.new()
	stock_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stock_box.add_theme_constant_override("separation", UITheme.sep(6))
	scroll.add_child(stock_box)

	UI.exit_button(root, "Leave", _on_leave, 40.0)

## Roll distinct cards for sale. Stored as ids so it survives scene reloads.
func _roll_stock() -> Array:
	# merchants here sell what this dungeon holds, so exclusives stay exclusive
	var pool: Array = GameState.card_pool()
	if pool.is_empty():
		pool = DEFAULT_STOCK.duplicate()
	pool = pool.filter(func(id): return MetaState.CATALOG.has(id))
	pool.shuffle()
	var out: Array = []
	for i in min(Balance.SHOP_CARD_OFFERS, pool.size()):
		out.append({"id": pool[i], "sold": false})
	return out

func _refresh() -> void:
	status_label.text = "Gold %d (%d banked + %d at risk)    HP %d/%d" % [
		GameState.available_gold(), MetaState.gold, GameState.escrow_gold,
		GameState.hp, GameState.max_hp]

	for c in stock_box.get_children():
		c.queue_free()

	# --- cards ---
	for i in GameState.shop_stock.size():
		var entry: Dictionary = GameState.shop_stock[i]
		var card := load(MetaState.CATALOG[entry["id"]]) as CardData
		if card == null:
			continue
		var price: int = Balance.card_price(card.rarity, GameState.dungeon)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.sep(10))
		stock_box.add_child(row)

		# illustration first, then the symbol that actually states what it does
		var art := TextureRect.new()
		art.texture = PixelArt.card_art(card.id, Icons.card_family(card))
		art.custom_minimum_size = Vector2(UITheme.px(28), UITheme.px(28))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.modulate = Icons.rarity_colour(card.rarity)
		row.add_child(art)
		var pic := TextureRect.new()
		pic.texture = Icons.tex(Icons.for_card(card))
		pic.custom_minimum_size = Vector2(UITheme.px(32), UITheme.px(32))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pic)
		var lbl := Label.new()
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
		lbl.custom_minimum_size.x = UITheme.px(500)
		lbl.text = "%s  [%s]  %s" % [
			card.name, CardData.Rarity.keys()[card.rarity], card.effect_text()]
		row.add_child(lbl)
		UI.hoverable(row, Icons.card_tooltip(card))

		var buy := Button.new()
		UITheme.style_button(buy)
		if entry["sold"]:
			buy.text = "SOLD"
			buy.disabled = true
		elif GameState.available_gold() < price:
			# A greyed button showing a bare price does not say WHY, and the merchant
			# was unaffordable on most first visits (D71) — so the one screen that had
			# to explain itself was the one that explained nothing. Same shape as
			# `combat.gd:_refresh_power()`, which states the shortfall.
			buy.text = "%d g  (short %d)" % [price, price - GameState.available_gold()]
			buy.disabled = true
			UI.hoverable(buy, "Costs %d gold. You have %d." % [
				price, GameState.available_gold()])
		else:
			buy.text = "Buy  %d g" % price
			buy.pressed.connect(_on_buy_card.bind(i, price))
		row.add_child(buy)

	# --- healing ---
	var heal := Balance.heal_amount(GameState.max_hp)
	var hprice := Balance.heal_price(GameState.max_hp, GameState.dungeon)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", UITheme.sep(10))
	stock_box.add_child(hrow)
	var hlbl := Label.new()
	hlbl.custom_minimum_size.x = UITheme.px(520)
	hlbl.text = "Healing salve — restore %d HP" % heal
	hrow.add_child(hlbl)
	var hbtn := Button.new()
	UITheme.style_button(hbtn)
	if GameState.hp >= GameState.max_hp:
		hbtn.text = "Already full"
		hbtn.disabled = true
	elif GameState.available_gold() < hprice:
		hbtn.text = "%d g  (short %d)" % [hprice, hprice - GameState.available_gold()]
		hbtn.disabled = true
		UI.hoverable(hbtn, "Costs %d gold. You have %d." % [
			hprice, GameState.available_gold()])
	else:
		hbtn.text = "Buy  %d g" % hprice
		hbtn.pressed.connect(_on_buy_heal.bind(hprice, heal))
	hrow.add_child(hbtn)

	_add_removal_service(hrow.get_parent())

## Thinning is the other direction of deck building, and it belongs next to the
## things it competes with for the same gold.
func _add_removal_service(root: Node) -> void:
	var price := Balance.removal_price(GameState.run_removals, GameState.dungeon)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(row)
	var lbl := Label.new()
	lbl.custom_minimum_size.x = UITheme.px(520)
	lbl.text = "Thin your deck — remove one card for the rest of this run (%d cards, one card seen every %.1f turns)" % [
		GameState.run_deck.size(), Balance.draw_interval(GameState.run_deck.size())]
	row.add_child(lbl)
	UI.hoverable(row, "Removing a card makes the rest come up more often. It does not touch your collection — this run only.")
	var btn := Button.new()
	UITheme.style_button(btn)
	btn.text = "Remove  (%dg)" % price
	btn.disabled = GameState.available_gold() < price or not GameState.can_remove_from_run_deck()
	# Two different reasons this can be refused, and they were both silent.
	if not GameState.can_remove_from_run_deck():
		btn.text = "Remove  (deck at minimum)"
		UI.hoverable(btn, "A run deck may not go below %d cards." % Balance.MIN_DECK_SIZE)
	elif GameState.available_gold() < price:
		btn.text = "Remove  %dg  (short %d)" % [price, price - GameState.available_gold()]
		UI.hoverable(btn, "Costs %d gold. You have %d." % [
			price, GameState.available_gold()])
	btn.pressed.connect(_on_remove.bind(price))
	row.add_child(btn)

func _on_remove(price: int) -> void:
	if GameState.available_gold() < price or not GameState.can_remove_from_run_deck():
		Audio.play("ui_denied")
		return
	UI.card_picker(self, GameState.run_deck, "Remove which card? (%dg)" % price,
		func(card):
			if not GameState.spend_gold(price):
				Audio.play("ui_denied")
				return
			if GameState.remove_from_run_deck(card):
				Audio.play("fuse")
				msg_label.text = "Removed %s. Deck is now %d cards." % [
					card.name, GameState.run_deck.size()]
			_refresh())

func _on_buy_card(index: int, price: int) -> void:
	var entry: Dictionary = GameState.shop_stock[index]
	if entry["sold"] or not GameState.spend_gold(price):
		return
	entry["sold"] = true
	var id: String = entry["id"]
	# bought with run gold, so it is held at risk on the same terms (D20)
	GameState.earn_card(id)
	var c := load(MetaState.CATALOG[id]) as CardData
	Audio.play("gold")
	msg_label.text = "Bought %s." % (c.name if c != null else id)
	_refresh()

func _on_buy_heal(price: int, amount: int) -> void:
	if not GameState.spend_gold(price):
		return
	GameState.hp = min(GameState.max_hp, GameState.hp + amount)
	Audio.play("ui_confirm")
	msg_label.text = "Healed %d HP." % amount
	_refresh()

func _on_leave() -> void:
	GameState.clear_node(GameState.pending)
	GameState.shop_stock = []
	GameState.autosave()
	get_tree().change_scene_to_file(GameState.run_scene())
