## Build tracker: what each archetype is MADE OF, how much of it you hold, and which
## bosses still owe you the rest.
##
## This is what makes the scattering of build cards legible. Without it the player
## only sees a pile of cards; with it, a run has a stated purpose.
##
## It used to state that purpose as a spreadsheet. A name, a fraction, the authored
## line, and then one row per PLACE reading "Missing — The Fungal Deep (not yet
## cleared): Venom Fang" — which on a fresh save is fifty-six such rows, because
## every build draws from eight distinct places (measured below). The only thing it
## asked `Icons` for was `rarity_colour(4)`, to tint a finished row gold: no symbol,
## no picture, nothing to look at (D133). Every card in the game has had a painted
## effect symbol since D116, and a build is a SET OF CARDS, so the honest picture of
## a build is the set drawn out — which is also the progress bar.
##
## ---
##
## ### 1. The builds do not cluster, so this screen does not group them
##
## The obvious grouping is "the effect the build is about", and it was derived before
## anything was drawn. Counting `Icons.for_card()` over every card each build names:
##
##     poison     12/12 poison
##     thorns      8/8  thorns
##     fortress    9/10 block           (+1 attack)
##     swarm       8/10 attack          (+1 weak, +1 vulnerable)
##     vampire     6/8  attack          (+1 heal, +1 block)
##     strength    5/10 attack          (+4 strength, +1 heal)
##     tempo       5/11 attack          (+2 card, +2 energy, +1 strength, +1 block)
##
## That is buckets of 1, 1, 1 and 4 — and the four in the lump are the four builds
## LEAST alike: swarm is area damage, vampire is lifesteal, strength is an engine
## that compounds, tempo is cheap cards played often. `for_card` cannot see `aoe`,
## `lifesteal`, `cost` or `draw`, which are precisely the axes that separate those
## four, so an "Attacks" header would print a kinship the data does not have and
## would put more than half the screen under it. `card_family()` is not the rescue
## either: it splits swarm (5 `attack_aoe`, 3 `attack_multi`) and gives tempo a
## `draw` family, and still lands vampire and strength in one undivided `attack`.
##
## So there is no cluster, and the presentation must not imply one. **Each build is
## its own group** — no headers above the headers — and the effect mix is SHOWN,
## one symbol per card, rather than asserted in a category name. A reader who wants
## "poison is the poison one" gets it from twelve identical symbols in a row; a
## reader looking at tempo sees five different symbols, which is the true answer.
##
## For the same reason there is no single icon on a build's header. A build's
## dominant symbol would be `attack` for four of the seven, so four headers would
## carry the same picture — the D91 failure ("seven telegraphs that each read as an
## angry shape") reached from the other direction.
##
## ### 2. The one axis that IS real is when a build can be finished
##
## `Balance.clears_required_for()` is derived, not authored, and `tests/test_build.gd`
## enforces a spread on it deliberately (at least two builds inside 3 clears, four
## inside 5, one beyond 6 — "the whole mid-game had no achievable objective" is a
## bug that shipped). Measured today: tempo 2, fortress 3, thorns 4, swarm 4,
## poison 6, strength 6, vampire 8.
##
## That is the sort order — nearest goal first, which the old screen already did —
## and it is left as an ORDER rather than turned into "Early / Mid / Late" headers,
## because the thresholds that would cut it into three exist nowhere but two inline
## literals inside a test. Restating a number in a second place is the D34 bug, and
## a heading is a worse place to restate one than most: it looks authored.
##
## Ties break on the registry order in `Balance.BUILDS`. `sort_custom` is not a
## stable sort, and two pairs tie today (thorns/swarm at 4, poison/strength at 6) —
## a row that can move between two runs of identical code is a row the player cannot
## learn the position of (the fixed-place argument in `relics_screen.gd`).
##
## ### 3. Where the missing cards are, said once instead of eight times
##
## The old per-place breakdown looked informative and was nearly content-free,
## because the scattering is almost uniform. Every one of the seven builds takes
## exactly THREE dungeon-exclusive cards (one from each of its three gate dungeons,
## which is what `test_build.gd` requires) and spreads the rest across ALL FIVE zone
## pools. So "where is the rest of this build" has the same answer — everywhere —
## for all seven, and the only discriminating part is the three named dungeons.
##
## The errand line therefore names the dungeons that still owe a card and counts the
## rest, and the per-card place labels are gone. What went with them: "(not yet
## cleared)" beside a dungeon name. That was a fact about the player's history
## printed next to an errand it does not change — earnings are escrowed (D20), so a
## card found in a dungeon is kept by beating that boss or spending a rope IN THAT
## RUN, whether or not the place has ever been cleared before.
##
## ### 4. Scene or section
##
## `_ready()` is four lines; everything else is `section()`, which is static, takes
## a parent, and builds no title, no scroll and no exit. That is the embed point —
## the report asks for Builds under How This Works, and `glossary.gd` is being
## restructured in the same batch, so this screen must work either way. Embedding
## costs one line:
##
##     preload("res://scripts/builds_screen.gd").section(list)
##
## with `list` the glossary's scroll column, and one `_section(list, "Builds")`
## heading above it if the host wants one. Built and photographed both ways at
## 1280x720, against a stand-in host with the glossary's own backdrop and scroll: the
## section renders identically inside it and costs the host 1359px of scroll against
## the standalone screen's 1322 — the difference being its own heading and the
## screen title it no longer carries. No `class_name`: no other screen in `scripts/`
## has one, the preload above is the whole cost of not having it, and a global class
## registered while five agents share the tree is a shared cache write to buy nothing.
##
## Whether Builds BELONGS there is a separate question from whether it fits, and the
## honest answer is that the report is right for a reason it did not give. It is not
## "info" the way the glossary is — the glossary states rules that are true for every
## save, and every line here is a fact about this one. What makes it belong is that
## it is the only meta screen with nothing to press: no fuse, no buy, no equip, no
## choice. A hub button leads to a place you do something; this is something you
## read. It reads as a section of a reference screen and it does not read as a peer
## of the Collection.
extends Control

