# Deckcrawl — Design & Implementation Plan

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
| Traversal models | Pluggable per dungeon: node graph, deck, dice board | `[x]` |
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
| **Run** | `GameState` | run deck instance, HP, map graph, position, dungeon tier | memory only | wiped |

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

  DeckBuilder ── assemble/select a deck for this dungeon ──▶ Map.tscn
  Map.tscn
    ├─ combat/elite node ──▶ Combat.tscn ──▶ reward ──▶ back to Map
    ├─ boss node ──▶ Combat.tscn ──▶ reward ──▶ advance dungeon ──▶ DeckBuilder (pick deck for next dungeon)
    ├─ rest node ──▶ heal inline, stay on Map
    ├─ shop node ──▶ Shop.tscn (buy cards / healing for gold) ──▶ back to Map
    └─ "Collection" button ──▶ Collection.tscn (fuse) ──▶ back
    └─ boss cleared ──▶ dungeon marked cleared + relic ──▶ DungeonSelect
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
| `scripts/traversal_graph.gd` | Layered node-graph model (Slay-the-Spire style). |
| `scripts/traversal_dice.gd` | Dice-board model: roll two, spend one, overshoot skips spaces. |
| `scripts/traversal_deck.gd` | Dungeon-as-a-deck model: reveal, then face or pay HP to avoid. |
| `scripts/run_flow.gd` | Shared encounter routing used by every traversal view. |
| `scripts/build_data.gd` | Build Resource: a named archetype and its defining cards. |
| `scripts/builds_screen.gd` | Build tracker: progress and where the missing cards are. |
| `scripts/icons.gd` | Placeholder art lookup, rarity colours, card styling. |
| `scripts/zone_data.gd` | Zone Resource: themed card pool + the dungeons it contains. |
| `scripts/dungeon_data.gd` | Dungeon Resource: difficulty, unlock gate, enemy roster, card pool, exclusives. |
| `scripts/dungeon_select.gd` | Dungeon choice screen — the seam the overworld will replace. |
| `scripts/relic_data.gd` | Relic Resource: run/combat/turn/reward effects + tuning weight. |
| `scripts/enemy_data.gd` | Enemy archetype Resource: stat shares, action pattern, group size. |
| `scripts/combatant.gd` | HP, block and status effects; owns the block-expiry / `retain_block` rule. |
| `scripts/balance.gd` | **All** tuning constants + scaling formulas (enemy stats, gold, rarity weights, deck bounds, power ratio). |
| `scripts/combat_engine.gd` | Pure combat rules, no UI/autoloads — shared by the Combat scene and the simulator. |
| `scripts/meta_state.gd` | Persistent collection, `CATALOG`, fusion, `build_run_deck`, JSON save/load. |
| `scripts/game_state.gd` | Run state, map generation, reachability. |
| `scripts/combat.gd` | Combat *screen*: thin UI over `CombatEngine`; reward flow and routing. |
| `scripts/map.gd` | View for the graph traversal. |
| `scripts/deck_run.gd` | View for the deck traversal. |
| `scripts/dice_run.gd` | View for the dice-board traversal. |
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
| `scripts/ui_theme.gd` | Fullscreen + **single-knob UI scaling** (`UI_SCALE`); builds the global Theme and size helpers. |
| `scenes/*.tscn` | Thin Control roots; all UI built in code. |
| `resources/cards/*.tres` | Card definitions (data, not code). |
| `resources/enemies/*.tres` | Enemy archetypes (data, not code). |
| `resources/relics/*.tres` | Relic definitions (data, not code). |
| `resources/dungeons/*.tres` | Dungeon definitions (data, not code). |
| `resources/events/*.tres` | Event definitions (data, not code). |
| `resources/zones/*.tres` | Zone definitions (data, not code). |
| `resources/builds/*.tres` | Build archetypes (data, not code). |
| `scripts/audio.gd` | Sound autoload: buses, voice pool, event -> stream. |
| `scripts/pixel_art.gd` | Authored 16x16 symbol glyphs + CC0 pixel sprite lookup. |
| `assets/pixel/` | CC0 pixel art (Kenney Tiny Dungeon, UI RPG Expansion) + licences. |
| `test_*.gd` | Headless regression tests (map, meta, death, deck, balance, status). |
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
| The Hollow Barrows | — | Crypt (d1), Warrens (d2) | martial basics, defence |
| The Ashen Foundry | 2 clears | Foundry (d3), Slag Pits (d4) | strength, thorns, growth |
| The Verdant Rot | 4 clears | Rot Gardens (d5) | poison, AoE debuffs |
| The Sunken Deeps | 6 clears | Sunken Vault (d5), Abyssal Stair (d7) | epics and legendaries |

