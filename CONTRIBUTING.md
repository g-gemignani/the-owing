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
4. Generate its combat plate — `godot --headless --script tools/gen_enemy_art.gd`
   then `godot --headless --import`. The plate is keyed by archetype id and its shape
   is derived from the fight (D89), so there is nothing to pin by hand; `test_art.gd`
   fails if any archetype has no plate.

The player is shown the boss and a warning generated from its rules before the
run starts. That is deliberate: knowing what waits is what makes choosing a deck
a decision.

## A dungeon

1. `resources/dungeons/<id>.tres` — difficulty, roster, boss, card pool, encounter mix.
2. Add the id to `Balance.DUNGEONS`.
3. Add it to exactly one zone's `dungeons` list, or it is unreachable.
4. Give it a shape and a surface — `Balance.ISO_STYLE_OF` and `Balance.ISO_TERRAIN_OF`.
   There is one traversal model (D94), so the floor is the only thing that makes a
   dungeon walk differently from its neighbour.
5. Its gate lives on the **zone**, not here. Leave `unlock_after_clears` at 0 unless the
   dungeon is a genuine capstone, meaning strictly deeper than its region's gate — a
   dungeon restating the number its zone already implies is two places holding one fact,
   and `tests/test_build.gd` fails it (D178).

## A floor architecture (an iso style)

One entry in `Balance.ISO_STYLES`, plus a `Balance.ISO_STYLE_DEEP` mapping saying what it
turns into at the bottom of a dungeon, and either an `ISO_STYLE_OF` dungeon or another
style drifting into it — `tests/test_traversal.gd` fails a style nothing ever builds.

Two rules, both learned the hard way:

* **Bring a KNOB, not new numbers.** Two styles differing only by a tile of room width and
  a loop count were indistinguishable side by side (D82). `fill`, `rubble` and `spine` all
  change what the walk *is*; room size does not.
* **Measure the walk.** New geometry moves moves-per-encounter, which is bounded
  (`ISO_MOVES_PER_ENCOUNTER_MAX`) and has about half a move of headroom. The three deep
  styles cost +0.11 on their first cut and `loops` was the lever that gave it back — not
  `fill`, which grows the floor and makes it worse (D177). The instrument's noise range is
  0.34, so take a mean of several runs, never one reading.

Then render it: `tools/IsoStyles.tscn` and a contact sheet. A style signed off from a
description rather than a picture is how two of four came out the same.

## A prop set, or a chamber role

Props: an entry per terrain in `Balance.ISO_PROPS` — `name`, a `shape` from
`ISO_PROP_SHAPES`, and `on` for whether it lies on the ground or hangs on rock. A new shape
needs a drawing in `iso_run.gd`'s `_draw_prop` (and `_draw_wall_prop` if it hangs); a shape
nothing draws is an invisible prop and the traversal suite fails it.

Roles: an entry in `Balance.ISO_ROOM_ROLES`, a dressing line in `ISO_ROOM_DRESSING`, and a
weight in the `roles` of every style that should produce one.

Three rules:

* **Nothing decorative may resemble anything interactive.** The floor's whole contract is
  that what is drawn on a tile is what you get — the creature (D85), the chest's tier and
  its lock (D172). There is no crate in the table that reads as a chest, on purpose.
* **Draw it darker than the ground it lies on.** A prop is read by its shape, and pale
  props photographed as sheets of paper competing with the hero (D176).
* **Judge it in a real capture at 1280×720**, not from the constants. Three of the four
  things wrong with the first version of this feature were only visible in a screenshot.

## A pocket prize, or an errand

Prizes: an id in `Balance.POCKET_PRIZES`, a weight beside it in `POCKET_PRIZE_WEIGHTS`, and a
branch in `TraversalIso._open_pocket` that puts it on the far cell. Then **measure the pack
channel**: `godot --headless --script tools/pack_income.gd -- --packs=N`, where N is 2 plus
what a full sweep can now find. A large jump is a reason to lower the tier or the count, not a
success — the first weights took the channel up 36% and were cut (D182).

Errands: an id in `Balance.ERRANDS`, its words in `ERRAND_TEXT`, and a clause in
`TraversalIso._errand_met`. Three rules, all test-enforced:

* **It must ask for MORE.** Anything paying for declining budgeted content is a skip, and a
  skip is a difficulty change no budget assertion can see (D88, D184).
* **It must read state the model already keeps.** A condition needing new bookkeeping is the
  wrong condition — bookkeeping kept for one feature goes stale the first time another moves.
* **It must be settleable on the floor that set it**, or it is not a hard errand, it is a lie.

Both channels pay in gold or packs, never in run-deck cards (dilution, D80/D81) and never in
relics or HP (free strength from outside the deck).

## A toll question, or an aspect

Tolls: an id in `Balance.TOLLS`, its phrasing in `TOLL_ASK`, and a branch in
`TraversalIso.toll_answer`. **The answer must be computed from floor state, live** — never
stored on the pocket and never written to the save, or it is a riddle that can be memorised
(D186). Check it is not a constant: `tests/test_traversal.gd` samples every kind at every
position of a partly-walked floor and fails a kind that always answers the same. Sample on a
*walked* floor; two of the three kinds are constant on a fresh one, which is a fact about the
sample and not about the game.

Aspects: an id in `Balance.ASPECTS`, a name and a line in `ASPECT_NAME`/`ASPECT_LINE`, and its
effect wherever the floor reads the number it bends. Two rules (D187): it must be
**budget-neutral** — the test generates every dungeon in every aspect and compares quotas — and
it must **change something the plain dungeon does**, compared against the plain dungeon rather
than against a constant, because that is the only version of the check that can see a no-op.

## A debt

An id in `Balance.DEBTS`, its wording in `DEBT_TEXT`, and a clause in `Balance.debt_met`. Three
rules (D191): a debt is a condition **observed** during a run and never a modifier **on** it; its
condition must read state the run already tracks; and it may only name a dungeon the player can
reach. It pays gate credit and gold, never cards or relics.

## A gate route

`MetaState.gate_credit()` is what every dungeon and zone gate is measured against. A new
kind of evidence goes in there and is priced in `Balance` beside `depth_credit`. It must be
discounted, capped short of the deepest gate, and **printed on the sealed row** — an
alternative the player cannot see does not exist. It must not grant strength: permanent HP
is a reward for clearing, and paying it for anything else is free power from outside the
deck (D178).

## A power or relic

Powers: `resources/powers/`, then `Balance.POWERS`. Relics: `resources/relics/`,
then `MetaState.RELIC_CATALOG`. Both sit **outside the deck**, so both must report
power to `Balance.power_ratio` — `PowerData` inherits `power_value()`, relics use
`flat_power()` + `triggered_power()`. An unpriced one is free strength and breaks
enemy scaling.

## Before you commit

```bash
tests/run.sh                                    # every suite; it lists them itself
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
