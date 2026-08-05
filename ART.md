# ART.md — the art brief for The Owing

What the game looks like now, what it should look like, and the **list of assets
that gets it there**. Companion to [AGENTS.md](AGENTS.md) (the concept) and
[DESIGN.md](DESIGN.md) (the decision log). Art decisions that stick get written up
as a `D##` entry there like everything else.

Every asset below names the **code hook** it plugs into, so nothing on this list is
a drawing that then needs somebody to figure out where it goes.

Captures used to write this were made with `tools/screenshots.gd` — regenerate them
before and after any art pass (§7). Nothing here was inferred from source code alone;
§6 says what each of the 16 captures shows.

---

## 1. The diagnosis: five visual languages, fighting

*Written against the 16-capture pass. Three things named here have since been fixed and
are marked in place: the dungeon backdrops were all installed (D73), the 41 Kenney enemy
sprites were replaced by 35 generated plates (D89), and the frame kit became computed
rather than painted (D83). The diagnosis is kept rather than deleted because the
reasoning is what the rest of the file is built on.*

*It also undercounted, and the miscount survived twelve decisions because it was in the
column nobody re-reads: `main_menu.jpg` was filed under "painted, inked" and it is not
inked at all, so the dialects were five and the table said four (D114).*

The game is not short of art. It is short of art that **agrees**. Right now five
screens' worth of assets speak five unrelated dialects — four, as first counted:

| language | assets | verdict |
|---|---|---|
| **Painted, inked illustration** | all 12 dungeon backdrops | **This is the game.** Keep. |
| **Flat vector illustration** | `main_menu.jpg` | *Was counted as inked here and it is not (D114) — no outline anywhere, a ninth the outline density of the rooms it shipped beside. On the re-roll list.* |
| **Kenney 16×16 pixel art** | 41 enemy sprites, 5 zone tiles, 1 card sheet | Off-style, and semantically arbitrary — *the 41 enemy sprites are gone (D89); the zone tiles and the card sheet remain* |
| **Hand-authored 16×16 mono glyphs** | 13 in `PixelArt.GLYPHS` | Off-style, too small to read as art |
| **A stretched illustration pretending to be a frame** | `ui_button.png`, `ui_panel.png` | Actively damaging — see below |

Three failures do most of the damage, and every one of them is visible in a capture:

**a) The frame kit is not a nine-slice, and the numbers say so.**
`assets/art/ui_button.png` is a 128×83 *painting* of torn parchment inside a stone
frame. With `BUTTON_SLICE = 22/22/19/21` that leaves an 84×43 centre, and the
arithmetic is brutal:

- **Horizontally:** a full-width button is 1248px. 44px goes to the fixed side
  borders, so the 84px centre is stretched to 1204px — a **14.3× stretch**. The
  ragged parchment edges and the lighting gradient across it become the horizontal
  purple-and-white smears visible on every wide button in the game.
- **Vertically:** `min_button_height()` is `19 + 21 + 10 = 50`, so a standard
  `UI.button(height=42)` renders at 50px — of which **40px is fixed border and 10px
  is parchment**. A 16px body font centred in that button overflows its own
  parchment band by 6px, which is why text sits *on* the carved border in every
  capture rather than inside it.
- **Small buttons are the worst case.** The `+` / `−` quantity buttons in
  `DeckBuilder.png` are roughly square at ~50px. With 44px of horizontal and 40px of
  vertical border there is essentially no interior left, and their labels are
  swallowed by the frame entirely — unreadable, not merely ugly.

`ui_panel.png` (384×250) has the same ragged-centre problem, plus a `38/19/49/57`
slice — four different values, i.e. a painting rather than a frame. A nine-slice
centre must be **low-frequency and tileable**, and its slice must be small relative
to the smallest control it dresses; these are neither.

**b) Half the screens have no backdrop at all.** Four of them build straight onto
the clear colour: `collection.gd`, `deck_builder.gd`, `encounter.gd`, `shop.gd`.
(Three more did — `deck_run` `dice_run` `map` — and went with their traversal models
in D94.) The shop and the event screen are flat near-black rectangles with text on
them, and they are two of the screens the player sees most.
*All four are fixed: `shop.gd` and `encounter.gd` call `UI.scene_backdrop()`, and
`collection.gd` and `deck_builder.gd` were moved inside `UI.screen()` in D95 — which is
where the backdrop is installed, and the reason they were the last two flat-black
screens in the game.*

