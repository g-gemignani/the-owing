## The collection as CARDS rather than as rows — the second way to read the same
## screen (D213).
##
## `collection.gd` is a table: one text row per card, fixed-width columns, every
## number in a cell. That shape is the right one for the question "what do I own and
## what does a level cost", because it puts a hundred cards' prices in one column the
## eye can run down. It is the wrong one for "what am I building", because a card
## game's cards are pictures and a player who has learned a deck by its art cannot
## find it in a list of names.
##
## So this is an ALTERNATIVE, not a replacement. The toggle is on the filter bar, the
## choice is remembered in settings (`SettingsState.card_view`), and both views share
## the same filter, the same selection, the same fuse prices and the same screen. What
## changes is only how a card is drawn and how a copy is added:
##
##     table    a row, a stepper, three priced fuse buttons
##     cards    a face you can drag, a footer count, one badge that opens the prices
##
## Nothing here owns state. The screen keeps `selection`; this draws it and reports
## back through the Callables on `Ctx`. That is what lets the two views sit on one
## `_refresh()` and makes switching between them free — the same dictionary is being
## drawn twice, so they cannot disagree about what is in the deck.
class_name CardGrid
extends RefCounted

## The card face in the grid, unscaled. Measured against the frame rather than
## chosen: `UI.screen`'s margins leave 1248 of the 1280, the deck bay takes `PANEL_W`
## and the two scrollbars take about 28, so the grid gets ~950. Eight columns of
## `TILE_W + GAP` is 896 and nine is 1008, so eight it is, and the width follows from
## that rather than the other way round.
##
## The HEIGHT is what makes this view work at all. `UITheme.BASE_CARD` is 150x214 and
## three of those rows do not fit under this screen's header stack — the table view
## already fought for that space and won it by deleting a whole control bar (D133).
## At 104x148 two rows are always visible and a third is half-shown, which is the
## honest signal that the grid continues; at full size one row filled the bay and the
## screen read as though the collection were eight cards long.
const TILE_W := 104.0
const TILE_H := 148.0
## The count strip under each face. It is NOT on the face: the face's bottom band is
## the card's own authored rules text, and a plate over the corner of it would cover
## the one thing the player opened this view to look at.
const FOOT_H := 20.0
const GAP := 8.0

## The deck bay down the right. Wide enough for `x12  Something Worse` — the longest
## card name in the catalogue behind a two-digit count — at the row font, and no
## wider, because every pixel here comes out of the grid beside it.
const PANEL_W := 250.0
## The same panel beside the TABLE view, where it is a readout rather than a drop
## target and the row beside it is the tightest in the game (D215).
##
## Measured, not picked, and the margin that decides it is one this file's own header
## already names: the widest table row asks 1038px, and the frame's 1248 is 1234 once
## the list's scrollbar is out. 1234 - 180 - 10 of separation leaves 1044, which the row
## fits with six to spare. At 200 it does not — the arithmetic says 1024 and the row
## overflows its own scroll by fourteen pixels, silently, which is how the table row got
## measured to the pixel in the first place.
##
## Names clip harder in it than at `PANEL_W`. That is the trade the width forces, and it
## is the right way round: the panel answers "what is in the deck", the count and the
## first word of a name answer it, and the whole card is one right-click away.
const PANEL_W_TABLE := 180.0
## The deck scroll's bar, widened from the theme's own. It is the only way to move a
## twenty-row deck other than the wheel, and at the kit's natural width it is a hard
## thing to put a cursor on beside a panel this narrow.
const BAR_W := 14.0
## Tall enough that the strip of illustration behind a row is a picture rather than a
## smear. `KEEP_ASPECT_COVERED` fills the 234px of row inside the bay's margins from a
## 320x240 painting, so the painting renders 175px tall and the row is a horizontal
## band cut from its middle: 15% of the picture at 26px, 19% at 34. The extra 4% is
## what moves the band from a colour swatch to a recognisable subject — the bandage
## wrap, the stonework, the armour plate. Ten kinds of card, more than any real deck
## carries, still fit the bay at this height without scrolling.
const ROW_H := 34.0

