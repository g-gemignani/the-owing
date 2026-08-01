## Runtime test: no card ever hides its own text.
##
## Written after a play report — "text of cards while playing in an encounter are
## overflowing and cannot be seen". Cards rendered everything through `Button.text`
## with `clip_text = true`, so a description longer than the frame was silently cut
## off mid-word. Nothing in the suite could see it: the scene booted, the buttons
## worked, only the words were missing.
##
## The hand is measured TWICE, at two sizes: the five combat deals, and the eleven
## real play reaches with two relics and one fused draw card (D116). `Balance.HAND_SIZE`
## is the opening hand, not the hand — and the fan gives every extra card its width out
## of the card before it, so the size that had never been measured was the dangerous one.
##
## Since D117 a resting card in a crowded hand may show its cost and its effect
## symbol INSTEAD of a name too narrow to render legibly, so "the name is visible and
## clear of the next card" is no longer the only acceptable answer — but "neither" is
## still a failure, and which of the two answers a hand gives is asserted at both hand
## sizes. See `_check_fan()`; skipping a hidden name is how this file would have gone
## quietly vacuous at the one size it was written for.
##
## A SCENE, not a `--script` test: line counts only exist once a tree has been laid
## out, and autoloads are absent in headless script runs.
## Run: godot --headless res://tests/CardTextTest.tscn
extends Node

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_cardtext_"

var _fails := 0
## What the last `_check_fan()` found the resting hand doing about names: how many
## cards showed one, and how many showed the D117 substitute (cost + effect symbol)
## because the fan had squeezed the strip past `UI.CARD_NAME_MIN_W`. Counted rather
## than asserted inside the fan check, because the two hand sizes want opposite
## answers and only the caller knows which hand it built.
var _named := 0
var _swapped := 0

func _ready() -> void:
	# Headless defaults to a SQUARE 1280x1280 viewport. Every geometry check below
	# would otherwise be measured against 560 pixels of vertical slack the player
	# never has — the same trap PlayableTest documents, walked into again the moment
	# this test started measuring rects instead of only font sizes.
	var design := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	get_window().size = Vector2i(design)
	await get_tree().process_frame
	# ...and then PROVE it took, rather than trusting the assignment. The project
	# stretches `canvas_items` with aspect "expand", so the visible rect follows the
	# WINDOW: one taller than the design gives every rect below it vertical slack the
	# player does not have, and every geometry check here silently passes on a screen
	# nobody plays. That is not hypothetical — the screenshot harness renders 1280x800
	# on a 16:10 desktop and hid a clipping bug that way (D115). One line, and the
	# trustworthiness of everything below stops being an assumption.
	var frame := get_viewport().get_visible_rect().size
	if not frame.is_equal_approx(design):
		_fails += 1
		print("FAIL measuring a %.0fx%.0f layout in a %.0fx%.0f frame" % [
			design.x, design.y, frame.x, frame.y])
	print("  measured in a %.0fx%.0f frame" % [frame.x, frame.y])

	MetaState.path_prefix = SANDBOX
	MetaState.slot = 0
	MetaState.new_save()

	# Every card in the game, not just a starter hand: the longest description is
	# what breaks, and a starter deck contains none of them.
	await _check_every_card()
	await _check_live_hand()
	# ...and again at the size real play reaches, which is not the size combat deals.
	# LAST, deliberately: it grants relics and puts a fused card in the collection, so
	# anything that wants the plain starter state has to run before it.
	await _check_large_hand()

	MetaState.writes_disabled = true
	_purge()
	if _fails == 0:
		print("CARD TEXT TEST: PASS (no card clips its name or rules text)")
	else:
		print("CARD TEXT TEST: FAIL (%d)" % _fails)
	get_tree().quit()

