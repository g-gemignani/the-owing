## Pure combat state machine — no UI, no autoloads. Drives both the real
## Combat scene and the headless balance simulator, so tuning always reflects
## the shipped rules.
##
## Supports groups of enemies with per-enemy archetypes, telegraphed intents and
## player targeting. The encounter's HP/damage budget comes from Balance and is
## split across the group, so adding archetypes cannot silently change difficulty.
class_name CombatEngine
extends RefCounted

var player: Combatant
var enemies: Array[Combatant] = []
## Per enemy: {"action": EnemyData.Action, "value": int}
var intents: Array = []
## Archetype + per-enemy base damage, parallel to `enemies`.
var archetypes: Array = []
var base_damage: Array = []
var enemy_turns: Array = []

var target: int = 0
var energy: int = Balance.MAX_ENERGY

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

## Relics held this run (Array[RelicData]). Passed in rather than read from an
## autoload, so the engine stays pure and the simulator can model relic builds.
var relics: Array = []
## Dungeon-supplied enemy roster (D6). Empty = use the tier roster.
var roster_override: Array = []
## The dungeon's named boss archetype, fought at its BOSS node.
var named_boss: String = ""
var bonus_energy: int = 0

# --- power: one equipped ability, firable ONCE per turn (see PowerData) ---
var power: PowerData = null
var power_used: bool = false

# --- what conditional enemy rules read (see EnemyData.Trigger) ---
## Cards played during the turn just finished. Rules read the COMPLETED turn, not
## the one in progress, so an intent shown at the top of a turn cannot be falsified
## by what the player does during it.
var cards_played_this_turn: int = 0
var cards_played_last_turn: int = 0
## Block the player was holding when the enemies last acted — what a
## block-punishing enemy is reacting to.
var player_block_last_turn: int = 0
## Rule indices already spent, per enemy. A once-only rule (an enrage) must not
## re-trigger every turn after its condition stays true.
var rules_fired: Array = []

## Relic triggers already spent this fight, keyed "relicIndex:effectIndex".
## ON_HP_BELOW_PCT must fire once as you cross the line, not every turn after it.
var relic_fired: Dictionary = {}
## Last thing a relic trigger did, so the UI can report it on the next refresh.
var last_relic_text: String = ""
var extra_draw: int = 0
## Draws the D120 hand cap has eaten since the last time anything reported them.
## Not persisted in `save_state()`: it is a message in flight, and a fight resumed
## on a later session should not open by announcing a draw lost before lunch.
var draws_lost: int = 0

var dungeon: int = 1
var tier: int = Balance.Tier.NORMAL
var ratio: float = 1.0
var turn: int = 0

## Current target (compat accessor: most callers only care about who they hit).
var enemy: Combatant:
	get:
		return current_target()

## Total damage the player will take this turn if nothing changes
## (compat accessor: the old single-enemy field meant the same thing).
var enemy_intent: int:
	get:
		var total := 0
		for i in enemies.size():
			if enemies[i].is_dead():
				continue
			if int(intents[i]["action"]) == EnemyData.Action.ATTACK:
				total += enemies[i].outgoing_damage(int(intents[i]["value"]))
		return total

func setup(deck: Array[CardData], hp: int, max_hp: int, p_dungeon: int, p_tier: int,
		forced_archetype: String = "", p_relics: Array = [],
		p_roster: Array = [], p_power: PowerData = null, p_boss: String = "") -> void:
	dungeon = p_dungeon
	tier = p_tier
	relics = p_relics
	power = p_power
	# relics and the equipped power are throughput outside the deck, so they must
	# raise enemy scaling too — otherwise they are free strength
	ratio = Balance.power_ratio(deck, relics, power)

	player = Combatant.new()
	player.name = "Hero"
	player.max_hp = max_hp
	player.hp = hp

	# per-turn relic bonuses, and combat-start relic effects
	bonus_energy = 0
	extra_draw = 0
	for r in relics:
		bonus_energy += r.bonus_energy
		extra_draw += r.extra_draw
		player.strength += r.start_strength
		player.dexterity += r.start_dexterity

	roster_override = p_roster
	named_boss = p_boss
	_spawn_enemies(forced_archetype)

	draw_pile = []
	hand = []
	discard_pile = []
	for c in deck:
		c.growth = 0   # `grows` accumulates within one combat only
		draw_pile.append(c)
	draw_pile.shuffle()

	start_turn()

