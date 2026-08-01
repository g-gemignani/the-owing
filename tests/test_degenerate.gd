## Headless test: the game must not contain a turn that never ends.
##
## A player reported a combat that hung: a short deck, several draw-2 cards, and
## enough zero-cost attacks (Nick, Jab) to keep swinging. It is not a UI bug and it
## is not specific to those cards — it is a property of three rules meeting:
##
##   1. `play_card()` subtracts `eff_cost()`, so a zero-cost card costs nothing;
##   2. a played card goes to the DISCARD pile, not out of the fight;
##   3. `draw_cards()` reshuffles the discard back into the draw pile the moment
##      the draw pile empties — mid-turn, with no limit on how often.
##
## So a zero-cost card that draws comes back around and can be played again, for
## free, forever. Nothing about the loop is random: it is closed. The zero-cost
## attacks are not the cause, they are what turns an endless turn into endless
## damage. `tools/sim_balance.gd` hangs outright on such a deck, because its
## "play everything that draws" policy is exactly this loop written down.
##
## Two things are checked, and they fail in different ways on purpose:
##   * the RULE, which is cheap and catches the next card before it ships;
##   * the actual FIGHT, fuzzed, which catches a loop the rule did not predict —
##     a relic, a power or a combo that hands back more than it takes.
##
## Every loop in here is bounded. A test that hunts for infinite loops must not be
## able to become one.
## Run: godot --headless --script tests/test_degenerate.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_degenerate_"

const CARD_DIR := "res://resources/cards/"
## A real turn plays a handful of cards. Anything approaching this is not a turn
## the rules produced, so the fight is treated as hung rather than merely long.
const PLAY_BUDGET := 400
const FUZZ_SEED := 20260801
const FUZZ_DECKS := 2000

func _init() -> void:
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	var fails := 0

	fails += _draw_cards_must_be_bounded()
	fails += _the_reported_deck()
	fails += _fuzz_short_zero_cost_decks()
	fails += _drawing_an_empty_deck_terminates()
	fails += _the_simulator_guards_its_play_loops()

	if fails == 0:
		print("DEGENERATE TEST: PASS (no deck, hand or tool loop runs without end)")
	else:
		print("DEGENERATE TEST: FAIL (%d)" % fails)
	quit()


## --- the rule ----------------------------------------------------------------
##
## Two things let a card be replayed: DRAW puts it back in your hand, and ENERGY
## pays for it. A card that hands back either one, and can return through the
## discard, is a cycle. Only two things break a cycle:
##
##   * an energy cost  — MAX_ENERGY caps how many you play per turn;
##   * `exhaust`       — the card leaves the fight, so it cannot come back around.
##
## An HP cost is deliberately NOT on that list, and the fuzzer below is why. It was
## on it in the first draft, which let Abyssal Gift through: "Pay 8 HP. Gain 1
## Energy. Draw 2." looks self-limiting and is not, because HP is RENEWABLE —
## Deep Breath heals 8 for the 1 energy Abyssal Gift just produced, and the pair
## runs forever while drawing three cards a lap. A bound has to be a resource the
## fight cannot hand back.
##
## Stated as a rule rather than a list of cards because the next Draw 2 will not
## be on the list.
func _draw_cards_must_be_bounded() -> int:
	var fails := 0
	var m = load("res://scripts/meta_state.gd").new()
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		if c == null or c.exhaust or c.eff_cost() > 0:
			continue
		if c.eff_draw() > 0:
			fails += 1
			print("FAIL %s draws %d for 0 energy and does not exhaust —" % [id, c.eff_draw()])
			print("     it returns via the discard and can be replayed for free forever")
		if c.energy_gain > 0:
			fails += 1
			print("FAIL %s returns %d energy for 0 energy and does not exhaust —" % [
				id, c.energy_gain])
			print("     it pays for its own replay; an HP cost does not bound it, healing exists")
	return fails


## --- the fight the player actually reported ----------------------------------
##
## Built to the report: a SHORT deck (so the discard reshuffles quickly), the
## draw-2s, and the zero-cost attacks. The enemy is given enough HP that it cannot
## end the fight by dying, because a loop that is only broken by killing something
## is still a loop — a tankier enemy or a missed target restores it.
func _the_reported_deck() -> int:
	var deck := _cards({"read_ahead": 3, "see_it_coming": 1, "focus": 2, "nick": 2, "jab": 2})
	var played := _greedy_turn(deck)
	if played >= PLAY_BUDGET:
		print("FAIL the reported deck never ends a turn: %d cards played and still going" % played)
		print("     (3x Read Ahead, See It Coming, 2x Focus, 2x Nick, 2x Jab)")
		return 1
	return 0


