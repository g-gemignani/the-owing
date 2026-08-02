## Headless test: no level a player can buy is allowed to buy nothing (D109).
##
## This exists because the whole game failed it and nothing noticed. Measured on the
## catalogue as it stood: 3,559 of 4,640 card level-ups (77%) and 44 of 63 power
## level-ups changed no number at all, commons worst at 86%, and eight cards plus two
## powers changed nothing at ANY level — Focus, Read Ahead, See It Coming, Kick,
## Abyssal Gift, Ram, Double Down, Set Stone, Foresight, Push On. Fusion charged
## copies and gold for every one of them.
##
## Every other suite in here was green throughout, because they all checked the
## ENDPOINTS of the curve (a maxed card is stronger than a level-1 card; a maxed card
## is not absurdly stronger) and never a step in the middle.
##
## Run: godot --headless --script tests/test_levels.gd
extends SceneTree

## Everything a level is allowed to move. A card improves on a level if ANY of these
## does — a Bash gaining damage while its Vulnerable stands still is a real upgrade.
## Two of them improve by getting SMALLER, so they are compared the other way.
func _rising(c: CardData) -> Array[int]:
	return [c.eff_damage(), c.eff_block(), c.eff_heal(), c.eff_draw(),
		c.eff_poison(), c.eff_vulnerable(), c.eff_weak(),
		c.eff_strength(), c.eff_dexterity(), c.eff_thorns()]

func _falling(c: CardData) -> Array[int]:
	return [c.eff_cost(), c.eff_hp_cost()]

## "" when the level is an improvement, else why it is not.
func _step(c: CardData, level: int) -> String:
	c.level = level - 1
	var was_up := _rising(c)
	var was_down := _falling(c)
	c.level = level
	var now_up := _rising(c)
	var now_down := _falling(c)
	for i in now_up.size():
		if now_up[i] > was_up[i]:
			return ""
		if now_up[i] < was_up[i]:
			return "Lv%d makes something WORSE (%d -> %d)" % [level, was_up[i], now_up[i]]
	for i in now_down.size():
		if now_down[i] < was_down[i]:
			return ""
		if now_down[i] > was_down[i]:
			return "Lv%d raises a cost (%d -> %d)" % [level, was_down[i], now_down[i]]
	return "Lv%d buys nothing" % level

func _init() -> void:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	var levels_checked := 0

	# --- every card, every level on its track ---
	for id in m.CATALOG.keys():
		var probe := (load(m.CATALOG[id]) as CardData).duplicate() as CardData
		var cap: int = probe.level_cap()
		if cap < 1:
			fails += 1; print("FAIL %s has no level track at all" % id); continue
		for L in range(2, cap + 1):
			var why := _step(probe, L)
			levels_checked += 1
			if why != "":
				fails += 1; print("FAIL card %s: %s" % [id, why]); break

	# --- and every power, which is a card the player always holds ---
	for pid in Balance.POWERS:
		var raw = Balance.power(pid)
		if raw == null:
			fails += 1
			print("FAIL power '%s' is in Balance.POWERS but resources/powers/%s.tres does not exist" % [
				pid, pid])
			continue
		var p := raw.duplicate() as PowerData
		var pcap: int = p.level_capped()
		if pcap < 2:
			# legal, but it must then be UNSELLABLE rather than a track of one
			print("  (info: %s has a single level — nothing to sell)" % pid)
		for L in range(2, pcap + 1):
			var why2 := _step(p, L)
			levels_checked += 1
			if why2 != "":
				fails += 1; print("FAIL power %s: %s" % [pid, why2]); break

	# --- a track must never outlive what the card has to give ---
	#
	# The inverse failure of the one above, and the one that produced Foresight's ten
	# identical levels: a cap authored by hand rather than derived from the card.
	for id2 in m.CATALOG.keys():
		var c2 := (load(m.CATALOG[id2]) as CardData).duplicate() as CardData
		if c2.level_cap() > Balance.max_level(c2.rarity):
			fails += 1
			print("FAIL %s sells %d levels, past its rarity's %d" % [
				id2, c2.level_cap(), Balance.max_level(c2.rarity)])

	# --- the preview must name the gain, including the ones that go DOWN ---
	#
	# `level_up_text` is what the Collection quotes next to the price. A Set Stone
	# level buys an energy discount and nothing else, so a preview that only knows
	# how to say "dmg 9->10" reports an empty string and the player is asked to pay
	# for a blank.
	for id3 in m.CATALOG.keys():
		var c3 := (load(m.CATALOG[id3]) as CardData).duplicate() as CardData
		if c3.level_cap() < 2:
			continue
		c3.level = 1
		if c3.level_up_text(2).strip_edges() == "":
			fails += 1
			print("FAIL %s sells a level its preview cannot describe" % id3)

	# --- the progress bands land on the track, at every track length -----------
	#
	# `PixelArt.level_band` picks which of the three overlays a card or power wears.
	# It is thresholded on INTEGER levels derived from the cap rather than on a float
	# against thirds, and this is the test for why: at cap 100, level 34 gives
	# (34-1)/(100-1) = 0.3333, which misses a 0.334 threshold, so a Common sitting
	# exactly a third of the way up its track wore nothing (D132).
	#
	# Every real cap is exercised rather than a sample: card caps come from
	# `Balance.max_level` over the five rarities, power caps off the powers themselves,
	# so a retuned cap is checked here by itself.
	var caps := {}
	for r in 5:
		caps[Balance.max_level(r)] = true
	for pid2 in Balance.POWERS:
		var pw := Balance.power(pid2)
		if pw != null:
			caps[pw.level_capped()] = true
	for cap in caps:
		var c: int = int(cap)
		# base level is never decorated: an effect you have before you have earned
		# anything is not a progress effect
		if PixelArt.level_band(1, c) != "":
			fails += 1
			print("FAIL a cap-%d track is already decorated at level 1" % c)
		# the cap always reads maxed, and only the cap does
		if PixelArt.level_band(c, c) != "max":
			fails += 1
			print("FAIL a cap-%d track does not read maxed at its own cap" % c)
		if c > 2 and PixelArt.level_band(c - 1, c) == "max":
			fails += 1
			print("FAIL a cap-%d track reads maxed one short of its cap" % c)
		# bands never go backwards as the level climbs
		var order := {"": 0, "1": 1, "2": 2, "max": 3}
		var prev := 0
		for lv in range(1, c + 1):
			var rank: int = int(order[PixelArt.level_band(lv, c)])
			if rank < prev:
				fails += 1
				print("FAIL a cap-%d track goes backwards a band at level %d" % [c, lv])
				break
			prev = rank
		# a track long enough to have middles must actually show them
		if c >= 5:
			var seen := {}
			for lv2 in range(1, c + 1):
				seen[PixelArt.level_band(lv2, c)] = true
			for want in ["1", "2"]:
				if not seen.has(want):
					fails += 1
					print("FAIL a cap-%d track never shows band '%s'" % [c, want])

	if fails == 0:
		print("LEVELS TEST: PASS (%d level-ups across every card and power, none empty)" % levels_checked)
	else:
		print("LEVELS TEST: FAIL (%d)" % fails)
	quit()
