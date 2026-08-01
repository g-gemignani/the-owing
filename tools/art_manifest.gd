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
##
## Second mode, same tables — the prompts for generating the missing art:
##
##   godot --headless --script tools/art_manifest.gd -- --prompts > ART_PROMPTS.md
##
## Same reason as the first: a hand-kept prompt sheet goes stale against the
## catalogues, and a prompt that names an enemy the game no longer has produces a
## painting with nowhere to go. It also encodes which files must NOT be generated —
## nine-slices are computed (D83) and fonts are licensed downloads — because the
## expensive mistake is not a bad painting, it is a good painting of the wrong thing.
extends SceneTree

const ART := "res://assets/art/"

## How a file gets MADE. The manifest lists what is wanted; this says by what.
enum Kind {
	PAINT,    ## image generator, subject on a flat field -> tools/install_cutouts.gd
	SCENE,    ## image generator, full-bleed opaque 1280x720 -> tools/install_*backdrops.gd
	KIT,      ## COMPUTED by tools/gen_ui_kit.gd. A nine-slice or a tileable strip.
	SHEET,    ## an animation. Frame-to-frame coherence is not something to prompt for.
	LICENCE,  ## a download with a licence, not a drawing.
}

## Fixed assets: nothing in `resources/` implies these, so they are listed.
## [path, size, brief] — or [path, size, brief, kind] where the row differs from its
## section's default. The frame kit is the mixed one: the frames themselves are
## computed and the loose objects that sit beside them are painted.
const FRAME_KIT := [
	["ui/frame_button.png", "192x96", "GENERATED, do not paint: `tools/gen_ui_kit.gd`. Nine-slice 12/12/12/12, carved slate edge, FLAT face. Stretched up to 14x horizontally, so the top/bottom strips must be constant along X, the left/right constant along Y, and the middle one colour — painted art breaks all three and smears (D83)."],
	["ui/frame_button_hover.png", "192x96", "Same frame, lit. Generated."],
	["ui/frame_button_pressed.png", "192x96", "Same frame, bevel inverted. Generated."],
	["ui/frame_button_disabled.png", "192x96", "Same frame, drained of colour. Generated."],
	["ui/frame_button_small.png", "96x96", "The square frame, for the 40px +/- buttons in the deck builder, which cannot wear the wide frame's corners. Generated."],
	["ui/frame_panel.png", "256x256", "Nine-slice 64/64/64/64, SYMMETRIC. Stone panel, flat interior."],
	["ui/frame_inset.png", "128x128", "Nine-slice 32/32/32/32. A dark recessed well for logs, lists and scroll areas."],
	["ui/frame_tooltip.png", "128x128", "Nine-slice 24/24/24/24. Small, high-contrast, sits over anything."],
	["ui/frame_card.png", "320x448", "Nine-slice 40/40/48/56. The card face: illustration band on top, rules text below."],
	["ui/frame_card_rarity_0.png", "320x448", "Common — plain stone/iron edge."],
	["ui/frame_card_rarity_1.png", "320x448", "Uncommon — green stone inlay."],
	["ui/frame_card_rarity_2.png", "320x448", "Rare — blue inlay, brighter metal."],
	["ui/frame_card_rarity_3.png", "320x448", "Epic — violet inlay, glow."],
	["ui/frame_card_rarity_4.png", "320x448", "Legendary — gold, ornate, unmistakable at a glance."],
	["ui/card_back.png", "320x448", "The back of a card. REQUIRED by the deck traversal, which reveals cards face-down.", Kind.SCENE],
	["ui/divider.png", "128x16", "Tileable horizontally. A carved rule between sections."],
	["ui/dropdown.png", "192x96", "Nine-slice 32/32/28/28, matching the button. OptionButton is unstyled today."],
	["ui/dropdown_arrow.png", "32x32", "The open/close chevron.", Kind.PAINT],
	["ui/slider_track.png", "128x24", "Tileable horizontally. HSlider is unstyled today."],
	["ui/slider_grabber.png", "48x48", "The slider handle.", Kind.PAINT],
	["ui/scrollbar_track.png", "24x128", "Tileable vertically. VScrollBar is unstyled today."],
	["ui/scrollbar_grabber.png", "24x48", "The scrollbar thumb.", Kind.PAINT],
	["ui/checkbox_on.png", "64x64", "Checked. Settings screen.", Kind.PAINT],
	["ui/checkbox_off.png", "64x64", "Unchecked.", Kind.PAINT],
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
	["ui/energy_orb_full.png", "128x128", "One unspent energy. Replaces the text 'Energy 3/3'.", Kind.PAINT],
	["ui/energy_orb_empty.png", "128x128", "One spent energy, same silhouette.", Kind.PAINT],
	["ui/orb_glow.png", "192x192", "Additive bloom for a spend/gain flash.", Kind.PAINT],
	["ui/target_ring.png", "256x256", "Ring/reticle marking the targeted enemy. Replaces the '> ' text prefix.", Kind.PAINT],
	["ui/card_glow.png", "320x448", "Additive edge glow: this card is affordable right now. Nothing marks it today.", Kind.PAINT],
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
	["ui/node_frame_available.png", "192x192", "Nine-slice. This node can be entered — must be unmistakable.", Kind.KIT],
	["ui/node_frame_cleared.png", "192x192", "Already taken. Spent, dimmed.", Kind.KIT],
	["ui/node_frame_locked.png", "192x192", "Not reachable from here.", Kind.KIT],
	["ui/map_path.png", "32x16", "Tileable horizontally. The link between nodes — NOTHING connects them today.", Kind.KIT],
	["ui/token_player.png", "128x128", "The player's marker on the dice track."],
	["ui/reveal_frame.png", "320x448", "Nine-slice. Housing for the card the deck traversal reveals.", Kind.KIT],
]

