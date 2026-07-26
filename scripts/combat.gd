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
var enemy_box: HBoxContainer
var hand_box: HBoxContainer
var log_label: Label
var reward_box: VBoxContainer
var end_btn: Button
var power_btn: Button

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

func _tier_of(node_type: int) -> int:
	match node_type:
		GameState.NodeType.ELITE: return Balance.Tier.ELITE
		GameState.NodeType.BOSS: return Balance.Tier.BOSS
		_: return Balance.Tier.NORMAL

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(16))
	margin.add_child(root)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", UITheme.title_font())
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	log_label = Label.new()
	log_label.text = "Combat start."
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
	end_btn.custom_minimum_size = Vector2(0, UITheme.px(44))
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
	var pstat := p.status_text()
	UI.hoverable(status_label, "Block expires at the start of your next turn. 'incoming' is what would actually land after Block.")
	status_label.text = "%s HP %d/%d %s | Energy %d/%d | D%d | incoming %d" % [
		p.name, p.hp, p.max_hp, ("[%s]" % pstat) if pstat != "" else "",
		eng.energy, Balance.MAX_ENERGY + eng.bonus_energy, eng.dungeon, eng.enemy_intent]

	# enemies
	for c in enemy_box.get_children():
		c.queue_free()
	for i in eng.enemies.size():
		var e: Combatant = eng.enemies[i]
		if e.is_dead():
			continue
		var b := Button.new()
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
		UI.card_button(hand_box, card, Vector2(w, base.y), _on_card_pressed.bind(card))

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
		p.name, p.description, why])

func _on_target_pressed(i: int) -> void:
	if eng.set_target(i):
		_refresh()

func _log(msg: String) -> void:
	log_label.text = msg

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
		UI.card_button(row, card, Vector2(rw, rbase.y), _on_reward_picked.bind(card),
			"%s\n(%d) [%s]\n%s" % [card.name, card.cost,
				CardData.Rarity.keys()[card.rarity], card.description])
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
	for c in hand_box.get_children():
		c.queue_free()
	Audio.play("defeat")
	GameState.combat_state = {}
	# D20: the run's earnings are forfeited — that is now the primary cost of dying.
	var lost := GameState.forfeit_escrow()
	# D3: plus a (retuned) permanent penalty scaled by dungeon difficulty.
	var pen := MetaState.penalize_death(GameState.dungeon)
	var lost_cards: Array = pen["cards_lost"]
	var cards_txt := ", ".join(lost_cards) if not lost_cards.is_empty() else "none"
	status_label.text = "DEFEAT. Forfeited %d cards and %d gold earned here. Also lost %d banked gold%s." % [
		lost["cards"], lost["gold"], pen["gold_lost"],
		" and: %s" % cards_txt if cards_txt != "none" else ""]
	GameState.reset_run_progress()
	GameState.clear_run()
	GameState.flush_save()   # death is final; do not risk losing the penalty
	await get_tree().create_timer(2.5).timeout
	get_tree().change_scene_to_file("res://scenes/Overworld.tscn")
