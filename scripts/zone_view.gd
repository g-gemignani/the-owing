## The dungeons of one zone. Split out from the overworld so travelling somewhere
## is a real step: you commit to a region, then choose a door inside it.
##
## It also answers "what is behind this door that I do not have yet" (D166), and the
## shape of that answer is set by the data rather than chosen. `Balance.card_pool_for`
## is the zone's themed pool PLUS the dungeon's own exclusives, and the pool is much
## the bigger half — measured across all twelve:
##
##     barrows       19 shared    crypt +1, ossuary +2, warrens +2
##     foundry_zone  20 shared    foundry +2, ember_road +2, slag_pits +2
##     rot           16 shared    fungal_deep +2, rot_gardens +3
##     deeps         17 shared    sunken_vault +1, drowned_market +1, abyssal_stair +2
##     beyond        15 shared    the_maw +1
##
## So a full pool under every dungeon would print the same nineteen cards three times
## on one screen, and the three lists would differ by two rows. **What is per-dungeon
## is the COUNT and the exclusives; what is per-region is the pool** — so the count and
## the exclusives sit on the dungeon, and the pool is drawn once, at the bottom.
##
## At the bottom, and not the top, because this screen's job is choosing a door. The
## region grid is nineteen slots — five rows, ~200px — and a player arriving to pick a
## dungeon would have had to scroll past their own want-list to reach the buttons.
extends Control

var list: VBoxContainer

## The two grids on this screen are laid out differently, because they hold different
## NUMBERS of the same thing and one rule cannot serve both.
##
## The exclusives are one to three slots. In a fixed grid they were spaced on the
## region pool's pitch, which put the second one 300px from the first with nothing in
## between — attached to a dungeon by indentation alone, half a screen from the line
## that introduces them. They FLOW instead, at a width sized to the widest card name
## the catalogue can produce (137px, measured by `builds_screen.gd` by rendering the
## font rather than counting letters) plus the symbol and its gap: 171, rounded up to
## 200 so tomorrow's card has room.
const EXCL_WIDTH := 200.0

## The region pool is fifteen to twenty slots and wants columns that line up, so it is
## a grid on `builds_screen.gd`'s numbers — four columns at 290 is 1196px, and with
## this screen's 28px indent that is 1224 inside the 1240 the margins leave.
const POOL_COLUMNS := 4
const POOL_WIDTH := 290.0

## Symbol size and the recede for a card not yet held. Both lifted from
## `builds_screen.gd` deliberately, because this is the same widget answering the
## same question and a slot that dimmed differently on the two screens would read as
## two different states. The measurements behind the numbers are documented there.
const ICON := 26.0
const MISSING_DIM := 0.34

## Held so the screen can rebuild itself in place. Taking a debt spends gold and changes what
## every OTHER row on this screen may offer — one debt at a time — so the whole list has to be
## redrawn, not just the row that was pressed (D205).
var zone: ZoneData = null
var purse: Label = null

func _ready() -> void:
	var z := Balance.zone(GameState.current_zone) if GameState.current_zone != "" else null
	if z == null:
		call_deferred("_back")
		return
	zone = z
	var col := UI.screen(self, z.name, "", "", false, z.id)
	UI.label(col, z.description)
	purse = UI.label(col, "")
	list = UI.scroll(col)
	UI.exit_button(col, "Back to the world", func(): _back())
	_refresh()

## Redraw the purse and every row. Cheap enough to do wholesale: this screen holds one region's
## dungeons, and the alternative — patching the pressed row and remembering which other rows a
## purchase invalidated — is the kind of bookkeeping that goes stale the first time a fifth
## state is added to `_debt_offer`.
func _refresh() -> void:
	if zone == null:
		return
	if purse != null:
		# "Met", off `relics_seen` (D247). A purse line reading "Relics 0" beside a real gold
		# figure reads as a bug in the save, which is the worst thing a status bar can do.
		purse.text = "Gold %d    Relics met %d    Cleared %d/%d" % [
			MetaState.gold, MetaState.relics_seen.size(),
			MetaState.clear_count(), Balance.DUNGEONS.size()]
	for c in list.get_children():
		c.queue_free()
	_fill(zone)

