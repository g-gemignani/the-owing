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

## Files that EXIST and are WRONG, so the prompt sheet has to keep asking for them.
##
## ART_PROMPTS.md lists what is absent, which is the right default and is also why a
## bad file is invisible to it: the moment something lands, correct or not, the sheet
## stops mentioning it and the defect has nowhere to be recorded except a person's
## memory. Every line here is a defect with evidence behind it, and the line comes
## OUT when the re-roll lands — so this shrinks to empty and is not a catalogue.
##
## It deliberately does not try to DETECT anything. `tests/test_art.gd` measures each
## backdrop's floor and says in its own comments that the number is confidently wrong
## about half the time; four of the six backdrops it flagged as 14-21 points off were
## checked by eye and are fine (D109). A generated re-roll list built on that would
## throw away good paintings, so this is a hand-kept list of things somebody LOOKED at.
## Shared, because the seven intent telegraphs have ONE defect between them: they came
## on a sheet, and the sheet was drawn as nine stone tiles instead of seven symbols on
## a field. Seven copies of the same sentence is what a shared constant is for.
const REDO_TILED := "drawn on its own stone tile, so the matte keeps the tile and the icon installs as an opaque plaque rather than a cutout; the symbol on it is dark violet on dark violet as well, which at 96px over a dark backdrop is not a read. One defect across the whole sheet — re-roll all seven together (D112)"

const REDO := {
	"ui/intent_attack.png": REDO_TILED,
	"ui/intent_attack_multi.png": REDO_TILED,
	"ui/intent_block.png": REDO_TILED,
	"ui/intent_buff.png": REDO_TILED,
	"ui/intent_debuff.png": REDO_TILED,
	"ui/intent_poison.png": REDO_TILED,
	"ui/intent_unknown.png": REDO_TILED,
	"ui/target_ring.png":
		"the middle is not empty: a warm bloom fills the ring, so the reticle covers the enemy it is supposed to mark, and where the same bloom spills across the four gaps it holds a wedge of background the matte cannot reach (D112)",
	# Two of the twenty-one status symbols, and the only two that cannot be NAMED by
	# somebody who is not told what they are. They were installed and unread until
	# D116, so nothing had ever looked at them at the size they are drawn (D117).
	"ui/sym_energy.png":
		"the point of light is off-centre. The brief asks for an orb 'lit from within by one point of light at its CENTRE'; what came back is a solid white disc with a small dot up and to the right, which the eye reads as a specular highlight — so it is a billiard ball or a pearl, not something lit from inside. The silhouette is also a plain circle, which is the one shape a 21-symbol set cannot afford to spend on an abstraction",
	"ui/sym_dexterity.png":
		"the blow goes the wrong way. The brief asks for 'a tilted buckler GLANCING a blow aside' and the arrow points INTO the disc instead of away from it, so the picture says the hit landed — the opposite of what Dexterity does. The disc also reads as a plate or a frisbee rather than a shield, having no rim and no boss, and at 28px it is a blob with a spike on it",
	"bg_abyssal_stair.png":
		"no floor where the fight is: the paved ground starts ~75% down, below the 72% standing line, so its enemies stand in the tunnel mouth (D109)",
	"bg_drowned_market.png":
		"has FIGURES in it — robed shapes at the far end of the room — and the brief for this tier says an empty room, no figures, no creatures",
	"bg_warrens.png":
		"has the words THE WARRENS painted into the wall, which a rename or a translation turns into a lie",
	"main_menu.jpg":
		"off-style: it carries NO ink outline, and the ink outline is the first line of the style block. Measured as the share of pixels that are a local luminance minimum by >0.08 against both neighbours 2px out, it reads 1.2% against 2.8-12.2% across the twelve dungeons — 2.3x below even bg_crypt, the style bible and the most open room in the set. Flat vector silhouettes for the firs and the mountains, no outline anywhere. Its palette and value are NOT the problem and re-rolling for them would be chasing the wrong fault: mean luminance 20.2% sits inside the 20-35% band and saturation matches the dungeons. It is also the one .jpg in the tree, so the re-roll lands as main_menu.png and four references move with it (D114)",
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
	["ui/card_back.png", "320x448", "The back of a card. NOTHING LOADS THIS TODAY — the deck traversal that required it went in D94, and combat's piles are the text 'Draw 12 - Discard 3'. Painted and installed anyway in D112, so it is waiting for whatever draws a face-down card next rather than blocking it.", Kind.SCENE,
		"A carved stone tablet seen face-on, filling the frame, one worn sigil cut into its centre — a closed eye pressed into rock. Symmetrical, quiet, nothing that reads as a face."],
	["ui/divider.png", "128x16", "Tileable horizontally. A carved rule between sections."],
	["ui/dropdown.png", "192x96", "Nine-slice 32/32/28/28, matching the button. `UITheme` already wires OptionButton to this name and skips it while the file is absent, so the dropdown falls back to Godot's grey chrome — the wiring is done, the picture is what is missing."],
	["ui/dropdown_arrow.png", "32x32", "The open/close chevron.", Kind.PAINT,
		"A small chevron of chipped iron pointing down. One solid shape, centred. The field around it stays FLAT and EMPTY — no glow, no light, no bloom spilling onto it; anything painted on the field is cut away with the field and leaves a hard edge where it was cut."],
	["ui/slider_track.png", "128x24", "Tileable horizontally. The grabber beside it is installed; HSlider takes this name the moment it exists, and runs on Godot's default groove until then."],
	["ui/slider_grabber.png", "48x48", "The slider handle.", Kind.PAINT,
		"A short bar of worn iron with a groove across its middle, seen face-on."],
	["ui/scrollbar_track.png", "24x128", "Tileable vertically. The thumb beside it is installed; VScrollBar takes this name the moment it exists, and runs on Godot's default well until then."],
	["ui/scrollbar_grabber.png", "24x48", "The scrollbar thumb.", Kind.PAINT,
		"A narrow vertical slug of worn iron, rounded at both ends."],
	["ui/checkbox_on.png", "64x64", "Checked. Settings screen.", Kind.PAINT,
		"A square socket of dark stone with an iron peg driven into it, seated hard."],
	["ui/checkbox_off.png", "64x64", "Unchecked.", Kind.PAINT,
		"The same square socket of dark stone, empty. The peg is gone."],
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
	["ui/energy_orb_full.png", "128x128", "One unspent energy. Replaces the text 'Energy 3/3'.", Kind.PAINT,
		"A round orb of cut stone lit from within by one warm point at its heart. Whole, and about to be spent."],
	["ui/energy_orb_empty.png", "128x128", "One spent energy, same silhouette.", Kind.PAINT,
		"The same orb with the light gone out of it: cold grey stone, the silhouette unchanged."],
	["ui/orb_glow.png", "192x192", "Additive bloom for a spend/gain flash.", Kind.PAINT,
		"A soft round bloom of warm light on black, brightest at the centre, fading to nothing at the edge. No object, only the glow."],
	["ui/target_ring.png", "256x256", "Ring/reticle marking the targeted enemy. Replaces the '> ' text prefix.", Kind.PAINT,
		"A ring of worn iron broken into four arcs with gaps between them, the inner edge notched like a sight. Face-on. The middle is EMPTY and so are the four gaps — plain flat field showing through, the same colour as the field outside the ring, with no glow, no light and nothing behind it. An enemy is drawn inside this ring and has to be visible through it."],
	["ui/card_glow.png", "320x448", "Additive edge glow: this card is affordable right now. Nothing marks it today.", Kind.PAINT,
		"A tall rounded halo of warm light on black, brightest along its edge and fading inward. No card, only the light that would spill around one."],
]

