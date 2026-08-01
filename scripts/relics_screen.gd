## Relic inventory — all thirty slots, held and unheld.
##
## Read-only: relics are earned, never spent, so this screen's job is to make the
## run's accumulated character legible.
##
## It used to do that by counting, and only by counting: "0 of 30 relics found",
## "None yet", "Still undiscovered: 30" — one fact stated three times, and past it a
## fresh save saw nothing at all, four short lines in the corner of an empty frame.
## A count is not a collection. This lists every SLOT, so what is out there has a
## shape before you own any of it (D116). No relic art exists yet, so the slot is
## text; when the thirty paintings land they go in the cell beside the name and
## nothing else here has to move.
##
## **An unfound slot shows its name and its rarity, and withholds only the effect.**
## The alternative — thirty rows of "???" — is the old defect with more rows: it
## states "you have not found this" twenty-four times and says nothing else, and a
## want-list you cannot read is not a want-list. The name is safe to print because
## there is nothing to plan against it: a relic is a rarity-weighted roll off a boss
## or an elite (`MetaState.pick_relic`), never a thing you can go and buy, so knowing
## Ancient Battery exists changes no decision the player is able to make. Rarity is
## the one part that DOES connect to a decision — a harder, deeper fight tilts the
## roll (`Balance.tier_weights`) — so it is shown deliberately, not leaked. The
## effect stays hidden because it is the only part reading as a discovery when the
## relic finally drops, and half these names give it away anyway.
extends Control

## Grouped by RARITY, because rarity is the one axis of a relic the player can act
## on: a deeper, harder fight rolls rarer ones (`Balance.WEIGHTS`, tilted by
## difficulty in `Balance.tier_weights`). It is also the only interesting shape the
## set has — 7 / 8 / 7 / 5 / 3, a pyramid — and a flat alphabetical list of thirty
## names hides it. Within a group the catalogue order stands: a slot that jumped
## somewhere else the moment it was filled would make the list feel unstable, and
## a fixed place is a thing the player can learn.
##
## The bracketed tag comes from `CardData.rarity_badge`, the one owner of that
## convention (D115), and is printed ONCE per group instead of on all thirty rows —
## the group header IS the rarity, so a badge per row would be the screen's old
## say-it-three-times habit at a smaller scale. Colour carries it on the rows.
const COLUMNS := 3

## Column floor, in unscaled px. Three columns is what fills 1280 with entries this
## short; one column of thirty one-line rows leaves half the frame empty, which is
## the defect being fixed. Measured against the widest string the relic table can
## actually produce rather than picked (the D95 rule): the longest effect line,
## Reliquary Heart's "Below 50% HP, gain 3 Strength. Once per combat.", renders 380px
## at 16px font, so at this floor every one of the thirty holds a single line — and
## a longer one added later wraps inside its cell instead of shoving the grid wider.
const SLOT_WIDTH := 380.0

## A group header's line height, in unscaled px, against a 16px font — the slack is
## the gap above it, which is where a group gets its air. Traded against the row
## pitch until the empty state fit: at 34 the last Legendary row was cut in half by
## the scroll edge, and at 26 the gap above a header (32px) was within 5px of the
## pitch inside one (27px), so the five groups read as one list of thirty. 30 puts
## 36 against 27 and still fits all thirty slots in 720px with no scrolling at all,
## which is the empty state's one real virtue.
const HEAD_LEADING := 30.0

## How far an unfound name recedes. By INK, never by `modulate`: a translucent label
## reads against the backdrop rather than against the colour chosen for it (D96).
## `darkened` keeps the rarity hue, so a dim slot still says which tier it belongs
## to, and it mixes toward black rather than restating the clear colour out of
## `ui_theme.gd` — a copied constant is the D34 bug in miniature.
##
## Measured on the 1280x720 capture, worst backdrop pixel under the row: held names
## run 6.1:1 (Epic) to 11.4:1 (Common), unfound 3.2:1 to 5.4:1, so every slot keeps
## about half the luminance of a held one. It started at 0.45 and that put Epic at
## 2.4:1, which is a name you have to hunt for on the screen that is mostly names.
##
## 4.5:1 is NOT reachable for an unfound Rare or Epic and asking for it would be a
## bug: those two hues are only 7.1:1 and 6.1:1 when held, so a dim variant bright
## enough to clear 4.5 would be indistinguishable from owning the thing. The palette
## sets the ceiling here; the guarantee this constant makes is the RATIO between the
## two states, not an absolute floor.
const UNFOUND_DIM := 0.32