func _fill(z: ZoneData) -> void:
	for did in z.dungeons:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.sep(4))
		list.add_child(box)

		# A region opens as a region (D178). Every door inside a zone is open the moment the
		# zone is, so this tag is now the exception rather than the rule: a dungeon states a
		# gate of its own only where it is a genuine capstone, and none of the twelve
		# currently is. `test_build.gd` asserts no dungeon restates the gate its zone already
		# implies — two places holding one number is D34, and its shape here would be a door
		# that stayed shut for a reason the region screen had already contradicted.
		var unlocked: bool = MetaState.dungeon_unlocked(d)
		var tag := "  [cleared]" if MetaState.has_cleared(d.id) else ""
		if not unlocked:
			tag = "  [locked — clear %s]" % Wording.count(
				Balance.effective_gate(d.id), "dungeon")
		# No traversal name on the button any more. It read "isometric floor" on all
		# twelve — a label that never varies is not information, it is furniture, and
		# it was spending the widest line on the screen saying nothing.
		# What it is wearing this time, on the row you press (D187). Named before you commit,
		# for the same reason the boss is (D41): a variation you cannot plan around is a
		# variation you can only be surprised by, and this game does not do that.
		var wears := Balance.aspect_for(MetaState.times_cleared(d.id))
		var wears_tag := "   [%s]" % Balance.aspect_name(wears) if wears != Balance.ASPECT_NONE else ""
		UI.button(box, "%s   difficulty %d%s%s" % [d.name, d.difficulty, wears_tag, tag],
			(func(): _enter(d.id)) if unlocked else Callable(), 40.0)
		UI.label(box, "    %s" % d.description)
		if wears != Balance.ASPECT_NONE and unlocked:
			var al := UI.label(box, "    %s: %s. It pays %d%% more for the trouble." % [
				Balance.aspect_name(wears), Balance.aspect_line(wears),
				Balance.ASPECT_GOLD_PCT])
			al.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))
		# Name the boss at the point of choosing. Knowing what waits is what turns
		# "which dungeon" and "which deck" from guesses into plans.
		var boss := Balance.boss_of(d.id)
		if boss != null and unlocked:
			var bl := UI.label(box, "    Boss: %s — %s" % [
				boss.name, Balance.boss_warning(d.id)])
			bl.add_theme_color_override("font_color", Color(0.95, 0.65, 0.45))
		# The back door, when somebody else's clear in this region has opened one (D190). A
		# second button rather than a toggle, because it is a different run: the same dungeon
		# one floor shorter, with everything it owed you packed into what is left.
		if unlocked:
			_back_door(box, d)
		if unlocked:
			_debt_offer(box, d)
		_cards_here(box, d)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(10))
		box.add_child(gap)
	_region_pool(z)

## The second way in, when a neighbour's clear has opened one (D190, reworded in D206).
##
## The old line was `...or in by the back door: 5 floors, the same reckoning`, and it failed in
## three ways at once — all of them worst at the exact moment the door appears, which is the
## visit after you beat something.
##
##   It never said WHY it was there. The button turns up on a dungeon you have not touched,
##   because you beat a different one. Nothing on it connected the two, so a door opening
##   somewhere you were not looking read as the screen changing its mind.
##
##   "The same reckoning" is opaque. It is trying to say the thing that actually matters — the
##   whole budget is still in there, packed into fewer floors, so this is SHORTER AND DENSER
##   rather than easier (D190) — and no player is getting that from the word "reckoning". A
##   back door that reads as "the easy way in" is a lie about what is behind it.
##
##   And `5 floors` is not a comparison. The number only means something beside the number it
##   replaces, which is the front door's — the same reason `_route_line` prints what you have
##   as well as what is needed, and the same reason the sealed rows print the remainder rather
##   than the total.
##
## A button and an indented line under it, which is the shape this screen already uses for the
## aspect and for the debt: the button is what you would be doing, the line is the terms.
func _back_door(box: VBoxContainer, d: DungeonData) -> void:
	# One question, asked of the one thing that can answer it. `deep_entry_open` now means "is
	# this door real" rather than "has a neighbour fallen" — a place already at the floor
	# minimum cannot be made shorter, so it has no back door to offer however many of its
	# neighbours are beaten (D206).
	if not Balance.deep_entry_open(d.id, MetaState.cleared_dungeons):
		return
	var opener := Balance.deep_entry_opener(d.id, MetaState.cleared_dungeons)
	var full: int = Balance.iso_floors_for(d.difficulty)
	var short: int = Balance.deep_entry_floors(d.id)
	var od := Balance.dungeon(opener)
	UI.button(box, "    ...or in by the back door: %d floors instead of %d" % [short, full],
		func(): _enter(d.id, true), 34.0)
	var terms := UI.label(box, "        %s falling opened it. Every fight it owed you is still in there, packed into one floor fewer — shorter, not easier." % (
		od.name if od != null else opener))
	terms.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))