**c) The things the game is *about* have no art.** No player character exists on
screen anywhere. Enemies were 16×16 tiles handed to `Button.icon` and were not
visibly rendered at all in the combat capture — *fixed in D89; 35 generated plates now
stand on the floor line*. All 30 relics render as text rows —
`relics_screen.gd` makes no icon call whatsoever. All 20 events are a title, two
lines and three buttons over 400px of black. There is no custom font: the whole
game runs on Godot's built-in default. *Fixed: Fira Sans is the Theme default and
Cinzel sets the headings and the card names — see `assets/art/fonts/PROVENANCE.txt`.*

### What is already right, and must not be thrown away

- **`bg_crypt.png` and `bg_warrens.png` are good, and they agree with each other**
  — same one-point symmetrical composition, same arch-and-brazier vocabulary, same
  cool-stone-plus-saturated-light lighting model. They are the style bible.
- The **contrast discipline** in `UI.illustration()` and `PixelArt.battle_backdrop()`
  (D39): scrims held flat across the text bands, measured worst-pixel contrast, a
  test that fails under 4.5:1. New art inherits this, it does not get to opt out.
- **NEAREST is global** (`project.godot`) and painted art overrides to LINEAR
  per-node. Any new painted asset must do the same or it aliases.

---

## 2. The direction: one style, stated plainly

**Painted dark-fantasy storybook.** Inked silhouettes, flat-to-soft painted
interiors, cool desaturated stone, one saturated light source per scene, deep
shadow. Read at a glance from a 1280×720 window; readable behind text.

Taken from what already works, so it needs no leap of faith:

- **Line.** Every foreground object carries a dark ink outline, weight roughly
  2–3px at 1280×720. This is what lets a painted enemy read against a painted room.
  `bg_warrens.png` has heavier ink than `bg_crypt.png` — **crypt's weight is the
  target**; warrens is the outlier.
- **Composition.** Symmetrical, one-point, centre vanishing point, foreground
  framing elements at the left and right thirds. Every dungeon backdrop reuses this
  skeleton so twelve rooms feel like one dungeon.
- **Value.** Backdrops sit at 20–35% luminance so UI text survives on them. The
  brightest thing in any scene is its light source, and it lives *off* the text
  bands (`BATTLE_SCRIM_BAND`, top and bottom 34%).
- **Palette.** Stone violet-grey base; one saturated accent per zone as the light
  (Barrows cyan, Foundry orange, Rot acid-green, Deeps deep-blue, Beyond magenta);
  gold `#F0B840` reserved for gold and energy; red for damage; green for poison.
  Codify these in `Icons`/`Balance` rather than restating them per screen — a
  duplicated constant has cost this project three bugs already.
- **Scale.** Author every UI asset at **2×** and downsample. There is no UI scale
  setting — the interface is laid out at a fixed 1280×720 and `UITheme.UI_SCALE` is a
  constant `1.0` (D65) — but the engine's `canvas_items` stretch scales the whole canvas
  to the window, so on a 1440p display every asset draws at 2× and on 4K at 3×. Nothing
  reflows; it is a clean scale-up, and it is why the source needs the headroom.

### Two rules that are non-negotiable

1. **Nine-slice centres are flat.** No gradient along the stretch axis, no ragged
   silhouette, no detail finer than ~4px. Detail belongs in the corners. If art
   must have a textured centre, it ships with
   `axis_stretch_horizontal = AXIS_STRETCH_MODE_TILE` and a genuinely tileable
   strip — measured for wrap error the way the zone tiles were.
2. **No baked-in text, ever.** `bg_warrens.png` has "THE WARRENS" painted into the
   sign above the door. Rename the dungeon, or translate the game, and the art
   lies. Signs stay blank; names come from `DungeonData.name`.

---

## 3. The asset list

> **The file-by-file list lives in [ART_ASSETS.md](ART_ASSETS.md)**, with every
> filename, size and a brief taken from the content's own name and description, and a
> running count of what is present against what is wanted. **The wording to ask for
> it with lives in [ART_PROMPTS.md](ART_PROMPTS.md)**, which adds the shared style
> block, the per-tier framing rules, and — the part that matters most — which files
> must NOT be generated at all. Both are *generated*, by `tools/art_manifest.gd`, from
> the catalogues in `resources/`, so neither can fall out of step with the game the
> way a hand-typed list of 35 enemy names would:
>
> ```bash
> godot --headless --script tools/art_manifest.gd > ART_ASSETS.md
> godot --headless --script tools/art_manifest.gd -- --prompts > ART_PROMPTS.md
> ```
>
> **This section is the reasoning; those files are the shopping list and the wording.**
> Where any of them disagree on a count, the generated one is right — no total is
> restated here, deliberately (D34).