## How the row's picture is held down so the name on top of it stays readable.
##
## Two knobs and not one, because they do different things. `ART_ALPHA` fades the
## picture toward the bay's own dark panel and keeps its colours; the scrim lays flat
## black over the result and kills the contrast that a bright patch of illustration
## would otherwise put behind a letter.
##
## Set by capture, not by arithmetic. The first pair (0.55 / 0.42) left an effective
## 32% of the painting and read as a tint rather than as art — the thing this was
## asked for was the picture, and at that strength there was no picture. These leave
## 56%, and the row that decides it is whichever one is a pale tan: Bandage, Bulwark
## and Give Ground are the brightest in the catalogue's palette and are where a name
## would go grey first. It does not, at these numbers, and it is worth re-photographing
## the bay rather than re-deriving them if either is ever moved.
const ART_ALPHA := 0.90
const SCRIM_ALPHA := 0.38

## Where the level badge sits on the face, as a fraction of the card. The top strip is
## the only band on a card that is guaranteed free: `UI.card_button` puts the cost
## badge in the top-LEFT corner and the effect symbol in the top-RIGHT, and leaves the
## middle 48% of that strip empty on every card in the game. Anywhere else and the
## badge covers either the illustration, the name, or the rules text.
const BADGE_SIDE := 0.26     ## width of the cost badge and effect symbol either side
const BADGE_BAND := 0.095    ## their height, as a fraction of the card

## How long a single click waits to see whether it is half of a double click.
##
## It has to wait, and the reason is not taste. `UI.inspect_card` opens a full-screen
## veil that swallows the next click, so a click that opened the card immediately would
## eat the second half of every double click and the add gesture could never fire. The
## number is the smallest that reliably catches a deliberate double click, and the
## delay costs nothing: hovering a card already enlarges it 1.45x instantly, so the
## click is the "hold it up and read it" gesture rather than the first look.
const DOUBLE_GRACE := 0.22

## What a dragged card carries. A dictionary rather than the bare id so a drop target
## can tell a card from whatever else this screen may learn to drag later, and refuse
## the rest instead of coercing it into a card id.
const DRAG_KEY := "card_grid_id"

## Everything the grid needs from the screen, and nothing it can change on its own.
##
## The Callables are the whole point. `collection.gd` owns `selection`, the fuse
## prices, the clamp against what is still owned and the refresh that follows any of
## them — all of which the table view already had — so the grid asks rather than
## reimplements. A grid that kept its own copy of the deck is a grid that can disagree
## with the table beside it about what is in the deck.
class Ctx extends RefCounted:
	## id -> copies committed. The loadout being edited, or in a live run the deck that
	## was already dealt — the screen decides which, so nothing here has to know.
	var counts: Dictionary = {}
	## A run is live: this is a reading, not a place to change anything.
	var ledger := false
	## Nothing is at risk, so levelling is on offer (`collection.gd::_fusing_allowed`).
	var fusing := false
	## The card grid is what is beside the deck panel, rather than the table. The panel
	## is in both views now (D215) and it has to say how a copy gets IN, which is the one
	## thing that differs: a drag or a double-click there, the row's `+` here.
	var grid := true
	var add := Callable()      ## (id: String) -> void
	var remove := Callable()   ## (id: String) -> void
	var fuse := Callable()     ## (id: String, steps: int) -> void
	var steps := Callable()    ## (id: String) -> Array[int]
	var price := Callable()    ## (id: String, steps: int) -> Dictionary {copies, gold}
	var note := Callable()     ## (id: String) -> String, the one line shown beside an opened card

	func held(id: String) -> int:
		return int(counts.get(id, 0))

## The card as the player owns it — the catalogue resource is authored at level 1, and
## handing that to a face would draw a card the collection fused to 12 with its
## starting numbers (D50).
static func card_of(id: String) -> CardData:
	if not MetaState.CATALOG.has(id):
		return null
	var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
	if MetaState.collection.has(id):
		c.level = int(MetaState.collection[id]["level"])
	return c

# --- the grid ----------------------------------------------------------------

## Lay `ids` out as faces. `parent` is the column inside the screen's scroll, so the
## flow container is built here rather than passed in: it carries the separations the
## tile size was measured against, and a caller that built its own would be free to
## get them wrong.
static func fill(parent: Node, ids: Array, ctx: Ctx) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", UITheme.sep(int(GAP)))
	flow.add_theme_constant_override("v_separation", UITheme.sep(int(GAP)))
	parent.add_child(flow)
	for id in ids:
		tile(flow, String(id), ctx)
	return flow

