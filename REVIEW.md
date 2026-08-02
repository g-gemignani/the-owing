# REVIEW.md — The Owing, reviewed as a game

A content and design review of the prototype as of `8c55002` (branch
`art-pipeline-d89`), written 2026-08-01. This is deliberately not an engineering
review — the engineering is the part that is already good. It is a review of **the
thing a player meets**: what it plays like, what it looks like, what it borrows, and
what about it is worth finishing.

> **Baseline note.** The captures and measurements below were taken against `8c55002`
> plus the working tree at the start of the review. A concurrent session landed
> `3c85d43` and began removing the three unused traversal models while this was being
> written, which overtakes two items here — they are marked **[already in flight]**
> where they appear.
>
> **This is a living list, not a frozen snapshot.** Items fixed since are struck
> through and marked **DONE** where they appear, so the P0/P1/P2 lists stay usable as
> a work queue. The *measurements* in the evidence table below are not re-run and are
> stale by design — they date the review. Anything numeric here should be taken from
> the tool that produces it, never from this file.

It is blunt where blunt is useful. The project is well past the stage where
encouragement helps more than a list.

---

## Evidence this is based on

Everything below was measured or looked at, not inferred from the docs:

| what | how |
|---|---|
| 34/34 test suites | `tests/run.sh` — all green, zero sandbox strays *(37 suites now)* |
| 20 screens | `tools/Screenshots.tscn` rendered at the shipped 1280×720, every PNG inspected *(19 captures now)* |
| art coverage | `tools/art_manifest.gd` regenerated: **209 files wanted, 69 present, 140 missing** *(as of the review, and deliberately left dated. The 26 map icons this review said to drop were dropped (D111) and two batches of `ui/` files have landed since, so all three of those numbers are wrong. **Run the tool.** This parenthetical used to carry a refreshed figure; it went stale twice, which is the point D111 made — a document that restates a number something else owns is a document that lies on a delay.)* |
| balance | `tools/sim_balance.gd` at 400 trials (see the appendix — the original "could not be run" note was wrong, and the table has since been superseded by an in-flight level-curve rework) |
| content | all 100 cards, 30 relics, 10 powers, 20 events, 35 enemies, 12 dungeons read as data |
| code | 13,969 lines in `scripts/`, 8,015 in `tests/`, 4,996 in `tools/`, 6,683 lines of docs |

---

## Verdict

**The engineering is a long way ahead of the game.** The systems underneath are
carefully reasoned, measured rather than guessed, and documented to a standard most
shipped games never reach. The parts a player actually touches — the card faces, the
hand, the collection, the crawl, the reward moments — are the least finished parts of
the project, and the gap is widening because the discipline that produced
`balance.gd` has no equivalent pointed at *feel*.

Three things, in order:

1. **It has one genuinely original idea and it is buried.** The escrow — everything
   you find is *at risk* until you kill the boss, and an Escape Rope is the only way
   to walk out with it — is the best mechanic in the game. It is also invisible for
   the first hour and explained in a status line.
2. **The card is the object the player looks at for 90% of the runtime, and it has no
   art, clipped text, and ~~a name they cannot read at rest~~.** The name is readable now
   (D97); **the art is not there at all** and that is the half that still stands. This
   one screen is worth more than the other nineteen combined.
3. ~~**Roughly a third of the card names are Slay the Spire's, verbatim.** That is a
   real problem for a game whose stated pitch is "Slay-the-Spire-shaped, but…".~~
   **DONE** — renamed in D98, the fourteen copied constants re-tuned in D103. §4 below is
   the original finding and is kept as the argument for why, not as a live defect.

---

## 1. Systems and design — **strong**

This is the best dimension and it is not close.

**What works:**

- **The escrow.** Cards, gold, relics and packs found in a dungeon are usable
  immediately but only *become yours* if you beat the boss or spend a rope. It turns
  the classic roguelike death into a legible loss with a number attached, and it makes
  the Escape Rope one of the most interesting consumables I have seen in the genre.
  The Defeat screen — "Left behind in the dungeon: 3 cards and 140 gold… (an Escape
  Rope would have carried these out)" — is the single best-communicated screen in the
  build.
- **Difficulty as a stated choice.** You pick a dungeon knowing its difficulty rating
  *and its boss's signature behaviour* before you commit. "Boss: The Marrow-Abbot —
  Below 50% HP it enrages; every 3 turns it shields itself" is exactly the right
  amount of information: enough to build against, not enough to solve.
- **The difficulty ratchet (D36).** A dungeon scales to you only up to a ceiling set
  by its own depth, so you outgrow the Crypt and never outgrow the Maw. This is the
  correct answer to the meta-progression problem and most games in this space get it
  wrong.
- **`power_ratio` as an accounting discipline.** Every source of strength outside the
  deck gets folded into the number enemies scale against. The decision log shows this
  invariant being violated and caught six separate times, which is what a real
  invariant looks like.