Two thirds are icons. Ordering below is by *visible improvement per hour*, not by
category:

| tier | what | files |
|---|---|---|
| 0 | frame kit + control chrome | 24 |
| 1 | combat readability (player, vitals, intents, symbols, VFX) | 43 |
| 2 | enemies | 35 — **done** |
| 3 | card illustrations | 12 |
| 4 | map and traversal | 0 — deleted with the models (D94/D111) |
| 5 | backdrops (5 zone + 6 scene; all 12 dungeons) | 23 — **done** |
| 6 | relics and powers | 40 |
| 7 | identity and shell | 6 |

**No total here is authoritative** and none is restated deliberately (D34) — the tiers
above are the *ordering*, and `ART_ASSETS.md` is generated and wins on any disagreement.
Its header line carries the wanted/present/missing counts; read them there.

Proposed layout — `assets/art/` grows subdirectories, `assets/pixel/` demotes to
fallback. Partly built: `enemies/`, `iso/` and `ui/` exist; the backdrops are still
flat in `assets/art/` (see the code note below) and the rest are unmade.

```
assets/art/
  bg/        1280x720 scene backdrops        (23 files — still flat in art/)
  enemies/   256/512 transparent             (35 — exists, full)
  iso/       the crawl's tiles and markers   (33 — exists, full; not on the list, generated)
  cards/     12 family illustrations         (12)
  relics/    128x128 objects                 (30)
  powers/    128x128 sigils                  (10)
  ui/        nine-slice kit, bars, icons     (~60 — exists, 16 in it)
  fx/        sprite sheets                   (6)
  fonts/     display + body                  (2)
```

> **One code note before drawing anything:** `PixelArt.BATTLE_ART_DIR` is
> `res://assets/art/` and resolves `bg_<dungeon_id>.png` flat in that directory.
> Moving backdrops into `bg/` is a one-line change there, but it *is* a change —
> make it deliberately, not by dropping files in a new folder and wondering why
> nothing loads.

---

### Tier 0 — The frame kit  ·  24 files  ·  fixes every screen at once

Highest leverage item in this document by a wide margin. One kit, and every screen
stops looking broken.

> **Superseded in part by D83.** The kit is **computed** by `tools/gen_ui_kit.gd`, not
> painted, and its real nine-slice margins live in `UITheme.KIT_SLICE` (12) and
> `Icons.CARD_SLICE`. The sizes and slices in the table below are the original spec and
> are kept for the reasoning; where they disagree with the code, the code is right —
> slicing a 12px border at 48 eats the flat middle and stretches the carved edge, which
> is the exact defect this tier exists to fix. `ART_ASSETS.md` has the live count of
> what is installed; do not read it off this page.

| file | size | 9-slice (l/r/t/b) | hook |
|---|---|---|---|
| `ui/frame_button.png` | 192×96 (2×) | 32/32/28/28 | `UITheme.BUTTON_ART` |
| `ui/frame_button_hover.png` | 192×96 | same | `style_button()` hover |
| `ui/frame_button_pressed.png` | 192×96 | same | `style_button()` pressed |
| `ui/frame_button_disabled.png` | 192×96 | same | `style_button()` disabled |
| `ui/frame_panel.png` | 256×256 | 64/64/64/64 | `UITheme.PANEL_ART` |
| `ui/frame_inset.png` | 128×128 | 32/32/32/32 | logs, lists, scroll wells — *new* |
| `ui/frame_tooltip.png` | 128×128 | 24/24/24/24 | tooltips — *new* |
| `ui/frame_card.png` | 320×448 | 40/40/48/56 | replaces `Icons.card_style()` StyleBoxFlat |
| `ui/frame_card_rarity_<0..4>.png` | 320×448 | same | 5 rarity treatments |
| `ui/divider.png` | 128×16 | tileable X | section rules — *new* |
| `ui/dropdown.png` + `_arrow.png` | 192×96, 32×32 | 32/32/28/28 | `OptionButton` — wired; arrow in, track wanted |
| `ui/slider_track.png` + `_grabber.png` | 128×24, 48×48 | tile X | `HSlider` — wired; grabber in, track wanted |
| `ui/scrollbar_track.png` + `_grabber.png` | 24×128, 24×48 | tile Y | `VScrollBar` — wired; thumb in, track wanted |
| `ui/checkbox_on.png` + `_off.png` | 64×64 | — | settings — wired, both in (D107) |

