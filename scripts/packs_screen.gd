## Packs — the overworld's one moment.
##
## Everything else you bring back from a run has already happened by the time you
## see it: gold is a number that went up, a relic is a line on the deck builder. A
## sealed pack is the only thing that is still *pending* when you get home, and
## opening it is the only beat in the meta layer that resolves in front of you.
##
## Which is why the cards are revealed here, one after another, rather than being
## added silently and reported as "+3 cards". The rarity colour is the payoff.
##
## Each pack states its tier and its build BEFORE it is opened (D81), because that
## is what the player was deciding about when they chose to carry it out of the
## dungeon rather than take the rope. A pack that hid its contents would be a slot
## machine, and the reveal is meant to be the payoff of a decision already made.
extends Control

var list_box: VBoxContainer
var result_box: VBoxContainer
var info_label: Label

func _ready() -> void:
	var col := UI.screen(self, "Packs", "", "table")
	info_label = UI.label(col, "")
	list_box = UI.scroll(col)
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", UITheme.sep(6))
	col.add_child(result_box)
	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))
	_refresh()

## Gilded reads as gold, sealed as parchment, worn as the dust it is.
func _tier_colour(tier: String) -> Color:
	match tier:
		Balance.PACK_GILDED: return Color(1.0, 0.84, 0.40)
		Balance.PACK_SEALED: return Color(0.80, 0.86, 0.95)
		_: return Color(0.72, 0.70, 0.66)

func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()

	var packs: Array = MetaState.packs
	if packs.is_empty():
		info_label.text = "Nothing sealed."
		UI.label(list_box, "Packs are found in treasures, dropped by elites, and left behind by bosses. They come home with you — or they do not come home at all.")
		return

	info_label.text = "%d sealed. Opened here, never in the dungeon." % packs.size()
	if packs.size() > 1:
		# several packs a run was the point of D81; several Open buttons was not
		UI.button(list_box, "Open all %d" % packs.size(), _on_open_all, 38.0)

	for i in packs.size():
		var p: Dictionary = packs[i]
		var tier := String(p.get("tier", Balance.PACK_WORN))
		var build_id := String(p.get("build", ""))
		var did := String(p.get("dungeon", ""))
		var dd := Balance.dungeon(did)
		var row := UI.row(list_box, 10)
		var lbl := Label.new()
		# A minimum width alone did not hold the Open buttons in a column: a Label
		# grows past it to fit its text, so the button's x tracked the length of the
		# pack's name. Clipped, the width is the width, and the column is straight.
		# 600 fits the longest title a pack can have; the tooltip carries the rest.
		lbl.custom_minimum_size.x = UITheme.px(600)
		lbl.clip_text = true
		lbl.add_theme_color_override("font_color", _tier_colour(tier))
		# what is inside is stated up front: a sealed pack is a promise, not a lottery
		lbl.text = "%s   (%d cards, found in %s)" % [
			Balance.pack_title(tier, build_id), Balance.pack_cards(tier),
			dd.name if dd != null else did]
		row.add_child(lbl)
		UI.hoverable(row, _describe(tier, build_id, dd))
		# the carved frame is a nine-patch: squeezed to the width of the word "Open"
		# its borders meet in the middle and the label is drawn over its own edge
		var open_btn := UI.button(row, "Open", _on_open.bind(i), 38.0)
		open_btn.custom_minimum_size.x = UITheme.px(140)

## The tooltip states the cap in words, because "cannot contain a legendary" is the
## whole meaning of a tier and it is not derivable from the name.
func _describe(tier: String, build_id: String, dd: DungeonData) -> String:
	var b := Balance.build(build_id)
	var cap: int = int(Balance.PACK_TIER_CAP.get(tier, CardData.Rarity.RARE))
	var cap_word: String = CardData.rarity_word(cap).to_lower()
	var lines: Array[String] = []
	if b != null:
		lines.append("%s — %s" % [b.name, b.description])
	lines.append("Holds %d cards of that build, nothing better than %s." % [
		Balance.pack_cards(tier), cap_word])
	if dd != null:
		lines.append("Found in %s, which is why it is worth %d gold." % [
			dd.name, Balance.pack_gold(dd.difficulty, tier)])
	return "\n".join(lines)

func _on_open(index: int) -> void:
	var got := MetaState.open_pack(index)
	if got.is_empty():
		return
	Audio.play("treasure")
	_show(int(got.get("gold", 0)), got.get("cards", []),
		Balance.pack_title(String(got.get("tier", Balance.PACK_WORN)),
			String(got.get("build", ""))))

func _on_open_all() -> void:
	var n: int = MetaState.packs.size()
	var got := MetaState.open_all_packs()
	if int(got.get("gold", 0)) == 0 and got.get("cards", []).is_empty():
		return
	Audio.play("treasure")
	_show(int(got.get("gold", 0)), got.get("cards", []), "%d packs" % n)

func _show(gold: int, cards: Array, what: String) -> void:
	for c in result_box.get_children():
		c.queue_free()
	var head := UI.label(result_box, "%s: %d gold, and —" % [what, gold])
	head.add_theme_font_size_override("font_size", UITheme.title_font())

	var size := UITheme.reward_card_size()
	var row := UI.row(result_box, 10)
	var per_row: int = maxi(1, int(floorf(UITheme.px(1180) / maxf(1.0, size.x + UITheme.sep(10)))))
	for i in cards.size():
		# a full haul can exceed one row; wrapping beats a line that runs off-screen
		if i > 0 and i % per_row == 0:
			row = UI.row(result_box, 10)
		var c := Balance.card(String(cards[i]))
		if c == null:
			continue
		# the collection's copy may be levelled; show what was actually gained
		var shown := c.duplicate() as CardData
		shown.level = int(MetaState.collection[String(cards[i])]["level"]) \
			if MetaState.collection.has(String(cards[i])) else 1
		UI.card_button(row, shown, size, Callable())
	_refresh()