## Enemy intent. `eng.intent_text()` renders as the string 'hit 5' today, and the
## telegraph is the core read of the whole combat system.
## The subjects are written to be distinguishable AS SILHOUETTES, which is what the
## recipe asks for and what a meaning cannot deliver: "it will defend" is a rule, and
## a generator handed a rule invents a picture of a fight.
const INTENTS := [
	["ui/intent_attack.png", "96x96", "Incoming single attack.", null,
		"One heavy blade driving down, point toward the viewer."],
	["ui/intent_attack_multi.png", "96x96", "Incoming multi-hit.", null,
		"Three narrow blades fanned side by side, driving down together."],
	["ui/intent_block.png", "96x96", "It will defend.", null,
		"A slab shield face-on, broad and flat, its rim raised."],
	["ui/intent_buff.png", "96x96", "It will strengthen itself.", null,
		"A blunt arrow rising out of a clenched fist."],
	["ui/intent_debuff.png", "96x96", "It will weaken you.", null,
		"A blunt arrow driving down into an open, sagging hand."],
	["ui/intent_poison.png", "96x96", "It will poison you.", null,
		"One fat droplet falling, a bubble rising through it."],
	["ui/intent_unknown.png", "96x96", "Intent hidden.", null,
		"A closed eye, the lid drawn down. Nothing to read."],
]