const SHELL := [
	["fonts/display.ttf", "-", "Display face for titles and card names. Needs an OFL/SIL licence, recorded like the Kenney ones. THE GAME HAS NO CUSTOM FONT — everything is Godot's default.", Kind.LICENCE],
	["fonts/body.ttf", "-", "Body face for rules text. Must stay legible at 12px, since card text shrinks to fit.", Kind.LICENCE],
	["ui/logo.png", "1600x480", "The wordmark. The title screen currently draws a plain Label reading 'DECKCRAWL'. The ONE asset that has to carry text: generate the ornament, set the type yourself.", Kind.PAINT],
	["ui/boot_splash.png", "1280x720", "Boot splash. None configured.", Kind.SCENE],
	["ui/cursor.png", "64x64", "Optional pointer.", Kind.PAINT],
	["ui/cursor_press.png", "64x64", "Optional pressed pointer.", Kind.PAINT],
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

## Pasted at the top of EVERY generation request, unchanged. The single biggest lever
## on coherence is not the model, it is that this block and one reference image are
## identical across 113 calls — the twelve backdrops agree with each other because
## they were asked for the same way, and the four visual languages ART.md §1 diagnoses
## are four different asks, not four different tools.
const PREAMBLE := """Painted dark-fantasy storybook illustration, in the style of the attached reference image.
Match the reference for line weight, palette and lighting; do not match its subject or composition.
LINE: every form carries a dark ink outline, weight ~2-3px at 1280x720.
PAINT: flat-to-soft interiors. Not photographic, not a 3D render, not cel-shaded anime, no lens blur, no chromatic aberration.
PALETTE: cool desaturated violet-grey stone base. ONE saturated light source; everything else in deep shadow.
VALUE: muted, overall luminance 20-35%. Nothing pure white, nothing pure black.
FORBIDDEN, in every image: text, letters, numerals, runes-as-writing, signage, logos, watermarks, signatures, borders, frames, drop shadows, colour bars."""

## The reference every request carries. `bg_crypt.png` is the style bible per ART.md
## §2 — the same file, every time, including for the tiers that look nothing like it.
const REFERENCE := "assets/art/bg_crypt.png"

## `EnemyData.Action`, in enum order, as something to draw. There is no description
## field on an archetype — the only things the game says about a Bone Picker are its
## name, where it appears and what it DOES — so the pattern is the brief. It is also
## the most useful half: a thing whose whole pattern is DEFEND should be armoured, and
## nothing else in the catalogue says so.
const ACTION_WORD := ["attacks", "makes you vulnerable", "weakens you", "defends",
	"empowers itself", "sunders armour", "enrages", "drains life"]

## Zone accent, per ART.md §2. Injected into the backdrop prompts so twelve rooms in
## five zones read as five places, and stated ONCE here rather than per prompt.
const ZONE_ACCENT := {
	"barrows": "cold cyan",
	"foundry_zone": "furnace orange",
	"rot": "acid green",
	"deeps": "deep blue",
	"beyond": "magenta",
}

var _rows: Array = []       # [path, size, brief, exists, kind]
var _sections: Array = []   # [title, note, first_row_index, count, recipe]
var _kind: Kind = Kind.PAINT   # default for rows added to the current section

func _init() -> void:
	_section("Tier 0 — frame kit and control chrome",
		"Highest leverage in the whole list: one kit and every screen stops looking broken.",
		Kind.KIT,
		"DO NOT GENERATE the nine-slices and tileable strips in this tier. A nine-slice survives being stretched to 14x only if its top and bottom strips are constant along X, its left and right constant along Y, and its centre one flat colour; a painting breaks all three and smears (D83). They come out of `tools/gen_ui_kit.gd`. The loose objects listed as paintable below are ordinary cutouts.")
	for e in FRAME_KIT:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

	_section("Tier 1b — vitals and selection", "HP, Block and Energy are all plain text today.",
		Kind.KIT,
		"Bar housings and fills are computed for the same reason as Tier 0 — a fill is a strip tiled along its length. The orbs and rings are cutouts: one object, centred, transparent, no ground shadow.")
	for e in VITALS:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

	_section("Tier 1c — intent telegraphs", "Currently the string 'hit 5'.",
		Kind.PAINT,
		"One symbol per cell, centred, filling ~70% of its cell, on a flat even field. These are read in under a second on a crowded screen, so silhouette beats detail: a shape that survives being described in three words. Keeping the seven mutually distinguishable AS SILHOUETTES is the actual requirement, and it is the one that is lost when they are asked for one at a time — each request is blind to the other six.",
		"A 3x3 grid at 768x768 or larger, flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- intents <sheet.png>`")
	for e in INTENTS:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

	_section("Tier 1d — status symbols",
		"Monochrome and tintable, please: callers tint by rarity and fade spent states.",
		Kind.PAINT,
		"OVERRIDE THE PALETTE LINE IN THE PREAMBLE: these are SINGLE-COLOUR — flat white glyphs on a flat near-black field, no gradient, no interior shading, no ink outline (the shape IS the ink). `Icons` tints them by rarity and fades them for spent states, and that behaviour is load-bearing: a coloured icon cannot be tinted, only muddied. The installer takes alpha from LUMINANCE and throws the colour away, so an anti-aliased edge survives and a hue does not. Read at 48px: one idea per symbol, no scene, no object in a setting.",
		"A 5x5 grid at 1280x1280 or larger (21 glyphs, 4 cells spare — leave them empty), flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- symbols <sheet.png>`")
	for e in SYMBOLS:
		_add("ui/sym_%s.png" % String(e[0]), "64x64", String(e[1]))

	_section("Tier 1e — combat VFX", "The game has no combat feedback animation at all.",
		Kind.SHEET,
		"NOT A GENERATION JOB. Eight frames that have to be the same effect evolving is exactly the thing image models do not hold — eight plausible frames of eight different explosions read as a strobe, not an impact. Shader, particle system, or hand-drawn.")
	for e in VFX:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

	# --- data-driven from here down ------------------------------------------
	_enemies()
	_cards()
	_map_and_traversal()
	_backdrops()
	_relics()
	_powers()

	_section("Tier 7 — identity and shell", "Two of these are downloads, not drawings.",
		Kind.PAINT,
		"The fonts are licensed downloads (OFL/SIL), recorded like the Kenney ones. The logo is the one asset in the game that must carry text and the one place a generator is reliably wrong — generate the ornament and set the wordmark yourself.")
	for e in SHELL:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

	if OS.get_cmdline_user_args().has("--prompts"):
		_emit_prompts()
	else:
		_emit()
	quit()

## A row's kind: its own if it declared one, otherwise the section's default.
func _kind_of(e: Array) -> Kind:
	return (e[3] as Kind) if e.size() > 3 else _kind

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

	var enemy_note := "FACING THE VIEWER (the fight is framed head-on into the corridor; there is no hero on screen), lit from above-front to match the backdrops. Transparent, NO baked ground shadow — the stage draws a contact mark. **Feet flush with the bottom edge of the canvas, no bottom padding**: every enemy is placed on one standing line (`PixelArt.STAND_LINE`, 72% of frame height), so padding at the bottom of the file makes that enemy hover. That line sits BELOW the painted horizon — the backdrops put the wall/floor junction at ~68% (`PixelArt.HORIZON_LINE`), and a figure standing on the junction is at the far end of the corridor rather than in the fight. Rendered height is 38% of the frame for an ordinary enemy, 1.14x for an elite and 1.34x for a boss, so draw the boss files with the detail that survives being the biggest thing on screen. Weight the silhouette low and dark — the floor is the BRIGHTEST band in every painted backdrop, so a pale-footed enemy dissolves into it. Filenames are archetype ids: `PixelArt.enemy_art(id)` looks them up directly, so a file lands on the enemy it was drawn for. (Do NOT put them in `assets/pixel/enemies/`, which is assigned positionally and would hand your file to whichever archetype the sort order reaches.)"
	_section("Tier 2 — enemies", enemy_note, Kind.PAINT,
		"Subject alone on a FLAT, EVEN field of a single colour that appears nowhere in the subject — that field is what `tools/install_cutouts.gd` mattes away, and it refuses any image whose border is not flat rather than cutting a hole in a painted wall. Full body, feet included, nothing cropped by the frame edge. No ground, no floor, no shadow, no pedestal, no background scenery. Facing the viewer, lit from above-front. One monster per image. Generate at 1024x1024 and let the installer scale down: the boss files are rendered at 1.34x the ordinary size and an upscaled boss is a soft boss.")
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
		var verbs: Array[String] = []
		for act in a.pattern:
			var w: String = ACTION_WORD[act] if act < ACTION_WORD.size() else "?"
			if not w in verbs:
				verbs.append(w)
		if not verbs.is_empty():
			bits.append("In a fight it %s." % _list(verbs))
		_add("enemies/%s.png" % aid, "512x512" if is_boss else "256x256",
			" ".join(bits))

## Card illustrations: shared per effect family first, unique art later.
func _cards() -> void:
	var fams := {}
	for cid in PixelArt.card_ids():
		var c := load("res://resources/cards/%s.tres" % cid) as CardData
		if c == null:
			continue
		var f := Icons.card_family(c)
		if not fams.has(f):
			fams[f] = []
		(fams[f] as Array).append(c.name)
	var keys := fams.keys()
	keys.sort()

	_section("Tier 3 — card illustrations",
		"One per effect family to start, shared by every card in it — NOT 100 unique paintings up front. Illustration band only (top of the card face), so it never competes with the rules text. The 100 cards break down as below; unique art for the most-played can come later as `cards/<card_id>.png`, which is checked first.",
		Kind.SCENE,
		"A filled 4:3 rectangle, not a cutout — it fills the card's top band and is cropped to it. Composed for a 320x240 letterbox seen at ~3cm: one clear shape, centred, no fine detail at the edges. It sits directly above rules text, so keep the BOTTOM third of the image quiet and dark. Each of these is shared by every card in its family, so paint the EFFECT, not any one card's fiction.")
	for f in keys:
		var names: Array = fams[f]
		var sample: Array = names.slice(0, mini(4, names.size()))
		_add("cards/%s.png" % f, "320x240",
			"%d cards: %s%s" % [names.size(), ", ".join(sample),
				", ..." if names.size() > sample.size() else ""])

func _map_and_traversal() -> void:
	_section("Tier 4 — map and traversal",
		"The graph map draws no icons at all today, and nothing connects its nodes.",
		Kind.PAINT,
		"Cutouts: one object per cell, centred, no ground shadow, on a flat even field. **This tier is THREE sheets, not one** — the seven `node_*` icons, the seven `tile_*` icons, and the six dice faces — and the tool takes them separately: `install_sheet.gd -- nodes|tiles|dice <sheet.png>`, each with its cells in the order of the table below. The seven encounter kinds appear twice because the graph map and the dice track show the same seven meanings, so draw the node set and re-frame it for the tiles rather than inventing fourteen ideas. The node frames and the path segment are computed, not painted, for the Tier 0 reason.")
	for e in ENCOUNTERS:
		_add("ui/node_%s.png" % String(e[0]), "128x128", String(e[1]))
	for e in ENCOUNTERS:
		_add("ui/tile_%s.png" % String(e[0]), "128x128",
			"Dice-track version of the same: %s" % String(e[1]))
	for i in 6:
		_add("ui/die_%d.png" % (i + 1), "128x128",
			"A die showing %d. The two dice are currently the text 'dice: [3, 2]'." % (i + 1))
	for e in MAP_KIT:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e))

