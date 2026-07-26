## Art manifest — every image the game wants, whether it exists, and what it is of.
##
## A diagnostic, not shipped. Emits ART_ASSETS.md on stdout:
##
##   godot --headless --script tools/art_manifest.gd > ART_ASSETS.md
##
## Why generated rather than written by hand: a hand-typed list of 35 enemy names is
## wrong the moment a 36th enemy lands, and this project has been bitten three times
## by a restated table going stale (D34). The catalogues in `resources/` are the
## source of truth for *which* files are wanted; the tables below are the source of
## truth for the ones no data file implies (frames, icons, fonts, VFX).
##
## The briefs come from the content's own `name` and `description`, so the artist is
## told what the game already says a thing is — not a second, drifting description.
##
## Path conventions are the ones ART.md specifies. They are stated ONCE, here, so the
## art-coverage test that ART.md §4 asks for can read them from this file instead of
## restating them.
extends SceneTree

const ART := "res://assets/art/"

## Fixed assets: nothing in `resources/` implies these, so they are listed.
## [path, size, brief]
const FRAME_KIT := [
	["ui/frame_button.png", "192x96", "Nine-slice 32/32/28/28. Carved stone edge, FLAT parchment centre — it is stretched up to 14x horizontally, so any lengthwise gradient or ragged edge becomes a smear."],
	["ui/frame_button_hover.png", "192x96", "Same frame, lit warmer."],
	["ui/frame_button_pressed.png", "192x96", "Same frame, pushed in / darker."],
	["ui/frame_button_disabled.png", "192x96", "Same frame, drained of colour."],
	["ui/frame_button_small.png", "96x96", "Nine-slice 12/12/12/12. For square icon buttons (+/- in the deck builder), which cannot wear the wide frame's 40px border."],
	["ui/frame_panel.png", "256x256", "Nine-slice 64/64/64/64, SYMMETRIC. Stone panel, flat interior."],
	["ui/frame_inset.png", "128x128", "Nine-slice 32/32/32/32. A dark recessed well for logs, lists and scroll areas."],
	["ui/frame_tooltip.png", "128x128", "Nine-slice 24/24/24/24. Small, high-contrast, sits over anything."],
	["ui/frame_card.png", "320x448", "Nine-slice 40/40/48/56. The card face: illustration band on top, rules text below."],
	["ui/frame_card_rarity_0.png", "320x448", "Common — plain stone/iron edge."],
	["ui/frame_card_rarity_1.png", "320x448", "Uncommon — green stone inlay."],
	["ui/frame_card_rarity_2.png", "320x448", "Rare — blue inlay, brighter metal."],
	["ui/frame_card_rarity_3.png", "320x448", "Epic — violet inlay, glow."],
	["ui/frame_card_rarity_4.png", "320x448", "Legendary — gold, ornate, unmistakable at a glance."],
	["ui/card_back.png", "320x448", "The back of a card. REQUIRED by the deck traversal, which reveals cards face-down."],
	["ui/divider.png", "128x16", "Tileable horizontally. A carved rule between sections."],
	["ui/dropdown.png", "192x96", "Nine-slice 32/32/28/28, matching the button. OptionButton is unstyled today."],
	["ui/dropdown_arrow.png", "32x32", "The open/close chevron."],
	["ui/slider_track.png", "128x24", "Tileable horizontally. HSlider is unstyled today."],
	["ui/slider_grabber.png", "48x48", "The slider handle."],
	["ui/scrollbar_track.png", "24x128", "Tileable vertically. VScrollBar is unstyled today."],
	["ui/scrollbar_grabber.png", "24x48", "The scrollbar thumb."],
	["ui/checkbox_on.png", "64x64", "Checked. Settings screen."],
	["ui/checkbox_off.png", "64x64", "Unchecked."],
]