- **Two reward channels with different rules (D80/D81).** A fight reward joins the run
  deck and therefore dilutes it — a decision. A sealed pack cannot touch the run it was
  found in — free. Clean, and correctly reasoned about.
- **The dungeon-exclusive card pools.** "Found only here: Cleave, Focus" gives each
  dungeon a reason to exist beyond its difficulty number.

**What doesn't:**

- **Twelve card mechanics appear on one to three cards each.** `damage_from_block` (1
  card), `strength_mult` (1), `retain_block` (1), `double_block` (2),
  `block_per_card_in_hand` (2), `damage_per_poison` (2), `damage_per_thorns` (2),
  `bonus_vs_debuffed` (2), `combo_at` (3), `energy_on_kill` (3), `hp_cost` (3),
  `lifesteal` (3). In a 12–20 card run deck drawn from a filtered pool, a mechanic on
  two of a hundred cards is not a build — it is a rounding error. Either give each of
  these a family of 4–6 cards so it can be built around, or cut it and stop paying for
  it in `combat_engine.gd`.
- **The Powers are all floors and no character.** Ten one-line effects, nine of which
  are "deal N" / "gain N" / "apply N". D37's reasoning for them (a floor under a bad
  draw) is sound, but nothing about equipping Blight versus Kindle changes *how you
  play* — only how much. A Power that changed a rule (draw an extra card but discard
  your leftmost; block persists but you cannot heal) would earn the slot.

---

## 2. Playability and UX — **the weakest dimension**

Every screen renders, nothing softlocks, `PlayableTest` guarantees a button on every
screen. Past that floor, the interface is a wall of left-aligned text sitting on top
of good paintings.

### 2.1 The hand is unreadable at rest — ~~highest-priority defect in the build~~ **DONE (D97)**

A card at rest deliberately shows only its **name**, its cost, and its headline number
(`ui.gd:458`, and the reasoning at `ui.gd:571` is sound). The problem is that the fan
layout (`combat.gd:595`) then covers the right-hand portion of every card except the
last with the neighbour on top of it — and the name is drawn across the card's full
inner width.

The result, from an actual capture of the combat screen:

```
Smith's Fu…   Prepare   Bludgeo…   Bite   Shiv
```

Three of five cards in the hand cannot be identified without hovering. The one thing
the resting state exists to show is the one thing the layout hides.

The fix is not to reduce the overlap (that is what makes a nine-card hand fit). It is
to **lay the name out in the strip that stays visible** — the left ~62% of the card,
matching the step the fan actually uses — and let the covered strip carry only the
art. This is measurable and belongs in `CardTextTest`: *for every card in a full hand,
the name's rect must not intersect the next card's rect.*

**Both halves of that were done (D97).** The card exposes `fit_name` and `_place_hand()`
calls it with the width the next card leaves uncovered, so the resting title re-fits into
the visible strip; the hovered layout is untouched. The assertion is in `CardTextTest`,
walking consecutive pairs, and it was proved non-vacuous the only way that counts — the
fix was disabled and the test reported four failures of 28–31px each. A fresh 1280×720
capture of the combat screen reads all five names in full.

**One gap, and it is the "full hand" in the sentence above.** The assertion only ever
runs on the hand a combat start deals, which is `Balance.HAND_SIZE` — five. Draw effects
and the extra-draw relics push past that, and `Combat.FAN_OVERLAP` (0.88) narrows the
step as the hand grows, so the case the wording was aimed at is the case nothing
measures. Not a defect on the evidence available; an untested boundary.

### 2.2 The deck builder and collection are spreadsheets

Choosing cards is the central act of a deckbuilder, and it happens in a scrolling text
list of rows like:

```
Anvil Stance [UNCOMMON] Lv1/40  owned 1   (blk 8)     [-] x0 [+]
```

Seven rows visible out of a hundred cards. Sixteen-pixel CC0 icons at the left. The
right half of the screen is empty. ~~Both screens draw on a flat black background — the
only two screens in the game with no backdrop at all, which makes them read as debug
tools that shipped. That last part is not a style choice: both bypass `UI.screen()`
and hand-roll their own container, and `UI.screen()` is what installs the backdrop
(defect 9).~~ **The backdrop half is DONE (D95)** — both now go through `UI.screen()`.
The spreadsheet half stands: a grid of card faces is still the right answer, and P1 #6
is still open.

A grid of actual card faces, at the size they appear in a hand, is the obvious answer
and the assets for it are the same assets §3 already needs.

### 2.3 Dead controls dominate two screens

The Collection shows ten stacked **"need 4+ copies"** buttons — disabled, identical,
and the visually loudest element on the page. The Relics screen with nothing found is
95% empty background with three lines of text at the top. Both are the same mistake:
the empty state was left as the absence of the full state instead of being designed.
Thirty locked relic silhouettes would make the Relics screen a reason to keep playing;
right now it is a reason to close it.