## One card: its face, a badge if it can be levelled, and a strip saying how much of
## it is in the deck.
static func tile(flow: Node, id: String, ctx: Ctx) -> Control:
	var card := card_of(id)
	if card == null:
		return null
	var owned: int = MetaState.owned(id)
	var held: int = ctx.held(id)
	var size := Vector2(UITheme.px(TILE_W), UITheme.px(TILE_H))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_FILL
	col.custom_minimum_size.x = size.x
	flow.add_child(col)

	var note: String = ctx.note.call(id) if ctx.note.is_valid() else ""
	# `Callable()` for the press, deliberately: the click is handled below, where it
	# can tell a single click from the first half of a double one. `card_button`'s own
	# handler fires on every press and would open the card under the second click.
	var b := UI.card_button(col, card, size, Callable(), "", null, note)
	var holder := b.get_parent() as Control
	# The promise, in the words `tests/tooltip_test.gd` looks for and the player reads:
	# a gesture nobody is told about is not a feature (`UI.inspect_thumb`'s rule).
	# ...and the LV+ corner is named here as well, because a badge is only discoverable
	# to somebody who already looked at it. This is the tooltip a player reads while
	# working out what the grid does with a card (D215).
	var lv: String = "\nLV+ in the corner levels it." if (ctx.fusing and _levelable(id, card)) else ""
	b.tooltip_text += "\n\n%s — click to see the whole card%s%s" % [
		card.name, "" if ctx.ledger else ", double-click or drag it to the deck", lv]

	# A card whose every copy is already committed is still SHOWN — you may want to
	# read it, or level it — but it is dimmed, because the one thing you cannot do with
	# it is put another copy in the deck. Same signal as a spent card in Hearthstone's
	# collection, and it is the answer to "why did my drag do nothing".
	if not ctx.ledger and owned > 0 and held >= owned:
		holder.modulate = Color(0.62, 0.62, 0.68)

	_wire_face(b, holder, card, id, ctx, note)
	if ctx.fusing and _levelable(id, card):
		_badge(holder, size, id, card, ctx)
	_footer(col, card, id, held, owned, note)
	return col

## Click, double-click and drag on one card face.
##
## All three are on the Button `card_button` already built, not on an overlay of our
## own. An overlay with `MOUSE_FILTER_STOP` would sit between the cursor and that
## button and kill the hover-enlarge, which is how a card in this grid is read at all;
## `MOUSE_FILTER_PASS` passes to the PARENT, not to the sibling underneath, so it
## would kill it just the same.
static func _wire_face(b: Button, holder: Control, card: CardData, id: String,
		ctx: Ctx, note: String) -> void:
	# One timer per card rather than one per screen. A shared timer would have to be
	# told which card it belongs to on every click, and the first thing that breaks is
	# clicking one card while another's grace period is still running.
	var wait := Timer.new()
	wait.one_shot = true
	wait.wait_time = DOUBLE_GRACE
	holder.add_child(wait)
	wait.timeout.connect(func(): UI.inspect_card(b, card, null, note))

	b.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
			return
		b.accept_event()
		if mb.double_click:
			# The second half of a double click. Cancel the reading the first half
			# asked for — the player has said what they wanted instead.
			wait.stop()
			if not ctx.ledger and ctx.add.is_valid():
				ctx.add.call(id)
			return
		wait.start())

	if ctx.ledger:
		return
	b.set_drag_forwarding(
		func(_at: Vector2) -> Variant:
			var payload := drag_payload(id, ctx)
			if payload.is_empty():
				return null
			# The click's grace period is still running when the drag begins, and it
			# would open the inspector over the card being dragged.
			wait.stop()
			b.set_drag_preview(_drag_ghost(card))
			return payload,
		Callable(), Callable())

## What a card hands to a drop target, and `{}` for a card that must not lift.
##
## Split out of the lambda above so it can be tested. `set_drag_forwarding` stores its
## callables where nothing in GDScript can read them back, so a suite can drive the
## DROP side of this gesture and not the pick-up side — which would leave the one rule
## on this half of it, "a card with no spare copies does not move", untested.
##
## Refused rather than dropped-and-ignored: a drag that starts and then quietly does
## nothing reads as a broken screen, where a card that will not lift at all reads as
## "there are none left", which is the truth.
static func drag_payload(id: String, ctx: Ctx) -> Dictionary:
	if ctx.ledger or ctx.held(id) >= MetaState.owned(id):
		return {}
	return {DRAG_KEY: id}

