# AGENTS.md — The Owing

Brief for anyone (human or AI) picking up this project. It is the *why*: the game's
concept, the decisions that shaped it, and the working rules that keep changes from
breaking it. The *what* — file-by-file detail and the whole decision log — is in
[DESIGN.md](DESIGN.md), which opens with a generated index; how to add content is in
[CONTRIBUTING.md](CONTRIBUTING.md); how to build and run is in [BUILD.md](BUILD.md);
what the game should *look* like, and the file-by-file asset list, are in
[ART.md](ART.md) and [ART_ASSETS.md](ART_ASSETS.md). An outside view of what it all
adds up to as a *game*, with the open work, is in [REVIEW.md](REVIEW.md).

> **Keep this file and DESIGN.md current.** Every substantive change should land with
> its reasoning written down. A decision that only lives in a commit message is a
> decision the next person re-litigates. See "Working rules" below.

---

## The concept

A **deckbuilding roguelike with a persistent RPG meta layer**, built in Godot 4.7
(GDScript). Slay-the-Spire-shaped combat, but what you carry between runs is a
*collection you grow, fuse and spend* — not a fresh deck every time.

The loop:

1. **Overworld** — pick a zone, then a dungeon. Each door you have already cleared offers its own
   debt, on the row that already names its difficulty, its boss and what it is wearing this time:
   pay gold at the door and it wants something specific of the run — the place cleared, or the
   bottom reached, or four hundred damage taken out of it, or three fights won without losing a
   point of health. Settle it and the stake comes back with gold and a pack whose tier is the size
   of what was asked; fail and the stake is gone (D191, D205). A first visit is offered nothing,
   because every debt is a wager on a number the place has not shown you yet (D248). A region opens as a region, so there are
   usually three doors rather than one, and a gate takes depth in places that beat you as
   well as clears (D178). Difficulty is a *choice*, shown up front, with the boss named
   before you commit.
2. **Deck builder** — assemble a run deck from your owned cards. The Power is no longer
   equipped here: press Start and the run deals **three, weighted by the deck you just
   built**, and you pick one on a screen of its own between the door and the floor
   (D245, D253, D256). The offer cannot be shown on this screen, because the deck that
   weights it is the thing this screen is for — three faces drawn against a deck still
   being edited would be replaced at the threshold, and that reads as a re-roll nobody
   asked for. Mid-run the bar here shows what the run is CARRYING, which is the one true
   thing left to say about a power once the offer is spent. Between
   `MIN_DECK_SIZE` and `MAX_DECK_SIZE` (20) cards, and the floor is *derived* from the opening
   collection rather than picked (D249): the deck you are handed is the smallest one the game
   accepts, so no deck is ever weaker than the one it taught you with. Up to
   six loadouts can be saved, and they are *kept* rather than piled up: a saved deck can be
   renamed and deleted from the same bar it loads from (D212). The collection is readable
   two ways off one toggle (D213): a **table** of rows, which is the surface that can put a
   hundred fuse prices in one column, and **cards**, a grid of the real painted faces you
   drag into a deck bay beside them. The deck panel sits beside **both** views (D215), because a
   stepper says how many of one card and only the panel says what the whole deck is. Both are
   the same screen, the same filter and the same selection — only the drawing and the gesture
   differ. A hundred cards need finding as well as reading, so the filter bar carries a
   **fuzzy search** (D214): near enough on the name
   is enough, and a word no name holds is looked for in what the cards *do*. Cards
   interact on purpose: a card can make the NEXT one better, or be worth more for what you
   already spent this turn — the earlier cards played, the debuff stacks on the target, the
   cards burned out of your hand, the Energy left over, whether it is the last card you hold
   (D66, D204). A turn is assembled rather than sorted by size.
3. **Run** — crawl the dungeon: a painted isometric building of rooms and corridors over
   several floors, explored a tile at a time. **Every fight in it walks, and all of them are
   walking toward you from the turn you arrive** (D197) — nothing waits on a tile, nothing
   sleeps, and the ones you outstay start taking two steps to your one. A hunter beside you
   can be fought or shaken off for health, and shaking it off costs the turn everything else
   spends getting closer. Shop, rest, hit events and crack chests, down to a named boss.
   A locked chest wants a key, and the keys are lying on the floors — off the route, in the
   far corner of some room you had no other reason to cross (D167). Which chest wants one is
   readable from the doorway: a chest stands in the light of its own tier (D172). The floor
   is dressed as a place rather than a board — props, chamber roles and a few sources of
   light per floor — and a dungeon's bottom is not its top: the surface changes as you
   descend, and then the architecture does (D176, D177). Some walls are not walls: a mark you
   can only make out from the tile beside it opens a sealed pocket with something in it, and
   usually an elite standing over it (D182, D183) — or a door that wants the key you were
   saving for a chest, or a question whose answer is the room you are standing in (D185,
   D186). Some floors ask something of you as well, written in a ledger standing in the floor's
   own lit room — you walk to it to find out what it wants, and reading it is what takes it on
   (D184, D203). What it asks is drawn from forty-five rows over a counter the fights and the
   floor both fill, so it can want damage dealt, poison landed, a wall of block, ground covered,
   or a fight won without playing an attack — and every one of them asks for MORE, never less,
   because a condition that paid for declining content would be a difficulty dial wearing a
   quest marker. A place you have already
   beaten reopens wearing a named variation (D187), a stone on the floor will change the rest
   of it for a price (D188), and a neighbour's clear opens a back door into somewhere one
   floor shorter — the same fights packed into fewer floors, so shorter and denser rather
   than easier, and only offered where the place can actually get shorter (D190, D206).
   (Three older traversal models — a node graph, a card draw, a dice board — lost to it in
   D88 and were deleted in D94; the `Traversal` seam they shared is still there.)
4. **Meta** — winning banks the run's gold and cards permanently. **Dying costs what you
   chose to risk and never what you already owned (D231, D235):** the escrow pays back a
   share set by depth, the door stake stays forfeit because it is the one cost you placed
   yourself, and the collection pays *nothing* — `penalize_death` is deleted. Between runs
   you fuse duplicates into levels, level Powers, and unlock deeper zones. **Gold does not buy
   a Power (D290): a character starts owning six, and each of the twelve dungeons hands over two
   more the first time you beat it.** A price is a gate a patient player pays without going
   anywhere, and it made the pool a function of income rather than of play. A place can only be
   paid for by playing the thing the power is meant to reward.
   **Relics are not in that list, because a relic does not persist (D238).** It is found on
   a run — three offered by an elite, three by a chest — and it leaves when the run does,
   won or lost. What survives is `MetaState.relics_seen`, a record of what the character
   has MET, deliberately the one part of a relic that carries no power. The thirty-eight
   are still the long tail of the *catalogue*: each rarity is
   sealed until you have cleared enough, and the last of them do not open until four
   clears past the twelfth dungeon (D223), so meeting the whole set is something you do
   after the game rather than halfway through it — the gate now governs what may enter the
   pool rather than what you own. **Rarity is a claim about strength,
   and it is derived rather than authored** (D224): every card's and every relic's band
   is written from `power_value()` by `tools/rerarify.gd` — cards, relics and the thirty
   Powers alike (D225) — the bands may not overlap, and the rarity suite fails a
   catalogue where a common outranks an uncommon. It is not a colour: it sets the level
   cap, the growth rate, the drop weight, the shop price, how many clears a relic waits
   for, what a Power costs to level, **and which dungeon hands a Power over** — the grant map is
   ordered by rarity and dealt over the twelve dungeons shallow to deep (D290), so the deepest
   places give the rarest powers.

   D255 put that pacing behind `Balance.POWER_UNLOCK`, a clears count indexed by rarity, and
   D290 deleted it along with `power_price`: **two gates on one thing is what made the powers
   screen need four row states and a paragraph of apology (D289).** What D255 FOUND survives the
   deletion and is why the new map is still ordered by rarity — an authored gate and a derived
   price disagreed about the same power, Short Change LEGENDARY behind 2 clears while Hold Fast
   waited 10 as a middling RARE. **A number that is authored and a number that is derived from
   the same subject will disagree, and the derived one is right.**

   **And the suite only ever checked the CARDS, for two hundred entries (D250).** Relics and
   powers wore a derived rarity with nothing asserting it, and it went wrong silently: the
   legendary guard asks whether a card *changes a rule*, that question was a hand-written list of
   eight fields, and it knew nothing of the conditional mechanics D66/D204 added — so a power
   whose whole identity is `discount_next` read as "only numbers" and was skipped for the top
   band. **LEGENDARY came out weaker than EPIC and nothing failed.** `changes_a_rule()` is now
   derived from the property list, lives on `CardData` as the ONE owner (the tool and the suite
   each held a copy, and they disagreed about `grows` the moment one was fixed), and the suite
   checks all three catalogues. **A field added later is a rule-changer by default** — the safe
   direction, since a new mechanic is more likely a rule than a number. D180's rule in a third
   costume, after D89's art list and D180's own relic-field list.

Two-tier state makes this work:

- **`MetaState`** — the persistent character: collection, decks, powers, gold, clears,
  and `relics_seen` (a record of relics met, at zero power). On disk, versioned, migrated.
- **`GameState`** — one ephemeral run. Rebuilt each dungeon, risked on death. **The
  relics a run finds live here** (`run_relics`) and are lost with it (D238).

## Content at a glance

100 cards · 8 build archetypes · 35 enemy archetypes (all painted) · 12 bosses (one named per
dungeon) · 38 relics — **counted off the catalogue at D262, not off `breaks_a_rule()`**:
21 conditional rules, 4 pure triggers, 11 that carry one flat `damage_pct` or `block_pct` and
nothing else, 2 flat energy or draw (D233/D237/D243/D257). The predicate reads 36 of 38 and that
is not the same claim — it went blind to the four pure triggers until D262 added the term, and it
still counts a lone flat percent as a rule ·
30 powers (13 lean attack, 7 lean defence, 10 neutral; three dealt to suit the deck, on their own
screen, D253/D256 — six owned from the start and two handed over per dungeon beaten, never bought,
D290) · 20 events · 12 dungeons across 5 zones · 4 difficulty rungs · 1 traversal
model · 7 floor architectures × 4 surfaces × 6 chamber roles × 16 props × 4 landmarks ·
4 pocket prizes · 3 pocket mouths · 3 toll questions · 45 errands and 16 debts over 44 counters · 3 aspects ·
24 sound effects · 5 score tracks · 49 test suites. All content is `.tres` data
plus one catalogue line; adding more is a data task, not a code task.

**Art: 434 files wanted, 434 present, 0 to provide — the list is CLOSED again (D296).**
was 205/205/0 at D129, then D131 opened Tier 3b (one illustration per card) and took it to
205/305; the hundred were painted four to a picture, a 2x2 grid of 4:3 cells tiling one
4:3 image, which turned a hundred browser requests into twenty-five (D136). It closed at
386/386/0, was reopened to 386/414 by the 8 relics and 20 powers that D233, D237 and D250
added, and D259 closed it: every relic and every power now has its own icon and no power
falls back to a drawn letter. It reopened once more to 414/430 for the sixteen isometric
props D282 put on it — the dressing that varies one floor from the next, drawn in code
until then — and D286 closed it off one sheet. Then to 430/434 for the four landmark caps,
which D282 had skipped for want of filenames that turned out to exist already, and D296
closed it. The shopping
list is
generated — `tools/art_docs.sh`, which writes ART_ASSETS.md and ART_PROMPTS.md together
— so it cannot fall out of step with the catalogues **once it is re-run**. It went three
content passes saying 386/386/0 while the manifest underneath it had known better all
along, because `--check` existed and nothing called it. A generated
document with no check is a document that is true on the day it is written, so
`tests/run.sh` is the caller now (D262): the run fails after the suites pass if either
generated document is out of step with what generated it. Two things in it are not paintings and
never will be: the frame kit is computed by `tools/gen_ui_kit.gd`, and the six combat
effects are drawn at runtime by `scripts/fx.gd`.

**Not everything generated is checked, and the gap is on purpose.** The README's seven
screenshots (`tools/screenshots.gd`, then `tools/readme_shots.gd`) are a claim about what
the game looks like now, and no test can tell a stale picture from a current one — re-run
both after anything visual lands. `tools/readme_downloads.sh` is left out of the gate
deliberately: it reads the GitHub releases API, and a test run that needs the network
fails on a train. Run it by hand before a release, which is the only time its subject
moves.

## The two ideas that run through everything

1. **`scripts/balance.gd` is the single source of truth for tuning.** Every constant
   and formula lives there, so the game and the headless simulator cannot drift. A
   duplicated lookup table elsewhere went stale once and made the first dungeon
   literally unplayable (D34); the tests now reject private copies of shared data.

