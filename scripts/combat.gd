## Combat screen — thin UI over CombatEngine (all rules live in the engine,
## all numbers in Balance). Reads the run from GameState, writes rewards to
## MetaState, then routes back to the map / deck builder.
extends Control

const CARD_DIR := "res://resources/cards/"
## Fallback pool when a dungeon defines none (D6: dungeons own their card pools).
const DEFAULT_POOL := ["hack", "cover", "stave_in", "shoulder", "clear_mind",
	"put_the_fear", "work_up", "light_on_it", "set_stone"]

var eng: CombatEngine
var tier: int = Balance.Tier.NORMAL

## The vitals that still have to be *read*: Block, the telegraphed hit, and — on the
## way out of a fight — the reward or defeat line. HP and Energy moved onto art in
## D116; this label is what says whatever the art cannot, which includes HP itself
## when `ui/bar_frame.png` is not on disk. It is also the anchor the player's own
## floating numbers rise from, so it must stay visible and laid out.
var status_label: Label
## What has no PAINTING, and nothing else. The statuses themselves are chips now
## (`buff_row`, D117); this label is what a missing `ui/sym_*.png` falls back into,
## which is the same contract every other piece of the kit has.
var buffs_label: Label
## The player's statuses as icon+number chips. Built once with every chip it can ever
## need; see `_build_chip_row`.
var buff_row: HBoxContainer
var piles_label: Label

## --- the painted vitals (D116) -----------------------------------------------
##
## Every one of these is null when its file is missing, and every null puts the
## number back in `status_label`. That is the contract `PixelArt.ui_kit` was built
## for and it is why the kit has been able to land one file at a time: a
## half-installed vitals block is still a readable vitals block, never a blank one.
var hp_bar: Control            ## the `bar_frame` housing, or null with no art
var hp_fill: TextureRect       ## what you have
var hp_loss: TextureRect       ## the slice the enemy has already promised to take
var block_fill: TextureRect    ## Block, stacked over the HP it stands in front of
var hp_number: Label           ## "42/60", ON the bar
var orb_row: HBoxContainer     ## one orb per point of energy; always built
var orb_full_tex: Texture2D
var orb_empty_tex: Texture2D
var orb_glow_tex: Texture2D
var energy_number: Label
## What the orbs last drew. Kept so a change can be *flashed* rather than just
## redrawn, and initialised to -1 so the first draw of a fight is silent.
var shown_energy: int = -1
## The stage: full-rect, enemies placed on the backdrop's floor line.
var enemy_box: Control
## Rebuild slot positions only when the living count changes, so a hit-shake tween
## is not fought by the next refresh snapping the slot back.
var slot_count: int = -1
## A Control, not an HBoxContainer: the hand is a fan, placed by `_place_hand()`.
## Leaving the old type here assigned a Control to an HBoxContainer variable, which
## GDScript rejects at RUNTIME — so `test_compile` passed, `hand_box` stayed null,
## every card silently failed to be added, and the fight rendered with no hand at
## all. Third time a stale restatement has done this (D34, D49).
var hand_box: Control
var log_label: Label
## The last few things that happened. One overwritten line lost most of a turn:
## three enemies acting reported only the third.
var log_lines: Array[String] = []
## Persistent widgets, built once and mutated. See `_refresh_enemies`.
var enemy_plates: Array = []
var card_widgets: Dictionary = {}
## Kit textures already resampled to a size they are DRAWN at. See `_kit_at`.
var kit_scaled: Dictionary = {}
## Where floating numbers and flashes are drawn: on top of everything, deaf to the
## mouse, and never a parent of anything the game logic reads.
var fx_layer: Control
## The room's own five-stop ramp, handed to every effect so what is drawn over the
## backdrop is lit like it (`Fx.palette`). Read once while the scene loads: sampling a
## painting costs ~45ms, which is nothing during a transition and a visible hitch if it
## happened on the first hit of the fight instead.
var fx_ramp: Array = []
var hurt_veil: ColorRect
var reward_box: VBoxContainer
var end_btn: Button
var power_btn: Button
var menu_btn: Button
var place_label: Label
var power_ring: Panel
var power_art: TextureRect
var power_fx: TextureRect
var power_cost: Label
## The two bottom corners the hand has to stay out of. Kept as members so the fan
## can measure them instead of guessing: a hardcoded reserve was wrong the moment a
## Label's BOX turned out wider than its text, and would be wrong again at any other
## UI scale.
var hud_box: VBoxContainer
var controls_box: HBoxContainer

func _ready() -> void:
	tier = _tier_of(GameState.pending.get("type", GameState.NodeType.COMBAT))
	fx_ramp = Fx.palette(GameState.dungeon_id)
	_build_ui()
	eng = CombatEngine.new()
	if not GameState.combat_state.is_empty():
		# resuming a fight the player quit out of: restored exactly, so quitting is
		# never a way to retry a bad turn (D22)
		eng.load_state(GameState.combat_state, MetaState.CATALOG, MetaState.relic_data())
	else:
		var dd := GameState.dungeon_data()
		var roster: Array = Array(dd.enemy_roster) if dd != null and dd.has_roster() else []
		# A traversal may already have decided WHICH creature this is — the iso model does,
		# at generation time, so that the thing standing on the tile is the thing you
		# fight (D85). `forced_archetype` is the parameter that has always existed for
		# this; before now the run path passed "" and let combat roll, which is why the
		# floor could show a spider and hand over a brute. Models that do not cast their
		# fights simply omit the key and nothing changes for them.
		eng.setup(GameState.run_deck, GameState.hp, GameState.max_hp, GameState.dungeon, tier,
			String(GameState.pending.get("enemy", "")), MetaState.relic_data(), roster,
			GameState.run_power, dd.boss if dd != null else "")
		_snapshot()
	_refresh()
	# rects only exist after a frame, and the fan is measured against them
	call_deferred("_place_hand")

## Persist the fight in progress. Called after every action that changes it.
func _snapshot() -> void:
	if eng != null and not eng.over():
		GameState.combat_state = eng.save_state()
	else:
		GameState.combat_state = {}
	GameState.autosave()

## Step out of the fight. Written to disk first, because the pause menu can quit
## to the title from here and an unflushed turn would be a free retry.
func _pause() -> void:
	_snapshot()
	GameState.flush_save()
	UI.goto(self, "res://scenes/PauseMenu.tscn")

## Between the killing blow and the reward pick the encounter is NOT resolved yet,
## so leaving and coming back would offer the same fight again. The exit closes
## for those few seconds — Escape included, since it runs the same Callable.
func _seal_exit() -> void:
	menu_btn.disabled = true
	UI.clear_escape(self)

## "The Crypt — Elite" / "— BOSS". Nothing for an ordinary fight: most encounters
## are ordinary, and labelling them says less than saying nothing.
func _tier_suffix() -> String:
	match tier:
		Balance.Tier.ELITE: return "  —  Elite"
		Balance.Tier.BOSS: return "  —  BOSS"
		_: return ""

func _tier_of(node_type: int) -> int:
	match node_type:
		GameState.NodeType.ELITE: return Balance.Tier.ELITE
		GameState.NodeType.BOSS: return Balance.Tier.BOSS
		_: return Balance.Tier.NORMAL

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# the place you are fighting in, behind everything and deaf to the mouse
	var zone := Balance.zone_of(GameState.dungeon_id)
	add_child(PixelArt.battle_backdrop(GameState.dungeon_id,
		zone.id if zone != null else Balance.ZONES[0]))
	# --- the stage -----------------------------------------------------------
	#
	# The fight is framed head-on into the corridor the backdrop paints, with no
	# player character rendered: the room belongs to the enemies and the frame
	# belongs to you. So the enemies are NOT a row in a stacked layout — they are
	# placed on the backdrop's own floor (PixelArt.STAND_LINE), full width,
	# with the HUD and the hand floating over them.
	#
	# Measured before building it: stacked as rows, the layout had 236px of height
	# left for a sprite that wants 240-270, and its stage ended 22px ABOVE the
	# painted floor. Layering is what makes the framing fit at all.
	enemy_box = Control.new()
	enemy_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	enemy_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(enemy_box)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(10))
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(root)

	# --- top band: where you are, and the way out ----------------------------
	#
	# The fight is serialized after every action, so leaving it is a pause, not an
	# escape: Resume comes straight back into this turn. Until this existed the
	# longest scene in the game was the only one with no way out of it at all.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.sep(12))
	root.add_child(header)

	place_label = Label.new()
	# the dungeon's name is a heading, so it takes the display face like every other
	# heading (D129). The other two labels on this screen at title SIZE deliberately do
	# not: `status_label` is running prose ("Encounter cleared. +12 gold...") and
	# `_float_number` is a numeral, and an inscriptional serif reads as decoration on
	# both — size is not what makes a heading.
	UITheme.style_title(place_label)
	place_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dd0 := GameState.dungeon_data()
	place_label.text = "%s%s" % [dd0.name if dd0 != null else "The dark", _tier_suffix()]
	header.add_child(place_label)

	menu_btn = UI.exit_button(header, "Menu", _pause, 38.0)

	# --- bottom left: everything about YOU -----------------------------------
	#
	# Back down here beside the hand, deliberately. Energy gates every click a turn
	# contains and HP is what every decision is spent against, so both belong where
	# the eye already is while cards are being read — not in a corner you look at
	# once. (This was at the top for one iteration. It reads better here.)
	# Anchored with explicit offsets, not PRESET_BOTTOM_LEFT: that preset puts the
	# box's TOP edge on the bottom of the screen, so the whole HUD rendered below the
	# frame — visible only because the layout was rendered and looked at.
	var hud := VBoxContainer.new()
	hud_box = hud
	hud.add_theme_constant_override("separation", UITheme.sep(4))
	add_child(hud)
	hud.anchor_left = 0.0
	hud.anchor_right = 0.0
	hud.anchor_top = 1.0
	hud.anchor_bottom = 1.0
	hud.offset_left = UITheme.px(16)
	# 330, not 348, and the number is the CAP the two wrapped labels inside already
	# carry rather than one picked with slack on top of it. Measured: with every status
	# up and two digits on each of them, this box's combined minimum is exactly 330 —
	# `status_label` and `log_label`, both of which clamp themselves there — so the 18px
	# it used to hold was reserved for nothing. It is worth taking because it is not
	# free width, it is the HAND's width: `_place_hand` measures the fan's left reserve
	# off this rect's right edge, and the fan is down to a 41.6px step at eleven cards
	# with names rendering at 7-9px (D116). 18px of room is +1.8px of step per card
	# there, and it costs nothing but the slack.
	hud.offset_right = UITheme.px(16) + UITheme.px(330)
	# Tall enough for the painted vitals, and bottom-aligned so it does not matter
	# whether it is. A VBox whose children out-measure its rect overflows past the
	# BOTTOM edge, which here is 10px from the bottom of the frame — so the old
	# top-aligned box was one extra line of log away from pushing the log off screen,
	# and growing it for the bar would only have moved that cliff. ALIGNMENT_END makes
	# the block grow UPWARDS into the empty middle of the frame instead, where there is
	# nothing to hit. The width above is the one thing here the hand feels, which is why
	# it is measured rather than chosen.
	hud.alignment = BoxContainer.ALIGNMENT_END
	hud.offset_top = -UITheme.px(228)
	hud.offset_bottom = -UITheme.px(10)

	# HP as a bar with the enemy's telegraphed damage marked on it, before the line
	# that carries the numbers the bar cannot say.
	_build_hp_bar(hud)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	# wrapped inside a known width: as one line it measured ~530px at title size and
	# ran straight under the leftmost card, which no box could prevent because a
	# Label overflows rather than clips
	status_label.custom_minimum_size.x = UITheme.px(330)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(status_label)
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what would actually land after Block.")

	# Energy as orbs, under the line it used to be a fragment of.
	_build_orbs(hud)

	# Buffs and debuffs under the vitals they modify — as a row of chips, because
	# spelling them out was a paragraph (see `_refresh_buffs`). They were a
	# "[Blk 5 Str 3]" fragment inside a run-on line before that, which is not where
	# anybody looks for the reason their damage changed.
	buff_row = _build_chip_row(hud, PLAYER_CHIP_SKIP)
	buffs_label = Label.new()
	buffs_label.add_theme_color_override("font_color", CHIP_GOOD)
	# Wrapped inside the same known width as the two lines above it. Without this the
	# fallback prose sets its own width and drags `hud_box` out from under the hand,
	# which is the bug `_refresh_buffs` documents — and a fallback is exactly the path
	# nobody looks at, so it has to be laid out rather than trusted.
	buffs_label.custom_minimum_size.x = UITheme.px(330)
	buffs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(buffs_label)

	# What is left to draw, and what has gone by. The reward screen quotes how often
	# you will see a card and the shop sells thinning, so the fight has to show the
	# piles those numbers are about.
	piles_label = Label.new()
	piles_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72))
	hud.add_child(piles_label)
	UI.hoverable(piles_label, "Your deck is drawn through, then the discard pile is shuffled back. A smaller deck comes round faster.")

	# Two lines, low and quiet: four lines of running commentary across a painted
	# corridor is what would ruin the framing.
	log_label = Label.new()
	log_lines = ["Combat start."]
	log_label.text = log_lines[0]
	log_label.custom_minimum_size.x = UITheme.px(330)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_color_override("font_color", Color(0.84, 0.82, 0.78))
	hud.add_child(log_label)

	# --- bottom right: the two things you press ------------------------------
	var controls := HBoxContainer.new()
	controls_box = controls
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.add_theme_constant_override("separation", UITheme.sep(10))
	add_child(controls)
	controls.anchor_left = 1.0
	controls.anchor_right = 1.0
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = -(UITheme.px(16) + UITheme.px(282))
	controls.offset_right = -UITheme.px(16)
	controls.offset_top = -UITheme.px(128)
	controls.offset_bottom = -UITheme.px(10)

	# The power as a round sigil rather than a wide bar: it is one always-available
	# ability with a cost, which is a Hearthstone hero power, not a menu entry. A
	# 260px bar next to an equally wide End Turn was eating the frame the fight is
	# supposed to be in.
	var orb := Control.new()
	var od := UITheme.px(112)
	orb.custom_minimum_size = Vector2(od, od)
	controls.add_child(orb)
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
	orb.add_child(ring)
	# The sigil goes UNDER the button, not on it. A Button's `icon` is laid out against
	# its text and would fight the cost for the same box; a TextureRect behind a flat
	# button lets the picture own the orb and the numeral sit on top of it.
	#
	# Inset, because the ring is a 3px border on a 999-radius corner: art taken to the
	# full rect corners gets clipped by the circle at four points, and a sigil with its
	# edges bitten off reads as a rendering fault rather than as a round icon.
	power_art = TextureRect.new()
	power_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := UITheme.px(POWER_ART_INSET)
	power_art.offset_left = inset
	power_art.offset_top = inset
	power_art.offset_right = -inset
	power_art.offset_bottom = -inset
	power_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	power_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	power_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_child(power_art)

	# The level-progress glow, on the same rect as the sigil and added rather than blended
	# so its black is invisible (D132). Its own node instead of a modulate on the sigil,
	# because the two dim independently: a spent power fades, its progress does not change.
	power_fx = TextureRect.new()
	power_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	power_fx.offset_left = inset
	power_fx.offset_top = inset
	power_fx.offset_right = -inset
	power_fx.offset_bottom = -inset
	power_fx.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	power_fx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	power_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var power_blend := CanvasItemMaterial.new()
	power_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	power_fx.material = power_blend
	orb.add_child(power_fx)

	power_btn = Button.new()
	power_btn.flat = true
	power_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	power_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_btn.add_theme_font_size_override("font_size", int(UITheme.font() * 0.85))
	power_btn.pressed.connect(_on_power_pressed)
	orb.add_child(power_btn)

	# The cost is its own Label rather than the Button's text, because a Button has no
	# vertical text alignment — only `alignment` (horizontal) and `vertical_icon_
	# alignment`, which moves the ICON and left "1E" sitting across the middle of the
	# shield. Anchored to the bottom of the orb, it sits over the ring's dark rim
	# instead of over the emblem's face.
	power_cost = Label.new()
	power_cost.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	power_cost.offset_top = -UITheme.px(POWER_COST_BAND)
	power_cost.offset_bottom = -UITheme.px(6)
	power_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	power_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Outlined, not boxed: the sigils are ten different colours and a numeral that only
	# works on the dark ones is a numeral that fails on Scythe and Foresight. An outline
	# reads on any of them without putting a plate over the art (D96's rule, applied to
	# ink rather than to a scrim).
	power_cost.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.07, 0.95))
	power_cost.add_theme_constant_override("outline_size", 6)
	orb.add_child(power_cost)
	power_ring = ring

	# End Turn is pressed once a turn and never in a hurry. A corner button.
	end_btn = Button.new()
	UITheme.style_button(end_btn)
	end_btn.text = "End Turn"
	end_btn.custom_minimum_size = Vector2(UITheme.px(150), UITheme.button_height(38))
	end_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	end_btn.pressed.connect(_on_end_turn)
	controls.add_child(end_btn)

	# --- the hand: a fan along the bottom edge -------------------------------
	#
	# A Control, not an HBox: the cards are placed and rotated by hand so the hand
	# reads as a hand. `_place_hand()` owns the arc, and `UI.card_button` lifts and
	# straightens whichever card is hovered.
	hand_box = Control.new()
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hand_box)
	hand_box.anchor_left = 0.0
	hand_box.anchor_right = 1.0
	hand_box.anchor_top = 1.0
	hand_box.anchor_bottom = 1.0
	hand_box.offset_top = -(UITheme.card_size().y * HAND_PEEK + UITheme.px(FAN_ARC))
	hand_box.offset_bottom = 0.0

	reward_box = VBoxContainer.new()
	reward_box.add_theme_constant_override("separation", UITheme.sep())
	reward_box.visible = false
	add_child(reward_box)
	reward_box.anchor_left = 0.12
	reward_box.anchor_right = 0.88
	reward_box.anchor_top = 0.30
	reward_box.anchor_bottom = 0.86

	# Feedback lives above the layout and outside it: a floating number must not
	# resize a container, and nothing here may ever eat a click meant for a card.
	hurt_veil = ColorRect.new()
	hurt_veil.color = Color(0.7, 0.05, 0.05, 0.0)
	hurt_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hurt_veil)
	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)

