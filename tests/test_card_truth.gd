## Headless test: a card never misreports itself.
##
## `CardData.description` is authored text baked at level 1. Everything that
## resolves an effect reads `eff_*()`, which scales with level. So a fused card lied
## to the player: a level-40 Bash read "Deal 10 damage." on its face while dealing
## 38, and disagreed with its own hover text, which was generated.
##
## Every player-facing string is now built from the same getters the engine uses.
## This test asserts they cannot drift apart again.
## Run: godot --headless --script tests/test_card_truth.gd
extends SceneTree

const CARD_DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	var scaled := 0

	for id in m.CATALOG:
		var base := load(m.CATALOG[id]) as CardData
		if base == null:
			continue
		for lv in [1, 10, Balance.max_level(base.rarity)]:
			var c := base.duplicate() as CardData
			c.level = lv
			var face := c.effect_text()
			var hover := Icons.card_tooltip(c)

			if face.strip_edges() == "":
				fails += 1; print("FAIL %s Lv%d has no face text" % [id, lv]); continue

			# every number the engine will actually use must appear on the face
			for pair in [["damage", c.eff_damage()], ["block", c.eff_block()],
					["poison", c.eff_poison()], ["vulnerable", c.eff_vulnerable()],
					["weak", c.eff_weak()], ["strength", c.eff_strength()],
					["dexterity", c.eff_dexterity()], ["thorns", c.eff_thorns()],
					["heal", c.eff_heal()]]:
				var n: int = int(pair[1])
				if n <= 0:
					continue
				if face.find(str(n)) == -1:
					fails += 1
					print("FAIL %s Lv%d: face says '%s' but %s is %d" % [
						id, lv, face, pair[0], n])
				if hover.find(str(n)) == -1:
					fails += 1
					print("FAIL %s Lv%d: hover text omits %s %d" % [id, lv, pair[0], n])

	# --- the actual reported bug: levelling must change what the card says ---
	for id2 in ["strike", "bash", "clear_mind"]:
		var lo := (load(CARD_DIR + id2 + ".tres") as CardData).duplicate() as CardData
		var hi := (load(CARD_DIR + id2 + ".tres") as CardData).duplicate() as CardData
		lo.level = 1
		hi.level = 40
		if hi.eff_damage() == lo.eff_damage() and hi.eff_block() == lo.eff_block():
			continue   # nothing scales on this card, nothing to report
		scaled += 1
		if hi.effect_text() == lo.effect_text():
			fails += 1
			print("FAIL %s reads the same at Lv1 and Lv40 while its numbers changed" % id2)
		# ...and it must no longer be the authored line, which never changes
		if hi.effect_text() == hi.description:
			fails += 1
			print("FAIL %s Lv40 still shows the authored text '%s'" % [id2, hi.description])
	if scaled == 0:
		fails += 1; print("FAIL no scaling card was actually exercised")

	# --- powers level too, and are shown the same way ---
	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p == null:
			continue
		var p1 := p.duplicate() as PowerData
		var p2 := p.duplicate() as PowerData
		p1.level = 1
		p2.level = p.level_capped()
		if p1.effect_text().strip_edges() == "":
			fails += 1; print("FAIL power %s has no face text" % pid)
		if p2.eff_damage() != p1.eff_damage() or p2.eff_block() != p1.eff_block():
			if p1.effect_text() == p2.effect_text():
				fails += 1
				print("FAIL power %s reads the same at Lv1 and Lv%d" % [pid, p2.level])

	# --- and nothing displays the stale field any more ---
	for f in ["res://scripts/ui.gd", "res://scripts/shop.gd",
			"res://scripts/powers_screen.gd", "res://scripts/deck_builder.gd"]:
		var src := FileAccess.open(f, FileAccess.READ)
		if src == null:
			continue
		var text := src.get_as_text()
		src.close()
		for bad in ["card.description", "p.description", "pd.description"]:
			if text.find(bad) != -1:
				fails += 1
				print("FAIL %s still shows %s, which does not scale with level" % [f, bad])

	if fails == 0:
		print("CARD TRUTH TEST: PASS (face and hover agree with the engine at every level)")
	else:
		print("CARD TRUTH TEST: FAIL (%d)" % fails)
	quit()