~~The theme styles **`Button` and `PanelContainer` only**. Every dropdown, slider,
scrollbar and checkbox in the game is default Godot chrome sitting next to painted
buttons.~~ **Done (D105/D107).** `UITheme` now wires `OptionButton`, `HSlider`,
`VScrollBar` and `CheckBox`, each one switching on the moment its file exists and
falling back to Godot's chrome until then. The four still absent are the three tracks
(`dropdown`, `slider_track`, `scrollbar_track`) and `frame_panel`/`frame_inset`/
`frame_tooltip` — so what is left in this tier is the *housings*, not the wiring.

Spec, restated because it is the thing that went wrong:

- **The centre must be flat.** No lengthwise gradient, no ragged silhouette, no
  detail finer than ~4px. It gets stretched 14× — draw the wear and the carved edge
  into the margins.
- **Keep the border thin relative to the button.** Today 40px of border lives inside
  a 50px button. Authored at 2×, the button frame's top+bottom slice should total no
  more than ~40% of the shortest button it has to dress. A 28/28 slice on a 96px-tall
  2× texture is 28px of border at 1:1, leaving real room for text.
- Corners must be exactly the slice size, and symmetric — the current panel slice is
  `38/19/49/57`, i.e. four different values, which is a painting, not a frame.
- **Ship a small variant.** Square icon buttons (`+` / `−` in the deck builder) cannot
  wear a frame designed for a 1248px bar. `ui/frame_button_small.png` at 96×96 with a
  12/12/12/12 slice. **Done** — `UITheme.style_button()` takes the choice as an argument
  rather than deriving it from `b.text.length()`, because almost every call site styles
  a button before setting its text (D83).

---

### Tier 1 — Combat readability  ·  47 files  ·  the screen that matters

Combat is where the game is played and it is currently the least drawn screen in
it: a text status line, two parchment rectangles for enemies, 250px of empty
middle, and five flat card shapes.

**The player (0 files) — resolved, and the answer is nobody.** These four files were
specced (`hero_idle`, `hero_idle_b`, `hero_hurt`, `hero_portrait`, 512×640) on the
assumption of a side-on arena. That is no longer the layout.

**The fight is framed head-on into the corridor the backdrop paints, and the player
is not drawn.** The room belongs to the enemies; the frame belongs to you. It suits
the art that already exists — all three painted backdrops are symmetric one-point
corridors, and a side-on arena fights that perspective rather than using it — and it
deletes work rather than deferring it: no facing to match, no idle/hurt set to keep
consistent with 35 enemies, no scale relationship between hero and monster to hold.

It also makes the feedback already in `combat.gd` correct rather than provisional:
with no body on screen, an incoming hit reads as a screen flash and a jolt toward the
camera, which is what it now does.

What replaces the hero is the HUD — vitals in the top band (next section) — and the
measured standing line the enemies share:

| decision | value | where |
|---|---|---|
| painted horizon | **68% of frame** — where the back wall meets the floor | `PixelArt.HORIZON_LINE` |
| standing line | **72% of frame** — where a combatant's feet go | `PixelArt.STAND_LINE` |
| enemy size | 38% of frame height, ×1.14 elite, ×1.34 boss | `combat.gd:TIER_SIZE` |
| slot spread | 1-3 across, flanks at 0.88 scale for depth | `combat.gd:_place_slots()` |
| art lookup | `assets/art/enemies/<archetype_id>.png` | `PixelArt.enemy_art()` |

**Those first two are different numbers on purpose**, and collapsing them was the
original error: a figure standing exactly on the wall/floor junction is at the far end
of the corridor rather than in the fight. The horizon is a property of the backdrop
and the standing line is a property of the stage, and the stage stands its enemies
*in front of* the junction.

`tests/test_art.gd` measures every painted backdrop against `HORIZON_LINE` and fails
when one lands more than 10 points off, because a backdrop that puts its floor
elsewhere does not look broken on its own — it makes that dungeon's enemies hover.

**Vitals (7 files)** — HP, Block and Energy are all *text* today
(`combat.gd:_refresh()` formats one `%s HP %d/%d ... Energy %d/%d` string).

