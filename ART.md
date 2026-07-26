# ART.md — the art brief for Deckcrawl

What the game looks like now, what it should look like, and the **list of assets
that gets it there**. Companion to [AGENTS.md](AGENTS.md) (the concept) and
[DESIGN.md](DESIGN.md) (the decision log). Art decisions that stick get written up
as a `D##` entry there like everything else.

Every asset below names the **code hook** it plugs into, so nothing on this list is
a drawing that then needs somebody to figure out where it goes.

Captures used to write this were made with `tools/screenshots.gd` — regenerate them
before and after any art pass (§7). Nothing here was inferred from source code alone;
§6 says what each of the 15 captures shows.

---

## 1. The diagnosis: four visual languages, fighting

The game is not short of art. It is short of art that **agrees**. Right now five
screens' worth of assets speak four unrelated dialects:

| language | assets | verdict |
|---|---|---|
| **Painted, inked illustration** | `main_menu.jpg`, `bg_crypt/ossuary/warrens.png` | **This is the game.** Keep. |
| **Kenney 16×16 pixel art** | 41 enemy sprites, 5 zone tiles, 1 card sheet | Off-style, and semantically arbitrary |
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

**b) Half the screens have no backdrop at all.** Seven of them build straight onto
the clear colour: `collection.gd`, `deck_builder.gd`, `deck_run.gd`, `dice_run.gd`,
`encounter.gd`, `map.gd`, `shop.gd`. The map, the shop and the event screen are
flat near-black rectangles with text on them. Those are three of the four screens
the player sees most.

**c) The things the game is *about* have no art.** No player character exists on
screen anywhere. Enemies are 16×16 tiles handed to `Button.icon` and are not
visibly rendered at all in the combat capture. All 30 relics render as text rows —
`relics_screen.gd` makes no icon call whatsoever. All 20 events are a title, two
lines and three buttons over 400px of black. There is no custom font: the whole
game runs on Godot's built-in default.

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
- **Scale.** Author every UI asset at **2×** and downsample. `UITheme.scale` runs
  0.6–3.0 and `BUTTON_SLICE` is deliberately *not* scaled, so a 1×-authored frame
  is visibly soft at scale 2.0 and mush at 3.0.

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

**About 225 files** — 245 if the optional per-card hero art in Tier 3 is taken.
Two thirds are icons. Ordering below is by *visible improvement per hour*, not by
category:

| tier | what | files |
|---|---|---|
| 0 | frame kit + control chrome | 23 |
| 1 | combat readability | 47 |
| 2 | enemies | 35 |
| 3 | cards | 25 (+20 later) |
| 4 | map and traversal | 26 |
| 5 | backdrops | 20 |
| 6 | relics and powers | 40 |
| 7 | identity and shell | 8 |

Proposed layout — `assets/art/` grows subdirectories, `assets/pixel/` demotes to
fallback:

```
assets/art/
  bg/        1280x720 scene backdrops        (23 files)
  enemies/   256/512 transparent             (35)
  hero/      the player                      (4)
  cards/     card illustrations              (30)
  relics/    128x128 objects                 (30)
  powers/    128x128 sigils                  (10)
  ui/        nine-slice kit, bars, icons     (~60)
  fx/        sprite sheets                   (6)
  fonts/     display + body                  (2)
```

> **One code note before drawing anything:** `PixelArt.BATTLE_ART_DIR` is
> `res://assets/art/` and resolves `bg_<dungeon_id>.png` flat in that directory.
> Moving backdrops into `bg/` is a one-line change there, but it *is* a change —
> make it deliberately, not by dropping files in a new folder and wondering why
> nothing loads.

---

### Tier 0 — The frame kit  ·  23 files  ·  fixes every screen at once

Highest leverage item in this document by a wide margin. One kit, and all 20 screens
stop looking broken.

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
| `ui/dropdown.png` + `_arrow.png` | 192×96, 32×32 | 32/32/28/28 | `OptionButton` — *unstyled today* |
| `ui/slider_track.png` + `_grabber.png` | 128×24, 48×48 | tile X | `HSlider` — *unstyled today* |
| `ui/scrollbar_track.png` + `_grabber.png` | 24×128, 24×48 | tile Y | `VScrollBar` — *unstyled today* |
| `ui/checkbox_on.png` + `_off.png` | 64×64 | — | settings — *unstyled today* |

