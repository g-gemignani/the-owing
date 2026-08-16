## Relic catalogue — every slot, found and unfound.
##
## Read-only, and since D238 it is a record rather than an inventory. A relic is found
## inside a run and leaves with it, so nothing here is owned. What the screen reads is
## `MetaState.relics_seen`, the log of what this character has MET, which is deliberately
## the one part of a relic that carries no power. The run's actual holdings are on the
## Cards screen, because those change the value of the rest of the deck.
##
## It used to state the count, and only the count: "0 of 30 relics found", "None yet",
## "Still undiscovered: 30" — one fact stated three times, and past it a
## fresh save saw nothing at all, four short lines in the corner of an empty frame.
## A count is not a collection. This lists every SLOT, so what is out there has a
## shape before you have met any of it (D116). Each slot carries its painted icon
## (D259 closed the set), drawn beside the name.
##
## **An unfound slot shows its name and its rarity, and withholds only the effect.**
## The alternative — a screen of "???" — is the old defect with more rows: it
## states "you have not found this" once per unfound row and says nothing else, and a
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
## set has — 14 / 9 / 7 / 5 / 3, a pyramid — and a flat alphabetical list of all
## thirty-eight hides it. Within a group the catalogue order stands: a slot that jumped
## somewhere else the moment it was filled would make the list feel unstable, and
## a fixed place is a thing the player can learn.
##
## The bracketed tag comes from `CardData.rarity_badge`, the one owner of that
## convention (D115), and is printed ONCE per group instead of on every tile —
## the group header IS the rarity, so a badge per tile would be the screen's old
## say-it-three-times habit at a smaller scale. Colour carries it on the names.
##
## `COLUMNS := 3` and `SLOT_WIDTH := 380.0` are GONE (D307). Both were measured against a slot
## that was a row of text — the widest effect line the relic table can produce, at the shipped
## font — and the slot is a 132px picture tile now, laid out by an `HFlowContainer` that fits as
## many across as the frame holds. A measured column count is the right answer for a column of
## sentences and the wrong one for a wall of icons.

## A group header's line height, in unscaled px, against a 16px font — the slack is
## the gap above it, which is where a group gets its air. Traded against the row
## pitch until the empty state fit: at 34 the last Legendary row was cut in half by
## the scroll edge, and at 26 the gap above a header (32px) was within 5px of the
## pitch inside one (27px), so the five groups read as one list. 30 puts
## 36 against 27, which is the gap the groups need. **The "empty state fits 720px with
## no scrolling" claim was measured at thirty relics and is not re-measured at
## thirty-eight** — the list scrolls either way (`UI.scroll` below), so this is a
## comment that has stopped being a fact rather than a layout that has broken.
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

## `ICON := 22.0` is GONE with the row it sized (D307). A relic is drawn at `UI.RELIC_TILE_W` by
## `UI.RELIC_TILE_H` now, the same size the elite's offer and the chest's draw it, which is the whole
## point of the change: one relic, one picture, wherever it appears.


## The one line that says what a relic does, shared by every tile on the screen.
var _reader: Label