| file | size | hook |
|---|---|---|
| `ui/bar_frame.png` | 256×48, 9-slice | new HP/Block widget |
| `ui/bar_hp_fill.png` | 32×48, tile X | ″ |
| `ui/bar_hp_loss.png` | 32×48, tile X | the chunk about to be lost — telegraphs `enemy_intent` |
| `ui/bar_block_fill.png` | 32×48, tile X | ″ |
| `ui/energy_orb_full.png` | 128×128 | replaces `Energy 3/3` |
| `ui/energy_orb_empty.png` | 128×128 | ″ |
| `ui/orb_glow.png` | 192×192, additive | spend/gain flash |

**Intent telegraphs (7 files, 96×96)** — `eng.intent_text(i)` currently renders as
the string `"hit 5"`. Telegraphs are the core read of the whole combat system and
they are plain text.

`intent_attack`, `intent_attack_multi`, `intent_block`, `intent_buff`,
`intent_debuff`, `intent_poison`, `intent_unknown`
→ hook: `Icons.for_intent()` (new), consumed in `combat.gd:_refresh()`.

**Status icons (21 files, 64×64)** — painted replacements for `PixelArt.GLYPHS`,
which is 13 monochrome bitmaps covering 21 needed meanings, so several currently
double up (`Icons.MAP` maps `relic` *and* `legendary` *and* `gold` to one coin).

`attack` `block` `pierce` `poison` `thorns` `vulnerable` `weak` `strength`
`dexterity` `retain` `exhaust` `hp` `heal` `energy` `gold` `card` `dice` `skull`
`campfire` `rope` `chest`
→ hook: `Icons.tex()` / `Icons.MAP`. Keep them **monochrome-tintable** — callers
tint by rarity and fade for spent states, and that behaviour is load-bearing.

**Target + selection (2 files)**

| `ui/target_ring.png` | 256×256 | replaces the `"▶ "` text prefix on the targeted enemy |
| `ui/card_glow.png` | 320×448, additive | playable-vs-unaffordable card, currently unmarked |

**VFX (6 sprite sheets, 8 frames each, 256×256 per frame)** — the game has **no
combat feedback animation at all**. A card is played and text changes.

`fx/slash.png`, `fx/impact.png`, `fx/block_up.png`, `fx/poison_cloud.png`,
`fx/heal.png`, `fx/death_dissolve.png`
→ hook: new one-shot `AnimatedSprite2D` spawner called from
`combat.gd:_on_card_pressed()`, keyed off the same effect branch that already picks
the sound. The audio switch there is the exact shape the VFX switch wants.

---

### Tier 2 — Enemies  ·  35 files  ·  **done (D89)**

35 archetypes and 12 named bosses *used to* share 41 unlabelled 16×16 Kenney tiles,
assigned **by sorted position** with a 12-entry override table to stop bosses
inheriting trash-mob faces. All 35 now have a generated plate at
`assets/art/enemies/<archetype_id>.png`, shaped from the archetype's own fight data;
`PixelArt.OVERRIDES`, `PixelArt.enemy_sprite()` and the CC0 pool behind them are gone.
The rest of this section is the brief they were generated against, and still governs
any replacement — the plates are markers, and painted figures remain the upgrade path.

| set | count | size | path |
|---|---|---|---|
| Non-boss archetypes | 23 | 256×256, transparent | `enemies/<archetype_id>.png` |
| Named bosses | 12 | 512×512, transparent | `enemies/<archetype_id>.png` |

Optional +70 files for a 2-frame idle and a hurt frame (`_idle_b`, `_hurt`).

Draw them **facing the viewer**, lit from above-front, standing on nothing — no baked
ground shadow, the stage draws a contact mark. This is a consequence of the head-on
framing above and it is the opposite of what this section said while the arena was
still specced side-on: a left-facing enemy in a symmetrical one-point corridor is a
monster looking at a wall.

Two placement rules that are invisible in the file and obvious in the game:

- **Feet flush with the bottom edge of the canvas, no bottom padding.** Every enemy is
  placed with its feet on `STAND_LINE`, so padding under the subject is that enemy
  hovering by exactly that much, in every fight. `tools/install_cutouts.gd` enforces
  it by trimming to the alpha bounding box and anchoring to the bottom row.
- **Weight the silhouette low and dark.** The floor is the brightest band in every
  painted backdrop, so a pale-footed enemy dissolves into the thing it is standing on.

Naming on `archetype_id` deleted real complexity: `PixelArt.OVERRIDES` and the
whole positional-assignment-that-skips-pinned-sprites dance in
`PixelArt.enemy_sprite()` both went, and adding a 36th enemy no longer silently
reshuffles every other enemy's face — it gets its own plate on the next generator run.