## Slots per row. Four, not the three `relics_screen.gd` uses, because a slot here is
## a symbol and a card name and nothing else, where a relic slot carries a whole
## effect sentence. Three columns wastes half the width and turns sixty-nine slots
## into twenty-six rows; four turns them into nineteen.
const COLUMNS := 4

## Column floor, unscaled px. Measured against the longest string the card table can
## actually produce rather than picked (D95): the widest of the sixty-nine names is
## "Something Worse" at 137px in the 16px body font — NOT "Survival Instinct", which
## has more letters and narrower ones, which is the whole reason this is measured by
## rendering the screen and asking the font rather than by counting characters. With
## the icon and its gap that is 171px, so the floor carries a name half again as long
## before anything clips. Four columns plus three 12px gaps is 1196 against the 1240
## the margins leave.
const SLOT_WIDTH := 290.0

## A build header's line height, unscaled px, against the 22px display font. The
## slack is the gap ABOVE it, which is where a build gets its air: a scroll's
## separation is uniform, so a gap on one side only has to be bought by the header
## itself. Lifted wholesale from `relics_screen.HEAD_LEADING`, including the reason —
## that screen's first capture had its five group headers jammed against the row
## above and read as one list of thirty.
const HEAD_LEADING := 34.0

## How far an unowned slot recedes. The same IDEA as the relic screen's
## `UNFOUND_DIM`, deliberately not the same constant: importing it would couple a
## build row's contrast to a relic row's, and the two sit on different paintings.
## `darkened` and not `modulate`, because a translucent label reads against the
## backdrop rather than against the colour chosen for it (D96).
##
## Measured at 1280x720 under Xvfb, and the instrument matters enough to write down:
## the screen is rendered twice, once normally and once with its content hidden, and
## a pixel counts only where the two frames differ — i.e. where a glyph actually
## landed. Sampling the whole label rect instead reports the brightest pixel in the
## empty tail of a 290px cell, which scored this screen at 1.05:1 and the shipped
## relic screen at 1.00:1, and neither is what an eye sees.
##
## Worst backdrop pixel under a glyph, by rarity:
##
##     owned    Common 6.4  Uncommon 6.6  Rare 4.5  Epic 3.8  Legendary 7.3
##     unowned  Common 3.8  Uncommon 2.5  Rare 2.2  Epic 2.5  Legendary 3.0
##
## For scale, the shipped relic screen's unfound rows measure 2.0–5.3 on the same
## instrument, so an unowned build card is no dimmer than a relic slot the game
## already ships. **4.5:1 is not reachable for an unowned Rare or Epic**, and this is
## a stronger statement than the relic screen's version of it: a fully OWNED Rare is
## 4.5 and a fully owned Epic is 3.8, so no dim of those two hues can clear 4.5 while
## remaining distinguishable from owning the card. The palette and the painting set
## the ceiling; what this constant guarantees is the RATIO between the two states.
const MISSING_DIM := 0.34

