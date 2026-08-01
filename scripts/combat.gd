## Combat screen — thin UI over CombatEngine (all rules live in the engine,
## all numbers in Balance). Reads the run from GameState, writes rewards to
## MetaState, then routes back to the map / deck builder.
extends Control

const CARD_DIR := "res://resources/cards/"
## Fallback pool when a dungeon defines none (D6: dungeons own their card pools).
const DEFAULT_POOL := ["strike", "defend", "bash", "iron_wave", "clear_mind",
	"terrify", "inflame", "footwork", "barricade"]

var eng: CombatEngine
var tier: int = Balance.Tier.NORMAL

var status_label: Label
var buffs_label: Label
var piles_label: Label
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
## Where floating numbers and flashes are drawn: on top of everything, deaf to the
## mouse, and never a parent of anything the game logic reads.
var fx_layer: Control
var hurt_veil: ColorRect
var reward_box: VBoxContainer
var end_btn: Button
var power_btn: Button
var menu_btn: Button
var place_label: Label
var power_ring: Panel
## The two bottom corners the hand has to stay out of. Kept as members so the fan
## can measure them instead of guessing: a hardcoded reserve was wrong the moment a
## Label's BOX turned out wider than its text, and would be wrong again at any other
## UI scale.
var hud_box: VBoxContainer
var controls_box: HBoxContainer

func _ready() -> void:
	tier = _tier_of(GameState.pending.get("type", GameState.NodeType.COMBAT))
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
	place_label.add_theme_font_size_override("font_size", UITheme.title_font())
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
	hud.offset_right = UITheme.px(16) + UITheme.px(348)
	hud.offset_top = -UITheme.px(128)
	hud.offset_bottom = -UITheme.px(10)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	# wrapped inside a known width: as one line it measured ~530px at title size and
	# ran straight under the leftmost card, which no box could prevent because a
	# Label overflows rather than clips
	status_label.custom_minimum_size.x = UITheme.px(330)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_child(status_label)
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what would actually land after Block.")

	# Buffs and debuffs spelled out, under the vitals they modify. They used to be a
	# "[Blk 5 Str 3]" fragment inside a run-on line, which is not where anybody looks
	# for the reason their damage changed.
	buffs_label = Label.new()
	buffs_label.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
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
	power_btn = Button.new()
	power_btn.flat = true
	power_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	power_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	power_btn.add_theme_font_size_override("font_size", int(UITheme.font() * 0.85))
	power_btn.pressed.connect(_on_power_pressed)
	orb.add_child(power_btn)
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
	hand_box.offset_top = -(UITheme.card_size().y + UITheme.px(FAN_ARC) + UITheme.px(14))
	hand_box.offset_bottom = -UITheme.px(20)

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

func _on_power_pressed() -> void:
	var before := _snapshot_hp()
	var msg := eng.use_power()
	if msg == "":
		return
	Audio.play("buff" if eng.power != null and eng.power.eff_damage() == 0 else "attack")
	_log(msg)
	_after_action(before)

func _on_card_pressed(card: CardData) -> void:
	var before := _snapshot_hp()
	var msg := eng.play_card(card)
	if msg == "":
		Audio.play("ui_denied")
		_log("Not enough energy for %s." % card.name)
		return
	# pick the sound from what the card actually did, so it matches the effect
	if card.eff_poison() > 0:
		Audio.play("poison")
	elif card.eff_damage() > 0 or card.damage_from_block:
		Audio.play("attack_heavy" if card.eff_damage() >= 12 else "attack")
	elif card.eff_block() > 0 or card.double_block:
		Audio.play("block")
	elif card.eff_strength() > 0 or card.eff_dexterity() > 0 or card.retain_block:
		Audio.play("buff")
	_log(msg)
	_after_action(before)

## Shared tail for anything the player does on their own turn: a kill may have
## ended the fight, and if not the run must be saved and the screen redrawn.
func _after_action(before: Dictionary = {}) -> void:
	if eng.won():
		_refresh_enemies()      # so the killing blow is shown before the plates go
		_show_deltas(before)
		_win()
		return
	_snapshot()
	_refresh()
	_show_deltas(before)

func _on_end_turn() -> void:
	var before := _snapshot_hp()
	var hp_before := eng.player.hp
	_log(eng.end_turn())
	if eng.player.hp < hp_before:
		Audio.play("hurt")
	if eng.lost():
		_show_deltas(before)
		_lose()
		return
	if eng.won():
		_show_deltas(before)
		_win()
		return
	_snapshot()
	_refresh()
	_show_deltas(before)

