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

## The isometric floor, for its `WANDER_DESIGNS` count only. The screen that DRAWS a
## set is the one allowed to say how big it is; a second copy of that number here is
## the D34 bug, and the shape it takes is a painted file nothing ever loads.
# (the wanderer count now lives in `Balance.ISO_WANDERERS`)

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
##
## A `REDO_TILED` constant used to sit here, holding the one defect the seven intent
## telegraphs shared — the sheet came back as nine stone tiles instead of seven symbols
## on a field. It went out with them in D122, along with the three dungeon backdrops:
## the table is meant to shrink, and a shared constant with no rows left pointing at it
## is the shrinking not finishing.
## A `REDO_ISO` constant sat here too, shared across all twenty-three Tier 8 files
## because they had one defect between them: every one measured luma 0.16-0.21 against
## floors of 0.43-0.49, so a figure was 2.5x darker than its own ground and read as a
## hole in the floor. All twenty-three were repainted in D122 and it went out with them,
## same as REDO_TILED did.

## The same defect, on the thirty-five combat plates. `tools/gen_enemy_art.gd` filled a
## directory that had been empty since the painted backdrops landed, and it was the
## right call at the time — it replaced 41 unlabelled 16x16 tiles assigned by sort
## order, where a boss was whichever tile the index fell on. But what it draws is a
## SILHOUETTE, and a silhouette is a placeholder that reads as finished: measured at
## luma 0.17-0.23 with an empty interior, so a Cultist and an Ember Hound are two dark
## shapes on a painted room, and the fight screen is the one the game is mostly spent on.
##
## This is also the case the REDO table was built for and nearly missed. Every one of
## the thirty-five EXISTS, so Tier 2 printed "all 35 present" and the prompt sheet said
## nothing about them — "the moment something lands, correct or not, the sheet stops
## mentioning it and the defect has nowhere to be recorded except a person's memory".
## `gen_enemy_art.gd` stays as the fallback: `PixelArt.enemy_art()` prefers a painted
## file, so these can be replaced one at a time (D122).
const REDO_SILHOUETTE := "a procedural SILHOUETTE from `tools/gen_enemy_art.gd`, not a painting: measured luma 0.17-0.23 with a flat empty interior behind a one-sided rim light, so at the 240px it draws at, in front of a painted room, it is a dark shape with no face, no weapon and no material. It was the right placeholder — it replaced 41 unlabelled 16x16 tiles handed out by sort order — but it reads as finished art and is not (D122)"

const REDO := {
	# `ui/target_ring.png` was here — a warm bloom filled the ring, so the reticle
	# covered the enemy it marks. Re-rolled in D122 as four arcs on a flat field with
	# the gaps left open, so the matte reaches the middle through them: the disc inside
	# the arcs now measures 0.00% alpha, which is the check the old one failed and no
	# corner test would have caught.
	# `ui/sym_energy.png` and `ui/sym_dexterity.png` were here — the two of the
	# twenty-one that could not be NAMED by somebody who was not told what they are.
	# Re-rolled together as one 2x1 sheet and installed in D122. Energy is a hollow
	# ring with the star at its dead centre, so the light is INSIDE it rather than a
	# highlight sitting on top, and flame tongues break the bare circle the old one
	# spent its whole silhouette on; Dexterity's arrow now points AWAY from the shield,
	# so the picture says the blow missed. Both measure ink luminance 1.00 with all
	# four corners clear, matching the nineteen already on disk, and both were looked
	# at rendered down to the 28px they are drawn at — which is the check D117 says
	# was never done on the originals.
	# The three dungeon backdrops were here — no floor under the fight on the Abyssal
	# Stair, figures in the Drowned Market, painted words in the Warrens. All three
	# re-rolled and installed in D122, so all three lines came out.
	# All twenty-three Tier 8 files were here and all twenty-three came out in D122,
	# painted as three sheets. What they were listed for, and what it measures now:
	#   - the whole tier read luma 0.16-0.21 against floors of 0.43-0.49, so a figure
	#     was a hole in the ground. Now 0.25-0.49.
	#   - `combat`, `elite` and `boss` were the SAME SILHOUETTE to the pixel, so the
	#     floor could not say whether the room ahead was a trash fight or the thing
	#     that ends the run. Overlap is now 17.6% and 25.6%.
	#   - `mon_caster_s` was the same drawing as the hero at 81.9% overlap, told apart
	#     by hue alone. Now 41.8%, and they are different characters rather than one
	#     character tinted twice.
	# All sixteen figures and all seven props measure 0.0% empty space below the feet,
	# which is what `install_sheet.gd`'s new foot-anchoring is for.
	"main_menu.png":
		"still off-style after TWO re-rolls, and the next person should read this before spending a third. Not enough ink: the share of pixels that are a local luminance minimum by >0.08 against both neighbours 2px out reads 1.2% against 2.8-12.2% across the twelve dungeons. Both D122 attempts led with that fault and named the ink outline six times; the second came back with visible pen hatching on the rocks and measured 1.0%, marginally WORSE than the file it would have replaced, so it was not installed. TWO WRONG EXPLANATIONS, BOTH TESTED AND BOTH DEAD. (1) 'the metric is just reporting darkness': normalising each image to its own 1st-99th percentile and re-running puts it at 3.6% against 5.1-15.4% for the dungeons, still last, on a range only slightly narrower. (2) 'the threshold is absolute and this scene is dark': re-measured with the threshold set to 0.75 local sigma instead of a fixed 0.08, it reads 4.7-4.9% against 8.8-12.8% for the dungeons — still about half, on two independent measures. THE LIVE HYPOTHESIS is that the SUBJECT cannot reach the target: the dungeons are near-field architecture where every form is close enough to outline, and this is a night exterior whose firs and spire recede into haze and cannot carry heavy contour lines without looking wrong. If that is right the answer is a different subject or a lower target for this one file, not a third re-roll of the same picture — and that is an art-direction call, not a generation one (D114, D122)",
}