func _spawn_enemies(forced_archetype: String) -> void:
	enemies = []
	intents = []
	archetypes = []
	base_damage = []
	enemy_turns = []

	# a dungeon's own roster wins, so each place fights differently
	var roster: Array = roster_override if not roster_override.is_empty() else Balance.ROSTER[tier]
	# ...but its BOSS is named and fixed, never rolled. Drawing the finale from the
	# same pool as the trash meant seven of twelve dungeons ended on a trash mob
	# with 1.55x HP, and leaked the others' signatures into ordinary fights.
	var id: String = forced_archetype
	if id == "":
		if tier == Balance.Tier.BOSS and named_boss != "":
			id = named_boss
		else:
			var pool: Array = roster.filter(
				func(x): return not (x in Balance.ROSTER[Balance.Tier.BOSS]))
			if pool.is_empty():
				pool = roster
			id = pool[randi() % pool.size()]
	var arch := Balance.enemy(id)
	if arch == null:
		arch = EnemyData.new()

	var count: int = arch.spawn_count()
	var hp_budget := Balance.enemy_max_hp(dungeon, tier, ratio) * Balance.multi_hp_factor(count)
	var dmg_budget := float(Balance.enemy_damage(dungeon, tier, ratio, 1)) * Balance.multi_dmg_factor(count)

	for i in count:
		var c := Combatant.new()
		c.name = arch.name if count == 1 else "%s %d" % [arch.name, i + 1]
		c.max_hp = maxi(1, int(round(hp_budget * arch.hp_mult / count)))
		c.hp = c.max_hp
		enemies.append(c)
		archetypes.append(arch)
		# partially offset utility turns (see EnemyData.damage_compensation)
		var per := dmg_budget * arch.dmg_mult / float(count) * arch.damage_compensation()
		base_damage.append(maxi(1, int(round(per))))
		enemy_turns.append(0)
		intents.append({"action": EnemyData.Action.ATTACK, "value": 0})

	for i in enemies.size():
		_roll_intent(i)

## Recompute what enemy `i` intends to do next.
## Context a conditional rule reads. Built once per intent so every rule sees the
## same snapshot.
func _rule_ctx(i: int) -> Dictionary:
	return {
		"self_hp": enemies[i].hp, "self_max_hp": enemies[i].max_hp,
		"player_hp": player.hp, "player_max_hp": player.max_hp,
		"player_block_last_turn": player_block_last_turn,
		"cards_played_last_turn": cards_played_last_turn,
	}

func _roll_intent(i: int) -> void:
	var arch: EnemyData = archetypes[i]
	var t: int = int(enemy_turns[i]) + 1
	while rules_fired.size() <= i:
		rules_fired.append([])
	var action: int = arch.action_for_turn(t)
	var rule: int = arch.rule_for(t, _rule_ctx(i), rules_fired[i])
	var override := 0
	if rule >= 0:
		action = arch.rule_action[rule]
		override = arch._rule_field(arch.rule_value, rule, 0)
		if arch._rule_field(arch.rule_once, rule, 0) == 1:
			(rules_fired[i] as Array).append(rule)
	var value := 0
	match action:
		EnemyData.Action.ATTACK:
			# escalation applies to the telegraphed number, so the player can see
			# the fight getting more dangerous rather than being surprised by it
			var esc := minf(Balance.ESCALATION_MAX,
				1.0 + Balance.ESCALATION_PER_TURN * float(maxi(0, turn - 1)))
			value = maxi(1, int(round(float(base_damage[i]) * esc + float(randi() % 3))))
		EnemyData.Action.SUNDER, EnemyData.Action.DRAIN:
			var esc2 := minf(Balance.ESCALATION_MAX,
				1.0 + Balance.ESCALATION_PER_TURN * float(maxi(0, turn - 1)))
			var frac: float = Balance.SUNDER_DAMAGE_FRAC \
				if action == EnemyData.Action.SUNDER else 1.0
			value = maxi(1, int(round(float(base_damage[i]) * esc2 * frac)))
		EnemyData.Action.DEBUFF_VULN, EnemyData.Action.DEBUFF_WEAK:
			value = arch.debuff_stacks
		EnemyData.Action.DEFEND:
			value = arch.block_amount
		EnemyData.Action.EMPOWER, EnemyData.Action.ENRAGE:
			value = arch.strength_gain
	if override > 0:
		value = override
	intents[i] = {"action": action, "value": value}