func _check_every_card() -> void:
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(host)
	var box := HBoxContainer.new()
	host.add_child(box)

	var ids: Array = MetaState.CATALOG.keys()
	var size := UITheme.card_size()
	# the narrowest a card ever gets: a full hand squeezed to the window width
	var narrow: float = Icons.fit_card_width(
		10, size.x, float(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 1280)) - UITheme.px(40),
		float(UITheme.sep()))
	for id in ids:
		var card := load(MetaState.CATALOG[id]) as CardData
		if card == null:
			continue
		UI.card_button(box, card, Vector2(narrow, size.y), Callable())
	await get_tree().process_frame
	await get_tree().process_frame

	var smallest := 999
	var worst := ""
	var checked := 0
	for holder in _cards(box):
		checked += 1
		var id: String = holder.get_meta("card_id")
		# The card is TWO PARTS and both are always on it: the rules text lives in a
		# band of its own under the picture, so unlike the old face it does not wait
		# for a hover to exist. This assertion used to be its exact opposite ("shows
		# its rules text while resting" was the failure) — the shape changed, and a
		# guard that outlives the design it was guarding is worse than none.
		_hover(holder, false)
		await get_tree().process_frame
		_measure(holder, "%s resting @%dpx" % [id, int(narrow)])
		if card_desc(id) != "" \
				and not _labels(holder).any(func(l): return l.text == card_desc(id) and l.visible):
			_fails += 1; print("FAIL %s does not show its rules text at rest" % id)
		# hovered: the same text, bigger — the hover is comfort now, not disclosure
		_hover(holder, true)
		await get_tree().process_frame
		_measure(holder, "%s hovered @%dpx" % [id, int(narrow)])
		var showed := false
		for l in _labels(holder):
			if not l.visible or l.text == "":
				continue
			if l.text == card_desc(id):
				showed = true
			var px: float = l.get_theme_font_size("font_size") * UITheme.CARD_HOVER_SCALE
			if px < float(smallest):
				smallest = int(px)
				worst = l.text
		if not showed and card_desc(id) != "":
			_fails += 1; print("FAIL %s does not reveal its rules text on hover" % id)
		_hover(holder, false)
	print("  worst case hovered at a %dpx-wide card: %dpx effective for \"%s\"" % [
		int(narrow), smallest, worst])
	# a floor on readability: shrink-to-fit must not solve overflow by vanishing
	if smallest < 14:
		_fails += 1; print("FAIL hovered text is only %dpx, too small to read" % smallest)
	if checked < ids.size():
		_fails += 1; print("FAIL only %d cards built of %d" % [checked, ids.size()])
	host.queue_free()
	await get_tree().process_frame

