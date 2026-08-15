## The three powers a run is offered, on the way down (D253).
##
## The choice used to be a row of buttons in the deck builder, beside the card list. That put the
## biggest decision of the run's opening on the busiest screen in the game, next to a hundred cards
## and a filter bar, in a panel three rows tall — and it made the screen's own job ambiguous, because
## the deck builder is also where you go mid-run to look at what you are holding (D252).
##
## So it is its own screen, and it is the last thing between the door and the floor. One question,
## three answers, nothing else on it.
##
## The powers are drawn as ROUND SIGILS, the same shape and the same art the fight puts in the corner
## of the screen — `combat.gd` builds one orb out of a 999-radius ring and a `PixelArt.power_art`
## texture inset inside it, and this builds three. A player choosing between three circles here meets
## the same circle every turn afterwards, which is the cheapest kind of teaching there is.
extends Control

## Circle diameter. Larger than the fight's 112px orb because these are being COMPARED rather than
## pressed by muscle memory, and because a sigil at 112 with a name under it reads as a toolbar.
const ORB := 168.0
## Art inset inside the ring, in the same proportion `combat.gd` uses: art taken to the full rect of
## a 999-radius corner is clipped at four points, and a sigil with its edges bitten off reads as a
## rendering fault rather than as a round icon.
const ORB_INSET := 21.0

func _ready() -> void:
	# The dungeon's OWN backdrop, handed to `UI.screen` as its `scene` rather than painted first.
	# Calling `scene_backdrop` before it did nothing visible: `UI.screen` paints a backdrop of its
	# own, and with no scene key it falls through to the tiling pattern — which then covered the
	# painting underneath it. **A backdrop applied before the thing that also applies backdrops is a
	# backdrop nobody sees**, and it looked exactly like a missing file.
	#
	# `reliquary` is the fallback — a room where things are kept — for a dungeon whose plate is not
	# painted, and `UI.screen` falls through to the tiling pattern if that is missing too.
	var dd := GameState.dungeon_data()
	var scene_key := GameState.dungeon_id
	if scene_key == "" or PixelArt.scene_art(scene_key) == null:
		scene_key = "reliquary"
	var col := UI.screen(self, "What will you carry?", "", scene_key)
	UI.label(col, "One ability, fired once a turn, every turn. It is yours for %s and no longer." % [
		dd.name if dd != null else "this run"])
	# A spacer on BOTH sides of the row, which is what centres it. `UI.spacer` is
	# SIZE_EXPAND_FILL, so one of them does not centre anything — it pushes everything after it to
	# the bottom, which is exactly where the first version of this screen put the circles.
	UI.spacer(col)

	var offer: Array = GameState.power_offer
	if offer.is_empty():
		# A save deep enough to have opened nothing is not a state the game can reach — `power_offer`
		# falls back to everything unlocked, and Bulwark is open at zero clears — but a screen with no
		# way out of it is a softlock, and this one is on the only path into a dungeon.
		UI.label(col, "Nothing is open to you yet. You go down as you are.")
		UI.spacer(col)
		UI.button(col, "Go down", _confirm.bind(""), 44.0)
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep(12))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for pid in offer:
		var p := Balance.power(String(pid))
		if p == null:
			continue
		p = p.duplicate()
		p.level = int(MetaState.powers.get(String(pid), 1))
		row.add_child(_orb(String(pid), p))
	UI.spacer(col)

