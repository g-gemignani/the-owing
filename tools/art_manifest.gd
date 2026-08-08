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
	## An animation. Frame-to-frame coherence is not something to prompt for.
	## NOTHING uses this today — the six combat effects that did are drawn at runtime
	## by `scripts/fx.gd` (D129). Kept as vocabulary: the next animation to come up
	## should be classified before someone briefs eight frames of eight explosions.
	SHEET,
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

## A `REDO_SILHOUETTE` constant sat here, held by all thirty-five combat plates: they
## were procedural silhouettes out of `gen_enemy_art.gd`, flat interiors behind a
## one-sided rim light, and they counted as PRESENT so Tier 2 printed "all 35 present"
## and the prompt sheet said nothing about them. All thirty-five were painted in D122
## and it went out with them, the same way REDO_TILED and REDO_ISO did. The measure that
## caught it is worth keeping: mean luminance does NOT separate a painting from a
## silhouette here (the brief wants these dark-weighted), and neither does plain interior
## variance (the rim is a big swing). Erode the mask first, then measure — ember_hound
## went 0.024 -> 0.093, brute 0.052 -> 0.086.


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
	# `main_menu.png` was here, and it was the last line in the table. It went in D114
	# for carrying no ink outline and survived TWO re-rolls of the same picture, each
	# measuring ~1.2% against 2.8-12.2% for the dungeons. Two explanations were tested
	# and killed — normalising for darkness, and a local-contrast threshold instead of
	# an absolute one — which left the subject itself as the suspect: the dungeons are
	# near-field architecture where every form can be outlined, and this was a night
	# exterior receding into haze. Re-composed CLOSE-UP in D122, everything within a few
	# paces, and the same scene now measures 10.5% ink against bg_foundry's 7.8%, mean
	# luminance 0.307 inside the 20-35% band, and 0.029% of pixels over 0.90 — cleaner
	# than bg_crypt. The hypothesis was right and it took a subject change, not a
	# fourth attempt at the same one.
	#
	# `main_menu.png` is back, and for a different defect than last time. D134 measured
	# 41.5% of the frame in a green hue band against 0.0% in `bg_crypt.png`, the reference
	# attached to every request — the largest hue mass in the game's front door was a
	# colour that appears NOWHERE in the style bible. The cause was the noun, not the
	# palette line: the subject said "a valley of firs" and firs are green.
	#
	# What is on disk now is a GRADE, not a painting: `tools/regrade.gd` moved the green
	# band into violet-blue in place, which took green to 0.0% and left the cyan flame
	# untouched at 7.5%. That was the right call — the composition had taken three
	# attempts and only the hue was wrong — but a remapped hue is not the same picture a
	# generator would have painted in that palette, and D134 says so itself: "the brief is
	# the durable fix ... if the title art is re-rolled, the new file should come back
	# inside the palette on its own".
	#
	# So this line is here to have that re-roll done against the corrected brief, which
	# now names the colour at the noun ("NO GREEN ANYWHERE IN THE FRAME: the firs are black
	# and violet-grey silhouettes at night, not foliage"). The test is the same measurement:
	# green under a percent or so without any grade applied afterwards. Until then the front
	# door of the game is a patched file rather than a painted one.
	# `main_menu.png` was here a second time and came out the same day. D134 fixed the
	# brief and GRADED the installed file — a hue remap, not a painting — and predicted a
	# re-roll would come back inside the palette on its own. It did, but only after a
	# second correction, and the first attempt is the part worth keeping:
	#
	#   attempt 1, brief as D134 left it   green 0.0%  BUT sat-in-light 0.211, colour on
	#                                      45% of lit pixels — a neutral grey night with
	#                                      one cyan flame, against the bible's 0.535/99.9%
	#   attempt 2, violet named at the noun green 0.0%, sat-in-light 0.422, colour 98.1%,
	#                                      blue 86.2% against the bible's 86.4%, mean
	#                                      luminance 0.238 inside the 20-35% band
	#
	# The brief had said what the picture must NOT be and left what it must BE to the word
	# "desaturated", so the generator desaturated all of it — D134's own "a concrete noun
	# beats an adjective", arriving from the other side (D137). Naming violet positively
	# where the nouns are fixed it in one attempt. `tools/regrade.gd` now reports "already
	# inside the palette — nothing to do" on the installed file, which is the check that
	# says this is a painting rather than another patch.
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
	# Every figure that stands on the isometric floor, and the reason is the floor itself.
	# The tile is 116x58 — exactly 2:1 — so the camera looks DOWN at it from about 27
	# degrees, and the four walking directions all run diagonally across the screen. Every
	# one of these files is drawn HEAD-ON AT EYE LEVEL and bilaterally symmetric, which is
	# a standee standing on an isometric floor rather than a figure standing in it.
	#
	# It is not a slip in one batch: the 23 hand-painted figures shipped this way and the 70
	# per-archetype ones inherited it, because the fronts were cut from combat plates that
	# are framed head-on into the corridor BY DESIGN (Tier 2 says so). The brief above always
	# asked for a three-quarter isometric view; nothing ever measured whether that is what
	# arrived, because "present" is the only question this file used to ask.
	#
	# Two consequences beyond the look, both now real: `IsoFooting.facing_mirrored` mirrors
	# each file to get the other two of the four directions, and a symmetric figure mirrors
	# to ITSELF — so the whole facing model has been decorative. And a figure painted on the
	# wrong diagonal walks sideways on half the compass once it is not symmetric.
	"iso/": "HEAD-ON, and the floor is isometric — redraw at the camera's own angle (see the brief).",
}