func intent_text(i: int) -> String:
	if i < 0 or i >= intents.size():
		return ""
	var a: int = int(intents[i]["action"])
	var v: int = int(intents[i]["value"])
	match a:
		EnemyData.Action.ATTACK:
			# show what would actually land, after the enemy's Weak and the
			# player's Vulnerable/block — including the share Block cannot stop
			var raw := enemies[i].outgoing_damage(v)
			var pierce := int(round(float(raw) * Balance.pierce_fraction(dungeon, ratio)))
			var total := player.predicted_damage(maxi(0, raw - pierce)) + pierce
			if pierce > 0:
				return "hit %d (%d pierces Block)" % [total, pierce]
			return "hit %d" % total
		EnemyData.Action.DEBUFF_VULN:
			return "Vuln %d" % v
		EnemyData.Action.DEBUFF_WEAK:
			return "Weak %d" % v
		EnemyData.Action.DEFEND:
			return "block %d" % v
		EnemyData.Action.EMPOWER:
			return "empower %d" % v
		EnemyData.Action.SUNDER:
			# the whole point is that Block will not help, so say so
			return "SUNDER %d (ignores Block)" % enemies[i].outgoing_damage(v)
		EnemyData.Action.ENRAGE:
			return "ENRAGE +%d" % v
		EnemyData.Action.DRAIN:
			return "drain %d" % player.predicted_damage(enemies[i].outgoing_damage(v))
	return "?"

func current_target() -> Combatant:
	if enemies.is_empty():
		return null
	if target < 0 or target >= enemies.size() or enemies[target].is_dead():
		retarget()
	return enemies[target] if target < enemies.size() else null

## Pick the first living enemy (used after a kill).
func retarget() -> void:
	for i in enemies.size():
		if not enemies[i].is_dead():
			target = i
			return

func set_target(i: int) -> bool:
	if i < 0 or i >= enemies.size() or enemies[i].is_dead():
		return false
	target = i
	return true

func living_enemies() -> int:
	var n := 0
	for e in enemies:
		if not e.is_dead():
			n += 1
	return n

func start_turn() -> void:
	turn += 1
	# Block expires inside player.begin_turn() below, so capture it first: a relic
	# that pays out on wasted Block needs to know how much was wasted.
	var expiring: int = 0 if player.retain_block else player.block
	energy = Balance.MAX_ENERGY + bonus_energy
	power_used = false
	cards_played_this_turn = 0
	player.begin_turn()  # block expires here unless a retain_block power is active
	# start_block relics re-apply every turn's opening, after block expiry
	for r in relics:
		if r.start_block > 0:
			player.gain_block(player.outgoing_block(r.start_block))
	draw_cards(Balance.HAND_SIZE + extra_draw)
	retarget()
	var relic_msg := _fire_relics(RelicData.Trigger.ON_TURN_START)
	var expired_msg := _fire_relics(RelicData.Trigger.ON_BLOCK_EXPIRED, expiring)
	last_relic_text = " ".join([relic_msg, expired_msg]).strip_edges()

## The ONE way a card gets into a hand — start of turn, a card's `draw`, a triggered
## relic, a power. Everything routes here, which is why the D120 cap only has to be
## written once. There is no "create a card into your hand" effect in the game: no
## card, relic or power makes one, and `hand` is appended to nowhere else, so the
## companion rule (a card CREATED into a full hand goes to the discard) has no
## subject to apply to and is deliberately not written — an unreachable branch is a
## claim nothing can check.
func draw_cards(n: int) -> void:
	for i in n:
		# D120: a hand at the cap does not draw, and the card it did not draw stays
		# on top of the pile. The draw is LOST, not spent — moving it to the discard
		# would cycle the deck for nothing, which is a favour to exactly the
		# free-draw loops test_degenerate.gd exists to bound.
		#
		# BEFORE the reshuffle below, deliberately. A refused draw must not be able to
		# turn the discard pile over: that is the same free deck cycle by another route,
		# and it would reorder the pile of a player who did nothing but hold ten cards.
		if hand.size() >= Balance.MAX_HAND_SIZE:
			draws_lost += n - i
			break
		if draw_pile.is_empty():
			draw_pile = discard_pile.duplicate()
			discard_pile.clear()
			draw_pile.shuffle()
		if draw_pile.is_empty():
			break
		hand.append(draw_pile.pop_back())