## --- the same shape, fuzzed --------------------------------------------------
##
## The reported deck is one point. The loop is a property of the POOL, so the pool
## is what gets searched: short decks assembled at random out of every zero-cost
## card and every card that draws. Seeded, so a failure is reproducible and prints
## the deck that caused it rather than "a deck".
func _fuzz_short_zero_cost_decks() -> int:
	seed(FUZZ_SEED)
	var m = load("res://scripts/meta_state.gd").new()
	var pool: Array[String] = []
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		if c != null and (c.eff_cost() == 0 or c.eff_draw() > 0):
			pool.append(id)
	if pool.size() < 4:
		print("FAIL the fuzz pool is empty — this test would pass by doing nothing")
		return 1

	for trial in FUZZ_DECKS:
		var loadout := {}
		# short on purpose: the shorter the deck, the sooner the discard comes back
		for i in 4 + (trial % 5):
			var id: String = pool[randi() % pool.size()]
			loadout[id] = int(loadout.get(id, 0)) + 1
		var played := _greedy_turn(_cards(loadout))
		if played >= PLAY_BUDGET:
			print("FAIL deck loops forever (%d cards played in one turn): %s" % [
				played, JSON.stringify(loadout)])
			return 1
	return 0


## --- the engine's own floor --------------------------------------------------
##
## `draw_cards()` reshuffles when the draw pile is empty. With BOTH piles empty
## there is nothing to reshuffle, and the obvious shape of that code ("keep trying
## until you have drawn n") spins. It must simply stop.
func _drawing_an_empty_deck_terminates() -> int:
	var eng = load("res://scripts/combat_engine.gd").new()
	eng.setup(_cards({"hack": 1}), 50, 50, 1, Balance.Tier.NORMAL, "cultist")
	eng.hand.clear()
	eng.draw_pile.clear()
	eng.discard_pile.clear()
	eng.draw_cards(10)          # must return, not spin
	if not eng.hand.is_empty():
		print("FAIL drawing from two empty piles produced %d cards" % eng.hand.size())
		return 1
	return 0


## --- and the tools must not be the thing that hangs --------------------------
##
## `sim_balance.gd` is run by hand before every tuning commit, so a hang there
## costs a person rather than CI. Every other loop in that file carries a guard;
## the play-policy loops did not, and a deck of free draw pinned them. Asserted on
## the source because the alternative is running the simulator, which is 420s.
func _the_simulator_guards_its_play_loops() -> int:
	var f := FileAccess.open("res://tools/sim_balance.gd", FileAccess.READ)
	if f == null:
		print("FAIL tools/sim_balance.gd is missing")
		return 1
	var src := f.get_as_text()
	f.close()
	var fails := 0
	for line in src.split("\n"):
		var t := line.strip_edges()
		if not t.begins_with("while "):
			continue
		# a guard is any bound that does not depend on the fight ending
		if t.find("guard") == -1 and t.find("steps") == -1 and t.find("< ") == -1:
			fails += 1
			print("FAIL sim_balance.gd has an unguarded loop: %s" % t)
	return fails


## --- helpers -----------------------------------------------------------------

func _cards(loadout: Dictionary) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in loadout:
		for i in int(loadout[id]):
			deck.append((load(CARD_DIR + id + ".tres") as CardData).duplicate())
	return deck

## Play greedily for ONE turn and return how many cards went down. This is the
## adversary: it mirrors the simulator's policy (take everything you can afford,
## draw first) because that policy is what a loop exploits. Returns PLAY_BUDGET if
## it never ran out of things to play, which is the failure the callers test for.
func _greedy_turn(deck: Array[CardData]) -> int:
	var eng = load("res://scripts/combat_engine.gd").new()
	eng.setup(deck, 500, 500, 1, Balance.Tier.NORMAL, "cultist")
	# the fight must not be endable by winning it: a loop that only stops because
	# the enemy died is still a loop against a tougher enemy
	for e in eng.enemies:
		e.hp = 1 << 24
		e.max_hp = 1 << 24
	eng.start_turn()
	var played := 0
	while played < PLAY_BUDGET:
		var chosen: CardData = null
		for c in eng.hand:
			if not eng.can_play(c):
				continue
			# draw first, exactly as the simulator does
			if c.eff_draw() > 0:
				chosen = c
				break
			if chosen == null:
				chosen = c
		if chosen == null:
			break
		eng.play_card(chosen)
		played += 1
	return played