## The real combat screen, so the sizes the player actually sees are the ones tested.
func _check_live_hand() -> void:
	# a real fight, not just the scene: the hand only exists once the engine is set up
	GameState.select_dungeon(Balance.DUNGEONS[0])
	GameState.enter_dungeon(_collection_deck())
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	GameState.combat_state = {}
	var scene := load("res://scenes/Combat.tscn") as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load Combat.tscn"); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var seen := 0
	for holder in _cards(inst):
		seen += 1
		_hover(holder, false)
		await get_tree().process_frame
		_measure(holder, "live combat resting: %s" % holder.get_meta("card_id"))
		_hover(holder, true)
		await get_tree().process_frame
		_measure(holder, "live combat hovered: %s" % holder.get_meta("card_id"))
		_hover(holder, false)
	if seen == 0:
		_fails += 1; print("FAIL combat rendered no card text at all")

	var vp := get_viewport().get_visible_rect()
	var cards := _hand_cards(inst)
	_check_fan(inst, cards, "a dealt hand of %d" % cards.size())
	# The OTHER direction of the D117 switch. The hand combat deals has ~101px of step
	# and an 85px name slot, which is more than twice the width the substitution is for,
	# so every card here must still be showing its name. Without this the threshold
	# could drift to "always" — a hand that never names a card would otherwise pass
	# every check in this suite, because the new branch answers all of them.
	print("  a dealt hand of %d: of the %d cards a neighbour overlaps, %d show a name and %d show cost+symbol" % [
		cards.size(), _named + _swapped, _named, _swapped])
	if _swapped > 0:
		_fails += 1
		print("FAIL %d of %d cards in the DEALT hand gave up their names; at this step the name fits" % [
			_swapped, cards.size()])
	# Everything in the bottom band has to be ON the screen. `PRESET_BOTTOM_LEFT`
	# puts a box's TOP edge on the bottom of the frame, so the entire HUD and both
	# controls rendered below it — and nothing in the suite noticed, because every
	# check was about cards. D33's lesson ("actionable content must be on screen")
	# applied to the widgets that were not there when it was written.
	for named in [["the vitals", inst.status_label], ["the buffs line", inst.buffs_label],
			["the piles", inst.piles_label], ["the log", inst.log_label],
			["the power", inst.power_btn], ["End Turn", inst.end_btn],
			["the Menu button", inst.menu_btn], ["the place name", inst.place_label]]:
		var widget: Control = named[1]
		if widget == null:
			_fails += 1; print("FAIL %s does not exist" % named[0]); continue
		if not widget.visible:
			continue
		var wr := widget.get_global_rect()
		if wr.position.y < -1.0 or wr.end.y > vp.size.y + 1.0 \
				or wr.position.x < -1.0 or wr.end.x > vp.size.x + 1.0:
			_fails += 1
			print("FAIL %s is off screen: %.0f,%.0f to %.0f,%.0f in a %.0fx%.0f frame" % [
				named[0], wr.position.x, wr.position.y, wr.end.x, wr.end.y,
				vp.size.x, vp.size.y])

	# --- hovering a card must show the WHOLE card --------------------------------
	#
	# The other half of the bargain the peek strikes: a card is allowed to hang off
	# the bottom edge at rest only because hovering it brings all of it back. The
	# lift is computed per card (the fan's outer cards hang lower than its middle
	# ones, and hover scales about the bottom edge so every pixel of the growth goes
	# upward), so measuring one card would prove nothing about the one most at risk.
	# Checked on EVERY card in hand, at the scale the player sees.
	for holder4 in cards:
		var open4: Callable = holder4.get_meta("preview", Callable())
		var btn4: Button = null
		for ch in holder4.get_children():
			if ch is Button:
				btn4 = ch
		if btn4 == null:
			continue
		btn4.mouse_entered.emit()
		await get_tree().process_frame
		# global_rect carries the scaled position but the UNSCALED size, so the
		# bottom edge has to be worked out rather than read off. Growth is about the
		# bottom-centre pivot, so the bottom stays put and the top rises.
		var gr := holder4.get_global_rect()
		var grown := holder4.size.y * holder4.scale.y
		var top := gr.end.y - grown
		if top < -1.0 or gr.end.y > vp.size.y + 1.0:
			_fails += 1
			print("FAIL hovered %s spans y %.0f-%.0f, not fully inside a %.0f-tall frame" % [
				holder4.get_meta("card_id"), top, gr.end.y, vp.size.y])
		btn4.mouse_exited.emit()
		await get_tree().process_frame
		if open4.is_valid():
			open4.call(false)

	# --- the number has to be readable WITHOUT hovering ---------------------------
	#
	# A resting card shows its name and its cost, and the rules text only appears on
	# hover. That made Strength invisible in the place it matters: with a buff up,
	# every attack is worth more and nothing on screen changed until you moused over
	# each card in turn. The face now carries the headline number, and in a fight it
	# is the live one.
	var eng2 = inst.eng
	if eng2 == null:
		_fails += 1; print("FAIL combat has no engine to read")
	else:
		eng2.player.strength = 6
		inst._refresh()
		await get_tree().process_frame
		var checked := 0
		for holder in _cards(inst):
			var card_id: String = holder.get_meta("card_id")
			var card: CardData = null
			for c in eng2.hand:
				if c.id == card_id:
					card = c
					break
			if card == null or card.eff_damage() <= 0:
				continue
			checked += 1
			var want := str(eng2.card_damage(card))
			_hover(holder, false)
			await get_tree().process_frame
			var on_face := _labels(holder).any(func(l): return l.visible and l.text.begins_with(want))
			if not on_face:
				_fails += 1
				print("FAIL %s does not show the %s damage it would deal until you hover it" % [
					card_id, want])
			if want == str(card.eff_damage()):
				_fails += 1
				print("FAIL 6 Strength changed nothing about what %s claims to do" % card_id)
		if checked == 0:
			_fails += 1; print("FAIL no attack card was in hand to check")
	# the real signal, not the helper: a layout that only responds to the test is
	# a layout the player never sees change
	for holder in _cards(inst):
		var btn: Button = null
		for c in holder.get_children():
			if c is Button:
				btn = c
		if btn == null:
			_fails += 1; print("FAIL card has no button to hover"); break
		btn.mouse_entered.emit()
		await get_tree().process_frame
		if holder.scale.x <= 1.0:
			_fails += 1; print("FAIL hovering does not enlarge the card")
		if not _labels(holder).any(func(l): return l.visible and l.text.length() > 6):
			_fails += 1; print("FAIL hovering reveals no rules text")
		btn.mouse_exited.emit()
		await get_tree().process_frame
		if holder.scale.x != 1.0:
			_fails += 1; print("FAIL card stays enlarged after the mouse leaves")
		break
	inst.queue_free()
	await get_tree().process_frame

