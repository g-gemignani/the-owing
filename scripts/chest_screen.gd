## A chest. Deliberately NOT the event screen (D84).
##
## Chests and events shared `Encounter.tscn` for as long as a chest was "gold, and
## sometimes a card" — one line of text either way. Once a chest grew a tier, a
## lock, a key cost and a vault condition, sharing the screen made two different
## kinds of moment read as one: an event is a *decision* with options to weigh, and
## a chest is a *thing you found*, which you open or fail to open. The event screen
## says "choose"; this screen says "here is what it is, and here is whether you got
## in".
##
## So the difference is stated in the layout rather than only in the prose: the tier
## is the headline and is coloured, what it wants is on its own line above the
## result, and the contents are shown as pack rows rather than a paragraph.
extends Control

var body: VBoxContainer

func _ready() -> void:
	# the treasure plate is not installed yet; the event room is the nearest lit
	# space and beats rendering the whole screen on black
	if not UI.scene_backdrop(self, "treasure"):
		UI.scene_backdrop(self, "event")
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	UITheme.pad(margin)
	add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", UITheme.sep(10))
	margin.add_child(body)
	_open()

func _open() -> void:
	# The tier the FLOOR was showing, not a fresh roll (D172). A chest's tier is its lock,
	# and rolling it here meant the lock came into existence at the moment it was too late to
	# do anything about — the player had already spent the turn walking in. The crawl casts it
	# when the floor is laid out and hands it over on `pending`; the roll survives as the
	# fallback for a chest that arrived from anywhere else, and for a save that predates this.
	var tier := String(GameState.pending.get("chest", ""))
	if not (tier in Balance.PACK_TIERS):
		tier = Balance.roll_pack_tier(Balance.PACK_TREASURE, GameState.dungeon)
	var lock := Balance.chest_lock(tier)
	var build_id := Balance.roll_pack_build(GameState.dungeon_id)

	var title := Label.new()
	title.text = "%s Chest" % Balance.PACK_TIER_NAME.get(tier, "Worn")
	UITheme.style_title(title)
	title.add_theme_color_override("font_color", Icons.pack_tier_colour(tier))
	body.add_child(title)

	var gold := Balance.TREASURE_GOLD_MIN + randi() % maxi(1, Balance.TREASURE_GOLD_MAX - Balance.TREASURE_GOLD_MIN + 1)
	gold += int(round(gold * MetaState.relic_bonus("gold_percent") / 100.0))
	GameState.earn_gold(gold)

	# What it wants, before what happened — the order the player experiences it in,
	# and the reason a failed vault is a disappointment rather than a trick.
	var opened := true
	match lock:
		Balance.CHEST_LOCK_KEY:
			if GameState.keys > 0:
				GameState.keys -= 1
				UI.label(body, "Locked. You have a key, and spend it.")
			else:
				opened = false
				# Says where a key comes from, because this screen is where the player
				# finds out they needed one and the answer is a place, not a chance:
				# keys lie on the floors of the dungeon (D167).
				UI.label(body, "Locked, and you have no key. It stays shut. Keys lie on the dungeon's own floors — off the path, where nothing else is.")
		Balance.CHEST_LOCK_VAULT:
			var cond: String = Balance.VAULTS[randi() % Balance.VAULTS.size()]
			var demand := UI.label(body, "A vault: it %s." % Balance.vault_text(cond, build_id))
			demand.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40))
			opened = _vault_met(cond, build_id)
			UI.label(body, "It reads you, and opens." if opened else "It reads you, and stays shut.")
		_:
			UI.label(body, "Unlocked. The lid lifts at a touch.")

	var haul := UI.label(body, "You take %d gold." % gold)
	haul.add_theme_font_size_override("font_size", UITheme.title_font())

	if opened:
		var n := Balance.chest_packs(tier)
		for i in n:
			GameState.earn_pack(Balance.PACK_TREASURE, "", tier)
		# each pack listed as an object, because that is what it is — a paragraph
		# saying "3 sealed packs" is the event screen's voice, not this one's
		var mine: Array = GameState.escrow_packs
		for i in range(maxi(0, mine.size() - n), mine.size()):
			var p: Dictionary = mine[i]
			var row := UI.label(body, "   %s   (%d cards)" % [
				Balance.pack_title(String(p.get("tier", Balance.PACK_WORN)),
					String(p.get("build", ""))),
				Balance.pack_cards(String(p.get("tier", Balance.PACK_WORN)))])
			row.add_theme_color_override("font_color",
				Icons.pack_tier_colour(String(p.get("tier", Balance.PACK_WORN))))
		UI.label(body, "Sealed. They leave with you, if you do.")
		# A chest is the other place a floor can pay a relic (D240). The elite is the first, and a
		# floor holding neither is a floor with no escalation on it at all — which is what made
		# "one decision per floor" the intent of D231 step 4. Three to choose from, bucketed toward
		# what the deck already does, exactly as the elite offers them: the point is not the relic,
		# it is that the player chose it.
		#
		# It costs the movement budget NOTHING. A chest already stands on the floor and is already
		# walked to; the tile is paid for. D84 established that adding a REASON to walk somewhere
		# lowers moves-per-encounter rather than raising it, and D79 established that adding tiles
		# to reach it is the part that has to be budgeted first. This adds a reason and no tiles.
		var offer: Array = MetaState.relic_offer(Balance.Tier.NORMAL, GameState.run_deck, 3,
			GameState.run_relics)
		if not offer.is_empty():
			UI.spacer(body)
			var rh := UI.label(body, "And something older, under the packs. Take one.")
			rh.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40))
			_relic_row(offer)
	else:
		UI.label(body, "Whatever was inside stays inside.")

	if randi() % 100 < Balance.TREASURE_ROPE_CHANCE:
		MetaState.add_item("escape_rope")
		UI.label(body, "   An Escape Rope, tucked beside it. A way out, if you want one.")

	UI.spacer(body)
	UI.label(body, "HP %d/%d    Gold %d (%d at risk)    Keys %d" % [
		GameState.hp, GameState.max_hp, GameState.available_gold(),
		GameState.escrow_gold, GameState.keys])
	UI.button(body, "Continue", _finish, 40.0)
	# Escape means Continue here, unlike the event screen, which deliberately has no
	# way out (an event is a decision you owe an answer to). A chest has already
	# resolved by the time it is on screen — there is nothing left to decide, so
	# trapping the player on it would be ceremony.
	UI.escape(self, _finish)

