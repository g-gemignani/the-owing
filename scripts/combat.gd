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
var enemy_box: HBoxContainer
var hand_box: HBoxContainer
var log_label: Label
## The last few things that happened. One overwritten line lost most of a turn:
## three enemies acting reported only the third.
var log_lines: Array[String] = []
var reward_box: VBoxContainer
var end_btn: Button
var power_btn: Button
var menu_btn: Button

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
		eng.setup(GameState.run_deck, GameState.hp, GameState.max_hp, GameState.dungeon, tier,
			"", MetaState.relic_data(), roster, GameState.run_power,
			dd.boss if dd != null else "")
		_snapshot()
	_refresh()

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
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(16))
	margin.add_child(root)

	# The fight is serialized after every action, so leaving it is a pause, not an
	# escape: Resume comes straight back into this turn. Until this existed the
	# longest scene in the game was the only one with no way out of it at all.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.sep(12))
	root.add_child(header)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(status_label)

	menu_btn = UI.exit_button(header, "Menu", _pause, 38.0)

	# Buffs and debuffs on their own line, spelled out. They used to be a "[Blk 5
	# Str 3]" fragment inside a run-on status line, which is not where anybody
	# looks for the reason their damage changed — and the cards did not show the
	# change either, so Strength was effectively invisible while it was working.
	buffs_label = Label.new()
	buffs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buffs_label.add_theme_color_override("font_color", Color(0.98, 0.85, 0.45))
	root.add_child(buffs_label)

	log_label = Label.new()
	log_lines = ["Combat start."]
	log_label.text = log_lines[0]
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(log_label)

	# enemy row: click to pick a target (highlighted), shows HP + telegraphed intent
	enemy_box = HBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", UITheme.sep(10))
	root.add_child(enemy_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	reward_box = VBoxContainer.new()
	reward_box.add_theme_constant_override("separation", UITheme.sep())
	reward_box.visible = false
	root.add_child(reward_box)

	# What is left to draw, and what has gone by. The reward screen quotes how often
	# you will see a card ("every 3.0 turns instead of 2.8") and the shop sells deck
	# thinning, and until now the fight itself showed neither pile — the player was
	# asked to price consistency while blind to it.
	piles_label = Label.new()
	piles_label.add_theme_color_override("font_color", Color(0.78, 0.76, 0.72))
	root.add_child(piles_label)
	UI.hoverable(piles_label, "Your deck is drawn through, then the discard pile is shuffled back. A smaller deck comes round faster.")

	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", UITheme.sep())
	root.add_child(hand_box)

	# The power sits next to End Turn, not in the hand: it is always there, and
	# putting it among the cards would imply it can be drawn or discarded.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", UITheme.sep())
	root.add_child(bar)

	power_btn = Button.new()
	power_btn.custom_minimum_size = Vector2(UITheme.px(260), UITheme.px(44))
	power_btn.pressed.connect(_on_power_pressed)
	bar.add_child(power_btn)

	end_btn = Button.new()
	end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_btn.text = "End Turn"
	end_btn.custom_minimum_size = Vector2(0, UITheme.button_height(44))
	end_btn.pressed.connect(_on_end_turn)
	bar.add_child(end_btn)

func _on_power_pressed() -> void:
	var msg := eng.use_power()
	if msg == "":
		return
	Audio.play("buff" if eng.power != null and eng.power.eff_damage() == 0 else "attack")
	_log(msg)
	_after_action()

func _on_card_pressed(card: CardData) -> void:
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
	_after_action()

## Shared tail for anything the player does on their own turn: a kill may have
## ended the fight, and if not the run must be saved and the screen redrawn.
func _after_action() -> void:
	if eng.won():
		_win()
		return
	_snapshot()
	_refresh()

func _on_end_turn() -> void:
	var hp_before := eng.player.hp
	_log(eng.end_turn())
	if eng.player.hp < hp_before:
		Audio.play("hurt")
	if eng.lost():
		_lose()
		return
	if eng.won():
		_win()
		return
	_snapshot()
	_refresh()

func _refresh() -> void:
	var p := eng.player
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what would actually land after Block.")
	status_label.text = "%s  HP %d/%d   Block %d   Energy %d/%d   incoming %d" % [
		p.name, p.hp, p.max_hp, p.block,
		eng.energy, Balance.MAX_ENERGY + eng.bonus_energy, eng.enemy_intent]
	_refresh_buffs(p)

	# enemies
	for c in enemy_box.get_children():
		c.queue_free()
	for i in eng.enemies.size():
		var e: Combatant = eng.enemies[i]
		if e.is_dead():
			continue
		var b := Button.new()
		UITheme.style_button(b)
		var estat := e.status_text()
		var mark := "▶ " if i == eng.target else ""
		b.text = "%s%s\nHP %d/%d\n%s%s" % [
			mark, e.name, e.hp, e.max_hp, eng.intent_text(i),
			("\n[%s]" % estat) if estat != "" else ""]
		b.custom_minimum_size = UITheme.card_size()
		var arch := eng.archetypes[i] as EnemyData
		var etex := Icons.enemy(arch.id if arch != null else "cultist")
		if etex != null:
			b.icon = etex
			b.expand_icon = true
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.tooltip_text = "%s\nIntent: %s\nClick to target." % [e.name, eng.intent_text(i)]
		b.pressed.connect(_on_target_pressed.bind(i))
		enemy_box.add_child(b)

	# hand
	for c in hand_box.get_children():
		c.queue_free()
	# every card in the hand gets the SAME width, shrunk only if the row would
	# otherwise run past the edge of the window
	var base := UITheme.card_size()
	var avail := get_viewport_rect().size.x - UITheme.px(40)
	var w := Icons.fit_card_width(eng.hand.size(), base.x, avail, float(UITheme.sep()))
	for card in eng.hand:
		# `eng` passed in: the face quotes what this card does THIS turn, Strength,
		# Dexterity, Weak and per-combat growth included.
		var cb := UI.card_button(hand_box, card, Vector2(w, base.y),
			_on_card_pressed.bind(card), "", eng)
		# A card you cannot afford used to look exactly like one you could, and the
		# only way to find out was to click it and be refused. Dimmed, not disabled —
		# pressing it still explains why, which is how the rule gets learned.
		if not eng.can_play(card):
			var holder := cb.get_parent() as Control
			if holder != null:
				holder.modulate = Color(1, 1, 1, 0.45)

	piles_label.text = "Draw %d   ·   Discard %d   ·   Hand %d" % [
		eng.draw_pile.size(), eng.discard_pile.size(), eng.hand.size()]

	_refresh_power()

## The power button states the whole rule: what it does, what it costs, and — when
## it cannot be fired — WHY. "Used this turn" and "not enough energy" are different
## problems and a greyed button that says neither teaches nothing.
func _refresh_power() -> void:
	var p := eng.power
	if p == null:
		power_btn.visible = false
		return
	power_btn.visible = true
	var cost := "Free" if p.cost == 0 else "%dE" % p.cost
	power_btn.text = "%s  (%s)" % [p.name, cost]
	power_btn.disabled = not eng.can_use_power()
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
const LOG_LINES := 4

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
	GameState.earn_gold(g)   # at risk until the boss falls (D20)
	end_btn.disabled = true
	_seal_exit()
	for c in hand_box.get_children():
		c.queue_free()
	for c in enemy_box.get_children():
		c.queue_free()
	Audio.play("boss_cleared" if tier == Balance.Tier.BOSS else "reward")
	if MetaState.hint_once("first_reward"):
		_log("Rewards are AT RISK until you beat this dungeon's boss — or leave with an Escape Rope.")
	var healed := "  Healed %d." % relic_heal if relic_heal > 0 else ""
	status_label.text = "Encounter cleared. +%d gold (%d at risk).%s Choose a reward:" % [
		g, GameState.escrow_gold, healed]
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
	var wtbl: Array = Balance.reward_weights(tier, GameState.dungeon)
	for i in n:
		if pool.is_empty():
			break
		var loaded: Array = []
		var weights: Array = []
		var total := 0
		for id in pool:
			var c := load(MetaState.CATALOG[id]) as CardData
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
		var banked := GameState.commit_escrow()
		GameState.last_haul = "Secured %d cards and %d gold." % [banked["cards"], banked["gold"]]
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
