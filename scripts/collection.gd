## Cards — the one screen for everything you do to a card you own (D133).
##
## It used to be two, and a player reported that they could not tell them apart.
## They were right, and it was worse than they knew: `Collection` listed what you
## own so you could LEVEL it, and `Loadouts` was not a screen at all. It was
## `deck_builder.gd` re-entered with `GameState.manage_only = true`, which hid the
## dungeon framing and relabelled one button — the same file, the same filter bar,
## the same row, under a second name on the hub. The deck builder even carried a
## "Collection (fuse)" button, so the game already admitted that somebody in the
## middle of choosing a deck wants to level a card.
##
## What one screen buys beyond one fewer name is that the two verbs are about the
## same object and they SPEND each other. Levelling a card is the best reason there
## is to put more copies of it in a deck, and it is paid for in copies the deck you
## are looking at is counting. Across two navigations neither half of that trade
## could see the other; here, fusing a card re-prices its row and the deck total in
## the same frame.
##
## The three states below are DERIVED from GameState, never set by the caller. That
## is what killed `manage_only`: a screen that behaves differently depending on
## which button you pressed is a screen whose behaviour the player cannot predict,
## which is the reported bug stated as a mechanism. Every existing entry point —
## the hub's two buttons, the zone view, `run_flow.leave_run()`, the powers screen,
## the pause menu and the run view — lands here and gets the right state without
## being told anything.
extends Control

## MANAGE  no dungeon: the hub sent you here to tend the collection.
## OUTFIT  a dungeon is chosen and not yet entered: the same screen with the boss
##         named and a Start button, which is what the deck builder always was.
## LEDGER  a run is live: the deck is dealt and the purse is half at risk, so this
##         is a reading of the collection and not a place to change it.
enum Mode { MANAGE, OUTFIT, LEDGER }

## Column widths, unscaled, stated as ONE budget because that is the only way to see
## that they add up. The 1280 frame leaves 1248 inside `UI.screen`'s margins and
## about 1234 inside the scrollbar, and the fused row is the first in the game that
## had to be arithmetic rather than taste: the old collection row alone asked for
## roughly 1410 (a 500px name, a 220px preview and up to three price buttons at ~190
## each) and was already clipping at the shipped height before anything was merged
## into it. Anything added here comes out of another column, on purpose.
const W_THUMB := 28.0
const W_ICON := 24.0
const W_NAME := 204.0
## Current numbers and what the next level does to them, in ONE cell. They were two
## columns and the second contained the first — `level_up_text` prints "dmg 28→238",
## which already states today's damage — so the pair cost 250px to say one thing
## twice. Merged, the cell reads as the current numbers on a card at its cap and as
## the trade on a card that can still grow, which is the only distinction the two
## columns were drawing.
const W_NUM := 162.0
const W_LEVEL := 100.0
const W_STEP := 36.0
const W_COUNT := 36.0
## Per bulk-fuse button. Three is the most `_bulk_steps` can offer, and the price is
## the one thing on this row that must not be clipped — so the width is measured
## against the widest label the fuse curve can actually produce rather than picked.
## That is a max-out on an UNCOMMON, not on a common as you would guess: a common
## has the deeper cap (100 levels against 40) but the cheaper curve, and it is the
## gold figure that runs long. `+39  288x 76013g`, photographed, at 178px lost its
## trailing "g" — the number was there and the unit was not, which is the one way a
## price can be wrong and still look right.
const W_FUSE := 186.0

var mode: int = Mode.MANAGE
var selection: Dictionary = {}   # id -> copies chosen for the deck

var info_label: Label
var note_label: Label
var decks_box: HBoxContainer
var list_bay: MarginContainer
var list_box: VBoxContainer
var filter_box: VBoxContainer
var power_box: HBoxContainer
var name_edit: LineEdit
var start_btn: Button
var msg_label: Label

func _ready() -> void:
	mode = _mode_now()
	# Start from a saved deck (prefer "Starter"), clamped to what is still owned.
	# Not in LEDGER: the deck for this run was dealt at the door and showing a saved
	# loadout beside it would be a second, wrong answer to "what am I playing".
	if mode != Mode.LEDGER:
		var src := ""
		if MetaState.decks.has("Starter"):
			src = "Starter"
		elif not MetaState.decks.is_empty():
			src = MetaState.decks.keys()[0]
		if src != "":
			_load_deck(src)
	_build_ui()
	_refresh()