## The three on offer, and the one press that resolves them.
##
## Rebuilt on a pick rather than disabled, for the reason the combat reward panel is: a dead row of
## buttons above a live Continue reads as a bug.
func _relic_row(offer: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.sep())
	body.add_child(row)
	for rid in offer:
		var rd := load(String(MetaState.RELIC_CATALOG[rid])) as RelicData
		if rd == null:
			continue
		var b := Button.new()
		UITheme.style_button(b)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = UITheme.px(190)
		b.text = "%s\n%s" % [rd.name, rd.description]
		UI.hoverable(b, ("You have met this one before." if MetaState.seen_relic(String(rid))
			else "You have never seen this one.") + " It is yours until this run ends.")
		b.pressed.connect(func():
			GameState.earn_relic(String(rid))
			Audio.play("treasure")
			for c in row.get_children():
				(c as Button).disabled = true
			(row.get_parent() as VBoxContainer).move_child(row, row.get_index())
			UI.label(body, "   You take %s." % rd.name))
		row.add_child(b)

## Does the run satisfy this vault? Every check reads state the player can see on
## the screen they came from, which is what makes the condition a decision rather
## than a dice roll.
func _vault_met(cond: String, build_id: String) -> bool:
	match cond:
		Balance.VAULT_RICH:
			return GameState.available_gold() >= Balance.VAULT_GOLD
		Balance.VAULT_ARMED:
			var b := Balance.build(build_id)
			if b == null:
				return false
			for c in GameState.run_deck:
				if c != null and String(c.id) in Array(b.cards):
					return true
			return false
		Balance.VAULT_THIN:
			return GameState.run_deck.size() <= Balance.MIN_DECK_SIZE + Balance.VAULT_THIN_SLACK
		Balance.VAULT_LADEN:
			return GameState.escrow_packs.size() >= Balance.VAULT_LADEN_PACKS
		_:
			return float(GameState.hp) >= Balance.VAULT_HP_FRAC * float(GameState.max_hp)

func _finish() -> void:
	GameState.clear_node(GameState.pending)
	GameState.autosave()
	get_tree().change_scene_to_file(GameState.run_scene())
