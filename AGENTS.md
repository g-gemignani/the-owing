# AGENTS.md — Deckcrawl

Brief for anyone (human or AI) picking up this project. It is the *why*: the game's
concept, the decisions that shaped it, and the working rules that keep changes from
breaking it. The *what* — file-by-file detail and the full decision log D1–D116 — is
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
3. **Run** — crawl the dungeon: a painted isometric building of rooms and corridors over
   several floors, explored a tile at a time, with things walking it that take a step
   whenever you do. Fight, shop, rest, hit events and crack chests, down to a named boss.
   (Three older traversal models — a node graph, a card draw, a dice board — lost to it in
   D88 and were deleted in D94; the `Traversal` seam they shared is still there.)
4. **Meta** — winning banks the run's gold and cards permanently; dying forfeits most
   of it. Between runs you fuse duplicates into levels, buy and level Powers and
   Relics, and unlock deeper zones.

Two-tier state makes this work:

- **`MetaState`** — the persistent character: collection, decks, relics, powers,
  gold, clears. On disk, versioned, migrated.
- **`GameState`** — one ephemeral run. Rebuilt each dungeon, risked on death.

## Content at a glance

100 cards · 35 enemy archetypes (6 painted, 29 on generated plates) · 12 bosses (one named per dungeon) · 30 relics ·
10 powers · 20 events · 12 dungeons across 5 zones · 1 traversal model · 37 test
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

- **The voice is content, and it belongs on the things the player handles.** Plain
  Anglo-Saxon, concrete nouns, mortuary and debt imagery, understatement — *"Cold stone
  and old debts"*, *"His pack is intact. He is not."*, The Grave-Sexton, The False Step.
  It was the strongest writing in the project and it was confined to flavour text, where
  it did no work, while thirty-six cards wore another game's names (D98). Cards now come
  from the same register. **Borrowed genre grammar is fine; a borrowed proper noun is
  not** — Block and Energy and intents are how the genre speaks, but a card called
  Bludgeon that deals exactly 32 and exhausts is somebody's specific design, and the
  constant is the tell. When new content needs a name, take it from `resources/events/`
  and the boss roster, not from the game this one is shaped like.

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
  tiles alone would have failed the suite, and deserved to.

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

- **Match the generator to the medium — but test where the line is.** Seamless materials
  are a solved problem in code and came out better than the packs they replaced;
  procedural monsters came out as coffins with antennae the first time (D89). When a
  plan has already argued that half a job is a bad fit, building that half anyway
  because the code is open is how a scoped pass becomes a rejected one.

- **A convention nobody can derive should be displayed, not documented.** The iso grid's
  four directions project to the four screen *diagonals*, so no key walks straight up and
  the choice of which diagonal W means is a genuine coin-flip. It is settled by putting
  the key letter on the move button next to its arrow (D87). Reach for this whenever the
  answer is arbitrary but the player still has to know it.

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
  Silhouettes are **derived** from fight behaviour, never tabled: the first two derivations
  put all 35 archetypes in one family, and the roster had to be read to find the one that
  separates them.

- **Variety inside a model has to be shown, not asserted.** Two dungeons on the same
  traversal model can pass every count and still be the same place. Architecture and
  surface are therefore *separate* axes (`ISO_STYLES` × `ISO_TERRAINS`, sixteen readings
  out of eight constants), both bounded by tests that check the tables index real things
  and that at least three of each are in use — and both judged by rendering floors side by
  side with `tools/IsoStyles.tscn`. That render is what caught two of four styles being
  indistinguishable, and the knob that fixed it (room-versus-corridor ratio) was the one
  that had been hardcoded (D82).

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

- **An asset on disk is not an asset in the game, and nothing tells you.** The 21 painted
  status symbols shipped in D112 and were read by exactly nothing until D115 — the loader
  had a bitmap fallback, so the screens looked the same as before and no test could fail.
  Installing art and wiring art are two jobs; the manifest tracks the first and there is
  no equivalent for the second. When a tier lands, `grep` for one of its filenames before
  calling it done.

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
assets/      pixel/ (CC0 Kenney) and art/ (generated backdrops + painted UI frames)
tests/       37 suites + run.sh; export.sh and export_ready.sh need templates
tools/       diagnostics, not shipped: sim_balance.gd, playthrough.gd, debug_map.gd,
             screenshots.gd (renders every screen to PNG — drive it under
             `Xvfb -screen 0 1280x720x24`, NOT on the desktop, or a 16:10 monitor
             plus `stretch/aspect="expand"` hands you a 1280x800 viewport and hides
             everything that only clips at the shipped height — D115),
             art_manifest.gd,
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
             strip_sparkle.gd (removes the generator's corner watermark — D83c),
             bench_iso.gd (how long is a floor to generate and to walk — the crawl is
             most of the simulator's runtime, so check here before a full report),
             gen_pollinations.py (drives ART_PROMPTS.md through Pollinations;
             PARSES the sheet rather than restating it, and refuses any
             text-only model because the style reference is mandatory — D100.
             `--browser` prints the same prompts for pasting into a chat UI
             by hand, no key — it prints its own paste count — D102)
DESIGN.md    the full reasoning, decision by decision (D1–D116)
ART.md       the art brief: the diagnosis, the style, the reasoning
ART_ASSETS.md  GENERATED by tools/art_manifest.gd — every art file wanted, and
             whether it exists yet. Never edit by hand; regenerate it.
ART_PROMPTS.md GENERATED by the same tool with `-- --prompts` — the style block, the
             per-tier recipe, and which files must NOT be generated (D90).
REVIEW.md    a review of the game AS A GAME (2026-08-01) — playability, graphics,
             originality, fun — with a prioritised fix list. Not a decision log:
             it is the outside view of what the systems currently add up to, and
             its P0 list is the argument for what to build next.
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