func _orb(pid: String, p: PowerData) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", UITheme.sep(6))
	cell.custom_minimum_size.x = UITheme.px(230)

	# ONE node, not a stack of anchored ones. The first version built the ring, the sigil and the
	# button as three siblings inside a plain `Control` with FULL_RECT anchors — the shape
	# `combat.gd` uses — and the ring drew while the sigil did not, on a screen where the texture
	# was provably loading. A Button carries its own StyleBox and its own icon and lays both out
	# itself, so there is no anchor arithmetic left to be wrong about.
	#
	# `expand_icon` is what makes it fill: without it a 128px sigil sits at 128px in the middle of a
	# 168px circle regardless of the button's size.
	var btn := Button.new()
	var d := UITheme.px(ORB)
	btn.custom_minimum_size = Vector2(d, d)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	# The painted sigil when one is installed, the procedural glyph when it is not — the same
	# fallback `powers_screen.gd` and the relics screen run on (D121, D122). Twenty of the thirty
	# powers have no painting yet (D250), and the first version of this screen fell back to a drawn
	# LETTER instead, which threw away a working icon the rest of the game already draws.
	var painted := PixelArt.power_art(pid)
	btn.icon = painted if painted != null else Icons.tex(Icons.for_card(p))
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, _ring(state == "hover" or state == "pressed"))
	btn.pressed.connect(_confirm.bind(pid))
	UI.hoverable(btn, "%s\n%s\nCosts %s, once per turn.%s" % [
		p.name, p.effect_text(),
		"nothing" if p.eff_cost() == 0 else "%d Energy" % p.eff_cost(),
		"" if MetaState.powers.has(pid) else "\nYou have never carried this one."])
	cell.add_child(btn)

	# The caption sits on a PLATE, not straight on the painting. D123's rule, and the capture is what
	# found it: over the Maw's plate the third column's "Draw 1." and "free" landed on the bright
	# mouth of the cave and stopped being readable, while the same text over the first column was
	# fine. **Translucent text reads against the backdrop, not against the colour you chose** — so
	# the fix is ink on its own ground rather than a lighter font.
	var plate := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.06, 0.05, 0.09, 0.78)
	psb.set_corner_radius_all(int(UITheme.px(8)))
	psb.content_margin_left = UITheme.px(10)
	psb.content_margin_right = UITheme.px(10)
	psb.content_margin_top = UITheme.px(6)
	psb.content_margin_bottom = UITheme.px(6)
	plate.add_theme_stylebox_override("panel", psb)
	cell.add_child(plate)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", UITheme.sep(4))
	plate.add_child(text)

	var name_lbl := UI.label(text, "%s  Lv%d" % [p.name, p.level])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var eff := UI.label(text, p.effect_text())
	eff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.add_theme_color_override("font_color", Color(0.92, 0.87, 0.68))
	var cost := UI.label(text, "free" if p.eff_cost() == 0 else "%d Energy" % p.eff_cost())
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color", Color(0.80, 0.78, 0.70))
	return cell

## The circle itself: a 999-radius StyleBox, the same shape the fight puts in the corner of the
## screen. Brighter on hover, because the whole circle is the target and it has to say so.
func _ring(lit: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.12, 0.19, 0.92) if lit else Color(0.10, 0.09, 0.14, 0.88)
	sb.border_color = Color(1.0, 0.86, 0.50, 1.0) if lit else Color(0.86, 0.72, 0.38, 0.85)
	sb.set_border_width_all(4 if lit else 3)
	sb.corner_radius_top_left = 999
	sb.corner_radius_top_right = 999
	sb.corner_radius_bottom_left = 999
	sb.corner_radius_bottom_right = 999
	# Keeps the sigil off the rim: `expand_icon` fills the whole content box, and a 999-radius
	# corner bites the four corners of anything taken to its edge.
	var pad := int(UITheme.px(ORB_INSET))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

## Take one and go down.
##
## No Escape and no way back. The stake is already spent and the floor is already generated — the run
## began at the deck builder's own button (D211) — so a way out of this screen would be a way to hold
## a run open with no power in it. It is the one screen in the game that owes an answer, which is the
## rule the event screen follows for the same reason.
func _confirm(pid: String) -> void:
	GameState.set_run_power(pid)
	GameState.flush_save()
	Audio.play("enter")
	get_tree().change_scene_to_file(GameState.run_scene())
