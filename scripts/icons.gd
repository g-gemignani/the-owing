## Art lookup. Everything is pixel art now (see PixelArt): symbols are authored
## 16x16 glyphs, enemies and UI panels are Kenney CC0 pixel packs.
##
## Every lookup still goes through here, so call sites ask for *meaning* rather
## than filenames and a missing asset degrades to null instead of crashing.
class_name Icons
extends RefCounted

## Semantic name -> pixel glyph.
const MAP := {
	"combat": "attack", "elite": "skull", "boss": "skull", "rest": "campfire",
	"shop": "gold", "event": "book", "treasure": "chest",
	"attack": "attack", "block": "block", "poison": "poison", "thorns": "thorns",
	"card": "card", "deck": "card", "collection": "card",
	"gold": "gold", "relic": "gold", "legendary": "gold",
	"rope": "rope", "dice": "dice", "hp": "heart",
	"locked": "block", "unlocked": "card", "unknown": "dice"
}

## Colour per rarity. Rarity is what a player reads at a glance, so it is carried
## by colour and not by text alone.
const RARITY_COLOURS := [
	Color(0.78, 0.78, 0.80),
	Color(0.45, 0.80, 0.50),
	Color(0.40, 0.62, 0.95),
	Color(0.72, 0.45, 0.92),
	Color(0.98, 0.72, 0.25)
]

static func tex(name: String) -> Texture2D:
	return PixelArt.symbol(String(MAP.get(name, name)))

## Pixel sprite for an enemy archetype.
static func enemy(archetype_id: String) -> Texture2D:
	return PixelArt.enemy_sprite(archetype_id)

## Icon for an encounter kind (Traversal.Enc / GameState.NodeType values).
static func for_encounter(enc: int) -> Texture2D:
	var names := ["combat", "elite", "rest", "boss", "shop", "event", "treasure"]
	if enc >= 0 and enc < names.size():
		return tex(names[enc])
	return tex("unknown")

static func rarity_colour(rarity: int) -> Color:
	return RARITY_COLOURS[clampi(rarity, 0, RARITY_COLOURS.size() - 1)]

## A card-shaped panel tinted by rarity, for use as a Button stylebox.
static func card_style(rarity: int, emphasis: float = 0.16) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var c := rarity_colour(rarity)
	sb.bg_color = Color(0.10, 0.09, 0.13).lerp(c, emphasis)
	sb.border_color = c
	sb.set_border_width_all(2)
	# square corners: rounded edges fight a pixel grid
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

## Give a button a rarity-tinted frame and an icon.
static func style_card_button(b: Button, rarity: int, icon_name: String = "") -> void:
	b.add_theme_stylebox_override("normal", card_style(rarity, 0.16))
	b.add_theme_stylebox_override("hover", card_style(rarity, 0.30))
	b.add_theme_stylebox_override("pressed", card_style(rarity, 0.36))
	b.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	b.tooltip_text = ""
	if icon_name != "":
		var t := tex(icon_name)
		if t != null:
			b.icon = t
			b.expand_icon = true
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP

