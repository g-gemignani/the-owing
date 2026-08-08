## Keyword reference, generated from the data rather than written out, so it cannot
## drift from the rules. Nothing in the game explained Vulnerable, escrow or ropes
## before this existed.
##
## **What it explains, and in what order, changed in D133.** The screen opened on
## Combat — Energy, Block, Vulnerable, Poison — which is the half of this game that is
## every other deckbuilder. Told all four, a new player still had not been told the
## thing that makes this one different: that nothing found in a dungeon is theirs until
## its boss is dead, that the collection is what survives a run, and that the floor
## takes a step whenever they do. Two of those three were one line each at the bottom
## of the scroll and one was not here at all.
##
## So the sections run **unusual first, generic last** — At Risk, What You Keep, The
## Floor, In a Fight. Someone who knows the genre can stop reading before the fight
## section and has still read the part they could not have guessed; someone who does
## not know it reaches the fight section having been given a reason to care about the
## cards it is about to describe. The alternative order — teach the fight first,
## because that is what the player does first — is the order that shipped, and it puts
## the game's own subject where a reader who is skimming will never reach it.
##
## **It shows as well as tells.** Every status carries the painted 64x64 symbol
## (D116) the fight itself draws for it, at the same size, in the same tint, so the
## word and the picture are learned once instead of twice.
##
## ## Adding a section
##
## The Builds screen is folding in here as one, and this is the whole of what a caller
## needs:
##
##     var body := _section(list, "Builds", "one line saying what a build is")
##     _entry(body, "Poison", "Stack it and wait.", "poison")
##     body.add_child(anything_that_is_not_a_term)
##
## `_section()` hands back its OWN VBox, so a section can hold controls that are not
## term/definition pairs, and it registers itself with the index at the top of the
## screen — which is built after every section exists, so there is no second list to
## keep in step. Put a new section where its subject sits on the unusual-to-generic
## run above rather than at the end by default.
extends Control

## The eight in-fight statuses are NOT restated here. `combat.gd`'s own comment on
## `STATUS_CHIPS` says why: there were two hand-kept lists of the same seven statuses
## and they did not say the same things, which is D34 in prose rather than in numbers.
## This screen was the third list, and it was the one that had drifted furthest — it
## taught a Block that "absorbs damage from the next attack" while the fight taught one
## that is "soaked off incoming hits", and it had no entry at all for two of the eight.
## Reading the table is also what gets the icons and the tints right by construction: a
## status added to the fight appears here the same day, with its painting.
const CombatScreen := preload("res://scripts/combat.gd")

## Where `Back` goes. It stays a static, and its default is now the title screen,
## because the title screen is the only door left: the overworld's copy of the button
## was removed once this one existed, and a `Back` defaulting to the overworld would
## have dropped a player who has not started a run into the middle of the game (D164).
##
## A caller that is not the title screen sets this before it navigates:
##
##     load("res://scripts/glossary.gd").return_to = "res://scenes/Overworld.tscn"
##     UI.goto(self, "res://scenes/Glossary.tscn")
static var return_to := "res://scenes/MainMenu.tscn"

## Heading labels in build order, for the index. Filled by `_section()`.
var _headings: Array[Label] = []

