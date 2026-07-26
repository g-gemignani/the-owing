# AGENTS.md — Deckcrawl

Brief for anyone (human or AI) picking up this project. It is the *why*: the game's
concept, the decisions that shaped it, and the working rules that keep changes from
breaking it. The *what* — file-by-file detail and the full decision log D1–D62 — is
in [DESIGN.md](DESIGN.md); how to add content is in [CONTRIBUTING.md](CONTRIBUTING.md);
how to build and run is in [BUILD.md](BUILD.md); what the game should *look* like, and
the file-by-file asset list, are in [ART.md](ART.md) and [ART_ASSETS.md](ART_ASSETS.md).

> **Keep this file and DESIGN.md current.** Every substantive change should land with
> its reasoning written down. A decision that only lives in a commit message is a
> decision the next person re-litigates. See "Working rules" below.

---

## The concept

A **deckbuilding roguelike with a persistent RPG meta layer**, built in Godot 4.7
(GDScript). Slay-the-Spire-shaped combat, but what you carry between runs is a
*collection you grow, fuse and spend* — not a fresh deck every time.

The loop:

1. **Overworld** — pick a zone, then a dungeon. Difficulty is a *choice*, shown up
   front, with the boss named before you commit.
2. **Deck builder** — assemble a run deck from your owned cards and equip one Power.
3. **Run** — traverse the dungeon (a node graph, a card draw, or a dice board,
   depending on the dungeon), fighting, shopping, resting, and hitting events, up to
   a named boss.
4. **Meta** — winning banks the run's gold and cards permanently; dying forfeits most
   of it. Between runs you fuse duplicates into levels, buy and level Powers and
   Relics, and unlock deeper zones.

Two-tier state makes this work:

- **`MetaState`** — the persistent character: collection, decks, relics, powers,
  gold, clears. On disk, versioned, migrated.
- **`GameState`** — one ephemeral run. Rebuilt each dungeon, risked on death.

## Content at a glance

100 cards · 35 enemy archetypes · 12 bosses (one named per dungeon) · 30 relics ·
10 powers · 20 events · 12 dungeons across 5 zones · 3 traversal models · 34 test
suites. All content is `.tres` data plus one catalogue line; adding more is a data
task, not a code task.

## The two ideas that run through everything

1. **`scripts/balance.gd` is the single source of truth for tuning.** Every constant
   and formula lives there, so the game and the headless simulator cannot drift. A
   duplicated lookup table elsewhere went stale once and made the first dungeon
   literally unplayable (D34); the tests now reject private copies of shared data.

2. **Tuning is measured, not guessed.** `tools/sim_balance.gd` auto-plays fights and
   reports run-completion per build per dungeon. Several designs that read fine on
   paper were reverted after the numbers came back. When you change anything that
   touches difficulty, run the sim and paste the numbers into the commit.

---

## Design pillars (the goals we keep returning to)

- **Priced power must equal delivered power.** Enemies scale to *deck power per
  energy* (`Balance.power_ratio`). Anything that makes the player stronger from
  *outside* the deck — a relic, a power, a run removal — must be folded into that
  ratio, or it is free strength that breaks scaling. This mistake has been made and
  caught for total-deck power, per-card power, block-vs-damage, relics, powers and
  triggered relics.

- **Difficulty comes from depth, not from your own growth.** A dungeon scales to the
  player only up to a ceiling set by its difficulty (D36). You outgrow the Crypt; you
  never outgrow the Maw. Progression should *feel* like progression — HP lost per
  fight must fall as you get stronger, at any fixed depth.

- **Every turn should have a floor and a ceiling.** Powers (once per turn) put a floor
  under a bad draw without raising the ceiling on a good one (D37). Reactive enemies
  and named boss signatures make each fight a puzzle rather than a solved routine
  (D38, D41). Block cannot be a complete answer at depth — piercing damage keeps
  defensive play honest (D45).

- **A run is a risk with an arc.** You commit a deck, earn cards that dilute it, and
  can thin or sharpen it at shops and rests (D46). Death forfeits the run's takings;
  the meta layer is what survives.

- **The player is never lied to and never stuck.** Telegraphs match what resolves.
  Card faces show the *current* numbers, not the level-1 text (D50). Every screen
  offers something to press, and every encounter can be left (D47). No fusion or death
  can strand the collection below a legal deck (D12).

- **Expandable by design.** New cards, enemies, bosses and dungeons are data files
  plus a catalogue line, guarded so a half-added piece of content fails loudly rather
  than silently not existing (D42).

