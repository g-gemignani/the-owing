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
## The one line that says what the selected power does and what its next level buys (D312).
var reader: Label
## The only control on this screen that spends anything. Disabled until a power is picked, and it
## states its own refusal when the pick cannot be levelled.
var up_btn: Button
## Which power the reader and the button are about. "" until one is pressed.
var picked: String = ""

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
	# The reader and the one button that acts on it, ABOVE the list and outside the scroll, so
	# they stay in front of the player while the wall of sigils moves under them (D312). Built to
	# full height before anything is pressed, like every other reader in this game: a line that
	# grew on the first press would shove the list down.
	reader = UI.fixed_line(root, UITheme.px(UI.RELIC_READER_H))
	reader.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))
	up_btn = Button.new()
	UITheme.style_button(up_btn)
	up_btn.disabled = true
	up_btn.text = PICK_FIRST
	up_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	up_btn.custom_minimum_size.x = UITheme.px(UI.BUTTON_WIDTH)
	up_btn.pressed.connect(func(): _on_upgrade(picked))
	root.add_child(up_btn)

	list_box = UI.scroll(root)
	UI.exit_button(root, "Back", func(): UI.goto(self, _back_to()))

## What the level button says with nothing picked. It states its own refusal, the way every other
## refusing button in this game does (D71).
const PICK_FIRST := "Pick a power above first"

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

	# The resting line, honest about what can be pressed. A screen with nothing in the deal has no
	# power to read, and telling the player to press one would be telling them to press a wall of
	# dead tiles.
	if picked == "":
		reader.text = "Press a power you hold to read it and level it." if in_deal > 0 \
			else "Beat a dungeon and the power it holds appears here."
		up_btn.disabled = true
		up_btn.text = PICK_FIRST

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

		# A FLOW of tiles, the shape the Relics screen wears (D312). Thirty powers as rows of
		# icon-plus-sentence-plus-button is a column of paragraphs; the sigils are painted, one per
		# power since D259, and they were a 32px thumbnail at the left margin of a text row.
		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", UITheme.sep(8))
		grid.add_theme_constant_override("v_separation", UITheme.sep(8))
		list_box.add_child(grid)
		for e in entries:
			_tile(grid, String(e["id"]), bool(e["owned"]))

## One power as a tile: its sigil, its name, and the press that selects it (D312).
##
## Selecting and never spending, which is the rule this project arrived at the hard way (D307): a
## tile SELECTS and a button ACTS. Pressing a tile is idempotent — it reads the power into the line
## above and points the level button at it, as many times as you like — so there is no second press
## that means something different and nothing here can spend gold by being tapped twice.
##
## A LOCKED power is greyed and dead, exactly as an unmet relic is (D308). There is nothing behind
## it: gold does not buy a power, the place that holds it hands it over, and the hover names that
## place. A control that answers a press with "there is nothing here" teaches the player to press
## it again.
func _tile(grid: Container, pid: String, owned: bool) -> void:
	var p := Balance.power(pid)
	if p == null:
		return
	var level: int = int(MetaState.powers.get(pid, 1))
	p = p.duplicate()
	p.level = level

	# The painted sigil when one is installed, the procedural glyph when it is not — the same
	# one-file-at-a-time contract the relics screen runs on (D121, D122).
	var painted := PixelArt.power_art(pid)
	var b := UI.sigil_face(grid, painted if painted != null else Icons.tex(Icons.for_card(p)),
		p.name, Icons.rarity_colour(p.rarity), 0.0 if owned else SEALED_DIM)
	UI.hoverable(b, _row_tip(pid, owned))
	if not owned:
		b.disabled = true
		return

	# How far up its track this power has come, over the sigil rather than beside it (D132). Only
	# over a painted sigil: the procedural glyph is a flat shape with no room inside it for light
	# to read as anything but smudging.
	var fx := PixelArt.level_overlay("power", level, p.level_capped()) if painted != null else null
	if fx != null:
		var art := _art_of(b)
		if art != null:
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

	b.pressed.connect(func() -> void:
		picked = pid
		_say(pid)
		Audio.play("ui_select"))

## The sigil inside a tile, so the level glow can be parented onto its rect rather than laid over
## the whole button. Found rather than passed back, because `UI.sigil_face` returns the one thing
## every caller needs and a second return value for one caller is a worse seam than a search of
## two children.
func _art_of(b: Button) -> TextureRect:
	for c in b.get_children():
		for k in c.get_children():
			if k is TextureRect:
				return k as TextureRect
	return null

## Read the picked power into the line, and point the level button at it.
##
## The button says what the level BUYS, which is the mechanism the camp's Temper uses on a card
## (D307) and the same sentence the collection quotes when it sells a card level. A power that
## levels for gold and never says what the gold changes was selling a number.
func _say(pid: String) -> void:
	var p := Balance.power(pid)
	if p == null:
		return
	var level: int = int(MetaState.powers.get(pid, 1))
	p = p.duplicate()
	p.level = level
	var cost := "free" if p.eff_cost() == 0 else "%dE" % p.eff_cost()
	var gain: String = p.level_up_text(level + 1)
	var tail := ""
	if p.at_max():
		tail = "  Lv%d is its cap." % level
	elif gain != "":
		tail = "  Lv%d would buy: %s" % [level + 1, gain]
	reader.text = "%s  [%s]  %s   Lv%d/%d.%s" % [
		p.name, cost, p.effect_text(), level, p.level_capped(), tail]

	# Three refusals, each of which was silent behind a greyed button, and each of which is a
	# different thing for the player to do next.
	if p.at_max():
		up_btn.disabled = true
		up_btn.text = "%s is at its cap" % p.name
		return
	var price: int = MetaState.power_upgrade_price(pid)
	if not MetaState.can_upgrade_power(pid):
		up_btn.disabled = true
		up_btn.text = "Level up  %dg  (short %d)" % [price, maxi(0, price - MetaState.gold)]
		return
	up_btn.disabled = false
	up_btn.text = "Level up %s  (%dg)" % [p.name, price]

func _row_tip(pid: String, owned: bool) -> String:
	if owned:
		return "In the deal. The door can offer you this one, and it leans toward the deck you built."
	# Guarded on the ID before the load, not on the result after it. `dungeon_for_power` answers ""
	# for a power no dungeon grants, and `Balance.dungeon("")` then tries to load
	# `res://resources/dungeons/.tres` — an engine error printed on every hover, under a tooltip
	# that handled the null perfectly well. A null check after a bad load is a check that runs too
	# late to stop the noise.
	var from := Balance.dungeon_for_power(pid)
	var dd := Balance.dungeon(from) if from != "" else null
	if dd == null:
		return "Locked. No dungeon grants this one yet."
	return ("Held by %s. Beat that place once and it is yours for good — there is nothing to buy "
		+ "and no gold to save up.") % dd.name

func _on_upgrade(pid: String) -> void:
	if pid == "":
		return
	if MetaState.upgrade_power(pid):
		Audio.play("fuse")
		_refresh()
		# The selection SURVIVES the rebuild, and the line re-reads at the new level: levelling a
		# power is the one action on this screen a player repeats, and dropping the pick would make
		# them find the same sigil again between every press.
		_say(pid)
	else:
		Audio.play("ui_denied")