## Status/effect symbols. Painted replacements for PixelArt.GLYPHS, which is 13
## monochrome bitmaps covering 21 needed meanings — so several currently share one.
## MUST stay monochrome-tintable: callers tint by rarity and fade for spent states.
## [id, meaning, glyph]. The meaning is for the shopping list; the glyph is what a
## generator can actually draw. "Block." and "+block per block card." name a rule,
## and a rule prompts a diagram — these are single shapes instead, chosen to stay
## apart from each other at 48px (D101).
const SYMBOLS := [
	["attack", "Damage.", "A notched blade, point up."],
	["block", "Block.", "A slab shield, face-on."],
	["pierce", "Damage that ignores Block.", "A narrow spike passing clean through a broken shield."],
	["poison", "Poison stacks.", "A fat droplet with a bubble caught in it."],
	["thorns", "Damage returned to attackers.", "A closed ring of barbs, every point turned outward."],
	["vulnerable", "Takes +50% damage.", "A shield split top to bottom, the crack open."],
	["weak", "Deals -25% damage.", "A drooping arm, the fist come unclenched."],
	["strength", "+damage per attack.", "A clenched fist, knuckles forward."],
	["dexterity", "+block per block card.", "A tilted buckler glancing a blow aside."],
	["retain", "Stays in hand at end of turn.", "A closed hand holding a single card edge-on."],
	["exhaust", "Playable once per fight.", "A card curling into ash from one corner."],
	["hp", "Health.", "A blunt anatomical heart, not a valentine."],
	["heal", "Healing.", "Two strips of linen crossed over a heart."],
	["energy", "Energy.", "A round orb with one point of light at its centre."],
	["gold", "Gold.", "Three coins stacked, seen edge-on."],
	["card", "A card.", "One card, corners rounded, its face blank."],
	["dice", "A die / the dice board.", "A cube seen at an angle, its faces marked with round pips."],
	["skull", "Elite or boss.", "A skull, jaw closed, face-on."],
	["campfire", "Rest.", "Three logs stacked, one flame above them."],
	["rope", "Escape Rope.", "A coiled rope with one end hanging free."],
	["chest", "Treasure.", "A small chest, lid shut, one iron band across it."],
]

const VFX := [
	["fx/slash.png", "8 frames of 256x256", "A weapon arc across the target."],
	["fx/impact.png", "8 frames of 256x256", "Blunt hit, dust and shock."],
	["fx/block_up.png", "8 frames of 256x256", "A ward snapping into place."],
	["fx/poison_cloud.png", "8 frames of 256x256", "Green miasma settling."],
	["fx/heal.png", "8 frames of 256x256", "Warm motes rising."],
	["fx/death_dissolve.png", "8 frames of 256x256", "An enemy coming apart. Plays on the kill."],
]

## Tier 4 — map and traversal — used to live here: seven `node_*` icons, seven
## `tile_*` icons, six dice faces and a six-file map kit, 26 files in all. They were
## the art for the graph map, the dice board and the deck draw, and all three models
## were deleted in D94 after D88 moved every dungeon onto the isometric crawl. The
## crawl's own markers are generated by `tools/gen_iso_markers.gd` and live in
## `assets/art/iso/`, so they are not a shopping-list item and never were. Briefing an
## artist on a screen that no longer exists is the expensive half of a stale manifest,
## which is the whole reason this file is generated (D101). The tier numbering below
## keeps its gap so the captures in ART.md §6 still line up.