# --- the painted vitals (D116) -------------------------------------------------
#
# HP, Block and Energy were three fragments of a four-number text block in the
# bottom-left corner. They are the numbers every card in hand is spent against, and
# reading them meant reading a sentence. Now HP and Block are a bar and Energy is a
# row of orbs — with the numerals kept, because this game's combat read is
# arithmetic and a bar you cannot subtract from is decoration.
#
# Where the numerals ended up, and why:
#   HP        on the bar, centred, because it is the bar's own quantity.
#   Block     in `status_label`, because the band is ten pixels tall and no numeral
#             fits on it — and because Block is the number you compare AGAINST incoming.
#   incoming  in `status_label`, beside Block, for the same comparison. The bar shows
#             it as a slice; the line says how big it is.
#   Energy    beside the orbs. Unary is exact up to about six, but energy is the one
#             number you actively subtract card costs from all turn, so it is written.
#
# `Draw / Discard / Hand` stay text: bookkeeping, not something you do arithmetic on
# under pressure.

## The bar housing is drawn at its art's own size. `ui/bar_frame.png` is 256x48 with a
## 10px border, so at 1:1 the nine-slice never stretches and the trough inside it is
## exactly 236px wide. Height is 44 rather than 48 to buy the block back for the log —
## the middle row is what gives, and the border keeps its 10px.
const BAR_SIZE := Vector2(256, 44)
## The nine-slice margin, in TEXTURE pixels, matching `gen_ui_kit.gd` BAR_BORDER.
## Deliberately not scaled, for the reason UITheme's button slices are not: slice
## margins index into the art, and scaling them slices the border in the wrong place.
const BAR_BORDER := 10.0
## How much of the trough Block occupies, stacked on top of the HP it stands in front
## of. A band, not a full-height segment: full height would hide the loss slice it is
## supposed to be shrinking.
const BLOCK_BAND := 0.44

## HP as a bar, or nothing at all. `UITheme.kit_frame` returns null when the file is
## absent, and that null is the whole fallback: `hp_bar` stays null, `_refresh_vitals`
## returns immediately and `_refresh` puts "HP 42/60" back at the front of the status
## line, exactly as it read before D116.
func _build_hp_bar(hud: VBoxContainer) -> void:
	var frame := UITheme.kit_frame("bar_frame", int(BAR_BORDER), int(BAR_BORDER),
		int(BAR_BORDER), int(BAR_BORDER), 0.0, 0.0)
	if frame == null:
		return
	hp_bar = Control.new()
	hp_bar.custom_minimum_size = Vector2(UITheme.px(BAR_SIZE.x), UITheme.px(BAR_SIZE.y))
	hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hud.add_child(hp_bar)
	var housing := Panel.new()
	housing.add_theme_stylebox_override("panel", frame)
	housing.set_anchors_preset(Control.PRESET_FULL_RECT)
	housing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_child(housing)
	# Draw order IS the stack: what you have, then the slice about to go, then the
	# Block standing in front of both. Each fill is one column of colour per row and
	# nothing per column, so stretching it along the bar is lossless — which is what
	# the strips were authored for (D114).
	hp_fill = _bar_fill("bar_hp_fill")
	hp_loss = _bar_fill("bar_hp_loss")
	block_fill = _bar_fill("bar_block_fill")
	hp_number = Label.new()
	hp_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_number.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_number.add_theme_font_size_override("font_size", UITheme.font())
	hp_number.add_theme_color_override("font_color", Color(0.97, 0.95, 0.91))
	# The trough is dark and the HP fill is a mid red, so the numeral crosses two very
	# different backgrounds along its own width. An outline is what makes one colour
	# work on both.
	hp_number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hp_number.add_theme_constant_override("outline_size", 5)
	hp_bar.add_child(hp_number)
	UI.hoverable(hp_bar, "Your HP. The dark slice at the near end is what the enemies have already promised to take this turn, after Block.")
	# The fills are placed in the bar's rect, and a rect does not exist until the
	# container has laid out — the first `_refresh()` of a fight runs before that and
	# measures a zero-width bar. Without this the bar sat empty until the player's
	# first action, which is the one moment they are looking hardest at their HP.
	hp_bar.resized.connect(_on_bar_resized)

## The bar has just been given (or re-given) a rect, so it can be filled. Guarded on
## `eng` because `_build_ui()` runs before the engine exists.
func _on_bar_resized() -> void:
	if eng != null:
		_refresh_vitals(eng.player)

## One fill strip, sized and placed by `_refresh_vitals`. Null-safe: a missing strip
## simply never draws, so the bar can show HP with no Block art installed and vice
## versa.
func _bar_fill(name: String) -> TextureRect:
	var tex := PixelArt.ui_kit(name)
	if tex == null:
		return null
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_child(t)
	return t

## A kit texture resampled to the size it will actually be DRAWN at, remembered by
## that size.
##
## The project forces NEAREST filtering, so every one of these files is a downscale
## waiting to turn into gravel — the 256px target ring lands in a ~70px box and the
## 448px card halo in a 214px one. `UITheme.kit_icon` does the resample with Lanczos,
## which is the right answer and an expensive one to repeat: the ring is asked for
## once per enemy per layout and the halo once per card in hand. Both ask for the
## same handful of sizes, so the cache is the whole cost.
##
## Null in, null out. A missing file still means "no art" to every caller, which is
## the contract that has let this kit arrive one file at a time (D116).
func _kit_at(name: String, side: float) -> Texture2D:
	var key := "%s@%d" % [name, int(round(maxf(1.0, side)))]
	if kit_scaled.has(key):
		return kit_scaled[key]
	var tex := UITheme.kit_icon(name, maxf(1.0, side))
	kit_scaled[key] = tex
	return tex

## Energy as one orb per point, spent orbs dark. The row is always built, because the
## numeral inside it is text and text needs no art: with the orbs missing it simply
## reads "Energy 3/3" where the old status line said it.
func _build_orbs(hud: VBoxContainer) -> void:
	var side := UITheme.px(30)
	# resampled properly rather than dropped in raw: the source is 128x128 and the
	# project forces NEAREST, which turns a 4.3x downscale of a shaded sphere into
	# gravel
	orb_full_tex = UITheme.kit_icon("energy_orb_full", side)
	orb_empty_tex = UITheme.kit_icon("energy_orb_empty", side)
	orb_glow_tex = PixelArt.ui_kit("orb_glow")
	orb_row = HBoxContainer.new()
	orb_row.add_theme_constant_override("separation", UITheme.sep(3))
	orb_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud.add_child(orb_row)
	energy_number = Label.new()
	energy_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	energy_number.add_theme_color_override("font_color", Color(0.96, 0.86, 0.58))
	orb_row.add_child(energy_number)
	UI.hoverable(orb_row, "Energy. Every card costs some, and it refills at the start of each of your turns.")