## The geometry a hand of ANY size has to keep, in one place so that a hand bigger
## than the one combat deals can be put through exactly the same measurements
## instead of a second set of them that quietly drifts (D116). Three things:
## every card's identifying part is on screen, a resting card's name is not under
## its right-hand neighbour, and no card runs under either bottom corner.
##
## `cards` must be in HAND order — the order the fan stacks them in, which is what
## makes "the next card" mean anything. See `_hand_cards()`.
func _check_fan(inst: Node, cards: Array[Control], tag: String) -> void:
	# Every one of these was broken at some point while building the layout, each
	# time found only by rendering it and looking: cards running off the bottom edge,
	# the vitals line overflowing its box and passing under the leftmost card, and the
	# rightmost card tucking behind the power orb. A still image cannot keep them
	# fixed, so the rects are measured.
	var vp := get_viewport().get_visible_rect()
	if cards.size() < 3:
		_fails += 1; print("FAIL only %d cards in hand to measure [%s]" % [cards.size(), tag])
	var rots := {}
	var lowest_y := -1.0e9
	var middle_y := 0.0
	for k in cards.size():
		var holder: Control = cards[k]
		var r := holder.get_global_rect()
		# A card in hand HANGS OFF the bottom edge on purpose (Combat.HAND_PEEK) —
		# that is what buys a portrait card its height. So the assertion is no longer
		# "the card is on screen", which would now fail by design; it is **the part
		# that identifies the card is on screen**: the picture band and the name strip
		# under it, which is also where the cost and the headline numbers live.
		# Without this the peek could be tuned to any value at all and nothing would
		# notice until a player could not tell two cards apart.
		var ident := roundf(holder.size.y
				* (UITheme.CARD_ART_BAND + UITheme.CARD_NAME_BAND)) \
			+ roundf(holder.size.x * UITheme.CARD_PAD)
		if r.position.y < 0.0:
			_fails += 1
			print("FAIL [%s] card %s starts at y %.0f, above a %.0f-tall frame" % [
				tag, holder.get_meta("card_id"), r.position.y, vp.size.y])
		if r.position.y + ident > vp.size.y + 1.0:
			_fails += 1
			print("FAIL [%s] card %s hangs too far: picture+name end at y %.0f in a %.0f-tall frame" % [
				tag, holder.get_meta("card_id"), r.position.y + ident, vp.size.y])
		if r.position.x < 0.0 or r.end.x > vp.size.x + 1.0:
			_fails += 1
			print("FAIL [%s] card %s spans x %.0f-%.0f, outside a %.0f-wide frame" % [
				tag, holder.get_meta("card_id"), r.position.x, r.end.x, vp.size.x])
		rots[snappedf(holder.rotation, 0.001)] = true
		if k == 0 or k == cards.size() - 1:
			lowest_y = maxf(lowest_y, r.position.y)
		if k == cards.size() / 2:
			middle_y = r.position.y
	# a fan, not a row: the cards are tilted, and the middle of it rides higher
	if rots.size() < 3:
		_fails += 1
		print("FAIL [%s] the hand is not fanned — %d distinct angles" % [tag, rots.size()])
	if middle_y >= lowest_y:
		_fails += 1
		print("FAIL [%s] the hand has no arc: middle card at y %.0f, outer at y %.0f" % [
			tag, middle_y, lowest_y])

	# --- the name a RESTING card shows must not be under the next card ------------
	#
	# A resting card shows its name, its cost and its headline number and nothing else,
	# and the fan lays the next card on top of this one's right-hand edge — so the name
	# was the one thing being hidden. A captured five-card hand read "Smith's Fu",
	# "Prepare", "Bludgeo", "Bite", "Shiv": three of five unidentifiable without
	# hovering (D97). None of the checks above can see it — every card was on screen,
	# fanned, arced and clear of both corners while being unreadable.
	#
	# The last card is drawn on top of the rest, so it is the one card allowed the
	# whole face; everything before it is measured against its right-hand neighbour.
	#
	# A card is allowed to answer this in EITHER of two ways, and the one thing it may
	# not do is answer in neither. Since D117 a strip too narrow to hold a name at a
	# legible size shows the card's cost and its effect symbol instead — so an unnamed
	# card is not automatically a defect. But "no visible name" used to `continue`
	# here, which means the moment the layout started hiding names this whole check
	# went silently vacuous at exactly the hand sizes it was written to protect. Hiding
	# the subject is not passing: whichever way the card answers, something that
	# identifies it has to be visible AND clear of the next card.
	_named = 0
	_swapped = 0
	for k in maxi(0, cards.size() - 1):
		var holder3: Control = cards[k]
		if not holder3.has_meta("name_label"):
			_fails += 1
			print("FAIL [%s] card %s exposes no name label to measure" % [
				tag, holder3.get_meta("card_id")])
			continue
		var cid: String = holder3.get_meta("card_id")
		var nm: Control = holder3.get_meta("name_label")
		# Tolerance is a whole character of the smallest font the fitter will use: the
		# holders are rotated, and get_global_rect() is axis-aligned, so both edges
		# carry a little slop. The defect this guards against is ~35% of a card wide.
		# The same number bounds the substitute below, because "inside the strip the
		# player can see" is the same measurement in both cases: not under the next card.
		var covered := (cards[k + 1] as Control).get_global_rect().position.x
		if nm != null and nm.visible:
			_named += 1
			if nm.get_global_rect().end.x > covered + 7.0:
				_fails += 1
				print("FAIL [%s] the name on %s runs to x %.0f, under the next card at x %.0f" % [
					tag, cid, nm.get_global_rect().end.x, covered])
			continue
		_swapped += 1
		var cst: Label = holder3.get_meta("cost_label", null)
		var glyph: TextureRect = holder3.get_meta("crowd_symbol", null)
		if cst == null or not cst.visible or cst.text == "":
			_fails += 1
			print("FAIL [%s] %s shows no name and no cost either — nothing identifies it" % [
				tag, cid])
		elif cst.get_global_rect().end.x > covered + 7.0:
			_fails += 1
			print("FAIL [%s] the cost on %s runs to x %.0f, under the next card at x %.0f" % [
				tag, cid, cst.get_global_rect().end.x, covered])
		if glyph == null or not glyph.visible or glyph.texture == null:
			_fails += 1
			print("FAIL [%s] %s hid its name and put no effect symbol in the strip" % [tag, cid])
		elif glyph.size.x < 8.0 or glyph.size.y < 8.0:
			# A symbol placed in a box too small to read is the same defect as no symbol,
			# and it is the mistake this session made twice in the measuring instrument
			# itself (a 16px window over a 64px glyph). The box is measured.
			_fails += 1
			print("FAIL [%s] the symbol on %s is a %.0fx%.0f box, too small to identify it" % [
				tag, cid, glyph.size.x, glyph.size.y])
		elif glyph.get_global_rect().end.x > covered + 7.0:
			_fails += 1
			print("FAIL [%s] the symbol on %s runs to x %.0f, under the next card at x %.0f" % [
				tag, cid, glyph.get_global_rect().end.x, covered])

	# ...and the hand must not run under the things parked in both bottom corners
	for zone in [["the vitals", inst.status_label], ["End Turn", inst.end_btn],
			["the power orb", inst.power_btn]]:
		var other: Control = zone[1]
		if other == null or not other.visible:
			continue
		var orect := other.get_global_rect()
		for holder2 in cards:
			if (holder2 as Control).get_global_rect().intersects(orect):
				_fails += 1
				print("FAIL [%s] card %s overlaps %s" % [
					tag, holder2.get_meta("card_id"), zone[0]])
				break