## How big an effect symbol draws in a slot, unscaled px. The files are painted at 64
## and `collection.gd` draws them at 32; this is smaller because sixty-nine of them
## are on one screen rather than one per row of a filtered list, and the icon sets
## the grid pitch — an HBox is as tall as its tallest child, so the symbol, not the
## text, decides how far this screen scrolls. Measured by resizing the built tree and
## re-reading the scroll content, empty state: 22 gives 1265px, 26 gives 1322px, 32
## gives 1436px. 26 buys a symbol that still reads as a shape at 1x for 57px, where
## `collection.gd`'s 32 would cost 114px on a screen that already scrolls twice.
const ICON := 26.0


func _ready() -> void:
	# UI.screen rather than a hand-rolled margin+VBox: it is the thing that installs
	# the backdrop, so a screen that scaffolds itself is a screen on flat black (D95).
	#
	# `ledger` and not `table`, which is what this screen used and what the other
	# card-collection screens use. Two reasons, one measured and one structural. The
	# measurement: `bg_table`'s lower half is a lit stone slab, and the list runs
	# straight across it — every rarity on this screen reads better on `bg_ledger`,
	# in identical states, worst pixel under a glyph:
	#
	#     owned      Common 4.0>6.4  Uncommon 3.1>6.6  Rare 2.1>4.5  Epic 2.0>3.8
	#     unowned    Common 1.6>3.8  Uncommon 1.9>2.5  Legendary 1.9>3.0
	#
	# A fully owned Epic at 1.99:1 is a name you hunt for. (That is a fact about
	# `bg_table`, not about this screen — `collection.gd`, `packs_screen.gd` and
	# `starter_kit.gd` all put a list over the same slab. Worth a REDO row.)
	# The structural reason: `ledger` is what `glossary.gd` uses, so the standalone
	# screen and the embedded section are the same picture either way.
	var col := UI.screen(self, "Builds", "", "ledger")
	section(UI.scroll(col))
	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))


## The whole tracker, built into `parent`. Static and free of `self` so it can be
## dropped into another screen's scroll column — see "Scene or section" above.
##
## It is a long section and that is priced, not accidental: sixty-nine slots, seven
## headers and fourteen prose lines measure 1322px of scroll in a 587px window on a
## fresh save and 1090px on a finished one, so 2.3 screens and 1.9. Both states were
## rendered. The alternative that would fit one screen is anonymous pips instead of
## names, and the relic screen already argued that one out: a want-list you cannot
## read is not a want-list.
static func section(parent: Node) -> void:
	# One pass counts the finished builds AND lays them out, so the number in the
	# header is not a second sum of the same thing (the mistake `collection.gd`
	# documents and `relics_screen.gd` avoids the same way).
	var blocks: Array = []
	var done := 0
	for b in _ordered():
		var owned: Array[String] = []
		var missing: Array[String] = []
		for cid in b.cards:
			if MetaState.collection.has(cid):
				owned.append(cid)
			else:
				missing.append(cid)
		if missing.is_empty():
			done += 1
		blocks.append({"build": b, "owned": owned, "missing": missing})

	# Two lines, each sized to fit on ONE at 1280 — measured on the capture, where the
	# first draft ran to 118 characters and wrapped, pushing the first build's grid a
	# whole row down the frame on the screen that already scrolls twice.
	var total: int = blocks.size()
	UI.label(parent, "%d of %d finished. A build is a set of cards, scattered on purpose — no one dungeon or zone holds a whole one." % [done, total])
	# Said once, at the top, instead of beside every unowned card. Dropped when there
	# is nothing left to collect, on the same rule as the relic screen's withholding
	# line: a standing instruction the player has finished obeying is noise.
	if done < total:
		UI.label(parent, "Three cards of each are found in one named dungeon only. Nothing is kept unless you beat a boss or spend a rope.")

	for e in blocks:
		_block(parent, e["build"], e["owned"], e["missing"])


## Nearest goal first, ties broken by the registry so a row never moves.
static func _ordered() -> Array:
	var out: Array = Balance.all_builds()
	out.sort_custom(func(a, b):
		var ga: int = Balance.clears_required_for(a)
		var gb: int = Balance.clears_required_for(b)
		if ga != gb:
			return ga < gb
		return Balance.BUILDS.find(a.id) < Balance.BUILDS.find(b.id))
	return out


