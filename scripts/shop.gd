## Shop node (Phase 8) — the gold sink. Sells cards (into the permanent collection
## AND the current run deck, matching reward semantics D1) and healing for the
## current run. Inventory is rolled once per visit and stored on GameState so
## leaving and returning cannot reroll it.
extends Control

const CARD_DIR := "res://resources/cards/"
## Fallback stock when the dungeon defines no pool.
const DEFAULT_STOCK := ["hack", "cover", "stave_in", "shoulder", "clear_mind",
	"put_the_fear", "work_up", "light_on_it", "set_stone"]

# The stall is a STALL: the goods are laid out as the things they are, and the price is under
# each one (D300).
#
# It used to be a table — one row per item, a 28px thumbnail, a 32px effect symbol, 600px of
# `clip_text` description and a `Buy 40 g` button in a column at the right. Everything about that
# was measured and correct and none of it was a shop. The card you were spending on was a
# thumbnail the width of a fingernail beside a sentence cut off mid-word, which is the one place
# in this game where a card is bought with gold and the purchase cannot be undone. On a phone the
# 600px column had nowhere to go at all.
#
# So the merchant lays the cards out at reward size, face up, priced. What the player compares is
# the cards, the way they compare them at every other decision in the run — the same
# `UI.card_button` the reward panel and the deck builder draw, so a card looks like itself
# everywhere and hover, right-click-to-inspect and the touch reveal all come with it.
#
# The two SERVICES — healing and thinning — are tiles of the same height beside the cards rather
# than rows under them. They compete with the cards for the same gold, so they belong on the same
# shelf; a service in a list below reads as an afterthought, and thinning the deck is often the
# better buy.

## How many tiles the shelf is sized to hold across: the merchant's cards, plus the salve and the
## thinning. Derived from `Balance.SHOP_CARD_OFFERS` rather than restated, so raising the stock
## narrows the faces instead of running the row off the edge.
const SERVICE_TILES := 2
## A service tile's width, unscaled: narrower than a card, because it carries a line of prose and
## a price rather than a picture, and two of them share the shelf with the cards.
const SERVICE_W := 210.0

var status_label: Label
var msg_label: Label
var stock_box: HBoxContainer

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
	UITheme.style_title(title)
	root.add_child(title)

	status_label = Label.new()
	root.add_child(status_label)

	msg_label = Label.new()
	root.add_child(msg_label)

	# The shelf scrolls, and it scrolls SIDEWAYS as well: a phone held upright cannot fit three
	# card faces and two service tiles across, and a stall you cannot reach the end of is a stall
	# with goods you never knew were for sale. `UI.scroll` brings `DragScroll` with it, which is
	# the only thing that pans a row of buttons under a finger (D225).
	var shelf := UI.scroll(root)
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_box = HBoxContainer.new()
	stock_box.add_theme_constant_override("separation", UITheme.sep(12))
	stock_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	shelf.add_child(stock_box)

	UI.exit_button(root, "Leave", _on_leave, 40.0)

# --- the stall (see the constants above) --------------------------------------

## One thing on the shelf: whatever is on offer, and under it the one control that buys it.
##
## Every item is this shape — a card, the salve, the thinning — so the prices line up along one
## band across the stall and "what does this cost" is answered by looking down rather than by
## reading a row across to a button column.
func _stall(width: float) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(6))
	col.custom_minimum_size.x = width
	# FILL, so every column is as tall as the tallest — which is a card column. That is what lets
	# a service tile put an expanding label above its button and land the button on the same band
	# as the three `Buy`s. With SHRINK_BEGIN the services hugged the top and their buttons sat
	# level with the card ART instead, which reads as two shelves rather than one.
	col.size_flags_vertical = Control.SIZE_FILL
	stock_box.add_child(col)
	return col