## The same three guards against the hand REAL PLAY reaches, which is not the hand
## combat deals.
##
## `Balance.HAND_SIZE` is 5 and every measurement above was taken at five, but
## nothing holds the hand there: Keen Lens draws one more every turn, Scholar's Lens
## draws two more on every third turn, and eleven cards in the catalogue draw on
## play. The fan's step is `min(card * FAN_OVERLAP, (room - card) / (n - 1))`, so
## each additional card takes width away from the one before it — a large hand is
## precisely where the name fitter is most likely to fail, and until now it had never
## been measured at anything but five.
##
## The size is not picked, it is added up out of content that exists:
##     5   Balance.HAND_SIZE
##    +1   Keen Lens — extra_draw 1, every turn
##    +2   Scholar's Lens — ON_TURN_START every 3rd turn, DRAW 2 (so: turn 3)
##    +4   a fused See It Coming — cost 0, Draw 3, and a common's draw budget of 1
##         buys it a level_cap of 2, so ONE fusion makes it Draw 4
##    -1   the card leaves the hand to be played
##   = 11, which is also about the ceiling a 13-card starter deck can hold up.
##
## Every card of that hand is dealt by the engine down the paths the game uses:
## relics owned in MetaState, a fresh Combat scene, two real End Turns, one real
## press on a card in hand. Assembling eleven widgets by hand would have been ten
## lines shorter and would have proved something about the test instead of the game.
func _check_large_hand() -> void:
	for rid in ["keen_lens", "scholars_lens"]:
		if not MetaState.add_relic(rid):
			_fails += 1; print("FAIL cannot grant %s to build a large hand" % rid)
	# In the collection the way FUSION leaves a levelled card: copies spent, one left.
	# The deck is built from the collection, so this card reaches the fight through
	# the same path as every other card in it.
	MetaState.collection["see_it_coming"] = {"count": 1, "level": 2}
	GameState.select_dungeon(Balance.DUNGEONS[0])
	GameState.enter_dungeon(_collection_deck())
	GameState.pending = {"type": GameState.NodeType.COMBAT}
	# A NEW fight, not the one just measured: `Combat._snapshot()` left that one in
	# `GameState.combat_state`, and combat resumes from that when it is there — which
	# would restore the `extra_draw` saved before the relics above were owned.
	GameState.combat_state = {}
	var scene := load("res://scenes/Combat.tscn") as PackedScene
	if scene == null:
		_fails += 1; print("FAIL cannot load Combat.tscn"); return
	var inst := scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	var eng = inst.eng
	if eng == null:
		_fails += 1; print("FAIL the large-hand fight has no engine"); return
	var sic: CardData = _find_card(eng, "see_it_coming")
	if sic == null:
		_fails += 1; print("FAIL the fused draw card is not in the run deck"); return

	# Turn 3, because that is the turn Scholar's Lens fires on. Driven through the
	# handler the End Turn button is wired to, so the hand is dealt by `start_turn()`
	# and laid out by `_refresh()` exactly as it is in play.
	for t in 2:
		# The enemies act in between and none of this is about surviving them: a dead
		# player routes to the defeat screen and there is no hand left to measure.
		# Topping the HP up is the arrangement; the hand is the subject.
		eng.player.hp = eng.player.max_hp
		if t == 1:
			_stack_draw(eng, sic)
		inst._on_end_turn()
		await get_tree().process_frame
		await get_tree().process_frame
	if eng.turn != 3:
		_fails += 1; print("FAIL two End Turns left the fight on turn %d" % eng.turn)
	if not (sic in eng.hand):
		_fails += 1; print("FAIL %s was stacked on the draw pile and not drawn" % sic.id)
	else:
		inst._on_card_pressed(sic)
		await get_tree().process_frame
		await get_tree().process_frame

	# What the arithmetic in the doc comment above claims, read back off the content
	# rather than restated as 11: if a relic is retuned or the card is renumbered this
	# says so, instead of silently measuring a smaller hand and passing.
	var want: int = Balance.HAND_SIZE + eng.extra_draw \
		+ _relic_draw(eng, "scholars_lens") + sic.eff_draw() - 1
	var cards := _hand_cards(inst)
	print("  large hand: %d cards (%d expected: %d dealt + %d relic draw + %d from %s)" % [
		cards.size(), want, Balance.HAND_SIZE, eng.extra_draw + _relic_draw(eng, "scholars_lens"),
		sic.eff_draw(), sic.name])
	if cards.size() < want:
		_fails += 1
		print("FAIL only %d cards in the large hand, expected %d — the size the rest of this check measures is not the size it claims" % [
			cards.size(), want])
	_check_fan(inst, cards, "a played-up hand of %d" % cards.size())
	# How the fan survives eleven cards, and now an assertion rather than a report.
	#
	# What this used to say: the step drops to 41.6px, so `fit_name` hands the name a
	# 24px slot, the fitter buys the fit with type size, and the names come out at
	# 7-9px against the 14px floor this suite puts under card text. Nothing clipped,
	# nothing covered — legally inside its slot and unreadable at arm's length. It
	# declined to assert on the grounds that the fix was a design change.
	#
	# It was, and D117 made it: below `UI.CARD_NAME_MIN_W` of name slot a resting card
	# shows its cost and its effect symbol instead of a name it cannot render legibly.
	# So the hand that produced the defect is the hand that has to show the swap. Both
	# directions are pinned — the dealt hand above must NOT swap, this one must — or the
	# threshold could drift to "always" or to "never" and nothing here would notice.
	var slots := ""
	for h in cards:
		slots += "%.0f " % float(h.get_meta("rest_w"))
	print("  name slots across a %d-card hand: %s(threshold %.0f)" % [
		cards.size(), slots, UITheme.px(UI.CARD_NAME_MIN_W)])
	print("  a played-up hand of %d: of the %d cards a neighbour overlaps, %d show a name and %d show cost+symbol" % [
		cards.size(), _named + _swapped, _named, _swapped])
	if _swapped == 0:
		_fails += 1
		print("FAIL every card in a %d-card hand still claims to show its name; at this step it renders too small to read" % cards.size())
	# The fan hands its TOPMOST card the whole face, so the switch has to be per card
	# and not per hand: the last card is never crowded and must keep its name however
	# many cards are in front of it.
	var last: Label = (cards[cards.size() - 1] as Control).get_meta("name_label")
	if last == null or not last.visible:
		_fails += 1
		print("FAIL the topmost card of a %d-card hand dropped its name, and nothing covers it" % cards.size())
	# Whatever names DO survive a crowded hand have to be worth reading, which is the
	# whole point of the swap: any card still showing one has the width for it. This is
	# what catches a threshold that drifts DOWNWARD without reaching "never" — set it
	# to 26px and most of this hand keeps a 7px name while a couple still swap, which
	# the count above would happily pass.
	var tiniest := 999
	for h in cards:
		var nm2: Label = h.get_meta("name_label")
		if nm2 != null and nm2.visible:
			tiniest = mini(tiniest, nm2.get_theme_font_size("font_size"))
	print("  smallest resting card NAME in a %d-card hand: %s" % [cards.size(),
		"none — every card swapped" if tiniest == 999 else "%dpx" % tiniest])
	if tiniest != 999 and tiniest < 14:
		_fails += 1
		print("FAIL a card in a %d-card hand still shows a %dpx name — below the floor the swap exists to keep" % [
			cards.size(), tiniest])
	# The swap is a RESTING decision, and this is the sentence that says so: opening a
	# card in the most crowded hand the game can deal must put the name back and take
	# the substitute away, because a lifted card is clear of its neighbours and short of
	# nothing. Driven through the card's own hover wiring, on a card the fan crowded.
	var mid: Control = cards[cards.size() / 2]
	var mid_btn: Button = null
	for ch in mid.get_children():
		if ch is Button:
			mid_btn = ch
	if mid_btn == null:
		_fails += 1; print("FAIL no button to hover on the middle card of a large hand")
	else:
		var nm3: Label = mid.get_meta("name_label")
		var sym3: TextureRect = mid.get_meta("crowd_symbol", null)
		if nm3 != null and nm3.visible:
			_fails += 1
			print("FAIL the middle card of a %d-card hand was not crowded, so hovering it proves nothing" % cards.size())
		mid_btn.mouse_entered.emit()
		await get_tree().process_frame
		if nm3 == null or not nm3.visible:
			_fails += 1
			print("FAIL hovering %s in a %d-card hand still hides its name" % [
				mid.get_meta("card_id"), cards.size()])
		elif nm3.get_theme_font_size("font_size") < 14:
			_fails += 1
			print("FAIL hovering %s gives its name back at only %dpx" % [
				mid.get_meta("card_id"), nm3.get_theme_font_size("font_size")])
		if sym3 != null and sym3.visible:
			_fails += 1
			print("FAIL the opened %s shows the crowded symbol over its name strip as well" % mid.get_meta("card_id"))
		mid_btn.mouse_exited.emit()
		await get_tree().process_frame
		# ...and back again, or the hand would be readable exactly once
		if nm3 != null and nm3.visible:
			_fails += 1
			print("FAIL %s kept its name after the mouse left a %d-card hand" % [
				mid.get_meta("card_id"), cards.size()])
	inst.queue_free()
	await get_tree().process_frame