## The bar, redrawn from the numbers: three widths over one span of max HP.
##
## The loss slice is what will actually come off HP, which is `enemy_intent` put through
## `Combatant.predicted_damage` — the engine's own answer, so Block AND Vulnerable are
## both in it and this screen keeps no private copy of the arithmetic. That is the whole
## reason `bar_hp_loss` exists as a third file rather than a tint of the second: play a
## card that gains 5 Block and the dark slice retreats by exactly 5, which is the same
## sum the status line spells out and far faster to see than to read.
func _refresh_vitals(p: Combatant) -> void:
	if hp_bar == null:
		return
	# The inset is the border's own thickness, UNSCALED, for the reason the slice margin
	# is unscaled: the housing is a nine-slice, so a bigger bar gets a longer middle and
	# a border that is still ten pixels of art. Scaling this inset would slide the fills
	# out from under the frame at any scale but 1.
	var b := BAR_BORDER
	var span := hp_bar.size.x - b * 2.0
	var band := hp_bar.size.y - b * 2.0
	if span <= 0.0 or band <= 0.0:
		return                      # first frame: the rect does not exist yet
	var per := span / maxf(1.0, float(p.max_hp))
	var hp_w := per * clampf(float(p.hp), 0.0, float(p.max_hp))
	var loss_w := per * float(mini(p.predicted_damage(eng.enemy_intent), p.hp))
	var block_w := per * float(clampi(p.block, 0, p.max_hp))
	if hp_fill != null:
		hp_fill.visible = hp_w >= 1.0
		hp_fill.position = Vector2(b, b)
		hp_fill.size = Vector2(hp_w, band)
	if hp_loss != null:
		# at the NEAR end of the HP, because that is the end the damage comes off
		hp_loss.visible = loss_w >= 1.0
		hp_loss.position = Vector2(b + hp_w - loss_w, b)
		hp_loss.size = Vector2(loss_w, band)
	if block_fill != null:
		block_fill.visible = block_w >= 1.0
		block_fill.position = Vector2(b, b)
		block_fill.size = Vector2(block_w, band * BLOCK_BAND)
	hp_number.text = "%d/%d" % [p.hp, p.max_hp]

## How far a spent orb recedes, and why it has to at all.
##
## Neither file is wrong and the pair still came out backwards: `energy_orb_full.png` is a
## soft violet globe with a small warm core, and the brief for `energy_orb_empty.png` asked
## for "cold grey stone, the silhouette unchanged" — which the generator delivered as a
## crisp pale rim around a dark face. Measured over each orb's own disc on a 1280x720
## capture at energy 1/3 (`shots_d117*`, a scratch harness pose; the shipped one can only
## photograph turn one, where every orb is lit):
##
##     undimmed      unspent  mean 0.426  p90 0.608  max 0.959
##                   spent    mean 0.294  p90 0.438  max 0.520
##
## So the arithmetic said the spent orb was already the darker one, by 30%, and the eye
## said otherwise — because the unspent orb spends its luminance on a 3px core inside a
## soft gradient while the spent orb spends its on a hard-edged RING around the whole
## disc, and there are two of them. Area times contrast, not peak. **This is the reverse
## of the usual trap: the measurement was reassuring and the render was not.**
##
## And the render that raised it was reading something else again. The 3x crop that
## reported the spent orbs as outright BRIGHTER (0.52-0.54 against 0.47) caught them
## mid-`_flash_orb`: their mean colour there is (158,125,118) against (76,73,96) here,
## while the unspent orb is (125,104,112) in both captures to the byte. That is the
## bloom's additive amber, and it is worth writing down rather than dismissing, because
## the bloom fires on the orbs that CHANGED — so for about a third of a second after you
## spend energy, the orb you just spent really is the brightest object in the corner.
##
## Dimming to half takes the steady state to mean 0.150 / p90 0.220, a third of the lit
## orb rather than seven-tenths, and the ring stops being the thing you see first.
## Verified by looking, not by that number: at 6x the spent orb still has a rim and an
## inner face, so it reads as cold stone and not as a hole punched in the HUD, which is
## the mirror-image defect this could have shipped instead. Fixing it in presentation is
## established practice here and not a new idea — `cutout_lib.gd`'s own summary of `Icons`
## is that it "tints them by rarity and fades them for spent states".
##
## The value is `_refresh_power`'s: the same colour this screen already dims a spent power
## ring with, so "spent" looks like one thing in one corner. Its ALPHA is deliberately not
## reused — at 0.7 the orb goes translucent and reads against the painted corridor behind
## it rather than as a stone in front of it. D96 states that rule for text (a row recedes
## by ink, never by `modulate`); for art the equivalent is that it recedes by tint and
## never by alpha.
const SPENT_ORB := Color(0.5, 0.5, 0.55)

## One orb per point of energy the turn can hold, lit up to what is left.
##
## Built to fit rather than to a constant: a relic can add energy (`bonus_energy`), so
## the number of orbs is a run-time fact. Orbs are added and never removed — a fight
## can only gain capacity — and the surplus is hidden rather than freed so nothing is
## allocated inside a refresh.
func _refresh_orbs() -> void:
	if orb_row == null:
		return
	var cap: int = Balance.MAX_ENERGY + eng.bonus_energy
	energy_number.text = ("%d/%d" if orb_full_tex != null else "Energy %d/%d") % [
		eng.energy, cap]
	if orb_full_tex == null:
		return
	var side := UITheme.px(30)
	while orb_row.get_child_count() - 1 < cap:
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(side, side)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orb_row.add_child(t)
		# the numeral stays last in the row, after however many orbs there are
		orb_row.move_child(energy_number, orb_row.get_child_count() - 1)
	for i in orb_row.get_child_count():
		# the numeral is the one child that is not an orb, and it is last
		var orb := orb_row.get_child(i) as TextureRect
		if orb == null:
			continue
		orb.visible = i < cap
		orb.texture = orb_full_tex if i < eng.energy else orb_empty_tex
		orb.modulate = Color(1, 1, 1) if i < eng.energy else SPENT_ORB
	# Only the orbs that CHANGED bloom, and only after the first draw of the fight.
	if shown_energy >= 0 and eng.energy != shown_energy:
		for i in range(mini(eng.energy, shown_energy), maxi(eng.energy, shown_energy)):
			_flash_orb(i)
	shown_energy = eng.energy