### 2.4 Alignment is visibly ragged

- ~~**Packs**: the three "Open" buttons sit at three different x positions, because each
  one is laid out after a label of a different length. Two of the three overlap the
  column the third starts in.~~ **DONE (D95)** — a Godot `Label` reports its *text* width
  as its minimum, so the `custom_minimum_size.x` that was already there was never a
  floor; `clip_text` makes it one. A fresh capture shows a straight column.
- **Collection**: the fuse buttons sit at two different x positions depending on
  whether that row happens to have a `next:` preview.
- **Shop**: all the interactive content is crowded into the top-left third; the painted
  merchant's counter — the part of the image that exists to hold goods — is empty.
- **The iso status bar** wraps mid-phrase: `AT RISK: 0` / newline / `cards, 0 gold`.

### 2.5 The isometric crawl uses a third of the screen

This is now the traversal model for **all twelve dungeons** (D88), so it is the second
most-seen screen in the game. In the capture it occupies roughly 30% of the viewport,
centred in a large field of empty dark blue, with two text buttons under it and two
full-width menu buttons under those. The floor should be the screen.

Related, and smaller: the player figure is an undetailed black obelisk with a staff.
At the size it is drawn it reads as a chess pawn. Given that the combat screen
deliberately does not draw the hero (a defensible framing choice), this silhouette is
the **only** representation of the player character in the entire game, and it is doing
that job badly.

### 2.6 Developer vocabulary is leaking into the UI **[partly in flight]**

Every dungeon row on the zone screen ends with **"isometric floor"**. That is the name
of an internal traversal enum. It is also now true of all twelve dungeons, so it
conveys nothing even to someone who understands it. *(A concurrent session removed
this line from `zone_view.gd` while this review was being written, with the same
reasoning.)*

The family it belongs to is still there: the raw `Deck 112` counter, `5/55 mapped`,
`AT RISK`, `Floor 1/2 · 0/13 cleared` — the crawl header is eight statistics in a row
and none of them is the one thing a player wants, which is *how much of this floor is
left*.

### 2.7 Input

There is no `[input]` section in `project.godot` and no `grab_focus` anywhere in
`scripts/`. Godot's default `ui_*` actions mean Tab and the arrow keys technically
walk the focus chain, but nothing ever seeds it, so the keyboard does nothing until
the mouse has been used, and there is no gamepad support and no rebinding. The crawl's
WASD keys are hardcoded in `iso_run.gd`. For a game that treats touch as a first-class
input this is a gap on the other end of the same axis.

---

## 3. Graphics and art direction — **good where it exists, and it exists in the wrong places**

### What is genuinely good

The **backdrops are excellent** and they are coherent. Twelve dungeon interiors, five
zone establishing shots, six screen backdrops — one style, one palette, one light
logic, symmetrical one-point perspective, and the discipline of keeping the light out
of the bands where text sits. The main menu illustration is the best single asset in
the project and would not look out of place on a store page.

The **35 enemy plates** are a real success. Standing on one line, weighted low and
dark against the bright floor band, sized by tier. The two Bone Pickers in the combat
capture read instantly as what they are.

### What is missing, and why it is the wrong 140 files

The regenerated manifest says **209 wanted, 69 present**. But the split is not random:

| tier | present / wanted | what this means in play |
|---|---|---|
| Dungeon + zone + screen backdrops | **23 / 23** | done |
| Enemy plates | **35 / 35** | done |
| Card illustrations | **0 / 12** | *every card in the game* |
| Vitals (HP/Block/Energy bars) | **0 / 9** | HP is the string `HP 60/60` |
| ~~Intent icons~~ | ~~**0 / 7**~~ | ~~an intent is the string `hit 5`~~ — **complete (D112)** |
| ~~Status icons~~ | ~~**0 / 21**~~ | ~~Poison/Weak/Vulnerable are text~~ — **complete (D112)** |
| Relic icons | **0 / 30** | relics are text rows |
| Power icons | **0 / 10** | the equipped Power is a text button |
| Combat impact FX | **0 / 6** | no hit sprite, no death, no card-play flourish |
| Frame kit (panel/inset/tooltip/card back/dropdown/slider/scrollbar/checkbox) | **11 / 24** | every list, tooltip and control is unstyled |
| ~~Map icons~~ | ~~**0 / 26**~~ | ~~for the graph model, which no dungeon uses~~ — **dropped from the manifest (D111)**, as P2 #14 asked |

**Everything painted so far is scenery. Nothing painted so far is something the player
touches.** That is the whole finding, and it explains why screens with beautiful
backdrops still look unfinished: the art and the interface are two different games
stacked on top of each other.