## What the log owes the player about a draw the cap ate, and a reset of the count.
##
## Slay the Spire shows nothing here, and this game cannot afford that: a run with
## Keen Lens equipped is paying enemy scaling for +1 card a turn (`Balance.power_ratio`
## folds relics in), so a draw that silently does not happen is a relic that silently
## stopped working. Same register as the escrow line — say what was left behind.
##
## Read-and-clear rather than a field the UI polls, because the three places a draw
## can be lost (turn start, a card's own draw, a triggered relic) each already return
## a log line, and a counter nobody empties reports the same loss every turn.
func take_draw_notice() -> String:
	if draws_lost <= 0:
		return ""
	var n := draws_lost
	draws_lost = 0
	if n == 1:
		return "Hand full at %d — the draw stays in the pile." % Balance.MAX_HAND_SIZE
	return "Hand full at %d — %d draws stay in the pile." % [Balance.MAX_HAND_SIZE, n]

func can_play(card: CardData) -> bool:
	# eff_cost / eff_hp_cost, not the authored fields: levels buy both of these
	# DOWN, and a card the player has paid to make cheaper has to actually be
	# cheaper at the one place the game checks whether it can be afforded.
	if card.eff_cost() > energy:
		return false
	# an HP cost must never be lethal: paying it has to leave you alive
	if card.eff_hp_cost() > 0 and player.hp <= card.eff_hp_cost():
		return false
	return true

## Fire every relic effect matching `when`. Returns a log line, or "".
##
## Relics used to be flat stats applied at setup; a trigger has to be checked at
## the moment it describes, so each call site names its own moment rather than one
## catch-all "update relics" pass that would quietly fire the wrong things.
func _fire_relics(when: int, amount: int = 0) -> String:
	var parts: Array[String] = []
	for ri in relics.size():
		var r = relics[ri]
		if not (r is RelicData):
			continue
		for ei in r.trigger_count():
			if r.trigger[ei] != when:
				continue
			var threshold: int = r.threshold_at(ei)
			var key := "%d:%d" % [ri, ei]
			match when:
				RelicData.Trigger.ON_TURN_START:
					if threshold <= 0 or turn % threshold != 0:
						continue
				RelicData.Trigger.ON_CARDS_PLAYED:
					if amount != threshold:
						continue   # the Nth card exactly, not every card after it
				RelicData.Trigger.ON_HP_BELOW_PCT:
					if relic_fired.has(key):
						continue
					if float(player.hp) * 100.0 / maxf(1.0, float(player.max_hp)) >= float(threshold):
						continue
					relic_fired[key] = true
				RelicData.Trigger.ON_BLOCK_EXPIRED:
					if amount <= 0:
						continue
			var msg := _apply_relic_effect(r, ei, amount)
			if msg != "":
				parts.append("%s: %s" % [r.name, msg])
	return " ".join(parts)

func _apply_relic_effect(r: RelicData, ei: int, amount: int) -> String:
	var v: int = r.effect_value[ei]
	match r.effect[ei]:
		RelicData.Effect.DAMAGE_ALL:
			var hit := 0
			for e in enemies:
				if not e.is_dead():
					e.take_damage(player.outgoing_damage(v))
					hit += 1
			if hit == 0:
				return ""
			retarget()
			return "%d to all." % v
		RelicData.Effect.DRAW:
			draw_cards(v)
			return "draw %d." % v
		RelicData.Effect.GAIN_BLOCK:
			# ON_BLOCK_EXPIRED converts what evaporated, so it scales with the loss
			var gain: int = v if amount <= 0 else v
			player.gain_block(player.outgoing_block(gain))
			return "block +%d." % gain
		RelicData.Effect.GAIN_STRENGTH:
			player.strength += v
			return "Strength +%d." % v
		RelicData.Effect.HEAL:
			player.hp = mini(player.max_hp, player.hp + v)
			return "heal %d." % v
		RelicData.Effect.GAIN_ENERGY:
			energy += v
			return "energy +%d." % v
	return ""

## Can the equipped power be fired right now?
##
## Once per turn, deliberately. With three energy and a one-cost power, unlimited
## firing makes "power, power, power" a legal turn: the power becomes both floor
## and ceiling, draw stops mattering, and the deckbuilder stops being one.
func can_use_power() -> bool:
	if power == null or power_used or over():
		return false
	if power.eff_cost() > energy:
		return false
	# an HP cost must never be lethal, same rule as a card
	return not (power.eff_hp_cost() > 0 and player.hp <= power.eff_hp_cost())