const SHELL := [
	["fonts/display.ttf", "-", "Display face for titles and card names. Needs an OFL/SIL licence, recorded like the Kenney ones. THE GAME HAS NO CUSTOM FONT — everything is Godot's default.", Kind.LICENCE],
	["fonts/body.ttf", "-", "Body face for rules text. Must stay legible at 12px, since card text shrinks to fit.", Kind.LICENCE],
	## The title art was the one painting in the tree that no row named, so the sheet
	## could not report it either way — the tier that owns the title screen listed the
	## logo that sits on top of it, the boot splash before it and the cursor over it, and
	## not the picture itself. That is why it stayed off the re-roll list while being the
	## most-seen image in the game (D114).
	["main_menu.jpg", "1280x720", "The title screen backdrop. `main_menu.gd` passes it to `UI.screen()`. The menu column is the LEFT 40% under a 0.82 scrim held across 42%, so the left third is covered and the subject belongs right of centre.", Kind.SCENE,
		"A lone hooded traveller seen from behind on a ridge at night, looking up at a black fortress spire far off across a valley of firs. One cold cyan flame in a stone bowl beside them is the only light source. Weight the traveller and the flame RIGHT OF CENTRE and keep the left third quiet — a text column sits over it. Moonless, or a moon kept small and dulled: nothing in the frame reads as pure white."],
	["ui/logo.png", "1600x480", "The wordmark. The title screen currently draws a plain Label reading 'DECKCRAWL'. The ONE asset that has to carry text: generate the ornament, set the type yourself.", Kind.PAINT,
		"An ornamental stone cartouche, wide and shallow, carved edge, symmetrical, EMPTY across its whole middle where type will be set later. No lettering of any kind."],
	["ui/boot_splash.png", "1280x720", "Boot splash. None configured.", Kind.SCENE,
		"A shut iron door at the foot of a stair, one lantern burning above it, seen head-on. Nobody in frame."],
	["ui/cursor.png", "64x64", "Optional pointer.", Kind.PAINT,
		"A slim iron spike pointing up and to the left. One solid shape."],
	["ui/cursor_press.png", "64x64", "Optional pressed pointer.", Kind.PAINT,
		"The same iron spike, shorter and driven in, its tip flared."],
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
## they were asked for the same way, and the five visual languages ART.md §1 diagnoses
## are five different asks, not five different tools. `main_menu.jpg` is the proof and
## the reason that count went from four to five: same tool as the twelve backdrops, one
## different ask, and it does not carry an ink outline at all (D114).
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

## One painting per effect family, and the ONLY authored art direction in this file
## that the catalogues cannot supply. `Icons.card_family` is a mechanical fact — it
## knows a card applies poison, not what poison looks like — so the families were
## emitted as their own membership lists ("28 cards: Bash, Bite, Blood Price, ...")
## and that is a table of contents, not a subject. The recipe says paint the EFFECT
## and not any one card's fiction, so each line below paints the effect once (D101).
##
## Keyed by family id. `_cards()` REFUSES to emit a family with no line here rather
## than falling back to the membership list, because the fallback is exactly the
## defect and a silent one: a 13th family would ship 99 good prompts and one bad
## (D34's habit, in a new place).
const CARD_ART := {
	"attack": "One heavy blade coming down through the frame, caught at the moment it lands. The stroke is the subject; no wielder needs to be in shot.",
	"attack_aoe": "A single stroke opening one wide arc clean across the frame, catching several shapes at once in the dark to either side.",
	"attack_multi": "The same blade struck three times over, its arcs overlapping, each one fainter than the last.",
	"block": "A slab of shield-iron braced square against the frame, a blow breaking apart on it.",
	"dexterity": "A blow glancing off a tilted buckler and away — the shape of the deflection, not the impact.",
	"draw": "A hand of cards fanning open, the topmost one lifting free of the rest.",
	"heal": "Strips of linen drawn tight over a wound, one warm point of light behind them.",
	"poison": "A green fume settling low across the frame, beading on cold stone.",
	"strength": "A fist closing on a hammer's grip, the knuckles going white.",
	"thorns": "A barbed ring closed around a reaching hand, every point turned outward.",
	"vulnerable": "A shield split top to bottom, the crack open and dark.",
	"weak": "An arm gone slack, the weapon dropping out of an opening hand.",
	# No card lands in these two today. They are written anyway: the guard below
	# fails on a family with no line, and the cheap half of that trade is here.
	"energy": "An orb of cut stone brightening as a second point of light kindles beside the first.",
	"utility": "A ring of iron keys, one held apart from the rest.",
}

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
## Set when a table and the catalogues disagree. Checked before anything is printed:
## a manifest that emits 99 correct rows and one wrong one is worse than no manifest,
## because the wrong row is the one nobody re-reads.
var _fatal: String = ""

func _init() -> void:
	_section("Tier 0 — frame kit and control chrome",
		"Highest leverage in the whole list: one kit and every screen stops looking broken.",
		Kind.KIT,
		"DO NOT GENERATE the nine-slices and tileable strips in this tier. A nine-slice survives being stretched to 14x only if its top and bottom strips are constant along X, its left and right constant along Y, and its centre one flat colour; a painting breaks all three and smears (D83). They come out of `tools/gen_ui_kit.gd`. The loose objects listed as paintable below are ordinary cutouts. Each loose object — the chevron, the bar, the slug, the two sockets — stands alone on a FLAT, EVEN field of a single colour, centred, with no wall, no room, no floor, no shadow and no scenery of any kind; that flat field is what gets cut away, and an object painted into a setting cannot be cut out of it. The card tablet is the one exception and fills its frame edge to edge. Three of the first five came back painted into a cave wall because this tier said none of that (D105).")
	for e in FRAME_KIT:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e), _subject_of(e))

	_section("Tier 1b — vitals and selection", "HP, Block and Energy are all plain text today.",
		Kind.KIT,
		"Bar housings and fills are computed for the same reason as Tier 0 — a fill is a strip tiled along its length. The orbs and rings are cutouts: one object, centred, transparent, no ground shadow.")
	for e in VITALS:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e), _subject_of(e))

	_section("Tier 1c — intent telegraphs", "Currently the string 'hit 5'.",
		Kind.PAINT,
		"One symbol per cell, centred, filling ~70% of its cell, on a flat even field. These are read in under a second on a crowded screen, so silhouette beats detail: a shape that survives being described in three words. Each symbol is one solid shape in a value clearly separated from that field — a dark shape on a dark field is not a read at 96px, and the silhouette is the whole job. Keeping the seven mutually distinguishable AS SILHOUETTES is the actual requirement, and it is the one that is lost when they are asked for one at a time — each request is blind to the other six. A symbol painted onto its own stone tile installs as an opaque plaque instead of a cutout, because the tile is then the subject and only the gutter between tiles is field (D112).",
		"A 3x3 grid at 768x768 or larger: seven symbols and two spare cells. The grid is a LAYOUT and not something drawn — no tile, no plaque, no panel, no border and no mortar line anywhere in the image; ONE flat even colour runs edge to edge behind all nine cells, and that colour is the only background there is. Fill the first seven cells in order, left to right then top to bottom, and leave the last two as bare flat colour. Draw exactly seven symbols and no more: a skipped cell in the middle of the run, or an eighth symbol invented to fill a spare one, puts every symbol after it on the wrong meaning. Nothing touches a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- intents <sheet.png>`")
	for e in INTENTS:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e), _subject_of(e))

	_section("Tier 1d — status symbols",
		"Monochrome and tintable, please: callers tint by rarity and fade spent states.",
		Kind.PAINT,
		"OVERRIDE THE PALETTE LINE IN THE PREAMBLE: these are SINGLE-COLOUR — flat white glyphs on a flat near-black field, no gradient, no interior shading, no ink outline (the shape IS the ink). `Icons` tints them by rarity and fades them for spent states, and that behaviour is load-bearing: a coloured icon cannot be tinted, only muddied. The installer takes alpha from LUMINANCE and throws the colour away, so an anti-aliased edge survives and a hue does not. Read at 48px: one idea per symbol, no scene, no object in a setting.",
		"A 5x5 grid at 1280x1280 or larger: twenty-one glyphs and four spare cells. Fill the first twenty-one cells in order, left to right then top to bottom, and leave the last four as bare background. Draw exactly twenty-one glyphs and no more: an extra glyph invented to fill a spare cell, or a duplicate of one already drawn, puts every glyph after it on the wrong meaning. Flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- symbols <sheet.png>`")
	for e in SYMBOLS:
		_add("ui/sym_%s.png" % String(e[0]), "64x64", String(e[1]), null, String(e[2]))

	_section("Tier 1e — combat VFX", "The game has no combat feedback animation at all.",
		Kind.SHEET,
		"NOT A GENERATION JOB. Eight frames that have to be the same effect evolving is exactly the thing image models do not hold — eight plausible frames of eight different explosions read as a strobe, not an impact. Shader, particle system, or hand-drawn.")
	for e in VFX:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e), _subject_of(e))

	# --- data-driven from here down ------------------------------------------
	_enemies()
	_cards()
	_backdrops()
	_relics()
	_powers()

	_section("Tier 7 — identity and shell", "Two of these are downloads, not drawings.",
		Kind.PAINT,
		"The fonts are licensed downloads (OFL/SIL), recorded like the Kenney ones. The logo is the one asset in the game that must carry text and the one place a generator is reliably wrong — generate the ornament and set the wordmark yourself.")
	for e in SHELL:
		_add(String(e[0]), String(e[1]), String(e[2]), _kind_of(e), _subject_of(e))

	if _fatal != "":
		push_error("art_manifest: %s" % _fatal)
		printerr("art_manifest: %s" % _fatal)
		quit(1)
		return

	if OS.get_cmdline_user_args().has("--prompts"):
		_emit_prompts()
	else:
		_emit()
	quit()