## Which of the three the player is in, from state alone.
##
## `in_run()` is asked FIRST and separately from `dungeon_id`, because both are set
## during a run — a live run also has a dungeon selected, and testing the dungeon
## first would offer a Start button in the middle of the dungeon it would start.
func _mode_now() -> int:
	if GameState.in_run():
		return Mode.LEDGER
	if GameState.dungeon_id != "":
		return Mode.OUTFIT
	return Mode.MANAGE

## Whether the fuse controls appear at all — the one real question this merge had
## to answer, because the two screens disagreed about it and neither said so.
##
## The collection is reachable from the pause menu and from the run view, so fusing
## mid-run has always been on offer. It should not have been, for two reasons that
## are independent and both are lies rather than mere weakness:
##
## 1. **It buys nothing for the run you are in.** `GameState.run_deck` is a snapshot
##    — `MetaState.build_deck()` duplicates each card and stamps its level at the
##    door. Levelling afterwards changes the collection, not the array being dealt
##    from. The player who fuses before the boss to hit harder has spent copies and
##    gold on a card that is unchanged in their hand until the NEXT run.
##
## 2. **It prices against a purse the player is not being shown.** `MetaState.fuse()`
##    spends `MetaState.gold` directly; it never goes through `GameState.spend_gold`,
##    which is the escrow-first spender every shop uses. So mid-run the row says
##    "need 52g (have 0)" while the map says you are carrying 300. And it cannot
##    simply be re-plumbed onto `available_gold()`: that would let a player convert
##    at-risk earnings into a permanent card level at the last rest before the boss,
##    which is laundering escrow past D20 and is the exact hole escrow was dug to
##    close. Spending banked gold only is CORRECT; offering the transaction while a
##    second, larger purse is on screen is not.
##
## So fusing is an out-of-run act, and the fused screen is the out-of-run one. The
## test is "nothing is at risk", not "no dungeon is selected", because the two come
## apart: the OUTFIT state at a dungeon's door has an empty escrow (a boss clear
## commits it, a death and a rope forfeit it) and is the single best moment in the
## game to spend a haul on the deck you are about to take back down.
func _fusing_allowed() -> bool:
	return not GameState.in_run() and GameState.escrow_gold == 0