## A defect that belongs to a whole DIRECTORY rather than to one file.
##
## `REDO` above is deliberately hand-kept, one line of evidence per file, and that is
## the right shape while a defect is a defect. It is the wrong shape when an entire
## family was produced by one generator and shares one fault: thirty-five identical
## strings do not read as thirty-five findings, they read as noise, and the next person
## editing one of them has to check all thirty-five for drift.
##
## Consulted AFTER `REDO`, never instead of it — so a single file can still carry its
## own worse fault on top of its family's, which is what the iso caster does. Removing
## a family is removing one line here, the same way removing a file is removing one
## line up there.
##
## **A prefix, not a directory, and the difference earned itself twice.** It started as
## `"iso/"` because all twenty-three files under it shared one defect. Then Tier 8b's
## seven props were painted and the sixteen figures were not, so it narrowed to the
## three figure prefixes; then the figures were painted too and the whole family came
## out. A key here is only ever as wide as the defect actually is, and the defect
## shrinks — which is the same thing `REDO` itself is for, one level up.
const REDO_DIRS := {
	"enemies/": REDO_SILHOUETTE,
}

## Files a `REDO_DIRS` rule no longer applies to, because they have been repainted.
##
## A family of thirty-five is not repainted in one sitting, and halfway through, both
## available answers are wrong: leave the directory rule alone and the sheet asks for
## twelve files that are already done, or drop it and it stops asking for the
## twenty-three that are not. Narrowing the key worked for `iso/` because the two halves
## happened to have different prefixes; these do not, and inventing a prefix that only
## exists to encode progress would be worse than saying it plainly.
##
## So this is the progress record, and it is the SHORTER of the two lists on purpose —
## it starts empty, grows as re-rolls land, and the moment it reaches the whole family
## the `REDO_DIRS` line comes out and this goes with it. The same shrink-to-nothing the
## table above is built around (D122).
const REDO_CLEARED := [
	# Tier 2, painted in D122. Order is the sheet they came in on, three per row.
	"enemies/bone_picker.png", "enemies/crypt_hound.png", "enemies/cultist.png",
	"enemies/grave_sexton.png", "enemies/marrow_abbot.png", "enemies/ossuary_wretch.png",
	"enemies/abyss_horror.png", "enemies/bellows_brute.png", "enemies/bellows_master.png",
	"enemies/bog_lurker.png", "enemies/brood_mother.png", "enemies/brute.png",
]

