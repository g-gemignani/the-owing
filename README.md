# The Owing

[![latest release](https://img.shields.io/github/v/release/g-gemignani/the-owing?label=latest%20release&color=brightgreen)](https://github.com/g-gemignani/the-owing/releases/latest)
[![platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-brightgreen)](#get-it)
[![licence](https://img.shields.io/badge/licence-Apache_2.0-brightgreen)](LICENSE)

**A card game about debt.** You take a deck of cards into a dungeon. You fight your way to the
bottom. If you get out alive, you keep what you found. If you die, you lose most of it.

The game is free. Nothing inside it costs money. It does not need the internet.

![The Cinder Knight, the boss of the Slag Pits](docs/screenshots/CombatBoss.webp)

<sub>**The Cinder Knight** waits at the bottom of the Slag Pits. You were told his name, and what
he does, before you chose to go down there.</sub>

---

## Get it

Pick your machine. Download the file. Open it. There is no installer and no account.

<!-- BEGIN GENERATED DOWNLOADS -- tools/readme_downloads.sh -->

| | download | opening it |
|---|---|---|
| **Windows** | [`TheOwing-windows-x86_64.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-windows-x86_64.zip) (79 MB) | Unzip and run **TheOwing.exe**. Windows shows a blue "unrecognised app" box the first time — click **More info**, then **Run anyway** |
| **macOS** | [`TheOwing-macos-universal.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-macos-universal.zip) (100 MB) | Unzip, then **right-click the app and choose Open** (not double-click) so macOS offers you the Open button |
| **Linux** | [`TheOwing-linux-x86_64.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-linux-x86_64.zip) (70 MB) | Unzip, then run `TheOwing.x86_64`. If it will not start, mark it executable first: `chmod +x TheOwing.x86_64` |
| **Android phone or tablet** | [`TheOwing-android.apk`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-android.apk) (94 MB) | Copy it to your phone and tap it. Android 7 or newer. If it says *App not installed*, delete the older copy first |

<sub>Sizes read from the current build by `tools/readme_downloads.sh` — not typed here,
because typed ones were three megabytes stale and nobody could tell (D207).</sub>
<!-- END GENERATED DOWNLOADS -->

**[Every version, on one page →](https://g-gemignani.github.io/the-owing/)** The table above holds
the current release. That page lists every version, each with its own downloads. At the bottom of
it sits the rolling build of `main`, which is today's work and changes on every push.

**Your computer will warn you the first time.** This is normal and it is not about this game.
Windows and macOS warn about any program that does not carry a paid publishing certificate. This
one does not have such a certificate. The steps in the table get you past the warning. On Android
the same thing takes the form of allowing an app from outside the Play Store.

**It is a prototype.** You can play it from start to finish. One person makes it, it changes
several times a day, and things will move under you. Your saved game stays on your own machine.
Nothing goes to a server.

---

## What you do

**Choose where to go.** Every dungeon tells you what you face before you enter. You learn how hard
it is, what waits at the bottom, and what that thing does. It also names the cards that drop only
down there. A difficulty never surprises you.

**Take a debt, if you want the risk.** Each door offers you a deal. You pay gold now, and the
dungeon asks one thing of you in return. Clear it. Or reach the bottom whatever it costs. Or get
through without ever being caught in the open. Meet the terms and your gold comes back with
interest, plus a sealed pack of cards. Fail and the gold is gone.

**Go down.** A dungeon is a building, drawn from above at an angle. It has rooms, corridors and
several floors, and you explore it one tile at a time. Step into a room and you see all of it.
Step into a corridor and you see almost nothing.

**Everything down there walks toward you.** Nothing sits on a square and waits for you. From the
moment you reach a floor, the things on it come for you. If you are slow, they start to move twice
for your once. When something reaches you, you can fight it. You can also shake it off, which
costs health and one turn — and everything else uses that turn to get closer.

| | |
|---|---|
| ![Choosing a dungeon](docs/screenshots/ZoneView.webp) | ![The isometric crawl](docs/screenshots/IsoRunExplored.webp) |
| **You know what is down there before you go.** | **A floor is a building, not a board.** |

**Fight with your deck.** Each turn you draw a hand and spend energy on cards. You hit, raise a
guard, poison, or make yourself stronger. Every enemy shows what it will do next, so a turn is a
puzzle and not a gamble. Some enemies watch what you did last turn and change their plan.

**Look around while you are down there.** Floors hide chests, keys in far corners, and walls that
open if you notice the mark on them. One stone will change the rest of the floor for a price. Some
floors hold an open ledger with a job written in it. Deal this much damage. Open every chest. Win
a fight without playing an attack. Settle the job and it pays.

| | |
|---|---|
| ![Inspecting a card mid-fight](docs/screenshots/CombatHover.webp) | ![A sealed chest](docs/screenshots/Chest.webp) |
| **Read any card in the middle of a turn.** | **A chest shows you what kind of lock it has.** |

**Then get out.** Everything you pick up is held, not banked. Beat the thing at the bottom and it
is yours for good. Die on the way and you lose a share of it, and how much comes home depends on
how deep you got. Reach the bottom and half of it still survives. The game never takes what you
already owned. That is the whole tension. The deeper you go, the more you carry, and the more one
bad turn costs you.

**Relics are lent, not kept.** Elites and chests lay out three of them and you take one. It works
for the rest of the run. Then it is gone, whether you win or lose. What you keep is the record
that you met it.

**Between runs you build.** Duplicate cards fuse into stronger ones. Gold buys powers and raises
their level. Each place you beat opens another. Sometimes it opens a back way into a neighbour,
one floor shorter, with all the same fights packed into it.

| | |
|---|---|
| ![The collection](docs/screenshots/Collection.webp) | ![Powers](docs/screenshots/Powers.webp) |
| **The collection is the progress.** | **Three powers are dealt at the door. You take one.** |

---

## How much is in it

| | |
|---|---|
| Cards | 100. Each has its own illustration and each can be levelled |
| Enemies | 35 kinds, plus 12 named bosses — one for each dungeon |
| Places | 12 dungeons across 5 regions, from gentle to genuinely hard |
| Relics and powers | 38 relics, lent for one run — 30 powers, three dealt at the door |
| Things to find | events, chests, hidden rooms, riddles, altars |
| Jobs and debts | 45 floor jobs and 16 debts, drawn from what you actually did |

One run takes between fifteen minutes and an hour. The length depends on how deep the place is,
and on how much of it you turn over.

---

## If something goes wrong

**Tell me which build you played.** The title screen prints the version in the corner, and
Settings shows it under *Build*. That string names the exact code you ran. A file name does not,
because every release names its files the same way. Then
[open an issue](https://github.com/g-gemignani/the-owing/issues).

Known rough edges, so that you do not waste time on them:

* **Android has never been tested on a real phone.** It installs and runs. Text size on a small
  screen is the most likely thing to be wrong.
* **There is no iPhone or iPad version yet.** The build exists and does not work.
* **On NixOS**, the Linux build needs `steam-run` — see [BUILD.md](BUILD.md).

---

## Working on it

This part is for developers. If you only want to play, everything you need is above.

The game is built in **Godot 4.7**, in GDScript. All of its content is data files rather than
code, so a new card or a new enemy is a data task. There are 48 test suites. One of them walks
every screen and every dungeon and checks that the player always has something to press.

```bash
./run.sh                 # play it from source (needs Godot 4.7 on PATH, or set GODOT=)
tests/run.sh             # run everything, in parallel
```

| | |
|---|---|
| [AGENTS.md](AGENTS.md) | what the game is, and the rules that keep changes from breaking it |
| [DESIGN.md](DESIGN.md) | every decision, what was measured, and what broke — the real documentation |
| [CONTRIBUTING.md](CONTRIBUTING.md) | how to add content |
| [BUILD.md](BUILD.md) | building and running on each platform |
| [ART.md](ART.md) | what it should look like, and every asset |

Two things are worth knowing before you change anything. **`scripts/balance.gd` is the only place
tuning lives**, so the game and the headless simulator cannot drift apart. A duplicated table once
made the first dungeon unplayable. And **tuning is measured, not guessed**: `tools/sim_balance.gd`
plays fights by itself and reports completion rates. Several designs that read well on paper were
reverted when the numbers came back.

---

## Licence

Code is [Apache 2.0](LICENSE).

The art under `assets/art/` was generated for this project and is **not** CC0. It covers the title
illustration, the 27 backdrops, the 35 enemy plates, the 100 card illustrations and the computed
frame kit. See `assets/art/README.md`. The five music loops are ours too. See their
`PROVENANCE.txt`. Every sound effect and every music track comes out of one synthesiser built for
this game (`tools/audio_voices.py`). It replaced three bought sound packs that made the game sound
like three different games.

Two typefaces come from outside this project. Both are under the **SIL Open Font License 1.1**.
[Cinzel](https://github.com/NDISCOVER/Cinzel) by Natanael Gama sets the headings.
[Fira Sans](https://github.com/mozilla/Fira) by Carrois Corporate & Edenspiekermann sets
everything else. Each one ships its own `OFL.txt` in `assets/art/fonts/`.

The pixel art in `assets/pixel/` is **CC0** by [Kenney](https://kenney.nl) — 1-Bit Pack and
Pattern Pack Pixel. Kenney's work is public domain and needs no attribution. It is given here
because it is deserved.