func _ready() -> void:
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black
	# (D95). This one already called it — checked, not assumed.
	var col := UI.screen(self, "Relics")

	# One pass builds the groups AND the count, so the number in the header is not a
	# second sum of the same thing (the mistake `collection.gd` documents), and the
	# total counts slots this screen actually shows rather than catalogue keys — a
	# relic whose resource failed to load is not a relic the player can be told about.
	var groups := {}
	var slots := 0
	var found := 0
	for id in MetaState.RELIC_CATALOG:
		var r := load(MetaState.RELIC_CATALOG[id]) as RelicData
		if r == null:
			continue   # a half-added relic fails loudly in test_content, not quietly here
		slots += 1
		var owned: bool = MetaState.has_relic(id)
		if owned:
			found += 1
		if not groups.has(r.rarity):
			groups[r.rarity] = []
		groups[r.rarity].append({"relic": r, "owned": owned})

	# The count, once — and then what to go and do about it, which is the part the
	# three old lines never said. A boss is the guaranteed source (`combat.gd` grants
	# one on a clear); an elite drops one at risk, and a few events hand one over.
	UI.label(col, "%d of %d found. Every dungeon boss gives one; elites and some events do too." % [
		found, slots])
	# Stated once, for the whole list, instead of writing "undiscovered" beside
	# twenty-four rows. Dropped when there is nothing left to withhold.
	if found < slots:
		UI.label(col, "An unfound relic shows its name and its rarity. What it does is learned by holding it.")

	# Empty, all thirty slots and their five headers fit 720px with no scrollbar at
	# all — measured, and what HEAD_LEADING is tuned against. Every slot that fills in
	# grows an effect line, so a well-stocked save runs about 900px and has to scroll,
	# the same way the collection does. `scrollbar_track`/`scrollbar_grabber` are
	# installed now, so this is the painted scrollbar rather than Godot's default.
	var list := UI.scroll(col)
	for rarity in CardData.Rarity.size():
		if not groups.has(rarity):
			continue
		var entries: Array = groups[rarity]
		var held := 0
		for e in entries:
			if bool(e["owned"]):
				held += 1
		var head := UI.label(list, "%s  %d of %d" % [
			CardData.rarity_badge(rarity), held, entries.size()])
		head.add_theme_color_override("font_color", Icons.rarity_colour(rarity))
		# The air a group needs goes ABOVE its header, and the scroll's own uniform
		# separation cannot put it on one side only — so the header carries a floor
		# under its height and sits at the bottom of it. Without this, the first
		# capture had "[Uncommon]" jammed against the last Common name and the five
		# groups read as one list of thirty.
		head.custom_minimum_size.y = UITheme.px(HEAD_LEADING)
		head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", UITheme.sep(12))
		grid.add_theme_constant_override("v_separation", UITheme.sep(4))
		list.add_child(grid)
		for e in entries:
			_slot(grid, e["relic"], bool(e["owned"]))

	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

## One slot: the name always, what it does only once it is yours.
##
## The two states differ in ink AND in structure — a found slot grows a second line
## — so the list reads as filled-in versus empty at a glance, without a "locked"
## badge repeated two dozen times.
func _slot(grid: GridContainer, r: RelicData, owned: bool) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size.x = UITheme.px(SLOT_WIDTH)
	grid.add_child(cell)

	var name_label := Label.new()
	name_label.text = r.name
	# `clip_text` is what makes the column floor real: a Label reports its own text
	# as its minimum width and grows straight past a `custom_minimum_size`, which is
	# how the Packs screen ended up with three buttons at three x positions (D95).
	# No relic name is long enough to be clipped today; the guard is for the one that
	# is added tomorrow.
	name_label.clip_text = true
	var tint := Icons.rarity_colour(r.rarity)
	name_label.add_theme_color_override("font_color",
		tint if owned else tint.darkened(UNFOUND_DIM))
	cell.add_child(name_label)

	if owned:
		# The authored description, not a paraphrase. Relics have no levels, so
		# unlike a card face (D50) this text cannot go stale — and restating what
		# the .tres says would be a second copy of it that could.
		UI.label(cell, r.description)