## The run deck the collection makes, at the levels the collection holds — the same
## thing the deck builder hands to a run.
func _collection_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in MetaState.collection:
		var entry: Dictionary = MetaState.collection[id]
		for i in int(entry["count"]):
			var c := (load(MetaState.CATALOG[id]) as CardData).duplicate()
			c.level = int(entry["level"])
			deck.append(c)
	return deck

func _find_card(eng, id: String) -> CardData:
	for pile in [eng.draw_pile, eng.hand, eng.discard_pile]:
		for c in pile:
			if c.id == id:
				return c
	return null

## Put a card the deck already contains on top of the draw pile, so the next draw
## takes it. `CombatEngine.draw_cards` pops from the BACK, so the top is the end.
##
## This fixes the ORDER a shuffle could have dealt anyway; it never adds a card the
## player does not hold. Waiting for the shuffle to volunteer the one card the
## measurement needs would make the suite flaky instead of honest.
func _stack_draw(eng, card: CardData) -> void:
	for pile in [eng.draw_pile, eng.hand, eng.discard_pile]:
		pile.erase(card)
	eng.draw_pile.push_back(card)

## What a triggered relic's DRAW effect is worth per firing, read off the relic.
func _relic_draw(eng, id: String) -> int:
	for r in eng.relics:
		if r == null or r.id != id:
			continue
		for i in r.trigger_count():
			if r.effect[i] == RelicData.Effect.DRAW:
				return int(r.effect_value[i])
	return 0

