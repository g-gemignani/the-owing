## Cuts each archetype's ISO front sprite out of the combat plate it already has.
##
##   godot --headless --script tools/derive_iso_fronts.gd [-- --dry]
##   godot --headless --import
##
## **The floor was showing a family, not a creature.** `iso_run.gd` drew a cast fight as
## `mon_<family>_s`, and `Balance.iso_family` sorts thirty-five archetypes into three
## buckets — so twelve different swarms crossed the hall as one grey quadruped and
## nineteen brutes as one ogre. D85 bound the floor to the fight it becomes; what it could
## not do with sixteen paintings is make the thing you see the thing you meet. Family is
## good information at a distance and it is the WRONG information at four tiles.
##
## **No generator is involved, and that is the point.** `assets/art/enemies/<id>.png` is
## already a painted, matted, bottom-anchored front view of exactly this creature. A fresh
## iso painting of `cultist` would be a second opinion about what a cultist looks like;
## rescaling the plate is the same opinion, so the front facing matches the arena BY
## CONSTRUCTION rather than by a prompt asking nicely. Thirty-five files for nothing, and
## no batch of thirty-five re-rolls to police.
##
## The back views (`iso/foe/<id>_n.png`) cannot come from here — a plate has no back — and
## are painted per archetype. A missing one falls back to the family sprite, so this tool
## is useful on its own and does not wait for them.
##
## **The per-archetype set lives in its own directory, and that is not tidiness.** The
## obvious name was `iso/mon_<id>_s.png`, which collides on the first archetype tried:
## `brute` is BOTH a family in `Balance.ISO_FAMILIES` and an archetype id in
## `resources/enemies/`, so `mon_brute_s.png` would mean two different things and the
## derive step would silently overwrite the family fallback with one member of it. A
## subdirectory makes the collision impossible for every id, present and future, rather
## than for the one that was noticed.
##
## **What it does NOT do is re-matte.** `install_cutouts.gd` already cut these; the alpha
## on disk is the finished mask, and running the flood fill again over art that has no flat
## field left would eat it (D153). So this reads the alpha, and only `cutout_lib.place`
## runs — trim to the silhouette, scale to fit, anchor to the bottom edge.
##
## **Aspect is preserved and that is load-bearing.** A rat is wide and short, so it lands
## in the bottom third of a 128x192 canvas with air above it; `IsoFooting.rect` scales the
## whole canvas to `SPRITE_H` tile-heights, so the rat then DRAWS small and the ogre fills
## its two tiles. Size on the floor comes out of the painting's own proportions rather than
## a table, which is the same trade `IsoFooting` makes for the stand point.
extends SceneTree

const Cut := preload("res://tools/cutout_lib.gd")

const SRC := "res://assets/art/enemies/"
const OUT := "res://assets/art/iso/foe/"
## The iso figure canvas, matching `install_sheet.gd`'s `TALL["iso_figures"]`. Restated
## rather than imported because that file is a `SceneTree` and cannot be preloaded.
const CANVAS := Vector2i(128, 192)
## Coverage under which the placed sprite is reported. Not a refusal: a genuinely slight
## creature (a moth, a rat) legitimately covers very little of a canvas sized for an ogre,
## and the number is here to be read rather than to gate.
const THIN_COVER := 0.08

func _init() -> void:
	var dry := "--dry" in OS.get_cmdline_user_args()
	var ids: Array = PixelArt.archetype_ids()
	if ids.is_empty():
		print("no archetypes found in res://resources/enemies/")
		quit(2)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("=== iso fronts from combat plates (%d archetypes) ===" % ids.size())
	print("%-24s %-10s %-7s %s" % ["file", "plate", "cover", "family it replaces"])

	var wrote := 0
	var missing := 0
	for id in ids:
		var aid := String(id)
		var src_path: String = SRC + aid + ".png"
		var img := Cut.load_image(src_path)
		if img == null:
			print("%-24s MISSING PLATE %s" % ["foe/%s_s.png" % aid, src_path])
			missing += 1
			continue
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)

		# The plate's own mask, not a new one. `alpha_of` is the whole of the matte step
		# here, and the reason this tool cannot silently shred a painting.
		var alpha := Cut.alpha_of(img)
		var note := Cut.place(img, alpha, CANVAS, true)
		if note != "":
			print("%-24s FAIL %s" % ["foe/%s_s.png" % aid, note])
			missing += 1
			continue

		var cover := Cut.opaque_fraction(Cut.alpha_of(img))
		var fam := Balance.iso_family(aid)
		var flag := "  <-- thin" if cover < THIN_COVER else ""
		print("%-24s %-10s %5.1f%%  %s%s" % [
			"foe/%s_s.png" % aid, "%dx%d" % [Cut.last_bbox.size.x, Cut.last_bbox.size.y],
			cover * 100.0, fam, flag])

		if dry:
			continue
		var dst := ProjectSettings.globalize_path(OUT + "%s_s.png" % aid)
		if img.save_png(dst) != OK:
			print("   FAILED to write %s" % dst)
			continue
		wrote += 1

	print("\n%d written, %d without a usable plate%s" % [
		wrote, missing, " (dry run)" if dry else ""])
	if not dry and wrote > 0:
		print("Run `godot --headless --import` to write the .import sidecars.")
	quit(1 if missing > 0 else 0)