## A row's kind: its own if it declared one, otherwise the section's default.
## An explicit `null` in the kind column means "section default" — needed by the
## tables that skip the kind to reach the subject column after it.
func _kind_of(e: Array) -> Kind:
	if e.size() > 3 and e[3] != null:
		return e[3] as Kind
	return _kind

## A const table row's prompt subject, if it wrote one. Optional 5th column, so
## the tables that need no override stay three or four wide.
func _subject_of(e: Array) -> String:
	return String(e[4]) if e.size() > 4 else ""

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

	var enemy_note := "FACING THE VIEWER (the fight is framed head-on into the corridor; there is no hero on screen), lit from above-front to match the backdrops. Transparent, NO baked ground shadow — the stage draws a contact mark. **Feet flush with the bottom edge of the canvas, no bottom padding**: every enemy is placed on one standing line (`PixelArt.STAND_LINE`, 72% of frame height), so padding at the bottom of the file makes that enemy hover. That line sits BELOW the painted horizon — the backdrops put the wall/floor junction at ~68% (`PixelArt.HORIZON_LINE`), and a figure standing on the junction is at the far end of the corridor rather than in the fight. Rendered height is 38% of the frame for an ordinary enemy, 1.14x for an elite and 1.34x for a boss, so draw the boss files with the detail that survives being the biggest thing on screen. Weight the silhouette low and dark — the floor is the BRIGHTEST band in every painted backdrop, so a pale-footed enemy dissolves into it. Filenames are archetype ids: `PixelArt.enemy_art(id)` looks them up directly, so a file lands on the enemy it was drawn for. There is no second source behind this any more: the positionally-assigned CC0 sprite pool went away with the assignment that handed it out (D89), so a missing plate is a missing enemy rather than a wrong one."
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
		"One per effect family to start, shared by every card in it — NOT 100 unique paintings up front. This is the single highest-value tier in the file: the card face is two parts, and this is the top one — a real picture with its own band, not a wash behind words (D104). The 100 cards break down as below; unique art for the most-played can come later as `cards/<card_id>.png`, which is checked first.",
		Kind.SCENE,
		"A filled 4:3 rectangle, not a cutout. It is the picture band across the top of a card and it fills that band edge to edge: one clear shape, centred, read at 320x240 and shown about 3cm wide. The band is 4:3 to within half a percent, so almost nothing is cropped — use the whole rectangle. LEAVE THE FOUR CORNERS QUIET AND EMPTY: top-left and top-right, each about a quarter of the width and a fifth of the height, and bottom-left and bottom-right, the same height but nearly half the width. Quiet means plain background — no object, no plate, no badge, and above ALL no numeral and no symbol. The FORBIDDEN line above applies hardest here: this one picture is shared by every card in its family, so a number painted into a corner is a WRONG number on twenty different cards, and it will sit under the real one the game draws there. The bottom two fifths also sit under a shadow that deepens to most of the way black at the very bottom edge, so put nothing down there that has to stay bright — weight the subject into the upper middle and let the lower edge fall away into dark. Paint the EFFECT the family shares, not any one card's fiction.")
	# Discovered families, not a written-down list — so a new effect family shows up
	# here by itself, and shows up as a failure until somebody says what it looks like.
	var undescribed: Array[String] = []
	for f in keys:
		if not CARD_ART.has(f):
			undescribed.append(String(f))
	if not undescribed.is_empty():
		_fatal = ("no CARD_ART line for card famil%s %s — add one to tools/art_manifest.gd. "
			+ "The membership list is NOT an acceptable fallback subject (D101).") % [
			"y" if undescribed.size() == 1 else "ies", ", ".join(undescribed)]
		return

	for f in keys:
		var names: Array = fams[f]
		var sample: Array = names.slice(0, mini(4, names.size()))
		_add("cards/%s.png" % f, "320x240",
			"%d cards: %s%s" % [names.size(), ", ".join(sample),
				", ..." if names.size() > sample.size() else ""],
			null, String(CARD_ART[f]))

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
		"Full-bleed 16:9, opaque, no transparency and no cutout. Symmetrical one-point perspective, vanishing point centred, foreground framing elements at the left and right thirds — every dungeon reuses that skeleton so twelve rooms feel like one dungeon. THE GROUND IS THE PART THAT MATTERS, so compose it first: the back wall meets the floor a little over two thirds down, and from there the floor is unbroken open ground all the way to the bottom edge of the frame. Figures are stood on that floor just under the junction, so the band from two thirds down to three quarters down the frame must be plain walkable ground — nothing rising through it, no water, no rubble pile, no undergrowth, no altar, no steps, no pit, and no darkness the eye reads as a hole. If the ground starts lower than that band, whatever is standing on it appears to hover in mid-air. Keep the light source OUT of the top and bottom 34%, where the combat text sits. Empty room: no figures, no creatures, and nothing anywhere in the image that reads as writing.")
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
		"A 4x3 grid at 1024x768 or larger: ten sigils and two spare cells. Fill the first ten cells in order, left to right then top to bottom, and leave the last two as bare background. Draw exactly ten sigils and no more: an extra one invented to fill a spare cell puts every sigil after it on the wrong meaning. Flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- powers <sheet.png>`")
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
	# Absent files AND re-rolls, because both are a request somebody has to paste, and
	# counting only the absent ones made this number smaller than the sheet below it:
	# it read 56 while the tiers asked for 67, and rule 3's "identical N times" is the
	# same number (D114). A re-roll is not cheaper than a first draft — it is the same
	# prompt, sent again.
	var todo := 0
	for r in _rows:
		if _generable(r[4]) and (not bool(r[3]) or REDO.has(String(r[0]))):
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
	print("1. **One generator, for everything — but one generator is not enough.** The art")
	print("   already in the game came from two different tools and it is visible: the")
	print("   dungeons and `main_menu.jpg` from one, the scene and zone backdrops from")
	print("   another. Pick one and finish the game with it. Then note what that alone does")
	print("   NOT buy you: `main_menu.jpg` came off the SAME tool as the twelve dungeons and")
	print("   is still a different dialect — flat vector silhouettes with no ink outline at")
	print("   all, at a ninth the outline density of the rooms it shipped beside (D114). One")
	print("   tool asked twice in two wordings is two dialects, which is what rule 2 is for.")
	print("2. **Attach `%s` to every single request**, including the ones that look" % REFERENCE)
	print("   nothing like it. It is the style bible (ART.md §2) and image-conditioning is a")
	print("   stronger constraint on palette and line weight than any adjective. `main_menu.jpg`")
	print("   is what a request without it looks like.")
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
	print("godot --headless --script tools/strip_sparkle.gd -- /tmp/staging")
	print("godot --headless --script tools/install_cutouts.gd -- enemies /tmp/staging")
	print("godot --headless --import")
	print("```")
	print("")
	print("Strip FIRST, on the whole batch at once, before anything crops or resizes —")
	print("the stamp is found by intersecting the images against each other, so they have")
	print("to still agree on where it is. A matted cutout survives skipping it, because")
	print("the corner is field and the matte takes it; anything installed OPAQUE or as a")
	print("bloom does not, and keeps the stamp in the shipped file (D112).")
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
	var redone: Array = []
	for i in range(start, start + count):
		var r: Array = _rows[i]
		if not _generable(r[4]):
			blocked.append(r)
		elif REDO.has(String(r[0])):
			# Present but wrong. Asked for again, and listed separately from the ones
			# that were never drawn, because the two need different care: a re-roll is
			# replacing something that already passed once.
			redone.append(r)
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
	if rows.is_empty() and redone.is_empty():
		print("Nothing to generate here%s." % ("" if have == 0 else " — all %d present" % have))
		print("")
		return
	if String(s[4]) != "":
		print("%s" % String(s[4]))
		print("")
	# A sheet tier asked for as a sheet — but ONLY while the whole set is being asked
	# for. A partial re-roll of a sheet tier must not be a sheet, and getting this
	# wrong produced a page that contradicted itself: two bad glyphs out of
	# twenty-one printed "Generate this tier as ONE image, not 2" directly above a
	# paragraph describing a 5x5 grid of twenty-one cells (D117).
	#
	# It is not a formatting problem, it is the requirement inverting. These tiers are
	# sheets because the set has to be mutually distinguishable AS SILHOUETTES and a
	# request for one glyph is blind to the other six (D91). When nineteen of the
	# twenty-one are already on disk, that blindness is gone — the survivors ARE the
	# reference, and the job is to match them, not to redraw them. Asking for the
	# sheet again would throw away nineteen good drawings to fix two.
	var whole_tier: bool = rows.size() + redone.size() == count - blocked.size()
	if String(s[5]) != "" and whole_tier:
		# The table below IS the reading order, and `install_sheet.gd` derives the same
		# order from the same tables — so the order asked for and the order installed
		# cannot drift apart the way a restated list would.
		# rows AND re-rolls: a sheet tier is redrawn whole, so a re-roll of one cell is
		# a re-roll of the sheet, and counting only `rows` printed "not 0" for a tier
		# whose every cell was a re-roll (D112).
		print("**Generate this tier as ONE image, not %d.** %s" % [
			rows.size() + redone.size(), String(s[5])])
		print("Cells in the order of the table below, left to right then top to bottom.")
		print("")
	elif String(s[5]) != "":
		# Still ONE image, but a SMALL one, and the geometry is the partial count's
		# rather than the tier's. Two things had to be true at once and the first
		# attempt at this got the second wrong: the set must not be redrawn whole (the
		# nineteen on disk are the reference, and a fresh sheet of twenty-one throws
		# them away), AND the delivery has to stay a grid, because `install_sheet.gd`
		# takes a grid and `cut_mono` is what these need. Emitting N individual pastes
		# instead produced a page that asked for two images and then told the operator
		# to install one sheet (D117).
		#
		# The grid mirrors `install_sheet.gd`'s own `ceil(sqrt(n))` so the doc and the
		# tool cannot disagree about the shape; `--only` is what makes the tool size
		# itself the same way.
		var partial: Array = []
		for r in rows + redone:
			partial.append(String(r[0]).get_file().get_basename())
		var pc: int = int(ceil(sqrt(float(partial.size()))))
		var pr: int = int(ceil(float(partial.size()) / float(pc)))
		print("**Generate these as ONE image, not %d.** A %dx%d grid, cells in the order of the table below, left to right then top to bottom, flat even background, nothing touching a cell edge. This is a RE-ROLL of %d of this tier's %d files: the rest are already installed and are the reference, so match the set on disk for weight, fill and how much of its cell the shape uses. Install: `godot --headless --script tools/install_sheet.gd -- %s <sheet.png> --only=%s`" % [
			partial.size(), pc, pr, partial.size(), count - blocked.size(),
			_sheet_set(String(s[5])), ",".join(partial)])
		print("")
	if not rows.is_empty():
		print("**%d to generate%s.** Style block above, then one of these as the last line:" % [
			rows.size(), "" if have == 0 else ", %d already present" % have])
		print("")
		_prompt_table(rows)
	# The re-rolls carry their own reason, so whoever pastes one knows what to look for
	# in what comes back. A re-roll with no stated defect is how a bad file gets
	# replaced by a differently bad file.
	if not redone.is_empty():
		# ONE line, and it has to START with the asterisk: `gen_pollinations.py`
		# recognises operator prose by the line's first character, so a wrapped second
		# line is picked up as art direction and pasted into the prompt (D109).
		print("**%d to RE-ROLL** — these files exist and are wrong. Same style block and same subject line as a first draft; what is on disk is not a constraint on what comes back." % redone.size())
		print("")
		var reasons := {}
		for r in redone:
			reasons[String(REDO[String(r[0])])] = true
		if reasons.size() == 1 and redone.size() > 1:
			# One defect across the whole set — said once. A seven-row table repeating
			# one sentence seven times is a table nobody finishes reading, and the
			# sentence is the part that has to land.
			#
			# The leading asterisk is load-bearing for the same reason the RE-ROLL
			# header's is: `gen_pollinations.py` tells operator prose from art
			# direction by the line's first character, and without it this sentence was
			# pasted into the prompt — telling the generator that the picture it had
			# not drawn yet was already wrong (D112).
			print("*All %d have the same defect: %s.*" % [
				redone.size(), reasons.keys()[0]])
		else:
			print("| save as | size | what is wrong with the one we have |")
			print("|---|---|---|")
			for r in redone:
				print("| `%s` | %s | %s |" % [String(r[0]), String(r[1]),
					String(REDO[String(r[0])]).replace("|", "\\|")])
		print("")
		_prompt_table(redone)