func use_power() -> String:
	if not can_use_power():
		return ""
	energy -= power.eff_cost()
	power_used = true
	var msg := _resolve(power)
	# a power that draws can hit the cap too — D120
	msg = (msg + " " + take_draw_notice()).strip_edges()
	return msg if msg != "" else "%s used." % power.name

## Play a card at the current target. Returns a short log line, or "" if unplayable.
func play_card(card: CardData) -> String:
	if not can_play(card):
		return ""
	energy -= card.eff_cost()
	cards_played_this_turn += 1
	var msg := _resolve(card)
	hand.erase(card)
	var fired := _fire_relics(RelicData.Trigger.ON_CARDS_PLAYED, cards_played_this_turn)
	if fired != "":
		msg += " " + fired
	# exhausted cards leave the combat entirely instead of returning to the discard
	if not card.exhaust:
		discard_pile.append(card)
	else:
		msg += "(exhausted) "
	# AFTER the relic fire, because both the card's own draw and an ON_CARDS_PLAYED
	# relic's draw can be eaten by the cap and the player is owed one line either way.
	var lost := take_draw_notice()
	if lost != "":
		msg += " " + lost
	return msg if msg != "" else "%s played." % card.name

# --- what a card would do RIGHT NOW ------------------------------------------
#
# D50 stopped cards lying about their level. They went on lying about the fight:
# a card face is generated from `eff_damage()`, which knows about fusion levels
# and nothing else, so with 3 Strength a "Deal 6 damage" card dealt 9 and said 6.
# Strength and Dexterity were effectively invisible — you could read the buff in
# the status line and still not see it anywhere it mattered.
#
# `_resolve()` computes its numbers HERE, and the card face reads the same
# functions, so what the player is shown is what the engine is about to do. A
# second copy of this arithmetic for display is the D34 label table again.

## Base damage before the target's own Vulnerable and Block.
##
## This is also where cards read the fight (D66). All of it lands here rather than
## in `_resolve` so the card FACE shows the conditional bonus too — a card that
## says 9 and hits for 17 because the target is poisoned is the D50 lie again, in a
## more confusing form.
func card_base_damage(card: CardData) -> int:
	var base := card.hit_damage()          # includes per-combat growth
	if card.damage_from_block:
		base = player.block
	if card.strength_mult > 0:
		base += player.strength * card.strength_mult
	var foe := current_target()
	if card.damage_per_poison > 0 and foe != null:
		base += card.damage_per_poison * foe.poison
	if card.damage_per_thorns > 0:
		base += card.damage_per_thorns * player.thorns
	if card.bonus_vs_debuffed > 0 and foe != null and (foe.vulnerable > 0 or foe.weak > 0):
		base += card.bonus_vs_debuffed
	if card.combo_at > 0 and cards_played_this_turn >= card.combo_at:
		base += card.combo_bonus
	return base

## Block this card actually grants, after Dexterity and anything it reads.
##
## `hand` still contains the card being played at this point (play_card erases it
## afterwards), so "other cards in hand" is one less than the hand.
func card_block_bonus(card: CardData) -> int:
	var bonus := 0
	if card.block_per_card_in_hand > 0:
		bonus += card.block_per_card_in_hand * maxi(0, hand.size() - 1)
	if card.combo_at > 0 and card.eff_block() > 0 and cards_played_this_turn >= card.combo_at:
		bonus += card.combo_bonus
	return bonus

## What one hit actually leaves the player's hands as: Strength added, Weak applied.
func card_damage(card: CardData) -> int:
	return player.outgoing_damage(card_base_damage(card))

func card_block(card: CardData) -> int:
	if card.eff_block() <= 0 and card_block_bonus(card) <= 0:
		return 0
	return player.outgoing_block(card.eff_block() + card_block_bonus(card))

## The face text with this fight's numbers in it.
func card_text(card: CardData) -> String:
	return card.effect_text(card_damage(card), card_block(card))