func _build_ui() -> void:
	var dd := GameState.dungeon_data()
	var title := "Cards — pick the deck, level what you own"
	match mode:
		Mode.OUTFIT:
			title = "Cards — %s (difficulty %d)" % [
				dd.name if dd != null else "Dungeon", GameState.dungeon]
		Mode.LEDGER:
			title = "Cards — %s, run in progress" % [dd.name if dd != null else "Dungeon"]
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black.
	var root := UI.screen(self, title, "", "table")

	info_label = Label.new()
	info_label.clip_text = true
	root.add_child(info_label)

	# One line under the numbers for whatever the screen currently has to SAY —
	# the first-fuse hint, the result of a fuse, why fusing is off in a run. It is
	# its own label because the line above it is a readout that must not be
	# overwritten by a message and then stay wrong until the next refresh, which is
	# what the single shared label used to do. Hidden while it has nothing to say,
	# because an empty label still takes a row's worth of the height the card list
	# is fighting for — see `_say`.
	note_label = Label.new()
	note_label.clip_text = true
	note_label.visible = false
	note_label.add_theme_color_override("font_color", Color(0.72, 0.86, 0.68))
	root.add_child(note_label)

	var relic_label := Label.new()
	relic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var names: Array[String] = []
	for r in MetaState.relic_data():
		names.append("%s (%s)" % [r.name, r.description])
	var prefix := ""
	if GameState.last_relic != "":
		prefix = "NEW RELIC: %s!    " % GameState.last_relic
		GameState.last_relic = ""
	relic_label.text = "%sRelics: %s" % [prefix, ", ".join(names) if not names.is_empty() else "none"]
	root.add_child(relic_label)

	# Who you are building against. A boss you cannot know is a boss you cannot
	# prepare for, and the preparation is the decision this screen exists to ask.
	if mode == Mode.OUTFIT:
		var boss := Balance.boss_of(GameState.dungeon_id)
		if boss != null:
			var warn := Label.new()
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.add_theme_color_override("font_color", Color(0.95, 0.65, 0.45))
			warn.text = "BOSS: %s — %s" % [boss.name, Balance.boss_warning(GameState.dungeon_id)]
			root.add_child(warn)
			UI.hoverable(warn, "%s waits at the end of %s.\n%s" % [
				boss.name, dd.name if dd != null else "this dungeon",
				Balance.boss_warning(GameState.dungeon_id)])

	# Power picker and saved loadouts, on ONE bar. Both belong to the deck rather
	# than to the collection, so both are hidden in LEDGER, where the deck is already
	# dealt and the power already equipped — a picker that cannot change this run is
	# a control that lies about what it does.
	#
	# One bar rather than two because the height is the scarce thing here. Every
	# framed button in this game is 50px tall (`UITheme.min_button_height`), so a
	# row of controls costs 60px with its separation, and the merged screen's header
	# stack had grown to the point where the CARD LIST — the thing both old screens
	# existed to show — was three rows deep at 1280x720. Two bars became one, the
	# save controls moved onto the bottom bar, and the list went from three rows to
	# six. Measured on the capture, not guessed (D133).
	if mode != Mode.LEDGER:
		var kit_row := HBoxContainer.new()
		kit_row.add_theme_constant_override("separation", UITheme.sep(6))
		root.add_child(kit_row)
		var plbl := Label.new()
		plbl.text = "Power:"
		kit_row.add_child(plbl)
		power_box = HBoxContainer.new()
		power_box.add_theme_constant_override("separation", UITheme.sep(6))
		kit_row.add_child(power_box)
		var manage := Button.new()
		UITheme.style_button(manage)
		manage.text = "Powers..."
		manage.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Powers.tscn"))
		kit_row.add_child(manage)

		var lbl := Label.new()
		lbl.text = "    Load:"
		kit_row.add_child(lbl)
		decks_box = HBoxContainer.new()
		decks_box.add_theme_constant_override("separation", UITheme.sep(6))
		kit_row.add_child(decks_box)

	# the bar lives in its own box so a filter change can rebuild just the controls
	filter_box = VBoxContainer.new()
	root.add_child(filter_box)

	# The card list is clipped to WHOLE rows — see `_snap_list_to_rows`. The frame
	# around it is what the slack is taken out of, so the scroll itself can be handed
	# a height that ends where a row does. `UI.scroll` builds the pair inside it
	# rather than this screen hand-rolling a second copy of the shared scaffold.
	list_bay = MarginContainer.new()
	list_bay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_bay.resized.connect(_snap_list_to_rows)
	root.add_child(list_bay)
	list_box = UI.scroll(list_bay)
	list_box.sort_children.connect(func(): _snap_list_to_rows.call_deferred())

	# The bottom bar carries everything that COMMITS: leave, start, and name-and-save
	# the loadout. They were two bars and are one for the height (see above), but
	# they also belong together — all three are "I am done arranging, do the thing".
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(bottom)
	UI.exit_button(bottom, _exit_text(), func(): UI.goto(self, _exit_to()))
	# Builds is the other question about a collection — not "what do I hold" but "what
	# is the pile FOR" — and it lives here because this is the screen that holds the
	# cards it counts. It was embedded in How the Owing Works, which put one player's
	# progress inside a screen of rules that are true for every save (D166).
	#
	# MANAGE only. In OUTFIT and LEDGER a deck is being arranged or dealt, and leaving
	# by a door that is not the exit button would throw the arrangement away — the
	# fuse controls are withheld in those modes for a version of the same reason.
	# The fraction is on the button for `overworld.gd`'s rule: a count on a menu entry
	# is the entry's reason to be pressed.
	if mode == Mode.MANAGE:
		var builds_btn := Button.new()
		UITheme.style_button(builds_btn)
		builds_btn.text = "Builds (%d/%d)" % [_builds_done(), Balance.BUILDS.size()]
		builds_btn.pressed.connect(func():
			load("res://scripts/builds_screen.gd").return_to = "res://scenes/Collection.tscn"
			UI.goto(self, "res://scenes/Builds.tscn"))
		UI.hoverable(builds_btn, "What each build is made of, how much of it you hold, and which dungeons still owe you the rest.")
		bottom.add_child(builds_btn)
	# One primary, and only where there is something for it to do. In MANAGE there is
	# no dungeon to start, so the way out IS the primary action and a second button
	# beside it would be two words for one press — which is the shape of the whole
	# bug this screen was merged to fix. (The button it replaces there said "Save
	# loadout and leave" and saved nothing at all; saving is the named button below.)
	if mode == Mode.OUTFIT:
		start_btn = Button.new()
		UITheme.style_button(start_btn)
		start_btn.text = "Start Dungeon"
		start_btn.pressed.connect(_on_start)
		bottom.add_child(start_btn)
	if mode != Mode.LEDGER:
		UI.hspacer(bottom)
		msg_label = Label.new()
		# Before the field rather than after it. A message at the far right edge of
		# the bar has nothing beyond it to take the slack, so "saved 'The Long Way
		# Down'" would push its own controls off the frame (D95's shape, sideways).
		msg_label.custom_minimum_size.x = UITheme.px(180)
		msg_label.clip_text = true
		msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bottom.add_child(msg_label)
		name_edit = LineEdit.new()
		name_edit.placeholder_text = "deck name"
		name_edit.custom_minimum_size.x = UITheme.px(190)
		bottom.add_child(name_edit)
		var save_btn := Button.new()
		UITheme.style_button(save_btn)
		save_btn.text = "Save deck"
		save_btn.pressed.connect(_on_save)
		UI.hoverable(save_btn, "Store the current selection under that name, to load again from the bar above.")
		bottom.add_child(save_btn)

