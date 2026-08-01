# Enemy plates

One combat plate per enemy archetype, keyed by id — `PixelArt.enemy_art(id)` looks the
file up directly, so a plate lands on the enemy it was drawn for. **Generated, ours
outright, committed:**

    godot --headless --script tools/gen_enemy_art.gd
    godot --headless --import

The second command is not optional. `ResourceLoader.exists()` answers for the *imported*
resource, so a freshly written PNG with no `.import` sidecar is invisible to the game —
`combat.gd` silently falls back to the 16x16 pixel sprite and the capture looks exactly
like the generator did nothing. That cost a full render cycle to notice (D89).

## These are markers, not portraits

They are flat shadow-puppet silhouettes: read by outline, inked in the palette's dark
end, lit from above-left, standing on the contact mark `combat.gd` draws. Nothing here
attempts to look painted. A procedurally *painted* monster is a bad painting; a
procedurally *designed* marker is a good marker, because the rules that make a marker
work — one silhouette, one ink weight, one contact point, tier carried by size — are
exactly the rules a program holds perfectly across 35 files and a hand does not.

They replace CC0 Kenney tiles that were perfectly legal and badly wrong: 35 archetypes
and 12 named bosses shared 41 unlabelled 16x16 sprites **assigned by sort order**, so a
boss wore whichever tile the index reached and adding an archetype reshuffled everyone
downstream. At 240px in front of a painted crypt, one of those tiles reads as a black
pixelated cross.

## Shape comes from the fight, not from a table

`Balance.iso_family` already sorts archetypes into swarm / brute / caster from their own
data. This extends that rather than running alongside it:

| input | effect on the plate |
|---|---|
| `Balance.iso_family(id)` | which body plan — swarm, brute or caster |
| `hp_mult` | shoulder width and bulk |
| `dmg_mult` | length of the blade, size of the caster's light |
| `block_amount` | pauldrons, collar |
| `count_max` | how many of them stand on the plate |
| the id's hash | hue within the family's band, so no two match by accident |

All four numeric scales are normalised against **the catalogue's own spread**, measured
at generation time. An earlier version divided by constants picked by eye and every
archetype landed between 0.00 and 0.34 — a derivation that produced no visible
difference, which is worse than a lookup table because it looks principled.

There is no list of names anywhere in the generator. Add `resources/enemies/wraith.tres`
and it gets a plate on the next run, shaped by what it does in a fight.

## What the first attempt got wrong

Filled silhouettes with no waist and no gap between the legs. A shape running from
shoulder to floor at constant width is a **coffin** whatever you draw on top of it, and
nineteen brutes came out as coffins with antennae. Two fixes carried the whole
difference: the head sits clear of the shoulder line on a neck, and the legs are
separate shapes with air between them.

`ArtShapes.measure` reports a **waist ratio** — mid-height width over shoulder width —
and the generator prints the worst one on every run, so a slab cannot pass unnoticed
again. Brutes now measure 0.40–0.44; a coffin measures 1.00.

The second thing it got wrong was value. `BODY_DARK = 0.10` was being run through a
transform with a 0.25 floor and rendering at about 0.50, so the constants said "dark
silhouette" and the screen showed a pale pink creature floating in front of the room.
A constant named DARK has to survive the transform applied to it, and the only way to
know is to photograph it in context.
