## Powers screen — buy a power, level it, and see which ones the door can deal you.
##
## The meta layer's second progression axis. Fusion turns copies plus gold into
## card levels; this turns gold alone into an ability that fires every single turn.
## They compete for the same purse on purpose (see Balance.power_upgrade_cost,
## which reuses the fusion gold curve), so spare gold always has two homes.
##
## **The screen used to describe the game as it was before D245, and that is what this
## rewrite is for.** Its title said *"one equipped per run"*, its header said
## *"Equipped: Bulwark"*, and every owned row carried an **Equip** button. None of that
## decides anything any more: the run deals three powers at the door and the player picks
## one (D245/D253), weighted by the deck (D256). `equipped_power` survives only as the
## fallback `set_run_power("")` reads, which no player can see. **A button that says
## "Equipped" is the strongest possible claim about which power you take in, and it was
## false.** D256 removed the deck builder's power box for this exact reason — *"a second
## place to press a decision that already had a first one"* — and this is the same box on
## a different screen.
##
## What a player actually needs here is which powers the door can deal, and the pool rule
## in `MetaState.power_offer` has three states, not two:
##
## * **unlocked and owned** — in the deal.
## * **unlocked, not owned** — buyable, and dealt anyway while you own fewer than three,
##   because an offer of one is not a choice.
## * **sealed by clears** — cannot be dealt at all.
##
## The old label collapsed all of that into `(owned)` / `(locked)`, so a power that was
## unlocked and merely unbought read as **locked**. That is the reported confusion, and it
## was the label rather than the gate.
##
## Grouped by RARITY for the reason the relics screen is (D223): the clears gate is
## `Balance.POWER_UNLOCK` indexed by rarity, so a whole group is sealed or open together
## and the header can say it once instead of every row saying it again.
extends Control

var info_label: Label
var rule_label: Label
var list_box: VBoxContainer

## How far a sealed row recedes. By INK and never by `modulate`, the same rule and the same
## number as the relics screen: a translucent label reads against the backdrop rather than
## against the colour chosen for it (D96).
const SEALED_DIM := 0.32

func _ready() -> void:
	_build_ui()
	_refresh()

func _build_ui() -> void:
	# `reliquary`, shared with the Relics screen: both are the list of what you have
	# earned and cannot lose, so they are one place (D123).
	var root := UI.screen(self, "Powers — the door deals three, you take one",
		"", "reliquary")
	info_label = Label.new()
	root.add_child(info_label)
	# The pool rule, stated once for the whole screen rather than on thirty rows. Written only
	# when it is doing something: a line that is always there stops being read (D240).
	rule_label = Label.new()
	rule_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	root.add_child(rule_label)
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
	var reach: int = MetaState.clear_count()

	# One pass builds the groups AND the counts, so the number in the header is not a second
	# sum of the same thing — the mistake `collection.gd` documents.
	var groups := {}
	var in_deal := 0
	var slots := 0
	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p == null:
			continue
		slots += 1
		if not groups.has(p.rarity):
			groups[p.rarity] = []
		var owned: bool = MetaState.owns_power(pid)
		var open: bool = MetaState.power_available(pid)
		if owned and open:
			in_deal += 1
		groups[p.rarity].append({"id": pid, "owned": owned, "open": open})

	# The count the player came here for, and the one the old header never printed. "Equipped:
	# Bulwark" is gone with the button under it: it named a power the door does not read.
	info_label.text = "Gold %d    Clears %d    %d of %d can be dealt" % [
		MetaState.gold, MetaState.clear_count(), in_deal, slots]

	# `power_offer` tops the pool up from everything unlocked while the save owns fewer than the
	# offer needs, because an offer of one is not a choice. That makes an unowned power dealable
	# RIGHT NOW, which contradicts every other row on the screen — so it is said out loud, and
	# only while it is true.
	var need: int = Balance.REWARD_CARD_OFFERS
	if in_deal < need:
		rule_label.text = ("You own %s that can be dealt, and the door needs %d. "
			+ "Until then it tops the deal up from everything unlocked below.") % [
			Wording.count(in_deal, "power"), need]
		rule_label.visible = true
	else:
		rule_label.visible = false

	for c in list_box.get_children():
		c.queue_free()

	for rarity in CardData.Rarity.size():
		if not groups.has(rarity):
			continue
		var entries: Array = groups[rarity]
		# The gate is per RARITY, so it goes on the group header and nowhere else — the same rule
		# the relics screen follows (D223). A sealed group says what would open it and how far off
		# that is, because "sealed" on its own is the "???" row D116 was built to stop printing.
		var to_go: int = Balance.power_clears_to_go(rarity, reach)
		var held := 0
		for e in entries:
			if bool(e["owned"]) and bool(e["open"]):
				held += 1
		var head := UI.label(list_box, "%s  %d of %d in the deal%s" % [
			CardData.rarity_badge(rarity), held, entries.size(),
			"" if to_go == 0 else "   SEALED — %s to go (%d clears in all)" % [
				Wording.count(to_go, "clear"), int(Balance.POWER_UNLOCK[rarity])]])
		head.add_theme_color_override("font_color", Icons.rarity_colour(rarity)
			if to_go == 0 else Icons.rarity_colour(rarity).darkened(SEALED_DIM))

		for e in entries:
			_row(String(e["id"]), bool(e["owned"]), bool(e["open"]))

