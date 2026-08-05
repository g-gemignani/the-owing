## Overworld: the world as a list of the places you can travel to.
##
## Rows rather than a map with coordinates — a zone's position relative to another
## zone is not a thing the game models, so drawing one would be inventing fiction the
## rest of the code cannot honour. What a row DOES carry is the zone's own
## establishing shot (D96), which is the part that makes five entries read as five
## places instead of five menu items.
##
## Zones own their card pools, so this screen is also where the player decides what
## they will be able to collect. Saying what KIND of deck a zone builds was tried and
## measured out — see `_pool_line()`.
extends Control

## Slightly wider than the 16:9 shots, so the crop trims the sky rather than the
## sides, and sized against a number that is not a taste: five zones plus the two
## button rows have to fit the shipped 720p frame WITHOUT scrolling on a fresh save.
## At 168x95 with a 10px gap the fifth row was cut in half — five pixels over, and the
## first thing a new player saw was a picture sliced by the bottom of the list.
##
## That target is a nice-to-have and it is NOT what keeps the picture whole, which is
## the thing this comment used to imply and D125 caught it not doing: at 160x82 the
## fresh-save list is 497px of content in 462px of frame and the fifth thumbnail was
## sliced again. Nor can any thumbnail size fix it for good — a row grows two lines of
## pool text the moment its zone unlocks, so a fully-cleared save wants 719px and no
## arithmetic here makes five of those fit. Scrolling is the honest answer and the
## defect was never the scrolling; it was the cut landing mid-row. `_snap_list_to_rows`
## is what actually holds the invariant now, at any size and any number of zones.
const THUMB := Vector2(160, 82)
const ROW_GAP := 6.0

var list_bay: MarginContainer
var list: VBoxContainer
var news: Label
var stats: Label

func _ready() -> void:
	# D96 rejected a full-bleed painting here, and what it actually rejected was a ZONE
	# SHOT: whichever zone that picks already has a thumbnail in the list below, so the
	# screen drew the same picture twice, and at ZONE_DIM its bright band ran under the
	# sealed rows' prose. Both halves of that objection are about reusing art composed
	# for somewhere else. `bg_world.png` is painted for this screen — a gateway looking
	# out, with nothing beyond the arch that resolves into a place, precisely so it
	# cannot compete with the five establishing shots stood in front of it (D123). The
	# rows still carry the art; this carries the room they are read in.
	var col := UI.screen(self, "The World", "", "world")
	# What happened since you were last here, kept apart from what is always true.
	# These used to be one label, so the first-run explanation arrived welded to the
	# gold count and wrapped onto a second line (D96).
	news = UI.label(col, "")
	news.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	stats = UI.label(col, "")
	# Zone rows are clipped to WHOLE rows — see `_snap_list_to_rows`. The constant
	# above sizes the list so five zones fit a fresh save without scrolling, and that
	# only ever holds for a fresh save: every zone the player unlocks grows its row by
	# two lines of pool text, so the list outgrows the frame and the fifth picture was
	# being sliced by the button rows below it. Being able to scroll is right; being
	# cut through the middle of a painting is not.
	list_bay = MarginContainer.new()
	list_bay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_bay.resized.connect(_snap_list_to_rows)
	col.add_child(list_bay)
	list = UI.scroll(list_bay)
	list.sort_children.connect(func(): _snap_list_to_rows.call_deferred())

	# ONE row, not two. The second row existed to hold "How this works" beside the quit
	# button; with that door gone (D164) it held a spacer and one button, so the hub
	# ended in a short row of collections and then a nearly empty line — two baselines
	# where the eye expects one. The three collections sit on the left of the same row
	# and quitting stays pushed to the far right, which is the arrangement the two rows
	# were already describing between them (D165).
	var nav := UI.row(col, 8)
	# A count on a menu entry is the entry's reason to be pressed — the argument that
	# put one on Packs applies to every button here that leads to a collection with a
	# ceiling. It also replaces the summary line that used to restate all four
	# numbers in a row below these buttons.
	# ONE button, because there was never more than one screen. "Loadouts" opened the
	# deck builder with `manage_only = true` and "Collection" opened the fusing list —
	# the same catalogue, listed twice, with the filter bar and the row layout shared
	# and a "Collection (fuse)" button crossing between them mid-task. A player could
	# not tell them apart because there was nothing to tell apart (D133).
	UI.button(nav, "Cards (%d/%d)" % [
		MetaState.collection.size(), MetaState.CATALOG.size()],
		func(): UI.goto(self, "res://scenes/Collection.tscn"), 38.0)
	UI.button(nav, "Relics (%d/%d)" % [
		MetaState.relics.size(), MetaState.RELIC_CATALOG.size()],
		func(): UI.goto(self, "res://scenes/Relics.tscn"), 38.0)
	var sealed: int = MetaState.packs.size()
	UI.button(nav, "Packs (%d)" % sealed if sealed > 0 else "Packs",
		func(): UI.goto(self, "res://scenes/Packs.tscn"), 38.0)

	# No Settings button: `UI.screen()` puts a settings control in every screen's
	# top-right corner now, so a second door on the hub is the same door twice (D133).
	# No "How the Owing works" either, for the same reason one step further out: it is on
	# the title screen, which is the screen a player who does not know how it works is
	# looking at, and the hub is the screen they reach after starting a run (D164).
	#
	# Quitting is pushed to the far end and sized to its own text. It was a full-width bar
	# across the bottom, which made quitting the loudest thing on the hub. It stays a
	# button and stays unbound to Escape on purpose — `tests/playable_test.gd` lists this
	# screen as having no key exit because leaving the world "must be deliberate",
	# and quiet is not the same as easy to hit by accident.
	UI.hspacer(nav)
	UI.button(nav, "Save and quit to title", func():
		MetaState.save_game()
		UI.goto(self, "res://scenes/MainMenu.tscn"), 38.0)
	_refresh()

