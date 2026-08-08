## Headless test: the card mechanics added with the big card batch.
## Every mechanic must (a) do what it says and (b) be priced in power_value, or
## enemy scaling silently falls behind the player's options (the D5/D11 lesson).
## Run: godot --headless --script tests/test_mechanics.gd
extends SceneTree

const DIR := "res://resources/cards/"

func _init() -> void:
	var fails := 0
	var deck := _deck({"hack": 8})

	# --- multi-hit deals damage per hit ---
	var e := _fight(deck)
	var tw := _card("two_quick")
	var hp0: int = e.enemies[0].hp
	e.energy = 3
	e.hand.append(tw)
	e.play_card(tw)
	var dealt: int = hp0 - e.enemies[0].hp
	if dealt < tw.eff_damage() * 2:
		fails += 1; print("FAIL twin_strike dealt %d, expected >= %d" % [dealt, tw.eff_damage() * 2])

	# --- AoE hits every living enemy ---
	var e2 := _fight(deck, "rat_swarm")
	if e2.enemies.size() < 2:
		print("  (info: rat_swarm spawned 1, AoE check limited)")
	var before: Array = []
	for en in e2.enemies:
		before.append(en.hp)
	var cl := _card("reap")
	e2.energy = 3
	e2.hand.append(cl)
	e2.play_card(cl)
	for i in e2.enemies.size():
		if e2.enemies[i].hp >= int(before[i]):
			fails += 1; print("FAIL cleave did not hit enemy %d" % i); break

	# --- exhaust removes the card from the combat ---
	# Bandage rather than a card that merely happens to exhaust today: this asserts
	# the ENGINE rule, and it was pointed at Keep Hitting, which stopped exhausting
	# the moment that card was given an identity of its own.
	var e3 := _fight(deck)
	var ex := _card("bandage")
	e3.energy = 3
	e3.hand.append(ex)
	var discard_before: int = e3.discard_pile.size()
	e3.play_card(ex)
	if e3.discard_pile.size() != discard_before:
		fails += 1; print("FAIL exhausted card went to the discard pile")

	# --- retain keeps a card through end of turn ---
	var e4 := _fight(deck)
	var keep := _card("give_ground")
	e4.hand.append(keep)
	e4.end_turn()
	var still_held := false
	for c in e4.hand:
		if c.id == "give_ground":
			still_held = true
	if not still_held:
		fails += 1; print("FAIL retain card was discarded at end of turn")

	# --- the hand cap refuses a draw, and the refused card stays in the pile (D120) ---
	#
	# Next to retain deliberately: a retained card is still in your hand when the next
	# turn deals, so retain is one of the two ways a hand reaches the cap on its own.
	#
	# The half a careless implementation gets wrong is not the hand, it is the PILE.
	# Discarding the card that was not drawn would cycle the deck for free — a gift to
	# exactly the free-draw decks `test_degenerate.gd` exists to bound — so the draw
	# pile and the discard pile are both counted here, not only the hand size.
	var ecap := _fight(_deck({"hack": 20}))
	ecap.draw_cards(Balance.MAX_HAND_SIZE - ecap.hand.size() - 1)
	if ecap.hand.size() != Balance.MAX_HAND_SIZE - 1:
		fails += 1; print("FAIL wanted a hand of %d to sit one under the cap, dealt %d" % [
			Balance.MAX_HAND_SIZE - 1, ecap.hand.size()])
	if ecap.take_draw_notice() != "":
		fails += 1; print("FAIL a hand one card under the cap already reports a lost draw")
	# The cap is a maximum, not a limit one short of it: the card that fills the hand
	# to exactly ten must be drawn. This is the off-by-one an implementation written
	# with `>` instead of `>=` gets backwards, and it lands as an eleven-card hand.
	ecap.draw_cards(1)
	if ecap.hand.size() != Balance.MAX_HAND_SIZE:
		fails += 1; print("FAIL the cap refused the card that fills a hand to exactly %d" % Balance.MAX_HAND_SIZE)
	if ecap.take_draw_notice() != "":
		fails += 1; print("FAIL filling a hand to exactly the cap reported a lost draw")

	var pile_before: int = ecap.draw_pile.size()
	var discard_before2: int = ecap.discard_pile.size()
	# `draw_cards` pops the BACK, so this is the card the next draw would have taken.
	var refused: CardData = ecap.draw_pile[pile_before - 1]
	ecap.draw_cards(3)
	if ecap.hand.size() != Balance.MAX_HAND_SIZE:
		fails += 1; print("FAIL drawing into a full hand added cards (%d held)" % ecap.hand.size())
	if ecap.draw_pile.size() != pile_before or ecap.draw_pile[pile_before - 1] != refused:
		fails += 1
		print("FAIL the refused draw did not stay on the pile: %d -> %d cards" % [
			pile_before, ecap.draw_pile.size()])
	if ecap.discard_pile.size() != discard_before2:
		fails += 1
		print("FAIL a lost draw went to the discard — that cycles the deck for free")
	var notice: String = ecap.take_draw_notice()
	if notice.to_lower().find("hand full") == -1 or notice.find("3 draws") == -1:
		fails += 1; print("FAIL three lost draws report '%s'" % notice)
	# ...and it has to reach the log by the path the screen actually reads:
	# `Combat._on_card_pressed` logs whatever `play_card` returns, and nothing else.
	# A notice the engine holds and no caller collects is a silent nerf again.
	var sic := _card("see_it_coming")
	ecap.hand.remove_at(ecap.hand.size() - 1)
	ecap.hand.append(sic)            # a full hand, one card of which draws
	ecap.energy = 3
	var played: String = ecap.play_card(sic)
	if played.to_lower().find("hand full") == -1:
		fails += 1
		print("FAIL playing %s into a full hand logged '%s'" % [sic.name, played])

	# --- poison ignores block and ticks at end of turn ---
	var e5 := _fight(deck)
	var vf := _card("venom_fang")
	e5.energy = 3
	e5.hand.append(vf)
	e5.play_card(vf)
	if e5.enemies[0].poison <= 0:
		fails += 1; print("FAIL poison not applied")
	e5.enemies[0].block = 999          # poison must bypass block entirely
	var php: int = e5.enemies[0].hp
	var tick: int = e5.enemies[0].end_turn()
	if tick <= 0 or e5.enemies[0].hp >= php:
		fails += 1; print("FAIL poison did not damage through block")

	# --- thorns retaliate against attackers ---
	var e6 := _fight(deck)
	e6.player.thorns = 5
	e6.intents[0] = {"action": EnemyData.Action.ATTACK, "value": 5}
	var ehp: int = e6.enemies[0].hp
	e6.end_turn()
	if e6.enemies[0].hp >= ehp:
		fails += 1; print("FAIL thorns did not damage the attacker")

	# --- body slam scales off current block ---
	var e7 := _fight(deck)
	e7.player.block = 17
	var bs := _card("ram")
	e7.energy = 3
	e7.hand.append(bs)
	var t0: int = e7.enemies[0].hp
	e7.play_card(bs)
	if t0 - e7.enemies[0].hp < 17:
		fails += 1; print("FAIL body_slam ignored Block (%d dealt)" % (t0 - e7.enemies[0].hp))

	# --- grows accumulates within a combat and resets between combats ---
	var g := _card("drilled")
	var e8 := _fight([g])
	e8.energy = 9
	if not (g in e8.hand):
		e8.hand.append(g)
	var first: int = g.hit_damage()
	e8.play_card(g)
	if g.hit_damage() <= first:
		fails += 1; print("FAIL grows did not increase damage")
	var e9 := CombatEngine.new()
	e9.setup([g], 60, 60, 1, Balance.Tier.NORMAL, "cultist")
	if g.growth != 0:
		fails += 1; print("FAIL growth carried into a new combat")

	# --- heal and energy gain ---
	var e10 := _fight(deck)
	e10.player.hp = 20
	var sw := _card("stitch")
	e10.energy = 3
	e10.hand.append(sw)
	e10.play_card(sw)
	if e10.player.hp <= 20:
		fails += 1; print("FAIL heal did nothing")
	var ad := _card("kick")
	var en_before: int = e10.energy
	e10.hand.append(ad)
	e10.play_card(ad)
	if e10.energy <= en_before:
		fails += 1; print("FAIL energy_gain did not add energy")

	# --- every card must be priced, or enemy scaling falls behind ---
	var m = load("res://scripts/meta_state.gd").new()
	for id in m.CATALOG:
		var c := _card(id)
		if c.power_value() <= 0.0:
			fails += 1; print("FAIL %s has no power_value" % id)
		if c.cost < 0:
			fails += 1; print("FAIL %s has negative cost" % id)
		if c.description.strip_edges() == "" or c.name.strip_edges() == "":
			fails += 1; print("FAIL %s missing name/description" % id)
	# mechanics must actually raise the price they are worth
	if _card("two_quick").power_value() <= _card("nick").power_value():
		fails += 1; print("FAIL multi-hit not priced above a single small hit")
	if _card("reap").power_value() <= _card("execute").power_value() * 0.5:
		fails += 1; print("FAIL AoE priced too low")
	# exhaust is a real cost, so an exhausting card must price BELOW its raw damage
	var fin := _card("decapitate")
	if fin.power_value() >= float(fin.eff_damage()):
		fails += 1; print("FAIL exhaust discount not applied: %.1f vs %d dmg" % [
			fin.power_value(), fin.eff_damage()])

	# --- cards that read the fight (D66) ------------------------------------------
	#
	# Every one of these has to (a) actually change the number and (b) be priced, or
	# enemy scaling falls behind the deck built around it. Both are asserted, because
	# the second failure is invisible: the card works, the build just quietly stops
	# keeping up with the dungeons it unlocked.
	var cond := _deck({"hack": 8})

	# poison: the same card is worth more into a poisoned target
	var ep := _fight(cond)
	var rup := _card("split")
	var plain: int = ep.card_damage(rup)
	ep.enemies[0].poison = 6
	var poisoned: int = ep.card_damage(rup)
	if poisoned <= plain:
		fails += 1; print("FAIL rupture ignores Poison: %d vs %d" % [plain, poisoned])

	# thorns: scales with what you are wearing, not with the target
	var et := _fight(cond)
	var rip := _card("riposte")
	var bare: int = et.card_damage(rip)
	et.player.thorns = 8
	if et.card_damage(rip) <= bare:
		fails += 1; print("FAIL riposte ignores Thorns")

	# debuffs: the follow-up hits harder
	var ed := _fight(cond)
	var iw := _card("shoulder")
	var clean: int = ed.card_damage(iw)
	ed.enemies[0].vulnerable = 2
	if ed.card_damage(iw) <= clean:
		fails += 1; print("FAIL iron_wave ignores a Vulnerable target")

	# tempo: worth more late in the turn than early
	var ec := _fight(cond)
	var shiv := _card("nick")
	var early: int = ec.card_damage(shiv)
	ec.cards_played_this_turn = 4
	if ec.card_damage(shiv) <= early:
		fails += 1; print("FAIL shiv is worth the same as the first card of a turn")

	# swarm: a kill pays an energy back
	#
	# Sword Dance rather than Cull, which carried this mechanic until D204 turned it
	# into the exhaust build's enabler. Any energy_on_kill card proves the ENGINE rule;
	# pointing at one that has since been given a different identity is how a green
	# suite ends up asserting nothing, which is the note on `bandage` above.
	var ek := _fight(cond)
	ek.enemies[0].max_hp = 6
	ek.enemies[0].hp = 6
	var swarm := _card("sword_dance")
	ek.energy = 3
	ek.hand.append(swarm)
	var e_before: int = ek.energy
	ek.play_card(swarm)
	if not ek.enemies[0].is_dead():
		print("  (info: sword_dance did not kill a 6hp enemy, skipping the refund check)")
	elif ek.energy != e_before - swarm.cost + 1:
		fails += 1
		print("FAIL sword_dance killed and did not refund energy: %d -> %d (cost %d)" % [
			e_before, ek.energy, swarm.cost])
	# ...and NOT when nothing dies
	var ek2 := _fight(cond)
	var swarm2 := _card("sword_dance")
	ek2.energy = 3
	ek2.hand.append(swarm2)
	ek2.play_card(swarm2)
	if ek2.energy != 3 - swarm2.cost:
		fails += 1; print("FAIL sword_dance refunded energy without a kill")

	# fortress: a fuller hand is a bigger shield
	var eh := _fight(cond)
	var gd := _card("guard")
	eh.hand = [gd]
	var alone: int = eh.card_block(gd)
	for i in 4:
		eh.hand.append(_card("hack"))
	if eh.card_block(gd) <= alone:
		fails += 1; print("FAIL guard ignores the cards in your hand")

	# --- cards that read the OTHER CARDS (D204) -----------------------------------
	#
	# Same two obligations as the D66 block above — move the number, and be priced —
	# plus a third that only this batch has: the face and the resolution must agree.
	# Every one of these mechanics is a count of something the player can see, so a
	# card that shows one number and delivers another is not a rounding error, it is
	# the mechanic failing at the only job it has.

	# enabler: the swing AFTER the empowering one is the one that gets it
	var eN := _fight(cond)
	var edge := _card("whetted_edge")
	var follow := _card("gash")
	var solo: int = eN.card_damage(follow)
	eN.energy = 3
	eN.hand.append(edge)
	eN.hand.append(follow)
	var edge_face: int = eN.card_damage(edge)
	eN.play_card(edge)
	if eN.next_attack_bonus != edge.empower_next:
		fails += 1; print("FAIL whetted_edge did not arm the next attack: %d" % eN.next_attack_bonus)
	if eN.card_damage(follow) != solo + edge.empower_next:
		fails += 1; print("FAIL the empowered follow-up did not get the bonus: %d vs %d" % [
			eN.card_damage(follow), solo + edge.empower_next])
	if edge_face != eN.player.outgoing_damage(edge.eff_damage()):
		fails += 1; print("FAIL whetted_edge empowered ITSELF — %d" % edge_face)
	eN.play_card(follow)
	if eN.next_attack_bonus != 0:
		fails += 1; print("FAIL the empower bonus was not spent by the attack that used it")

	# enabler: a discount is real money at the place affordability is checked
	var eD := _fight(cond)
	var prep := _card("read_ahead")
	var dear := _card("brace")
	eD.energy = 1
	eD.hand.append(prep)
	eD.hand.append(dear)
	if eD.can_play(dear):
		fails += 1; print("FAIL a 2-cost card was affordable on 1 energy before the discount")
	eD.play_card(prep)
	if eD.play_cost(dear) != dear.eff_cost() - prep.discount_next:
		fails += 1; print("FAIL the discount did not reach play_cost: %d" % eD.play_cost(dear))
	if not eD.can_play(dear):
		fails += 1; print("FAIL the discount did not make the card affordable")
	var pool: int = eD.energy
	eD.play_card(dear)
	if eD.energy != pool - (dear.eff_cost() - prep.discount_next):
		fails += 1; print("FAIL the discount was quoted but not charged: pool %d -> %d" % [
			pool, eD.energy])
	if eD.next_card_discount != 0:
		fails += 1; print("FAIL the discount survived the card that spent it")

	# payoff: the fourth card of a turn is worth more than the first, and the FACE says so
	var eP := _fight(cond)
	var grind := _card("grinding_down")
	eP.hand.append(grind)
	var turn_open: int = eP.card_damage(grind)
	eP.cards_played_this_turn = 3
	var fourth: int = eP.card_damage(grind)
	if fourth != turn_open + grind.per_card_played * 3:
		fails += 1; print("FAIL grinding_down does not read the turn: %d then %d" % [turn_open, fourth])
	# ...and the block half of the same axis, on a card that pays in Block
	var eB := _fight(cond)
	var rly := _card("rally")
	eB.hand.append(rly)
	var b_first: int = eB.card_block(rly)
	eB.cards_played_this_turn = 2
	if eB.card_block(rly) != b_first + rly.per_card_played * 2:
		fails += 1; print("FAIL rally does not read the turn")
	# a skill must not acquire a damage roll from a shared axis (see card_base_damage)
	if eB.card_base_damage(rly) != 0:
		fails += 1; print("FAIL rally deals %d damage it does not have" % eB.card_base_damage(rly))

	# payoff: scales with the STACK, where bonus_vs_debuffed only sees the flag
	var eV := _fight(cond)
	var press := _card("pressure")
	var undebuffed: int = eV.card_damage(press)
	eV.enemies[0].vulnerable = 2
	eV.enemies[0].weak = 1
	if eV.card_damage(press) != undebuffed + press.damage_per_debuff * 3:
		fails += 1; print("FAIL pressure does not count the stacks")

	# payoff: the exhaust tally, and the projection that keeps Cull's face honest
	var eX := _fight(cond)
	var burn := _card("cull")
	eX.hand = [burn, _card("hack"), _card("hack"), _card("hack")]
	var promised: int = eX.card_block(burn)
	if promised <= eX.player.outgoing_block(burn.eff_block()):
		fails += 1; print("FAIL cull's face does not count the hand it is about to burn")
	eX.energy = 3
	eX.play_card(burn)
	if eX.exhausted_this_combat != 3:
		fails += 1; print("FAIL cull burned %d cards, expected 3" % eX.exhausted_this_combat)
	if not eX.hand.is_empty():
		fails += 1; print("FAIL cull left %d cards in hand" % eX.hand.size())
	if eX.player.block != promised:
		fails += 1; print("FAIL cull promised %d Block and delivered %d" % [
			promised, eX.player.block])
	# ...and a later payoff collects the same tally
	var drain := _card("lifedrain")
	eX.hand.append(drain)
	if eX.card_damage(drain) <= eX.player.outgoing_damage(drain.eff_damage()):
		fails += 1; print("FAIL lifedrain ignores the cards already exhausted")

	# payoff: X-cost spends the pool, and quotes what it is about to spend
	var eE := _fight(cond)
	var xc := _card("stave_in")
	eE.energy = 3
	eE.hand.append(xc)
	var quoted: int = eE.card_damage(xc)
	if quoted != eE.player.outgoing_damage(xc.eff_damage() + xc.damage_per_energy * 2):
		fails += 1; print("FAIL stave_in quoted %d, which is not 3 energy less its cost" % quoted)
	var xhp: int = eE.enemies[0].hp
	eE.play_card(xc)
	if eE.energy != 0:
		fails += 1; print("FAIL stave_in left %d energy unspent" % eE.energy)
	if xhp - eE.enemies[0].hp != quoted:
		fails += 1; print("FAIL stave_in quoted %d and dealt %d" % [quoted, xhp - eE.enemies[0].hp])

	# payoff: the last card in your hand
	var eH := _fight(cond)
	var lastw := _card("last_word")
	eH.hand = [lastw, _card("hack")]
	var held: int = eH.card_damage(lastw)
	eH.hand = [lastw]
	if eH.card_damage(lastw) != held + lastw.bonus_if_hand_empty:
		fails += 1; print("FAIL last_word does not know it is the last card")

	# payoff: thorns already worn, converted to Block
	var eT := _fight(cond)
	var bram := _card("bramble_armour")
	eT.hand.append(bram)
	var bare_blk: int = eT.card_block(bram)
	eT.player.thorns = 6
	if eT.card_block(bram) <= bare_blk:
		fails += 1; print("FAIL bramble_armour ignores the Thorns it is wearing")

	# payoff: the echo resolves the previous card, and cannot chain
	var eR := _fight(cond)
	var setup := _card("gash")
	var echo := _card("dead_weight")
	eR.energy = 3
	eR.hand = [setup, echo]
	eR.play_card(setup)
	var mid: int = eR.enemies[0].hp
	eR.energy = 3
	eR.play_card(echo)
	var swung: int = mid - eR.enemies[0].hp
	var expect: int = eR.player.outgoing_damage(echo.eff_damage()) \
		+ eR.player.outgoing_damage(setup.eff_damage())
	if swung != expect:
		fails += 1; print("FAIL dead_weight dealt %d, expected its own hit plus the echo (%d)" % [
			swung, expect])
	# an echo with nothing behind it is the card alone, not a crash
	var eR2 := _fight(cond)
	var lone := _card("dead_weight")
	eR2.energy = 3
	eR2.hand = [lone]
	if eR2.play_card(lone) == "":
		fails += 1; print("FAIL dead_weight was unplayable as the first card of a turn")

	# the per-turn carriers expire with the turn, like Block
	var eW := _fight(cond)
	eW.next_attack_bonus = 9
	eW.next_card_discount = 2
	eW.previous_card = _card("hack")
	eW.end_turn()
	if eW.next_attack_bonus != 0 or eW.next_card_discount != 0 or eW.previous_card != null:
		fails += 1; print("FAIL the combo carriers survived the turn they belonged to")

	# An `exhaust_hand` card must not also draw: `play_card` burns the hand AFTER
	# `_resolve`, so the cards it drew would go straight into the fire. Asserted rather
	# than commented, because the card that breaks it reads perfectly well on paper.
	for id in load("res://scripts/meta_state.gd").new().CATALOG:
		var c := _card(id)
		if c.exhaust_hand and c.eff_draw() > 0:
			fails += 1
			print("FAIL %s both burns the hand and draws — the draw is burned with it" % id)

	# ...and every one of them must cost the deck something in priced power
	for pair in [["split", "damage_per_poison"], ["riposte", "damage_per_thorns"],
			["shoulder", "bonus_vs_debuffed"], ["nick", "combo_bonus"],
			["sword_dance", "energy_on_kill"], ["guard", "block_per_card_in_hand"],
			["whetted_edge", "empower_next"], ["read_ahead", "discount_next"],
			["grinding_down", "per_card_played"], ["rally", "per_card_played"],
			["pressure", "damage_per_debuff"], ["red_mind", "per_exhausted"],
			["stave_in", "damage_per_energy"], ["last_word", "bonus_if_hand_empty"],
			["bramble_armour", "block_per_thorns"], ["plague_bearer", "repeat_previous"]]:
		var real := _card(String(pair[0]))
		var stripped := _card(String(pair[0]))
		stripped.set(String(pair[1]), false if typeof(real.get(String(pair[1]))) == TYPE_BOOL else 0)
		if real.power_value() <= stripped.power_value():
			fails += 1
			print("FAIL %s is not priced for %s — enemy scaling will fall behind it" % [
				pair[0], pair[1]])

	# LAST, and that is a fix rather than a style. The summary and the `quit()` used to
	# sit two thirds of the way up this function, above the D66 block — and `quit()` in a
	# SceneTree only REQUESTS a quit, so everything below it ran, printed its FAIL lines
	# into a report that had already declared PASS, and was counted by nobody. Every
	# check has to be above the line that reports the count.
	if fails == 0:
		print("MECHANICS TEST: PASS (multi-hit, AoE, exhaust, retain, hand cap, poison, "
			+ "thorns, block-scaling, grows, heal, energy, and the D204 combo axes)")
	else:
		print("MECHANICS TEST: FAIL (%d)" % fails)
	quit()

func _card(id: String) -> CardData:
	return (load(DIR + id + ".tres") as CardData).duplicate()

func _deck(loadout: Dictionary) -> Array[CardData]:
	var d: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			d.append(_card(id))
	return d

func _fight(deck, archetype: String = "cultist") -> CombatEngine:
	var typed: Array[CardData] = []
	for c in deck:
		typed.append(c)
	var e := CombatEngine.new()
	e.setup(typed, 60, 60, 1, Balance.Tier.NORMAL, archetype)
	e.enemies[0].max_hp = 500
	e.enemies[0].hp = 500
	return e