## How many dungeons are still on the 16x16 fallback tile. COUNTED, not written down:
## this line read "nine of twelve" while nine of them were being installed, which is
## the restated-number habit this project keeps paying for (D34).
func _backdrop_gap() -> String:
	var missing := 0
	for did in Balance.DUNGEONS:
		if not FileAccess.file_exists(ART + "bg_" + did + ".png"):
			missing += 1
	if missing == 0:
		return "Every dungeon has one now."
	return "%d of %d dungeons still fall back to a 16x16 tinted tile." % [
		missing, Balance.DUNGEONS.size()]

func _backdrops() -> void:
	_section("Tier 5 — dungeon battle backdrops",
		"%s Match `bg_crypt.png`: symmetrical one-point perspective, 20-35%% luminance, light source kept OUT of the top and bottom 34%% where the combat text sits. NO text painted into the image — `bg_warrens.png` has a 'THE WARRENS' sign in it, which a rename or a translation turns into a lie." % _backdrop_gap(),
		Kind.SCENE,
		"Full-bleed 16:9, opaque, no transparency and no cutout. Symmetrical one-point perspective, vanishing point centred, foreground framing elements at the left and right thirds — every dungeon reuses that skeleton so twelve rooms feel like one dungeon. The wall/floor junction sits at 68% of the frame height (`PixelArt.HORIZON_LINE`); `tests/test_art.gd` measures it and fails a backdrop more than 10 points off, because a backdrop with its floor elsewhere does not look broken on its own — it makes that dungeon's enemies hover. Keep the light source OUT of the top and bottom 34%, where the combat text sits. Empty room: no figures, no creatures.")
	for did in Balance.DUNGEONS:
		var dd := Balance.dungeon(did)
		if dd == null:
			continue
		var z := Balance.zone_of(did)
		var boss := Balance.boss_of(did)
		_add("bg_%s.png" % did, "1280x720",
			"%s (difficulty %d, %s). %s%s Light: %s." % [dd.name, dd.difficulty,
				z.name if z != null else "?", dd.description,
				"  Its boss is %s." % boss.name if boss != null else "",
				_accent(_zone_id_of(did))])

	_section("Tier 5b — zone backdrops",
		"For the zone-select screen. Wider establishing shots, not fight arenas. Note the `bg_zone_` prefix: `foundry` is a dungeon id AND a zone (`foundry_zone`), so one namespace would put an establishing shot in a fight (D83d).",
		Kind.SCENE,
		"Full-bleed 16:9, opaque. An ESTABLISHING SHOT, not a fight arena: wide, deep, a place you are looking at rather than standing in — deliberately unlike the one-point corridors, because this screen is the one that has to feel like choosing between five places. Same palette and ink weight; no figures.")
	for zid in Balance.ZONES:
		var zd := Balance.zone(zid)
		if zd == null:
			continue
		_add("bg_zone_%s.png" % zid, "1280x720",
			"%s. %s Light: %s." % [zd.name, zd.description, _accent(zid)])

	_section("Tier 5c — scene backdrops", "One per non-combat screen.", Kind.SCENE,
		"Full-bleed 16:9, opaque. These sit under dense UI, so they carry LESS detail than a dungeon, not more: a readable middle, quiet top and bottom bands, luminance at the low end of 20-35%.")
	for e in SCENE_BG:
		_add("bg_%s.png" % String(e[0]), "1280x720", String(e[1]))

