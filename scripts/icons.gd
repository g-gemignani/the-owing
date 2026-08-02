## Art lookup. Symbols are the painted 64x64 `ui/sym_*.png` set where one exists and
## the authored 16x16 glyphs where it does not (D115) — both white-on-transparent, so
## the tinting below reads the same against either.
##
## Every lookup still goes through here, so call sites ask for *meaning* rather
## than filenames and a missing asset degrades to null instead of crashing.
class_name Icons
extends RefCounted

## Semantic name -> symbol name. Values are GLYPH names, not filenames: `"hp": "heart"`
## routes through `PixelArt.SYMBOL_ART_ALIAS` to the painted `sym_hp.png` and still has a
## bitmap to land on if that file is ever absent. Pointing it straight at "hp" would look
## tidier and would resolve to nothing the moment the art moved.
##
## The nine rows added in D116 — pierce, strength, dexterity, vulnerable, weak, retain,
## exhaust, heal, energy — are the other half of that sentence: the painted set covers 21
## meanings and `GLYPHS` only ever had 13, so these have **no bitmap underneath them** and
## resolve through the painting or not at all. That is why they are written down here
## rather than left to `tex()`'s identity fallback, which would have resolved them just as
## well and been invisible: `tests/test_art.gd` walks `MAP`, so a row here is the thing
## that fails when `ui/sym_weak.png` goes missing. Nobody would notice otherwise — an
## unlisted name that stops resolving just draws nothing (D116).
##
## They also existed as *files* for three decisions before anything asked for one, which
## is the D115 lesson stated as a mapping: the manifest could see 21 paintings installed
## and the code could only say 13 things, so `for_card()` sent Strength cards to a stack
## of coins and healing to a heart. Every semantic name in here needs a caller; the ones
## that still have none are noted where their caller belongs.
const MAP := {
	"combat": "attack", "elite": "skull", "boss": "skull", "rest": "campfire",
	"shop": "gold", "event": "book", "treasure": "chest",
	"attack": "attack", "block": "block", "poison": "poison", "thorns": "thorns",
	# Enemy-side, not card-side: pierce is a share of an incoming hit that Block never
	# sees (`Balance.pierce_fraction`), so its reader is the intent telegraph, not a card.
	"pierce": "pierce",
	"strength": "strength", "dexterity": "dexterity",
	"vulnerable": "vulnerable", "weak": "weak",
	# Card keywords rather than dominant effects — no card in the game IS a retain, it
	# retains while doing something else — so `for_card()` deliberately cannot reach these
	# two. They belong on a keyword row on the card face, beside the rules text.
	"retain": "retain", "exhaust": "exhaust",
	"card": "card", "deck": "card", "collection": "card",
	# Three names, one coin, and still the honest answer: nobody painted a relic or a
	# rarity, so these are the doubling-up ART.md complains about that D116 does NOT fix.
	# `for_card` stopped routing Strength here, which leaves `relic` and `legendary`
	# waiting on `relics_screen.gd` and a painting of their own.
	"gold": "gold", "relic": "gold", "legendary": "gold",
	# Two meanings, two paintings, and conflating them is what `for_card` used to do: the
	# heart is how much life you have, `heal` is the act of getting some back.
	"rope": "rope", "dice": "dice", "hp": "heart", "heal": "heal",
	"energy": "energy",
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

## The plate for an enemy archetype, or null if one has not been generated. There is
## no second source any more: the CC0 sprite pool behind this went away with the
## positional assignment that handed it out (D89), and `combat.gd` already draws an
## empty footprint box when a plate is missing, which is honest where a wrong sprite
## was not.
static func enemy(archetype_id: String) -> Texture2D:
	return PixelArt.enemy_art(archetype_id)

## Icon for an encounter kind (Traversal.Enc / GameState.NodeType values).
static func for_encounter(enc: int) -> Texture2D:
	var names := ["combat", "elite", "rest", "boss", "shop", "event", "treasure"]
	if enc >= 0 and enc < names.size():
		return tex(names[enc])
	return tex("unknown")

static func rarity_colour(rarity: int) -> Color:
	return RARITY_COLOURS[clampi(rarity, 0, RARITY_COLOURS.size() - 1)]

## A card-shaped panel tinted by rarity, for use as a Button stylebox.
## Which family of card art this card wants.
##
## The ART manifest had its OWN copy of this classification — twelve families there,
## seven here, and filenames that did not even match (`cards/family_x.png` against
## the `cards/x.png` the loader looks for). A generated document exists so it cannot
## drift from the code; a generator with a private lookup table is the D34 bug with
## better manners. This is the one function, and `tools/art_manifest.gd` calls it.
##
## `for_card()` at the bottom of this file asks a *different* question — which small
## tintable symbol states the effect — and the two are deliberately not merged; the
## reasons are written out there, because that is the one that changed in D116.
static func card_family(c: CardData) -> String:
	if c == null:
		return "utility"
	if c.apply_poison > 0:
		return "poison"
	if c.gain_thorns > 0:
		return "thorns"
	if c.damage > 0 or c.hits > 1 or c.damage_from_block or c.strength_mult > 0:
		if c.aoe:
			return "attack_aoe"
		return "attack_multi" if c.hits > 1 else "attack"
	if c.block > 0 or c.double_block or c.retain_block:
		return "block"
	if c.heal > 0:
		return "heal"
	if c.gain_strength > 0:
		return "strength"
	if c.gain_dexterity > 0:
		return "dexterity"
	if c.eff_draw() > 0:
		return "draw"
	if c.energy_gain > 0:
		return "energy"
	if c.apply_vulnerable > 0:
		return "vulnerable"
	if c.apply_weak > 0:
		return "weak"
	return "utility"

## The painted card frame if one exists — per rarity first, then the shared one.
## Returns null when nobody has drawn them, and `card_style` below is what ships.
##
## The margins are the generator's `CARD_BORDER`, in texture pixels, and NOT the
## 40/40/48/56 that ART_ASSETS specs. A card is 150x132 on screen: a 48px top margin
## and a 56px bottom one leave 28px of stretchable middle, so Godot scales the
## margins down and the carved edge draws squashed instead of crisp — the same
## failure the buttons had (D83). Change these only alongside `gen_ui_kit.gd`.
const CARD_SLICE := 14

static func card_frame(rarity: int) -> StyleBox:
	for name in ["frame_card_rarity_%d" % clampi(rarity, 0, 4), "frame_card"]:
		var tex := PixelArt.ui_kit(name)
		if tex == null:
			continue
		var sb := StyleBoxTexture.new()
		sb.texture = tex
		sb.texture_margin_left = CARD_SLICE
		sb.texture_margin_right = CARD_SLICE
		sb.texture_margin_top = CARD_SLICE
		sb.texture_margin_bottom = CARD_SLICE
		return sb
	return null

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
	lines.append("%s — %s, cost %d" % [c.name, CardData.rarity_word(c.rarity).to_lower(), c.eff_cost()])
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
	if c.eff_draw() > 0:
		lines.append("Draws %s." % Wording.count(c.eff_draw(), "card"))
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
	if c.eff_hp_cost() > 0:
		lines.append("Costs %d HP to play (never lethal)." % c.eff_hp_cost())
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
##
## A **priority cascade, not a lookup**. Most cards do two or three things and this picks
## the one the card is *about*: `creeping_death` deals 5 and poisons for 4, and it is a
## poison card, so poison is tested first. Reordering these lines changes what the deck
## builder, the collection, the shop and every card face say about a hundred cards.
##
## Not the same question as `card_family()` above, and they must not be merged:
##
## * `card_family()` names a **painting to commission** — one illustration shared by every
##   card in the family, so it splits attacks three ways (a sweep, a flurry and a thrust
##   are three pictures) and has a `draw` family because "cards fanning out" is drawable.
## * this names a **symbol to state the effect** in a ~28px box. The painted set has one
##   attack glyph, so the three-way split would resolve to one file; and it has no draw
##   glyph, so a `draw` branch here could only return `card` — which is already the
##   fallback, meaning the branch would say nothing and would hide `energy` behind it.
##   `kick` is "+1 Energy, draw 1, exhaust" and the energy is the point of it.
##
## Six of the nine unwired paintings land here (D116). Before that the tail of this
## cascade was two wrong answers: healing went to `hp`, a heart, which is how much life
## you have rather than the act of restoring it; and Strength *and* Dexterity both went to
## `relic`, which `MAP` sends to `gold` — so a Strength card showed the player a stack of
## coins. Neither was a bug in the mapping, they were the closest of thirteen shapes.
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
		return "heal"
	if c.gain_strength > 0:
		return "strength"
	if c.gain_dexterity > 0:
		return "dexterity"
	if c.energy_gain > 0:
		return "energy"
	if c.apply_vulnerable > 0:
		return "vulnerable"
	if c.apply_weak > 0:
		return "weak"
	return "card"