## `ui/orb_glow.png` over one orb, once. This is not an animation system and must not
## become one: the orbs are already a row of discrete rects, so "which orb changed" is
## an index and the bloom is one node on the effects layer with one tween on it — the
## same shape as `_float_number` and `_flash_hurt`, which is why it was worth wiring at
## all. Additive, per the brief: a bloom adds light to the orb underneath rather than
## painting over it.
func _flash_orb(i: int) -> void:
	if orb_glow_tex == null or fx_layer == null or orb_row == null or not is_inside_tree():
		return
	if i < 0 or i >= orb_row.get_child_count() - 1:
		return
	var orb := orb_row.get_child(i) as Control
	if orb == null or not orb.visible:
		return
	var r := orb.get_global_rect()
	if r.size.x <= 1.0:
		return
	var side := r.size.x * 2.0
	var g := TextureRect.new()
	g.texture = orb_glow_tex
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	g.material = mat
	fx_layer.add_child(g)
	g.size = Vector2(side, side)
	g.position = r.get_center() - Vector2(side, side) * 0.5
	g.pivot_offset = Vector2(side, side) * 0.5
	g.scale = Vector2(0.55, 0.55)
	# Tinted to the orb's own amber core rather than left white. Additive white over a
	# violet orb came out as grey haze, which reads as a smudge on the screen; warm, it
	# reads as the light in the orb arriving or leaving. Only the alpha is tweened, so
	# the tint survives the fade.
	g.modulate = Color(1.0, 0.84, 0.52, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	# Peak well under half: additive at 0.9 the bloom's own core out-shone the orb it is
	# supposed to be lighting, and a spent orb read as a white disc for a third of a
	# second. Both were caught by holding the peak open in a capture and looking at it —
	# a 66ms flash is not something you can judge from the numbers.
	#
	# The orb under it is dimmer since D117 (`SPENT_ORB`), so this peak now sits against a
	# third of the luminance it was tuned against. Left alone deliberately: the tuning was
	# a cap on the bloom's own brightness, not a ratio to the orb, and the flash is the
	# TRANSITION — a light leaving reads better over a stone than over another light. Not
	# photographed at peak against the new value, because a bloom whose whole life is
	# 0.4s cannot be caught by a harness whose frames are seconds apart under software GL,
	# and posing the node by hand would be a capture of a state no player produces.
	tw.tween_property(g, "modulate:a", 0.4, FX_FLASH * 0.3)
	tw.tween_property(g, "scale", Vector2.ONE, FX_FLASH * 1.4)
	tw.tween_property(g, "modulate:a", 0.0, FX_RISE * 0.55).set_delay(FX_FLASH * 0.6)
	tw.chain().tween_callback(g.queue_free)

## Above this, an attack is a bludgeoning; below it, a cut. It is the threshold the
## attack SOUND has always used, named rather than restated — the ear and the eye are
## now told the same thing by the same decision, and two constants would have been two
## thresholds within a week.
const HEAVY_BLOW := 12

## Which of the two hit pictures a card leaves on what it hits.
##
## Two, because `Fx` draws two: at 0.15s a player can tell a cut from a bludgeoning and
## cannot tell six kinds of cut apart. The classification reads CardData — the same
## fields the face and the sound already read — and never the log line, for
## `_intent_icon`'s reason: the moment this screen parses prose it can disagree with
## what happened.
##
## Called BEFORE the card resolves, so `card_damage` is the number the player was
## looking at when they pressed it, and so a card that leaves the hand still has one.
func _blow_of(card: CardData) -> String:
	# a flurry is cuts however hard it lands: it is the multiplicity that reads
	if card.hits > 1:
		return Fx.SLASH
	# Ram and its family swing your own guard at the thing, which is the definition of
	# blunt whatever the number on it is
	if card.damage_from_block or eng.card_damage(card) >= HEAVY_BLOW:
		return Fx.IMPACT
	return Fx.SLASH

func _attack_sound(blow: String) -> String:
	return "attack_heavy" if blow == Fx.IMPACT else "attack"

func _on_power_pressed() -> void:
	if eng.power == null:
		return
	var before := _snapshot_vitals()
	# a power resolves through `_resolve` exactly as a card does (PowerData extends
	# CardData), so it is classified exactly as a card is
	var blow := _blow_of(eng.power)
	var msg := eng.use_power()
	if msg == "":
		return
	Audio.play("buff" if eng.power.eff_damage() == 0 else _attack_sound(blow))
	_log(msg)
	_after_action(before, blow)

func _on_card_pressed(card: CardData) -> void:
	var before := _snapshot_vitals()
	var blow := _blow_of(card)
	var msg := eng.play_card(card)
	if msg == "":
		Audio.play("ui_denied")
		_log("Not enough energy for %s." % card.name)
		return
	# pick the sound from what the card actually did, so it matches the effect
	if card.eff_poison() > 0:
		Audio.play("poison")
	elif card.eff_damage() > 0 or card.damage_from_block:
		Audio.play(_attack_sound(blow))
	elif card.eff_block() > 0 or card.double_block:
		Audio.play("block")
	elif card.eff_strength() > 0 or card.eff_dexterity() > 0 or card.retain_block:
		Audio.play("buff")
	_log(msg)
	_after_action(before, blow)

## Shared tail for anything the player does on their own turn: a kill may have
## ended the fight, and if not the run must be saved and the screen redrawn.
func _after_action(before: Dictionary = {}, blow: String = Fx.IMPACT) -> void:
	if eng.won():
		_refresh_enemies()      # so the killing blow is shown before the plates go
		_show_deltas(before, blow)
		_win()
		return
	_snapshot()
	_refresh()
	_show_deltas(before, blow)

func _on_end_turn() -> void:
	var before := _snapshot_vitals()
	var hp_before := eng.player.hp
	_log(eng.end_turn())
	if eng.player.hp < hp_before:
		Audio.play("hurt")
	# Everything the room does lands as a bludgeoning: no enemy in the game carries a
	# blade in its intent set (`INTENT_ICONS` shares one attack symbol between the three
	# attacking actions for the same reason), and a cut arcing across the HP bar would be
	# the screen claiming a distinction the rules do not make.
	if eng.lost():
		_show_deltas(before, Fx.IMPACT, true)
		_lose()
		return
	if eng.won():
		_show_deltas(before, Fx.IMPACT, true)
		_win()
		return
	_snapshot()
	_refresh()
	_show_deltas(before, Fx.IMPACT, true)

func _refresh() -> void:
	var p := eng.player
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what the enemies are swinging for; the number after the arrow is what gets through your Block, and it is the dark slice on the bar.")
	# Block and the telegraphed hit are the pair you compare, so they share a line.
	# HP joins them only when there is no bar to carry it — that null is the whole
	# fallback, and it is what lets `ui/bar_frame.png` be absent without leaving a
	# player unable to see how close to dead they are (D116).
	var said: Array[String] = []
	if hp_bar == null:
		said.append("HP %d/%d" % [p.hp, p.max_hp])
	# Only when there IS Block. "Block 0" was printed on every turn that began with a
	# clean slate, which is most of them, and it sat first in the line the player reads
	# more than any other on this screen — a term whose whole job is to be compared
	# against "incoming", saying nothing, in front of the number it modifies (D125).
	# The bar says the same thing by having no blue band, and the tooltip still
	# explains Block whether or not the word is on screen.
	if p.block > 0:
		said.append("Block %d" % p.block)
	# Both halves of the sum, because the bar draws the SECOND one and a line that only
	# said the first would disagree with the picture next to it. The tooltip claimed
	# "incoming" was already net of Block and it never was — 13 was the raw swing — so
	# a player with 9 Block up had no number for the 4 that was going to land. An arrow
	# rather than "(4 through)": at title size the parenthesis form measured past the
	# label's 330px and wrapped, which cost a line and read as a mistake.
	var through := p.predicted_damage(eng.enemy_intent)
	if through != eng.enemy_intent:
		said.append("incoming %d → %d" % [eng.enemy_intent, through])
	else:
		said.append("incoming %d" % eng.enemy_intent)
	status_label.text = "    ".join(said)
	_refresh_vitals(p)
	_refresh_orbs()
	_refresh_buffs(p)

	_refresh_enemies()
	_refresh_hand()
	_refresh_power()

## Enemy slots are built ONCE and then updated.
##
## Every action used to `queue_free` the entire enemy row and the entire hand and
## build them again. That is why nothing in this game had ever moved: you cannot
## tween between two states when one of them has been deleted.
##
## Slots are placed by hand rather than by a container, because they stand on the
## backdrop's floor line — a container would put them wherever the stack had room,
## which measured 22px above the painted floor. `_hit()` also jolts a slot's own
## position, which a container would immediately undo.
func _refresh_enemies() -> void:
	while enemy_plates.size() < eng.enemies.size():
		enemy_plates.append(_build_slot(enemy_plates.size()))
	var living: Array[int] = []
	for i in eng.enemies.size():
		if not eng.enemies[i].is_dead():
			living.append(i)
	if living.size() != slot_count:
		slot_count = living.size()
		_place_slots(living)
	for i in eng.enemies.size():
		var e: Combatant = eng.enemies[i]
		var slot: Control = enemy_plates[i]
		if e.is_dead():
			slot.visible = false
			continue
		slot.visible = true
		var targeted := i == eng.target
		# Its statuses are the chip row's job now; what comes back is only what had no
		# symbol to draw, and that goes back in the bracket it used to live in, so a
		# plate with `ui/sym_*.png` missing reads exactly as it did before D117.
		var estat := _fill_chips(slot.get_meta("chips") as HBoxContainer, e, true)
		var vitals: Label = slot.get_meta("vitals")
		vitals.text = "%s%s   %d/%d%s" % ["\u25b6 " if targeted else "", e.name,
			e.hp, e.max_hp, ("   [%s]" % " ".join(estat)) if not estat.is_empty() else ""]
		vitals.add_theme_color_override("font_color",
			Color(1.0, 0.92, 0.62) if targeted else Color(0.88, 0.86, 0.84))
		var intent: Label = slot.get_meta("intent")
		intent.text = eng.intent_text(i)
		# The picture and the number, not one instead of the other. See `_intent_icon`.
		var glyph: TextureRect = slot.get_meta("intent_icon")
		glyph.texture = _kit_at(_intent_icon(i), glyph.custom_minimum_size.y)
		glyph.visible = glyph.texture != null
		var mark: Panel = slot.get_meta("mark")
		# A RING when targeted, never a filled disc. The mark is centred on the
		# standing line, so its upper half lies across the feet — which is what a
		# contact SHADOW should do, but the targeted version was 85%-opaque gold. It
		# painted the enemy's ankles out and left it sitting on a bright solid
		# lozenge. The report was "the monsters are floating"; the backdrops were
		# mostly innocent (D109).
		#
		# D125 hands the targeted state to `ui/target_ring.png` and gives the SHADOW
		# back to both states. The painted ring is four arcs of worn iron with an open
		# middle, so it can lie across the feet without painting anything out — which
		# is what the stylebox outline was standing in for and never managed, because a
		# 999-radius rounded rectangle 27px tall is a capsule, not a ring on a floor.
		# The shadow stays underneath it because being targeted is a fact about the UI
		# and standing on the ground is a fact about the enemy: swapping one for the
		# other used to un-ground whichever creature you were pointing at.
		var reticle: TextureRect = slot.get_meta("reticle")
		var painted_ring: bool = reticle.texture != null
		reticle.visible = targeted and painted_ring
		# With no file on disk the plate falls all the way back to the D109 pair, so
		# an uninstalled ring costs the outline, not the targeting.
		var lit := targeted and not painted_ring
		mark.add_theme_stylebox_override("panel",
			slot.get_meta("mark_ring" if lit else "mark_shadow"))
		mark.modulate = Color(1.0, 0.82, 0.40, 0.9) if lit else Color(0, 0, 0, 0.72)
		var hit: Button = slot.get_meta("hit")
		hit.tooltip_text = "%s\nIntent: %s\nClick to target." % [e.name, eng.intent_text(i)]

## One enemy: its art, the ground mark it stands on, what it intends, and a hit
## area over the whole silhouette.
##
## `PixelArt.enemy_art(id)` is keyed by archetype id, so a painted file lands on
## the enemy it was drawn for. The 16x16 CC0 sprite is the stand-in until one
## exists — assigned positionally, which is exactly why the painted directory is
## keyed separately rather than sharing that pool.
func _build_slot(i: int) -> Control:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_box.add_child(slot)

	# TWO marks in one node, and which one is showing says whether this enemy is the
	# target. Filled it is a contact shadow; as an outline it is a ring drawn ON the
	# floor the enemy stands on. They cannot be the same box: a filled mark that is
	# also bright reads as a platform rather than as ground (D109).
	var mark := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.corner_radius_top_left = 999
	sb.corner_radius_top_right = 999
	sb.corner_radius_bottom_left = 999
	sb.corner_radius_bottom_right = 999
	var ring := sb.duplicate() as StyleBoxFlat
	ring.bg_color = Color(1, 1, 1, 0.14)   # a breath of fill, so the ellipse still reads as flat on the floor
	ring.border_color = Color(1, 1, 1)
	ring.set_border_width_all(2)
	slot.set_meta("mark_shadow", sb)
	slot.set_meta("mark_ring", ring)
	mark.add_theme_stylebox_override("panel", sb)
	mark.modulate = Color(0, 0, 0, 0.72)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mark)

	# The painted reticle, over the shadow and UNDER the creature — which is the whole
	# reason it can be a ring rather than a halo. The mark is centred on the standing
	# line and the enemy's sprite has its feet on that same line, so the ring's near
	# half falls below the sprite's bottom edge where there is nothing to hide it, and
	# its far half is occluded by the body exactly as a ring drawn on the floor behind
	# an enemy should be. Added here, before the art, is what buys that for free.
	#
	# Sized and given its texture in `_place_slots`, because the size it is drawn at is
	# not known until the slot has one and this file is not allowed to guess at a size
	# (D125). Textureless until then, and textureless forever if the file is absent.
	var reticle := TextureRect.new()
	reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reticle.stretch_mode = TextureRect.STRETCH_SCALE
	# Filtered for the same reason the painted enemy above it is: NEAREST is forced
	# project-wide, and this quad is a square texture pulled out into a floor ellipse.
	reticle.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	reticle.modulate = Color(1.0, 0.84, 0.46, 0.92)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.visible = false
	slot.add_child(reticle)

	# The footprint a painted enemy is meant to fill: shown ONLY while it is
	# missing, so the frame can be composed before anything is drawn. A 16x16
	# stand-in blown up to 240px otherwise dominates the whole picture and makes
	# the layout impossible to judge.
	var arch := eng.archetypes[i] as EnemyData
	var aid: String = arch.id if arch != null else "cultist"
	var painted := PixelArt.enemy_art(aid)
	var box := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.05, 0.06, 0.09, 0.30)
	bsb.border_color = Color(0.85, 0.80, 0.60, 0.28)
	bsb.set_border_width_all(2)
	box.add_theme_stylebox_override("panel", bsb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.visible = painted == null
	slot.add_child(box)

	var art := TextureRect.new()
	art.texture = painted if painted != null else Icons.enemy(aid)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if painted != null:
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	else:
		# a dark silhouette at a plausible size, standing on the mark
		art.modulate = Color(0.16, 0.18, 0.24, 0.92)
	slot.add_child(art)

	var vitals := Label.new()
	vitals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(vitals)

	# What it is carrying, between who it is and what it is about to do. Chips rather
	# than the `[Blk 5 Psn 3 Vuln 2 Weak 1 Str 2 Dex 1]` this used to append to the name
	# line: those abbreviations existed because there was no icon to use (D117), and at
	# six of them the string ran well past a 273px plate in both directions, because a
	# Label draws outside its own rect rather than clipping.
	var chips := _build_chip_row(slot, [])
	chips.alignment = BoxContainer.ALIGNMENT_CENTER

	# What it is about to do: the painted telegraph AND the number, side by side and
	# centred as a pair.
	#
	# The icon does not replace the text and must not. "hit 6" is two facts — a kind
	# and a quantity — and `ui/intent_attack.png` carries only the first; a plate that
	# showed the blade alone would have thrown away the number the whole telegraph
	# exists to deliver. The row is an HBox so that dropping the icon (no file, or an
	# action with no symbol for it) leaves the label centred on its own, which is
	# exactly the line this screen printed before D125.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep(5))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# IGNORE for the reason the chip row is: this spans the plate and must not swallow
	# the click that targets the creature.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(row)

	var glyph := TextureRect.new()
	var glyph_side := UITheme.px(SLOT_TEXT_BAND) / 3.0
	glyph.custom_minimum_size = Vector2(glyph_side, glyph_side)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.visible = false
	row.add_child(glyph)

	var intent := Label.new()
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intent.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55))
	intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(intent)

	var hit := Button.new()
	hit.flat = true
	hit.pressed.connect(_on_target_pressed.bind(i))
	slot.add_child(hit)

	slot.set_meta("art", art)
	slot.set_meta("box", box)
	slot.set_meta("stand_in", painted == null)
	slot.set_meta("vitals", vitals)
	slot.set_meta("chips", chips)
	slot.set_meta("intent", intent)
	slot.set_meta("intent_row", row)
	slot.set_meta("intent_icon", glyph)
	slot.set_meta("mark", mark)
	slot.set_meta("reticle", reticle)
	slot.set_meta("hit", hit)
	return slot

## Which painted telegraph goes with which enemy action.
##
## The classification is the ENGINE'S, not a second one invented here: an intent is
## `{"action": EnemyData.Action, "value": int}` and this maps that enum onto the seven
## files in `ui/intent_*.png`. No string is parsed and no damage is recomputed — the
## number on the plate stays whatever `intent_text()` says it is, because the moment
## this screen starts doing its own arithmetic about a telegraph it can disagree with
## the hit that lands (D50).
##
## The three attacks share one blade. SUNDER and DRAIN are attacks that also do
## something else, and that something else is in the words beside the icon
## ("ignores Block", "drain"); giving each a symbol of its own would mean three
## silhouettes the player has to learn apart at 22px, which is the size a distinction
## has to survive to be worth making.
##
## **Two of the seven files have no action to attach to.** `EnemyData.Action` is
## ATTACK, DEBUFF_VULN, DEBUFF_WEAK, DEFEND, EMPOWER, SUNDER, ENRAGE, DRAIN — there is
## no multi-hit action and no enemy anywhere applies Poison (only cards do), so
## `intent_attack_multi` and `intent_poison` are painted for behaviour the engine
## cannot currently telegraph. They are left unmapped on purpose. Inventing a rule
## here for "this reads like a multi-hit" would be exactly the private copy of shared
## data that D34 cost a dungeon, and the fix belongs in `EnemyData.Action` and
## `CombatEngine._roll_intent`, not on this screen.
const INTENT_ICONS := {
	EnemyData.Action.ATTACK: "intent_attack",
	EnemyData.Action.SUNDER: "intent_attack",
	EnemyData.Action.DRAIN: "intent_attack",
	EnemyData.Action.DEFEND: "intent_block",
	EnemyData.Action.EMPOWER: "intent_buff",
	EnemyData.Action.ENRAGE: "intent_buff",
	EnemyData.Action.DEBUFF_VULN: "intent_debuff",
	EnemyData.Action.DEBUFF_WEAK: "intent_debuff",
}

## The kit name for enemy `i`'s telegraph. `intent_unknown` is the answer for anything
## the map does not hold, which is the same "?" `intent_text` falls back to and the
## honest picture for it: a closed eye rather than a wrong verb.
func _intent_icon(i: int) -> String:
	if i < 0 or i >= eng.intents.size():
		return "intent_unknown"
	var action := int((eng.intents[i] as Dictionary).get("action", -1))
	return String(INTENT_ICONS.get(action, "intent_unknown"))

## How much of the frame, at EACH side, the enemies are kept out of.
##
## This exists because two decisions were in conflict and only one of them knew it.
## The Tier 5 brief in `tools/art_manifest.gd` asks every dungeon backdrop for
## "foreground framing elements at the left and right thirds" — that skeleton is what
## makes twelve rooms feel like one dungeon, and it is deliberate. The layout below
## used to spread enemies over the FULL width at `vp.x * (k+1)/(n+1)`, which puts two
## enemies at exactly x=1/3 and x=2/3: the two columns the brief fills with pillars,
## stall fronts and arch bases. So a pair of enemies stood on the scenery rather than
## on the floor, and because `PixelArt.STAND_LINE` is a single number for the whole
## frame, they stood at the height of the CENTRE floor while the visible ground under
## them started lower. That reads as hovering, and it was reported as one (D122).
##
## Only the flanks were ever wrong, which is why it went unseen: one enemy sits dead
## centre and is fine, and `tests/test_art.gd` reduces each backdrop to one floor
## number and says in its own comments that it is confidently wrong about half the
## time. `tools/screenshots.gd` grew a `CombatGroup` capture for this.
##
## 0.20 keeps the whole cast inside the middle 60% — for n=2 that is x=40% and 60%,
## both over open corridor in all twelve rooms. It is NOT 1/3: the framing elements
## start at the thirds, so standing on the line is standing on their inside edge.
const STAGE_INSET := 0.20