## What this place will forgive, and what it wants at the door for it (D205).
##
## On the dungeon's own row, which is the entire point of moving it here: the row already names
## the difficulty, the aspect it is wearing and the boss waiting at the bottom, so a debt is one
## more thing to weigh about THIS place before pressing it — rather than a contract taken a
## screen earlier about a dungeon that screen could not show.
##
## Five states, and each says the thing a player actually needs at that moment:
##
##   never beaten   — (D248) this place has nothing to offer yet, and the line says so and says what
##                    opens it. Same reason the sealed rows print the remainder (D178): a door
##                    that is simply absent reads as a door that does not exist.
##   owed here      — you are already carrying this one. Say so, and do not offer it again.
##   owed elsewhere — you are carrying somebody else's. Say WHERE, because the reason this
##                    door is not offering is standing in another region and is otherwise
##                    invisible from here.
##   too dear       — the fee is named and so is the shortfall. A button that is merely
##                    greyed out is a rule the player has to reverse-engineer (D178's lesson
##                    about the sealed rows: an alternative you cannot see does not exist).
##   on offer       — the ask, the fee, and what comes back, in that order.
##
## The never-beaten line comes FIRST, before the one-at-a-time line, because it is the more
## permanent fact about this row: telling a player they already owe somebody else implies this
## door would otherwise be open, and on a place they have never cleared that is not true.
func _debt_offer(box: VBoxContainer, d: DungeonData) -> void:
	# Asked of `debt_on`, not of `has_cleared`, so the rule lives in one place. `Balance.debt_for`
	# is the thing that decides a place has no offer yet, and a second copy of "unless cleared"
	# here is D34 — two places holding one rule, drifting apart the first time it moves.
	var kind := MetaState.debt_on(d.id)
	if kind == "":
		var shut := UI.label(box, "    It has nothing to ask of you yet. Clear it once and it will let you go in owing.")
		shut.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
		return
	var held: Dictionary = MetaState.debt_taken
	if not held.is_empty():
		if String(held.get("dungeon", "")) == d.id:
			var mine := UI.label(box, "    Owed here: %s" % Balance.debt_text(
				String(held.get("kind", "")), d.id))
			mine.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
		else:
			var other := Balance.dungeon(String(held.get("dungeon", "")))
			var away := UI.label(box, "    You already owe %s. One at a time." % (
				other.name if other != null else String(held.get("dungeon", ""))))
			away.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
		return
	var fee: int = Balance.debt_stake(kind, d.id)
	var pays: int = Balance.debt_gold(kind, d.id)
	var tier: String = Balance.debt_pack_tier(kind)
	if MetaState.gold < fee:
		var poor := UI.label(box, "    It would take %d gold at the door for a debt. You have %d." % [
			fee, MetaState.gold])
		poor.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))
		return
	# The fee is named on the button and the payout underneath, because they are different
	# kinds of fact: one is a price, and the other is a thing you might not come back with.
	# Putting them on one line read as a price tag.
	#
	# **The button GOES IN (D211).** It used to take the debt and call `_refresh()`, which
	# spent the gold where the player was standing and left them on this screen next to a
	# row that now said "Owed here" — so pressing the thing that names a dungeon did not go
	# to that dungeon, and the one irreversible part of it had already happened. It is a
	# door now, the same door the two buttons above it are, and it goes through the deck
	# builder like every other way into a dungeon. Nothing is spent until the run starts.
	UI.button(box, "    ...or go in owing, for %d gold at the door: %s" % [
		fee, Balance.debt_text(kind, d.id)],
		func(): _enter(d.id, false, true), 34.0)
	var terms := UI.label(box, "        The %d is taken as the dungeon opens, not now. Settle it and you get it back, %d gold on top, and a %s pack. Fail and the %d is gone." % [
		fee, pays, Balance.PACK_TIER_NAME.get(tier, "Worn"), fee])
	terms.add_theme_color_override("font_color", Color(0.70, 0.82, 1.0))