2. **Tuning is measured, not guessed.** `tools/sim_balance.gd` auto-plays fights and
   reports run-completion per build per dungeon. Several designs that read fine on
   paper were reverted after the numbers came back. When you change anything that
   touches difficulty, run the sim and paste the numbers into the commit.

   **Three things about the instrument, all learned the hard way.** It does not seed its
   RNG, so *establish the noise floor before believing a delta* — two runs of identical
   code differ by a mean of 0.4 points with one cell swinging 15 (D120). And **check
   that a profile in it actually holds the thing you changed.** Its twelve profiles
   contain no draw relic at all, so it reported "no measurable effect" for a hand cap
   that fires on 77% of a real draw build's fights; the delta was real and the
   instrument could not see it. A tool that cannot play the build cannot price it, so
   the policy was fixed first and the relics priced afterwards (D124) — and fixing it
   moved five cells by ten points or more, including two the project had been reading
   as "the endgame is brutal" that were the driver burning its turn on a card it could
   not use. **A number the simulator reports about difficulty may be a fact about its
   policy.**

   **And the third: it has to read the numbers the CARD reads (D204).** Every pass in the
   driver read `eff_damage()` / `eff_block()` / `eff_cost()` — a card's authored numbers —
   which made it blind to every conditional mechanic in the game, not just the new ones.
   Split read as 4 damage into a target holding six Poison. An X-cost card read as a
   1-cost bargain and then ate the whole turn. It now goes through `card_damage`,
   `card_block` and `play_cost`, the same functions the card face reads. The same pass
   found a hand-burner the driver played every single turn and then, over-corrected,
   never at all — **a guard that turns a mechanic off measures the same nothing as a
   policy that abuses it**, and both readings look like a verdict on the cards.

   **That hole was closed for draw and left open everywhere else, and the second half
   cost more than the first (D180).** Two years after D124, the same shape: of thirty
   relics the profiles held ten, and nine of those ten were flat numbers. Four of the
   five relic TRIGGER kinds never fired once in a full report, and `GAIN_ENERGY` — on
   the one resource `power_ratio` is *defined* against — was one relic in the catalogue
   and zero measured. Worse than uncovered: `heal_after_combat` was applied in
   `combat.gd` and nowhere in the simulator, so Healing Idol measured as strictly
   **worse than no relic**, paying ratio points that raise enemy scaling and returning
   nothing to a metric that is pure attrition. **The fix is not another profile, it is a
   check that DISCOVERS its subjects** — `tests/test_relic.gd` now walks `RelicData`'s
   own property list and both its enums, so a field or a trigger the game reads and the
   tool does not is a failing test rather than a discovery. Coverage kept by a list of
   what somebody remembered is the D89 art bug in a third costume.

   **And the third instance was not coverage but ARITHMETIC (D208).** With every relic
   effect finally delivered, the profiles still held the wrong *number* of them: `clears`
   grew the HP bar through `Balance.max_hp_for` and nothing else, while in the game a boss
   drops a relic on every clear and relics are never lost. Eleven rows of fifteen wore
   fewer relics than their clears guarantee — three of them wore none at six clears. Half
   a progression is a player nobody plays, and dressing them properly moved **42 cells by a
   mean of +17 points**, one by +81. The matched-progression cells then read 86-100%
   against a target band of 40-60%: *the tuning had been fitted to a player who owned
   nothing.* So the check is not only "does a profile hold the thing you changed" but
   **"is this profile a player the game can produce?"** — every stat on a profile that the
   game derives from another must be derived here too, or the two halves of one
   progression disagree inside a single row.

   **And when you retune against it, check the knob is still connected (D209).** The
   correction above put the report at 86-100%, and the obvious lever —
   `DIFFICULTIES[*].ratio` — could not bring it back, because `scaling_ratio` clamps the
   multiplied ratio to the dungeon's ceiling and **it was already a no-op in 25 of 42
   cells**: three of the four difficulty rungs were the same enemy damage in most of the
   game. Sweeping it 2.8 -> 12.0 bought five points. A tuning constant that has been
   clamped away reads exactly like a constant that is correctly set. Sweep a knob to an
   absurd value before you trust a small move from it; if the game barely notices, you are
   tuning something the code throws away.

   The lever that did work was `DMG_POWER_K`, because it scales with the PLAYER'S power
   rather than flat — which is the general rule this project keeps relearning: **a global
   multiplier cannot tell the middle of the game from its ends.** Flat damage hit the
   target mean and took the first dungeon from 96% to 23%; a steeper ratio ceiling hit it
   and cost the deepest cells another 5-23 points. When the walkover is in one region,
   the fix has to be shaped like that region.

   **And a difficulty rung's multiplier can point the wrong way while reading as bigger.**
   The retune ended by moving the `ratio` column DOWN (2.8/4.0 to 2.4/3.2), because above
   about 1.6 a built deck is clamped by `ratio_ceiling` and every further point lands only
   on the deck too weak to be clamped — the ladder had been punishing the beginner and
   sliding off the veteran. `tests/test_difficulty.gd` is the guard for that, and it found
   it in the shipped numbers only because a different change walked into it. Its probe is
   a single integer damage value that quantises in ~6% steps while asserting a 10% margin,
   so **it flips on rounding**: 0.095 fails and 0.105 passes. Tune against a probe averaged
   over rolls, turns and tiers, and never take a value because that guard happened to go
   green.

   **And it measures difficulty only — until D229 nothing in the tree could see fun.** The tool
   now prints a second line per cell: `esc` (median last-fight damage-per-turn over first-fight,
   the escalation a run delivered), end-of-run HP and fights-survived percentiles, deck
   divergence between consecutive runs, and the share of card choices with a live runner-up.
   All diagnostic, none pass/fail, because a fun metric with a threshold becomes a thing that
   gets tuned toward. `--noise` reads every cell twice and prints the gap, which is the only
   thing that says whether a delta is a change: at 400 trials `esc` moves ±0.05x, at 60 trials
   ±0.11x. The first baseline read 0.78-1.32x, mean 1.08x, and that spread was an artifact:
   damage per turn rises with the NUMBER of enemies in a fight, and a won run's last fight is
   always the single-target boss. Readings now come only from NORMAL fights the run won (D232).
   **The corrected baseline is `esc` 0.94-1.18x, mean 1.05x, and `esc@3` is 1.05x too** — so
   the curve is not back-loaded, it is flat end to end, and no cell reaches 1.5x. Won runs read
   1.07x against lost runs at 1.02x: winning is barely more escalated than losing. That is the
   measurement D226 is aimed at. It also refuted half of D226's own reasoning: `real` 48% and
   `solved` 8% say the turn-level decision is live, so the flatness is in the ARC and not in
   the turn.

   And when you add a rule to that policy, **count how often it fires.** The first
   version of the draw gate looked principled and declined nothing at all — 1,498
   opportunities, zero refusals — because every card it would have caught costs zero
   energy. A full report agreed it changed nothing, which is exactly what a correct
   no-op looks like too.

   **And count it over the whole report, because one cell is not a sample (D276).** The
   card driver's new skip rule read `skipped 0%` on 111 offers from one shallow dungeon, and
   the entry was nearly written calling it redundant. Across 51 cells it is **21%**. A
   firing rate read off one cell is a guess wearing a percentage.

   **D239's fault was still open on the larger reward surface, and it cost more (D276).** The
   game lays out three cards with a Skip under them and the driver dealt ONE and kept it, so
   it was not making the decision the game makes — on the surface a run touches once per won
   fight, against at most eight relics. A third of the cards it accepted were ones the reward
   screen itself calls *"WEAKER than what you hold"*. Choosing from the three, scored by
   `Balance.card_vs_deck` — **the screen's own function, not a second opinion** — is worth
   **+0.20x of `cap` and +0.15x of `esc` with completion unmoved**, which is D231's shape at
   last: the deck grows more without the game getting easier. Every report before it was
   paying a dilution cost the player would refuse.

---

## Design pillars (the goals we keep returning to)

- **Priced power must equal delivered power.** Enemies scale to *deck power per
  energy* (`Balance.power_ratio`). Anything that makes the player stronger from
  *outside* the deck — a relic, a power, a run removal — must be folded into that
  ratio, or it is free strength that breaks scaling. This mistake has been made and
  caught for total-deck power, per-card power, block-vs-damage, relics, powers and
  triggered relics.

  **The pillar was never cut, and three earlier entries were wrong to say it would be (D238).**
  `power_ratio` still prices everything it is given; relics are simply no longer given to it. They
  reach a fight through `CombatEngine.setup`'s `p_untaxed` slot and the priced argument is `[]`. A
  rule stated correctly does not need changing when its subject moves. Relics now live in
  `GameState.run_relics` and are lost when the run ends however it ends; `escrow_relics`,
  `grant_relic` and the sim's `_worn_relics` are deleted, and the D68 die-on-purpose exploit stops
  existing rather than being guarded.

  **And moving them was necessary but nowhere near sufficient, which was measured before it was
  built (D230).** `CombatEngine.setup` has a trailing `p_untaxed` slot — relics whose effects
  apply and whose power is kept out of `power_ratio` — and `tools/sim_balance.gd --spoils=N`
  lends every run N of them. Eight free relics move the escalation from 1.09x to **1.18x**,
  saturating by five, against a target of 3x; what they do buy is eight points of run completion
  and six of end-of-run HP. Because only **5 of the 30 relics that existed then raised what a turn
  is worth** — eleven kept you alive, three paid you — so a draw of eight expected 1.3 that could
  raise damage per turn. **Untaxing the relics as they existed then is a difficulty reduction
  wearing a power fantasy's clothes**, and shipping it alone would have spent the pillar to buy a
  tuning change. (That count is D230's reading of a 30-relic pool. D233, D237, D243 and D257
  rebuilt it: 38 now, and the composition is in "Content at a glance".)

  **The rule now reads: persistent power lives in the deck and is priced; found power is free
  and temporary.** Relics are found in a run and leave with it (D238), so the invariant above
  binds the deck, the equipped power and every run removal — and binds them exactly as hard as
  it did. What it no longer reaches is a relic, because a relic is no longer something you own.

  **And since D299 it no longer reaches a card the run gave you either**, which was the other
  thing on the wrong side of that sentence: a won card is found, it leaves through the escrow, and
  it was raising the number the enemies scale against. The game already said so — the reward
  screen prints *"WEAKER than what you hold"* and D276 measured the driver refusing those offers.
  **A reward the player is right to refuse is not a reward.** `CombatEngine.setup` prices the deck
  you walked in with; `earn_card` marks what the dungeon hands over and is the one writer, so the
  fight reward, the shop and the event screen are all covered by one line. Measured over the full
  table: **cells at 0% completion 36 → 19, profiles that clear nothing anywhere 8 → 4 of 19**,
  against three new cells at 100%. `cap` barely moves, and that is the shape — this is not more
  deck growth, it is the same growth surviving to be used.

  **So every relic COUNT the player sees is `relics_seen` — what the character has met — and
  never `MetaState.relics`, which nothing has written to since (D247).** That array is empty on
  any save started after the change and `.size()` on it is a plausible-looking zero, so five
  screens printed "Relics 0" for eight decisions and all of them read as working code.
  `tests/test_relic.gd` greps `scripts/` for `MetaState.relics.size()` and fails on it, because
  no behavioural test can see a wrong integer that renders correctly.

  Measured end to end: escalation went from **1.05x** (D229's corrected baseline, no cell above
  1.18x) to **1.29x mean and 1.53x at best**, with `esc@3` at 1.32x — the escalation arrives
  early rather than at the boss (D239).

  **The death rate target is MET (D244): `ENEMY_DAMAGE_BASE_MULT` = 1.6 puts completion at 39%
  with deaths at fight 2.7 of five, and `real` held at 51%.** It sits in `enemy_damage()` and not
  in the `DIFFICULTIES` table, because a constant multiplying all four rungs equally cannot flatten
  a rung's slope — and `test_difficulty`'s probe now sums 72 readings instead of one, which is the
  fix AGENTS.md nominated for exactly this moment. Escalation reads 1.53x and TURNS-TO-KILL reads
  1.40x, so two independent yardsticks agree: **1.5x is a fact about the design, not an artifact of
  the metric.** Per-cell completion now spans 0-99% and needs fitting per cell.

  **`esc` was the wrong yardstick and the 5x has arrived on the right one (D265, D266).** Five
  separate player-side changes left `esc` flat at ~1.6 — the content pass, an enemy-damage sweep, a
  commitment tilt, a build-planning driver, and 50% more relics. It reads damage per turn out of a
  fight that ENDS, so once the deck can kill inside the fight it reports enemy HP growth and nothing
  about the player. **When every change to one side of an equation leaves a number unmoved, the
  number is about the other side.**

  `cap` replaced it: damage per turn against a target that cannot die, sampled at both ends of a run
  and played with the same driver the real fights use. It now reads **median 3.27x, mean 4.72x, max
  20.04x** — the 5x, on a metric that did not exist when it was asked for. Completion sits at 38%
  and `real` at 47%, which has held near half through nine consecutive changes.

  **D241 is discharged and D280 replaced it.** What got the growth there was not content: it was
  D270's within-run difficulty ramp (nothing had raised enemy strength as a run descended, so the
  first fight was the hardest moment in the game) and D275's pacing (the floor is the unit now, and
  depth adds floors — The Maw is 20 encounters against the Crypt's 10, where both were 12).

  **What is left: archetype spread, and block's double job (D285).** Combo clears 100% at the
  Foundry and Status 4%. Re-pricing block would help the defensive builds and is refused for now —
  `BLOCK_VALUE` is the numerator of `BASELINE_CARD_POWER`, the divisor of every ratio in the game,
  so moving it opens the unpriced-throughput hole in powers. Splitting it into a shop price and a
  scaling weight is the real fix. The playtest is live rather than pending — the player is playing,
  and "the dungeons feel off" is where D275 came from.

  **And the pillar is about to take a deliberate, bounded wedge (D291, decided and not built).**
  Because the ratchet prices every fused level, fusing raises both sides of the equation and cannot
  move a wall: a twelve-card deck at d4 prices 8.56 at Lv15 and 13.19 at Lv40, both under the 20.90
  ceiling, so 289 copies and 48,076 gold buy the same fight. The grind pays nothing until the ratio
  crosses the ceiling and then the dungeon collapses at once, which is the worst shape a grind can
  have. So a card will be priced at `PRICED_LEVEL_FULL` (10) levels in full and a
  `PRICED_LEVEL_SHARE` (0.25) of everything above, while delivering at its real level — bounded at
  about **1.5x**, against D230's yardstick that every relic in the game handed over free is 1.18x.
  The first ten levels stay fully priced, so D36's opening promise holds. **Nothing is built: the
  entry is the decision and the arithmetic, and both constants have to be swept per cell first.**

  **Built, and the share was wrong by a factor of two.** `PRICED_LEVEL_FULL` 10 and
  `PRICED_LEVEL_SHARE` **0.50**, applied inside `power_ratio` and not in `deck_power`/`deck_cost`
  — those two are what `card_vs_deck` divides by, and the reward verdict is a claim about
  DELIVERED power. The 0.25 D291 wrote down was read as one `power_ratio` over another, and
  `power_ratio` ends in `soften_ratio`, so every figure in that table came out flatter than the
  strength a player gets: 0.25 hands a maxed deck **2.74x**, not the 1.51x predicted. **A ratio of
  two numbers that have each been through a softening transform is not the ratio of the things
  they came from.** At 0.50 it is 1.11x at Lv15 and **1.48x at Lv40**, the realistic top of the
  grind. Measured: matched completion **36% → 40%**, cells at 100% **6 → 4**, and the gains land
  on the fused profiles because they are the only ones above the cap (Late 6% → 41%, Deep 4% →
  26%).

  **A guard found blind on the way, and not yet fixed (D291).** `test_upgrade.gd` pins
  `MAX_ACHIEVABLE_RATIO` against **ten copies of `hack`** — 23.14, comfortably under 31.7. Twenty
  maxed `cheap_shot` is an equally legal deck (`deck_valid` bounds the size and nothing bounds the
  copies) and prices at **54.49**, past the deepest dungeon's ceiling of 33.25, because
  `power_ratio` is power per energy and that card costs 0. It is an overcharge rather than an
  exploit — D280's archetype fault at its limit — and the lesson is the older one: **a guard that
  names its subject guards nothing new.** D89's art list in a fourth costume.