## The defect recorded against a file, or "" if there is none. Every reader goes
## through this rather than indexing `REDO`, so the directory rule cannot be honoured
## in one place and forgotten in another — which is exactly how the prompt sheet and
## the asset sheet would start disagreeing about what is wrong.
func _redo(rel: String) -> String:
	if REDO.has(rel):
		return String(REDO[rel])
	if rel in REDO_CLEARED:
		return ""
	for prefix in REDO_DIRS:
		if rel.begins_with(String(prefix)):
			return String(REDO_DIRS[prefix])
	return ""

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

## Scene backdrops for the META screens — the twelve that pass nothing to
## `UI.screen()` and so fall through to `PixelArt.backdrop()`, the procedural tiling
## pattern: glossary, powers, builds, settings, deck builder, overworld, packs,
## pause, collection, starter kit, relics, save slots.
##
## FOUR paintings for twelve screens, and the grouping IS the decision here. One file
## per screen is the obvious shape and it is wrong twice: it asks for twelve paintings
## where four do the job, and it asserts twelve different PLACES when the fiction has
## four. The deck builder, the collection, the builds tracker, the packs screen and
## the starter kit are one action seen five ways — you are stood at a table with your
## cards out — and a separate room each would say they are five errands in five
## places, which is not what the meta loop is. Relics and Powers are both "what you
## have earned and cannot lose", and they are already each other's sibling in code:
## two read-mostly lists of owned things off `MetaState`.
##
## The two that stay alone stay alone for a reason rather than being left over. The
## Overworld is the hub every other screen is reached FROM, so its backdrop is doing
## navigation work rather than dressing, and it has a constraint none of the others
## has (see its subject). The ledger group is the game's own machinery — how it works,
## which save, which settings — the one set here that is not about the character at
## all, and dressing a settings page as a card table would be a lie about what the
## screen does.
##
## The cost of sharing is that five screens look alike, and that is accepted: each
## carries its own title and its own list, so the backdrop is the thing they have in
## common and it is TRUE that they have it in common. The cost of not sharing is eight
## more paintings and eight more chances for the wording to drift, which is the fault
## D114 is about.
##
## [id, brief, subject]
const META_BG := [
	["table",
		"Deck builder, Collection, Builds, Packs and the starter kit. One place, five screens: every one of them is a list of cards you own with something to do to them.",
		"A long stone bench seen end-on from slightly above, its far end lost in the dark, with a few cards lying FACE DOWN on it beside a stub of candle and a shallow iron bowl of tokens. Card backs only — plain, worn, no faces, no marks, no pips. The candle is the only light source and it sits in the UPPER THIRD, well off centre. The near half of the bench fills the whole bottom half of the frame and is one unbroken slab of worn stone at one even value: no objects on it, no edge crossing it, no highlight, no grain that changes value — rows of text run down over that half from side to side. Nobody in frame."],
	["reliquary",
		"Relics and Powers. Both screens are the same claim — this is what you have earned and cannot lose — and they are the same list in code, so they are the same room.",
		"A shallow niche cut into a stone wall, seen head-on, holding a row of iron pegs and one narrow shelf with three unremarkable objects on it: a ring, a knuckle bone, a stoppered jar. One cold flame in a wall bracket in the UPPER THIRD is the only light source. Below the niche the bare wall face and the floor under it fill the whole bottom half of the frame as one flat, evenly dark surface — no carving, no moulding, no bracket, no object and no highlight anywhere in it, because thirty rows of text run down over it. Nobody in frame."],
	["ledger",
		"Glossary, Save Slots and Settings — the game's own machinery rather than the character's. Not a place in the fiction, which is why it is a desk and not a room.",
		"A writing desk set against a stone wall, seen head-on, with a SHUT ledger and an inkpot on it and a shelf of more shut ledgers above. Every book closed: no open page, no writing, no marking on any cover or spine. One candle on the shelf, in the UPPER THIRD, is the only light source. The front of the desk and the floor before it fill the whole bottom half of the frame as one flat, evenly dark surface with no drawer, no handle, no object and no highlight in it, because a column of text and controls runs down over it. Nobody in frame."],
	["world",
		"The Overworld hub. Alone because it is what every other screen is reached from, and because it is the one screen already carrying five paintings of its own (D96).",
		"A stone gatehouse arch seen head-on from inside it, the road out running away through the opening into fog. NOTHING beyond the arch resolves — no landmark, no tower, no ridge, no landscape of any kind, only depth and haze. One cold flame in a bracket on the arch, in the UPPER THIRD, is the only light source. The gateway flagstones fill the whole bottom half of the frame as one flat, evenly dark surface: no rubble, no puddle, no rut, no highlight, because rows of text with painted thumbnails beside them run down over it. Nobody in frame."],
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

	_iso()

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
		"%s Match `bg_crypt.png`: symmetrical one-point perspective, 20-35%% luminance, light source kept OUT of the top and bottom 34%% where the combat text sits. NO text painted into the image — `bg_warrens.png` came back with a 'THE WARRENS' sign in it, which a rename or a translation turns into a lie, and it took a re-roll to get out (D122)." % _backdrop_gap(),
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

	_section("Tier 5d — meta-screen backdrops",
		"Twelve screens, four paintings. The grouping is by PLACE and the argument for it is in `META_BG` in the tool; these are the screens that passed nothing to `UI.screen()` and were rendering the procedural tiling pattern (D123).",
		Kind.SCENE,
		"Full-bleed 16:9, opaque. One thing about these decides the whole composition and it is what separates them from Tier 5c: a shop or an event puts its prose in the top half and framed buttons below it, so there is a half of the frame nothing is written on, and those six are composed for it. These twelve are LISTS — a title on the top edge, rows down the middle, a button on the bottom edge. MEASURED off the 1280x720 captures of seven of them, UI ink runs from row 24 to row 684-688: **3% to 96% of the frame height, on every one of the seven**, against a backdrop whose brightest pixel in an empty patch is 26/255. There is no band of the frame text does not cross. On top of that `UI.screen()` lays a near-opaque scrim over the top of the image and fades it out about two thirds down (`SCENE_HOLD`/`SCENE_END` in `scripts/ui.gd`), leaving a light flat dim below — so the picture effectively SHOWS in the bottom third, and the bottom third is where the rows are. Compose for that and not against it: put the light source and everything worth looking at in the upper third, where the scrim will hold it back, and make the bottom half ONE continuous surface at one even value — a table top, a wall face, a floor — with no object, no edge and no highlight crossing it. A backdrop whose lower half has anything going on in it is a backdrop nobody can read a list over. Keep the whole image at the low end of the 20-35% luminance band. Empty rooms: no figures, and nothing anywhere that reads as writing.")
	for e in META_BG:
		_add("bg_%s.png" % String(e[0]), "1280x720", String(e[1]), null, String(e[2]))

func _relics() -> void:
	_section("Tier 6a — relic icons",
		"Painted objects on transparent, lit from upper-left, ink-outlined, readable at 48px. `relics_screen.gd` makes no icon call at all today — all 30 render as text rows.",
		Kind.PAINT,
		"One OBJECT, three-quarter view, centred, on a flat even field for the matte. Lit from upper-left. No hand holding it, no pedestal, no ground, no shadow, no background scenery. It is drawn at 22px in a row of thirty — MEASURED off the built screen, not the 48 this brief used to claim, which was written before anything was on it and before the row pitch was known (D121). At 22px the whole job is silhouette and one memorable colour: two or three big shapes, one clear outline, no small detail and no fine text-like ornament, because none of it survives. A beautifully rendered trinket that reads as a brown smudge has failed. Paint what the relic IS, not what it does.")
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

## Tier 8 — everything that STANDS on the isometric floor.
##
## These files all exist. They are computed by `tools/gen_iso_markers.gd`, and the
## reason is worth restating because it is easy to read this tier as a plan being
## reversed: D89 threw out the downloaded figure packs because they could not be
## COMMITTED — the monsters shipped with no licence file and the hero's store page
## says non-commercial. Authoring them in code was the answer to a redistribution
## problem, not a judgement that painted figures were wrong. Painting our own clears
## the same bar, so this tier is the licence question already answered rather than
## re-opened, and `gen_iso_markers.gd` stays as the fallback the way `Icons` does for
## the powers: a floor with no painted figure installed must still draw something.
##
## **The facings are the part that cannot be generated one file at a time.** `_s`
## faces the camera and `_n` is the SAME figure turned away — `iso_run.gd` swaps
## between them as she walks — so the two have to be one drawing seen twice. Asked
## for separately they come back as two different characters. Hence one sheet, two
## columns, and the column is the facing.
func _iso() -> void:
	_section("Tier 8a — isometric figures",
		"Every one of these exists and is a flat near-black silhouette; the floor is the screen a run is mostly spent on.",
		Kind.PAINT,
		"A small figure seen in three-quarter ISOMETRIC view from slightly above, standing on nothing, on a flat even field for the matte. It is composited onto a lit stone floor at about 90px tall and anchored BY ITS FEET, so the feet must be the lowest painted pixel and there must be no ground, no shadow, no plinth and no scenery under it. The whole tier's defect is that the current set is unlit: every figure measures luma 0.16-0.21 against a floor of 0.43-0.49, so they read as holes cut in the ground rather than as people standing on it. So these must be MID-VALUE AND LIT — clearly lighter than the floor across most of their body, lit from the upper left, with real interior: cloth, metal, skin, a face. A rim light alone is what is already there and is not enough.",
		"Two columns and one row per figure. The LEFT column faces the camera, the RIGHT column is the SAME figure from behind, same size, same colours, same silhouette width — it is one character turned around, not a second character. Flat even background, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- iso_figures <sheet.png>`")
	_add("iso/hero_s.png", "128x192", "The player, facing the camera.")
	_add("iso/hero_n.png", "128x192", "The player, walking away.")
	for fam in Balance.ISO_FAMILIES:
		_add("iso/mon_%s_s.png" % fam, "128x192",
			"A %s, facing the camera. It IS the fight this tile becomes, so it must match the arena's %s (D85)." % [fam, fam])
		_add("iso/mon_%s_n.png" % fam, "128x192", "The same %s, from behind." % fam)
	# Read off the screen that draws them rather than restated here. Four is not a
	# number this file gets to have an opinion about: `iso_run.gd` indexes wanderer
	# art with `design % WANDER_DESIGNS`, so a fifth painted file it does not know
	# about is a file nothing ever asks for (D34).
	for i in Balance.ISO_WANDERERS:
		_add("iso/wander_%d_s.png" % i, "128x192",
			"Wanderer design %d, facing the camera — something else walking the floor." % i)
		_add("iso/wander_%d_n.png" % i, "128x192", "Wanderer design %d, from behind." % i)

	_section("Tier 8b — isometric furniture",
		"What a tile IS, read off the floor before you walk into it.",
		Kind.PAINT,
		"A small object or prop seen in three-quarter ISOMETRIC view from slightly above, standing on nothing, on a flat even field for the matte, anchored by its base. Same lighting and same value rule as Tier 8a: clearly lighter than the floor, lit from the upper left, real material. No ground, no shadow, no scenery.",
		"One row of seven, in the order of the table below. Flat even background, nothing touching a cell edge. THE THREE FIGHT MARKERS ARE THE WHOLE POINT OF THIS SHEET and they are why it is drawn as a set: today `combat`, `elite` and `boss` are the same silhouette to the pixel, so the floor cannot tell you whether the room ahead is a trash fight or the thing that ends the run, and that is the one decision the map exists to support. Give the three visibly ESCALATING silhouettes — bigger, taller, more of it — not three tints of one shape. Install: `godot --headless --script tools/install_sheet.gd -- iso_furniture <sheet.png>`")
	_add("iso/combat.png", "128x192", "An ordinary fight waiting on this tile.")
	_add("iso/elite.png", "128x192", "A harder fight — bigger than `combat.png` at a glance.")
	_add("iso/boss.png", "128x192", "The floor's boss — unmistakably the biggest of the three.")
	_add("iso/shop.png", "128x192", "A merchant's stall, nobody behind it.")
	_add("iso/rest.png", "128x192", "A campfire. A light source, so it is the one thing here that glows.")
	_add("iso/event.png", "128x192", "A standing rune-stone. Something to read, not to fight.")
	_add("iso/treasure.png", "128x192", "A chest, shut.")

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
		if _generable(r[4]) and (not bool(r[3]) or _redo(String(r[0])) != ""):
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
		elif _redo(String(r[0])) != "":
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
			reasons[_redo(String(r[0]))] = true
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
					_redo(String(r[0])).replace("|", "\\|")])
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