## Builds whose every card is in the collection. Counted here rather than asked of
## `builds_screen.gd`, which counts as it LAYS OUT — one pass that both sums and
## draws, so the screen's own header cannot disagree with its rows. Exposing that
## count would mean building the whole tracker to put a number on a button.
func _builds_done() -> int:
	var done := 0
	for b in Balance.all_builds():
		var have := true
		for cid in b.cards:
			if not MetaState.collection.has(cid):
				have = false
				break
		if have:
			done += 1
	return done

func _exit_text() -> String:
	match mode:
		Mode.LEDGER:
			return "Back to the run"
		Mode.OUTFIT:
			return "Back"
		_:
			return "Done"

func _exit_to() -> String:
	match mode:
		Mode.LEDGER:
			# resume_scene, not run_scene: this screen is reachable from the pause
			# menu DURING a fight, and returning to the map with a fight still saved
			# would leave the player able to walk into a different node and be handed
			# the old fight back.
			return GameState.resume_scene()
		Mode.OUTFIT:
			# back out to the zone to pick a different dungeon, if we came through one
			return "res://scenes/ZoneView.tscn" if GameState.current_zone != "" \
				else "res://scenes/Overworld.tscn"
		_:
			return "res://scenes/Overworld.tscn"

## Trim the frame around the list so its bottom edge falls in the gap BETWEEN two
## rows instead of through the middle of one.
##
## A `ScrollContainer` is given whatever height the column has left over, and a
## leftover is not a multiple of anything: the card list ended under the save bar
## with a row sliced in half, which reads as a rendering fault rather than as "there
## is more below this". The slack comes out of the frame instead of out of a row.
##
## Measured off the BUILT TREE rather than off a row-pitch constant. Partly because
## a restated pitch is the thing that goes stale the first time a row grows a
## control, and partly because the same defect on the world screen is a list whose
## rows are deliberately different heights (sealed zones are shorter than unlocked
## ones), so there is no single pitch there to state. One algorithm covers both.
##
## Two things it does not claim. It fixes the RESTING frame — the one every capture
## and every first glance shows — and scrolling can still stop mid-row, because
## Godot has no row-snapped scroll to ask for and re-snapping on every wheel click
## would change the viewport height under the wheel. And it is duplicated: the right
## home is `UI.scroll()`, so both screens get it from one place, and that file
## belongs to another agent this batch (D125).
func _snap_list_to_rows() -> void:
	var scroll := list_box.get_parent() as ScrollContainer
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
	for c in list_box.get_children():
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