## One build: what it is called and how far along, what it is for, what is left to
## do, and then the set itself.
static func _block(parent: Node, b: BuildData, owned: Array[String],
		missing: Array[String]) -> void:
	var complete := missing.is_empty()
	var gate: int = Balance.clears_required_for(b)
	var locked: bool = MetaState.clear_count() < gate

	# The header is a ROW and not one formatted string, because its three parts want
	# three different treatments: the name is the display face, the fraction is the
	# number, and the status is an aside. The old version concatenated all three and
	# so had to spend the name's font on the parenthetical.
	var head := UI.row(parent, 12)
	head.custom_minimum_size.y = UITheme.px(HEAD_LEADING)
	var title := Label.new()
	UITheme.style_title(title)
	title.text = b.name
	title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(title)

	var tally := Label.new()
	tally.text = "%d / %d" % [owned.size(), b.cards.size()]
	tally.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(tally)

	var status := ""
	if complete:
		status = "complete"
	elif locked:
		status = "needs %s, you have %d" % [Wording.count(gate, "clear"), MetaState.clear_count()]
	if status != "":
		var st := Label.new()
		st.text = status
		st.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		head.add_child(st)
		_tint_head(st, complete, locked)
	# Three states, read by ink, and applied AFTER the label is in the tree — see
	# `_tint_head`. Gold is the finished one, the same `rarity_colour(4)` the old
	# screen used, kept because it is the game's one "this is as good as it gets"
	# colour. A build whose gate dungeons are not open yet recedes instead, the way a
	# sealed zone row does (D96): it is a real goal, just not this one, and greying it
	# out would read as a broken widget.
	_tint_head(title, complete, locked)

	# The authored line. It is the only sentence on this screen written by a person
	# rather than derived, and the voice belongs on the things the player handles
	# (D98), so it stays even though it costs a line per build.
	UI.label(parent, "    %s" % b.description)

	var errand := _errand(b, missing)
	if errand != "":
		# The description above is atmosphere and this is the instruction, so the two
		# indented lines under a header need to be told apart at a glance. By hue, not
		# by ink: dimming the flavour to promote the errand would put the authored
		# voice in the same visual register as a card the player does not own.
		#
		# `rarity_colour(1)` rather than a green chosen here. There is already a green
		# in the palette and `collection.gd` has a fourth one of its own hardcoded; a
		# fifth is how a palette stops being one. There is no confusion with an
		# Uncommon card because this is a sentence and the rarities only ever tint a
		# slot — the same licence `glossary.gd` takes with `rarity_colour(2)`.
		UI.label(parent, "    %s" % errand).add_theme_color_override(
			"font_color", Icons.rarity_colour(1))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", UITheme.sep(12))
	grid.add_theme_constant_override("v_separation", UITheme.sep(4))
	parent.add_child(grid)
	for cid in b.cards:
		_slot(grid, cid, MetaState.collection.has(cid))


## Gold when finished, receded when its gate dungeons are not open yet, otherwise
## left alone.
##
## The recede is derived from the theme's own colour instead of restating one. The
## old screen wrote `Color(0.9, 0.9, 0.9)` for "the normal label colour", which is a
## copy of a value `ui_theme.gd` owns and the D34 bug at its smallest — it is wrong
## the day the theme changes and nothing says so. `get_theme_color` returns the real
## one, which is why the call sites above add the label to the tree FIRST: outside a
## tree there is no parent chain to resolve a theme through.
static func _tint_head(l: Label, complete: bool, locked: bool) -> void:
	if complete:
		l.add_theme_color_override("font_color", Icons.rarity_colour(4))
	elif locked:
		l.add_theme_color_override("font_color",
			l.get_theme_color("font_color").darkened(MISSING_DIM))