## The buy control, and the two ways it can refuse.
##
## A greyed button showing a bare price does not say WHY, and the merchant is unaffordable on most
## first visits (D71) — so the one screen that has to explain itself explained nothing. The
## shortfall is on the button, in the same shape `combat.gd:_refresh_power()` states its own.
func _price_button(col: VBoxContainer, price: int, on_press: Callable,
		sold: bool = false) -> Button:
	var b := Button.new()
	UITheme.style_button(b)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(b)
	if sold:
		b.text = "SOLD"
		b.disabled = true
		return b
	if GameState.available_gold() < price:
		b.text = "%d g  (short %d)" % [price, price - GameState.available_gold()]
		b.disabled = true
		UI.hoverable(b, "Costs %d gold. You have %d." % [price, GameState.available_gold()])
		return b
	b.text = "Buy  %d g" % price
	b.pressed.connect(on_press)
	return b

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

	# --- the cards, face up ---
	#
	# Sized off the frame the way the reward panel sizes its own offers, so a narrow screen gets
	# smaller faces rather than a row running off the edge.
	var base := UITheme.reward_card_size()
	var cw := Icons.fit_card_width(Balance.SHOP_CARD_OFFERS + SERVICE_TILES, base.x,
		get_viewport_rect().size.x - UITheme.px(60), float(UITheme.sep(12)))
	var ch := base.y * (cw / base.x)
	for i in GameState.shop_stock.size():
		var entry: Dictionary = GameState.shop_stock[i]
		var card := load(MetaState.CATALOG[entry["id"]]) as CardData
		if card == null:
			continue
		var price: int = Balance.card_price(card.rarity, GameState.dungeon)
		var col := _stall(cw)
		# The note is the PRICE and where the card stands in the collection. The shop's own
		# question is "what does this cost and can I pay for it"; the collection's is "do I
		# already have one" — and on the one screen where a card is bought with gold, both of
		# them are the decision. `UI.card_button` puts the note on the hover and carries it into
		# the inspect overlay, so a card held up at full size still says what the shelf said.
		var note := "Costs %d gold. You have %d.\n\n%s" % [
			price, GameState.available_gold(), String(UI.collection_standing(card)["tip"])]
		if entry["sold"]:
			note = "Already bought this visit.\n\n" + String(UI.collection_standing(card)["tip"])
		# No press action on the face (D300). The face is for reading; the price button buys.
		# That is the same rule the reward panel now runs on, and it matters more here: a tap
		# that finishes reading a card must not be the tap that spends the gold.
		UI.card_button(col, card, Vector2(cw, ch), Callable(), "", null, note, true)
		# ON the shelf, not only in the hover (D322). `collection_standing` has answered this
		# since D174 and both screens put the answer in a tooltip, so a phone — which has no
		# hover — could not reach it at all, and a desktop had to go looking for it on each of
		# the three stalls in turn. `collection_line` was written for this and never called.
		#
		# EXPAND_FILL for the reason the salve's description carries it: the note is the one
		# part of a stall whose height depends on its content — a legendary quoting two stat
		# changes wraps to twice the lines a common does — so it is the part that absorbs the
		# slack. Without this the longest note pushes its own price and Buy button below the
		# other two, and the price band that the whole stall layout exists to line up stops
		# lining up. Measured on a Crypt shelf: the legendary's button sat 32px low.
		var note_label := UI.collection_line(col, UI.collection_standing(card))
		note_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var pl := UI.label(col, "%s  %s" % [
			CardData.rarity_badge(card.rarity), "SOLD" if entry["sold"] else "%d g" % price])
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
		_price_button(col, price, _on_buy_card.bind(i, price), bool(entry["sold"]))

	_add_heal_service(cw)
	_add_removal_service()

## The salve, as a tile on the same shelf as the cards.
func _add_heal_service(card_w: float) -> void:
	var heal := Balance.heal_amount(GameState.max_hp)
	var price := Balance.heal_price(GameState.max_hp, GameState.dungeon)
	var col := _stall(minf(UITheme.px(SERVICE_W), card_w))
	var t := UI.label(col, "Healing salve")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.95, 0.87, 0.62))
	var l := UI.label(col, "Restores %d HP. You are on %d of %d." % [
		heal, GameState.hp, GameState.max_hp])
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.hoverable(col, "Healing is bought with the same gold as a card. HP you do not spend on the next fight is HP you keep for the boss.")
	if GameState.hp >= GameState.max_hp:
		var full := Button.new()
		UITheme.style_button(full)
		full.text = "Already full"
		full.disabled = true
		full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(full)
		return
	_price_button(col, price, _on_buy_heal.bind(price, heal))

## Thinning is the other direction of deck building, and it belongs next to the
## things it competes with for the same gold.
func _add_removal_service() -> void:
	var price := Balance.removal_price(GameState.run_removals, GameState.dungeon)
	var col := _stall(UITheme.px(SERVICE_W))
	var t := UI.label(col, "Thin your deck")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(0.95, 0.87, 0.62))
	# The two numbers are the whole decision — what a removal is WORTH is how much more often
	# everything else comes up (D70's rule, applied to a price in cards).
	var l := UI.label(col, "This run only. %d cards, one seen every %.1f turns." % [
		GameState.run_deck.size(), Balance.draw_interval(GameState.run_deck.size())])
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UI.hoverable(col, "Removing a card makes the rest come up more often. It does not touch your collection — this run only.")

	var btn := Button.new()
	UITheme.style_button(btn)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(btn)
	# Two different reasons this can be refused, and they were both silent.
	if not GameState.can_remove_from_run_deck():
		btn.text = "Deck at minimum"
		btn.disabled = true
		UI.hoverable(btn, "A run deck may not go below %d cards." % Balance.MIN_DECK_SIZE)
		return
	if GameState.available_gold() < price:
		btn.text = "%d g  (short %d)" % [price, price - GameState.available_gold()]
		btn.disabled = true
		UI.hoverable(btn, "Costs %d gold. You have %d." % [price, GameState.available_gold()])
		return
	btn.text = "Remove  %d g" % price
	btn.pressed.connect(_on_remove.bind(price))

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
