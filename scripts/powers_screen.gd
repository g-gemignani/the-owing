## Powers screen — buy a power, level it, choose which one you take into a run.
##
## The meta layer's second progression axis. Fusion turns copies plus gold into
## card levels; this turns gold alone into an ability that fires every single turn.
## They compete for the same purse on purpose (see Balance.power_upgrade_cost,
## which reuses the fusion gold curve), so spare gold always has two homes.
extends Control

var info_label: Label
var list_box: VBoxContainer

func _ready() -> void:
	_build_ui()
	_refresh()

func _build_ui() -> void:
	# `reliquary`, shared with the Relics screen: both are the list of what you have
	# earned and cannot lose, so they are one place (D123).
	var root := UI.screen(self, "Powers — one equipped per run, fires once every turn",
		"", "reliquary")
	info_label = Label.new()
	root.add_child(info_label)
	list_box = UI.scroll(root)
	UI.exit_button(root, "Back", func(): UI.goto(self, _back_to()))

## Back to wherever this was opened from: the deck builder mid-setup, else the map
## if a run is live, else the overworld.
func _back_to() -> String:
	if GameState.dungeon_id != "" and not GameState.in_run():
		return "res://scenes/DeckBuilder.tscn"
	if GameState.in_run():
		return GameState.resume_scene()   # back into the fight, if one is live
	return "res://scenes/Overworld.tscn"

func _refresh() -> void:
	info_label.text = "Gold %d    Clears %d    Equipped: %s" % [
		MetaState.gold, MetaState.clear_count(),
		MetaState.equipped_power if MetaState.equipped_power != "" else "none"]

	for c in list_box.get_children():
		c.queue_free()

	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p == null:
			continue
		var owned: bool = MetaState.owns_power(pid)
		var level: int = int(MetaState.powers.get(pid, 1))
		p = p.duplicate()
		p.level = level

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.sep(10))
		list_box.add_child(row)

		var art := TextureRect.new()
		# The painted sigil when one is installed, the procedural glyph when it is not.
		# The slot was already here at 32px and already sized, so a painted set changes
		# nothing about this row's layout — which is the whole reason the sigils were
		# asked for as a set rather than as ten separate pictures. Falling BACK to
		# `Icons` rather than replacing it keeps a half-painted set working, the same
		# one-file-at-a-time contract the relics screen runs on (D121, D122).
		var painted := PixelArt.power_art(pid)
		art.texture = painted if painted != null else Icons.tex(Icons.for_card(p))
		art.custom_minimum_size = Vector2(UITheme.px(32), UITheme.px(32))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)

		var lbl := Label.new()
		lbl.custom_minimum_size.x = UITheme.px(520)
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(p.rarity))
		var cost := "free" if p.eff_cost() == 0 else "%dE" % p.eff_cost()
		lbl.text = "%s  [%s]  %s   Lv%d/%d   (%s)" % [
			p.name, cost, p.effect_text(), level, p.level_capped(),
			"owned" if owned else "locked"]
		row.add_child(lbl)
		UI.hoverable(row, Icons.card_tooltip(p))

		if not owned:
			if not MetaState.power_available(pid):
				var gate := Button.new()
				UITheme.style_button(gate)
				# Two powers unlock at exactly one clear, so this button read
				# "needs 1 clears" for the whole life of the screen (D125).
				gate.text = "needs %s" % Wording.count(p.unlock_after_clears, "clear")
				gate.disabled = true
				row.add_child(gate)
			else:
				var price := MetaState.power_price(pid)
				var buy := Button.new()
				UITheme.style_button(buy)
				buy.text = "Buy  (%dg)" % price
				buy.disabled = MetaState.gold < price
				buy.pressed.connect(_on_buy.bind(pid))
				row.add_child(buy)
			continue

		if p.at_max():
			var maxed := Button.new()
			UITheme.style_button(maxed)
			maxed.text = "max level"
			maxed.disabled = true
			row.add_child(maxed)
		else:
			var up := Button.new()
			UITheme.style_button(up)
			up.text = "Level up  (%dg)" % MetaState.power_upgrade_price(pid)
			up.disabled = not MetaState.can_upgrade_power(pid)
			up.pressed.connect(_on_upgrade.bind(pid))
			row.add_child(up)

		var eq := Button.new()
		UITheme.style_button(eq)
		var on: bool = pid == MetaState.equipped_power
		eq.text = "Equipped" if on else "Equip"
		eq.disabled = on
		eq.pressed.connect(func():
			MetaState.equip_power(pid)
			Audio.play("ui_confirm")
			_refresh())
		row.add_child(eq)

func _on_buy(pid: String) -> void:
	if MetaState.buy_power(pid):
		Audio.play("gold")
		_refresh()
	else:
		Audio.play("ui_denied")

func _on_upgrade(pid: String) -> void:
	if MetaState.upgrade_power(pid):
		Audio.play("fuse")
		_refresh()
	else:
		Audio.play("ui_denied")
