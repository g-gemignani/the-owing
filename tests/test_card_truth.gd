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
	for id2 in ["hack", "stave_in", "clear_mind"]:
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

	# --- and a card must not lie about the FIGHT either ---
	#
	# Level was only half of it. `eff_damage()` knows about fusion and nothing else,
	# so with Strength in play a "Deal 6 damage" card dealt 9 and still said 6 —
	# which made Strength and Dexterity invisible on the one surface a player reads
	# before spending energy. `CombatEngine.card_damage()/card_block()` are what
	# `_resolve()` itself uses; the face and the hover now quote those.
	var Engine2 = load("res://scripts/combat_engine.gd")
	var hack := (load(CARD_DIR + "hack.tres") as CardData).duplicate() as CardData
	var cover := (load(CARD_DIR + "cover.tres") as CardData).duplicate() as CardData
	var deck: Array[CardData] = []
	for i in 8:
		deck.append(hack.duplicate())
		deck.append(cover.duplicate())
	var eng = Engine2.new()
	eng.setup(deck, 200, 200, 1, Balance.Tier.NORMAL, "cultist")
	eng.player.strength = 5
	eng.player.dexterity = 3

	var live_dmg: int = eng.card_damage(hack)
	var live_blk: int = eng.card_block(cover)
	if live_dmg <= hack.eff_damage():
		fails += 1
		print("FAIL 5 Strength did not raise what Hack would deal (%d vs %d)" % [
			live_dmg, hack.eff_damage()])
	if live_blk <= cover.eff_block():
		fails += 1
		print("FAIL 3 Dexterity did not raise what Cover would give (%d vs %d)" % [
			live_blk, cover.eff_block()])
	if hack.effect_text(live_dmg, -1).find(str(live_dmg)) == -1:
		fails += 1
		print("FAIL the card face does not show the %d damage it would deal" % live_dmg)
	if Icons.card_tooltip(hack, live_dmg, live_blk).find(str(live_dmg)) == -1:
		fails += 1
		print("FAIL the hover text does not show the %d damage it would deal" % live_dmg)
	if cover.effect_text(-1, live_blk).find(str(live_blk)) == -1:
		fails += 1
		print("FAIL the card face does not show the %d Block it would give" % live_blk)

	# ...and the number shown is the number the engine then removes from an enemy.
	# This is the assertion that cannot be satisfied by a second, agreeing copy of
	# the arithmetic: it compares the text against the enemy's HP bar.
	var foe = eng.current_target()
	foe.block = 0
	foe.vulnerable = 0
	var hp_before: int = foe.hp
	var promised: int = eng.card_damage(hack)
	eng.energy = 9
	eng._resolve(hack)
	var actually: int = hp_before - foe.hp
	if actually != promised:
		fails += 1
		print("FAIL the card promised %d damage and dealt %d" % [promised, actually])

	# and with no Strength at all it must read exactly as it does at rest
	var calm = Engine2.new()
	calm.setup(deck, 200, 200, 1, Balance.Tier.NORMAL, "cultist")
	if calm.card_text(hack) != hack.effect_text():
		fails += 1
		print("FAIL an unbuffed card reads differently in combat: '%s' vs '%s'" % [
			calm.card_text(hack), hack.effect_text()])

	# --- the authored line must not contradict the engine either -----------------
	#
	# `description` is no longer shown to players (that is the check below), which is
	# exactly why it rotted: seven cards stated a number the engine had stopped using
	# — All You Have promised 32 damage and dealt 28, Kick promised Draw 2 and drew 1.
	# Nobody was misled, because nobody could see it, but it is the authored record of
	# what the card is FOR and every one of those was a tuning change that only got
	# half made. Numbers only: the phrasing is deliberately freer than the generated
	# face ("Gain 3 Dexterity (permanent)." vs "+3 Dexterity."), so requiring the
	# strings to match would only force the authored line to stop being useful.
	var digits := RegEx.new()
	digits.compile("\\d+")
	for cid3 in m.CATALOG:
		var c3 := load(m.CATALOG[cid3]) as CardData
		if c3 == null:
			continue
		var face3 := c3.effect_text()
		if face3 == c3.description:
			continue          # the fallback path: nothing to disagree with
		for hit in digits.search_all(c3.description):
			if face3.find(hit.get_string()) == -1:
				fails += 1
				print("FAIL %s is authored '%s' but does %s" % [
					cid3, c3.description, face3])
				break

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
