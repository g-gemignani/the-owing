## Non-combat encounter screen: events (choices with declarative effects) and
## treasure (gold, sometimes a card).
##
## All effects are applied HERE rather than inside the data, so run rules are
## enforced in one place: HP never drops below 1, gold never goes negative, and
## card loss respects the collection floor that prevents softlocks.
##
## Deliberately registers no `UI.exit_button`: an event is a decision, and every
## event offers a cost-free option (asserted by tests/test_event.gd), so there is
## nothing to be trapped by. Backing out with Escape would leave the node
## unresolved and re-rollable, which is a different way of taking the good branch.
extends Control

var title_label: Label
var body_label: Label
var result_label: Label
var options_box: VBoxContainer
var resolved := false

func _ready() -> void:
	_build_ui()
	if int(GameState.pending.get("type", -1)) == GameState.NodeType.TREASURE:
		_show_treasure()
	else:
		_show_event()

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", UITheme.sep(12))
	margin.add_child(root)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", UITheme.title_font())
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title_label)

	body_label = Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(body_label)

	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(result_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", UITheme.sep(8))
	root.add_child(options_box)

func _status() -> String:
	return "HP %d/%d    Gold %d (%d at risk)" % [
		GameState.hp, GameState.max_hp, GameState.available_gold(), GameState.escrow_gold]

# ---------------- events ----------------
var ev: EventData

func _show_event() -> void:
	ev = _pick_event()
	if ev == null:
		_finish()
		return
	title_label.text = ev.title
	body_label.text = "%s\n\n%s" % [ev.description, _status()]
	for i in ev.choice_count():
		var b := Button.new()
		UITheme.style_button(b)
		b.text = ev.choice_labels[i]
		b.custom_minimum_size = Vector2(0, UITheme.button_height(40))
		# do not offer a choice the player cannot pay for
		if GameState.available_gold() + ev.gold_delta(i) < 0:
			b.disabled = true
			b.text += "  (not enough gold)"
		else:
			b.pressed.connect(_on_choice.bind(i))
		options_box.add_child(b)

func _pick_event() -> EventData:
	var pool := Balance.EVENTS.duplicate()
	pool.shuffle()
	for id in pool:
		var e := load(Balance.EVENT_DIR + id + ".tres") as EventData
		if e != null and e.choice_count() > 0:
			return e
	return null

func _on_choice(i: int) -> void:
	if resolved:
		return
	resolved = true
	for c in options_box.get_children():
		c.queue_free()

	var lines: Array[String] = [ev.result_text(i)]

	# HP: flat and percent-of-max, never lethal (an event should not kill you)
	var hp := ev.hp_delta(i) + int(round(GameState.max_hp * ev.hp_percent(i) / 100.0))
	if hp != 0:
		GameState.hp = clampi(GameState.hp + hp, 1, GameState.max_hp)
		lines.append("%s %d HP." % ["Gained" if hp > 0 else "Lost", abs(hp)])

	var gold := ev.gold_delta(i)
	if gold > 0:
		GameState.earn_gold(gold)
		lines.append("Gained %d gold." % gold)
	elif gold < 0:
		GameState.spend_gold(-gold)
		lines.append("Paid %d gold." % -gold)

	var cd := ev.card_delta(i)
	if cd > 0:
		var got := _grant_card()
		if got != "":
			lines.append("Gained %s." % got)
	elif cd < 0:
		var lost := _lose_card()
		lines.append("Lost %s." % lost if lost != "" else "Nothing could be taken.")

	if ev.relic_grant(i) > 0:
		var rid := MetaState.grant_relic(Balance.Tier.ELITE)
		if rid != "":
			var r := load(MetaState.RELIC_CATALOG[rid]) as RelicData
			lines.append("Gained relic: %s." % (r.name if r != null else rid))
		else:
			lines.append("Nothing new to give.")

	if ev.fights(i):
		# the encounter becomes an elite fight; combat returns to the run afterwards
		GameState.pending = {"type": GameState.NodeType.ELITE}
		get_tree().change_scene_to_file("res://scenes/Combat.tscn")
		return

	result_label.text = "\n".join(lines) + "\n\n" + _status()
	var cont := Button.new()
	UITheme.style_button(cont)
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, UITheme.button_height(40))
	cont.pressed.connect(_finish)
	options_box.add_child(cont)

# ---------------- treasure ----------------
func _show_treasure() -> void:
	title_label.text = "Treasure"
	var gold := Balance.TREASURE_GOLD_MIN + randi() % maxi(1, Balance.TREASURE_GOLD_MAX - Balance.TREASURE_GOLD_MIN + 1)
	gold += int(round(gold * MetaState.relic_bonus("gold_percent") / 100.0))
	GameState.earn_gold(gold)
	var lines: Array[String] = ["You find %d gold." % gold]
	if randi() % 100 < Balance.TREASURE_CARD_CHANCE:
		var got := _grant_card()
		if got != "":
			lines.append("Tucked underneath: %s." % got)
	if randi() % 100 < Balance.TREASURE_ROPE_CHANCE:
		MetaState.add_item("escape_rope")
		lines.append("Also here: an Escape Rope. A way out, if you want one.")
	body_label.text = "\n".join(lines) + "\n\n" + _status()
	var cont := Button.new()
	UITheme.style_button(cont)
	cont.text = "Continue"
	cont.custom_minimum_size = Vector2(0, UITheme.button_height(40))
	cont.pressed.connect(_finish)
	options_box.add_child(cont)

# ---------------- shared ----------------
## Grant a card from this dungeon's pool (so exclusives stay exclusive), added to
## both the collection and the current run deck, matching reward semantics (D1).
func _grant_card() -> String:
	var pool: Array = GameState.card_pool()
	if pool.is_empty():
		pool = MetaState.CATALOG.keys()
	pool = pool.filter(func(id): return MetaState.CATALOG.has(id))
	if pool.is_empty():
		return ""
	var id: String = pool[randi() % pool.size()]
	GameState.earn_card(id)          # at risk until the boss falls (D20)
	var c := load(MetaState.CATALOG[id]) as CardData
	return c.name if c != null else id

## Remove one owned copy, but never below the collection floor (softlock guard).
func _lose_card() -> String:
	if MetaState.total_copies() - 1 < Balance.MIN_KEEP:
		return ""
	var ids: Array = MetaState.collection.keys()
	if ids.is_empty():
		return ""
	var id: String = ids[randi() % ids.size()]
	var c := load(MetaState.CATALOG[id]) as CardData
	MetaState.collection[id]["count"] -= 1
	if int(MetaState.collection[id]["count"]) <= 0:
		MetaState.collection.erase(id)
	MetaState.save_game()
	return c.name if c != null else id

func _finish() -> void:
	GameState.clear_node(GameState.pending)
	GameState.autosave()
	get_tree().change_scene_to_file(GameState.run_scene())