The theme styles **`Button` and `PanelContainer` only**. Every dropdown, slider,
scrollbar and checkbox in the game is default Godot chrome sitting next to painted
buttons — clearest in `Collection.png`, where the Sort/Rarity/Type dropdowns are flat
grey rectangles between two framed buttons.

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
  12/12/12/12 slice, selected by `UITheme.style_button()` when the control is under
  ~120px wide.

---

### Tier 1 — Combat readability  ·  47 files  ·  the screen that matters

Combat is where the game is played and it is currently the least drawn screen in
it: a text status line, two parchment rectangles for enemies, 250px of empty
middle, and five flat card shapes.

**The player (4 files)** — there is *no* player representation anywhere in the game.

| file | size | hook |
|---|---|---|
| `hero/hero_idle.png` | 512×640 | new node in `combat.gd:_build_ui()`, in the empty centre |
| `hero/hero_idle_b.png` | 512×640 | 2-frame breathe |
| `hero/hero_hurt.png` | 512×640 | on `_on_end_turn` HP loss |
| `hero/hero_portrait.png` | 256×256 | status bar, deck builder, save slots |

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

### Tier 2 — Enemies  ·  35 files  ·  biggest single credibility gap

35 archetypes and 12 named bosses currently share 41 unlabelled 16×16 Kenney tiles,
assigned **by sorted position** with a 12-entry override table to stop bosses
inheriting trash-mob faces.

| set | count | size | path |
|---|---|---|---|
| Non-boss archetypes | 23 | 256×256, transparent | `enemies/<archetype_id>.png` |
| Named bosses | 12 | 512×512, transparent | `enemies/<archetype_id>.png` |

Optional +70 files for a 2-frame idle and a hurt frame (`_idle_b`, `_hurt`).

Draw them **facing left**, lit from the left, standing on nothing (no baked ground
shadow — the backdrop supplies the floor).

Naming on `archetype_id` deletes real complexity: `PixelArt.OVERRIDES` and the
whole positional-assignment-that-skips-pinned-sprites dance in
`PixelArt.enemy_sprite()` both go away, and adding a 36th enemy stops silently
reshuffling every other enemy's face.

Boss list, for reference: `grave_sexton` `brood_mother` `marrow_abbot`
`bellows_master` `warden` `cinder_knight` `mycelial_lord` `the_gardener`
`deep_warden` `last_vendor` `false_step` `abyss_horror`.

---

### Tier 3 — Cards  ·  25 files now, 20 more later

100 cards currently draw their illustration from `assets/pixel/cards/sheet.png` —
Kenney's 1-Bit pack, a monochrome sheet of tiny symbols, **letters and dither
patterns**. `PixelArt.CARD_TILES` picks 140 of them by index and assigns by sorted
position. Many are literally alphabet glyphs. They render at 0.22 alpha behind the
card text, where they read as noise.

Recommended: **not** 100 unique paintings up front.

| step | count | size | note |
|---|---|---|---|
| Family illustrations | 24 | 320×240 | one per effect family × zone flavour; shared |
| Card back | 1 | 320×448 | **required** by the DECK traversal, which reveals cards |
| Rarity frames | 5 | — | already counted in Tier 0 |
| Hero cards | 20 | 320×240 | unique art for the 20 most-played, later |

→ hook: `PixelArt.card_art(card_id)`, resolving `cards/<card_id>.png` first and
falling back to `cards/family_<family>.png`. `CARD_ART_OVERRIDES` becomes the
exception table it was always meant to be.

**Blocker (code):** the illustration currently sits full-rect behind the text at
0.22 alpha. Real art wants its own band — top ~40% of the card face, text below it,
per `UI.card_button()`'s existing hand-placed band layout.

---

### Tier 4 — Map and traversal  ·  26 files

Three traversal models, all of them text. `Map.png` is the single worst capture in
the set: black background, no path lines, no icons, `Balance.NODE_LABEL` strings in
buttons.

**Graph map (11 files)**