func _load_deck(deck_name: String) -> void:
	selection = {}
	var lo: Dictionary = MetaState.decks.get(deck_name, {})
	for id in lo:
		selection[id] = min(int(lo[id]), MetaState.owned(id))

func _adjust(id: String, delta: int) -> void:
	var cur: int = selection.get(id, 0)
	var next: int = clampi(cur + delta, 0, MetaState.owned(id))
	if next == 0:
		selection.erase(id)
	else:
		selection[id] = next
	_refresh()

## Fusing eats copies, so a deck chosen before the fuse can be asking for more of a
## card than the collection still holds. `loadout_size` and `build_deck` both clamp,
## so nothing breaks — but the row would go on printing "x5" of a card you own three
## of, which is the screen lying about the one number the player is managing. The
## whole point of merging the two screens is that these two acts now happen in one
## frame, so this is the interaction the merge created and has to pay for.
func _clamp_selection() -> void:
	for id in selection.keys():
		var n: int = min(int(selection[id]), MetaState.owned(id))
		if n <= 0:
			selection.erase(id)
		else:
			selection[id] = n

## How many copies of this card the live run is actually holding. Only asked in
## LEDGER, where the "in deck" column has no stepper and would otherwise be blank —
## and where the true answer is a fact about `GameState.run_deck`, not about a saved
## loadout. It is also the reason the pause menu links here at all: "what did I bring
## and what have I picked up" is the question you open this screen mid-run to ask.
func _in_run_deck(id: String) -> int:
	var n := 0
	for c in GameState.run_deck:
		if c != null and c.id == id:
			n += 1
	return n

func _refresh() -> void:
	_clamp_selection()
	var shown: Array = CardFilter.apply(MetaState.collection, MetaState.CATALOG)
	_write_info(shown)

	if power_box != null:
		_refresh_powers()
	if decks_box != null:
		_refresh_decks()

	for c in filter_box.get_children():
		c.queue_free()
	UI.card_filter_bar(filter_box, _refresh)

	for c in list_box.get_children():
		c.queue_free()
	for id in shown:
		_build_row(id)

## Say something on the note line — and give it a line's worth of height only when
## there is something to say. An always-present label that is usually empty costs a
## card row for nothing, on the one screen in the game with a genuine height budget.
func _say(text: String) -> void:
	note_label.text = text
	note_label.visible = text != ""

## The one readout line: the collection, the deck, and the purse. Three numbers that
## used to live on two screens and could not be compared, which is how a player ends
## up fusing away the copies a legal deck needed.
func _write_info(shown: Array) -> void:
	# MetaState already knows the total; recounting it here was a second copy of the
	# same sum, and the kind of loop that gets mistaken for a listing loop later.
	var total: int = MetaState.total_copies()
	var filtered: String = CardFilter.summary(shown.size(), MetaState.collection.size())
	if mode == Mode.LEDGER:
		# The purse is quoted the way the run quotes it, banked and at-risk apart,
		# because that split is the whole reason fusing is off here.
		info_label.text = "%d cards owned    Deck in play %d    HP %d/%d    Gold %d banked, %d at risk    %s" % [
			total, GameState.run_deck.size(), GameState.hp, GameState.max_hp,
			MetaState.gold, GameState.escrow_gold, filtered]
		_say("Levelling waits until the run is settled: a level bought now would not reach the deck already dealt, and the gold at risk cannot pay for it.")
		return

	var size := MetaState.loadout_size(selection)
	# Empty when the deck is legal, not "OK". A hint exists to say what is WRONG, and
	# a screen that congratulates you on every valid state has to be read every time
	# to find out it had nothing to say. The Start Dungeon button below is already
	# enabled or not, which is the same fact where the player is looking (D128).
	var hint := ""
	if size < MetaState.MIN_DECK_SIZE:
		hint = "    need %d more" % (MetaState.MIN_DECK_SIZE - size)
	elif size > MetaState.MAX_DECK_SIZE:
		hint = "    over cap by %d" % (size - MetaState.MAX_DECK_SIZE)
	info_label.text = "%d cards owned (min %d to run)    Deck %d (min %d, max %d)    HP %d/%d    Gold %d    %s%s" % [
		total, Balance.MIN_KEEP, size, MetaState.MIN_DECK_SIZE, MetaState.MAX_DECK_SIZE,
		GameState.hp, GameState.max_hp, MetaState.gold, filtered, hint]
	if start_btn != null:
		start_btn.disabled = not MetaState.deck_valid(selection)