## The card under the cursor while it is being dragged.
##
## Half-size and half-lit, so it reads as a card in transit rather than as a second
## card that has appeared on the screen, and centred on the pointer because Godot
## otherwise hangs the preview off the cursor's top-left corner and the card the
## player is aiming with is nowhere near the drop they are aiming at.
static func _drag_ghost(card: CardData) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.modulate = Color(1, 1, 1, 0.85)
	var size := Vector2(UITheme.px(TILE_W), UITheme.px(TILE_H)) * 0.8
	var b := UI.card_button(wrap, card, size, Callable())
	var holder := b.get_parent() as Control
	holder.set_anchors_preset(Control.PRESET_TOP_LEFT)
	holder.position = -size * 0.5
	holder.size = size
	wrap.custom_minimum_size = size
	return wrap

## Whether this card has a level left to buy. `can_fuse` is asked as well as the cap
## because the badge is a PRICE TAG: it opens a panel of purchases, and a badge on a
## card whose every purchase is refused is a door onto a wall.
## Whether this card has a level left to buy AT ALL — not whether it can be paid for
## today (D215).
##
## Those were the same test, and that is the bug a player reported as "it is not clear
## how to evolve a card": the badge is the only levelling control in this view, and it
## appeared only on cards whose price was already met. A player with no spare copies of
## anything — which is everyone early on, and everyone again after a fuse — saw a grid
## with no levelling on it anywhere and no reason to think the game had any. The table
## view never had this problem: it draws the price button blocked, with the reason on
## it, so the mechanism is visible before it is affordable.
static func _levelable(id: String, card: CardData) -> bool:
	return card.level < MetaState.max_level(id)

## The one mark this view adds to a card face: it can be levelled, and here is where
## you press.
##
## D133 refused to put the fuse prices behind a click on the table view, and was right
## to — the prices are what you shop on, and a shop that hides them behind a click has
## stopped being a shop. This does not undo that. The prices are still stated before
## anything is spent, in two places: on this badge's own hover, and on the priced
## buttons in the panel it opens, which are the same buttons the table row carries.
## What moved is only WHERE they are stated, and it moved because a 104px card face
## has no room for three price buttons — which is the honest reason, and the reason
## the table view still exists one toggle away for anyone who wants the whole column.
static func _badge(holder: Control, size: Vector2, id: String, card: CardData,
		ctx: Ctx) -> void:
	var pad := roundf(size.x * UITheme.CARD_PAD)
	var inner_x := size.x - pad * 2.0
	var side := roundf(inner_x * BADGE_SIDE)
	var h := roundf(size.y * BADGE_BAND)
	var x := pad + side + 2.0
	var w := inner_x - side * 2.0 - 4.0
	if w <= 0.0:
		return

	# Blocked is DRAWN, not withheld: a control that only exists once you can afford it
	# cannot teach anyone that the purchase exists (D215). Greyed and unpressable, with
	# the reason on the hover — the same treatment, and the same sentence, the table
	# view's price button has always given it.
	var blocked: String = MetaState.fuse_blocked_reason(id)
	var up := Button.new()
	up.text = "LV+"
	up.focus_mode = Control.FOCUS_NONE
	up.disabled = blocked != ""
	up.add_theme_font_size_override("font_size", maxi(9, int(h * 0.72)))
	up.add_theme_color_override("font_color", Color(0.72, 0.94, 0.66))
	up.add_theme_color_override("font_hover_color", Color(0.88, 1.0, 0.82))
	up.add_theme_color_override("font_disabled_color", Color(0.60, 0.64, 0.58, 0.72))
	for state in [["normal", 0.72], ["hover", 0.92], ["pressed", 1.0], ["disabled", 0.34]]:
		var sb := StyleBoxFlat.new()
		var off: bool = String(state[0]) == "disabled"
		sb.bg_color = (Color(0.07, 0.07, 0.08, float(state[1])) if off
			else Color(0.05, 0.10, 0.05, float(state[1])))
		sb.border_color = (Color(0.42, 0.44, 0.40, float(state[1])) if off
			else Color(0.50, 0.80, 0.46, float(state[1])))
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(h * 0.4))
		sb.set_content_margin_all(0)
		up.add_theme_stylebox_override(String(state[0]), sb)
	holder.add_child(up)
	up.set_anchors_preset(Control.PRESET_TOP_LEFT)
	up.position = Vector2(x, pad)
	up.size = Vector2(w, h)
	up.custom_minimum_size = Vector2.ZERO

	# The next level's price, on the badge itself. This is the sentence that keeps the
	# move honest: the cheapest purchase behind this door is quoted before the door is
	# opened, so nobody clicks it to find out what it costs.
	var one: Dictionary = ctx.price.call(id, 1) if ctx.price.is_valid() else {}
	var gain: String = card.level_up_text(card.level + 1)
	# A blocked badge still quotes the level it is refusing to sell. "Need 4 copies" on
	# its own is a wall; "need 4 copies, and it would take this to 16 damage" is a goal,
	# and it is the sentence that makes somebody go and earn the copies.
	up.tooltip_text = "Level %s: %s\n%s" % [
		card.name, gain if gain != "" else "no change to its numbers",
		("Costs %d copies and %d gold.\nClick for the bulk prices." % [
			int(one.get("copies", 0)), int(one.get("gold", 0))]) if blocked == ""
		else "Not yet: %s." % blocked]
	if blocked != "":
		return
	up.pressed.connect(func(): _fuse_panel(up, id, ctx))