| file | size | hook |
|---|---|---|
| `ui/node_<combat\|elite\|rest\|boss\|shop\|event\|treasure>.png` | 128×128 | `Icons.for_encounter()`, currently unused by `map.gd` |
| `ui/node_frame_available.png` | 192×192, 9-slice | replaces `Icons.style_card_button(b, 1)` |
| `ui/node_frame_cleared.png` | 192×192 | replaces `modulate.a = 0.35` |
| `ui/node_frame_locked.png` | 192×192 | replaces `modulate.a = 0.6` |
| `ui/map_path.png` | 32×16, tile X | **there are no edges drawn between nodes at all** |

**Dice board (14 files)** — the player's position is the string `"^you"` under a
16×16 glyph, and the two dice are the text `dice: [3, 2]` in the status line.

`ui/tile_<7 encounter kinds>.png` 128×128 · `ui/die_<1..6>.png` 128×128 ·
`ui/token_player.png` 128×128

> The board was invisible when this brief was written — a `ScrollContainer` with both
> scroll modes at AUTO reports a minimum size of 0, so the surrounding
> `SIZE_EXPAND_FILL` spacers crushed it flat. **Fixed in D57**; the track now renders
> its 16 cells, using the 16×16 encounter glyphs. Those glyphs are what this tier
> replaces.

**Deck traversal** — needs the card back from Tier 3 plus `ui/reveal_frame.png`
(320×448, 9-slice) for `deck_run.gd:reveal_icon`.

---

### Tier 5 — Backdrops  ·  20 files at 1280×720  ·  the most *visible* gap

Three dungeon backdrops exist. **Nine of twelve dungeons fall back to a 16×16
tinted tile** — which is what `Overworld.png`, `Map.png`, `Shop.png` and
`Encounter.png` all show: near-black with a faint dot grid.

| set | count | missing |
|---|---|---|
| Dungeon battle backdrops | 12 | 9 — `foundry` `ember_road` `slag_pits` `fungal_deep` `rot_gardens` `sunken_vault` `drowned_market` `abyssal_stair` `the_maw` |
| Zone backdrops (overworld / zone view) | 5 | 5 — all are 16×16 tiles today |
| Scene backdrops | 6 | 6 — shop interior, rest camp, event shrine, treasure vault, victory, defeat |

→ hooks: `PixelArt.battle_art()` for dungeons, `PixelArt.backdrop_texture()` for
zones, and **new** `UI.screen(..., art)` calls on the seven screens listed in §1(b).

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

### Tier 7 — Identity and shell  ·  8 files

| file | size | note |
|---|---|---|
| `fonts/display.ttf` | — | **no custom font exists**; titles use Godot's default |
| `fonts/body.ttf` | — | ″ — needs an OFL/SIL licence, recorded like the Kenney ones |
| `ui/logo.png` | 1600×480 | the title is a plain `Label` reading `"DECKCRAWL"` |
| `icon.svg` + `icon.png` | 256×256 | **no window or export icon configured** in `export_presets.cfg` |
| `ui/boot_splash.png` | 1280×720 | none configured |
| `ui/cursor.png`, `ui/cursor_press.png` | 64×64 | optional |

The font is the cheapest large win on this list: two files and a `Theme` change,
and every one of the 20 screens changes character.

---

## 4. Code work the art needs

Assets that land on top of these problems will not look better. None of it is large.

1. **Backdrops on the seven bare screens** — `collection` `deck_builder` `deck_run`
   `dice_run` `encounter` `map` `shop`. They build a `MarginContainer` directly and
   never call `UI.screen()` or `PixelArt.backdrop()`.