## What this door is worth to a collection: how much of your pool you already hold,
## and the cards that exist nowhere else, drawn out.
##
## The count covers the WHOLE pool — the region's cards plus this dungeon's own —
## because that is what the door drops, and a count of the exclusives alone would say
## "1 of 2" about a place that can hand you twenty different cards. The grid under it
## is the exclusives only: the rest is the same nineteen cards for every dungeon in
## the region and is drawn once at the bottom of the screen.
##
## A locked dungeon still gets both. What is behind a door you cannot open yet is the
## reason to go and open it, and this screen already names the boss of one.
func _cards_here(box: VBoxContainer, d: DungeonData) -> void:
	var pool: Array = Balance.card_pool_for(d.id)
	if pool.is_empty():
		return
	var held := 0
	for cid in pool:
		if MetaState.collection.has(cid):
			held += 1
	var line := UI.label(box, "    Cards found here: you hold %d of %d." % [held, pool.size()])
	# Gold when there is nothing left to want from this place, on the builds screen's
	# rule — `rarity_colour(4)` is the game's one "this is as good as it gets" colour,
	# and a fifth green chosen here is how a palette stops being one.
	if held == pool.size():
		line.add_theme_color_override("font_color", Icons.rarity_colour(4))

	# A plain loop: `exclusive_cards` is a PackedStringArray, which has no `filter`.
	var only: Array[String] = []
	for cid in d.exclusive_cards:
		if MetaState.CATALOG.has(cid):
			only.append(cid)
	if only.is_empty():
		return
	UI.label(box, "    Found only here:")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UITheme.sep(12))
	flow.add_theme_constant_override("v_separation", UITheme.sep(4))
	box.add_child(_indent(flow))
	for cid in only:
		UI.card_slot(flow, cid, MetaState.collection.has(cid), EXCL_WIDTH, ICON,
			MISSING_DIM, "Found only in %s." % d.name)

## The region's shared pool, once, under everything. Every dungeon in the zone drops
## these, so it belongs to the zone and not to any door in it.
func _region_pool(z: ZoneData) -> void:
	if z.card_pool.is_empty():
		return
	UI.divider(list)
	var held := 0
	for cid in z.card_pool:
		if MetaState.collection.has(cid):
			held += 1
	var head := Label.new()
	head.text = "Found anywhere in this region"
	UITheme.style_title(head)
	list.add_child(head)
	var line := UI.label(list, "    You hold %d of these %d." % [held, z.card_pool.size()])
	if held == z.card_pool.size():
		line.add_theme_color_override("font_color", Icons.rarity_colour(4))

	var grid := GridContainer.new()
	grid.columns = POOL_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UITheme.sep(12))
	grid.add_theme_constant_override("v_separation", UITheme.sep(4))
	list.add_child(_indent(grid))
	for cid in z.card_pool:
		if MetaState.CATALOG.has(cid):
			UI.card_slot(grid, cid, MetaState.collection.has(cid), POOL_WIDTH, ICON,
				MISSING_DIM, "Drops anywhere in %s." % z.name)

## Line a container up with the prose above it. Those lines are indented with four
## literal spaces, and a container cannot be — so the margin is the same step, once,
## rather than every caller nudging its own.
func _indent(c: Control) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", UITheme.sep(28))
	pad.add_child(c)
	return pad

## Every way into a dungeon from this screen: the front door, the back door (D190) and
## owing (D211). All three land in the deck builder, because that is where a run starts.
##
## Both flags are set on EVERY call, never left to a default. They are the two facts about
## a run that only this screen knows, and a player who opens one row, backs out of the deck
## builder and enters a different dungeon must not carry the first row's choice into the
## second. Stating them both every time makes that impossible rather than merely unlikely.
func _enter(id: String, deep: bool = false, owing: bool = false) -> void:
	GameState.select_dungeon(id)
	GameState.deep_entry = deep
	GameState.pending_debt = owing
	UI.goto(self, "res://scenes/DeckBuilder.tscn")

func _back() -> void:
	UI.goto(self, "res://scenes/Overworld.tscn")