## Trim the frame around the list so its bottom edge falls in the gap BETWEEN two
## rows instead of through the middle of one.
##
## A `ScrollContainer` is given whatever height the column has left over, and a
## leftover is not a multiple of anything — so the fifth zone showed as a sliced
## thumbnail above the nav bars, which reads as a rendering fault rather than as
## "there is more below this". The slack comes out of the frame instead of a row.
##
## Measured off the BUILT TREE and not off a row-pitch constant, because this list
## has no single pitch: a sealed row is a thumbnail and one line, an unlocked one is
## a thumbnail and three, and the mix changes every time a zone opens. The deck
## builder's list is uniform and gets the same function anyway, because a stated
## pitch is the thing that goes stale the first time a row grows a control.
##
## Two things it does not claim. It fixes the RESTING frame — the one every capture
## and every first glance shows — and scrolling can still stop mid-row, because
## Godot has no row-snapped scroll to ask for. And it is duplicated with
## `deck_builder.gd`: the right home is `UI.scroll()`, so both screens get it from
## one place, and that file belongs to another agent this batch (D125).
func _snap_list_to_rows() -> void:
	var scroll := list.get_parent() as ScrollContainer
	if scroll == null:
		return
	# The FRAME's height, never the scroll's. Measuring the scroll makes the margin a
	# function of itself: trim 30px off, ask again, the last row now ends exactly at
	# the bottom, so the answer is "trim 0" and the fix undoes itself on the next
	# layout pass. It did, silently, and the capture looked like the code had not run.
	var avail := list_bay.size.y
	# in the scroll's own coordinates, so a rebuild while the list is scrolled down
	# does not measure content that is above the top edge
	var top := float(scroll.scroll_vertical)
	var fits := 0.0
	for c in list.get_children():
		var ctl := c as Control
		if ctl == null or not ctl.visible:
			continue
		var bottom := ctl.position.y + ctl.size.y - top
		if bottom > avail:
			break
		fits = bottom
	# nothing fits whole — a window shorter than one row. Leave the frame alone
	# rather than blanking the list, which is the worse of the two failures.
	var slack: int = 0 if fits <= 0.0 else int(avail - fits)
	if list_bay.get_theme_constant("margin_bottom") == slack:
		return
	list_bay.add_theme_constant_override("margin_bottom", slack)

func _builds_done() -> int:
	var done := 0
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if MetaState.collection.has(c):
				have += 1
		if have == b.cards.size():
			done += 1
	return done