func _relics() -> void:
	_section("Tier 6a — relic icons",
		"Painted objects on transparent, lit from upper-left, ink-outlined, readable at 48px. `relics_screen.gd` makes no icon call at all today — all 30 render as text rows.",
		Kind.PAINT,
		"One OBJECT, three-quarter view, centred, on a flat even field for the matte. Lit from upper-left. No hand holding it, no pedestal, no ground, no shadow, no background scenery. It is seen at 48px in a row of thirty, so the whole job is silhouette and one memorable colour — a beautifully rendered trinket that reads as a brown smudge has failed. Paint what the relic IS, not what it does.")
	for rid in MetaState.RELIC_CATALOG:
		var r := load(String(MetaState.RELIC_CATALOG[rid])) as RelicData
		if r == null:
			continue
		_add("relics/%s.png" % rid, "128x128", "%s — %s" % [r.name, r.description])

func _powers() -> void:
	_section("Tier 6b — power icons",
		"A power is fired once per turn, every turn, so its icon is seen constantly. Several currently share one monochrome glyph.",
		Kind.PAINT,
		"A SIGIL, not an object: a carved or inlaid emblem, roughly circular, centred in its cell, on a flat even field for the matte. Unlike the relics these are abstract — the power is an ability, not a thing you picked up — and unlike the Tier 1d symbols they are full-colour and never tinted. Ten of them are pressed in the same corner of the same screen all game, so being distinguishable from each other at a glance is the requirement, which is why they are drawn together.",
		"A 4x3 grid at 1024x768 or larger (10 sigils, 2 cells spare — leave them empty), flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- powers <sheet.png>`")
	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p == null:
			continue
		_add("powers/%s.png" % pid, "128x128", "%s — %s" % [p.name, p.description])