## How many copies of this card the deck is asking for, out of how many exist.
##
## Under the card rather than on it, and it is the number this whole view is arranged
## around: a grid of faces answers "what is this" beautifully and cannot answer "how
## many did I take" at all, which is the one thing the table's stepper column said at
## a glance.
static func _footer(col: VBoxContainer, card: CardData, id: String, held: int,
		owned: int, note: String) -> void:
	var foot := Label.new()
	foot.custom_minimum_size = Vector2(UITheme.px(TILE_W), UITheme.px(FOOT_H))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.clip_text = true
	foot.add_theme_font_size_override("font_size", maxi(11, UITheme.font() - 3))
	foot.text = "%d of %d" % [held, owned]
	foot.add_theme_color_override("font_color",
		Color(0.72, 0.90, 0.66) if held > 0 else Color(0.62, 0.60, 0.66))
	col.add_child(foot)
	# The second way into the card, and the one `tooltip_test.gd` counts as the TEXT
	# half of the pair: every card in every list is openable from its picture and from
	# its words, or the affordance is only half shipped (D205b).
	UI.inspect_text(foot, card, note)

# --- the fuse panel ----------------------------------------------------------

## The priced level buttons, over the card they belong to.
##
## Deliberately the same three purchases the table row offers — `+1`, `+10`, and
## everything you can afford — built from the screen's own `steps` and `price`, so
## there is one fuse curve in the game and not a second one that drifts. A player who
## learns the prices in one view knows them in the other.
static func _fuse_panel(anchor: Control, id: String, ctx: Ctx) -> void:
	var card := card_of(id)
	if card == null or not ctx.steps.is_valid() or not ctx.price.is_valid():
		return
	# The OUTERMOST Control above the badge, never `current_scene` — `UI.inspect_card`
	# spells out why and this is the same problem: the two are the same node in the game
	# and are not the same node under a harness that parents a screen beneath a plain
	# Node, which gets a null host and silently opens nothing. Hanging the panel off the
	# screen's own root also means it dies with the screen.
	var host: Control = null
	var walk: Node = anchor
	while walk != null:
		if walk is Control:
			host = walk as Control
		walk = walk.get_parent()
	if host == null:
		return

	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.72)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.z_index = 120
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(veil)
	# Anywhere off the panel closes it. Same gesture as `UI.inspect_card`'s veil, so
	# the two overlays this screen can raise are dismissed the same way.
	veil.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed:
			veil.queue_free())

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(centre)

	var bay := PanelContainer.new()
	bay.add_theme_stylebox_override("panel", Icons.card_style(card.rarity, 0.10))
	centre.add_child(bay)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(8))
	bay.add_child(col)

	var cap: int = MetaState.max_level(id)
	var head := Label.new()
	head.text = "%s — level %d of %d" % [card.name, card.level, cap]
	head.add_theme_color_override("font_color", Icons.rarity_colour(card.rarity))
	col.add_child(head)

	var purse := Label.new()
	purse.text = "%d copies owned, %d gold in the purse" % [MetaState.owned(id), MetaState.gold]
	purse.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
	col.add_child(purse)

	# What the next level BUYS, beside what it costs, and not only on a hover. This is
	# the half D133 added to the table row — a shop that states its prices and not its
	# goods is asking for a decision nobody can make well — and it would have been the
	# easiest thing in the world to leave in a tooltip here and call the prices moved.
	var gain: String = card.level_up_text(card.level + 1)
	if gain != "":
		var buys := Label.new()
		buys.text = "One more level: %s" % gain
		buys.add_theme_color_override("font_color", Color(0.72, 0.86, 0.68))
		col.add_child(buys)

	for step in ctx.steps.call(id):
		var n := int(step)
		var p: Dictionary = ctx.price.call(id, n)
		var target: int = card.level + n
		var buys: String = card.level_up_text(target)
		var f := Button.new()
		UITheme.style_button(f)
		f.text = "+%d   %d copies, %d gold" % [n, int(p.get("copies", 0)), int(p.get("gold", 0))]
		UI.hoverable(f, "To level %d: %s\nCosts %d copies and %d gold." % [
			target, buys if buys != "" else "no change to its numbers",
			int(p.get("copies", 0)), int(p.get("gold", 0))])
		# The panel closes on the purchase because the screen rebuilds underneath it:
		# the card is now a level higher and every price on this panel is stale.
		f.pressed.connect(func():
			veil.queue_free()
			if ctx.fuse.is_valid():
				ctx.fuse.call(id, n))
		col.add_child(f)

	var never := Button.new()
	UITheme.style_button(never)
	never.text = "Never mind"
	never.pressed.connect(func():
		Audio.play("ui_back")
		veil.queue_free())
	col.add_child(never)