func _refresh() -> void:
	var owned := 0
	for id in MetaState.collection:
		owned += int(MetaState.collection[id]["count"])

	var told: Array[String] = []
	if GameState.last_relic != "":
		told.append("NEW RELIC: %s!" % GameState.last_relic)
		GameState.last_relic = ""
	if GameState.last_haul != "":
		told.append(GameState.last_haul)
		GameState.last_haul = ""
	# Explain the world once, the first time it is seen. It used to end by naming "How
	# this works", which was a button in the row below until that door moved to the title
	# screen — and a hint that names a button which is not on the screen is worse than a
	# hint that names none, so the pointer is gone rather than re-aimed (D164). Sending
	# somebody to the title screen mid-run is not a hint, it is an errand. What stays is
	# the rule itself, which is the one thing a player standing here has to know before
	# choosing a door.
	if MetaState.hint_once("overworld"):
		told.append("Pick a region, then a dungeon. Cards found inside are only KEPT if you beat its boss.")
	news.text = "    ".join(told)
	news.visible = not told.is_empty()

	# Only what is always true, and only what is not already on a button below.
	# No "Slot 1". Which save file is open is a thing you chose two screens ago and
	# cannot change from here, so it informs no decision the world map offers — it is
	# bookkeeping about the program rather than about the run (D128). The save slots
	# screen names it, which is where it means something.
	stats.text = "Gold %d    Cleared %d/%d    Cards %d copies    Ropes %d%s" % [
		MetaState.gold,
		MetaState.clear_count(), Balance.DUNGEONS.size(),
		owned, MetaState.item_count("escape_rope"),
		"    Ascension %d" % MetaState.ascension if MetaState.ascension > 0 else ""]

	for c in list.get_children():
		c.queue_free()

	_debt_row()

	for z in Balance.all_zones():
		var unlocked: bool = MetaState.zone_unlocked(z)
		var cleared := 0
		for did in z.dungeons:
			if MetaState.has_cleared(did):
				cleared += 1

		var row := UI.row(list, 12)
		UI.zone_thumb(row, z.id, THUMB, not unlocked)

		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", UITheme.sep(4))
		row.add_child(box)

		var title := "%s   (%d/%d cleared)" % [z.name, cleared, z.dungeons.size()]
		if not unlocked:
			# What is left to do, not what the total was. The absolute number made
			# the player subtract it from a "Cleared 4/12" printed elsewhere on the
			# same screen; this is the subtraction already done.
			var need: int = z.unlock_after_clears - MetaState.gate_credit()
			title = "%s   [sealed — clear %d more dungeon%s]" % [
				z.name, need, "" if need == 1 else "s"]
		UI.button(box, title, (func(): _travel(z.id)) if unlocked else Callable(), 40.0)
		var desc := UI.label(box, z.description)
		if unlocked:
			for line in _pool_line(z):
				UI.label(box, line)
		else:
			# The OTHER route, on the row that is holding it shut (D178). A gate takes depth
			# in dungeons that beat you as well as clears, and an alternative the player
			# cannot see does not exist as far as they are concerned — this is the whole
			# reason the second currency is worth having rather than just being fair.
			UI.label(box, _route_line())
			# A locked row recedes: four of the five are sealed on a fresh save, and
			# at equal weight they buried the one that could be pressed.
			#
			# Recedes by INK, not by opacity. Dimming the row with `modulate` was
			# tried and photographed: it makes the text translucent, so what it
			# actually reads against is whatever the backdrop is doing behind it, and
			# "Sealed for a reason" landed on the one bright band in the picture. A
			# flat darker font colour is the same recession with no dependency on
			# what is underneath (D96).
			desc.add_theme_color_override("font_color", Color(0.70, 0.70, 0.78))

		# The gap belongs to the LIST, not to the text column. Inside the column it
		# only separated rows whose prose was taller than their thumbnail — which is
		# the unlocked ones — and the four sealed rows underneath ran their pictures
		# into a continuous strip.
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(ROW_GAP))
		list.add_child(gap)