## The zone a dungeon belongs to, as an ID — `Balance.zone_of()` returns the resource
## and the accent table is keyed by id.
func _zone_id_of(dungeon_id: String) -> String:
	for zid in Balance.ZONES:
		var z := Balance.zone(zid)
		if z != null and dungeon_id in z.dungeons:
			return zid
	return ""

func _list(items: Array[String]) -> String:
	if items.size() <= 1:
		return "".join(items)
	return "%s and %s" % [", ".join(items.slice(0, items.size() - 1)), items[-1]]

func _accent(zone_id: String) -> String:
	return String(ZONE_ACCENT.get(zone_id, "a single saturated accent"))


# --- prompts ------------------------------------------------------------------

## The same tables, emitted as the thing you paste into an image tool.
##
## The layout is deliberate: ONE style block, printed once, then a bare subject line
## per file. That is the shape the work actually takes — the preamble and the
## reference image are held constant across the whole batch and only the last line
## changes — and it is the shape that produces art that agrees, which is the entire
## problem ART.md §1 is about. A sheet of 113 self-contained paragraphs would each
## drift a little, and 113 little drifts is four visual languages again.
func _emit_prompts() -> void:
	var todo := 0
	for r in _rows:
		if not bool(r[3]) and _generable(r[4]):
			todo += 1
	print("<!-- GENERATED by tools/art_manifest.gd — do not edit by hand.")
	print("     Regenerate: godot --headless --script tools/art_manifest.gd -- --prompts > ART_PROMPTS.md -->")
	print("")
	print("# ART_PROMPTS.md — how to ask for the missing art")
	print("")
	print("Generated from the same catalogues as [ART_ASSETS.md](ART_ASSETS.md), for the")
	print("same reason: a hand-kept prompt sheet goes stale, and a prompt naming an enemy")
	print("the game no longer has produces a painting with nowhere to go. The *why* is")
	print("[ART.md](ART.md); that file is the shopping list; this one is the wording.")
	print("")
	print("**%d files can be generated.** The rest of the list cannot, and the sections below" % todo)
	print("say which and why — the expensive mistake is not a bad painting, it is a good")
	print("painting of a thing that had to be computed.")
	print("")
	print("## The three rules that do the work")
	print("")
	print("1. **One generator, for everything.** The art already in the game came from two")
	print("   different tools and it is visible: `main_menu.jpg` and the dungeons from one,")
	print("   the scene and zone backdrops from another. Two tools is two dialects no")
	print("   prompt reconciles. Pick one and finish the game with it.")
	print("2. **Attach `%s` to every single request**, including the ones that look" % REFERENCE)
	print("   nothing like it. It is the style bible (ART.md §2) and image-conditioning is a")
	print("   stronger constraint on palette and line weight than any adjective.")
	print("3. **Paste the style block below unchanged, then one subject line.** Do not")
	print("   improve it between images. Its job is to be identical %d times." % todo)
	print("")
	print("```")
	print(PREAMBLE)
	print("```")
	print("")
	print("Then: strip the generator's corner watermark, and install with the tool named in")
	print("each section — never by copying files in by hand. The filename is the wiring")
	print("(D73), and the installers also matte, trim, anchor and resize:")
	print("")
	print("```bash")
	print("godot --headless --script tools/strip_sparkle.gd -- /tmp/staging   # backdrops only")
	print("godot --headless --script tools/install_cutouts.gd -- enemies /tmp/staging")
	print("godot --headless --import")
	print("```")
	print("")
	for s in _sections:
		_emit_prompt_section(s)

