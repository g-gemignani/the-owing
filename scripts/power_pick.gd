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
	# The dungeon's OWN backdrop. This screen is the threshold of a specific place, so the place is
	# what belongs behind it — and it costs no new art, which matters because 20 of the 30 powers do
	# not have a sigil yet (D253). `reliquary` is the fallback: a room where things are kept.
	if not UI.scene_backdrop(self, GameState.dungeon_id):
		UI.scene_backdrop(self, "reliquary")

	var dd := GameState.dungeon_data()
	var col := UI.screen(self, "What will you carry?",
		"", "", false, "", false)
	UI.label(col, "One ability, fired once a turn, every turn. It is yours for %s and no longer." % [
		dd.name if dd != null else "this run"])
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

func _orb(pid: String, p: PowerData) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", UITheme.sep(6))
	cell.custom_minimum_size.x = UITheme.px(230)

	var holder := Control.new()
	var d := UITheme.px(ORB)
	holder.custom_minimum_size = Vector2(d, d)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.add_child(holder)

	# The ring, copied in shape from the fight's orb so the two read as the same object.
	var ring := Panel.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.10, 0.09, 0.14, 0.88)
	rsb.border_color = Color(0.86, 0.72, 0.38, 0.85)
	rsb.set_border_width_all(3)
	rsb.corner_radius_top_left = 999
	rsb.corner_radius_top_right = 999
	rsb.corner_radius_bottom_left = 999
	rsb.corner_radius_bottom_right = 999
	ring.add_theme_stylebox_override("panel", rsb)
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ring)

	var sigil := PixelArt.power_art(pid)
	if sigil != null:
		var art := TextureRect.new()
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var inset := UITheme.px(ORB_INSET)
		art.offset_left = inset
		art.offset_top = inset
		art.offset_right = -inset
		art.offset_bottom = -inset
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(art)
	else:
		# Twenty of the thirty powers have no sigil yet (D250 added them, the art did not follow), and
		# an empty ring is a rendering fault to look at. The initial is a placeholder that reads as
		# deliberate — and it is DERIVED from the name, so a sigil arriving later needs no edit here.
		var letter := Label.new()
		letter.set_anchors_preset(Control.PRESET_FULL_RECT)
		letter.text = p.name.substr(0, 1).to_upper()
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override("font_size", int(UITheme.px(ORB) * 0.42))
		letter.add_theme_color_override("font_color", Color(0.86, 0.72, 0.38, 0.9))
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(letter)

	# The whole circle is the button, flat and over the art, so the target is the thing being looked
	# at rather than a bar underneath it (D205b).
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(_confirm.bind(pid))
	UI.hoverable(btn, "%s\n%s\nCosts %s, once per turn.%s" % [
		p.name, p.effect_text(),
		"nothing" if p.eff_cost() == 0 else "%d Energy" % p.eff_cost(),
		"" if MetaState.powers.has(pid) else "\nYou have never carried this one."])
	holder.add_child(btn)

	var name_lbl := UI.label(cell, "%s  Lv%d" % [p.name, p.level])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var eff := UI.label(cell, p.effect_text())
	eff.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	eff.add_theme_color_override("font_color", Color(0.85, 0.80, 0.62))
	var cost := UI.label(cell, "free" if p.eff_cost() == 0 else "%d Energy" % p.eff_cost())
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_color_override("font_color", Color(0.70, 0.68, 0.60))
	return cell

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