## Full plain-English reading of a card, for tooltips. Generated from the data so
## it stays true when numbers or scaling change.
## `live_damage` / `live_block` come from `CombatEngine.card_damage()` /
## `card_block()` when the card is hovered inside a fight, so the hover quotes the
## same numbers the face does. Two independently generated descriptions of one
## card is how the face and the hover disagreed in the first place (D50).
static func card_tooltip(c: CardData, live_damage: int = -1, live_block: int = -1) -> String:
	if c == null:
		return ""
	var dmg: int = live_damage if live_damage >= 0 else c.eff_damage()
	var blk: int = live_block if live_block >= 0 else c.eff_block()
	var live := live_damage >= 0 or live_block >= 0
	var lines: Array[String] = []
	lines.append("%s — %s, cost %d" % [c.name, CardData.Rarity.keys()[c.rarity].to_lower(), c.cost])
	if dmg > 0:
		var d := "Deals %d damage" % dmg
		if c.hits > 1:
			d += " %d times" % c.hits
		if c.aoe:
			d += " to every enemy"
		if live and (c.strength_mult > 0 or c.damage_from_block):
			d += " right now"
		lines.append(d + ".")
	if c.damage_from_block:
		lines.append("Deals damage equal to your current Block.")
	if c.strength_mult > 0:
		lines.append("Deals %d extra damage per point of Strength." % c.strength_mult)
	if c.damage_per_poison > 0:
		lines.append("Deals %d extra damage per Poison stack already on the target." % c.damage_per_poison)
	if c.damage_per_thorns > 0:
		lines.append("Deals %d extra damage per point of Thorns you are wearing." % c.damage_per_thorns)
	if c.bonus_vs_debuffed > 0:
		lines.append("Deals %d extra damage if the target is Vulnerable or Weak." % c.bonus_vs_debuffed)
	if c.combo_at > 0 and c.combo_bonus > 0:
		lines.append("Worth %d more from your %s card of the turn onward." % [
			c.combo_bonus, ["", "first", "second", "third", "fourth"][mini(c.combo_at, 4)]])
	if c.energy_on_kill:
		lines.append("Refunds 1 Energy if it kills something.")
	if c.block_per_card_in_hand > 0:
		lines.append("Grants %d extra Block for each other card in your hand." % c.block_per_card_in_hand)
	if c.lifesteal:
		lines.append("Heals you for the damage it deals.")
	if blk > 0:
		lines.append("Grants %d Block (expires at the start of your next turn)." % blk)
	if c.double_block:
		lines.append("Doubles your current Block.")
	if c.eff_heal() > 0:
		lines.append("Heals %d HP." % c.eff_heal())
	if c.energy_gain > 0:
		lines.append("Grants %d Energy this turn." % c.energy_gain)
	if c.draw > 0:
		lines.append("Draws %d card(s)." % c.draw)
	if c.eff_vulnerable() > 0:
		lines.append("Vulnerable %d: target takes +50%% damage while it lasts." % c.eff_vulnerable())
	if c.eff_weak() > 0:
		lines.append("Weak %d: target deals -25%% damage while it lasts." % c.eff_weak())
	if c.eff_poison() > 0:
		lines.append("Poison %d: damage each turn end that ignores Block." % c.eff_poison())
	if c.eff_strength() > 0:
		lines.append("Strength +%d for the rest of the fight." % c.eff_strength())
	if c.eff_dexterity() > 0:
		lines.append("Dexterity +%d for the rest of the fight." % c.eff_dexterity())
	if c.eff_thorns() > 0:
		lines.append("Thorns +%d: attackers take damage back." % c.eff_thorns())
	if c.retain_block:
		lines.append("Your Block stops expiring for the rest of the fight.")
	if c.hp_cost > 0:
		lines.append("Costs %d HP to play (never lethal)." % c.hp_cost)
	if c.retain:
		lines.append("Stays in your hand at end of turn.")
	if c.exhaust:
		lines.append("Exhaust: playable once per fight.")
	if c.grows > 0:
		lines.append("Permanently gains +%d each time you play it this fight." % c.grows)
	lines.append("Level %d of %d." % [c.level, Balance.max_level(c.rarity)])
	return "\n".join(lines)

## Uniform card width for a hand of `count`, shrinking only when the row would
## otherwise run off screen.
##
## Hands are not a fixed size — draw effects and Scholar's Lens push them past the
## usual five — so a fixed width overflows the window exactly the way the map did.
## Every card in a row gets the SAME width: cards that differ in size read as a
## rendering bug, which is precisely how the previous version was reported.
static func fit_card_width(count: int, base_w: float, available_w: float, gap: float) -> float:
	if count <= 0:
		return base_w
	var total_gaps := gap * float(maxi(0, count - 1))
	var each := (available_w - total_gaps) / float(count)
	return maxf(48.0, minf(base_w, each))

## Icon for the dominant effect of a card, for a quick read of what it does.
static func for_card(c: CardData) -> String:
	if c == null:
		return "card"
	if c.apply_poison > 0:
		return "poison"
	if c.gain_thorns > 0:
		return "thorns"
	if c.damage > 0 or c.hits > 1 or c.damage_from_block or c.strength_mult > 0:
		return "attack"
	if c.block > 0 or c.double_block or c.retain_block:
		return "block"
	if c.heal > 0:
		return "hp"
	if c.gain_strength > 0 or c.gain_dexterity > 0 or c.gain_thorns > 0:
		return "relic"
	return "card"
