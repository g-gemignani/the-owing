# Isometric floor art

Everything `scripts/iso_run.gd` draws for the `TraversalIso` model. **All 33 files are
ours outright and committed** — three tools, split by what they draw:

| | what it is | where it comes from |
|---|---|---|
| `floor*.png`, `rock*.png` | ground and wall materials | computed by `tools/gen_iso_art.gd` |
| the 23 figures and furniture | the hero, monsters, wanderers, stall, fire, rune, chest | **painted** in sheets, installed by `tools/install_sheet.gd` (Tier 8) |
| the same 23, before that | procedural markers | `tools/gen_iso_markers.gd`, still the fallback generator |

The figures were procedural markers first and are paintings now, and the difference
matters to the drawing code rather than only to the eye. A generated marker is symmetric
about its own foot point; a painting is not — `cutout_lib.place` bottom-anchors the subject
and centres its **bounding box**, and a painted figure's bounding box is its widest part,
which is a cloak or a swung axe and not the ground it stands on. `iso_run.gd` believed the
middle of the canvas was the foot point for a while after the paintings landed, and the
hero's two mirrored facings visibly stood beside their own tile as a result. The stand
point is measured off each file now (`IsoFooting.offset`, D149).

It was not always so. These replaced downloaded packs that were gitignored because
they could not be pushed at all, and for a milestone the ignored half sat here
undeclared under a README headed "licence status: UNKNOWN" (D89). Nothing in this
directory is gitignored now, and nothing in it came from outside.

## The materials are ours (D89)

Ten seamless materials — one ground/wall pair per terrain in `Balance.ISO_TERRAINS`,
plus the bare `floor`/`rock` fallback names — are **computed**, not downloaded:

    godot --headless --script tools/gen_iso_art.gd
    godot --headless --import

They are deterministic, so regenerating produces byte-identical files and an art pass
is a real diff rather than twelve mystery binaries. Their **palette is sampled from
the painted backdrops of the dungeons that actually use that terrain** — the Warrens
are `earth`, so the Warrens' floor is built from the colours of the floor in
`bg_warrens.png`, taken from the band below `PixelArt.HORIZON_LINE`. Repaint a
backdrop and the floor follows on the next run. Nothing here is matched by eye.

The generator prints a seam measurement against the interior as a control, because
`iso_run.gd` does not tile these — it UV-projects them per diamond with a per-cell
offset, so pixels from opposite edges meet *inside a single tile* and a mirror-blended
"seamless" texture would show its axis immediately.

## The figures are ours too

The hero, the three monster families, the four wanderer designs and the seven encounter
markers are painted for this project and installed from sheets. The packs they replaced
could not be pushed at all: the monsters shipped with no licence file of any kind, and the
hero's store page states "prototyping, **non-commercial** use", which is a hard limit
rather than an unknown. The installer for those packs, and the `.gitignore` block that kept
their filenames out of the repository, are both gone.

`tools/gen_iso_markers.gd` still builds the procedural set these were, and it is worth
keeping for the reason it was written: the creatures there share
`ArtShapes.brute/caster/swarm` with the combat arena's plates (`tools/gen_enemy_art.gd`),
and that sharing is a rule rather than a saving. D85 casts the enemy when the floor is laid
out, so a wanderer crossing a hall IS the fight it will become — the thing you see coming
has to be the thing you meet, and the paintings are commissioned per family for exactly
that reason.

`_s` faces the camera; `_n` is the same creature from behind. Two files per figure, because
the left-hand facings are the right-hand file mirrored (D131) — which is also why a
painting's stand point has to be measured rather than assumed (D149): a mirrored anchor
error moves the figure twice.

**A clean checkout still survives losing all of it.** Every lookup in `iso_run.gd` goes
through `ResourceLoader.exists` and falls back to the flat encounter glyphs the other
traversal views use; the player falls back to a lit ground ring and a lantern-bright
pip, which the code treats as the real marker rather than a degraded one — a lone figure
on textured stone in a scrolling window is genuinely hard to spot, and knowing where you
are is the one thing this screen cannot get wrong.

## They were markers first, and the markers still have a job

The procedural set was not a placeholder that got replaced and forgotten. A procedurally
*painted* monster is a bad painting, but a procedurally *designed* marker is a good marker:
one silhouette, one ink weight, one contact point, tier carried by size — rules a program
holds perfectly across twenty-three files and a hand does not. That is why the paintings
were briefed from those rules rather than instead of them, why the brief is generated from
the code that consumes it (`tools/art_manifest.gd`), and why `gen_iso_markers.gd` is still
here: it is the answer for any figure a painting fails to deliver.

The one rule the paintings could not keep is the contact point, because a painter frames a
subject and an installer trims a bounding box. So the game reads it back off the file
instead of asking the art to promise it.