## What is left and where, in one line — see "Where the missing cards are" above for
## why this is a line and not a paragraph.
##
## The two clauses answer different questions. A dungeon-exclusive card is a PLACE
## you must go, so the places are named; a zone-pool card is a drop you accumulate,
## and since every build draws on all five zones, naming them would print "all of
## them" seven times. It is counted instead.
static func _errand(b: BuildData, missing: Array[String]) -> String:
	if missing.is_empty():
		return ""
	var places: Array[String] = []
	var exclusive := 0
	for did in Balance.dungeons_required_for(b):
		var d := Balance.dungeon(did)
		if d == null:
			continue
		var owes := 0
		for cid in d.exclusive_cards:
			if cid in missing:
				owes += 1
		if owes > 0:
			exclusive += owes
			places.append(d.name)
	var parts: Array[String] = []
	if not places.is_empty():
		parts.append("%s only in %s" % [
			Wording.count(exclusive, "card"), ", ".join(places)])
	var anywhere: int = missing.size() - exclusive
	if anywhere > 0:
		# Not "from the zone pools": `card_pool` is the name of a field, and a screen
		# that hands the player an identifier is a screen written for its own author.
		parts.append("%s that turn up anywhere in their zone" % Wording.count(anywhere, "card"))
	return "Still to find: %s." % "; ".join(parts)


## One card of a build: the symbol for what it does, the name, and whether it is
## yours. Nothing else — the grid is the SET, and the errand line above it is the
## errand; a place label on each of sixty-nine slots was the wall of text.
static func _slot(grid: GridContainer, cid: String, owned: bool) -> void:
	var card: CardData = null
	if MetaState.CATALOG.has(cid):
		card = load(MetaState.CATALOG[cid]) as CardData
	# A card you own is quoted at the level you own it at. The catalogue resource is
	# the level-1 authored one, and handing it straight to `card_tooltip` would print
	# "Deals 6 damage. Level 1 of 5." over a card the player has fused to 4 — the
	# exact drift D50 exists to stop, and `collection.gd` duplicates for this reason.
	# An unowned card keeps level 1, which is not a lie: that is what it arrives at.
	if card != null and owned:
		card = card.duplicate()
		card.level = int(MetaState.collection[cid]["level"])

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.x = UITheme.px(SLOT_WIDTH)
	row.add_theme_constant_override("separation", UITheme.sep(8))
	grid.add_child(row)

	# `Icons.for_card`, not `Icons.card_family`. They answer different questions and
	# the header comment above measures why the answer matters here, but the asset is
	# the shorter argument: `card_family` names the 320x240 illustration a whole family
	# of cards shares, and a slot in a grid of sixty-nine is 26px square — a landscape
	# painting letterboxed into that is a smudge, where `sym_*.png` is a 64px
	# white-on-transparent glyph drawn to be tinted and read small at the size the
	# player is given it. `for_card` is also what `collection.gd` and
	# `deck_builder.gd` already put beside a card name, so a card carries one symbol
	# everywhere in the game instead of one per screen.
	var pic := TextureRect.new()
	pic.texture = Icons.tex(Icons.for_card(card))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2.ONE * UITheme.px(ICON)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# An unowned card's symbol recedes the same way its name does, so a slot is one
	# decision rather than two. `modulate` is the right tool HERE and wrong on the
	# label: this is a picture, so there is nothing behind it for translucency to
	# read against (the D96 corollary, stated in `relics_screen.gd`).
	if not owned:
		pic.modulate = Color(1, 1, 1, 1.0 - MISSING_DIM)
	row.add_child(pic)

	var name_label := Label.new()
	name_label.text = card.name if card != null else cid
	# `clip_text` is what makes SLOT_WIDTH real: a Label reports its own text as its
	# minimum width and grows straight past a `custom_minimum_size`, which is how
	# three identical buttons ended up at three x positions on the Packs screen
	# (D95). Nothing in the catalogue is long enough to clip today; the guard is for
	# the card added tomorrow.
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tint := Icons.rarity_colour(card.rarity if card != null else 0)
	name_label.add_theme_color_override("font_color",
		tint if owned else tint.darkened(MISSING_DIM))
	row.add_child(name_label)

	# The full reading of the card, on the row, so a symbol nobody recognises has an
	# answer. Generated from the data by the one function that does it, so it cannot
	# drift from the numbers the card face shows (D50).
	#
	# Shown for a card the player does NOT own, which is where this screen parts
	# company with `relics_screen.gd` — and for that screen's own reason, landing the
	# other way. It withholds what a relic does because a relic is a rarity-weighted
	# roll off a boss, so knowing changes no decision you are able to make. A build
	# card is the opposite: it is the thing you can go and get, and "is this build
	# worth chasing" is exactly the decision this screen is for. Withholding here
	# would be withholding the answer to the question the screen asks.
	if card != null:
		UI.hoverable(row, Icons.card_tooltip(card))
