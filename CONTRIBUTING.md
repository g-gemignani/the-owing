# Adding content

Everything in the game is a `.tres` file plus one catalogue line. `tests/run.sh`
fails if those two ever disagree, so you cannot half-add a thing and not notice.

## A card

1. `resources/cards/<id>.tres` — `id` must equal the filename.
2. Add `"<id>": "res://resources/cards/<id>.tres"` to `MetaState.CATALOG`.
3. Optionally list it in a dungeon's `card_pool` / `exclusive_cards`, or a build's
   `cards`, to control where it drops.

Illustration is assigned automatically. `CardData.power_value()` must price any
new mechanic you invent, or enemy scaling will not see it and the card becomes
free power — see `DESIGN.md` on the difficulty ratchet.

## An enemy

1. `resources/enemies/<id>.tres`.
2. Add it to a dungeon's `enemy_roster`, or to `Balance.ROSTER` for the generic
   pool.
3. Keep `hp_mult` / `dmg_mult` within about ±20%: they multiply an already-tuned
   budget.

Conditional behaviour goes in the `rule_*` arrays. Two hard rules, both learned
the hard way and both test-enforced:

* **No rules on `count_max > 1`.** Three copies of a compounding buff swamp the
  dungeon's difficulty rating.
* **No heal tied to a lasting condition** without `rule_once`, or the fight
  becomes a stalemate rather than a threat.

## A boss

1. Author the archetype as above, with at least one rule — the signature is the
   point.
2. Add its id to `Balance.ROSTER[Tier.BOSS]`.
3. Set `boss = "<id>"` on exactly one dungeon, and make sure it is **not** in that
   dungeon's `enemy_roster`.
4. Pin a sprite in `PixelArt.OVERRIDES` and make sure the tile file exists.

The player is shown the boss and a warning generated from its rules before the
run starts. That is deliberate: knowing what waits is what makes choosing a deck
a decision.

## A dungeon

1. `resources/dungeons/<id>.tres` — difficulty, traversal, roster, boss, card pool.
2. Add the id to `Balance.DUNGEONS`.
3. Add it to exactly one zone's `dungeons` list, or it is unreachable.

## A power or relic

Powers: `resources/powers/`, then `Balance.POWERS`. Relics: `resources/relics/`,
then `MetaState.RELIC_CATALOG`. Both sit **outside the deck**, so both must report
power to `Balance.power_ratio` — `PowerData` inherits `power_value()`, relics use
`flat_power()` + `triggered_power()`. An unpriced one is free strength and breaks
enemy scaling.

## Before you commit

```bash
tests/run.sh                                    # 29 suites
godot --headless --script tools/sim_balance.gd  # if you touched anything tuned
```

`tests/test_content.gd` checks catalogues against disk, ids against filenames,
every cross-reference, art capacity, persisted enum ordinals and the hand-computed
`BASELINE_CARD_POWER`. If you are adding a lot of enemies, watch the sprite
headroom line — below three spares, two enemies start sharing a face.

**Enum values are persisted** in `.tres` files and save games. Append to
`EnemyData.Action`, `EnemyData.Trigger`, `RelicData.Trigger`, `RelicData.Effect`
and `CardData.Rarity` — never insert or reorder. A test pins their numbers.

**Bumping `MetaState.SAVE_VERSION`** means adding a migration step *and* a fixture
for the old shape in `tests/test_save.gd`.