# --- the deck bay ------------------------------------------------------------

## The deck, down the right, as the thing you drag onto.
##
## It is a panel and not a column of loose rows for one reason: a drop target has to
## be a place. A card dragged at "the list of cards on the right" needs an edge to
## aim for and something that lights up when the cursor is inside it, and a bare VBox
## is only as big as its rows — so an empty deck would have no target at all, which is
## exactly the state a player is in the first time they build one.
static func deck_bay(parent: Node, ctx: Ctx) -> DropBay:
	var bay := DropBay.new()
	bay.custom_minimum_size.x = UITheme.px(PANEL_W)
	bay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bay.mouse_filter = Control.MOUSE_FILTER_STOP
	bay.cool()
	parent.add_child(bay)
	if not ctx.ledger:
		bay.on_drop = ctx.add
	return bay

## A PanelContainer that knows when a drag is over it, and — the part that needs a
## class rather than three lambdas — when one has ENDED.
##
## `can_drop_data` is the only hook Godot calls while a card hovers a target, so it is
## the natural place to light the frame. Nothing calls it once the cursor leaves, and
## nothing calls it when the player drops the card somewhere else entirely, so a bay
## lit that way stays lit for the rest of the session. `NOTIFICATION_DRAG_END` is
## broadcast to every Control when a drag finishes wherever it finished, and it is
## reachable only from `_notification` — which is why this is a subclass and not the
## `set_drag_forwarding` call the rest of the file would have used.
class DropBay extends PanelContainer:
	var on_drop := Callable()   ## (id: String) -> void, unset in a live run
	var _hot := false

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if not on_drop.is_valid():
			return false
		var ok: bool = typeof(data) == TYPE_DICTIONARY and data.has(CardGrid.DRAG_KEY)
		if ok and not _hot:
			_hot = true
			add_theme_stylebox_override("panel", CardGrid._bay_style(true))
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		cool()
		if typeof(data) == TYPE_DICTIONARY and data.has(CardGrid.DRAG_KEY) and on_drop.is_valid():
			on_drop.call(String(data[CardGrid.DRAG_KEY]))

	func _notification(what: int) -> void:
		# DRAG_END covers the drop that missed and the drag the player abandoned;
		# MOUSE_EXIT covers the cursor sliding off the bay with the card still held,
		# which DRAG_END has no opinion about because the drag is still going.
		if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
			cool()

	func cool() -> void:
		if not _hot and has_theme_stylebox_override("panel"):
			return
		_hot = false
		add_theme_stylebox_override("panel", CardGrid._bay_style(false))

## The bay's frame, lit while a card is over it.
static func _bay_style(hot: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.12, 0.86) if not hot else Color(0.10, 0.16, 0.11, 0.92)
	sb.border_color = Color(0.36, 0.34, 0.42) if not hot else Color(0.58, 0.88, 0.54)
	sb.set_border_width_all(2 if not hot else 3)
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(8)
	return sb