Boss list, for reference: `grave_sexton` `brood_mother` `marrow_abbot`
`bellows_master` `warden` `cinder_knight` `mycelial_lord` `the_gardener`
`deep_warden` `last_vendor` `false_step` `abyss_horror`.

---

### Tier 3 — Cards  ·  12 files now, unique art later

100 cards currently draw their illustration from `assets/pixel/cards/sheet.png` —
Kenney's 1-Bit pack, a monochrome sheet of tiny symbols, **letters and dither
patterns**. `PixelArt.CARD_TILES` picks 140 of them by index and assigns by sorted
position. Many are literally alphabet glyphs. They render at 0.22 alpha behind the
card text, where they read as noise.

Recommended: **not** 100 unique paintings up front.

| step | count | size | note |
|---|---|---|---|
| Family illustrations | 12 | 320×240 | one per effect family, shared by every card in it |
| Card back | 1 | 320×448 | in Tier 0. Nothing loads it since D94 took the deck traversal — leave it until something draws a face-down card |
| Rarity frames | 5 | — | in Tier 0 |
| Unique card art | later | 320×240 | `cards/<card_id>.png`, checked before the family file |

Twelve, not twenty-four: the 100 cards actually fall into twelve effect families, and
they are lopsided — 28 attack, 19 block, 12 poison, 8 thorns, then a long tail of
2–5. Splitting each family per zone would mean drawing 60 variants for the tail to
serve three cards each. `ART_ASSETS.md` lists which cards land in each family, so the
big four are the ones worth a second variant if any are.

→ hook: `PixelArt.card_art(card_id)`, resolving `cards/<card_id>.png` first and
falling back to `cards/family_<family>.png`. `CARD_ART_OVERRIDES` becomes the
exception table it was always meant to be.

**Blocker (code):** the illustration currently sits full-rect behind the text at
0.22 alpha. Real art wants its own band — top ~40% of the card face, text below it,
per `UI.card_button()`'s existing hand-placed band layout.

---

### Tier 4 — Map and traversal  ·  0 files

**Nothing left to draw here.** This tier asked for 26 files across three traversal
models — 11 for the graph map, 14 for the dice board, one reveal frame for the deck
draw. All three models were deleted in D94 after D88 moved every dungeon onto the
isometric crawl. The crawl's own markers are generated by `tools/gen_iso_markers.gd`
into `assets/art/iso/`, so they are not a shopping-list item and never were.

`tools/art_manifest.gd` went on briefing all 26 for another eleven decisions, because
deleting a feature does not touch the tool that advertises it — removed in D111, which
is what took the manifest from 209 files wanted to 183. The tier is kept as a heading
rather than removed so the numbering below still matches the captures.

---

### Tier 5 — Backdrops  ·  0 to draw of 23 at 1280×720  ·  **done**

| set | count | missing |
|---|---|---|
| Dungeon battle backdrops | 12 | **0 — done (D73)** |
| Zone backdrops (overworld / zone view) | 5 | **0 — done (D83d)** |
| Scene backdrops | 6 | **0 — done (D83b)** — shop, rest, event, treasure, victory, defeat |

→ hooks: `PixelArt.battle_art()` for dungeons, `PixelArt.zone_art()` for zones,
`PixelArt.scene_art()` via `UI.scene_backdrop()` for the rest.

The one thing left in this tier is a *quality* complaint rather than a gap: the Chest,
Victory and Defeat plates are visibly a flatter tier than the other twenty — heavy
uniform ink, unrendered surfaces — and Victory is the screen at the end of every
successful run (REVIEW.md §3).

Author to the D39/`BATTLE_SCRIM` contract: 20–35% luminance, light source away from
the top and bottom 34% bands, and the existing contrast tests must stay green.

Also: **strip the baked "THE WARRENS" sign** from `bg_warrens.png`, and bring its
ink weight down to match `bg_crypt.png`.

---

### Tier 6 — Relics and powers  ·  40 files at 128×128

- **30 relic icons** → `relics/<relic_id>.png`. `relics_screen.gd` currently
  contains **no icon call at all**; 30 relics are text rows. Needs a new
  `Icons.relic()` plus the render call.
- **10 power icons** → `powers/<power_id>.png`. Powers borrow
  `Icons.for_card()`, i.e. one of 13 monochrome glyphs, so several powers show the
  same symbol.

Painted objects on transparent, lit from upper-left, ink-outlined, readable at
48px — they are shown small.