## Files under a `REDO_DIRS` prefix that have ALREADY been redrawn, so the sheet stops asking
## for them. The iso redraw (D202) is 97 files and cannot be done in one sitting: without this,
## the prompt sheet keeps listing everything already finished, and dropping the directory rule
## instead would stop it asking for the ones that are not.
##
## Grown as each sheet lands, and it goes out with the `iso/` line when it reaches all 97.
const REDO_CLEARED := [
	# Tier 8a, all 20: the hero's six, the three families, the four wanderers.
	"iso/hero_s.png", "iso/hero_n.png",
	"iso/hero_s_a.png", "iso/hero_n_a.png", "iso/hero_s_b.png", "iso/hero_n_b.png",
	"iso/mon_swarm_s.png", "iso/mon_swarm_n.png",
	"iso/mon_brute_s.png", "iso/mon_brute_n.png",
	"iso/mon_caster_s.png", "iso/mon_caster_n.png",
	"iso/wander_0_s.png", "iso/wander_0_n.png",
	"iso/wander_1_s.png", "iso/wander_1_n.png",
	"iso/wander_2_s.png", "iso/wander_2_n.png",
	"iso/wander_3_s.png", "iso/wander_3_n.png",
	# Tier 8b, six of seven. `treasure` is NOT here: the sheet came back with that cell
	# empty, so the chest on disk is still the head-on one.
	"iso/combat.png", "iso/elite.png", "iso/boss.png",
	"iso/shop.png", "iso/rest.png", "iso/event.png",
	# Tier 8c, redrawn in batches of three creatures a sheet.
	"iso/foe/abyss_horror_s.png", "iso/foe/abyss_horror_n.png",
	"iso/foe/bellows_brute_s.png", "iso/foe/bellows_brute_n.png",
	"iso/foe/bellows_master_s.png", "iso/foe/bellows_master_n.png",
	"iso/foe/bog_lurker_s.png", "iso/foe/bog_lurker_n.png",
	"iso/foe/bone_picker_s.png", "iso/foe/bone_picker_n.png",
	"iso/foe/brood_mother_s.png", "iso/foe/brood_mother_n.png",
	"iso/foe/brute_s.png", "iso/foe/brute_n.png",
	"iso/foe/cinder_knight_s.png", "iso/foe/cinder_knight_n.png",
	"iso/foe/crypt_hound_s.png", "iso/foe/crypt_hound_n.png",
	"iso/foe/cultist_s.png", "iso/foe/cultist_n.png",
	"iso/foe/deep_warden_s.png", "iso/foe/deep_warden_n.png",
	"iso/foe/drowned_thrall_s.png", "iso/foe/drowned_thrall_n.png",
	"iso/foe/ember_hound_s.png", "iso/foe/ember_hound_n.png",
	"iso/foe/false_step_s.png", "iso/foe/false_step_n.png",
	"iso/foe/forge_hound_s.png", "iso/foe/forge_hound_n.png",
	"iso/foe/fungal_host_s.png", "iso/foe/fungal_host_n.png",
	"iso/foe/grave_moth_s.png", "iso/foe/grave_moth_n.png",
	"iso/foe/grave_sexton_s.png", "iso/foe/grave_sexton_n.png",
	"iso/foe/hexer_s.png", "iso/foe/hexer_n.png",
	"iso/foe/last_vendor_s.png", "iso/foe/last_vendor_n.png",
	"iso/foe/market_ghoul_s.png", "iso/foe/market_ghoul_n.png",
	"iso/foe/marrow_abbot_s.png", "iso/foe/marrow_abbot_n.png",
	"iso/foe/marrow_priest_s.png", "iso/foe/marrow_priest_n.png",
	"iso/foe/maw_tender_s.png", "iso/foe/maw_tender_n.png",
]

## A `REDO_CLEARED` list lived here while Tier 2 was half repainted — the thirty-five
## enemy plates could not be done in one sitting, and midway both available answers were
## wrong: leave the directory rule alone and the sheet asks for files already finished,
## drop it and it stops asking for the ones that are not. It started empty, grew as the
## six sheets landed, and went out with the `REDO_DIRS` line when it reached all
## thirty-five (D122). Bring it back the same way the next time a family is repainted
## across more than one session.


## The defect recorded against a file, or "" if there is none. Every reader goes
## through this rather than indexing `REDO`, so the directory rule cannot be honoured
## in one place and forgotten in another — which is exactly how the prompt sheet and
## the asset sheet would start disagreeing about what is wrong.
func _redo(rel: String) -> String:
	# Checked FIRST, so a file that has already been redrawn is clear of the directory rule
	# that put it on the list. Every reader goes through this one function (see below), which
	# is what stops the two sheets disagreeing about what is still outstanding.
	if rel in REDO_CLEARED:
		return ""
	if REDO.has(rel):
		return String(REDO[rel])
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
	# Not a status — the only entry here that names a CONTROL rather than a rule. It
	# lives in this table because `PixelArt.symbol()` resolves `ui/sym_<name>.png`, so
	# that filename is what the settings door in every screen's top-right corner asks
	# for; anywhere else and it would not be found. Until it lands that control renders
	# the word "Settings", which is why nothing is broken while this row is unfilled —
	# and why the row exists at all, so the absence is on the shopping list instead of
	# in somebody's memory (D133).
	["gear", "Settings. The door in the top-right corner of every screen.",
		"A cog of dark iron, seen face-on, six square teeth and a round hole at its centre. One solid shape, nothing behind it."],
]