## Fill the bay: what is in the deck, and how to take it back out.
static func fill_deck(bay: PanelContainer, ctx: Ctx) -> void:
	# Removed BEFORE the new column is added, not just freed. `queue_free` runs at the
	# end of the frame, so a PanelContainer would spend this frame holding two children
	# stacked on each other — and a PanelContainer sizes itself to all of them.
	for c in bay.get_children():
		bay.remove_child(c)
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.sep(4))
	bay.add_child(col)

	# Summed here rather than through `MetaState.loadout_size`, which clamps every
	# entry to the copies still in the COLLECTION. That clamp is right for a loadout
	# being edited and wrong for a run in progress: a deck picks up cards mid-run that
	# the collection has never seen, and the clamp would report a smaller deck than the
	# one the player is holding.
	var size := 0
	for id in ctx.counts:
		size += int(ctx.counts[id]) if ctx.ledger else mini(int(ctx.counts[id]), MetaState.owned(String(id)))
	var head := Label.new()
	head.add_theme_font_size_override("font_size", UITheme.font() + 2)
	if ctx.ledger:
		head.text = "Deck in play — %d" % size
		head.add_theme_color_override("font_color", Color(0.86, 0.84, 0.90))
	else:
		head.text = "Deck  %d / %d" % [size, MetaState.MAX_DECK_SIZE]
		# The bounds are a rule the player meets by breaking it, so the header says
		# which way it is broken rather than only that it is. Same two sentences the
		# readout at the top of the screen gives, where the eye already is.
		var legal: bool = size >= MetaState.MIN_DECK_SIZE and size <= MetaState.MAX_DECK_SIZE
		head.add_theme_color_override("font_color",
			Color(0.86, 0.84, 0.90) if legal else Color(0.95, 0.72, 0.45))
		if size < MetaState.MIN_DECK_SIZE:
			head.text += "   need %d more" % (MetaState.MIN_DECK_SIZE - size)
		elif size > MetaState.MAX_DECK_SIZE:
			head.text += "   over by %d" % (size - MetaState.MAX_DECK_SIZE)
	# How a copy comes back out, on the header rather than on a line of its own under the
	# list (D215). That line was 46px of a panel whose scroll had 312px to spend on a
	# deck 737px long — an eighth of the deck, permanently, to repeat something every row
	# in the list already says in its own tooltip. A player reported the deck as hard to
	# scroll, and this is a seventh of the reason.
	UI.hoverable(head, "%s\n%s" % [
		"What the run will be dealt from." if ctx.ledger else "What the run will be dealt from, once you start it.",
		"Right-click a card here to read it." if ctx.ledger
			else "Click a card here to take one copy back out; right-click to read it."])
	col.add_child(head)

	var rows := UI.scroll(col)
	rows.add_theme_constant_override("separation", UITheme.sep(3))
	# A bar you can actually put a cursor on. The wheel works over the panel and always
	# did, but the wheel is not the gesture somebody reaches for when the list they can
	# see is a third of the list they have.
	var sc := rows.get_parent() as ScrollContainer
	if sc != null:
		sc.get_v_scroll_bar().custom_minimum_size.x = UITheme.px(BAR_W)

	var ids: Array = ctx.counts.keys()
	ids.sort_custom(func(a, b) -> bool:
		var ca := card_of(String(a))
		var cb := card_of(String(b))
		if ca == null or cb == null:
			return String(a) < String(b)
		if ca.eff_cost() != cb.eff_cost():
			return ca.eff_cost() < cb.eff_cost()
		return ca.name < cb.name)

	if ids.is_empty():
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.62, 0.60, 0.66))
		# The empty panel is the one place the way IN has to be spelled out, and it is not
		# the same way in both views (D215).
		if ctx.ledger:
			empty.text = "Nothing in the deck."
		elif ctx.grid:
			empty.text = "Nothing in the deck yet.\n\nDrag a card here, or double-click it."
		else:
			empty.text = "Nothing in the deck yet.\n\nUse the + on a card's row."
		rows.add_child(empty)
		return

	for id in ids:
		_deck_row(rows, String(id), ctx)