func _refresh() -> void:
	var p := eng.player
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what would actually land after Block.")
	status_label.text = "HP %d/%d    Block %d\nEnergy %d/%d    incoming %d" % [
		p.hp, p.max_hp, p.block,
		eng.energy, Balance.MAX_ENERGY + eng.bonus_energy, eng.enemy_intent]
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
		var estat := e.status_text()
		var vitals: Label = slot.get_meta("vitals")
		vitals.text = "%s%s   %d/%d%s" % ["\u25b6 " if targeted else "", e.name,
			e.hp, e.max_hp, ("   [%s]" % estat) if estat != "" else ""]
		vitals.add_theme_color_override("font_color",
			Color(1.0, 0.92, 0.62) if targeted else Color(0.88, 0.86, 0.84))
		var intent: Label = slot.get_meta("intent")
		intent.text = eng.intent_text(i)
		var mark: Panel = slot.get_meta("mark")
		mark.modulate = Color(1.0, 0.82, 0.40, 0.85) if targeted else Color(0, 0, 0, 0.72)
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

	var mark := Panel.new()          # ground contact / target ring
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1)
	sb.corner_radius_top_left = 999
	sb.corner_radius_top_right = 999
	sb.corner_radius_bottom_left = 999
	sb.corner_radius_bottom_right = 999
	mark.add_theme_stylebox_override("panel", sb)
	mark.modulate = Color(0, 0, 0, 0.72)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mark)

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

	var intent := Label.new()
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intent.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55))
	intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(intent)

	var hit := Button.new()
	hit.flat = true
	hit.pressed.connect(_on_target_pressed.bind(i))
	slot.add_child(hit)

	slot.set_meta("art", art)
	slot.set_meta("box", box)
	slot.set_meta("stand_in", painted == null)
	slot.set_meta("vitals", vitals)
	slot.set_meta("intent", intent)
	slot.set_meta("mark", mark)
	slot.set_meta("hit", hit)
	return slot

## Where each living enemy stands. Feet on `PixelArt.STAND_LINE`, spread across the
## frame, and the flanks pushed slightly back — the backdrops are one-point
## corridors, so a dead-flat row of equal sizes reads as pasted-on.
func _place_slots(living: Array[int]) -> void:
	var vp := get_viewport_rect().size
	# On the floor and near the viewer, not on the horizon: standing them where the
	# back wall meets the floor put them at the far end of the corridor, small and
	# detached from the fight. Kept clear of the hand by measurement, so the two can
	# never end up on top of each other at another UI scale.
	var floor_y := vp.y * PixelArt.STAND_LINE
	if hand_box != null and hand_box.size.y > 1.0:
		floor_y = minf(floor_y, hand_box.global_position.y - UITheme.px(10))
	# leave the top band and the two text lines their room, and never let the hand
	# swallow the stage at large UI scales
	var text_h := UITheme.px(46)
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
		var cx := vp.x * float(k + 1) / float(n + 1)
		slot.position = Vector2(cx - w * 0.5, floor_y - h - text_h)
		slot.size = Vector2(w, h + text_h)

		var vitals: Label = slot.get_meta("vitals")
		vitals.position = Vector2(0, 0)
		vitals.size = Vector2(w, text_h * 0.5)
		var intent: Label = slot.get_meta("intent")
		intent.position = Vector2(0, text_h * 0.5)
		intent.size = Vector2(w, text_h * 0.5)
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
		var want_a := 1.0 if eng.can_play(card) else 0.45
		if holder == null:
			# `eng` passed in: the face quotes what this card does THIS turn, with
			# Strength, Dexterity, Weak and per-combat growth applied.
			var cb := UI.card_button(hand_box, card, base,
				_on_card_pressed.bind(card), "", eng)
			holder = cb.get_parent() as Control
			card_widgets[card] = holder
			holder.modulate = Color(1, 1, 1, want_a)
			_deal_in(holder, want_a)
		else:
			# a buff landing mid-turn changes what every card in hand would do
			var again: Callable = holder.get_meta("relabel", Callable())
			if again.is_valid():
				again.call(eng)
			holder.modulate = Color(1, 1, 1, want_a)
	_place_hand()

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
			left = maxf(left, hr.end.x + UITheme.px(14))
	if controls_box != null:
		var cr := controls_box.get_global_rect()
		if cr.size.x > 1.0:
			right = minf(right, cr.position.x - UITheme.px(14))
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
		holder.set_meta("fan", {"pos": pos, "rot": rot, "lift": base.y * 0.34})
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
func _refresh_power() -> void:
	var p := eng.power
	if p == null:
		power_btn.visible = false
		power_ring.visible = false
		return
	power_btn.visible = true
	power_ring.visible = true
	power_btn.text = "%s\n%s" % [p.name, "free" if p.cost == 0 else "%dE" % p.cost]
	power_btn.disabled = not eng.can_use_power()
	# spent or unaffordable reads on the ring, not only in the tooltip: the orb is
	# small, so its STATE has to be visible from the shape rather than the words
	power_ring.modulate = Color(1, 1, 1) if not power_btn.disabled else Color(0.5, 0.5, 0.55, 0.7)
	var why := ""
	if eng.power_used:
		why = "\nAlready used this turn."
	elif p.cost > eng.energy:
		why = "\nNeeds %d energy, you have %d." % [p.cost, eng.energy]
	elif p.hp_cost > 0 and eng.player.hp <= p.hp_cost:
		why = "\nCosts %d HP and would be lethal." % p.hp_cost
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