## Tier 1e — combat VFX — used to live here: six `fx/*.png` sprite sheets, 8 frames of
## 256x256 each, for the slash, impact, ward, poison cloud, heal and death dissolve.
## This manifest lists files THE GAME WILL LOOK FOR, and it will never look for those:
## `scripts/fx.gd` draws all six at runtime out of primitives, particles and one
## dissolve shader (D129).
##
## Kept as a note rather than deleted, because "no combat feedback animation at all"
## was the single most-cited gap in this file and its absence needs an explanation
## that is not silence. The row that briefs a file nobody loads is the expensive kind
## of stale (D101) — and a SHEET row is worse than an ordinary one, because the only
## way to fill it is by hand.

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
	["fonts/display.ttf", "-", "Display face for titles and card names. Cinzel Bold 2.000, OFL 1.1 — Roman inscriptional, which is what the frame kit is already pretending to be. Bold, not Regular: this is the card NAME too, and `UI.fit_label` takes a name to 7px in a crowded fan where hairline serifs disappear. Wired as `UITheme.display_face()`.", Kind.LICENCE],
	["fonts/body.ttf", "-", "Body face for rules text. Must stay legible at 12px, since card text shrinks to fit — Fira Sans Regular 4.203, OFL 1.1, picked by rendering the shortlist at 12/14/16px rather than by taste: largest x-height and most open counters of the set. Theme `default_font`, so nothing falls back to the engine face.", Kind.LICENCE],
	## The title art was the one painting in the tree that no row named, so the sheet
	## could not report it either way — the tier that owns the title screen listed the
	## logo that sits on top of it, the boot splash before it and (then) the cursor over
	## it, and not the picture itself. That is why it stayed off the re-roll list while
	## being the most-seen image in the game (D114).
	["main_menu.png", "1280x720", "The title screen backdrop. `main_menu.gd` resolves it through `PixelArt.title_art_path()`. The menu column is the LEFT 40% under a 0.82 scrim held across 42%, so the left third is covered and the subject belongs right of centre. It was `.jpg` until D114 renamed it on the re-roll; this row is one of the references that had to move with it, and it did not until D122 noticed the tier still reporting one file missing.", Kind.SCENE,
		"A lone hooded traveller seen from behind on a ridge at night, looking up at a black fortress spire far off across a valley of firs. NO GREEN ANYWHERE IN THE FRAME: the firs are black and violet-grey silhouettes at night, not foliage, and the traveller's cloak is the same cold stone colour as the rock — a forest and a cloak are the two things a painter reaches for green for, and this palette does not have it. THE PICTURE IS STILL IN COLOUR AND THE COLOUR IS VIOLET: the rock, the cliffs, the distant mountains and the cloak are all a deep blue-violet stone, plainly violet against a violet-blue night sky, never neutral grey and never black-and-white. One cold cyan flame in a stone bowl beside them is the only light source and the only saturated colour in the image. Weight the traveller and the flame RIGHT OF CENTRE and keep the left third quiet — a text column sits over it. Moonless, or a moon kept small and dulled: nothing in the frame reads as pure white."],
	["ui/logo.png", "1600x480", "The wordmark. The title screen sets a plain Label reading 'THE OWING' into this plate's empty middle. The ONE asset that has to carry text: generate the ornament, set the type yourself.", Kind.PAINT,
		"An ornamental stone cartouche, wide and shallow, carved edge, symmetrical, EMPTY across its whole middle where type will be set later. No lettering of any kind."],
	["ui/boot_splash.png", "1280x720", "Boot splash. None configured.", Kind.SCENE,
		"A shut iron door at the foot of a stair, one lantern burning above it, seen head-on. Nobody in frame."],
	## `ui/cursor.png` and `ui/cursor_press.png` used to close this table: a painted iron
	## spike and a driven-in variant, installed and hotspot-measured across D125 and
	## D133. Both are gone (D138). The game does not replace the system pointer, so
	## these are not "optional" any more — they are two files nothing would load, which
	## is the state this manifest exists to make impossible.
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
## Tier 3b's subject, one line per card. Hand-written, and that is the correction this
## table exists to make (D138).
##
## D131 built Tier 3b to DERIVE its subject from the `.tres` — name, description and
## family — so there would be no second list to drift out of step with
## `resources/cards/`. The reasoning is right about drift and wrong about what a
## generator can read: what it derived was `**Bandage.** Heal 6. Exhaust. A heal card.`,
## which is a RULE, and D101 already recorded where that ends — *"a generator can only
## draw an object; 'Block.' and 'A choice with consequences' are rules, and a rule
## prompts a diagram."* Worse, the derived line carries NUMERALS into a style block whose
## FORBIDDEN list opens with them, so every prompt argued with itself.
##
## A picture cannot be derived from arithmetic. So the picture is written down and the
## mechanics stay derived: the effect line still comes off the `.tres` and is appended as
## CONTEXT after the subject, which means a retuned card still gets a corrected prompt
## for free and only the painting has to be authored once. The guard below makes the
## drift D131 feared LOUD rather than silent — a new card with no line here is a fatal
## error in this tool, exactly as an undescribed family already is.
##
## House rules for a line: one concrete thing, no numerals, no keyword nouns (Block,
## Vulnerable, Exhaust mean nothing to a painter), and distinct from both its family's
## picture and its siblings' — twenty attack cards that all read "a sword" would put the
## tier back where it started.
const CARD_SUBJECT := {
	# --- attack ---
	"all_you_have": "A greatsword swung with both hands and nothing held back, the swordsman's guard wide open behind it.",
	"bite": "Teeth closing on an armoured forearm, the bite deep enough to draw the arm down.",
	"cheap_shot": "A short knife going in low under a raised guard, from behind.",
	"counterblow": "A blade caught on a bracer and a second blade already coming back the other way.",
	"dead_weight": "A blunt iron weight at the end of a slack chain, swung on its own momentum.",
	"decapitate": "An axe at the top of its arc above a bowed neck, the stroke not yet begun.",
	"drilled": "The same thrust worn into the air three times over, each ghost of it straighter than the last.",
	"execute": "A sword point resting in the gap of a fallen figure's gorget.",
	"exsanguinate": "A hollow blade drawing a dark thread of blood out along its fuller.",
	"forge_strike": "A hammer coming down on a blade laid across the anvil, sparks going up.",
	"gash": "One long clean opening cut across dark leather armour, the edges parting.",
	"grinding_down": "A whetstone worked along an edge that has been worked too many times already.",
	"hack": "A heavy chopping blade buried in a shield rim and being wrenched free.",
	"heavy_swing": "A maul at the far end of a full-body swing, the wielder's heels off the ground.",
	"in_and_out": "A short blade going in and the same figure already turning away from the wound.",
	"jab": "A short straight punch of a blade, thrown without stepping in.",
	"last_word": "A duelling blade thrust clean through, hilt-deep, the arm behind it locked straight.",
	"leech": "A dark blade drinking, one thin line of red climbing the steel against gravity.",
	"lifedrain": "A gauntleted hand closed on a ribcage with light draining out between the fingers.",
	"nick": "The smallest possible cut, opening on a knuckle, a single bead standing on it.",
	"old_debt": "A tally stick snapped in two, its notched half driven into a table like a blade.",
	"ram": "A shield turned edge-on and driven forward as the weapon itself.",
	"salt_the_wound": "A fistful of coarse grey salt scattered across an open cut.",
	"sanguine_feast": "A goblet of cut stone brimming and running over, held in an armoured fist.",
	"shoulder": "An armoured shoulder driven into a shield, both figures going off balance.",
	"stave_in": "A war pick punching a hole clean through a breastplate and staying there.",
	"thrown_iron": "A throwing knife caught mid-flight, still turning, its handler's hand open behind it.",
	"whetted_edge": "An edge held up to the light, one bright hairline running its whole length.",
	# --- attack_aoe ---
	"black_tide": "A black wave rearing across the frame with shapes drowning inside it.",
	"clear_the_room": "One blade sweeping a full circle, cutting through several standing shapes at once.",
	"massacre": "A wide killing arc that has already finished, the shapes on both sides falling away.",
	"reap": "A long scythe drawn level through a standing crop of dark shapes.",
	"riptide": "A backwash of dark water dragging several figures off their feet at once.",
	# --- attack_multi ---
	"cull": "Three quick cuts laid across a line of shapes, one shape dropping out of the line.",
	"keep_hitting": "The same fist landing over and over on the same spot, the dent deepening.",
	"pressure": "A blade held against a breastplate and leaned on, the metal beginning to give.",
	"sword_dance": "One figure mid-turn with three blade arcs closing around it like a shell.",
	"two_quick": "Two short thrusts thrown so fast their arcs overlap into one shape.",
	# --- block ---
	"anvil_stance": "A shield planted on an anvil's flat, braced and immovable.",
	"brace": "Both feet set wide behind a shield jammed against the ground.",
	"bulwark": "A wall of overlapping shield-iron filling the frame, no gap in it anywhere.",
	"cover": "A figure ducked behind a broken slab of masonry, only the helm showing.",
	"double_down": "A second shield brought up behind the first, the two rims locking.",
	"feint": "A shield swung wide to draw an eye, the real hand empty and low.",
	"give_ground": "A shield-bearer stepping back one pace with the shield never dropping.",
	"guard": "A high guard held with the shield up under the eyes, nothing showing above it.",
	"iron_lung": "A deep breath drawn behind a closed visor, the chestplate expanding against its straps.",
	"kelp_snare": "Wet black kelp wound around an ankle and pulling tight.",
	"last_stand": "One shield-bearer alone with the shield still up, everything else in the frame broken.",
	"rally": "A hand pulling another fighter back onto their feet by the wrist.",
	"set_stone": "A slab of dressed stone lowered into a wall and settling, mortar squeezing out.",
	"shield_wall": "Shields locked edge to edge in a line running out of frame both ways.",
	"shut_out": "A studded door slammed and barred from the inside, the bar dropping into its brackets.",
	"sidestep": "A blow passing through the space a figure has just left.",
	"survival_instinct": "A forearm thrown up over the face before the mind has caught up.",
	"take_it": "A blow landing square on a braced shoulder, the bearer not moving.",
	# --- heal ---
	"bandage": "A strip of stained linen wound tight around a forearm and knotted off.",
	"bloodlust": "A wound closing over as the fist above it clenches harder.",
	"deep_breath": "A helm lifted off and a long breath taken in cold air.",
	"second_heart": "A second heart beating in an opened ribcage, lit from within.",
	"stitch": "A curved needle drawing catgut through the lips of a cut.",
	# --- draw ---
	"abyssal_gift": "A hand reaching up out of black water holding something out, palm open.",
	"kick": "A boot driving a jammed door open, light coming through the gap.",
	"read_ahead": "A finger held on a line partway down a page already turning.",
	"see_it_coming": "A blow seen an instant early, the eye wide and the head already moving.",
	# --- poison ---
	"blight_bloom": "A pale flower opening on a corpse-grey stalk, spores lifting off it.",
	"creeping_death": "A grey rot spreading along a limb, further at the wrist than at the elbow.",
	"noxious_cloud": "A low yellow-green fog rolling across flagstones at knee height.",
	"pandemic": "A dead field of stalks all bent the same way, every one of them blackened.",
	"plague_bearer": "A hooded figure walking away, leaving a trail of dying ground behind it.",
	"plague_heart": "A swollen black heart in a nest of veins, pulsing and feeding the veins.",
	"rot_touch": "A bare fingertip pressed to skin, the grey spreading out from the contact.",
	"scrape": "A rusted nail drawn across a forearm, the scratch already going dark at its edges.",
	"split": "A blistered pod bursting and throwing wet spores out both sides.",
	"spore_burst": "A puffball crushed underfoot, its cloud going up around the boot.",
	"venom_fang": "One hollow fang, a single drop hanging off the point of it.",
	"virulence": "Black veins running visibly outward under skin, faster than they should.",
	# --- strength ---
	"focus": "A single eye narrowing, everything around it falling out of focus into dark.",
	"red_mind": "A helm with red light behind both eye slits and nothing human in it.",
	"smiths_fury": "A smith bringing the hammer down twice as hard as the work needs.",
	"something_worse": "A shape in a doorway that is bigger than the doorway was a moment ago.",
	"undying": "A skeletal hand closing on a sword grip and pulling itself upright.",
	"work_up": "A back and shoulders swelling under a leather harness, the straps going tight.",
	# --- dexterity ---
	"clear_mind": "Fog pulling back off still water to leave one clear reflection.",
	"light_on_it": "A boot resting on a stretched rope, the rope barely dipping.",
	"stone_skin": "A forearm turning to dressed grey stone, the joins showing at the knuckles.",
	# --- thorns ---
	"bramble_armour": "A breastplate overgrown with woody bramble, every thorn turned out.",
	"bristle": "A hide standing its spines straight up along the spine ridge.",
	"iron_will": "An iron collar with the spikes pointing inward and the wearer unmoved.",
	"molten_core": "A hollow chest cavity glowing furnace-orange behind a cage of iron ribs.",
	"riposte": "A blade turned aside onto a spiked bracer, the attacker's hand torn on it.",
	"sharp_ground": "Broken caltrops and bone shards scattered across a floor.",
	"spiked_guard": "A shield with a ring of spikes worked through its face, one already bloodied.",
	"thorn_crown": "A circlet of black iron thorns, the points turned in toward the wearer.",
	# --- weak ---
	"cold_read": "A stare that has found the flaw, the read figure's guard beginning to sag.",
	"put_the_fear": "A helm turned slowly toward the viewer and a figure backing out of frame.",
	"smoke_bomb": "A clay ball burst on flagstones, grey smoke going up in a column.",
	# --- vulnerable ---
	"hex": "A hooked sign cut into the air above a group of dark shapes, glowing faintly.",
	"stumble": "A foot catching on a raised flagstone, the body already past its balance.",
	"wither": "A hand shrivelling around its own grip, the weapon loosening in it.",
}

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

	# --- data-driven from here down ------------------------------------------
	_enemies()
	_cards()
	_cards_unique()
	_level_fx()
	_backdrops()
	_relics()
	_powers()

	_section("Tier 7 — identity and shell", "Two of these are downloads, not drawings.",
		Kind.PAINT,
		"The fonts are licensed downloads (OFL/SIL), not drawings — both now installed, with the upstream OFL verbatim beside them and a sha256 of each shipped binary in `assets/art/fonts/PROVENANCE.txt`. The logo is the one asset in the game that must carry text and the one place a generator is reliably wrong — generate the ornament and set the wordmark yourself.")
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
		"Subject alone on a FLAT, EVEN field of a single colour that appears nowhere in the subject — that field is what `tools/install_cutouts.gd` mattes away, and it refuses any image whose border is not flat rather than cutting a hole in a painted wall. Full body, feet included, nothing cropped by the frame edge. NOTHING BENEATH THE SUBJECT: no ground, no floor, no flagstones, no paving, no dirt, no platform, no plinth, no base, no shadow, no pool of light, no scenery. Its feet touch nothing and the flat field runs right up to the soles. Facing the viewer, lit from above-front, and the lower body and feet a shade darker than the head and shoulders. One monster per image. Generate at 1024x1024 and let the installer scale down: the boss files are rendered at 1.34x the ordinary size and an upscaled boss is a soft boss.")
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