- **State the denominator, or the percentage is not a measurement (D298).** D285 records
  completion at 38% and a remade table read 16%, which looked like the plan's floor falling out.
  They are different statistics: 16% is the mean over all 51 cells, and most cells are
  deliberately mismatched — a Lv15 deck at the Maw should read zero. Meaned the way the target
  band means it, each profile at its own dungeon, it is **33%, and 33% at all three points
  checked** (before D290, before this session's code, now). The tool prints no summary figure, so
  every such number in this file was computed by hand and none of them say over what.

  **And when two columns of one report disagree about a collapse, check which one changed
  subject.** Nineteen boss cells read 100% → 0% across the same session — because D295 fixed
  `_measure` to pass the dungeon's boss, and before that fix the column had been fighting a trash
  archetype wearing boss multipliers. The cells did not fall; they had never been measured. The
  RUN column, which has always fought the named boss, did not move.

  **Eight of nineteen profiles complete 0% of their runs at every dungeon they are measured at** —
  Poison, AoE, Combo, Vampire, Draw, Late, Endgame, Deep — and that is identical in the
  pre-session baseline. It is the oldest open item in the project and the number to move. D299 and
  D301 took it to four; D303 says what the last four are.

  **It takes TWO columns to see it, and neither works alone (D303).** Defensive share against
  ratio: Maxed commons carries the second-highest ratio in the game and clears 69%, because 36% of
  it is Block; Status carries almost no defence and clears 95%, because its ratio is 4.43. The
  clean pair is **Status against AoE — the same 12% defensive share, ratio 4.43 against 12.56,
  completion 95% against 1%.** So `power_ratio` raises enemy DAMAGE against a deck's total power
  while only its DEFENSIVE share can answer that damage: **a deck that grows on offence is charged
  on the axis it did not grow**, every turn of every fight. D285's *block is one number wearing two
  jobs*, reached from the other side.

  Two repairs were built for this and both were refuted by measurement — a survival term in the
  driver (fired on 1% of 11,954 offers) and an offer that ignores affinity (matched completion 52%
  → 51%). What settled it was sweeping the driver's defence weight to an absurd 100: forced to take
  every guard bundle it is ever shown, all four still complete 0%. **One run of an absurd value
  said what two plausible builds could not.**

- **Completion percentage is a constraint, not the goal (D231).** The tool has printed
  `Target: RUN completion ~40-60%` since D54 and every difficulty entry since has been an
  argument about moving cells into that band. Under the goal this project is now aimed at —
  *the minutes are good whether or not you win* — that target scores a thrilling loss as a
  failure and a walkover as perfect. Completion must not be 0% and must not be 100%, because
  both mean the outcome was decided before the run started; nothing is tuned toward the middle.
  What is steered by is `esc` and the spread. **And escalation has to arrive EARLY** — a run
  that is flat for six fights and triples on the boss had six ordinary fights — which is why
  `esc@3` and a won/lost split of every fun number come before the content work.

- **Difficulty comes from depth, not from your own growth.** A dungeon scales to the
  player only up to a ceiling set by its difficulty (D36). You outgrow the Crypt; you
  never outgrow the Maw. Progression should *feel* like progression — HP lost per
  fight must fall as you get stronger, at any fixed depth.

  **And that pillar had only ever been asked of ONE tier, which is where it inverted (D301).**
  `tier_hp_power_k(BOSS)` was 1.00 — "the boss answers fully" — and answering fully means scaling
  boss HP 1:1 with the player's output, cancelling their growth exactly. Measured at a fixed
  depth: turns-to-kill FLAT at 38.8 from ratio 2 to 14 while turns-to-die fell 4.4 to 2.1. **A
  stronger deck killed no faster and died twice as fast**, which is what four archetypes clearing
  nothing anywhere turned out to be — all four read N 100%, E 63-100%, B 0%. It is 0.65 now, swept
  against a check that asks the property of EVERY tier: matched completion **40% → 52%**, cells at
  0% **18 → 12**, and the gains land on the decks that got stronger (Deep 26% → 79%, Maxed 7% →
  69%). Ask a pillar of every tier, or it holds only where somebody once looked.

- **A difficulty knob in THIS game must scale with the player, because the enemies
  already do.** The obvious design — one constant multiplying enemy HP and damage — was
  built, measured and deleted (D175). Enemies scale to `power_ratio`, so a flat number
  lands hardest on the deck with the least slack: at enemy damage x1.50 the tutorial
  Crypt fell 99% → 34% and the Ossuary 69% → 1%, while every walkover cell (Barricade at
  the Warrens, Late at the Drowned Market) sat at 100% and did not move. **It walled the
  opening and left the too-easy cells exactly where they were**, and the aggregate hid it
  — the mean slid 86 → 74 → 57 the whole time, looking like a working ladder. The knob
  that works multiplies the ratio enemies are scaled AGAINST, inside `scaling_ratio()` so
  the ratchet above still clamps it: nearly free at ratio ~1, expensive at ratio ~15.
  Ask of any difficulty control: does it cost the strong player more than the weak one?
  And check that per cell — a mean cannot see the shape.

- **A boss bends a rule; every other enemy is a number (D295).** `EnemyData.Action`'s eight verbs
  are all quantities, so twelve named bosses read as twelve big cultists. Each now carries exactly
  one signature — a hand ceiling, a cards-per-turn ceiling, what Block is worth here, or the first
  card each turn burning — named on the dungeon row before you commit (D41, D187) and again as a
  band under the boss's name for the whole fight. Measured over 36 cells the aggregate does not
  move (**mean boss −0.7, run −0.5 points**) while the cells that do move are the decks the rules
  are aimed at: the Draw build, the strongest in the game, loses 17 points to three-cards-a-turn.
  **Three of the first seven fields were deleted for being cliffs rather than dials** — a card
  tax, an Energy tax and a draw tax all subtract from a per-turn resource, and the smallest step
  each can take is a third of the Energy or a fifth of the draw. The card tax took the Ember Road
  from 87% to 0%; the draw tax took the tutorial Crypt from 85% to 19%. **A knob whose smallest
  step is a cliff is not a knob**, and that is the arithmetic to do before authoring a signature,
  not the fiction — the card tax had the best fiction on the board.

  **And the fourth cliff was found by closing a coverage gap, not by the sweep.** Those readings
  covered eight of the twelve dungeons the profiles visit, so four signatures had never been in a
  measured cell — D124's fault committed while quoting D124. One of them was a `sig_hand_cap` of
  **4** against a `HAND_SIZE` of **5**: −12.9 points of boss win rate and −61 on the Draw build.
  **At or above the opening draw a hand cap takes only cards the player was holding and dials
  smoothly; one below it eats the base draw and becomes the draw tax already deleted.** The caps
  are 7 / 6 / 5 by depth now (mean boss −2.1 over 27 cells) and `test_signature` fails one under
  `HAND_SIZE`.

  **And the instrument said all of it was free, because the `B` column had never fought a boss.**
  `sim_balance.gd`'s `_measure` passed `""` for `p_boss`, so a column headed "Dungeon Boss" rolled
  a TRASH archetype at boss budget for the whole life of the tool. Found only by sweeping three
  signatures to absurd values and watching the report move by ±3 (D209's rule earning its keep).
  D124 and D180 in a third costume.

- **Every turn should have a floor and a ceiling.** Powers (once per turn) put a floor
  under a bad draw without raising the ceiling on a good one (D37). **The power is DEALT at the
  start of a run now — three offered, one taken (D245), rolled by `GameState.select_dungeon` and
  carried in the run (D252)** — so each run has a different centre
  instead of the best owned power every time. It buys variance and cannot buy escalation: a power
  held from the first fight raises the first and the last equally, which is the third time that
  fact has decided something here (D233, D237, D245). **Thirty powers now (D250)** — twenty authored, varied in
  kind rather than magnitude, most of them using the conditional fields D66/D204 built for cards.
  All thirty are reachable: 200 offers on a cleared save show every one, and every one comes up
  first. Six were too strong for `test_power`'s 1.6x ceiling and were retuned against a measured
  column, not guessed; Hold Fast then failed the OTHER way, too weak for its cost and therefore
  unpriced, which is a narrower window than it looks. Reactive enemies
  and named boss signatures make each fight a puzzle rather than a solved routine
  (D38, D41). Block cannot be a complete answer at depth — piercing damage keeps
  defensive play honest (D45).

- **A reward is a direction, not a card (D297).** A fight paid one card of three, which in a
  fourteen-card deck is a change the player cannot feel — eight won fights meant eight cards
  picked one at a time, pointing eight ways. It pays one BUNDLE of three now: two cards named
  after the build they come from, so eight wins point mostly one way. The bundles ARE the eight
  builds (`resources/builds/`), intersected with what this dungeon can drop, so `test_build.gd`'s
  old rule that a build's cards are scattered across zones (D96) is already the rule that stops a
  bundle turning a dungeon into a farm. Measured: `cap` median **1.25x to 1.80x** with completion
  unmoved at −0.1 points over 36 cells — the deck grows half again as much and the game does not
  get easier, which is D231's shape at four times D276's size.

  **And what you may BRING is 14, down from 20.** Eight cards of toolbox out of a hundred owned is
  an archetype decided at the deck builder, which is what D280's table is a picture of. The cap
  never reaches the simulator — profiles are literals and never pass `deck_valid` — so its whole
  effect there was that seventeen of nineteen profiles became decks the game would refuse. They
  are trimmed, and `test_balance` parses the literals and fails on any that goes over (D208's
  question, made mechanical).

  **The first build measured as a failure and it was a level-1 face.** `bundle_vs_deck` looked its
  cards up with `Balance.card(id)`, which returns the level-1 catalogue instance, so every bundle
  was scored as level-1 against a Lv15 deck: the driver skipped **88%** and the screen told the
  player every offer was "WEAKER than what you hold". Two other diagnoses were tried and
  disproved by measurement first (a bundle of ONE still skipped 80%, so not the size; a
  rarity-weighted roll still skipped 85%, so not the pool). D50's drift, and `_roll_rewards` had
  carried the fix for it since D50 — it moved into `combat._reward_face` without the scoring
  moving with it. **A number that is right in the panel and wrong in the score is a decision the
  player and the tool make differently**, and only a firing count could see it.

- **A run is a risk with an arc.** You commit a deck, earn cards that dilute it, and
  can thin or sharpen it at shops and rests (D46). Death forfeits the run's takings;
  the meta layer is what survives.

  **And death costs what you chose to risk, never what you already owned (D231, built in
  D235).** It cost three things and now costs one and a fraction: the escrow pays a share set by
  depth (`Balance.escrow_salvage`, half at the bottom, almost none on the first floor), the
  collection pays **nothing** — `gold_loss_fraction`, `cards_lost_on_death` and
  `penalize_death` are deleted — and the door stake stays forfeit *because* it is the one cost
  the player consciously placed. Discoveries bank win or lose in `MetaState.relics_seen`, at
  zero power, which is also the mechanism step 5 needs. `MIN_KEEP` STAYS: D231 said the softlock
  guard would go with the penalty and that was wrong, because `can_fuse` needs the same floor.
  A guard with two subjects only loses the one that went.

- **The voice is content, and it belongs on the things the player handles.** Plain
  Anglo-Saxon, concrete nouns, mortuary and debt imagery, understatement — *"Cold stone
  and old debts"*, *"His pack is intact. He is not."*, The Grave-Sexton, The False Step.
  It was the strongest writing in the project and it was confined to flavour text, where
  it did no work, while thirty-six cards wore another game's names (D98). Cards now come
  from the same register. **Borrowed genre grammar is fine; a borrowed proper noun is
  not** — Block and Energy and intents are how the genre speaks, but a card called
  Bludgeon that deals exactly 32 and exhausts is somebody's specific design, and the
  constant is the tell. When new content needs a name, take it from `resources/events/`
  and the boss roster, not from the game this one is shaped like. **The rule binds the
  title hardest, because that is the most-read string in the project.** The game was
  called *Deckcrawl* — genre grammar promoted to a proper noun, the one name in the tree
  written in a different language from The Grave-Sexton and The False Step, and naming
  the interface rather than the fiction. It is **The Owing** (D127): definite article,
  one concrete noun, Old English root, and it names the loop — the meta layer is a debt
  you take on going down and settle by coming back.

- **Every traversal model must cost the same, and charge for the right thing.** A model
  spends the attrition budget it is given or a difficulty rating stops meaning one thing
  (D14) — checked as an average in `tests/test_traversal.gd`. Each also needs its own
  priced decision, and the price must fall on what the model is *about*: the deleted deck
  model charged to see less of a dungeon, the crawl charges for being caught in it. The
  crawl's first attempt charged for *walking*, which is the thing it exists to sell, and
  the mechanic was deleted (D77). **Equal encounter counts are not equal cost.** All four
  models passed the count assertion at 13.2 while the graph was running 7.2 fights against
  a mix asking for 4 — it took its size from the mix and its contents from five fixed
  percentages with COMBAT as the fallback (D84). When a model's shape changes, check fights
  actually *met*, not just the budget. Only the crawl is left (D94), and the test still runs
  over an array of models rather than over one, because that is the wiring a second one needs.

- **Walking is bought, not granted.** `ISO_MOVES_PER_ENCOUNTER_MAX` is a ratio, so the
  way to make a dungeon bigger is to give it more to walk toward — chests took the iso
  floor from 78 tiles to 130 and the measured walk *fell* from 7.1 to 6.8 (D84). Adding
  tiles alone would have failed the suite, and deserved to. Keys on the floor cost 0.1 of
  the same ratio (6.9 → 7.0 of a 7.5 ceiling, D167), which is what a detour that is worth
  taking is supposed to cost.

- **The floor is the beat, and it cost no tiles (D240).** A chest offers three relics and the
  arrival line says what the floor is carrying, so the escalation is countable — and both halves
  reuse tiles that were already walked to, so the measured walk stayed at 6.7 moves per encounter
  against a ceiling of 7.5. The arithmetic was done BEFORE building, per D79, and it said not to
  spend the 0.8 of headroom it had found. What is still unbuilt is a *guaranteed* decision on the
  minority of floors holding neither an elite nor a chest; that is the half that costs tiles, and
  the budget for it is written down rather than guessed. **A budget you have measured is a decision
  somebody else can make.**

- **A spatial model must not bury the card game.** An encounter count can be perfect while
  the player spends sixty moves between fights, and no other assertion in the suite can
  see that. So **moves per encounter** is bounded too (`ISO_MOVES_PER_ENCOUNTER_MAX`,
  measured over every dungeon in `tests/test_traversal.gd`), and it is what sizes a
  dungeon: the tile budget is per *dungeon*, so more floors means smaller ones. Deciding
  this arithmetically before building killed two designs on paper and caught a third that
  had passed every structural check (D79). **This is also why the iso floor is still a
  grid.** Dropping the tiles for a continuous Diablo-style world was asked for and
  declined: a continuous world has no move to count, so the bound above stops having a
  subject and "every model costs the same" stops being measurable (D87). What the request
  actually wanted — a place rather than a board — was presentation, and was delivered by
  deleting the per-tile outlines and sliding figures between tiles while the simulation
  stayed discrete.

- **Art in this tree must be licensed, generated, or gitignored — and the check that
  says so must DISCOVER its subjects.** Thirty-three unlicensed files sat in
  `assets/art/iso/` for a milestone with a README beside them headed "licence status:
  UNKNOWN", while `tests/test_art.gd` checked a hand-written list of four other
  directories (D89). The check now walks `assets/` and accounts for every PNG. An
  invariant guarded by a hand-kept list of places is guarded nowhere new.

- **An assertion and the code it guards must agree on the vocabulary, and a relaxed guard has
  to be shown to still fail.** `test_traversal`'s "nothing holds its ground" clause counted
  every non-rock neighbour as a way out, while `_hunt_step` refuses three kinds — rock, a cell
  outside a penned guard's pocket, and a cell another hunter occupies. The clause's own comment
  had always named the second exemption and the code never implemented it, so a hunter boxed in
  by a crowd stood still correctly and was reported as a broken chase (D228). It fired once in
  ~2,400 generated floors, which is once in five hundred suite runs: it passed on every
  developer machine for months and then went red in CI on a commit that touched nothing near
  it. Two lessons, and the second is the one that costs money. **A guard written in different
  words from the code it guards is a guard that will accuse the exemption.** And **loosening one
  is indistinguishable from deleting it unless you measure that it still fails on the thing it
  was written for** — the fix here was checked against a deliberately broken sidestep and kept
  361 of 365 detections, which is what made it a correction rather than a quiet removal (D47
  from the other direction).

- **Depth order is bent exactly once, and everything with height obeys the same gate.** The
  player is drawn last, over everything, because correct depth hides her behind the rock in
  front — realistic and unplayable. What makes that survivable is that anything occluding her
  is held back and re-drawn over her at a third strength. Exempting one object from that gate
  (the landmark, D177) put the brightest thing on the screen *underneath* her, so she read as
  standing on top of the light (D192). There is one list and one decision now, so a new tall
  thing joins by being tall rather than by somebody remembering a parallel array.

- **Photograph a layout change before believing it (D254).** The Power Pick screen shipped with
  three EMPTY circles: the ring drew, the sigil did not, the row sat on the floor of the screen and
  the backdrop was the tiling pattern because `UI.scene_backdrop` ran before `UI.screen` painted
  over it. Every automated check passed on all four faults — the suite instantiates every scene and
  audits its exits, which is enough to make shipping a layout feel safe. One capture found all of
  them plus a contrast fault nobody had asked about. It costs a minute:
  `DISPLAY=:0 LIBGL_ALWAYS_SOFTWARE=1 godot --rendering-driver opengl3 res://tools/Screenshots.tscn`.

- **Judge art in context, against the thing it actually replaces.** Procedural enemy
  plates were rejected off a contact sheet at 4x, in isolation, against an imagined
  alternative — then a capture of the combat screen showed the incumbent was a 16x16
  tile magnified to 240px, reading as a black pixelated cross, and the rejection was
  reversed (D89). Two defects only the capture could find: a silhouette with no waist
  and no gap between the legs is a coffin whatever is drawn on it, and a constant named
  `BODY_DARK` rendered at 0.50 because the transform applied to it carried a 0.25 floor.
  **A constant has to survive the transform applied to it, and the only way to know is
  to photograph the result.**

- **A label that names a theme has to be measured before it is written.** The world
  screen's zone line was meant to say what kind of deck a region builds, and two
  derivations of that were built and thrown away: per-zone build coverage tops out at
  25–40% with the runners-up a few points behind, and mechanical concentration rests on
  two or three cards out of twenty (D96). That is not a content gap — `test_build.gd`
  *enforces* that builds are scattered, because a build you can farm in one place has no
  journey in it. **There was no theme to name, so the honest line is the one that says
  what you do not own and what is found only here.** Derive the claim, look at the
  spread, and if the top of it is within noise of the next two, do not print it.

- **Put the picture beside the text, not under it.** The hub was the only navigation
  screen rendering the tiling pattern instead of a painting, and the obvious fix — the
  deepest unlocked zone as a full-bleed backdrop — was built, photographed and rejected:
  it drew the same picture the list was already showing, and its bright band ran under
  the sealed rows' prose at a dim measured for a different screen. The establishing shots
  went into the ROWS as thumbnails instead (D96). **A thumbnail beside its text needs no
  contrast measurement at all**, which is the cheapest form of that whole class of bug.
  Its corollary: a row recedes by ink, never by `modulate` — translucent text reads
  against the backdrop, not against the colour you chose.

- **A backdrop for a LIST is a different brief from a backdrop for a screen with
  prose.** A shop or an event puts text in the top half and framed buttons below it, so
  half the frame has nothing written on it and Tier 5c is composed for that. Every meta
  screen is a list — title on the top edge, rows down the middle, a button on the bottom
  — and measured at 1280x720 they carry ink from **3% to 96% of the frame height, all
  seven of the ones captured** (D123). There is no quiet band to put a subject in, so
  the picture has to be composed the other way round: everything worth looking at in the
  upper third where `UI.screen()`'s scrim holds it back, and the bottom half one
  continuous surface at one even value. Also: twelve screens are not twelve places —
  four paintings cover them, and asking for twelve would have asserted a fiction the
  game does not have.

- **Match the generator to the medium — but test where the line is.** Seamless materials
  are a solved problem in code and came out better than the packs they replaced;
  procedural monsters came out as coffins with antennae the first time (D89). When a
  plan has already argued that half a job is a bad fit, building that half anyway
  because the code is open is how a scoped pass becomes a rejected one.

- **A convention nobody can derive should be displayed, not documented.** The iso grid's
  four directions project to the four screen *diagonals*, so no key walks straight up and
  the choice of which diagonal W means is a genuine coin-flip. It is settled by showing the
  letter beside the arrow it walks (D87) — on the move buttons until D168 deleted them, and
  since then on the pad's keys and in the keyboard legend under the floor. When the control
  that was carrying such a display goes, the display moves; it does not go with it.

- **An affordance has to be on the thing the player is looking at.** "Hold this card up so I
  can read it" was reachable from a list row's illustration — a 28px square at the far left,
  the smallest target in the row and not the part anyone is reading. The name and the rules
  text are where the eye is when that question arrives, and clicking them did nothing; the
  shop had no way in at all, on the one card list whose decisions cost gold and cannot be
  undone (D205b). Existing is not the same as being found. Ask of any gesture: is it on the
  element the player is already reading, and does something *say* it is there? And when the
  answer is a tooltip promising what a click will do, **test the click, not the promise** —
  a count of affordances passed a handler wired to the wrong mouse button.

- **A control the player aims at must not move under their finger.** The crawl offered one
  move button per exit, rebuilt every step, so its count and its order changed between the
  decision and the press (D168). Movement is four directions that are always the same four
  — a fixed pad whose keys grey out says which are rock; a row that appears and disappears
  cannot. Ask of any generated control: does the thing in this position mean the same thing
  it meant a moment ago?

- **The moment of payment decides where "before" is, and a control that names a place should
  go there.** The debt offer sat on the dungeon's own row (D205) and then behaved like nothing
  else on that row: every other control there is a door, and this one was a purchase — it spent
  the stake where the player stood, redrew the row, and still needed a different button pressed
  to actually enter. Take it, walk into the deck builder, think better of the deck, walk out:
  the gold is gone and the contract is on a dungeon you are not in. It is a door now, and the
  stake is taken at the one moment a run begins (D211). Moving the payment moved the disclosure
  with it — the fee is named again on the screen that now charges it, because a screen behind
  you is not "before". Ask of any irreversible step: does it happen at the moment the player
  believes they are committing, and does the screen where it happens say so?

- **A price must be visible before it is paid, which means it must exist before then.** A
  chest's tier is its lock, and the tier was rolled on the chest SCREEN — so the lock came
  into being one step after the only step that could have answered it, and the floor drew
  every chest identically (D172). The fix was not a warning, it was moving the roll to
  generation so the tile can be drawn with what it wants. Ask of any cost the player is
  expected to plan around: does the game know it early enough to show it?

- **What the rules decide, the picture has to be able to say.** One painted chest, three
  tiers, and the tier decides the lock — so the tiers are lit differently (a pool of light on
  the ground, the sprite tinted with channels above 1.0, and a key drawn on the lock that is
  the same drawing as a key lying on the floor). A ring on the ground was tried first and is
  read after the sprite, if at all. Pick the channel by the distance the reading has to work
  at, and derive the colours from the one function that owns them (`Icons.pack_tier_colour`)
  rather than starting a second palette.

- **A model's skip is part of its price.** Three traversal models were quietly discounting
  their own budgets — measured fights actually *met* against a budget of 13.2: graph 4.5–5.1
  (a route misses other routes), dice **3.5–4.1** (overshoot sails past spaces), deck 4.9
  plus 1.1 dodged. Iso met 5.9–6.0, because stripping a floor misses nothing. So moving
  every dungeon onto it handed each a full extra fight and the Foundry fell from 63% to 0%
  (D88). Deleting a skip is a difficulty change that **no budget assertion can see**, which
  is why iso prices a slip-past of its own. It reused the deck's tuned number, and that was
  the wrong instinct twice over — see the next entry.

- **A ladder tuned for N rungs is wrong the moment something changes N, and nothing tells
  you.** The dodge price was a fixed per-rung climb, tuned so that FOUR dodges came to ~70%
  of a health bar — four being the *global default* encounter mix. Encounter mixes then
  became per-dungeon (D84) and the crawl started taking wanderers out of the combat budget
  (D88), and a wanderer cannot be slipped past. Measured, the crawl offers **two or three**
  dodges, never four: the real bill was 25–46% of a bar, and exactly 25% in six of twelve
  dungeons. `test_traversal.gd` asserted "at least half a bar" and passed for two years,
  because it counted the rungs from the same global constant the price did. **Two things
  deriving a number from the same stale source agree with each other and with nothing
  else.** `avoid_cost` now takes the count from the traversal that generates it, and solves
  the base so the whole ladder lands on the target however many rungs there are (D99).
  **And it happened again the moment N moved, exactly as designed to be survivable:** when
  every fight started walking (D197) the rung count doubled, the solver did its job, the
  first rung fell to 3 HP of a 60 HP bar and completion went *up* three points on a change
  meant to make the floor meaner. Solving for the total is what keeps a ladder honest; it
  does not tell you the total is still the right total.

- **A harness that selects by name goes quiet when the name changes.** The avoid calibration
  filtered on `Kind.DECK` and matched nothing the moment every dungeon became isometric — so
  the check that a priced dodge is not a dominant strategy (D20) printed a header and no
  rows on the exact turn a new model inherited the mechanic. It asks the model for the
  behaviour now, by walking a floor and looking (D88). The same filter sat in
  `tests/test_traversal.gd`, silently skipping the dodge-pricing block for every dungeon in
  the game, and was only found when D94 deleted the name it was filtering on. Unskipping it
  did not make it right: it then passed on the wrong rung count (D99, above). **A test that
  starts running after years of being skipped has never been checked against reality — read
  it, do not just watch it go green.**

- **Profile before optimising, and measure the ratio, not the clock.** `sim_balance.gd`
  took nineteen minutes, and the obvious suspect — combat, the thing it exists to
  measure — was 4% of it. 95% was the avoid calibration, and inside that it was the
  crawl: floods over the floor, four per step, each using `Array.pop_front` (which
  shifts the whole queue, so every flood was O(n²)) and allocating a fresh neighbour
  Array per cell visited. Packed arrays, a read cursor, inlined neighbours, one shared
  flood per step instead of two, and a memo on `options()` took the whole report to
  **420s from 1142s (2.7x)** with `fight_play` unmoved at 49s — which is the proof the
  diagnosis was right. Two cautions learned the hard way: single wall-clock readings on
  a loaded machine drifted 40% and pointed the wrong way twice, so `tools/bench_iso.gd`
  reports the **minimum** of interleaved batches; and the one hot spot left alone is
  entrance selection, which floods from every candidate tile. The cheap version picks a
  *different* tile, and regenerating every floor in the game to save 10% of a run is not
  an optimisation, it is a content change wearing one (D99).

- **A memo is only as good as its dirty flag, and a stale one is silent.** `options()`
  caches because a step built the list twice. Nothing crashes when an invalidation is
  missed — the player is simply offered moves for a floor they have left. So
  `test_traversal.gd` walks every dungeon comparing the cached list against a freshly
  computed one at every step, and that assertion was verified by deleting an
  `_invalidate()` and watching it fail (D99).

- **An invariant about the members of a set says nothing until something checks the set is
  not empty.** The iso model's sealed rooms asserted "a vault has exactly one way in" and
  "a vault has a key" — both vacuously true, and both passed for the entire life of a
  feature that generated **zero** vaults, because the architecture rewrite removed the
  dead-end tiles it needed. Write the assertion the other way round too: *generated must
  equal opened*. And when two features collide, check which one is load-bearing before
  deciding which to adapt — this one was bearing nothing, so the fix was deleting it (D86).

- **What the player is shown must be what resolves — including the creature.** Telegraphs
  matching their attacks was never the whole of it: the iso floor drew a sprite chosen by
  an arbitrary index while combat rolled the archetype separately, so you could walk up to
  a spider and fight a brute. Fights are cast when the floor is generated and ride out on
  `pending["enemy"]` into `CombatEngine`'s long-existing `forced_archetype` (D85). Two
  rules follow: the cast is drawn from the pool combat *would* have used, so this changes
  *when* the choice happens and never *what* — and the simulator honours the same key,
  because a tool rolling its own enemy measures a different game (the D72/D74/D77 trap).
  **Casting the fight was only half the promise.** The floor then drew that cast as one of
  three FAMILY silhouettes over thirty-five archetypes, so twelve swarms shared one grey
  quadruped and nineteen brutes one ogre: you still walked toward an ogre and met a cultist.
  Family is the right reading across a dark hall and the wrong one four tiles away. The
  fronts are now **cut from the combat plate each archetype already has**
  (`tools/derive_iso_fronts.gd`), so the floor figure and the arena figure are the same
  picture by construction rather than by a prompt asking for a match (D198).
  Silhouettes are **derived** from fight behaviour, never tabled: the first two derivations
  put all 35 archetypes in one family, and the roster had to be read to find the one that
  separates them.

- **Variety inside a model has to be shown, not asserted.** Two dungeons on the same
  traversal model can pass every count and still be the same place. Architecture and
  surface are therefore *separate* axes (`ISO_STYLES` × `ISO_TERRAINS`), both bounded by
  tests that check the tables index real things and that at least three of each are in use
  — and both judged by rendering floors side by side with `tools/IsoStyles.tscn`. That
  render is what caught two of four styles being indistinguishable, and the knob that fixed
  it (room-versus-corridor ratio) was the one that had been hardcoded (D82). **Every axis
  since has needed a new knob rather than new numbers on the old ones**: `rubble` and
  `spine` are what tell the three deep styles apart (D177), and both change the *walk*
  rather than the shape of a room.

  Between dungeons was never the hard half, though. **Inside one floor everything was
  identical** — every ground tile the same diamond at one of three tints — so three more
  axes are local: per-terrain **props**, per-style **room roles**, and a **light field**
  split out from explored-state, which had been doing illumination's job and is the whole
  reason the screen read at one value (D176). A dungeon's floors also stop being the same
  place: a drift rule gives every dungeon a different bottom from its top, with the surface
  turning one floor before the architecture does (D177). All of it is presentation, none of
  it is read by `options()` or any flood, and the walk measured 6.99 before and after.

  Three of those took a *capture* to get right, not an assertion (D89's rule holding again):
  the first light tuning lit 91% of the ground, shading light per tile put back the very grid
  D87 deleted, and props drawn paler than the floor read as sheets of paper. **Assert the
  band from both sides** — the light check now fails a floor that is fully lit as well as one
  that is dark, because the 91% build passed a check that only asked whether anything was lit.

- **Every gate should not ask the same question.** One scalar (`clear_count()`) fed both the
  dungeon and the zone gate, so every clear was interchangeable and nothing you did was
  remembered except how many times you did it. A gate now takes **depth in dungeons that beat
  you** as well as clears, discounted and capped (D178) — which is a way forward for a player
  who keeps dying that is not farming the first dungeon eleven times. Two rules make that
  safe: the cap is short of the deepest gate, so clears still matter and nobody walks a
  starting collection into difficulty 8 (D36's ceiling would make that a wall, not a
  freedom); and **a gate is permission, never strength** — the permanent max-HP bonus stays
  on clears, or the second route is free power from outside the deck. A gate is also stated
  in exactly one place, the zone, and an alternative route the player cannot see does not
  exist as far as they are concerned, so every sealed row prints it.

- **The walker that measures the pace only measures the REQUIRED route.** It takes the first
  ranked option, and optional business is deliberately invisible to that ranking — keys are
  ranked, not required (D167). So there is a second walker for the player who strips a floor,
  with its own figure and a ceiling *derived* from `ISO_LINGER` (an optional route costing
  more than one extra hurrying of the floor has become a difficulty setting, not a choice), plus
  a `--explore` route policy in the simulator, because a walker counts moves and only the
  simulator can price them in HP. **It shipped alone, before any optional content existed**
  (D179): a baseline measured after the feature it exists to price has landed is not a
  baseline. Against that baseline the pockets read +16 turns a floor, well inside the budget.

- **Optional content must be invisible to the required path, and it is TWO lines that make it
  so.** A secret pocket does not seed the field the greedy walker steers by, and does not count
  toward the unresolved total that decides whether the stairs are offered (D182). Get either
  wrong and `ISO_MOVES_PER_ENCOUNTER_MAX` silently starts measuring the optional route instead
  of the required one. The same rule downstream: a pocket's contents are outside `quota`, so
  taking one cannot flatter `progress()`; a guard is outside `dodgeable`, so it cannot re-price
  every slip in the dungeon (D99's shape); and pocket tiles are cut from leftover rock, so they
  cannot shrink every room in the game.

- **Three currencies reach a gate, and none of them is a modifier on the run.** Clears, depth in
  places that beat you (D178), and debts taken at the hub (D191). A debt names a place and a
  condition *observed* during the run — never a card-pool or difficulty change, which would
  reopen every scaling question the ratchet closes — and every condition reads state the run
  already tracks, because bookkeeping kept for one feature goes stale the first time another
  moves. That is what C1 meant by replacing one scalar with several so several orders are viable.

- **A rule that already has a price is cheaper than a new one.** A floor-wide state is an ASPECT
  applied mid-floor by choice (D188), not a fourth mechanism for "the floor is different now";
  a back door keeps the whole budget and divides it over fewer floors (D190), not a new content
  type with a difficulty rating of its own. Both reuse machinery that is already measured, and
  both are budget-neutral because the thing they reuse already was.

- **When the numbers do not come clean, delete it and write down what it measured.** Barred
  doors were built, corrected three times against the walkers, and removed: every flood in the
  traversal assumes symmetric movement, and with all three fixes in the walkers still failed one
  run in six and the optional route blew its ceiling (D189). Phase 7 was explicitly gated on the
  numbers staying clean. The tree is full of features that measured badly and went — the torch
  (D77), the continuous world (D87), the flat difficulty multiplier (D175) — and the entry that
  records why is worth more than the feature would have been.

- **A question with a fixed answer is furniture, so the answer is the floor.** A toll asks how
  many ways lead out of the room you are standing in, or how much of the ground about you you
  have trodden — derived live, never stored, never in the save (D186). Knowing the mechanic
  tells you nothing about the answer, which is the property a written riddle cannot have. The
  same rule one noun over: a *variation* on a dungeon is rotated by clear count and named
  before you commit (D187), because a change you cannot plan around is one you can only be
  surprised by, and this game names its bosses in advance for exactly that reason.

- **A wager needs a number the player can read, so it waits for the first clear.** Every debt
  quotes a figure sized off the place — take 340 damage out of it, put 11 of them down — and on
  a dungeon you have never entered that figure means nothing, leaving the fee as the only thing
  to weigh (D248). So `Balance.debt_for` returns `""` at a clear count of zero, and the offer
  arrives with the aspect on the visit after your first clear. The screen prints the reason
  rather than dropping the row, because an alternative you cannot see does not exist (D178).

- **A secret must be a DEAD END, and an errand must ask for MORE.** Both rules exist for one
  reason: a skip is a difficulty change no budget assertion can see (D88). A shortcut secret
  would let a player reach the stairs past content; an errand paying for "leave the chests
  alone" or "reach the stairs in twenty turns" would pay them for declining budgeted content.
  Either would leave the whole suite green while the dungeon got cheaper than its rating says.
  So a pocket has exactly one mouth and the floor's connectivity is *identical* sealed and open
  (asserted, with a non-zero generated count beside it — D86 asserted the same shape about zero
  generated vaults), and every errand condition is checked to be settleable only by a player who
  does more (D182, D184).

- **A rank has to be safe against the largest value the tiers below it can reach.** Option order
  is `rank * 1000000 + away * 1000 + cell`, and an unreachable goal scores `away` as 9999 — so a
  plain step can sort at ten million. A push ordered "between the stairs and the slip" at 2.5M
  therefore outranked every step on any tile whose route ran through the way on, and the headless
  walkers started pushing walls (D182). Nominal tier order is not the invariant; the arithmetic is.

- **Anything unreachable that is seeded as a destination deadlocks a walker.** Four times now:
  D74 twice, then a pocket whose only approach was the stair, then a pocket lying beyond it —
  the way on is placed on the furthest *chamber* tile, so a corridor dead end can be further
  still. Descent is one-way, so a route through the stairs is a route nobody can take, and both
  the generator and the walkers now ask a flood that treats the way on as solid.

- **There are two reward channels, and only one of them can be given away freely.** A
  card that joins the run deck is a *decision* — it can dilute the draw it was meant to
  improve, which is D46 seen from the other side and is why the fight reward still works
  that way. A sealed pack (D80) cannot touch the run it was found in, so it needs no
  rationing, no coin flip, and no modelling in the simulator. Before moving a reward
  between the two, measure what it is worth where it currently sits: deck growth is
  worth nothing in the opening and 10–25 points of clear rate at depth, and in two cells
  a fixed deck measured *better*. The two now mean one thing each — a fight reward is
  the *dungeon's* cards, a pack is the *archetype's* (D81).

- **Cards earned is the wrong number; copies of ONE card is the right one.** Fusion
  spends copies of the *same* card, so across a 20-card pool raw volume barely moves
  any single one. Typing packs by build raised cards per run 44% and made levelling
  *slower* until the dungeon-affinity weight was tuned, because seven build pools
  broadened the collection instead of deepening it (D81). Measure with
  `tools/pack_income.gd` before repricing anything in the fusion curve — and if it
  needs repricing, the lever is `FUSE_COPIES_STEP`, not `FUSE_BASE_COPIES`, which
  taxes the fresh save that cannot afford to fuse at all.

- **The player is never lied to and never stuck.** Telegraphs match what resolves.
  Card faces show the *current* numbers, not the level-1 text (D50) — including the
  Vulnerable on the enemy the card is pointed at, which is the one status whose whole
  purpose is to change the number about to be read, and which the face could not see
  until D300. A card being OFFERED states where it already stands in the player's
  collection: copies held, the level they are held at, and what the next one costs and
  buys (D174). It does **not** state a verdict on the offer — scoring a set against the
  deck and printing STRONGER or WEAKER is the game making the decision, and a mean of
  card power is a fact about arithmetic rather than about the run (D300). Every screen
  offers something to press, and every encounter can be left (D47). No fusion or death
  can strand the collection below a legal deck (D12).

- **The two lists of earned things are one screen twice.** Relics and Powers hold the same
  kind of thing — earned, unlosable, one painted icon each — so they share a backdrop
  (D123), a tile (`UI.sigil_face`), a greyed-and-dead state for what you have not got, and
  one reader line for what a press says (D308, D312). Levelling a power quotes
  `level_up_text`, the same sentence the camp and the Collection quote for a card, because
  `PowerData extends CardData` and there is one implementation to quote.

- **A control with nothing behind it is dead, not polite.** A press that answers "there is
  nothing here" teaches the player to press again — the Relics screen had nineteen live tiles
  with dead outcomes on a mid save (D308). An unmet relic is `disabled`, so the frame itself
  says so before it is touched, and the dim goes on the picture and the name together. The
  same rule sets what a screen may CLAIM: a resting line reading "press a relic to read what
  it does" is an instruction to press something on a screen where nothing can be.

- **A control that commits is the control that says so.** A card face is for reading. On
  a touchscreen a card needs one tap to be legible at all, so a face that also buys
  something turns the tap that finished reading into the tap that spent the reward — the
  reward sets and the merchant's stock both worked that way until D300. The face reads;
  a named button beside it takes, buys or skips. **A tile SELECTS and a button TAKES, and
  a press that selects is idempotent** (D307): the two-tap dance is safe only while "have
  I read this" is a fact about the last thing tapped, and the relic offer kept it per tile
  for ever — tap one relic, tap another, come back, and it was taken. A choice the player
  cannot re-read is a choice they did not make. The same rule keeps a panel STILL while it
  is being read: nothing rebuilds under a hand that has just pressed something, and a line
  that fills on hover reserves its height before anything is pointed at (`UI.fixed_line`).

- **A thing you cannot resolve yet is not a thing you have resolved.** Walking onto a
  key-locked chest with no key ran the normal resolution path, so the tile went bare and
  the chest was destroyed — while its key lay on the same floor, which a probe over 1,320
  generated floors showed is always true (D307). It reads as "the key is missing" and it is
  the chest that is missing. `TraversalIso.leave_pending` steps off without resolving:
  nothing paid, nothing rolled, nothing counted, the tile untouched. Anything that pays out
  on a visit that resolves nothing is a tile the player can farm, which is why the chest's
  gold moved to the visit that opens it.

- **Expandable by design.** New cards, enemies, bosses and dungeons are data files
  plus a catalogue line, guarded so a half-added piece of content fails loudly rather
  than silently not existing (D42).

- **Cross-platform.** Desktop (Linux/Windows/macOS) builds here; Android and iOS stay
  *exportable* even though their toolchains cannot run here (D44). Touch is a first
  class input — a finger has no hover, so cards read on tap (D43), and a finger has no
  wheel, so every list carries its own drag-to-scroll rather than trusting the engine's
  (D225). The APK reaches as wide as the engine allows: Android 7.0 is Godot's own
  floor, and both ARM ABIs ship in one package because 64-bit-only is refused by a
  32-bit phone as *"app not compatible"* — a message that names neither (D170).

- **A set can be uniform and uniformly the wrong game.** D150 made the sound coherent —
  one instrument, one rate, one key, one measured loudness ladder — and it was still a
  chiptune under 310 paintings, because none of its gates asked the question the player
  was actually asking. **Measure the property the complaint is about**, and expect the
  first guess at that property to be wrong: "the old sound was bright and thin" was the
  obvious hypothesis and the numbers said the opposite (it measured *darker* and heavier
  than what replaced it). The two that carried it were `pulse` — every old track had a
  beat, including the menu, and a dungeon you can tap along to is a dungeon you stop
  being afraid of — and `tail`, where a 35 ms click meant nothing in the game happened
  anywhere. Both are gates now, and `assets/audio/*/measurements.json` carries the
  numbers into the engine so a gameplay branch cannot ship past them (D173).

## The engineering lessons, learned the hard way

These are failure modes that have actually bitten this project. Treat each as a rule.

- **A function that is called twice may not roll dice (D271).** The elite reward panel is
  drawn once when the fight ends and again after a relic is taken, because the relic row
  has to redraw as taken — and it rolled the three card rewards, so taking the relic dealt
  three new cards underneath. The player controls when that second draw happens, which makes
  it a re-roll on a reward: D22's slot machine reached through a door nobody built, the same
  shape as quitting to retry a bad turn. **A draw function draws; what it shows is decided
  before it is called.** `tests/test_layout.gd` reads the body of `_offer_rewards` out of the
  source and fails on any `randi`, `pick_random`, `shuffle` or `_roll_` inside it. The
  extraction that introduced this was documented as changing nothing about the panel, which
  is why nobody looked — **a note saying "nothing changed" is a claim, and it is checkable.**

- **A green suite can hide the whole feature being broken.** Every suite checked the
  ENDPOINTS of the level curve — a maxed card is stronger than a level-1 card, and not
  absurdly stronger — and none ever asked about a step in the middle. 77% of every
  level-up in the game bought the player nothing, for gold and copies, and eight cards
  changed nothing at any level (D109). **When a system is a curve, test a step, not its
  ends.** `tests/test_levels.gd` walks all 3,859 of them.
- **And a suite that guards a SHAPE cannot see the height.** The D109 retune satisfied
  every predicate in `tests/test_balance.gd` while turning the game into a walkover —
  Barricade at the Foundry went 24% to 100% run completion. Constants whose comments say
  "measured" must be re-measured with `tools/sim_balance.gd`, against a baseline from
  the tree you started from. The analytic version was elegant and wrong.
- **What belongs to the player's machine is not the game's to art-direct.** The game
  shipped its own mouse pointer — painted, hotspot-measured to the pixel, repaired twice
  — and it went in the bin the moment it was mentioned (D138). A cursor is configured by
  the player, agreed on by every other window they have open, and quite possibly set for
  a reason. Same test for anything system-level: is this offered, or imposed?
- **A control the player can move must reach something.** `show_numbers` was
  persisted, drawn in the Settings menu, and read by nothing at all for its whole life
  — the checkbox never once changed the screen, and its label promised to hide enemy
  intents, which would have been a difficulty option wearing a comfort option's clothes
  (D130). A dead control is worse than a missing one: the player concludes the game
  ignores them. `tests/test_flow.gd` now asserts every offered setting is read.
- **A test that has never been seen to fail has not been tested.** D130's effects test
  passed while proving nothing: in a `--script` run a node added to `root` is not in the
  ACTIVE tree, so every effect bailed at its own first guard and "nothing was drawn"
  read as success. It would have kept passing with the settings unwired. Scene tests
  exist for this — and when a test guards a single clause, delete the clause once and
  watch it go red.
- **`JSON.stringify` does not fail on a type it cannot write — it writes `str()` of it.**
  A `PackedByteArray` in a save comes back as the *string* `"[1, 0, 1]"`, and the loop
  that reads it walks characters instead of cells. Two grids of the explored floor were
  lost on every resume for a day, and the crawl resumed as a hero standing in a void
  (D140). Only `Packed*Int/Float` arrays survive the trip. **Anything that goes into a
  save is a plain Array, a Dictionary, a number, a string or a bool — convert at the
  `_save` boundary**, and assert the round trip *cell by cell*, because a restored run
  with no map still reports the same counts and offers the same moves.
- **`|| true` chooses which error message you get; it does not avoid one.** `gh release
  delete <tag> --yes || true` was written because a missing release is not an error —
  correct reasoning, wrong code: it cannot tell "nothing to delete" from "the call did not
  work", so the real fault surfaced three lines later as "a release with that tag already
  exists". True, specific, and about the wrong cause (D146). **Ask first, then let the
  command fail.**
- **A fault that appears alongside an unrelated change will be blamed on it.** That same
  publish failure landed in the run where the repository was renamed, and "GitHub 301s a
  renamed repo and `gh` does not follow that on DELETE" fit every fact available. It was
  wrong; the job simply had no `actions/checkout`, and `gh` reads `GH_REPO` — not
  `GITHUB_REPOSITORY` — to find the repository. A coincidence makes a good enough story to
  survive one round of evidence. **A hypothesis that predicts a fix is only confirmed by
  the fix passing** (D146).
- **GitHub caches README images and will not let go.** Badges are proxied through
  `camo.githubusercontent.com`, keyed on URL, and the RESULT is cached — so a shields
  badge that fails upstream for one minute keeps serving the red picture indefinitely,
  long after the underlying query started working. `curl -X PURGE` on the camo URL
  returns 200 and does nothing. The only lever is to change the URL (D148). Corollary:
  **do not fetch a fact that never changes** — the licence badge is static and pinned to
  `LICENSE` by `test_content.gd`, which is strictly better than an API round-trip that
  can be poisoned.
- **Anything visual has to be LOOKED at, and the suite cannot do it for you.** The six
  combat effects passed review and passed 37 suites while every particle was invisible
  — 4px motes at the value of the floor, on a painted corridor. Rendering them under
  Xvfb at `Engine.time_scale = 0.2` found that plus a poison cloud that was a haze and
  a dissolve that came apart in tidy squares (D129). Three for three with D56 and D89:
  **capture the frame.** `tools/screenshots.gd`.
- **Booting is not playability.** A scene that loads can still be a black screen. 34
  suites once passed while the first dungeon was unplayable. `tests/test_compile.gd`
  and `tests/PlayableTest.tscn` exist because of this — run them.
- **Nor is passing a test *looking* right.** Rendering every screen to PNG (D56)
  found a dice board with zero height, seven screens with no backdrop and a button
  frame stretched 14×, none of which any suite noticed and none of which is visible in
  a diff. `tools/screenshots.gd` exists because of this — look at the game.
- **A nine-slice is a mechanical contract, not a picture.** Its top/bottom strips are
  stretched horizontally and its left/right strips vertically, so each must be constant
  along the axis it is stretched on, and the middle must be one flat colour. Painted
  art breaks all three and the button becomes a smear (D83). The frame kit is generated
  by `tools/gen_ui_kit.gd` for that reason — do not replace it with an illustration.
- **Do not derive a style decision from state the caller has not set yet.** Picking the
  button frame from `b.text.length()` looked fine and was wrong everywhere, because
  almost every call site styles the button and then sets its text (D83). Pass it in.
- **A test that reads source text proves code exists, not that it works.** A
  `--script` test has no autoloads, so it can only inspect files — which is why
  `test_layout.gd` happily confirmed the dice board's scroll-to-token function while
  the board itself was 0px tall (D57). Anything about *size, position or visibility*
  belongs in a scene test that measures the built tree.
- **Zero-size is the quiet failure mode.** A `ScrollContainer` reports a minimum size
  of 0 on any axis it can scroll, so `SIZE_EXPAND_FILL` siblings will crush it to
  nothing and its contents vanish while every other check stays green. `PlayableTest`
  now asserts no scroll area is squeezed flat.
- **A `custom_minimum_size` is not a minimum if the content sets the size.** The mirror
  image of the above. A `Label` reports its *text* width as its minimum, so it grows
  straight past the floor you set and anything laid out after it tracks the string
  length — which is why the Packs screen's three "Open" buttons sat at three different
  x positions despite the label already carrying a width (D95). `clip_text` is what
  makes the floor real, and the width beside it should be measured against the longest
  string the content tables can actually produce, not picked.
- **A shared scaffold is only shared by the callers that call it.** `UI.screen()` exists
  so one edit restyles every screen once there is art. Two screens hand-rolled the same
  `MarginContainer` + `VBox` themselves, and so were the only two in the game rendering
  on flat black when the backdrops landed (D95). A helper whose whole value is uniformity
  needs a check that everyone is inside it — the boilerplate it replaces is, by
  construction, easy to write again by accident.
- **A card is two parts, and the bottom one is allowed off the screen.** The face is a
  picture band over a text band (the Slay the Spire shape), which makes it taller than
  fits above a hand — so 74% of it shows and the rest hangs off, and hovering computes the
  lift that brings the whole card back (D104). The invariant that replaces "the card is on
  screen" is **the identifying part is on screen**: picture, name, cost, headline number,
  all in the top half by construction. Anything moved into the bottom corners is a thing
  the player in a fight cannot see.
- **An enlarged card must fit the thing that CLIPS it, not the screen (D246).** The same
  bottom-edge pivot that keeps a card in hand on screen sends all 45% of the hover growth
  upward — so in the collection's grid, which lives in a `ScrollContainer`, the top row lost
  67px off its top and the left column 23px off its side. `UI._keep_in_clip` slides an opened
  card back inside its nearest clipping ancestor and puts it back when it closes. A top margin
  was the wrong fix: scroll two rows down and whichever row is at the edge grows into the cut.
  Note what cannot see this bug — `get_global_rect` reports the UNSCALED size, so a check that
  uses it passes while the player looks at a card with no top.
- **A guard that outlives its design is worse than no guard.** Two of `CardTextTest`'s
  assertions were the old card stated as rules — *no rules text while resting*, *every card
  inside the frame* — and both were exactly backwards after D104. Re-aim them at the new
  invariant, computed from the same constants the layout uses; deleting them would have
  left the peek free to take any value at all.
- **Some defects live in the PAIR, and no per-item assertion can see one.** `CardTextTest`
  checked every card was on screen, fanned, arced, clear of both corners and never under
  14px — and passed on a hand where three of five names were hidden under the next card,
  because overlap is a fact about two cards and every check was about one (D97). D84 is
  the same shape one layer up. When something is laid out *relative to* something else,
  assert the relationship, and prove the assertion by disabling the fix and watching it
  fail: a new check that has never been red is a comment.
- **The capture approves a change as well as condemning one.** D56 exists because renders
  find what tests cannot. It runs in both directions: forcing card names never to break
  mid-word passed every measurement and looked worse than the defect, because the font
  had to shrink too far — reverted on sight of the render, and a broken word is now the
  accepted cost (D97). Measure, then look, then decide; the render can veto.
- **`load()` returns non-null for a script that failed to parse.** Never use it as a
  "does this compile" check. `get_instance_base_type() == ""` is the honest probe.
- **`--headless --import` does not compile scripts** and its viewport defaults to a
  square 1280×1280. Scene tests must set the shipped 1280×720. (There is no UI
  scale to set any more — the interface is a fixed size, D65.)
- **Tests must be sandboxed.** They write to `user://t_*` via `MetaState.path_prefix`
  and `SettingsState.path_override`, and disable writes on teardown — because a test
  once overwrote a real save and a debug tool destroyed a run. `tests/run.sh` fails if
  any `t_*` file is left behind. Headless runs default to a sandbox for this reason.
- **Persisted enum ordinals may only be appended to.** `EnemyData.Action`/`Trigger`,
  `RelicData.Trigger`/`Effect`, `CardData.Rarity` are stored as raw ints in `.tres`
  and saves; inserting a value silently rewrites every existing file. A test pins them.
- **Duplicated constants rot silently.** A restated number (`1.6`, a label table, an
  upgrade-cost comment, a rarity multiplier copied into two price formulas) has caused
  four separate bugs. Derive, don't restate.
- **A flat number in a scaling game is a bug with a delay on it.** Shop prices were
  flat gold at every depth while income scales with `GOLD_DEPTH_EXP`, so the merchant
  had nothing affordable on 74% of first-dungeon visits and nothing meaningful at d8
  (D70). Anything the player pays or is paid should be expressed in what it is worth —
  fights of income, points of HP — not in a number that only happened to be right once.
- **Scripted whole-block text edits land at the wrong indent** in an
  indentation-sensitive language and look right in a diff. Edit in place with exact
  anchors; `test_compile.gd` is the backstop.
- **Generated art needs the constraint stated once and applied identically.** One
  generator, one style block, `bg_crypt.png` attached to every request as the style
  reference — the coherence comes from the ask being the same, not from the model
  (D90). Which files may be generated at all is in `ART_PROMPTS.md`, and it is a real
  question: nine-slices are computed (D83) and animations are not stills. **One
  generator is necessary and not sufficient:** `main_menu.jpg` came off the same tool as
  the twelve dungeons and matches none of them — flat vector shapes, a ninth their ink
  density — because it was asked for in different words (D114). The wording is the part
  that drifts, which is what the reference image is for.
- **A file that exists is invisible to a shopping list, so a bad one has nowhere to be
  recorded.** `ART_PROMPTS.md` prints what is absent; the moment anything lands, correct
  or not, the sheet stops mentioning it. That is what `REDO` in `tools/art_manifest.gd`
  is for — a hand-kept list of defects somebody LOOKED at, each with its measurement,
  emptied as re-rolls land. It only works if a row exists to key on: the title art was
  off-style for thirteen decisions because Tier 7 listed the logo over it and the splash
  before it and not the painting itself (D114). A re-roll counts in the sheet's total —
  it is the same prompt sent again.
- **A placeholder that reads as finished is worse than an empty slot**, because an empty
  slot is on a list. Thirty-five enemy plates and twenty-three isometric figures are
  procedural silhouettes — luma 0.16–0.23, flat interior behind a one-sided rim light —
  and every one of them counted as *present*, so Tier 2 printed "all 35 present" and the
  prompt sheet said nothing (D122). Both were the right call when they landed; neither
  is art. When a whole family shares one defect it goes in `REDO_DIRS`, consulted after
  `REDO` so a single file can still carry its own worse fault: `combat`, `elite` and
  `boss` are 100% identical silhouettes and that is not the family's problem, it is
  theirs.
- **Quiet is not empty, and a brief that conflates them gets a fill.** Four meta-screen
  backdrops shipped with their lower halves flooded flat, because the recipe asked for
  "one continuous surface at one even value ... no grain that changes value" (D125). The
  screens need nothing an eye stops on; they do not need nothing at all. When a brief
  constrains a region, say what it must NOT have — features, brightness, objects — and
  say separately that it must still be painted.
- **A harness is only as honest as its list, and an absent row looks like a passing
  one.** Every screenshot entered `DUNGEONS[0]` — the Crypt, which is `stone` — so three
  of the four isometric terrains had never been photographed at all, and Settings had no
  row until somebody went looking for it (D122, D123). Before trusting "the captures look
  fine", check what the capture list does not contain.

  **And the check itself has a blind spot with a shape (D218).** `find_gouges` lists
  transparent pockets *enclosed by the subject*, which is right and is why it can never see
  a bite taken out of an outer EDGE — that is joined to the surround, and the surround is
  background by definition. Two passes over the art (D195, D199) used it or the eye, and the
  moth's wings, the forge-hound's leg and the brood-mother both shipped through them and
  were reported by a player. When a detector excludes a case *by construction*, write down
  which case, because that sentence is the list of what it will never find.
  `tools/plate_check.gd` is the answer here: it composites every cutout over flat magenta,
  because **a cutout can only be judged against something brighter than it** — over a dark
  corridor a hole reads as shadow.

  **And a correct instrument read at the wrong SIZE is still a miss (D219).** That sheet was
  judged at 380px a cell and a hole clean through a hound's chest was called clean twice; it
  is unmistakable at 700px. Use the contact sheet to pick suspects and then render the
  suspects large, one at a time. The same rule as the 48px relic strip, in the other
  direction: **judge at the size the defect is visible, which is not always the size the
  thing is drawn.**

- **An animation is judged by its SEQUENCE, and a frame count is not one.** The hero walked
  on two poses alternated once per STEP, so a step showed one frozen pose for its whole
  0.13s while the position lerped underneath — a sprite being dragged, not a figure walking
  (D222). Both poses were also *contacts*, the two extremes of the stride, with no passing
  frame between them; playing two extremes faster only flickers faster. The fix was one more
  drawing per facing and a phase keyed to the PAIR of steps, so the cycle reads
  `a, p, b, p` and does not repeat a pose where two steps join. **Ask what the thing looks
  like between the keyframes, not how many keyframes there are** — and assert the sequence,
  since a check on any single frame passes on a slide.

  **And the frames of one animation are ONE character, so they cannot be measured one at a
  time (D317).** Reading a sprite's anchor and size off its own art is right for a set of
  unrelated pictures and is what keeps a cloak from deciding where a figure stands (D149).
  Inside a cycle it is wrong: the anchor and the size belong to the character, so a per-frame
  measurement lets the pose move her. The hero's contact frame anchored on her floor-length
  cloak rather than her boots and jumped 15px sideways on a 116px tile, and one frame drawn
  90% as tall dropped her 10.6px shorter, twice per two steps. Measuring each frame *better*
  does not fix it — feet apart and feet together are honestly different stand points. Pin the
  whole cycle to the idle painting, which is also the frame it starts and ends on.

  **They are also not all painted facing the same way, and a generator will not tell you
  (D318).** Asked for "the same character mid-stride", it answers the pose and flips a coin on
  the hand: five of the eight hero files look the opposite way from their own idle. The facing
  table held one entry per PAIR, which was right while a pair was two files, so one mirror
  decision got applied to every frame and she turned round partway through a step — *"going
  south west, sometimes the hero turns south east"*. **A property of a FILE cannot be stored
  per family**, and the moment a family grows from two files to eight, every such entry is
  standing for two questions at once. Check a set like this by measuring each frame against
  its own idle and against that idle MIRRORED — and measure the pixels that get drawn, since
  a table and the rule that reads it will always agree with each other.

  **The one picture that decides it is the PAIR (D221).** On magenta a missing trident head
  looks like a trident drawn short and a severed arm looks like a sleeve ending in rags — the
  sprite is *plausible* without the part, which is the case a single picture cannot settle. So
  `tools/plate_check.gd --paired` draws each plate twice, shipped and with its alpha ignored;
  since the pipeline only ever wrote alpha, the second panel is the painting that was
  delivered, and "missing" versus "never drawn" stops being a judgement call. Two plates were
  cleared by eye TWICE from the magenta panel alone and were wrong both times.

  **A shortlist you have already decided against reads as noise.** Both of those plates were
  on `drop_strays`' list and `refill_pockets`' list while being called fine. When an
  instrument disagrees with your eye, it has seen something your eye has not; the cheap move
  is not to argue with it but to take the one picture that separates the readings.

  **And not every mark on a sprite is a hole (D220b).** The one on the Marrow-Priest was the
  generator's watermark left OPAQUE in the field beside his arm — no detector that looks for
  missing alpha can see it, and at 1:1 over a dark corridor it reads as a smudge on the
  robe. It took 10x on magenta to tell "beside the arm" from "on the arm", and those are
  different defects with different fixes. Ask what a mark IS before reaching for the repair
  that matches what it looks like.

  **And a list of STATES rots the same way a list of screens does (D217).** Every iso
  capture photographs a floor being *walked*, and a walk never stops at an offer — so the
  row of buttons that carries push, answer, break-away and the stone had never been in a
  frame. Behind that gap: a toll offers three answers on one tile, both of the screen's
  no-button selectors take the first match, and the game **could only ever say the lowest
  of the three numbers.** Nearly half the riddles in the game were unanswerable, through
  three shipped features and a green suite. When a feature adds an interaction, ask which
  capture will contain it — and if the honest answer is *none*, that is the row to add
  before the feature is called done.
- **A UI that filters on a NAME goes quiet when a fifth thing arrives; one that filters on a
  PROPERTY follows it.** The act row read `action == "avoid"` from the day the slip was the
  only non-movement offer, and three kinds added later were simply never drawn (D217). The
  same shape as the avoid calibration that silently matched nothing when every dungeon
  became iso (D88) and the hand-kept art list of D89. The rule is now "anything the model
  calls an action", so the next kind is offered on the day it is added — and the test
  asserts against the model's own option list rather than against a list of names, because a
  guard kept by hand goes stale exactly like the code it guards.
- **Two decisions can each be right and still collide, and the seam is where nobody
  looks.** The backdrop brief asks for framing elements at the left and right thirds;
  combat spread enemies across the full width, which puts two of them at exactly the
  thirds. Enemies stood on the scenery and it was reported as an art bug — the sprites
  measured perfect, 0.0% empty below the feet, all thirty-five (D122). A single enemy
  sits dead centre and is fine, which is why single-enemy captures never showed it.
- **A prompt sheet is read by two audiences and only one of them paints.** The per-tier
  prose in ART_PROMPTS.md mixes art direction with notes to the operator — which files are
  computed, which installer takes the sheet, why a decision was made — and pasting it whole
  sent "DO NOT GENERATE the nine-slices … they come out of `tools/gen_ui_kit.gd`" to the
  generator (D102). Filtered per sentence, not per tier: the two kinds share a paragraph.
- **A brief and a prompt are different sentences.** "Why is this file wanted" belongs in
  ART_ASSETS.md; "what do I draw" belongs in ART_PROMPTS.md. One string served both and
  the prompts lost — they quoted the UI text they were replacing at a style block that
  bans text, and named card families by their membership lists instead of painting the
  effect (D101). `_add()` takes a separate `subject` for the prompt sheet now. **A
  generator can only draw an object**: "Block." and "A choice with consequences" are
  rules, and a rule prompts a diagram.
- **Regenerate the generated docs in the commit that changes what they describe.** Both
  art documents spent two commits asking for 35 enemy paintings that were already
  installed (D101). A generated file is only current if regenerating is part of the
  change, and the counts in it are the tell.
- **A generator that cannot accept a reference image cannot do this job.** The style
  reference is the constraint that actually holds, so a text-only endpoint is not a
  cheaper option, it is a different pipeline with no style bible. Check the model's
  input modalities before its price (D100).

- **A safeguard's cost is usually the mirror-image defect.** The matte floods in from the
  frame edge and stays connected so a field-coloured patch inside the subject is never
  punched into a hole; the price is that field the silhouette SEALS OFF is unreachable and
  ships as a slab of flat magenta behind a skeleton's ribs (D92). `despeckle` cannot catch
  it — a trapped pocket touches the subject, so it belongs to the largest component. The
  fix separates *recognising* background from *removing* it: identify a pocket at a tight
  tolerance where the untouched field sits (distance ~0) and armour that merely resembles
  it does not, then grow that verified seed at the ordinary tolerance. Seed tightly, grow
  normally; a tolerance is a claim about confidence, not about extent.
- **Judge a cutout through something that respects alpha.** `apply_alpha` zeroes alpha and
  leaves RGB, so any viewer that ignores alpha shows the matted background, the pad and
  the stripped watermark as though the install had done nothing (D92). Use the contact
  sheet or the opaque fraction.

- **An icon SET is one asset, and its requirement is mutual distinguishability.** Seven
  intent telegraphs that each read as "angry shape" have failed even if each is
  individually good, and a request for one is blind to the other six — so the icon tiers
  are generated as one gridded sheet and sliced (D91). That buys consistency of hand and
  pays for it in positional assignment — the hazard the deleted `PixelArt.enemy_sprite()`
  demonstrated for years, handing each archetype whichever CC0 tile the sort order
  reached. It is survivable only because the order is generated into the prompt and
  read back by the installer from the same table, and printed on every run to be checked.
  **Printed to be checked is not checked**, and D112 is what that costs: the sheet prompt
  said "a single grid image containing 21 cells" and never once said *5x5*, or that four
  cells were spare, because the line in ART_PROMPTS.md carrying the grid also carried the
  `Install:` command and the parser dropped the whole line. Both sheets came back with the
  right drawings in the wrong boxes — one with 25 glyphs where 21 were asked for — and
  reading-order assignment would have shipped 18 correct pictures on 18 wrong meanings.
  A positional contract has to state the positions.

- **A harness that captures one state certifies one state.** `tools/IsoArtCheck.tscn` draws
  the floor with the hero at her default facing, and three consecutive attempts to fix her
  mirrored facings were verified against captures that never drew one (D154). The engine was
  also not doing what the call site asked: `draw_texture_rect` with a NEGATIVE width flips the
  image and draws it from `position` rightwards, so a rect built with its right edge as the
  position lands a whole sprite width away — and a test that checks the rect it computed
  cannot see that. Mirroring is done to the texture now, and the test asserts the width is
  positive. **Where a view has N discrete states, photograph N of them, or assert against the
  pixels rather than against the arguments.** `IsoArtCheck` takes `--facing SE|SW|NW|NE` for
  exactly this, one capture per process — two captures inside one process return the same
  frame under `opengl3`, whatever you await (D155) — and it prints which draw is in the file.

- **A number is only evidence if you know what it should read when the thing WORKS.** Mean
  pixel difference over a window around the hero reads ~6 whether two facings are identical or
  completely different, because her sprite is a fifth of that window; on that metric a working
  fix looked like a broken one and cost a round of chasing it (D155). Difference two states to
  isolate the thing that moved, measure it against something fixed in the frame, and state the
  expected reading before you take it.

- **A capture on an X display is not a capture of the shipped game unless you force it.**
  Two ways to be lied to, both hit for real. `tools/screenshots.gd` on the desktop renders
  the *monitor's* aspect — 1280x800 on a 16:10 panel, 80 rows the game never has, which hid
  a live clipping bug (D115). And Godot **silently falls back to Wayland at 2560x1600 →
  1280x800** if `DISPLAY` points at a dead Xvfb, so a capture can claim the right size and
  not be it (D133). `Xvfb :N -screen 0 1280x720x24` plus `--display-driver x11` with
  `WAYLAND_DISPLAY` unset, or do not trust the picture. **And set `OWING_SANDBOX`:**
  `MetaState.path_prefix` only sandboxes when `DisplayServer.get_name() == "headless"`, so
  anything driven under Xvfb that is not the harness writes the player's real `save.json`.

- **A silent partial success is worse than a failure, and the installers can produce one.**
  `cutout_lib.gd` refuses loudly in three places — a subject painted in a room, a matte
  that ate the subject, a matte that found no background. Between those guards was a gap:
  a subject whose own colour sits inside the flood fill's tolerance of the field, so the
  fill walks in through one shaded pixel, `despeckle` keeps whichever scraps survive, and
  what lands is a plausible file. `ui/cursor.png` shipped **9.4% opaque against 93.9%
  non-black RGB** and `ui/logo.png` lost its carved scrollwork while keeping the panel
  behind it (D125b; the cursor file is gone since D138, the bug it proves is not). It then
  did it again to five iso figures — a mummy in grey bandages on a grey field came out as
  a scatter of dust (D152).
  **All of them look perfect in an image viewer**, because the matte destroys alpha and
  leaves colour alone — so the check that finds this is opaque coverage against surviving
  RGB, not looking at the thumbnail. The tool even printed the tell (`dropped_islands`) and
  nobody read it.

  **The replacement key does the same thing in the other direction, and the trigger is a
  RECOLOUR rather than a bug.** `lumakey` was written for these files and sets alpha from
  distance to the field, so a subject is opaque in proportion to how far it sits from its
  own background. That held while `ui/logo.png` was pale stone on black. D283 re-cut the
  same plate in cold dark slate, and the same key installed its flat middle — the part
  type is set on — at **alpha 0.39**, 19.3% of the file above alpha 0.5 against 72.26%
  before. Nothing about the tool changed and nothing warned. So the rule generalises:
  **an installer recipe is a claim about the art's VALUES, and re-generating an asset can
  expire it.** The two techniques trade places at roughly a mid grey — the flood fill
  refuses dark-on-dark, the luma key refuses dark-subject — and picking one once is not
  picking it forever. Re-read the opacity line after every re-cut, not just after a code
  change.

  **The cue that works is local FLATNESS, not colour and not an edge** (`STD_FLAT`, D153).
  The installers verify the border is flat before cutting, so background is smooth by
  contract, while bandages, fur and wood grain are not — field-coloured pixels measure 0-2
  levels of local deviation and painted ones 7-20. Colour cannot be made to work at any
  threshold: 68% of a mummy's pixels are within `TOL` of the field colour. An edge gate was
  tried first and fails in both directions at once — it stops at the outline, so it leaves a
  two-pixel rim of background on every figure, and it does not fire at all on a faded flank.
  Three passes hang off the same idea: the rim is GRADED by colour rather than eroded, a
  trapped pocket must be featureless rather than merely flat (`POCKET_STD`) or clearing it
  punches a hole in an arm, and a bloom — flat, brighter than the field, reachable without
  crossing anything dark — is the subject's own light and still background. **And the colour
  surviving under a destroyed mask is a repair path, not just a diagnostic**:
  `tools/rematte_iso.gd` recovered all 23 figures from the files themselves, no new art. A
  repair tool must not assume its own direction, either — the campfire's correct mask is
  *smaller* than its broken one, so the tool rewrites on disagreement, not on growth.

  **That repair does not generalise, and six holed enemy plates are how we found out.** The
  iso figures came off a sheet and kept a border of field inside their own cells, which is
  what a second matte samples. A combat plate was trimmed at install and has none, so
  re-cutting all thirty-five made **every one of them 5-25 points more opaque**, healthy
  files included. They were repainted instead (D199). The deeper lesson is about *where* a
  cutout is judged: these had shipped holed because the arena draws an enemy over a dark
  corridor, where a hole reads as shadow. **A cutout can only be judged against something
  brighter than it** — the check is now a render onto flat magenta.

- **"Present" is not "correct", and a manifest that only counts files cannot tell you.** Every
  figure standing on the isometric floor was drawn HEAD-ON AT EYE LEVEL, while the tile is
  116x58 — exactly 2:1 — so the camera looks down from 27 degrees and all four walking
  directions project to screen diagonals. The brief had asked for a three-quarter isometric
  view all along; nothing ever checked, because the only question being asked was whether the
  file existed. The 23 hand-painted figures shipped that way and the 70 derived ones inherited
  it faithfully, because their source plates are framed head-on into the corridor *by design*.
  Its worst effect was silent: a bilaterally symmetric painting **mirrors to itself**, so
  `IsoFooting`'s whole facing model — three rounds of anchor arithmetic — has been decorative
  since it was written. The brief now states the angle as a measurement and names both
  diagonals, because "slightly above" is the adjective that produced this (D202).

- **A key colour you can find is a key colour you can see.** Asking a generator for a
  maximally-unlike backdrop makes the matte's job easy and its *residue* loud, and it
  exposed three defects that muted slate had hidden in every cutout ever installed:
  background sealed in by a silhouette but not enclosed (`key_clear`, opt-in via
  `--key` because the guarantee lives in the prompt, not the image); the field's colour
  left on the rim that survives (`despill_edge`, which repaints from the subject's own
  interior and so never needs to know the key colour); and the backdrop **still sitting
  under the alpha**, which `texture_filter = LINEAR` drags back into the sprite's edge
  regardless of alpha (`bleed_alpha`). Every cutout this library writes carried that last
  one; it only became visible when the backdrop was loud (D200).

- **A filter that asks one question is blind to everything on the other side of it.**
  `despeckle` removes opaque islands under 8% of the largest, and it was built for the
  generator's watermark, which is a speck in a corner. A generator that paints **two
  monsters** hands back two islands that are both large, so nothing in the pipeline said a
  word: the trim box stretched around both, and `rat_swarm` shipped with the rat at a third
  of its canvas and a robed figure's legs standing over it, through 42 passing tests (D194).
  Size alone cannot separate the cases — `powers/expose` is two arcs of one ring at 94% —
  and over all 310 cutouts the signal is the **gap**: every legitimate multi-part cutout
  overlaps its other half or sits directly on it, the broken one had 55px of air. The
  bottom-anchored families can ask this at all because the anchor names the subject: the
  body reaching lowest is the one standing on `PixelArt.STAND_LINE`, and in the rat's case
  it was the *smaller* of the two. It refuses rather than cleaning up (`--drop-stowaways`
  is the deliberate override), for the reason `despeckle` prints its count: from inside the
  tool, a stowaway and a floating limb the artist meant look identical.

- **A secret in the wrong place is indistinguishable from a secret that is absent**, so the
  absence has to say so and name the place. The Android key lives in *repository secrets*: not
  GitHub Variables (plaintext, and not read for these) and not environment secrets (the job
  declares no `environment:`, so they would not be there) — and both wrong answers used to end
  in a throwaway key and no explanation. Each one now fails with a message naming the tab
  (D161). That first diagnostic then named the wrong cause on its first real failure, twice
  over: a defaulted password turned "the secret is absent" into "the password is wrong", and
  `keytool` prints its reason on **stdout**, which the check sent to `/dev/null`. **A fallback
  is only honest where the thing falling back is not also an input to the check**, and a
  diagnostic is worth what its output stream is worth (D162).

- **A stub proves a branch; it does not prove a tool runs.** `make_release_key.sh` was tested
  here against a fake `keytool` because this machine had no JDK — which is exactly the state
  the machine it was written for was in, so it shipped unable to run at all, after prompting
  for a password twice (D159). The dev shell carries `pkgs.jdk` now and the script re-execs
  itself through `nix shell nixpkgs#jdk` when run outside it, the same way `gen_music.py` gets
  ffmpeg. **Check what a script cannot work without ABOVE its first prompt**, and when a
  dependency is missing locally, that is the finding — not an obstacle to route around.

- **A caveat on a download page is not a fix.** Every published APK was signed with a fresh
  throwaway key, so none could install over another; Android's word for that is *"App not
  installed"*, which mentions neither keys nor signatures. It was written down in BUILD.md and
  in the release notes for three milestones and still arrived as a bug report (D157) — because
  a user hits the failure, not the documentation. CI now uses a stable key when the repository
  has one (`ANDROID_KEYSTORE_BASE64`, made by `tools/make_release_key.sh`) and keeps the
  throwaway as a fallback so a fork with no secrets still builds. **An update needs a newer
  `version/code` AND a matching signature; each missing half fails with its own message.**

- **A permanent link makes the download anonymous, whatever provides the permanence.** The
  README's URLs never go stale — `releases/latest/download/<file>` is resolved by GitHub to the
  current release (D227; it was a tag that never moved off `latest` before that) — and every
  Android build ever published is called `TheOwing-android.apk`, same name, same size. So the
  build carries its own name: `application/config/version` is stamped per export by
  `tools/stamp_build.sh` and shown by `BuildInfo` on the title screen and in Settings (D156).
  The committed value must stay `-dev` and `test_content.gd` enforces that, because a version
  string that lies is worse than one that admits it was built by hand. **A footnote on the
  title screen earns its place by being different tomorrow** — which is the test D128's
  catalogue-sizes line failed and this one passes. Since D227 the stamp is also what a `v*`
  tag is checked against: `stamp_build.sh` refuses to export when the tag and
  `config/version` disagree, because a release page and a Settings screen stating different
  versions is the D34 shape in the one field only a bug report would ever compare.

  **A second channel is safe only while it cannot become the default download (D251).** A
  rolling build of `main` is published again, and the thing that makes it safe is one flag:
  `--latest=false` keeps `releases/latest/download/<file>` resolved to the newest `v*` release,
  so the rolling build is reachable for anyone who wants it and invisible to a stranger. That
  is the precise failure D227 removed — not that a build of main existed, but that it was the
  newest thing on the page and so the one a player took. What the permanence rule buys is the
  anonymous link; what this adds is that the link keeps pointing at the build somebody chose.

  A downloads badge stays deleted through both channels, for two different reasons. On the
  rolling one GitHub counted per release object and the object was recreated on every push, so
  the counter reset several times a day and read 0 after real downloads (D158). Per tag it
  would at last be true — and still resets to zero every time a version is cut, while a reader
  takes it for "how many people play this". **Before adding a badge, ask what it reads when the
  thing it measures is working** — and if the honest label would be "since the last release",
  there is no fact there to display.

- **A file that exists is invisible to a list of what is missing.** ART_PROMPTS.md asks
  for what is absent, which is right, and is why a file that landed *wrong* had nowhere to
  be recorded: the moment it appears on disk the sheet stops mentioning it and the defect
  lives only in somebody's memory. `art_manifest.gd`'s `REDO` table is the fix — a
  hand-kept list of files that exist and are wrong, each with the evidence, each line
  deleted when the re-roll lands (D109, D112). It deliberately detects nothing: the one
  measurement available guessed wrong about half the time, and a re-roll list built on a
  bad measurement throws away good paintings. **The largest instance of this went unseen
  for the whole project and is still open:** ART_PROMPTS.md says of the enemies "nothing
  to generate here — all 35 present", and twenty-nine of those thirty-five plates are
  featureless coloured silhouettes (D115). They are present, so the count cannot see
  them, and every capture of the combat screen ever taken happened to roll one of the six
  that are paintings. If a tier's files were produced in bulk by a tool, "present" is a
  statement about the tool having run, not about the art.

- **A batch tool's blind spot is the file that never travelled with a batch.**
  `strip_sparkle.gd` had cleaned the generator's watermark off twelve dungeon backdrops,
  the scene backdrops and the boot splash. `main_menu.png` kept its star the whole time,
  because it predates the installers and so was in none of those runs — and the tool
  cannot work on one image at all: it finds the stamp by intersecting "brighter than its
  surroundings" across a set, and one frame has nothing to intersect with (D163). It takes
  a hand-given search box now, with the automatic mask still measured inside it. **Ask
  which files were installed before the installer existed**, because every later pass over
  "all of them" means all of the ones the tool knows about.

- **A hint that names a control which is not on the screen is worse than a hint that
  names none.** The overworld's first-visit line ended with `"How this works" explains the
  rest`, naming a button in the row below it; the button moved to the title screen and the
  sentence stayed (D164). Removing a control means grepping for its LABEL, not just its
  callback — and the fix is usually to delete the pointer, not to re-aim it at wherever the
  screen went, because sending somebody out of a run to read a definition is an errand.
  Same screen, one door: two entrances to one place is the duplication D133 removed from
  that hub in the first place. **And a removal leaves a shape, not a hole** — the row that
  had held the button stayed behind with a spacer and one button in it, an almost empty
  line under the one it should have been part of (D165). Both leftovers showed up in a
  capture; neither showed up in the diff.

- **Sort a screen by "true for everyone" vs "true for this save", not by "reading" vs
  "doing".** How the Owing Works had the Builds tracker embedded in it, so half the screen
  stated the game's rules and half counted one player's cards, with nothing marking the
  join (D166). The axis that put it there — a hub button leads somewhere you *do*
  something, this is somewhere you *read* — is not the axis a player notices. Builds is
  reached from the Collection now, which holds the cards it counts, and a test fails if
  `glossary.gd` reads `MetaState` again. **The same split decides where new information
  goes:** a rule goes on the rules screen, a fact about this save goes on the screen that
  owns the thing it is a fact about.

- **A reward pool with no duplicates is a countdown, and it needs a gate or it just
  empties.** Every relic grant handed out a relic you did not own, so thirty relics was
  thirty grants however shallow the play — and the twelve dungeons pay 26 of them in one
  pass (D223). A collection meant to last needs the pool itself gated by depth, not just a
  rarity weighting on the roll: weights change *which* one you get, never *how many are
  left*. **Price the gate in a currency that can exceed the game** — `clear_count()` caps at
  twelve distinct dungeons, so any threshold past the end measured against it never opens.

- **A withheld reward and an unlucky one look identical, so say which.** An elite that
  drops no relic means "you own them all" or "the rest are sealed", and only one of those
  means keep going (D223). Any gate added to a random reward owes the player a sentence
  somewhere, or it reads as the reward being broken.

- **Count the ways into a feature, and check how many of them a finger can make.** D213's
  grid offered three — drag to the bay, double-click, and a 40x14 badge — and on Android all
  three are unusable: touch drag fights the scroll, `double_click` is not reliable on
  emulated mouse events, and a fingertip is bigger than the badge. The screen had no working
  way to build a deck and nothing failed (D220b). **A gesture is not a control. If every way
  in is a gesture, there is no way in on a touchscreen** — the fix was to put every verb in
  the card preview as a named button, which is also faster with a mouse.

- **Ship the mark, drop the press.** When a target is too small to hit, making it
  `MOUSE_FILTER_IGNORE` so taps fall through to the large thing underneath beats shrinking
  the gesture or growing the target (D220b). It keeps whatever the mark was teaching and
  leaves nothing dead. Remember its tooltip has to move somewhere reachable, or
  `tooltip_test.gd` fails — correctly.

- **A gesture that opens a modal cannot also be half of a compound gesture.** Clicking a
  card face opens `UI.inspect_card`, which raises a full-screen veil that swallows the next
  click — so opening it on the first press eats the second half of every double click and
  double-click-to-add can never fire (D213). The first press starts a 220ms timer instead.
  **Before adding a second meaning to a click, check what the first meaning puts on top of
  the thing being clicked.**

- **A refusal is part of the rule that refuses; a screen must not guess why.** Every
  denied card printed "Not enough energy" because `play_card` returned a bare `""` and the
  screen filled in the reason. Right most of the time, and absurd in the one case a player
  cannot reason about — a card showing cost 0 refused beside a full energy pool, because
  paying its HP cost would have been lethal (D216). `CombatEngine.why_not()` generates the
  reason where the rule lives, and `can_play` is *defined as* `why_not() == ""` rather than
  written beside it, so the two cannot drift.

- **A number that is true per-item can be a lie across the set.** A standing "next card
  costs 1 less" is subtracted from *every* card in hand, so five 1-cost cards all read 0 —
  five free cards, when only one can have it (D216). The per-card figure is right and must
  stay; what was missing is the **scope**, and scope is a fact about the turn, so it goes on
  the status line beside Block. Per-turn carriers are state the player is holding: if
  `end_turn` clears it, the screen should have named it.

- **When a player reports a rule is broken, check what the screen told them about the rule
  before checking the rule.** Three reports about discounts, two rounds of investigation
  starting in `play_cost`, and the arithmetic was correct every time — all three were the
  screen failing to say what the engine was doing (D216).

- **A diffed widget is a cache, and every number on it needs an entry in the invalidator.**
  The combat hand is diffed rather than rebuilt so cards can animate; `relabel` re-read the
  damage, the Block and the hover text, and not the cost. A discount landing left the price
  stale in both directions, and the player got a card advertising 0 that the engine charged
  full (D216). **When a face quotes live state, list every figure on it in the function that
  re-reads them** — and verify the guard by breaking the fix, or a regression test nobody
  has seen fail is a test whose subject nobody has confirmed it can see.

- **A layout that only looks correct because everything in it is one colour is not known
  to be correct.** The deck bay's rows overflowed their slots by 18px from the day they were
  built — `Icons.style_card_button` stacks its glyph above the label, giving a 52px minimum
  against a stated 26px row, and anchoring a Control to a rect never shrinks it below its
  own minimum. Invisible while the rows were identical flat plates; instantly obvious the
  moment each row had a different picture behind it (D213). Third time in this log a
  cosmetic change was what exposed a geometry fault nothing was testing (D95, D169). **Size
  a holder from `get_combined_minimum_size()` of what goes in it, not from the number you
  wish the row were.**

- **A drop target has to be a place, and it has to be able to turn its highlight OFF.**
  A target sized to its contents does not exist when it is empty, which is the state a
  player is in the first time they use it. And `can_drop_data` is the only hook called while
  a drag is over a target, so it is the natural place to light the frame — and nothing calls
  it when the cursor leaves or the card is dropped elsewhere, so a bay lit there stays lit
  for the session. `NOTIFICATION_DRAG_END` is the off switch and it is reachable only from
  `_notification`, which is why `CardGrid.DropBay` is a subclass and not three lambdas.

- **Measure the data before designing the panel that shows it.** "A card panel for every
  dungeon" would have printed the same nineteen cards three times on one screen, because a
  dungeon's pool is its ZONE's pool plus one to three exclusives (D166). What is
  per-dungeon is the count and the exclusives; the shared pool is drawn once. Ask what the
  numbers actually are before deciding what the layout repeats.

- **Clarity outranks voice on the control a confused player presses.** The rules screen was
  called "How this works" — a pronoun with no antecedent, and the one heading on a screen of
  At Risk, What You Keep and The Floor that was written as interface rather than as the
  game. It is "How the Owing works" (D165). *The Terms* fits the debt framing better and was
  rejected because on a title screen beside Quit it reads as a licence agreement. **The
  voice rule (D98, D127) binds hardest on the things a player handles knowingly; a label
  they press because they are lost has to say what it does first.**

- **A capture harness's default state can be the one state a screen has nothing to say
  in.** `tools/screenshots.gd` gives every capture all hundred cards — right for the
  screens that list what you hold, and the worst possible state for a want-list, where it
  means no dim slot is ever photographed (D166). It takes `partial` (two cards in five
  removed) and `meta` (out of a run — every row used to enter a dungeon, so the Collection
  was only ever captured in its mid-run mode) and the flags combine with `+`. **Ask what
  state makes a screen's new half visible, and add the row for it.**

- **An asset on disk is not an asset in the game, and nothing tells you.** The 21 painted
  status symbols shipped in D112 and were read by exactly nothing until D115 — the loader
  had a bitmap fallback, so the screens looked the same as before and no test could fail.
  Installing art and wiring art are two jobs; the manifest tracks the first and there is
  no equivalent for the second. When a tier lands, `grep` for one of its filenames before
  calling it done.

- **`set_anchors_preset()` does not resize a control — it PRESERVES the rect it has.**
  With `keep_offsets` false (the default) it rewrites the offsets so the control keeps
  its current rect, so calling it on a node created two lines earlier anchors 0x0 to the
  full parent and holds it there. Twelve card illustrations were installed, correctly
  named, resolving to the right texture, visible — and drawn into a zero-sized rect, so
  the picture band measured 0.0533 against source art at 0.302 (D121). Use
  `set_anchors_and_offsets_preset`, or preset BEFORE `add_child` while there is no
  parent rect to preserve against.

- **"The file is present" and "the art reaches the screen" are different claims.**
  `art_manifest.gd` counts a relic as present by stat-ing the path, which is what it
  measures and all it can measure. Six relic icons are installed, matted and verified at
  display size, and **nothing in `scripts/` reads `assets/art/relics/`** — no
  `Icons.relic()`, no reference at all, so the screen renders exactly as it did before
  they existed (D121). A present-count reads like a coverage figure and is not one.

- **A brief that names what will be drawn ON TOP of the art gets it drawn INTO the art.**
  The card tier told the generator "a cost numeral top left and an effect symbol top
  right" — meaning the plates the game composites over the picture — and got a painted
  "5", "8" and "15", against the same prompt's own FORBIDDEN-numerals line (D119). A
  family illustration is shared by twenty cards, so that is a permanently *wrong* cost on
  all of them. Third time in this shape (D101, D108). **Describe a keep-clear region by
  position and emptiness; never name its future occupant.**

- **Judge an icon at the size it is DRAWN, not the size it is stored.** A 128px relic is
  seen at 48px. `balanced_grip` installed clean, looked right in a file browser, and read
  at 48px as two floating fragments: its dark thin midsection fell outside the matte, and
  the despeckle dropped the severed pieces as specks. The count the installer prints is
  the tell — 41 and 101 were watermark, **167 was the handle** (D119). Cutout prompts now
  demand one connected solid mass, lighter than the field everywhere.

- **A style reference decides more than style.** "ONE saturated light source" plus a
  cyan-lit reference is a cyan light source every time — thirty relics that each obey the
  brief and collectively fail it, because "one *memorable* colour" is a claim about an
  icon relative to the other twenty-nine (D119). And past ~15 images one chat starts
  answering its own output instead of the subject line, returning near-duplicates that
  are individually well-made and on-style. **The only tell is that two results could
  carry the same caption** — so check each against its subject, not just the style block.

- **A generated document is only as current as the tool that writes it, and a tool
  advertises a deleted screen forever.** `art_manifest.gd` briefed 26 icons for the graph
  map, the dice track and the deck reveal through the entire life of a tree in which none
  of those three models existed — D94 deleted the models and nobody re-read the file that
  sells them (D111). Generation stops a list drifting from the *catalogue*; nothing stops
  the tool's own prose drifting from the *code*. So when a feature is deleted, grep
  `tools/` for it — and treat the totals as the tell: 209 files wanted did not move when
  a fifth of the shopping list stopped having a screen to land on.

## Layout

```
scripts/     game code — one file per screen or system; balance.gd owns all tuning
resources/   all content as .tres: cards, enemies, relics, powers, events, dungeons,
             zones, builds
scenes/      thin .tscn wrappers; screens build their UI in code
assets/      pixel/ (CC0 Kenney), art/ (painted + generated, incl. the computed app icon),
             audio/ (all ours: 5 loops, 24 effects, one instrument in tools/audio_voices.py)
tests/       48 suites + run.sh; export.sh and export_ready.sh need templates
tools/       diagnostics, not shipped: sim_balance.gd, playthrough.gd, debug_map.gd,
             screenshots.gd (renders every screen to PNG — drive it under
             `Xvfb -screen 0 1280x720x24`, NOT on the desktop, or a 16:10 monitor
             plus `stretch/aspect="expand"` hands you a 1280x800 viewport and hides
             everything that only clips at the shipped height — D115),
             readme_shots.gd (the second half of that harness: picks the seven
             captures the README shows, LANCZOS-downsamples them and writes
             docs/screenshots/ as WebP — the front page's pictures are generated
             so they cannot go stale, D141),
             plate_check.gd (composites every painted cutout over flat magenta,
             one sheet per family — the only way a hole in a sprite is visible,
             since combat draws them over a dark corridor where one reads as
             shadow; pair with refill_pockets.gd, which restores the ones that
             still carry paint — D218),
             drop_strays.gd (the other half: opaque islands the matte KEPT,
             which are the generator's watermark on anything installed before
             despeckle existed. Reports, never decides — the three it finds
             across the installed sets are all painted drips — D220),
             art_manifest.gd (driven by art_docs.sh — see the doc list below),
             art_docs.sh, design_index.sh and readme_downloads.sh (the three
             documentation generators; all take `--check`, which is how you find
             out a generated file has drifted without reading it — D196.
             readme_downloads.sh reads the PUBLISHED release's asset sizes, not a
             local build's, because the table documents what a player downloads;
             the four typed sizes it replaced were three megabytes low — D207),
             install_backdrops.gd, install_scene_backdrops.gd,
             install_cutouts.gd (mattes/trims/anchors enemies, relics, powers — D90),
             install_sheet.gd (slices an icon-set sheet into its files — D91),
             install_chrome.gd (the loose ui/ paintings — control chrome, the combat
             HUD and the card back — which have no catalogue to resolve names
             against, so its table IS the catalogue; per-file crop/matte/stretch,
             plus a luminance-alpha mode for the two blooms — D105, D112),
             cutout_lib.gd (the shared matte/trim/anchor, incl. trapped-pocket
             fill — D92; NOT a class_name),
             gen_ui_kit.gd (COMPUTES the nine-slice button frames — D83),
             strip_sparkle.gd (removes the generator's corner watermark — D83c;
             `--file=<png> --box=x,y,w,h` for one image, which has no
             intersection to find the stamp with — D163),
             bench_iso.gd (how long is a floor to generate and to walk — the crawl is
             most of the simulator's runtime, so check here before a full report)

             No tool generates art. Images are made in the Gemini web app driven
             by Claude in Chrome; ART_PROMPTS.md is the wording and the
             `gemini-browser` skill is the how (D263, D264).
docs/        the README's screenshots, and nothing else. Carries a .gdignore:
             nothing in the game loads them and Godot would otherwise write a
             .import and a .uid beside each one
.github/     ci.yml — suite and export-readiness on every push and PR, then
             (on a `v*` TAG or a push to main, D227/D251) three build-* jobs, one
             release job and one pages job, all on Ubuntu. TWO channels through
             the one release job: a `v*` tag publishes a release that is KEPT,
             main publishes ONE rolling prerelease under `main-latest` that the
             next push replaces. The iOS job is written and COMMENTED OUT — three
             rounds, never past xcodebuild, and its log needs admin rights to
             read (D147); it is preserved verbatim because the preset patch and
             the macOS setup do work. The Android key is a per-build throwaway
             unless the repository holds one secret. The README's download links
             are stable without naming a version because
             `releases/latest/download/` resolves to the current release, which
             is why a version is published `--latest` and never `--prerelease`
             (D142, D227) and why the rolling build is published
             `--prerelease --latest=false` — the same rule read from both ends.
             The pages job renders tools/downloads_page.py to GitHub Pages, which
             is where every downloadable version is listed (D251).
             actions/setup-godot/ is the shared cache-and-install step, and runs
             on both Linux and macOS
README.md    the front page, and the ONLY file here written for a PLAYER rather
             than for whoever works on this. What the game is, how to get it,
             what you do in it. Keep developer material out of it — it has one
             short section at the bottom pointing here, and everything that used
             to be spelled out on it (CI, badges, the flake, the test runner's
             two file kinds) already lived in these files in more detail (D207).
             Its download table is GENERATED by tools/readme_downloads.sh from
             the published release, and its screenshots by tools/readme_shots.gd
DESIGN.md    the full reasoning, decision by decision. Chapters 1-8 are the
             architecture and the plan; the rest is the log, which is most of
             the 11,600 lines. It opens with a GENERATED index
             (tools/design_index.sh) because the entries are not in numeric
             order — a correction lands beside its subject, not at the end. The
             range is not written down anywhere: read it off the index (D196)
ART.md       the art brief: the diagnosis, the style, the reasoning. Carries no
             file counts at all, on purpose — the tiers here are the ORDERING
             and ART_ASSETS.md owns every number (D34). §8 is the RE-ROLL list:
             art that is installed and in the wrong dialect, which is the one
             question a manifest cannot ask (D268)
ART_ASSETS.md  GENERATED — every art file wanted, and whether it exists yet.
             Present is not the same as agreeing: read it with ART.md §8
ART_PROMPTS.md GENERATED — the style block, the per-tier recipe, and which files
             must NOT be generated (D90)
             Both come from tools/art_manifest.gd via `tools/art_docs.sh`, which
             writes them TOGETHER and strips Godot's version banner. Regenerate
             both or neither: ART_PROMPTS spent a long time briefing sixty card
             illustrations that were already installed, because only the other
             one was ever refreshed (D101, D196). `--check` fails if either drifted
REVIEW.md    a review of the game AS A GAME (2026-08-01) — playability, graphics,
             originality, fun — with a prioritised fix list. Not a decision log:
             it is the outside view of what the systems currently add up to, and
             its P-lists are the argument for what to build next. Reconciled
             against the tree in D196; four items are genuinely open (a card
             grid, the iso floor filling the screen, the numeric relics, and an
             input map). RECONCILE IT WHEN YOU CLOSE ONE — a queue that still
             lists finished work reads as a bigger backlog than the project has
```

## Working rules

- **Before committing anything that touches tuning:** `tests/run.sh` (all suites) and
  `godot --headless --script tools/sim_balance.gd` (paste the numbers).
- **Before committing content or code:** `tests/run.sh` must be green, including
  `test_compile`, `PlayableTest` and `test_content`.
- **A green suite is only a claim that the checks RAN (D300).** A runtime script error aborts
  the function it happens in, leaves the exit code at 0 and lets `_ready` print its PASS line,
  so a whole section can stop running and the suite still reports green — `RewardNoteTest` did
  it for the life of a deleted function. `run.sh` reads stderr now and fails on a
  `SCRIPT ERROR`; a suite that provokes them on purpose prints `TEST EXPECTS ERRORS` and says
  in a comment why. Two do, and both `load()` scripts that name autoloads.
- **Green on the working tree is not green on the commit (D272).** The working tree is the
  union of everybody's unfinished work; CI runs `HEAD`. When another session is on the same
  checkout — which is normal here — verify the thing you actually pushed:

  ```bash
  git worktree add --detach /tmp/verify HEAD && /tmp/verify/tests/run.sh
  ```

  This is how a call reached `main` without its definition: `git status` showed `combat.gd`
  clean, the other session wrote into it before it was staged, `git add <path>` took their
  half, and the local suite passed because the tree still held both halves. **`git status` is
  a snapshot, not a lease.** Stage by hunk, or re-read a file between checking it and adding it.
- **On a shared tree, prefer the repair that ADDS to the one that reverts (D272).** Somebody
  else's uncommitted edit may exist in exactly one place — the file you just committed — so
  taking it back out deletes it everywhere. Commit the missing half instead.
- **Before committing anything that touches content or decisions:** run the three
  generators — `tools/art_docs.sh`, `tools/design_index.sh`, `tools/readme_downloads.sh`
  (or all three with `--check` first). Nothing runs them automatically, and a commit
  that changed twenty cards and added two decisions shipped all three stale (D210).
- **A new decision takes the next FREE number.** Check `grep -oE '^### D[0-9]+[a-z]?'`
  before writing one: two sessions picked D205 on the same afternoon and neither could
  see the other. `test_content.gd` now fails on a repeat, but the number is still yours
  to choose (D210).
- **A hook re-asserts this every turn.** `.claude/hooks/docs-current.sh` (a
  `UserPromptSubmit` hook in `.claude/settings.json`) injects a reminder to keep
  these two files current on every prompt, and escalates to a STALE warning when the
  working tree has changes under `scripts/` or `resources/` but none to AGENTS.md or
  DESIGN.md. It cannot write the docs for you — it makes sure you never forget to.
- **When you make a real decision, write it down** — a new `D##` section in DESIGN.md
  with what was tried, what was measured, and what broke — and update this file's
  pillars or content totals if they changed. Keeping these two documents current is
  part of the change, not paperwork after it.
- **Commit on `main` and push. Do not open a branch, and do not ask first.** The
  general advice an agent carries is to branch before committing to a default branch.
  That advice is for a shared repository and this one is not: every commit in the
  history is linear on `main`, there is no review step, and a branch here only adds a
  merge nobody needs. This rule is scoped to THIS repository — it says nothing about
  any other, where the default still applies.
- **Push only from a green suite.** The rule above removes the branch, not the check.
  `tests/run.sh` at 48 passed is the gate, and it matters more once the work goes
  straight to `main`: there is no branch to hold a red commit while it is fixed. A
  commit that shipped with `test_content` red is already in this history, recorded
  rather than amended so it stays findable.
- **Several sessions share this checkout.** Two have run at once more than once, and
  the working tree has held three unrelated decisions at the same time. Before
  committing, read what is actually staged: `git status` and `git diff --cached --stat`
  will show work you did not do. Commit it if the whole tree was asked for, and say so
  in the message rather than writing a confident account of somebody else's change.