func _ready() -> void:
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black
	# (D95). This one already called it — checked, not assumed.
	var col := UI.screen(self, "Relics", "", "reliquary")

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
		# MET, not owned (D238). Nothing is owned any more — a relic is found on a run and leaves
		# with it — so this screen is a record of what the character has SEEN. That is the only
		# part of a relic that survives a run, and it is deliberately the part that carries no
		# power (D235).
		var owned: bool = MetaState.seen_relic(id)
		if owned:
			found += 1
		if not groups.has(r.rarity):
			groups[r.rarity] = []
		groups[r.rarity].append({"relic": r, "owned": owned})

	# The count, once — and then what to go and do about it, which is the part the
	# three old lines never said. The sources are the elite and the chest, each of which
	# lays out three to choose from (D239, D240), plus a few events. **The boss is not a
	# source any more (D238)**: its grant sat three statements before `clear_run()`, so a
	# run-scoped relic there would have lived for one function call.
	UI.label(col, "%d of %d met. Elites and chests each offer three to choose from, and some events hand one over." % [
		found, slots])
	# Said plainly, once, because it is the single biggest change to how this game works and a
	# player reading a list of relics they cannot buy or keep needs it said here rather than
	# inferred from a defeat screen.
	UI.hoverable(UI.label(col,
		"Relics are lent, not owned: what you find is yours until the run ends, win or lose."),
		"This list is a record of what you have met. Meeting one is permanent; holding it is not.")
	# Stated once, for the whole list, instead of writing "undiscovered" beside
	# every unfound row. Dropped when there is nothing left to withhold.
	if found < slots:
		UI.label(col, "An unfound relic shows its name and its rarity. What it does is learned by holding it.")
	# ...and the OTHER reason a slot is empty, which is new and is not "you have been
	# unlucky" (D223). The rarer half of the set is sealed until you have cleared
	# enough, so a player grinding the Crypt for a Legendary is grinding for something
	# that cannot drop — and before this there was nothing anywhere that said so.
	var reach: int = MetaState.total_clears()
	var sealed := 0
	for id in MetaState.RELIC_CATALOG:
		if MetaState.relic_locked(id, reach):
			sealed += 1
	if sealed > 0:
		var seal := UI.label(col, ("%d of them are sealed until you have cleared more: %s so far. "
			+ "Depth is what opens them, and a clear of a place you have already beaten counts.")
			% [sealed, Wording.count(reach, "clear")])
		seal.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))

	# Empty, the slots and their five headers were measured to fit 720px with no
	# scrollbar at thirty relics, which is what HEAD_LEADING is tuned against. Every
	# slot that fills in grows an effect line, so a well-stocked save runs past that
	# and has to scroll, the same way the collection does. `scrollbar_track`/`scrollbar_grabber` are
	# installed now, so this is the painted scrollbar rather than Godot's default.
	# ONE reader for the whole screen, above the scroll rather than inside it, so it stays in front
	# of the player while the list moves under it. It is where a relic's effect is said now — the
	# effect used to be a second line inside every met slot, which is thirty-eight paragraphs on
	# one screen and the reason the list could only ever be a column of text.
	#
	# Built to its full height before anything is pressed, like every other reader in this game: a
	# line that grew on the first press would shove the whole list down.
	_reader = UI.fixed_line(col, UITheme.px(UI.RELIC_READER_H))
	_reader.text = "Press a relic to read what it does."
	_reader.add_theme_color_override("font_color", Color(0.92, 0.88, 0.74))

	var list := UI.scroll(col)
	for rarity in CardData.Rarity.size():
		if not groups.has(rarity):
			continue
		var entries: Array = groups[rarity]
		var held := 0
		for e in entries:
			if bool(e["owned"]):
				held += 1
		# The gate is per RARITY, so it goes on the group header and nowhere else —
		# the same rule that keeps the rarity badge off every row. A sealed
		# group says what would open it and how far off that is, because "sealed" on
		# its own is the "???" row this screen was built to stop printing (D223).
		var to_go: int = Balance.relic_clears_to_go(rarity, reach)
		var head := UI.label(list, "%s  %d of %d%s" % [
			CardData.rarity_badge(rarity), held, entries.size(),
			"" if to_go == 0 else "   sealed — %s to go (%d clears in all)" % [
				Wording.count(to_go, "clear"), int(Balance.RELIC_UNLOCK[rarity])]])
		head.add_theme_color_override("font_color", Icons.rarity_colour(rarity)
			if to_go == 0 else Icons.rarity_colour(rarity).darkened(UNFOUND_DIM))
		# The air a group needs goes ABOVE its header, and the scroll's own uniform
		# separation cannot put it on one side only — so the header carries a floor
		# under its height and sits at the bottom of it. Without this, the first
		# capture had "[Uncommon]" jammed against the last Common name and the five
		# groups read as one list.
		head.custom_minimum_size.y = UITheme.px(HEAD_LEADING)
		head.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		# A FLOW of tiles, not a grid of text rows (D307). The relic is the picture now, the same
		# picture the elite's offer and the chest's put in front of the player — so what you met on
		# a reward panel is recognisable on the screen that records it. Flowing rather than a fixed
		# column count because the tile is a fixed 132px and the frame is not: eight fit across a
		# desktop and three across a phone, and neither number belongs in this file.
		var grid := HFlowContainer.new()
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", UITheme.sep(8))
		grid.add_theme_constant_override("v_separation", UITheme.sep(8))
		list.add_child(grid)
		for e in entries:
			_slot(grid, e["relic"], bool(e["owned"]))

	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

## One slot: the relic's face, and the press that says what it does.
##
## It was a row — icon, name, and for a met relic the effect spelled out underneath. That made the
## screen a column of paragraphs three across, and it made a relic look like nothing it looks like
## anywhere else in the game. Now it is the same tile the offers draw (`UI.relic_face`), and the
## effect goes in the one reader at the top of the screen.
##
## **An unmet slot still withholds its effect.** That is the rule this screen was built on: the
## name and the rarity are safe to print because there is nothing to plan against them, and the
## effect is the only part left to be a discovery when the relic finally drops. Pressing one says
## so, rather than saying nothing — a tile that does not answer reads as a tile that is broken.
func _slot(grid: Container, r: RelicData, owned: bool) -> void:
	var b := UI.relic_face(grid, r, 0.0 if owned else UNFOUND_DIM)
	var line := ("%s — %s" % [r.name, r.description]) if owned else \
		"%s — not met yet. What it does is learned by holding it." % r.name
	UI.hoverable(b, line)
	if not UI.touch_ui():
		b.mouse_entered.connect(func() -> void: _reader.text = line)
	b.pressed.connect(func() -> void:
		_reader.text = line
		Audio.play("ui_select"))