## Apply a card's effects. Split out of play_card so a POWER resolves through the
## identical path — a power is a card the player always holds, and duplicating
## twenty mechanics for it would guarantee the two drift apart.
## Pays no energy and does no hand bookkeeping; the caller owns both.
func _resolve(card: CardData) -> String:
	var foe := current_target()
	var msg := ""
	if card.eff_hp_cost() > 0:
		player.hp = maxi(1, player.hp - card.eff_hp_cost())
		msg += "Paid %d HP. " % card.eff_hp_cost()

	# --- damage: multi-hit, AoE, Block-scaled, Strength-scaled ---
	var base_dmg := card_base_damage(card)
	if base_dmg > 0:
		var targets: Array = []
		if card.aoe:
			for e in enemies:
				if not e.is_dead():
					targets.append(e)
		elif foe != null:
			targets.append(foe)
		var total := 0
		for tgt in targets:
			for h in maxi(1, card.hits):
				if tgt.is_dead():
					break
				var dealt := player.outgoing_damage(base_dmg)
				total += tgt.predicted_damage(dealt)
				tgt.take_damage(dealt)
		if card.lifesteal and total > 0:
			player.hp = mini(player.max_hp, player.hp + total)
			msg += "Drained %d. " % total
		if not targets.is_empty():
			var who: String = "all enemies" if card.aoe else String(targets[0].name)
			msg += "%s hits %s for %d%s. " % [
				card.name, who, total, (" x%d" % card.hits) if card.hits > 1 else ""]
		var killed := false
		for e in enemies:
			if e.is_dead():
				if not e.get_meta("counted_dead", false):
					e.set_meta("counted_dead", true)
					killed = true
				msg += "%s dies! " % e.name
				var onkill := _fire_relics(RelicData.Trigger.ON_KILL)
				if onkill != "":
					msg += onkill + " "
		# a kill that pays for itself: this is what makes a swarm turn keep going
		if killed and card.energy_on_kill:
			energy += 1
			msg += "Energy +1. "
		retarget()

	if card.double_block:
		var extra := player.block
		player.gain_block(extra)
		msg += "Block doubled to %d. " % player.block
	if card.eff_block() > 0 or card_block_bonus(card) > 0:
		var blk := card_block(card)
		player.gain_block(blk)
		msg += "Block +%d. " % blk
	if card.eff_heal() > 0:
		player.hp = mini(player.max_hp, player.hp + card.eff_heal())
		msg += "Healed %d. " % card.eff_heal()
	if card.energy_gain > 0:
		energy += card.energy_gain
		msg += "Energy +%d. " % card.energy_gain

	# --- statuses on the target (AoE spreads debuffs too) ---
	var debuff_targets: Array = []
	if card.aoe:
		for e in enemies:
			if not e.is_dead():
				debuff_targets.append(e)
	elif foe != null and not foe.is_dead():
		debuff_targets.append(foe)
	elif foe != null:
		debuff_targets.append(foe)
	for tgt in debuff_targets:
		if card.eff_vulnerable() > 0:
			tgt.vulnerable += card.eff_vulnerable()
		if card.eff_weak() > 0:
			tgt.weak += card.eff_weak()
		if card.eff_poison() > 0:
			tgt.poison += card.eff_poison()
	if card.eff_vulnerable() > 0:
		msg += "Vulnerable %d. " % card.eff_vulnerable()
	if card.eff_weak() > 0:
		msg += "Weak %d. " % card.eff_weak()
	if card.eff_poison() > 0:
		msg += "Poison %d. " % card.eff_poison()

	# --- self buffs ---
	if card.eff_strength() > 0:
		player.strength += card.eff_strength()
		msg += "Strength +%d. " % card.eff_strength()
	if card.eff_dexterity() > 0:
		player.dexterity += card.eff_dexterity()
		msg += "Dexterity +%d. " % card.eff_dexterity()
	if card.eff_thorns() > 0:
		player.thorns += card.eff_thorns()
		msg += "Thorns +%d. " % card.eff_thorns()
	if card.retain_block:
		player.retain_block = true
		msg += "Block now persists between turns! "
	if card.grows > 0:
		card.growth += card.grows
		msg += "(grows +%d) " % card.grows
	if card.eff_draw() > 0:
		draw_cards(card.eff_draw())
		# Still the card's own number, not the number that landed. The D120 notice
		# `play_card` appends says what the cap ate, so the pair reads "Draw 3. Hand
		# full at 10 — 3 draws stay in the pile." — the promise and its consequence,
		# which is the same shape as the escrow line. Quietly printing "Draw 0." would
		# hide WHY, and the card face would still be advertising 3.
		msg += "Draw %d." % card.eff_draw()
	return msg