## The hand as the FAN sees it: the widget for each card, in `eng.hand` order.
##
## Not `_cards()`, which walks the tree. Tree order is creation order, and the two
## stop agreeing the moment a card is played — the played card's widget is still in
## the tree (flying out on `fx_layer`) and the cards drawn to replace it are appended
## at the end. Measuring "the next card along" against that order would compare
## neighbours that are not neighbours.
func _hand_cards(inst: Node) -> Array[Control]:
	var out: Array[Control] = []
	for card in inst.eng.hand:
		var holder: Control = inst.card_widgets.get(card)
		if holder != null and is_instance_valid(holder):
			out.append(holder)
	return out

## Two distinct failures, both of which read as "I cannot see the text":
## the label clips (fewer lines drawn than the text needs), or the label is drawn
## outside the card frame it belongs to. The original bug was the first; raising the
## font to fix it silently produces the second.
##
## Measured in LOCAL coordinates. A hovered card is scaled, and global rects mix a
## scaled position with an unscaled size, which reports overflow that is not there.
func _measure(holder: Control, tag: String) -> void:
	var frame := Rect2(Vector2.ZERO, holder.size)
	for l in _labels(holder):
		if l.text == "" or not l.visible:
			continue
		if l.get_visible_line_count() < l.get_line_count():
			_fails += 1
			print("FAIL clipped [%s] %d of %d lines at %dpx: %s" % [
				tag, l.get_visible_line_count(), l.get_line_count(),
				l.get_theme_font_size("font_size"), l.text])
		var r := l.get_rect()
		if r.position.x < frame.position.x - 1.0 or r.position.y < frame.position.y - 1.0 \
				or r.end.x > frame.end.x + 1.0 or r.end.y > frame.end.y + 1.0:
			_fails += 1
			print("FAIL overflows card [%s] label %s vs card %s: %s" % [
				tag, r, frame, l.text])

## Drive the card's own hover handler, so the test exercises the shipped wiring
## rather than a reimplementation of it.
func _hover(holder: Control, open: bool) -> void:
	var cb: Callable = holder.get_meta("show_all")
	cb.call(open)

## What the card actually puts on its face. Generated from the effective numbers,
## not the authored `description`, which is baked at level 1 and lied about any
## fused card — see tests/test_card_truth.gd.
func card_desc(id: String) -> String:
	var c := load(MetaState.CATALOG[id]) as CardData
	return c.effect_text() if c != null else ""

func _cards(n: Node) -> Array[Control]:
	var out: Array[Control] = []
	if n is Control and (n as Control).has_meta("card_id"):
		out.append(n as Control)
	for c in n.get_children():
		out.append_array(_cards(c))
	return out

func _labels(n: Node) -> Array[Label]:
	var out: Array[Label] = []
	if n is Label:
		out.append(n as Label)
	for c in n.get_children():
		out.append_array(_labels(c))
	return out

func _purge() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