## Tier 3b — one painting per card, which is what the family tier was always a stand-in
## for. `PixelArt.painted_card_art()` has checked `cards/<card_id>.png` BEFORE
## `cards/<family>.png` since the family art landed, so this tier needs no code: every
## file added here simply takes over from the shared one, and a card with no unique
## painting keeps its family's. That is the same one-file-at-a-time contract the relics
## and the powers run on, and it is why this can be worked through a few cards at a time
## rather than as a hundred-file blocking batch (D131).
##
## The subject is SPLIT, and D138 is why. The picture comes from `CARD_SUBJECT` above,
## hand-written once per card; the mechanics stay derived off the `.tres` and follow it
## as context. D131 derived the whole thing and produced `**Bandage.** Heal 6. Exhaust.`
## — a rule, not a picture, with a numeral in it that the style block's FORBIDDEN line
## bans. Arithmetic cannot be painted; the effect it belongs to can. Splitting keeps what
## D131 was right about (a retuned card corrects its own prompt) and drops what it was
## wrong about (that a subject is derivable at all).
func _cards_unique() -> void:
	_section("Tier 3b — one illustration per card",
		"The family paintings in Tier 3 are shared by up to twenty cards each; these replace them one at a time. Nothing breaks while it is half done — the per-card file is checked first and the family file is the fallback.",
		Kind.SCENE,
		"A filled 4:3 rectangle, not a cutout — the picture band across the top of a card, filling it edge to edge. One clear subject, centred, read at 320x240 and shown about 3cm wide. LEAVE THE FOUR CORNERS QUIET AND EMPTY: top-left and top-right about a quarter of the width and a fifth of the height, bottom-left and bottom-right the same height and nearly half the width. Quiet means plain background — no object, no plate, no badge, and above all NO NUMERAL AND NO SYMBOL, because the game draws the real cost and damage over those corners and a painted one sits under it as a lie. The bottom two fifths sit under a shadow that deepens almost to black at the bottom edge, so weight the subject into the upper middle and let the lower edge fall away. Paint THIS CARD, not its family: the whole point of this tier is that the twenty cards sharing one picture stop sharing it.")
	# Same shape as the family guard above, for the same reason: a card with no picture
	# written for it must be a loud failure here, not a quiet fallback to its rule text.
	# This is the whole answer to the drift D131 was avoiding — the second list cannot go
	# stale unnoticed, because the tool refuses to emit while it is.
	var unpainted: Array[String] = []
	for cid in PixelArt.card_ids():
		if not CARD_SUBJECT.has(cid):
			unpainted.append(String(cid))
	if not unpainted.is_empty():
		_fatal = ("no CARD_SUBJECT line for %d card%s (%s) — add one to tools/art_manifest.gd. "
			+ "The card's effect text is NOT an acceptable fallback subject: it is a rule, "
			+ "and a rule prompts a diagram (D101, D138).") % [
			unpainted.size(), "" if unpainted.size() == 1 else "s", ", ".join(unpainted)]
		return

	for cid in PixelArt.card_ids():
		var c := load("res://resources/cards/%s.tres" % cid) as CardData
		if c == null:
			continue
		var fam := Icons.card_family(c)
		# The picture first and on its own sentence, because it is the instruction. The
		# rest is context and reads as context: what the card does, and which family it
		# sits in, so a painter can keep it distinct from its twenty neighbours.
		var bits: Array[String] = ["**%s.**" % c.name, String(CARD_SUBJECT[cid])]
		# "A attack card" reads as a typo in a hundred prompts, and these are read by a
		# person as often as by a generator.
		var fam_words := fam.replace("_", " ")
		var article := "An" if fam_words.substr(0, 1) in ["a", "e", "i", "o", "u"] else "A"
		bits.append("%s %s card%s" % [article, fam_words,
			(": %s" % c.description) if c.description != "" else "."])
		_add("cards/%s.png" % cid, "320x240", " ".join(bits))