2. **Give text somewhere to sit.** `UITheme._frame()` sets `content_margin` to `10`
   vertically against a `19/21` texture slice, and `min_button_height()` is only
   `t + b + 10`. The result is a 50px button with 40px of border and a 10px parchment
   band — a 16px font cannot fit. Content margins must be **≥ the slice**, which in
   turn means `min_button_height()` has to rise (or the new art's slice has to fall).
3. **Enemies need a composed panel**, not a `Button` with `icon` + multi-line
   `text`. The 16×16 sprite is not visibly rendered in `Combat.png` at all. Sprite,
   name, HP bar and intent icon each want their own placed region — the same
   hand-placed approach `UI.card_button()` already uses, and for the same reason.
4. **Style every button, and every other control.** `map.gd`, `dice_run.gd` and
   `deck_run.gd` build their "Collection" buttons without `UITheme.style_button()`,
   so they render flat grey next to a framed "Menu". The theme itself only covers
   `Button` and `PanelContainer` — `OptionButton`, `HSlider`, `VScrollBar` and
   `CheckBox` are untouched.
5. ~~**The dice board collapses to zero height.**~~ **Done (D57).** One line —
   `vertical_scroll_mode = SCROLL_MODE_DISABLED`, since the track scrolls sideways and
   a `ScrollContainer` only contributes its content's minimum size on axes it cannot
   scroll. `PlayableTest` now asserts the general case: no scroll area may be squeezed
   to zero on an axis whose content needs pixels.
6. **Draw map edges.** Nothing connects the nodes. A `Line2D` layer under
   `rows_box`, fed from `TraversalGraph`'s existing edge data.
7. **Flip the texture filter default.** `project.godot` sets NEAREST globally and
   painted art overrides per-node. Once painted art is the majority that is backwards
   — flip the default to LINEAR and mark the surviving pixel assets NEAREST.
8. **An art-coverage test**, per the D42 rule that half-added content must fail
   loudly: every archetype, card, relic, power and dungeon id has a file at its
   conventional path, or the suite goes red. Convention over an `@export var art`
   field — no `.tres` churn, and it keeps "add content = data file plus a catalogue
   line" true.

---

## 5. If you only do three things

1. **Tier 0, the frame kit.** Twenty screens stop looking broken. One day of work.
2. **The nine missing dungeon backdrops** (Tier 5) plus backdrops on the seven bare
   screens. This is the difference between "a prototype" and "a game", and three
   existing paintings already set the target.
3. **A font, and the player character.** The font changes every screen for two
   files; the hero fills the hole in the middle of the screen the game is played on.

Enemies (Tier 2) are the biggest *credibility* gap and the biggest single job — 35
paintings. Worth starting in parallel, because it is the item that will not compress.

---

## 6. The captures, screen by screen

All 15 rendered at 1280×720, UI scale 1.0, with a stocked save. What each one says:

| capture | verdict |
|---|---|
| `MainMenu` | The one screen that works. Painted art, scrim, readable. Buttons are smeared. |
| `Overworld` | Near-black tile. Status text wraps onto a second line and collides with the first button. |
| `ZoneView` | Same. Three dungeon entries, each a smeared bar with text on its border. |
| `DeckBuilder` | Worst frame damage in the game: `+`/`−` buttons are pure frame, labels invisible. Dropdowns and the name field are unstyled. |
| `Map` | Flat black. No backdrop, no icons, **no lines between nodes**. `Icons.for_encounter()` exists and is never called. |
| `DeckRun` | One 16px sword glyph and two unstyled grey buttons on black. |
| `DiceRun` | Board was 0px tall — a layout bug, not an art gap, **fixed in D57**. Now 16 track cells of 16×16 glyphs, and the player token is the string `^you`. |
| `Combat` | The screen the game is played on: no player, no HP bar, no energy orb, intent as the text `hit 5`, enemy sprites not visibly rendered, 250px of empty centre. |
| `Shop` | Flat black, no merchant, text rows, illegible small buttons. |
| `Encounter` | Title, two lines, three smeared buttons, and 400px of black where the event illustration goes. |
| `Collection` | The card-illustration problem in one image: a shopping cart on Battle Trance, a cactus on Berserker Rage, a dither pattern on Abyssal Gift. |
| `Relics` | Empty state on a near-invisible tile. 30 relics have no icons to show. |
| `Powers` | Ten powers sharing a handful of monochrome glyphs. |
| `Glossary` | Text. Fine as text, but nothing teaches a symbol the player will later have to recognise. (It also read `+50%%` to the player — fixed in D57.) |
| `Victory` | The payoff moment of the whole meta layer is a five-line list on a flat tile. |

## 7. Looking at the game

`tools/screenshots.gd` boots every screen at the shipped 1280×720 with a stocked
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