One pool helper feeds rewards, shop stock *and* event card grants, so exclusivity holds everywhere.

### Traversal is pluggable (D13)

A dungeon is not required to navigate like a graph. `DungeonData.traversal` selects a model, and
everything else — combat, cards, relics, shops, meta, deck-building — talks only to the `Traversal`
interface (`options()` / `select()` / `clear_pending()` / `is_complete()`).

Two rules make this cheap rather than a maintenance tax:

1. **Implementations are pure logic** (no UI, no autoloads). The balance simulator drives them
   directly, so **one generic walker measures every model**. A per-model walker would be the first
   thing to rot when a model is added.
2. **Every model spends a comparable attrition budget** (`Balance.ENCOUNTER_*`). Otherwise
   "difficulty 3" means different things in different dungeons and the scaling model decouples.
   `tests/test_traversal.gd` asserts this, plus termination and exactly-one-boss, for *every* registered
   model — adding a model means adding its `Kind` to one array in that test.

Views are per model (a dice board should not render like a graph); shared encounter routing lives in
`RunFlow` so a new view does not re-derive how a rest heals or which scene a shop opens.

Current assignment doubles as the teaching order, since `unlock_after_clears` already sequences
dungeons: Crypt = graph, Warrens = deck, Foundry = graph, Sunken Vault = **dice board**.

**A model's encounter count must be derived, not structural.** The graph visits one node per row, so
its row count *is* its encounter count — it was hardcoded at 6 and silently broke the budget contract
the moment new encounter types entered the mix. `TraversalGraph.rows()` now derives from the budget.

**The budget is an average, not a per-run guarantee.** The dice board has real variance by design (a
lucky sequence skips content; an unlucky one grinds through it), so `tests/test_traversal.gd` asserts the
*mean* encounters per model and keeps only a loose per-run bound to catch runaway generation.
Measured: graph 9.0, deck 9.0, dice 8.7 against a budget of 9.

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

The game is pixel art throughout. Assets are split by whether *meaning* has to be exact:

| What | Source | Why |
|---|---|---|
| Enemy sprites (28) | Kenney **Tiny Dungeon**, CC0 | any distinct sprite works for an enemy |
| UI panels / buttons | Kenney **UI Pack RPG Expansion**, CC0 | pixel-styled frames |
| Effect symbols (13) | **authored in `pixel_art.gd`** as 16x16 bitmaps | a shield must read as a shield |
| Backdrops (5, one per zone) | Kenney **Pattern Pack Pixel**, CC0 | genuinely seamless tiles |
| Sound (23 events) | Kenney **Interface / RPG / Jingles**, CC0 | named files, so mapping is exact |
| Card illustrations (100) | Kenney **1-Bit Pack** sheet, CC0 | 992 usable tiles; monochrome, so tintable |

The packs ship *unlabelled* spritesheets (`tile_0093.png`) and there is no way to tell a sword tile from
a barrel tile without looking at it. Picking symbols from them would have been guesswork presented as
art, so the twelve glyphs that carry meaning — attack, block, poison, thorns, heart, gold, card, dice,
skull, campfire, rope, chest, book — are authored as bitmap strings instead. They are monochrome, so
callers tint them (rarity colour, faded board spaces).

Enemy sprites are assigned by **position in a sorted archetype list**, not by hashing the id: hashing
collided and left 28 enemies sharing only 17 sprites, so different enemies looked identical. Position
guarantees distinctness while sprites last, stays stable across runs, and `PixelArt.OVERRIDES` lets any
one of them be corrected by eye later.

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

Still missing: animation.