## HP of everything, before an action. Compared afterwards to work out what to
## show — derived from the real numbers rather than from parsing the log line.
func _snapshot_hp() -> Dictionary:
	var out := {"player": eng.player.hp, "block": eng.player.block}
	for i in eng.enemies.size():
		out[i] = eng.enemies[i].hp
	return out

## Float the difference above whoever it happened to, and shake them.
func _show_deltas(before: Dictionary) -> void:
	for i in eng.enemies.size():
		if not before.has(i) or i >= enemy_plates.size():
			continue
		var lost: int = int(before[i]) - eng.enemies[i].hp
		var plate: Control = enemy_plates[i]
		if lost > 0:
			_float_number(plate, "-%d" % lost, Color(1.0, 0.62, 0.42))
			_hit(plate)
		elif lost < 0:
			_float_number(plate, "+%d" % (-lost), Color(0.62, 0.95, 0.62))

	var p_lost: int = int(before.get("player", eng.player.hp)) - eng.player.hp
	if p_lost > 0:
		_float_number(status_label, "-%d" % p_lost, Color(1.0, 0.5, 0.45))
		_flash_hurt(p_lost)
	elif p_lost < 0:
		_float_number(status_label, "+%d" % (-p_lost), Color(0.62, 0.95, 0.62))
	var gained_block: int = eng.player.block - int(before.get("block", eng.player.block))
	if gained_block > 0:
		_float_number(status_label, "+%d block" % gained_block, Color(0.62, 0.80, 1.0))

func _float_number(over: Control, text: String, colour: Color) -> void:
	if fx_layer == null or not is_inside_tree():
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

## Buffs and debuffs, written out, in the colour of what they are.
##
## `Combatant.status_text()` is the compact form used on the little enemy plates;
## it was also the player's only readout, tucked inside the status line as
## "[Blk 5 Str 3]". Strength changes every attack you make, so it belongs where it
## can be read at a glance — and on the cards themselves, which is what
## `CombatEngine.card_text()` now does.
func _refresh_buffs(p: Combatant) -> void:
	var good: Array[String] = []
	var bad: Array[String] = []
	if p.strength > 0:
		good.append("Strength +%d  (every attack hits harder)" % p.strength)
	if p.dexterity > 0:
		good.append("Dexterity +%d  (every Block is bigger)" % p.dexterity)
	if p.thorns > 0:
		good.append("Thorns %d" % p.thorns)
	if p.retain_block:
		good.append("Block persists")
	if p.vulnerable > 0:
		bad.append("Vulnerable %d  (you take +50%%)" % p.vulnerable)
	if p.weak > 0:
		bad.append("Weak %d  (you deal -25%%)" % p.weak)
	if p.poison > 0:
		bad.append("Poison %d  (ignores Block)" % p.poison)
	var parts := good + bad
	buffs_label.visible = not parts.is_empty()
	buffs_label.text = "   ·   ".join(parts)
	# warm for "this is helping you", cold for "this is happening to you"
	buffs_label.add_theme_color_override("font_color",
		Color(0.98, 0.85, 0.45) if bad.is_empty() else Color(0.95, 0.62, 0.55))

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
	piles_label.visible = false
	GameState.reset_run_progress()
	GameState.clear_run()
	GameState.flush_save()   # death is final; do not risk losing the penalty
	get_tree().change_scene_to_file("res://scenes/Defeat.tscn")

## Whatever is still standing gets the credit. The current target first: that is
## the one the player was looking at.
func _killer_name() -> String:
	var foe := eng.current_target()
	if foe != null and not foe.is_dead():
		return foe.name
	for e in eng.enemies:
		if not e.is_dead():
			return e.name
	return "something in the dark"