## Deliberately empty. The fight is framed HEAD-ON into the corridor the backdrop
## paints, with no player character rendered: the room belongs to the enemies and
## the frame belongs to you. Four hero files were specced here before that was
## decided — a facing to match, an idle/hurt set to keep consistent with 35
## enemies, and a scale relationship to maintain, all for a figure that would stand
## in front of the one-point perspective these backdrops are built on.
##
## What replaces it is the HUD: vitals in the top band (Tier 1b), and an incoming
## hit reading as a flash and a jolt toward the camera, which is what combat.gd
## already does now that there is no body to animate instead.
const HERO := []

const VITALS := [
	["ui/bar_frame.png", "256x48", "Nine-slice. The empty HP/Block bar housing."],
	["ui/bar_hp_fill.png", "32x48", "Tileable horizontally. Current HP."],
	["ui/bar_hp_loss.png", "32x48", "Tileable. The slice about to be lost — this is how the enemy's telegraphed damage gets shown on the bar."],
	["ui/bar_block_fill.png", "32x48", "Tileable. Block, stacked over HP."],
	["ui/energy_orb_full.png", "128x128", "One unspent energy. Replaces the text 'Energy 3/3'."],
	["ui/energy_orb_empty.png", "128x128", "One spent energy, same silhouette."],
	["ui/orb_glow.png", "192x192", "Additive bloom for a spend/gain flash."],
	["ui/target_ring.png", "256x256", "Ring/reticle marking the targeted enemy. Replaces the '> ' text prefix."],
	["ui/card_glow.png", "320x448", "Additive edge glow: this card is affordable right now. Nothing marks it today."],
]

## Enemy intent. `eng.intent_text()` renders as the string 'hit 5' today, and the
## telegraph is the core read of the whole combat system.
const INTENTS := [
	["ui/intent_attack.png", "96x96", "Incoming single attack."],
	["ui/intent_attack_multi.png", "96x96", "Incoming multi-hit."],
	["ui/intent_block.png", "96x96", "It will defend."],
	["ui/intent_buff.png", "96x96", "It will strengthen itself."],
	["ui/intent_debuff.png", "96x96", "It will weaken you."],
	["ui/intent_poison.png", "96x96", "It will poison you."],
	["ui/intent_unknown.png", "96x96", "Intent hidden."],
]

## Status/effect symbols. Painted replacements for PixelArt.GLYPHS, which is 13
## monochrome bitmaps covering 21 needed meanings — so several currently share one.
## MUST stay monochrome-tintable: callers tint by rarity and fade for spent states.
const SYMBOLS := [
	["attack", "Damage."], ["block", "Block."], ["pierce", "Damage that ignores Block."],
	["poison", "Poison stacks."], ["thorns", "Damage returned to attackers."],
	["vulnerable", "Takes +50% damage."], ["weak", "Deals -25% damage."],
	["strength", "+damage per attack."], ["dexterity", "+block per block card."],
	["retain", "Stays in hand at end of turn."], ["exhaust", "Playable once per fight."],
	["hp", "Health."], ["heal", "Healing."], ["energy", "Energy."], ["gold", "Gold."],
	["card", "A card."], ["dice", "A die / the dice board."], ["skull", "Elite or boss."],
	["campfire", "Rest."], ["rope", "Escape Rope."], ["chest", "Treasure."],
]

const VFX := [
	["fx/slash.png", "8 frames of 256x256", "A weapon arc across the target."],
	["fx/impact.png", "8 frames of 256x256", "Blunt hit, dust and shock."],
	["fx/block_up.png", "8 frames of 256x256", "A ward snapping into place."],
	["fx/poison_cloud.png", "8 frames of 256x256", "Green miasma settling."],
	["fx/heal.png", "8 frames of 256x256", "Warm motes rising."],
	["fx/death_dissolve.png", "8 frames of 256x256", "An enemy coming apart. Plays on the kill."],
]

## Encounter kinds, in Traversal.Enc order. Used by the graph map (which draws NO
## icons today), the dice board and the deck traversal.
const ENCOUNTERS := [
	["combat", "An ordinary fight."],
	["elite", "A harder fight, worth more."],
	["rest", "A campfire: heal, or work on the deck."],
	["boss", "The named finale of the dungeon."],
	["shop", "A merchant."],
	["event", "A choice with consequences."],
	["treasure", "Gold, sometimes a card."],
]

