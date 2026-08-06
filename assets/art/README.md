# Painted art

Full-bleed illustrations, as opposed to the CC0 pixel tilesets in `assets/pixel/`.

These are **generated images, not Kenney CC0 assets**, and are not covered by the
licence files under `assets/pixel/` and `assets/audio/`.

The one exception is `fonts/`, which is the only thing under here that was
downloaded rather than made: two SIL Open Font License faces, each shipping the
upstream `OFL.txt` verbatim beside it. See `fonts/PROVENANCE.txt`.

| file                     | used by                        | origin                       |
|--------------------------|--------------------------------|------------------------------|
| main_menu.png            | scenes/MainMenu                | generated — re-rolled twice since D114 flagged it off-style: D126 for the foreground, D134 for the green |
| bg_&lt;dungeon_id&gt;.png      | the fight in that dungeon (12) | generated (Gemini 2.5 Flash) |
| bg_shop.png              | scenes/Shop                    | generated (Leonardo)         |
| bg_rest.png              | the rest overlay, RunFlow      | generated (Leonardo)         |
| bg_event.png             | scenes/Encounter               | generated (Leonardo)         |
| bg_treasure.png          | scenes/Encounter, chests       | generated (Leonardo)         |
| bg_victory.png           | scenes/Victory                 | generated (Leonardo)         |
| bg_defeat.png            | scenes/Defeat                  | generated (Leonardo)         |
| bg_zone_&lt;zone_id&gt;.png     | scenes/ZoneView (5)            | generated (Leonardo)         |
| enemies/&lt;archetype_id&gt;.png | PixelArt.enemy_art() (35)    | COMPUTED — gen_enemy_art.gd  |
| iso/*.png                | scripts/iso_run.gd (33)        | COMPUTED — see iso/README.md |
| relics/&lt;relic_id&gt;.png    | the relics screen (30)         | to come — cutouts            |
| powers/&lt;power_id&gt;.png    | the power button (10)          | to come — cutouts            |
| ui/frame_button*.png     | every button, via UITheme      | COMPUTED — see below         |
| ui/frame_card*.png       | every card, via Icons          | COMPUTED — see below         |
| ui/checkbox_*, dropdown_arrow, slider_grabber, scrollbar_grabber | the theme's loose controls (5) | generated — install_chrome.gd |
| cards/&lt;family&gt;.png       | 12 families, 100 cards         | to come — cutouts            |
| ui_button.png            | fallback if `ui/` is empty     | generated                    |
| ui_panel.png             | PanelContainer fallback        | generated                    |
| fonts/body.ttf           | the Theme default, via UITheme | DOWNLOADED — OFL, see fonts/PROVENANCE.txt |
| fonts/display.ttf        | headings and card names        | ″                            |

**Two generators is two dialects.** The backdrops above came from Gemini and Leonardo
and it is visible in a contact sheet. Everything from here on goes through ONE tool,
with `bg_crypt.png` attached to every request as the style reference — that image
conditioning does more for coherence than any wording. The wording itself is generated:
`ART_PROMPTS.md`, from `tools/art_manifest.gd -- --prompts`.

**And one generator is not one dialect.** `main_menu.jpg` came off the same Gemini as
the twelve dungeons and matches none of them: flat vector silhouettes, no ink outline
anywhere, a ninth the outline density of the rooms it shipped beside. Which is the
argument for the style reference rather than against picking one tool — the tool was
already the same, only the wording differed, and the wording is what drifted (D114).

Rendered with LINEAR filtering — the project sets NEAREST globally for pixel art
(`project.godot`), which turns smooth illustration into jagged edges.

## Installing a new backdrop

Do not drop the generated file in by hand. The filename is the wiring, and the
installers also strip the letterbox and crop to 16:9 rather than squashing:

    godot --headless --script tools/install_backdrops.gd -- <src_dir>        # dungeons
    godot --headless --script tools/install_scene_backdrops.gd -- <src_dir>  # shop/rest/event/... + main_menu
    godot --headless --script tools/strip_sparkle.gd                         # see below
    godot --headless --import

The title art rides the scene installer, under the source name `main_menu` or `title`.
It is the only backdrop with no `bg_` prefix and the only one that is currently a .jpg,
because it predates these tools; installing writes `main_menu.png` and deletes the
superseded .jpg. Nothing spells that extension — `PixelArt.title_art_path()` resolves
it, PNG first, so the swap lands in one step instead of leaving a blank title screen.

## Installing cutouts — enemies, relics, powers, card art

Everything that is not a backdrop is a subject on transparent at a fixed canvas size,
and no image tool produces that; it produces a painting of a monster in a room. Ask
for the subject on a **flat, even field** of one colour and let the installer do the
rest — matte, despeckle, trim, scale, anchor:

    godot --headless --script tools/install_cutouts.gd -- enemies /tmp/staging
    godot --headless --script tools/install_cutouts.gd -- relics  /tmp/staging
    godot --headless --import

It matches source names against both the id and the display name, so
`The Grave-Sexton (2).png` lands on `grave_sexton.png`, and it **refuses** a source
whose border is not flat rather than cutting a hole in a painted wall. Anything it
could not place is listed at the end: a file nobody could match is art that was made
and will never load, which is the failure this whole tool exists to make loud.

**Enemies are anchored to the bottom, and that is not cosmetic.** `combat.gd` puts
every enemy's feet on `PixelArt.STAND_LINE`, so transparent padding under the subject
is that enemy hovering, in every fight, forever. The installer trims to the alpha
bounding box and puts the lowest opaque pixel on the canvas's last row.

## Icon sets arrive as one gridded sheet

For the icon tiers the requirement is not that each icon is good, it is that the SET is
mutually distinguishable — seven intent telegraphs that all read as "angry shape" have
failed even if each is handsome. Asked for one at a time, each request is blind to the
other six. Asked for as one image, the model sees the whole set while drawing it:

    godot --headless --script tools/install_sheet.gd -- symbols <sheet.png>
    godot --headless --script tools/install_sheet.gd -- intents|powers <sheet.png>
    godot --headless --import

Cells are matted and trimmed individually, so an icon that is off-centre in its cell
still lands centred in its file. A bounding box that touches its cell edge is reported
loudly: it means the generator ignored the grid and that icon is a crop.

**The mapping is positional, and that is the cost.** It is the same hazard as the
deleted `PixelArt.enemy_sprite()`, which handed CC0 sprites to archetypes by sort order
until D89 killed it. The difference is that the order is not implicit — `ART_PROMPTS.md`
prints it INTO the
prompt from the same tables `install_sheet.gd` reads, and the mapping is printed on
every run. Check it against the sheet before committing: a set installed one cell out
is 21 correct icons on 21 wrong meanings.

**The 21 status symbols take a different route through the same tool.** They are
specced monochrome-tintable, so their alpha comes from **luminance** rather than from
the flood-fill matte, and their colour is thrown away for flat white. Luminance is the
better matte here and not merely the cheaper one: a flood fill resolves every pixel to
in-or-out, which turns an anti-aliased glyph edge into a staircase at the 3x the canvas
is scaled to on a 4K display. Polarity is read off the border, so a sheet that comes
back dark-on-light installs the same as light-on-dark.

## The generator signs its work

The image tool stamps a small four-point sparkle into the bottom-right corner. It is
on all twelve dungeon backdrops. `tools/strip_sparkle.gd` finds it by intersecting
"brighter than its surroundings" across every image that shares the 1280×720 frame —
a brazier is bright in one file and absent from the next, the stamp is in all of them
at the same pixel — and fills it with a harmonic (Laplace) patch. Run it after
installing any new dungeon backdrop, and check the result: `--dry` writes a mask
preview instead of touching anything.

**Cutouts do not need it**, and not by luck: the stamp sits in a corner, the corner is
background, and the matte takes it. What it leaves behind is a small opaque island
away from the subject — which would drag the trim box out to the corner and shrink the
monster to fit beside its own watermark — so `install_cutouts.gd` drops opaque
components under 8% of the largest, and prints how many went.

The scene backdrops escape it for free, because they arrive as 2.33:1 panoramas and
the 16:9 crop takes the corner with it. The zone shots do not — one of the five has
no letterbox and keeps its corner — so for a batch that has not been installed yet,
strip it in the source frame FIRST, where every image in the batch still agrees on
where the stamp is:

    cp ~/Downloads/*.png /tmp/staging/
    godot --headless --script tools/strip_sparkle.gd -- /tmp/staging
    godot --headless --script tools/install_scene_backdrops.gd -- /tmp/staging

Never point it at `~/Downloads` directly; it rewrites in place.

**One image on its own needs the box given by hand**, because the intersection is what
finds the stamp and one frame has nothing to intersect with. `main_menu.png` was that
case: it predates the installers, so it sat through every batch this tool cleaned and
kept its sparkle on the rock ledge until D163. The box is only the *search area* — the
mask is still measured inside it, so it hugs the star rather than being the rectangle
that was typed:

    godot --headless --script tools/strip_sparkle.gd -- \
        --file=res://assets/art/main_menu.png --box=1130,565,90,90 --dry

Look at the preview before dropping `--dry`. With one frame, nothing but the eye stands
between that box and a brazier.

## Zone art has its own prefix, and it matters

`foundry` is a dungeon id AND (as `foundry_zone`) a zone. The generator names files
after what is in them, so the zone establishing shot arrived as `foundry.png` —
installed without a prefix it would have replaced the Foundry's fight arena with a
landscape, silently. Zone art is `bg_zone_<zone_id>.png`, the installer maps source
names to ids explicitly, and `tests/test_art.gd` asserts the namespaces never collide.

## The button frames are generated, not drawn

`assets/art/ui/frame_button*.png` and `ui/frame_card*.png` come out of
`tools/gen_ui_kit.gd`, not out of an image tool. A nine-slice has to survive being stretched from 96px to 1240px, and that
requires the top/bottom strips to be identical along X, the left/right strips identical
along Y, and the middle a single flat colour. Painted art breaks all three and smears
(D83). Re-run after editing the palette in that file:

    godot --headless --script tools/gen_ui_kit.gd -- stone   # or: parchment
    godot --headless --import

The nine-slice MARGINS live in the code that uses them — `UITheme.KIT_SLICE` and
`Icons.CARD_SLICE` — and must match `gen_ui_kit.gd`'s `BORDER`/`CARD_BORDER`. Slicing
a 14px border at 48 eats the flat middle and stretches the carved edge instead, which
is what ART_ASSETS' specced 40/40/48/56 would have done to a 150x132 card.