## One kind of card in the deck. Clicking it takes a copy back out.
##
## The row does NOT promise the card preview in those words, and that is deliberate
## rather than an omission: a left click here REMOVES, so a row saying "click to see
## the whole card" would be a lie about the one gesture that costs the player
## something. Right-click still opens it, which is the gesture every card face in the
## game already answers to, and the tooltip says so.
## The row wears the card's own illustration, dimmed, behind its name.
##
## The bay's whole job is telling you what is in the deck at a glance, and the grid
## beside it has just taught the player to find a card by its picture — so a bay of
## flat plates makes them read the names of the very cards they were recognising by
## sight a moment ago. A strip of the painting is enough: the eye matches colour and
## shape long before it finishes a word.
##
## Only where there IS a painting. `PixelArt.card_art` falls back to a 16x16 CC0 sheet
## slice, and a 16px sprite stretched across a 234px strip is sixteen-fold mush — the
## same trap `UI.card_button` documents in its picture band. `painted_card_art`
## returns null rather than the fallback, so a card without art keeps exactly the plate
## it has today. Same "use it if it exists" contract as every backdrop in the game.
static func _deck_row(parent: Node, id: String, ctx: Ctx) -> void:
	var card := card_of(id)
	if card == null:
		return
	var n: int = ctx.held(id)
	var art := PixelArt.painted_card_art(card.id, Icons.card_family(card))

	# A plain Control, so the picture, the scrim and the button can be stacked in a
	# known order. A container would take its size from them and lose the layering.
	var holder := Control.new()
	holder.custom_minimum_size.y = UITheme.px(ROW_H)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(holder)

	if art != null:
		# A clipping window, because KEEP_ASPECT_COVERED deliberately overflows on the
		# short axis — a 320x240 painting filling a 234px-wide strip is 175px tall, and
		# without this it would paint over the rows above and below.
		var win := Control.new()
		win.clip_contents = true
		win.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(win)
		win.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.modulate = Color(1, 1, 1, ART_ALPHA)
		win.add_child(pic)
		# `set_anchors_AND_OFFSETS_preset`. `set_anchors_preset` preserves the control's
		# current rect, and a control created two lines ago has a rect of 0x0, so it
		# anchors to the full band and stays zero-sized forever (D121).
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var scrim := ColorRect.new()
		scrim.color = Color(0.04, 0.03, 0.06, SCRIM_ALPHA)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		win.add_child(scrim)
		scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var b := Button.new()
	Icons.style_card_button(b, card.rarity, Icons.for_card(card))
	# BESIDE the text, not above it. `style_card_button` stacks the effect glyph on top
	# of the label, which is right on the wide buttons it was written for and makes this
	# row 52px tall — where `ROW_H` says 34, so the button overflowed its holder by 18px
	# and painted over the row below. Every row's picture then covered the previous
	# row's overflowing text, which looked like a clipping fault in the artwork and was
	# a layout fault in the button.
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if art != null:
		# The rarity frame stays; its fill goes, or it would cover the picture it is
		# framing. Hover and pressed keep a tint, because the row is a control and has
		# to answer the cursor — over a painting that tint is the only thing that says
		# so, since there is no flat colour left to brighten.
		for state in [["normal", 0.0], ["hover", 0.42], ["pressed", 0.58]]:
			var sb := Icons.card_style(card.rarity, 0.16)
			sb.bg_color.a = float(state[1])
			b.add_theme_stylebox_override(String(state[0]), sb)
	b.text = "%dx  %s" % [n, card.name]
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", maxi(12, UITheme.font() - 2))
	b.tooltip_text = "%s\n\n%s\n\n%s" % [
		card.name, card.effect_text(),
		"Right-click for the whole card." if ctx.ledger
			else "Left-click takes one copy out. Right-click shows the whole card."]
	if not ctx.ledger:
		b.pressed.connect(func():
			if ctx.remove.is_valid():
				ctx.remove.call(id))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		b.accept_event()
		UI.inspect_card(b, card, null,
			ctx.note.call(id) if ctx.note.is_valid() else ""))
	holder.add_child(b)
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The row is `ROW_H`, or as tall as the button needs — whichever is more. Anchoring a
	# Control to a rect does NOT shrink it below its own minimum, so a holder shorter
	# than its button is not a squeeze, it is an overflow onto whatever is underneath,
	# and it is silent. Asking the button how tall it is means the next theme change
	# that grows it grows the row instead of breaking it.
	holder.custom_minimum_size.y = maxf(UITheme.px(ROW_H), b.get_combined_minimum_size().y)