func _ready() -> void:
	# Named for its subject, like every section inside it. "How This Works" was the one
	# heading in this screen written as interface rather than as the game — "this" naming
	# nothing, next to At Risk, What You Keep and The Floor, and above a lede that opens
	# "You go down owing" (D165). The title screen's button says the same words.
	var col := UI.screen(self, "How the Owing Works", "", "ledger")

	# Built empty here so it sits between the title and the list, and filled at the
	# bottom of this function once every section exists. A section therefore cannot be
	# added without appearing in it.
	var index := HFlowContainer.new()
	index.add_theme_constant_override("h_separation", UITheme.sep(8))
	index.add_theme_constant_override("v_separation", UITheme.sep(6))
	col.add_child(index)

	var list := UI.scroll(col)
	# Prose, not a table. A Label only wraps if something upstream refuses to give it
	# more width, and a ScrollContainer that can scroll sideways hands out as much as
	# the text asks for — so the longest definition sets the width of the screen and
	# every line runs off the right edge (D95, one screen over).
	var scroll := list.get_parent() as ScrollContainer
	if scroll != null:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_lede(list)
	_at_risk(list)
	_what_you_keep(list)
	# The Builds tracker used to be embedded here, between the two sections above and
	# below (D133). It is gone, and the rule it broke is now the rule this screen is
	# held to: EVERY LINE ON THIS SCREEN IS TRUE OF EVERY SAVE. Builds counted what this
	# player holds and named what they must still go and get, so a reader could not tell
	# which half of the screen was the game and which half was their own progress
	# (D166). It is reached from the Collection, which is where the cards it counts are.
	# `tests/test_content.gd` fails if this screen reads MetaState again.
	_the_floor(list)
	_in_a_fight(list)
	_build_index(index, scroll)

	UI.exit_button(col, "Back", func(): UI.goto(self, return_to))

## The game in three sentences, before any term is defined. It is the escrow, the
## collection and the death penalty in that order, because that is the loop the title
## names (D127) and a reader who gets no further than this paragraph has still been
## told what the game is about.
func _lede(list: Node) -> void:
	var l := UI.label(list, ("You go down owing. Everything you find in a dungeon belongs to the dungeon "
		+ "until its boss is dead — you may spend it and play it the whole way down, and none of it "
		+ "is yours. Carry it out and it joins a collection that never resets. Die and it stays on "
		+ "the floor."))
	l.add_theme_color_override("font_color", Icons.rarity_colour(0))

# --- the sections -------------------------------------------------------------

## The escrow first, because REVIEW.md's verdict is that it is the best thing in the
## game and invisible for the first hour, and because everything below it is a
## consequence of it.
func _at_risk(list: Node) -> void:
	var body := _section(list, "At Risk", "Nothing you find down there is yours yet.")
	_entry(body, "At risk", ("Cards, coin, relics and sealed packs found inside a dungeon are yours to "
		+ "use the moment you find them and belong to the dungeon until its boss falls. The run "
		+ "header counts what is riding on the boss, every step of the way down."), "gold")
	_entry(body, "Escape Rope", ("The other way out. You keep the haul; the dungeon stays uncleared, "
		+ "so no relic and no unlock. %d%% of chests hold one and %d%% of bosses drop one on top of "
		+ "their relic. No merchant has ever stocked them — a way out you could buy is not a "
		+ "risk.") % [Balance.TREASURE_ROPE_CHANCE, Balance.BOSS_ROPE_CHANCE], "rope")
	# Both ends of the penalty, not one: it is a fraction and a count that both climb
	# with the dungeon's difficulty, and quoting only the shallow end would read as a
	# promise the deep end breaks.
	var deep := _deepest_difficulty()
	_entry(body, "Dying", ("The haul stays on the floor, and the collection pays on top of it. In the "
		+ "shallows that is %d%% of your banked gold and %d card; at the bottom it is %d%% and %d "
		+ "cards. It can never take you below a legal deck.") % [
			roundi(Balance.gold_loss_fraction(1) * 100.0), Balance.cards_lost_on_death(1),
			roundi(Balance.gold_loss_fraction(deep) * 100.0), Balance.cards_lost_on_death(deep)],
		"skull")
	_entry(body, "Quitting", ("Costs nothing. The run is written down mid-fight and picks up exactly "
		+ "where you put it down. Dying is the only thing that takes."))