## Every owned power, the equipped one marked. Sits with the deck because it IS part
## of the loadout: one ability, chosen per run, firable once every turn.
func _refresh_powers() -> void:
	for c in power_box.get_children():
		c.queue_free()
	if MetaState.powers.is_empty():
		var none := Label.new()
		none.text = "none owned"
		power_box.add_child(none)
	for pid in MetaState.powers:
		var pd := Balance.power(pid)
		if pd == null:
			continue
		pd = pd.duplicate()
		pd.level = int(MetaState.powers[pid])
		var pb := Button.new()
		UITheme.style_button(pb)
		var on: bool = pid == MetaState.equipped_power
		pb.text = "%s%s Lv%d" % ["> " if on else "", pd.name, pd.level]
		pb.disabled = on
		UI.hoverable(pb, "%s\n%s\nCost %s, once per turn." % [
			pd.name, pd.effect_text(), "free" if pd.eff_cost() == 0 else "%dE" % pd.eff_cost()])
		pb.pressed.connect(func():
			MetaState.equip_power(pid)
			_refresh())
		power_box.add_child(pb)

func _refresh_decks() -> void:
	for c in decks_box.get_children():
		c.queue_free()
	if MetaState.decks.is_empty():
		var none := Label.new()
		none.text = "no saved decks yet"
		decks_box.add_child(none)
	for dn in MetaState.decks:
		var lb := Button.new()
		UITheme.style_button(lb)
		lb.text = dn
		UI.hoverable(lb, "Load the '%s' loadout, clamped to what you still own." % dn)
		lb.pressed.connect(func():
			_load_deck(dn)
			_refresh())
		decks_box.add_child(lb)

