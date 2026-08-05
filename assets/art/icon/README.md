# The app icon

Six PNGs, all **generated** by `tools/gen_icon.gd`. Nothing here was painted or downloaded;
the licence is the repository's (see `../../../LICENSE`).

    godot --headless --script tools/gen_icon.gd
    godot --headless --import

| file | size | used by |
|---|---|---|
| `icon_384.png` | 384×384 | `application/config/icon` — the window icon, and the fallback every exporter reaches for |
| `icon_192.png` | 192×192 | `launcher_icons/main_192x192` — Android before 8.0, and launchers that ignore adaptive icons |
| `icon_adaptive_bg_432.png` | 432×432 | `launcher_icons/adaptive_background_432x432` |
| `icon_adaptive_fg_432.png` | 432×432 | `launcher_icons/adaptive_foreground_432x432` |
| `icon_adaptive_mono_432.png` | 432×432 | `launcher_icons/adaptive_monochrome_432x432` — Android 13 themed icons |
| `icon_48.png` | 48×48 | nothing. The grid as authored, at 1:1, so the legibility question can be looked at |

## Why generated rather than painted

The same reason `tools/gen_ui_kit.gd` computes the frame kit: an illustration tool is bad at
the one rule this asset lives by. **A pixel-art icon has to sit on its grid at every size it
ships in**, and an image model draws 48-pixel-looking shapes out of anti-aliased edges and
hundreds of colours. The grid is authored here instead — 48×48, a multiple of the project's
16px pixel-art grid — and every shipped size is a whole-number scale of it:

    48 × 4 = 192      48 × 8 = 384      48 × 9 = 432

That is also why the project icon is 384 and not the 256 `ART.md` asked for: 256 ÷ 48 is
5.33, and scaling by that draws some pixels five wide and others six.

## The design

A gold coin with a skull struck into it, on a lit stone plate, **and a bite missing from the
coin's rim** — something is owed, and it is not whole. Colours are the game's own: the plate
is `boot_splash/bg_color` and the stone violet the backdrops are lit against, the struck bone
is `UITheme.INK`.

## Android wants three layers, and the mask is the trap

An adaptive icon is two layers the launcher composites and then masks to whatever shape the
phone prefers. **Only the central 66% of a 432px layer is guaranteed to survive that mask**,
so the emblem lives inside the middle 32 of the 48 cells and the plate is full-bleed beneath
it. The 192px icon is composited here, because Android before 8.0 does none of its own.

The monochrome layer carries its shape in **alpha**, which makes a blank one and a correct one
look identical in every image viewer — it only shows up on a phone with themed icons enabled.
The generator measures it and fails instead of writing one, because the first run produced
exactly that: an empty layer, from a colour comparison that could not survive 8-bit rounding.

Replacing this with a painted icon is a file swap — keep the names above — but read the
grid rule first: a 432px painting scaled to 192 by anything other than a whole number is the
mush the whole pixel-art pipeline exists to avoid.