## What the escrow is FOR. The collection is the pitch and the thing a player coming
## from a run-based deckbuilder will assume this game does not have.
func _what_you_keep(list: Node) -> void:
	var body := _section(list, "What You Keep", "The part of a run that outlives it.")
	_entry(body, "The collection", ("Cards do not go back in the box at the end of a run. What you "
		+ "carried out stays carried out, and every dungeon is entered with a deck cut fresh from "
		+ "the pile you have built."), "card")
	_entry(body, "Deck size", "Between %d and %d cards, chosen again before every dungeon." % [
		Balance.MIN_DECK_SIZE, Balance.MAX_DECK_SIZE], "card")
	_entry(body, "Fusing", ("Spend copies AND gold to raise a card's level. Both prices rise with the "
		+ "level you are buying, so the cheap gains come early. Copies are deck width, gold is your "
		+ "next shop, levels are power — you cannot have all three."), "gold")
	_entry(body, "Level caps", ("Commons level to %d, legendaries only to %d — but the rarer a card "
		+ "is, the more each level gives it.") % [Balance.max_level(0), Balance.max_level(4)])
	_entry(body, "Sealed packs", ("Cards found already boxed, in chests and off elites and bosses. A "
		+ "pack cannot be opened underground and cannot touch the deck that found it; it is carried "
		+ "out at risk with everything else and opened on the world screen."), "chest")
	_entry(body, "Exclusive cards", ("Some cards are in one dungeon and nowhere else. Builds are "
		+ "deliberately scattered, so finishing one means clearing several places."), "card")
	# A pointer, not a progress bar. Where a thing is tracked is true of every save,
	# which is the line this screen is drawn on (D166): the counting itself belongs on
	# the screens that hold the cards, and this one says which those are.
	_entry(body, "Builds", ("A named set of cards that work as one deck. The Cards screen tracks how "
		+ "much of each you hold; a region's screen marks which of its cards are still missing."), "card")
	# "relic" and not "gold", though both resolve to the same painted coin today: the
	# semantic name is what picks up a relic of its own the day one is painted, and a
	# call site that asked for the coin would still be asking for the coin (D116).
	_entry(body, "Relics", "Permanent upgrades, dropped by bosses. Never lost, not even on death.", "relic")

## The crawl. It is the newest of the three subjects and the one with no line anywhere
## else in the interface: the run header shows a wanderer count and nothing says what a
## wanderer is or what walking past one costs.
func _the_floor(list: Node) -> void:
	var body := _section(list, "The Floor", "It takes a step whenever you do.")
	_entry(body, "A step is a turn", ("A dungeon is a painted floor walked one tile at a time, and "
		+ "everything else standing on it moves when you move. Standing still buys nothing."))
	_entry(body, "Nothing waits", ("Every fight in a dungeon walks it, and all of them are walking "
		+ "toward you from the moment you arrive. They come out of the encounter count rather "
		+ "than on top of it: a floor that hunts is not a harder floor, it is the same floor "
		+ "coming to meet you."), "skull")
	_entry(body, "Caught in the open", ("Anything that reaches you swings first: %d%% of your "
		+ "health before a card is played. The price is for being caught, never for walking.") % [
			roundi(Balance.ISO_AMBUSH_PCT)], "hp")
	_entry(body, "Breaking away", ("A hunter beside you can be shaken off instead of fought, for "
		+ "health. It costs a turn, and every other thing on the floor spends that turn getting "
		+ "closer. Each one after the first costs more."), "hp")
	_entry(body, "Lingering", ("Past %d steps on one floor, everything on it takes two steps to "
		+ "your one. Greed is timed.") % Balance.ISO_LINGER)
	# The one rule on this screen that is a PLACE rather than a number. It belongs here
	# because the alternative is finding it out at a chest that has already stayed shut,
	# and because "keys are somewhere" is the whole of D167.
	_entry(body, "Chests and keys", ("A chest wants nothing, a key, or something proved about your "
		+ "run. The keys are on the floors: one lies in some room of a floor that holds a chest, "
		+ "placed away from everything you had a reason to walk to. You start every dungeon with "
		+ "none, and nothing else in the game hands you one."), "chest")