## How far the power sigil is held back from the orb's edge, in unscaled px. The ring
## is a circle drawn as a 999-radius corner on a square Panel, so art taken to the full
## rect loses its four corners to the curve; this is the margin that keeps the emblem
## inside the circle instead of clipped by it.
const POWER_ART_INSET := 14.0

## The band at the bottom of the orb the cost numeral sits in, in unscaled px.
const POWER_COST_BAND := 30.0

## The three text rows above every enemy, in unscaled px — see the note on `text_h`
## in `_place_slots` for why it is 66 and what a boss pays for the third row. A
## constant because the intent icon is sized off a third of it and the two must not be
## able to drift: an icon built to a number copied out of a layout is the same defect
## as a reserve taken off a screenshot, which is what `_place_hand` is still apologising
## for.
const SLOT_TEXT_BAND := 66.0

## The floor ring, as a multiple of the contact shadow's width and of its own.
##
## Slightly WIDER than the shadow so the shadow sits inside it rather than on its line,
## and squashed because a ring lying on a floor seen from the front is an ellipse, not
## a circle. Together they put the far arc 12.7% of the creature's height up its shins
## — high enough to read as a ring around the enemy rather than a line under it, and
## low enough that what it crosses is ankles. It is allowed to cross them because it is
## four arcs of open ironwork; the thing D109 banned there was a FILLED bright mark,
## which reads as a platform.
const RING_WIDEN := 1.14
const RING_SQUASH := 0.36

## Where each living enemy stands. Feet on `PixelArt.STAND_LINE`, spread across the
## middle of the frame (see `STAGE_INSET`), and the flanks pushed slightly back — the
## backdrops are one-point corridors, so a dead-flat row of equal sizes reads as
## pasted-on.
func _place_slots(living: Array[int]) -> void:
	var vp := get_viewport_rect().size
	# On the floor and near the viewer, not on the horizon: standing them where the
	# back wall meets the floor put them at the far end of the corridor, small and
	# detached from the fight. Kept clear of the hand by measurement, so the two can
	# never end up on top of each other at another UI scale.
	var floor_y := vp.y * PixelArt.STAND_LINE
	if hand_box != null and hand_box.size.y > 1.0:
		floor_y = minf(floor_y, hand_box.global_position.y - UITheme.px(10))
	# leave the top band and the text lines their room, and never let the hand
	# swallow the stage at large UI scales.
	#
	# THREE rows above the creature since D117, not two: who it is, what it is carrying,
	# what it is about to do. The band is 20px taller for it, and that is not free — the
	# clamp below is `floor_y - top_limit - text_h`, and a boss asks for 366.6px of a
	# 720-tall frame, which was inside the old ceiling of 376.4 and is outside the new
	# one of 356.4. So a boss now draws 2.8% shorter and nothing else moves (an elite
	# wants 311.9 and an ordinary enemy 273.6, both well clear). Paid knowingly: the
	# status row it buys is the thing that says why the boss is hitting for 50.
	var text_h := UITheme.px(SLOT_TEXT_BAND)
	var line_h := text_h / 3.0
	var top_limit := UITheme.px(96)
	# A boss should loom. Same corridor, same floor line, more of the frame — this is
	# the cheapest way for a fight to announce what it is before the numbers do.
	var tier_scale: float = TIER_SIZE.get(tier, 1.0)
	var body := clampf(vp.y * 0.38 * tier_scale, UITheme.px(48),
		maxf(UITheme.px(48), floor_y - top_limit - text_h))
	var n := living.size()
	for k in n:
		var i: int = living[k]
		var slot: Control = enemy_plates[i]
		var s := 1.0 if n == 1 else lerpf(0.88, 1.0,
			1.0 - absf(float(k) - float(n - 1) * 0.5) / maxf(1.0, float(n - 1) * 0.5))
		var w := body * s
		var h := body * s
		var cx := vp.x * (STAGE_INSET + (1.0 - 2.0 * STAGE_INSET)
			* float(k + 1) / float(n + 1))
		slot.position = Vector2(cx - w * 0.5, floor_y - h - text_h)
		slot.size = Vector2(w, h + text_h)

		var vitals: Label = slot.get_meta("vitals")
		vitals.position = Vector2(0, 0)
		vitals.size = Vector2(w, line_h)
		var chips: HBoxContainer = slot.get_meta("chips")
		chips.position = Vector2(0, line_h)
		chips.size = Vector2(w, line_h)
		# The icon and the number travel together, so the ROW takes the third line and
		# the HBox centres the pair inside it.
		var intent_row: HBoxContainer = slot.get_meta("intent_row")
		intent_row.position = Vector2(0, line_h * 2.0)
		intent_row.size = Vector2(w, line_h)
		var art: TextureRect = slot.get_meta("art")
		var box: Panel = slot.get_meta("box")
		box.position = Vector2(0, text_h)
		box.size = Vector2(w, h)
		if bool(slot.get_meta("stand_in", false)):
			# the stand-in is 16x16 pixel art with transparent margins: at full slot
			# size its "feet" float halfway up the box. Real art is authored with its
			# feet on the bottom edge of the canvas and fills the footprint.
			art.size = Vector2(w * 0.52, h * 0.52)
			art.position = Vector2(w * 0.24, text_h + h * 0.46)
		else:
			art.position = Vector2(0, text_h)
			art.size = Vector2(w, h)
		var hit: Button = slot.get_meta("hit")
		hit.position = Vector2(0, text_h)
		hit.size = Vector2(w, h)
		# the contact mark sits ON the floor line, under the feet
		var mark: Panel = slot.get_meta("mark")
		mark.size = Vector2(w * 0.62, maxf(4.0, h * 0.10))
		mark.position = Vector2((w - mark.size.x) * 0.5, text_h + h - mark.size.y * 0.5)
		# The reticle shares that centre and that floor line, wider and taller (see
		# RING_WIDEN / RING_SQUASH).
		#
		# Resampled to the ring's HEIGHT rather than its width, which looks like the
		# wrong axis and is the right one: a 256px square going into a ~190x69 box is a
		# 3.7x downscale vertically and a 1.3x one horizontally, and downscaling is the
		# direction that eats detail. Taking the source to 69px square with Lanczos and
		# letting the GPU stretch it back out sideways means the only resample the
		# hardware does is an UPscale, which cannot alias.
		var reticle: TextureRect = slot.get_meta("reticle")
		var rw := mark.size.x * RING_WIDEN
		var rh := rw * RING_SQUASH
		reticle.size = Vector2(rw, rh)
		reticle.position = Vector2((w - rw) * 0.5, text_h + h - rh * 0.5)
		reticle.texture = _kit_at("target_ring", rh)

## The hand is diffed, not rebuilt: cards that stayed keep their node (and so can
## be animated), cards that left are flown out, cards that arrived are dealt in.
func _refresh_hand() -> void:
	var base := UITheme.card_size()

	# gone from hand: played, discarded or exhausted
	for card in card_widgets.keys():
		if card in eng.hand:
			continue
		var ghost: Control = card_widgets[card]
		card_widgets.erase(card)
		_fly_out(ghost)

	for idx in eng.hand.size():
		var card: CardData = eng.hand[idx]
		var holder: Control = card_widgets.get(card)
		# A card you cannot afford used to look exactly like one you could, and the
		# only way to find out was to click it and be refused. Dimmed, not disabled —
		# pressing it still explains why, which is how the rule gets learned.
		var playable := eng.can_play(card)
		var want_a := 1.0 if playable else 0.45
		if holder == null:
			# `eng` passed in: the face quotes what this card does THIS turn, with
			# Strength, Dexterity, Weak and per-combat growth applied.
			var cb := UI.card_button(hand_box, card, base,
				_on_card_pressed.bind(card), "", eng)
			holder = cb.get_parent() as Control
			card_widgets[card] = holder
			_add_card_glow(holder, base)
			holder.modulate = Color(1, 1, 1, want_a)
			_deal_in(holder, want_a)
		else:
			# a buff landing mid-turn changes what every card in hand would do
			var again: Callable = holder.get_meta("relabel", Callable())
			if again.is_valid():
				again.call(eng)
			holder.modulate = Color(1, 1, 1, want_a)
		# Affordability said twice, once in each direction: what you cannot pay for
		# goes dim, and what you can pay for is lit. The dimming alone was a statement
		# about the cards you are NOT going to play, which is the wrong half to draw
		# attention to, and at 0.45 against 1.0 it needs two cards side by side to be
		# legible at all. The halo is on the card the answer is about (D125).
		var glow: TextureRect = holder.get_meta("glow", null)
		if glow != null:
			glow.visible = playable
	_place_hand()

## How far past the card's own rect the affordability halo spreads, and how hard it
## burns.
##
## The art is a rounded band of light with an empty middle, and the band is INSET from
## the file's own edge — measured on `card_glow.png` itself, its brightest ring runs
## 7.5% of the width in from the left and right and 6.5% of the height down from the
## top. So the halo drawn at exactly the card's rect puts every lit pixel it has behind
## the card, under an opaque painted frame, and the first render of this showed a hand
## with no glow on it at all and no error anywhere. The multiple that lands the band ON
## the border solves `inset * k = (k - 1) / 2`, which is 1.18 across and 1.15 down; 1.20
## takes both a shade past it so the fade actually falls outside the card, which is what
## "the light that would spill around one" means.
##
## 0.50 because five cards wear this at once. A hint that reads as a highlight is a
## highlight on the whole hand, which says nothing. Rendered and looked at: full
## strength is a rim of light on every card and shouts; a third is a warm smudge that
## does not survive being next to a lit card illustration; half reads as an edge you
## notice without reading, which is the whole job. Additive rather than
## alpha-blended so it can only ever ADD light — over the backdrop it glows, over the
## card's own frame it does nothing, and it can never dim or tint a face the player is
## trying to read.
const CARD_GLOW_SPILL := 1.20
const CARD_GLOW_BURN := 0.50

## Put the halo behind one freshly dealt card. Silent no-op with no
## `ui/card_glow.png` on disk: the hand then marks affordability exactly as it did
## before, by dimming what cannot be paid for.
func _add_card_glow(holder: Control, base: Vector2) -> void:
	var outer := base * CARD_GLOW_SPILL
	var tex := _kit_at("card_glow", outer.y)
	if tex == null:
		return
	var glow := TextureRect.new()
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.modulate = Color(1, 1, 1, CARD_GLOW_BURN)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.visible = false
	# Sized and placed by hand rather than by a preset, and NOT anchored: the halo is
	# deliberately bigger than its parent, and `set_anchors_preset` on a node with no
	# rect yet is the trap that cost D121 a whole tier of card illustrations.
	glow.position = -(outer - base) * 0.5
	glow.size = outer
	holder.add_child(glow)
	# BEHIND the card, which is where a spill comes from. Also behind the Button, so
	# it cannot come between the player and the click.
	holder.move_child(glow, 0)
	holder.set_meta("glow", glow)

## Lay the hand out as a hand: an arc across the bottom, cards overlapping, each
## tilted a little, the middle of the fan riding highest.
##
## Overlapping is what makes a hand of nine cards possible at all — side by side
## they would either run off the frame or shrink until nothing on them could be
## read. The trade is that a card at rest is partly covered, which is why hovering
## one straightens it, lifts it clear and enlarges it (UI.card_button); at rest a
## card shows its name, its cost and its headline number, which is what you scan.
const FAN_TILT := 0.075        ## radians at the outermost card
const FAN_ARC := 22.0          ## how much higher the middle of the fan rides
const FAN_OVERLAP := 0.88      ## fraction of a card's width between neighbours

## How much of a card is above the bottom edge of the screen at rest. The rest of
## it hangs off, deliberately.
##
## A portrait card that had to fit on screen whole would have to be short, and a
## short card is the one the old layout had: a picture too small to be a picture
## and a rules band too small to hold rules, which is why the text was hidden
## until you hovered. Letting the bottom go off-frame buys the height back for
## free, because the bottom of a card is its least urgent part — what you scan a
## hand for is cost, name, picture and the headline number, and every one of those
## is in the top half by construction (see `UI.card_button`).
##
## The invariant this has to keep is that the visible part is the identifying
## part; `CardTextTest` measures it rather than trusting this comment.
const HAND_PEEK := 0.74

## Clearance between a lifted card and the frame, so a hovered card is read
## against the screen rather than jammed into its edge.
const HOVER_MARGIN := 10.0

