# Deckcrawl

A deckbuilding roguelike with a persistent RPG meta layer, built in Godot 4.7
(GDScript). Slay-the-Spire-shaped combat, but what you carry between runs is a
*collection* you grow, fuse and spend — not a fresh start every time.

> Status: playable prototype. Art and audio are CC0 placeholders (plus a generated
> title image) and there is no animation yet. The systems are the point.

---

## What's in it

|                |                                                             |
|----------------|-------------------------------------------------------------|
| Cards          | 100, five rarities, levelled by fusing duplicates            |
| Enemies        | 35 archetypes with telegraphed intents; many react to you    |
| Bosses         | 12 — one per dungeon, named and announced before you commit  |
| Relics         | 30                                                           |
| Powers         | 10 — one equipped per run, fires once every turn             |
| Events         | 20                                                           |
| Dungeons       | 12 across 5 zones, 8 difficulty tiers                        |
| Traversal      | 3 pluggable models: node graph, card draw, dice board        |
| Tests          | 29 suites                                                    |

## Running it

Needs **Godot 4.7**. Either put it on `PATH`, or:

```bash
GODOT=/path/to/godot ./run.sh
```

There is a Nix flake if you want a pinned toolchain:

```bash
nix develop --command godot
```

## Tests

```bash
tests/run.sh              # everything
tests/run.sh softlock     # filter by name
GODOT=/path/to/godot tests/run.sh
```

Two kinds live in `tests/`:

* `test_*.gd` — headless script tests (`godot --script`).
* `*Test.tscn` — **scene** tests. Some properties only exist once a tree has
  actually been built (`mouse_filter`, wrapped line counts, scaled rects), and
  autoloads are not registered in a `--script` run.

Tests are sandboxed away from real save data, and the runner fails if any test
leaves a file behind. That is not paranoia: a test once overwrote a real
`settings.json`, and a debug harness destroyed someone's in-progress run.

## How the code is organised

```
scripts/     game code — one file per screen or system
resources/   all content as .tres data: cards, enemies, relics, powers, events,
             dungeons, zones, builds
scenes/      thin .tscn wrappers; screens build their UI in code
tests/       29 suites + tests/run.sh
tools/       diagnostics, not shipped: sim_balance.gd, playthrough.gd, debug_map.gd
DESIGN.md    the reasoning behind every decision, and every mistake
```

Two ideas run through all of it.

**`scripts/balance.gd` is the single source of truth for tuning.** Every constant
and formula lives there so the game and the headless simulator cannot drift apart.
A duplicated lookup table elsewhere once went stale and made the first dungeon
literally unplayable; the tests now reject private copies of shared tables.

**Tuning is measured, not guessed.** `tools/sim_balance.gd` auto-plays fights and
reports run completion per build per dungeon:

```bash
godot --headless --script tools/sim_balance.gd
```

Several designs that read fine on paper were reverted after the numbers came back.
Enemies that punish blocking dropped defensive builds from 74% to 32% completion
before being retuned. Fusion was measured making the player too strong too fast.
Enemy scaling once made a *maxed* deck perform worse than a merely good one. Those
stories, with the numbers, are in [DESIGN.md](DESIGN.md).

## Adding content

See [CONTRIBUTING.md](CONTRIBUTING.md). Every piece of content is a `.tres`
file plus one catalogue line, and `tests/test_content.gd` fails if the two ever
disagree — so a half-added card cannot silently not exist.

## Design notes

[DESIGN.md](DESIGN.md) is long and is the actual documentation — decisions D1
through D38, each with what was tried, what was measured, and what broke. If you
only read one section, read the ones on the difficulty ratchet (D36) and on
enemies that react (D38); both are cases where the obvious design was wrong and
the simulator said so.

## Licence

Code is [Apache 2.0](LICENSE).

The title illustration in `assets/art/` is generated and is **not** CC0; see
`assets/art/README.md`.

The rest of the art and all audio are **CC0** by [Kenney](https://kenney.nl) — Tiny Dungeon, 1-Bit
Pack, UI Pack RPG Expansion, Pattern Pack Pixel, Interface Sounds, RPG Audio and
Music Jingles. The original licence files ship alongside the assets under
`assets/`. Kenney's work is public domain and requires no attribution; it is given
here because it is deserved.