## The set label out of a sheet tier's own Install: command ("symbols", "intents",
## "powers"). Lifted rather than restated: the label is `install_sheet.gd`'s first
## positional argument and the tier note already carries it, so a second copy here is
## the D34 habit at one line long.
func _sheet_set(note: String) -> String:
	var m := RegEx.create_from_string(r"install_sheet\.gd -- (\w+)")
	var r := m.search(note)
	return r.get_string(1) if r != null else "SET"

## The subject table. Carries the target SIZE per row, because the shape of the
## request is per FILE and not per tier: Tier 0 is five square-ish cutouts and one
## portrait card back, and a tier-wide "generate a square image" asked for the card
## back at 1:1 when the card is 320x448 (D109). `gen_pollinations.py` reads this
## column and picks the aspect from it.
func _prompt_table(rows: Array) -> void:
	print("| save as | size | subject |")
	print("|---|---|---|")
	for r in rows:
		# The prompt sheet asks for a drawing, so it prefers the subject; the
		# brief is the fallback for rows whose brief is already visual.
		var subject := String(r[5]) if String(r[5]) != "" else String(r[2])
		print("| `%s` | %s | %s |" % [String(r[0]), String(r[1]),
			subject.replace("|", "\\|")])
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

## `brief` answers "why is this file wanted" and goes to ART_ASSETS.md. `subject`
## answers "what do I draw" and goes to ART_PROMPTS.md; when it is empty the brief
## is reused. They started as one string and that was a defect, not a saving: a
## brief earns its keep by naming the wiring ("Replaces the text 'Energy 3/3'"),
## and a prompt carrying that sentence asks a generator for UI it cannot see and
## quotes text at a style block whose FORBIDDEN line bans text (D101).
func _add(rel: String, size: String, brief: String, kind: Variant = null,
		subject: String = "") -> void:
	var path := ART + rel
	var exists := ResourceLoader.exists(path) or FileAccess.file_exists(path)
	_rows.append([rel, size, brief, exists, _kind if kind == null else kind, subject])
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