func _emit_prompt_section(s: Array) -> void:
	var start := int(s[2])
	var count := int(s[3])
	if count <= 0:
		return
	var rows: Array = []
	var have := 0
	var blocked: Array = []
	for i in range(start, start + count):
		var r: Array = _rows[i]
		if not _generable(r[4]):
			blocked.append(r)
		elif bool(r[3]):
			have += 1
		else:
			rows.append(r)
	print("## %s" % String(s[0]))
	print("")
	if not blocked.is_empty():
		print("*%d of these %d files are NOT for a generator: %s* — %s" % [
			blocked.size(), count, _blocked_reason(blocked), _blocked_list(blocked)])
		print("")
	if rows.is_empty():
		print("Nothing to generate here%s." % ("" if have == 0 else " — all %d present" % have))
		print("")
		return
	if String(s[4]) != "":
		print("%s" % String(s[4]))
		print("")
	if String(s[5]) != "":
		# The table below IS the reading order, and `install_sheet.gd` derives the same
		# order from the same tables — so the order asked for and the order installed
		# cannot drift apart the way a restated list would.
		print("**Generate this tier as ONE image, not %d.** %s" % [rows.size(), String(s[5])])
		print("Cells in the order of the table below, left to right then top to bottom.")
		print("")
	print("**%d to generate%s.** Style block above, then one of these as the last line:" % [
		rows.size(), "" if have == 0 else ", %d already present" % have])
	print("")
	print("| save as | subject |")
	print("|---|---|")
	for r in rows:
		print("| `%s` | %s |" % [String(r[0]), String(r[2]).replace("|", "\\|")])
	print("")