- **Cross-platform.** Desktop (Linux/Windows/macOS) builds here; Android and iOS stay
  *exportable* even though their toolchains cannot run here (D44). Touch is a first
  class input — a finger has no hover, so cards read on tap (D43).

## The engineering lessons, learned the hard way

These are failure modes that have actually bitten this project. Treat each as a rule.

- **Booting is not playability.** A scene that loads can still be a black screen. 34
  suites once passed while the first dungeon was unplayable. `tests/test_compile.gd`
  and `tests/PlayableTest.tscn` exist because of this — run them.
- **Nor is passing a test *looking* right.** Rendering every screen to PNG (D56)
  found a dice board with zero height, seven screens with no backdrop and a button
  frame stretched 14×, none of which any suite noticed and none of which is visible in
  a diff. `tools/screenshots.gd` exists because of this — look at the game.
- **A test that reads source text proves code exists, not that it works.** A
  `--script` test has no autoloads, so it can only inspect files — which is why
  `test_layout.gd` happily confirmed the dice board's scroll-to-token function while
  the board itself was 0px tall (D57). Anything about *size, position or visibility*
  belongs in a scene test that measures the built tree.
- **Zero-size is the quiet failure mode.** A `ScrollContainer` reports a minimum size
  of 0 on any axis it can scroll, so `SIZE_EXPAND_FILL` siblings will crush it to
  nothing and its contents vanish while every other check stays green. `PlayableTest`
  now asserts no scroll area is squeezed flat.
- **`load()` returns non-null for a script that failed to parse.** Never use it as a
  "does this compile" check. `get_instance_base_type() == ""` is the honest probe.
- **`--headless --import` does not compile scripts** and its viewport defaults to a
  square 1280×1280. Scene tests must set the shipped 1280×720 and the UI scale.
- **Tests must be sandboxed.** They write to `user://t_*` via `MetaState.path_prefix`
  and `SettingsState.path_override`, and disable writes on teardown — because a test
  once overwrote a real save and a debug tool destroyed a run. `tests/run.sh` fails if
  any `t_*` file is left behind. Headless runs default to a sandbox for this reason.
- **Persisted enum ordinals may only be appended to.** `EnemyData.Action`/`Trigger`,
  `RelicData.Trigger`/`Effect`, `CardData.Rarity` are stored as raw ints in `.tres`
  and saves; inserting a value silently rewrites every existing file. A test pins them.
- **Duplicated constants rot silently.** A restated number (`1.6`, a label table, an
  upgrade-cost comment) has caused three separate bugs. Derive, don't restate.
- **Scripted whole-block text edits land at the wrong indent** in an
  indentation-sensitive language and look right in a diff. Edit in place with exact
  anchors; `test_compile.gd` is the backstop.

## Layout

```
scripts/     game code — one file per screen or system; balance.gd owns all tuning
resources/   all content as .tres: cards, enemies, relics, powers, events, dungeons,
             zones, builds
scenes/      thin .tscn wrappers; screens build their UI in code
assets/      pixel/ (CC0 Kenney) and art/ (generated backdrops + painted UI frames)
tests/       34 suites + run.sh; export.sh and export_ready.sh need templates
tools/       diagnostics, not shipped: sim_balance.gd, playthrough.gd, debug_map.gd,
             screenshots.gd (renders every screen to PNG), art_manifest.gd
DESIGN.md    the full reasoning, decision by decision (D1–D62)
ART.md       the art brief: the diagnosis, the style, the reasoning
ART_ASSETS.md  GENERATED by tools/art_manifest.gd — every art file wanted, and
             whether it exists yet. Never edit by hand; regenerate it.
```

## Working rules

- **Before committing anything that touches tuning:** `tests/run.sh` (all suites) and
  `godot --headless --script tools/sim_balance.gd` (paste the numbers).
- **Before committing content or code:** `tests/run.sh` must be green, including
  `test_compile`, `PlayableTest` and `test_content`.
- **A hook re-asserts this every turn.** `.claude/hooks/docs-current.sh` (a
  `UserPromptSubmit` hook in `.claude/settings.json`) injects a reminder to keep
  these two files current on every prompt, and escalates to a STALE warning when the
  working tree has changes under `scripts/` or `resources/` but none to AGENTS.md or
  DESIGN.md. It cannot write the docs for you — it makes sure you never forget to.
- **When you make a real decision, write it down** — a new `D##` section in DESIGN.md
  with what was tried, what was measured, and what broke — and update this file's
  pillars or content totals if they changed. Keeping these two documents current is
  part of the change, not paperwork after it.