## Last, and deliberately so. Everything in here is genre grammar — the words Block and
## Energy and Vulnerable mean here what they mean everywhere — so what this section is
## worth is the project's own NUMBERS against them, and the painted symbol beside each
## one that the player will meet again in the fight.
func _in_a_fight(list: Node) -> void:
	var body := _section(list, "In a Fight", "The ordinary business of a deckbuilder, at this game's numbers.")
	_entry(body, "Energy", ("%d a turn. Cards cost it, and whatever you do not spend is gone when the "
		+ "turn ends.") % Balance.MAX_ENERGY, "energy")
	for spec in CombatScreen.STATUS_CHIPS:
		var term_text := _chip_term(spec)
		_entry(body, term_text[0], term_text[1], String(spec[1]),
			CombatScreen.CHIP_GOOD if bool(spec[2]) else CombatScreen.CHIP_BAD)
	_entry(body, "Pierce", ("A share of an incoming hit that Block never sees. It grows with depth, "
		+ "and it is the reason a wall of Block cannot be the whole answer down there."), "pierce")
	# The last three rows carry no symbol on purpose. There is a painting for every
	# status above them and none for a telegraph, a turn count or a cycle — and the
	# nearest thing on the sheet, the sword, means "attack", which is not what any of
	# these three is. A decorated row that names the wrong thing teaches the wrong
	# thing; the empty gutter keeps their text on the same edge as the rest and says
	# nothing it cannot back up.
	_entry(body, "Intent", ("Every enemy shows what it means to do next turn, and what would actually "
		+ "land once your Block has taken its cut."))
	# Both numbers, because the cap is the half that stops "hits harder every turn"
	# reading as a fight that eventually cannot be won.
	_entry(body, "Escalation", ("Enemies hit %d%% harder for every turn a fight runs, up to %.1f times "
		+ "their opening damage. Stalling is not a plan.") % [
			roundi(Balance.ESCALATION_PER_TURN * 100.0), Balance.ESCALATION_MAX])
	_entry(body, "Patterns", _patterns_text())

# --- the pieces a section is made of -------------------------------------------

## A heading, an optional line saying what the section is for, and the VBox its rows
## go in. Registers the heading with the index.
##
## The rows live in a child VBox rather than being poured into `list` flat, so that a
## section OWNS its contents: a caller adding one can hold whatever it likes in there,
## and moving a section is moving one call rather than a run of them.
func _section(parent: Node, title: String, blurb: String = "") -> VBoxContainer:
	# Not under the first heading: a rule directly below the screen title is
	# decoration, and what the asset is for is the join between two sections (D125).
	if not _headings.is_empty():
		UI.divider(parent)
	var l := Label.new()
	l.text = title
	UITheme.style_title(l)
	parent.add_child(l)
	_headings.append(l)
	if blurb != "":
		var b := UI.label(parent, "   %s" % blurb)
		b.add_theme_color_override("font_color", Icons.rarity_colour(0))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", UITheme.sep(6))
	parent.add_child(body)
	return body