const MAP_KIT := [
	["ui/node_frame_available.png", "192x192", "Nine-slice. This node can be entered — must be unmistakable."],
	["ui/node_frame_cleared.png", "192x192", "Already taken. Spent, dimmed."],
	["ui/node_frame_locked.png", "192x192", "Not reachable from here."],
	["ui/map_path.png", "32x16", "Tileable horizontally. The link between nodes — NOTHING connects them today."],
	["ui/token_player.png", "128x128", "The player's marker on the dice track."],
	["ui/reveal_frame.png", "320x448", "Nine-slice. Housing for the card the deck traversal reveals."],
]

const SHELL := [
	["fonts/display.ttf", "-", "Display face for titles and card names. Needs an OFL/SIL licence, recorded like the Kenney ones. THE GAME HAS NO CUSTOM FONT — everything is Godot's default."],
	["fonts/body.ttf", "-", "Body face for rules text. Must stay legible at 12px, since card text shrinks to fit."],
	["ui/logo.png", "1600x480", "The wordmark. The title screen currently draws a plain Label reading 'DECKCRAWL'."],
	["ui/boot_splash.png", "1280x720", "Boot splash. None configured."],
	["ui/cursor.png", "64x64", "Optional pointer."],
	["ui/cursor_press.png", "64x64", "Optional pressed pointer."],
]

## Scene backdrops that are not one dungeon or one zone.
const SCENE_BG := [
	["shop", "A merchant's stall underground. Wares, lantern light, a figure who has been waiting."],
	["rest", "A campfire in a safe corner. The one warm image in the game."],
	["event", "A shrine or crossroads — deliberately ambiguous, since 20 different events reuse it."],
	["treasure", "A small vault, chest open, gold catching the light."],
	["victory", "Dawn, or a door out. The payoff of the whole meta layer, currently a five-line text list."],
	["defeat", "Where the run ended. Quiet, not gory."],
]

var _rows: Array = []       # [path, size, brief, exists]
var _sections: Array = []   # [title, note, first_row_index, count]

func _init() -> void:
	_section("Tier 0 — frame kit and control chrome",
		"Highest leverage in the whole list: one kit and every screen stops looking broken.")
	for e in FRAME_KIT:
		_add(String(e[0]), String(e[1]), String(e[2]))

	_section("Tier 1b — vitals and selection", "HP, Block and Energy are all plain text today.")
	for e in VITALS:
		_add(String(e[0]), String(e[1]), String(e[2]))

	_section("Tier 1c — intent telegraphs", "Currently the string 'hit 5'.")
	for e in INTENTS:
		_add(String(e[0]), String(e[1]), String(e[2]))

	_section("Tier 1d — status symbols",
		"Monochrome and tintable, please: callers tint by rarity and fade spent states.")
	for e in SYMBOLS:
		_add("ui/sym_%s.png" % String(e[0]), "64x64", String(e[1]))

	_section("Tier 1e — combat VFX", "The game has no combat feedback animation at all.")
	for e in VFX:
		_add(String(e[0]), String(e[1]), String(e[2]))

	# --- data-driven from here down ------------------------------------------
	_enemies()
	_cards()
	_map_and_traversal()
	_backdrops()
	_relics()
	_powers()

	_section("Tier 7 — identity and shell", "Two of these are downloads, not drawings.")
	for e in SHELL:
		_add(String(e[0]), String(e[1]), String(e[2]))

	_emit()
	quit()