func _place_hand() -> void:
	var n := eng.hand.size()
	if n == 0:
		return
	var base := UITheme.card_size()
	var vp := get_viewport_rect().size
	# stay clear of the vitals on the left and the power/End Turn on the right
	# Measured against what is actually beside the hand, not assumed. The first
	# version hardcoded the reserves from a screenshot and was wrong immediately: a
	# Label overflows its box, so the vitals text looked narrower than the 380px box
	# it sits in, and the leftmost card slid under it. The rects are the truth, and
	# they are also what the test checks.
	var left := UITheme.px(372)
	var right := vp.x - UITheme.px(320)
	if hud_box != null:
		var hr := hud_box.get_global_rect()
		if hr.size.x > 1.0:
			# The measured edge REPLACES the constant rather than being max()'d with it.
			# As a floor it silently outranked the measurement the moment the measurement
			# got smaller, which is what D117 narrowing `hud_box` to 330 found: 18px of
			# reserve came back and the fan only saw 6 of it, because 372 was still bigger
			# than the 360 the rects were reporting. That is the same defect this block's
			# own comment is about — a reserve taken off a screenshot rather than off the
			# layout — wearing a `maxf`. The constant is the value for the ONE frame where
			# no rect exists yet, and the guard above is what says so.
			left = hr.end.x + UITheme.px(14)
	if controls_box != null:
		var cr := controls_box.get_global_rect()
		if cr.size.x > 1.0:
			right = minf(right, cr.position.x - UITheme.px(14))
	# A tilted card is WIDER than a card. It turns about its bottom centre, so its
	# top corner swings out by height x sin(tilt) — and that is a number the card's
	# height controls, which is why a reserve that was correct for a 132px-tall card
	# put a 214px one 16px inside the vitals. Only the outermost pair are tilted the
	# full amount, and a hovered card straightens before it lifts, so this is a
	# resting-state correction and it belongs on both edges.
	var swing := base.y * sin(FAN_TILT)
	left += swing
	right -= swing
	var room := maxf(base.x, right - left)
	# The step has to leave room for the WIDTH of the outermost cards, not just for
	# their centres: `room / n` put the leftmost card's edge 21px inside the vitals,
	# which the render did not show and the geometry test did.
	var step := base.x * FAN_OVERLAP
	if n > 1:
		step = minf(step, (room - base.x) / float(n - 1))
	var span := step * float(n - 1)
	var cx := (left + right) * 0.5
	var arc := UITheme.px(FAN_ARC)
	for i in n:
		var card: CardData = eng.hand[i]
		var holder: Control = card_widgets.get(card)
		if holder == null:
			continue
		holder.custom_minimum_size = base
		holder.size = base
		# Tell the card how much of its own face survives the fan. Cards are drawn in
		# hand order, so card i is covered by card i+1 and only `step` of it is left;
		# the last one is on top of everything and keeps the lot. Without this the name
		# — the only thing a resting card shows — is laid out across a width the player
		# cannot see (D97).
		if holder.has_meta("fit_name"):
			(holder.get_meta("fit_name") as Callable).call(base.x if i == n - 1 else step)
		# rotation and growth both happen about the bottom-centre, so a card pivots
		# in the hand rather than sliding sideways as it turns
		holder.pivot_offset = Vector2(base.x * 0.5, base.y)
		var f := 0.0 if n == 1 else (float(i) / float(n - 1)) * 2.0 - 1.0   # -1..1
		var rot := f * FAN_TILT
		# measured DOWN from the top of the band: the band is exactly a card plus the
		# arc, so the outermost (lowest) card still finishes inside the frame. Taking
		# it up from the bottom instead pushed the whole fan off the screen edge.
		var pos := Vector2(cx - span * 0.5 + step * float(i) - base.x * 0.5,
			f * f * arc)
		# How far this card must rise to be read WHOLE. Not a constant fraction: the
		# card hangs off the bottom edge by design, the fan's outer cards hang off
		# further than its middle ones, and hover scales about the bottom-centre pivot
		# — so the bottom edge does not move when the card grows, and every pixel of
		# the enlargement goes upward. Solve for the lift that puts the bottom edge
		# HOVER_MARGIN inside the frame and the whole card follows, because the top
		# edge is then bottom - height*scale, which the band above the hand has room
		# for. Computing it per card is what makes "displays in full" true for the
		# outermost card and not just the middle one.
		var bottom := hand_box.global_position.y + pos.y + base.y
		var lift := maxf(0.0, bottom - (vp.y - UITheme.px(HOVER_MARGIN)))
		holder.set_meta("fan", {"pos": pos, "rot": rot, "lift": lift})
		# do not fight the hover: a card being read owns its own transform
		if holder.z_index == 0:
			holder.position = pos
			holder.rotation = rot
		hand_box.move_child(holder, i)

	piles_label.text = "Draw %d   ·   Discard %d   ·   Hand %d" % [
		eng.draw_pile.size(), eng.discard_pile.size(), eng.hand.size()]

## The power button states the whole rule: what it does, what it costs, and — when
## it cannot be fired — WHY. "Used this turn" and "not enough energy" are different
## problems and a greyed button that says neither teaches nothing.
##
## **The NAME is on hover; the sigil and the cost are on the orb.** The name used to be
## printed across the orb, which was the only thing there to look at while `powers/`
## was empty. Now that the ten sigils are painted (Tier 6b), the picture is the faster
## read — and a word set at 0.85x font inside a 112px circle was never a good one.
##
## The cost stays visible and does NOT move to the tooltip with the name, which is the
## one place this departs from "picture only". It is not a label, it is the number the
## turn is planned against: energy is spent on cards from the same pool, so "can I
## still afford this" is asked every turn and hovering to find out would be a worse
## screen, not a cleaner one. The ring already dims when the power cannot be fired, but
## dimming says "no" without saying "how much".
func _refresh_power() -> void:
	var p := eng.power
	if p == null:
		power_btn.visible = false
		power_ring.visible = false
		power_art.visible = false
		power_fx.visible = false
		return
	power_btn.visible = true
	power_ring.visible = true
	# Falls back to the name when a sigil has not been painted, rather than to an empty
	# orb: the same one-file-at-a-time contract the rest of the art runs on (D121).
	var sigil := PixelArt.power_art(p.id)
	power_art.texture = sigil
	power_art.visible = sigil != null
	# Only over a painted sigil. Laid over the name-text fallback it would be light
	# sitting on nothing, which reads as a rendering fault rather than as progress.
	var fx := PixelArt.level_overlay("power", p.level, p.level_capped()) if sigil != null else null
	power_fx.texture = fx
	power_fx.visible = fx != null
	if fx != null and not power_fx.has_meta("pulsing"):
		# once per orb, not once per refresh — `_refresh_power` runs every time the energy
		# changes and a fresh looping tween each time would stack into a flicker
		power_fx.set_meta("pulsing", true)
		UI.animate_level_glow(power_fx, PixelArt.level_band(p.level, p.level_capped()))
	var cost := "free" if p.eff_cost() == 0 else "%dE" % p.eff_cost()
	# With a sigil the Button carries no text at all — the picture is the button, the
	# numeral is the Label below, and the name is on hover.
	power_btn.text = "" if sigil != null else "%s\n%s" % [p.name, cost]
	power_cost.text = cost if sigil != null else ""
	power_cost.visible = sigil != null
	power_btn.disabled = not eng.can_use_power()
	# The sigil goes with the ring when the power is spent. Without this the orb stayed
	# bright and only its thin border dimmed, which at 112px is a state you have to
	# hunt for.
	power_art.modulate = Color(1, 1, 1) if not power_btn.disabled \
		else Color(0.55, 0.55, 0.6, 0.65)
	power_cost.modulate = power_art.modulate
	# goes dim with the sigil it sits on, or it would glow brightest on a power that
	# cannot be fired
	power_fx.modulate = Color(1, 1, 1) if not power_btn.disabled else Color(0.55, 0.55, 0.6, 0.65)
	# spent or unaffordable reads on the ring, not only in the tooltip: the orb is
	# small, so its STATE has to be visible from the shape rather than the words
	power_ring.modulate = Color(1, 1, 1) if not power_btn.disabled else Color(0.5, 0.5, 0.55, 0.7)
	var why := ""
	if eng.power_used:
		why = "\nAlready used this turn."
	elif p.eff_cost() > eng.energy:
		why = "\nNeeds %d energy, you have %d." % [p.eff_cost(), eng.energy]
	elif p.eff_hp_cost() > 0 and eng.player.hp <= p.eff_hp_cost():
		why = "\nCosts %d HP and would be lethal." % p.eff_hp_cost()
	UI.hoverable(power_btn, "%s\n%s\nOnce per turn, every turn.%s" % [
		p.name, p.effect_text(), why])

func _on_target_pressed(i: int) -> void:
	if eng.set_target(i):
		_refresh()

# --- feedback -----------------------------------------------------------------
#
# Until now every state change was instantaneous and silent: HP numbers jumped,
# nothing flashed, cards vanished from the hand. The rules were all legible and
# none of them were felt. These are deliberately short — a card game is read, and
# an animation you have to wait through is worse than none.

## How much of the frame an enemy takes, by what kind of fight it is.
const TIER_SIZE := {
	Balance.Tier.NORMAL: 1.0,
	Balance.Tier.ELITE: 1.14,
	Balance.Tier.BOSS: 1.34,
}

const FX_RISE := 0.55        ## how long a floating number lives
const FX_FLASH := 0.22       ## hit tint
const FX_SHAKE := 0.20

## The state an effect is a difference from, before an action.
##
## Everything the effects layer draws is DERIVED from this against the state after —
## never from parsing the log line, and never from the engine telling the screen what
## to play. `combat_engine.gd` says at the top of itself that it has no UI in it, and it
## drives the headless simulator; a fight that has to fire animations is a fight that
## costs something to simulate.
##
## Poison is here because a stack that changed is the only honest signal that poison
## DID something: it goes up when a card applies it and down after it bites (see
## `Combatant.end_turn`), so one comparison covers both and neither needs a flag.
##
## The intents are the enemies' telegraphs, snapshotted because `end_turn` re-rolls
## them: what an enemy was about to do is the game's own answer to what it just did, and
## it is more truthful than reading its Block afterwards — an enemy that blocks 5 every
## turn has its guard expire and rebuild to the same number, and a delta sees nothing.
func _snapshot_vitals() -> Dictionary:
	var foes: Array = []
	for i in eng.enemies.size():
		var e: Combatant = eng.enemies[i]
		foes.append({
			"hp": e.hp, "block": e.block, "poison": e.poison, "dead": e.is_dead(),
			"intent": int((eng.intents[i] as Dictionary).get("action", -1)),
		})
	return {
		"player": eng.player.hp, "block": eng.player.block,
		"poison": eng.player.poison, "foes": foes,
	}

## How hard a hit landed, as a share of the target's own bar, for the effects that
## scale with it. Same shape as `_flash_hurt`'s: a 4-point chip must not look like a
## boss landing 40, and a floor under it stops a 1-point tick drawing nothing at all.
func _blow_force(amount: int, max_hp: int) -> float:
	return clampf(float(amount) / maxf(1.0, float(max_hp) * 0.30), 0.35, 1.0)

