# The Owing

[![latest release](https://img.shields.io/github/v/release/g-gemignani/the-owing?label=latest%20release&color=brightgreen)](https://github.com/g-gemignani/the-owing/releases/latest)
[![platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-brightgreen)](#get-it)
[![licence](https://img.shields.io/badge/licence-Apache_2.0-brightgreen)](LICENSE)

**A card game about debt.** You go down into a place with a deck of cards, you fight your way
to whatever is at the bottom of it, and if you make it out alive you keep what you found. If
you don't, you lose almost all of it.

It is free, there is nothing to buy inside it, and it does not need the internet.

![The Cinder Knight, the boss of the Slag Pits](docs/screenshots/CombatBoss.webp)

<sub>**The Cinder Knight**, waiting at the bottom of the Slag Pits — and you were told his name,
and what he does, before you chose to go down there.</sub>

---

## Get it

Pick your machine, download, open. There is no installer and no account.

<!-- BEGIN GENERATED DOWNLOADS -- tools/readme_downloads.sh -->

| | download | opening it |
|---|---|---|
| **Windows** | [`TheOwing-windows-x86_64.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-windows-x86_64.zip) (77 MB) | Unzip and run **TheOwing.exe**. Windows shows a blue "unrecognised app" box the first time — click **More info**, then **Run anyway** |
| **macOS** | [`TheOwing-macos-universal.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-macos-universal.zip) (98 MB) | Unzip, then **right-click the app and choose Open** (not double-click) so macOS offers you the Open button |
| **Linux** | [`TheOwing-linux-x86_64.zip`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-linux-x86_64.zip) (68 MB) | Unzip, then run `TheOwing.x86_64`. If it will not start, mark it executable first: `chmod +x TheOwing.x86_64` |
| **Android phone or tablet** | [`TheOwing-android.apk`](https://github.com/g-gemignani/the-owing/releases/latest/download/TheOwing-android.apk) (92 MB) | Copy it to your phone and tap it. Android 7 or newer. If it says *App not installed*, delete the older copy first |

<sub>Sizes read from the current build by `tools/readme_downloads.sh` — not typed here,
because typed ones were three megabytes stale and nobody could tell (D207).</sub>
<!-- END GENERATED DOWNLOADS -->

**[Every version, on one page →](https://g-gemignani.github.io/the-owing/)** The table above is
the current release. That page lists every version ever published, each with its own downloads,
and at the bottom the rolling build of `main` — today's work, replaced on every push.

**Your computer will probably warn you the first time.** That is expected and it is not about
this game specifically: Windows and macOS show that warning for anything not bought from a
company with a paid publishing certificate, which this isn't. The steps above get past it. On
Android the same thing takes the form of allowing an app from outside the Play Store.

**It is a prototype.** It is playable start to finish, but it is one person's project, it
updates several times a day, and things will change under you. Your saved progress lives on
your own machine and nothing is uploaded anywhere.

---

## What you actually do

**Choose where to go.** Every place tells you how hard it is, what the thing at the bottom is
called and what it does, and which cards only exist down there. You are never surprised into a
difficulty you did not pick.

**Take on a debt, if you fancy the risk.** Each door will make you an offer — pay some gold up
front and it wants something particular of you down there. Clear the place. Or reach the
bottom whatever it costs. Or get through without ever being caught in the open. Manage it and
you get your money back with interest and a sealed pack of cards. Fail and the money is gone.

**Go down.** The dungeon is a building, drawn from above at an angle — rooms, corridors, several
floors — and you explore it a tile at a time. Step into a room and you see the whole room. Step
into a corridor and you see almost nothing.

**Everything in there is walking toward you.** Nothing waits on a square for you to bump into
it. From the moment you arrive on a floor, the things on it are coming, and if you dawdle they
start moving twice for your once. When something reaches you, you can fight it — or shake it
off, which costs you health and costs you the turn everything *else* spends getting closer.

| | |
|---|---|
| ![Choosing a dungeon](docs/screenshots/ZoneView.webp) | ![The isometric crawl](docs/screenshots/IsoRunExplored.webp) |
| **You know what is down there before you go.** | **A floor is a building, not a board.** |

**Fight with your deck.** Each turn you draw a hand and spend energy playing cards — hit things,
raise a guard, poison them, make yourself stronger. Enemies tell you what they intend to do
before they do it, so a turn is a puzzle rather than a gamble. Some of them watch what you did
last turn and change their minds.

**Look around while you are down there.** Chests, keys lying in far corners, walls that are not
walls if you notice the mark on them, and a stone that will change the rest of the floor for a
price. Some floors leave an open ledger somewhere with a job written in it — deal this much
damage here, get every chest open, win a fight without ever playing an attack — and settling it
pays.

| | |
|---|---|
| ![Inspecting a card mid-fight](docs/screenshots/CombatHover.webp) | ![A sealed chest](docs/screenshots/Chest.webp) |
| **Cards can be read mid-turn, in place.** | **A chest shows you what kind of lock it has.** |

**Then get out.** Everything you picked up is held, not banked. Beat the thing at the bottom and
it is permanently yours. Die on the way and you forfeit most of it. That is the whole tension of
the game: the deeper you push, the more you are carrying, and the more a bad turn costs.

**Between runs, you build.** Duplicate cards fuse into stronger versions. Gold buys relics and
powers. Beating places opens new ones — and sometimes opens a back way into a neighbouring
place, one floor shorter with all the same fights packed into it.

| | |
|---|---|
| ![The collection](docs/screenshots/Collection.webp) | ![Powers](docs/screenshots/Powers.webp) |
| **The collection is the progress.** | **One power carried per run, usable every turn.** |

---

## How much of it is there

| | |
|---|---|
| Cards | 100, each with its own illustration, each levellable |
| Enemies | 35 kinds, plus 12 named bosses — one per dungeon |
| Places | 12 dungeons across 5 regions, from gentle to genuinely hard |
| Relics and powers | 30 relics, 10 powers |
| Things to find | events, chests, hidden rooms, riddles, altars |
| Jobs and debts | 46 floor jobs and 16 debts, drawn from what you actually did |

A full run takes somewhere between fifteen minutes and an hour, depending on how deep the place
is and how much of it you decide to turn over.

---

## If something goes wrong

**Tell me which build it was.** Every copy stamps its own version in the corner of the title
screen, and Settings spells it out under *Build*. That string identifies the exact code you were
running; the filename doesn't, because every release names its assets the same way.
Then [open an issue](https://github.com/g-gemignani/the-owing/issues).

Known rough edges, so you don't waste time reporting them:

* **Android has never been tested on a real phone.** It installs and runs, but text size on a
  small screen is the most likely thing to be wrong.
* **There is no iPhone or iPad version yet.** The build exists and does not currently work.
* **On NixOS**, the Linux build needs `steam-run` — see [BUILD.md](BUILD.md).

---

## Working on it

This part is for developers; if you only want to play, everything you need is above.

The game is built in **Godot 4.7** in GDScript, and all of its content is data files rather than
code, so adding a card or an enemy is a data task. There are 46 test suites, including one that
walks every screen and every dungeon checking the player always has something to press.

```bash
./run.sh                 # play it from source (needs Godot 4.7 on PATH, or set GODOT=)
tests/run.sh             # run everything, in parallel
```

| | |
|---|---|
| [AGENTS.md](AGENTS.md) | what the game is and the rules that keep changes from breaking it |
| [DESIGN.md](DESIGN.md) | every decision, what was measured, and what broke — the real documentation |
| [CONTRIBUTING.md](CONTRIBUTING.md) | how to add content |
| [BUILD.md](BUILD.md) | building and running on each platform |
| [ART.md](ART.md) | what it should look like, and every asset |

Two things are worth knowing before changing anything. **`scripts/balance.gd` is the only place
tuning lives**, so the game and the headless simulator cannot drift apart — a duplicated table
once made the first dungeon unplayable. And **tuning is measured, not guessed**:
`tools/sim_balance.gd` auto-plays fights and reports completion rates, and several designs that
read well on paper were reverted when the numbers came back.

---

## Licence

Code is [Apache 2.0](LICENSE).

The art under `assets/art/` — the title illustration, the 27 backdrops, the 35 enemy plates, the
100 card illustrations and the computed frame kit — was generated for this project and is **not**
CC0; see `assets/art/README.md`. The five music loops are ours too; see their `PROVENANCE.txt`.
All sound effects and music come out of one synthesiser built for this game
(`tools/audio_voices.py`), replacing three bought sound packs that made it sound like three
different games.

Two typefaces were downloaded and are under the **SIL Open Font License 1.1** —
[Cinzel](https://github.com/NDISCOVER/Cinzel) by Natanael Gama for headings, and
[Fira Sans](https://github.com/mozilla/Fira) by Carrois Corporate & Edenspiekermann for
everything else. Each ships its own `OFL.txt` in `assets/art/fonts/`.

The pixel art in `assets/pixel/` is **CC0** by [Kenney](https://kenney.nl) — 1-Bit Pack and
Pattern Pack Pixel. Kenney's work is public domain and needs no attribution; it is given here
because it is deserved.