## Every archetype, with the dungeons that can field it and the shape it fights in.
func _enemies() -> void:
	var bosses := {}
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd != null and dd.boss != "":
			bosses[dd.boss] = dd.name
	var rosters := {}
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd == null:
			continue
		for aid in dd.enemy_roster:
			if not rosters.has(aid):
				rosters[aid] = []
			(rosters[aid] as Array).append(dd.name)

	_section("Tier 2 — enemies",
		"FACING THE VIEWER (the fight is framed head-on into the corridor; there is no hero on screen), lit from above-front to match the backdrops. Transparent, NO baked ground shadow — the stage draws a contact mark. **Feet flush with the bottom edge of the canvas, no bottom padding**: every enemy is placed on one standing line (`PixelArt.FLOOR_LINE`, measured at 68% of frame), so padding at the bottom of the file makes that enemy hover. Weight the silhouette low and dark — the floor is the BRIGHTEST band in every painted backdrop, so a pale-footed enemy dissolves into it. Filenames are archetype ids: `PixelArt.enemy_art(id)` looks them up directly, so a file lands on the enemy it was drawn for. (Do NOT put them in `assets/pixel/enemies/`, which is assigned positionally and would hand your file to whichever archetype the sort order reaches.)")
	for aid in PixelArt.archetype_ids():
		var a := load("res://resources/enemies/%s.tres" % aid) as EnemyData
		if a == null:
			continue
		var is_boss: bool = bosses.has(aid)
		var bits: Array[String] = ["**%s.**" % a.name]
		if is_boss:
			bits.append("The BOSS of %s." % String(bosses[aid]))
		elif rosters.has(aid):
			bits.append("Appears in: %s." % ", ".join(rosters[aid]))
		if a.count_max > 1:
			bits.append("Fights in groups of %d-%d, so it must read at small size." % [
				a.count_min, a.count_max])
		if a.hp_mult >= 1.1:
			bits.append("Tanky — draw it heavy.")
		elif a.hp_mult <= 0.7:
			bits.append("Fragile — draw it slight.")
		if a.dmg_mult >= 1.1:
			bits.append("Hits hard.")
		_add("enemies/%s.png" % aid, "512x512" if is_boss else "256x256",
			" ".join(bits))

## Card illustrations: shared per effect family first, unique art later.
func _cards() -> void:
	var fams := {}
	for cid in PixelArt.card_ids():
		var c := load("res://resources/cards/%s.tres" % cid) as CardData
		if c == null:
			continue
		var f := _family(c)
		if not fams.has(f):
			fams[f] = []
		(fams[f] as Array).append(c.name)
	var keys := fams.keys()
	keys.sort()

	_section("Tier 3 — card illustrations",
		"One per effect family to start, shared by every card in it — NOT 100 unique paintings up front. Illustration band only (top of the card face), so it never competes with the rules text. The 100 cards break down as below; unique art for the most-played can come later as `cards/<card_id>.png`, which is checked first.")
	for f in keys:
		var names: Array = fams[f]
		var sample: Array = names.slice(0, mini(4, names.size()))
		_add("cards/family_%s.png" % f, "320x240",
			"%d cards: %s%s" % [names.size(), ", ".join(sample),
				", ..." if names.size() > sample.size() else ""])

func _family(c: CardData) -> String:
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
	if c.draw > 0:
		return "draw"
	if c.energy_gain > 0:
		return "energy"
	if c.apply_vulnerable > 0:
		return "vulnerable"
	if c.apply_weak > 0:
		return "weak"
	return "utility"

func _map_and_traversal() -> void:
	_section("Tier 4 — map and traversal",
		"The graph map draws no icons at all today, and nothing connects its nodes.")
	for e in ENCOUNTERS:
		_add("ui/node_%s.png" % String(e[0]), "128x128", String(e[1]))
	for e in ENCOUNTERS:
		_add("ui/tile_%s.png" % String(e[0]), "128x128",
			"Dice-track version of the same: %s" % String(e[1]))
	for i in 6:
		_add("ui/die_%d.png" % (i + 1), "128x128",
			"A die showing %d. The two dice are currently the text 'dice: [3, 2]'." % (i + 1))
	for e in MAP_KIT:
		_add(String(e[0]), String(e[1]), String(e[2]))