## Float the difference above whoever it happened to, shake them, and draw what
## happened over the top.
##
## `blow` is which hit picture a landing attack leaves (`_blow_of`). `their_turn` says
## the enemies have just acted, which is the one thing the before/after pair cannot
## tell: it is what licenses reading the snapshotted intents.
##
## Everything below tolerates a partial `before` — a caller that only knows about the
## player passes only the player, and the enemy loop simply does not run.
func _show_deltas(before: Dictionary, blow: String = Fx.IMPACT,
		their_turn: bool = false) -> void:
	var foes: Array = before.get("foes", [])
	for i in eng.enemies.size():
		if i >= foes.size() or i >= enemy_plates.size():
			continue
		var was: Dictionary = foes[i]
		var e: Combatant = eng.enemies[i]
		var plate: Control = enemy_plates[i]
		var art := _body_art(plate)
		var body: Rect2 = art.get_global_rect() if art != null else plate.get_global_rect()
		var lost: int = int(was["hp"]) - e.hp
		if lost > 0:
			_float_number(plate, "-%d" % lost, Color(1.0, 0.62, 0.42))
			_hit(plate)
			var force := _blow_force(lost, e.max_hp)
			if blow == Fx.SLASH:
				Fx.slash(fx_layer, body, fx_ramp, force)
			else:
				Fx.impact(fx_layer, body, fx_ramp, force)
		elif lost < 0:
			_float_number(plate, "+%d" % (-lost), Color(0.62, 0.95, 0.62))
			Fx.heal(fx_layer, body, fx_ramp)      # a drain heals the thing draining you
		if e.poison != int(was["poison"]):
			Fx.poison_cloud(fx_layer, body, fx_ramp)
		if their_turn and int(was["intent"]) == EnemyData.Action.DEFEND \
				and not e.is_dead() and e.block > 0:
			Fx.block_up(fx_layer, body, fx_ramp)
		if e.is_dead() and not bool(was["dead"]):
			# The slot is already hidden by the refresh that ran before this, so the
			# dissolve stands in for it — same rect, same texture, same tint, on the
			# effects layer where `_win()`'s clear-out cannot reach it. The tint matters:
			# a stand-in silhouette is a 16x16 sprite drawn at `modulate` 0.16, and a
			# ghost that dropped that would come apart in the wrong colour entirely.
			Fx.death_dissolve(fx_layer, body, fx_ramp,
				art.texture if art != null else null,
				art.modulate if art != null else Color(1, 1, 1))

	# The player's own numbers rise off the thing that just changed. That used to be
	# the status line because the status line was the only thing there; now HP and
	# Block are a bar, so they rise off the bar, and off the line only when there is
	# no bar installed. The effects go to the same place for the same reason: there is
	# no player figure on this screen to put them on.
	var pin: Control = hp_bar if hp_bar != null else status_label
	# Grown, because the bar is 256x44 and every effect here sizes itself off the
	# SMALLER side of the box it is given — a ward or a shock inside 44px of height is a
	# mark you would have to go looking for. The bar is the anchor; this is the room
	# around it, and it stays inside the HUD column either way.
	var pin_rect := pin.get_global_rect().grow(UITheme.px(30))
	var p_lost: int = int(before.get("player", eng.player.hp)) - eng.player.hp
	if p_lost > 0:
		_float_number(pin, "-%d" % p_lost, Color(1.0, 0.5, 0.45))
		_flash_hurt(p_lost)
		Fx.impact(fx_layer, pin_rect, fx_ramp, _blow_force(p_lost, eng.player.max_hp))
	elif p_lost < 0:
		_float_number(pin, "+%d" % (-p_lost), Color(0.62, 0.95, 0.62))
		Fx.heal(fx_layer, pin_rect, fx_ramp)
	var gained_block: int = eng.player.block - int(before.get("block", eng.player.block))
	if gained_block > 0:
		_float_number(pin, "+%d block" % gained_block, Color(0.62, 0.80, 1.0))
		Fx.block_up(fx_layer, pin_rect, fx_ramp)
	if eng.player.poison != int(before.get("poison", eng.player.poison)):
		Fx.poison_cloud(fx_layer, pin_rect, fx_ramp)

## The creature inside its slot — the TextureRect the plate was built with, painted
## plate or 16x16 stand-in. Effects go on THIS and not on the plate: a plate is the art
## plus three lines of text above it, and an effect centred on that is drawn over the
## name.
func _body_art(plate: Control) -> TextureRect:
	return plate.get_meta("art", null) as TextureRect

func _float_number(over: Control, text: String, colour: Color) -> void:
	if fx_layer == null or not is_inside_tree():
		return
	# The one place `show_numbers` reaches. It was persisted and offered in the menu
	# from the day it was added and read by nothing at all, so the checkbox had never
	# once changed the screen (D130). Everything it hides is a duplicate of a number
	# already on a bar; nothing the player needs in order to choose a card goes with it.
	if not SettingsState.show_numbers:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", UITheme.title_font())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(l)
	var r := over.get_global_rect()
	l.position = Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.25)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - UITheme.px(44), FX_RISE)
	tw.tween_property(l, "modulate:a", 0.0, FX_RISE).set_delay(FX_RISE * 0.4)
	tw.chain().tween_callback(l.queue_free)

## Tint red and jolt. The jolt is on the plate's own position, so the row layout
## is untouched — a container that reflows on every hit would be far worse than
## no feedback at all.
func _hit(plate: Control) -> void:
	var home := plate.position
	var tw := create_tween()
	tw.tween_property(plate, "modulate", Color(1.6, 0.6, 0.6), FX_FLASH * 0.35)
	tw.tween_property(plate, "modulate", Color(1, 1, 1), FX_FLASH)
	var sh := create_tween()
	sh.tween_property(plate, "position:x", home.x + UITheme.px(6), FX_SHAKE * 0.25)
	sh.tween_property(plate, "position:x", home.x - UITheme.px(4), FX_SHAKE * 0.35)
	sh.tween_property(plate, "position:x", home.x, FX_SHAKE * 0.4)

## The player has no plate to shake, so the screen itself takes the hit. Scaled by
## how hard: a 4-point chip should not look like a boss landing 40.
func _flash_hurt(amount: int) -> void:
	if hurt_veil == null:
		return
	var share := clampf(float(amount) / maxf(1.0, float(eng.player.max_hp) * 0.35), 0.08, 1.0)
	hurt_veil.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(hurt_veil, "color:a", 0.26 * share, 0.06)
	tw.tween_property(hurt_veil, "color:a", 0.0, 0.32)

## A played card leaves the hand rather than blinking out of existence. It is
## reparented to the effects layer first: hand_box must contain only real cards,
## because that is what the screen and the tests count.
func _fly_out(holder: Control) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var here := holder.get_global_rect()
	if hand_box.is_ancestor_of(holder):
		hand_box.remove_child(holder)
	if fx_layer == null:
		holder.queue_free()
		return
	fx_layer.add_child(holder)
	holder.position = here.position
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "position:y", here.position.y - UITheme.px(60), 0.26)
	tw.tween_property(holder, "modulate:a", 0.0, 0.26)
	tw.tween_property(holder, "scale", Vector2(0.7, 0.7), 0.26)
	tw.chain().tween_callback(holder.queue_free)

## A drawn card fades up instead of appearing fully formed. It fades to whatever
## alpha affordability wants, so the two do not fight over the same property.
func _deal_in(holder: Control, target_alpha: float) -> void:
	if holder == null:
		return
	holder.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(holder, "modulate:a", target_alpha, 0.18)

# --- status chips (D117) -------------------------------------------------------
#
# Every status the game can put on a combatant, in ONE table, because there were two
# hand-kept lists of the same seven and they did not say the same things: this screen's
# prose ("Strength +2  (every attack hits harder)") and `Combatant.status_text()`'s
# abbreviations ("Str 2"). Two descriptions of one set is the D34 shape, and the damage
# was exactly where it always is — the prose taught what Dexterity does and the
# abbreviations did not, on the plates where a player first meets Vulnerable.
#
# Columns, and why each is here:
#   key      what to read off a Combatant; `_status_count` owns that, because the keys
#            are SYMBOL names and the fields are not (`retain` against `retain_block`)
#   symbol   the semantic name `Icons.tex()` resolves. Null means the painting is not
#            installed and the row degrades into `text` below — the same "use it if it
#            exists" contract the whole kit is built on (D116), stated once more here
#            because a status with no picture still has to be readable.
#   good     whose doing it is: yours, or the room's. This is what carries the tint.
#   teach    the hover, and where the parentheticals went. "(every Block is bigger)"
#            is the only thing in the game that ever said what Dexterity does, so it
#            is not deleted, it is moved somewhere it costs no width. Its FIRST
#            sentence is also the no-symbol fallback line — which is why the headline
#            clause comes first and the decay rule second. One string, two lengths, no
#            second copy to drift.
#   abbrev   the plate's compact word, lifted off `Combatant.status_text()` unchanged,
#            so an enemy plate with no symbols installed reads exactly as it did.
#
# A row carrying a literal `%` must also carry a `%d`: `teach` is only put through `%`
# when it has a number in it, so "+50%%" in a numberless row would ship as two percent
# signs. Both rows that need one have one.
const STATUS_CHIPS := [
	["block", "block", true,
		"Block %d — soaked off incoming hits, then gone at the start of the next turn.", "Blk"],
	["strength", "strength", true,
		"Strength +%d — every attack hits that much harder. Lasts the whole fight.", "Str"],
	["dexterity", "dexterity", true,
		"Dexterity +%d — every Block gained is that much bigger. Lasts the whole fight.", "Dex"],
	["thorns", "thorns", true,
		"Thorns %d — anything that attacks takes that much straight back.", "Thorns"],
	["retain", "retain", true,
		"Block persists — Block stops expiring and piles up from turn to turn.", "Blk+"],
	["vulnerable", "vulnerable", false,
		"Vulnerable %d — +50%% damage taken from every hit. One stack expires each turn.", "Vuln"],
	["weak", "weak", false,
		"Weak %d — -25%% damage dealt. One stack expires each turn.", "Weak"],
	["poison", "poison", false,
		"Poison %d — that much damage at each turn's end, ignoring Block, then one stack falls off.", "Psn"],
]

## The player's Block is the band on the HP bar AND the first number in `status_label`,
## so a Block chip beside them would be its third copy. Everything else shows on both
## sides in the same order, so there is one reading rule rather than two.
const PLAYER_CHIP_SKIP := ["block"]

## Warm for "you did this", red for "the room did this to you". Not a new palette —
## these are the exact two colours `_refresh_buffs` has always chosen between; the
## amber is `energy_number`'s and the target ring's, the red is the family
## `_float_number` uses for damage taken. What changed is that they are applied PER
## CHIP instead of to the whole line. The old line picked one colour for all of it, so
## a fight with Strength up and Weak on you painted your own Strength in the enemy's
## colour — which is worse than the no distinction at all it was meant to be.
const CHIP_GOOD := Color(0.98, 0.85, 0.45)
const CHIP_BAD := Color(0.95, 0.62, 0.55)
## The drawn side of a symbol, in layout pixels. ONE number for the HUD and the enemy
## plates both, for D113's reason: two sizes of the same icon set read as one of them
## being wrong, and there is no measurement that says a plate wants a smaller Poison
## than the corner does.
const CHIP_SIDE := 20.0

## One row of icon+number chips, built once with every chip it will ever need and each
## one hidden until its status is up.
##
## Nothing is allocated inside a refresh, for `_refresh_orbs`' reason: this is redrawn
## after every card played, and a row that frees and rebuilds its children cannot hold
## a tooltip open under the mouse and could never be tweened. A chip whose symbol does
## not resolve is never built at all — that is what lets `_fill_chips` tell "not up"
## from "no art for this" and put the second one into prose instead of drawing nothing.
func _build_chip_row(parent: Node, skip: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep(7))
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	# IGNORE on the row, STOP on each chip. The enemy plate's row spans the whole plate
	# width, and a container that ate the mouse there would swallow the click that
	# targets the creature; a chip is ~36px and is the only part that wants a pointer.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chips := {}
	for spec in STATUS_CHIPS:
		var key := String(spec[0])
		if key in skip:
			continue
		var tex := Icons.tex(String(spec[1]))
		if tex == null:
			continue
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", UITheme.sep(2))
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.visible = false
		row.add_child(chip)
		var art := TextureRect.new()
		art.texture = tex
		art.custom_minimum_size = Vector2(UITheme.px(CHIP_SIDE), UITheme.px(CHIP_SIDE))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# The symbols are painted at 64x64 and drawn here at a fifth of that. Filtered
		# for the same reason `_build_slot` filters a painted enemy: the project forces
		# NEAREST, which turns a 3x downscale of a painted glyph into gravel.
		art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(art)
		var num := Label.new()
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(num)
		chips[key] = chip
	row.set_meta("chips", chips)
	row.set_meta("skip", skip)
	parent.add_child(row)
	return row

## Show what this combatant is carrying, and hand back a line for anything the chips
## could not say — a status whose painting is absent. `compact` picks which of the two
## written forms that line takes: a plate is 273px wide and gets "Vuln 2", the HUD
## column is 330 and gets the sentence that teaches.
func _fill_chips(row: HBoxContainer, c: Combatant, compact: bool) -> Array[String]:
	var missing: Array[String] = []
	if row == null:
		return missing
	var chips: Dictionary = row.get_meta("chips", {})
	var skip: Array = row.get_meta("skip", [])
	var shown := 0
	for spec in STATUS_CHIPS:
		var key := String(spec[0])
		if key in skip:
			continue
		var n := _status_count(c, key)
		var chip: Control = chips.get(key)
		if chip == null:
			if n > 0:
				missing.append(_chip_fallback(spec, n, compact))
			continue
		chip.visible = n > 0
		if n <= 0:
			continue
		shown += 1
		# A stack count, or nothing at all: `retain` is a switch and not a quantity, and
		# "Block persists 1" is a number the player cannot do anything with.
		var num := chip.get_child(1) as Label
		num.text = str(n) if String(spec[3]).contains("%d") else ""
		chip.modulate = CHIP_GOOD if bool(spec[2]) else CHIP_BAD
		UI.hoverable(chip, _chip_teach(spec, n))
	# An empty row still costs its container a separation gap, and on turn one — full
	# HP, nothing up — that gap is every plate and the HUD both.
	row.visible = shown > 0
	return missing

## What a Combatant is carrying, by chip key. A `match` rather than a Dictionary of
## Callables (a const table cannot hold one) and rather than `get(key)` reflection,
## because the keys are symbol names and deliberately do not match the field names.
func _status_count(c: Combatant, key: String) -> int:
	match key:
		"block": return c.block
		"strength": return c.strength
		"dexterity": return c.dexterity
		"thorns": return c.thorns
		"retain": return 1 if c.retain_block else 0
		"vulnerable": return c.vulnerable
		"weak": return c.weak
		"poison": return c.poison
	return 0

## The hover: the whole teaching sentence, with this stack count in it.
func _chip_teach(spec: Array, n: int) -> String:
	var s := String(spec[3])
	return (s % n) if s.contains("%d") else s