## Discard hand, every living enemy acts, next turn begins if the player survives.
## Order matters: block absorbs incoming hits *before* it expires at the start of
## the player's next turn.
func end_turn() -> String:
	# retained cards stay in hand instead of being discarded
	var kept: Array[CardData] = []
	for c in hand:
		if c.retain:
			kept.append(c)
		else:
			discard_pile.append(c)
	hand = kept

	# snapshot what the enemies are reacting to, BEFORE they chew through it
	player_block_last_turn = player.block
	cards_played_last_turn = cards_played_this_turn

	var parts: Array[String] = []
	for i in enemies.size():
		if enemies[i].is_dead():
			continue
		enemies[i].begin_turn()  # enemy block expires before it acts again
		parts.append(_resolve_enemy(i))
		enemy_turns[i] = int(enemy_turns[i]) + 1
		if player.is_dead():
			break

	# elites/bosses additionally pressure the player's plan
	var extra := _enemy_debuff()
	if extra != "":
		parts.append(extra)

	# poison bites at end of turn, ignoring block
	var pdot := player.end_turn()
	if pdot > 0:
		parts.append("Poison deals %d to you." % pdot)
	for e in enemies:
		var edot := e.end_turn()
		if edot > 0:
			parts.append("Poison deals %d to %s." % [edot, e.name])
	# poison can finish an enemy off
	if won():
		return " ".join(parts)

	if player.is_dead():
		return " ".join(parts)
	for i in enemies.size():
		if not enemies[i].is_dead():
			_roll_intent(i)
	start_turn()
	# The next hand is dealt in here, so this is where a turn-start draw lost to
	# retained cards surfaces — the one case in D120 the player did not cause on
	# purpose, and the one most worth saying out loud.
	var lost := take_draw_notice()
	if lost != "":
		parts.append(lost)
	return " ".join(parts)

func _resolve_enemy(i: int) -> String:
	var e: Combatant = enemies[i]
	var a: int = int(intents[i]["action"])
	var v: int = int(intents[i]["value"])
	match a:
		EnemyData.Action.ATTACK:
			var dealt := e.outgoing_damage(v)
			# Deeper places hit through a shield. Split off the piercing share
			# BEFORE Block sees the rest — see Balance.pierce_fraction.
			var pierce := int(round(float(dealt) * Balance.pierce_fraction(dungeon, ratio)))
			var blockable := maxi(0, dealt - pierce)
			var landed := player.predicted_damage(blockable) + pierce
			player.take_damage(blockable)
			if pierce > 0:
				player.hp = maxi(0, player.hp - pierce)
			var out := "%s hits for %d%s." % [
				e.name, landed, (" (%d pierces)" % pierce) if pierce > 0 else ""]
			var hurt := _fire_relics(RelicData.Trigger.ON_HP_BELOW_PCT)
			if hurt != "":
				out += " " + hurt
			if player.thorns > 0:
				e.take_damage(player.thorns)
				out += " Thorns bite back for %d." % player.thorns
				if e.is_dead():
					out += " %s dies!" % e.name
					retarget()
			return out
		EnemyData.Action.DEBUFF_VULN:
			player.vulnerable += v
			return "%s makes you Vulnerable %d." % [e.name, v]
		EnemyData.Action.DEBUFF_WEAK:
			player.weak += v
			return "%s weakens you %d." % [e.name, v]
		EnemyData.Action.DEFEND:
			e.gain_block(v)
			return "%s blocks %d." % [e.name, v]
		EnemyData.Action.EMPOWER:
			e.strength += v
			return "%s empowers itself (+%d)." % [e.name, v]
		EnemyData.Action.SUNDER:
			# straight to HP: this is the answer to turtling, so Block must not stop it
			var raw := e.outgoing_damage(v)
			player.hp = maxi(0, player.hp - raw)
			return "%s SUNDERS through your guard for %d!" % [e.name, raw]
		EnemyData.Action.ENRAGE:
			e.strength += v
			return "%s ENRAGES (+%d Strength)!" % [e.name, v]
		EnemyData.Action.DRAIN:
			var dd := e.outgoing_damage(v)
			var land := player.predicted_damage(dd)
			player.take_damage(dd)
			e.hp = mini(e.max_hp, e.hp + land)
			return "%s drains %d and heals." % [e.name, land]
	return ""

## Elite/boss debuff every few turns, on top of archetype behaviour.
func _enemy_debuff() -> String:
	if tier == Balance.Tier.NORMAL or turn % Balance.ENEMY_DEBUFF_PERIOD != 0:
		return ""
	if randi() % 2 == 0:
		player.vulnerable += Balance.ENEMY_VULNERABLE_STACKS
		return "You are Vulnerable %d." % Balance.ENEMY_VULNERABLE_STACKS
	player.weak += Balance.ENEMY_WEAK_STACKS
	return "You are Weakened %d." % Balance.ENEMY_WEAK_STACKS