## Tier 3c — the level-progress overlays, and the reason there are six of them.
##
## The ask was effects layered onto a card as it is fused, with a distinct one at max,
## WITHOUT multiplying the art. Done naively that is 100 cards x 3 milestones = 300 new
## paintings, and per-rarity variants would make it 1500. These are six.
##
## What makes that work is that the effect is not part of the illustration. It is a
## SEPARATE image composited over the top and tinted by rarity at draw time, so it does
## not care which card is underneath it — the same three files sit over all hundred, and
## `Icons.rarity_colour` supplies the five colours without five more files.
##
## Six rather than three only because a card's illustration band is 4:3 and a power's
## sigil is square, and one image cannot be both without stretching. The milestones are
## FRACTIONS of each thing's own track (`PixelArt.level_band`), never absolute levels: a
## Common card caps at 100 and a Legendary at 5, Bulwark at 10 and Foresight at 2, so
## "at level 5" is unreachable for one and immediate for another (D132).
func _level_fx() -> void:
	_section("Tier 3c — level-progress overlays",
		"Six files that serve every card and every power at every rarity. Composited over the art, not painted into it.",
		Kind.SCENE,
		"A LAYER, not a picture: this is drawn ON TOP of a finished illustration, so most of the image must be EMPTY BLACK — pure #000000, which the game adds rather than blends, so black is invisible and only the light shows. Paint ONLY the effect and leave everything else black. It must be MONOCHROME, a single warm-white light, because the game tints it to the card's rarity colour; any colour painted in fights that tint. Keep the effect to the EDGES of the frame and the area behind where a subject would stand — the middle must stay clear enough to read the illustration through, and the FOUR CORNERS must stay completely black because the game draws the cost and the damage over them. No text, no numerals, no symbols, no runes, no object: this is light, not a thing. The three steps must read as ESCALATION at a glance and at thumbnail size, which means each one is bigger and brighter than the last rather than merely different.")
	for shape in [["card", "320x240", "the illustration band of a card"],
			["power", "128x128", "a power sigil"]]:
		_add("fx/lvl_%s_1.png" % shape[0], String(shape[1]),
			"First milestone on %s — a third of the way up its track. The FAINTEST of the three: a thin arc of light along the lower edge and a breath of glow creeping in from the two lower corners. Barely there; it should read as 'this one has been touched' and nothing louder." % shape[2])
		_add("fx/lvl_%s_2.png" % shape[0], String(shape[1]),
			"Second milestone on %s — two thirds up. The arc has closed into a full thin ring of light around the whole subject area, brighter than the first, with a few small sparks lifting off it. Still clear in the middle." % shape[2])
		_add("fx/lvl_%s_max.png" % shape[0], String(shape[1]),
			"MAXED on %s — the end of the track and the one state a player is working toward, so it must be unmistakable and different in KIND, not just brighter. A full radiant corona breaking outward past the ring, thick rays reaching to the frame edges, the whole border alight. The middle is still readable but everything around it is burning." % shape[2])

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
		"Full-bleed 16:9, opaque. One thing about these decides the whole composition and it is what separates them from Tier 5c: a shop or an event puts its prose in the top half and framed buttons below it, so there is a half of the frame nothing is written on, and those six are composed for it. These twelve are LISTS — a title on the top edge, rows down the middle, a button on the bottom edge. MEASURED off the 1280x720 captures of seven of them, UI ink runs from row 24 to row 684-688: **3% to 96% of the frame height, on every one of the seven**, against a backdrop whose brightest pixel in an empty patch is 26/255. There is no band of the frame text does not cross. On top of that `UI.screen()` lays a near-opaque scrim over the top of the image and fades it out about two thirds down (`SCENE_HOLD`/`SCENE_END` in `scripts/ui.gd`), leaving a light flat dim below — so the picture effectively SHOWS in the bottom third, and the bottom third is where the rows are. Compose for that and not against it: put the light source and everything worth looking at in the upper third, where the scrim will hold it back, and make the bottom half ONE CONTINUOUS SURFACE — a table top, a wall face, a floor — with no object, no edge, no seam and no highlight crossing it. QUIET IS NOT EMPTY, and the difference is the whole of D125: that surface must still be PAINTED, with visible tooth and grain and brush-work all the way down to the bottom edge, the way a real stone slab or a plank is painted. What it must not have is FEATURES — nothing an eye stops on, nothing that competes with a row of text. An earlier wording asked for 'one even value' and 'no grain that changes value', and three of the four came back with the lower half filled in as a flat rectangle: bg_world measured row-variance 0.001 below 65% of frame height against 0.049-0.202 across bg_crypt, and on a sparse screen like Packs that is a grey slab covering the bottom 60%. Keep every row's horizontal variation above about 0.02 — low, but never nothing. Keep the whole image at the low end of the 20-35% luminance band. Empty rooms: no figures, and nothing anywhere that reads as writing.")
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
		"A small figure seen from the ISOMETRIC CAMERA THIS GAME ACTUALLY USES, which is not a head-on view. The floor tile is 116x58 - exactly 2:1 - so the camera looks DOWN at the floor from about 27 degrees above it. Draw the figure from that height: you see the top of its head and its shoulders, its feet are further down the frame than a head-on view would put them, and the ground it stands on would read as a flattened diamond rather than a line. It is also TURNED: the four walking directions all run diagonally across the screen, so the figure faces a DIAGONAL, three-quarter, never straight out of the frame. IT FACES DOWN AND TO THE LEFT - toward the camera and to the viewer's left, at 45 degrees, so the viewer sees the front of it and its left-hand side at once. Standing on nothing, on a flat even field for the matte: the feet must be the lowest painted pixel and there must be no ground, no shadow, no plinth and no scenery under it. Mid-value and lit from above and in front, clearly lighter than the floor across most of the body, with real interior: cloth, metal, skin, a face.",
		"Two columns and one row per figure. LEFT column: the figure walking TOWARD the camera and to the viewer's LEFT (down-left, 45 degrees). RIGHT column: the SAME figure walking AWAY and to the viewer's RIGHT (up-right, 45 degrees) — seen from behind and above, one character turned around, not a second character, same size and colours and silhouette width. THOSE TWO ANGLES ARE NOT NEGOTIABLE: the game mirrors each file to get the other two of the four walking directions (`IsoFooting.facing_mirrored`), so a figure drawn facing straight out of the frame mirrors to itself and the mirror does nothing, and a figure drawn on the WRONG diagonal walks sideways on half the compass. Flat even background of a single colour that appears nowhere in the subject, nothing touching a cell edge. Install: `godot --headless --script tools/install_sheet.gd -- iso_figures <sheet.png> --key`")
	_add("iso/hero_s.png", "128x192", "The player, facing the camera. Standing still: this is the pose the floor draws whenever she is not mid-step.")
	_add("iso/hero_n.png", "128x192", "The player, walking away. Standing still.")
	# Her walk. Two poses per facing, alternated once per step by `iso_run.stride`, and the
	# reason there are two rather than four is that the model moves one tile per turn — a
	# step IS the unit of the cycle, so a third pose would never be on screen at a decision
	# point. The standing paintings above stay the idle frame, so this is a set of four, not
	# a replacement for the two.
	for e in [["s", "facing the camera"], ["n", "walking away"]]:
		for foot in [["a", "LEFT"], ["b", "RIGHT"]]:
			_add("iso/hero_%s_%s.png" % [e[0], foot[0]], "128x192",
				("The player %s, mid-stride with her %s leg leading. Same character, same cloak, same colours and the same height as `hero_%s.png` — only the legs and the swing of the cloak move. Her feet must still be the lowest painted pixel: this pose is anchored exactly as the standing one is, and a stride drawn with a raised foot at the bottom of the canvas walks along a floor it is sunk into." % [e[1], foot[1], e[0]]))
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

	_section("Tier 8c — the creature on the tile",
		"One figure per enemy archetype, so the thing you walk toward is the thing you meet.",
		Kind.PAINT,
		"A small figure seen from the ISOMETRIC CAMERA THIS GAME ACTUALLY USES, which is not a head-on view. The floor tile is 116x58 - exactly 2:1 - so the camera looks DOWN at the floor from about 27 degrees above it. Draw the figure from that height: you see the top of its head and its shoulders, its feet are further down the frame than a head-on view would put them, and the ground it stands on would read as a flattened diamond rather than a line. It is also TURNED: the four walking directions all run diagonally across the screen, so the figure faces a DIAGONAL, three-quarter, never straight out of the frame. IT FACES DOWN AND TO THE LEFT - toward the camera and to the viewer's left, at 45 degrees, so the viewer sees the front of it and its left-hand side at once. Standing on nothing, on a flat even field for the matte: the feet must be the lowest painted pixel and there must be no ground, no shadow, no plinth and no scenery under it. Mid-value and lit from above and in front, clearly lighter than the floor across most of the body, with real interior: cloth, metal, skin, a face.",
        "BOTH facings are painted, and the `_s` files are no longer cut from the combat plates. Deriving them made the floor figure IDENTICAL to the arena figure, which is what fixed the mismatch (D198) — but a combat plate is framed head-on into the corridor at eye level, and pasting that onto a floor the camera looks down at from 27 degrees is a standee, not a creature standing there. The match is kept by DESIGN instead: draw each one against its `enemies/<id>.png` — same creature, same colours, same proportions, same silhouette — turned onto the diagonals above. `_s` walks down-left toward the camera; `_n` is that same creature walking up-right, seen from behind and above. Install: `godot --headless --script tools/install_sheet.gd -- iso_foes <sheet.png> --key --only=<ids>`")
	for aid in PixelArt.archetype_ids():
		var ae := load("res://resources/enemies/%s.tres" % aid) as EnemyData
		var nm: String = ae.name if ae != null else String(aid)
		_add("iso/foe/%s_s.png" % aid, "128x192",
			"**%s**, walking down-left toward the camera. The same creature as `enemies/%s.png`, turned onto the diagonal." % [nm, aid])
		_add("iso/foe/%s_n.png" % aid, "128x192",
			"**%s**, walking up-right away from the camera, seen from behind and above." % [nm, aid])

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
	# ...and separately, how much of the game is still UNPAINTED. The two differ, and
	# once they did the sheet started lying: with every file present it still opened
	# "0 files can be generated, the rest of the list cannot", which reads as art
	# outstanding that a generator is no use for. There was no rest. A sheet that
	# misreports its own state is the failure it exists to prevent (D101).
	var absent := 0
	for r in _rows:
		if not bool(r[3]):
			absent += 1
	print("<!-- GENERATED by tools/art_manifest.gd — do not edit by hand.")
	print("     Regenerate: tools/art_docs.sh — writes BOTH; a bare > captures Godot's banner. -->")
	print("")
	print("# ART_PROMPTS.md — how to ask for the missing art")
	print("")
	print("Generated from the same catalogues as [ART_ASSETS.md](ART_ASSETS.md), for the")
	print("same reason: a hand-kept prompt sheet goes stale, and a prompt naming an enemy")
	print("the game no longer has produces a painting with nowhere to go. The *why* is")
	print("[ART.md](ART.md); that file is the shopping list; this one is the wording.")
	print("")
	if absent == 0 and todo == 0:
		print("**Nothing is outstanding.** Every file the game looks for is present, so there is")
		print("nothing here to ask a generator for. The sections below are kept for the next")
		print("thing added to a catalogue, which will appear in them the moment it is.")
	elif todo == 0:
		print("**None of the %d missing files can be generated**, and the sections below say why" % absent)
		print("— computed kits, animations and licensed downloads. The expensive mistake is not")
		print("a bad painting, it is a good painting of a thing that had to be computed.")
	else:
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
		# "RE-ROLL" only when it IS one. A partial sheet is usually a re-roll, and the
		# first version of this line said so unconditionally — then the gear was added
		# to a set whose other twenty-one were already painted, and the sheet asked an
		# artist to re-roll a file that had never been drawn (D133).
		var what := "a RE-ROLL of" if rows.is_empty() else "%d new and %d re-rolled of" % [
			rows.size(), redone.size()] if not redone.is_empty() else "NEW —"
		print("**Generate these as ONE image, not %d.** A %dx%d grid, cells in the order of the table below, left to right then top to bottom, flat even background, nothing touching a cell edge. This is %s %d of this tier's %d files: the rest are already installed and are the reference, so match the set on disk for weight, fill and how much of its cell the shape uses. Install: `godot --headless --script tools/install_sheet.gd -- %s <sheet.png> --only=%s`" % [
			partial.size(), pc, pr, what, partial.size(), count - blocked.size(),
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
	print("     Regenerate: tools/art_docs.sh — writes BOTH; a bare > captures Godot's banner. -->")
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