func _row(pid: String, owned: bool, open: bool) -> void:
		var p := Balance.power(pid)
		if p == null:
			return
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

		# How far up its track this power has come, over the sigil rather than beside it
		# (D132). Only over a painted sigil — the procedural glyph is a flat shape with no
		# room inside it for light to read as anything but smudging. A child of the art
		# rather than a sibling in the row, so it lands on the sigil's rect and not in a
		# column of its own.
		var fx := PixelArt.level_overlay("power", level, p.level_capped()) if painted != null else null
		if fx != null:
			var glow := TextureRect.new()
			glow.texture = fx
			glow.set_anchors_preset(Control.PRESET_FULL_RECT)
			glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var blend := CanvasItemMaterial.new()
			blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
			glow.material = blend
			glow.modulate = Icons.rarity_colour(p.rarity)
			art.add_child(glow)
			UI.animate_level_glow(glow, PixelArt.level_band(level, p.level_capped()))

		var lbl := Label.new()
		lbl.custom_minimum_size.x = UITheme.px(520)
		# A sealed row recedes by ink, which is what says "not yet" without a badge repeating
		# the group header above it. `darkened` keeps the rarity hue, so a dim row still says
		# which tier it belongs to (D96).
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(p.rarity)
			if open else Icons.rarity_colour(p.rarity).darkened(SEALED_DIM))
		var cost := "free" if p.eff_cost() == 0 else "%dE" % p.eff_cost()
		# THREE states, not two. The old text printed `(owned)` or `(locked)`, so a power that
		# was unlocked and merely unbought said "locked" — which is the one word a player reads
		# as "the door cannot deal me this", and it was wrong about every buyable row.
		var state := "in the deal" if (owned and open) else (
			"not bought" if open else "sealed")
		lbl.text = "%s  [%s]  %s   Lv%d/%d   (%s)" % [
			p.name, cost, p.effect_text(), level, p.level_capped(), state]
		row.add_child(lbl)
		UI.hoverable(row, _row_tip(p, owned, open))

		if not owned:
			if not open:
				var gate := Button.new()
				UITheme.style_button(gate)
				# Two powers unlock at exactly one clear, so this button read
				# "needs 1 clears" for the whole life of the screen (D125).
				#
				# The number is what is STILL TO GO rather than the gate itself (D255), which is
				# what a player wants from a locked row and is what the relics screen already
				# prints. It is derived from rarity now, so a retune of `power_value` moves this
				# line without anybody editing it.
				gate.text = "needs %s" % Wording.count(
					Balance.power_clears_to_go(p.rarity, MetaState.clear_count()), "more clear")
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
			return

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
