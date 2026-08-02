# The Owing — Design & Implementation Plan

A 2D deckbuilding roguelike with RPG progression, built in Godot 4.7.1 (GDScript) on NixOS.

Status legend: `[x]` done & validated · `[~]` partial/stubbed · `[ ]` not started

---

## 1. Vision

Slay-the-Spire-style card combat wrapped in two progression loops:

- **Roguelike loop** — enter a dungeon, traverse an encounter map of random fights, die and restart. Run-local state (HP, current deck) resets on death.
- **RPG loop** — cards earned across runs accumulate in a persistent collection. Duplicates are fused to level cards up (the "training" dimension). Relics and quests add character development on top.

Long-term the dungeons sit inside an **open 2D/2.5D world** with cities, NPCs, and quests that hand out relics — dungeon difficulty gates card rarity (rare/epic/legendary), and some cards are exclusive to specific dungeons.

Nearest existing analogues: *Griftlands*, *Nowhere Prophet*, *Dream Quest*, *Slice & Dice*. None combine all four systems (combat + run roguelike + persistent card RPG + open-world quest hub) — that combination is the novel, and riskiest, part.

### Scope reality
This is four systems bolted together. Each is individually solved; the risk is integration scope and content authoring (every exclusive card / city / quest is bespoke). Build order deliberately validates the cheap, central systems first (combat) and defers the expensive, peripheral one (open world) last.

---

## 2. Systems overview

| System | Role | Status |
|---|---|---|
| Card combat | Turn-based, energy, block, telegraphed intents | `[x]` |
| Enemy archetypes | Data-driven, cycling action patterns per archetype | `[x]` |
| Multi-enemy encounters | Groups sharing one budget, player targeting | `[x]` |
| Reward | Pick 1-of-3, rarity-weighted by encounter tier | `[x]` |
| Traversal | One model: an isometric crawl, walked by all 12 dungeons. The `Traversal` seam stays (D13); the graph, deck and dice models lost to it in D88 and were deleted in D94 | `[x]` |
| Meta collection | Persistent card ownership + fusion/leveling | `[x]` |
| Upgrade caps | Max level per rarity (common 100), derived from drop weight | `[x]` |
| Gold currency | Persistent: earned in combat, lost on death, spent at shops | `[x]` |
| Consumables | Escape Ropes: the only way to leave a run with its loot | `[x]` |
| Resumable runs | Run *and* mid-combat state persisted, in a separate file | `[x]` |
| Save/load | Versioned JSON with migration + backup | `[x]` |
| Death stakes | Lose gold + cards, scaled by dungeon difficulty | `[x]` |
| Status effects | Vulnerable / Weak / Strength / Dexterity, enemy debuffs | `[x]` |
| Block lifetime | Expires each turn; legendary `Barricade` makes it persist | `[x]` |
| Relics | Second meta axis: persistent, granted by boss clears | `[x]` |
| Shop nodes | Cards + healing for gold (the sink) | `[x]` |
| Event nodes | Data-driven choices with declarative effects | `[x]` |
| Treasure nodes | Gold, sometimes a card from the dungeon pool | `[x]` |
| Zones | Themed regions clustering dungeons and card pools | `[x]` |
| Builds | Named archetypes, gated behind clearing several dungeons | `[x]` |
| Starting kits | Three 12-card openings, each pointing at a build | `[x]` |
| Onboarding | Data-generated tooltips, glossary, first-time hints | `[x]` |
| Endgame | Victory screen + Ascension (New Game+) | `[x]` |
| Named dungeons | Selectable places with own roster, card pool, unlock gate | `[x]` |
| Exclusive cards | Cards obtainable in exactly one dungeon | `[x]` |
| Rarity gating by difficulty | Loot tilts toward rare/epic/legendary with difficulty | `[x]` |
| Open world / cities / NPC quests | Hub layer, quest-granted relics | `[ ]` |

---

## 3. Architecture

### State tiers (the load-bearing split)

| Tier | Singleton | Holds | Persists? | On death |
|---|---|---|---|---|
| **Meta** | `MetaState` | card collection `id→{count,level}`, **relics**, `gold`, `highest_dungeon` | disk (`user://save.json`) | gold+cards partly lost (D3); **relics kept** |
| **Run** | `GameState` | run deck instance, HP, the generated floors, position, dungeon tier | memory only | wiped |

Autoload order matters: `MetaState` loads before `GameState` (GameState builds its deck from the collection).

### Scenes & flow

```
MainMenu.tscn (entry)
  ├─ Continue / New Game / Load ──▶ SaveSlots.tscn ──▶ Overworld.tscn
  ├─ Settings.tscn
  └─ Quit

Overworld.tscn  (zones: travel + what each zone's card pool holds)
  ├─▶ ZoneView.tscn (dungeons of one zone) ──▶ DeckBuilder.tscn
  ├─▶ Collection.tscn (fuse)   ├─▶ DeckBuilder (Loadouts mode)   ├─▶ Relics.tscn
  ├─▶ Settings.tscn
  └─▶ Save and quit ──▶ MainMenu

  DeckBuilder ── assemble/select a deck for this dungeon ──▶ IsoRun.tscn
  IsoRun.tscn
    ├─ combat/elite tile ──▶ Combat.tscn ──▶ reward ──▶ back to the floor
    ├─ boss tile ──▶ Combat.tscn ──▶ reward ──▶ advance dungeon ──▶ DeckBuilder (pick deck for next dungeon)
    ├─ rest tile ──▶ heal inline, stay on the floor
    ├─ shop tile ──▶ Shop.tscn (buy cards / healing for gold) ──▶ back to the floor
    └─ "Collection" button ──▶ Collection.tscn (fuse) ──▶ back
    └─ boss cleared ──▶ dungeon marked cleared + relic ──▶ ZoneView
  Combat defeat ──▶ death penalty ──▶ run reset ──▶ Overworld
  any run view ──▶ "Menu" ──▶ PauseMenu.tscn (Resume / Collection / Settings /
                              Abandon run / Save and quit)
```

Run views route back through `GameState.run_scene()`, and `RunFlow.leave_run()` decides where a
finished or absent run returns to — so adding a screen or a traversal model does not mean editing
navigation in every scene.

Per-dungeon deck (D4): a run deck is built from a chosen loadout at each dungeon entry, not auto-loaded from the whole collection.

### Files

| Path | Responsibility |
|---|---|
| `scripts/card_data.gd` | Card = data Resource (`id`, `rarity`, `level`, cost, effects). `eff_damage()/eff_block()` apply level scaling. |
| `scripts/traversal.gd` | Traversal contract: options/select/complete + shared encounter budget. |
| `scripts/traversal_iso.gd` | The one model: an isometric building of rooms and corridors over several floors (D79, D88). Three others — graph, deck, dice — were deleted in D94. |
| `scripts/run_flow.gd` | Shared encounter routing used by every traversal view. |
| `scripts/packs_screen.gd` | Sealed packs: what is unopened, and opening it (D80/D81). |
| `scripts/powers_screen.gd` | Power roster: buy, level, equip the one carried into a run. |
| `scripts/chest_screen.gd` | The chest a crawl tile opens. |
| `scripts/glossary.gd` | Generated from the data, so a mechanic cannot exist unexplained. |
| `scripts/starter_kit.gd` | The three 12-card openings a new save picks between. |
| `scripts/card_filter.gd` | The sort/rarity/type filter shared by collection and builder. |
| `scripts/victory.gd`, `scripts/defeat.gd` | End-of-run screens; defeat names what was left behind (D59). |
| `scripts/art_palette.gd`, `scripts/art_shapes.gd` | Shared by the art generators: the palette, and the silhouette primitives the enemy plates and iso markers both build from. |
| `scripts/build_data.gd` | Build Resource: a named archetype and its defining cards. |
| `scripts/builds_screen.gd` | Build tracker: progress and where the missing cards are. |
| `scripts/icons.gd` | Placeholder art lookup, rarity colours, card styling. |
| `scripts/zone_data.gd` | Zone Resource: themed card pool + the dungeons it contains. |
| `scripts/dungeon_data.gd` | Dungeon Resource: difficulty, unlock gate, enemy roster, card pool, exclusives. |
| `scripts/overworld.gd` + `scripts/zone_view.gd` | Dungeon choice, in two steps: pick a zone, then a dungeon within it. These replaced the old `dungeon_select.gd`, which was always described as the seam the overworld would take over. |
| `scripts/relic_data.gd` | Relic Resource: run/combat/turn/reward effects + tuning weight. |
| `scripts/enemy_data.gd` | Enemy archetype Resource: stat shares, action pattern, group size. |
| `scripts/combatant.gd` | HP, block and status effects; owns the block-expiry / `retain_block` rule. |
| `scripts/balance.gd` | **All** tuning constants + scaling formulas (enemy stats, gold, rarity weights, deck bounds, power ratio). |
| `scripts/combat_engine.gd` | Pure combat rules, no UI/autoloads — shared by the Combat scene and the simulator. |
| `scripts/meta_state.gd` | Persistent collection, `CATALOG`, fusion, `build_run_deck`, JSON save/load. |
| `scripts/game_state.gd` | Run state, floor generation, run save/restore. |
| `scripts/combat.gd` | Combat *screen*: thin UI over `CombatEngine`; reward flow and routing. |
| `scripts/iso_run.gd` | View for the crawl: a camera onto the floor, drawn at an angle. |
| `scripts/event_data.gd` | Event Resource: choices + declarative effects. |
| `scripts/encounter.gd` | Event/treasure screen; applies all effects centrally. |
| `scripts/collection.gd` | Collection/fusion UI. |
| `scripts/shop.gd` | Shop node: sells cards + healing for gold. |
| `scripts/deck_builder.gd` | Per-dungeon deck assembly: select copies, save/load named loadouts, start dungeon. |
| `scripts/ui.gd` | Shared menu builders (screen/label/button/row/slider/scroll). |
| `scripts/main_menu.gd` | Title screen; owns which save slot is played. |
| `scripts/save_slots.gd` | Slot picker for both New Game and Load, with confirmations. |
| `scripts/settings_menu.gd` | Settings screen (audio rows are placeholders). |
| `scripts/settings_state.gd` | Persisted settings autoload (`user://settings.json`). |
| `scripts/overworld.gd` | Zone travel; the layer art will replace. |
| `scripts/zone_view.gd` | Dungeons within one zone. |
| `scripts/relics_screen.gd` | Relic inventory. |
| `scripts/pause_menu.gd` | In-run menu, incl. abandon-run confirmation. |
| `scripts/ui_theme.gd` | Fullscreen, the global Theme (buttons, panels, dropdowns, sliders, scrollbars, checkboxes) and the size helpers. The interface is a **fixed** 1280x720 since D65; `UI_SCALE` is a constant `1.0` and nothing varies it. |
| `scenes/*.tscn` | Thin Control roots; all UI built in code. |
| `resources/cards/*.tres` | Card definitions (data, not code). |
| `resources/enemies/*.tres` | Enemy archetypes (data, not code). |
| `resources/relics/*.tres` | Relic definitions (data, not code). |
| `resources/dungeons/*.tres` | Dungeon definitions (data, not code). |
| `resources/events/*.tres` | Event definitions (data, not code). |
| `resources/zones/*.tres` | Zone definitions (data, not code). |
| `resources/builds/*.tres` | Build archetypes (data, not code). |
| `scripts/audio.gd` | Sound autoload: buses, voice pool, event -> stream. |
| `scripts/pixel_art.gd` | Authored 16x16 symbol glyphs, the card sheet, and the lookup for every painted asset (backdrops, enemy plates, the UI kit). |
| `assets/pixel/` | What is left of the CC0 pixel art: the 1-Bit card sheet and five Pattern Pack zone tiles, each with its licence. The Tiny Dungeon enemy sprites went in D89 and the UI RPG frames in D83. |
| `assets/art/` | Everything painted or generated for this project: 23 backdrops, 35 enemy plates, the iso floor, the computed UI kit. Not CC0 — see its README. |
| `tests/test_*.gd` + `tests/*Test.tscn` | 37 suites. Script tests inspect files; scene tests measure a built tree, because size, position and visibility do not exist until one is. |
| `tools/sim_balance.gd` | Headless balance simulator (see Balance workflow). |

### Menus, slots and settings (D19)

Structure before graphics: every screen is a placeholder visually, but the *shape* is real — three
independent save slots, a title screen that owns slot choice, an overworld that gates zones, an in-run
pause menu, and a settings screen whose audio rows exist so adding sound later is wiring rather than
UI work.

- **Settings live outside the save** (`user://settings.json`): they belong to the machine, so deleting a
  save or switching slots must never change them. Values are clamped on load, not just on set.
- **Slots are independent** (`save.json`, `save_1.json`, …) and `MetaState.slot_summary()` reads a slot
  *without* disturbing what is loaded, so the menus can list slots mid-game.
- **Destructive actions confirm**: overwriting a slot and abandoning a run both ask first. Abandoning
  deliberately does **not** apply the death penalty — the player chose to leave rather than lose.
- **`UI` builders** keep screens declarative, so restyling all of them later is one file.

`tests/test_flow.gd` scans every script for `res://scenes/...` references and asserts each target exists.
With this many screens the realistic failure is a typo'd path that only surfaces when a player clicks
that one button; it also warns about scenes nothing navigates to.

### Save versioning (D15)

`MetaState.SAVE_VERSION` is written into every save. On load:
- **older** → back up to `save.json.v<N>.bak`, run `_migrate()`, apply, rewrite at the current version
- **newer** → refuse to load rather than silently dropping fields a future build added
- **unknown content ids** (renamed/removed cards, relics, dungeons) are dropped in `_apply()`, not in
  migration, so renaming content can never corrupt a save
- **unreadable or empty** → refuse / repair rather than leaving the player unable to build a deck

Bump `SAVE_VERSION` and add a `_migrate()` step whenever the shape changes. `tests/test_save.gd` covers
round-trip, v0 migration, backup creation, future-version refusal, junk rejection and corruption.

### Builds are gated behind clearing dungeons (D25)

A deck archetype ("build") is now data: `BuildData` names the cards that define it. Their defining
cards are deliberately **scattered across dungeons in different zones**, so assembling a build means
clearing several places rather than farming one.

This only has teeth because of escrow (D20): a dungeon-exclusive card is kept **only** by beating that
dungeon's boss or spending a rope on it. Exclusivity plus escrow is what converts "collect cards" into
"clear these four places".

| Build | Cards | Gated behind |
|---|---|---|
| The Long Death (poison) | 12 | 4 dungeons, 4 zones |
| The Bramble Wall (thorns) | 8 | 4 dungeons, 4 zones |
| The Rising Arm (strength) | 10 | 4 dungeons, 4 zones |
| The Closed Door (fortress) | 10 | 4 dungeons, 4 zones |
| The Wide Cut (swarm) | 10 | 4 dungeons, 4 zones |
| The Quick Hand (tempo) | 11 | 4 dungeons, 4 zones |
| The Red Ledger (vampire) | 8 | 4 dungeons, 4 zones |

`tests/test_build.gd` enforces the rule rather than trusting the content: every build must be gated behind at
least 3 dungeons across at least 2 zones, **no single dungeon or zone may complete any build**, builds
must name real cards and cover at least half the card set, and every gate dungeon must be reachable.
One content edit could otherwise quietly collapse an archetype back into a single farmable dungeon.

The **Builds screen** (from the overworld) shows progress per archetype and, for each missing card,
*where* it is found and whether that dungeon is cleared — so a run has a stated purpose.

### Zones cluster content geographically (D16)

Card availability is **geographic**: a zone owns a themed card pool, and a dungeon's obtainable cards
are `zone.card_pool ∪ dungeon.card_pool` (via `Balance.card_pool_for`). Zone pools carry the theme,
dungeon pools carry the exclusives — so a poison deck is something you travel to build.

| Zone | Unlock | Dungeons | Theme |
|---|---|---|---|
| The Hollow Barrows | — | Crypt, Ossuary, Warrens | martial basics, defence |
| The Ashen Foundry | 2 clears | Foundry, Ember Road, Slag Pits | strength, thorns, growth |
| The Verdant Rot | 4 clears | Fungal Deep, Rot Gardens | poison, AoE debuffs |
| The Sunken Deeps | 6 clears | Sunken Vault, Drowned Market, Abyssal Stair | epics and legendaries |
| Beyond the Stair | 8 clears | The Maw | the last door anyone mapped |

Zone membership is the authority and lives in `resources/zones/*.tres`; the difficulty
of a dungeon lives on the dungeon. Neither is restated here — a dungeon listed in two
zones, or in none, is caught by `tests/test_content.gd` rather than by this table.

One pool helper feeds rewards, shop stock *and* event card grants, so exclusivity holds everywhere.

### Traversal is a seam, and there is one model behind it (D13, D88, D94)

Everything else — combat, cards, relics, shops, meta, deck-building — talks only to the `Traversal`
interface (`options()` / `select()` / `clear_pending()` / `is_complete()`), and `TraversalIso` is the
only implementation. Four models were built against this seam; D88 measured the other three
discounting their own attrition budgets and moved every dungeon onto the crawl, and D94 deleted them.
`DungeonData` no longer carries a `traversal` field — a dungeon differs from its neighbour by its
floor's shape and surface (`Balance.ISO_STYLE_OF` / `ISO_TERRAIN_OF`), not by its model.

**The seam is kept deliberately, and so is the plural in the tests.** Two rules made it cheap rather
than a maintenance tax, and both still hold:

1. **Implementations are pure logic** (no UI, no autoloads). The balance simulator drives them
   directly, so **one generic walker measures every model**. A per-model walker would be the first
   thing to rot when a model is added.
2. **Every model spends a comparable attrition budget** (`Balance.ENCOUNTER_*`). Otherwise
   "difficulty 3" means different things in different dungeons and the scaling model decouples.
   `tests/test_traversal.gd` asserts this, plus termination and exactly-one-boss, and still loops over
   an array of models rather than over one — that is the wiring a second one would need.

Shared encounter routing lives in `RunFlow`, so a new view does not re-derive how a rest heals or
which scene a shop opens.

**A model's encounter count must be derived, not structural.** The graph visited one node per row, so
its row count *was* its encounter count — hardcoded at 6, it silently broke the budget contract the
moment new encounter types entered the mix, and had to derive from the budget instead.

**The budget is an average, not a per-run guarantee**, so `tests/test_traversal.gd` asserts the *mean*
encounters and keeps only a loose per-run bound to catch runaway generation.

**And equal encounter counts are not equal cost**, which is the lesson the other three died of: all
four passed the count assertion at 13.2 while the fights actually *met* were graph 4.5–5.1, dice
3.5–4.1, deck 4.9, against iso's 5.9–6.0. A model's skip is part of its price and no budget assertion
can see it (D88). The crawl prices a slip-past of its own, and `avoid_cost` takes the rung count from
the traversal that generates it rather than from a global constant, because a ladder tuned for N rungs
is wrong the moment something changes N (D99).

### Run earnings are escrowed (D20)

Rewards used to commit to the collection the moment they were picked (the original D1). That made the
**boss optional**: clear the four or five easy encounters, bank every card and coin, then abandon. Since
failures cluster on the boss row in every measurement, skipping it removed nearly all the risk while
keeping identical loot — strictly better than fighting it. A dominant strategy is a broken option.

Now cards and gold earned inside a run go to `GameState.escrow_*`. They are usable **immediately within
that run** (the useful half of D1 — a reward you cannot play is no reward), but become permanent only
when the dungeon's boss falls:

| Outcome | Run earnings | Dungeon cleared? | Permanent cost |
|---|---|---|---|
| Boss killed | committed | yes — relic, unlock, +max HP | — |
| **Escape Rope used** | **committed** | **no** | one rope |
| Died | forfeited | no | gold fraction + `cards_lost_on_death` copies |
| Quit to title mid-run | forfeited | no | — (run is not resumable) |

**There is no free abandon (D21).** Leaving a dungeon *with* what you found requires an **Escape Rope**:
a consumable that is **found and never sold** — treasures and cleared bosses drop them. A purchasable
exit would let the player buy their way out of every risk, which is the farming loop escrow exists to
close; a found one is supply-limited, so retreat becomes a resource decision instead of a menu click.
A new save starts with exactly one rope so the mechanic teaches itself.

Using a rope keeps the loot but leaves the dungeon **uncleared** — no relic, no unlock, no max-HP. So
the interesting question is "is this haul worth my only rope, or do I risk the boss for the relic?"

**Runs are resumable (D22)**, which is what makes the rope meaningful: quitting is a *pause*, not an
escape. The run rides inside the normal save and `Continue` picks it up.

Crucially, **the fight in progress is serialized too** — hand, both piles, energy, turn, target, every
combatant's statuses, and each enemy's archetype, intent and accumulated turns. Persisting only the run
*between* encounters would have created a new exploit: force-quitting a fight that is going badly and
reloading would restore the pre-fight HP, i.e. a free retry. Restoring mid-combat removes the incentive
because there is nothing to roll back to.

Serialization is owned per traversal model (`save_state`/`_save`/`_load`, rebuilt by
`Traversal.from_state`), so adding a model does not mean touching save code. Autosaves happen at every
point progress could be lost: entering an encounter, resolving a rest/shop/event, and **each combat
action and turn**.

**Saves are incremental (D23).** Two changes, because saving on every card play originally rewrote the
entire collection:

1. **The run lives in its own file** (`save_N.run.json`) beside the meta save. They change at completely
   different rates — meta only when something permanent is gained, the run on every action — so writing
   them together meant rewriting 100 card entries to record one turn. It also isolates damage: a
   truncated run file cannot take the permanent save with it, and a run that fails to load is discarded
   while the collection survives.
2. **Writes are coalesced.** Mutations call `mark_meta_dirty()`/`mark_run_dirty()`; `_process` flushes
   after `FLUSH_SECONDS` (0.75). `flush()` forces a write at moments where losing a second would
   matter — death, a boss kill, using a rope, quitting — and `_notification` flushes on window close.

Measured on a late-game save (3849-byte meta, 2360-byte run with a full mid-combat state), a combat turn
that touches state ~12 times went from 12 writes / 46 KB to **1 write / 2.4 KB — 12x fewer writes and
~20x fewer bytes**, with the meta file not rewritten at all during combat. Worth noting honestly: a full
save measured only ~0.3 ms, so this was never a stall — the win is write volume and crash isolation, not
frame time.

Two things that bite here and are covered by tests: JSON turns every number into a float, so restore has
to coerce ints back (row/col arithmetic and enum comparisons break silently otherwise); and content
renamed since the save must be dropped rather than crash — a run whose deck no longer resolves is
discarded instead of loading half-formed.

Details that matter:
- **Spending draws from the at-risk pool first**, so a shop purchase never eats gold the player could
  have walked away with. A failed spend rolls back rather than half-charging.
- **Shop-bought cards are escrowed too.** They were bought with run gold, so keeping them after
  abandoning would just re-open the exploit through the shop.
- The at-risk total is shown in every run view, the shop, and the abandon confirmation — the tension
  only works if the player can see it.

**D3 was retuned as a consequence.** Forfeiting a whole run is now the main sting, so permanent card
loss dropped from `difficulty` copies to `ceil(difficulty/2)` (`Balance.cards_lost_on_death`) — it still
scales with depth, but no longer stacks a harsh permanent regression on top of losing the run.

### Invariant: no unrecoverable states

The collection must never fall below `MIN_DECK_SIZE`. Below it no legal deck can be built, so no
dungeon can be entered, so no cards can be earned — a **hard softlock** with no way out.

`Balance.MIN_KEEP` is therefore *derived* from `MIN_DECK_SIZE` rather than set independently, and every
sink on the collection has to respect it:
- **Fusion** (`MetaState.can_fuse`) refuses when spending copies would breach the floor.
- **Death penalty** (`penalize_death`) stops removing copies at the floor.

`tests/test_softlock.gd` fuzzes fusion, deaths, purchases and card gains together and asserts a legal deck
stays buildable throughout. Any future collection sink (card removal, crafting, trading) must be added
to that fuzz list.

### Pixel art (D29)

> **Largely superseded.** The game was pixel art throughout when this was written. It is
> now painted: 23 generated backdrops, 35 generated enemy plates, a computed UI kit and a
> generated isometric floor. Two rows below survive — the authored glyphs and the card
> sheet — and the *reasoning* survives all of it, which is why the section is kept. What
> replaced each row is named in the right-hand column.

| What | Source | Status |
|---|---|---|
| Enemy sprites (28→41) | Kenney **Tiny Dungeon**, CC0 | **gone (D89)** — 35 generated plates, keyed by archetype id |
| UI panels / buttons | Kenney **UI Pack RPG Expansion**, CC0 | **gone (D83)** — computed by `tools/gen_ui_kit.gd` |
| Effect symbols (13) | **authored in `pixel_art.gd`** as 16x16 bitmaps | still here; 21 painted replacements are Tier 1d of the art list |
| Backdrops (5, one per zone) | Kenney **Pattern Pack Pixel**, CC0 | still here as the fallback; the zone screens draw painted establishing shots (D83d) |
| Sound (23 events) | Kenney **Interface / RPG / Jingles**, CC0 | still here — named files, so mapping is exact |
| Card illustrations (100) | Kenney **1-Bit Pack** sheet, CC0 | still here, and **the worst-looking thing in the game**: a 16x16 tile magnified ten times across a card face. Twelve family illustrations are Tier 3. |

The packs ship *unlabelled* spritesheets (`tile_0093.png`) and there is no way to tell a sword tile from
a barrel tile without looking at it. Picking symbols from them would have been guesswork presented as
art, so the twelve glyphs that carry meaning — attack, block, poison, thorns, heart, gold, card, dice,
skull, campfire, rope, chest, book — are authored as bitmap strings instead. They are monochrome, so
callers tint them (rarity colour, faded board spaces).

Enemy sprites were assigned by **position in a sorted archetype list**, not by hashing the id: hashing
collided and left 28 enemies sharing only 17 sprites, so different enemies looked identical. Position
guaranteed distinctness while sprites lasted, stayed stable across runs, and `PixelArt.OVERRIDES` let
any one of them be corrected by eye. All of it went in D89 — the plate is named for the archetype, so
adding a 36th enemy no longer reshuffles every face downstream, and `PixelArt.OVERRIDES` and
`PixelArt.enemy_sprite()` no longer exist. Positional assignment survives in exactly one place, the
gridded icon sheets, and only because the order is generated into the prompt and read back by the
installer from the same table (D91).

Two things that are invisible headlessly and are therefore asserted by `tests/test_art.gd`:
**nearest-neighbour filtering** (`default_texture_filter=0` — the default is linear, which turns every
sprite to mush when scaled) and **coverage** (every symbol builds and is not near-empty, every enemy has
a distinct sprite, every card resolves to a fitting symbol, licences ship beside the borrowed art, and
the rarity colours are far enough apart to tell apart).

**Backdrops** tile behind every screen and are themed by wherever the player is (the run's zone, else
the zone being browsed). They were selected by *measurement*, not by eye, because I cannot see them:
each candidate tile was scored for **wrap error** — how different its opposite edges are, so tiling
leaves no visible seam — and for **internal contrast**, so a backdrop stays a backdrop. The five
installed all score a wrap error of 0.000 at 21-29% luminance. Since the art is near-monochrome, zone
identity comes from tinting it.

`tests/test_art.gd` asserts the part that actually matters: a background's failure mode is not being missing,
it is **competing with the text on top of it**. So brightness, busyness and seamlessness are all bounded,
and every zone must have both art and a distinct tint. `UI.screen()` adds the backdrop for every screen
at once, with mouse input ignored so it can never eat a click.

**Card illustrations** come from one 20 KB spritesheet sliced with `AtlasTexture` — 100 distinct
regions rather than 100 imported files. Tiles were filtered by ink coverage (12-72%, so nothing blank or
solid) and then *sampled across the sheet* rather than taken contiguously, since neighbouring tiles are
variations of one another. Assignment is by position in the sorted card list, which guarantees no two
cards share art; `CARD_ART_OVERRIDES` corrects any single one by eye.

**Cards are layered, and the layering is the point.** The illustration is arbitrary art from an
unlabelled sheet, so it sits *behind* the text at 22% opacity where it gives a card identity without
making a claim about what it does. The **effect symbol** — derived from the card's actual fields — stays
in front and legible. Decoration behind, meaning in front; `UI.card_button()` builds both so no screen
can get that ordering wrong.

### Sound (D32)

23 CC0 Kenney sounds (`assets/audio/`, licences alongside): interface clicks, RPG foley and 8-bit
stingers. Unlike the art packs these ship **named** files, so the mapping is semantically correct rather
than arbitrary — `knifeSlice` really is the attack sound, `handleCoins` really is the gold sound.

`Audio` (autoload) owns two things:

* **Buses.** `Music` and `SFX` sit under `Master`, created in code so there is no bus-layout resource to
  keep in sync. The settings sliders were placeholders until now; they drive these for real, mapped
  linear-to-dB with 0 muting outright rather than leaving a whisper at -80 dB.
* **A voice pool** of 8 players. A burst of hits during one turn reuses voices instead of spawning
  nodes, and each play gets slight pitch jitter — repeated identical samples otherwise fuse into one
  long machine noise.

Sounds are chosen from **what a card actually did** (poison / heavy hit / light hit / block / buff),
read off its real fields, so a new card is audible correctly without being registered anywhere.
`UI.button()` and `UI.card_button()` attach the click and card sounds centrally, so a new screen is
never silent by omission.

`tests/test_art.gd` covers the part that fails quietly: **a missing sound is silence, and silence is
indistinguishable from "nothing was meant to play"**. So every declared event must resolve to a real,
non-empty stream, unused files are flagged, and the volume curve is asserted to mute at 0, be
unattenuated at 100, and rise monotonically between.

Still missing: **art-driven** animation. Combat has tweened feedback — floating damage numbers, a hit
shake, a screen flash scaled to the hit — but no impact sprite, no death effect and no card-play
flourish. Those are the six FX sheets in Tier 1e, and the manifest says plainly that eight frames of
one effect evolving is the thing an image model does not hold: it is a shader or a particle system.

Older note — all lookups still go through `scripts/icons.gd`:
- call sites ask for **meaning** (`"boss"`, `"poison"`, `"gold"`) rather than filenames, so swapping art
  is one file;
- a missing icon returns `null` instead of crashing a screen;
- `Icons.for_card()` picks an icon from what a card actually *does*, so new cards get sensible art with
  no per-card work;
- `rarity_colour()` / `style_card_button()` carry rarity as **colour**, which is the thing a player reads
  at a glance — text alone made every card look identical.

*That note ended "Still placeholder: no animation, no sound, no backgrounds, no enemy portraits." Sound
landed in D32, backgrounds in D73/D83b/D83d, enemy plates in D89. Animation is the one still true, in
the narrowed sense above.*

### Conventions
- UI is built programmatically in `_ready()` — no editor scene wiring. Keeps everything diffable and reviewable in code.
- **All UI sizes come from `UITheme`** (`font()`, `title_font()`, `sep()`, `card_size()`, `px()`), never hardcoded pixels. The layout is designed at a fixed 1280x720 and the engine's `canvas_items` stretch scales the whole canvas to the window, so nothing reflows (D65). Game starts fullscreen; `F11` toggles it, `Esc` leaves it. There is no live rescale and no scale setting — `UI_SCALE` is `1.0` and nothing varies it.
- **Rules in the engine, numbers in Balance, UI in the scene.** Combat scripts must not contain tuning constants or rules logic — otherwise the simulator stops predicting the real game.
- Cards are `.tres` data files; adding a card = new file + entry in `MetaState.CATALOG`.
- Any script a headless `--script` test loads directly must fetch autoloads via `get_node_or_null("/root/MetaState")`, not the global identifier (globals aren't registered in `--script` mode).

---

## 4. Design decisions

### Resolved (all cheap to flip)
- **D1 — Reward destination.** In-run card rewards go to the **persistent collection AND** the current run deck. Immediate gratification plus permanent accumulation.
- **D2 — Fusion model.** Copies of a card share one level. Fusing spends **copies and gold** to raise level by 1, and both prices rise with the level being bought (`Balance.fuse_copy_cost` / `fuse_gold_cost`). Three-way tension: keep copies (deck width / more draws), keep gold (the next shop), or fuse (per-card power).
- **D12 — No-softlock floor.** Both fusion and the death penalty could drive the collection below the
  minimum legal deck, stranding the player permanently (a fresh 8-card save could reach it with a
  single fuse). The fix is structural rather than a tuned number: `MIN_KEEP` is now *derived* from
  `MIN_DECK_SIZE`, and fusion checks the post-spend total. See "Invariant: no unrecoverable states".

- **D3 — Death semantics.** Death wipes the run and applies a penalty scaled by the dungeon tier died in: lose a **fraction of gold** (`clamp(0.25 + 0.1·(tier−1), 0.25, 0.8)`) and **`tier` random card copies** from the collection. Safety floors: collection never drops below `MIN_KEEP` (5) copies, and the last attack card is never stripped. Gold is earned per combat win (tier/dungeon-scaled: elite ×2, boss ×4). This makes runs risky without being unrecoverable.

- **D4 — Deck construction.** Per-dungeon decks. At each dungeon entry a deck-builder screen assembles a run deck from owned cards (up to `count` copies of each, at their fused level), with named loadouts saved persistently in `MetaState.decks` and reused across dungeons. Minimum deck size `MIN_DECK_SIZE` (8). Rewards still permanently grow the collection mid-run; each dungeon you re-pick from the collection. Boss clear and death both return to the builder.

- **D5 — Power curve & scaling.** Enemies scale against **deck power per energy** (`Balance.power_ratio`), not deck size or raw card totals, because energy is the binding constraint on player throughput. Consequences, all deliberate: a bigger deck of the same cards is more *consistent* but not stronger; an expensive card only helps if it beats the cost-efficiency curve; fusing raises the ratio and enemies keep pace. `HP_POWER_K` keeps fight *length* roughly constant as decks improve, and `DMG_POWER_K` cannot lag too far behind it or progressed decks become invulnerable. **The two values are not restated here** — they have moved four times since this was written (most recently in D109's level-curve rework, which shifted the whole difficulty axis) and a number copied into prose is a number that goes stale silently. Read them from `scripts/balance.gd`, where each carries the measurement that set it; `HP_POWER_K_HIGH` was added later still, because power above the floor needed a second slope or more power made the game *easier* at the top. All tuning lives in `balance.gd`; rules live in `scripts/combat_engine.gd`; both are exercised by the simulator so the game and the tuning model cannot drift.

- **D7 — Block lifetime.** Block absorbs the incoming hit and then **expires at the start of the next turn**, so defence is a per-turn decision rather than an accumulating wall. The legendary **Barricade** removes the expiry, turning block into a resource that compounds across turns — the payoff for a rare card, and the reason `retain_block` is modelled as a persistent combatant flag rather than a card effect applied once.

- **D18 — Rarity means two things.** With 100 cards, rarity has to be defined, not felt. It governs
  *power* and *growth*, and the second one was inverted: level caps derive from drop weight (common
  100, legendary 5), so a single flat gain made a maxed common reach 3.5x while a maxed
  legendary reached 1.5x — grinding commons beat every legendary. The fix was to scale gain against
  track length so the maxed multiplier *ascends* with rarity rather than inverting.

  *(The constant that did it, `LEVEL_GAIN_BY_RARITY`, was replaced in D109 by
  `LEVEL_RATE_BY_RARITY` and a per-card budget spread across the track. The invariant is
  unchanged and still asserted — a maxed legendary must out-multiply a maxed common.)*

  Design rules per tier, enforced by `tests/test_rarity.gd`:

  | Rarity | Count | Role | Growth |
  |---|---|---|---|
  | Common | 32 | one simple number, no rider | 100 levels do the work |
  | Uncommon | 28 | two effects, or a good rate | 40 levels |
  | Rare | 22 | enables a build | 15 levels |
  | Epic | 12 | large swing, usually paid for | 5 levels, steep gain |
  | Legendary | 6 | changes a rule for the combat | 5 levels, steepest |

  Both ladders are asserted: average power per energy among *repeatable* cards (one-shots cannot be
  rate-compared, and legendaries are almost all one-shots), and average total power across every card.
  The test found real problems rather than confirming intent: two stat-identical card pairs, four epics
  priced *below* rares of the same cost, and three legendaries below epics — all fixed by changing the
  cards, not the assertion. Buff weights were then recalibrated against measured run completion after
  an initial repricing inflated buff decks' *priced* power without changing their real power, pushing
  enemy scaling past them (thorns builds fell 69% to 46%).

- **D17 — Card mechanics.** The card vocabulary went from 9 cards to **47** on ten new mechanics:
  multi-hit, AoE, exhaust, retain, poison (ignores Block, ticks at end of turn), thorns, Block-scaled
  damage, per-combat growth, healing and energy gain. Lineage is drawn from Slay the Spire, Monster
  Train, Hearthstone, Dicey Dungeons and Darkest Dungeon rather than one source.

  Every mechanic **must** be priced in `CardData.power_value()` or enemy scaling silently falls behind
  the player's options. Two pricings were measurably wrong on the first pass and were corrected against
  the simulator: poison was priced like immediate damage (it is back-loaded and wasted when a fight
  ends early → 3.0 to 2.0 per stack, poison builds 40% → 63%), and AoE was priced near
  "damage × enemies" when the average encounter holds only ~1.3 living enemies (1.6 to 1.35 ×,
  AoE builds 41% → 58%). Exhaust applies a 0.65 discount because one use per combat is a real cost.

- **D14 — Non-combat encounters.** Events are data (`EventData`) with 2-3 choices and *declarative*
  effects (HP flat/percent, gold, card gain/loss, relic, start-a-fight). Effects are applied centrally
  in `encounter.gd`, never inside the data, so run rules are enforced in one place: an event can never
  kill you (HP clamps at 1), never drive gold negative, and never remove a card below the collection
  floor that prevents softlocks. `tests/test_event.gd` additionally requires every event to offer at least
  one cost-free option — an event should be a decision, not a tax — and asserts `Traversal.Enc` stays
  in lockstep with `GameState.NodeType`, since combat routes on those raw values.

- **D13 — Pluggable traversal.** Traversal is a strategy per dungeon rather than one global model.
  The deck model's texture is deliberately the *inverse* of the graph's: the graph commits you to a
  route before you know what is on it, while the deck reveals each encounter and asks whether it is
  worth fighting (facing it earns the reward; avoiding it costs HP and forfeits the loot). Remaining
  counts are public so avoiding is a calculated risk, not a blind one. Traversals never touch run
  resources — the view pays the HP — which keeps them pure and simulator-drivable.

- **D6 — Dungeon identity.** A dungeon is a **place you choose**, not a depth counter: `DungeonData` owns its difficulty, enemy roster, card pool, exclusive cards and unlock gate. Consequences: an "exclusive" card is simply a card in exactly one pool (rewards *and* shop stock draw from the dungeon pool, so exclusivity actually holds); each place fights differently because the roster overrides the tier roster; and `reward_weights(tier, difficulty)` **tilts** rarity toward the top as difficulty rises rather than replacing the table, so a hard dungeon still drops commons but a deep boss reaches ~31% epic / ~13% legendary. Progression is now "clears" rather than depth: clearing marks the dungeon, unlocks the next gate, and grants permanent max HP. `DungeonSelect` is deliberately the seam the overworld replaces — a city node only needs to call `GameState.select_dungeon(id)`.

- **D11 — Relic scaling.** Relics are permanent power that never appears in `deck_power`, so they are folded into `power_ratio`: flat effects add (`flat_power() / RELIC_POWER_PER_RATIO`) while **energy and draw multiply** (`throughput_multiplier`). The split is the point — treating `+1 energy` as flat power undervalued it badly, because +1 of 3 energy is +33% of everything the deck does; the relic build measured 90% completion at a reported ratio of 2.34 until energy was made multiplicative (3.65). Relics remain deliberately **net-positive** after scaling — a relic build clears roughly one dungeon deeper than the same deck without them, which is the intended role of a progression axis; the scaling only stops them trivializing the curve. Relics survive death because they are the *character* axis, while the card collection and gold are what a run risks (D3).

- **D10 — Archetype budgeting.** An archetype declares *shares* (`hp_mult`, `dmg_mult`) of the tier's budget rather than absolute stats, and a group splits one budget instead of multiplying it — so adding an enemy can never silently change difficulty, and retuning `Balance` retunes every archetype at once. Utility turns (defend/empower/debuff) are offset by `damage_compensation()` = `sqrt(1/attack_frequency)`: a **partial** offset on purpose, because a Vulnerable or Empower turn is deferred-and-amplified damage rather than lost damage. Group encounters add a small premium (`MULTI_*_PREMIUM`) since focus-firing removes a share of incoming damage with every kill.

- **D9 — Shop pricing.** Card prices derive from drop weight like upgrade caps, but by **sqrt** rather than linearly: `SHOP_BASE_PRICE · sqrt(common_weight / weight)` → common 40g, uncommon 63g, rare 103g, epic 179g, legendary 400g. Linear derivation priced a legendary near 4000g — roughly 20 runs of income, which reads as unobtainable rather than aspirational. A run yields ~135g, so a legendary is ~3 runs of saving. Healing is sold as a fraction of max HP priced per point restored, deliberately partial so it competes with card purchases instead of trivializing attrition.

- **D8 — Upgrade ceiling.** Each card has a max level by rarity: **common 100**, uncommon 40, rare 15, epic 5, legendary 5. Derived, not hand-picked: giving each rarity a track proportional to its drop weight (`WEIGHTS[NORMAL]` = 100/40/15/5/1) makes every rarity cost roughly the same hoarding effort, floored at `MIN_MAX_LEVEL` (5) so even a legendary is worth fusing. Prices for a level live only in `Balance.fuse_copy_cost` / `fuse_gold_cost` — a maxed common now costs **862 copies**, not 199.

  Level scaling had to become **sub-linear** for this to work at all: the old linear `+3/level` would put a maxed Strike at ~300 damage, far beyond anything `power_ratio` can scale enemies to, collapsing the curve. Consequence worth remembering: **Lv2 is early-game on a 100-level track**, so "mid progression" means roughly Lv15 and deep play Lv40.

  **Superseded by D109.** The sqrt curve (`LEVEL_GAIN` 0.25) that first solved this was *shape*-correct and step-wrong: rounding ate 77% of every individual level-up, so most levels cost gold and copies and bought the player nothing, and eight cards changed at no level at all. `LEVEL_GAIN` and `LEVEL_GAIN_BY_RARITY` are gone; `CardData` now spends a per-card budget across the track (`_headline_budget` / `_spread`, front-loaded by `FRONTLOAD_EXP`) so that **every** step moves a number. `tests/test_levels.gd` walks all 3,859 of them. Read D109 before touching any of it — the analytic retune that came first satisfied every predicate in `test_balance.gd` and turned the game into a walkover.

### Open

*This heading held a verbatim second copy of D18, D17, D14 and D13 from "Resolved"
above — an editing accident, not four re-opened questions. All four are resolved, and
the copy is deleted rather than kept: two statements of one decision drift, and the
reader cannot tell which is current. D6's stub here ("how are exclusive cards
declared?") is answered in its own Resolved entry: a card is exclusive by being in
exactly one dungeon pool, with no tag and no table.*

What is actually open is one thing, and it is the largest item in the plan:

- **The open world.** Cities, NPCs and quests that hand out relics — Phase 10, `[ ]`,
  deliberately deferred last because it is the expensive, peripheral system and every
  city and quest is bespoke. The seam it needs already exists: a city node only has to
  call `GameState.select_dungeon(id)`.

---

## 5. Implementation plan

### Phase 0 — Environment `[x]`
- [x] Nix flake dev shell with Godot 4 (`godot4` / nixpkgs `godot`)
- [x] Godot 4.7.1 runs; headless import/boot validated
- [x] `run.sh` fallback launcher (bypasses dev shell when store is inconsistent)

### Phase 1 — Combat core `[x]`
- [x] `CardData` Resource with level-scaling hooks
- [x] `Combatant` HP/block
- [x] Turn loop: draw 5, energy 3, play cards, block, enemy intent, end turn
- [x] Draw pile reshuffles from discard
- [x] Win / lose resolution
- [x] Starter cards (Strike, Defend)

### Phase 2 — Reward `[x]`
- [x] Victory → pick 1-of-3
- [x] `rarity` field on cards; weighted offer (no duplicate offers per screen)
- [x] Skip option
- [x] Reward cards (Bash, Iron Wave, Clear Mind)
- [x] Reward rarity biased by encounter tier (normal/elite/boss weight tables)

### Phase 3 — Encounter map `[x]`
- [x] `GameState` autoload for cross-scene run state
- [x] Layered node-graph generator (6 rows, weighted types) with guaranteed connectivity
- [x] Node types: Combat / Elite / Rest / Boss
- [x] Reachability gating; map rendering; scene routing to combat
- [x] Rest heals inline; boss clear → next dungeon, heal, fresh map
- [x] Enemy HP + intent scale by node type and dungeon tier
- [x] HP persists across fights within a run
- [x] Connectivity regression test (`tests/test_map.gd`, 50 trials — folded into `test_traversal.gd`, and the graph model it covered was deleted in D94)

### Phase 4 — Meta layer `[x]`
- [x] `MetaState` autoload, persistent, `user://save.json`
- [x] Collection model `id→{count,level}`, card `CATALOG`
- [x] Card `id` field; JSON save/load with int coercion
- [x] Fusion (`can_fuse`/`fuse`, spend copies → +level)
- [x] Run deck built from collection
- [x] Reward writes to collection (D1)
- [x] Collection/fusion screen + map access button
- [x] Persistence + fusion + deck-build regression test (`tests/test_meta.gd`)

### Phase 5 — Run stakes & deckbuilding `[~]`
- [x] Gold currency in `MetaState` (persistent); earned per combat win, tier-scaled
- [x] Death penalty: lose gold fraction + `tier` card copies, scaled by dungeon (D3)
- [x] Safety floors: `MIN_KEEP` collection floor + last-attack guard
- [x] Gold shown on Map + Collection; loss summary shown on defeat
- [x] Death penalty regression test (`tests/test_death.gd`)
- [x] Per-dungeon deck builder (D4): select copies, save/load named loadouts, `MIN_DECK_SIZE`
- [x] Run flow rewired: boot / boss-clear / death → DeckBuilder → dungeon
- [x] Deck loadout regression test (`tests/test_deck.gd`)
- [x] `MAX_DECK_SIZE` (20) enforced in validation + shown in the builder
- [x] Balance extraction: `balance.gd` (all constants) + `combat_engine.gd` (pure rules); Combat scene reduced to UI
- [x] Headless balance simulator (`tools/sim_balance.gd`): greedy AI, full-dungeon runs with persistent HP
- [x] Curve tuned against measured data (D5); invariant test (`tests/test_balance.gd`)
- [ ] Gold sink (depends on Phase 8 shop)

### Phase 6 — Combat depth `[x]`
- [x] Status effects: Vulnerable (+50% taken), Weak (-25% dealt), Strength, Dexterity
- [x] Decaying debuffs vs. permanent buffs; status display in combat UI
- [x] **Block expires at end of turn** (absorbs the hit first), enforced in `Combatant.begin_turn()`
- [x] **Legendary `Barricade`**: block persists and accumulates across turns
- [x] Power cards (`Inflame`, `Footwork`) + debuff cards (`Bash` → Vulnerable, `Terrify` → Weak)
- [x] Elites/bosses apply debuffs periodically
- [x] **Per-turn damage escalation** so stalling is punished (see below)
- [x] `power_value()` so status/power cards feed enemy scaling
- [x] Status + block-lifetime regression test (`tests/test_status.gd`)
- [x] Enemy archetypes as data (`EnemyData` + `resources/enemies/*.tres`): Cultist, Brute, Hexer, Rat swarm, Warden
- [x] Cycling action patterns (attack / debuff / defend / empower), **telegraphed as intent**
- [x] Multi-enemy encounters: group shares one HP+damage budget (`MULTI_*_PREMIUM`)
- [x] Player targeting (click an enemy); auto-retarget on kill; win only when all die
- [x] Per-archetype rosters by tier (`Balance.ROSTER`)
- [x] Archetype regression test (`tests/test_enemy.gd`)

### Phase 7 — Relics `[x]`
- [x] `RelicData` Resource + 7 relics (`resources/relics/*.tres`)
- [x] Effect hooks: max HP, combat-start block/strength/dexterity, per-turn energy/draw, post-victory heal, gold %
- [x] Relic ownership in `MetaState`, persisted, **never lost on death** (distinct from cards/gold)
- [x] Granted on boss clear, rarity-weighted from the unowned pool
- [x] Folded into `power_ratio` so relic power raises enemy scaling (D11)
- [x] Shown on Map (count) and Deck Builder (full list + "NEW RELIC" banner)
- [x] Relic regression test (`tests/test_relic.gd`)

### Phase 8 — Map variety `[~]`
- [x] Shop nodes: 3 rolled card offers + a healing purchase, priced from `Balance`
- [x] `MetaState.spend_gold()` with affordability guards; gold now has a sink
- [x] Bought cards enter the collection **and** the run deck (matches reward semantics D1)
- [x] Inventory rolled per visit and held in run state, so re-entering cannot reroll it
- [x] Node-type chances moved into `Balance` (`NODE_CHANCE_*`); ~1.4 shops/map
- [x] Shop regression test (`tests/test_shop.gd`)
- [ ] Event nodes (choices with consequences)
- [ ] Treasure nodes

### Phase 11 — Build goals and content depth `[x]`
- [x] `BuildData` + 7 archetypes; defining cards scattered across dungeons/zones
- [x] Gating enforced by `tests/test_build.gd` (3+ dungeons, 2+ zones, no single-place completion)
- [x] Builds screen showing progress and where missing cards live
- [x] Dungeons 7 → 12 across 5 zones; enemies 20 → 28
- [x] Bulk fusion (`fuse_many`), CC0 placeholder icons with rarity colouring

### Phase 9 — Dungeon identity `[x]`
- [x] `DungeonData` Resource + 4 dungeons (Crypt, Warrens, Foundry, Sunken Vault)
- [x] Per-dungeon card pools driving both rewards and shop stock; exclusive cards
- [x] Per-dungeon enemy rosters (roster override in `CombatEngine`)
- [x] Rarity tilt by difficulty (`Balance.reward_weights`)
- [x] `DungeonSelect` entry screen with unlock gates and "only here" callouts
- [x] Clears tracked in `MetaState` (persistent), driving unlocks + permanent max HP
- [x] Dungeon regression test (`tests/test_dungeon.gd`)

### Phase 10 — Open world `[ ]` (largest, deferred)
- [ ] Overworld traversal (2D/2.5D), node-to-node or free movement
- [ ] Cities as scenes; NPCs with dialogue
- [ ] Quest system + state tracking, persisted alongside meta
- [ ] Quest-granted relics; world unlocks

---

## 6. Testing

Headless regression tests, run with the Godot binary directly:

```
godot --headless --import
godot --headless --script tests/test_traversal.gd # the traversal contract, per model
godot --headless --script tests/test_meta.gd   # persistence + fusion + deck build
godot --headless --script tests/test_death.gd  # death penalty: gold+card loss, floors, guards
godot --headless --script tests/test_deck.gd    # deck loadouts: validation, clamp, build, persistence
godot --headless --script tests/test_balance.gd # scaling invariants (see below)
godot --headless --script tests/test_status.gd  # status effects + block expiry/Barricade retention
godot --headless --script tests/test_upgrade.gd # level caps by rarity + sub-linear growth
godot --headless --script tests/test_shop.gd    # shop pricing, spend guards, node generation
godot --headless --script tests/test_enemy.gd   # archetypes, patterns, group budget, targeting
godot --headless --script tests/test_relic.gd   # relic ownership, persistence, scaling, effects
godot --headless --script tests/test_softlock.gd # fuzz: a legal deck is always buildable
godot --headless --script tests/test_dungeon.gd  # dungeon defs, unlocks, exclusives, loot tilt
godot --headless --script tests/test_traversal.gd # traversal contract, applied to every model
godot --headless --script tests/test_event.gd    # events well-formed, treasure sane, enums aligned
godot --headless --script tests/test_mechanics.gd # every card mechanic + every card is priced
godot --headless --script tests/test_rarity.gd   # rarity ladders, duplicates, obtainability
godot --headless --script tests/test_flow.gd     # scene refs resolve, settings, save slots
godot --headless --script tests/test_escrow.gd   # run earnings held, forfeited, committed
godot --headless --script tests/test_resume.gd   # traversal + combat round-trip identity
godot --headless --script tests/test_save.gd     # versioning, migration, corruption handling
godot --headless --quit-after 60          # clean-boot smoke test (boots DeckBuilder)
```

All currently passing. Add a test per new system with non-trivial logic (relics, events).

### Block is priced below damage (D28)

An "endgame" profile measured *worse* than a weaker one (51% vs 73% at the final dungeon). Chasing it
found two separate things, and it is worth keeping both straight:

**Mostly my benchmark was unfair.** The two profiles were different decks, not the same deck at
different strength — the "endgame" one had four card types instead of six, no Vulnerable, and a lower
damage share. Comparing the *same* deck at Lv40 vs Lv100 with a superset of relics gives 83% → 98%, so
scaling is monotonic and the game rewards composition rather than raw numbers.

**But it did expose a real model flaw.** `power_value` priced Block equally with damage. Damage does
double duty — it removes enemy HP *and* thereby shortens the fight, which prevents damage in turn —
while Block only mitigates, and escalation makes a longer fight strictly worse. So a block-heavy deck was
charged enemy scaling for power that never shortened a fight, then bled out: measured 11.9 turns and 60%
HP lost, against 8.0 turns and 46% for the lighter deck.

`CardData.BLOCK_VALUE` (0.65) now weights Block below damage, and `BASELINE_CARD_POWER` was recomputed
(5.5 → 4.625) so the reference deck still sits at ratio 1.0. `tests/test_balance.gd` asserts that adding Block
raises the ratio *less* than adding the same amount of damage, and that levelling a deck or adding a
relic always raises it.

This is the third time the same lesson has appeared: **priced power must equal delivered power.** Total
deck power punished large decks, per-card power punished expensive cards, and now equal block pricing
punished defensive ones.

### First hour, and last (D27)

Six problems the playthrough surfaced, fixed together because they are one problem: the player never met
the interesting decision.

**Starting kits.** A fresh save was 4 Strike + 4 Defend — *exactly* the minimum legal deck — so run 1
had no deckbuilding choice, and fusion stayed hidden until ~10 copies had accumulated. Now the game
opens on a choice of three 12-card kits (Blade / Wall / Cunning), each leaning toward a different
archetype. One change fixes three things: the first decision becomes the decision the game is about, the
deck builder has slack, and 3+ copies of something means **fusion is live on run 1**.

**Three opening dungeons instead of one.** All Barrows gates are now 0, and the three differ in
traversal model *and* which builds they gate — so the opening asks "which archetype, and which way of
exploring?" rather than "press the only button".

**Onboarding, in three layers.** `Icons.card_tooltip()` generates a plain-English reading of any card
**from its data**, so tooltips cannot drift from the rules and new cards need no writing. A Glossary
screen explains every mechanic, also generated from `Balance` so the numbers it quotes are the real
ones. `MetaState.hint_once()` fires a one-line explanation the first time the player meets a system.

**An ending.** Clearing the final dungeon opens a victory screen with completion figures, then offers
**Ascension**: the collection and relics are kept, the world re-locks, and every enemy scales by
`ASCENSION_STEP` while loot tilts richer. Difficulty the player opts into, so 100 cards have somewhere
to go.

**The deep end was free — and the cause was a guard rail.** Fully-equipped late decks pinned
`POWER_RATIO_CAP` and cleared the deepest dungeons 100% of the time. A *hard* cap is itself a
power-creep bug: past it, every further point of player power costs nothing. `soften_ratio()` now
continues scaling on a square-root tail, so enemies keep pace forever without running away. The Maw went
from 100% to 51-73% for late decks, while early-game numbers did not move.

### A duplicated lookup table made the first dungeon unplayable (D34)

The follow-up report — *"I see different paths but still cannot click any of them"* — was a different
bug, and the real one.

`map.gd` kept its **own** `TYPE_LABEL` dictionary with five entries. Encounters had since grown to seven
(Event, Treasure). Rendering an Event node threw `Invalid access to key '5'` **in the middle of the
render loop**, so every row after it was never created — and since the map draws top-down from the boss,
the row that was lost was row 0: the only actionable one. Zero enabled buttons, no error visible to the
player.

The shared table (`Balance.NODE_LABEL`) was complete, and `tests/test_event.gd` already asserted it covered
every encounter kind. **The test was checking the shared constant; the crash was in a private copy of
it.** Duplicated lookups escape the tests written for the original.

Fixed by deleting the private table and reading `Balance.NODE_LABEL` with a fallback. `tests/test_layout.gd`
now fails if any screen declares its own encounter-label table, and checks that every encounter kind a
real generated map can contain has a shared label. That assertion was verified by reintroducing the bug
and watching it fail.

Worth noting how it was found: not by reasoning, but by instantiating the actual scene in a headless run
(`tools/debug_map.gd`) with the player's own save loaded, and dumping the button states. The scene had
been "booting cleanly" in every check the whole time, because a mid-`_ready` exception still leaves a
scene that loads.

### Actionable content must be on screen (D33)

Reported from play: *"I'm in the Crypt, I can only see a boss and an elite, and I can't press
anything."* Nothing was broken in the map — it renders the boss at the top and the entrance at the
bottom, and at nine rows and the default 1.6 UI scale that is **826 px of map in a 720 px window**, with
the scroll parked at the top. The only pressable row began ~740 px down, off screen.

Two changes that were each correct on their own combined into it: rows became *derived* from the
encounter budget (6 → 9), and the default UI scale went to 1.6. Neither was ever checked against the
window.

Fixed by scrolling to the actionable row on entry and after every step, marking reachable nodes with a
`▶` and a highlighted frame, dimming cleared and unreachable ones, and removing the raw edge indices
(`→[0, 1]`) that were being printed at the player. The dice board had the same problem sideways — a
17-space track is 1523 px wide in a 1280 px window — so it now scrolls to keep the token centred.

`tests/test_layout.gd` exists because **every earlier check only asked whether a scene booted**. Booting is
not playability. It computes rendered extents against the window at the shipped scale and requires a
scroll-to-focus wherever content overflows, walks every traversal in every dungeon asserting no state is
ever left with nothing pressable, and greps for debug text leaking into player-facing labels.

A related note for anyone writing tests here: UI scripts reference autoloads, which do not exist in a
headless `--script` run, so they cannot be instantiated in a test — inspect their source instead.

### Playing it (D26)

`tools/playthrough.gd` drives the real classes the way a player would — new save, pick a dungeon, build a
deck, traverse, fight, take rewards, clear, repeat — and reports friction rather than pass/fail. It is a
**diagnostic, not a test**, and it took three corrections before its output was worth trusting:

1. its combat policy blocked only at a 45% threshold and died in the first dungeon — a weak driver makes
   a diagnostic lie;
2. it picked the first available route every time, so it never steered toward a Rest;
3. it reported **one run** where the simulator uses hundreds — a single sample is not a measurement.

Lesson worth keeping: a harness is only evidence if its driver is at least as competent as the thing it
is judging. Its absolute numbers still read pessimistic on branching-map dungeons, so it is used for
*structure* (is there a goal? is a choice real?) and the simulator is used for balance.

What it found, all real:
- **The first dungeon was harder than the two after it** (79% vs 89%/100%) — an inversion at the most
  sensitive point in the game, caused by a 1.1-damage archetype and a 2-3 group in the opening roster.
  Softened; now 94%.
- **No build was completable before 6-8 clears**, so the whole early and mid game had no achievable
  goal. Builds are now tiered: 2 / 3 / 4 / 4 / 6 / 6 / 8 clears.
- **Roster threat overrode difficulty ratings.** Now measurable via `Balance.roster_threat` and bounded
  by a test: a sane band, spread under 1.6x, and the opening dungeon at or below average threat.
- Friction it flagged and I did *not* fix, because they are design calls: the first dungeon choice is
  forced, the starter deck is exactly the legal minimum (so run 1 has no deckbuilding decision), and
  fusion is invisible until ~10 copies of something have accumulated.

### Balance workflow (D5)

Balance is *measured*, not guessed:

```
godot --headless --script tools/sim_balance.gd
```

A greedy AI plays complete dungeon runs (persistent HP, real generated maps, rest nodes) across
representative deck profiles — starter, early, mid-fusion, max-deck — and reports **run completion
rate** per dungeon depth, plus per-fight diagnostics and where deaths cluster.

Run completion is the metric that matters; single-fight win rates at full HP overstate survivability
because the real pressure is attrition across a path. Tune constants in `balance.gd`, re-run, repeat.

**Turtling was a dominant strategy (structural, not a tuning issue).** Block costs ~5 per energy and
enemies hit for less than the 3-energy block budget, so a player could neutralize every hit and win
slowly at zero risk — and no value of any single constant fixes that, because stalling had no cost.
Fixed with `ESCALATION_PER_TURN`: enemy damage grows each turn (capped by `ESCALATION_MAX`). The cap is
load-bearing — stronger decks face more enemy HP and therefore longer fights, so uncapped escalation
punished progression. Enemy HP is now *derived* from `TARGET_NORMAL_TURNS` and `OFFENSE_SHARE` rather
than being a magic number, so pacing stays put when other constants move.

Profiles are keyed to the 100-level upgrade track (D8): Lv1 starter/early, Lv15 mid, Lv40 deep,
Lv100 maxed. Measured progression: Lv1 clears D1 (~70%), Lv15 clears D3 (~88%) and D4 (~61%),
Lv40 clears D5 (~58%) through D7 (~15%), Lv100 clears D8 (~78%) and reaches D10 (~26%) — the long
grind buys real depth access. A maxed common deck sits at ratio ~4.0 against a `POWER_RATIO_CAP` of
4.5, so enemies still scale at the ceiling.

Older shape (pre-upgrade-caps): each profile cleared its matched dungeon ~50-78% and its next-deeper "stretch" dungeon
~14-47%; deaths cluster on the boss row. Normal fights cost ~5-27% HP, elites ~28-50%, bosses ~43-64%,
so attrition across a path is the real pressure.

**Attrition bug (found in play, not by the sim's win rates).** Enemies were dying in 2 turns, so they
only ever attacked once (an enemy never acts on the turn it dies); one hit of ~7 minus a 5-block Defend
meant ~3 HP lost per fight, while a Rest healed 18 — HP effectively never moved. The sim had *printed*
the tell (`N 100% (2.3t)`) but reported only win rates, so it read as "fine". Fixes: enemy base HP
raised so fights last 4+ turns (`MIN_FIGHT_TURNS`), `REST_HEAL_FRAC` cut to 0.18, and the report now
prints **HP lost per fight** — a near-zero value there means attrition is broken regardless of win rate.

Lessons already paid for, encoded as invariants in `tests/test_balance.gd`:
- Scaling on *total* deck power punished bigger decks (throughput is energy-capped) → scale per energy.
- Scaling per *card* punished expensive cards → divide by cost, not count.
- Letting incoming damage scale slower than block made progressed decks invulnerable → keep
  `DMG_POWER_K` near `HP_POWER_K`.
- A greedy "highest damage" AI misplays cost-inefficient cards, which reads as a balance problem but
  is not — the sim policy picks by value per energy.
- A "block only when the hit would kill" AI takes near-maximum damage and made attrition look brutal;
  the policy now blocks whenever a hit is a meaningful chunk of HP, like a competent player.
- Fights shorter than ~3 turns silently delete attrition from the entire game (see above).
- Action patterns silently nerfed enemies: a utility turn is a turn not attacking, so introducing
  archetypes cut total damage ~40% and pushed completion from 62% to 92%. Compensating *fully* for it
  then over-corrected to 7%, because utility turns amplify later damage rather than losing it. Partial
  (sqrt) compensation landed it. Any enemy ability that changes how often they attack needs this.
- A pure-debuff card (no damage, no block) was never played at all, because card selection ranked by
  damage/block per energy — making a whole build look 4x weaker than it was (13% -> 50% once fixed).
  Any new *category* of card needs matching policy, or the sim silently under-rates decks using it.
- Over-valuing an effect in `power_value()` backfires: it raises enemy damage via `power_ratio`, so an
  offense-heavy deck gets punished with damage it has no block to answer.

---

## 7. Known issues / environment

- **Dev shell store corruption.** During development `nix develop` began erroring with a missing `mes-libc-...-builder.drv` — a garbage-collected leaf `.drv` while `keep-derivations` held its parent. Not a code or flake bug. Fix (root): `sudo nix-store --verify --check-contents --repair`. Meanwhile `run.sh` launches the realized Godot output directly.
- **`run.sh` pins a store path** — intentional temporary bridge; remove after the repair and use `nix develop` normally.

---

## 8. Changelog

- **The simulator was spending its life in ResourceLoader (D76).** The full report had stopped finishing — 32 minutes and abandoned — so D72 was tuned at reduced precision. Profiled rather than guessed: a single reward roll cost ten times an entire simulated fight, because every content accessor (`dungeon()`, `zone_of()`, and the card pool built from them) did a `load()` per call, and the reward screen in the *game* did the same on every victory. Caching those, building the reward table once per dungeon, and memoising `power_value()` per level cut the report to a fraction of its runtime. The tool now prints where its own time goes.

- **A tuning pass on a corrected instrument (D75).** Everything tuned before D72 was set against a simulator that modelled a weaker player than the game provides. Re-tuned: the Abyssal Stair no longer out-punishes the Maw a full depth below it, mid-game ceilings now sit above the decks that visit them (so a matched deck is no longer pinned where enemies stop scaling), and relics are priced 40% higher after a relic deck out-cleared two stronger-looking ones at the same dungeon. `DMG_POWER_K` was tried as a global lever and rejected with numbers — it crushed the already-hard cells to fix the soft ones.

- **A fourth way to walk a dungeon: an isometric floor (D74).** From play, and not as a bug report: the graph model is the best of the three and that is the problem, because it is the one that reads most like the game this one stands next to. All three existing models abstract a *route*; none of them is a *place*. `TraversalIso` carves a floor of rooms out of a 6x6 plate, lights the room you stand in and its neighbours, and hides the stair down — so the run is a question of coverage, not of route. The torch pays for one tidy tour and every step past it costs HP, which is the mirror of the deck model's priced dodge: there you pay to see less of a dungeon, here you pay to see more. It walks the same encounter budget as the other three (9.2 against 9.2), the contract test caught a pacing deadlock that only fired 3 runs in 360, and it is plugged into the Warrens so the three opening dungeons teach three different models. **The torch did not survive contact with play — see D77.**

- **The floor became a place, and the torch was deleted (D77).** Also from play: no real empty tiles, monsters that do not move, and a wish for bigger spaces. The torch turned out to be a step allowance with an HP overdraft fee that never changed what the player could see, and — fatally — `rooms × 1.4` meant a bigger floor granted proportionally more steps, so growing the floor would have deleted the mechanic anyway. It charged the player for looking around, which is the one thing this model exists to sell. Gone. The floor is now ~30 tiles for a nine-encounter budget with encounters placed by farthest-point spreading, the plate is 12x12 behind a camera that centres on you, and part of the combat budget **walks** — wanderers that step when you step and hunt inside five tiles. Greed is priced on exposure rather than on walking, and being caught costs HP a careful player can avoid. Same budget as the other three (9.2 against 9.2); the mobile content re-created D74's deadlock twice at the same 3-in-360 rate; and the simulator was caught measuring a drunkard's walk, which had been reporting the floor as a flat 72% for every deck in the report.

- **The floor got painted, and most of the work was not drawing (D78).** Four downloaded packs became the iso floor's art. The "tiles" turned out to be seamless *top-down* materials, so the isometric projection is done in the renderer by mapping a diamond's corners to a unit square's — exact, not approximate. Every sprite turned out to be a small figure parked in a big empty canvas, so the installer trims to the alpha box, which makes the sprite anchor free (bottom-centre of a trimmed silhouette is where its feet are). Rock became a *block* with a lifted top and two lit faces, because a flat dark diamond reads as darker ground once the floor has texture; ground and standing art split into two passes so a floor row could not slice the legs off what stood behind it; and the player is drawn last over everything, because correct occlusion by a wall in front of them was realistic and unplayable. Wanderers are spiders and stationary combats are armoured brutes, so the floor says which kind of danger you are looking at before you read a word. Licence status of the packs is unknown and recorded rather than assumed — see `assets/art/iso/README.md`.

- **The floor became a building (D79).** Play report: 30 tiles still did not feel like exploring a dungeon — and the diagnosis was not size. Two thirds of the floor held literally nothing, there was no architecture (one organic blob, every tile the same width, nothing a *place*), and there was only ever one floor. So: rectangular chambers joined by corridors in a shape that differs per dungeon, **a room revealed whole the moment you enter it** while a corridor shows two steps, several smaller floors descended one way with the boss on the last, and treasure sealed in a dead-end vault whose key is across the floor. The pacing was settled by arithmetic BEFORE any of it was built, which killed two designs on paper (three big floors measured ~15 moves per encounter; round-tripping every floor cost ~8) and then caught a third in measurement — fixing the room count per style gave 53-tile floors and 8.6 moves per encounter, so the tile budget is now per DUNGEON and floor size falls as floor count rises. Landed at 6.9 against a ceiling of 7.5 that `tests/test_traversal.gd` now enforces, with the encounter budget still 9.2 against 9.2. Multiple floors needed nothing outside the traversal, because descending regenerates in place and `is_complete()` only fires on the last boss. The D74 deadlock arrived a third time, as the mirror of its own lesson: the exit has to be findable too.

- **Twelve painted rooms, and the filename is the wiring (D73).** Every dungeon has its own backdrop now, and the fourth instance in this log of a hand-typed list rotting next to the manifest that exists to prevent exactly that.

- **The simulator was measuring a weaker player than the game gives you (D72).** Reported from play as "the first dungeons feel easy and the sim disagrees" — and the sim was wrong four ways: max HP grew with the dungeon's difficulty instead of with dungeons cleared (60 HP where the player has 120), the equipped Power was never passed, the named boss was never passed so every finale was a roster enemy in a boss costume, and the deck never grew during a run. The opening now measures the way it plays, and `test_balance.gd` fails if the tool drops any of it again.

- **Elites drop relics, the mid-game plateau closed, and the last two art paths wired (D68, D69, D70).** An elite was a stat check; it now drops a relic, held in escrow so dying on purpose cannot bank it. The five-dungeon plateau in the middle turned out to be an incentive problem rather than a difficulty one — re-clearing a beaten dungeon was the safest income in the game — so repeat clears pay a fifth of what a first clear does, down to a floor. And the card-illustration and frame-kit files finally have code that looks for them, after finding that the art manifest had been generating filenames from its own private copy of the card taxonomy.

- **Cards that read the fight, and dungeons with their own shapes (D66, D67).** Not one card in the game was conditional — no "for each", no "if you played" — so a turn was arithmetic and a deck never became an engine; six mechanics now let a build's cards multiply each other. And every dungeon drew from one global encounter mix, so twelve dungeons had one rhythm; the mix is per-place now (a swarm, a market, a climb, a treasure run). Both were measured, and both needed correcting: the card pricing was under-charging builds by half, and the first pass at shapes turned the deepest dungeons into six-fight gauntlets on top of their difficulty.

- **The UI scale was a second scale (D65).** Removed the zoom — keys, slider, persisted value and setters. The engine's `canvas_items` stretch already scales the whole canvas to the window (measured: a 640x360 window and a 1920x1080 one both present 1280x720 layout units), so the app-level multiplier was a duplicate that had already caused three separate incidents. F11 still toggles fullscreen; nothing else resizes.

- **The horizon is not the standing line (D64).** Enemies stood on the backdrop's wall/floor junction, which in one-point perspective is the *far end* of the corridor — so they read as small and distant. Split into `HORIZON_LINE` (what the painting does) and `STAND_LINE` (where feet go, nearer the viewer, clamped clear of the hand), and grew them to match. Also gave D63's four layout bugs their tests: three were already covered by the new geometry checks, the fourth — the entire HUD anchored off screen — was covered by nothing, and those checks turned out to be measuring a square 1280x1280 window rather than the shipped 720.

- **The bottom of the screen, laid out properly (D63).** Vitals back at the bottom-left beside the hand, the hand itself a fan of overlapping tilted cards that straighten and lift when hovered, the power a round sigil and End Turn a small corner button instead of two full-width bars. Four layout bugs on the way, three of them invisible to the existing suite — including a `Control` assigned to an `HBoxContainer`-typed variable, which GDScript rejects at runtime, so the hand silently never existed. `CardTextTest` now measures the hand's geometry.

- **The fight is framed head-on, and nobody plays the hero (D62).** Chose a frontal framing into the corridor the backdrops paint over the side-on arena the art brief assumed, which deleted four hero files and a whole class of consistency work. Measured the backdrops to find the shared standing line (68%), measured the old layout to prove the stage had to become a layer rather than a row (236px for a 240-270px sprite, ending 22px above the floor), and added the id-keyed enemy-art lookup plus a floor-line assertion so the coming art pass lands on a contract the game enforces.

- **The fight moves, and the dodge got priced (D60, D61).** Damage numbers, hit flashes, a screen jolt and cards that fly out of the hand — made possible by the real change underneath, which is that combat now updates its widgets instead of destroying and rebuilding them every action. Separately, the simulator's driver was taught to use the deck model's Avoid at all (it never had, in the model's whole existence), which immediately showed that skipping every fight beat fighting: 49% to 87% completion for one deck. The price now rises with depth and with each dodge taken.

- **The numbers behind three decisions (D58, D59).** A card now shows what it will do in *this fight* — Strength and Dexterity applied — on its face, its hover and in the engine that resolves it, after a play report that gaining Strength changed nothing visible. Alongside it: the draw and discard piles are on screen, unaffordable cards are dimmed, the combat log keeps four lines, dying gets a screen the player dismisses instead of a 2.5-second wait, and fusing states what a level buys rather than only what it costs.

- **The endgame stopped being a walkover (D54).** The deepest dungeons were cleared 100% of the time by every late deck, because enemy HP grows at half the rate of the player's damage — so more power made fights *shorter*, and a shorter fight offers fewer chances to be hit. Extra enemy HP and ratio-scaled pierce now switch on above a floor at the top of the build band, leaving every cell the previous pass tuned exactly where it was. The Maw now reads 40/49/70% by deck strength. The test changed probe: attrition per fight rose all through the plateau, so fight length is what is asserted.
- **Music, at last, on the Music bus (D53).** The bus and its slider existed with nothing routed to them. Five generated, measured, seamless loops now play, chosen by which screen the player is on from one table polled in one place, so a new screen cannot be silent by omission. Also fixed a third restated constant: `SettingsState` defaulted the UI scale to 1.6 and applied it over the theme's 1.0, so no new player ever got the shipped default.
- **A way out of the fight (D52).** Combat had no exit control and Escape only left fullscreen. Screens now declare their exit once, and the button and the key run the same Callable; combat seals it between the killing blow and the reward pick so the fight cannot be re-offered. Found a crash class while doing it: a static Callable outliving its screen corrupted the heap at shutdown and, because the output is piped, silently discarded three tests' PASS lines — the runner now checks exit codes too.

- **Phase 0–4 complete.** Environment, combat, reward, encounter map, and meta layer built and validated (headless tests green).
- **Phase 5 mostly done.** D3 (gold + death penalty) and D4 (per-dungeon deck builder with saved loadouts) resolved & implemented; run flow rewired through the DeckBuilder.
- **Unclickable map (D34).** The Crypt was unplayable because `map.gd` kept a private copy of the encounter-label table that had gone stale, throwing mid-render and destroying every row below it. Deleted the duplicate, and `tests/test_layout.gd` now rejects private copies of shared lookups — verified by reintroducing the bug.
- **Unreachable map rows (D33).** A play report — "I can't press anything in the Crypt" — turned out to be the actionable row rendering below the window at the shipped UI scale. Added scroll-to-focus on the map and the dice board, clearer reachable/cleared states, and `tests/test_layout.gd`, which measures rendered extents against the window because every previous check only verified that scenes *booted*.
- **Sound (D32).** 23 CC0 sounds wired to gameplay events, chosen from each card's real effects rather than registered per card. Added Music/SFX buses so the settings sliders stop being placeholders, plus a voice pool with pitch jitter. Tested for the failure mode that matters: silence is indistinguishable from intent, so every declared event must resolve to a real stream and the volume curve must genuinely mute.
- **Per-card illustrations (D31).** All 100 cards now carry distinct pixel art, sliced from a single CC0 spritesheet. Cards became layered widgets: arbitrary illustration behind at low opacity, the meaningful effect symbol in front. The test asserts every card has its own slice, that no two share one, and that every region lands inside the sheet.
- **Pixel backdrops (D30).** Every screen now tiles a seamless CC0 pixel pattern, tinted per zone. Tiles were chosen by scoring wrap error and internal contrast rather than by guessing, and the test bounds brightness/busyness/seams because a background that fights the UI text is worse than none.
- **Pixel art throughout (D29).** Replaced the vector placeholder icons with CC0 pixel packs for enemies and UI, and authored the thirteen meaning-carrying symbols by hand rather than guessing at unlabelled spritesheet tiles. Set nearest-neighbour filtering, made every enemy visually distinct (hashing had collapsed 28 enemies onto 17 sprites), and added `tests/test_art.gd` because both blurred filtering and missing textures are invisible in a headless run.
- **Block repriced (D28).** Investigated why a stronger deck won less, and found both an unfair benchmark (different composition, not more power) and a real flaw: Block was priced like damage even though only damage ends fights. Weighted Block to 0.65 with the baseline recomputed so the reference deck stays at 1.0; pinned by new assertions.
- **First hour and endgame (D27).** Starting kits (which also make fusion reachable on run 1), three opening dungeons instead of one, tooltips/glossary/first-time hints generated from the data, and an ending with Ascension. Fixed one more real bug while verifying the deep end: the hard `POWER_RATIO_CAP` made late-game power free, so the deepest dungeons cleared 100% of the time — scaling now continues on a diminishing tail. Three older tests were still asserting the old 8-card starter and now derive their expectations from the collection.
- **Played it, and fixed what that found (D26).** Added `tools/playthrough.gd`, which drives the real classes as a player would. It required three fixes to its own driver before its output was trustworthy, then found three real problems: the opening dungeon was harder than the next two, no build was completable before the endgame, and roster threat was silently overriding difficulty ratings. All three fixed, the last two pinned by new assertions in `tests/test_build.gd` and `tests/test_dungeon.gd`.
- **Builds gated behind dungeon clears (D25).** Archetypes are now data, with their defining cards scattered so no build can be farmed from one place; enforced by test, surfaced by a Builds screen. Dungeons 7 → 12 (5 zones), enemies 20 → 28. Measurement caught the compounding trap again and this time it was swept systematically: six group archetypes also applied debuffs, and several copies stacking Vulnerable every turn made a difficulty-4 dungeon harder than a difficulty-5 one. Group archetypes no longer debuff, and the rule is documented on the field.
- **Content pass and placeholder art (D24).** Enemies 5 → 20, relics 7 → 30, events 4 → 20, and CC0 Kenney icons wired through an `Icons` helper with rarity colouring. Added bulk fusion (`fuse_many` / `fusable_levels`) after noticing that maxing a common took 99 clicks — the grind belongs in earning copies, not in pressing a button. Two things the tests caught: an event with no cost-free option (a tax, not a decision), and a d7 roster of nothing but heavy hitters that measured 0% completion — a wall rather than a difficulty.
- **Incremental saves (D23).** Split the in-progress run into its own file and coalesced writes behind dirty flags with a forced flush at critical moments. A combat turn now costs 1 write of ~2.4 KB instead of 12 writes of ~3.8 KB, and the permanent save is untouched during combat. Also fixed a latent noise bug found while benchmarking: absolute `get_node()` lookups errored whenever an autoload script was instantiated outside the tree (which every headless test does).
- **Resumable runs (D22).** The run — and the fight in progress — are serialized into the save, so quitting is a pause rather than an escape, and force-quitting a losing fight is no longer a free retry. Each traversal model owns its own serialization; save format bumped to v3. `tests/test_resume.gd` asserts round-trip *identity* (same options, same board, same telegraphed damage), not merely that it loads.
- **Retreat is now an item, not a button (D21).** Removed free abandonment; leaving with your earnings costs an Escape Rope (found in treasures and from bosses, never sold). Also fixed a worse hole found while doing it: quitting to the title mid-run was a *silent* free abandon, since run state is not persisted — it now warns and forfeits explicitly. Save format bumped to v2 for consumables, with migration that grants existing saves a rope.
- **Run escrow closes the abandon exploit (D20).** Abandoning a dungeon kept every reward at zero cost, so skipping the boss was strictly optimal. Earnings are now escrowed and commit only on a boss kill; death and abandonment both forfeit them. D3's permanent card loss was halved in response, since losing the run is now the primary cost.
- **Menus, overworld, slots, settings (D19).** Added MainMenu, SaveSlots (3 independent slots), Settings (display real, audio placeholder), Overworld (zone travel), ZoneView, Relics and an in-run PauseMenu, plus a shared `UI` builder module. Retired `DungeonSelect` in favour of Overworld → ZoneView. `tests/test_flow.gd` guards navigation by scanning scene references. Hit the autoload trap once more: `settings_state.gd` referenced `UITheme` at compile time, which made it unloadable in headless `--script` runs.
- **100 cards with enforced rarity (D18).** Grew the set to exactly 100 across five tiers (32/28/22/12/6) and four new mechanics (HP cost, lifesteal, Strength-scaling, Block-doubling). Fixed inverted rarity scaling, two duplicate cards, and eleven mis-tiered cards. Recalibrated buff pricing against measured completion rather than intuition.
- **Save versioning, 47 cards, zones (D15-D17).** Added versioned saves with migration and backup; grew the card pool from 9 to 47 across ten new mechanics; added three dungeons (including a difficulty-7 endgame) and clustered everything into four themed zones so card availability is geographic. The simulator caught two mispriced mechanics (poison, AoE) and one repeat of a known trap: poison-only cards were invisible to the sim's card-selection policy, exactly as pure-debuff cards once were.
- **Dice board + non-combat encounters (D14).** Added a third traversal model (tabletop dice board: roll two dice, spend one, overshoot skips spaces) and two new encounter kinds (Event, Treasure) with four data-driven events. Fixing the budget contract exposed that the graph's row count was hardcoded and had to be derived from the encounter budget, and that a stochastic model can only honour the budget on average — the contract test now checks means.
- **Traversal made pluggable (D13).** Extracted the `Traversal` contract, ported the node graph behind it, and added a second model (dungeon-as-a-deck) selected per dungeon. The simulator now drives traversals directly, so one walker measures all models. Measurement then exposed that **archetype multipliers were swamping dungeon difficulty** (a roster of 1.35x hitters made difficulty 3 harder than difficulty 6); multipliers are now constrained to ~±20% and that constraint is documented on the field itself.
- **Phase 9 complete: dungeon identity.** Dungeons are now named, selectable places with their own rosters, card pools and unlock gates; loot rarity tilts with difficulty. Replaced the depth counter with clear-tracking, and made `DungeonSelect` the entry point so the overworld can slot in later. The test caught a real content error — a card listed as Crypt-exclusive also sat in the Foundry pool.
- **Softlock fix (D12).** Fusion and the death penalty could each shrink the collection below the smallest legal deck, permanently stranding the player — a fresh save reached it after one fuse. `MIN_KEEP` is now derived from `MIN_DECK_SIZE` and fusion validates the post-spend total; `tests/test_softlock.gd` fuzzes every sink to keep it that way.
- **Phase 7 complete: relics.** Seven relics as data, granted on boss clears, persisted and never lost on death. Effects span run setup, combat start, per turn, and rewards. Folded into enemy scaling (D11) after measurement showed a flat treatment of `+1 energy` undervalued it by roughly 1.3 ratio points.
- **Phase 6 complete: archetypes + multi-enemy.** Enemies are now data (`EnemyData` resources) with cycling, telegraphed action patterns; encounters can contain groups that split a single budget, with player targeting and auto-retarget. Elite win rates now vary 67-100% by archetype instead of a flat 100%. Two measurement traps handled: patterns quietly reducing damage output, and a status test that was non-deterministic because it spawned a random archetype (a killing blow wasted the card's rider effects).
- **Phase 8 (partial): shops.** Gold had been a dead currency — earned and lost on death with nothing to spend it on. Shop nodes now sell rolled cards and partial healing, with prices derived from drop weight (D9). Run completion rose ~5-15pp across all profiles, since shop nodes displace some fights and healing offsets attrition. The simulator models only the healing purchase: buying cards mid-run would mutate the deck a profile is meant to measure.
- **D8 upgrade caps.** Max level per card by rarity (common 100, derived from drop weight so each rarity costs comparable effort). Level scaling switched to sub-linear sqrt — mandatory, since linear scaling at level 100 produced ~300-damage cards that no enemy scaling could answer. Fusion now stops at the cap, UI shows `Lv X/max`, `POWER_RATIO_CAP` raised to 4.5 for headroom. Two older tests asserted the old linear numbers and now derive expectations from the card model instead.
- **Phase 6 (partial).** Status effects (Vulnerable/Weak/Strength/Dexterity), power and debuff cards, enemy debuffs for elites/bosses. Block expires at end of turn after absorbing the hit; the legendary **Barricade** makes it persist and accumulate. Added per-turn damage escalation after measurement showed defending was a dominant, risk-free strategy. `power_value()` keeps status cards inside the D5 scaling model. Remaining: enemy archetypes, multi-enemy encounters.
- **Attrition fix + presentation.** Fixed a balance bug reported from play: fights ended in 2 turns so the hero never lost meaningful HP (enemy HP too low, rest healing too high); the simulator now reports HP-lost-per-fight and `tests/test_balance.gd` asserts fights last long enough for attrition to exist. Added `ui_theme.gd`: fullscreen start and one-parameter UI scaling across all screens. Also guarded a latent crash when the Map scene is entered with no dungeon generated.
- **D5 resolved.** Combat rules extracted to `combat_engine.gd` and all tuning to `balance.gd`; added a headless run simulator and tuned the curve against measured completion rates. Fixed three real scaling bugs found by measurement (total-power scaling punished large decks; per-card scaling punished expensive cards; lagging damage scaling made late decks invulnerable). 6 test suites green. Remaining in Phase 5: gold sink (needs shops).

### Test isolation (learned the hard way)

Tests used to run against the player's real `save.json` / `settings.json`. One of
them wrote `ui_scale: 99.0`, which clamped to 3.0 and made every card enormous —
reported as a gameplay bug. A debug harness under `tools/` destroyed an
in-progress run the same way.

Three rules now enforce isolation:

* `MetaState.path_prefix` and `SettingsState.path_override` redirect every save
  path. Each test sets its own prefix; `tools/debug_map.gd` sets one too.
* `_cleanup_sandbox()` runs at both ends of a test — a leftover from a crashed
  run would otherwise be read as real state.
* `MetaState.writes_disabled` is set during teardown. A leaked instance still
  flushes when the engine frees it at exit, which re-created a sandbox file
  *after* cleanup deleted it; deleting alone was not enough.

### Tooltips must be hoverable, not just written

"Hovering a card in the collection should show what it does." The text was already
there — `Icons.card_tooltip()` generates a full effect breakdown from card data —
but it was assigned to `Label`s, and Label defaults to `MOUSE_FILTER_IGNORE`. The
mouse passed straight through, so the collection, deck builder, shop and four
status lines all shipped explanations no player could ever read.

`UI.hoverable(control, text)` now owns this: it sets the text and promotes the
control out of IGNORE. Card entries attach it to the **row**, not the label, so
hovering the art or the fuse buttons explains the card too — a child Button with no
tooltip of its own inherits the row's by walking up the tree.

`tests/TooltipTest.tscn` guards it. It is a scene rather than a `--script` test
because `mouse_filter` only exists on a built tree; it walks Collection, DeckBuilder
and Shop and fails on any control with tooltip text it cannot receive a hover for.
Verified by reintroducing the bug: 5 failures, one per card plus the coverage check.

### Cards must be able to say what they do

"Text of cards while playing in an encounter are overflowing and cannot be seen."
Cards rendered name, cost and rules text as one `Button.text` with `clip_text`, so
anything longer than the frame was cut off mid-word, and the frame was only 90px
tall to begin with.

The card interior is now laid out by hand — cost badge, effect symbol, title, rules
text — with **no containers inside the card**. A `VBox`/`HBox` honours its children's
*minimum* sizes, and an autowrapping Label's minimum width is one character: the
title got squeezed to 8px wide, wrapped to 441px tall, and pushed the description
clean off a 211px card. Badge widths are a share of the card's width, never its
height; sizing them off the header height drove the title's width negative on a
squeezed hand.

`UI.fit_label()` shrinks the font until the text fits, rather than clipping. It asks
the Label itself via `get_visible_line_count()`. Two attempts at *predicting* the
wrap with `Font.get_multiline_string_size()` were both wrong — it breaks only on
word boundaries while `AUTOWRAP_WORD_SMART` also breaks inside long words, and it
ignores the `line_spacing` theme constant — and each miss shipped as unreadable
text. Agreeing with the renderer's own measurement cannot drift.

Base card size is now 150x132 (was 140x90): at the old height the fit pass had to
shrink long descriptions past readability to make them fit.

**Hover to read.** Fitting a full description into a hand-sized card still drove the
wordiest card down to 12px. So a resting card shows only its **name and cost** — which
lets the name use the whole face at 35px — and hovering enlarges the card (x1.45,
growing from its bottom edge, since a hand sits along the bottom of the screen) and
reveals the rules text. Worst case is now 17px effective, and a typical card reads
36px name / 31px rules text while hovered.

`tests/CardTextTest.tscn` builds **all 100 cards** at the narrowest width a hand is
ever squeezed to, plus a real Combat scene, and drives both states. It fails on: a
label that clips, a label drawn outside its card's frame, rules text visible while
resting, rules text *not* revealed on hover, a card that does not grow or does not
shrink back, and any hovered text under 14px — shrink-to-fit must not "solve"
overflow by vanishing. Measured in local coordinates, because a hovered card is
scaled and global rects mix a scaled position with an unscaled size. Verified by
disabling the shrink: 235 failures.

### A fuzz test that cried wolf

`tests/test_softlock.gd` failed intermittently — roughly one run in five — reporting
"fuzz softlocked: total=21". It was wrong. Its `_can_build()` helper selected
*every* copy in the collection, so the moment a player owned 21 cards it exceeded
the 20-card deck cap and the test called that unrecoverable. In the game the player
simply leaves one card at home.

It surfaced rarely because it needed random draws to outrun random deaths. Two
changes: the helper now takes cards up to `MAX_DECK_SIZE`, and the fuzz runs from a
**fixed seed** with 200 trials instead of 40 random ones. A failure nobody can
reproduce is a failure nobody fixes.

Confirmed the relaxed check still has teeth by deleting the `MIN_KEEP` floor from
`penalize_death()`: four real softlocks, at every depth.

### D35 — Fusion was free power

"Fusing makes the user too strong too fast. Also gold should be required for fusing."

Fusing cost a **flat 2 copies** and **no gold**, so deck power grew linearly with
copies hoarded and nothing else gated it. Nothing competed with it either: gold had
only the shop to go to, and fusion had only copies to spend.

Two brakes, both in `Balance`:

* `fuse_copy_cost(level)` — 3 copies, +1 every 8 levels. The tail costs real
  hoarding instead of the same two cards forever.
* `fuse_gold_cost(rarity, level)` — `20 x sqrt(100/weight) x level^1.35`. The rarity
  multiplier is the shop's, so levelling a card is priced against buying one.

The gold exponent was **measured, not guessed**. A linear price was tried first and
a progression sim showed it stops mattering after about four runs: income scales
with dungeon depth, so a flat step per level becomes rounding error. Superlinear
keeps fusion competing with the shop all game.

Simulated twenty runs, old model vs new (greedy fusing, deck power ratio):

| run | old ratio | old top level | new ratio | new top level |
|-----|-----------|---------------|-----------|---------------|
| 1   | 2.12      | 3             | 2.27      | 2             |
| 4   | 3.11      | 5             | 2.40      | 3             |
| 8   | 3.42      | 7             | 2.86      | 5             |
| 20  | 3.94      | 13            | 3.13      | 9             |

Gold is the **early** gate and copies are the **long-run** gate: by run 20 the purse
has 4941g spare while the collection is pinned at the `MIN_KEEP` floor.

A consequence worth stating: a fresh 0-gold save can no longer fuse at all. Power
now comes *after* a run rather than before one. `tests/test_onboarding.gd` asserts both
halves — a new save cannot fuse, and one boss payout makes it possible — so the
mechanic can never become unreachable by a later price change.

`fusable_levels()` now walks the curve step by step; no single division describes
the run of affordable steps once both prices move.

### D36 — Enemies stopped matching you forever

Analysis of what was missing beyond art and sound found something worse than
polish: **progression was punished**. Enemy HP and damage scaled against the
player's deck power with no upper bound, at every depth. Measured at a fixed depth
3, holding the dungeon constant and varying only deck power:

| deck ratio | enemy HP | turns to kill | HP lost per fight |
|-----------|----------|---------------|-------------------|
| 1.0 (starter) | 43 | 3.10 | **27.9** |
| 2.0 | 68 | 2.45 | 31.9 |
| 4.5 (maxed) | 133 | 2.13 | **46.9** |

Quadrupling deck power made fights 31% shorter and cost 68% MORE HP. Kill speed and
incoming damage scaled at the same rate, so they cancelled — attrition never
improved no matter what the player collected, fused or equipped. That is why a
maxed deck measured worse than a merely good one.

**The ratchet.** Each dungeon now matches the player only up to a ceiling set by its
own difficulty (`Balance.ratio_ceiling`, applied inside `enemy_max_hp` /
`enemy_damage` so no caller can forget it). Below the ceiling enemies still answer
your deck; above it their stats freeze while your damage keeps climbing.
`HP_POWER_K` 0.6 -> 0.5 and `DMG_POWER_K` 0.4 -> 0.15 soften the climb underneath it.

HP lost per normal fight, after:

| depth | starter (1.0) | maxed (4.5) |
|-------|---------------|-------------|
| d1 Crypt | 19.0 | **5.6** |
| d3 | 27.9 | 12.5 |
| d6 | 46.0 | 34.3 |
| d8 The Maw | 58.8 | 56.6 |

You outgrow the Crypt. The Maw never lets go. Difficulty is now a choice of depth.
Past the power cap the answer is ascension, which multiplies enemy stats *outside*
the ceiling.

**The hole this opened.** Making shallow dungeons outgrowable made farming them
optimal: d1 -> d8 was 10x the HP lost for only 1.8x the gold. Gold now climbs
superlinearly with depth (`GOLD_DEPTH_EXP` 1.8), giving 5.1x the income for the
deepest floor with mid-depth income roughly unchanged — the fusion prices from D35
were tuned against it.

**Tests rewritten as properties, not constants.** The old guard asserted a ratio
between `DMG_POWER_K` and `HP_POWER_K`; that encoded the very design being replaced.
`tests/test_balance.gd` now measures the thing that matters — HP lost per fight must
FALL as the player grows, the deepest dungeon must still scale to the power cap,
depth must hurt more than power at equal power, and depth must pay at least 3x.
`tests/test_shop.gd` was repricing legendaries against d1 income, which is now the
poorest floor by design; it measures against mid depth.

### Test layout

All suites live in `tests/`, run by `tests/run.sh` (optionally filtered:
`tests/run.sh softlock`). Two kinds:

* `tests/test_*.gd` — headless script tests, `godot --script`.
* `tests/*Test.tscn` — scene tests. Some properties only exist on a tree that has
  actually been built (`mouse_filter`, wrapped line counts, scaled rects), and
  autoloads are not registered in a `--script` run.

The runner also fails if any `t_*` sandbox file is left in the player's data
directory — tests once wrote over a real save and a real settings file.

### D37 — Player Powers

"Powers that cost energy and could always be triggered every turn."

Fills a gap the earlier analysis under-ranked: **dead turns**. A bad draw was a
wasted turn and the only remedy the game offered was deck consistency. A power puts
a floor under the worst hand without raising the ceiling on the best one.

`PowerData extends CardData` on purpose — a power is a card you always hold, so it
inherits every mechanic, every level-scaling rule and the whole `power_value()`
pricing model. `play_card()` was split into `play_card()` (energy + hand
bookkeeping) and `_resolve()` (effects), and a power runs through the identical
`_resolve()`. Nothing can drift between cards and powers, which is the D34 lesson
applied before the bug rather than after it.

**Once per turn.** With three energy and a one-cost power, unlimited firing makes
"power, power, power" a legal turn: the power becomes both floor and ceiling, draw
stops mattering, and a deckbuilder stops being one.

**Priced into the ratio, and the first attempt was wrong.** A power is throughput
from outside the deck — the hole relics had before `RELIC_POWER_PER_RATIO`. The
first formula charged a power's full value as *added* throughput, which priced a
6-Block ability at +0.39 ratio. But firing it spends energy that would otherwise
have played a card, so the real gain is the **difference**:

    gain = value(power) x reliability - cost x deck value per energy

which puts the same ability at +0.06. A zero-cost power displaces nothing and is
worth its full value. `energy_gain` is routed through `throughput_multiplier`
instead, like a relic's — priced additively it read as +0.91, nearly triple what
the identical effect costs on a relic. Ten powers now price in a 0.04-0.33 band.

Economy: bought with gold, levelled with gold on the fusion curve doubled
(`power_upgrade_cost`), gated by dungeon clears. Fusion and powers compete for one
purse, so spare gold always has two homes. Save version 5; v4 saves are granted
Bulwark so an existing player is not worse off than a new one.

### Headless runs are sandboxed by default

`MetaState.path_prefix` now defaults to `"t_headless_"` whenever
`DisplayServer.get_name() == "headless"`. The game is never played headless, so
anything running that way is a test or a throwaway diagnostic.

This is the third time real player data was touched by tooling: settings were
corrupted by a test, an in-progress run was destroyed by a debug harness, and a
save's collection changed under a diagnostic. Each time the fix was "remember to set
a prefix". Opting *out* was too easy to forget, so real paths are now something a
process has to opt *in* to.

### D38 — Enemies that react, and bosses with signatures

Enemies were clockwork: `action_for_turn(t)` returned `pattern[t % n]`, blind to
the player's HP, the player's Block, their own HP and everything else. Every fight
was solvable once and then repeated forever. And 12 dungeons shared **4 boss
archetypes** distinguished only by `TIER_HP_MULT 1.55` and `TIER_DMG_BONUS 2` — the
climax of a run was a cultist with more HP.

Both are one mechanism. `EnemyData` gains a small rule table (parallel
`PackedInt32Array`s, so a rule is four numbers in a `.tres`): a `Trigger`, a
threshold, an `Action`, a magnitude and a once-only flag. Rules are checked in
order and the first match replaces the patterned action. Three new verbs —
**SUNDER** (through Block), **ENRAGE**, **DRAIN** (heals the attacker).

Boss signatures, each demanding a different plan: the **Warden** sunders a player
hiding behind Block, the **Cinder Knight** enrages once below half so it is a race,
the **Deep Warden** drains on a drumbeat so stalling loses, the **Abyss Horror**
closes on a wounded player. Seven normals react too.

**The telegraph cannot lie.** Intents are chosen at the top of the player's turn
and resolved at the end of it, so rules read the *completed* turn — never the one
in progress. Otherwise blocking after seeing "hit 9" could silently turn it into a
SUNDER, which is a coin flip rather than a puzzle. The test asserts an intent
cannot change after being shown.

**Three tuning mistakes, all caught by measurement rather than review.** Run
completion, rules off -> on:

| build @ dungeon | off | first attempt | shipped |
|-----------------|-----|---------------|---------|
| AoE @ Drowned Market d6 | 92% | **32%** | 49% |
| Barricade @ Foundry d3 | 74% | **32%** | 74% |
| Barricade @ Sunken Vault d5 | 88% | 57% | 73% |

1. **SUNDER on the commonest trash mob, at full damage.** Full damage makes it
   strictly better than attacking, so it is not a trade; on `cultist` it fired
   every turn and in multi-enemy fights it fired from every enemy. Removed from
   `cultist`, and `SUNDER_DAMAGE_FRAC` 0.55 makes bypassing Block cost damage.
2. **A rule on a group archetype.** `rat_swarm` spawns three, and three copies of a
   compounding buff swamp the dungeon rating — the exact trap `enemy_data.gd`
   already documented for debuffs.
3. **Heal-on-a-lasting-condition.** `deep_warden` drained whenever below 60% HP, so
   past half health it healed every turn: a stalemate, not pressure. `bog_lurker`
   had the same shape and was caught by the test written for the first one.

All three are now test-enforced, not comments: no rules on `count_max > 1`, no
heal tied to a permanent condition without `once`, and SUNDER must cost damage.

### D39 — A painted title screen

The main menu now uses a generated illustration instead of a tiling pixel
backdrop. Two things had to change for it to work, and neither was obvious.

**Filtering.** `project.godot` sets `default_texture_filter=0` (NEAREST) globally,
which is correct for every pixel asset in the game and turns a smooth illustration
into jagged edges. `UI.illustration()` overrides to LINEAR on that node only.

**Legibility, measured rather than eyeballed.** White menu text over the raw image
sat at **3.7:1** contrast in the button area — below the 4.5:1 needed to read
comfortably — with highlights bright enough to swallow a glyph. A gradient scrim
fixed the average immediately (5.8:1) but the *worst pixel* was still 1.4:1: a pure
left-to-right fade had dropped to 0.2 opacity exactly where the right-hand end of
the menu column sits. Averages do not read text; the brightest pixel under a glyph
does.

The scrim is therefore held FLAT at `SCRIM_ALPHA` across `SCRIM_HOLD` of the width
before it fades, and `MENU_WIDTH` keeps the column inside that cover. Godot centres
Button text by default, which would otherwise have thrown every label into the
middle of the picture where the scrim is gone. Worst-pixel contrast is now
5.0-9.7:1 across the title, buttons and footer.

`tests/MenuArtTest.tscn` measures the real image and fails under 4.5:1, so a
darker scrim cannot be quietly weakened and a brighter replacement image cannot be
dropped in unnoticed. Verified by weakening the scrim (1.6:1, caught) and by
reverting the filter to NEAREST (caught).

It is a **scene** test: reading `UI.*` from a `--script` run pulls in the UITheme
autoload, which is not registered there, and the resulting compile error silently
skips the checks while the suite still reports a pass. That false pass happened on
the first attempt at this test.

The image is generated, not CC0 — `assets/art/README.md` records that it is not
covered by the Kenney licences alongside the pixel and audio assets.

### D40 — Relics that change how you play

All 30 relics were flat stat fields: `+15 max HP`, `start_block = 8`,
`gold_percent = 40`. They changed your numbers and never your decisions.

`RelicData` gains the same rule shape `EnemyData` uses — parallel
`PackedInt32Array`s of trigger, threshold, effect and value — deliberately reusing
one proven pattern rather than inventing a second. Five triggers (`ON_KILL`,
`ON_TURN_START`, `ON_CARDS_PLAYED`, `ON_HP_BELOW_PCT`, `ON_BLOCK_EXPIRED`) and six
effects. Ten relics were rebuilt around them:

* *Bone Charm* — an enemy dies, draw 1. Chase kills.
* *Crown of Thorns* — an enemy dies, 4 to all. Snowballs through a group.
* *Duelist's Glove* — every 3rd card in a turn, 5 to all. Rewards emptying a hand.
* *Weighted Soles* — Block you did not spend comes back next turn.
* *Reliquary Heart* / *Surgeon's Thread* — pay out once, when you are nearly dead.

**Priced, and verified twice.** A trigger is throughput from outside the deck —
the hole `RELIC_POWER_PER_RATIO` exists to close, and the one that made powers read
as +0.9 ratio on the first attempt. `triggered_power()` values each effect by how
often it realistically fires in a fight of `TARGET_NORMAL_TURNS`, and feeds
`flat_power()`. Triggered relics land at 0.03-0.39 ratio, the same band as the flat
ones (0.19-0.29).

Pricing being *correct* is a separate question from it existing, so it was
measured: the relic-bearing sim profiles were run with triggers live and with
`_fire_relics` stubbed out. Run completion and HP loss were identical within noise.
The relics change what you do without changing how hard the game is, which is
exactly the intent.

**A mistake worth recording.** The first pass converted `ancient_battery` and
`scholars_lens`, which the suite uses as *the* energy relic and *the* draw relic in
four unrelated assertions. Repurposing a fixture broke tests that had nothing to do
with triggers. Both were restored and the two triggers moved onto `lucky_penny` and
`field_kit`, whose flat effects (20% gold, heal 3) nothing depended on.

### Known gap: the endgame plateaus above the deepest ceiling  *(closed in D54)*

Measured while verifying D40, not caused by it. `ratio_ceiling(8)` is 4.55, but
real late decks reach ratio 5.09 and maxed ones 5.92. Above the ceiling nothing
scales, so the last dungeons finish at 100% completion losing 1-6% HP.

This is the flip side of the D36 ratchet and the test for it did not catch the
case: it checks that the deepest dungeon still scales up to `POWER_RATIO_CAP`
(4.5), and 4.55 clears that — but decks do not stop at the cap. Ascension is the
designed answer and multiplies enemy stats outside the ceiling, but it is off by
default, so a first playthrough ends on a walkover. Not fixed here; fixing it means
deciding whether the deepest dungeons should keep scaling indefinitely or whether
finishing should push the player into ascension.

### D41 — Twelve dungeons, twelve bosses

The boss archetype was drawn at random from the dungeon's own `enemy_roster`.
Auditing that turned up something worse than expected:

* **Seven of twelve dungeons had no boss archetype in their pool at all.** The
  Crypt's finale was a `cultist`, `crypt_hound` or `bone_picker` with 1.55x HP.
* In the five that did, it was a coin flip whether the boss archetype turned up.
* Where one was in the pool it also spawned as a normal encounter, spending its
  signature before the fight that needed it.

So the boss signatures built in D38 barely reached the player at all.

`DungeonData.boss` now names a fixed archetype per dungeon, matched to the place,
its foes and its loot — and the engine filters boss archetypes out of ordinary
encounters entirely.

| dungeon | boss | signature |
|---------|------|-----------|
| The Crypt d1 | The Grave-Sexton | winds up every 3 turns — teaches racing a telegraph |
| The Warrens d2 | The Brood-Mother | grows every 2 turns; nothing here fights alone |
| The Ossuary d2 | The Marrow-Abbot | enrages under half, shields on a drumbeat |
| The Ember Road d3 | The Bellows-Master | stokes itself hotter every 3 turns |
| The Foundry d3 | The Forge-Warden | strikes through 20+ Block — "they hit back harder" |
| The Slag Pits d4 | The Cinder Knight | enrages under half; punishes a dumped hand |
| The Fungal Deep d4 | The Mycelial Lord | drains on a drumbeat; it breathes with you |
| The Rot Gardens d5 | The Gardener | tends itself; enrages when cut back |
| The Sunken Vault d5 | The Deep Warden | drains every 3 turns; a slow fight is a lost one |
| The Drowned Market d6 | The Last Vendor | you spend cards, it profits |
| The Abyssal Stair d7 | The False Step | takes you through Block when you falter |
| The Maw d8 | The Maw Itself | an appetite, and it enrages |

**This is what makes choosing a deck a decision.** The boss is named at the zone
list, on the deck-building screen and on the map node, with a one-line warning
generated from its own rules so the text can never drift from the fight. Knowing
the Forge-Warden punishes Block *before* choosing whether to bring Block is the
decision that screen existed to ask and never did.

**Two things measurement caught.**

*Difficulty leaked out with the bosses.* Those archetypes had been carrying real
pressure as normals; removing them made their dungeons soft — AoE decks went from
49% to 99% completion at the Drowned Market, Barricade from 73% to 91% at the
Sunken Vault. Restored by giving two single-spawn normals conditional rules and
topping the thin rosters up with foes that belong there, rather than by inflating
numbers: 88% and 85% now.

*Four boss sprites silently did nothing.* `PixelArt.OVERRIDES` pins each boss to a
chosen tile, but four named tiles had never been copied into the project, and
`enemy_sprite()` fell back to positional assignment without a word — so those
bosses wore other enemies' faces. Positional assignment also now skips pinned
sprites, or a trash mob inherits the finale's look. Both are test-enforced.

`tests/test_dungeon.gd` asserts every dungeon names a loadable boss with a
signature and a warning, that no dungeon fights its own or any other boss as
trash, that no two dungeons share a boss, and that 30 rolled normal encounters
never produce a boss archetype.

### D42 — Making the game expandable

An audit of what it costs to add a card, an enemy or a dungeon, and what would
break first. Two real defects, several ceilings, and one thing that would only
have shown up after shipping.

**Runtime `res://` listing does not survive export.** `enemy_sprites()` and the
card-art lister matched `f.ends_with(".png")`. Godot does not put source PNGs in a
PCK — it ships the imported texture and leaves `sprite.png.remap` beside it. So
both listings would have returned **nothing** in an exported build: no enemy art,
no card illustrations, in a game whose whole look is those sprites. Neither the
editor nor a `--headless` run can reveal it, because both read the real
filesystem, and this project has never been exported. Now routed through
`PixelArt.list_resources()`, which strips `.remap`.

**Catalogues were hand-maintained with nothing checking them.** Six lists —
`CATALOG` (100 cards), `RELIC_CATALOG`, `POWERS`, `DUNGEONS`, `ZONES`, `BUILDS` —
each needing an edit per new file. They happened to be in sync, but a forgotten
line means finished content that silently does not exist, and a renamed file means
a catalogue entry that fails at load with no clue why.

**Ceilings, now measured and asserted rather than discovered:**

| resource | in use | available | headroom |
|----------|--------|-----------|----------|
| enemy sprites | 35 archetypes | 41 tiles, 12 pinned | **6** |
| card illustrations | 100 | 140 | 40 |

Six spare sprites is the real limit on new enemies, and it was hit blind while
adding bosses in D41 — the art test only caught it because it already checked for
duplicates. `tests/test_content.gd` now prints the headroom every run and fails
below three.

**Persisted enum ordinals.** `EnemyData.Action` and `Trigger`, `RelicData.Trigger`
and `Effect`, `CardData.Rarity` are stored as raw ints in `.tres` files and in save
games. Inserting a value silently rewrites every existing enemy and every save.
This was a comment on one enum; it is now a test that pins the numbers.

**A hand-computed constant that rots silently.** `BASELINE_CARD_POWER` (4.625) is
the reference deck's power per energy, written out by hand, and every scaling
number is relative to it. Change card pricing without recomputing it and the whole
curve drifts with no error anywhere. The test recomputes it from the actual cards.

**Untested migration chain.** `SAVE_VERSION` is 5 with five migration steps, and
only v0 had a fixture — a v2 or v3 save could have been broken for releases with
nobody knowing. `tests/test_save.gd` now carries a fixture per historical version
and asserts each arrives with its progress intact and current defaults filled in.

`CONTRIBUTING.md` documents the actual steps per content type, and the two
authoring rules that are enforced rather than suggested (no conditional rules on
group archetypes; no heal on a lasting condition without `once`).

**Still open, deliberately.** Content ids are strings everywhere, so a rename is a
find-and-replace across `.tres` files — checked by the reference test, not
prevented. Rule tables are parallel arrays, which the tests keep honest but which
will get unreadable well before fifty bosses. Neither is worth restructuring yet.

### D43 — Exporting, and the bug only an export could find

D42 flagged that runtime `res://` listing looked unsafe for exported builds and
fixed it by reasoning about how PCKs work. That reasoning was **wrong**, and only
building the thing showed it.

The first fix stripped a `.remap` suffix. An actual exported pack reports entries
as `tile_0056.png.import`. So the fix changed nothing, and a smoke test run inside
a real pack reported:

```
enemy sprites found : 0        <- every enemy had no sprite
card ids found      : 100      <- .tres survive packing fine
strike card art     : OK       <- a single sheet loaded by path is fine
```

Only *directory-listed* PNGs break. `load()` on the original path still works;
it is listing that returns the sidecar. Now stripped correctly, verified at 41
sprites and 0 archetypes without one.

`tests/export.sh` + `tests/export_smoke.gd` make this permanent: they pack the
project and run assertions **inside the pack**. Kept out of `tests/run.sh` because
they need ~1 GB of export templates a normal checkout will not have.

**Built and verified:** Linux (72 MB), Windows (106 MB), macOS universal (58 MB).
macOS/arm64 additionally required `import_etc2_astc`, which every arm64 target
needs — the export simply refuses without it.

**Not built here.** Android needs a JDK and the Android SDK (`platform-tools`,
`build-tools`), neither of which is on this machine; the preset is written and
`BUILD.md` has the exact commands. iOS requires macOS with Xcode and cannot be
produced from Linux at all.

### Touch: a finger sends no hover

The card design from D37 — resting cards show name and cost, hovering enlarges
them to reveal rules text — is unusable on a phone, because touchscreens generate
no hover events. Every card would have been unreadable until played, which is
exactly backwards, and the same applies to every tooltip in the game.

`UI.touch_ui()` now splits the interaction: mouse hovers, touch **taps once to
read and again to commit**. Implemented as a single handler owning both taps
rather than a reveal handler racing the caller's — deciding whether a tap counts
by relying on signal connection order would break the first time someone moved a
line.

Also set: landscape orientation (a hand of cards along the bottom of a 1280x720
layout is unusable in portrait) and mouse emulation from touch.

Nobody has run this on real hardware. Text size at phone DPI is the likeliest
thing to need work; `UITheme.UI_SCALE` is the single knob and Settings exposes it.

### D44 — Staying exportable to platforms we cannot build

Android and iOS will never build in CI: one needs a JDK and the Android SDK, the
other macOS with Xcode and a per-developer team ID. None of that can live in a
repository. What *can* be guaranteed is that the toolchain is the only thing
missing — so the day someone installs it, the export works with no further edits.

Godot reports both kinds of problem identically, as "configuration errors".
`tests/export_ready.sh` attempts every preset and classifies each reason:

* a missing JDK, SDK, `platform-tools`, `apksigner`, Xcode or team ID -> **skip**
* anything else -> **FAIL**, the project itself has regressed

```
built Linux · built Windows · built macOS
skip  Android — A valid Java SDK path is required in Editor Settings.
skip  iOS     — App Store Team ID not specified.
3 buildable here, 2 need a toolchain, 0 blocked by the project
```

Verified by breaking it two ways: turning off `import_etc2_astc` (macOS flipped to
FAIL — every arm64 target refuses without it) and blanking the iOS bundle
identifier (iOS flipped from skip to FAIL). Both exit non-zero.

An iOS preset was added while doing this, and setting it up surfaced a real
configuration error — `Metal renderer require iOS 14+` — which is now fixed rather
than waiting to be discovered on a Mac. The one remaining iOS blocker is the team
ID, which is a credential, not a defect.

The half that needs no templates lives in `tests/test_content.gd` and runs in the
normal suite: presets exist for all five platforms, `import_etc2_astc` is on,
landscape orientation is set, touch emulation is on, and `card_button` has a touch
path. Both halves run in CI, with the ~1 GB templates cached on the engine version.

### D45 — The curve flatlined, and Block was why

Measuring the whole progression, not one cell of it, showed the game had exactly
**one** difficult moment and then nothing:

| deck | ratio | result |
|------|-------|--------|
| Starter | 1.00 | Crypt 99% |
| Early | 1.26 | **Foundry d3 39%** |
| Mid | 2.84 | everything 100%, -3 to -13% HP |
| Relic (Lv15 + 4) | 4.32 | everything 100%, **-0 to -6% HP** |
| Late (Lv40 + 6) | 5.09 | 100%, **-0 to -3% HP** |
| Endgame (Lv100) | 5.92 | 100%, -1 to -2% HP |

Roughly 80% of the content had no resistance left in it. Two causes, and the
second was not a tuning value at all.

**The ceiling was below achievable power.** `ratio_ceiling(8)` was 4.55 while real
decks reach 5.92 — and mid-game decks already hit 4.32, above the ceiling of every
dungeon up to d7. The D36 ratchet was meant to let a player outgrow the *Crypt*;
it let them outgrow the *Maw*. `RATIO_CEILING_PER_DEPTH` 0.45 -> 0.73 puts the
deepest ceiling at 6.51, above `MAX_ACHIEVABLE_RATIO`.

**Block scales linearly and enemy damage cannot.** This is structural. A deck
spends about half its throughput on Block, and that grows linearly with deck
power; enemy damage grows as `1 + DMG_POWER_K x (ratio - 1)`, sublinear for any K
below 1 — which is the entire point of the ratchet. So past a threshold, Block
absorbs everything. Measured net damage per turn at ratio 5, at four different
values of K:

| DMG_K | enemy dmg/turn | player block/turn | net taken |
|-------|----------------|-------------------|-----------|
| 0.15 | 20.0 | 54.3 | **0.0** |
| 0.35 | 30.1 | 54.3 | **0.0** |
| 0.55 | 40.3 | 54.3 | **0.0** |
| 0.75 | 50.4 | 54.3 | **0.0** |

No value of K fixes it. Raising it to 1.0 only flips back to punishing
progression. The system is a knife edge between "Block wins outright" and "power
is punished", and a single constant cannot sit between them.

**Pressure Block cannot answer is what breaks the tie.** The game already had it
in SUNDER and poison, just on too few archetypes to matter. `pierce_fraction()`
now makes depth carry it: 0% of a hit at d1, rising 3.2% per difficulty to ~22% at
the Maw. Shallow floors stay answerable with a shield; deep ones are not, which is
also what makes them read as deeper. The intent line says so — "hit 14 (4 pierces
Block)" — because piercing damage the player was not warned about is a cheat.

After, every stage has something that resists it:

| build | result |
|-------|--------|
| Status Lv15 | Foundry 69%, Ember Road 64% |
| Barricade Lv15 | Foundry 53%, Sunken Vault 60% |
| AoE Lv15 | Rot Gardens 85%, Drowned Market 73% |
| Thorns Lv15 | Abyssal Stair 78%, Maw 71% |
| Late Lv40 + 6 relics | Maw 100% but -12 to -21% HP a fight |
| Endgame Lv100 | Maw 100%, -9 to -17% HP |

Pierce was first set at 4.5% per depth, which put Barricade at 44% — a block deck
eats it twice, once for being blocked-through and again because its slow fights
multiply the per-turn cost. 3.2% keeps it the hardest build to pilot without
deleting it.

**The test was measuring the wrong thing.** `test_balance.gd`'s attrition helper
ignored Block entirely — half of what a deck does. It reported the deepest dungeon
costing 58 HP a fight when the truth was zero, which is precisely how this went
unnoticed through D36 and D41. It now models Block, including a calibrated
efficiency factor (you hold what you drew, not what you wanted), and guards the
flatline directly: the deepest ceiling must clear `MAX_ACHIEVABLE_RATIO`, a maxed
deck must still lose HP at depth, and Block must never be a complete answer there.
Verified by reverting each cause in turn — both are caught.

### D46 — Reward tension and in-run deck shaping

A run only ever ADDED cards: `earn_card` appends and nothing removed it, so
surviving longer made the deck steadily less consistent. And the reward screen's
"take one of three" had no tension in it, because taking was free — dilution is
real but was completely invisible.

**Both directions now exist.** Shops sell a removal at a price that rises with each
cut taken this run (`Balance.removal_price`), and a rest is no longer a free heal:
it offers *Recover* or *Sharpen*, so healing costs you the thinning and vice versa.
The picker is an overlay (`UI.card_picker`) rather than a screen, so it works
identically from a shop, a rest and all three traversal views without any of them
knowing how it works.

Thinning is **run-scoped** — the collection is never touched — and it is **not free
power**: `power_ratio` is power per energy, so cutting a weak card raises the ratio
and enemies scale to match. What the player buys is consistency, which is the point.

**The reward screen now quotes what taking costs**: "Taking one makes your deck 15
cards: you would see any given card every 3.0 turns instead of 2.8", and Skip reads
"keep the deck at 14" so declining looks like the play it is.

### D47 — A black screen shipped, and the suite stayed green for five commits

`map.gd` stopped compiling in D41 and stayed broken through **four more commits**,
every one of which reported 29/29 passing, while every graph dungeon — including
the Crypt, the first dungeon in the game — was a black screen. A player found it,
not the tests.

Three independent failures let that happen, and each is worth stating plainly:

1. **`godot --headless --import` does not compile scripts.** It reported zero
   errors the entire time.
2. **`load()` returns a non-null Resource for a script that failed to parse.** The
   export smoke test's `if load(path) == null` check therefore passed happily on a
   broken `Map.tscn`. `can_instantiate()` is no better — it answers false for
   perfectly good scripts. `get_instance_base_type() == ""` is the honest probe.
3. **No test loaded the traversal scripts at all.** `test_layout.gd` inspects them
   as *text*, which cannot notice that they no longer parse.

The deeper problem was that the suite tested *units and data* thoroughly and the
*game* barely at all. D33 had already recorded the lesson — "booting is not
playability" — and it was enforced for exactly one screen.

**`tests/test_compile.gd`** — every script in `scripts/`, `tests/` and `tools/`
plus every scene root must compile. Runs in about a second and would have caught
this the moment it was introduced.

**`tests/PlayableTest.tscn`** — the integration test that was missing:

* every screen instantiates *and offers at least one thing the player can press*.
  A screen with no enabled control is a dead end and indistinguishable from a crash
  to whoever is holding the controller.
* **every dungeon** can be entered and its traversal view offers a reachable
  encounter. This is the exact reported failure, across all three traversal models.
* a combat plays from the first card to victory through the real scene.
* a rest resolves and hands control back.

Verified by reintroducing the precise bug that shipped: `test_compile` names the
file and the scene, and `PlayableTest` reports *"crypt: entered the dungeon and
there is nothing to click"* for all four graph dungeons.

Two things learned while writing it. A screen with missing state bails out by
*navigating* — `ZoneView` with no zone calls `change_scene_to_file`, which in a
harness replaces the test scene itself and hangs the await forever; every screen
therefore gets plausible state, as the game would have given it. And feeding a
traversal view another kind's run state spins forever, so those three are covered
per-dungeon with the state they actually receive rather than generically.

**Root cause of my own error:** three of these breakages came from scripted
whole-block text replacements that silently landed at the wrong indentation. GDScript
is indentation-sensitive and the edits looked right in a diff. Blocks are now edited
in place with exact anchors, and `test_compile.gd` is the backstop.

### D49 — Default UI scale 1.0

`UITheme.UI_SCALE` 1.6 -> 1.0. It is only the default for a machine with no
settings file; `SettingsState` applies the persisted value straight after, so an
existing player keeps whatever they chose.

Two things broke on the way down, both instructive.

**A duplicated constant lied.** `tests/test_layout.gd` carried
`var scale := 1.6   # the shipped default UI scale`. Lowering the real constant
would have left that test measuring a window nobody uses while still passing. It
now reads `UI_SCALE` from the script. Third time a restated number has done this.

**Buttons squashed their own frame.** The painted border is drawn 1:1 at 40px and
does not scale, so `px(40)` — 64px at scale 1.6, fine — became 40px at 1.0 and the
carved frame collapsed. Caught by `MenuArtTest`, which had just been taught to
check exactly this. Fixed with `UITheme.button_height(base)`, which never returns
less than `min_button_height()`, so the default scale can move again without
breaking every button in the game.

### D50 — A card must not lie about itself

`CardData.description` is authored text baked at level 1, while everything that
resolves an effect reads `eff_*()`, which scales. So a fused card misreported
itself, and disagreed with its own hover text, which was generated:

| card | level | face said | actually dealt |
|------|-------|-----------|----------------|
| Strike | 40 | "Deal 6 damage." | 15 |
| Bash | 40 | "Deal 10 damage. Apply 2 Vulnerable." | 38, Vulnerable 6 |
| Clear Mind | 40 | "Gain 3 block, draw 2." | 11 Block |

`CardData.effect_text()` generates the face line from the same getters the engine
uses, so the two cannot drift. `Icons.card_tooltip()` remains the long form. Every
display site — card faces, shop rows, the powers screen, the combat power button,
the deck-builder power picker — now reads the generated text, and powers inherit it
because `PowerData extends CardData`.

**Deviation worth stating.** The request was to drop the text from the card and rely
on the hover. I generated it instead, because tooltips do not exist on a
touchscreen: `UI.touch_ui()` reveals the card's own text on the first tap (D43), so
deleting it would have left mobile players with no way to read a card at all.
Generating it satisfies the same goal — one source of truth, no contradiction —
without that cost.

The authored field is kept only as a fallback for a mechanic `effect_text()` has not
been taught, so a new card shows something rather than a blank face.

`tests/test_card_truth.gd` walks all 100 cards at levels 1, 10 and their cap and
asserts every effective number appears in both the face text and the hover text; it
also asserts a scaling card reads differently at Lv40 than Lv1, and greps the UI
scripts for any return of the stale field. Verified by restoring
`card.description` on the card face — caught immediately.

`CardTextTest` had encoded the old behaviour (it looked for the authored line), which
is why updating a test is sometimes the correct half of a fix.

### D51 — Filter and sort the collection

Both the collection and the deck builder listed cards by raw iteration order of
`MetaState.collection`, which is neither stable nor meaningful once you own a
hundred of them.

`CardFilter` is a **pure function over ids** — `apply(collection, catalog, state)`
returns the ids that pass, in order — so it is tested headlessly without building a
screen, and both screens call the same function. Two independent sort
implementations would be the same class of bug as the D34 label table that made the
first dungeon unplayable.

Six sort keys (name, cost, rarity, level, owned count, power), an
ascending/descending toggle, and rarity + type filters that AND together. `UI.card_filter_bar`
is the one control strip both screens mount, and `CardFilter.state` is a session
static so moving from the collection to the deck builder keeps what you asked for.

Two things worth noting. **Power sorts by the level actually owned**, not the base
card — a level-12 Strike outranks an unlevelled one, which the test pins by sorting
the same collection with and without the level. And the filter test greps both
screens for `CardFilter.apply` and for any surviving raw `for id in
MetaState.collection` in a listing loop, which caught a leftover count loop in the
collection (replaced with the existing `total_copies()`).

### D52 — A way out of the fight, and Escape means it

Combat had no exit control at all, and Escape was bound to *leave fullscreen* on
every screen in the game. The longest scene was the only one you could not leave,
and the key everybody presses did something unrelated.

Both are one registration now. `UI.exit_button()` builds the button **and** binds
the key to the same `Callable`, so a screen states its way out once; `UITheme`
asks `UI.run_escape()` and only falls back to leaving fullscreen when a screen
declares none. Three screens declare none deliberately and the test names them:
MainMenu and Overworld are roots, and an event is a decision (every event has a
cost-free option, so nothing traps you there).

Two details that are not decoration:

* **Combat seals its exit between the killing blow and the reward pick.** The
  encounter is not cleared until the reward is taken, so stepping out there and
  coming back would re-offer the fight. Mid-fight leaving is safe because the
  fight is serialized after every action (D22) and Resume returns to that turn —
  `GameState.resume_scene()` now owns that rule, which had been written out three
  times (Continue, slot load, and the pause menu, which sent you to the *map*).
* **The escape action lives on the node, not in a static.** A static `Callable`
  holding a lambda that captured a screen outlived that screen and corrupted the
  heap at engine shutdown. Because a scene test writes to a pipe, the abort
  discarded the buffered output — including the `PASS` line the runner greps for —
  so three passing tests reported as failures with no message. `tests/run.sh` now
  checks the exit code as well as the report: a crash after a pass is still a
  crash.

`PlayableTest` gained the assertion, verified by removing one registration and one
seal: it names the screen with no way out, and reports that combat can be left
between the kill and the reward.

### D53 — The Music bus finally has music on it

`Audio` created a Music bus, `apply_volumes()` drove it, and the settings screen
offered a Music slider. Nothing was ever routed to it — every voice in the pool
plays on SFX. The slider adjusted the volume of silence, which is worse than an
absent feature because the UI claims otherwise. It is the same placeholder problem
D32 set out to end, arrived at from the other side.

Five looping scores (menu, world, dungeon, combat, boss) now play on that bus,
switched by **where the player is**: `Audio._process` watches the current scene and
looks it up in one table. Polling beats asking each screen to announce itself —
screens are entered from a dozen places, some of them raw `change_scene_to_file`,
and the one that forgets is the one that goes quiet. Anything unlisted still gets
the world theme, so a new screen cannot be silent by omission, exactly as
`UI.button` attaches its own click sound. Combat is the one screen whose score
depends on more than its name: a boss node sounds different from the corridor.

**The music is generated** (`tools/gen_music.py`), and the reasoning is the same
as D29's hand-authored glyphs. The sprites and effects are CC0 packs because packs
of those exist with licences verifiable on the page and in the pack; no comparable
CC0 pack of *looping* music turned up, and choosing tracks by ear is not a
judgement I can make honestly. So it is synthesised and **measured** instead, and
the generator fails rather than shipping a track that clicks at the loop point,
competes with the sound effects for level, or measures identically to another
track. Every voice is written into the buffer modulo its length, so a note or a
delay tail crossing the end wraps into the beginning: the loop is continuous by
construction rather than repaired afterwards.

One measurement was wrong first and is worth recording. The seam check began as
"RMS of the first 50 ms against the last 50 ms" and failed all five tracks — a
loop that begins on a downbeat and ends on a decay is *supposed* to jump in level
there. That is music, not a click. A click is a step the waveform does not
otherwise take, so the check now compares the step across the loop point against
the 99th percentile of every other step. It then caught something real: the
percussion had an instant attack, which put a full-amplitude sample at index 0 —
and index 0 *is* the loop point. A 1.5 ms ramp fixed it.

Five tracks, 475 KB. The stingers (victory, defeat, boss cleared) stay on SFX
although they came from a music pack: they are feedback for something that just
happened, and a player who turns the music off still wants to hear that they won.

**A third restated constant, found on the way.** `SettingsState.ui_scale`
defaulted to 1.6 while `UITheme.UI_SCALE` had been lowered to 1.0 in D49 — and
settings apply *after* the theme, so every machine without a settings file (that
is, every new player) got 1.6. `tests/test_layout.gd` read the constant, measured
1.0, and passed. The field is now a sentinel resolved from the theme, and the test
fails if it is ever a number again.

### D54 — The endgame stopped being a walkover

The gap recorded above ("the endgame plateaus above the deepest ceiling") was still
open, and measuring it fresh showed both halves:

| deck | ratio | Abyssal Stair | The Maw |
|------|-------|---------------|---------|
| Thorns Lv15 | 3.76 | 80% | 68% |
| Late (Lv40 + 6) | 5.09 | 100% | 100% |
| Endgame (Lv100) | 5.92 | 100% | 100% |

A greedy playthrough cleared all twelve dungeons without dying once. The ceiling
was no longer the cause — D45 had already lifted it past `MAX_ACHIEVABLE_RATIO`.
The cause was that **more power made the deepest floor easier**. `HP_POWER_K` is
0.5, so enemy HP grows at half the rate of the player's damage: the maxed deck
finished a Maw fight in 4.0 turns where the late deck needed 5.2, and a shorter
fight simply hands out fewer opportunities to be hit. Pierce (D45) is per-hit, so
fewer hits is a discount on it too.

Raising `HP_POWER_K` to 1.0 fixes the top and guts the middle — measured Barricade
55% → 29% at the Foundry, AoE 72% → 6% at the Drowned Market — because it
lengthens fights at *every* ratio and escalation compounds on decks that were
already slow. The same is true of raising `DMG_POWER_K`: at 0.35 the endgame lands
at 72% and Status drops from 66% to 28%.

So both new rules switch on **above a floor** (`HIGH_POWER_FLOOR` = 3.0, the top of
the build band) and change nothing below it:

* `HP_POWER_K_HIGH` adds enemy HP per point of ratio past the floor, so fights stop
  shortening once a deck is beyond what any build reaches.
* `pierce_fraction()` takes the deck's ratio as well as the depth, and rises past
  the same floor. It still runs through `scaling_ratio`, so it is capped by the
  dungeon: the Crypt's ceiling is 1.4 and no amount of growth makes the Crypt
  pierce you. The ratchet is untouched — you outgrow the Crypt, not the Maw.

Applying the ratio term from ratio 1 instead of from a floor took Barricade from
59% to 31%: block builds pay pierce twice, once for being blocked through and again
because their slow fights pay it every turn. The floor is what makes this safe.

After (before → after):

| deck | ratio | cell | |
|------|-------|------|--|
| Early | 1.26 | Foundry | 41% → 37% |
| Barricade Lv15 | 2.37 | Foundry / Vault | 55/59% → 52/58% |
| Status Lv15 | 3.15 | Foundry | 66% → 67% |
| Thorns Lv15 | 3.76 | Stair / Maw | 80/68% → 54/40% |
| Late Lv40 + 6 | 5.09 | Stair / Maw | 100/100% → 69/**49%** |
| Endgame Lv100 | 5.92 | Stair / Maw | 100/100% → 89/**70%** |

The build band is where D45 left it, and the last dungeon in the game now reads as
a gradient: 40% for a deck that arrived early, 49% for a strong one, 70% for a
maxed one. More power still wins — it is no longer free.

**The test for this had to change probe.** The obvious assertion — a maxed deck
must still lose HP per fight at depth — passed all the way through the plateau,
because pierce alone keeps that number rising while the runs themselves were free.
Fight *length* is the mechanism, so `tests/test_balance.gd` now asserts that fights
in the deepest dungeon never shorten as power climbs past the floor, while the
first dungeon must still get easier (or the ratchet has been undone). Verified by
setting `HP_POWER_K_HIGH` back to 0: the HP-loss version passes, the length version
names all three ratios.

### D55 — AGENTS.md, and a hook that keeps the docs honest

*(Numbered D52 when written, colliding with "A way out of the fight". Renumbered
here; the summary list above references the combat one, which keeps D52.)*

Added `AGENTS.md`: the concept, the design pillars, and the engineering lessons in
one brief, with DESIGN.md as the full decision log behind it. It exists so the *why*
is discoverable without reading 1800 lines — for a human or an AI picking the project
up cold.

The docs are only useful if they stay current, so `.claude/hooks/docs-current.sh` is
a `UserPromptSubmit` hook (fires every turn) that injects a standing reminder to keep
AGENTS.md and DESIGN.md current, and escalates to a STALE warning when the working
tree has uncommitted changes under `scripts/` or `resources/` with no matching change
to either doc.

What a hook can and cannot do, stated plainly: it cannot write good prose — only the
author can. What it can do is make forgetting impossible, by re-asserting the rule in
context on every call and surfacing a concrete staleness signal. The three-way logic
(clean tree, code-only, code+docs) was verified in an isolated git repo; the JSON
output was verified valid both with and without `jq` on PATH, because the dev shell
here does not always have it.

### D56 — Art direction, and looking at the game before talking about it

The graphics work needed a brief, so `ART.md` is now the art brief: the diagnosis,
the one style everything gets brought to, and the ~225-file asset list with the code
hook each asset plugs into. It sits alongside AGENTS.md (the concept) and this file
(the decision log).

**The harness came first, deliberately.** `tools/screenshots.gd` boots all 20 screens
at the shipped 1280×720 with a stocked save and writes a PNG each. Writing an art
brief from source code would have produced a plausible document and missed everything
below, because none of it is visible in the code. It needs a real GL context — art
direction is a render, not a simulation — so it runs against Xvfb with software GL
rather than `--headless`.

Two things the harness taught about itself:

* `GameState.reset_run_progress()` clears `dungeon_id`, and as an *argument* to
  `enter_dungeon()` it evaluated **after** `select_dungeon()`. Combat therefore saw no
  dungeon and fell back to the tiling zone backdrop. The first capture looked exactly
  like missing painted art, and the conclusion "the Crypt backdrop does not load"
  would have been wrong.
* One process per screen. The first all-in-one run wedged on a screen and spun for 26
  CPU-minutes, costing every capture after it; a `-- <SceneName>` filter makes a hang
  cost one.

**What the captures showed that the code did not.**

The frame art is the headline. `ui_button.png` is a 128×83 *painting* of torn
parchment, nine-sliced with `22/22/19/21`. Horizontally its 84px centre is stretched
to 1204px on a full-width button — **14.3×** — so the ragged edges and the lighting
gradient across them become the purple-and-white smears on every wide button in the
game. Vertically it is worse and it is arithmetic, not taste: `min_button_height()`
is `19 + 21 + 10 = 50`, so a standard button is 50px tall with **40px of fixed border
and a 10px parchment band**, and a 16px font overflows that band by 6px. That is why
text sits *on* the carved border everywhere. Neither fact is visible in a diff, and
both were introduced by art that is illustrative where a nine-slice has to be flat.

Also found, and all invisible from source:

* **Seven screens have no backdrop at all** — `collection` `deck_builder` `deck_run`
  `dice_run` `encounter` `map` `shop`. They never call `UI.screen()` or
  `PixelArt.backdrop()`. The map, shop and event screens are flat near-black.
* **The dice board renders nothing.** `dice_run.gd` puts `board_box` in a
  `ScrollContainer` with both scroll modes AUTO, so its minimum size is 0 on both axes
  and the surrounding `SIZE_EXPAND_FILL` spacers crush it to zero height. Sixteen
  track cells are built every refresh and none are visible at the shipped scale. This
  is the D47 lesson again — a scene that loads can still be a black screen — and
  `test_layout.gd` should assert a non-zero board rect.
* **The theme covers `Button` and `PanelContainer` only.** Every `OptionButton`,
  `HSlider`, `VScrollBar` and `CheckBox` is default Godot chrome next to painted
  buttons.
* **Card illustrations are semantic noise.** `PixelArt.CARD_TILES` indexes Kenney's
  1-Bit sheet, which is largely alphabet glyphs and dither patterns; the collection
  capture shows a shopping cart on Battle Trance and a cactus on Berserker Rage.
* **`bg_warrens.png` has "THE WARRENS" painted into the sign above the door** — a
  rename or a translation makes the art lie. It also carries visibly heavier ink than
  `bg_crypt.png`, which is the style target.

**The direction chosen** is what already works rather than something new:
`bg_crypt.png` and `bg_warrens.png` agree with each other on composition, lighting
model and vocabulary, so painted-and-inked dark fantasy is the style and everything
else — 16×16 Kenney sprites, the 13 authored mono glyphs, the stretched frames — gets
brought to it. New art inherits the D39 contrast contract (worst-pixel, not average)
rather than being allowed to opt out of it.

**Not done here, on purpose.** No assets were drawn and no screens changed. The brief
names the files, their sizes, their paths and their hooks, and §4 lists the seven code
fixes that have to land or new art will sit on top of the same problems.

**The list itself is generated** — `tools/art_manifest.gd` → `ART_ASSETS.md`, 213
wanted, 3 present. Hand-typing 35 enemy names, 30 relics and 12 dungeon backdrops
would be a restated table, and a restated table has gone stale on this project three
times (D34): the 36th enemy would simply never appear on the list. The briefs are the
content's own `name` and `description`, so an artist is told what the game already
says a thing is rather than a second, drifting description of it. It reports which
files exist, so it doubles as the coverage report and is the natural backing for the
art-coverage test ART.md §4 asks for.

Writing it corrected two guesses in the brief. Card families are **12, not 24**: the
100 cards do fall into twelve effect families, but lopsidedly — 28 attack, 19 block,
12 poison, 8 thorns, then a tail of 2-5 — so splitting each family per zone would have
meant 60 variants serving three cards each. And the hero briefs presume an **arena**
layout (hero facing right, enemies facing left), which `combat.gd` does not have: it
stacks enemies at the top and the hand at the bottom with ~250px of nothing between.
That is now written down as a layout change rather than smuggled in as an art note.

It also reproduced the D57 glossary bug inside the generator — `%%` in a plain string
that never reaches a `%` operation, printed verbatim into the manifest. Caught by
reading the output, one commit after fixing the same thing in `glossary.gd`. Escapes
without an operation to escape into are apparently a habit worth watching for.

### D57 — Two bugs the renders found, and the assertion that was missing

Both defects came out of the D56 capture pass, and neither was findable any other way.

**The dice board was 0px tall.** `dice_run.gd` put the track in a `ScrollContainer`
and left both scroll modes at their `AUTO` default. A `ScrollContainer` contributes
its content's minimum size **only on axes where scrolling is DISABLED** — on a
scrollable axis it reports 0, because scrolling is how it copes with being too small.
So the board's minimum height was 0, the `SIZE_EXPAND_FILL` spacers either side of it
took every spare pixel, and all sixteen track cells were built on every refresh with
nowhere to be drawn. Four of the twelve dungeons use this traversal; on all four the
player saw no board.

The fix is one line — `vertical_scroll_mode = SCROLL_MODE_DISABLED` — and it is also
the honest statement of intent: the track scrolls sideways, never vertically.

**The glossary said "+50%% damage".** Two `_entry()` calls carried `%%` in plain
string literals. `%%` only collapses inside a `%` format operation, and those two
lines have none, so the escape was rendered verbatim to the player. The other four
`%%` in the codebase are all inside real format calls and are correct.

**Why nothing caught the board.** Every existing check passed throughout: the scene
loads, its script compiles, `_enabled_buttons()` finds the two move buttons enabled
and pressable, and `test_layout.gd` confirms `_scroll_to_token` exists — by reading
`dice_run.gd` as *text*, which is all a `--script` test can do without autoloads.
What no check asked was whether the content had a **size**.

`playable_test.gd` now asserts it, and deliberately as a *class* rather than as this
one screen: no `ScrollContainer` may be squeezed to zero on an axis whose content
needs pixels. The same shape would have hidden the map, the shop stock or the
collection just as silently. Verified both ways through `tests/run.sh` — red on all
four dice dungeons with the fix reverted (`a scroll area is 0px TALL holding 67px of
content`), green with it in. 34/34 suites pass.

This is D47 for the third time. Booting is not playability; passing is not looking
right either. The generalisation worth keeping: **a test that reads source text can
only confirm that code exists, never that it had an effect.**

One thing that looked like a third bug and was not: with the board finally visible,
no `^you` marker appears under any cell. `TraversalDice.pos` starts at `-1` — at the
entrance, not yet on the board — so no cell is the player's yet. Correct as written.

### D58 — A card must not lie about the fight either

D50 stopped cards misreporting their *level*. They went on misreporting the
*fight*. `CardData.effect_text()` is generated from `eff_damage()`, which knows
about fusion and nothing else, so with 3 Strength a card that dealt 9 still said
6 — and the buff itself was a "[Blk 5 Str 3]" fragment inside a run-on status
line. Reported from play as "gaining Strength is not visible during the game and
the card text stays the same", which is exactly right: the effect existed, and
nothing the player was looking at changed.

Three surfaces, one source. `CombatEngine.card_base_damage()` is what `_resolve()`
itself computes with, and `card_damage()` / `card_block()` run it through the same
`Combatant.outgoing_damage()` / `outgoing_block()` the resolution uses. The face
text, the hover text and the number on the card all read those. A second copy of
that arithmetic for display would be the D34 label table again.

* **The face carries the headline number**, always, not only on hover. A resting
  card showed its name and its cost, so the number could only be found by mousing
  over each card in turn — useless for the thing that changes when a buff lands.
  Damage in red, Block in blue. The strip hides again when the card opens, because
  the rules text then carries the same number and leaving it up squeezed the
  description to 11px, which `CardTextTest` correctly calls unreadable.
* **Buffs and debuffs get their own line**, spelled out — "Strength +4 (every
  attack hits harder)" — warm when they are yours, cold when they are being done
  to you.
* `Icons.card_tooltip()` takes the same two numbers, so the hover cannot disagree
  with the face.

`test_card_truth.gd` pins it with the assertion that a second agreeing copy of the
arithmetic could not satisfy: it plays the card and compares the number the face
promised against the HP the enemy actually lost. `CardTextTest` pins the visible
half — with 6 Strength, the number on the *resting* face must be the buffed one.

### D59 — Three places the game asked for a decision without showing the numbers

**The fight.** No draw or discard count, though the reward screen quotes draw
intervals ("every 3.0 turns instead of 2.8") and the shop sells deck thinning: the
player was asked to price consistency while blind to it. Unaffordable cards looked
exactly like affordable ones, and the only way to find out was to click and be
refused — they are dimmed now, and still clickable, because the refusal is how the
rule gets learned. The log kept one line, so a turn where three enemies acted
reported only the third; it keeps four.

**Dying.** Defeat was one line of status text followed by a forced 2.5 second wait
and a scene change. Escrow (D20), the Escape Rope (D21) and the death penalty (D3)
all exist to make that moment weigh, and it could not be read, let alone sat with.
`Defeat.tscn` now reports what killed you and where, what the run was carrying and
forfeited, what the penalty took from the collection, and — the part that stops a
loss reading as having undone the whole game — what survives it: relics, card
levels, banked gold. The player dismisses it themselves.

**Fusing.** The Collection quoted the price ("+1 (-4x, -180g)") and never the
gain. Since D35 fusion spends gold as well, that is an economic decision against
the shop with the benefit side missing. `CardData.level_up_text()` generates
"dmg 10→14, vuln 2→3" from the same getters the engine resolves with, shown on the
row and on every bulk button's hover.

All three are pinned by tests that were verified by reintroducing each bug in turn:
the piles vanish, every card looks playable, the log drops to one line, the defeat
screen loses its numbers, the fusion preview stops naming the before and after.

### D60 — The dodge nobody had ever measured

Every cell of the balance report read `0.0 avoided`. The deck model's entire
decision — face this encounter, or pay HP to skip it and forfeit the loot — had
never been exercised, because the simulator's driver only reached for Avoid below
35% HP, and a greedy player is rarely sitting there. `DECK_AVOID_HP_COST` had
therefore never been calibrated against anything at all. Same class of blind spot
as the pure-debuff cards the sim never played and the poison-only cards it could
not value: **a mechanic the driver ignores reads as a mechanic that does not
matter.**

The driver now decides it the way a player does — on what fights have been costing
it. `cost_est` is a running average of HP lost per encounter type, learned across
the trials of a cell and carried between them, which is the same thing as a player
who has walked this dungeon before. It dodges when the fight is dearer than the
dodge (with a bias toward facing, because the loot is worth some HP) or when the
fight's average cost is close enough to what is left that facing it is a coin flip.

The tool also measures the two degenerate lines of play, because the property that
matters is D20's — a dominant strategy is a removed decision:

| | face everything | smart | avoid everything |
|---|---|---|---|
| Drowned Market, AoE Lv15 | 49% | **87%** | 87% |
| Slag Pits, Thorns Lv15 | 97% | 100% | 100% |

Skipping every fight was strictly better, and the reason is that a **flat** 8 HP
gets cheaper the deeper you go while fights get dearer: at the Drowned Market, four
dodges cost 32 of a 110-point health bar, against fights costing 17-31% each. Every
deck-dungeon number ever reported was measuring a line of play no sensible player
would take.

The price now scales with depth *and* rises with each dodge already taken this run
— the same shape as `removal_price`, and derived from the dungeon's difficulty
rather than the player's max HP, because a Traversal must never read run resources
(D13). Tuned so dodging everything costs ~70% of the bar and arrives at the boss
with no gold and no rewards. After: SMART is at least as good as both fixed lines
everywhere, always-avoid now *loses* (57% vs 61% facing at the Drowned Market), and
the smart line dodges 22-56% of what it could — situational, which is the point.

`tests/test_traversal.gd` pins it structurally rather than by simulation: the cost
must rise per dodge, dodging every fight must cost at least half a health bar, one
dodge must still be affordable (under a quarter), and depth must matter. Verified
by restoring the flat 8 — it names every dungeon.

### D61 — Making the fight move

Nothing in this game had ever animated. `_refresh()` freed the entire enemy row and
the entire hand and rebuilt them on every action, so HP numbers jumped, nothing
flashed, and a played card blinked out of existence. That rebuild is also *why*
nothing could animate: you cannot tween between two states when one of them has
been deleted.

**The refactor is the feature.** Enemy plates are built once and mutated. The hand
is diffed — cards that stayed keep their node, cards that left are flown out, cards
that arrived are dealt in. `UI.card_button` grew a `relabel` hook so a card already
on screen can re-read its live numbers when a buff lands, instead of being
destroyed and rebuilt to say a different number.

On top of that, deliberately short (a card game is read; an animation you wait
through is worse than none):

* floating damage and healing numbers, derived by diffing real HP before and after
  an action rather than by parsing the log line;
* a red tint and a jolt on whatever was hit — the jolt moves the plate's own
  position, so the row never reflows;
* a screen flash when the player is hit, scaled by how hard, because the player has
  no plate to shake;
* played cards fly out of the hand and drawn cards fade in.

Feedback lives on its own full-rect layer above the layout, mouse-deaf, and a
played card is *reparented* onto it rather than left in `hand_box` — the hand must
contain real cards only, because that is what both the screen and the tests count.

The load-bearing test is the invisible one: **a card that stays in hand must keep
the same node across a refresh.** Damage numbers and flashes get noticed when they
go missing; a future edit that quietly goes back to rebuilding would take every
animation with it and leave the screen looking perfectly correct in a screenshot.
Verified by putting the rebuild back — the test names it. The floating number is
also checked for actually *moving*, since a tween that was never started looks
exactly like a label parked on the spot.

### D62 — The fight is framed head-on, and nobody plays the hero

The art brief specced a side-on arena: hero on the left facing right, enemies facing
left, both in the empty middle band. Four hero files, and a layout change to hold
them. The alternative, chosen instead: **frame the fight head-on into the corridor
the backdrop paints, and do not draw the player at all.**

Measured first, because the backdrops decide this:

| | size | floor meets wall | luminance top → bottom |
|---|---|---|---|
| `bg_crypt` | 1280×720 | 71% down | 0.14 → 0.20 |
| `bg_ossuary` | 1280×720 | 66% down | 0.21 → 0.25 |
| `bg_warrens` | 1280×720 | 66% down | 0.20 → 0.27 |

All three are symmetric one-point corridors (asymmetry 0.02-0.06), so a frontal fan
uses that perspective where a side-on arena fights it. All three put the floor at
~68%, which is a shared standing line. And the floor is the *brightest* band in every
one, which is a real constraint on the sprites: weight them low and dark or their
feet dissolve into it.

It also deletes work instead of deferring it — no facing to match, no idle/hurt set
to keep consistent across 35 enemies, no hero-to-monster scale to hold — and it makes
the feedback from D61 correct rather than provisional: with no body on screen, an
incoming hit reading as a screen flash and a jolt toward the camera is the right
answer, not a stand-in for an animation nobody drew.

**The layout had to be measured before it could be built.** Stacked as rows the way
combat.gd was, at 1280×720 and scale 1.0, the fixed bands (header 50, buffs 22, log
80, piles 22, hand 132, bar 50, six separators 96) left **236px** for a sprite that
wants 240-270 — and the stage bottomed out at y≈468, **22px above the painted floor at
y≈490**. No amount of shrinking fixes that; the stage had to stop being a row and
become a layer. Enemies are now placed by hand on a full-rect stage with the HUD and
the hand floating over them, which is also what lets `_hit()` jolt a slot without a
container snapping it back.

Per the player's call, **vitals live in the top band, not beside the hand**: HP,
Block, Energy, incoming and the pile counts sit with the exit, and the bottom of the
screen belongs to the cards. The log dropped from four lines to two and moved to the
bottom corner — four lines of running commentary across a painted corridor is exactly
what would ruin the framing.

Each enemy slot carries its name and HP, its intent above its head, a contact mark on
the floor line that doubles as the target ring, and a hit area over the whole
silhouette. Bosses take 1.34× the frame and elites 1.14×, so a fight announces what it
is before the numbers do.

**Placeholders that read as placeholders.** With no painted enemies yet, the first
render blew a 16×16 CC0 sprite up to 240px and the white pixel mass dominated the
frame so completely that the composition could not be judged at all. The stand-in is
now a dark silhouette at 52% of the footprint with the intended footprint outlined
around it, so the frame can be composed before anything is drawn.

Three things landed with it so the 210-file art pass can be generated against a
contract the game enforces:

* `PixelArt.enemy_art(id)` — painted enemies keyed by **archetype id** in their own
  directory. The existing pixel sprites are assigned by position in a sorted
  directory listing, so a correctly-named file dropped in *there* is handed to
  whichever archetype the sort order reaches: 35 right files, 35 wrong enemies, and
  the only symptom is "the art looks wrong".
* `tests/test_art.gd` measures every painted backdrop's floor line, prints it, and
  fails when one lands more than 10 points off `FLOOR_LINE`. The measurement is a
  heuristic (largest row-to-row luminance step in the lower half), so it is
  deliberately loose — a flaky assertion about a painting would be worse than none.
  Verified by moving `FLOOR_LINE` to 0.45: it names all three backdrops.
* The brief itself was regenerated, not edited — `tools/art_manifest.gd` owns that
  text. Tier 1a is now empty with the reasoning in it, the enemy brief says facing
  the viewer, feet flush to the bottom edge, weight low and dark, and *not* in the
  positional directory. 213 files became **209**.

### D63 — The bottom of the screen, laid out properly

D62 put the vitals in the top band at the player's request; they are back at the
bottom, at the same player's request, and this time the whole bottom band was
designed around the hand rather than stacked above it.

* **Vitals bottom-left** — HP and Block on one line, Energy and incoming on the
  next, with the buffs, the pile counts and the two-line log under them. Energy
  gates every click a turn contains and HP is what every decision is spent against,
  so both belong where the eye already is while cards are being read.
* **The hand is a fan** — placed and rotated by `_place_hand()`, cards overlapping,
  the middle of the fan riding highest, each tilted a little. Overlapping is what
  makes a hand of nine cards possible at all; side by side they either run off the
  frame or shrink until nothing on them can be read. The trade is that a resting
  card is partly covered, which is why hovering one **straightens it, lifts it clear
  of its neighbours and enlarges it** — `UI.card_button` reads a `fan` meta the
  combat screen sets, so the widget owns its own hover and the screen owns the
  layout.
* **The power is a round sigil** rather than a 260px bar: it is one
  always-available ability with a cost, which is a hero power, not a menu entry. Its
  state reads on the ring, because at that size the words are too small to carry it.
* **End Turn is a small corner button.** It is pressed once a turn and never in a
  hurry. The two of them together used to occupy the full width of the frame the
  fight is supposed to be in.

**Four bugs, and only one of them was found by a test.** Worth listing because they
are the same shape each time — a layout that cannot be judged without looking at it:

1. `set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, ...)` puts the box's TOP edge
   on the bottom of the screen, so the entire HUD and both controls rendered
   *below* the frame. Anchors and offsets are now written out.
2. **`var hand_box: HBoxContainer` with a `Control` assigned to it.** GDScript
   rejects that at RUNTIME, not compile time, so `test_compile` passed, `hand_box`
   stayed null, every card silently failed to be added, and the fight rendered with
   no hand at all. `PlayableTest` caught it only because the piles text is built in
   the same function. Third time a stale restatement has done real damage (D34, D49).
3. The vitals were one title-size line measuring ~530px, which **overflowed its
   380px box** — a Label overflows rather than clips — and passed under the leftmost
   card. Two wrapped lines now, and the hand measures the real widget rects instead
   of a reserve read off a screenshot.
4. The fan was centred without accounting for the **width** of its outermost cards,
   so `room / n` put the leftmost card's edge 21px inside the vitals. The render did
   not show it; the new geometry test did.

`CardTextTest` now measures the hand: every card inside the frame on both axes, at
least three distinct angles (it is a fan, not a row), the middle of the fan higher
than its ends, and no card intersecting the vitals, the power or End Turn. Three of
the four bugs above would have been caught by it, and it is the only thing that will
keep them fixed — a still image cannot.

### D64 — The horizon is not the standing line

Play feedback on D62's framing: the enemies sit too high, they should come closer
to the cards. Correct, and the cause was two different things sharing one constant.

`FLOOR_LINE` was measured as the wall/floor junction of the painted backdrops (68%),
and then used as the place combatants stand. But in one-point perspective the floor
spans a *range* of depths, and the junction is its far end — so every enemy was
standing as far away as the room allows, which is exactly how it read: small,
distant, detached from the fight.

Split in two. `HORIZON_LINE` (0.68) is a property of the painting and is what
`tests/test_art.gd` measures every backdrop against. `STAND_LINE` (0.72) is where
feet go: on the floor, nearer the viewer, and clamped at runtime to stay clear of
the top of the hand so the two can never collide at another UI scale. Enemies also
grew from 34% to 38% of the frame, because something closer to the camera is bigger.
The test asserts the stand line is *below* the horizon — above it, a figure is
standing in the back wall.

**And the four bugs from D63 got their tests.** Asked directly whether they had been
covered, three had and one had not:

| bug | covered by |
|---|---|
| card off the bottom edge | new: every card rect inside the frame |
| vitals label overflowing under the hand | new: no card intersects the vitals, power or End Turn |
| fan centred without card width | same check — it is what caught it in the first place |
| **HUD anchored off screen entirely** | **nothing** |

The last one is the one worth having: `PRESET_BOTTOM_LEFT` put the whole bottom band
below the frame and *no test noticed*, because every check in the suite was about
cards. `CardTextTest` now walks the vitals, buffs, piles, log, power, End Turn, Menu
and place name and fails if any of them leaves the frame — D33's "actionable content
must be on screen", applied to the widgets that did not exist when D33 was written.
Verified by re-anchoring the HUD off screen: it names three of them.

**The new assertions were themselves measuring the wrong window.** They passed on a
1280×**1280** viewport, because headless defaults to square and `CardTextTest` had
never needed a window size before — it only measured font sizes. Every geometry
check had 560 pixels of vertical slack the player does not have. It now sets the
shipped size the way `PlayableTest` does, which is where that trap was already
written down. A test measuring the wrong frame is worse than no test, because it
reports the thing as covered.

### D65 — The UI scale was a second scale

The interface had a zoom: `Ctrl +/-`, `Ctrl+0`, a settings slider from 0.8 to 2.6,
and a persisted value. Removed entirely. The layout is a fixed 1280x720 and F11
toggles fullscreen; nothing else resizes.

**It was redundant with a mechanism that already works.** `project.godot` sets
`stretch/mode = "canvas_items"` against a 1280x720 base, so the engine scales the
whole canvas to the window on its own. Measured rather than assumed:

| window | viewport, in layout units |
|---|---|
| 1280x720 | 1280x720 |
| 640x360 | 1280x720 |
| 1920x1080 | 1280x720 |
| 1024x768 | 1280x960 *(aspect "expand" adds units on the short axis)* |

So a smaller window already shrinks everything, fullscreen already fills the
display, and the layout never reflows — it is a clean scale-up or scale-down of one
composition. A second multiplier on top could only ever disagree with the layout it
was laid out for, and it repeatedly did: the zoom is what put the map's only
actionable row below the window (D33), what collapsed the button frames when the
default moved (D49), and what a restated default in `settings_state.gd` silently
overrode for every new player (D53). Three separate incidents from one knob that was
never needed.

It also had a real cost for the art pass now starting: every asset size, every
nine-slice margin and every layout constant had to be reasoned about across a
0.6-3.0 range that no longer exists.

Gone with it: `UITheme.set_scale()` / `set_scale_silent()`, `SettingsState.ui_scale`
(an older settings file may still contain the key; it is read by nobody and not
carried forward), the slider, and the `set_scale_silent` calls four tests and the
screenshot tool were making to force a scale they now get for free.
`tests/test_layout.gd` fails if a setter comes back.

The art brief was regenerated to say what is now true: assets are still authored at
2x, not because a slider might enlarge them, but because a 1440p display draws every
one of them at 2x and a 4K display at 3x.

**One thing to know about the aspect row above.** At a non-16:9 window the viewport
gains units on the short axis rather than letterboxing, so the frame gets taller (or
wider) in layout units. The combat layout reads `get_viewport_rect()` for the stand
line and the hand, so it adapts — but the painted backdrops are `KEEP_ASPECT_COVERED`
and will crop, which moves their horizon away from the 68% the enemies stand
against. Not fixed here; 16:9 is what the game is composed for, and the alternative
(letterbox bars) trades a visible black frame for an invisible one.

### D66 — Cards that read the fight

Asked what would make the game more fun, the honest answer was in the data model:
`CardData` had 31 exported fields and **not one of them was conditional**. No "for
each", no "if you played", no "when you gain". Every card was a self-contained
arithmetic packet — deal N, block N, apply N — so a turn was "spend three energy on
the biggest numbers", nothing you drew made anything else better, and a deck never
became an *engine*. Three cards of a hundred read any state at all (`strength_mult`,
`damage_from_block`, `grows`).

Six new fields, one per existing build, chosen so a build is a set of cards that
multiply each other rather than a shared tag:

| build | mechanic | on |
|---|---|---|
| poison | `damage_per_poison` | Rupture, Scrape |
| thorns | `damage_per_thorns` | Riposte, Molten Core |
| status | `bonus_vs_debuffed` | Iron Wave, Cheap Shot |
| tempo | `combo_at` / `combo_bonus` | Shiv, Cut and Run, Dagger Throw |
| swarm | `energy_on_kill` | Cull, Sword Dance, Riptide |
| fortress | `block_per_card_in_hand` | Guard, Shield Wall |

Fourteen existing cards were rewritten rather than fourteen added: the set stays at
100 with its rarity distribution intact, and D18 already says a rare's job is to
*enable a build*. Base numbers came **down** where a conditional went on, so the
ceiling rises and the floor falls — that is what makes it a build card instead of a
strictly better card.

All of it resolves in `card_base_damage()` / `card_block()`, which is what the card
FACE reads (D58). A card that says 9 and hits for 17 because the target is poisoned
would be the same lie in a more confusing form.

**Pricing was wrong twice, in both directions, and the measurements caught it.**
Every mechanic must be in `power_value()` or enemy scaling silently falls behind the
decks using it. First pass assumed "~4 stacks", which is what a deck that *happens
to draw* the card holds, not what a deck built for it holds:

| | before | after first pricing | after calibration |
|---|---|---|---|
| Thorns build @ the Maw | 40% | **69%** (ratio *fell* 3.76 → 3.54) | 61% |
| Poison build @ Rot Gardens | 89% | 85% | 87% |

A build whose completion jumps while its priced ratio *falls* is D28's exact signal:
power delivered without being charged for. Per-stack weights went to 3.5 (poison)
and 5.0 (thorns). Thorns stays high at the Maw and further pricing barely moves it —
because the rest of that gap is not mispricing but a genuine interaction: the Maw is
now elite-heavy, thorns punishes attackers, and a deck built to hurt things that hit
you does well in a dungeon full of things that hit you. That is the texture this and
D67 exist to create, so it is left alone.

`tests/test_mechanics.gd` asserts each one both ways: the number actually changes
(a poisoned target takes more, a fuller hand blocks more, a kill refunds energy and
a non-kill does not) *and* stripping the field lowers `power_value()`.

### D67 — Twelve dungeons, twelve shapes

Every dungeon drew from ONE global mix — 3 combats, 1 elite, 1 rest, 1 shop,
1 event, 1 treasure — so the Crypt and the Maw had identical rhythms and twelve
dungeons were one dungeon with different wallpaper and bigger numbers.

The mix moved onto `DungeonData` (`enc_*`, -1 meaning "use the default"), and the
three traversal models all build from it, so a place can be a swarm, a market, a
climb or a treasure run:

| | shape | what it is |
|---|---|---|
| The Warrens | 5 fights, no elite | a swarm: nothing here is elite, there is simply a lot of it |
| The Foundry | 3 + **2 elites** | the wall the early game breaks on |
| The Fungal Deep | 2 rests, 2 events, no shop | it grows back, and the deep is strange |
| The Sunken Vault | **3 treasures** | a treasure run: fewer fights, more to carry out |
| The Drowned Market | **2 shops, no rest** | the market: nowhere to sleep |
| The Maw | **2 combats, 2 elites** | short, and nothing in it is ordinary |

**The first pass made shape into a second difficulty axis, which it must not be.**
Fight counts were free to climb with depth, and did: the Abyssal Stair and the Maw
each ran six fights against the default four, on top of already being d7 and d8.

    Abyssal Stair, Late deck   69% -> 20%
    The Maw, Late deck         49% -> 22%
    Ember Road, Status build   63% -> 31%   (no rest at all is a wall, not a road)

Fight count is now deliberately *uncorrelated* with depth — deep dungeons get fewer,
heavier fights (the Maw is 2 combats and 2 elites, not 4 and 2) and shallow ones can
afford more, cheaper ones. After: the Maw reads 61/44/69% by deck strength and the
Stair 56/46/75%, against a D54 baseline of 40/49/70.

`tests/test_traversal.gd` polices the shapes so the mix cannot become a back door
onto the difficulty curve: 8-11 encounters, 3-6 fights, at least two things that are
not a fight, at least six distinct shapes across the twelve, and — unchanged — all
three models must still spend whatever budget a dungeon asks for, compared now
against the mean of the per-dungeon budgets rather than one global number.

### D68 — The elite drops a relic, and escrow holds it

An elite was a harder fight for more gold: a stat check, not a decision. It drops a
relic now, which is also the mid-run "this run is special" spike the game did not
have — `grant_relic` was called from exactly two places, beating a boss and an event
that happened to roll one.

**It goes into escrow, not into the collection.** Granting it immediately would
reopen the hole D20 was built to close, with a different noun: kill the elite, die
on purpose, keep the relic. `MetaState.pick_relic()` splits rolling from taking so
the elite path can hold one at risk; `commit_escrow` banks it on the boss (or a
rope), `forfeit_escrow` loses it, and `run_to_dict` carries it through a quit —
otherwise the escrow is a lie the moment somebody reloads. Relics are still never
lost once banked (D11); they are simply not banked until the run is finished.

### D69 — The plateau was an incentive, not a difficulty

Measured across the whole game, the curve read: **wall, plateau, wall.**

    Crypt 92%  Ossuary 68%  Warrens 100%  |  Foundry 28%  |
    Ember 100%  Slag 100%  Fungal 100%  Rot 100%  Vault 100%  |
    Market 8%  Stair 8%  Maw 16%

Five consecutive dungeons with no resistance in them. The tempting fix — make d3-d5
harder — would have been wrong: the D36 ratchet *means* you to outgrow a place, and
each of those caps at `1.4 + 0.73 x (depth - 1)`, which a mid deck passes on purpose.

The real problem was the incentive. Re-clearing a dungeon you had already beaten at
100% was the safest income in the game, so farming the flat middle strictly beat
risking the next depth. Nothing was too easy; the easy thing paid too well.

`Balance.repeat_reward_mult()` makes ground already taken pay less — full price the
first time, then 0.45 per clear down to a floor of 0.25 — applied to gold and to the
reward rarity tilt. The floor is deliberate: a build's cards live in specific places
and you may need to go back for one, so returning stays possible, it is simply no
longer the efficient way to get stronger. `MetaState.clear_counts` records how well
trodden each dungeon is (SAVE_VERSION 6; an existing save's cleared dungeons migrate
to exactly one clear each, so nobody is charged for history the file never kept).

### D70 — Two art paths with no code behind them

Wiring the enemy art (D62) covered one of three. Two remained where a correctly
named file would have sat on disk doing nothing, which is the worst kind of gap
because it reads as an art problem:

* **Card illustrations.** `card_art()` sliced a CC0 atlas by position and had no
  file path at all. Now `cards/<card_id>.png`, then `cards/<family>.png`, then the
  atlas — id first, family second, exactly as ART_ASSETS describes.
* **The frame kit.** Two of its 24 files had hooks. Buttons now take per-state
  paintings, and the panel, tooltip, dropdown, slider, scrollbar, checkbox and the
  card frame (per rarity) all light up the moment their file appears. Each is "use
  it if it exists, else keep exactly what ships", so the kit can arrive one file at
  a time.

**The generator had a private copy of the card taxonomy.** `art_manifest.gd` carried
its own `_family()` — twelve families — while the runtime resolved seven, under
filenames that did not match (`cards/family_x.png` against the `cards/x.png` the
loader looks for). Five of the paintings it asked for could never have loaded and
the other seven would have been sought under other names. A document is generated
precisely so it cannot drift from the code; a generator with its own lookup table is
the D34 bug with better manners. `Icons.card_family()` is now the one function, the
manifest calls it, and `tests/test_art.gd` fails if a private copy comes back.

**And the autoload trap, for the fourth time.** `Icons` reached for `UITheme.kit()`
while this was being wired. UITheme is an autoload, autoloads are not registered in
`--script` runs, and the symptom is not a failure — three suites **hung**, because
the parse error skips the `quit()`. The lookup moved to `PixelArt` (a plain
class_name), and `tests/test_layout.gd` now greps the four classes the headless
suite loads for bare autoload calls, ignoring comments. Verified by putting the call
back.

### D71 — The merchant sold nothing, because prices were flat and income is not

Reported from play as "the merchant is bugged, it never sells anything". The
purchase code was fine — driven headless, a buy correctly moved gold 999→959, the
run deck 12→13, escrow_cards 0→1 and marked the entry `sold`. The bug was economic.

Shop prices were **flat gold at every depth**: common 40, uncommon 63, rare 103,
epic 179, legendary 400, heal 42, removal 55. Income is not flat — `gold_reward`
scales with `GOLD_DEPTH_EXP` (1.8). A Crypt fight pays 5-10 gold and the shop sits
at row 2-4 of the map, so the player arrives holding almost nothing.

**Measured, 400 generated Crypt maps, first run, 0 banked gold, walking a legal
path that takes the shop as soon as it is reachable:** median 20 gold in hand
against a cheapest item of 40, and **nothing at all affordable on 74% of visits**.
The 26% that could buy something had a treasure node (25-60 gold) fall first. A
full Crypt clear earns 91 gold, so the money exists — it arrives after the shop,
and the shop is one-shot (`_on_leave` clears the stock and the node is cleared).
At the other end it inverts: the Maw pays 46-51 per fight against the same 40-gold
common.

**Prices are now quoted in FIGHTS.** `fight_income(difficulty)` is one average
fight's takings, and every shop price is a multiple of it: a common is
`SHOP_COMMON_IN_FIGHTS` (2.0), a heal 2.5, a removal 3.0 rising 2.0 per removal
already taken. A purchase costs the same amount of *play* at every depth, and the
price cannot drift from the income curve because it is computed from it. Common
now runs 14g at d1 to 96g at d8; one fight pays 7g and 48g respectively.

Re-measured with a natural policy over a whole run: **67-90% of runs containing a
shop now get at least one usable purchase**, 0.7-1.1 items bought per run, flat
across all twelve dungeons.

**One copy of the rarity multiplier.** `card_price` and `fuse_gold_cost` each
carried their own `sqrt(common / weight)`, with a comment on the second saying it
was deliberately the same as the first — the D34 restated-table shape, and the
reason pricing cards by depth risked silently repricing every fusion in the game.
Extracted to `rarity_price_mult()`; depth is an argument to the shop price and
fusion simply does not take one. Fusion costs are pinned unchanged at
[20, 32, 52, 89, 200], and `test_shop.gd` now fails if a second copy of that
formula appears.

Anything bought OUTSIDE a dungeon has no run to take a difficulty from, so
`card_price` defaults to `mid_difficulty()` — derived from the dungeons that exist,
not restated. `test_shop.gd` already reasoned this way, measuring legendary
affordability at mid depth because "pricing the rarest card against the poorest
floor would call every legendary unobtainable"; that was the right instinct applied
to the test instead of to the price. `power_price` moves only 80→72 at common.

**The sim moved, and it moved at depth.** Measured by isolation, not by comparing
against an older commit: one worktree at the same HEAD with *only* the three price
formulas reverted to flat, against the tree as it stands. The first attempt did
compare against an older commit and was worthless — D68/D69 landed in `balance.gd`
underneath it mid-measurement, so reward changes and price changes were mixed into
one number. 19 of 34 comparable RUN cells moved; the shallow ones by ±1-3, the deep
ones by 7-15:

```
Endgame (Lv100)     The Maw             69% -> 54%   (-15)
Late (Lv40+6)       The Abyssal Stair   49% -> 35%   (-14)
Late (Lv40+6)       The Maw             44% -> 30%   (-14)
Thorns build        The Maw             61% -> 50%   (-11)
AoE build           The Drowned Market  62% -> 55%    (-7)
Endgame (Lv100)     The Abyssal Stair   71% -> 64%    (-7)
Status build        The Ember Road      43% -> 46%    (+3)
Status build        The Foundry         65% -> 77%   (+12)
```

The cause is heal pricing specifically: healing is the only mitigation the simulator
buys at a shop, and a 42-gold salve at d8 was under one fight's takings — free, in
effect, exactly where survival is supposed to be the question. The two `+` outliers
are the shallow end getting cards it could not previously afford.

Every deep cell moved *toward* the documented target band (~50-70% matched, <20%
over-reaching) rather than away: the Maw at Endgame from above the band into the
middle of it, Late at the Maw from 44% to 30% while over-reaching. It is nonetheless
a real difficulty change riding on a bug fix that did not ask for one, and it should
be judged as such rather than waved through because the arrows point the right way.
If the endgame should keep its old slack, the lever is `SHOP_HEAL_IN_FIGHTS` alone —
the card and removal prices carry no HP curve at all.

**Also fixed: the screen would not say why.** An unaffordable button read a bare
`"40 g"`, greyed, with no hint that you had 20 and needed 40 — so the one screen
that had to explain itself explained nothing, and it read as a broken button rather
than an expensive one. All three now state the shortfall and carry a tooltip, the
same shape `combat.gd:_refresh_power()` already used ("Needs %d energy, you have
%d"). The removal button had two silent refusal reasons (no gold, deck at minimum)
and now distinguishes them.

**Found while measuring, not fixed here:** the Ossuary's encounter deck contains
**no Shop at all** — 200 generated piles, zero shops (Combat, Elite, Event, Rest,
Treasure, BOSS only). The Warrens has no Elite and no Treasure. Those are content
gaps in `resources/dungeons/*.tres`, not pricing, and repricing the shop cannot
reach a dungeon that never offers one.

### D72 — The simulator was measuring a weaker player than the game gives you

Reported from play: the first dungeons feel easy, and the simulator disagrees. It
did, and the simulator was wrong. Its model of the player had drifted from the
game in four separate ways, every one of which made the tool pessimistic, and all
four produced perfectly plausible numbers.

**1. The health bar.** The game grows max HP with dungeons *cleared*; the sim grew
it with the *difficulty of the dungeon being measured*.

    game:  BASE_MAX_HP + relics + clears x HP_PER_DUNGEON
    sim:   BASE_MAX_HP + relics + (difficulty - 1) x HP_PER_DUNGEON

A player with six clears walking into the Crypt has 120 HP. The sim gave that run
60 — half the bar — and reported the opening of the game as about twice as
dangerous as it is. `Balance.max_hp_for()` is the one formula now; the game itself
had *two* copies of it before the sim's third.

**2. No Power.** `eng.setup()` takes the equipped ability as its ninth argument and
the sim passed eight. Every run was measured without the once-per-turn ability that
every save carries — less throughput than the player has, and a lower ratio than
they are scaled against.

**3. The wrong boss.** It passed no `p_boss`, so every finale was a random roster
enemy wearing boss multipliers — precisely the bug D41 fixed *in the game* and never
in the tool. All balance work since D41 was tuned against a boss the player never
meets.

**4. A deck that never grew.** The sim held its deck fixed for a whole run while a
real player takes a card at nearly every encounter (D1), arriving at the boss five
to eight cards richer. It fought the finale with the opening deck.

There is a fifth, subtler one: `clears` is now derived per cell as
`max(profile, Balance.effective_gate(dungeon))`, because you cannot be standing in
the Maw without having cleared the eight things that open it. Written per cell it
would go stale the first time a zone requirement moved.

The opening now measures the way it plays:

| | before | after |
|---|---|---|
| Starter @ Crypt | 99% | 99% |
| Early @ Crypt | 98% | **100%** |
| Early @ Foundry | 41% | **60%** |
| Mid @ Foundry | 98% | **100%** |
| Status @ Ember Road | 42% | **81%** |

and the deep end still resists: the Maw reads 41% for a late deck and 71% for a
maxed one, the Abyssal Stair 20-66%.

`tests/test_balance.gd` now reads the simulator's source and fails if it restates
the HP formula or stops modelling the Power, the named boss, the cards won during a
run, or the gate a dungeon sits behind. A tool cannot be unit-tested into honesty,
but it can be stopped from quietly dropping the player's equipment again — verified
by putting the old HP formula back.

### D73 — Twelve painted rooms, and the filename is the wiring

All nine missing dungeon backdrops arrived as generated images, so every dungeon now
fights in a painted room instead of on a 16×16 tinted tile. What is worth writing
down is not the art but the three things that could have made installing it silently
useless.

**The filename IS the wiring.** `PixelArt.battle_art()` resolves
`assets/art/bg_<dungeon_id>.png` by convention — no `@export`, no catalogue line. A
backdrop dropped in as `bg_rot_gardgens.png` (the source file carried exactly that
typo) loads nothing and the dungeon keeps its fallback tile, which looks identical
to "the art was never made". `tools/install_backdrops.gd` therefore checks every
target against `Balance.DUNGEONS` before writing a byte, and reports what is *still*
missing afterwards so a partial delivery cannot read as a complete one. It caught
two mismatches on the way in: `rot gardgens` → `rot_gardens`, and `maw` → `the_maw`.

**Contrast was measured before installing, not after.** `menu_art_test.gd` gates
these at 3.0:1 worst-pixel for white text over the top band, after the D39 dim and
scrim. Reimplementing that arithmetic outside the engine and running it on the
source files took a minute and meant nothing was committed on the hope it would
pass. All twelve now measure 6.1–9.5:1 — the new nine at 6.4–9.5, the three older
ones unchanged at 6.1–6.7.

**Resized to the shipped 1280×720.** They arrived at 1376×768, a 0.8% wider aspect.
`STRETCH_KEEP_ASPECT_COVERED` would have absorbed it invisibly, so this is about
weight, not correctness: nine files at 2.2–2.6 MB would have added ~19 MB to a 12 MB
repository. At 1280×720 they are 1.6–2.0 MB, matching the three that were already
there and the size ART.md specifies. If high-DPI ever matters, that is a decision
for all twelve at once, not a side effect of an install.

The art itself holds the brief: one-point symmetrical composition, ink weight
matching `bg_crypt.png` rather than the heavier `bg_warrens.png`, the zone accent
carrying the light (Foundry orange, Rot acid-green, Deeps blue, Beyond magenta), and
**no readable text painted in** — the Foundry's door plaque is deliberately blank,
and the runes on the ceilings are decorative script, not words. `bg_warrens.png`
still has its "THE WARRENS" sign and is still the one that needs redrawing.

**A restated number, one more time.** The generator's Tier 5 blurb said "nine of
twelve dungeons fall back to a 16×16 tinted tile" as a hardcoded string, and was
therefore wrong the moment the first file landed. It counts now
(`_backdrop_gap()`). Fourth instance of the same habit in this log; the manifest
exists precisely because hand-typed lists rot, and it had one typed into it anyway.

Remaining backdrop work is the eleven that are not dungeons: five zone establishing
shots and six scene rooms (shop, rest, event, treasure, victory, defeat).

### D74 — A fourth way to walk a dungeon: an isometric floor, because the best of the other three was the problem

Play report, and it is not a bug report: *"the Slay-the-Spire version is the best out
of the three, but it makes the game too similar to Slay the Spire."* All three
existing models are abstractions of a **route** — a layered graph you commit to
blind (D6), a stack of encounters you draw and can pay to dodge (D13), a track you
roll along and overshoot (D14). None of them is a *place*. The one that feels best
is the one that reads most like the game it is standing next to.

So: a fourth model, `TraversalIso`, deliberately built as a placeholder to answer
one question — does crawling a floor feel like something this game should be? — and
plugged into a dungeon that is open on a fresh save, so the answer can be had by
playing rather than by reasoning.

**What is different about it.** It is the only model where the ground is spatial and
can be re-walked. A floor is a grid of rooms carved out of a 6×6 plate; you stand in
one, and your options are the doors out of it. The torch shows the room you are in
and the rooms adjoining it, and nothing further. **The stair down is not marked** —
it is somewhere on the floor. So the run is a question of coverage rather than
route: how much of the floor do you strip before you take the stairs you have just
found?

Two rules turn that from a chore into a decision:

* **Every room holds something.** There are no empty corridors padding the floor, so
  a route is a plan and not a walk to a marked exit.
* **Light runs out.** `torch = rooms × 1.4` pays for a tidy tour of the whole floor.
  It does not pay for crossing explored ground twice more to come back for the last
  treasure. Past that, every step costs HP (`Balance.iso_dark_cost`, `2 + depth-1`).
  This is the mirror of the deck model's priced dodge: there you pay to see *less* of
  a dungeon, here you pay to see *more* of one.

**Keeping the shared budget.** The contract (D14) is that every model costs a
comparable attrition budget, or a difficulty rating stops meaning one thing. A
spatial model can break that *geometrically*, in two ways, and both are now closed:

* The floor carves exactly `budget + 2` rooms — one per budgeted encounter, plus the
  entrance and the stair — and `tests/test_traversal.gd` fails if the grid cannot
  hold them, because the surplus would otherwise be dropped silently during
  generation and the dungeon would quietly become cheaper than itself.
* The stair goes in the room **furthest from the entrance**, and `options()` sorts it
  **last** while any room is still unexplored. That ordering is not decoration: it is
  what makes a greedy driver — the simulator, and a player leaning on the first
  button — spend a whole floor instead of beelining. Measured over 30 runs of all 12
  dungeons: ISO averages **9.2 encounters** against a budget of 9.2, the same as
  GRAPH (9.2), DECK (9.2) and DICE (9.1).

**The deadlock the contract test caught.** Ordering the stair last created a
loop that no amount of reading the code would have found: on a floor where the
*short* way to the remaining rooms ran through the stair room, the "one step closer"
ordering pointed at a room the ranking then refused to enter, and the walker paced
between two rooms for ever. It failed in 3 runs of 360 — a rate that would have
looked like a hang in play and like nothing at all in a diff. The fix is that the
stair is neither a destination nor a **way through** while there is floor left, which
is also simply true: nobody walks through the boss to reach a shop. That cannot cut
the floor in two, and the reason is worth writing down: the stair sits at the
furthest room from the entrance, and a furthest room can never be the only way to
anywhere — whatever was behind it would be further still.

**The entrance is two constraints, and each fix broke the other one.** The carve
seeds from the middle of the grid and grows outward, so the seed room was usually a
stub with a single exit: the run opened on one button, where every other model opens
on a choice. Taking the room with the **most** doors instead fixed that and quietly
broke something worse — the most-connected room is the hub in the middle of the
plate, and from the middle the furthest room is *two steps away*, so the stair was
placed two steps from the entrance and the entire floor could be skipped by walking
into it. The entrance is now the room, **of those with at least two doors**, that the
floor stretches furthest from. Measured over 3000 generated floors: the entrance
always has 2-4 doors, and the stair sits 4 to 8 steps away (mode 5) on a ten-room
floor carrying 14 torch — so a tidy tour is affordable and a completionist's last
detour is not. Both halves are now asserted, because each was satisfied on its own
while the other was broken.

**Looking at it, twice (D56/D57, again).** The first capture of the screen was three
diamonds floating in an empty window with one card-sized button holding three words
of text — every test green, the encounter counts perfect, and it read as a broken
screen. Two things were wrong and neither is visible in a diff: only *lit* rooms were
drawn, so there was no ground for them to be cut out of, and the move buttons reused
`reward_card_size()`. The floor now draws the rock plate as well, the tiles are
116×58 rather than 96×48, and the buttons are a row of short labels.
`tests/test_layout.gd` reads the tile size and the grid size **together** and fails if
they stop fitting the window, because this floor is the one board in the game with no
scrolling to fall back on and a drawn Control cannot report being crushed.

**Where it is plugged in.** The Warrens (difficulty 2, open on a fresh save, five
combats and no elite — "nothing here fights alone, and the tunnels double back").
The three opening dungeons now teach three different models instead of two:
Crypt/graph, Ossuary/deck, Warrens/floor.

**Measured** (`tools/sim_balance.gd`, the Warrens against the two dungeons on either
side of it):

| profile | Crypt (d1, graph) | Ossuary (d2, deck) | Warrens (d2, **iso**) |
|---|---|---|---|
| Starter, 60 HP | 98% | 74% | **88%** |
| Early, 70 HP | 100% | — | **97%** |
| Mid, 90 HP | — | — | **100%** |
| Status build, 90 HP | — | — | **99%** |

with 5.2-5.4 fights per run, which is what the mix asks for. The completion rates
move a point or two between runs; the shape is what matters — the floor sits where a
difficulty-2 dungeon should, between the Crypt and the Ossuary, and it is not the
dodge-priced outlier the deck model is.

**A drift the new model exposed in the simulator.** The walker paid an option's
`hp_cost` only when `select()` resolved nothing, because until now the only priced
option in the game was the deck's dodge and a dodge resolves nothing by definition.
A step taken after the torch is out costs HP *and* hands back the encounter in the
room it led to, so the sim was measuring walking in the dark as free. Every priced
option is now paid for, and the avoid metrics key on `action == "avoid"` rather than
on "has a price", so a step across explored ground is no longer counted as a dodged
fight.

**Deliberately not done.** No tileset, no wall art, no character sprite, no
animation, no multiple floors per dungeon, no line of sight past the adjoining rooms,
and the dark costs a flat price per step. This is a concept test; art and depth are
only worth spending once the feel is judged.

### D75 — A tuning pass, now that the instrument reads true

D72 corrected four ways the simulator modelled a weaker player than the game gives
you. Every constant tuned against the old readout was therefore set against wrong
numbers, so this is the pass that re-tunes them. Three defects, three targeted
levers, and one lever tried and rejected.

**1. A difficulty rating that did not mean anything.** The Abyssal Stair (d7) was
harder than the Maw (d8) for every deck measured — 20% against 52% for a thorns
build, 29% against 41% for a late one. Its shape was 3 combats + 2 elites where the
Maw runs 2 + 2, and an elite is heavier than a combat, so the *shape* was outweighing
a whole point of depth. The Stair drops to one elite. This is the D13 trap again
(roster and now shape swamping the difficulty number) and it is why
`tests/test_traversal.gd` bounds the mix.

**2. Matched decks were pinned at the ceiling.** `ratio_ceiling(d)` was
`1.4 + 0.73 x (d - 1)`, which puts d5 at 4.32 — below the 4.43 a relic-carrying
mid-game deck reaches. A deck at or above the ceiling faces enemies that have
stopped scaling, so the dungeon can never answer it however well it is played. At
0.90 per depth the ceilings become d3 3.20, d5 5.00, d8 7.70, and the mid-game
dungeons can scale to the decks that actually visit them. d1 is untouched at 1.4 —
outgrowing the Crypt is the point of the ratchet (D36).

**3. Relics were under-priced.** Three decks at the Sunken Vault, and the one with
relics beat both stronger-looking decks: ratio 4.43 cleared 99% while 4.09 cleared
79% and 3.82 cleared 73%. A deck that outperforms its ratio is D28's signal, and
`RELIC_POWER_PER_RATIO` (flat relic power per point of ratio) was the knob: 70 → 50,
so a relic contributes 40% more ratio and enemies scale to it. Relic-free profiles
are unmoved, which is exactly what a targeted fix should look like.

**Tried and rejected: `DMG_POWER_K`.** Raising it from 0.15 is the obvious lever for
"fully-scaled dungeons are too soft", and it is global, so it cannot tighten the
loose cells without crushing the tight ones. Measured at 0.25 it took the AoE build
at the Drowned Market from 51% to 11% and a late deck at the Maw from 41% to 19%,
while the cell it was aimed at (a relic deck at the Vault) only fell from 99% to
76%. At 0.20 the same shape, half the size. Reverted to 0.15 — D45 already recorded
that this constant is a knife edge, and the honest fix for a specific over-performer
is to price that thing, not to raise the tide.

The simulator also gained `--trials=N`, because a tuning pass needs many runs of the
report and one at full precision, not fifteen at full precision.

**Measured after the change.** The figures below are the 400-trial confirmation run
that D76 made affordable; every cell landed within 8 points of the 120-trial numbers
this pass was actually tuned against, so the tuning holds at full precision.

| deck | | |
|---|---|---|
| Starter, 0 clears | Crypt 98% | Ossuary 80% |
| Early, 1 clear | Crypt 100% | **Foundry 62%** |
| Mid Lv15, 3 clears | Foundry 98% | Ember Road 100% |
| Status Lv15 | Foundry 82% | Ember Road 71% |
| Barricade Lv15 | Foundry 44% | Sunken Vault 62% |
| Poison Lv15 | Fungal Deep 70% | Rot Gardens 63% |
| AoE Lv15 | Rot Gardens 68% | Drowned Market 34% |
| Thorns Lv15 | Abyssal Stair 33% | The Maw 54% |
| Relic build, 4 relics | Foundry 100% | **Sunken Vault 92%** |
| Late Lv40, 6 relics | Abyssal Stair 36% | The Maw 31% |
| Endgame Lv100, 7 relics | Abyssal Stair 73% | The Maw 68% |

The opening stays easy, which is what a player reported and what D71 established the
tool had been lying about. The Foundry is still the one early wall. The deep end
spans 27-70% by how well equipped you are, and the Stair no longer beats the Maw.

**A confirmation run at the full 400 trials was abandoned after 32 minutes.** The
simulator has become much slower — growing decks mean more cards to shuffle and draw
each fight, and higher ceilings mean longer fights — so the numbers above carry the
uncertainty of 120 trials, and the tool needs profiling before the next pass. That
is a real cost of D71's fidelity, and it is worth stating rather than hiding: a
measurement nobody can afford to run is one that stops being run.

### D76 — The simulator was spending its life in ResourceLoader

D75 had to be tuned at 120 trials per cell because the full 400-trial report had
stopped finishing: it ran for 32 minutes and was abandoned. A measurement nobody can
afford to run is one that stops being run, so this is the pass that made it
affordable — profiled, not guessed, and the first guess was wrong.

**What it actually cost, measured per operation:**

| | cost |
|---|---|
| an entire simulated fight | 0.35 ms |
| ...of which combat setup | 0.13 ms |
| **one reward roll** | **3.52 ms** |

A reward roll cost **ten times an entire fight**. Splitting it showed two separate
culprits, not one:

* `Balance.card_pool_for()` — **1.04 ms per call**, because it calls
  `Balance.dungeon()` and `zone_of()`, and *every one of those accessors did a
  `load()` on every call*. Six resource lookups to answer a question about static
  content.
* loading the 19 cards in the pool to weight them — **2.58 ms**, at 0.136 ms per
  `load()`.

`load()` returns the same cached instance for a path, so the cost was pure
ResourceLoader path resolution — tolerable once, ruinous in a loop. And the loop was
not only in the tool: the game's reward screen rebuilt the same pool and reloaded
the same nineteen cards on **every victory**.

**The fixes, in order of what they bought:**

1. `Balance._cached()` behind `dungeon()`, `zone()`, `build()`, `power()`, and new
   `card()`, `enemy()`, `event()` accessors, plus a memo on `card_pool_for()`.
   Semantically identical — `load()` already returned the shared instance — so this
   introduced no aliasing that was not already there. `card_pool_for` went
   **1.044 ms → 0.003 ms**.
2. The simulator builds its reward table (ids, weights, total) **once per dungeon**
   instead of per roll. Rewards fell from ~90% of a run's cost to 3%.
3. `CardData.power_value()` memoised per level. `power_ratio()` sums it over the
   whole deck at the start of every fight, which was 31% of combat setup — for a
   number that cannot change unless the card levels up. Setup: 0.13 → 0.10 ms.
4. `Balance.enemy()` replacing a per-fight archetype `load()`: setup 0.10 →
   0.03 ms, and fight_setup across a whole report fell 6.5 s → 2.0 s.
5. The per-fight diagnostic columns run a **third** of the run trials. The report
   says itself that they are full-HP indicators rather than the metric that decides
   anything, and at parity they cost as much as the run simulation beside them.

**The tool now profiles itself.** Guessing was wrong twice — the content-accessor
cache won 350x on one call but only 3x overall, which meant the model of where the
time went was off — so every phase is timed and printed at the end of a report:

    === where the time went ===
       fight_play          19.6 s   67%
       avoid_calibration    6.7 s   23%
       fight_setup          2.0 s    7%
       rewards              0.9 s    3%

Two thirds of it is now simulating combat, which is the work the tool exists to do.
It also gained `--trials=N`, so a tuning pass can iterate at low precision and
confirm once at full.

**The full report went from 32 minutes (abandoned) to 64 seconds** — at least 30x —
which is what let D72's tuning be confirmed at 400 trials instead of left provisional
at 120. That confirmation immediately caught a stale number of its own:
`MAX_ACHIEVABLE_RATIO` still said 6.0 while a maxed loadout now measures 6.09, since
D72 repriced relics. A constant whose comment says "measured" has to be re-measured
when the thing it measures moves.

### D77 — The floor became a place: real ground, things walking it, and no torch

Play report on D74's isometric floor: *"I like it a lot, but there are no real empty
tiles, the monsters don't move, and I'd like to walk more and have bigger spaces."*
Plus a direct question about the torch — *"I am not that convinced by the idea"* —
which turned out to be the right instinct, for a reason worth writing down.

**What the torch actually was.** Three lines: `torch = rooms × 1.4` at generation,
`torch -= 1` per move, and once it hit zero every option carried `hp_cost = 2 +
depth-1`. What it never did was affect vision — sight was `_reveal_around`, the tile
you stand on plus its neighbours, and `seen` was sticky. **At torch zero the screen
looked identical.** So it was not light. It was a step allowance with an overdraft
fee, wearing light as a costume, and four things followed from that:

* The fiction and the feedback disagreed. A torch that burns out and changes nothing
  you can see teaches the player "I get fourteen free steps", not "I carry light".
* It was a tax, not a decision. Nothing to spend it on, no refill, no trade at the
  moment of choosing — one threshold, evaluated once, near the end of a floor.
* It was slack. Every room held something, so fourteen torch on a ten-room floor only
  bit after four wasted moves. Most floors never felt it.
* It scaled itself into irrelevance, and this is the one that mattered: `rooms × 1.4`
  means a **bigger** floor hands out proportionally **more** steps. The exact change
  this entry is about would have made the torch stop existing.

Worse than any of those: it charged the player for looking around, which is the one
thing this model exists to sell. The torch is deleted.

**What replaces it.** Greed is still priced, but on exposure rather than on walking.
The floor is now mostly open ground (`ISO_TILES_PER_ENCOUNTER = 3.0`, so ~30 walkable
tiles for a nine-encounter budget against the old ten), and part of the combat budget
is not in a room at all — it is **wanderers**, taking a step every time you take one,
pathing toward you inside `ISO_WANDER_SENSE = 5` and drifting outside it. Exploring
costs turns, and turns are what the floor charges for.

Wanderers come **out** of the combat budget and are never added to it, or a difficulty
rating would stop meaning one thing (D14). Measured over 30 runs of all 12 dungeons:
ISO averages **9.2 encounters against a budget of 9.2**, level with GRAPH (9.2), DECK
(9.2) and DICE (9.2).

**Three geometry decisions, each of which was wrong the first way round.**

* **Encounters are placed by farthest-point spreading**, not by shuffling a subset.
  A random subset of a 30-tile floor clumps, and a clump is the *old* dense floor with
  rock around it — three encounters in adjoining tiles read as one room with three
  doors, and the new open ground ends up in one corner nobody visits. The test now
  asserts the property directly: **no two pieces of content adjoin.**
* **The floor is sized against the whole budget, counted before any of it is lifted
  off the ground to walk.** Sizing it on what was left afterwards had it exactly
  backwards — more wanderers gave a *smaller* floor (24 tiles against 27), when a
  wanderer is the thing that most needs room to roam and to be evaded in.
* **The camera is not clamped to the plate.** Clamping is right for a board you can
  see all of and wrong here, for a reason the first capture showed plainly: a diamond
  plate's bounding box has four empty corners, so clamping near an edge shoved the
  player token to one side of the window with dead space opposite it. Centring always
  means the floor scrolls under a token that stays put.

**The D74 deadlock, twice more, wearing new hats.** D74 recorded a pacing deadlock
that only fired 3 runs in 360. Mobile content re-created it twice at the same rate:

* A wanderer counts as unfinished business, so `options()` refuses the stair while one
  lives — but `_dist_to_unresolved` did not know where wanderers *were*, so with
  nothing else left every option scored `away = -1`, the ordering fell back to cell
  index, and a greedy walker paced between two tiles for ever. **A thing that blocks
  the exit has to be findable.**
* Then: the player walks *onto* a wanderer, so `away == 0` — and the awake branch only
  closed distance when there was distance to close, so at zero the wanderer fell
  through to the drift branch and politely stepped aside. The walker chased it round
  the floor for ever, because the thing blocking the stair was the thing it could
  never catch. Contact has two halves and both must be checked; the zero case first.

Both failed 12 runs in 360 and both would have read as a hang in play and as nothing
at all in a diff.

**A drift in the simulator that only a big floor could expose.** With the floor
walking correctly, the Warrens still measured a flat **72% for every deck in the
report** — starter and fully-relic'd alike, every fight won, HP barely touched. That
shape is not difficulty, and it was not: `_choose_option` picked **randomly** among
the non-avoid options. That is right when the options are *encounters* — it stops the
driver quietly favouring whatever a model lists first — and wrong when they are merely
*directions*. On the old floor every room held something, so a random step still
stripped the floor; on 30 tiles of open ground it is a drunkard's walk, and a drunkard
does not reliably reach the far corner. A quarter of runs simply never found the
stair. The driver now picks randomly among options that **resolve** something and
falls back to the model's own first suggestion when none do. The other three models
only ever offer encounters, so nothing about their numbers moves.

This is the third time the tool has been caught modelling something other than the
game (D72's weaker player, D74's unpaid `hp_cost`), and the pattern is the same every
time: **a policy written for one model's option shape silently becomes a measurement
of that shape.**

**Deleting the torch cost real attrition, and the numbers said so.** With the driver
fixed, the Warrens completed **100% at every tier** — against 79% for the Ossuary,
which sits at the same difficulty. Wanderers had not replaced the torch at all,
because mechanically they were budget combats that walked: same count, same tier, same
fight. So being **caught** is now priced (`iso_ambush_cost`, `9 + 2×(depth-1)`), which
is the torch's HP cost levied on the opposite thing — the torch charged for walking,
which the model exists to sell; this charges for being caught, which is the part a
careful player can actually avoid. A first attempt at `4 + depth-1` moved 100% to 98%,
which is what a 5 HP chip is worth against fights this cheap.

| profile | Crypt (d1, graph) | Ossuary (d2, deck) | Warrens (d2, **iso**) |
|---|---|---|---|
| Starter, 60 HP | 98% | 80% | **80%** |
| Early, 70 HP | 100% | — | **99%** |
| Mid, 90 HP | — | — | **100%** |
| Status build, 90 HP | — | — | **98%** |
| Barricade, 90 HP | — | — | **94%** |

The two difficulty-2 dungeons now agree with each other (80% against 80%), and
completion **climbs with progression** instead of sitting flat — which is the shape
the pillar asks for and the thing the broken driver was hiding. As in D74 the rates
move a point or two between runs; the shape is what matters. A mid-game deck clearing
a difficulty-2 floor outright is not a miss — "you outgrow the Crypt" is the pillar,
and the Warrens is an opening dungeon.

**What "9.2 against 9.2" does and does not claim, because a spatial model can be
rushed.** The stair is ordered last but never *withheld* — walking onto it fights the
boss and ends the floor, whatever is left up there. That is the model's central
decision and not a leak, but it does mean the budget figure describes a player who
explores, not one who leaves early. Measured over 60 runs of all 12 dungeons, taking
the shortest route to the stair the instant its position is known: **12.0 steps, and
4.6 of 9.2 budgeted encounters fought — 50% of the dungeon skippable.** Three things
price that rather than forbidding it: half the floor is half the gold and cards, the
boss is met with a deck that never grew, and D-escrow means the run's takings are only
banked on a boss kill. What keeps the *measured* number honest is that the stair is
unmarked and sits at the furthest tile from the entrance, so the 12 steps have to be
spent discovering it — there is no beeline from turn one, and the greedy driver the
simulator uses never takes the early line at all (rank 2 sorts last). Worth writing
down because a future reader comparing 4.6 against the contract would otherwise read
it as a generation bug.

**Looking at it, twice, again (D56/D57/D74).** Every test green and the first capture
was one enormous black polygon filling the window with a few grey tiles adrift in it.
Painting every unknown cell was right on a 6×6 plate, where it read as the stone the
rooms were cut out of; on a 12×12 plate it is 130-odd black diamonds. Rock is now
drawn **only where it walls in ground you know about**, so the drawn shape hugs what
has been explored and grows as the floor is learned. Two further things the capture
showed that no assertion did:

* Four exits all labelled "Open ground" is a choice with no information in it. A tile
  now reads as its contents, or "Into the dark" (unseen), or "Open ground" (seen), or
  "Back the way you came" — which needed a `walked` array distinct from `seen`,
  because on a floor that is mostly open ground "have I been here?" is the question
  the player is actually asking, and when every tile held an encounter its contents
  answered it.
* The floor is drawn in two greys for the same reason, so your own route back is
  visible on it. The drawing *is* the map in a model about coverage.

`tools/screenshots.gd` now captures this screen **twice** — at the entrance and a
third of the way through a floor — because the opening state of a discovery model is
the least informative picture of it there is, and it was the state that made the rock
look broken.

**The layout constraint moved rather than disappearing.** The floor used to be the one
board with no scrolling, so `ISO_GRID` and the tile size were only safe *together* —
and at 6×6 on 116×58 tiles the plate already drew 406px into 460px of room, meaning
**7×7 would not have fitted.** The floor could not grow at all. `test_layout.gd` now
checks that `VIEW_W`/`VIEW_H` fit the window *and* that the plate is **bigger** than
the view, so nobody shrinks the grid back to where the camera is dead code and the
floor has stopped being somewhere you discover.

**Deliberately not done.** No tileset, no wall art, no character or monster sprites,
no multiple floors per dungeon, no line of sight past the sight radius, and no
distinct wanderer archetypes — a wanderer is a combat from the dungeon's roster. The
better version of the ambush is "the wanderer takes the first turn of combat" rather
than a flat HP chip: it would scale with depth and deck for free instead of through a
tuned constant, but it needs `CombatEngine` to support losing the initiative and the
simulator to model it, so it is left as the obvious next step. This is still a concept
test; art and depth are worth spending once the feel is judged.

### D78 — The floor got its art, and most of the work was not drawing

D77 left the isometric floor deliberately unpainted — drawn diamonds and the flat
encounter glyphs the other traversal views use — on the grounds that art is worth
spending once the feel is judged. The feel was judged, and four downloaded asset packs
turned up: seamless ground materials, isometric props, 13 monsters with a facing pair
each, and a set of flaming swords.

**What the packs actually were, which is not what they looked like.** Two findings
changed the whole approach and neither is visible from a file listing:

* **The "tiles" are not isometric tiles.** `Free_pixel_tiles_pack` is twelve seamless
  1024² *top-down* materials — cobblestone, cracked earth, grass, sand. There is no
  diamond in the pack. So the projection is the renderer's job:
  `draw_colored_polygon` takes UVs, and mapping a diamond's four corners to the four
  corners of the unit square **is** an isometric view of a square tile. It is exact
  rather than approximate, because a diamond is a parallelogram and affine UV
  interpolation across the two triangles has no seam.
* **Every sprite is a small figure parked in the bottom of a big empty canvas.**
  `boss_0_S` is 256×512 with its art inside (12,332)-(223,505). Drawn untrimmed and
  centred on a tile, a monster comes out a third of the size it should be, floating
  well above the floor. `tools/install_iso_art.gd` trims each source to its alpha
  bounding box, and that pays for itself twice: **the trim makes the anchor free.**
  Bottom-centre of a trimmed sprite is where its feet are, so nothing needs a
  per-file offset table.

**A diagnostic that reported the opposite of the truth.** The first contact sheet of
the monster pack came back as a grid of white boxes, which reads as "this art has no
alpha and is unusable". It has perfect alpha. `Image.blit_rect` **copies** RGBA, so
every transparent pixel punched a hole straight through the backing colour, and the
viewer drew those holes white. `blend_rect` is the call. Worth recording because the
failure inverted the finding: the tool said "no alpha" about art that was entirely
alpha, and the next step from believing it would have been colour-keying sprites that
needed nothing done to them.

**Three things the render showed that no assertion could (D56/D57/D74/D77, again).**

* **Rock has to have height.** A wall drawn as a dark flat diamond reads as *darker
  ground* once the floor is textured — the first pass looked like a stain, not a room.
  Rock is now a block: the top face lifted by `WALL_LIFT`, plus the two faces that
  point at the camera, each on its own tint because a single flat value made a run of
  blocks read as one shapeless mass. That one change is the difference between a grid
  of tiles and a dungeon with corridors in it.
* **Ground and standing art need separate passes.** Drawing each tile with its own
  contents let the next row's floor slice the legs off whatever stood behind it. Flat
  ground first (it cannot occlude anything), then everything with height, back to
  front among itself — walls and sprites *together*, since a wall in front of a
  monster does have to hide its legs.
* **Correct depth ordering made the game unplayable.** With walls occluding properly,
  a block standing in the row between the camera and the player hid the player behind
  it. Realistic, and useless. The player is now drawn last, over everything,
  deliberately breaking the depth order the pass above is careful to maintain: knowing
  where you are outranks being correctly occluded by a wall you are standing behind.

**A rig for looking at art, because a normal capture cannot prove it is wired.** The
fog hides most of the floor by design, the greedy walk used for the explored capture
*clears* whatever it finds, and any role whose file failed to install silently falls
back to a flat glyph. So "I did not see a market stall" had three innocent
explanations and one real one, and the first painted capture showed no sprites at all
purely because the walker had already cleared everything within sight.
`tools/IsoArtCheck.tscn` forces one of every role plus all four wanderer designs onto
one lit floor at the real tile size, so scale, footing and facing are judged in a
single look.

**What each thing is now, and why that mapping and not another.** The roles are wired
by meaning rather than by source filename — which is not optional here, because two of
the four packs differ **only by capitalisation** (`free_pack` props, `Free_pack`
monsters) and both name their contents `table_N`/`boss_N`. `table_0` tells you nothing
about whether it is a market stall or a hearth.

| encounter | art | why |
|---|---|---|
| combat | grey armoured brute | stands where it is put; a sentinel |
| elite | gold armoured brute | same silhouette, heavier read |
| stair / boss | robed reaper on a flame base | the only figure in the packs that looks like a destination |
| shop | isometric market stall | it is literally a stall of wares |
| rest | roofed hearth with a lit fire | fire reads as rest without a label |
| event | apothecary counter with lanterns and jars | something happened here |
| treasure | flaming sword planted in the floor | a vertical landmark, visible past a wall |
| wanderer | four spider designs, two facings each | **the things that hunt you are not the things that stand guard** |

That last row is the one that is design rather than decoration. Wanderers are spiders
and stationary combats are armoured brutes, so the floor tells you which of the two
kinds of danger you are looking at before you read anything — and four designs mean
three wanderers on one floor do not read as one monster cloned.

**Deliberately not done.** No player sprite: these packs are monsters, furniture and
swords, with no hero in them, so the player is still a drawn marker. No animation, no
wall variety (one material, three face tints), no per-dungeon materials even though
the pack ships grass, sand and cracked earth — the Warrens is the only iso dungeon, and
twelve floors' worth of terrain palettes is a decision to make when there is a second
one. No lighting beyond the three fog tints.

**Licence status is unresolved, and it is recorded rather than assumed.** All four packs
arrived as bare directories of PNGs with no licence file, no readme and no attribution
text — `find` over them turns up nothing but images. Names and shape match the free
tiers of shops like CraftPix and itch.io, whose licences commonly permit *use in a
game* while forbidding *redistribution of the art*, and committing these files is
redistribution. `assets/art/iso/README.md` carries the per-file provenance table and
the flag. Two things make that recoverable rather than a trap: the installer is the
version-controlled artefact, so the whole directory regenerates from a source folder
with one command; and every role is looked up through `ResourceLoader.exists` with a
glyph fallback, so a checkout with `assets/art/iso/` emptied still plays.

### D79 — The floor became a building: rooms, floors, sealed vaults, and a pacing ceiling

Play report on the D77/D78 floor: *"30 tiles doesn't give me the feeling of exploring a
dungeon."* Correct, and the diagnosis was not tile count. Three numbers said what was
actually wrong:

* **21 of the 30 tiles held literally nothing** — not a prop, not a coin, not a hint.
  Exploring them could not be rewarding because there was nothing there to find. Open
  ground had been added so travel would *exist*; travel without discovery is walking.
* **There was no architecture.** One organic blob grown from the middle of the plate, so
  every tile was the same width. Nothing was a *place*, so nothing was a landmark.
* **There was one floor.** The stair "down" led to the boss and out. A crawl that never
  descends is not crawling.

Adding thirty more tiles to that gives a longer walk through the same featureless blob,
which is why the fix is architecture, depth and something to find — not size.

**The arithmetic came first, and it changed the design twice before anything was built.**
A card battler's loop is short decision → fight → reward, so the number that governs a
spatial model is **moves per encounter** (~5 on the old floor). Two candidate designs
died on paper:

* Splitting one dungeon's budget across three 30-tile floors gives **~15 moves per
  encounter** — the card game buried. So: more floors, each *smaller*.
* Making every floor a round trip (crawl in, crawl back out) costs ~8 on its own. So:
  floors are **one-way descents**, and walking back out is reserved as the price of
  retreat rather than the normal case.

`Balance.ISO_MOVES_PER_ENCOUNTER_MAX` is that budget written down at 7.5, and
`tests/test_traversal.gd` now walks every dungeon and **fails if the measured average
exceeds it**. It is the replacement for eyeballing floor sizes, and it earned its keep
immediately (below).

**Total tiles per dungeon is the budget, not tiles per floor.** The first build fixed the
room COUNT per style and produced 53-tile floors holding three encounters each: every
structural invariant passed and it measured **8.6 moves per encounter**. A floor can be
beautifully built and still be too big for the game it is in. Rooms are now placed until
they cover a share of `ISO_TILES_PER_DUNGEON / floors`, so **floor size falls as floor
count rises** — a four-floor dungeon is four small floors — which is the only reason the
pacing survives being deeper. Measured after: **6.9 moves per encounter**, and the
encounter budget itself untouched at 9.2 against 9.2.

**Multiple floors needed nothing outside the traversal.** Descending regenerates the
floor *in place* inside the same `TraversalIso`, and `is_complete()` stays false until
the last floor's boss dies — so `RunFlow`, the save format, combat and the other three
models learned nothing. The same trick covers the three new tile types: a stair, a key
and a vault all resolve *inside* `select()` and hand back `{}`, which is what keeps them
invisible to a caller that only knows about encounters.

**Architecture, and why it is per dungeon.** Rectangular chambers with at least a tile of
rock between them, joined by L-shaped corridors — a spanning path first so the floor is
certainly connected, then `loops` extra links. That loop count is what makes a style feel
different to walk: zero is a tree where every dead end costs a double walk, three is
somewhere you can come round behind a thing that is chasing you. Four styles
(`cells` / `galleries` / `warren` / `halls`) are mapped to the twelve dungeons, and this
is what replaces "the traversal model differs" as the reason two dungeons do not feel
alike. Room *bounds* are per style; the *count* is whatever fills the tile budget, so a
style of small cells naturally needs more of them than a style of big halls.

**A room is revealed whole the moment you enter it**, while a corridor gives you two
steps and no more. This is the cheapest big win in the whole entry: a uniform sight
radius everywhere is precisely what made a dungeon feel like a field, and the contrast
between a blind passage and a hall opening up is the sensation the model exists for.

**Sealed vaults, and the one invariant they rest on.** Treasure — the only purely
rewarding encounter, and so the right thing to gate — is moved into a **dead-end tile**
and sealed, with its key placed as far away on the same floor as the geometry allows. The
dead end is not decoration: **a tile with one way in can never be the only route to
anywhere**, so a sealed vault can never cut a floor in two or fence off the stairs,
wherever the generator puts it. The test asserts exactly that, plus that no vault exists
without a key. If a floor has no dead end free, the treasure simply stays unlocked — a
floor that cannot be finished is worse than a floor with one fewer puzzle.

A vault is also the first thing here that is **visible but not enterable**, which forced
sight and movement apart. Sharing one distance field made a sealed vault unreachable and
therefore *invisible* — the player was never shown the thing they needed a key for, which
turns a puzzle into an absence. `_dist_from` (walking, respects the seal) and
`_dist_open` (sight and sound, only rock stops it) are now separate, and the ordering
that steers a walker automatically stops routing through a vault it cannot open and
starts once it can.

**The battle system now reaches back into the space.** A resolved fight wakes every
wanderer within `ISO_NOISE`, so *where* you choose to fight matters and clearing a room
next to something asleep is no longer free. Lingering past `ISO_LINGER` steps on one
floor wakes all of it. Both were chosen over spawning extra monsters, which would have
inflated the encounter budget — waking what is **already counted** is pressure that
cannot cheat.

**The D74 deadlock, for the third time, and its mirror.** Twice before, the lesson was
written down as *a thing that blocks the exit has to be findable*. This time the walker
paced between two tiles once a floor was stripped, because with no content and no
wanderers left, nothing seeded the goal field, every option scored `away = -1`, and the
ordering fell back to cell index. The rewrite had dropped the case where **the exit
itself is the objective**. So the mirror of the old lesson, now also written down: *the
exit has to be findable too.* Keys are seeded for the same reason — a vault you cannot
approach is unfinished business whose real destination is its key.

**Looking at it, twice more (D56/D57/D74/D77/D78).** Every test green, and:

* **The hero was standing on the walls.** With walls now everywhere, "draw the player
  last, over everything" (D78's fix for being hidden) made her look like she was
  balanced on top of the rock in front of her — and on a floor of one-tile corridors the
  tile in front of you is usually rock. Blocks between the camera and the player are now
  held back and drawn **translucent over her** at a third strength, so the wall is still
  there and she is legibly behind it.
* **The stairs were nearly invisible** — a dark hole on dark stone. Wrong for the single
  tile the whole floor is a search for: everything else can be missed and found later.
  They are now nested diamonds stepping down into black with a lit gold lip, and are
  deliberately the loudest thing the floor draws.

`tools/IsoArtCheck.tscn` was extended to stage a stair, a vault and a key alongside the
sprites, because all three are *drawn* rather than sprited — there is no stair, vault or
key art in any pack — and drawn features are exactly the ones with nothing to fall back
on if they read badly.

**Balance held without retuning.** The Warrens measures 80% at a starter deck against the
Ossuary's 74% at the same difficulty, climbing with progression, which is where D77 left
it.

**Deliberately not done, and all of it deliberate rather than forgotten.** The other three
traversal models are untouched and still shipping — nothing has been deleted, and this
was built as a rebuild of `TraversalIso` in place so the comparison is a
`traversal = N` change in one `.tres`. No overworld, no expedition framing, no banking
loot by carrying it home, no spending cards on the world, no monster behaviour variety
(patrollers, sleepers), no doors to shut behind you, and no per-dungeon floor materials
even though the pack ships grass, sand and cracked earth. Retreat-by-walking-out is
designed but unbuilt: it needs the run flow, which this pass deliberately did not touch.

### D80 — Sealed packs: a reward that has to survive the walk home

Every card the player earned arrived the same way: a fight ended, three faces
appeared, one was clicked, and it was in the deck. That is D1's reward loop and it
works, but it was the *only* channel, and being the only one had two costs.

The first is that the overworld is a menu. Everything waiting there has already
resolved — gold is a number that went up, a relic is a line in a list. Nothing is
*pending* when the player gets home, so coming home is administration.

The second was measured before anything was built. The simulator was run with deck
growth disabled to price what a mid-run card is actually worth: in the opening,
nothing at all. At depth, 10–25 points of clear rate (the Maw with a maxed deck fell
68% → 43%). And in two cells a *fixed* deck did better — Fungal Deep 70% → 78%,
Drowned Market 34% → 46% — because a card added mid-run is a card that dilutes the
draw it was meant to improve. That is D46's thinning trade-off seen from the other
side, and it is why this is a second channel and not a replacement: **the reward
after a fight still joins the run deck, because that decision is a real one.**

A sealed pack is the other channel. It is found in a treasure and left behind by a
boss, it does not open in the dungeon, and it goes into escrow with everything else
(D20) — so it can be lost, and the Escape Rope is what carries it out. It opens on
the overworld, which is the one screen in the game that needed something unresolved
to happen in it.

**Why it can be handed out freely.** A pack cannot change the run it was found in —
that is what sealed means. So the coin flip that used to decide whether a treasure
also held a card is gone: `TREASURE_CARD_CHANCE` is retired and every treasure
yields a pack. Rationing existed to protect the run deck from dilution, and a reward
that never touches the run deck does not need rationing. The same reasoning is why
the simulator does not model packs at all, and says so at the line where it would
have.

**What is inside is stated before it is opened**, because a pack that hides its
contents is a slot machine and this game does not have those: a treasure pack is 2
cards, a boss pack is 3, plus gold that scales with the depth it was found at. The
cards roll from the pool of the dungeon the pack came from — a pack remembers where
it was found — so one from the Maw cannot pay out Crypt commons, and a boss pack
rolls on the boss reward weights.

**What it cost in run difficulty, measured as an A/B.** Comparing against D75's
table would have been dishonest — the isometric work (D77–D79) landed in between and
moves the same cells. So both arms were run on the *same* tree, 400 trials, one
variable: treasure grants a card 55% of the time, against treasure grants a sealed
pack.

| | card in the deck | sealed pack | |
|---|---|---|---|
| Starter @ Crypt / Ossuary / Warrens | 99 / 78 / 83% | 98 / 76 / 81% | −1 / −2 / −2 |
| Early @ Foundry | 60% | 55% | −5 |
| Status @ Ember Road | 67% | 65% | −2 |
| Barricade @ Foundry | 48% | 42% | −6 |
| Poison @ Fungal Deep | 66% | 68% | +2 |
| AoE @ Drowned Market | 52% | 46% | −6 |
| Thorns @ Abyssal Stair / Maw | 28 / 55% | 35 / 47% | +7 / −8 |
| Relic build @ Sunken Vault | 93% | 94% | +1 |
| Late @ Abyssal Stair / Maw | 40 / 36% | 34 / 30% | −6 / −6 |
| Endgame @ Abyssal Stair / Maw | 70 / 70% | 76 / 57% | +6 / −13 |

**Mean −1.1 points across all 34 cells.** The opening moves by a point or two, which
is the earlier finding restated: a card is worth nothing there. The deep cells swing
±13 in both directions, which is larger than the effect being measured — at 400
trials those cells are noisy, and reading −13 at the Maw as a real regression while
ignoring +7 at the Stair in the same run would be picking the number that tells a
story. No cell left its band, so nothing was re-tuned. The sim also does not count
what a pack *pays* — meta cards and gold that make the next run stronger — so the
true cost to the player is smaller than −1.1 and is paid in a different currency
than it is refunded.

**One thing this exposed.** The four traversal screens each carried their own copy of
the at-risk format string, and packs had to appear in all four. They now call
`GameState.risk_line()`, which also names relics — those have been in escrow since
D68 and were displayed nowhere while at risk. Something that can be forfeited and is
never shown is not in escrow; it is a surprise on the Defeat screen. The rope
confirmation names them too, since the rope is what saves them.

**Not built.** Packs do not stack, have no rarities, and none of them holds a relic.
Opening one is a reveal, not a choice — a pack that made you pick one of its cards
would be a second reward screen, and the fight already has that screen.

### D81 — Packs got a type and a tier, and the fusion curve did not move

From play: packs should be scattered more widely, should have a *type* (only certain
cards inside), and a *rarity* (a common pack cannot hold a legendary) — and since
the player would then end up with many more cards, levelling should cost more
copies. Three of those were built. The fourth was measured and dropped, and the
measurement is the interesting part.

**Type.** A pack is typed by **build**, using the seven archetypes `Balance.BUILDS`
already defines — each `BuildData` names its own ~10 cards, so the taxonomy the
builds screen teaches is the taxonomy packs use. A pack found in the Fungal Deep is
usually "The Long Death", and it contains poison cards.

The pool is the *build's* list, not the dungeon's, and that was decided by
measurement rather than taste: the overlap between any build and any dungeon pool is
**1–3 cards**. Intersecting them would not have produced a pack, it would have
produced a guarantee. So the two reward channels split cleanly, and each now means
one thing: **a fight reward is the dungeon's cards; a pack is the archetype's.**

**Tier.** Three — worn, sealed, gilded — and a tier is a *cap*: `PACK_TIER_CAP`
filters the pool by rarity before anything is rolled. A weight of zero would only
have made a legendary unlikely, and "cannot" was the requirement, so the cap filters
rather than de-weights. `tests/test_meta.gd` opens 200 worn packs at the deepest
dungeon and asserts none of them ever produces one. Tier odds move with depth: a
chest is usually worn, a boss is never worn, and an elite sits between them — which
makes taking the harder fight the thing that buys the better tier.

**Scattered wider.** Elites now drop a pack alongside their relic, so the three
sources are treasure, elite and boss — about three packs a run. Several packs made
one Open button per pack a chore, so the screen grew an Open-all with a single
combined reveal.

**And then the part that was dropped.** `tools/pack_income.gd` was written to
measure the currency fusion actually spends. Total cards is the *wrong* number:
levelling needs copies of the **same** card, and across a 20-card pool volume barely
moves any single one. The right number is expected copies per run of the card you
are actually levelling.

| | cards per run | copies of the best single card |
|---|---|---|
| before packs were typed | ~10 | ~0.89 |
| typed, affinity 3× (33% of packs) | 14.4 | Crypt 0.81 · Fungal 0.57 · Maw 0.96 |
| typed, affinity 8× (57%) | 14.4 | Crypt 1.04 · Fungal 0.75 · Maw 1.44 |
| typed, affinity 15× (71%) | 14.4 | Crypt 1.16 · Fungal 0.85 · Maw 1.73 |

**At the first weight tried, typed packs made levelling *slower*.** Card volume rose
44%, and copies of any one card went *down* — spread across seven builds, typed
packs broadened the collection instead of deepening it, which is the exact opposite
of the aiming they exist to provide. The premise behind "so require more copies" was
half right: many more cards, and none of them the ones you needed.

`PACK_AFFINITY_WEIGHT` is the knob that turns volume into concentration, and it was
set to 8 (about 57% of a dungeon's packs are its own build) — enough that farming the
Fungal Deep for poison *works*, not so much that the drop is a foregone conclusion.
That lands targeted income 15–60% above where it was, against 44% more total cards.

**So the fusion curve was not touched.** A 15–60% faster climb does not justify
repricing a curve that already asks 49 copies for level 15, 194 for level 40 and 862
for level 100 — at roughly one targeted copy per run, level 40 is two hundred runs
and level 100 is decorative. Raising the copy cost on top of that would have bought
the player more clicking for the same progression. If it ever does need repricing,
the lever is `FUSE_COPIES_STEP` (the curve's steepness), not `FUSE_BASE_COPIES`,
which would tax the fresh save that cannot afford to fuse at all.

**One thing derived rather than authored.** A dungeon's build affinity is computed
from how many of that build's cards sit in its own pool, not stored on the dungeon
resource. A `pack_build` field on twelve `.tres` files would be the D34 duplication
trap again — it would silently stop matching the pool the first time a card list
changed. Adding a poison card to the Rot Gardens now makes the Rot Gardens more of a
poison dungeon without anyone remembering to say so.

**Not built.** Packs still do not stack, none holds a relic, and you cannot buy one.
The tier a pack rolls is not influenced by anything the player does inside the run
except choosing to fight the elite.

### D82 — Terrain as a second axis, and the samey test that made the styles earn their keep

D79 gave the iso dungeon architecture but left the variety claim untested. This is Gate 2
from the validation plan, and it is the cheapest test of the hardest question about
dropping the other three traversal models: **if two dungeons walked on the same model are
indistinguishable, the model differing was carrying variety that nothing has replaced.**
No encounter count and no assertion can answer that. Six floors rendered side by side can.

**Terrain is a separate axis from architecture, deliberately.** Style says what shape the
place is; terrain says what it is made of. Four styles against four terrains is sixteen
readings out of eight constants, where folding surface into style would have given four.
The materials were already sitting unused in the tile pack — `stone`, `earth`, `moss`
(an overgrown floor between **stone** walls, because grass climbing a wall face reads as a
hillside rather than a ruin) and `sand`. The dungeon's pair overwrites the generic
`floor`/`rock` roles at load, so the drawing code never learns terrain exists and a
terrain with no art installed silently keeps the default.

**The test found that half the styles did not work.** `tools/IsoStyles.tscn` forces
`TraversalIso` onto any dungeon regardless of its own `traversal` field — so the
comparison needs no `.tres` edits — walks each one, captures, and `contact_sheet.gd`
(now with `--cell`/`--cols`) puts them in a grid. First result:

* `halls` and `galleries` read immediately — one big open room against long parallel bars.
* **`cells` and `warren` were indistinguishable.** They differed by one tile of room width
  and a loop count, which is nothing to the eye.

**The knob that fixed it was the one that was hardcoded.** Room-versus-corridor ratio was
a flat 0.75 for every style, and it is the thing the eye actually reads first. It is now
per style — `fill` 0.90 for a honeycomb of cells against 0.45 for tunnels with chambers
hung off them — plus `align`, which snaps chamber origins to a lattice so burial cells
come out cut in ranks. Regularity is a signature that no amount of size variation
provides. Measured after: `cells` averages 9.0 chambers a floor against `warren`'s 3.3,
and both same-terrain pairs are now tellable apart by eye (Crypt against Ossuary in stone;
the Maw against the Warrens in earth), which is the hard half of the test.

**The rig itself was wrong first, in a way that libelled the design.** A flat 22-step walk
caught the Maw five tiles into its *second* floor, which made a four-floor dungeon look as
though it had no architecture — when in fact the capture had simply arrived somewhere new
and dark. Every subject is now shown its first floor at ~65% mapped, stopping if it takes
the stairs. **A comparison harness that samples inconsistently produces a finding about
itself**, and this one would have been read as "deep dungeons have no shape".

Pacing held at 6.9 moves per encounter against the 7.5 ceiling, and the encounter budget
at 9.2 against 9.2. The Warrens measures 84% at a starter deck against the Ossuary's 78%.

Two tables are now asserted rather than trusted, because both are looked up **by dungeon
id with a silent default**: a typo gives that dungeon the fallback and the variety it was
supposed to have goes quietly missing. `tests/test_traversal.gd` checks every key is a
real dungeon, every value exists in the set it indexes, and that at least three of each
axis are actually in use across the twelve — because twelve dungeons all defaulting to the
same pair would satisfy every other assertion in the file.

**What Gate 2 answers, and what it does not.** It says the variety lost by dropping the
other three models *can* be rebuilt inside one model, and that it now has been for the
axes built so far. It does not say the game is better for it — that still needs Gate 4,
which is playing it.

---

### D83 — The buttons were a smear, and the reason was mechanical

The main menu drew five horizontal streaks with the text riding over the top border.
Not a taste problem: `ui_button.png` is 128x83 with a mottled, high-contrast middle,
and a nine-slice stretches that middle up to 14x across a 1240px button. Every
lengthwise variation becomes a smear, and the 19/21px texture margins do not fit
inside a 50px button, so the border squashes as well.

**A nine-slice has a rule, and the rule is checkable.** The top and bottom strips are
stretched horizontally, so every pixel in them must be identical along X. The left and
right strips are stretched vertically, so identical along Y. The middle is stretched
both ways, so it must be one flat colour. Satisfy those three and the frame is exact at
any size; break any one and it smears in that direction. An illustration tool cannot be
asked for this reliably, so the kit is **computed** — `tools/gen_ui_kit.gd` evaluates a
border profile as a function of depth from the nearest edge, per side, which meets the
rule by construction. Bevel included: a lit top and a shadowed bottom vary only along Y,
which is exactly what the top and bottom strips are allowed to do.

**The face changed from parchment to slate, so the ink had to stop being a constant.**
D48 measured the parchment at 0.86 luminance and hardcoded near-black text. The
generated kit is dark, in the violet the backdrops are lit in, so that constant would
have painted near-black on near-black. `UITheme.ink_for()` now *measures* the middle of
whatever frame is installed and returns near-black or warm off-white accordingly, and
`MenuArtTest` measures the same pair rather than the legacy file against the old
constant — the test would otherwise have gone on passing while the game was unreadable.
Measured after: 6.5:1.

**The bug that shipped for one screenshot.** The square icon frame was selected with
`b.text.length() <= 2`, and almost every call site in the game styles a button *before*
setting its text. So every button asked for the icon frame and its 6px padding, and
seven deck-builder buttons drew their text underneath their own border. It is a
parameter now. The general shape — deriving a style decision from state the caller has
not set yet — is worth remembering; it fails silently and only on some screens.

**Eight buttons were never styled at all.** `Start Dungeon`, `End Turn`, four
`Collection` headers and the starter-kit picks build a bare `Button` and rely on the
global Theme, which D48 already recorded as not resolving styleboxes. They were
invisible against the old smear and obvious next to a crisp frame. The card-shaped and
tile-shaped buttons (map nodes, reward cards) are deliberately left alone: they have
their own sizing language and a 12px carved frame is not it.

### D83b — Three scene backdrops, and a letterbox that was not there

`shop`, `rest` and `event` are installed from generated art, and Tier 5c is wired:
`PixelArt.scene_art()`, `UI.scene_backdrop()`, and calls from the shop, the encounter
screen and the rest overlay. Treasure falls back to the event shrine rather than to
black. The rest overlay's veil goes fully opaque when the art is present — it sits over
a live traversal view, and a translucent one leaves the floor grid showing through the
picture.

**The scrim had to be turned through ninety degrees.** The title screen's scrim is a
left-hand column because a menu is a column. These screens are not: their prose runs the
full width and stops halfway down. Reusing the column scrim blacked out the left two
thirds — which is where the merchant and the shrine are — and covered nothing that
needed covering. It is a top band now, plus a flat 0.25 dim for the lanterns and flames
that a gradient alone leaves at 1.1:1 against white.

**The letterbox detector was wrong twice before it was right.** `rest.jpg` came back with
a baked black frame; the obvious test is "dark rows at the edges". That cropped 73 rows
of painting off `event.jpg`, whose cavern ceiling measures 0.07 — the same as its top
rows. Darkness does not identify a bar in a set of night-time paintings. **Flatness
does**: a baked bar is a constant across its width and jpeg noise over real paint is not.
Rows with a luminance range under 0.008 find `rest`'s frame exactly and correctly leave
the other two uncropped. Aspect is fixed by cropping the long axis, not by resizing to
1280x720 — 1344x768 is 1.75 and the game is 1.78, and scaling straight across stretches
every face in the picture by 2%.

Three of six Tier 5c files exist; `treasure`, `victory` and `defeat` are still to draw,
as are all five Tier 5b zone backdrops.

### D83c — The generator signs its work, and finding the signature was the hard part

Twelve dungeon backdrops shipped with a four-point sparkle stamped into the
bottom-right corner, and it survived two milestones unnoticed: at 45px, in a corner
that combat dims to 0.55, it reads as a highlight. What made it visible was putting
the twelve corners in a grid — the same trick as D82's style comparison, and the
second time in this project that *a contact sheet found what no assertion could*.

**Brightness does not identify it.** A "bright blob in the corner" test finds a
brazier in nine of the twelve. The property that separates a stamp from a brazier is
not how bright it is but how *repeated* it is: the twelve share one 1280x720 frame,
so the intersection of "brighter than its own local background" across all twelve is
the stamp and nothing else. One room's fire is another room's plain wall.

Three things had to be added before that worked:

* **Exclude a margin.** The local mean is clipped within a radius of the window edge,
  so a light-to-dark boundary there shows a false excess in every image at once —
  which is precisely what the test looks for. It reported a pillar highlight running
  to the window edge as part of the mark.
* **Keep the largest blob only.** One stamp means one component; anything else that
  survives twelve images is a coincidence between two rooms.
* **Read the PNGs off disk, not through `ResourceLoader`.** The import cache handed
  back the pre-write file and made a successful strip look like a failed one.

**Removing it: the obviously-correct idea was the worse one.** The stamp is additive
light, so in principle it can be subtracted and the drawing underneath survives
intact — and the twelve images even supply the amount, being the least any of them is
lit above its own background. But that minimum is a *lower bound*: it is dragged down
by whichever room has dark linework under the stamp, so it under-subtracts everywhere
and leaves a crisp negative outline of the star. Measurably and visibly worse than a
harmonic (Laplace) fill, which is what ships. The fill's cost is that at 4x it reads
as a smudge where the ink lines were; at 1:1, dimmed, in the corner, it is not
findable. **Judge it at the size it is seen at.**

`tests/test_art.gd` re-derives the detection independently rather than calling the
tool, because a check that shares its subject's code cannot catch its subject being
wrong. It fails if more than 150 px of the corner are lit in every backdrop.

### D83d — Six more backdrops, and a filename that would have overwritten a fight

Tier 5c is complete (`treasure`, `victory`, `defeat` joined shop/rest/event) and
Tier 5b landed whole: five zone establishing shots behind the zone-select screen.

**`foundry.png` is a zone painting and `bg_foundry.png` is the Foundry's fight
arena.** The generator names files after what is in them, and the zone id is
`foundry_zone` while the dungeon id is `foundry`, so installing the establishing
shot under its own name would have replaced one dungeon's combat backdrop with a
landscape — with no error anywhere, because both names are valid. Zone art therefore
lives at `bg_zone_<id>.png` in its own namespace, the installer's table maps source
names to ids explicitly (the barrows arrived spelled `burrows`, which is the other
half of why the table exists), and `test_art.gd` asserts the two namespaces cannot
collide.

**The stamp is stripped BEFORE installing, not after.** The scene backdrops arrive as
2.33:1 panoramas and the 16:9 crop takes the corner with it — free. The zone shots do
not: one of the five is 1372x784 with no letterbox at all, and its crop keeps the
corner. Stripping in the source frame, before any geometry changes, is what lets all
five agree on where the stamp is. That works across mismatched sizes because the
detection window is anchored to the bottom-right *corner*, and the generator's inset
from that corner is fixed — a 1372x784 source lines up with a 1376x768 one inside the
window even though the images line up nowhere else.

**Three different scrims now, and the difference is layout, not taste.**

* Title screen: a left-hand COLUMN, because a menu is a column.
* Scene backdrops: a top BAND, because their prose is in the top half and everything
  below it is a button carrying its own opaque frame.
* Zone shots: a heavier flat DIM (0.60 against 0.25), because the zone screen is a
  scrolling list — dungeon names, boss warnings and card lines cross every part of
  the picture, so there is nowhere a band can help and only the dim reaches it all.

Victory needed a fourth thing: it is the one screen with prose *below* the fold, and
the one backdrop that is bright there. Its last line measured 1.3:1 over the doorway
light. A foot scrim, opt-in, takes it to 3.9:1.

### D84 — Chests, keys, vaults, and the generator that was inventing fights

From play: scatter far more packs, make walking worth doing, find keys, open locked
rooms, and put a reward behind something you have to crack. Built, with one part of
the request answered by measurement instead of by agreement, and one bug found that
had nothing to do with chests.

**A chest is not a treasure pile.** Every dungeon now holds four to six of them
(each dungeon's old count plus four, so relative character survives — but no dungeon
holds zero, because a dungeon paying nothing when chests are the meta channel would
collapse the overworld choice onto whichever dungeon pays). A chest has the same
three tiers a pack does, and the tier decides everything at once: how many packs are
inside, and what it wants first.

| tier | packs | wants |
|---|---|---|
| Worn | 1 | nothing, the lid lifts |
| Sealed | 2 | a key |
| Gilded | 3 | the run to prove something |

The packs inside inherit the chest's tier, or the word on the lid means nothing.

**Keys are found, never bought** — the Escape Rope rule (D21) for the same reason: a
purchasable key makes every locked chest a gold check, and a gold check is a delay
rather than a decision. They drop from open chests, from fights, and usually from
elites, so one chest tends to pay for the next and taking the hard fight is what
buys the better tier.

**Vaults ask, they do not riddle.** A written riddle is solved once and is a lever
ever after, and this game is replayed hundreds of times — so the "crack it" moment
is generated from run state instead: *above 70% health*, *carry 150 gold*, *a card
from The Long Death in your deck*, *a deck of 11 cards or fewer*, *three sealed
packs already carried*. Every one is knowable before the door and actionable at it,
which is what separates a puzzle from a coin toss, and none of them needs a writer.
The gilded coefficient was raised from 2 to 3 after measuring 0.6 vaults per run at
the deepest dungeon and none at all above depth 2 — too rare to be something a
player learns to play around.

**More walking, bought rather than granted.** D79 capped moves per encounter at 7.5
because a spatial model can bury the card game, and the iso floor was already
sitting at 7.1 — there was no room to simply make it bigger. But the ceiling is a
*ratio*, and chests are encounters: four more of them raise the denominator, so the
same ceiling permits a far longer walk. `ISO_TILES_PER_DUNGEON` went 78 → 130, and
the measured walk came out at **6.8 against the unchanged 7.5**. The dungeon is
two-thirds bigger and the card game is less buried than before, because every extra
step now has something at the end of it.

**The fusion curve moved this time, and the numbers say how far.** D81 measured
typed packs and declined to reprice. Chests are a different scale: targeted income
went from ~1.15 copies of the card you are levelling per run to **~2.17**.
`FUSE_COPIES_STEP` 8 → 4 — not 2, which would have cancelled the gain exactly and
handed the player ten pack openings to buy what three used to buy. At 4 the climb
genuinely shortens (level 15 in ~28 runs against 43, level 40 in ~133 against 169)
and still has a tail. The lever is the curve's *steepness* and never
`FUSE_BASE_COPIES`, which would tax the fresh save that cannot afford to fuse at
all.

**Chest gold, halved twice.** At the old 25-60 per chest, five chests would have
been a 5x gold inflation; the simulator buys healing at shops with that gold, so the
chests would have quietly made the game easier while looking like a card change.
10-25 still measured +2.3 points and pushed four deep cells above the 50-70% target
band. At 6-14 a run's chest gold lands near where one treasure used to leave it.

**And then the models came apart, which was not about gold at all.** Grouping the
remaining difference by traversal model:

| model | cells | mean change |
|---|---|---|
| dice | 12 | **+5.1** |
| deck | 4 | +1.8 |
| iso | 6 | +0.8 |
| graph | 12 | **−2.0** |

Halving the gold barely moved those numbers, so the cause was structural. Fights
actually met per run: graph **5.5 → 7.2**, against an encounter mix that asks for
four. The graph generator took its *size* from the mix and rolled its *contents*
from five fixed percentages with COMBAT as the fallback — two sources of truth for
one shape, the D34 trap again, and it survived only because every dungeon's mix sat
near 8. Adding four chests grew the map four rows and filled them with the fallback.
`NODE_CHANCE_*` is retired and `TraversalGraph._weigh()` derives the weights from
the mix, which is the single source the other three models were already using.

This is the pillar (D14) doing its job in the only way it could: the traversal test
asserts equal encounter *counts*, and all four models passed it at 13.2 the entire
time this was broken. The count was never the thing that differed.

**Where it landed, and the honest cost.** After the fix, fights actually met per run
against a mix that asks for four:

| model | fights/run before → after | difficulty |
|---|---|---|
| deck | 3.6 → 3.9 | +1.0 |
| dice | 4.6 → 4.1 | +5.1 |
| graph | 5.5 → **4.8** (was 7.2 before the fix) | +2.7 |
| iso | 6.0 → 6.0 | +1.8 |

**Overall +3.2 points easier than the pre-chest baseline**, and that is not the
chests — it is what the declared design has always been worth. The graph and the
dice models were both over-delivering fights relative to their own encounter mix,
and the run is easier now because two of them stopped. Re-tuning the difficulty
curve to hide that would be re-hiding it. The number to watch is the last row:
**the iso model still runs 6.0 fights against a mix asking for four**, which is the
same class of bug in the model this pass did not touch, and is why that model has
always measured harshest. It sets its own quota rather than dealing from the mix.

**Chests are their own screen.** From play again, and correct: chests and events
shared `Encounter.tscn` from when a chest was one line of text either way. Once a
chest had a tier, a lock, a key cost and a vault condition, one screen made two
different kinds of moment read as one — an event is a decision you owe an answer to,
a chest is a thing you found which opens or does not. `Chest.tscn` states the tier
as a coloured headline, the demand on its own line above the outcome, and the
contents as pack rows. Escape means Continue there, where the event screen
deliberately offers no way out. `tests/test_flow.gd` asserts the two routes stay
separate, since both scenes existing and compiling would not catch a merge.

**Still shared, and the one thing that gives it away:** `bg_treasure.png` has never
been drawn, so the chest screen falls back to the event backdrop. The two moments
still look alike until that plate exists — it is listed in ART_ASSETS.md and now
says why it matters.

**Not built.** Locked *rooms* are locked *chests*: the key is spent at the chest, not
at a door in the floor plan, so the iso model's geometry is untouched and the
mechanic works identically in all four models. A door you unlock and walk through
belongs to the iso work and its files. Keys do not stack into anything, cannot be
bought or sold, and there is no chest that takes two.

### D85 — The floor was lying about what you were walking towards

Asked whether monster behaviour types imply a bestiary. Checking turned up the defect
underneath the question, which is worth more than the answer: **the creature drawn on the
floor had nothing to do with the creature you fought.**

`CombatEngine._spawn_enemies` rolls the archetype at **fight time** from the dungeon's
roster. The thing walking toward you was given `design = (k + depth) % 4` at spawn — a
sprite index and nothing else. So you watched a red spider cross a hall and met an
armoured brute.

That is survivable while a wanderer is "a combat that moves". It stops being survivable the
moment behaviour types exist, because a patroller and a sleeper only mean something if the
thing patrolling *is* something. Otherwise a creature walks like a stalker and fights like
a swarm, decided by two unrelated dice.

**Fights are now cast when the floor is laid out.** `TraversalIso.enemy_of` maps a tile to
an archetype id, wanderers carry theirs on the monster record, and both ride out on
`pending["enemy"]`. Three things made this small:

* `CombatEngine.setup` has **always** had `forced_archetype` as its first optional
  parameter — the named-boss path uses the same idea. The run path was passing `""`. So
  honouring the traversal's choice is one argument at one call site, not a new mechanism.
* `Balance.roster_pool` is drawn from the exact pool combat would have rolled from, at the
  tile's own tier, bosses filtered out. **This moves *when* the choice happens, not *what*
  gets chosen**, so no distribution and no difficulty moves.
* The simulator honours it too. That is not optional: a sim that kept rolling its own
  enemy while the game used the traversal's would be measuring a different distribution —
  the D72/D74/D77 mistake for a fourth time, and the reason that lesson is now a pillar.

**Silhouettes are derived from what an enemy does, not from a table.** 35 archetypes
against 13 available designs means families rather than portraits — and family is *better*
information at a distance anyway, because what you want to know across a hall is the shape
of the fight, not its name. Three readings: `swarm` comes in numbers, `brute` is tough or
relentless, `caster` is frail and spends its turns setting something up. Size stays
independent, so an elite swarm is spiders drawn large rather than a different creature.

**The derivation was wrong twice, and the roster said so.** `rule_count() > 0` looked like
the mark of a caster and is nothing of the kind — reactive behaviour was handed out across
the board in D38, so it is nearly universal and put **all 35 archetypes in one family**,
which the new test caught immediately. Attack frequency was barely better: almost every
single-spawn enemy alternates attack and utility, so nine of ten sit at 0.50-0.67. What
actually separates them is **toughness** — brutes measure `hp_mult` 1.00-1.15 against
casters at 0.85-0.90, with `crypt_hound` the one frail thing that just attacks, which the
frequency clause catches. Measured split: **swarm 8, brute 6, caster 4**. Read off the
roster with a throwaway probe rather than guessed, and asserted afterwards, because a
derivation that quietly collapses into one bucket passes every other check in the file.

**What is asserted now.** Every COMBAT and ELITE tile must have a creature cast, from the
right tier's pool, and never a boss (a finale leaking into a corridor takes its signature
with it). Every wanderer likewise. And every family must match at least one enemy. Absence
is a failure rather than a default, because an uncast fight silently falls back to combat
rolling its own — which looks like nothing at all and undoes the whole feature.

Pacing 7.0 moves per encounter against the 7.5 ceiling; all four models still agree on the
budget at 13.2. The Warrens measures **85%** at a starter deck against 84% before the
change — checked at 60 trials rather than 400, which is the right precision for the claim
being made: casting cannot move the distribution because it draws from the pool combat
would have drawn from, so this is a check that nothing broke rather than a re-tuning.

**On the bestiary itself: not built, and the ordering is the point.** A screen was never the
valuable half. Binding the floor to real creatures is what had to happen first, and it was
worth doing on its own because it fixed a lie. What a bestiary would add on top is
*recognition*: a silhouette you have met gets named, one you have not stays "something
moving" — the fog rule extended from terrain to knowledge, which is the iso model's own
texture rather than a reference screen bolted to it. It needs `MetaState` to remember what
has been met, so it is meta-layer work and deliberately not in this pass.

**A collision to resolve, flagged rather than fixed.** D84 (built in parallel) introduced
`GameState.keys` for chests. D79's iso vaults have their own `TraversalIso.keys`. Two key
currencies, both called keys, both found on the floor, both spent to open something. The
iso vault should almost certainly spend the D84 key — one key concept — with the traversal
*reporting* the requirement and the view paying it, the way every other run resource
crosses that boundary (D13). Left alone here because merging two features mid-flight is a
design call, not a cleanup.

### D86 — Two keys, two locks, one idea: resolved by deleting mine

D79 gave the iso floor a sealed dead-end room holding a treasure, with a key placed across
the floor. D84, built in parallel from a play request, gave chests tiers, locks and
`GameState.keys`. The collision was worse than a duplicated counter:

* **Two currencies.** `TraversalIso.keys` and `GameState.keys`, both called keys, both
  found on the floor, both spent to open something — and a key found on an iso floor could
  not open a chest, which no player would ever predict.
* **Two locks.** A treasure behind a sealed door, and D84's chest behind its own tier lock.
  A Sealed-tier chest inside a sealed room wants **two** keys for one reward.
* **Two meanings of one word.** D84's "vault" is a chest lock that reads your *build*.
  Mine was a sealed tile. Same word, unrelated mechanics.

**And mine had been dead since the day it was built.** `_seal_treasures` required a tile
with exactly one walkable neighbour. The D79 architecture rewrite replaced the organic
carve with rectangles joined corridor-to-corridor, and **rooms of 2x2 and up have no
dead-end tiles at all** — measured after the fact: 0 sealed rooms and 0 dead ends across
60 generated floors. The feature had silently produced nothing for its entire life, and
nothing noticed because the tests only asserted properties *of* a vault ("has one way in",
"has a key") which are all vacuously true when there are none.

What caught it was writing the assertion the other way round — *sealed rooms generated
must equal sealed rooms opened* — while wiring the currencies together. **An invariant
about the members of a set says nothing until something also checks the set is not
empty.**

**So the fix is deletion, not plumbing.** `SEALED`, `KEY`, and the whole key-mirror
apparatus are gone from the model. A treasure tile already routes to the Chest screen,
which already has the tier, the lock and the run's keys — so the iso floor's contribution
is the *space you walk to reach a chest*, and the lock lives in exactly one place. Three
things fell out with it:

* The `keys_held` mirror I had just built — a documented input written by the view because
  a traversal may not read run resources (D13). Correct, and unnecessary the moment the
  model has nothing to gate.
* `_blocked()`, which existed only to make a sealed tile impassable.
* `_dist_open()`. Sight and movement had been split into two distance fields *purely*
  because a sealed room was visible but not enterable. With that gone they were the same
  function, and keeping both would have left a comment explaining a distinction that no
  longer existed.

Zero balance impact, and it is worth saying why that is certain rather than measured: the
deleted feature was generating nothing. Pacing 6.9 moves per encounter, budget 13.2 across
all four models, silhouettes 8/6/4.

**The lesson worth keeping.** Two sessions built toward the same play request from
different ends, and the duplicate was not caught by either one's tests, because each was
internally consistent. What exposed it was going to *read the other feature* before
extending mine — and what made the resolution obvious was noticing that the older, more
developed, measured system already covered the whole idea. **When two features collide,
check which one is load-bearing before deciding which one to adapt.** Mine was not
load-bearing; it was not bearing anything at all.

### D87 — WASD on a rotated grid, and the tiles that stopped looking like tiles

Two questions arrived together: should the floor take arrow keys, and should the
tiles go away entirely in favour of a continuous isometric world, Diablo-style. They
sound like one question about presentation. They are not, and the second one is the
interesting half.

**The keyboard was easy and had one real decision in it.** `options()` was already
indexed by direction and the view already drew one button per exit, so a key press is
the call the button was already making. What is not obvious is the *mapping*: the
four grid directions project to the four screen DIAGONALS, never to up or right. Bind
them grid-relative and W walks you down-right — the complaint every isometric game
with a rotated keyboard collects. Bound screen-relative, W is the most-up-and-right of
the four available and the ring of keys maps onto the ring of diagonals.

Which way round it rotates is a genuine coin-flip: ↗ and ↖ are exactly as "up" as each
other and no argument picks one. So it is **resolved by showing it rather than by
choosing well** — every move button carries its key letter beside its arrow, and the
mapping is read off the screen in two steps instead of inferred. A convention that
cannot be derived should be displayed, not documented.

**Hold-to-walk is paced by the animation, and that is the point.** A step is a TURN
here: the wanderers move when you move. Held at the OS key-repeat rate, a floor's
worth of exposure would be spent in about a second and a half with no decision in it
— which is exactly the greed the torch was removed to charge for (D77). So key repeat
is dropped, and a held key only rolls into another step when the current one has
finished walking. A held key also stops on anything that earns a beat: a descent, a
fight, or something NEW coming into sight. The player who walks into a corridor and
finds something in it has a decision in front of them, and walking through it because
a key is still down is the one way this feature could cost somebody a run.

**The tiles: no, and the reason is that the grid is not a rendering choice.**

`ISO_MOVES_PER_ENCOUNTER_MAX` is a ratio of discrete moves to encounters. It is what
enforces the D14 pillar — every traversal model costs the same — against three other
models that are all discrete by nature, and it is the specific guard that stops a
spatial model burying the card game (D79). A continuous world has no move to count.
Substitute distance or seconds and the comparison to deck/dice/graph stops being
commensurable; the test at `tests/test_traversal.gd` does not get harder to write, it
stops having a subject.

Two more, either of which would be enough on its own:

* **Lockstep is the tension.** "It takes a step whenever you do" is the whole exposure
  mechanic. Continuous movement forces the wanderers real-time, and then either they
  chase — pathing, aggro, kiting — or they do not and the pressure evaporates. Real-time
  dodging into a turn-based card fight is a seam between two genres.
* **Diablo's walking is not this game's walking.** There, movement *is* combat and
  positioning is the decision. Here the fight is a separate screen, so free-form
  movement between fights adds fidelity and no decisions — the exact shape of the torch
  D77 deleted: measured fine, did not feel like anything.

**What the request was actually after was reachable without any of that**, because
"it should read as a place, not a board" is a presentation problem:

* **The per-tile outline is gone.** On a floor of seamless stone drawn through fog
  tints, that hairline WAS the grid — the last thing saying the ground is made of
  cells. Without it, neighbouring tiles at one tint merge into continuous stone and
  the fog does the delineating it was drawing anyway. The reach highlight stays: at
  most four of them, and it is an affordance rather than a lattice.
* **The hero and the wanderers slide between tiles** instead of snapping. Diablo-feel
  is continuous *animation*, not continuous coordinates — which is the whole trick,
  and it costs one interpolated point. The camera and the hero are derived from the
  same one, so she stays nailed to `EYE_Y` and the floor slides under her exactly as
  it does when she is still.

**One deliberate imprecision, written down rather than fixed.** A sliding wanderer is
drawn at its DESTINATION tile's turn in the depth sort and offset back from there, so
for the length of one step it can be a tile out of order with the blocks around it.
The honest fix is re-sorting the standing pass by interpolated depth every frame — a
sort per redraw, to correct an error that is one tile wide and lasts an eighth of a
second. Wanderers also carry no id, so matching one to where it stood a moment ago
goes by design and type within one step; two of the same design standing a tile apart
are visibly the same thing twice, and a monster with no match simply appears, which is
what a monster stepping into sight is supposed to do.

**Measured non-regression, which is the only measurement this entry needs.** Iso moves
per encounter: **6.9 against the unchanged 7.5 ceiling** — a walk is the same turn it
always was, drawn over 0.13s instead of instantly. One keypress is one `select()`, one
entry in `steps`. That separation is the reason the grid was kept when the *look* of
the grid was dropped, and it is why this entry contains no rebalancing.

`tests/test_layout.gd` gained the guard that matters: **every direction the floor
offers has a key that walks it.** That failure is silent by construction — a direction
with no binding behaves exactly like a direction with a wall in it, so the only symptom
is a quarter of the floor being unreachable by keyboard with nothing saying why.

### D88 — Every dungeon became the crawl, and the other three models had been hiding a discount

All twelve `.tres` files now say `traversal = 3`. The switch itself is one line each. What it
exposed is the entry.

**Saves needed no migration, by a property already in the code.** `Traversal.from_state`
rebuilds a model from the `kind` stored *in the save*, not from the dungeon file — so a run
in progress on a node graph finishes on a node graph, and only new runs are isometric. That
was not designed for this; it is a consequence of each model owning its own serialisation
(D22), and it is why a switch this broad cost nothing at the save layer.

**Then the measurements came back and half the game was broken.** The Foundry at difficulty
3 with an Early deck fell from 63% completion to **0%**. The Abyssal Stair went 47% to 4%.
Two separate causes, and the second was the interesting one.

**Cause one: a constant fitted to a single dungeon.** `iso_ambush_cost` was
`9 + 2×(depth-1)`, tuned when exactly one dungeon used this model to make *that* dungeon
land where a difficulty-2 dungeon should. Applied to twelve it was a depth-scaling HP tax
stacked on dungeons already scaled for depth: 26 HP off an 80-point bar at d3, before a
single fight. It is now **7% of max HP**, floored at 3. A flat number cannot be right at
both 60 HP and 220 HP — it is a third of the opening bar and a rounding error by the
endgame — and depth-scaling it only chooses which end is wrong. A percentage is the same
*decision* everywhere, which is what a price for carelessness should be.

**Cause two: iso is the only model with nothing to skip.** This is the one worth
remembering. Measured fights actually *met*, per model, against a budget of 13.2:

| model | fights met | how it skips |
|---|---|---|
| graph | 4.5–5.1 | a route misses the nodes on the other routes |
| dice | **3.5–4.1** | overshoot sails past spaces |
| deck | 4.9 **+ 1.1 dodged** | pay HP to discard the card |
| iso | **5.9–6.0** | nothing. You strip the floor |

So three models had been quietly delivering a *discount* on their own budgets — the dice
worst of all, meeting barely a third of it — and every dungeon's difficulty was tuned
against whichever discount it happened to have. Moving them all to the model with no
discount handed each one a full extra fight. **"Equal encounter counts are not equal cost"
was already a pillar; this is the same lesson from the other side — a model's skip is part
of its price, and deleting the skip is a difficulty change nothing in the budget can see.**

**So the spatial model needed a spatial way to decline.** A tile holding a fight now also
offers to **slip past** it for HP, reusing `Balance.deck_avoid_cost` unchanged — the same
number, the same rising shape, because it is the same decision. It is ranked below even the
stairs, so a player leaning on the first button still faces everything and the headless
walkers still measure the full budget. The plumbing cost almost nothing: `_choose_option`
has evaluated `action: "avoid"` since the deck model existed, and the view already paid
option prices for the ambush.

| profile / dungeon | before (mixed models) | all-iso, no slip | all-iso + slip |
|---|---|---|---|
| Crypt d1, starter | 99% | 95% | 100% |
| Ossuary d2, starter | 68% | 48% | 62% |
| Warrens d2, starter | 85% | 99% | 99% |
| Foundry d3, Early | 63% | **8%** | 36% |
| Foundry d3, Status | 85% | 60% | 66% |
| Drowned Market d6, Late | 52% | 51% | 98% |
| Abyssal Stair d7, Thorns | 47% | 14% | 16% |
| Maw d8, Late | 40% | 15% | 22% |
| Maw d8, Endgame | 75% | 41% | 90% |

**A harness that selected by name went dark at the worst moment.** The avoid calibration —
the check that a priced dodge is not a *dominant* strategy (D20) — filtered on
`traversal == Kind.DECK`. With no deck dungeons it matched nothing and printed a header
with no rows: the tool that grades this exact mechanic fell silent on the turn a new model
inherited it. It now asks the model whether it prices a skip, by **walking** a floor and
looking, because a spatial model only offers one when you are standing next to a fight and
peeking at the opening options answers "no". *A harness that selects by name goes quiet when
the name changes; one that selects by behaviour follows it.*

**And the repaired harness immediately caught the mechanic it grades.** With the calibration
running again, two cells fail D20 outright — *always-slip clears more often than
always-fight*, which makes the skip a dominant strategy and therefore a removed decision:

    The Foundry    Early    face 13% | smart 36% (71% dodged) | avoid 43% (98% dodged)
    The Ember Road Status   face 52% | smart 61% (71% dodged) | avoid 79% (98% dodged)

Borrowing `deck_avoid_cost` unchanged was the wrong instinct after all, and the reason is
structural rather than numeric: **the deck offers one dodge per revealed card from a pile
that runs out, while a floor offers a slip at every fight standing on it.** Same price, far
more opportunities. Two candidate levers, neither pulled here because each needs its own
measured cycle: a steeper rise than `DECK_AVOID_STEP`'s +50%, or refusing to *offer* a slip
the player cannot afford — the payment is currently clamped so it can never be lethal, which
is correct for an unavoidable ambush and wrong for a price the player chose, because it makes
slipping past everything survivable by construction. **Left failing and visible rather than
quietly tuned**, since the tool now reports it on every run.

**Not finished, and the remaining gap is specific.** The deep dungeons at mid progression
are still harder than they were: the Abyssal Stair at d7 sits at 16% against 47%, the Maw at
d8 at 22% against 40%. The cause is legible — those were the *dice* dungeons, tuned against
the model that met barely 3.5 of ~13 budgeted encounters, so they carry the largest
discount to lose. Two levers, neither yet pulled, and both needing measurement rather than
a guess: `deck_avoid_cost` has never been exercised above d6 and its rising multiplier may
be too steep where it now runs (13 HP, then 20, then 26 at d8), and the d7-d8 enemy scaling
was set with a third of its budget effectively skippable. The endgame cells are already
*better* than before (Maw 75% → 90%), so this is a mid-game shape problem, not a global one.

**Deliberately not done.** The other three models are still in the tree and still work —
nothing was deleted. That is the fallback and the comparison baseline, and the argument for
deleting them is now stronger than it was, because a model no dungeon uses is a model
nothing measures: their numbers above are the last ones anyone will collect unless a
dungeon points at them again.

### D83e — Card frames, computed; and the illustration hook that was treating paintings as icons

Two halves of "make the cards match the art".

**The frames are generated, like the buttons (D83).** `Icons.card_frame()` has been
wired since the frame kit landed and had no files behind it, so every card in the
game drew the 2px flat rarity border instead. `tools/gen_ui_kit.gd` now emits
`frame_card.png` plus one per rarity: the same carved slate profile as the buttons,
so the hand and the HUD are the same object, with the rarity as a **coloured line
set into the stone** rather than a tint over the whole frame. Rarity has to be read
across seven overlapping cards at 150px wide, and a tinted frame is only legible
next to a differently-tinted one.

The margins are 14px, not the 40/40/48/56 ART_ASSETS specs. A card is 150x132 on
screen: a 48px top margin plus a 56px bottom one leaves 28px of stretchable middle,
Godot scales the margins down to fit, and the carved edge draws squashed. Exactly the
failure the buttons had. The spec numbers were written for a portrait card that this
game does not have.

**One call was returning two different kinds of picture.** `PixelArt.card_art()`
gives back either a 16x16 slice of the CC0 atlas or a painted 320x240 family
illustration, and `UI.card_button` treated both as an icon: tinted by rarity, held
at 22% opacity, aspect-centred. That is right for the atlas slice, which is a hint of
colour behind the name. It is wrong for a painting — a violet wash at 22% over an
illustration is mud, and it would have made Tier 3 look not worth drawing. A painted
one is now full-bleed, untinted, at 55%, with a gradient scrim from the card's
midpoint down so the rules text and the damage/Block numbers survive whatever the
illustration does there. The brief asks for a dark lower half as well, because a
brief is not a guarantee.

Not done: `ui/card_back.png` is in the manifest and nothing loads it — the deck
traversal reveals cards face-down and draws no back. That is a wiring gap, not an
art gap, and it is left alone rather than half-filled.

### D90 — The art pipeline had a backdrop-shaped hole in it, and the brief was lying about which way the enemies face

The question was whether to generate the remaining art with one image model, in a
coherent style. The answer is yes and it needed almost no argument — twelve dungeon
backdrops already came out of one, and they are the thing ART.md §1 calls "the style
bible". What the question exposed is that **the model was never the reason the rest of
the game is incoherent**, and that starting to generate against the brief as written
would have produced 35 files that were wrong in the same way.

**Three findings, in ascending order of how much they would have cost.**

**1. Two generators is two dialects.** `main_menu.jpg` and the twelve dungeons came
from one tool; the six scene backdrops and five zone shots from another. No prompt
reconciles that, and it is visible in a contact sheet. The fix is not a better
adjective, it is **image conditioning**: `bg_crypt.png` attached to every request,
including the ones that look nothing like a crypt, plus one style block that is
identical across all ~156 calls and is never improved between images. A hundred
individually-tuned prompts drift a little each, and a hundred little drifts is the
four visual languages again.

**2. Not everything on the list may be generated, and the file that says which had no
way to say it.** `ART_ASSETS.md` listed the nine-slice frames next to the enemies with
the same weight, when the frames are *computed* by `tools/gen_ui_kit.gd` for a
mechanical reason that has already cost this project a release-blocking smear (D83):
a nine-slice survives a 14x stretch only if its strips are constant along the stretch
axis. So `art_manifest.gd` grew a `Kind` per row — PAINT, SCENE, KIT, SHEET, LICENCE —
and a second output mode:

    godot --headless --script tools/art_manifest.gd -- --prompts > ART_PROMPTS.md

Same tables, same catalogues, so the prompt sheet cannot go stale against the game the
way a hand-kept one would. It emits the style block once, a per-tier recipe, and one
subject line per file — and, for each tier, which of its files are **not** for a
generator and why. The expensive mistake here is not a bad painting. It is a good
painting of a thing that had to be computed.

The 8-frame VFX sheets are marked SHEET for the same class of reason: eight plausible
frames of eight different explosions read as a strobe, not an impact. That is not a
prompt problem.

**3. The brief said "facing left", and the game has faced the viewer since D77.**
ART.md's Tier 2 section still described the side-on arena that the head-on framing
replaced, along with a `FLOOR_LINE` constant that no longer exists and two numbers
(34% enemy height, 68% standing line) that the code contradicts. The live values are
`HORIZON_LINE = 0.68` and `STAND_LINE = 0.72` — **deliberately different numbers**,
because a figure standing exactly on the wall/floor junction is at the far end of the
corridor rather than in the fight — and 38%. Thirty-five enemies generated against the
stale section would each have been individually fine and collectively unusable: a
corridor of monsters looking at the wall.

Worth noting *why* it went stale while `ART_ASSETS.md` stayed correct. The manifest is
generated and the brief is prose; the generated file had already been updated at its
source and the prose had not. That is the D34 habit in its purest form, and the fix
applied here is the same one: ART.md no longer restates a single count or constant
that the manifest computes.

**What was actually missing from the pipeline: alpha.** All three existing installers
assume an opaque 16:9 frame. Every remaining tier — 35 enemies, 30 relics, 10 powers —
is a subject on transparent at a fixed canvas size, and no image tool produces that.
It produces a painting of a monster in a room. `tools/install_cutouts.gd` is the
missing half: matte, despeckle, trim, scale, anchor.

Four decisions in it are worth keeping:

* **Matte by flood-fill from the border, not by chroma key.** The obvious approach is
  to ask for the subject on a key colour and drop that colour. There is no safe key:
  the five zone accents are cyan, orange, acid-green, deep-blue and *magenta* (ART.md
  §2), so every obvious key is somebody's light source. Filling inward from the border
  and requiring connectivity keeps a patch of stone inside the subject that happens to
  match the field from being punched out into a hole.
* **Refuse rather than guess.** If under 80% of the border agrees with its own average,
  the image is a painting of a room and the tool says so instead of cutting a hole in
  a wall. Likewise if what survives is under 2% or over 92% of the frame.
* **The despeckle pass is load-bearing, not tidiness.** `strip_sparkle.gd` cannot help
  here — it finds the watermark by intersecting "brighter than its surroundings" across
  images that share one frame, and a batch of cutouts at different sizes with different
  silhouettes shares no frame. It does not need to: the stamp is in the corner, the
  corner is background, the matte takes it. What it *leaves* is a small opaque island
  in the corner, which would then drag the trim box out to meet it and shrink the
  monster to fit beside its own watermark. Components under 8% of the largest are
  dropped, and the count is printed, because a silently-deleted limb and a
  silently-deleted watermark look identical from inside the tool.
* **Bottom-anchoring is per-family, not a flag.** Enemies are placed with their feet on
  `STAND_LINE`, so transparent padding under the subject is that enemy hovering by
  exactly that much, in every fight, forever — a defect that is invisible in the file
  and obvious in the game. Relics and powers sit in a square slot and are centred. The
  installer trims to the alpha bounding box and puts the lowest opaque pixel on the
  canvas's last row; measured on fixtures, bottom gap 0px for enemies and 2px for a
  centred relic.

Name matching earns its complexity for the same reason D73 did: **the filename is the
wiring.** A generator names its output after the prompt, so sources are matched against
both the id and the display name with copy-numbers stripped — `The Grave-Sexton (2).png`
lands on `grave_sexton.png` — and anything unmatched is listed loudly at the end,
because a file nobody could place is art that was made and will never load, which from
the game's side is indistinguishable from art that was never made at all.

**Not done, deliberately.** No art was generated in this entry. The 21 status symbols
need a white-and-alpha flatten step on the way in that does not exist yet — they are
specced monochrome-tintable because callers tint by rarity and fade spent states, and
a coloured icon cannot be tinted, only muddied. That step is a real piece of work and
pretending the tier is unblocked would be the half-added content D42 exists to catch.

### D89 — The art that could not be committed, and the half of it worth generating

The request was "I do not like the game assets and they prevent us to commit — can we
generate new ones that go with the background style?" The second clause turned out to
be the literal problem, and it was already written down: `assets/art/iso/README.md`
said, in its own heading, **"Licence status: UNKNOWN for the floor, NON-COMMERCIAL for
the hero."**

* The four floor packs arrived as bare `~/Downloads` directories with no licence file,
  no readme and no attribution of any kind. Their shape matches the free tiers that
  CraftPix and itch.io hand out, which commonly permit *use in a game* while forbidding
  **redistribution of the art**. Committing a file to a repository is redistribution.
* The hero is Engvee's prototyping hero, whose store page states its terms in prose:
  "for prototyping, **non-commercial** use". Not unknown — known, and disqualifying.

Nothing had been committed yet (`assets/art/iso/` was entirely untracked), so this was
caught before it became a licence problem rather than after. That is luck, not process,
and the process gap is dealt with below.

**Materials: generated, and better than what they replace.** `tools/gen_iso_art.gd`
computes ten seamless textures — a ground/wall pair per terrain in
`Balance.ISO_TERRAINS`, plus the bare fallback names. Deterministic, so a regenerate is
a real diff rather than ten mystery binaries.

The part worth keeping is how the colour is decided. "Goes with the painted backdrops"
is a judgement, and judgements drift, so it is made mechanical: **each terrain's ramp
is sampled from the floor band of the backdrops of the dungeons that actually use that
terrain.** The Warrens are `earth`, so the Warrens' iso floor is built out of the
colours of the floor in `bg_warrens.png`, taken below `PixelArt.HORIZON_LINE` — the
same constant `tests/test_art.gd` already asserts every backdrop agrees with, so the
two cannot drift. Repaint a backdrop and the floor follows. It is D34's rule applied to
pixels: derived, not matched by eye.

**Two failed palettes before the third worked, and both failures are instructive.**

* Indexing one sample per percentile gave worked stone `#3c0c00 #2d2136 #22346a
  #773c22` — a red, a purple, a blue and a brown. Four dungeons feed that ramp, and
  consecutive luminances belong to whichever painting happened to own that brightness.
* Averaging a window around each percentile fixed the incoherence and left a hue
  *sweep*: dark violet climbing to pink. The brightest percentile of a floor band is
  not floor at all — it is the braziers these rooms are lit by.

What works is taking chroma and value from **different places**. Hue and saturation are
one saturation-weighted circular mean over the middle of the distribution — the colour
of the ground itself. The value ramp is the percentile spread — how that ground is lit.
No stop can drift to a different hue because there is only one hue. **A material is one
surface lit across a range, and a sampler has to be built to produce that rather than
hoping the statistics land there.**

Two smaller measured corrections: absolute level is set by the view, not sampled (these
paintings are dim, and `iso_run.gd` multiplies by fog tints again — shipped as sampled
the floor was near-black with no headroom left to dim); and the normaliser backs its
factor off rather than clamping per channel, because clamping pinned red at 1.0 while
green and blue kept scaling and turned the brightest stone into `#ffc5dc`.

**Seams are measured, not assumed.** Every pattern is evaluated on a torus. The check
compares the wrap step against the interior as a control, and the first run reported
worked stone at **3.95x** — which was not a visible seam but a bad probe: the control
sampled a single column at x=128, which happened to fall inside a cobble where
neighbours are nearly identical. Averaged over every interior column instead, the same
file measures **1.64x**, and the four floors land between 0.55x and 1.64x. *A control
has to be representative of the whole texture, or the ratio measures where you put the
probe.*

**Figures: rejected, then partly reinstated when the rejection was tested.**

*(Revised. The first version of this entry ended here with the figures deleted. A
capture of the combat screen taken afterwards showed the judgement had been made
against the wrong comparison, and the reversal is recorded rather than edited away.)*

**Figures: generated, looked at, and thrown away.** The same pipeline drew the hero,
three monster families, the wanderers, the furniture, and 35 combat plates whose
silhouette proportions were derived from each archetype's own fight data — bulk from
`hp_mult`, reach from `dmg_mult`, count from `count_max`, family from
`Balance.iso_family` itself, which already sorts archetypes from their numbers for
exactly this reason.

The derivation worked. The art did not. On the contact sheet the brutes read as coffins
with antennae, the robed figures as lava lamps, the campfire as a traffic cone, the
chest as a plain box. **It was worse than the CC0 pixel sprites it was meant to replace
and worse than the drawn fallback already in the code**, so it is recorded here and not
shipped, and the three files that made it are deleted rather than left in the tree
looking like the pipeline.

Worth being exact about the mistake, because it was predicted before it was made: the
plan offered was *materials procedurally, figures as designed markers*, on the stated
grounds that procedural generation handles seamless surfaces well and figures badly.
That is what the evidence then showed. **Building the thing you have just argued
against, because the code is right there, is how a scoped pass turns into a rejected
one.**

Two things survive the deletion. `scripts/art_palette.gd` is the sampler, which the
material generator uses and any future one will. And the finding that a *marker* and a
*failed monster* are not the same object: `iso_run.gd` already falls back to a lit
ground ring and a lantern-bright pip and treats that as the real marker rather than a
degraded one, which is better than what was drawn to replace it.

**The process gap, which is the durable part.** `tests/test_art.gd` had a licence check
already — over a hand-written list of four directories. `assets/art/iso/` was not on it,
which is exactly how thirty-three unlicensed files sat in the tree for a milestone with
a README next to them announcing the problem to nobody. The check now **discovers**
every directory under `assets/` holding a PNG, and requires each file to be accounted
for in one of three ways: a licence file beside it, a README (its own or its parent's)
naming a generator that exists, or a `.gitignore` pattern keeping it out of the
repository. It reports **98 PNGs across 7 directories**, and it found a real gap on its
first run — the UI frame kit is generated by `tools/gen_ui_kit.gd` and nothing in its
own directory said so.

*An invariant guarded by a hand-kept list of places is guarded nowhere new.* The same
lesson as the empty-set one two entries earlier, in a different costume: the assertion
was fine and the enumeration was what rotted.

**The reversal, and what actually decided it.** The plates were rejected from a contact
sheet at 4x actual size, viewed in isolation, against an imagined alternative. Then the
combat screen was photographed: the enemy standing in front of that painted crypt is a
16x16 tile scaled to 240px and modulated dark, and it reads as a **black pixelated
cross**. The claim "worse than the CC0 sprites it was meant to replace" had never been
tested against the thing it named.

Rebuilt and shipped for the arena. Two defects carried the original failure, and both
are the kind that only a capture finds:

* **No waist and no gap between the legs.** A silhouette running from shoulder to floor
  at constant width is a coffin whatever is drawn on it. The head now sits clear of the
  shoulder line on a neck and the legs are separate shapes with air between them;
  `ArtShapes.measure` reports a **waist ratio** and the generator prints the worst on
  every run. Brutes measure 0.40–0.44 against a coffin's 1.00.
* **`BODY_DARK = 0.10` was rendering at about 0.50.** It was run through a transform
  carrying a 0.25 floor, so the constants said "dark silhouette" while the screen showed
  a pale pink creature floating in front of the room rather than standing in it. *A
  constant named DARK has to survive the transform applied to it.*

A third, cheaper lesson sits between those two: the first re-capture still showed the
Kenney sprite, because the plates had been written after the last `--import` and
`ResourceLoader.exists()` answers for the imported resource. A generated PNG with no
sidecar is invisible to the game and looks exactly like a generator that did nothing.

**So the corrected rule is narrower than the one first written here.** Not "procedural
figures are bad" — procedural figures at *arena* size, judged in context, are a clear
improvement on a magnified 16x16 tile. What is bad is judging art on a contact sheet
against an alternative you have not photographed. The iso floor's own figures are still
absent, and that is now a scope decision rather than a verdict: the fallback ring and
pip are good, and the same generator could dress that floor whenever it is wanted.

**And then the isometric floor got them too.** Once the plates worked in the arena the
same generator dressed the floor: hero, three monster families, four wanderer designs
and four pieces of furniture. `ArtShapes.brute/caster/swarm` are shared between the two
generators, which is a rule rather than a saving — D85 casts the enemy when the floor is
laid out, so a wanderer crossing a hall IS the fight it will become, and the thing you
see coming has to be the thing you meet. Two copies of those tables would drift the
moment one screen was tweaked.

**What went out with it.** Generated art made three things dead, and dead art is worse
than no art because it looks like a decision:

* `assets/pixel/enemies/` — 41 CC0 tiles handed out **by sort order**, needing a
  12-entry override table to stop bosses inheriting trash-mob faces. Gone with the
  machinery: `enemy_sprite`, `enemy_sprites`, `OVERRIDES`. Plates are keyed by id, so
  "two enemies share a face" and "adding an archetype reshuffles everyone downstream"
  are now impossible rather than merely tested for. Two tests changed shape as a result
  — `test_content` measured *sprite headroom*, meaning how many spare tiles remained
  before the next archetype started sharing, and that quantity no longer exists.
* `assets/pixel/ui/` — the Kenney UI pack, with **zero callers**. The procedural frame
  kit replaced it and nobody deleted it.
* `tools/install_iso_art.gd` — the installer for the unlicensable packs, along with the
  `.gitignore` block holding their filenames out of the repository. Both were scaffolding
  for a problem that no longer exists.

Figures for the isometric floor are no longer outstanding. What remains outstanding is
*painted* art rather than designed markers, and the brief for commissioning it exists
and is generated from the code that consumes it (`tools/art_manifest.gd`: canvas,
anchor, standing line, lighting direction, and why a pale-footed figure dissolves into
these backdrops).

### D91 — Twenty-one icons that had to be one image, and an alpha channel taken from the wrong place first

Two tiers were left blocked at the end of D90 and both were blocked for the same
un-obvious reason: **the unit of work is the set, not the file.**

**Why a sheet.** The 21 status symbols, the 7 intent telegraphs, the 10 power sigils
and the 7+7 map icons share a requirement that no individual file can satisfy — they
have to be **distinguishable from each other**. Seven intents that each read as "angry
shape" have failed even if every one of them is handsome, and the intent telegraph is
the core read of the whole combat system (ART.md Tier 1c). Requested one at a time,
each request is blind to the other six, and the third one comes back as a shield again.
Requested as one gridded image, the model sees the set while drawing it and consistency
of hand costs nothing. `tools/install_sheet.gd` slices the grid, mattes and trims each
cell individually — so an icon that sits off-centre in its cell still lands centred in
its own file — and names the cells against the catalogue.

**The cost is positional assignment, which this project already has a scar from.**
`PixelArt.enemy_sprite()` hands sprites to archetypes by sort order and needed a
12-entry override table to stop bosses inheriting trash-mob faces; D73 was about
deleting exactly that. A sheet has no filename per cell, so it cannot be avoided here —
only made survivable, in three ways. The order is **not implicit**: `ART_PROMPTS.md`
prints it into the prompt from the same tables `install_sheet.gd` reads back, so the
order asked for and the order installed are one list. The mapping is **printed on every
run**, with a standing instruction to check it against the sheet. And a cell whose
subject touches its own edge is **reported as probably clipped**, because that is the
one misalignment the per-cell trim cannot repair. A set installed one cell out is 21
correct icons on 21 wrong meanings, and nothing downstream would notice.

**The monochrome flatten, and the matte that was wrong for it.** The symbols are
specced tintable — `Icons` tints by rarity and fades for spent states, and a coloured
glyph cannot be tinted, only muddied. The obvious implementation was to reuse the
flood-fill matte from D90 and then paint the result white. That is wrong, and not for a
subtle reason: **a flood fill resolves every pixel to in or out**, which turns a glyph's
anti-aliased edge into a staircase — immediately visible, because these are authored at
64px and the canvas is scaled up to 3x on a 4K display (D65). Alpha comes from
**luminance** instead, which keeps the edge as the partial alpha it already was.
Measured on a fixture: 1080 visible pixels, of which 378 are partial alpha and zero are
non-white. There is nothing lost by discarding the hue, because the destination is one
colour by contract.

Two corrections inside that, both found by fixtures rather than by reading:

* **Polarity is read off the border, not assumed.** A generator asked for "white glyph
  on black" returns black-on-white often enough that hardcoding the direction would
  silently invert part of a set — and an inverted glyph is not obviously wrong in a
  thumbnail, it is a filled square with a hole in it.
* **An empty cell has to be recognised as empty, not normalised into one.** A 5x5 grid
  holding 21 symbols has four spare cells. The autocontrast that stretches field-to-peak
  into 0-255 will happily divide an empty cell's sensor noise by its own tiny span and
  produce a confident, fully opaque field of static — which then passes every coverage
  check there is, because it *is* covered. A dynamic-range floor rejects the cell before
  the stretch runs.

**The refactor that came with it, and why it was not optional.** `install_cutouts.gd`
already contained matte, despeckle, erode, trim, scale and anchor. `install_sheet.gd`
needs all six. Copying them would have produced two implementations of "what a cutout
is" that agree today and diverge on the first tuning change — the D34 habit that has
cost this project four bugs. They live in `tools/cutout_lib.gd`, deliberately **not** a
`class_name`: these are diagnostics that never ship, and a global class would put them
in the game's class list beside `CardData` and `EnemyData`.

**Also fixed here: a D-number clash.** Two entries were numbered D88 — the traversal
consolidation and D90's art-pipeline entry, written in parallel sessions. The art one is
renumbered, and its references in AGENTS.md with it. This is the second time (see
`097069c`), and both times the cause was the same: an entry appended to the log while
another session held a stale idea of the last number. Worth checking `grep '^### D'`
before appending, not after.

**Still not done.** No art has been generated. What is unblocked is the whole icon half
of the list — 21 symbols, 7 intents, 10 powers, 14 map icons, 6 dice — as five sheet
requests instead of 58 individual ones.

**One miscount, caught by reading the output rather than the code.** Tier 4 reported 26
files as generable when five of them are computed nine-slices — the `MAP_KIT` loop was
the one table-walk that did not pass `_kind_of(e)`, so its per-row kinds were silently
replaced by the section default. The tags were right and the plumbing dropped them,
which is the failure mode a per-row override always has: it is invisible unless the
default happens to be wrong. Generable total 156 -> 151.

### D92 — The matte could not reach the background the monster was standing around

Six painted enemies arrived for install — four regular archetypes and two bosses
(`mycelial_lord`, `grave_sexton`). `install_cutouts.gd` reported a clean sweep: six
written, nothing unmatched, every enemy now has art. The contact sheet said otherwise.
The skeleton had a **slab of flat magenta behind its ribs**, the grave-sexton had a
lozenge of yellow in the eye of its own halberd hook, and the tomb guard wore a crimson
halo around its shield. The tool was not lying — it had done exactly what it was written
to do.

**Why the fill cannot reach it.** `matte()` is a magic wand from the frame edge, not a
chroma key, and that choice is right: the zone accents run cyan, orange, acid-green,
deep-blue and magenta (ART.md §2), so every obvious key colour is somebody's light
source. Connectivity is the safeguard — it is what stops a patch of stone inside the
subject that happens to match the field from being punched into a hole. The **cost of
that safeguard is the exact opposite defect**: field that the subject's own silhouette
seals off from the border is unreachable, so it survives fully opaque and still
background-coloured. A gap between a raised arm and a torso. The eye of a hook. The
triangle between two legs.

**`despeckle` structurally cannot catch it,** which is why nothing upstream noticed. A
trapped pocket *touches* the subject, so it is part of the subject's own connected
component — the largest one — and no island threshold will ever see it. And because the
sources are per-enemy colour fields, the defect is a different colour on every enemy;
there is no single artefact to grep for.

**The discriminator, measured rather than guessed.** The naive fix — clear anything near
the background colour — would have been a disaster, and the batch contained its own
counter-example. The hexer is grey armour on a grey field: 10,166 of its pixels sit
within the ordinary `TOL` of the background, in a scatter whose largest blob is 1,247px.
Those are its pauldrons. Sweeping the tolerance separated the two populations cleanly,
because **a trapped pocket is the literal untouched field and sits at distance ~0**,
while armour that resembles the field merely comes close:

```
                tol=0.14 tol=0.08 tol=0.05 tol=0.03   <- largest enclosed blob, px
bone-picker        10182     9422     8810     8034    trapped magenta
tomb-guard          7282     6229     4887     1958    trapped crimson
grave-sexton        2836     2646     2498     2297    trapped yellow
mycelial-lord       1074      962      882      786    trapped blue
hexer               1247      181       95        7    GREY ARMOUR — must survive
plague-rat             7        1        0        0    already clean
```

At `HOLE_TOL = 0.05` the real pockets stay in the thousands and the false positives
collapse under a hundred. A minimum area of 0.05% of frame sits in the order-of-magnitude
gap between the smallest real pocket (0.084%) and the largest false one (0.009%), and
exists because tolerance alone leaves a scatter of single pixels inside textured armour —
punching those out is not a fix, it is speckle.

**Two tolerances, doing two different jobs — and collapsing them was the first attempt's
bug.** Filling only the tightly-matching core removed the slabs and left a **rim**: the
field carries a faint vignette, so a pocket's middle is at distance ~0 while its outer
ring drifts to 0.08–0.14, and a tight threshold stops short by exactly the width of the
gradient. The probe showed it plainly — every survivor had `mean_dist` 0.03–0.09 with
`max_dist` pinned at the loose bound. So `HOLE_TOL` is **not a claim about where the
pocket ends, only about where it can safely be RECOGNISED.** Once enclosure and area have
established that a pocket *is* field, it has earned the same trust the frame edge gets,
and the ordinary `TOL` can finish the job. Seed tightly, grow normally. Growing an
*unverified* seed at `TOL` is the thing that would gouge the hexer — so the tight test
guards the seed, not the growth.

```
largest near-background blob remaining, px
                  before   tight-only   seed-and-grow
bone-picker        10182         199          62
tomb-guard          7282        1921          29
grave-sexton        2836          31           3
hexer               1247        1247        1247   <- untouched, correctly
plague-rat             7           7           7
```

`hexer` and `plague_rat` come out with **bit-identical opaque fractions** (26.8%, 30.1%)
to before the change — the strongest available evidence that nothing was gouged where
there was nothing to fix. All 34 suites pass.

**A false alarm worth recording, because it will recur.** Opening `mycelial_lord.png`
directly appeared to show the install had failed completely — full blue field, black
frame, watermark plainly visible. The file was correct. `apply_alpha` sets alpha to zero
and **deliberately leaves RGB untouched**, so a viewer that ignores alpha renders the
matted background, the transparent pad, and the already-removed sparkle as if they were
still there. The contact sheet uses `blend_rect` and respects alpha, which is why it
showed the truth. The standing rule that art direction is judged by looking (D56) needs
the corollary that **what you look THROUGH matters**: for a cutout, use the sheet or the
opaque fraction, not a preview of unknown alpha handling.

**Counters are per-file or they are lies.** `filled_pockets` is reset at the top of
`cut()` and `cut_mono()`, not only inside `matte()` — an image arriving with usable alpha
skips `matte()` entirely and would otherwise be reported carrying the previous image's
number. Both counts are printed for the reason `dropped_islands` always was: from inside
`cutout_lib.gd`, a filled pocket and a gouged subject look identical.

**Not fixed here.** `bg_crypt.png` was also in the drop but is a backdrop, not an enemy;
it is the style reference from D90 and already installed, so it was left out of the
staging directory rather than fed to a cutout installer that would have refused it for a
non-flat border. `install_sheet.gd` shares the `cut()` path and so inherits the fix, but
reports neither counter — it reported neither before either, so that was left alone
rather than half-changed.

---

### D94 — Three ways to walk a dungeon that nobody could walk, and one label that said the same thing twelve times

Every dungeon in the game has been an isometric crawl since D88. The three models it
replaced — a layered node graph, a dungeon-as-a-deck, a dice board — stayed in the tree
as a fallback nothing fell back to. This deletes them.

**What "fallback" was costing.** Four models is four things that must keep compiling,
four serialization formats the save has to be able to rebuild, four views the screenshot
harness photographs, and four entries in every loop in `tests/test_traversal.gd`,
`test_layout.gd` and `test_resume.gd`. All of that ran on every commit for content that
could not be reached from the menu. Worse, dead code is not inert:

* The avoid calibration in `tools/sim_balance.gd` filtered on `Kind.DECK`, matched
  nothing after D88, and printed a header with no rows — recorded at the time (D88) as
  a lesson about harnesses that select by name.
* **The same filter was in `tests/test_traversal.gd` and nobody noticed.** The block
  asserting that dodging is a trade and not a discount — the D20 property, the one the
  price was retuned for in D57 — skipped every dungeon in the game for the same reason
  and printed nothing at all. It was found by deleting the field it filtered on, which
  is the only way a vacuous test ever gets found. It now runs over all twelve, and
  passes.
* `tools/screenshots.gd` hung for twenty-two minutes on shot five handing the graph view
  a `TraversalIso`, and had to grow a "force the model" branch to keep photographing
  screens no player would see.

**What went.** `traversal_graph.gd`, `traversal_deck.gd`, `traversal_dice.gd` and their
views `map.gd`, `deck_run.gd`, `dice_run.gd` with `Map.tscn`, `DeckRun.tscn`,
`DiceRun.tscn` — about 800 lines. With them: `Traversal.Kind`, `Traversal.make()`,
`Traversal.kind()`, and `DungeonData.traversal`, which was a per-dungeon choice with one
option in all twelve `.tres` files. `GameState.run_scene()` is now a constant with a
function's signature, kept as a function because it is the one place that decides.

**What stayed, and why.** The `Traversal` base class. One implementation behind an
interface looks like ceremony, but it is what keeps the crawl pure logic — no UI, no
autoloads — which is what lets one headless walker in `sim_balance.gd` measure it, and
`test_traversal.gd` still loops over an array of models rather than over the crawl
directly, so a second model rejoins the suite by being named rather than by someone
writing a second walker. `Balance.deck_avoid_cost` was renamed `avoid_cost`: the crawl
inherited that mechanic in D88 and now owns it, and a constant named for a deleted model
is a comment that lies.

**Saves.** A run saved on a deleted model describes a board the crawl cannot read, and
every field it would look for is missing — restoring one would hand the player a
half-formed dungeon rather than an error. Saves written before this stamp the model
number in the traversal blob; the crawl's was 3 and it now writes none. So
`GameState.traversal_is_current()` drops any run stamped with anything else. It is static
and separate from `run_from_dict` for a reason worth writing down: `run_from_dict` reads
autoloads through absolute paths, a `--script` test has no active scene tree, and the
first version of that test passed because the function bailed on line one. **A guard is
only tested if the test can reach it.**

**The label.** `ZoneView` printed each dungeon's traversal name on its button. With one
model it read "isometric floor" on all twelve — the widest line on the screen, spent
saying nothing, and worse than nothing because a value that never varies still reads as
a distinguishing fact. Gone. What tells the twelve apart is already on that screen and
already true: difficulty, boss, description, exclusive cards, and the shape and surface
of the floor itself (D82).

**Also found while deleting.** `TraversalIso.options()` walked off the end of an empty
grid when handed a blob with no cells — reachable only from a degenerate restore, which
the new guard now rejects before it gets there, but a model should not error on its own
empty state. It returns no options instead.

34/34 suites green.

### D95 — A review of the game as a game, and the five defects worth fixing the same afternoon

The systems have been measured since D5. Nothing had ever been pointed at what the
build *is to play*, and the two are no longer in step: the engineering is well ahead
of the game. `REVIEW.md` is that pass — 20 screens captured with `tools/Screenshots.tscn`
and looked at, the art manifest regenerated, all 100 cards / 30 relics / 10 powers /
20 events read as data, and the whole thing scored on playability, graphics,
originality, fun and content. It is not a decision log; it is the outside view, and
its P0 list is the argument for what to build next. This entry records what came out
of it that was small enough to fix immediately.

**The three findings that are NOT small, stated here so they are not lost in a
document nobody re-opens:**

1. **The hand is unreadable at rest.** A resting card deliberately shows only its name
   (`ui.gd`), and the fan overlap (`combat.gd`) covers exactly that. A capture of a
   five-card hand reads `Smith's Fu… / Prepare / Bludgeo… / Bite / Shiv`. The one thing
   the resting state exists to show is the one thing the layout hides. The fix is to lay
   the name into the strip the fan leaves visible, and it wants an assertion in
   `CardTextTest`: in a full hand, no card's name rect may intersect the next card's rect.
2. **There is no card art at all.** `assets/art/cards/` does not exist, so
   `PixelArt.card_art()` falls through to a 16x16 CC0 atlas tile which `ui.gd` then
   stretches across a ~160x210 face at 22% alpha. **This is D89's lesson recurring on the
   most-looked-at object in the game** — a 16px tile magnified ten times is noise, and it
   was diagnosed once already on the enemy plates. Twelve family illustrations would move
   the look of the whole product further than any other twelve files.
3. **Roughly 36 of 100 card names are Slay the Spire's verbatim, and 14 copy the effect
   AND the constant** — Bludgeon 32 damage exhaust, Impervious 30 Block exhaust, Cleave 8
   to all, Adrenaline, Pummel, Twin Strike, Barricade, Body Slam, Entrench, Footwork 2
   Dexterity, Inflame 2 Strength, Shrug It Off 8 Block draw 1, Strike 6, Defend 5. The
   numbers are the tell: a constant arrived at independently does not land on 32. The
   renames are a data edit; the fourteen need re-tuning, and therefore a sim pass.

**What was fixed here.** Five defects, chosen because none of them needed a
measurement and none touched a file the concurrent D94 work held.

**A guard that existed in one of two identical lists.** `deck_builder.gd` rendered
`Abyssal Gift [RARE] Lv1/15 owned 1 ()` for any card with neither damage nor block.
`collection.gd` builds the same row from the same fields and had guarded the empty
string all along. The two lists are near-copies of each other and had drifted exactly
where a copy drifts — this is the duplicated-logic rot the working rules already warn
about, showing up in layout rather than in a constant.

**Two screens that opted out of the boilerplate and so opted out of the art.**
`deck_builder.gd` and `collection.gd` were the only screens rendering on flat black.
Root cause: both hand-rolled the `MarginContainer` + `VBoxContainer` scaffold instead
of calling `UI.screen()`, and `UI.screen()` is what installs the backdrop. Its own
docstring says it exists "so one edit changes the look of all of them once there is
art" — which is true, and worth nothing to a caller that does not call it. Both now do.

**A minimum size that was not a minimum.** The Packs screen's three "Open" buttons sat
at three different x positions. The label already carried a `custom_minimum_size.x`, so
the obvious diagnosis was wrong: a Godot `Label` reports its *text* width as its minimum,
so it grows past the floor and the button's x tracks the pack name's length. `clip_text`
makes the floor real. The new width was measured against the longest string the tier x
build x dungeon tables can actually produce (569px) rather than picked.

**A relic that was another relic.** `scholars_lens.tres` and `keen_lens.tres` were
byte-identical apart from `id` and `name` — both "Draw 1 extra card each turn.", both
rarity 3, both `extra_draw = 1`. Scholar's Lens becomes ON_TURN_START / 3 -> DRAW 2,
"Every 3rd turn, draw 2." Differing in KIND and not in magnitude was the whole point:
the review's complaint about this roster is that **18 of 30 relics are numeric tiers of
five templates** (five +max HP, five start-with-Block, three gold%, two +1 draw, two
start-with-Strength), against a pillar that says relics should change how you play. A
sixth tier would have closed the defect and widened the flaw.

> **NOT MEASURED. This is a balance change and it has not been simulated.**
> `triggered_power()` does price ON_TURN_START/DRAW into `power_ratio`, so scaling folds
> it in and `test_balance`'s invariants are green — but green invariants are not a
> measurement of outcomes. The relic moved from `extra_draw * 14.0`, a flat term
> deliberately routed around `flat_power()` because draw is multiplicative, to
> `triggered_power()`'s additive `2 * 1.5 * (TARGET_NORMAL_TURNS / 3)`. Two different
> pricing paths with different semantics; the delta is unchecked, and the Relic profile
> leans on it. **Run `tools/sim_balance.gd` before trusting it.**

**And the test that named the thing it was testing.** `test_relic.gd` loaded
`"scholars_lens"` by id as *the* extra-draw relic, so the redesign broke it — the same
shape as the avoid calibration that filtered on a `Kind` that stopped existing (D88),
except this one failed loudly instead of going quiet, which is the good outcome and only
by luck. It now asks the catalogue which relic grants `extra_draw` and derives the
expected hand size from that relic's own value. With the non-vacuity check beside it:
if no relic in the catalogue grants a draw, the hand-size assertion has nothing to test
and says so, rather than passing. Both halves of that are already written down as rules
here — a harness that selects by name, and an invariant about the members of a set.

**Documentation.** `README.md` was stale in four places, not three: three traversal
models listed when there is one (the two counts were both wrong and neither named the
model actually in use), "decisions D1 through D38" against a log at D94, a status line
claiming CC0 placeholders and no animation when 23 backdrops and 35 enemy plates are
generated and combat has tweened feedback, and — found while fixing that — a licence
section claiming *all* audio is Kenney CC0 when the five music tracks are generated by
`tools/gen_music.py` under the repo licence, which `assets/audio/music/PROVENANCE.txt`
has said all along. A licence claim that is wrong in the permissive direction is the
one kind of stale sentence that is not merely untidy.

**Not fixed, and why.** The crawl's header wraps mid-phrase (`AT RISK: 0` / `cards, 0
gold`) — `iso_run.gd` was held by the D94 work. `assets/art/README.md` lists
`cards/<family>.png` as "generated (Leonardo)" for a directory that does not exist; the
table is describing intent as fact, which is the same defect class as the `iso/` README
headed "licence status: UNKNOWN" in D89, and it deserves its own pass rather than a
line here.

### D96 — The hub was the only screen with no art on it, and the one line meant to sell a zone described no deck

The world screen was the screen the player returns to after every run, and the only
navigation screen in the game rendering the tiling 16x16 pixel pattern instead of a
painting. `UI.screen(self, "The World")` passed no `art`/`scene`/`zone`, so it fell
through to `PixelArt.backdrop()`. One click deeper, `ZoneView` passes `z.id` and gets
`bg_zone_barrows.png` full-bleed. Five establishing shots already existed on disk. The
hub showed none of them.

**Rows carry the art, not the background.** The obvious fix — pass the deepest unlocked
zone to `UI.screen` — was built and photographed, and the capture rejected it. Whichever
zone that picks is a zone that also has a row in the list, so the screen drew the same
picture twice; and at `ZONE_DIM` the painting's one bright band ran directly under the
sealed rows' prose, which is a contrast regression the 0.60 dim was never measured for
(it was measured against `ZoneView`, whose rows are opaque). So the establishing shots
go in the ROWS, as 160x82 thumbnails beside the text, and the pattern stays the
background. Five paintings on one screen, more than any other screen has, and **no
contrast measurement needed at all — a thumbnail sits beside its text, never under it.**

**A locked row recedes by ink, not by opacity.** The first version dimmed sealed rows
with `row.modulate = Color(1,1,1,0.62)`. Translucent text does not read against a colour,
it reads against whatever is behind it, and "Sealed for a reason" landed on the mist. A
flat darker `font_color` is the same recession with no dependency on the backdrop.
Related, and the reason four of five rows needed to recede at all: on a fresh save four
zones are sealed, and at equal weight they buried the one that could be pressed.

**Sized against a number, not a taste.** 168x95 with a 10px gap put the fifth zone half
off the bottom of the list — five pixels over, and a new player's first sight of the hub
was a picture sliced by the frame edge. 160x82 with a 6px gap fits all five inside 720p.
The gap also moved from the text column to the list: inside the column it only separated
rows whose prose was taller than their thumbnail, so the four sealed rows ran their
pictures into a continuous strip.

**The pool line described no deck, and could not be made to.** It read
"Deck cards found here: Adrenaline, Anvil Stance, Bash, Berserker Rage, ..." — alphabetical,
truncated at ten of seventeen. Naming the deck instead was tried twice and **measured
out both times.** Per-zone build coverage: the best build in each zone runs 25–40% with
the next two within a few points of it (Barrows 36/30/30, Beyond the Stair's best is 2 of
8 cards). Mechanical concentration is no better — it rests on two or three cards out of
twenty, so "the Barrows is where cards grow" would be a claim built on two files. This is
not a content gap to fix: `test_build.gd` *enforces* that builds are scattered across
zones, because a build you can farm in one place is a build with no journey in it. **There
is no zone theme to name, and a label claiming one would be invented.** What replaced it
is what the decision actually turns on and is true: how many cards the pool holds, how
many of them you do not own yet, and what is found only here.

**Four numbers moved onto the buttons that lead to them.** The footer restated
`Cleared · builds · relics · cards` one line under a nav row whose buttons led to exactly
those four screens, and `Cleared` was also in the header. The Packs button already carried
its count with the reason written beside it — "a menu entry that does not say 3 is a menu
entry nobody opens" — and that argument covers every button here leading to a collection
with a ceiling. The footer line is gone.

**The header was four things in one label.** Hint, `NEW RELIC:`, the run haul and six
stats were concatenated with four-space gaps, so the first-run explanation arrived welded
to the gold count and wrapped to a second line. Transient news is now its own amber label,
hidden when there is nothing to say; the stat bar is what is always true.

**What did NOT change, and why.** `Save and quit to title` was a full-width bar across the
bottom — the loudest control on the hub was the one that leaves the game. It is now sized
to its own text and pushed to the far end of the second button row. It stays unbound to
Escape: `tests/playable_test.gd` lists this screen in `NO_EXIT` on purpose, because leaving
the world "must be deliberate", and quiet is not the same as easy to hit by accident.

33/34 suites green; `test_relic` fails identically on the unmodified tree (a draw relic,
unrelated).

### D97 — The one thing a resting card shows was the one thing the fan covered

`REVIEW.md`'s highest-priority defect, and the reason it survived so long is worth as
much as the fix.

**The defect.** A card at rest deliberately shows only its name, its cost and its
headline number; the rules text arrives on hover. That is a good trade and D50's
reasoning for it stands. But the hand is a fan — cards overlap by design, because nine
side by side would either run off the frame or shrink past reading — and the neighbour
to the right is drawn *on top*. So the visible strip of every card except the last is
`step` wide, while the name was being laid out across the full `inner.x`. A captured
five-card hand read:

```
Smith's Fu    Prepare    Bludgeo    Bite    Shiv
```

Three of five unidentifiable without hovering each one. The resting state's entire
purpose is scanning a hand at a glance, and it could not be done.

**Why nothing caught it.** `CardTextTest` already measured a great deal about this
hand: every card on screen, the fan tilted through at least three angles, the middle
riding higher than the ends, nothing overlapping the vitals or the End Turn button or
the power orb, no label under 14px hovered. Every one of those passed on a hand nobody
could read. The checks were about *the card*, and the defect is about **the pair** —
it only exists in the relationship between a card and the one drawn over it, and no
single-card assertion can see a relationship. That is the same shape as D84 (four
models passing an encounter-count assertion while one of them ran 7.2 fights against a
budget of 4): the quantity being checked was real, and was not the quantity that
mattered.

**The fix, and where it had to live.** `card_button()` cannot know the answer — it also
builds reward cards, shop rows and deck lists, none of which overlap, and the fan's
step changes every time the hand size changes. So the card exposes `fit_name`, and
`_place_hand()` calls it with the width the next card leaves uncovered (`step`, or the
full face for the last card, which is on top of everything). The resting title re-fits
into that; the open layout is untouched, because a hovered card is lifted clear of its
neighbours and genuinely does have the whole face.

The mutable width lives in a meta rather than a local because **a GDScript lambda
captures locals by value**, and `show_all` and `fit_name` both have to see the same
current number. The metas were already the convention here for exactly this reason.

**The assertion, and proving it was not vacuous.** `CardTextTest` now walks consecutive
pairs and fails if a resting card's name label runs past the left edge of the card in
front of it. It passed the moment it was written, which proves nothing — so the fix was
disabled and the test re-run. It reported four failures, by 28-31px each:

```
FAIL the name on defend runs to x 512, under the next card at x 481
FAIL the name on jab runs to x 623, under the next card at x 594
FAIL the name on twin_strike runs to x 735, under the next card at x 707
FAIL the name on twin_strike runs to x 847, under the next card at x 820
```

Re-enabled, green. **A new assertion that has never been seen to fail is a comment.**

**TRIED AND REVERTED: refusing to break inside a word.** Narrowing the strip made
`AUTOWRAP_WORD_SMART` reachable in a way it had not been at full card width — it splits
a word too long for the box rather than overflowing it, so "Footwork" rendered as
"Footwor" / "k". `fit_label` could not see this: both halves are perfectly visible
lines, so its height check was satisfied at the largest font. A `whole_words` option
was added that additionally required every single word to fit the width, measured with
`get_string_size` (safe on one word, where the existing docstring's warning about
`get_multiline_string_size` does not apply, because a single word has no line break to
disagree about).

It worked and it looked worse: forcing the longest word to fit drove the font down far
enough that the fix was more conspicuous than the defect. **Reverted on sight of the
render.** Two-word names wrap at the space and read fine; a long single word breaking
is accepted. `fit_label` is back to four parameters and `_words_fit` is gone. This is
D56's rule doing its job in the other direction — the capture is what approves a change,
not only what condemns one.

**Not addressed here.** The review's other two P0 items are untouched: there is still no
card art (`assets/art/cards/` does not exist, so every face wears a 16x16 CC0 tile
stretched ten times), and ~36 card names are still Slay the Spire's, fourteen of them
with the effect and the constant as well.

### D98 — Thirty-six card names that belonged to another game

`REVIEW.md`'s third P0 item, and the one that was pure data. Of 100 cards, **30 carried
Slay the Spire card names verbatim** — Adrenaline, Barricade, Bash, Battle Trance,
Bludgeon, Body Slam, Caltrops, Cleave, Dagger Throw, Defend, Demon Form, Entrench,
Finisher, Footwork, Heavy Blade, Impervious, Inflame, Iron Wave, Juggernaut, Perfected
Strike, Prepared, Pummel, Rupture, Searing Blow, Second Wind, Shiv, Shrug It Off,
Strike, Twin Strike, Whirlwind — with six more a letter away (Berserker Rage, Dodge
Roll, Cut and Run, Terrify, Blood Price, Slash).

**Why this was worth doing before anything cheaper.** Genre grammar is not the problem;
every deckbuilder since 2017 uses Block and Energy and intents, and this one should. The
problem is that the borrowing is concentrated in **the first twenty minutes**, which is
the window where a player decides what your game is. The pitch — "Slay-the-Spire-shaped
combat, but the meta layer is different" — is a much weaker claim than this project has
earned, and the opening hand was arguing for the weaker one.

**Where the replacements came from.** Not invented from nothing: the game already has a
voice, and it was confined to flavour text where it did no work. The events and the boss
roster read plain, concrete and Anglo-Saxon, with mortuary and debt imagery and a lot of
understatement — *"Cold stone and old debts"*, *"His pack is intact. He is not."*,
*"Nothing here was built for people"*, The Grave-Sexton, The False Step, The Last Vendor.
Every new name is drawn from that register, and several are direct echoes: `blood_price`
(pay 5 HP, deal 16) is now **Old Debt**, which is the Barrows' own description.

```
strike            -> Hack             barricade      -> Set Stone
defend            -> Cover            impervious     -> Shut Out
bash              -> Stave In         entrench       -> Double Down
slash             -> Gash             shrug_it_off   -> Take It
heavy_blade       -> Dead Weight      dodge_roll     -> Give Ground
cleave            -> Reap             juggernaut     -> Bristle
twin_strike       -> Two Quick        caltrops       -> Sharp Ground
whirlwind         -> Clear the Room   footwork       -> Light on It
bludgeon          -> All You Have     inflame        -> Work Up
finisher          -> Last Word        demon_form     -> Something Worse
pummel            -> Keep Hitting     berserker_rage -> Red Mind
searing_blow      -> Grinding Down    battle_trance  -> See It Coming
perfected_strike  -> Drilled          prepared       -> Read Ahead
iron_wave         -> Shoulder         adrenaline     -> Kick
body_slam         -> Ram              second_wind    -> Stitch
shiv              -> Nick             terrify        -> Put the Fear
dagger_throw      -> Thrown Iron      rupture        -> Split
blood_price       -> Old Debt         cut_and_run    -> In and Out
```

**IDs were not touched, and that is the whole reason this was safe.** A card's `id` is
the key it is stored under in `MetaState.collection`, in every saved deck and in every
dungeon's exclusive-card list; renaming one would silently orphan a player's collection.
Only the `name` field moved. Nothing in `scripts/` or `tests/` compares a card name to a
string literal — checked before starting, and it is why "Found only here: Read Ahead"
updated itself on the zone screen with no code change.

**Two powers went with them.** `powers/cleave` and `powers/second_wind` carried the same
two borrowed names, and renaming the cards while leaving the powers would have left the
vocabulary half-imported: **Scythe** and **Push On**. `CardData`'s schema default
`name = "Strike"` was updated to `"Hack"` in the same pass — never rendered, since every
`.tres` sets its own, but a default naming a card that no longer exists is a small lie
with a long life.

**NOT done, and it is the more serious half.** Fourteen of these copy the effect **and
the tuned constant**, not just the name: All You Have still deals 32 and exhausts, Shut
Out still gives exactly 30 Block, Reap 8 to all, Two Quick 5 twice, Take It 8 Block and
a card, Light on It 2 Dexterity, Work Up 2 Strength, Hack 6, Cover 5, plus Kick, Keep
Hitting, Ram, Double Down and Set Stone reading word-for-word. **The numbers are the
tell** — a constant arrived at independently does not land on 32. Changing them is a
balance change and needs `tools/sim_balance.gd`, which a concurrent session is currently
running calibration passes on, so it was deliberately left alone rather than half-done.
Renaming without re-tuning is the cosmetic half of this fix; the entry exists partly so
the other half is not mistaken for finished.

> **Correction (D110).** The paragraph above reads the authored `description`, not the
> data, and the two had already parted company: All You Have's `damage` was **28** when
> that was written, Shut Out's `block` **26**, Two Quick **6**, Take It **7**, Light on
> It and Work Up **3** each. The tuned constants were re-tuned; only the authored line
> still quoted the other game. So this was never the balance change it was filed as, and
> it needed no simulator run — seven descriptions were simply stale, which is invisible
> because `description` is not shown to players (D50 moved every surface onto the
> generated face) and not read by the engine. They now match, and `test_card_truth.gd`
> asserts that every number in an authored line is a number the card actually does, so
> the two halves cannot drift apart again. Hack 6 and Cover 5 are untouched: those are
> the starter kit and their numbers are the 1.0 baseline `Balance.power_ratio` is
> defined against.

34/34 suites green, and the combat, zone and shop screens re-rendered and read.

---

### D99 — A ladder built for four rungs on a staircase with two

`tools/sim_balance.gd` flagged one cell on the D94 run: at the Fungal Deep with the
poison build, slipping past *every* fight cleared more often than choosing when to. A
dominant strategy is a removed decision (D20), so the price was wrong. Chasing it found
something bigger than one cell.

**The measurement first.** The flag itself was mostly noise — 150 trials read 77% smart
against 86% avoid, and 600 trials read 84% against 85%. What was not noise was the shape
underneath it: **always-avoid cleared 85% while always-face cleared 71%.** Declining
every fight in the dungeon beat having them, and the price was supposed to make that
ruinous.

**The defect.** `avoid_cost` was `6 + depth` per rung with each dodge 50% dearer than the
last, tuned so that FOUR dodges came to ~70% of a health bar. Four is
`ENCOUNTER_COMBATS + ENCOUNTER_ELITES`, the *global default* encounter mix. Two later
changes moved the real number and neither came back here:

* **D84** made encounter mixes per-dungeon. Six of the twelve no longer ask for 3+1.
* **D88** put every dungeon on the crawl, which takes wanderers **out** of the combat
  budget — and a wanderer walks to you, so it can never be slipped past.

Counting what the crawl actually lays down:

    dungeon          offers   real bill    as tuned
    crypt              2      15 / 60 HP    25%   (target 70%)
    warrens            2      18 / 70 HP    26%
    fungal_deep        2      23 / 90 HP    26%
    rot_gardens        2      25 /100 HP    25%
    sunken_vault       2      25 /100 HP    25%
    drowned_market     2      28 /110 HP    25%
    abyssal_stair      2      30 /120 HP    25%
    ossuary/foundry/ember_road/slag_pits/the_maw   3    45-46%

**Dodging an entire dungeon cost a quarter of a health bar.** Not one dungeon in twelve
charged what the price was designed to charge.

**And the test agreed with it, because it made the same mistake.** `test_traversal.gd`
asserts the ladder totals at least half a bar — and computed its rung count from
`ENCOUNTER_COMBATS + ENCOUNTER_ELITES`, the same global constant the price was tuned
against. Two things deriving a number from one stale source agree with each other and
with nothing else. It had been green throughout. Worse, this block had *just* started
running: D94 removed a `Kind.DECK` filter that had been skipping it entirely since D88,
so its first act on being restored was to pass for a second wrong reason. **A test that
starts running after years of being skipped has never been checked against reality.**

**The fix is to size the ladder to the staircase.** `Balance.avoid_cost` now takes how
many dodges the dungeon offers and solves for the base that lands the *whole* ladder on
`AVOID_TOTAL_FRACTION` (0.70) of the depth-derived bar. A dungeon offering two charges
more per dodge than one offering four, which is the answer a fixed rung cannot give.
`TraversalIso` counts its own dodgeable fights at generation (`dodgeable`, serialized
with the rest of the floor) and hands the number over; nothing derives it twice.

`AVOID_STEP` goes 0.5 → **1.0**: the second slip costs twice the first, the third three
times it. The steeper climb is what keeps the first rung affordable while a *two*-rung
ladder still reaches 70% — at +50% a two-dodge dungeon had to charge 28% of the bar up
front, past the point where anyone would take the first one. Every dungeon now lands on
70% with a first dodge at 11-23%.

This is the lever D88 named and left: *"a steeper rise than `DECK_AVOID_STEP`'s +50%…
left failing and visible rather than quietly tuned."* It was the right lever. What D88
missed is that the rung count was wrong too, which is why a steeper rise alone would have
overshot the three-rung dungeons.

**Measured after (100-trial report, 150-trial calibration).** Not one cell reports
ALWAYS-AVOID beating SMART — the flag that started this is gone everywhere, not just at
the Fungal Deep, which now reads face 72 / smart 71 / **avoid 37**. Dodging is not
decoration either: choosing beats never-dodging by 13 points at the Ossuary, 13 at the
Foundry on an Early deck, 18 at the Drowned Market late, 20 at the Maw at endgame. The
matched-progression band still sits at 56-75% and the over-reach cells under 25%.

**The reprice exposed a real flaw in the driver, which is the honest order for that to
happen in.** SMART's "this fight might end the run, pay the known price instead" branch
never checked that the known price was the *cheaper* one. While the dodge was underpriced
every dodge was cheaper than every fight and the guard was free; at the new prices the
driver was paying 23 of its last 30 HP at the Sunken Vault to skip a fight averaging 20,
and SMART came in 14 points below never dodging at all. Fixed, and the Maw went 32 → 40,
the Sunken Vault 59 → 69. **A harness is only evidence if its driver is as competent as
the thing it judges (D26).**

**Four cells still report ALWAYS-FACE beating SMART, and they are printed rather than
tuned away.** Dodging forfeits the reward, and the reward joins the run deck — so at
depth, where the boss is decided by deck power, declining a fight can be right on HP and
wrong on the run. `cost_est` only knows HP, so the driver cannot see that trade. That is
the driver's ceiling, not the price's, and the calibration now says so on every run in its
own words. Raising `FACE_BIAS` until the line disappears would be fitting the policy to
the scoreboard.

**Also here.** `sim_balance.gd` grew `--only=`, `--profile=`, `--calibration-only` and
`--cal-trials=`. The calibration is 95% of a full run's wall clock, and a price is tuned
by changing a constant and measuring again; without narrowing, that loop is the whole
report, which in practice means the constant gets guessed. Guessing at this price is what
D57 was.

---

#### And then: why nineteen minutes at all

Narrowing the report made the loop bearable; it did not make the tool fast. Profiling it
put the answer somewhere unexpected — **the thing the simulator exists to measure was 4%
of its runtime.**

    avoid_calibration  1083.4 s   95%
    fight_play            49.4 s    4%
    fight_setup            5.8 s    1%

The calibration phase wraps the fights inside it, so a thousand of those 1083 seconds were
spent *not fighting*: generating floors and walking them. Four faults, none of them subtle
once looked at:

* **`Array.pop_front()` as a BFS queue.** It shifts every remaining element, so each flood
  over a 144-cell floor was quadratic. Three flood functions, all of them.
* **`_neighbours()` inside the flood's inner loop**, allocating a fresh `Array` for every
  cell visited — around 144 allocations per flood.
* **Two floods from the same tile per step.** `_reveal_around(pos)` and `_floor_turn()`
  both flood from the player, one after the other, in the same `select()`.
* **Two option lists per step.** The caller builds one to choose from and `select()`
  builds it again to resolve the index it was handed. Each build is another flood.

Fixed by, respectively: a read cursor instead of `pop_front`; the four neighbours stepped
inline; one flood computed in `select` and passed to both callers; and a memo on
`options()` dropped by every mutator. The four grids (`enc`, `seen`, `walked`, `room_of`)
became `PackedInt32Array`/`PackedByteArray` — `enc[n] == WALL` is the innermost line of
every flood, and JSON round-trips packed arrays unchanged, so the save format did not move.
`_reveal_around` also stopped scanning the whole grid for "which tiles share my room": a
floor's rooms do not move, so they are bucketed once per floor.

**Measured, same configuration, same cells, same numbers out:**

    before   avoid_calibration 1083.4 s   fight_play 49.4 s   TOTAL 1141.8 s
    after    avoid_calibration  361.7 s   fight_play 49.9 s   TOTAL  420.2 s

**2.7x overall, 3.0x on the calibration, with `fight_play` unmoved** — which is the proof
that the diagnosis was right rather than a coincidence, and also says where the next
bottleneck is: combat has gone from 4% to 12% of the run.

**Two things about measuring this were harder than doing it.** Wall-clock readings on this
machine drifted 40% between identical runs and sent the work the wrong way twice — one
change read as a 40% *regression* that was pure load. `tools/bench_iso.gd` therefore
reports the **minimum** of several interleaved batches, because load can only make a batch
slower, and the load-independent check is a count: floods per step went 4.09 → 3.09 and
option builds 2.00 → 1.00, exactly as intended.

**The one hot spot deliberately left alone** is entrance selection, which floods from
*every* candidate chamber tile — around forty per floor, the most expensive thing in
generation. The cheap answer is a double sweep, two floods instead of forty, and it picks
a **different tile**: it would move every entrance in the game, reshape every floor, and
invalidate every balance number measured against them. Regenerating the content to save
10% of a run is not an optimisation, it is a content change wearing one. What made it
affordable was making each of its forty floods cheap.

**The memo needed its own guard.** Nothing crashes when an invalidation is missed — the
player is handed a list of moves for a floor they have already left, which is the quietest
kind of wrong. `test_traversal.gd` now walks every dungeon comparing the cached list
against a freshly computed one at every step. Verified by deleting an `_invalidate()` and
watching it fail; the first version of that assertion also failed on all twelve dungeons
for a reason of its own, having used different `Dictionary.get` defaults on the two sides
so that every option without an `hp_cost` differed from itself.

34/34 suites green.

### D101 — The prompt sheet was describing the wiring, not the picture

**One string was doing two jobs and failing the second.** `_add()` took a single
`brief`, and it fed both documents: ART_ASSETS.md, where it answers *why is this file
wanted*, and ART_PROMPTS.md, where it has to answer *what do I draw*. Those are
different sentences, and the shopping list's version was winning. So the prompt for an
energy orb read "One unspent energy. Replaces the text 'Energy 3/3'", and the prompt for
a die read "A die showing 3. The two dice are currently the text 'dice: [3, 2]'" —
**quoting UI text at a style block whose FORBIDDEN line bans text**, and describing a
Label the generator cannot see. `_add()` now takes an optional `subject` that goes only
to the prompt sheet, falling back to the brief where the brief is already visual. Both
documents still come out of the same tables; they just stop sharing a sentence.

**Tier 3 was asking for a table of contents.** The twelve card families were emitted as
their own membership lists — `28 cards: Stave In, Bite, Old Debt, All You Have, ...` —
while the recipe two paragraphs above said *paint the EFFECT, not any one card's
fiction*. A list of card names is neither. `Icons.card_family` is a mechanical fact: it
knows a card applies poison, it cannot know what poison looks like. So `CARD_ART` is the
one piece of authored art direction in the file, twelve lines, and poison is now "a
green fume settling low across the frame, beading on cold stone."

**The guard matters more than the twelve lines.** A hand-kept table keyed by family id is
the stale-list habit this project keeps paying for (D34), so `_cards()` **discovers** the
families from the catalogue and refuses to emit at all when one has no line — exit 1, the
family named, nothing on stdout. The tempting fallback is the membership list, and that is
precisely the defect: a 13th family would otherwise ship 99 good prompts and one bad one,
which is the failure nobody re-reads. Verified by deleting the poison line: exit 1, no
half-written sheet. Same split applied to the 21 status symbols and the 7 encounter kinds,
where "Block." and "A choice with consequences" name a rule rather than a shape — a rule
prompts a diagram.

**Regenerating surfaced a staler thing than the prompts.** ART_ASSETS.md was last built at
8c55002 and `3c85d43` landed six painted enemies after it, so both documents still asked
for all **35 enemy files that were already committed** — 34 present became 69, and 175 to
provide became 140. The sheet that exists so a prompt cannot name an enemy the game no
longer has was itself asking for files the game already had. Not regenerating after
installing art is the habit to break.

**And it exposed what the presence check cannot see.** Those 35 files are 6 paintings and
29 procedural plates from `gen_enemy_art.gd` — bimodal on disk, 129-577KB against
9-16KB — and `ResourceLoader.exists()` cannot tell them apart. So the regenerated Tier 2
now reads "Nothing to generate here — all 35 present", and the 29 placeholders will never
be prompted for again. The stale sheet was accidentally more useful than the current one
on exactly this point. **A file existing is not the same as the art being done**, and the
manifest has no way to say so today; a `Kind`-style marker for "present but provisional"
is the shape of the fix, and it is not written yet. Left flagged rather than papered over
with a file-size threshold, which would be a guess wearing a check's clothes.

116 files can now be generated, down from 151, and every one of them names an object.
34/34 suites green.

### D102 — The prompt sheet was still pasting the operator's half of the page

**The free-tier survey came back with one name, and it was the one already wired.** The
question was which free image endpoints could replace Pollinations. Cloudflare Workers AI
has the most generous free tier by a distance — 10,000 neurons a day, no card, and FLUX.1
Schnell at 4.8 neurons per 512x512 tile, so thousands of images — but its whole image
catalogue is text-to-image, and a text-only endpoint cannot take `bg_crypt.png` (D100).
Together's free `FLUX.1-schnell-Free` was deprecated 2025-12-23. Gemini's image models
have no free API tier at all. Hugging Face's included credit is sized to prove an
integration works, not to paint 116 files. **The constraint that decides this is
reference-image support, not price**, and it disqualifies almost everything a search for
"free image API" returns. So Pollinations stays, and the fallback for when it rate-limits
is not another endpoint — it is a person, in a browser, with the reference image attached
by hand.

**That fallback needed the prompts, and asking for them found the bug.** `--browser`
composes the same prompts from the same parse and prints them for copy-paste, adding only
the three things an HTTP body carries that a chat box cannot: the reference image, the
size (as words — a chat UI has no `size` parameter), and the filename the installers
expect. 63 pastes cover all 116 files, because the four sheet tiers are one paste each.
Both routes now build their jobs through one `build_jobs()`, since a browser prompt that
differs from the posted one is the second dialect rule 1 exists to prevent.

**A tier's prose was going to the generator whole, and only some of it was art
direction.** `compose()` pasted the whole per-tier preamble, but that paragraph is written
for someone *reading ART_PROMPTS.md*. So every tier 0 request opened with **"DO NOT
GENERATE the nine-slices and tileable strips in this tier … They come out of
`tools/gen_ui_kit.gd`"** — an instruction not to generate, sent to a generator, citing a
Godot script and D83 at it. Tier 4 was worse: each single-sheet request carried "**This
tier is THREE sheets, not one**", contradicting the ask in the same prompt. Tier 1d
explained that the installer takes alpha from luminance; tier 7 explained the font
licensing. This is D101's defect one level up — that fix split the per-file *brief* from
the *subject*, and left the per-tier paragraph doing both jobs.

**Filtered per sentence, because the two kinds share a paragraph.** A tier-level keep/drop
flag would lose "OVERRIDE THE PALETTE LINE … these are SINGLE-COLOUR", which sits two
sentences from the luminance explanation and is the most load-bearing line in tier 1d.
`art_direction()` drops sentences carrying markers that never appear in real art
direction: a backtick, a `(D##)` reference, `.gd`, a cross-tier "Tier N", "below",
"computed", "installer", "generator", "licensed", "request". Tiers 0 and 7 correctly
reduce to nothing — their subjects were always self-contained — and the seven others keep
only shape, framing and lighting. The fix lands on the API route too; it was never a
browser-only problem.

**Tier 4's installer was invisible to the parser.** The Install: line is found by looking
for a line with both `install_` and `godot` in it, and tier 4 names
`install_sheet.gd -- nodes|tiles|dice` mid-paragraph without the word `godot`, so the one
tier that installs as three separate sheets was the one tier that printed no command.
`install_hints()` derives it instead: for a group tier each group label *is* the set name,
and for the rest the target directory is matched against `install_cutouts.gd`'s FAMILIES.
The loose `ui/` cutouts in tiers 0, 1b and 7 have no installer, and the sheet says that
plainly rather than inventing one.

### D103 — The fourteen constants, and three of them measured worse before one measured right

D98 renamed the borrowed cards and said plainly that the rename was the cosmetic half:
fourteen of them still carried Slay the Spire's **effect and its tuned constant**, and
the constant is the real fingerprint — a number arrived at independently does not land
on 32. This is the other half, done the way tuning is supposed to be done here.

**Eleven changed, three deliberately not.** Ram (damage = your Block), Double Down
(double your Block) and Set Stone (Block stops expiring) share only a *cost* with their
originals, and 1/2/3 energy are the costs any designer lands on for those effects. Once
the name differs there is no identity left to buy, and changing a cost is pure balance
risk. They keep what they have.

**Method: baseline first.** A before-reading was taken at 120 trials *before touching a
value*, because an after-reading on its own says nothing. Four rounds followed, each one
read against that baseline.

**Round 1 — eleven values changed. Two cells collapsed.**

```
Status build    @ Foundry     57% -> 19%     Barricade build @ Sunken Vault  36% -> 14%
Status build    @ Ember Road  56% -> 27%     Maxed commons   @ Sunken Vault  64% -> 43%
```

Both failures were the same mistake from opposite directions, and both are the D28
signal — *a deck performing unlike its own ratio*:

* **Cost is mispriced against a three-energy turn.** `footwork` and `inflame` went
  1 -> 2 energy. `power_value()` divides by cost, so the ratio duly fell (Status 3.15 ->
  2.99) and enemies scaled *down* — yet the build lost two thirds of its clear rate. A
  2-cost buff in a 3-energy game does not cost 2/1 of a 1-cost buff, it costs the turn.
  Status runs `inflame x2 + footwork x1`, Barricade runs `footwork x2`; the two profiles
  that collapsed are exactly the two that hold those cards.
* **A base bump is over-credited at high card level.** `strike` 6 -> 7 and `defend`
  5 -> 6 pushed Maxed commons (`strike x8 + defend x8` at Lv100) from ratio 4.09 to 4.77,
  +17%, so enemies scaled 17% — but level scaling is **sqrt**, so +1 on the base delivers
  far less than 17% at Lv100. Priced power outran delivered power and the cell fell 21
  points.

**Round 2 — corrected the costs, overcorrected the basics.** Costs back to 1 (Status
Foundry 19% -> 57%, exactly baseline; Barricade Vault 14% -> 37%: diagnosis confirmed).
But `strike` 5 / `defend` 4, chosen to push the ratio the other way, put **Starter at the
Ossuary on 11%** — a fresh save could not clear the second dungeon. The starter deck is
`strike x4 + defend x4` and nothing else, and at d1-d2 the **ratio floor** means the
dungeon does not scale down to meet you (D36, working as designed). Maxed commons went
the other way to 90%.

**Round 3 — the basics are a local optimum.** 7/6 over-scaled, 5/4 gutted the opening,
6/5 sat in band. Both directions measured worse, so `strike` and `defend` were **reverted
to 6 and 5 and left there**. That is a fingerprint knowingly kept: the de-identifying
value of a basic attack's constant is the lowest in the set — the card is called Hack now,
and "1 energy, 6 damage" is the most generic line in the genre — while its balance
leverage is the highest, because every deck is mostly these two cards.

**Round 4 — break the constant upward, not downward.** Round 3 still left one real
regression: AoE at the Rot Gardens, 62% -> 42%. That build runs `cleave x3` *and*
`shrug_it_off x3` and both had been cut, so six of its fifteen cards were nerfed at once.
`cleave` 8 -> **9** instead of 7 removes the fingerprint just as well and gives the
archetype its power back. **Nothing says a de-fingerprinting change has to be a nerf.**

**Result, against the baseline, 120 trials both sides:**

```
                    round 3          round 4 (kept)
mean delta          +0.6             +0.7
max |delta|         20               12
cells >= 15 points  3                0
```

Thirty-four cells, none moved more than 12 points, mean drift under one point. That is
the target: the fingerprints are gone and **the difficulty curve is where it was**.

Confirmed at **400 trials**, and this is the table of record:

```
Starter   Crypt 100  Ossuary  67  Warrens 100      AoE       Rot    64  Market 36
Early     Crypt 100  Warrens 100  Foundry  24      Thorns    Slag   99  Stair  15  Maw 29
Mid       Warrens 100 Foundry  96  Ember   100      Maxed     Foundry 100 Vault 71
Status    Warrens 100 Foundry  66  Ember    62      Relic     Warrens 100 Foundry 100 Vault 84
Barricade Warrens  99 Foundry  18  Vault    30      Late      Market 82  Stair  20  Maw 12
Poison    Fungal   69 Rot      67                   Endgame   Stair  62  Maw    67
                                                    Deep      Foundry 100 Vault 64
```

**Final values.** cleave 8->9 · twin_strike 5->6 · pummel 2x4->3x3 · bludgeon 32->28 ·
shrug_it_off 8->7 · impervious 30->26 · footwork 2->3 dex · inflame 2->3 str ·
adrenaline draw 2->1. `strike` and `defend` unchanged at 6 and 5, on purpose, above.

**A correction to REVIEW.md, which this run disproves.** The review's appendix reported
the simulator as effectively unrunnable — two attempts abandoned — and filed "re-time
`sim_balance`" as a finding, on the strength of `8514f38`'s profile putting a full
400-trial report at ~53 seconds of measured work. **It runs.** A 120-trial report takes
**7m40s-8m25s** here and the full 400-trial report finishes in about nine minutes. The
original abandonments were a concurrent session competing for all sixteen cores, and,
twice, my own `timeout` being shorter than the report plus a pipe into `grep -c` that
threw the partial output away on kill. The ~53s figure is still unexplained and the tool
is still slower than it should be — but "slow" and "cannot be run" are different
findings, and the review made the wrong one. **A tool that looks broken under contention
should be re-measured on a quiet machine before it is written up.**

### D104 — The card was one part pretending to be two

**The picture and the words were fighting over the same rectangle.** A card was
150x132 with the illustration full-bleed behind the text at 55% alpha and a scrim over
the lower half to keep the words legible. That is not an illustration, it is a wash: the
brief for Tier 3 even had to ask for a *quiet dark bottom third*, which is a painting
being told to get out of the way of something. And because the face had one region, the
name and the rules text could not both be in it — so the rules text was hidden until you
hovered, and a resting card showed a name, a cost and a headline number. The request was
for the Slay the Spire / Hearthstone shape, picture on top and text below, and the
interesting part is what it costs: **a two-part card is taller, and a taller card does
not fit above the bottom of the screen.**

**So it does not fit, on purpose.** `HAND_PEEK = 0.74` — a card in hand shows 74% of
itself and the rest hangs off the bottom edge. That is the trade that buys the height:
150x132 became 150x214 with the width untouched, because every number in the fan is a
width (step, overlap, the reserves either side) and leaving those alone meant the hand
still lays out the same. The picture band is 47% of the card, the name strip 13%, and the
rules text takes what is left — 69px against the ~40px the old face could spare, which is
what makes the text permanent rather than a hover disclosure.

**What hangs off has to be the part you do not need.** A hand is scanned for cost, name,
picture and the headline number, so all four are in the top half by construction: the cost
badge sits over the picture's top-left, and the damage and Block numerals moved from the
card's bottom corners — where they had been perfectly readable and would now be under the
screen edge — to the picture's bottom corners. Each sits on a dark plate, because a
numeral over a painting is at the mercy of whatever the painting put in that corner.

**Hovering brings the whole card back, and the lift is computed, not chosen.** The old
lift was `height * 0.34`, a constant that happened to look right. It cannot be a constant
now: the card hangs off the bottom by design, the fan's outer cards hang lower than its
middle ones, and hover scales about the bottom-centre pivot so the bottom edge does not
move and all the growth goes upward. Each card solves for the lift that puts its own
bottom edge 10px inside the frame. Measured at 1280x720: the outermost card rests at
y 568-782 and opens at 400-710.

**A taller card is a WIDER card when it is tilted.** The outermost cards turn 0.075 rad
about their bottom centre, so the top corner swings out by `height * sin(tilt)` — 10px at
132 tall, 16px at 214. The fan's left reserve was measured off the vitals box and was
correct for the old card; the new one put its corner 1.8px inside the vitals, which
`CardTextTest` caught and no amount of looking at the render would have. Both reserves now
carry the swing.

**The test had to be re-aimed, not relaxed.** Two of its assertions were the old design
stated as rules: *a resting card must not show its rules text* (now exactly backwards),
and *every card is inside the frame* (now false by design, and deleting it would have left
the peek free to take any value at all). They became: the rules text is on the card in
both states, and **the identifying part of the card — picture band plus name strip — is
above the screen edge**, computed from the same constants the layout uses. Plus a new one
the old suite had no reason to want: hovering any card in hand must put the whole of it,
at the hovered scale, inside the frame. That one is checked on every card rather than a
sample, because the card most at risk is the outermost and a sample would take the middle.

**Reading a card and hovering a card are different needs.** Hover ends the moment you look
away, so you cannot hold a card open and read an enemy's intent, and comparing two cards
means holding one in your head. `UI.inspect_card` holds one card up at 360px over a dimmed
screen, with the per-rule prose beside it. Right-click opens it on any card face anywhere —
hand, reward, shop. The collection, the deck builder and the fuse prices are LISTS, though,
and a list row has no card to right-click: their row thumbnails became buttons that open
the same overlay, in the same 28px the plain `TextureRect` occupied, so no row got wider.
The fuse rows pass what the next level buys, which is the one screen where the card being
priced was never shown.

**Tier 3's brief changed with the shape.** The prompt sheet still asked for a quiet dark
bottom third — a rule that existed because text was written over the picture, and nothing
is written over it now. It asks for an edge-to-edge picture and names the four corners
that carry a numeral. Regenerating also surfaced two files the last change left stale:
`powers/cleave.png` and `powers/second_wind.png` were still being asked for after the
powers were renamed to Scythe and Push On (D98), so 116 generatable files were really 114.

**And the render vetoed two things the measurements liked.** Both assertions passed and
both looked wrong. The fallback card art is a 16x16 atlas slice, and giving it the whole
picture band meant `KEEP_ASPECT_CENTERED` scaled sixteen pixels to 101 — a 6x blow-up, in
a branch whose own comment said not to do that. It is an emblem at 62% of the band now,
NEAREST-filtered, so it reads as pixel art rather than as a smear. And the collection's new
thumbnail shipped as `flat = true`, which is the plain `TextureRect` it replaced wearing a
click handler: the only clue it could be pressed was the tooltip, which you have to hover
to find. It has a thin rarity-coloured edge that brightens under the cursor — not
`UITheme.style_button`, which forces a minimum height and would have made every row in a
thirty-row list taller. D56 again: measure, then look, then decide.

### D105 — Three of the five were painted into a wall, and the prompt is why

**The control chrome arrived, and the matte refused most of it.** Five Tier 0 files came
back from the browser sheet — `dropdown_arrow`, `slider_grabber`, `scrollbar_grabber`,
`checkbox_on`, `checkbox_off`. `ui_theme.gd` has been reaching for all five by name since
the kit was specced, each one silently switching on the moment its file exists, so
installing them was supposed to be a matte and a copy. It was not. `slider_grabber` was a
bar of iron mounted on a lit stone wall with mortar lines running behind it: 14% of its
border agrees with itself, against the 80% `cutout_lib.gd` requires, and the matte refused
it rather than cutting a hole in the wall — which is the refusal working, not failing.

**`dropdown_arrow` is the one worth writing down, because it looks cuttable and is not.**
Its field averages `(0.104, 0.102, 0.159)` and its worst border pixel sits 0.143 away from
that, so the border check passes. But the chevron is painted half in shadow, and its
darkest arm sits **0.049** from the same field — the subject is closer to the background
than parts of the background are to each other. There is no tolerance that separates them,
and the flood fill walks straight through the arms; the first install dropped 761 islands
and produced a chevron with its top bitten off. Luminance cannot rescue it either, and for
a reason that generalises: the style block mandates *a dark ink outline on every form*, and
here the outline is DARKER than the field, so any brightness matte cuts the outline off the
shape it belongs to. Both files install **opaque**, cropped to the object's own edge. The
arrow gets away with it because the field it keeps is `#1a1a29`, near enough to the
chrome's own dark to vanish against it.

**The prompt was the defect, not the matte.** `gen_pollinations.py` filters each tier's
prose per sentence, dropping the operator-facing half so a generator is not told which
files not to generate (D102). Tier 0's prose was *entirely* operator-facing — nine-slices,
`gen_ui_kit.gd`, a D-number, the word "below" — so every sentence was filtered and the five
subjects went out with **no art direction at all**. Tier 1b's survives ("one object,
centred, transparent, no ground shadow") and Tier 6b's says "on a flat even field for the
matte" in the subject line itself; Tier 0 alone said nothing, and got back what nothing
asks for. It now carries a sentence written to survive the filter, naming `card_back` as
the one Tier 0 file that fills its frame instead of standing on a field — the tier is mixed
and a blanket rule would have mis-aimed the tablet.

**`install_chrome.gd`, because there is no catalogue to resolve against.**
`install_cutouts.gd` maps a source filename to an archetype, a relic or a card id, and
chrome has no such list — the catalogue is the set of names `ui_theme.gd` hardcodes. So the
recipe table in the new tool IS that catalogue, and it carries the three columns chrome
needs and cutouts do not: a crop rectangle (a socket is painted in a wall because that is
where sockets live), a matte flag, and a stretch flag. The stretch flag exists for exactly
one file: `scrollbar_grabber` is nine-sliced 8/8/8/8 by the theme, so it has to reach all
four canvas edges or the slice margins bite into transparent gutter and the thumb renders
narrower than its own bar. `Cut.place()` preserves aspect on purpose — a stretched monster
is a deformed monster — so filling had to be written beside it rather than into it.

**What is left.** Both checkboxes and the scrollbar thumb are good. The two opaque files
are honest placeholders: a re-roll under the fixed prompt comes back cuttable, at which
point they move to `"matte": true` and nothing else changes. Worth noting for whoever does
it — the generated `checkbox_on` is DARKER than `checkbox_off`, because the peg sits over
the socket's glow. The peg reads unmistakably, so the pair is legible, but a checked box
that dims when you check it is backwards and the re-roll should say so.

### D106 — The ids were still the other game's words, and the saves paid for fixing it

D98 renamed the cards and D103 re-tuned their constants, but both stopped at the
`name` field. The **ids and filenames were untouched on purpose** — an id is the key a
card is stored under in `MetaState.collection`, in every saved deck and in each
dungeon's `card_pool`, so renaming one orphans a real save. The result was a game that
was clean and a repo that was not: 36 files still called `bludgeon.tres`,
`perfected_strike.tres`, `shrug_it_off.tres`.

**Why that was worth spending a save wipe on.** Nothing in the UI renders a raw id, and
the generated art briefs come from `name`, so no player would ever have seen one. But
the tree is the artifact a collaborator reads, and — the concrete reason — the art
manifest specifies card illustrations as `cards/<card_id>.png`, so leaving the ids
alone would have baked the borrowed vocabulary into the asset filenames the moment the
art lands. A rename after that is a rename of art files too.

**No migration. The saves were deleted instead.** `SAVE_VERSION` has a working
`_migrate()` and a 36-entry remap would have been perhaps fifteen lines, but this is a
prototype with no players, and an explicit wipe is honest where a migration is a
permanent piece of code carried for the benefit of nobody. `save.json`, `save.run.json`,
`save_1.json` and seven `.bak` files were removed; `settings.json` was kept, because
settings are not saves. **Left alone deliberately:** a `t_headless_save_0.json` sandbox
belonging to a concurrently running suite — deleting another session's live sandbox is
exactly the failure the new `run.sh` header warns about.

**The rename itself.** 36 cards and 2 powers, 87 files rewritten, 38 `git mv`s. Matching
was on **quoted tokens** (`"strike"`) and resource paths (`cards/strike.tres`), never
bare substrings: a naive pass would have rewritten `perfected_strike` and `twin_strike`
while replacing `strike`. Longest ids were substituted first for the same reason. A
collision check ran first (36 new ids against the 64 untouched ones — none clashed), and
afterwards every `id` field was re-verified against its filename, which is what
`test_content` asserts anyway.

`hack cover stave_in gash dead_weight reap two_quick clear_the_room all_you_have
last_word keep_hitting grinding_down drilled shoulder ram nick thrown_iron old_debt
split in_and_out set_stone shut_out double_down take_it give_ground bristle
sharp_ground light_on_it work_up something_worse red_mind see_it_coming read_ahead
kick stitch put_the_fear` — plus powers `scythe` and `push_on`.

**A reporting failure worth recording, because it is the reason this happened at all.**
The D103 summary listed the changed values as "cleave 8→9, twin_strike 5→6" and so on.
Those are **ids**, which is what the edit script keyed on — the displayed names are
Reap and Two Quick. It read as though the rename had not happened, and the question
"why are you still saying cleave?" is what surfaced the id problem. **When two names
exist for one object, a summary that quotes the internal one is worse than useless: it
is evidence of a bug that isn't there, and it hides one that is.**

### D103 — CORRECTION: its absolute table is superseded

D103's 400-trial "table of record" was measured at roughly 11:30. A concurrent session
then rewrote the card level curve — `card_data.gd` at 12:22 (257 lines) and `balance.gd`
at 12:33, taking `HP_POWER_K` 0.5 → 0.217, `DMG_POWER_K` 0.15 → 0.065 and
`HP_POWER_K_HIGH` 0.5 → 0.38. **Those numbers no longer describe this game and must not
be quoted.**

What survives is the part that matters: D103's conclusion was a *comparison*, and both
sides of it — the pre-change baseline and the four iteration rounds — were measured
under the same constants within a single afternoon. "The de-fingerprinting moved no cell
more than 12 points" is still true of the change it describes. The absolute clear rates
are not. They need re-measuring once the level curve settles, and until then
`tests/test_balance.gd` and `tests/test_upgrade.gd` are red on that work, not on this.

### D107 — A theme icon is not authored at 2x, and a checked box has a fourth state

**The grey box around the art is the crop, and it is only on the two that could not be
cut.** D105 installed `dropdown_arrow` and `slider_grabber` opaque because no matte can
separate them from the wall they were painted on. In a still that looked acceptable; in
the game it does not. The slider grabber carries a pale violet-grey strip along its left,
top and right — the wall the rectangle kept, sitting on a dark track — and it reads as a
sprite someone forgot to cut out, which is exactly what it is. The two checkboxes are
fine: a checkbox IS a tile, so the tile's own edge is a border rather than a leftover.
The fix is not in the installer; it is the re-roll the D105 prompt change makes possible.

**Screens are photographed under a plain `Node`, and that hid all of it.** The first look
at this used `tools/screenshots.gd`, which showed every widget wearing Godot's DEFAULT
chrome — no painted arrow, no painted thumb — and the obvious conclusion was that the
theme had not applied. It had. `Screenshots.tscn`'s root is a plain `Node`, and a theme
owner does not propagate to Controls through one, so every captured screen loses the root
Window's theme. The buttons in those captures look painted only because `style_button()`
sets per-node overrides, which owe nothing to propagation. Anything themed by TYPE —
checkboxes, sliders, scrollbars, the dropdown arrow — has never appeared in a single
screenshot this harness has taken. Worth fixing before the next art review reads one.

**A nine-slice is authored at 2x for free. An icon is not.** ART_ASSETS says to author UI
at 2x and let the canvas stretch scale it, and for a nine-slice that is true — the slice
margins are in texture pixels and the frame scales around them. Godot blits a theme ICON
at its own pixel size, so `checkbox_on` at the specced 64x64 drew a 64px block in a row
built for a 16px font, taking the row from 31px to 80px. `icon_max_width` caps it at 26,
on `"CheckBox"` and deliberately not on `"Button"`: a constant resolves off the control's
own type first, so the cap reaches every checkbox state without shrinking the relic, power
and card-thumbnail icons, which are meant to be bigger than a tick.

**The label was hidden by the state nobody sets.** A checkbox is a TOGGLE, so a checked
one draws `pressed`, and hovering a checked one asks for **`hover_pressed`** — which was
set on neither `"Button"` nor `"CheckBox"`. It fell through to the engine default, an
empty box with no content margin. So hovering a ticked row did not light it, it deleted
the frame, and the 22px of `KIT_PAD_X` that frame was carrying went with it: the label
slid left, under an icon that had not moved, and the F of "Fullscreen" was painted over by
an opaque stone corner. The theme now fills the whole state family from one source —
`hover_pressed` from `hover` — on `"CheckBox"` and on `"Button"`, because every toggle in
the game had the same hole and only the checkbox had an icon big enough to show it.

**Two of the three only looked wrong once they were on a real screen.** The 8x contact
sheet in D105 showed the checkbox tile and called it good, and it is; what it could not
show is a 64px tile in a 31px row, or a state that only exists under the mouse. A capture
of the asset is not a capture of the widget.

### D108 — The card brief described a card that had already changed twice

**Asked whether the Tier 3 prompts were right, and they were not.** D104 rewrote the card
into two parts and rewrote this brief with it, but the brief was written from the intent
rather than from the code, and four claims in it are false against what `ui.gd` actually
draws. Measured off the shipped constants, the picture band is `inner.x` x `art_h` =
134x101 at the 150x214 card, and four things are drawn over it:

| what | corner | size, as a fraction of the band |
|---|---|---|
| cost numeral | top left | 26% x 20%, on a 72%-opaque plate |
| effect symbol | top right | 26% x 20% |
| damage numeral | bottom left | 42% x 20%, on a plate |
| Block numeral | bottom right | 42% x 20%, on a plate |

Against that, the brief said *"nothing is written over it"*; said *"two corners carry a
small number each"* and then listed three positions and then called them *"those four
spots"*; never mentioned the **top-right effect symbol** at all; and called the bottom
pair *small* when each is nearly half the band's width. It also said *"keep detail away
from the outer eighth, which the band crops"*. The band is 1.327:1 and the source is
1.333:1, so `STRETCH_KEEP_ASPECT_COVERED` crops **0.5%** — the brief was throwing away a
quarter of every illustration to avoid a crop of a quarter of a percent.

**The scrim was the omission that mattered most.** `CARD_SCRIM_START` is 0.58 and it
deepens to 62% black by 0.92 of the band, so the bottom two fifths of every card picture
is progressively darkened and the bottom eighth is nearly gone. Twelve paintings composed
with their subject low — which is the natural reading of "one clear shape, centred" in a
4:3 frame — would each have lost their subject to a shadow the brief never mentioned. The
brief now names the shadow and says to weight the subject into the upper middle.

**Same failure as D105, one tier over, and the same lesson.** A prompt is part of the
pipeline, not documentation of it: it goes stale exactly like a duplicated lookup table
(D34), and it fails silently and expensively, because what comes back is a good painting
of the wrong thing. The numbers in this brief are now the numbers in `UITheme` and
`UI.CARD_SCRIM_*`; nothing here should be restated from memory again.

**Not changed: the tier still produces a PICTURE, not a card.** The frame, the name strip,
the rules text and all four numerals are drawn by the game over a 4:3 image. That was
right and stays right — a generator asked for a whole card would return one with baked
text, which the style block already forbids in every image for this reason.

### D109 — Seventy-seven per cent of every level-up bought nothing, and the fix moved the whole difficulty axis

The report was one card: *the first power still gives 8 Block going from level 2 to 3.*
Bulwark's ten levels read **6, 8, 8, 9, 9, 9, 10, 10, 10, 11**. Five of its nine
level-ups changed no number at all.

**It was not one card.** Swept across the whole game before touching anything:

| | dead level-ups | of | |
|---|---|---|---|
| commons | 2,715 | 3,168 | **86%** |
| uncommons | 712 | 1,092 | 65% |
| rares | 112 | 308 | 36% |
| epics | 12 | 48 | 25% |
| legendaries | 8 | 24 | 33% |
| **cards, total** | **3,559** | **4,640** | **77%** |
| powers | 44 | 63 | 70% |

Eight cards changed nothing at **any** level — Focus, Read Ahead, See It Coming, Kick,
Abyssal Gift, Ram, Double Down, Set Stone — and two powers joined them: Foresight read
"Draw 1" at all ten levels, Push On "+1 Energy, costs 5 HP" at all ten. Fusion charged
copies **and** gold for every one of those.

**The cause was one line meeting integer arithmetic.** Growth was
`base + round(base * rate * sqrt(level - 1))`: a shape chosen for feel, then rounded to
an int. Any step smaller than half a point vanishes. A common card's entire track was
**+15 damage spread over 99 levels**, so 84 of them landed on the number below. Statuses
were worse — a common gained **+5 across a hundred levels**, so `_status_growth` returned
`base + 1` for levels 2 through 9 inclusive.

**Why no test caught it.** Every suite checked the *endpoints*: a maxed card is stronger
than a level-1 card (true), a maxed card is not absurdly stronger (true). Nothing ever
asked about a step in the middle. `tests/test_levels.gd` now walks all 3,859 of them.

#### The constraint is arithmetic, so one of two things had to give

A track can never be longer than the number of integer steps it has to give. Commons
have 99 steps and a +15 budget. Either the track shortens to fit the budget, or the
budget grows to fit the track. Asked, and the answer was **grow the numbers**: keep the
100/40/15/5/5 caps, put a floor of **+1 per level** under every track, and pay for it
downstream. A maxed common Hack goes from 21 damage to **107**.

`CardData._spread` makes that structural rather than tuned: the step is `1 + (a
front-loaded share of the surplus)`, and *two reals a whole point apart cannot round to
the same integer*. It is a guarantee, not a calibration.

**Three things the +1 floor cannot apply to, and what they got instead.**

* **Statuses.** A stack multiplies every later action; 100 Vulnerable is not a strong
  card, it is a fight that ends before it starts. They keep a budget for the whole
  track (4→8 by rarity), and a card whose *only* axis is a status gets a track short
  enough to spend it — Expose sells five levels, not ten.
* **Draw.** The most valuable single point in the game. Budgets of 1–3, so Focus sells
  one level and Foresight one. Short and honest beats a hundred levels of "Draw 1".
* **Cards with no number at all.** Set Stone is `retain_block` and nothing else. Energy
  cost became the last-resort axis: a card comes down to 1, a card already at 1 can
  reach 0. It is opened **only** for cards with nothing else to grow, because a card
  that got both cheaper and bigger every level would double-dip on `power_ratio`, which
  is power *per energy*.

`PowerData` now derives its cap from the same rule instead of the hand-authored 10, and
overrides `level_cap()` rather than only `level_capped()` — the getters spread their
budget across `level_cap()` steps, so a power that stops at 10 has to say 10 *there*, or
it arrives at its last level having collected a tenth of its growth.

#### And then the part that took the rest of the afternoon

A maxed common went 21 → 107 damage, so the strongest reachable deck went **ratio 6.1 →
31.7**. Every constant in the ratchet is a slope against ratio or a point on it.

**First attempt: map the axis through one factor.** Elegant, and it passed every
predicate in `tests/test_balance.gd`. Measured against a HEAD baseline at 120 trials it
had turned the game into a walkover:

| profile / dungeon | baseline | after |
|---|---|---|
| Barricade / The Foundry | 24% | **100%** |
| Thorns / The Abyssal Stair | 6% | **97%** |
| AoE / The Drowned Market | 42% | **97%** |
| Poison / The Rot Gardens | 60% | **100%** |

**The lesson, and it is the same one as D45.** That suite guards the *shape* of the
curve, and the shape was intact — what moved was its height, which only the simulator
sees. **A constant whose comment says "measured" has to be measured by the thing that
measures play.** The green suite is what let a 70-point swing through.

The specific mechanism was `soften_ratio`. It is a sqrt, so the wider the raw range the
more it eats: at the old range it turned 7.1 into 6.1, but at the new one it turned 31.7
into 13.8 — enemies were being scaled for **less than half the deck they were facing**.
`POWER_RATIO_CAP` moved above the reachable maximum, making the knee a backstop rather
than a working part.

**Second attempt: anchor on measured cells.** Enemy HP fitted to hold fight *length* at
the Mid and Thorns anchors (`HP_POWER_K` 0.5 → 0.68, `HP_POWER_K_HIGH` 0.5 → 0.52),
enemy damage and pierce fitted as far as the maxed-deck guard permits (`DMG_POWER_K`
0.15 → 0.060, `PIERCE_PER_RATIO` 0.5 → 0.020), ceilings re-pitched to clear 31.7
(`RATIO_CEILING_PER_DEPTH` 0.90 → 4.55). Fight lengths now land within ~0.5 turns of
baseline on every profile and the early game is unchanged within noise.

#### What is still open, because it should not be buried

**Fused archetype decks remain easier than baseline by a mean of 14 points**, worst at
Barricade (+67 at the Foundry, +49 at the Sunken Vault). The mechanism is not in
`balance.gd` at all: a Lv15 Cover now grants **20 Block where it used to grant 10**, so a
block deck's defensive pool doubled, while enemy damage growth is bounded *above* by the
D36 guard that a maxed deck must not be punished for its own power.

Both obvious levers were tried and measured worse:

* `DMG_POWER_K` at 0.09 and beyond fails the maxed-deck guard outright (a maxed deck
  loses 40.7 HP a fight at depth 6 against a starter's 34.0).
* `ESCALATION_PER_TURN` 0.06 → 0.10 was aimed at block decks, on the theory that
  escalation punishes long fights. It moved the fused profiles by 1.5 points and took
  the **unfused** Early deck at the Foundry from 32% to 8% — it punishes a slow deck,
  and a weak deck is slow for a different reason than a defensive one.

So it is not a ratchet problem and one more pass over these numbers will not fix it. It
belongs in `CardData.power_value`'s Block pricing (0.65 per point, set when a Lv15 block
card granted half what it now grants) or in the archetype cards themselves.

**One bug found on the way in, unrelated but in the way.** `Balance.POWERS` listed
`"reap"` and `"stitch"` while the files were `scythe.tres` and `push_on.tres` — the D106
rename moved the *cards* `cleave → reap` and `second_wind → stitch` and dragged the power
ids along with them. Two of the ten powers had been failing to load and `Balance.power()`
was handing back `null`. `tests/test_levels.gd` checks the list against disk now.

### D109 — The monsters were not floating; they were standing on a gold lozenge

**Reported as a backdrop problem, and the backdrops were mostly innocent.** The ask was
to re-roll every battle backdrop because enemies did not look planted. `tests/test_art.gd`
appeared to agree — it measures each backdrop's wall/floor junction and printed six of
twelve as 14 to 21 points off the 68% the brief specifies. That test says in its own
comments that the number is confidently wrong about half the time, and it is right about
itself. Checked by eye:

| dungeon | measured | actually |
|---|---|---|
| fungal_deep | 78% | ~68%. The measurement found the bright slime pool, not the junction. |
| rot_gardens | 86% | ~68%. Found the glowing mushrooms. |
| drowned_market | 86% | ~68%. Found the lit aisle. |
| the_maw | 82% | ~70%. Borderline, fine. |
| abyssal_stair | 89% | ~75%. Genuinely wrong — the paved ground starts under the standing line. |

So one backdrop of twelve has the defect that was reported, and re-rolling all six would
have thrown away four good paintings. **A measurement that is unreliable must not be
allowed to drive a work list**, which is why the re-roll list added here is hand-kept.

**What was actually wrong is one line of `combat.gd`.** The ground mark under each enemy
is a rounded Panel centred ON the standing line, so its upper half lies across the feet —
correct for a contact shadow, which is what it is at `Color(0, 0, 0, 0.72)`. For the
TARGETED enemy the same filled box was recoloured to `Color(1.0, 0.82, 0.40, 0.85)`:
85%-opaque gold, 62% of the enemy's width, painted over its ankles. In a one-enemy fight
the enemy is always the target, so the effect is permanent — a monster with no feet
sitting on a bright solid lozenge. It is now a RING for the target and stays filled for
the shadow: two styleboxes on the same node, and which one shows is the targeting cue.
The floor reads through it and the feet are back.

**Three prompt-sheet defects came out of the same look.**

*The shape of a request is per FILE, not per tier.* `gen_pollinations.py` took the
generation size from `TIER_RULES`, so Tier 0's six paintable files were all asked for as
"a square 1:1 image" — including `card_back.png`, which is **320x448** because the card is
150x214. A square card back has to be squashed or cropped to fit the thing it is the back
of. Tier 7 had the same fault less visibly: a 10:3 wordmark, a 16:9 splash and a 64x64
cursor, all requested at 10:3. ART_PROMPTS.md now carries each row's target size and the
aspect is derived from it; a tier whose files agree with their tier keeps its old wording
exactly, so this changed two tiers and nothing else.

*A sheet that only lists what is ABSENT cannot describe what is WRONG.* The moment a file
lands, correct or not, it disappears from ART_PROMPTS.md — so a bad asset has nowhere to
be recorded except somebody's memory, and `bg_warrens.png` has had THE WARRENS painted
into its wall for long enough that the defect is written down in the tier's own note and
still shipped. A `REDO` table names files that exist and are wrong, each with its evidence,
and they are emitted in their own table with the reason beside them: a re-roll with no
stated defect is how a bad file gets replaced by a differently bad file. It shrinks to
empty, which is what makes it a work list rather than a catalogue.

*Two of the new re-roll lines never reached the paste, for two different silly reasons.*
The filter that strips operator prose (D102) works per sentence and drops anything
containing "below" — so the single most important sentence in the rewritten backdrop
brief, the one naming the band that must be plain walkable ground, was deleted on its way
out. And the re-roll header wrapped onto a second line, which the same parser recognises
as art direction by its first character, so "subject line; what is already there is not a
constraint on what comes back" was being pasted into a generator as composition advice.
Both are the same lesson as D102 itself: the filter is a heuristic over prose, so prose
written for it has to be checked THROUGH it. The `--browser` output is the only place
either of these was visible.

**Also fixed while in there:** the sheet told you "no installer covers these" for the
backdrops. They install with `tools/install_backdrops.gd`, but they live at the root of
`assets/art/` rather than in a family directory, and the hint rule matched on the
directory name. It now recognises the `bg_` prefix the loader itself resolves them by.

---

### D111 — The tool was still selling three screens that had been deleted eleven decisions ago

An audit of every markdown file in the tree against the code it describes. Most of what
it turned up was ordinary rot — counts that had moved, a symbol renamed — but one item
was a different shape and is the reason this entry exists.

**`tools/art_manifest.gd` was briefing 26 files of art for the graph map, the dice board
and the deck reveal.** All three traversal models were deleted in D94. The manifest is
*generated*, and generated for exactly this reason (D101: "a prompt naming an enemy the
game no longer has produces a painting with nowhere to go") — but generation only
protects the half of the sheet that comes from `resources/`. The tiers that come from
hand-written tables inside the tool are as static as any hand-typed list, and nothing
looks at them when a feature is deleted. So `ART_ASSETS.md` and `ART_PROMPTS.md`
faithfully regenerated a shopping list containing `ui/node_frame_available.png`,
`ui/die_4.png` and a reveal frame for a card nothing reveals, every time, for eleven
decisions. `ART.md` §Tier 4 said "nothing left to draw here" the whole time and lost.

**The counts were the tell and nobody read them.** 209 files wanted did not move when a
fifth of the list stopped having a screen to land on. It is now 183 wanted, 74 present.
`tools/install_sheet.gd` had three matching dead modes (`nodes`, `tiles`, `dice`) reading
`Manifest.ENCOUNTERS`, which meant deleting the table broke the installer — a useful
accident, because `test_compile` would have caught it and nothing else would have.

**What the rest of the audit found**, grouped by the code change that orphaned it:

| the change | what still described the old world |
|---|---|
| D65 removed UI scaling | BUILD.md said Settings exposes `UI_SCALE`; ART.md said `UITheme.scale` runs 0.6–3.0; DESIGN.md §Conventions said `Ctrl +/-/0` rescale live. `UI_SCALE` is a `const 1.0` and `settings_state.gd` says in a comment that it is read by nobody. |
| D94 deleted three traversal models | DESIGN.md §2 listed them as a shipped system, §3 said `DungeonData.traversal` selects one (no such field), and named which dungeon used which. |
| D89 deleted the CC0 enemy sprites | CONTRIBUTING.md told you to add a boss by pinning a sprite in `PixelArt.OVERRIDES`; AGENTS.md and two asset READMEs cited `PixelArt.enemy_sprite()`. Neither symbol exists, and `assets/pixel/` no longer holds an enemy. |
| D83/D105/D107 styled every control | Four documents said `OptionButton`, `HSlider`, `VScrollBar` and `CheckBox` were "unstyled today". `UITheme` wires all four. |
| D95 moved two screens into `UI.screen()` | REVIEW.md's defect 9 and §2.2 still called them the only flat-black screens. |

Plus the ordinary drift: three "34 suites" against 37, three different decision ranges
(D92, D108, D109) against D109, and a README crediting two Kenney packs whose licence
files are no longer in the tree because their assets are not either.

**Two rules come out of this.**

**A generated document is only as current as the tool that writes it.** Regenerating
proves the file matches the *tool*; it proves nothing about whether the tool matches the
*game*. When a feature is deleted, grep `tools/` for it — the installers and the manifest
are code that nothing else references, so no compile error and no test will find them.

**Do not restate a number that something else owns.** Every count this audit corrected
was a number copied out of a directory listing or a constant into prose, and every one
of them was wrong. The two that were *right* — the content totals in AGENTS.md, and
ART.md's own note that no total is authoritative because ART_ASSETS.md is generated —
are right for structural reasons, not because anyone maintained them. D34 said this
about lookup tables; it is equally true of a sentence.

**Deliberately not done:** the duplicated `D109` heading (the level curve, and the gold
targeting lozenge) and the two things both calling themselves `D110` were left alone —
a concurrent session was writing them as this ran, and renumbering another session's
in-flight entry is how you get three of them.

### D112 — The sheet prompt never said 5x5, and 21 correct drawings landed on 21 wrong meanings

A batch of Gemini output arrived for four tiers at once — the loose `ui/` chrome and HUD
(tier 0 and 1b), the seven intent telegraphs (1c) and the twenty-one status symbols (1d).
34 files installed. Three separate things were wrong with the pipeline that took them,
and the third one is the expensive one.

**The sheets came back with the right pictures in the wrong boxes.** `install_sheet.gd`
assigns cells to names by reading order, and says so loudly on every run: *"a set
installed one cell out is 21 correct icons on 21 wrong meanings."* Both sheets were more
than one cell out. Tier 1c put its seven symbols in cells 0-3, 5, 6 and 8 of a 3x3,
skipping the middle. Tier 1d drew **25** glyphs where 21 were asked for — the 21, plus a
spiked ring, a sword-and-arrows, a duplicate buckler and a duplicate die — so everything
from cell 3 on was shifted. Straight install would have wired 18 of 21 symbols to the
wrong meaning, and `sym_strength` would have been a cracked shield.

**The cause was in the parser, not the generator.** ART_PROMPTS.md carries the grid on
the same line as the install command:

```
**Generate this tier as ONE image, not 21.** A 5x5 grid at 1280x1280 or larger
(21 glyphs, 4 cells spare — leave them empty), ... Install: `godot ... install_sheet.gd`
```

`gen_pollinations.py` matched `install_` on that line, took the command, and `continue`d
— dropping the grid with it. So what reached the model was *"A single grid image
containing 21 cells, in this exact order"*, with no rows, no columns and no spare-cell
rule anywhere in the prompt. A model handed no geometry picks its own and then fills
whatever the subject list did not reach. **The line was half operator prose and half art
direction, and the half that got thrown away was the load-bearing half** — the same
mistake as D102, in the opposite direction: D102 was pasting the operator's half INTO the
prompt, this was dropping the artist's half OUT of it. The parser now keeps the text
before `Install:`, strips the bold count, and `compose_sheet` states the grid before the
cell list. All three sheet tiers had their notes rewritten to say the geometry, the fill
order, and that an invented extra shifts every subject after it.

**Recovering the two sheets took a `--cells=` argument**, an explicit source cell per
target in target order:

```
install_sheet.gd -- symbols sheet.png --cells=0,1,2,5,6,7,8,11,9,10,13,14,15,16,17,18,19,21,22,23,24
```

It is an argument and not a table, because the next misaligned sheet is misaligned
differently and a stored permutation would be right once and quietly wrong afterwards.
It refuses a list that is not exactly as long as the set — a permutation one entry short
is the same shift it exists to undo. Both sets were then verified by eye against a
contact sheet in name order, which is the only check that actually closes this loop.

**The watermark is not backdrops-only, and the sheet said it was.** ART_PROMPTS.md told
the operator to run `strip_sparkle.gd` on backdrops and nothing else. That is right for a
matted cutout — the stamp is in a corner, the corner is field, the matte takes it and
`despeckle` drops the remnant, which `cutout_lib.gd` already explains. It is wrong for
everything installed OPAQUE or as a bloom: `card_back` fills its frame, so its corner is
painting, and both glows are black where the stamp is brightest. Those three would have
shipped the stamp. `intent_unknown` did ship it on the first attempt — the tile is one
opaque component, so the stamp joined the subject and no island test could see it.

Two things about stripping this batch are worth keeping. It needs **four images that
still agree on where the stamp is**, so it runs on the whole staging directory before
anything crops — and a batch of two sheets is short, which was solved by staging them
with three still-unstripped files from the same session. And the intersection is only
reliable where the stamp is *lit in every frame*: on the symbols sheet the stamp sits
half over a white glyph, where it is DARKER than its surroundings, and the intersection
collapsed from 64x64 to 41x41 — a mask that would have inpainted the middle of the chest.
That sheet was left unstripped and came out clean anyway, because `cut_mono` normalises
a faint grey sparkle to zero alpha.

**What the batch is, and what is still wrong with it.** `install_chrome.gd` grew from
five names to eleven and is no longer "control chrome" — it is every loose `ui/` painting
with no catalogue behind it. It also grew a fourth column: a **glow** mode taking alpha
from luminance rather than from a flood fill, because a bloom's own falloff ends in the
same black its field is, so a matte at `TOL` walks up the gradient and leaves a
hard-edged disc — a ring, in the one asset whose entire job is to have no edge. Two
defects out of D105 are closed: `dropdown_arrow` and `slider_grabber` came back on flat
fields and their hand-measured crop rectangles are gone. Three are open and in `REDO`:

| file | what is wrong |
|---|---|
| `ui/target_ring.png` | a warm bloom fills the ring, so the reticle covers the enemy it marks, and where the bloom spills through the four gaps it holds a wedge of background the border fill cannot reach |
| `ui/dropdown_arrow.png` | a cyan bloom on the FIELD under the chevron; the matte can only stop where the bloom stops being field-coloured, so it installs as a chevron on a hard-edged opaque disc taking a third of a 32px icon |
| the seven `ui/intent_*.png` | drawn as nine stone tiles rather than seven symbols on a field, so the tile is the subject and only the gutter between tiles is field — they install as opaque plaques, dark violet on dark violet |

**All three are the same defect wearing three hats, and it is D105's:** something was
painted onto the field. The matte cannot tell a bloom on the background from the
background, and it should not try — loosening `TOL` to eat a gradient is how it starts
eating grey armour on a grey field. So the fix is always in the prompt, and the prompt
now says it for all three: the field stays flat and empty, and anything painted on it is
cut away with it and leaves a hard edge where it was cut.

`ui/card_back.png` is the one that got *better* between attempts and shows the D109
size column working: the first take came back square, which the recipe would have
stretched 1.4x vertically into the sigil; the second came at 864x1216, 0.7105 against the
card's 0.7143, and the stretch is half a percent.

**Deliberately not done:** the intents and the two bloomed cutouts are installed rather
than held back. Nothing loads any of them yet — intent still renders as the string
`hit 5` — so an opaque plaque on disk costs nothing, and a file that is present and
listed in `REDO` is a defect with evidence attached, where a file that was never saved is
a defect nobody can look at.

### D113 — Two controls in one list, drawn from two different rules

**The slider handle was nearly twice the checkbox beside it.** Both are theme ICONS in
the same settings list, and Godot blits an icon at its texture's own pixel size, so what
each one drew was whatever its asset happened to be: the checkbox capped to 26 by
`icon_max_width` (D107), the slider handle uncapped at its installed 48x48. They are the
same kind of thing at the same eye level, and any difference between them reads as one of
the two being wrong rather than as a deliberate hierarchy. One number now, `CONTROL_ICON`,
renamed from `CHECKBOX_ICON` because it stopped being about checkboxes.

**`icon_max_width` is a Button constant, so the slider needed a different lever.** Only
Button and its subclasses read it; `HSlider` draws `grabber` at `get_size()` and offers no
constant, no scale and no override. So the only lever on a slider is the SIZE OF THE
TEXTURE handed to it, which is why `kit_icon()` resamples rather than setting a constant —
the one place in this file that pre-scales art instead of asking the theme to.

**It is deliberately not on `kit_frame`'s path.** A nine-slice must never be pre-scaled:
its slice margins are in texture pixels, and resampling moves the border out from under
them, which is the smearing D83 is about. `kit_icon` also returns the texture untouched
when it already fits, so nothing is resampled for the sake of it, and null when the file
is absent — the same contract as `PixelArt.ui_kit`, so every caller's `!= null` gate still
means "the art is installed" and the kit can keep arriving in pieces.

**Capping beats shrinking the file, and that is a real choice.** `slider_grabber.png` stays
48x48 on disk. The layout is a fixed 1280x720 that `canvas_items` scales to the window, so
on a 4K display every asset is drawn at 3x — an asset shrunk to 26 on disk would be soft
there, while a 48px source scaled to a 26-unit box has headroom to spare. The size a
control draws at is a property of the row it sits in, not of the painting, so it belongs in
the theme.

### D114 — The most-seen painting in the game was off-style, and the doc said it was the style

The title screen does not match the rest of the art, and it took someone looking at it to
notice, because every document that mentions it said the opposite.

**What is actually wrong with it.** Not the palette, which is the thing you would guess
and the thing a re-roll would have chased. `main_menu.jpg` measures mean luminance 20.2%,
inside the style block's 20-35% band, and its saturation sits between `bg_crypt`'s and
`bg_the_maw`'s. The defect is the FIRST line of the style block — *every form carries a
dark ink outline* — and it carries none. Measured as the share of pixels that are a local
luminance minimum by more than 0.08 against both neighbours two pixels out:

| image | ink-line pixels |
|---|---|
| `main_menu.jpg` | **1.2%** |
| `bg_crypt.png` (the style reference) | 2.8% |
| `bg_sunken_vault.png` | 8.0% |
| `bg_warrens.png` | 10.9% |
| `bg_the_maw.png` | 11.0% |
| `bg_ossuary.png` | 12.2% |

It is a ninth the outline density of a typical room and less than half of `bg_crypt` — and
`bg_crypt` is the floor of that set, being the most open composition in it. What is on the
title screen is flat vector silhouettes: firs, mountains and a fortress spire as filled
shapes with no line around them.

**It could not be on the re-roll list, because no row named it.** `REDO` is keyed by the
manifest's own paths, and Tier 7 listed the logo that sits on top of the title art, the
boot splash shown before it and the cursor that moves over it — not the picture itself. So
the file was invisible to the sheet in both directions: never asked for, because it exists,
and never re-rolled, because nothing knew it was there. It now has a row, and the sheet
prints it with the measurement as its stated defect.

**Two documents asserted it was fine, and one of them argued from it.** ART.md §1's
dialect table filed it under *"Painted, inked illustration — this is the game, keep"*
beside the twelve dungeons, so the count of fighting visual languages was five and the
heading said four; that miscount survived thirteen decisions because it was in the column
nobody re-reads. Worse, ART_PROMPTS.md's rule 1 used it as the *example* of the two-tool
problem — "`main_menu.jpg` and the dungeons from one, the scene and zone backdrops from
another." But `assets/art/README.md` records the provenance, and the title art and all
twelve dungeons came off the SAME Gemini. So the file it named as one tool's coherent
output is the counterexample to the rule it was illustrating.

**That inverts the lesson, and rule 1 now says so.** One generator is necessary and not
sufficient: the same tool, asked twice in two wordings, produced two dialects. Which is an
argument FOR rule 2 rather than against rule 1 — the reference image and the fixed style
block exist precisely because the wording is the part that drifts, and `main_menu.jpg` is
what a request sent without them looks like.

**The count on the sheet was low by eleven and is now right.** `**N files can be
generated**` counted rows whose file is absent, so the twelve re-rolls were excluded while
their tables were printed below — the header read 56 while the tiers asked for 67. A
re-roll is the same prompt sent again and costs the same as a first draft, so it counts:
68.

**Landing the re-roll needed an installer route and a resolver, and the resolver is the
load-bearing half.** The title art is the one painting with no `bg_` prefix and the one
that is a `.jpg`, because it predates the installers — which is also how it escaped them.
It now rides `install_scene_backdrops.gd` (same job: full-bleed 16:9, opaque, letterbox
stripped, cropped rather than squashed) under the source name `main_menu` or `title`, and
that tool only writes PNG. Four places spelled the `.jpg` path — `main_menu.gd` and three
tests — and if the install had left them behind, the failure would have been SILENT:
`UI.screen()` treats a missing backdrop as "not drawn yet" and draws the menu on flat
colour, so the symptom of a half-landed swap is a title screen that looks deliberate.
`PixelArt.title_art_path()` resolves the extension in one place, PNG first, and the
installer deletes the superseded `.jpg` rather than leaving two answers to the question.

**Deliberately not done: the `.jpg` was not converted to PNG now.** Normalising the
extension ahead of the re-roll would mean re-encoding and 16:9-cropping a file that is
about to be replaced anyway, to fix a wart the resolver already covers. The swap happens
once, when the new painting lands.

---

### D118 — The card tier could never have installed, and the generator was blamed for it

Found while harvesting the first card illustration. `tools/install_cutouts.gd -- cards`
refuses every source it is given:

```
FAIL  block.png   background is not flat (28% of the border agrees, need 80%)
                  — this looks like a painting of a room, not a subject on a field
wrote 0, failed 1
```

**The installer is right and the routing is wrong.** `Cut.cut()` mattes anything whose
opaque fraction is above 0.995, which every card illustration is, because a card
illustration *is a filled rectangle*. Its own brief says so in the first sentence — "A
filled 4:3 rectangle, not a cutout" — and then the sheet tells you to install it with
the tool whose entire job is cutting subjects off fields. The matte then hunts for a
flat border on art that deliberately bleeds to all four edges, fails to find one, and
refuses. Correctly. **0 of 12 could ever have landed**, at any quality, from any
generator, however good the painting.

Three families are a subject that must be cut out of its field; one is a picture that
fills its frame. That distinction already existed in the manifest as `Kind.SCENE`
versus `Kind.PAINT` — it just never reached the installer, which had one code path.
`FAMILIES` now carries a fourth flag and cards take `Cut.fill()`: cover-crop to the
canvas, centre the overflow, no matte, no trim, no alpha. Cover rather than squash, so
a source a few percent off 4:3 loses a sliver instead of stretching its subject.

**What made this expensive is what it looked like.** A tier failing 12/12 with a
message about flat backgrounds reads as "the generator keeps painting rooms" — a
prompt problem, and there *was* a real prompt problem in the same tier the same
afternoon (the painted cost numerals, above). Two defects in one tier, one of them
loud and cosmetic, and the loud one hides the structural one. **A whole tier failing
identically is evidence about the pipeline, not about the art**: one bad generation is
a generation, twelve identical refusals are a route.

It also went unnoticed because nothing had ever reached the installer. The tier has
been 0/12 since it was written, so the first file to arrive was the first test the
code path ever had. A route with no traffic is not a working route; it is an untested
one, and `ART_PROMPTS.md` printed its install command all the while.

### D115 — The art was on disk and nothing read it, and the screens were being judged 80 rows too tall

A sweep of the cheap defects, run as five parallel agents. Four of the five found
something the brief had wrong, which is most of what this entry is for.

**The painted symbols were installed and unreachable.** D112 landed 21 status symbols at
`ui/sym_*.png`; `grep` found zero call sites. `PixelArt.symbol()` built a 16x16 bitmap
from `GLYPHS` and `ui_kit()` sat directly beside it already doing the resolve needed, so
the fix is that `symbol()` prefers the painted file and falls back. **12 of 13 glyph
names now serve painted art** — the brief said 18 names and was wrong: `stone`, `forge`,
`rot`, `deeps` and `void` are in a separate `PATTERNS` const for tiling zone backdrops
and were never symbols. `heart` reaches `sym_hp.png` through a one-entry alias; `book`
has no painting and keeps its bitmap, which is why the fallback is not dead code.

The tint contract was verified by reading pixels rather than the docstring: every opaque
pixel in the painted files is pure white, because `install_sheet.gd` runs the symbols set
through `cut_mono`, which takes alpha from luminance and throws the colour away. One real
difference: the bitmaps encode shading as grey at full alpha, the paintings as white at
partial alpha, so a painted glyph's soft interior reads as translucent rather than as a
darker tint.

**This broke `tests/test_art.gd` in 16 places, and the test was wrong.** It asserted
symbols are *exactly* 16x16, then counted lit pixels in a hardcoded `for y in 16 / for x
in 16` window — which on a 64px glyph samples only the top-left quadrant, so four painted
symbols read as "nearly empty" with their subject untouched in the middle of the frame.
Neither claim was what the test was protecting. It now asserts **square and a multiple of
16** (every consumer centres the glyph in a square box, so a non-square glyph arrives
letterboxed) and scans the real image with the emptiness floor as the *fraction*
`12/256` always meant. An absolute count is not scale-free: 12 lit pixels is a glyph at
16x16 and a fleck of dust at 64x64.

**Eight files marked GENERATED, DO NOT PAINT had never been generated.** `divider`,
`dropdown`, `slider_track`, `scrollbar_track`, `bar_frame` and the three bar fills.
`gen_ui_kit.gd` gained one primitive: `_strip()` copies a single line of pixels along the
long axis, so **tileability is structural rather than checked afterwards** — column x and
x+1 are literally the same pixels, and no seam can exist. That is D83's nine-slice rule
in one axis, and it is the reason these are computed and not painted.

The first cut of the two grooves failed its own eye check (D56): the channel floor sat at
the background's own luminance, 0.05 against 0.07, so at 4x they drew as two hairlines
with a hole between them rather than a channel. Lifting the floor to the level the
already-installed `slider_grabber` stone sits at fixed it.

**And the eighth file activated a latent bug three feet away.** `ui_theme.gd` hardcoded
`INK` as OptionButton's font colour, chosen when the kit was parchment and harmless for
as long as `dropdown.png` was absent, because the whole block is skipped while the file
does not exist. The moment it existed: near-black text on a face of luminance 0.067,
**1.27:1**, which is not low contrast but invisible, and it would have taken the three
filter dropdowns and the settings dropdowns out together. `ink_for()` already existed to
measure ink off the middle of the art. **Compensating in the artwork was considered and
rejected** — a paler dropdown face would then have swallowed `dropdown_arrow.png`, which
is a pale carved-stone chevron. The frame was right; the ink was guessed.

**The crawl header wrapped mid-phrase because the unit of wrapping was the string.** Nine
statistics concatenated into one `Label` broke inside `AT RISK: 0 cards, 0 gold`. A
shorter string is not the fix and neither is a smaller font: **the unit of wrapping has
to be the FACT**. Every statistic is its own `Label` in a flow container now, so a row
that runs out of width breaks between facts and there is nothing left inside one to
break — which holds at any content length, verified against a forced worst case
(`The Drowned Market (d12)`, `Gold 999999`, `AT RISK: 99 cards, 99999 gold, 30 relics, 12
packs`). Importance became expressible once the facts were separate: the escrow figure
and the ropes that answer it share the header's only frame, dim while empty and lit amber
the moment something is in it, because an alarm that is on from the first step of every
run is wallpaper by the third.

**One rarity vocabulary, seven spellings.** `CardData.Rarity.keys()` was indexed at eight
call sites which had each picked their own casing, so three shouted `[RARE]`, three said
`rare` and one said `Rare`. `CardData.rarity_word()` derives the word from the keys
rather than holding a table, because a private copy of a shared classification is D34 in
better clothes. `rarity_badge()` exists because the *brackets* had drifted too, as a
literal in four format strings. Relics and powers correctly share this scale —
`relic_data.gd` declares `@export var rarity: CardData.Rarity` and `power_data.gd extends
CardData` — so only the enum's *name* is misleading, and renaming it would move persisted
ordinals that `.tres` files and saves store raw.

## The screens were being judged at 1280x800, not 1280x720

`project.godot` sets `window/size/mode=3` (fullscreen) with `stretch/aspect="expand"`, so
`tools/Screenshots.tscn` on a 16:10 monitor renders a **1280x800 logical viewport** — 80
rows the shipped game does not have. Every capture used to write ART.md and REVIEW.md is
3072x1920, which is 1280x800. The harness's own header documents the
`Xvfb -screen 0 1280x720x24` invocation for exactly this reason and nobody had used it.

It was hiding a live defect: the crawl's two stacked full-width footer buttons pushed
`Menu` half off the bottom edge, and had been doing so for as long as the header wrapped.
`Collection` and `Menu` are side by side now, recovering ~60px without taking any height
from the floor viewport.

**What this does NOT invalidate:** `CardTextTest` sets `get_window().size` from the
project settings explicitly, so the hand assertions were always measured at 720. The
guard added in D97 — no resting card's name may run under its right-hand neighbour — is
sound and non-vacuous. Its real gap is narrower: it only ever runs on the hand combat
deals, and `Balance.HAND_SIZE` is 5, so a hand pushed past five by draw effects against
`FAN_OVERLAP` 0.88 is unmeasured.

## What the 720 render found instead: 29 of the 35 enemies are flat silhouettes

`ART_PROMPTS.md` says of Tier 2, **"Nothing to generate here — all 35 present."** The
plates are present. Six of them are paintings and twenty-nine are featureless coloured
humanoids — `cultist.png` is a flat brown figure with no interior detail at all, and it
is the shipped plate, not a missing-art fallback. The file sizes are the tell and there
is no ambiguity in them: six plates at 70-577KB, then a cliff to 21KB and below for the
other twenty-nine.

Every earlier capture of the combat screen happened to roll Bone Pickers, which is one of
the six, so the screen looked finished in every review this project has written.

**This is D109's finding in the largest content tier in the game, and the mechanism built
for it was never pointed here.** `REDO` exists precisely because a list of what is
*absent* cannot see a file that arrived *wrong*; the moment something lands the sheet goes
quiet. Twenty-nine plates landed, the sheet went quiet, and the shopping list has said
enemies are done ever since. The counts cannot catch it either — they count presence, and
these are present. Nothing measured them and nothing was going to.

### D116 — Six cheap fixes, and four of them found something the brief had wrong

Second sweep, six parallel agents on disjoint files. The pattern from D115 held: the
value was mostly in what the agents refused to accept.

**The vitals became instruments.** `HP 60/60` / `Energy 3/3` were text with the art for
both sitting unread on disk. HP is now a `bar_frame` nine-slice with three fills stacked
in the trough — current HP, Block as a band across the top of it, and the telegraphed
damage as a dark slice at the near end. All three are scaled against one span of max HP,
which is what makes them comparable: the Block band and the loss slice can be read
against each other by width alone.

The loss slice is `Combatant.predicted_damage(eng.enemy_intent)`, the engine's own
answer, not the raw intent — so Block and Vulnerable are already in it and combat keeps
no private copy of the arithmetic. **That exposed a lie in the old line:** the tooltip
said `incoming` was net of Block and it never was. 13 was the raw swing, and a player
holding 9 Block had no number anywhere for the 4 that would actually land. It reads
`Block 9    incoming 13 → 4` now.

`orb_glow` found a use, and only because the orbs are a row of discrete rects: "which orb
changed" is an index, so the bloom is one node on the existing `fx_layer` with one tween,
the same shape as `_float_number`. Photographing it with the peak held open caught two
bugs invisible any other way — at 0.9 alpha the bloom out-shone the orb so a *spent* orb
read as a white disc, and untinted white additive over a violet orb read as grey smudge
rather than light.

The vitals block grew from ~56px to ~160px, so the HUD box became **`ALIGNMENT_END`**,
which matters more than the offset change: a VBox whose children out-measure its rect
overflows past the *bottom*, and the bottom was 10px from the frame edge. The old
top-aligned box was one log line away from pushing the log off screen.

**Nine painted symbols had no consumer, and the ones that did were wrong.** `for_card()`
sent a Strength card to `"relic"` → `"gold"` — **a stack of coins** — and a heal to a
heart, because the cascade only ever had 13 shapes to choose from. Distinct symbols across
the 100 cards went 7 → 11, measured by reverting rather than asserted.

The interesting part is the assertion. Raising the existing "must discriminate" floor from
4 to 8 was not enough: on a *partial* revert `kinds.size()` was still 10, comfortably over
the floor, while heal, strength and dexterity had silently gone back to being decoration on
disk. **An aggregate count cannot see a file going unread.** So each wired meaning now has
its own check that a real card reaches it, failing with the filename:
`no card resolves to 'strength' — ui/sym_strength.png has no consumer again`.

Three deliberate omissions, all documented at the call site: no `draw` branch, because the
painted set has no draw glyph so it could only return `card` and its one effect would be
to hide `energy` behind it; `retain` and `exhaust` unreachable from `for_card`, because no
card *is* a retain, it retains while doing something else; `pierce` is enemy-side
(`Balance.pierce_fraction`) and belongs to the intent telegraph.

**Keys were being carried by a promise that was false.** `GameState.risk_line()` returned
a pre-joined string and two screens had started reverse-engineering its formatting to get
the parts back — `iso_run` splitting on runs of two spaces, `pause_menu` doing
`trim_prefix("AT RISK: ")`. `risk_parts()` fixes that, returning display phrases rather
than counts on purpose: handing back numbers pushes the pluralisation and the
which-kinds-to-mention rule into every caller, which is the duplication being removed.

But the refactor's real finding was the content. The pause menu read *"At risk in this
run: 2 cards, 140 gold, 1 pack **Keys 2** — secured by beating the boss, or by using an
Escape Rope"*, and keys are secured by neither; the rope prompt repeated it. The function's
own comment already said keys are not at risk in the same sense, and the crawl was
*disagreeing with the string* by stripping them off the tail — that disagreement was the
tell. Keys are out of `risk_line()`; both callers still show them, just not under a
promise the game does not keep. `at_risk()` was added because the D115 header had become a
second place deciding what "at risk" means.

`TraversalIso.status()` was left joined, for a better reason than the one given: `status()`
is a virtual on the `Traversal` seam, so a parts accessor is the base class's to declare,
and adding one to the override alone is a half-migration.

**A 1244px button is not a button, it is a banner.** And the bug was the container, not the
button: a `VBoxContainer` hands its full width to any child left on the default
`SIZE_FILL`, while an `HBoxContainer` sizes to content — so every banner in the game was a
`UI.button()` whose parent was a VBox, and every row had already solved it. Rows are
untouched, which is what keeps combat's header, the deck builder's footer and D115's
IsoRun pair byte-identical.

It is a **minimum, not a maximum**: Godot has no max width and a hard cap clips labels, so
`max(480, content)` narrows every offender while letting a long label grow. No new
parameter — the width is applied before the caller receives the button, so a screen
overrides it by writing `custom_minimum_size.x`, which `packs_screen.gd` already does for
its 140px `Open`. 480 was chosen by photographing the whole set at 480 and at 320: 320 is
the better `Back` and the worse title screen, because `Continue` is ~335px of text and the
one column that had been deliberately sized went ragged.

Width did **not** fix Packs' `Open all`, and that is worth recording rather than assuming.
It is still the first pressable thing on the screen, still above the three packs it
short-circuits. What invites the skip is reading order, not size.

**The Relics screen said one thing three times over an empty frame.** "0 of 30 found",
"None yet", "Still undiscovered: 30", then 95% void. It shows all thirty slots now, in
five rarity groups of 7/8/7/5/3 — the one interesting shape the set has, and the only axis
the player can act on, since a deeper fight tilts the roll.

Two calls worth keeping. The **effect is withheld, not the name**: thirty rows of "???" is
the old defect with more rows, and a relic is a rarity-weighted roll off a boss, never
something you can go and buy, so the name changes no decision available to the player. And
the recession value was **measured off the rendered PNGs**, which found a floor that cannot
be met: the first dim value put an unfound Epic name at **2.35:1**, and 4.5:1 is
*unreachable* for unfound Rare and Epic because those hues are only 7.1:1 and 6.1:1 *when
held* — a dim variant clearing 4.5 would be indistinguishable from owning the thing.
Asking for the usual target there would have been a bug, not a standard.

## The hand survives eleven cards by shrinking its type below its own legibility floor

D115 said the pairwise name guard from D97 was sound but only ever measured the five cards
combat deals. Measured at eleven — `5` `HAND_SIZE` + `1` Keen Lens + `2` Scholar's Lens +
`4` a once-fused See It Coming − `1` played, every card dealt by the real engine, and the
test computes that number back off the live relics rather than restating it so a retuned
relic fails instead of silently measuring less.

**All three assertions pass.** The tightest pair has 3.0px of slack. And the names come out
at **7-9px** — "Two Quick" at 7px, wrapped to two lines — against the **14px floor this
same suite enforces for hovered text**. Legally inside its slot and unreadable at arm's
length. That is printed rather than asserted, because an assertion there is a design
change: a cap on hand width, a second row, or less overlap. It is the real defect and it is
still open.

Non-vacuity was proved by reproducing D97's failure at the new size from inside the test,
without touching `combat.gd`: **10 of 11 names ran 92-107px under their neighbour.**

**The frame size is now asserted, not assumed.** `card_text_test` set `get_window().size`
from project settings and trusted it; it now measures `get_viewport().get_visible_rect()`
and fails if it is not 720. Forcing 1280x800 made **only that check fail and nothing
else** — so every rect in the file had been trustworthy by luck rather than by
construction. That is D115's screenshot trap turned into a guard.

## Still open, and one of them is bigger than everything above

- **29 of the 35 enemy plates are flat silhouettes** (D115). Not fixed here; the fix is
  `REDO` entries, and `art_manifest.gd` was being edited by a concurrent session
  throughout both sweeps.
- **`sym_energy` reads as a plain disc with a hole and `sym_dexterity` cannot be named at
  any size** — weak as paintings, independent of scaling. `REDO` candidates.
- **The spent energy orb reads LIGHTER than the unspent one.** The brief asked for "cold
  grey stone" for spent and a lit violet orb for full, and cold grey stone is the brighter
  of the two, so the state that should recede advances. Visible only by looking at the
  render.
- **Thin strokes chew at 28px** under the project's NEAREST filter — `rope`'s coil breaks
  into a dotted ring. Cosmetic, never semantic. The fix is a `PixelArt.symbol_at(name,
  side)` sharing `kit_icon`'s LANCZOS; it cannot simply call `UITheme.kit_icon`, because
  that is a method on an autoload and referencing an autoload at compile time makes a
  headless `--script` test hang rather than fail (D19).
- **`combat.gd`'s `_refresh_buffs()` is still run-on prose joined by `·`** — six statuses
  is a paragraph inside a 330px HUD — and `Combatant.status_text()` still abbreviates to
  `Blk 5 Psn 3 Vuln 2` *because there was never an icon to use*. All seven now have one.
- **`BAR_BORDER` is restated** in `combat.gd` and `gen_ui_kit.gd` and the two must agree or
  the fills slide out from under the frame. `test_art.gd` already asserts `gen_ui_kit`'s
  palettes against their real owners; this belongs in that net.
- **`tools/screenshots.gd` can only photograph turn one of combat**, so a partial HP bar, a
  Block band and spent orbs are all invisible to the shipped harness. The agent that built
  them had to fork the repo to see its own work.

---

### D119 — Generating the art through a browser, and the four things that were wrong with asking

The Gemini API refuses image generation on an unbilled key — every image model reports
a free-tier quota of zero, and one real call returns `429 ... quota exceeded for metric
generate_content_free_tier_input_token_count`. Billing was ruled out, so the whole
remaining art list had to come through the consumer web app, driven by Claude in Chrome.
The mechanics are written up in the `gemini-browser` skill; what belongs here is what
the run found out about the *asking*, because three of the four defects were in this
repository's own prompt sheet and would have reappeared through any pipeline.

**Delivered: tier 3 complete (12/12 card families) and 6 of 30 relic icons**, manifest
108 → 135 present.

#### The brief described the wiring, not the picture — again

`ART_PROMPTS.md` told the generator that "FOUR things are drawn on top of it … a cost
numeral top left and an effect symbol top right". Those are the plates the *game*
composites over the art. The generator drew them: a "5" top-left, a sword icon
top-right, an "8" and a "15" along the bottom — in direct contradiction of the same
prompt's own `FORBIDDEN: … numerals` line three paragraphs above. A family illustration
is shared by every card in it, so that is a permanently *wrong* cost on nineteen cards.

This is D101 and D108 for the third time. **Describe a keep-clear region by position and
emptiness, never by naming what will later occupy it.** The fix is in the tool.

#### A whole tier failing identically is evidence about the route, not the art

Written up separately as D118, because it is a code defect rather than a prompt one:
`install_cutouts.gd -- cards` mattes anything opaque, card art is opaque by
construction, and the matte therefore refused all twelve. It had never been exercised —
the tier was 0/12 since it was written, so the first file to arrive was the first test
the path ever had. **A route with no traffic is not a working route, it is an untested
one**, and the prompt sheet printed its install command the entire time.

#### The matte can eat the subject, and only the display size shows it

`balanced_grip` installed cleanly, looked right in a file browser, and read at 48px —
the size a relic icon is actually drawn — as two floating fragments. Its dark
leather-wrapped midsection fell outside the matte, which severed the object; the
despeckle then dropped the pieces as specks. The count it prints is the tell: 41 and 101
were watermark, **167 was the handle**, and 10–22 is what a clean cutout costs.

So the prompt now requires **one connected solid mass, lighter than the field
everywhere, no thin dark parts** — and the tier is judged on a 48px contact strip, which
is the only size at which its own brief ("silhouette and one memorable colour") means
anything. Same lesson as D89: photograph the result, at the size it ships.

#### A style reference decides more than style

Every relic came back glowing the same cyan, because "ONE saturated light source" plus a
cyan-lit reference is a cyan light source thirty times over. "One *memorable* colour"
is a claim about an icon relative to the other twenty-nine, and nothing in the prompt
made it one. Accent colour is now named per item.

#### And a long chat stops reading the subject line

After ~15 images in one conversation the model began answering its own recent output:
`balanced_grip` returned a near-duplicate of the previous relic, a rune-covered power
cube with no grip in it. Every image was individually well-made and on-style, which is
exactly why it nearly passed — **the only tell is that two results could carry the same
caption.** Naming the shape to avoid ("do NOT draw a cube, block, box or anything
covered in runes") beats it; a generic "make it different" does not.

#### What actually limits this

Not the automation. The free tier allows roughly **20–25 images a day**, then silently
switches the model to Flash-Lite and answers image requests with "I can create more
images as soon as your limit resets". Verified as account-level, not per-model, by
switching back to 3.6 Flash and getting the same refusal. The remaining 33 files are a
two-day job at that rate. The paid API would do the lot for about two dollars, which is
worth restating whenever this comes up again.

### D117 — A Label reports its text as a minimum width, and it was eating the hand

Three fixes that turned out to be one finding: **the combat HUD's width was data-driven and
nothing was bounding it.**

**The status readout was collapsing the fan.** `_refresh_buffs()` rendered the player's
statuses as run-on prose in a single `Label`, and a Label reports its text as its own
minimum width. With six statuses up that forced `hud_box` to **1373px** — 16..1389 inside a
1280 frame, running under the hand and off the right edge — and with seven two-digit
statuses to **1563px**, which drops the fan's step from 107.8px to **7.9px**. With a
five-card hand. So the unreadable-hand problem was never an eleven-card edge case; its
common trigger is a fight where statuses stack.

It is a row of icon+number chips now, and `hud_box` holds at 330px whatever is up. Every
one of the seven meanings had a painted symbol waiting since D112 and unread until D116.
The old line also applied ONE colour to the whole string, so **Strength went red whenever
any debuff was up** — worse than no distinction. The two chip colours are the same two
literals that code was already choosing between, promoted to named constants.

`Combatant.status_text()` — the enemy-side `Blk 5 Psn 3 Vuln 2` abbreviation, abbreviated
*because there had never been an icon* — was **deleted** rather than kept, after a grep
found exactly one caller. Keeping it would have left a second hand-kept list of the same
seven statuses that nothing reads, which is the D111 shape.

**Taking 18px back off the HUD exposed a `maxf` that outranked its own measurement.**
`_place_hand` did `left = maxf(px(372), hr.end.x + px(14))`, so the constant — a number
taken off a screenshot, which that block's own comment is an apology for — silently won as
soon as the live rect got *smaller*. It is a pre-layout default only now.

## The hand keeps one row, and gives up the name rather than shrinking it

The fan is staying a single overlapping row. `step = (room - card_width) / (n - 1)`, so at
n=11 the step is ~41px and `fit_name` was buying the fit with type size: names at **7-9px**
against the **14px floor this same suite enforces on card text**. Legally inside the slot
and unreadable at arm's length.

**Density is the wrong lever and the arithmetic says so.** `card_width` appears once in the
numerator while the divisor is `n-1`, so narrowing cards 150→110 buys about +4px; reclaiming
HUD width bought +1.8px measured. Neither touches a 7px problem.

So below a threshold the resting card stops showing its name and shows its **cost and its
effect symbol** instead. This is only worth doing because of D116: that glyph is a painted
symbol that states what the card does, where a week ago it was a 16x16 CC0 tile that read as
noise. "Attack, costs 1" at a glance beats four legible letters of a name.

**The threshold is measured, not chosen.** All 100 card names were fitted into the real
28px-tall strip at every slot width from 4 to 140, recording where each first holds 14px:
22px for "Jab", 119px for "Something Worse", median 69px. Read as a curve — how much of the
deck a slot can still name — 86px names 76 of 100, 52px names 26, 35px names 13, 33px names
9. `CARD_NAME_MIN_W = 34.0` is where that crosses **one name in ten**: below it the strip has
stopped being a way to name a card. Deliberately a *width* and not "did the fitter end below
the floor", because the latter is per-name and would fire on the 24 longest names in a
five-card hand.

The five-card hand is unchanged, and that was verified as identity rather than resemblance:
the same seeded pose rendered against `HEAD:scripts/ui.gd` and against the change produced
**the same md5**.

**The vacuity trap was the real hazard, and it was already in the file.** The pairwise name
assertion from D97 opened with `if nm == null or not nm.visible: continue` — so hiding the
name would have made it silently pass at exactly the hand sizes it was added to protect.
Hiding the subject to satisfy the check is not a fix. It now demands *either* a visible name
clear of its neighbour *or* a visible cost and a visible symbol with a real texture, never
neither; asserts the swap happens at eleven and does **not** at five, so the threshold cannot
drift to "always" or "never" unnoticed; and asserts hovering still gives back the whole face.
Every one of those was watched go red — threshold at 0 gives "still claims to show its name"
plus a 7px name, at 999 gives "4 of 5 cards in the DEALT hand gave up their names".

## Two corrections to what D116 recorded about the spent orb

D116 said the spent energy orb reads lighter than the unspent one. The conclusion was right
and both of its premises were wrong.

Undimmed, the spent orb was already the **darker** one by mean — 0.294 against 0.426. It
advanced anyway because the unspent orb spends its luminance on a 3px warm core inside a
soft gradient while the spent one spends its on a hard-edged **ring around the whole disc**,
and there are two of them. Area times contrast, not peak. The reverse of the usual trap: the
numbers were reassuring and the render was not.

And the measurement that reported spent as outright brighter had caught them
**mid-`_flash_orb`** — spent is (158,125,118) in that frame against (76,73,96) at rest,
while the unspent orb is identical to the byte in both. That was the bloom's additive amber.
Worth keeping: the bloom fires on the orbs that *changed*, so for ~⅓s after spending, the
orb you just spent really is the brightest thing in the corner.

Spent now sits at a third of the lit orb, with alpha deliberately 1.0 — at 0.7 it goes
translucent and reads as a hole, which is the mirror-image defect.

## REDO and sheet tiers did not compose

Two of the twenty-one status symbols cannot be *named* by someone who is not told what they
are: `sym_energy`'s point of light is off-centre, so a brief asking for an orb "lit from
within by one point of light at its centre" produced a disc with a specular highlight — a
billiard ball; and `sym_dexterity`'s arrow points INTO the buckler instead of glancing off,
so the picture says the hit landed, the opposite of what Dexterity does. Both had been
installed and unread until D116, so nothing had ever looked at them at the size they are
drawn.

Listing them in `REDO` printed **"Generate this tier as ONE image, not 2"** directly above a
paragraph describing a 5x5 grid of twenty-one cells. That is not a formatting bug, it is the
requirement inverting: these tiers are sheets because the SET has to be mutually
distinguishable and a single request is blind to the others (D91) — but once nineteen are on
disk, **the survivors are the reference**, and re-rolling the sheet throws away nineteen good
drawings to fix two.

So `install_sheet.gd` gained `--only=`, which restricts the target list and sizes the grid to
what is left: two names is a 2x1 sheet, not a 5x5 with twenty-three cells to leave empty. It
refuses a name it has no target for, printing the valid list, rather than installing the
subset it recognised.

The first attempt at the document half got the delivery format wrong — it emitted N
individual pastes, producing a page that asked for two images and then told the operator to
install one sheet. Caught by rendering the browser route and reading it, which is the only
way it could have been caught.

### D120 — The hand is capped at ten, and the simulator cannot see the build it affects

Slay the Spire's rule, copied exactly: `Balance.MAX_HAND_SIZE = 10`; a draw into a full
hand does not happen and **the card stays in the draw pile**. The cap is checked *before*
the discard-reshuffle, deliberately — a refused draw must not be able to turn the discard
pile over, which would be the same free deck cycle by another route.

`hand` is appended to in exactly one place in all of `scripts/`, `draw_cards()`, and every
one of the seven routes into hand goes through it: `start_turn`'s base draw, Keen Lens's
`extra_draw`, Scholar's Lens on turn start, a card's own `eff_draw()`, Field Kit on cards
played, Bone Charm on kill, and Foresight. Retained cards are not a draw and count against
the cap next turn by construction.

**"A card created into a full hand goes to the discard" was not implemented, because it has
no subject** — nothing in this game creates a card into hand. An unreachable branch is a
claim nothing can check, so `draw_cards()` says in a comment that it was considered and why
it is absent, rather than leaving the next reader to wonder whether it was forgotten.

The loss is surfaced: `Hand full at 10 — 3 draws stay in the pile.`, appended to the same
returns `combat.gd` already logs. Slay the Spire shows nothing here, but a player with Keen
Lens equipped whose draw silently stops happening is paying for a relic that quietly
stopped working, and this game's register is legible consequence.

## The rebalance was asked for, measured, and turned out not to be needed

The instruction was to cap and then rebalance, on the reasoning that a cap must lower
delivered power for draw builds while `power_ratio` keeps charging for it. **The
measurement contradicts that, and the change was not made.**

**A noise floor was established first**, by running `sim_balance.gd` twice on *unmodified*
code from two trees — the sim does not seed its RNG. Two runs of identical code: mean +0.4
pts across 34 cells, range −5 to +15, one cell ≥10 (Thorns/The Maw swinging 50→65 on
fights-avoided alone).

Baseline → capped, same 34 cells: **mean +0.0, range −6 to +3, zero cells ≥10.** The effect
of the change is smaller than the instrument's own variance between identical runs. No
dungeon changed which line of play wins.

## The finding that matters more than the cap: the instrument is blind to the subject

Instrumented counters in `draw_cards()` (added, measured, removed):

| | shipped 12 profiles | a real draw build |
|---|---|---|
| draws refused by the cap | 716 of 1,029,286 = **0.07%** | 121,622 of 1,440,005 = **8.4%** |
| turns with ≥1 refusal | **0.20%** | **35.5%** |
| fights with ≥1 refusal | **0.81%** | **76.9%** |

Ten is reachable and for a draw build it binds one turn in three. `tools/sim_balance.gd`
cannot see any of it, because **no profile in it holds a draw relic** — not Keen Lens, not
Scholar's Lens — and of the eleven cards that draw, two appear anywhere in the twelve decks.
The tool this project trusts for every tuning decision was blind to the mechanic being
changed, and would have reported "no effect" for a change that fires on three quarters of a
draw build's fights.

So the missing profiles were built (a temporary subclass overriding only `_profiles()`, run
against both trees, deleted) with each one the report's own **Mid** deck plus something, so
every row has a known 98-100% neighbour. **13 of 15 lens-bearing cells moved UP** (sign test
p ≈ 0.007); six control cells scatter −4..+5. Draw-heavy at The Foundry 71→88, draw+retain at
The Sunken Vault 45→61.

**The cap did not lower delivered power. It raised it** — and the mechanism is visible in the
turn counts, which fell (Draw-heavy Foundry 7.8 turns → 6.3). `_play_draw` plays every draw
card it can afford every turn, so a smaller hand means fewer draw cards to burn energy on,
which means shorter fights and less escalation damage. The greedy policy was over-drawing and
the cap incidentally corrected it.

Repricing draw *down* in `power_ratio` would therefore have been a straight buff fitted to a
hypothesis the instrument contradicts, stacked on an already-neutral-to-positive change. That
is precisely the D109 shape — an analytic retune with no measured need, which goes green on
`test_balance.gd` and is wrong. `tests/run.sh` is 37/37, and per D109 that is not offered as
evidence about balance.

## A pre-existing pillar violation, found and deliberately not acted on

Clean A/B, identical 17-card deck, only the two draw relics differing: Keen Lens + Scholar's
Lens take `power_ratio` from 6.60 to 7.22 — **+9.4% enemy scaling** — and the build clears
*less* (Sunken Vault 86% without them, 67% with; 90/75 after the cap). **Priced power exceeds
delivered power for the draw relics**, a violation in the opposite direction to the usual one,
pre-existing and unchanged by this decision.

Not acted on, and the reason is the same instrument problem: the policy weakness that makes
the cap look like a buff is the weakness that makes draw look worthless. Both readings come
out of a simulator that plays draw cards greedily and gets nothing from card selection.
**The next lever is `sim_balance.gd` itself** — put a draw profile with both lenses in the
shipped table, stop `_play_draw` spending energy on draw it cannot use, and re-measure the
relic price then. Repricing a relic against a policy that cannot play it is how D109 happened.

## The nine-card hand was showing 7px names, and the threshold is the wrong shape

D117 set `CARD_NAME_MIN_W` where the name-length curve crosses one name in ten: 34px. That
left a **nine**-card hand at a 36px slot — just above the line — so the swap did not fire and
its names rendered at **7px**, the exact defect the swap exists to prevent. Nine was always
reachable, and the cap makes it the *modal* large hand: a card's own draw resolves while the
card is still in hand, so playing a draw card out of nine leaves nine, not ten. Found by
running the suite red, not by reasoning.

37 closes that case. **It does not close the next one, and this is a patch on a wrong shape:**
an eight-card hand has a 43px slot, above 37, and still cannot name 82 of the 100 cards at
the floor. No single width can fix that, because the test is per-NAME — "Jab" needs 22px,
"Something Worse" needs 119 — so every width is right for some names and wrong for the rest.
The honest rule is a floor on the *rendered* size: swap when the fitter would have to take
this card's own name below what can be read. That changes the five-card hand for long-named
cards, which is a visible design decision rather than a bug fix, so it is recorded and not
taken.

## Two tests were already broken and the cap exposed one of them

`tests/test_relic.gd`'s Bone Charm ON_KILL check was **vacuous and inverted before this
change**: it measured the hand *before* appending the killer, so `hand.size() == hand_before`
after the play arithmetically demanded the relic draw nothing — and it passed because a
redundant second `start_turn()` drew the ten-card deck dry, leaving the hand at exactly ten,
which the cap then refused on its own. Two independent reasons to pass and neither was the
relic working. Both preconditions are asserted now instead of assumed.

`tests/card_text_test.gd`'s eleven-card guard went red as designed. It was re-aimed rather
than lowered: the supply arithmetic is still added up from content (5 + 1 + 2 + 4 − 1 +
Foresight 1 = 12) and is now asserted to **exceed** the cap, so a relic retuned to nothing
goes red instead of quietly measuring a smaller hand, with delivered asserted as
`min(cap, supply)`. Foresight is equipped *because* of the cap — a card's draw counts against
its own cap, so the only thing that fills a hand to exactly ten is a draw arriving with
nothing in flight.

The cap's own test covers the half a careless implementation gets wrong: not just that the
draw is skipped, but that `draw_pile` is unchanged with the same card still on top, and that
`discard_pile` did not grow. Proved non-vacuous three ways — discarding the refused card,
`>` for `>=`, and dropping the notice — each watched red and restored.

---

### D121 — The card illustrations were installed, correct, resolved, and zero pixels wide

Asked to check where the generated art had actually landed, because the screens looked
wrong. Two separate failures, and neither was visible from the filesystem — which is
the point worth keeping.

#### The card art was drawn into a control with no size

Twelve family illustrations installed at 320x240, correctly named, and
`PixelArt.card_art()` returned the right texture for every card. The combat capture
still showed a black picture band. Measured, the band read **0.0533 mean luminance
against source art at 0.302** — and 0.0533 is exactly `Color(0.06, 0.05, 0.08)`, the
`bed` ColorRect the picture is supposed to sit on top of.

Dumping the built tree found it:

```
@ColorRect@15   (bed)      rect=S: (134.0, 101.0)
@TextureRect@16 (picture)  rect=S: (0.0, 0.0)    tex=CompressedTexture2D (320, 240)
@TextureRect@17 (scrim)    rect=S: (134.0, 101.0)
```

Right texture, visible, zero-sized. **`set_anchors_preset()` does not resize a
control** — with `keep_offsets` false (the default) it rewrites the offsets so the
control keeps the rect it currently has. Called on a control created two lines earlier,
that rect is 0x0, and the anchors then hold it at zero against a parent of any size.
The bed and the scrim either side of it escape only because they are preset BEFORE
`add_child`, when there is no parent rect to preserve against. One call is
`set_anchors_and_offsets_preset` and the band goes 0.0533 -> 0.400.

This branch had never run. It was written in D104 for art that did not exist until
today, so the first illustration to arrive was the first test the code path ever had —
exactly D118's shape, two days apart: **a route with no traffic is not a working route,
it is an untested one.** Both were found by looking at the game rather than at the
files, which is D56 for the umpteenth time.

#### The relic icons have no code to display them

Six installed at 128x128, matted, verified at their display size — and nothing in
`scripts/` reads `assets/art/relics/` at all. There is no `Icons.relic()`, no
`PixelArt.relic_art()`, no reference. The Relics screen renders exactly as it did
before they existed: five rarity headings and thirty text rows.

**Fixed the same afternoon.** `PixelArt.relic_art()` mirrors `enemy_art` — keyed by id,
null when unpainted — and the relics screen puts the icon in an HBox beside the name,
which is the shape it was written for ("when the thirty paintings land they go in the
cell beside the name and nothing else here has to move", D116). A relic with no art adds
no icon and no gap, so a half-painted set is a list with pictures appearing in it rather
than a list of holes.

**And that immediately broke the property the screen is tuned around.** An HBox is as
tall as its tallest child, so the icon sets the grid's pitch: at 34px the thirty slots
no longer fit 720px and the Legendary group fell off the bottom behind a scrollbar — the
one virtue the empty state has, and what `HEAD_LEADING` exists for. Rendered at three
sizes and read the scrollbar column: 34 scrolls, 26 scrolls, **22 does not**. The first
comment written for that constant asserted 34 was safe *because it sounded right*; the
capture said otherwise, which is the D56 rule applying to a number rather than a picture.

**The art-coverage question is not "is the file there".** `art_manifest.gd` counts a
relic as *present* because it stats the path, and it is right to — that is what it
measures. But "present" and "reaching the screen" are different claims, and the
manifest's 135-present figure quietly asserts the first while reading like the second.
ART.md §4 has asked for the render call since it was written; the icons are now waiting
on it rather than the other way round.

### D122 — The art that shipped as a placeholder and read as finished

Fifty-one images were outstanding. Twenty-three landed this pass — the last relic, three
dungeon backdrops, the seven intent telegraphs, two status symbols, ten power sigils,
the targeting reticle, and four Tier 7 files. What that clearing exposed is the decision
worth keeping: **the manifest's re-roll list could only see files that were missing, and
the worst art in the game was not missing.**

**`REDO` was built for exactly this and still nearly missed it.** Its own comment says
"the moment something lands, correct or not, the sheet stops mentioning it". Tier 2
printed *all 35 present* for thirty-five enemy combat plates that are procedural
silhouettes out of `gen_enemy_art.gd` — measured luma 0.17–0.23, flat interior behind a
one-sided rim light. They were the right call when they landed: they replaced 41
unlabelled 16x16 tiles handed out by sort order, where a boss was whichever tile the
index fell on. But a placeholder that reads as finished is worse than an empty slot,
because an empty slot is on a list. Same story for the twenty-three files standing on
the isometric floor, now Tier 8a/8b.

The iso numbers are the ones that decide priority. Every figure reads 0.16–0.21 against
floors of 0.43–0.49 — **2.5x darker than its own ground**, so the eye takes it for a
hole in the floor rather than a person on it. `hero_s` and `mon_caster_s` overlap 81.9%
by silhouette, which `gen_iso_markers.gd` admits in its own comment ("told apart by
hue") and which at 0.20 on a 0.45 floor is not a distinction anybody can see. Worst:
`combat`, `elite` and `boss` are **100% identical silhouettes**, separated by hue alone.
The floor is where you choose what to walk into, and it cannot answer the question.

Thirty-five identical `REDO` lines would be noise, not thirty-five findings, so
`REDO_DIRS` carries a defect that belongs to a whole family. It is consulted *after*
`REDO`, never instead of it — the three iso fight markers and the caster each carry
their own worse fault on top of their family's, and would lose it to a flat rule.

**Enemies were hovering, and it was not the enemies.** Reported as an art bug. Every
sprite has its feet exactly on the canvas bottom — 0.0% empty below the lowest painted
pixel, all thirty-five, measured. The fault was two decisions that never met: the Tier 5
brief asks every backdrop for "foreground framing elements at the left and right
thirds", and `_place_slots` spread enemies over the full width at `vp.x * (k+1)/(n+1)`,
which puts two enemies at **exactly** x=1/3 and x=2/3. They stood on the pillars and the
braziers, at the height of the *centre* floor, because `STAND_LINE` is one number for a
frame whose floor is not one height. `STAGE_INSET = 0.20` keeps the cast in the middle
60%. Only the flanks were ever wrong, which is why a year of single-enemy captures never
showed it.

**A harness is only as honest as its list.** Three of the four iso terrains had never
been photographed — every capture enters `DUNGEONS[0]`, which is the Crypt, which is
`stone` — so a fault in `earth`, `moss` and `sand` was invisible to the one tool whose
job is seeing. `tests/test_art.gd` already said this out loud: "whether a specific enemy
hovers is a question for `tools/screenshots.gd`, where you can see it". It was, and
nobody had looked. Added `IsoEarth`/`IsoMoss`/`IsoSand` and a `CombatGroup` capture —
`ember_hound` because `count_min` and `count_max` are both 2, so it frames the same
fight every run instead of a coin flip.

**Three tool contracts were wrong in the same shape: right once, for the batch they were
written for.** `install_backdrops` walked its own table and printed MISS for every row
the folder did not answer — correct for one delivery of nine, six failures and a
non-zero exit for a re-roll of three; it now installs what the directory *has*.
`strip_sparkle` demanded four frame-sharing images when a re-roll is three; the count
was never what protected the art (the compactness bounds and the `--dry` mask preview
are), so it is three. `install_sheet` passed `anchor_bottom: false` because every set it
had ever seen was an icon, and an icon is centred — an isometric figure is placed by its
bottom edge, so it would have hovered by whatever margin the trim left above its head.
`install_cutouts` already knew this for the `enemies` family. The two tools disagreed
only because no footed set had ever arrived on a sheet.

**What failed.** The title-art re-roll did not fix its defect. The prompt led with the
fault and named the ink outline six times; the result visibly carries contour lines and
still measures **1.2%** on D114's own metric — identical to the file it replaced, below
`bg_crypt`'s 3.2%. It is installed, the superseded `.jpg` is gone as D114 designed, and
it stays on the re-roll list.

**The obvious excuse was tested and does not hold, which is why it is written down.**
D114's threshold is a fixed 0.08 luminance delta, and the title art is a moonless ridge
at night — so the reasonable suspicion is that the metric was reporting *darkness*
rather than *absence of ink*, and that re-rolling against it would be chasing the wrong
fault for a second time. Measured: each image's luminance stretched to fill 0..1 across
its own 1st–99th percentile, then the identical test re-run. Normalised, `main_menu`
scores **3.6%** against 5.1–15.4% for the dungeons — still the lowest of the set, still
below `bg_warrens` and `bg_crypt`. Its 1st–99th span is 0.469 against the dungeons'
0.511–0.650, so it is barely more compressed than they are and the compression cannot
account for a 3x gap. The picture is genuinely under-inked and the metric is sound.

Two things fall out of that control run and are worth keeping. `bg_warrens` scores 2.1%
absolute, under the 2.8–12.2% band D114 quoted, and 5.1% normalised — comfortably inside
the dungeon spread, so it is fine and the absolute number merely under-reports a dim
room. And `ui/boot_splash.png` lands at 1.3% / 4.7% with the narrowest span in the set
(0.410); it is a lantern in the dark and meant to be, but it is the next file this metric
will flag, and it should be judged on a render before anybody re-rolls it.

**After the quota reset, the tier was painted and every number moved.** Twenty-three
Tier 8 files in three sheets, plus three of the four meta-screen backdrops D123 asked
for. What they were listed for, measured before and after: figure luma **0.16–0.21 →
0.25–0.49** against floors of 0.43–0.49, so a figure is on the ground rather than a hole
in it; `combat`/`elite`/`boss` silhouette overlap **100% → 17.6% and 25.6%**, so the
floor can finally say whether the room ahead is a trash fight or the thing that ends the
run; hero-vs-caster **81.9% → 41.8%**, two characters instead of one tinted twice. All
twenty-three measure 0.0% empty space below the feet, which is what the new
foot-anchoring in `install_sheet.gd` is for.

**Two sheet defects worth knowing, because both look like a bad drawing and are not.**
A generator asked for evenly spaced subjects drifts — by up to a quarter of a cell — so
a wide subject crosses its boundary, the neighbour bleeds into the next cell's border,
and `Cut.cut` refuses it with "background is not flat". The border genuinely is not; the
art is fine. `respace.gd` finds the real gaps (columns that are entirely field), cuts
each subject at its own bbox and re-emits them evenly, so the equal-cell reader is
correct again and the mapping stays positional. Separately, a sheet drawn as rows can
come back with faint horizontal BANDS in the background, one per row, and a cell
straddling a band edge fails the same check — `flatten_bg.gd` repaints every pixel
within tolerance of its own row's background to one colour, which cannot reach the
drawing because a subject pixel is nowhere near the field colour. That is the premise
the matte already runs on.

**The `_s`/`_n` pairing is the thing that cannot be generated one file at a time**, and
one row proved it: asked for a scuttling creature and the same creature from behind, the
right cell came back as an unrelated human in a tunic. The two facings have to be one
drawing seen twice or they are two characters. Two sheets of eight beat one of sixteen —
the failure is per-cell, and `--only` plus `--cells` installs the survivors without
re-rolling the good ones.

**Never tell the generator WHY a rule exists — it draws the reason.** Twelve enemy
plates came back clean from a prompt that said "keep the lower body and feet darker".
The next sheet said "keep the lower body and feet darker, *because these sit on a
brightly lit stone floor*", and every one of the six came back standing on a lit stone
floor. Same class as D101 and D119, and the third time this project has paid for it: a
prompt is not a place to explain yourself, because every noun in it is a thing that can
be drawn. The rule goes in the prompt; the reason goes in `ART_ASSETS.md`, which is the
split D101 already established and which this violated by hand rather than through the
manifest. Tier 2's recipe now carries the no-ground clause as a bare instruction.

**The title art was fixed by changing the SUBJECT, and the measurements are what found
that.** It had been on the re-roll list since D114 for carrying no ink outline, and two
re-rolls of the same picture each came back at ~1.2% against 2.8-12.2% for the dungeons
— the second visibly hatched and still measuring worse than the file it would have
replaced. Two explanations were tested and both died: normalising each image to its own
1st-99th percentile (3.6% against 5.1-15.4%), and setting the threshold to 0.75 local
sigma instead of a fixed 0.08 (4.7% against 8.8-12.8%). That left the subject. The
dungeons are near-field architecture where every form is close enough to outline; the
title was a night exterior receding into haze, and haze cannot carry a contour line.

Re-composed CLOSE-UP — same traveller, same cyan flame, but everything within a few
paces and the tower seen between near trunks instead of across a valley — it measured
**13.8%** on the first try, above the entire dungeon band. Three more rolls to hold the
other two constraints at the same time, because fixing one broke another each time: the
bright gap behind the tower blew to pure white (1.06% of pixels over 0.90 against
bg_crypt's 0.20%), and killing that overshot into a 0.107 mean when the band is
0.20-0.35. The installed file reads **10.5% ink, 0.307 mean, 0.029% over 0.90** — inside
every one of D114's three criteria and cleaner on white than the style bible.

Worth stating plainly because it is the cheaper lesson: **four attempts at the same
picture would never have worked, and the numbers said so after the second.** When a
re-roll fails twice on the same measurement, the thing to change is the brief, not the
seed.

**And the trap caught me one more time.** The first close-up prompt said the left third
must stay quiet "because a column of menu text goes over it" — and the picture came back
with MENU, START, CONTINUE, LOAD GAME, OPTIONS, QUIT painted into it. That is the same
rule as the enemy plinths, one hour later: every noun in a justification is a thing that
can be drawn.

**On capture.** Autocropping a screenshot against a black overlay is right for a cutout,
whose subject sits on a field the generator never paints pure black. It silently eats a
*scene*: the boot splash falls away into darkness at its own edges and came back 1.616
against the 1.790 it was drawn at. The picture still installs — it is just cropped. So a
scene is cropped by the rect read off the page (`getBoundingClientRect()` scaled by
screenshot width over `innerWidth`), not by a luminance guess.

### D123 — Twelve screens with no painting, and four places between them

`UI.screen()` resolves a backdrop from an explicit path, then a scene id, then a zone
id, and falls through to `PixelArt.backdrop()` — the procedural tiling pattern — when
it is handed none of the three. Twelve screens handed it none: glossary, powers,
builds, settings, deck builder, overworld, packs, pause, collection, starter kit,
relics, save slots. Every navigation screen in the meta layer, which is most of the
game outside a fight.

#### Twelve screens are not twelve places

The obvious shape is one painting per screen and it is wrong twice. It asks for twelve
paintings where four do the work, and — the part that matters — it asserts twelve
different PLACES when the fiction has four. The deck builder, the collection, the
builds tracker, the packs screen and the starter kit are one action seen five ways:
you are stood at a table with your cards out. Giving each its own room says they are
five errands in five places, which is not what the meta loop is. Relics and Powers are
the same claim — this is what you have earned and cannot lose — and they are already
each other's sibling in code, two read-mostly lists off `MetaState`.

So: `bg_table.png` for five screens, `bg_reliquary.png` for two, `bg_ledger.png` for
the three that are the game's own machinery rather than the character's (how it works,
which save, which settings), and `bg_world.png` for the hub. The full argument, and
the cost of sharing, is in `META_BG` in `tools/art_manifest.gd` rather than restated
here, because that table is what the prompt sheet is generated from.

The cost is accepted rather than unnoticed: five screens look alike. They each carry
their own title and their own list, so the backdrop is the thing they have in common
and it is TRUE that they have it in common.

#### The pause menu needed no painting at all

Pause is only reachable inside a run, so there is always a zone, and all five zone
establishing shots are already installed. It now passes that zone to `UI.screen()`.
That is not a fifth grouping, it is D115's defect in a new place — art on disk that
nothing read. D96 rejected a zone shot on the **Overworld** because the Overworld
already draws the same picture as a thumbnail in the list under it; nothing on the
pause screen draws a zone.

#### The Overworld is the one reversal, and only half of one

D96's `no full-bleed painting here` comment reads as a decision against backdrops on
that screen. What it actually rejected was reusing a ZONE SHOT: whichever zone it
picks already has a thumbnail below it, and at `ZONE_DIM` that shot's bright band ran
under the sealed rows' prose. Both halves of the objection are about art composed for
somewhere else. `bg_world.png` is painted for this screen — a gateway looking out,
with **nothing beyond the arch that resolves into a place** — specifically so it
cannot compete with the five establishing shots stood in front of it.

#### The composition constraint is different from Tier 5c, and it was measured

Tier 5c is composed for a shop or an event: prose in the top half, framed buttons
below, so half the frame has nothing written on it. These twelve are lists, and that
was checked rather than assumed. Rendering seven of them at the shipped 1280x720 and
taking the topmost and bottommost row carrying a pixel over 110/255:

```
Overworld   rows  24..688      Relics     rows  24..684
Collection  rows  24..684      Glossary   rows  24..684
Packs       rows  24..684      DeckBuilder rows 24..688
Powers      rows  24..684
```

**3% to 96% of the frame height, on all seven.** The threshold has a four-times margin
under it: the brightest pixel in a 210x100 empty patch of the tiling backdrop measures
26/255, so what this counts is UI ink and not the background it sits on.

Meanwhile `UI.screen()` scrims the top of a scene backdrop nearly opaque and fades it
out about two thirds down (`SCENE_HOLD`/`SCENE_END`), leaving a light flat dim below.
So the picture only really SHOWS in the bottom third — and the bottom third is where
the rows are. The subjects are written against that: light source and everything worth
looking at in the upper third where the scrim holds it back, and the bottom half one
continuous surface at one even value with no object, no edge and no highlight crossing
it. **This is the one thing about the tier that a generator cannot infer and that a
wrong answer makes unusable**, which is why it is in the recipe as a measurement and
not as an adjective.

What is deliberately NOT decided yet: whether `SCENE_DIM` is heavy enough under a full
column of list rows, or whether these four want the zone screen's flat `ZONE_DIM`
instead. That is a contrast question, contrast questions here are settled by measuring
the worst pixel under a row on a render (D96, D116, D121), and there is nothing to
render yet. Guessing a constant now and writing "measured" beside it is the habit D109
is about.

#### Wired before the art, on purpose

All twelve now pass their id. `UI.screen()` already degrades to the procedural
backdrop when the file is absent — confirmed by capturing seven of them after wiring,
all unchanged and all still 1280x720 — so this costs nothing and closes the gap that
D115 and D121 are both about: `assets/art/relics/` and `assets/art/powers/` were
installed correct and completely unreachable because no code loaded them. Installing
art and wiring art are two jobs, and the one that can be done first is the wiring.

The ids are also in `PixelArt.SCENE_ART` and in `install_scene_backdrops.gd` — the
first because that list is what `tests/test_art.gd` walks for the dungeon-id collision
and the 1280x720 install size, so an id kept out of it is an id nothing checks; the
second in its own `META_MAP` rather than in `MAP`, because a missing source in `MAP`
fails the run. That is right for the six Tier 5c backdrops, which were commissioned
and delivered as a set, and wrong for four that will land one at a time.

### D124 — Two formulas were charging for draw and disagreeing by four times

D120 left the draw relics knowingly mispriced and refused to fix it, because the
simulator's policy could not play a draw build: `_play_draw` played every draw card it
could afford, unconditionally, before anything else. Repricing a relic against a policy
that cannot play it is how D109 happened. This fixes the instrument first, then prices.

## The policy, and the first attempt that had no subject

Shipped rule: **buy draw only when the HAND is the bottleneck, not the energy.**
`end_turn()` discards the hand, so a card drawn and not played is thrown away rather than
banked — a draw card is worth its cost only if what it fetches can still be played.

The first attempt exempted any card with a body (damage, block, energy) and gated only
"pure" draw. It sounded principled and **refused nothing**: instrumented over a draw-heavy
profile it evaluated 1,498 draw plays and declined **zero**. Every card in the catalogue
whose only effect is draw costs *zero* energy, every paid draw card has a body, and Clear
Mind is not even pure draw — it grants Dexterity, so `_play_powers` takes it before
`_play_draw` ever sees it. A full report with that gate moved the mean −0.1: a no-op
wearing the shape of a fix. **It was caught by counting how often the new branch fired**,
which is the cheapest check there is and the one that was missing.

Bake-off over 10 cells and 5 draw-holding decks, 400 trials, identical code otherwise:
greedy **68.6**, body-exempt **69.0**, uniform **72.8**.

## Recalibration — the instrument moved, and the game was NOT re-tuned to match

Kept deliberately apart from any balance number, because a better simulated player clears
more and that must not be read as the game getting easier.

Noise floor, identical code: ±0.2 to ±0.3 mean, one cell swinging 12. Greedy → gated:
**mean +2.7 over 36 cells, range −17 to +53, five cells ≥10.**

| profile / dungeon | before | after | Δ |
|---|---|---|---|
| Draw build / The Foundry | 44.0 | 97.0 | **+53.0** |
| Endgame / The Abyssal Stair | 10.0 | 39.5 | **+29.5** |
| Endgame / The Maw | 18.5 | 40.5 | **+22.0** |
| Draw build / The Sunken Vault | 82.0 | 65.0 | **−17.0** |
| Thorns / The Maw | 68.0 | 55.0 | −13.0 *(that cell's own noise is ±12–17)* |

**The Endgame profile reading 10% and 18.5% was never difficulty — it was the greedy pass
burning its turn on block-that-draws.** Two numbers this project has been reading as "the
endgame is brutal" were an artifact of the driver. Nothing was re-tuned to claw any of it
back; the numbers are the instrument telling the truth for the first time.

`tests/test_balance.gd` is unchanged and green. It never invokes the simulator — it opens
`sim_balance.gd` as *source text* and asserts the tool models the equipped Power, the boss,
reward cards and the clears gate, none of which a driver change touches.

## The pricing bug: one effect, two formulas, 4x apart

With the instrument fixed, the lenses still cost the player 12.1 points of run completion
across 8 cells while charging +9.4% enemy scaling. The cause was not a value that needed
nudging, it was **two different formulas pricing the same effect**:

- `extra_draw` (Keen Lens, every turn) went through `throughput_multiplier`, `1.0 + 0.08 × draw`
- a triggered draw (Scholar's Lens, every third turn) went through the additive
  `triggered_power`, at `2 × DRAW_VALUE × 4/3 = 4.0`

Charging the same thing two ways is the D34 habit in arithmetic. `extra_draw` now prices
additively at the rate the game already uses everywhere else — `1 × 1.5 × TARGET_NORMAL_TURNS
= 6.0`, i.e. **+0.12 ratio** against Scholar's **+0.08** — which is derived from the
existing constants rather than fitted to a target. `DRAW_VALUE` is named in `balance.gd`
where tuning belongs.

The argument for additive is a fact about this game's shape: **draw is not throughput here.**
`HAND_SIZE` 5 against `MAX_ENERGY` 3 means the hand already holds more than the turn can pay
for, so an extra card buys *selection* — a flat per-turn gain — not more actions.

Price 6.60 → 7.22 (+9.4%) becomes 6.60 → 6.80 (+3.0%). Delivered went −12.1 → **−7.0**,
confirmed at −6.75 on a clean re-run. The balance table for the reprice alone: mean +0.1,
range −4.5 to +5.5, **zero cells ≥10**, with the single directed cell being Draw build /
Sunken Vault 65.0 → 70.5 — the one profile holding Keen Lens, which is the containment
check.

## Why it stopped at −7 instead of driving the gap to zero

A diagnostic run with the lenses priced at **zero** still measured **−5.75**. With enemy
stats *identical*, the relics still cost completion, and fights get *longer* (Mid/Foundry
3.5 → 3.8 turns). So the residual is not price at all: a bigger hand feeds
`_block_incoming`, which over-blocks, which lengthens the fight and takes more escalation
damage. Pricing draw below the derived figure to cancel that would be fitting a price to a
driver artifact — D109's exact shape, one layer down.

## Found on the way, reported, deliberately not fixed

- **`_block_incoming`'s tolerance is 8% of max HP** — at the Sunken Vault it eats up to 9.6
  damage a turn rather than spend a card. The greedy `_play_draw` was masking it; gating
  draw exposed it, and it is the whole of the −17. Re-pitching it is its own policy change
  with its own recalibration.
- **`DRAW_VALUE = 1.5` is now stated three times** — the new named constant, plus literals
  in `CardData.power_value` and `RelicData.triggered_power`. Two are outside this change's
  scope; the constant is named and the duplication written down rather than left silent.
- **`RelicData.power_value()` prices `extra_draw × 14.0`** for shop gold, against the 6.0
  now used for scaling. Different currency, so not necessarily wrong — but the two should
  be reconciled deliberately rather than by coincidence.
- **A genuinely draw-dense deck is unplayable**: 11 draw/defence cards around 4 attackers
  clears 0% at both dungeons with 13-turn normal fights, under *all three* policies. That
  is a content fact, not a driver one, and it is why the new shipped profile keeps Mid's
  attacking spine.

### D126 — The title art's subject was never the problem; the foreground was

D122 concluded that the title screen's SUBJECT could not carry the ink density the
dungeons set: they are near-field architecture where every form can be outlined, a night
exterior recedes into haze, and haze cannot take a contour line. It re-composed the
picture close-up on that basis, measured 13.8%, and the number backed the story up.

The story was wrong, and it was wrong in the way a plausible one usually is — it
explained the evidence without being tested against the alternative. The wide vista
scores 1.2% not because it is wide but because the earlier attempts painted the NEAR
ground as softly as the far. Asked again for the same vista with the near third treated
as a pen-and-ink plate — every boulder, the ledge, the traveller, the near firs given
thick unbroken contours and cross-hatching, and only the far ridge and sky allowed to go
atmospheric — the same composition measures **8.6% / 10.6%**, inside the band, seven
times the old file, with the cleanest whites of any candidate (0.007% over 0.90).

So the rule is not "this subject cannot be inked". It is: **in a wide view, ink density
comes from the foreground, and a picture whose near ground is as soft as its distance
has no linework anywhere.** D122's close-up worked because everything in it was near,
which is a special case of the same rule rather than a different one.

Recorded because the user asked for the wide version back and the honest answer was
that my recorded reason for abandoning it did not hold. The measurement that convicted
the subject was real; the inference from it was not, and a re-roll aimed at the actual
variable settled it in one attempt.

### D125 — Quiet is not empty, and four backdrops were filled in rather than painted

Four meta-screen backdrops shipped with their lower halves as flat rectangles. It hid
under a full list and was glaring on Packs, which is sparse: the bottom 60% of that
screen was a grey slab with a hard seam across the middle of it.

**The brief asked for it.** D123's Tier 5d recipe said the lower half must be "ONE
continuous surface at one even value ... with no object, no edge and no highlight
crossing it", and the per-image prompts went further with "no grain that changes value".
That is a description of a fill, and a generator delivered one. What these screens
actually need is QUIET — nothing an eye stops on, nothing competing with a row of text —
and quiet still has tooth. The recipe now says so, and says it twice, because the first
half of the sentence is the part that reads as permission to flood.

**The reviewer's symptom was right and the cause was not.** It was reported as a crop
artifact — `install_scene_backdrops.gd` cropping to 16:9 and dragging pad along. That is
not what happened: the sources were cropped by exact rect at aspect 1.790 and the
installer *strips* letterbox rather than adding it. The flat region was in the generated
art. Worth recording because the fix that follows from the wrong cause — adjusting the
installer — would have changed nothing and left four bad paintings on disk.

**Finding a measurement that catches it took three attempts, and the first two are the
instructive ones.** Counting rows with zero horizontal variance catches `bg_reliquary`
(49%) and `bg_ledger` (48%) and MISSES `bg_table`, whose dead half is filled at 0.021
rather than at nothing. Thresholding the bottom half's texture on its own cannot work
either: `bg_shop` legitimately bottoms out at 0.016, the same neighbourhood. Restricting
either to the lower half helps but still cannot separate a quiet painting from a quiet
fill, because *level* is not what distinguishes them.

The DROP does. Mean row-variance in the top half against the bottom half:

```
bg_table      0.104 / 0.021   4.9x        bg_crypt    0.069 / 0.107   0.6x
bg_world      0.145 / 0.015   9.9x        bg_shop     0.061 / 0.053   1.2x
bg_ledger     0.101 / 0.003  40.4x        bg_event    0.058 / 0.087   0.7x
bg_reliquary  0.094 / 0.002  49.9x        main_menu   0.160 / 0.174   0.9x
```

Broken 4.9–49.9, legitimate 0.4–1.2. `tests/test_art.gd` asserts on it at 3.0 with a
texture floor underneath for the degenerate case a ratio cannot see. Unlike the
floor-fraction heuristic in the same file, this one is not a judgement call and is safe
to assert on: paint always has tooth, and fill never does.

All four re-rolled against the corrected brief and measured after: 1.0, 1.3, 1.6, 2.8.
`bg_event` is the case that proves the check is aimed correctly — it is 17.6% flat rows
overall and passes, because its flat rows are a night sky at the top and a dark strip at
the bottom rather than a slab where the list sits.

### D125 — Three shipped files were nine-tenths transparent and looked perfect in a file browser

A look through all 24 screens at a true 1280x720 after the art batch landed, then four
parallel fixes. The look found more than the fixes did.

## The matte silently gutted the Tier 7 art

`install_chrome.gd` specced `logo`, `cursor` and `cursor_press` with `matte: true`. All
three are **dark subjects on a near-black field**, which is the one case a border flood
fill cannot key: the subject sits inside `TOL` of its own background, so the fill walks
through it and `despeckle` then keeps the largest surviving island and discards the rest.
It does not fail. It returns a plausible file.

Measured, opaque against non-black RGB:

| file | opaque | RGB present |
|---|---|---|
| `ui/cursor.png` | **9.4%** | 93.9% |
| `ui/cursor_press.png` | **12.6%** | 93.9% |
| `ui/logo.png` | **44.0%** | 74.8% |

Nine tenths of the cursor was there in colour and invisible; what shipped was the
highlight hairline, a pointer that vanished over the title art. The logo kept its flat
inner panel and lost **every piece of carved scrollwork**, which is the entire reason the
asset exists. **Both look correct in an image viewer** — the RGB is untouched — which is
why this survived generation, installation, a re-roll and a commit.

The repair is `lumakey`: alpha from luminance, geometry untouched. Deliberately not the
existing `glow` mode, which trims to the ink and re-fits — `pointer.gd` pins its hotspot
to the spike's tip in image coordinates, so re-framing would move the point the player
aims with, and recovering alpha is the whole job. Afterwards opaque tracks the artwork to
two decimals: cursor 9.4% → **93.85%** against 93.85% RGB, logo 44% → **74.95%** against
74.80%. The sources were gone from `~/Downloads`, so this ran on the installed files
themselves — possible only because the matte destroys alpha and leaves colour alone.

**The wider lesson is about which failures are loud.** `BORDER_AGREE` refuses a
subject-in-a-room and says so; `MIN_COVER`/`MAX_COVER` refuse a matte that ate the subject
or found no background. This case passed all three — 9.4% coverage is above `MIN_COVER`'s
2% — and the only signal was `dropped_islands`, which the tool prints and nobody read.

## The boot splash shipped the generator's watermark

Not a matte problem: `boot_splash` is `matte: false` and correct, and it carried the
four-point sparkle at 110px in from the right — the brightest thing in the lower half of
the **first image anyone sees**.

Stripping it needed a new lever. `strip_sparkle.gd` finds the stamp by intersecting "lit
above local background" across images, so **the least-contrasty frame in the batch decides
how far the mask reaches**. Keyed against bright square generator output, a near-black
splash yielded the stamp's 53x45 core and left its halo behind — and a soft pale smudge on
a boot splash is worse than the crisp star it replaced. `--grow=` overrides the default 8;
at 22 the mask is 81x73 and the corner comes out clean. The default is untouched, because
it is right for a batch that shares one look; `LIT` was right both times and was not
touched either.

## Painted, installed, and read by nothing

The batch landed and the screens went on drawing placeholders past it — the pitfall AGENTS
already carries, at larger scale. Now wired: the **target ring** (combat drew a
`StyleBoxFlat` capsule), the **intent telegraphs** (combat printed `hit 6` as text), the
**card glow** as an affordability hint, the **logo**, the **boot splash**, the **cursors**,
and `divider` in the one screen that has two labelled sections.

Two of the seven intent telegraphs have **no behaviour to attach to**. `EnemyData.Action`
is ATTACK / DEBUFF_VULN / DEBUFF_WEAK / DEFEND / EMPOWER / SUNDER / ENRAGE / DRAIN — there
is no multi-hit action, and **no enemy anywhere applies Poison**; only cards do. So
`intent_attack_multi` and `intent_poison` were specified, prompted, generated, re-rolled
with the stone-tile batch, installed, and telegraph something the engine cannot produce.
The manifest's `INTENTS` table was written against a design and nothing compares it to the
enum. They are left unmapped rather than papered over with a parallel classification.

The card glow needed a measurement to work at all: its brightest band is inset 7.5% of its
own width, so at the card's rect every lit pixel lands behind the opaque frame. Solving
`inset·k = (k−1)/2` gives the spill that puts the band on the border.

## The pluralisation helper could not live where it belonged

"needs 1 clears" ships — `blight.tres` and `expose.tres` both unlock at exactly one clear.
A grep found ~90 `%d <noun>` sites and **four different idioms for one rule**: six wrong at
n=1, three using the `(s)` evasion, several correct but hand-spelled at the call site.

Putting the helper on `UI` **silently broke four headless suites**. `ui.gd` names the
`UITheme` autoload, and an autoload referenced at compile time makes every script touching
it unloadable in a `--script` run — the D19 hang, fourth occurrence. `CardFilter.summary()`
started returning `""` rather than failing. The helper is a dependency-free `Wording` class
now, with that constraint in its docstring.

## The enemy numbers stay, and the reason is the log

"Bone Picker 1 / Bone Picker 2" reads as developer output, and removing the suffix is
*safe* — nothing parses the name back, targeting is by index. It would still be wrong. The
name is the subject of **eleven sentences** in `combat_engine.gd`: `%s dies!`,
`%s hits for %d`, `Poison deals %d to %s`. With two unnumbered Bone Pickers, "Bone Picker
dies!" is a claim about the pair. Slay the Spire can drop the number because its feedback
is spatial; this game says it in prose and the log has no other handle.

The one place it does no work is the defeat screen — the fight is over, there is nothing
to disambiguate, and "Bone Picker 2 brought you down in The Crypt" is a bug report at the
game's highest-drama moment. `_killer_name()` strips the index there and only there.

## Layout, measured rather than nudged

Victory's ascension line ran across the lit doorway at **3.86:1**, under the 4.5:1 floor
`menu_art_test.gd` holds every button to — and `ui.gd`'s own `SCENE_FOOT_ALPHA` comment
claimed 3.9:1 for that line, so the scrim that existed was tuned to a number that fails. A
480-wide plate above the buttons takes it to **5.8:1**; narrowing alone would not have
done it, because the wall immediately outside the plate's edge reads 3.1:1.

Encounter's three 1244px bars route through `UI.button()` with no exception, because the
longest `choice_labels` string in the game is 34 characters — every choice lands at 480 for
free. The clipped lists in the deck builder and the overworld take their leftover out of a
frame around the scroll: **the first attempt measured `scroll.size.y`, which makes the
margin a function of itself** — trim 30px, ask again, answer is now "trim 0", fix undone
next layout. Only the capture caught it. Shop's four buttons at three x positions were two
D95 causes at once, now one row builder with a derived gutter: `before 616/616/616/556/813`
→ `after all five at 716`. Packs' "Open all" moved to the *last* row of the list, so all
three packs are read before the control that skips them.

## Coordination cost, recorded because it will happen again

A concurrent session's commit `5b7342c`, titled *"Paint the halves of four backdrops that
were only filled in"*, swept in **31 files and ~1000 lines** of this decision's work. It
also split a feature across the commit boundary by **one second**: `pointer.gd` was written
at 06:45:10 and committed at 06:45:20; the `project.godot` line registering it as an
autoload was written at 06:45:21 and missed, leaving an autoload script in history that
nothing loads. The history was not rewritten — the commit is another session's, it contains
their real work, and amending would change the SHA under a running agent. The repair is
forward, and this entry is where the code actually landed.

### D127 — The game was named after its mechanic, in a project whose own rule forbids that

`Deckcrawl` was a genre description standing in for a name. It is now **The Owing**.

**It broke the voice pillar by name.** AGENTS.md says *"Borrowed genre grammar is fine;
a borrowed proper noun is not"* — Block and Energy and intents are how the genre speaks,
but a proper noun has to come from this game's register. "Deck" is genre grammar, and the
title used it as the proper noun. Set beside what the project actually calls things —
The Grave-Sexton, The False Step, The Maw Itself, The Last Vendor, *"Cold stone and old
debts"*, cards named `old_debt`, `all_you_have`, `dead_weight`, `something_worse` — it was
the one proper noun in the tree written in a different language from everything else.
Which is the same fault as D114 one layer out: the title screen was off-register in its
words as well as its picture.

**The Owing fits the house grammar exactly.** Definite article plus one concrete noun, the
form every boss and dungeon already uses. `owe` is Old English *āgan*, so it satisfies the
plain-Anglo-Saxon rule. And it names the *loop* rather than the interface: the meta layer
is a debt — you descend, you take, winning banks it and dying forfeits it — which is what
`The Coin Press`, `The Old Bargain`, `The Cursed Hoard` and the starting zone's *"Cold
stone and old debts"* have been saying all along.

**The subtitle went with it.** The title screen read *"A deckbuilding descent."* directly
under the carved plate. Same mistake in a second place: explaining the genre on the one
surface that should be speaking in the game's own voice, on the asset (D119) whose entire
brief was to carry a title alone.

**Scope was held to the display name.** `config/name`, the title Label, and the headings
in README/AGENTS/ART/DESIGN. Bundle identifiers, build artefact filenames and the
`DECKCRAWL_SANDBOX` environment variable were left alone — they are app identity and
tooling, not what the player reads, and changing them makes installed builds look like a
different application.

**The save directory was the trap, and the first fix for it silently did nothing.** Godot
derives `user://` from `config/name`, so the rename alone moves
`app_userdata/Deckcrawl/` to `app_userdata/The Owing/` — and orphans every save with no
error, because the new directory is empty and `MetaState` reads empty as a new player. The
fix is `config/use_custom_user_dir` + `config/custom_user_dir_name`, pinning the data path
so this and every future rename is free. Two things went wrong on the way:

1. **The keys were first written fully-qualified** — `application/config/use_custom_user_dir`
   inside the `[application]` section, where the header already supplies the prefix. Godot
   accepts the line into the file, ignores it, and reports nothing; `user://` still
   resolved to `app_userdata/The Owing/`. The guard against silent orphaning failed
   silently.
2. **`use_custom_user_dir` is not a rename of the last segment.** It drops the
   `godot/app_userdata/` layer entirely, so the directory becomes
   `~/.local/share/Deckcrawl/`. The pin is therefore a MOVE and not a no-op — the live
   `save.json`, `save.run.json` and `settings.json` were **copied**, not moved, so the
   originals remain at the old path as a backup.

**`tests/run.sh` hardcoded that directory, and a wrong path there fails open.** It sweeps
`$USERDATA` for `t_*` sandbox files to prove no suite wrote over a real save. Pointed at a
directory that no longer exists, `ls` returns nothing, the check passes, and a real
regression stops being caught — the guard reports green precisely when it has gone blind.
Updated with the pin, and the comment now says which way it fails.

**Verified rather than assumed:** `user://` resolves to `~/.local/share/Deckcrawl/`, all
three JSON files parse from it under the new name, `run.sh`'s log directory lands there
(so the stray check is watching the live directory), the full suite is 37/37, and the
captured title screen shows `THE OWING` set in the cartouche with no subtitle under it.

**Found in passing, not fixed:** `DESIGN.md` has **two** `### D125` sections — *"Quiet is
not empty"* and *"Three shipped files were nine-tenths transparent"* — and `### D126` sits
above both rather than below. Three code and doc sites cite "D125" and cannot say which
one they mean. Renumbering would break those inbound references, so it is left for whoever
knows which decision came first.

### D128 — The title screen was printing the size of its own data tables

Reported as "log prints on several screens". There is no `print()` anywhere in
`scripts/` — the shipped code is clean, and grep confirms it. What the report is
actually about is on-screen text that *reads* like a log, and the named example is the
clearest case in the game.

**`main_menu.gd` printed `Cards 100   Relics 30   Dungeons 12   Zones 5`** — the sizes of
`CATALOG`, `RELIC_CATALOG`, `Balance.DUNGEONS` and `Balance.ZONES`. Not what the player
owns; **how many rows are in the game's own data files.** Identical for every player who
will ever launch it, changing only when content is added, and answering no question
anybody holding a mouse is asking. A developer's "did my content load" check, dimmed to
60% alpha and shipped. Deleted.

The test that separates the rest is: **does this line inform the decision the screen
exists to support, or is it a readout of internal state?** By that rule most of the stat
strips survive — the chest states HP, gold and keys because you are deciding whether to
spend a key; the shop states banked-versus-at-risk gold because that is the purchase; the
combat piles are card-game information. Three did not:

- **`powers_screen.gd` showed `Equipped: bulwark`** — a lowercase database key, on the
  screen whose entire subject is that power, one row below the same power written
  "Bulwark". `MetaState.equipped_power` is an id and was interpolated raw. The same leak
  D115 gave one owner for the rarity badges, in a different table.
- **`overworld.gd` led with `Slot 1`.** Which save file is open is a thing chosen two
  screens earlier and unchangeable from the world map, so it informs nothing there. It is
  bookkeeping about the *program*, not the run. The save-slots screen names it, which is
  where it means something.
- **`deck_builder.gd` ended its strip with a bare `OK`.** A hint exists to say what is
  *wrong*; a screen that congratulates you on every legal state has to be read every time
  to discover it had nothing to say. Empty when valid now — and the Start Dungeon button
  is already enabled or not, which is the same fact where the player is looking.

Left alone deliberately: Victory's five totals, which are a completion summary on the
completion screen; `run_flow`'s "one card seen every 22.4 turns", which is a derived
statistic but the exact one the thinning decision needs; and combat's `Draw / Discard /
Hand`, which is what a card game owes its player.

**And a one-line change broke a screen, caught by looking rather than by the suite.** The
new local in `_refresh()` was called `eq`, which collides with the `var eq := Button.new()`
forty lines further down the same function — a GDScript parse error, so the whole screen
failed to load and rendered black. The suite had been green *before* the edit and was not
re-run in between; the render was. `tools/screenshots.gd` printing a parse error into an
otherwise ordinary capture is the cheapest failure detector in the project, and it only
works if something actually opens the picture (D56).

### D129 — The last eight files were the two the pipeline was built to refuse

`ART_ASSETS.md` had sat at *8 to provide* for a long time, and the eight were the only
ones the generation pipeline deliberately cannot make: six `fx/*.png` sprite sheets
(`Kind.SHEET`) and two fonts (`Kind.LICENCE`). `ART_PROMPTS.md` reported **0 files can
be generated** and was right to.

Both were done at once, by two agents in parallel, because they share nothing but the
manifest.

#### The fonts were a download, and the interesting part was choosing them

**`display.ttf` — Cinzel Bold 2.000**, OFL 1.1. Roman inscriptional, which is what the
computed frame kit is already pretending to be: carved stone with a parchment inlay. It
is the one shortlisted display face that *agrees* with the art direction rather than
merely not fighting it. **Bold, not Regular**, because the display face is not only a
title face here — it is the card NAME, and `UI.fit_label` takes a name down to 7px in a
crowded fan, where Cinzel Regular's hairline serifs are simply gone.

Google Fonts ships Cinzel only as a variable `Cinzel[wght].ttf`. The static Bold came
from the upstream repository that Google's own `METADATA.pb` names as canonical, at the
same 2.000 the variable is cut from.

**`body.ttf` — Fira Sans Regular 4.203**, OFL 1.1. **Chosen by measurement, not taste.**
Alegreya Sans Regular, Alegreya Sans Medium, Fira Sans, Spectral and the engine default
were rendered at 12/14/16px on the game's own dark backing; at 12px Fira Sans has
visibly the largest x-height and the most open counters of the set. It was drawn for
small text on screens and it measures that way. 12px is the binding constraint, because
card rules text shrinks to fit.

Provenance follows the Kenney house pattern — verbatim upstream `OFL.txt` beside each
file, plus a `PROVENANCE.txt` carrying name, version, author, exact source path and **a
sha256 of each shipped binary**. Both checksums verified against the installed files.

Wired as `theme.default_font`, not as a font on `"Label"`: a per-type entry would have
left TooltipLabel, the OptionButton popup and LineEdit on the engine face. `style_title`
sets the display face and the title size *together*, so the two cannot drift apart
screen by screen.

**Nothing was adjusted for metrics.** `test_layout`, `TooltipTest`, `CardTextTest` and
`PlayableTest` all measure real wrapped line counts and control rects, and all stayed
green first time — `UI.fit_label`'s shrink-to-fit absorbs the change by construction,
which is what it is for.

*Where the display face deliberately does NOT go:* the iso risk/ropes/vitals chips,
"You take N gold.", combat's `status_label` (running prose — "Encounter cleared. +12
gold... Choose a reward:") and `_float_number`. **Size is not what makes a heading.** An
inscriptional serif on a numeral or a sentence reads as decoration.

#### The six VFX were never a generation job, and are not files at all now

The manifest's own brief said it: *"eight plausible frames of eight different explosions
read as a strobe, not an impact."* An image model returns eight slashes, not eight
frames of one slash.

So they are computed. `scripts/fx.gd` draws all six at runtime and **no PNG was added**.
Its shape is two pieces rather than six systems: a `Mark` control that `_draw()`s one
inked primitive at whatever progress it is tweened to (`CUT`, `SHOCK`, `WARD`), and one
self-reaping `CPUParticles2D` each effect tunes. CPU, not GPU, because the counts are
12–26 and a headless run has no GPU. Colours come from `ArtPalette.ramp()` of the
dungeon's own backdrop, so an effect is in the room's palette for free — there is not
one hex literal in the file.

The slash is a bowed quadratic chord whose head runs ahead of the tween and whose tail
chases it, so it is a stroke *travelling*; the ward's snap is `TRANS_BACK/EASE_OUT`
rather than a drawing; the dissolve discards the plate's own texture through a cell+fine
noise threshold tilted by UV.y, so an enemy comes apart from the top down.

**`combat_engine.gd` was not touched.** It is a pure state machine driving both the real
scene and the balance simulator, and the whole effect layer is derived from a
before/after vitals snapshot the *screen* takes itself. `git diff` on the engine,
`combatant.gd`, `balance.gd` and `card_data.gd` is empty.

**Three defects only rendering could find.** The effects were captured on the real
Combat screen under Xvfb at `Engine.time_scale = 0.2` — 14 frames of each of seven
poses. Every particle was invisible (4px motes at the value of the floor, on a painted
corridor). The dot texture's squared falloff made the poison cloud a green *haze* rather
than a cloud. The dissolve came apart in tidy squares until a second finer noise
raggedized the flake edges. **None of these are visible in code review** — this is D56's
lesson again, and it is now three for three.

#### What this closes, and the one thing it opened

`ART_ASSETS.md`: **205 wanted · 205 present · 0 to provide.** The six `SHEET` rows came
out of `tools/art_manifest.gd` — this manifest lists files the game will look for, and
it will never look for those — replaced by a comment saying where the effects went, and
the `Kind.SHEET` enum member kept as vocabulary with a note that nothing uses it.

Then the prompt sheet started lying. With every file present it still opened *"0 files
can be generated. The rest of the list cannot"* — which reads as art outstanding that a
generator is no use for, when there was no rest. `--prompts` now branches on whether
anything is absent at all. **A generated sheet that misreports its own state is the
exact failure it was generated to prevent** (D101), and it took reaching zero to notice
the zero case had never been written.

*Still open:* no animation-speed or accessibility setting exists — `Fx`'s six `T_*`
constants and its `_ok()` early-out are where one would hang. And `project.godot` still
forces NEAREST globally, so the font atlas will sample nearest on a 1440p/4K scale-up;
at the 1:1 1280x720 canvas it is invisible, which is why it has survived.

### D130 — Two settings for the new effects, and one that had never done anything

D129 shipped six combat effects with no way to turn them down, which is a problem for
exactly the players least able to say so. Adding the control turned up an older one
that had never worked.

#### Two controls, because one cannot do both jobs

The obvious design is a single "effects" slider running 0–200%, where 0 means off. It
was rejected: **turning particles UP is not a reduced-motion setting**, and the person
who needs the accessibility answer and the person who finds a 0.34s ward slow are not
the same person. Conflating them gives each of them a control that is mostly about the
other.

* **`effects_enabled`** — a checkbox. The accessibility answer.
* **`effect_speed`** — a percentage, **50–200**, default 100.

The slider's floor is the interesting number. It does not go to zero, and not because
zero is awkward to implement: an effect fast enough to be a single frame is a *flash*,
which is the one thing a motion-sensitive player is most likely to have opened this
screen to stop. Off is the toggle's job. `tests/EffectsTest.tscn` pins the floor at
0.05s per effect so nobody later "helpfully" widens the range.

**Where they attach cost nothing, and that is the point.** `Fx._ok` already sat in
front of all six effects, guarding the layer and the rect — one more clause there is
the whole toggle, and there is no seventh effect that can forget to check. Every `T_*`
already existed as a named constant, so `_dur()` is one multiply in one place; the
death dissolve alone poses four tweens off `T_DEATH` at four different fractions, and
scaling per-tween would have been four places for those fractions to stop agreeing.

Off is safe by construction rather than by testing: nothing downstream reads an effect
back, and the death dissolve stands in for a slot the refresh has *already* hidden
rather than being the thing that removes it.

`Fx` reaches SettingsState by node path, not as a global — autoloads are not registered
in a headless `--script` run and a compile-time reference would make the file
unloadable in the suite that loads every script. A missing autoload reads as the
shipped defaults.

#### The setting that was never wired to anything

`show_numbers` had been persisted, saved, offered in the Settings menu — and read by
**nothing outside that menu** for its entire life. The checkbox had never once changed
the screen.

Its label was worse than its wiring: *"Show damage numbers and intents"*. The intent is
what a player reads to decide whether to block, so the half that was never implemented
was a **difficulty option wearing a comfort option's clothes**. It now says "Float
damage numbers" and does exactly that — `_float_number` and nothing else, all of which
duplicates a number already on a bar.

A dead control is worse than a missing one: the player concludes the game ignores them.
`tests/test_flow.gd` now asserts that anything the settings menu offers is read
somewhere in the game.

#### The test that passed for the wrong reason

The behavioural test was written first as a `--script` SceneTree test: stand a
SettingsState up under `/root`, add a layer, fire an effect, count children. It failed
with the settings correctly wired — and the reason is worth recording, because the
naive fix is to delete the test.

**In a `--script` run, a node added to `root` during `_init` is not inside the ACTIVE
tree.** `is_inside_tree()` is false and an absolute node path errors out. So every
effect bailed at `_ok`'s *first* guard, the setting was never consulted, and "nothing
was drawn" looked like a pass for the off case. A test shaped that way would have kept
passing with the settings entirely unwired.

It is a scene test now (`tests/EffectsTest.tscn`), which is what `tests/run.sh`'s header
has said scene tests are for since it was written. **And it was mutation-checked**:
removing the one clause from `_ok` turns it red on all six effects. A test that has
never been seen to fail is a test that has never been tested.

38 suites.

### D131 — The hero had two facings for four directions, and one art per card is now on the list

**Two facings, four ways to walk.** `iso_run.gd` set `face_south = (x + y) > 0` and drew
`hero_s` or `hero_n` from it. The grid's four directions project to the four screen
DIAGONALS — `x` runs ↘ and `y` runs ↙ — so that test folds ↘ and ↙ together and ↖ and ↗
together. Walking right and walking left drew the same sprite. Reported as the hero
looking wrong while a floor is being explored, which is exactly when it shows: exploring
is when you change direction most.

Four facings out of two files. `x + y` still separates toward-camera from away; `x > y`
separates right from left, because ↘ is (1,0) against ↙ (0,1) and ↗ is (0,-1) against ↖
(-1,0). The left-hand facing is the right-hand art **mirrored at draw time** — a negative
width in the `draw_texture_rect`. That is what 2D isometric games have always done, and
it is why this costs two paintings instead of four; it also means the same trick is
available for the wanderers and the three monster families without doubling their tier.

The art has to face along a diagonal for the mirror to buy anything: a figure drawn
square-on to the camera looks identical flipped. The code shipped ahead of the art
because a mirrored symmetric sprite is harmless — the facing is simply not yet legible,
which is where it already was.

**One illustration per card, as Tier 3b.** This needs no code and never did:
`PixelArt.painted_card_art()` has checked `cards/<card_id>.png` before
`cards/<family>.png` since the family art landed, and Tier 3's own note said unique art
"can come later ... which is checked first". So the tier is 100 rows in the manifest and
nothing else, and a card with no unique painting keeps its family's — the same
one-file-at-a-time contract the relics and powers run on, which is what lets this be
worked through a few cards at a time rather than as a blocking batch of a hundred.

Every subject is DERIVED from the card's own `.tres` — name, effect text, family — so a
card retuned tomorrow gets a corrected prompt for free and there is no second list to
drift out of step with `resources/cards/` (D34). The file total goes 205/211 to 205/305,
which is the honest shape of the request rather than a number that flatters it.


### D132 — Three overlays for a hundred cards, and thirds of a track rather than levels

The ask was an effect on a card's art once it has been levelled a certain amount, plus a
different one at max, and then the same for powers — **without multiplying the number of
arts**. Painted into the illustrations that is 100 cards × 3 states = 300 files for the
cards alone, which is a year of the browser grind for decoration.

**It is a layer, not a repaint.** Three images per shape, drawn OVER the finished
illustration and tinted at draw time. Two things make one file serve every subject: the
overlay is mostly pure black and composited additively, so black is invisible and only
the painted light lands; and it is monochrome, so `Icons.rarity_colour` supplies the five
rarity colours instead of five more files. A hundred cards at five rarities across three
milestones costs **three** files. Six in total only because a card's illustration band is
4:3 and a power's sigil is square, and one image cannot be both without stretching.

The brief carries the constraints that make it composable: the four corners stay black
because the cost and damage numbers are drawn over them, the middle stays clear enough to
read the art through, and the three steps must read as escalation at thumbnail size — the
max state different in KIND rather than merely brighter, since it is the state a player is
actually working toward.

**Milestones are fractions of each thing's own track.** Measured before choosing:

    card caps by rarity   100, 40, 15, 5, 5
    power caps            2 to 10 (Foresight 2, Bulwark 10, Siphon 10)

Any milestone written as an absolute level is wrong on both ends of that range — "at
level 5" is a Legendary card's cap and a Common card's opening. So `level_band` takes the
cap and returns "", "1", "2" or "max" from thirds of it.

Thirds computed as INTEGER LEVELS, not a float against 0.334. The float version shipped
first and was wrong at exactly the levels it was meant to catch: at cap 100, level 34 is
(34-1)/(100-1) = 0.3333, which misses 0.334, so a Common sitting precisely a third of the
way up wore nothing; cap 40 missed at level 14 and cap 5 never reached band "1" at all. A
threshold in level numbers has no such edge. Bands now open at 34/67 of 100, 14/27 of 40,
6/10 of 15, 2/4 of 5 — where you would put them by hand.

The floor of 2 on both thresholds is what keeps a two-level track honest: at cap 2 the
thirds round down onto level 1, which is where everything STARTS, and an effect present
the moment you own the thing is not a progress effect. Clamped up, Foresight has base and
maxed, which is all two levels can mean.

`test_levels.gd` enumerates every real cap — the five rarities out of `Balance.max_level`,
every power's own `level_capped()` — and asserts level 1 is bare, the cap and only the cap
reads maxed, bands never go backwards, and any track of five or more actually shows both
middle bands. A retuned cap is checked by that test rather than by eye.

### D133 — Six reported annoyances, and four of them were something else underneath

Six points, one agent each. Four came back having found a different problem than the one
reported, which is the useful half of this entry.

## The screen before the main screen was a black rectangle with a lamp in it

Reported as looking like a glitch. It was the boot splash D125 had just wired, and the
measurements say it could not have looked like anything else. Sampled off the framebuffer
(`Xvfb -fbdir`, polled at ~400 Hz, nine boots): the splash holds for **287 ms mean**, and
its **median pixel is 12/255 against the flat `bg_color`'s 16** — so the painting was
*darker* than the empty colour it replaced, with 1.2% of the frame lit. Then a hard cut to
a MainMenu at 2.5x the brightness, because Godot's boot splash cannot fade.

**There was no load to cover** — deleting the shader cache changed the timing not at all.
Two fixes were tried on a copy and rejected with numbers: `minimum_display_time=1500`
charges every launch 1.2 s to hide nothing *and makes the cut worse*, because a
dark-adapted eye then meets the brighter screen; pointing the splash at the menu art
steps 75 → 51 instead, since the menu dims and scrims that painting and the raw file is
not dimmed. Cover cropping was cleared at 5:4, and there is no unlayouted first frame.

So the image is gone and the flat colour stays — the one `ui_theme.gd` already hands
`RenderingServer.set_default_clear_color`, so the window opens as one field of the right
colour and the title screen replaces it. That was the half of D125 that was right; the
image was the only thing flashing.

## The cursor's "dirty background" was a solid grey box, and the cause was a drawn frame

I diagnosed a faint wash from field pixels above the border average. Measured, **the field
was 58% opaque at alpha 147/255** — 3,210 of 4,096 pixels in one bucket.

Both cursors carry a **1px pure-black frame line drawn around the whole 64x64 image**, and
`Cut.mono_alpha()` takes its field reference from the border *mean*. So D125's `lumakey`
keyed everything against that frame line: the frame got the only alpha-0 pixels in the
file and the actual grey field landed at 147. Three faults, not one — the level now comes
from the *median* of a 6px band with complete rings peeled first; the key is `|luminance −
field|`, because these spikes have a dark outline at 0.06 *and* a lit shaft at 0.60
straddling a field at 0.256, so a one-sided key even off the correct level returns the
D125 hairline; and there is a knee at alpha 15, taken from a histogram whose field sits in
three dither lumps at 0-1, 4-5 and 9-10 holding 79-84% of the frame with a clear gap above.
Coverage 93.85% → **13.09%**.

**And `_lumakey` had no `MIN_COVER`/`MAX_COVER` guard.** Every other path in `cutout_lib`
has one; the mode I added in D125 did not. 93.85% is over `MAX_COVER`'s 0.92, so **the
guard would have refused my own broken install**. Added.

## Loadouts and Collection were never two screens

"Loadouts" was `deck_builder.gd` re-entered with `manage_only = true`. Same catalogue,
same filter bar, same row layout, and a "Collection (fuse)" button crossing between them
mid-task. The player could not tell them apart because there was nothing to tell apart —
and neither could `test_filter.gd`, whose "both screens must read the same function" loop
named one behaviour twice.

One **Cards** screen now, with three states *derived* from GameState rather than flagged
(`in_run` → ledger, `dungeon_id != ""` → outfit, else manage) — a flag a caller must
remember to set is the reported bug in a new hat. `manage_only` is deleted.

**Fusing mid-run is refused, and the reason is not tidiness.** `MetaState.fuse()` spends
`MetaState.gold` directly, never `GameState.spend_gold`. So it buys nothing for the run you
are in — `build_deck()` snapshots levels at the door — and it prices against a purse the
player is not shown. Re-plumbing it onto `available_gold()` would be worse: that converts
at-risk earnings into a permanent card level at the last rest before the boss, laundering
escrow past D20. The gate is `escrow_gold == 0`, not "no dungeon", because a dungeon's door
has an empty escrow and is the best moment in the game to spend a haul.

Width forced the layout: the old collection row alone asked ~1410px in a 1234px frame and
was already clipping. The "stats" and "next level" columns merged, because
`level_up_text` prints `dmg 28→238` — the pair cost 250px to say one thing twice.

## The builds do not cluster, measured

`Icons.for_card` over all 69 cards gives buckets of **1, 1, 1 and 4**, and the four in the
lump are the four builds *least* alike — AoE, lifesteal, a compounding engine, cheap cards.
The separating axes are `aoe`, `lifesteal`, `cost` and `draw`, none of which either
classifier can see. So the screen does not group them, and no build header carries an icon,
because four of seven would carry the same one.

The wall of text had a specific cause: **every build takes exactly 3 dungeon-exclusive
cards and spreads the rest across all 5 zone pools**, so "where is the rest of this build"
had an identical answer for all seven — 56 lines of the same sentence.

It belongs under How This Works, but not because it is "info": the glossary states rules
true for every save and every line here is about *this* one. It belongs because it is **the
only meta screen with nothing to press**. A hub button leads somewhere you do something.

## The gear does not exist, and the row that says so had to be careful

There is no cog in the 21 painted symbols and none in `PixelArt.GLYPHS`. The control asks
`PixelArt.symbol("gear")` and renders the word "Settings" until `ui/sym_gear.png` lands.
A `"settings"` row was deliberately **not** added to `Icons.MAP`, because `test_art.gd`
walks that table and fails on any name resolving to nothing — the row would break a suite
to document an absence. The manifest row is where the absence belongs, and adding it
exposed that the D117 partial-sheet line called a first draft a "RE-ROLL"; it now says
which.

**One screen must not get a gear, and it is an exploit rather than a style call.**
`chest_screen._open()` re-rolls the tier and lock on every `_ready`, so a settings door
there is a free re-roll: leave, come back, new chest. Combat and Encounter are excluded
too — combat clears Escape between the killing blow and the reward pick, and a mis-click
in that corner costs a turn.

The gear also **weakened an assertion**: `playable_test`'s "presents nothing to press — a
dead end" is answered on every screen at once by a control that is there by construction.
It is skipped by the meta `UI.gear()` stamps, not by name, and without that the check could
pass on a screen that had lost every button of its own.

## Two hazards that are not about any of the six

**A non-headless render writes the player's real save.** `MetaState.path_prefix` only
redirects to a sandbox when `DisplayServer.get_name() == "headless"`, so anything driven
under Xvfb that is not `tools/screenshots.gd` (which sets its own prefix) writes
`save.json`. With six agents rendering at once it happened — the file is stamped mid-batch.
Any harness driven on an X display needs `DECKCRAWL_SANDBOX`.

**And Godot silently falls back to Wayland at 1280x800** if `DISPLAY` points at a dead
Xvfb — the D115 trap wearing a new hat. `--display-driver x11` with `WAYLAND_DISPLAY`
unset is required, or a capture claiming to be the shipped size is not.

## Numbering

This batch was briefed as D130 and the concurrent session took D130, D131 and D132 while it
ran, so every reference was renumbered to D133 — except `combat.gd`'s, which is genuinely
theirs. Two sessions cannot pick decision numbers up front; the number has to be claimed
when the entry is written, not when the work starts.

### D134 — The title screen was 41.5% green against a style bible that is 0.0%

"The green is not convincing me." Measured, hue bucketed over the whole frame:

| file | green | cyan | blue | violet | mean sat |
|---|---|---|---|---|---|
| `main_menu.png` | **41.5%** | 7.5% | 22.4% | 24.3% | 0.61 |
| `bg_crypt.png` — the style bible | **0.0%** | 2.7% | 85.0% | 12.2% | 0.58 |
| `bg_world.png` | 0.1% | 10.0% | 12.4% | 0.0% | 0.15 |

So the largest hue mass in the game's front door was a hue that appears **nowhere** in
the reference image attached to every single generation request. Not a matter of taste:
the green forest and the green cloak were a second saturated mass competing with the cyan
flame, in a style whose rule is *one* saturated light source and everything else in deep
shadow.

## The palette line was not the problem — the noun was

The style block has said `PALETTE: cool desaturated violet-grey stone base. ONE saturated
light source` on every request since D100. The subject line said **"a valley of firs"**,
and firs are green. A concrete noun beats an adjective, which is D101's finding ("the
prompt sheet was describing the wiring, not the picture") and D108's ("the card brief
described a card that had already changed twice") arriving a third time in a third place.
The generator did exactly what it was told.

The brief now names the colour where the noun is, rather than trusting the palette line to
win an argument it has already lost twice: *"NO GREEN ANYWHERE IN THE FRAME: the firs are
black and violet-grey silhouettes at night, not foliage, and the traveller's cloak is the
same cold stone colour as the rock — a forest and a cloak are the two things a painter
reaches for green for, and this palette does not have it."*

## Graded rather than re-rolled, and why

The composition took three attempts to land — the traveller and the flame right of centre,
the left third quiet under the text column, the fortress far off across the valley. Only
the hue was wrong, and a hue is arithmetic. Re-rolling would have spent a composition that
works to fix something an operation fixes exactly.

`tools/regrade.gd` moves one hue band into another in place. Two choices in it are not
obvious:

- **The remap runs descending.** 70° (yellow-green) lands at 275° (violet) and 160°
  (teal-green) at 235° (blue), so the *tealest* greens stay nearest the cyan flame they
  sit beside. Ascending would have swapped them and put the forest's warm edge next to the
  one saturated light source in the frame.
- **Moved pixels lose 55% of their saturation.** A saturated blue forest is the same defect
  in a new hue; the rule is a desaturated base, so the forest becomes cool stone and the
  flame keeps its saturation because the cyan band is never touched.

Result: green **41.5% → 0.0%**, blue 22.4% → 57.6%, cyan **unchanged at 7.5%** (the flame
survived, which is the whole point), mean saturation 0.61 → 0.47.

**It refuses to run twice.** A grade is not idempotent — applied to its own output it walks
the hue further every pass — so the tool measures the band first and exits with "already
inside the palette, nothing to do" when it is empty. Verified: the second run does nothing.
That is what makes it safe to leave for whoever re-rolls this file next, and it is the
difference between a tool and a one-shot somebody re-runs by accident.

**A grade is a patch on the installed file and the brief is the durable fix**, which is why
both landed together. If the title art is re-rolled, the new file should come back inside
the palette on its own; if it does not, the tool is there and will say so.

### D135 — Tier 3b asked a hundred times for a rule and expected a picture

The decision to give every card its own illustration is taken. The prompts that were
supposed to buy it could not have.

**What Tier 3b was emitting.** D131 built the tier so the subject is DERIVED from the
`.tres` — name, description, family — explicitly to avoid a second list that drifts out
of step with `resources/cards/`. What came out was:

```
**Bandage.** Heal 6. Exhaust. A heal card.
**Abyssal Gift.** Pay 8 HP. Gain 1 Energy. Draw 2. Exhaust. A draw card.
```

That is a rule, and D101 already wrote down where a rule ends up: *"A generator can only
draw an object: 'Block.' and 'A choice with consequences' are rules, and a rule prompts a
diagram."* The tier reintroduced the exact defect thirty decisions after it was fixed,
and it was invisible because the row count looked right — a hundred well-formed rows,
every one of them unpaintable.

**And each prompt contradicted itself.** The style block's FORBIDDEN line opens with
`text, letters, numerals`. The derived subject is nothing but numerals: *Heal 6*,
*Deal 28 damage*, *Pay 8 HP*. Every one of the hundred prompts told the generator to paint
no numerals and then handed it four. That is the same class as D102 and D112 — operator
text reaching the model as art direction — one layer further in, where the conflicting
half is generated rather than pasted.

**The fix is to split the subject rather than to derive or to hand-write all of it.**
D131 was right that mechanics should not be written down twice and wrong that a subject
can be derived at all: arithmetic cannot be painted, and a picture is not a function of a
damage number. So `CARD_SUBJECT` now carries one hand-written line per card — the
picture, the only part that had to be authored — and the effect text stays derived and
follows as *context*. A retuned card still corrects its own prompt for free; only the
painting is fixed. Same output shape as Tier 3's `CARD_ART`, which has worked since it
landed:

```
**Bandage.** A strip of stained linen wound tight around a forearm and knotted off.
A heal card: Heal 6. Exhaust.
```

**The drift D131 feared is answered by a guard, not by derivation.** A card with no
`CARD_SUBJECT` line is a FATAL error in the tool — it refuses to emit, exactly as an
undescribed family already does. Verified by removing `bandage` and watching the run
abort naming it. So the second list cannot go quietly stale; it can only stop the
manifest until somebody writes the missing sentence.

**House rules for a line, written down because a hundred of them is where consistency
goes to die:** one concrete thing, no numerals, no keyword nouns (Block, Vulnerable,
Exhaust mean nothing to a painter), and distinct from both the family's picture and the
card's siblings — twenty attack cards that all read "a sword" would put the tier back
where it started.

**Not generated yet, and the reason is access rather than art direction.** Both routes
are shut, and each needs a decision that is not the tool's to make:

| route | state |
|---|---|
| Gemini API | Image models report a free-tier quota of **0** on this key. Confirmed with one real call; the skill is explicit that this is not transient and that cycling models does not help. Needs billing — about **$4** for all hundred, unattended, one model throughout. |
| Gemini web app | The Chrome extension is installed, but no `mcp__claude-in-chrome__*` tools exist in this session: Claude Code was not started with `claude --chrome`, which is a **launch flag** and cannot be set mid-session. Beyond that the free tier caps at roughly **20-25 images per day**, making a hundred cards a four-to-five day job, and automating the consumer product is against Google's ToS in a way the paid API is not. |

The prompt sheet is regenerated and correct, so whichever route opens, the batch is one
command away rather than an evening of authoring.

**Found in passing:** the Gemini MCP server's defaults are unexpanded shell variables —
`list_models` reports `image=${GEMINI_IMAGE_MODEL}, text=${GEMINI_TEXT_MODEL}` literally,
and a `generate_image` call with no explicit `model` fails with *"unexpected model name
format"* rather than with anything naming the cause. Passing `model` explicitly works
around it.


### D136 — Four cards to a picture, and the colour fixed after the fact rather than asked for

Tier 3b is a hundred illustrations and the generator is a browser window with a daily cap
(the standing constraint: paying for the API is not an option). One card per request is a
hundred requests. **Four 4:3 cells tile exactly into one 4:3 picture**, so a 2x2 grid costs
nothing in shape and turns a hundred requests into twenty-five. `install_card_sheet.gd`
cuts them; it is a separate tool from `install_sheet.gd` because that one mattes, trims and
anchors CUTOUTS on a flat field and every one of those steps is wrong for a full-bleed
painting whose edges are meant to run to the frame.

**The grid works. The colour was the hard part, and asking for it did not fix it.** Three
rolls of the same four subjects:

    style block as written, plus "2x2 grid"     greyscale comic page
    + "FULL COLOUR, richly coloured, vivid"     every cell flooded with orange or teal
    + "one small light, most stays cool grey"   back to nearly grey, one literal floating flame

The generator has no dial between "no colour" and "all colour", and it cannot be given one,
because each request is a fresh conversation with no sight of what the last one produced.

So the colour is **set after the fact**. Ask for the flooded version — which gets the REACH
of colour right, light touching the whole subject the way the family art does — and scale
saturation down to a measured target at install (`--sat=0.33`). That is exact, repeatable,
and costs no generations. The rescue only works in that direction: scaling a grey page up
just amplifies its JPEG chroma noise, so the greyscale failure is still a refusal.

**The first metric ranked the cells backwards.** `(max-min)/max` is unstable in the dark — a
pixel of (10,9,8) is grey to any eye and scores 0.20 — and these paintings are deliberately
mostly shadow, so the average was mostly noise. It passed a cell at 23.5% colourful and
refused one at 37.8%. Measuring only pixels above a luminance floor separates them:

    family attack / block / heal    sat 0.34 / 0.34 / 0.24   colourful 100 / 100 / 68%
    bg_crypt.png (the style bible)  sat 0.535                colourful  99.9%
    greyscale comic-page sheet      sat 0.171                colourful  24.5%
    flooded sheet                   sat 0.46-0.67            colourful  85-100%
    flooded sheet at --sat=0.33     sat 0.33-0.35            colourful  76-99%

The band in the installer is those numbers, and both ends refuse. A number inside it is not
proof a painting is good; a number outside it is proof one is wrong, which is worth a
refusal when the alternative is finding out a hundred cards later.

**Two things this does not solve.** Image-conditioning on `bg_crypt.png` — rule 2 of
ART_PROMPTS.md, and the strongest style constraint available — is unreachable from here: the
page has no file input until its Upload button opens a native picker, and a native dialog
blocks the browser extension outright. Text-only plus the measured saturation band is the
substitute. And the generator's corner watermark still lands in the bottom-right cell of
every sheet; `strip_sparkle.gd` needs several frames sharing a position to find it, which
the sheets will supply once enough exist. The family art already installed carries the same
watermark, so this is not a new defect, but it is an open one.


### D137 — The reference image cannot be attached from here, and saying only what a picture is NOT drains it

Two findings that arrived together, both about the same thing: a prompt that constrains
without describing.

## The style bible cannot ride on the request, and the tool that claims otherwise lies quietly

Rule 2 of ART_PROMPTS.md is "attach `bg_crypt.png` to every single request" — image
conditioning is a stronger constraint on palette and line weight than any adjective. From
this harness it is unreachable, and it took a measurement to establish that rather than an
assumption:

- `file_upload` needs an `input[type=file]`. Gemini creates none until its Upload button
  opens a **native** picker, and a native dialog blocks the extension outright.
- `upload_image` — screenshot the reference in another tab, drag it onto the composer —
  is the route the browser skill recorded as tested and working. It reports
  `Successfully dropped image (120KB)` and **nothing attaches**. Instrumenting `window`
  with a capture-phase listener says why:

      [{"t":"dragenter","trusted":false,"files":1},
       {"t":"dragover", "trusted":false,"files":1},
       {"t":"drop",     "trusted":false,"files":1}]

  The events carry the file and arrive **untrusted**, and Gemini discards them exactly as
  Quill discards untrusted paste events. The skill has been corrected. The lesson worth
  keeping is not about drag and drop: **a tool reporting success is not evidence the page
  did anything**, and the only proof is the attachment chip in the composer.

The remaining route is the user attaching it by hand once per chat, which is what the skill
now recommends without alternatives.

## "No green" produced a black-and-white picture

D134 corrected the title brief by naming the colour at the noun: *"NO GREEN ANYWHERE IN THE
FRAME: the firs are black and violet-grey silhouettes."* It predicted that a re-roll against
that brief would come back inside the palette on its own. Measured on the first re-roll, it
was right — and it was not enough:

    green   0.0%   (was 41.5% before D134, 0.2% after the grade)   <- fixed, natively
    sat-in-light   0.211   against bg_crypt 0.535, graded file 0.456
    colour reach   45.4%   against bg_crypt 99.9%, graded file 92.7%

Green was gone and so was every other colour: a neutral grey night with one cyan flame in
it. The brief said what the picture must NOT be and left what it must BE to the word
*desaturated* in the palette line, so the generator desaturated all of it. That is D134's
own finding — a concrete noun beats an adjective — arriving from the other side: a
prohibition is not a description, and removing the wrong colour does not supply the right
one.

The brief now names violet positively where the nouns are: *"THE PICTURE IS STILL IN COLOUR
AND THE COLOUR IS VIOLET: the rock, the cliffs, the distant mountains and the cloak are all
a deep blue-violet stone, plainly violet against a violet-blue night sky, never neutral grey
and never black-and-white."* The REDO line now carries both tests, because passing one of
them alone is how this file has failed twice: **green under 1% AND saturation near 0.45.**

`main_menu.png` is on the re-roll list either way. What is installed is a hue grade — a
patch that moved 41.5% green to 0.0% in place — and D134 said itself that the brief, not the
grade, is the durable fix. The grade stays because it works; the row stays because a graded
file is not the picture a generator would paint in that palette.

### D138 — The pointer is the player's, and the game had taken it

Reported flatly, as a preference: *"I do not like games that change the pointer, use the
system default."*

The game had a whole pointer. A `Pointer` autoload replaced the system arrow with a
painted iron spike and swapped in a driven-in variant while the mouse button was down.
Two 64x64 plates, two hotspots measured off the ink to the pixel — (2, 2) and (8, 8) —
an `_input` listener chosen over `_unhandled_input` specifically so a Button eating the
click could not eat the press, and a focus-out guard so alt-tabbing mid-click could not
leave the spike driven in for the rest of the session. It had been repaired twice: D125
recovered its alpha after it shipped 9.4% opaque, and D133 re-keyed it after the first
repair left it dragging a grey box across every screen.

**It is all gone, and the reasoning is worth keeping even though the code is not.** A
cursor is not part of a game's art direction in the way a backdrop is. It is the one
piece of the interface the player already configured, that every other window on their
machine agrees about, and that they may have configured for a reason — size, contrast,
a system theme. Replacing it is a preference imposed rather than offered, and nothing
about the spike was worth that.

**Removed rather than made optional.** A setting was the obvious alternative and is the
wrong shape here: D130 added two settings for the combat effects because those effects
have a real reason to exist and a real reason to be turned down. A cursor the author does
not want has no such tension — a toggle would have been a way of not deciding, and it
would have kept two plates, an autoload, two installer entries and two hotspot constants
alive to serve an option nobody asked for.

Deleted: `scripts/pointer.gd`, the `Pointer` autoload line, `assets/art/ui/cursor.png`
and `cursor_press.png`, both `install_chrome` tier entries, the `ART.md` row and the two
manifest rows. **Git holds the plates if this is ever reversed.**

**What deliberately stayed.** The `lumakey` constants in `install_chrome.gd`
(`LUMA_BAND`, `LUMA_FRAME_FAR`, `LUMA_MAX_PEEL` and the knee) were all measured off these
two cursors — they were the worst case that key ever met — and `ui/logo.png` still depends
on every one of them. The comments now say the files are gone rather than pointing a
reader at a path that no longer exists, which is the failure mode D101 named: a note that
briefs something absent is worse than no note.

**Why "optional" was never a safe word for these two rows.** The manifest called them
optional and it read as harmless. It was not: with the code removed they would have become
two installed files that nothing loads, which REVIEW.md already records as a fixed bug from
D125 — *"logo, target ring, all seven intent telegraphs, card glow, boot splash, cursors,
divider: installed and read by nothing."* An asset is either wired or it is absent. There
is no third state, and a row that offers one invites the tree back into it.

Verified by rendering every screen: nothing referenced the autoload, no screen changed,
38 suites green.


### D138 — The level overlay does not always work, and the reason is saturation not visibility

Asked whether the level masks would read over a hundred freshly painted card
illustrations. Doubt was correct; the failure was not the one expected.

**Visibility was never the problem.** HEADROOM — the mean of `1 - base` over the pixels
the overlay lights, weighted by how hard it lights them — runs **0.51 to 0.86** across all
112 illustrations, mean 0.68, nothing below 0.45. There is no card the effect disappears on.

**Clipping was.** Additive light plus already-bright paint runs past white, and a saturated
pixel has lost two things at once: the rarity tint (everything above 1.0 is white, whatever
colour it was) and the shape that separates a thin ring from a full corona. Measured over
the maxed overlay:

    mean clipped area of the effect      30.7%
    worst cards (bloodlust, pressure,    48.4%, 47.5%, 45.6%
      forge_strike)

So on the brightest third of the art the maxed state read as a white smear rather than a
gold corona, and the mid band's ring vanished into bright paint on one side.

## The fix is a dark halo, and it costs no generations
##
## **Superseded by D139 the same day.** The halo fixed the number it was aimed at and was
## the wrong fix: it bought a readable effect by darkening the illustration underneath it.
## Read on, then read D139 — what follows is the reasoning that led to the better answer,
## and the measurement that convicted it is in D139.

A black scrim under the light, in normal blending, with its alpha taken from a **spread
copy of the light itself** — dilate by 7px so the dark reaches slightly past the glow (a
halo exactly the size of the light would be covered by it), then blur so it has no edge of
its own. `install_overlay.gd` derives it from the finished overlay and writes
`lvl_<shape>_<band>_halo.png` beside it; six more files, all computed.

It is self-cancelling in the right direction: on dark art it changes nothing, because black
over near-black is near-black, and on bright art it buys back exactly the headroom the light
is about to need. Result:

    mean clipping    30.7%  ->  8.5%
    worst card       48.4%  ->  13.1%

The residual 8.5% is the corona's own white-hot core, which is supposed to be white. That is
where this stops — pushing `HALO_MAX` past 0.88 would start showing the scrim as a dark ring
on the dark cards to buy back a defect that is not one.

Drawn under the light at all three sites (`UI.card_button`, the combat orb, the powers
screen). `PixelArt.level_overlay_halo` returns null when the file is absent, so a
half-installed set still draws the light rather than nothing.

**Why the additive contract survives.** The alternative was to stop adding and start
blending, which reads the art underneath and replaces it — that fixes clipping by deleting
the illustration, which is the thing Tier 3b just spent a hundred generations making. Adding
light and darkening underneath keeps both.


### D139 — Screen the glow instead of adding it, and the halo goes away

D138 asked whether the level overlays read over the hundred new illustrations, found that
the additive blend clipped on 30-48% of the maxed effect, and fixed it with a black scrim
underneath. Asked next how to make the effect actually look GOOD rather than merely legible,
which is a different question, and the honest answer was that D138's own fix was the thing
standing in the way.

## The halo was buying readability with the art

The metric D138 used — how much of the effect runs past white — only ever looks at the
effect. Adding a second one, how much of the ILLUSTRATION still shows through underneath
(correlation between the base and the result, inside the lit area), changes the verdict:

    mode                 clip%   punch    art still showing
    add                   45.6   +0.374        0.61
    add + dark halo       16.4   +0.177        0.29
    screen                10.9   +0.286        0.57

The halo more than halved how much of the painting survived. It was fixing a white blob by
making a dark one, and the first version of the "does the art survive" measurement did not
catch it either — local contrast scored every mode above 1.0, because the overlay brings
its own edges and inflates the number. Correlation was the metric that worked.

## Screen wins on all three axes and needs no shader

`screen = light + art*(1 - light)` cannot exceed white by construction, and it leaves the
art alone wherever the light is weak. Godot's `CanvasItemMaterial` has no screen mode, but
`BLEND_MODE_PREMULT_ALPHA` computes `src.rgb + dst*(1 - src.a)` — which IS screen, provided
the overlay carries the light in its **alpha** as well as its colour. So `install_overlay`
now writes `Color(v, v, v, v)` instead of `Color(v, v, v, 1)` and the draw sites ask for
premultiplied. Measured at 10.9% clip / 0.55 art, within noise of true screen, and the six
halo files are deleted.

**One trap, and it would have shipped.** Godot defaults `process/fix_alpha_border=true`,
which bleeds neighbouring colour into fully transparent pixels. That is correct for an
alpha-tested sprite, where nothing samples the colour of a transparent texel, and wrong
here: premultiplied blending adds the RGB whatever the alpha says. Measured on the maxed
overlay, **8145 pixels came back with r=0.588 under a=0.004** — light scattered across the
part of the frame that is supposed to be empty. Set false on all six.

## What makes it look cool is that it moves

A static decal in the same place on all hundred cards reads as a sticker. The glow now
breathes — `self_modulate.a` between 0.70 and 1.0, faster and shallower as the band climbs
— and the maxed corona turns, one revolution per 52 seconds. Only the maxed band turns: it
is the state a player is working toward, it already differs in kind rather than degree
(D132), and a corona is the only band radial enough for rotation to read as motion rather
than wobble. The pulse rides `self_modulate` and not `modulate`, because `modulate` already
carries the rarity tint and, in combat, the dimming of a power that cannot be fired.

`tests/GlowTest.tscn` is new and guards all four things, because every one of them is
silently breakable and nothing else was watching: the blend mode, the light living in the
alpha, the arithmetic being unable to exceed white against pure white art, and the tween
actually running and turning about the centre.