> The column above is the split *at the time of the review* and is not maintained — the
> two struck rows landed in D112, along with part of the frame kit and part of the vitals.
> The rows that still read `0 /` are the ones nobody has started. For the live figures ask
> the tool that owns them: `godot --headless --script tools/art_manifest.gd`, whose summary
> line and per-tier "*N files, M still to provide*" counts are the only current answer. The
> finding survives the update: the tiers still at zero are the card illustrations, the
> relic icons, the power icons and the combat FX — which is to say the split has begun to
> move but it has not moved on the object §3 says matters most.

### The card art specifically

`assets/art/cards/` does not exist. So `PixelArt.card_art()` (`pixel_art.gd:474`)
falls through to a **16×16 CC0 atlas tile**, which `ui.gd:494` then stretches across a
~160×210 card face at 22% alpha. A 16-pixel icon magnified ten times is not an
illustration; it is noise. In the combat capture the five cards in hand are covered in
grey and purple maze patterns that read as a rendering bug.

This is **exactly the lesson D89 already learned and wrote down** — "a 16×16 tile
magnified to 240px, reading as a black pixelated cross" — recurring on the one object
the player looks at more than everything else combined. Twelve family illustrations
(the manifest's own recommendation: one per effect family, not 100 unique paintings)
would change the look of the entire game more than any other twelve files could.

### Two art tiers are shipping side by side

The Chest, Victory and Defeat backdrops are visibly a **different, flatter tier** than
the rest: heavy uniform ink outlines, unrendered surfaces, low internal contrast —
next to the Crypt or the Merchant they look like line art that never got its paint
pass. Since Victory is the screen you see at the end of every successful run, this is
the worst place to have the weakest asset.

---

## 4. Originality — **the honest section**

The game's own pitch is "Slay-the-Spire-shaped combat, but the meta layer is
different." The meta layer *is* different and it is good. The combat layer is not
shaped like Slay the Spire — in large parts it **is** Slay the Spire.

### The card names

Of 100 cards, these are Slay the Spire card names **verbatim**:

> Adrenaline · Barricade · Bash · Battle Trance · Bludgeon · Body Slam · Caltrops ·
> Cleave · Dagger Throw · Defend · Demon Form · Entrench · Finisher · Footwork ·
> Heavy Blade · Impervious · Inflame · Iron Wave · Juggernaut · Perfected Strike ·
> Prepared · Pummel · Rupture · Searing Blow · Second Wind · Shiv · Shrug It Off ·
> Strike · Twin Strike · Whirlwind

That is **30**. Add the one-letter-off cases — Berserker Rage (*Berserk*), Dodge Roll
(*Dodge and Roll*), Cut and Run (*Cloak and Dagger*), Terrify (*Terror*), Blood Price
(*Blood for Blood*), Slash (*Slice*) — and it is closer to **36 of 100**.

### It is not only the names

Reading the effects made this worse rather than better. These are the same *card
design*, down to the tuned number:

| card | The Owing | Slay the Spire |
|---|---|---|
| Barricade | "Block no longer expires at end of turn." | "Block no longer expires at the end of your turn." |
| Body Slam | "Deal damage equal to your Block." | identical |
| Entrench | "Double your Block." | identical |
| Impervious | "Gain 30 Block. Exhaust." | identical, same 30 |
| Bludgeon | "Deal 32 damage. Exhaust." | identical, same 32 |
| Pummel | "Deal 2 damage 4 times. Exhaust." | identical |
| Adrenaline | "Gain 1 Energy. Draw 2. Exhaust." | identical |
| Cleave | "Deal 8 damage to ALL enemies." | identical, same 8 |
| Twin Strike | "Deal 5 damage twice." | identical, same 5 |
| Shrug It Off | "Gain 8 Block. Draw 1." | identical, same 8 |
| Footwork | "Gain 2 Dexterity." | identical, same 2 |
| Inflame | "Gain 2 Strength." | identical, same 2 |
| Strike / Defend | "Deal 6 damage" / "Gain 5 Block" | identical, same numbers |

Fourteen cards where the name, the effect and the constant are all the same. That is
past "genre convention" and into "this is that game's card, relabelled" — and the
numbers are the tell, because a number arrived at independently does not land on 32.

### The vocabulary

The status system is Slay the Spire's, term for term: **Block** that expires at the
start of your turn, **Vulnerable** at +50% damage taken, **Weak** at −25% damage
dealt, **Strength**, **Dexterity**, **Poison** that ignores block, **Thorns**,
**Intent** telegraphs, **Exhaust**, **Retain**, 3 **Energy** a turn, **relics**, a shop
that sells **card removal**, and **Ascension** as the post-clear difficulty ladder —
which is not even a mechanic name, it is that game's proper noun for the feature.

None of this is illegal and all of it is standard genre grammar by now. But "we are
the same as the leader plus a meta layer" is a much weaker position than this project
has actually earned, and the borrowing is concentrated in the first twenty minutes of
play — which is exactly the window where a player decides what your game *is*.

### What is actually yours, and is good

- The **escrow / at-risk** system and the Escape Rope economy.
- The **persistent fusable collection** — copies of one card, spent on levels — as the
  progression currency, with the tuning insight that raw card volume is the wrong
  metric and copies-of-one-card is the right one (D81).
- **Sealed packs typed by build**, which cannot affect the run they were found in.
- **Difficulty chosen up front with the boss's signature named**, instead of a random
  map.
- **A crawled isometric floor replacing the node map**, with the wanderers that take a
  step when you do.
- **Dungeon-exclusive cards**, so a place is a reason and not just a number.

### The recommendation

Rename the 36 — a `name`-field data edit, nothing structural, and the writing voice to
do it with is already in `resources/events/`. Then **re-tune the fourteen**: change the
constant, change the cost, or change one clause, so they are your cards and not
someone else's with a new label. A card that deals 32 and exhausts is a fingerprint;
one that deals 29 and costs 3 is a design.

Then re-skin two or three status effects into your own fiction (*Rot*, *Marrow*,
*Debt*, *Quiet* are all sitting right there in the dungeon names) so the tooltip
vocabulary stops reading as an import.

---

## 5. Fun and moment-to-moment feel — **thin, and fixable cheaply**

The systems generate good decisions. The game does not yet *celebrate* any of them.

- **Rewards do not land.** Beating a fight produces a status-bar sentence and three
  card buttons. Opening a pack produces a text line. The Packs screen offers
  **"Open all 3"** as the *first and largest button* — the interface telling you the
  rewards are chores to clear rather than moments to have. A card reveal that flips,
  one at a time, with a sound, is a day of work and is the highest fun-per-hour item
  on this list.
- **Victory is a stats table.** "Dungeons cleared: 0/12. Builds completed: 7/7. Relics
  found: 0/30." At the end of a successful run — the thing the escrow system has spent
  the whole dungeon making you care about — the game should show you *the haul you just
  made permanent*, as objects. `GameState.last_haul` already computes the sentence; it
  deserves a screen, not a line.
- **Combat feedback exists but is minimal.** There are tweens: floating damage numbers,
  a hit shake, a screen flash scaled to the hit (`combat.gd:722–814`) — better than
  most prototypes. What is missing is any *art* on top: no impact sprite, no death
  effect, no card-play flourish, no block shimmer. The manifest's 6 FX files.
- **The crawl is quiet in the wrong way.** The atmosphere writing is excellent
  ("Something else is walking this floor. You cannot hear it from here."), but the
  interaction under it is pressing a direction and reading a status line. There is a
  wanderer on the floor and the only evidence of it is a number in the header. Showing
  the prowler's last-known tile, or a footstep sound that gets louder, would turn the
  best line of prose in the game into a mechanic.
- **Relics are mostly not decisions.** Of 30 relics, **18 are numeric tiers of five
  templates**:
  - five `+N max HP` (Worn Boots 10, Iron Ration 15, Iron Heart 20, Hearth Stone 25, Giant's Marrow 40)
  - five `Start each combat with N Block` (Leather Wrap 4, Padded Vest 6, Kite Shield 8, Tower Shield 12, Bulwark Plate 18)
  - three `Gain N% more gold` (20 / 40 / 60)
  - two `Draw 1 extra card each turn` — **Keen Lens and Scholar's Lens are word-for-word identical**
  - two `Start each combat with N Strength` (Whetstone 2, Warlord's Banner 3)

  `AGENTS.md`'s own pillar, and commit `6cd2ad5`, say *"Relics that change how you
  play, not just your numbers."* The twelve that do — Bone Charm, Crown of Thorns,
  Weighted Soles, Duelist's Glove, Field Kit, Reliquary Heart — are good. The other
  eighteen are a loot table pretending to be a design.

---

## 6. Content depth and writing

Breadth is genuinely good for a prototype: 100 cards, 35 enemy archetypes, 12 named
bosses across 12 dungeons and 5 zones, 30 relics, 10 powers, 20 events, 7 build
archetypes, 8 difficulty tiers.

**The event prose is the best writing in the project and it is not close.** Twenty
one-line hooks that all land:

> *"Your reflection is a moment behind you."*
> *"They are singing your name, slightly wrong."*
> *"It is not hunting. It is begging."*
> *"His pack is intact. He is not."*
> *"She will not make it out. She knows the way in."*

The zone and boss names are on the same level — The Hollow Barrows, Beyond the Stair,
The Marrow-Abbot, The Grave-Sexton, The Last Vendor, The False Step. This voice is a
real asset and it is currently confined to flavour text. **It should be doing work.**
The card names that were borrowed from another game could all be replaced from this
voice; the status effects could be renamed into it; the Victory and Defeat screens
could be written in it. The person who wrote "Nothing here was built for people"
should be naming the cards.

---

## 7. Audio — **better than expected**

Nineteen named CC0 SFX plus five generated music tracks, on separate Music and SFX
buses created in code, crossfaded by place with a 0.45s fade, and a voice pool so a
burst of hits cannot spawn dozens of nodes. Both volume sliders route to something
real, and the reasoning for generating the music rather than picking a pack (licence
verifiability) is honest and documented.

The generated score is thin and loops audibly, and there is no combat-state music
(a boss's second phase, a low-HP sting). But this is a solved-enough problem sitting
well above the bar for a prototype, and it should not get more attention until §2 and
§3 are dealt with.

---

## 8. Engineering health — **excellent, with one cost**

Stated briefly because it is not the point of this review: 34/34 suites green (37 now),
sandboxed test state with a leak check, a single source of truth for tuning that the
tests actively defend against private copies, a headless balance simulator, a
screenshot harness, a `PlayableTest` that walks every screen, and a decision log
(D1–D92 at the review; well past that now — `DESIGN.md` owns the range and this line has
already been wrong twice, so it will not carry a figure again) that records what was
*tried and rejected*, with numbers. This is a better
engineering culture than most commercial projects have.

Two costs worth naming:

- **Documentation is 6,683 lines against 13,969 lines of game code.** `DESIGN.md`
  alone is 4,787 lines. That is defensible while the reasoning is still load-bearing,
  but the reader who most needs it — someone joining — will not read a 4,800-line file.
  It wants an index, or a split by system. *Worse since: it is now past 6,000 lines, and
  the D111 audit found its §1–§4 architecture chapter describing the pre-D65, pre-D94
  game in the present tense. A long file is a maintenance problem before it is a
  reading problem — nobody re-reads chapter three when they land decision one hundred.*
- **Three traversal models were maintained and used by zero dungeons.**
  `traversal_graph.gd`, `traversal_deck.gd`, `traversal_dice.gd`, `map.gd`,
  `deck_run.gd`, `dice_run.gd` — about 1,050 lines plus three scenes, plus their share
  of `test_traversal.gd`, plus 26 map icons still sitting in the art manifest as
  "wanted". D88 moved every dungeon to the isometric floor and they have been dead
  weight since. **[already in flight]** — a concurrent session is deleting them as
  this is written, which is the right call. The art manifest should lose the 26 map
  icons in the same pass, or the next artist gets briefed on a screen that no longer
  exists.

---

## Specific defects found

| # | where | what |
|---|---|---|
| 1 | `scripts/combat.gd:595` + `scripts/ui.gd:571` | ~~Card names are occluded by the fan overlap; a hand of 5 shows 3 truncated names. The resting state's only content is the part that gets covered.~~ **FIXED (D97)** — the name re-fits into the strip the fan leaves visible, with the pairwise assertion in `CardTextTest` proved non-vacuous. Only ever exercised at a five-card hand; see §2.1. |
| 2 | `assets/art/cards/` (absent) → `scripts/pixel_art.gd:474`, `scripts/ui.gd:494` | Zero card illustrations. A 16×16 CC0 tile is magnified ~10× across every card face and reads as noise. |
| 3 | `scripts/deck_builder.gd:262` | ~~Prints a bare `()` for any card with no damage and no block ("Abyssal Gift [RARE] Lv1/15 owned 1 ()"). `scripts/collection.gd:109` guards the identical string; the deck builder does not — the same duplicated-logic rot `AGENTS.md` warns about.~~ **FIXED (D95)** — the row builds a `stat_txt` and omits the parens when it is empty. |
| 4 | `resources/relics/` | ~~**Keen Lens** and **Scholar's Lens** are the same relic: "Draw 1 extra card each turn." Identical text, identical effect, different names.~~ **FIXED (D95)** — Scholar's Lens is now "Every 3rd turn, draw 2", a trigger rather than a sixth numeric tier. Note D95's own warning that the re-pricing is **unsimulated**. |
| 5 | `scripts/packs_screen.gd` | ~~The three "Open" buttons land at three different x positions; two overlap the column the third starts in.~~ **FIXED (D95)** — `clip_text` makes the label's minimum width an actual minimum. |
| 6 | `scripts/zone_view.gd` | Every dungeon row is labelled "isometric floor" — an internal enum name, and true of all 12, so it carries no information. **[fixed in the working tree while this was written]** |
| 7 | `scripts/iso_run.gd` (status line) | Header wraps mid-phrase: `AT RISK: 0` / `cards, 0 gold`. |
| 8 | `assets/art/bg_chest.png`, `bg_victory.png`, `bg_defeat.png` | Visibly a flatter, unrendered art tier than the other 20 backdrops. Victory is the end-of-run screen. |
| 9 | `scripts/deck_builder.gd:35`, `scripts/collection.gd:13` | ~~The only two screens with no backdrop — flat black. **Root cause:** both build their own `MarginContainer` + `VBoxContainer` instead of calling `UI.screen()`, which is the function that installs the backdrop.~~ **FIXED (D95).** The lesson generalised into a pillar: a helper whose whole value is uniformity needs a check that everyone is inside it. |
| 10 | `README.md` | ~~Stale in three places: "3 pluggable models" (there are 4, and only the unlisted one is used), "decisions D1 through D38" (D92), and "Art and audio are CC0 placeholders… there is no animation yet".~~ **FIXED**, and found stale again twice since — suite counts, the decision range and the Kenney licence list were all wrong at the D111 audit. A README that restates a count will go stale again; the durable fix is to stop restating them. |
| 11 | `project.godot` | No `[input]` map, and no `grab_focus` in `scripts/` — the keyboard does nothing until the mouse is used, no gamepad, no rebinding. |

---

## Found 2026-08-02, after the art batch landed

Recorded here rather than in the lists above because these are *new* and the lists are
the original review's queue. All measured at a true 1280x720 (D115: the harness renders
1280x800 on a 16:10 desktop and hides anything that only clips at the shipped height).

| what | state |
|---|---|
| `bg_world`, `bg_table`, `bg_ledger`, `bg_reliquary` are **half painted** — a hard seam at 42-59% down, flat grey below, across nine screen instances | handed to a concurrent session |
| `ui/cursor.png` 9.4% opaque, `ui/logo.png` 44%, both with the artwork intact in RGB — the matte cannot key a dark subject on a near-black field | FIXED (D125, `lumakey`) |
| `ui/boot_splash.png` shipped the generator's watermark, brightest thing in the first image anyone sees | FIXED (D125, `strip_sparkle --grow=`) |
| logo, target ring, all seven intent telegraphs, card glow, boot splash, cursors, divider: installed and read by nothing | FIXED (D125) |
| `intent_attack_multi` and `intent_poison` telegraph behaviour `EnemyData.Action` cannot produce — no multi-hit action, and no enemy applies Poison | OPEN; the fix is in the enum, not the art |
| "needs 1 clears"; every slider value rendered as "100.0"; "Block 0" shown at zero | FIXED (D125) |
| Victory's ascension line at **3.86:1** over the lit doorway, under the 4.5:1 floor the suite holds buttons to | FIXED (D125) — 5.8:1 |
| Encounter's three 1244px option bars; deck builder and overworld lists clipped mid-row; Shop's buttons at three x positions; Packs' "Open all" above the packs it skips | FIXED (D125) |
| **12 card illustrations across 100 cards**, so a five-card hand can show the same picture twice — "Abyssal Gift" and "Kick" are pixel-identical neighbours | OPEN, and it is a content decision, not a defect |
| Energy orbs read as three small dots at their shipped ~20px | OPEN |

## Priorities

### P0 — do these before anything else

1. ~~**Make the hand readable.** Lay the card name into the strip the fan leaves
   visible, and add the assertion to `CardTextTest`: in a full hand, no card's name
   rect may intersect the next card's rect.~~ **DONE (D97)** — both halves: the name
   re-fits to the fan's step, and the pairwise assertion is in `CardTextTest` and was
   proved non-vacuous by disabling the fix (four failures, 28–31px). A capture reads all
   five names. **One thing the wording asked for is still not covered**: the assertion
   only runs on the five-card hand a combat start deals, so "a full hand" — one pushed
   past five by draw effects, against `FAN_OVERLAP` 0.88 — is untested. Worth a hand-size
   sweep, not a re-open.
2. **Twelve card illustrations, one per effect family.** The manifest already
   specifies them and `PixelArt.painted_card_art()` already prefers them. This
   changes the look of the whole game. *(the single highest-leverage art job in the
   list)*
3. ~~**Rename the ~36 borrowed card names, and re-tune the 14 that copy the effect and
   the constant too.**~~ **DONE** — renamed in D98, re-tuned in D103. Eleven of the
   fourteen constants moved; `strike`/`defend` were measured at three values and kept
   at 6/5 on the numbers, and three mechanic-only cards were left alone. Verified to
   move no cell more than 12 points against a pre-change baseline.
4. **Fix defects 3, 4, 5, 7, 9, 10** — all small, all visible.
   **3, 4, 5, 9 and 10 are done** (3, 4, 5 and 9 in D95; 10 in D95 and again in the D111
   doc audit). **7 is the only one still open**: the crawl header wrapping mid-phrase
   (`iso_run.gd` `_refresh()`).

### P1 — the next tier

5. **Vitals as art, not strings.** HP/Block/Energy bars (9 files) plus the 7 intent
   icons. `HP 60/60` and `hit 5` are the two most-read pieces of text in a fight and
   both are placeholder.
6. **Rebuild the deck builder and collection as card grids** on a backdrop. They are
   where the deckbuilding happens and they currently look like debug screens.
7. **Give the rewards a moment.** Pack reveal one card at a time; a Victory screen
   that shows the haul as objects instead of a stats table; demote "Open all".
8. **Let the isometric floor fill the screen**, and give the player figure a
   silhouette worth being the only picture of the protagonist in the game.
9. **Redesign the eighteen numeric relics** into twelve that change a rule. Cut the
   duplicate outright.

### P2 — worth doing, not yet

10. Combat impact FX (6 files).
11. Relic and power icons (40 files) — needed before the Relics screen is worth
    opening.
12. Design the empty states: 30 locked relic silhouettes, a Collection that shows what
    you have not found.
13. Keyboard/gamepad focus, and an `[input]` map so the crawl's keys can be rebound.
14. ~~Consolidate or delete the three unused traversal models~~ **DONE (D94)**, ~~but
    drop their 26 map icons from the art manifest in the same pass~~ **DONE (D111)** —
    though not in the same pass, which is the whole finding: the models went in D94 and
    the manifest went on briefing their art for eleven more decisions.
15. Give the mechanics on 1–3 cards either a family or a funeral.
16. Split `DESIGN.md` by system, or give it an index.
17. **Profile `sim_balance.gd` again.** It runs fine (~8 min at 120 trials, ~9 at 400)
    — the appendix's original "cannot be run" claim was wrong and is corrected there —
    but that is still far off the ~53s of measured work `8514f38` profiled, and the gap
    is unexplained.

---

## Appendix — balance

> **CORRECTED 2026-08-01, after D103.** This section originally reported the simulator
> as effectively unrunnable — two attempts abandoned — and filed "re-time it" as a
> finding. **That was wrong, and the error was mine.** On a quiet machine a 120-trial
> report takes 7m40s–8m25s and a full 400-trial report finishes in about nine minutes.
> The two abandoned attempts were a concurrent session using all sixteen cores, plus —
> twice — my own `timeout` being shorter than the report and a pipe into `grep -c` that
> discarded the partial output when the process was killed. The tool is *slow* relative
> to the ~53s of measured work `8514f38` profiled, and that gap is still unexplained and
> still worth closing. But "slow" and "cannot be run" are different findings and this
> review made the wrong one. **A tool that looks broken under contention should be
> re-measured on a quiet machine before it is written up.**

The table below was a real measurement — 400 trials, taken after the D103 re-tune — but
**it is now superseded and should not be quoted.** A concurrent session rewrote the card
level curve about an hour later (`card_data.gd`, and `DMG_POWER_K` 0.15 -> 0.065 in
`balance.gd`), so these absolute rates describe a game that no longer exists. What still
holds is D103's *comparison*: baseline and result were measured under the same constants,
and the de-fingerprinting moved no cell more than 12 points. Re-measure once that curve
settles — see the D103 correction in DESIGN.md.

```
Starter   Crypt 100  Ossuary  67  Warrens 100
Early     Crypt 100  Warrens 100  Foundry  24
Mid       Warrens 100 Foundry  96  Ember   100
Status    Warrens 100 Foundry  66  Ember    62
Barricade Warrens  99 Foundry  18  Vault    30
Poison    Fungal   69 Rot      67
AoE       Rot      64 Market   36
Thorns    Slag     99 Stair    15  Maw      29
Maxed     Foundry 100 Vault    71
Relic     Warrens 100 Foundry 100  Vault    84
Late      Market   82 Stair    20  Maw      12
Endgame   Stair    62 Maw      67
Deep      Foundry 100 Vault    64
```

<details><summary>The superseded D75 figures this section originally quoted (120 trials)</summary>

```
Starter   Crypt  99   Ossuary 75
Early     Crypt 100   Foundry 61
Mid       Foundry 99  Ember   98
Status    Foundry 88  Ember   62
Barricade Foundry 50  Vault   52
Poison    Fungal 63   Rot     68
AoE       Rot    68   Market  28
Thorns    Stair  32   Maw     57
Relic     Foundry 100 Vault   89
Late      Stair  32   Maw     27
Endgame   Stair  70   Maw     67
```

</details>

Read as design rather than as tuning, two things stand out in the current numbers and
neither is a bug:

- **The opening cannot be lost.** Starter and Early both clear the Crypt at 100%. That
  is a defensible teaching choice, but it means the escrow — the mechanic the whole meta
  layer hangs on — never *bites* in the window where the player is learning what the game
  is about. Someone who cannot lose the Crypt has no reason to notice that "AT RISK"
  means anything. Note this survived D103 untouched: `strike` and `defend` were measured
  at three values and 6/5 was the only one that did not either gut the opening or
  over-scale the late game, so the softness is not a stray constant — it is the ratio
  floor at d1 doing exactly what D36 designed it to do.
- **The deep end is decided by equipment, not by play.** At the Maw: Late 12%, Thorns
  29%, Endgame 67%. At the Abyssal Stair: Thorns 15%, Late 20%, Endgame 62%. A 45–55
  point swing between builds at one depth is a build-selection problem presenting as a
  difficulty curve. Barricade at the Foundry (18%) and Early at the Foundry (24%) are the
  tightest cells; the Foundry remains the one early wall, as it has been since D75.

Neither is urgent relative to §2 and §3. The numbers are healthy; the game they
describe is not the part that needs work.