func _backdrops() -> void:
	_section("Tier 5 — dungeon battle backdrops",
		"The single most VISIBLE gap: nine of twelve dungeons fall back to a 16x16 tinted tile. Match `bg_crypt.png`: symmetrical one-point perspective, 20-35% luminance, light source kept OUT of the top and bottom 34% where the combat text sits. NO text painted into the image — `bg_warrens.png` has a 'THE WARRENS' sign in it, which a rename or a translation turns into a lie.")
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd == null:
			continue
		var z := Balance.zone_of(did)
		var boss := Balance.boss_of(did)
		_add("bg_%s.png" % did, "1280x720",
			"%s (difficulty %d, %s). %s%s" % [dd.name, dd.difficulty,
				z.name if z != null else "?", dd.description,
				"  Its boss is %s." % boss.name if boss != null else ""])

	_section("Tier 5b — zone backdrops",
		"For the overworld and zone-select screens. Wider establishing shots, not fight arenas. All five are 16x16 tiles today.")
	for zid in Balance.ZONES:
		var zd := Balance.zone(zid)
		if zd == null:
			continue
		_add("bg_zone_%s.png" % zid, "1280x720", "%s. %s" % [zd.name, zd.description])

	_section("Tier 5c — scene backdrops", "One per non-combat screen.")
	for e in SCENE_BG:
		_add("bg_%s.png" % String(e[0]), "1280x720", String(e[1]))

func _relics() -> void:
	_section("Tier 6a — relic icons",
		"Painted objects on transparent, lit from upper-left, ink-outlined, readable at 48px. `relics_screen.gd` makes no icon call at all today — all 30 render as text rows.")
	for rid in MetaState.RELIC_CATALOG:
		var r := load(String(MetaState.RELIC_CATALOG[rid])) as RelicData
		if r == null:
			continue
		_add("relics/%s.png" % rid, "128x128", "%s — %s" % [r.name, r.description])

func _powers() -> void:
	_section("Tier 6b — power icons",
		"A power is fired once per turn, every turn, so its icon is seen constantly. Several currently share one monochrome glyph.")
	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p == null:
			continue
		_add("powers/%s.png" % pid, "128x128", "%s — %s" % [p.name, p.description])

# --- plumbing ----------------------------------------------------------------

func _section(title: String, note: String) -> void:
	_sections.append([title, note, _rows.size(), 0])

func _add(rel: String, size: String, brief: String) -> void:
	var path := ART + rel
	var exists := ResourceLoader.exists(path) or FileAccess.file_exists(path)
	_rows.append([rel, size, brief, exists])
	if not _sections.is_empty():
		_sections[-1][3] = _rows.size() - int(_sections[-1][2])

func _emit() -> void:
	var have := 0
	for r in _rows:
		if bool(r[3]):
			have += 1
	print("<!-- GENERATED by tools/art_manifest.gd — do not edit by hand.")
	print("     Regenerate: godot --headless --script tools/art_manifest.gd > ART_ASSETS.md -->")
	print("")
	print("# ART_ASSETS.md — the files to provide")
	print("")
	print("Every image the game will look for, generated from the content catalogues so it")
	print("cannot fall out of step with them. The *why* behind all of it is [ART.md](ART.md);")
	print("this is the shopping list.")
	print("")
	print("**%d files wanted · %d already present · %d to provide.**" % [
		_rows.size(), have, _rows.size() - have])
	print("")
	print("Paths are relative to `assets/art/`. Author UI assets at **2x** and downsample:")
	print("`UITheme.scale` runs 0.6-3.0 and the nine-slice margins do not scale with it.")
	print("Every painted asset needs `texture_filter = LINEAR` at its node — `project.godot`")
	print("sets NEAREST globally for the pixel assets, which would alias smooth art.")
	print("")
	for s in _sections:
		var count := int(s[3])
		if count <= 0:
			continue
		var start := int(s[2])
		var missing := 0
		for i in range(start, start + count):
			if not bool(_rows[i][3]):
				missing += 1
		print("## %s" % String(s[0]))
		print("")
		print("*%d files, %d still to provide.* %s" % [count, missing, String(s[1])])
		print("")
		print("| ? | file | size | what it is |")
		print("|---|---|---|---|")
		for i in range(start, start + count):
			var r: Array = _rows[i]
			print("| %s | `%s` | %s | %s |" % [
				"x" if bool(r[3]) else " ", String(r[0]), String(r[1]),
				String(r[2]).replace("|", "\\|")])
		print("")
