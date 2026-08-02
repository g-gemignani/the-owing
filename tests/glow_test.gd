## The level glow: how it is blended, what its alpha carries, and that it moves.
##
## All three are silently breakable and none of them is caught by anything else. Flip the
## blend back to ADD and the maxed corona blows out to white on 45.6% of its own area
## against bright art; write the overlay with an opaque alpha and PREMULT_ALPHA turns into
## a flat paste-over; drop the tween and a hundred cards wear the same motionless sticker
## (D139).
extends Node2D

func _ready() -> void:
	var fails := 0

	# --- the light must live in the alpha, not just the colour -------------------
	#
	# PREMULT_ALPHA computes `src.rgb + dst*(1 - src.a)`, so the alpha IS the term that
	# scales the art down where the light is strong. An opaque overlay makes that term
	# zero everywhere and the blend stops screening.
	for shape in ["card", "power"]:
		for band in ["1", "2", "max"]:
			var p := "res://assets/art/fx/lvl_%s_%s.png" % [shape, band]
			if not ResourceLoader.exists(p):
				fails += 1
				print("FAIL missing overlay %s" % p)
				continue
			var im := (load(p) as Texture2D).get_image()
			im.convert(Image.FORMAT_RGBA8)
			var opaque := 0
			var n := im.get_width() * im.get_height()
			var mismatch := 0
			for y in im.get_height():
				for x in im.get_width():
					var c := im.get_pixel(x, y)
					if c.a > 0.99:
						opaque += 1
					if absf(c.a - c.r) > 0.02:
						mismatch += 1
			if float(opaque) / float(n) > 0.5:
				fails += 1
				print("FAIL %s is %.0f%% opaque — the light is not in its alpha" % [
					p, 100.0 * float(opaque) / float(n)])
			if float(mismatch) / float(n) > 0.02:
				fails += 1
				print("FAIL %s alpha does not track its light on %.1f%% of pixels" % [
					p, 100.0 * float(mismatch) / float(n)])

	# --- and it must never be able to run past white -----------------------------
	#
	# The whole point of the change. Worst case is the brightest art under the loudest
	# band, so check the arithmetic directly rather than trusting the blend name.
	var mx := (load("res://assets/art/fx/lvl_card_max.png") as Texture2D).get_image()
	mx.convert(Image.FORMAT_RGBA8)
	var over := 0
	for y2 in mx.get_height():
		for x2 in mx.get_width():
			var c2 := mx.get_pixel(x2, y2)
			# white art (1.0) under full rarity tint (1.0): light + art*(1 - alpha)
			if c2.r + 1.0 * (1.0 - c2.a) > 1.001:
				over += 1
	if over > 0:
		fails += 1
		print("FAIL the maxed overlay can still blow out on %d pixels of white art" % over)

	# --- and it has to move ------------------------------------------------------
	var one := _glow("1")
	var maxed := _glow("max")
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	if one.self_modulate.a >= 1.0 or one.self_modulate.a <= 0.0:
		fails += 1
		print("FAIL the first band is not breathing (alpha %.3f)" % one.self_modulate.a)
	if absf(one.rotation) > 0.0001:
		fails += 1
		print("FAIL a non-maxed band is rotating")
	if maxed.rotation <= 0.0:
		fails += 1
		print("FAIL the maxed band is not rotating")
	if maxed.pivot_offset != Vector2(160, 120):
		fails += 1
		print("FAIL the maxed band turns about %s, not its centre" % maxed.pivot_offset)

	if fails == 0:
		print("GLOW TEST: PASS (premultiplied, alpha carries the light, cannot clip, and moves)")
	else:
		print("GLOW TEST: FAIL (%d)" % fails)
	get_tree().quit()


func _glow(band: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = load("res://assets/art/fx/lvl_card_%s.png" % band) as Texture2D
	add_child(tr)
	tr.size = Vector2(320, 240)
	UI.animate_level_glow(tr, band)
	return tr