## What you owe, or what you could take on (D191).
##
## At the top of the world list, because it is the thing that decides which door is next — and
## one at a time, because a player carrying three debts has a checklist and the decision this
## exists for is *which one*.
func _debt_row() -> void:
	if not MetaState.debt_taken.is_empty():
		var owed := UI.label(list, "Owed: %s" % Balance.debt_text(
			String(MetaState.debt_taken["kind"]), String(MetaState.debt_taken["dungeon"])))
		owed.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
		UI.divider(list)
		return
	var offers: Array = MetaState.offer_debts()
	if offers.is_empty():
		return
	UI.label(list, "Take one on, if you like. Settling it opens a door and pays for the trouble.")
	for i in offers.size():
		var o: Dictionary = offers[i]
		var dd := Balance.dungeon(String(o["dungeon"]))
		var idx := i
		UI.button(list, "%s   (+1 toward the next gate, +%d gold)" % [
			Balance.debt_text(String(o["kind"]), String(o["dungeon"])),
			Balance.debt_gold(dd.difficulty if dd != null else 1)],
			func(): MetaState.take_debt(idx); _refresh(), 36.0)
	UI.divider(list)

## The second way in, written on a sealed row (D178).
##
## Says what is being counted and how much is already in hand, because both halves are
## needed for the sentence to be an invitation rather than a rule: "three floors is a
## clear" tells you what to do, and "you have two" tells you it is nearly worth doing. The
## cap is named too — a route with a ceiling nobody mentioned is a route that stops working
## for reasons the player has to guess at.
func _route_line() -> String:
	var floors: int = Balance.depth_credit_floors(
		MetaState.depth_records, MetaState.cleared_dungeons)
	var got: int = Balance.depth_credit(MetaState.depth_records, MetaState.cleared_dungeons)
	var per: int = Balance.GATE_DEPTH_FLOORS_PER_CREDIT
	var line := "Or go deep and not come back: every %d floors below the first, in places you have not beaten, counts as one clear." % per
	if got >= Balance.GATE_DEPTH_CREDIT_MAX:
		return line + "   You have %d — as far as depth alone will take you." % got
	if floors > 0:
		return line + "   You have %d floor%s, worth %d; %d more for the next." % [
			floors, "" if floors == 1 else "s", got, per - (floors % per)]
	return line + "   At most %d of a gate, so a clear is still the better answer." % \
		Balance.GATE_DEPTH_CREDIT_MAX

## What a zone's pool is worth to you, in the two facts that are actually true of it.
##
## This line used to name the pool's cards, alphabetically, cut off at ten of
## seventeen — which read as "Adrenaline, Anvil Stance, Bash, Berserker Rage, ..."
## and described no deck. Naming the deck instead was tried twice and measured out:
## per-zone build coverage runs 25–40% for the best build with the next two within
## a few points of it, and mechanical concentration rests on two or three cards out
## of twenty. Builds are SCATTERED across zones on purpose (`test_build.gd` enforces
## it), so there is no zone theme to name and any label claiming one would be
## invented (D96).
##
## What is left is true and is what the decision actually turns on: how much of this
## pool you are still missing, and what cannot be got anywhere else.
func _pool_line(z: ZoneData) -> Array[String]:
	var pool: Array[String] = []
	for cid in z.card_pool:
		if cid not in ["hack", "cover"] and cid not in pool:
			pool.append(cid)
	var only: Array[String] = []
	for did in z.dungeons:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		for cid in d.exclusive_cards:
			if cid not in pool:
				pool.append(cid)
			if cid not in only:
				only.append(cid)

	var missing := 0
	for cid in pool:
		if not MetaState.collection.has(cid):
			missing += 1

	var out: Array[String] = []
	out.append("%d cards found here%s" % [pool.size(),
		"" if missing == 0 else " · %d you do not own yet" % missing])
	if not only.is_empty():
		out.append("Only here: %s" % _names(only))
	return out

func _names(ids: Array[String]) -> String:
	var names: Array[String] = []
	for cid in ids:
		if MetaState.CATALOG.has(cid):
			var c := load(MetaState.CATALOG[cid]) as CardData
			if c != null:
				names.append(c.name)
	if names.is_empty():
		return "—"
	if names.size() > 8:
		return "%s, +%d more" % [", ".join(names.slice(0, 8)), names.size() - 8]
	return ", ".join(names)

func _travel(zone_id: String) -> void:
	GameState.current_zone = zone_id
	UI.goto(self, "res://scenes/ZoneView.tscn")