## One term. The icon is a semantic name for `Icons.tex()`, and an empty one — or a
## name with no painting behind it — still reserves the gutter, so a row without a
## picture keeps its text on the same left edge as the rows around it. That is the
## whole reason the TextureRect is built unconditionally instead of skipped.
##
## `tint` colours the word and its picture together. It defaults to the same blue the
## terms have always been; the fight's statuses pass the fight's own two colours
## instead, so a player who has learned that red means "the room did this to you"
## reads the same code here.
func _entry(parent: Node, term: String, text: String, icon: String = "",
		tint: Color = Icons.rarity_colour(2)) -> void:
	var rowbox := HBoxContainer.new()
	rowbox.add_theme_constant_override("separation", UITheme.sep(8))
	rowbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(rowbox)

	var art := TextureRect.new()
	art.texture = Icons.tex(icon) if icon != "" else null
	# The size the fight draws these at, taken from the fight rather than chosen: two
	# sizes of one icon set read as one of them being wrong (D113), and the point of
	# putting a symbol on this screen is that it is the same symbol.
	var side := UITheme.px(CombatScreen.CHIP_SIDE)
	art.custom_minimum_size = Vector2(side, side)
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The project forces NEAREST globally, which is right for the 16x16 bitmaps and
	# turns a 64px painting shown at 20 into gravel.
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.modulate = tint
	rowbox.add_child(art)

	var textcol := VBoxContainer.new()
	textcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	textcol.add_theme_constant_override("separation", UITheme.sep(2))
	rowbox.add_child(textcol)
	var t := Label.new()
	t.text = term
	t.add_theme_color_override("font_color", tint)
	textcol.add_child(t)
	var d := UI.label(textcol, text)
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## The jump bar. Four sections is already more than fits on a 720-high screen at once,
## and the ones a returning player wants are the ones furthest down.
##
## An HFlowContainer and not a row: the next section added here is somebody else's and
## its heading could be any length, and a row that overflows puts the last button off
## the right edge with nothing to say it is there.
##
## The jump sets `scroll_vertical` from the heading's own position rather than calling
## `ensure_control_visible`, which scrolls the MINIMUM distance — a heading already
## half on screen would not move, which reads as a button that does nothing.
func _build_index(bar: HFlowContainer, scroll: ScrollContainer) -> void:
	if scroll == null:
		return
	for l in _headings:
		var target := l
		UI.button(bar, target.text, func(): scroll.scroll_vertical = int(target.position.y), 32.0)

# --- derivations ---------------------------------------------------------------

## A status chip's `teach` string, split into the term and its definition.
##
## The chip form is "Name %d — what it does.", written for a hover that has a stack
## count to put in it. A glossary has no count, so the number comes out and the
## sentence after the dash becomes the definition. The literal percent signs in it are
## doubled for the `%` operation the fight puts them through and have to be undoubled
## here, where there is none: the last time this screen printed "+50%%" to a player it
## was for the mirror-image reason.
##
## Falls back to the whole string if the shape ever changes, because a definition that
## reads oddly is better than a blank row.
func _chip_term(spec: Array) -> Array:
	var whole := String(spec[3])
	var parts := whole.split(" — ", true, 1)
	if parts.size() < 2:
		return [String(spec[4]), whole.replace("%%", "%")]
	var term := parts[0].replace("+%d", "").replace("%d", "").strip_edges()
	var text := parts[1].replace("%%", "%")
	return [term, text.substr(0, 1).to_upper() + text.substr(1)]

## The deepest difficulty rating any dungeon carries, for the death penalty's far end.
## Read off the dungeons rather than off the size of the list: the penalty scales on
## the rating, and the two are not the same number.
func _deepest_difficulty() -> int:
	var deep := 1
	for did in Balance.DUNGEONS:
		var d := Balance.dungeon(did)
		if d != null:
			deep = maxi(deep, d.difficulty)
	return deep

## Enemies act on a repeating cycle, and the honest way to say how long one is is to
## count one. The old version of this entry was its own section — "Statuses on enemies"
## — holding a single line about patterns under a heading that did not describe it.
func _patterns_text() -> String:
	var line := ("Most things act on a fixed cycle, and the intent line shows the next step of it. "
		+ "Some also react to what you do, which is where a boss stops being a routine.")
	var e := Balance.enemy("cultist")
	if e != null and e.pattern.size() > 1:
		line = ("Most things act on a fixed cycle — the %s repeats the same %d moves, in order, in "
			+ "every fight it is in. Watch it once and the third turn is yours to plan. Some also "
			+ "react to what you do, which is where a boss stops being a routine.") % [
				e.name, e.pattern.size()]
	return line
