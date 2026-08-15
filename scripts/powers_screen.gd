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
## What a player actually needs here is which powers the door can deal, and since D290 that is ONE
## question. A power is held or it is not. Gold does not buy one — beating a dungeon hands it over —
## and the clears gate that used to sit beside ownership is deleted.
##
## That collapses the four row states D289 had to invent back down to two, and the paragraph of
## apology under the header with them. **The fix for a confusing screen turned out to be one fewer
## rule in the game behind it.**
##
## Still grouped by RARITY, and the reason changed with the gate. It is no longer that a whole
## rarity opens at once — nothing opens by rarity any more. It is that rarity is the axis a player
## reads a power's strength off (D224), and a locked row now names its own dungeon, which is a fact
## per row rather than per group.
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
		if owned:
			in_deal += 1
		groups[p.rarity].append({"id": pid, "owned": owned})

	# The count the player came here for, and the one the old header never printed. "Equipped:
	# Bulwark" is gone with the button under it: it named a power the door does not read.
	#
	# ONE number now. It used to need a second line explaining that the door topped the pool up
	# from unbought powers, and that top-up branch is deleted (D290) — so the headline and the
	# group headers below it are the same count by construction rather than by care.
	info_label.text = "Gold %d    Clears %d    %d of %d in the deal" % [
		MetaState.gold, MetaState.clear_count(), in_deal, slots]

	# Where the rest come from, said once. Silent at the end, because a line that congratulates
	# you on a finished set every time you open the screen stops being read (D240).
	var left := slots - in_deal
	rule_label.visible = left > 0
	if rule_label.visible:
		rule_label.text = ("The other %d are held by the places that own them. Beat a dungeon and it "
			+ "hands over %s — no gold, and nothing to buy.") % [
			left, Wording.count(Balance.POWERS_PER_DUNGEON, "power")]

	for c in list_box.get_children():
		c.queue_free()

	for rarity in CardData.Rarity.size():
		if not groups.has(rarity):
			continue
		var entries: Array = groups[rarity]
		# No SEALED marker on the header any more (D290). Nothing opens by rarity — a locked power
		# names the dungeon that holds it, on its own row, which is a different fact for each row
		# in the group and cannot be said once above them.
		var held := 0
		for e in entries:
			if bool(e["owned"]):
				held += 1
		var head := UI.label(list_box, "%s  %d of %d in the deal" % [
			CardData.rarity_badge(rarity), held, entries.size()])
		head.add_theme_color_override("font_color", Icons.rarity_colour(rarity)
			if held > 0 else Icons.rarity_colour(rarity).darkened(SEALED_DIM))

		for e in entries:
			_row(String(e["id"]), bool(e["owned"]))

func _row(pid: String, owned: bool) -> void:
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
		# EXPAND_FILL, not a fixed width. At 520px the longest row — Running Total's
		# "Deal 1 damage. +2 per earlier card." — overflowed its own minimum and pushed its Buy
		# button a hundred pixels right of every other one, so the button column was straight for
		# nine rows and bent for the tenth. Measured off the capture rather than guessed (D95):
		# letting the label eat the slack puts every button on the same right edge whatever the
		# effect text says, and a longer effect written later cannot bend it again.
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.custom_minimum_size.x = UITheme.px(520)
		# A sealed row recedes by ink, which is what says "not yet" without a badge repeating
		# the group header above it. `darkened` keeps the rarity hue, so a dim row still says
		# which tier it belongs to (D96).
		lbl.add_theme_color_override("font_color", Icons.rarity_colour(p.rarity)
			if owned else Icons.rarity_colour(p.rarity).darkened(SEALED_DIM))
		var cost := "free" if p.eff_cost() == 0 else "%dE" % p.eff_cost()
		# TWO states (D290). D289 needed four because ownership and a clears gate were separate
		# questions and the top-up branch made a third answer out of the pair. One rule, one word.
		var state := "in the deal" if owned else "locked"
		lbl.text = "%s  [%s]  %s   Lv%d/%d   (%s)" % [
			p.name, cost, p.effect_text(), level, p.level_capped(), state]
		row.add_child(lbl)
		UI.hoverable(row, _row_tip(pid, owned))

		if not owned:
			# The Buy button stood here and is GONE (D290). Gold does not buy a power: the place
			# that holds it does, and the row says WHICH place. That is what the old button could
			# never say — "needs 3 more clears" names a number, and a number is not somewhere you
			# can go. `Balance.dungeon_for_power` is the one owner of that mapping.
			var from := Balance.dungeon_for_power(pid)
			var dd := Balance.dungeon(from)
			var gate := Button.new()
			UITheme.style_button(gate)
			gate.text = "clear %s" % (dd.name if dd != null else from)
			gate.disabled = true
			row.add_child(gate)
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

		# The Equip button stood here and is GONE (D289). It called `MetaState.equip_power`, which
		# no longer decides anything a player can see: the run's power comes from the three the
		# door deals (D245/D253). A button reading "Equipped" beside one row, on a screen whose
		# question is which power you take in, answered that question wrongly and louder than
		# anything else on the screen. `equip_power` and `equipped_power` stay in `MetaState` —
		# `set_run_power("")` falls through to them and the tools and suites rely on it — but the
		# fallback is not a decision, so it does not get a control.

func _row_tip(pid: String, owned: bool) -> String:
	if owned:
		return "In the deal. The door can offer you this one, and it leans toward the deck you built."
	var dd := Balance.dungeon(Balance.dungeon_for_power(pid))
	if dd == null:
		return "Locked."
	return ("Held by %s. Beat that place once and it is yours for good — there is nothing to buy "
		+ "and no gold to save up.") % dd.name

func _on_upgrade(pid: String) -> void:
	if MetaState.upgrade_power(pid):
		Audio.play("fuse")
		_refresh()
	else:
		Audio.play("ui_denied")