## One card, one row: identify it, then the two things you can do to it.
##
## The order across the row is the order of the decisions — what is this, what does
## it do (and what would a level do to that), how much of it do I own, how many am I
## taking, what does a level cost. The two verbs are BOTH inline on every row, and
## neither is behind a mode or behind a selection, for reasons worth stating once:
##
## - A mode toggle is `manage_only` again wearing a new hat. A control that changes
##   what a row MEANS is exactly the thing the player could not see when the two
##   modes were two screens; putting it inside one file does not make it visible.
## - Behind a selection, the fuse prices would be a click away. The prices are what
##   you shop on — that is the whole reason this row already grew a "what the next
##   level buys" column beside the buttons that quote the price. A shop that states
##   its prices and its goods does not hide either behind a click.
##
## They cannot both be primary, though, and the tell is width: laid end to end the
## two old rows ask for more than the 1280 frame has. So they are ranked by POSITION
## rather than by a mode. The stepper sits at a fixed x on every row, adjacent to the
## card, silent and free; the fuse buttons sit outboard of it and each quotes a
## price. The reversible act gets the cheap, always-there position because you will
## use it fifty times in a visit; the act that permanently spends copies and gold
## gets the deliberate one further out and has to say what it costs before you reach
## it. Fixed widths everywhere, because a column whose x tracks a string length is a
## column the eye cannot find down a list (D95).
func _build_row(id: String) -> void:
	var entry: Dictionary = MetaState.collection[id]
	var card := (load(MetaState.CATALOG[id]) as CardData).duplicate()
	card.level = entry["level"]
	var cap: int = MetaState.max_level(id)
	var level := int(entry["level"])
	var gain: String = card.level_up_text(level + 1)
	# `_fusing_allowed` is part of the test, not just `level < cap`: the preview is
	# priced in green as "you can buy this", and in a run you cannot. Mid-run the cell
	# shows what the card does in the fight you are standing in, which is the question
	# you opened this screen to ask.
	var can_level: bool = gain != "" and level < cap and _fusing_allowed()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep(5))
	list_box.add_child(row)

	# The illustration is the way into the full card — see UI.inspect_thumb. Its note
	# is where the two old screens' notes merge: how many copies this deck is asking
	# for, and what one more level would buy. Neither screen could say both.
	var note := "%s: %d copies." % [
		"In the run deck" if mode == Mode.LEDGER else "In this deck", _shown_count(id)]
	if can_level:
		note += "\nLevel %d of %d.\nOne more level: %s" % [level, cap, gain]
	UI.inspect_thumb(row, card, UITheme.px(W_THUMB), note)

	var pic := TextureRect.new()
	pic.texture = Icons.tex(Icons.for_card(card))
	pic.custom_minimum_size = Vector2(UITheme.px(W_ICON), UITheme.px(W_ICON))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)

	var name_lbl := Label.new()
	name_lbl.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
	name_lbl.custom_minimum_size.x = UITheme.px(W_NAME)
	# `clip_text` is what makes the width above a real floor: a Label reports its own
	# TEXT width as its minimum and grows straight past a `custom_minimum_size`, and
	# then every column after it tracks the longest card name in the filter (D95).
	name_lbl.clip_text = true
	name_lbl.text = "%s %s" % [card.name, CardData.rarity_badge(card.rarity)]
	row.add_child(name_lbl)

	# What the card does, and what the next level BUYS, in one cell. The buttons out
	# to the right have always quoted the price; the benefit was left for the player
	# to infer, which is not a decision anyone can make well against a shop that
	# states its prices AND its goods. Green when it is a preview, plain when it is
	# just the card's numbers — so the colour means "this is purchasable", which is
	# the only thing the two separate columns were saying.
	var stats := ""
	if card.eff_damage() > 0:
		stats += "dmg %d " % card.eff_damage()
	if card.eff_block() > 0:
		stats += "blk %d " % card.eff_block()
	var num_lbl := Label.new()
	num_lbl.custom_minimum_size.x = UITheme.px(W_NUM)
	num_lbl.clip_text = true
	if can_level:
		num_lbl.add_theme_color_override("font_color", Color(0.72, 0.86, 0.68))
		num_lbl.text = gain
		UI.hoverable(num_lbl, "What one more level gives this card: %s.\nLevel %d of %d." % [
			gain, level + 1, cap])
	else:
		# no empty cell text on a card whose numbers are not damage or block
		num_lbl.text = stats.strip_edges()
	row.add_child(num_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.custom_minimum_size.x = UITheme.px(W_LEVEL)
	lvl_lbl.clip_text = true
	lvl_lbl.text = "Lv%d/%d  x%d" % [level, cap, int(entry["count"])]
	UI.hoverable(lvl_lbl, "Level %d of a possible %d, and %d copies owned." % [
		level, cap, int(entry["count"])])
	row.add_child(lvl_lbl)

	_build_deck_cell(row, id)
	_build_fuse_cell(row, id, card, entry)

	# on the row, so hovering the art, the stepper or the fuse buttons explains the
	# card too
	UI.hoverable(row, Icons.card_tooltip(card))

## Copies of this card the player is currently committed to: the loadout being
## edited, or — in a run, where there is no loadout to edit — the deck in play.
func _shown_count(id: String) -> int:
	return _in_run_deck(id) if mode == Mode.LEDGER else int(selection.get(id, 0))

func _build_deck_cell(row: HBoxContainer, id: String) -> void:
	if mode == Mode.LEDGER:
		# No stepper: the run deck is dealt and cannot be edited from here. The count
		# keeps the column's width so the fuse cell stays where it is on every row.
		var held := Label.new()
		held.custom_minimum_size.x = UITheme.px(W_STEP * 2 + W_COUNT)
		held.clip_text = true
		held.text = "in run x%d" % _in_run_deck(id)
		row.add_child(held)
		return

	var minus := Button.new()
	UITheme.style_button(minus, true)
	minus.text = "-"
	minus.custom_minimum_size.x = UITheme.px(W_STEP)
	minus.pressed.connect(_adjust.bind(id, -1))
	row.add_child(minus)

	var cnt := Label.new()
	cnt.custom_minimum_size.x = UITheme.px(W_COUNT)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.text = "x%d" % int(selection.get(id, 0))
	row.add_child(cnt)

	var plus := Button.new()
	UITheme.style_button(plus, true)
	plus.text = "+"
	plus.custom_minimum_size.x = UITheme.px(W_STEP)
	plus.pressed.connect(_adjust.bind(id, 1))
	row.add_child(plus)

func _build_fuse_cell(row: HBoxContainer, id: String, card: CardData,
		entry: Dictionary) -> void:
	if not _fusing_allowed():
		return
	if not MetaState.can_fuse(id):
		var blocked := Button.new()
		UITheme.style_button(blocked)
		blocked.text = MetaState.fuse_blocked_reason(id)
		blocked.clip_text = true
		# Two buttons wide, because it is the only thing in the cell and the longest
		# reason ("collection would drop below N cards") is longer than any price.
		blocked.custom_minimum_size.x = UITheme.px(W_FUSE * 2.0)
		blocked.disabled = true
		UI.hoverable(blocked, "Cannot level %s yet: %s." % [
			card.name, MetaState.fuse_blocked_reason(id)])
		row.add_child(blocked)
		return

	if MetaState.hint_once("first_fuse"):
		_say("Fusing spends copies AND gold: deck width and purse traded for power.")
	# bulk options: maxing a common is 99 levels, which is not 99 clicks
	var possible: int = MetaState.fusable_levels(id)
	for step in _bulk_steps(possible):
		var price := _price_of(id, step)
		var f := Button.new()
		UITheme.style_button(f)
		f.text = "+%d  %dx %dg" % [step, price["copies"], price["gold"]]
		f.clip_text = true
		f.custom_minimum_size.x = UITheme.px(W_FUSE)
		var target: int = int(entry["level"]) + step
		var buys: String = card.level_up_text(target)
		UI.hoverable(f, "To level %d: %s\nCosts %d copies and %d gold." % [
			target, buys if buys != "" else "no change to its numbers",
			price["copies"], price["gold"]])
		f.pressed.connect(_on_fuse.bind(id, step))
		row.add_child(f)

## Which bulk buttons to offer. Prices rise per level, so a "+10" is no longer ten
## times the "+1" price and each button has to quote its own total.
##
## Deduplicated, which it was not: at exactly ten affordable levels the old version
## appended 10 for the ten-step and then 10 again for the everything-step, so the row
## drew two identical buttons at the same price. Harmless and silly, and invisible
## unless a card happens to sit on that one number.
func _bulk_steps(possible: int) -> Array[int]:
	var steps: Array[int] = [1]
	if possible >= 10 and not steps.has(10):
		steps.append(10)
	if possible > 1 and not steps.has(possible):
		steps.append(possible)
	return steps

## Total copies and gold for the next `count` levels of a card.
func _price_of(id: String, count: int) -> Dictionary:
	var entry: Dictionary = MetaState.collection[id]
	var card := load(MetaState.CATALOG[id]) as CardData
	var rarity: int = card.rarity if card else 0
	var level := int(entry["level"])
	var copies := 0
	var gold := 0
	for i in count:
		copies += Balance.fuse_copy_cost(level + i)
		gold += Balance.fuse_gold_cost(rarity, level + i)
	return {"copies": copies, "gold": gold}

func _on_fuse(id: String, times: int = 1) -> void:
	var gained := MetaState.fuse_many(id, times)
	if gained > 0:
		Audio.play("fuse")
		# The card's NAME, not its id. The line used to read "Fused stave_in", which is
		# the only place in the game that showed the player a resource filename.
		var c := load(MetaState.CATALOG[id]) as CardData
		_say("Fused %s: +%s.   Gold left %d" % [
			c.name if c != null else id, Wording.count(gained, "level"), MetaState.gold])
		_refresh()

func _on_save() -> void:
	var nm := name_edit.text.strip_edges()
	if nm == "":
		msg_label.text = "name required"
		return
	MetaState.save_deck(nm, selection)
	msg_label.text = "saved '%s'" % nm
	_refresh()

func _on_start() -> void:
	if not MetaState.deck_valid(selection):
		msg_label.text = "deck too small"
		return
	Audio.play("enter")
	GameState.enter_dungeon(MetaState.build_deck(selection))
	GameState.autosave()   # the run exists from here on and can be resumed
	get_tree().change_scene_to_file(GameState.run_scene())