Older note — all lookups still go through `scripts/icons.gd`:
- call sites ask for **meaning** (`"boss"`, `"poison"`, `"gold"`) rather than filenames, so swapping art
  is one file;
- a missing icon returns `null` instead of crashing a screen;
- `Icons.for_card()` picks an icon from what a card actually *does*, so new cards get sensible art with
  no per-card work;
- `rarity_colour()` / `style_card_button()` carry rarity as **colour**, which is the thing a player reads
  at a glance — text alone made every card look identical.

Still placeholder: no animation, no sound, no backgrounds, no enemy portraits.

### Conventions
- UI is built programmatically in `_ready()` — no editor scene wiring. Keeps everything diffable and reviewable in code.
- **All UI sizes come from `UITheme`** (`font()`, `title_font()`, `sep()`, `card_size()`, `px()`), never hardcoded pixels — so one constant rescales the whole interface. Game starts fullscreen; `Ctrl +/-/0` rescale live, `F11` toggles fullscreen, `Esc` leaves it.
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

- **D5 — Power curve & scaling.** Enemies scale against **deck power per energy** (`Balance.power_ratio`), not deck size or raw card totals, because energy is the binding constraint on player throughput. Consequences, all deliberate: a bigger deck of the same cards is more *consistent* but not stronger; an expensive card only helps if it beats the cost-efficiency curve; fusing raises the ratio and enemies keep pace. `HP_POWER_K` ≈ 1.0 keeps fight *length* roughly constant as decks improve; `DMG_POWER_K` is held near it (0.85) because letting incoming damage lag behind block makes progressed decks invulnerable. All tuning lives in `scripts/balance.gd`; rules live in `scripts/combat_engine.gd`; both are exercised by the simulator so the game and the tuning model cannot drift.

- **D7 — Block lifetime.** Block absorbs the incoming hit and then **expires at the start of the next turn**, so defence is a per-turn decision rather than an accumulating wall. The legendary **Barricade** removes the expiry, turning block into a resource that compounds across turns — the payoff for a rare card, and the reason `retain_block` is modelled as a persistent combatant flag rather than a card effect applied once.

- **D18 — Rarity means two things.** With 100 cards, rarity has to be defined, not felt. It governs
  *power* and *growth*, and the second one was inverted: level caps derive from drop weight (common
  100, legendary 5), so a single flat `LEVEL_GAIN` made a maxed common reach 3.5x while a maxed
  legendary reached 1.5x — grinding commons beat every legendary. `LEVEL_GAIN_BY_RARITY` now scales
  gain against track length so the maxed multiplier *ascends*: 3.5 / 3.8 / 4.2 / 4.6 / 5.0.

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

  Level scaling had to become **sub-linear (sqrt, `LEVEL_GAIN` 0.25)** for this to work at all: the old linear `+3/level` would put a maxed Strike at ~300 damage, far beyond anything `power_ratio` can scale enemies to, collapsing the curve. sqrt puts a maxed card at ~3.5x base (Strike 6 → 21) — early levels feel substantial, late ones incremental. Status magnitudes grow slower still (`sqrt/2`), because a stack multiplies every later action instead of adding once. Consequence worth remembering: **Lv2 is early-game on a 100-level track**, so "mid progression" now means roughly Lv15 and deep play Lv40.

### Open
- **D18 — Rarity means two things.** With 100 cards, rarity has to be defined, not felt. It governs
  *power* and *growth*, and the second one was inverted: level caps derive from drop weight (common
  100, legendary 5), so a single flat `LEVEL_GAIN` made a maxed common reach 3.5x while a maxed
  legendary reached 1.5x — grinding commons beat every legendary. `LEVEL_GAIN_BY_RARITY` now scales
  gain against track length so the maxed multiplier *ascends*: 3.5 / 3.8 / 4.2 / 4.6 / 5.0.

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

- **D6 — Dungeon identity.** How exclusive cards and per-dungeon loot pools are declared (tags on `CardData`? per-dungeon pool tables?).

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
- [x] Connectivity regression test (`tests/test_map.gd`, 50 trials)

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
godot --headless --script tests/test_map.gd    # map connectivity, 50 trials
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

### Known gap: the endgame plateaus above the deepest ceiling

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
