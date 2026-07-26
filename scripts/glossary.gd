## Keyword reference, generated from the data rather than written out, so it cannot
## drift from the rules. Nothing in the game explained Vulnerable, escrow or ropes
## before this existed.
extends Control

func _ready() -> void:
	var col := UI.screen(self, "How This Works")
	var list := UI.scroll(col)

	_section(list, "Combat")
	_entry(list, "Energy", "You get %d energy a turn. Cards cost energy. Unspent energy is lost." % Balance.MAX_ENERGY)
	_entry(list, "Block", "Absorbs damage from the next attack, then expires at the start of your next turn. Legendary cards can make it persist instead.")
	_entry(list, "Vulnerable", "The target takes +50%% damage. One stack expires each turn.")
	_entry(list, "Weak", "The target deals -25%% damage. One stack expires each turn.")
	_entry(list, "Strength / Dexterity", "Permanent for the fight: +damage per attack, +block per block card.")
	_entry(list, "Poison", "Damage at the end of each turn that ignores Block entirely, losing one stack each time.")
	_entry(list, "Thorns", "Anything that attacks you takes this much damage back.")
	_entry(list, "Intent", "Each enemy shows what it will do next turn, and what would actually land after your Block.")
	_entry(list, "Escalation", "Enemies hit harder the longer a fight runs, so stalling is not a strategy.")

	_section(list, "A Run")
	_entry(list, "At risk", "Cards and gold found inside a dungeon are yours to use immediately, but only become permanent if you kill the boss — or spend an Escape Rope.")
	_entry(list, "Escape Rope", "Leave a dungeon and keep everything found. The dungeon stays uncleared, so no relic and no unlock. Found in treasures and from bosses; never sold.")
	_entry(list, "Dying", "You forfeit everything found in that run, lose some banked gold and %s card(s) from your collection, scaled by the dungeon's difficulty." % "a few")
	_entry(list, "Quitting", "Safe. The run is saved mid-fight and resumes exactly where you left it.")

	_section(list, "Between Runs")
	_entry(list, "Fusing", ("Spend copies AND gold to raise a card's level. Both prices rise "
		+ "with the level you are buying, so the cheap gains come early. Copies are deck "
		+ "width, gold is your next shop, levels are power — you cannot have all three."))
	_entry(list, "Level caps", "Commons level to %d, legendaries only to %d — but rarer cards gain far more per level." % [
		Balance.max_level(0), Balance.max_level(4)])
	_entry(list, "Deck size", "Between %d and %d cards, chosen fresh for every dungeon." % [
		Balance.MIN_DECK_SIZE, Balance.MAX_DECK_SIZE])
	_entry(list, "Exclusive cards", "Some cards exist in exactly one dungeon. Builds are deliberately spread out, so finishing one means clearing several places.")
	_entry(list, "Relics", "Permanent character upgrades from bosses. Never lost, even on death.")

	_section(list, "Statuses on enemies")
	for aid in ["cultist", "hexer", "warden"]:
		var a := load(Balance.ENEMY_DIR + aid + ".tres") as EnemyData
		if a != null:
			_entry(list, a.name, "Acts on a fixed, visible cycle. Learn the pattern and you can plan around it.")
			break

	UI.button(col, "Back", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

func _section(parent: Node, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", UITheme.title_font())
	parent.add_child(l)

func _entry(parent: Node, term: String, text: String) -> void:
	var t := Label.new()
	t.text = "  %s" % term
	t.add_theme_color_override("font_color", Icons.rarity_colour(2))
	parent.add_child(t)
	var d := Label.new()
	d.text = "      %s" % text
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(d)