# --- persistence (D22) ---
##
## Combat is serialized, not just the run between fights. Without this, force
## quitting a fight that is going badly and reloading would be a free retry from
## the pre-fight HP — save scumming. Restoring mid-combat removes the incentive
## entirely, because there is nothing to roll back to.
static func _cards_to_state(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append({"id": c.id, "level": c.level, "growth": c.growth})
	return out

static func _cards_from_state(arr: Array, catalog: Dictionary) -> Array[CardData]:
	var out: Array[CardData] = []
	for e in arr:
		var id := String(e.get("id", ""))
		if not catalog.has(id):
			continue   # content renamed since the save
		var c := (load(catalog[id]) as CardData).duplicate()
		c.level = int(e.get("level", 1))
		c.growth = int(e.get("growth", 0))
		out.append(c)
	return out

func save_state() -> Dictionary:
	var foes: Array = []
	for i in enemies.size():
		foes.append({
			"combatant": enemies[i].save_state(),
			"archetype": (archetypes[i] as EnemyData).id,
			"base_damage": int(base_damage[i]),
			"turns": int(enemy_turns[i]),
			"intent": intents[i],
		})
	return {
		"player": player.save_state(),
		"enemies": foes,
		"target": target, "energy": energy, "turn": turn,
		"dungeon": dungeon, "tier": tier, "ratio": ratio,
		"bonus_energy": bonus_energy, "extra_draw": extra_draw,
		"power": power.id if power != null else "",
		"power_level": power.level if power != null else 1,
		"power_used": power_used,
		"cards_played_last_turn": cards_played_last_turn,
		"player_block_last_turn": player_block_last_turn,
		"rules_fired": rules_fired,
		"relic_fired": relic_fired,
		"draw": _cards_to_state(draw_pile),
		"hand": _cards_to_state(hand),
		"discard": _cards_to_state(discard_pile),
	}

## Restore a combat exactly. `relics` is re-supplied by the caller (it lives in
## meta state), and `catalog` maps card ids to resources.
func load_state(d: Dictionary, catalog: Dictionary, p_relics: Array = []) -> void:
	relics = p_relics
	dungeon = int(d.get("dungeon", 1))
	tier = int(d.get("tier", Balance.Tier.NORMAL))
	ratio = float(d.get("ratio", 1.0))
	bonus_energy = int(d.get("bonus_energy", 0))
	var pid := String(d.get("power", ""))
	if pid != "":
		power = Balance.power(pid)
		if power != null:
			power = power.duplicate()
			power.level = int(d.get("power_level", 1))
	power_used = bool(d.get("power_used", false))
	cards_played_last_turn = int(d.get("cards_played_last_turn", 0))
	player_block_last_turn = int(d.get("player_block_last_turn", 0))
	relic_fired = d.get("relic_fired", {}).duplicate()
	rules_fired = []
	for entry in d.get("rules_fired", []):
		var spent: Array = []
		for n in entry:
			spent.append(int(n))
		rules_fired.append(spent)
	extra_draw = int(d.get("extra_draw", 0))
	energy = int(d.get("energy", Balance.MAX_ENERGY))
	turn = int(d.get("turn", 1))
	target = int(d.get("target", 0))

	player = Combatant.new()
	player.load_state(d.get("player", {}))

	enemies = []
	archetypes = []
	base_damage = []
	enemy_turns = []
	intents = []
	for e in d.get("enemies", []):
		var c := Combatant.new()
		c.load_state(e.get("combatant", {}))
		enemies.append(c)
		var arch := Balance.enemy(String(e.get("archetype", "cultist")))
		archetypes.append(arch if arch != null else EnemyData.new())
		base_damage.append(int(e.get("base_damage", 5)))
		enemy_turns.append(int(e.get("turns", 0)))
		var it: Dictionary = e.get("intent", {})
		intents.append({
			"action": int(it.get("action", EnemyData.Action.ATTACK)),
			"value": int(it.get("value", 0)),
		})

	draw_pile = _cards_from_state(d.get("draw", []), catalog)
	hand = _cards_from_state(d.get("hand", []), catalog)
	discard_pile = _cards_from_state(d.get("discard", []), catalog)

func won() -> bool:
	return living_enemies() == 0

func lost() -> bool:
	return player.is_dead()

func over() -> bool:
	return won() or lost()