---

### Tier 7 — Identity and shell  ·  6 files (two of them downloads)

| file | size | note |
|---|---|---|
| `fonts/display.ttf` | — | **done** — Cinzel Bold (OFL); `UITheme.style_title` and card names |
| `fonts/body.ttf` | — | **done** — Fira Sans Regular (OFL); the `Theme` default |
| `ui/logo.png` | 1600×480 | the title is a plain `Label` reading `"THE OWING"`, set into the painted cartouche |
| `icon/icon_*.png` (6) | 48×48 grid | **done (D180)** — *generated*, not painted: `tools/gen_icon.gd`. A gold coin with a skull struck into it and a bite out of its rim, authored on a 48-cell grid and scaled by whole numbers to 192 / 384 / 432 — the two Android adaptive layers, the themed layer, the legacy launcher icon and the project icon. Not 256×256, because 256 ÷ 48 is 5.33 |
| `ui/boot_splash.png` | 1280×720 | none configured |

The font was the cheapest large win on this list and it is spent: two files and a
`Theme` change, and every screen in the game changed character. Body face chosen at
12px rather than at 22px, because that is where card rules text actually lands once
`UI.fit_label` has shrunk it; display face chosen in BOLD for the same reason, since
a card name in a crowded fan goes down to 7px and a hairline serif does not survive
it. Three headings in `combat.gd` still carry the body face and want `style_title`.

---

## 4. Code work the art needs

Assets that land on top of these problems will not look better. None of it is large.

1. ~~**Backdrops on the four bare screens** — `collection` `deck_builder` `encounter`
   `shop`.~~ **Done.** `shop` and `encounter` call `UI.scene_backdrop()`; `collection`
   and `deck_builder` were the last two hand-rolling their own `MarginContainer` + `VBox`
   and were moved inside `UI.screen()` in D95. The lesson outlived the fix: a helper
   whose whole value is uniformity needs a check that everyone is inside it, because the
   boilerplate it replaces is by construction easy to write again by accident. (It was
   seven; three were the traversal views deleted in D94.)