func _generable(k: Kind) -> bool:
	return k == Kind.PAINT or k == Kind.SCENE

func _blocked_reason(blocked: Array) -> String:
	var kinds := {}
	for r in blocked:
		kinds[r[4]] = true
	var bits: Array[String] = []
	if kinds.has(Kind.KIT):
		bits.append("computed by `tools/gen_ui_kit.gd`")
	if kinds.has(Kind.SHEET):
		bits.append("animation, not a still")
	if kinds.has(Kind.LICENCE):
		bits.append("a licensed download")
	return "; ".join(bits)

func _blocked_list(blocked: Array) -> String:
	var names: Array[String] = []
	for r in blocked:
		names.append("`%s`" % String(r[0]).get_file())
	return ", ".join(names)


# --- plumbing ----------------------------------------------------------------

func _section(title: String, note: String, kind: Kind = Kind.PAINT, recipe: String = "",
		sheet: String = "") -> void:
	_kind = kind
	_sections.append([title, note, _rows.size(), 0, recipe, sheet])

func _add(rel: String, size: String, brief: String, kind: Variant = null) -> void:
	var path := ART + rel
	var exists := ResourceLoader.exists(path) or FileAccess.file_exists(path)
	_rows.append([rel, size, brief, exists, _kind if kind == null else kind])
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
	print("Paths are relative to `assets/art/`. Author UI assets at **2x** and downsample.")
	print("The interface is laid out at a FIXED 1280x720 and the engine's `canvas_items`")
	print("stretch scales the whole canvas to the window — so on a 1440p display every")
	print("asset is drawn at 2x and on 4K at 3x. Nothing reflows; it is a clean scale-up,")
	print("and it is why the source art has to have the headroom.")
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