## What to write when this status has no symbol installed to draw.
func _chip_fallback(spec: Array, n: int, compact: bool) -> String:
	if compact:
		var a := String(spec[4])
		return ("%s %d" % [a, n]) if String(spec[3]).contains("%d") else a
	# the headline clause of the hover, which is the reason that sentence is ordered
	# the way it is rather than a second string saying the same thing shorter
	return _chip_teach(spec, n).get_slice(". ", 0)

## What you are carrying, as a row of tinted icon+number chips.
##
## It was run-on prose joined by `·`, and at six statuses that is a ~900px paragraph
## laid out in a 330px column. Worse than ugly: a Label reports its TEXT as its minimum
## width, so it did not wrap and it did not clip, it pushed `hud_box` WIDER — and
## `_place_hand` takes the fan's left reserve off that box's right edge, so a fight with
## Strength, Dexterity, Thorns, Vulnerable, Weak and Poison up was quietly squeezing a
## hand that is already down to a 41px step at eleven cards (D116). That is D95's
## "a custom_minimum_size is not a minimum if the content sets the size" one screen over.
## Seven chips measure ~322px, inside the box the layout was built around, so nothing
## moves.
##
## `buffs_label` survives as the fallback and only as that: it says whatever has no
## painting installed and is invisible when the chips said everything. It also wraps
## now, which the prose never did — the widening above was a defect in the fallback path
## as much as in the main one, and the fallback is what ships from a bare checkout.
## Its colour stays the amber it is built with rather than turning red when any debuff
## is up, because that line-wide red is precisely what the per-chip tint replaces; in
## the fallback the words name the status.
func _refresh_buffs(p: Combatant) -> void:
	var said := _fill_chips(buff_row, p, false)
	buffs_label.visible = not said.is_empty()
	buffs_label.text = "   ·   ".join(said)

## Keep the last few lines. A turn where three enemies act used to report only the
## third, because this overwrote a single Label.
const LOG_LINES := 2

func _log(msg: String) -> void:
	if msg.strip_edges() == "":
		return
	log_lines.append(msg.strip_edges())
	while log_lines.size() > LOG_LINES:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)

# --- reward ---
func _win() -> void:
	GameState.combat_state = {}   # the fight is over; nothing to resume
	GameState.hp = eng.player.hp  # persist HP for the next fight
	# relic: heal after victory
	var relic_heal := MetaState.relic_bonus("heal_after_combat")
	if relic_heal > 0:
		GameState.hp = min(GameState.max_hp, GameState.hp + relic_heal)
	# relic: gold percentage bonus
	var g := Balance.gold_reward(GameState.dungeon, tier, randi() % 6)
	g += int(round(g * MetaState.relic_bonus("gold_percent") / 100.0))
	# ground already taken pays less (D69): the first clear is worth full price, a
	# fourth run through a dungeon you beat at 100% is not income, it is a treadmill
	var repeats := MetaState.times_cleared(GameState.dungeon_id)
	if repeats > 0:
		g = maxi(1, int(round(float(g) * Balance.repeat_reward_mult(repeats))))
	GameState.earn_gold(g)   # at risk until the boss falls (D20)
	end_btn.disabled = true
	_seal_exit()
	# Nothing is incoming from a dead room. `status_label` is about to become the reward
	# line, so the bar is the only thing left saying what your HP is — and it would
	# otherwise keep a dark slice reserved for a hit that can no longer land.
	_refresh_vitals(eng.player)
	card_widgets.clear()
	enemy_plates.clear()
	for c in hand_box.get_children():
		c.queue_free()
	for c in enemy_box.get_children():
		c.queue_free()
	Audio.play("boss_cleared" if tier == Balance.Tier.BOSS else "reward")
	if MetaState.hint_once("first_reward"):
		_log("Rewards are AT RISK until you beat this dungeon's boss — or leave with an Escape Rope.")
	# An elite was a harder fight for more gold, which is a stat check rather than a
	# decision. It drops a relic now — held at risk with everything else, so taking
	# the fight and then dying still costs you it.
	var relic_line := ""
	if tier == Balance.Tier.ELITE:
		var won_relic := MetaState.pick_relic(Balance.Tier.ELITE)
		if won_relic != "":
			GameState.earn_relic(won_relic)
			var rd := load(MetaState.RELIC_CATALOG[won_relic]) as RelicData
			relic_line = "  Took %s (at risk)." % (rd.name if rd != null else won_relic)
			Audio.play("treasure")
		# ...and a pack, so the elite is the middle rung of the three pack sources
		# (D81): a chest is usually worn, an elite is usually sealed, a boss is
		# never worn. Choosing to take the hard fight is what buys the better tier.
		GameState.earn_pack(Balance.PACK_ELITE)
		var ep: Dictionary = GameState.escrow_packs.back()
		relic_line += "  Sealed: %s." % Balance.pack_title(
			String(ep.get("tier", Balance.PACK_WORN)), String(ep.get("build", "")))
	# Keys drop from fights as well as chests (D84), so a locked chest is a reason
	# to take a fight rather than a reason to have walked somewhere else earlier.
	var chance: int = Balance.KEY_ELITE_CHANCE if tier == Balance.Tier.ELITE else Balance.KEY_FIGHT_CHANCE
	if randi() % 100 < chance:
		GameState.keys += 1
		relic_line += "  Took a key."

	var healed := "  Healed %d." % relic_heal if relic_heal > 0 else ""
	status_label.text = "Encounter cleared. +%d gold (%d at risk).%s%s Choose a reward:" % [
		g, GameState.escrow_gold, healed, relic_line]
	for c in reward_box.get_children():
		c.queue_free()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep())
	reward_box.add_child(row)
	var rbase := UITheme.reward_card_size()
	var rw := Icons.fit_card_width(3, rbase.x,
		get_viewport_rect().size.x - UITheme.px(40), float(UITheme.sep()))
	for card in _roll_rewards(3):
		UI.card_button(row, card, Vector2(rw, rbase.y), _on_reward_picked.bind(card))
	# What taking one COSTS. Dilution is real — a bigger deck draws each card less
	# often — but it was invisible, so "take one of three" was an automatic click
	# rather than a decision. Skipping is a legitimate play and should read as one.
	var now: int = GameState.run_deck.size()
	var cost := Label.new()
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost.add_theme_color_override("font_color", Color(0.85, 0.80, 0.62))
	cost.text = "Taking one makes your deck %d cards: you would see any given card every %.1f turns instead of %.1f." % [
		now + 1, Balance.draw_interval(now + 1), Balance.draw_interval(now)]
	reward_box.add_child(cost)
	UI.hoverable(cost, "Every card you add makes the rest come up less often. Shops and rests can thin the deck back down.")

	var skip := Button.new()
	UITheme.style_button(skip)
	skip.text = "Skip  —  keep the deck at %d" % now
	skip.pressed.connect(_on_reward_picked.bind(null))
	reward_box.add_child(skip)
	reward_box.visible = true

## Reward offers come from the dungeon's card pool (so exclusives are real), with
## rarity weights tilted by the dungeon's difficulty (harder place, better loot).
func _roll_rewards(n: int) -> Array[CardData]:
	var out: Array[CardData] = []
	var pool: Array = GameState.card_pool()
	if pool.is_empty():
		pool = DEFAULT_POOL.duplicate()
	pool = pool.filter(func(id): return MetaState.CATALOG.has(id))
	# rarity tilts back toward commons on ground already taken, for the same reason
	var wtbl: Array = Balance.reward_weights(tier,
		GameState.dungeon if MetaState.times_cleared(GameState.dungeon_id) == 0
		else maxi(1, GameState.dungeon - 2))
	for i in n:
		if pool.is_empty():
			break
		var loaded: Array = []
		var weights: Array = []
		var total := 0
		for id in pool:
			# Balance.card, not load(): the same shared instance, without paying
			# ResourceLoader's path resolution nineteen times per reward screen
			var c := Balance.card(id)
			loaded.append(c)
			var w: int = wtbl[clampi(c.rarity, 0, wtbl.size() - 1)]
			weights.append(w)
			total += w
		var r := randi() % maxi(1, total)
		var pick := 0
		for j in weights.size():
			r -= int(weights[j])
			if r < 0:
				pick = j
				break
		out.append((loaded[pick] as CardData).duplicate())
		pool.remove_at(pick)
	return out

func _on_reward_picked(card) -> void:
	if card != null:
		# usable immediately, permanent only if this dungeon is completed (D20)
		GameState.earn_card(card.id)
	GameState.clear_node(GameState.pending)
	GameState.flush_save()   # a resolved encounter is worth writing at once
	if tier == Balance.Tier.BOSS:
		# dungeon cleared -> mark it, grant a relic, then back to dungeon select (D6)
		# the boss is the commit point: banked earnings become permanent here
		# the boss's own pack, earned a moment before everything commits
		GameState.earn_pack(Balance.PACK_BOSS)
		var banked := GameState.commit_escrow()
		GameState.last_haul = "Secured %d cards, %d gold, %d relic(s) and %d pack(s)." % [
			banked["cards"], banked["gold"], banked["relics"], banked["packs"]]
		MetaState.mark_cleared(GameState.dungeon_id)
		var got := MetaState.grant_relic(Balance.Tier.BOSS)
		if got != "":
			var r := load(MetaState.RELIC_CATALOG[got]) as RelicData
			GameState.last_relic = r.name if r else got
		if randi() % 100 < Balance.BOSS_ROPE_CHANCE:
			MetaState.add_item("escape_rope")
			GameState.last_haul += " Found an Escape Rope."
		MetaState.highest_dungeon = max(MetaState.highest_dungeon, GameState.dungeon)
		GameState.clear_run()
		MetaState.save_game()
		GameState.refresh_max_hp()
		# the final dungeon completes the world and offers the next ascension
		if GameState.dungeon_id == Balance.final_dungeon():
			Audio.play("victory")
			get_tree().change_scene_to_file("res://scenes/Victory.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
	else:
		get_tree().change_scene_to_file(GameState.run_scene())

func _lose() -> void:
	end_btn.disabled = true
	_seal_exit()
	card_widgets.clear()
	for c in hand_box.get_children():
		c.queue_free()
	Audio.play("defeat")
	GameState.combat_state = {}
	# D20: the run's earnings are forfeited — that is now the primary cost of dying.
	var lost := GameState.forfeit_escrow()
	# D3: plus a (retuned) permanent penalty scaled by dungeon difficulty.
	var pen := MetaState.penalize_death(GameState.dungeon)
	var dd := GameState.dungeon_data()
	# Hand the whole reckoning to a screen the player dismisses themselves. This
	# used to be one line of status text and a forced 2.5 second wait.
	GameState.last_defeat = {
		"dungeon": dd.name if dd != null else "the dark",
		"difficulty": GameState.dungeon,
		"killer": _killer_name(),
		"tier": tier,
		"turns": eng.turn,
		"forfeited_cards": int(lost["cards"]),
		"forfeited_gold": int(lost["gold"]),
		"forfeited_packs": int(lost.get("packs", 0)),
		"penalty_gold": int(pen["gold_lost"]),
		"penalty_cards": pen["cards_lost"],
	}
	status_label.text = "DEFEAT."
	buffs_label.visible = false
	# ...and the chips with it. They are the readout the label used to be, so anything
	# that clears one has to clear the other or the corner keeps saying what a dead
	# player's Strength was next to the word DEFEAT.
	if buff_row != null:
		buff_row.visible = false
	piles_label.visible = false
	# an empty bar and a row of dark orbs say nothing the word does not
	if hp_bar != null:
		hp_bar.visible = false
	if orb_row != null:
		orb_row.visible = false
	GameState.reset_run_progress()
	GameState.clear_run()
	GameState.flush_save()   # death is final; do not risk losing the penalty
	get_tree().change_scene_to_file("res://scenes/Defeat.tscn")

## Whatever is still standing gets the credit. The current target first: that is
## the one the player was looking at.
##
## WITHOUT the duplicate's number, and this is the one place that is right. A
## second Bone Picker on the field makes the combat log's `%s dies!` a claim about
## the pair unless the name carries an index, which is why `combat_engine.gd`
## numbers them and why D125 decided to keep it. None of that applies once the
## fight is over: there is no second line to disambiguate, nothing left to target,
## and this is the highest-drama sentence the game writes — "Bone Picker 2 brought
## you down in The Crypt" reads like a bug report at the exact moment it should
## not (D125).
func _killer_name() -> String:
	var foe := eng.current_target()
	if foe != null and not foe.is_dead():
		return _unnumbered(foe.name)
	for e in eng.enemies:
		if not e.is_dead():
			return _unnumbered(e.name)
	return "something in the dark"

## A duplicate's display name with its disambiguating index taken off. Only the
## trailing " <digits>" the engine appends — a name that ends in a numeral of its
## own would have to be one somebody authored, and no archetype does.
func _unnumbered(n: String) -> String:
	var cut := n.rstrip("0123456789").rstrip(" ")
	return cut if cut != "" and cut != n else n