2. **Give text somewhere to sit.** `UITheme._frame()` sets `content_margin` to `10`
   vertically against a `19/21` texture slice, and `min_button_height()` is only
   `t + b + 10`. The result is a 50px button with 40px of border and a 10px parchment
   band — a 16px font cannot fit. Content margins must be **≥ the slice**, which in
   turn means `min_button_height()` has to rise (or the new art's slice has to fall).
3. **Enemies need a composed panel**, not a `Button` with `icon` + multi-line
   `text`. The 16×16 sprite is not visibly rendered in `Combat.png` at all. Sprite,
   name, HP bar and intent icon each want their own placed region — the same
   hand-placed approach `UI.card_button()` already uses, and for the same reason.
4. ~~**Style every control, not just buttons.**~~ **Done (D105/D107).** `UITheme` now
   wires `OptionButton`, `HSlider`, `VScrollBar` and `CheckBox` alongside `Button` and
   `PanelContainer`, each switching on when its file lands. What remains is art, not
   code: the three track housings. (The three run views that built unstyled
   "Collection" buttons were deleted in D94; the general rule outlived them, so audit
   new screens for it.)
5. ~~**The dice board collapses to zero height.**~~ **Done (D57).** One line —
   `vertical_scroll_mode = SCROLL_MODE_DISABLED`, since the track scrolls sideways and
   a `ScrollContainer` only contributes its content's minimum size on axes it cannot
   scroll. `PlayableTest` now asserts the general case: no scroll area may be squeezed
   to zero on an axis whose content needs pixels.
6. **Flip the texture filter default.** `project.godot` sets NEAREST globally and
   painted art overrides per-node. Once painted art is the majority that is backwards
   — flip the default to LINEAR and mark the surviving pixel assets NEAREST.
7. **An art-coverage test**, per the D42 rule that half-added content must fail
   loudly: every archetype, card, relic, power and dungeon id has a file at its
   conventional path, or the suite goes red. Convention over an `@export var art`
   field — no `.tres` churn, and it keeps "add content = data file plus a catalogue
   line" true. **Partly done:** `tests/test_art.gd` fails on any archetype with no
   plate, and since D89 it *discovers* its subjects by walking `assets/` rather than
   checking a hand-written list of directories.

---

## 5. If you only do three things

1. ~~**Tier 0, the frame kit.**~~ **Mostly done (D83/D105/D107)** — computed rather
   than painted, 16 of 24 installed, every control wired. The three track housings and
   the panel/inset/tooltip frames are what is left.
2. ~~The nine missing dungeon backdrops.~~ **Done (D73), and all 23 backdrops with
   them (D83b/D83d)**, and the screens that were bypassing `UI.screen()` were brought
   inside it (D95). This item is closed.
3. ~~**A font, and the enemies.**~~ **Done.** The 35 enemy plates landed in D89 and the
   two faces are installed: Fira Sans as the `Theme` default, Cinzel Bold on headings
   and card names. This item is closed. What is now the largest visible win left is the
   **twelve card family illustrations** — the card is the object the player looks at for
   most of the runtime and it is still a 16×16 tile magnified ten times.

---

## 6. The captures, screen by screen

All rendered at 1280×720 — the size the interface is laid out at, and the only one
there is (D65) — with a stocked save. This was the 16-capture pass; `tools/screenshots.gd`
now takes **19**, having added `Chest`, `Packs`, and the two extra states of the combat
hand that D104 exists because nobody had photographed. What each one said:

| capture | verdict |
|---|---|
| `MainMenu` | The one screen that works. Painted art, scrim, readable. Buttons are smeared. |
| `Overworld` | Near-black tile. Status text wraps onto a second line and collides with the first button. *Painted since (D83d).* |
| `ZoneView` | Same. Three dungeon entries, each a smeared bar with text on its border. *Painted since, with establishing thumbnails in the rows (D96).* |
| `DeckBuilder` | Worst frame damage in the game: `+`/`−` buttons are pure frame, labels invisible. Dropdowns and the name field are unstyled. *Small frame variant and control styling landed in D83/D105.* |
| ~~`Map`~~ ~~`DeckRun`~~ ~~`DiceRun`~~ | The three traversal views, deleted in D94. Their rows are dropped rather than kept: unlike the entries above, there is no screen left for a verdict to be about. |
| `Combat` | The screen the game is played on. Framed head-on: enemies stand on the floor line with name/HP/intent above them and a contact mark under them; the hand is a fan along the bottom edge; vitals, piles and log occupy the bottom-left; the power is a round sigil and End Turn a small corner button, bottom-right. Still text where art is wanted — no HP bar, no energy orb, intent as `hit 14`. *The enemies were placeholder footprints; 35 plates landed in D89.* |
| `Shop` | Flat black, no merchant, text rows, illegible small buttons. *Backdrop painted since (D83b).* |
| `Encounter` | Title, two lines, three smeared buttons, and 400px of black where the event illustration goes. *Backdrop painted since (D83b).* |
| `Collection` | The card-illustration problem in one image: a shopping cart on Battle Trance, a cactus on Berserker Rage, a dither pattern on Abyssal Gift. *Those three names went in D98; the illustration problem did not.* |
| `Relics` | Empty state on a near-invisible tile. 30 relics have no icons to show. |
| `Powers` | Ten powers sharing a handful of monochrome glyphs. |
| `Glossary` | Text. Fine as text, but nothing teaches a symbol the player will later have to recognise. (It also read `+50%%` to the player — fixed in D57.) |
| `Victory` | The payoff moment of the whole meta layer is a five-line list on a flat tile. |
| `Defeat` | Says the right things (D59) and shows none of them: no killer portrait, no before/after on the collection, flat tile, one smeared button. |

## 7. Looking at the game

`tools/screenshots.gd` boots 19 captures at the shipped 1280×720 with a stocked
save and writes a PNG each. It is a diagnostic, not shipped, and it needs a real GL
context — art direction cannot be judged from a simulation:

```bash
Xvfb :99 -screen 0 1280x720x24 &
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
  godot --rendering-driver opengl3 --resolution 1280x720 \
        res://tools/Screenshots.tscn            # every screen
# one screen per process — a screen that hangs then costs one capture, not all of them
DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 \
  godot --rendering-driver opengl3 res://tools/Screenshots.tscn -- Combat
```

Output lands in `user://shots/` (printed as a real path on exit). Software GL takes
roughly a minute per screen; on a machine with a GPU, drop `LIBGL_ALWAYS_SOFTWARE`.

**Do not run it while `tests/run.sh` is running.** Both write `t_*` sandbox saves and
the harness purges every one of them on exit, so overlapping the two made
`CardTextTest` and `PlayableTest` fail with nothing wrong in either.

Capture before and after every art pass. "The combat screen is busy" is an opinion
until two PNGs sit side by side.
