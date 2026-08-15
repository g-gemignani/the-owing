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
## Has `repeat_first_attack` already been spent this turn? Reset by `start_turn`.
var repeated_attack_this_turn: bool = false
var cards_played_last_turn: int = 0
## Block the player was holding when the enemies last acted — what a
## block-punishing enemy is reacting to.
var player_block_last_turn: int = 0
## Rule indices already spent, per enemy. A once-only rule (an enrage) must not
## re-trigger every turn after its condition stays true.
var rules_fired: Array = []

# --- the tally: what this fight did, for the floor's errand (D203) --------------------
#
# Kept HERE and not in `combat.gd` for the reason this file opens with: the engine drives the
# headless simulator as well as the scene, so a counter kept in the scene is a fact about the
# game `tools/sim_balance.gd` cannot see. That is precisely the hole D124 found for draw and
# D180 found again for relics — a thing the game reads and the instrument does not — and it is
# cheaper to not dig it than to fill it in two years later.
#
# Fight-scoped. `combat.gd` hands it to the floor when the fight is WON, and a lost fight ends
# the run anyway.
var tally: Dictionary = {}
## Damage landed since this turn began, for `peak_turn`.
var turn_damage: int = 0
## What this fight has and has not done, for the rows that ask about the SHAPE of a win rather
## than an amount. Set as they happen and read once, at the win.
var played_attack: bool = false
var played_skill: bool = false
var fired_power: bool = false

## Add to a running count.
func _t(key: String, n: int = 1) -> void:
	if n <= 0:
		return
	tally[key] = int(tally.get(key, 0)) + n

## Raise a high-water mark. Separate from `_t` because a peak summed is a different and much
## easier ask wearing the same words — "stand behind 40 block" settled by blocking 8 five times.
func _pk(key: String, n: int) -> void:
	if n > int(tally.get(key, 0)):
		tally[key] = n

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

# --- what the D204 combo cards read ------------------------------------------
#
# Three of these are per TURN and one is per COMBAT, and the split is the design:
# an enabler you did not cash in this turn is gone, so the cards that set a turn up
# have to be played in the same turn as the card that collects — while the exhaust
# tally is the fight's whole history and only ever grows.
#
## Damage owed to the next attack this turn (`empower_next`). Spent the moment one
## lands, before the same resolve can grant a new one.
var next_attack_bonus: int = 0
## Energy off the next card this turn (`discount_next`). Read through `play_cost`.
var next_card_discount: int = 0
## The card played immediately before the one being played, this turn only. What
## `repeat_previous` echoes.
var previous_card: CardData = null
## Cards that have left this combat for good — exhausted by their own rule or burned
## out of a hand. The ammunition `per_exhausted` collects.
var exhausted_this_combat: int = 0
## Enemies killed so far in this fight. What `kill_damage_pct` compounds on (D257).
##
## Counted rather than derived from `enemies`, because a fight restored mid-combat from a save can
## open with a corpse already in the array — deriving it would hand the relic its stack back for
## kills the player made before quitting, which is a small save-scum and a wrong number either way.
var kills_this_combat: int = 0
## How deep the run was when this fight began, 0.0 at the mouth and 1.0 at the boss. Negative means
## the caller is not in a run and wants no ramp (D270). Held so `enemy_damage` can read it on every
## turn, not only at setup.
var run_progress: float = -1.0
## How many times this dungeon has killed the player since they last beat it (D285). Raises enemy
## HP and damage; the player comes back holding relics to answer it.
var run_grudge: int = 0
## Energy the X-cost card currently being played will spend, stashed before the pool
## moves so the face and the resolution read one number. -1 when nothing is mid-play.
var x_energy: int = -1
## True only while `play_card` is inside `_resolve`. See `cards_played_before()`.
var resolving_play: bool = false

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

## `p_untaxed` is relics whose EFFECTS apply and whose power is deliberately NOT folded into
## enemy scaling — free strength, on purpose. Nothing in the game passes it yet; it exists so
## `tools/sim_balance.gd --spoils=N` can price untaxed in-run power before D226 commits to it,
## and it is the seam D226 step 3 needs either way. Default empty, so every existing caller is
## unchanged and the pillar still holds everywhere it is not passed.
##
## Two arrays rather than a flag on RelicData: whether a relic is taxed is a fact about HOW IT
## WAS ACQUIRED — found in this run, or owned — and not about the relic. The same Bone Charm is
## priced when you own it and free when the floor lends it to you.
func setup(deck: Array[CardData], hp: int, max_hp: int, p_dungeon: int, p_tier: int,
		forced_archetype: String = "", p_relics: Array = [],
		p_roster: Array = [], p_power: PowerData = null, p_boss: String = "",
		p_untaxed: Array = [], p_progress: float = -1.0, p_grudge: int = 0) -> void:
	dungeon = p_dungeon
	tier = p_tier
	# Everything below this line — per-turn bonuses, combat-start effects, `_fire_relics` —
	# reads `relics`, so an untaxed relic is a relic in every respect except the one.
	run_progress = p_progress
	run_grudge = p_grudge
	relics = p_relics.duplicate()
	relics.append_array(p_untaxed)
	power = p_power
	# relics and the equipped power are throughput outside the deck, so they must
	# raise enemy scaling too — otherwise they are free strength. `p_untaxed` is the
	# exception and is the whole point of it: priced against `p_relics` alone, and read
	# BEFORE `_spawn_enemies` below, which is what actually scales to it.
	ratio = Balance.power_ratio(deck, p_relics, power)

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
		# `block_carries` (D233) reuses `Combatant.retain_block`, which a Legendary power already
		# sets and `begin_turn` already honours. A second mechanism for one sentence of rules is
		# the D34 shape, and this one is tested by every retain_block card in the catalogue.
		if r.block_carries:
			player.retain_block = true

	tally = {}
	turn_damage = 0
	played_attack = false
	played_skill = false
	fired_power = false
	# D204: fight-scoped like the tally above, and reset in the same place for the same
	# reason. `start_turn()` clears the per-turn carriers, but the exhaust count belongs
	# to the whole combat — and an engine instance that is set up twice would otherwise
	# open its second fight holding the first one's ammunition.
	exhausted_this_combat = 0
	x_energy = -1
	resolving_play = false

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
	# `run_progress` is how deep the RUN is, 0 at the mouth and 1 at the boss (D270). Negative means
	# no ramp, which is what every caller that is asking about the dungeon rather than about one
	# moment in one run gets by default.
	var hp_budget := Balance.enemy_max_hp(dungeon, tier, ratio, run_progress, run_grudge) \
		* Balance.multi_hp_factor(count)
	var dmg_budget := float(Balance.enemy_damage(dungeon, tier, ratio, 1, 1, run_progress,
		run_grudge)) * Balance.multi_dmg_factor(count)

	for i in count:
		var c := Combatant.new()
		# "Bone Picker 2" reads as developer output, and taking the suffix off was
		# looked at and declined (D125). The name is not a label, it is the SUBJECT of
		# every line the fight writes: eleven sentences in this file are built around
		# it — "%s hits for %d", "%s dies!", "Poison deals %d to %s", "%s blocks %d",
		# "%s ENRAGES" — and the log has no other handle on which one it means. Slay
		# the Spire can drop the number because its feedback is spatial: damage floats
		# over the creature it happened to. This game says it in prose, so with two
		# unnumbered Bone Pickers "Bone Picker dies!" claims the pair is dead, and
		# nothing on screen resolves it. The number is doing work; it stays until the
		# log can point.
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
	_t(Balance.TALLY_TURNS)
	turn_damage = 0
	# Block expires inside player.begin_turn() below, so capture it first: a relic
	# that pays out on wasted Block needs to know how much was wasted.
	var expiring: int = 0 if player.retain_block else player.block
	energy = Balance.MAX_ENERGY + bonus_energy
	power_used = false
	cards_played_this_turn = 0
	repeated_attack_this_turn = false
	# D204: the three per-turn combo carriers expire with the turn, exactly like Block.
	# An enabler you did not cash in is gone, which is what forces a combo deck to
	# assemble its turn rather than bank a discount over three of them.
	next_attack_bonus = 0
	next_card_discount = 0
	previous_card = null
	player.begin_turn()  # block expires here unless a retain_block power is active
	# start_block relics re-apply every turn's opening, after block expiry
	for r in relics:
		if r.start_block > 0:
			player.gain_block(player.outgoing_block(r.start_block))
	draw_cards(Balance.HAND_SIZE + extra_draw)
	# After the start_block relics and the draw, so a relic's opening block counts toward the
	# wall the player is asked to stand behind — it is block they are genuinely standing behind.
	_pk(Balance.TALLY_PEAK_BLOCK, player.block)
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
		# Counted here rather than at the call sites, for the same reason the D120 cap is
		# written here: this is the ONE way a card gets into a hand, so a draw errand cannot
		# miss a source, and a draw the cap ate does not count — the player did not get it.
		_t(Balance.TALLY_DRAWS)

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

## What this card costs RIGHT NOW: its levelled cost, less any discount standing.
##
## Every read of a price during a fight goes through here, for exactly the reason
## every read of a card's damage goes through `card_damage` (D50). A discount the
## player was promised has to apply at the place the game checks affordability AND on
## the badge that quotes the price, or the two disagree and one of them is lying.
## Sum of one rule-modifier field over every relic held, including the untaxed ones (D233).
##
## `Balance.relic_field_sum` does the same job for the run loop and the simulator. This exists
## because the engine holds its relics in `relics` and asks this question at four chokepoints,
## and four hand-written loops is the D34 shape waiting to happen.
func _mod(field: String) -> int:
	var n := 0
	for r in relics:
		if r is RelicData:
			n += int(r.get(field))
	return n

## The product of one PERCENT field over every relic held, as a multiplier (D243).
##
## Percentages used to be summed and applied once: three relics at +30% gave +90%, so 1.9x at the
## very best and 1.29x measured. Reaching 5x additively needs each relic to be worth about +80%, and
## a run finds about five. Compounded, five relics at +38% give 5x — the same relics in the same
## slots, applied in a different order.
##
## This is the multiplication the escalation lives in, so it is one function and every percent field
## reads it. Summing survives in `_mod` for the fields where adding is what the rule MEANS —
## `cost_reduction` is "one less" per relic and two of them are two less, not 1.21 less.
func _mod_mult(field: String) -> float:
	var m := 1.0
	for r in relics:
		if r is RelicData:
			var pct := int(r.get(field))
			if pct != 0:
				m *= 1.0 + float(pct) / 100.0
	return m

## Is any relic held setting this flag?
func _mod_flag(field: String) -> bool:
	for r in relics:
		if r is RelicData and bool(r.get(field)):
			return true
	return false

func play_cost(card: CardData) -> int:
	# `free_first_card` before `cost_reduction`, because a card that is already free cannot be
	# made cheaper and the order would otherwise decide whether the reduction is wasted.
	if _mod_flag("free_first_card") and cards_played_this_turn == 0:
		return 0
	return maxi(0, card.eff_cost() - next_card_discount - _mod("cost_reduction"))

## How many cards will have left this combat for good once `card` has resolved.
##
## PROJECTED rather than counted, and the projection is the whole point: the card face
## reads `per_exhausted` before the card is played, so a Cull that advertises 4 Block
## and then grants 14 is the D50 lie in a new costume. The face and `_resolve` both
## call this while the hand is still intact and the tally has not moved, so the two
## cannot disagree — which is why `play_card` does its exhaust bookkeeping afterwards.
func projected_exhausted(card: CardData) -> int:
	var n := exhausted_this_combat
	if card.exhaust_hand:
		n += maxi(0, hand.size() - (1 if card in hand else 0))
	if card.exhaust:
		n += 1
	# Capped, and the cap is why the payoffs can be priced at all — see
	# Balance.EXHAUST_TALLY_CAP for the numbers that made it necessary. Applied HERE
	# rather than to `exhausted_this_combat` itself, because the raw count is also the
	# fight's history and a ceiling on the reward is not a ceiling on the fact.
	return mini(n, Balance.EXHAUST_TALLY_CAP)

## Will playing `card` leave your hand empty? The card itself is counted out, because
## it is on its way to the discard: "the last card in your hand" is what the player
## means by it, and what the face has to promise.
func hand_empties(card: CardData) -> bool:
	if card.exhaust_hand:
		return true
	return hand.size() - (1 if card in hand else 0) <= 0

## Energy an X-cost card spends: whatever is left over after paying for it.
##
## `play_card` stashes this before the cost comes out of the pool. Without the stash
## the face and the resolution disagree by the card's own cost, because `_resolve`
## runs after the energy has been paid — a two-energy gap on the one card whose whole
## number is the energy.
## How many cards were played BEFORE the card currently being asked about.
##
## One function because it is one question asked from two moments, and the two used to
## answer it differently. `cards_played_this_turn` is bumped before `_resolve` runs, so
## a card mid-resolution is already in the count and a card being drawn on the face is
## not — which made the tempo mechanic disagree with itself: on your third card Nick's
## face showed +0 and then dealt +5 (a D50 lie, in the one mechanic whose entire
## content is a count). Every reader of "how far into the turn is this" comes here.
##
## A Power is deliberately not counted as a card by `play_card`'s sibling `use_power`,
## and it does not set the flag either, so this still reads "before it" for one too.
func cards_played_before() -> int:
	return maxi(0, cards_played_this_turn - (1 if resolving_play else 0))

func x_energy_for(card: CardData) -> int:
	if not card.spend_all_energy:
		return 0
	if x_energy >= 0:
		return x_energy
	return maxi(0, energy - play_cost(card))

## Why this card cannot be played right now, in the words the player gets, or "" if
## it can be.
##
## The refusals used to be a bare `false` and the screen guessed the reason: every
## denial in the game printed "Not enough energy for X". That was right most of the
## time and wrong in the one case a player is most likely to hit and least able to
## work out — a card with an HP cost, refused because paying it would kill them, while
## the card in front of them said it cost 0 and the pool was full. Reported as a card
## that could not be played for no reason, which is exactly what it looked like.
##
## So the reason is generated where the rule lives, and `can_play` is defined in terms
## of it rather than beside it. Two functions that each decide affordability is the
## D50 disagreement in a new place: one of them gets a rule added and the other goes on
## refusing, or explaining, something that is no longer true.
##
## Both lines quote the numbers rather than naming the resource, because "not enough
## health" is a statement a player at 4 HP holding a card that costs 5 cannot argue
## with, and "you cannot play that" is one they can only test by clicking.
func why_not(card: CardData) -> String:
	# play_cost / eff_hp_cost, not the authored fields: levels buy both of these
	# DOWN and a discount buys the first one down again, and a card the player has
	# been promised is cheaper has to actually be cheaper at the one place the game
	# checks whether it can be afforded.
	var cost := play_cost(card)
	if cost > energy:
		return "%s needs %d energy and you have %d." % [card.name, cost, energy]
	# an HP cost must never be lethal: paying it has to leave you alive
	var hp_cost := card.eff_hp_cost()
	if hp_cost > 0 and player.hp <= hp_cost:
		return "%s costs %d health and you have %d — paying it would kill you." % [
			card.name, hp_cost, player.hp]
	return ""

func can_play(card: CardData) -> bool:
	return why_not(card) == ""

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
	if play_cost(power) > energy:
		return false
	# an HP cost must never be lethal, same rule as a card
	return not (power.eff_hp_cost() > 0 and player.hp <= power.eff_hp_cost())

func use_power() -> String:
	if not can_use_power():
		return ""
	energy -= power.eff_cost()
	power_used = true
	_t(Balance.TALLY_POWER_USES)
	_t(Balance.TALLY_ENERGY, power.eff_cost())
	fired_power = true
	# NOT counted as a card: `_resolve` is shared with `play_card` for the effects, but a Power
	# is the one thing you carry rather than something in the deck, and an errand asking for
	# twenty cards must not be settleable partly by an ability that costs no card at all.
	var msg := _resolve(power)
	# a power that draws can hit the cap too — D120
	msg = (msg + " " + take_draw_notice()).strip_edges()
	return msg if msg != "" else "%s used." % power.name

## Play a card at the current target. Returns a short log line, or "" if unplayable.
func play_card(card: CardData) -> String:
	if not can_play(card):
		return ""
	# D204: every price is read off the PRE-PAYMENT pool, which is the state the card
	# face the player clicked was drawn from. Three of them — the discounted cost, the
	# energy an X-cost card is about to spend, and the card it is about to echo — stop
	# being answerable the moment anything below runs, so they are all taken here.
	var paid := play_cost(card)
	var echo: CardData = previous_card if card.repeat_previous else null
	x_energy = maxi(0, energy - paid) if card.spend_all_energy else -1
	energy -= paid
	if card.spend_all_energy:
		energy = 0            # the rest of the turn IS the card; x_energy holds how much
	# spent by this card whether or not the card grants a fresh one further down
	next_card_discount = 0
	cards_played_this_turn += 1
	# What was played, before it resolves — a card that kills the last enemy still got played.
	_t(Balance.TALLY_CARDS)
	_t(Balance.TALLY_ENERGY, paid)   # what left the pool, discount and all
	match card.type:
		CardData.Type.ATTACK:
			_t(Balance.TALLY_ATTACKS)
			played_attack = true
		CardData.Type.SKILL:
			_t(Balance.TALLY_SKILLS)
			played_skill = true
		CardData.Type.POWER:
			_t(Balance.TALLY_POWERS)
	if card.aoe:
		_t(Balance.TALLY_AOE)
	if card.hits > 1:
		_t(Balance.TALLY_MULTI)
	_pk(Balance.TALLY_PEAK_HAND, cards_played_this_turn)
	# `block_per_card` (D257). In `play_card` and NOT in `_resolve`, because a power resolves through
	# `_resolve` too — it is a card the player always holds — and "every card you play" must not mean
	# the power as well. It is also before the resolution rather than after, so the Block is standing
	# when the card that granted it is a Block-scaled attack reading `player.block`.
	var per_card := _mod("block_per_card")
	var per_card_msg := ""
	if per_card > 0:
		var pcb := player.outgoing_block(per_card)
		player.gain_block(pcb)
		_t(Balance.TALLY_BLOCK, pcb)
		per_card_msg = "Block +%d. " % pcb
	resolving_play = true
	var msg := per_card_msg + _resolve(card)
	# D204: ...and then the last thing again. Outside `_resolve` on purpose. The echo is
	# a second RESOLUTION, not an item in this card's effect list, and keeping it here is
	# what makes the three rules it needs true for free: it pays no energy, it moves no
	# pile, and it cannot itself echo, because echoing is something `play_card` does and
	# nothing is playing the echoed card.
	if echo != null:
		msg += "Again — " + _resolve(echo)
	resolving_play = false
	hand.erase(card)
	var fired := _fire_relics(RelicData.Trigger.ON_CARDS_PLAYED, cards_played_this_turn)
	if fired != "":
		msg += " " + fired
	# D204: burn the rest of the hand, AFTER the erase above so the card doing the
	# burning is not in what it burns — and after `_resolve`, so that everything which
	# read `projected_exhausted()` (the face included) was looking at the same intact
	# hand. Move this earlier and Cull starts paying out on a tally it has already moved.
	# `exhaust_returns` (D234) sends burnt cards to the discard instead of out of the fight. The
	# TALLY still counts them: an exhaust deck's `per_exhausted` cards and the `exhaust` errand
	# both ask what was burnt, and the relic changes where the card GOES, not whether it burned.
	# Counting it otherwise would make the relic quietly switch off the build it most helps.
	var returns := _mod_flag("exhaust_returns")
	if card.exhaust_hand and not hand.is_empty():
		var burned := hand.size()
		exhausted_this_combat += burned
		for _i in burned:
			_t(Balance.TALLY_EXHAUST)
		if returns:
			discard_pile.append_array(hand)
		hand.clear()
		msg += "Burned %d card%s out of your hand%s. " % [
			burned, "" if burned == 1 else "s", " (they return to the pile)" if returns else ""]
	# exhausted cards leave the combat entirely instead of returning to the discard
	if not card.exhaust:
		discard_pile.append(card)
	else:
		exhausted_this_combat += 1
		_t(Balance.TALLY_EXHAUST)
		if returns:
			discard_pile.append(card)
			msg += "(burnt, and back in the pile) "
		else:
			msg += "(exhausted) "
	previous_card = card
	x_energy = -1
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
	# `+ 1` counts the card being asked about, on top of the ones before it. See
	# `cards_played_before()` for why this is not `cards_played_this_turn` any more.
	if card.combo_at > 0 and cards_played_before() + 1 >= card.combo_at:
		base += card.combo_bonus
	if card.damage_per_debuff > 0 and foe != null:
		base += card.damage_per_debuff * (foe.vulnerable + foe.weak)
	if card.damage_per_energy > 0:
		base += card.damage_per_energy * x_energy_for(card)
	# The three shared axes (see CardData's D204 block) pay in the card's own currency,
	# and `base > 0` is what decides which. A card with no damage of its own is a skill
	# whose bonus belongs to `card_block_bonus` below; scaling from zero here would hand
	# Rally a damage roll it does not have and an attack animation to go with it.
	if base > 0:
		base += card.per_card_played * cards_played_before()
		base += card.per_exhausted * projected_exhausted(card)
		if card.bonus_if_hand_empty > 0 and hand_empties(card):
			base += card.bonus_if_hand_empty
		# LAST, and only onto a swing that is actually happening: an empowered attack
		# spends the bonus, and a card that deals no damage must not eat it.
		base += next_attack_bonus
	return base

## Block this card actually grants, after Dexterity and anything it reads.
##
## `hand` still contains the card being played at this point (play_card erases it
## afterwards), so "other cards in hand" is one less than the hand.
func card_block_bonus(card: CardData) -> int:
	var bonus := 0
	if card.block_per_card_in_hand > 0:
		bonus += card.block_per_card_in_hand * maxi(0, hand.size() - 1)
	if card.combo_at > 0 and card.eff_block() > 0 and cards_played_before() + 1 >= card.combo_at:
		bonus += card.combo_bonus
	# D204. Thorns you are already wearing, converted — a thorns deck buying a guard
	# with what it has instead of paying for Block twice.
	if card.block_per_thorns > 0:
		bonus += card.block_per_thorns * player.thorns
	# ...and the block half of the three shared axes. Gated on the card having Block of
	# its own, which is the mirror of the `base > 0` gate in `card_base_damage`: between
	# them each axis is counted once, on whichever side the card actually pays out.
	if card.eff_block() > 0:
		bonus += card.per_card_played * cards_played_before()
		bonus += card.per_exhausted * projected_exhausted(card)
		if card.bonus_if_hand_empty > 0 and hand_empties(card):
			bonus += card.bonus_if_hand_empty
	return bonus

## What one hit actually leaves the player's hands as: Strength added, Weak applied.
## One point of outgoing damage, with the player's own modifiers and then any `damage_pct` relic.
##
## It exists because `card_damage` is the FACE and `_resolve` is the HIT, and they read the same
## base through two different call sites. The first version of `damage_pct` was applied in
## `card_damage` alone, so the card advertised a number it did not deal — D50's rule ("a card must
## not lie about itself") broken from the other direction, and invisible to every test that reads
## only the face. Percent last, so it multiplies the Strength and Vulnerable the fight has already
## worked out rather than the card's printed number.
func _outgoing(base: int) -> int:
	var d := player.outgoing_damage(base)
	var m := _mod_mult("damage_pct") * _conditional_damage_mult()
	if m != 1.0 and d > 0:
		d = maxi(1, int(round(float(d) * m)))
	return d

## The product of the conditional damage percents whose condition holds right now (D257).
##
## One function and not four branches at four call sites, for the reason `_outgoing` itself exists:
## the face and the hit read the same base through two paths, and a condition evaluated in only one
## of them is D50's lie in a new costume — the shape `damage_pct` shipped with and D233 had to fix.
##
## Evaluated per SWING, which is deliberate. A card that kills the second-to-last enemy on its first
## hit should swing harder on its second, and the face shows one swing with `x{hits}` beside it, so
## the two agree about what they are describing.
func _conditional_damage_mult() -> float:
	var m := 1.0
	var lone := _mod("lone_damage_pct")
	if lone > 0 and _living_enemies() == 1:
		m *= 1.0 + float(lone) / 100.0
	var wounded := _mod("wounded_damage_pct")
	if wounded > 0 and player.max_hp > 0 and player.hp * 2 < player.max_hp:
		m *= 1.0 + float(wounded) / 100.0
	var opener := _mod("opener_damage_pct")
	if opener > 0 and turn <= 1:
		m *= 1.0 + float(opener) / 100.0
	# The compounding one. `kills_this_combat` is a running count and not `enemies.size()` minus the
	# living, because a fight can start with a corpse in it after a resumed save.
	var per_kill := _mod("kill_damage_pct")
	if per_kill > 0 and kills_this_combat > 0:
		m *= 1.0 + float(per_kill) * float(kills_this_combat) / 100.0
	return m

func _living_enemies() -> int:
	var n := 0
	for e in enemies:
		if not e.is_dead():
			n += 1
	return n

func card_damage(card: CardData) -> int:
	return _outgoing(card_base_damage(card))

func card_block(card: CardData) -> int:
	if card.eff_block() <= 0 and card_block_bonus(card) <= 0:
		return 0
	var b := player.outgoing_block(card.eff_block() + card_block_bonus(card))
	var m := _mod_mult("block_pct")
	if m != 1.0 and b > 0:
		b = maxi(1, int(round(float(b) * m)))
	return b

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
		# `attacks_hit_all` (D233) makes a single-target attack spread. Read here rather than on
		# the card, because the card is shared data and a relic must not edit it — the same
		# reason `grows` is reset per fight.
		if card.aoe or _mod_flag("attacks_hit_all"):
			for e in enemies:
				if not e.is_dead():
					targets.append(e)
		elif foe != null:
			targets.append(foe)
		# `repeat_first_attack` (D233): the turn's first attack swings twice. Counted per TURN and
		# not per card, so a second attack in the same turn is not doubled — and tracked on the
		# engine rather than derived from `cards_played_this_turn`, because a skill played first
		# must not spend it.
		var swings := maxi(1, card.hits)
		if _mod_flag("repeat_first_attack") and not repeated_attack_this_turn:
			repeated_attack_this_turn = true
			swings *= 2
		var total := 0
		for tgt in targets:
			for h in swings:
				if tgt.is_dead():
					break
				var dealt := _outgoing(base_dmg)
				var landed: int = tgt.predicted_damage(dealt)
				# Damage the target could not absorb because it did not have the HP: what an
				# `overkill` errand asks you to waste. Measured before the hit, because
				# afterwards the difference between "killed it exactly" and "hit it for triple"
				# is gone — the corpse is at 0 either way.
				_t(Balance.TALLY_OVERKILL, maxi(0, landed - tgt.hp))
				total += landed
				tgt.take_damage(dealt)
		# Damage LANDED, not damage swung: what an enemy's block ate never reached it, and an
		# errand asking for 200 damage means 200 off their bars.
		_t(Balance.TALLY_DAMAGE, total)
		turn_damage += total
		_pk(Balance.TALLY_PEAK_TURN, turn_damage)
		if card.lifesteal and total > 0:
			var before_heal := player.hp
			player.hp = mini(player.max_hp, player.hp + total)
			_t(Balance.TALLY_HEAL, player.hp - before_heal)
			msg += "Drained %d. " % total
		# The relic's version (D257), beside the card's for the reason `energy_per_kill` sits beside
		# `energy_on_kill`: one mechanism, two authors. A percent of damage LANDED, so it rides every
		# `damage_pct` relic already held rather than being a flat heal bolted on beside them.
		var steal_pct := _mod("lifesteal_pct")
		if steal_pct > 0 and total > 0:
			var stolen := maxi(1, int(round(float(total) * float(steal_pct) / 100.0)))
			var pre_steal := player.hp
			player.hp = mini(player.max_hp, player.hp + stolen)
			_t(Balance.TALLY_HEAL, player.hp - pre_steal)
			msg += "Drained %d. " % (player.hp - pre_steal)
		if not targets.is_empty():
			# Reads the TARGET LIST rather than `card.aoe`, because `attacks_hit_all` makes a
			# single-target card hit everything and the sentence has to say what happened.
			var who: String = "all enemies" if targets.size() > 1 else String(targets[0].name)
			msg += "%s hits %s for %d%s. " % [
				card.name, who, total, (" x%d" % card.hits) if card.hits > 1 else ""]
		var killed := false
		for e in enemies:
			if e.is_dead():
				if not e.get_meta("counted_dead", false):
					e.set_meta("counted_dead", true)
					killed = true
					kills_this_combat += 1
					_t(Balance.TALLY_KILLS)
				msg += "%s dies! " % e.name
				var onkill := _fire_relics(RelicData.Trigger.ON_KILL)
				if onkill != "":
					msg += onkill + " "
		# a kill that pays for itself: this is what makes a swarm turn keep going
		if killed and card.energy_on_kill:
			energy += 1
			msg += "Energy +1. "
		# The relic's version (D234), beside the card's for the same reason `start_block` sits
		# beside a Block card: one mechanism, two authors.
		var per_kill := _mod("energy_per_kill")
		if killed and per_kill > 0:
			energy += per_kill
			msg += "Energy +%d. " % per_kill
		# D204: the empowered swing has landed, so the bonus is spent. HERE rather than
		# further down is what lets an attack empower the attack AFTER it without
		# empowering itself: this card's damage was computed at the top of the function,
		# this clears what it used, and the grant below then arms the next one.
		next_attack_bonus = 0
		retarget()

	if card.double_block:
		var extra := player.block
		player.gain_block(extra)
		_t(Balance.TALLY_BLOCK, extra)
		msg += "Block doubled to %d. " % player.block
	if card.eff_block() > 0 or card_block_bonus(card) > 0:
		var blk := card_block(card)
		player.gain_block(blk)
		_t(Balance.TALLY_BLOCK, blk)
		msg += "Block +%d. " % blk
	_pk(Balance.TALLY_PEAK_BLOCK, player.block)
	if card.eff_heal() > 0:
		var pre_heal := player.hp
		player.hp = mini(player.max_hp, player.hp + card.eff_heal())
		_t(Balance.TALLY_HEAL, player.hp - pre_heal)
		msg += "Healed %d. " % card.eff_heal()
	if card.energy_gain > 0:
		energy += card.energy_gain
		msg += "Energy +%d. " % card.energy_gain

	# --- statuses on the target (AoE spreads debuffs too) ---
	var debuff_targets: Array = []
	if card.aoe or _mod_flag("debuffs_spread"):
		for e in enemies:
			if not e.is_dead():
				debuff_targets.append(e)
	elif foe != null and not foe.is_dead():
		debuff_targets.append(foe)
	elif foe != null:
		debuff_targets.append(foe)
	# Counted PER TARGET, so an AoE debuff that lands on four enemies is four times the work —
	# which it is. The alternative (counting the card once) would make a status errand a
	# question about how many cards you own rather than about what you did to the floor.
	for tgt in debuff_targets:
		if card.eff_vulnerable() > 0:
			tgt.vulnerable += card.eff_vulnerable()
			_t(Balance.TALLY_VULN, card.eff_vulnerable())
		if card.eff_weak() > 0:
			tgt.weak += card.eff_weak()
			_t(Balance.TALLY_WEAK, card.eff_weak())
		if card.eff_poison() > 0:
			tgt.poison += card.eff_poison()
			_t(Balance.TALLY_POISON, card.eff_poison())
			_pk(Balance.TALLY_PEAK_POISON, tgt.poison)
	if card.eff_vulnerable() > 0:
		msg += "Vulnerable %d. " % card.eff_vulnerable()
	if card.eff_weak() > 0:
		msg += "Weak %d. " % card.eff_weak()
	if card.eff_poison() > 0:
		msg += "Poison %d. " % card.eff_poison()

	# --- self buffs ---
	if card.eff_strength() > 0:
		player.strength += card.eff_strength()
		_t(Balance.TALLY_STRENGTH, card.eff_strength())
		_pk(Balance.TALLY_PEAK_STRENGTH, player.strength)
		msg += "Strength +%d. " % card.eff_strength()
	if card.eff_dexterity() > 0:
		player.dexterity += card.eff_dexterity()
		_t(Balance.TALLY_DEX, card.eff_dexterity())
		msg += "Dexterity +%d. " % card.eff_dexterity()
	if card.eff_thorns() > 0:
		player.thorns += card.eff_thorns()
		_t(Balance.TALLY_THORNS, card.eff_thorns())
		msg += "Thorns +%d. " % card.eff_thorns()
	if card.retain_block:
		player.retain_block = true
		msg += "Block now persists between turns! "
	# --- D204 enablers: what this card leaves behind for the next one --------------
	#
	# After the damage block above has already spent whatever was standing, so a card
	# can be both halves of a combo — Whetted Edge swings for its own 5 and then arms
	# the +6 for the swing after it, rather than paying itself.
	if card.empower_next > 0:
		next_attack_bonus += card.empower_next
		msg += "Next Attack +%d. " % card.empower_next
	if card.discount_next > 0:
		next_card_discount += card.discount_next
		msg += "Next card costs %d less. " % card.discount_next
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
	# `block_heals_pct` (D257). HERE — after the snapshot, before the enemies act — because the Block
	# it pays on is the wall you finished your turn behind, not what survives being hit. Reading it
	# after `_resolve_enemy` would pay nothing on exactly the turns the wall did its job, which is
	# the opposite of what the relic says.
	var heal_pct := _mod("block_heals_pct")
	if heal_pct > 0 and player.block > 0:
		var mended := maxi(1, int(round(float(player.block) * float(heal_pct) / 100.0)))
		var pre_mend := player.hp
		player.hp = mini(player.max_hp, player.hp + mended)
		if player.hp > pre_mend:
			_t(Balance.TALLY_HEAL, player.hp - pre_mend)
			parts.append("Your guard mends %d." % (player.hp - pre_mend))
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
	# `debuffs_persist` (D234) stops the decay on the ENEMIES only. The player's own Vulnerable
	# and Weak still tick down: a relic that froze those would be a relic that makes the enemies
	# permanently better at hurting you, which is the opposite of what it says on the tin.
	var pdot := player.end_turn()
	if pdot > 0:
		parts.append("Poison deals %d to you." % pdot)
	for e in enemies:
		var held_v := e.vulnerable
		var held_w := e.weak
		var held_p := e.poison
		var edot := e.end_turn()
		if _mod_flag("debuffs_persist"):
			e.vulnerable = held_v
			e.weak = held_w
			# Poison still BITES — `end_turn` already took the damage above — it just does not
			# spend a stack. Restoring the pre-tick value is what "does not decay" means here.
			e.poison = held_p
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
			# `retaliate_pct` (D257), beside the Thorns status for the reason every relic rule sits
			# beside the card mechanic it mirrors. Taken off `landed` — what actually reached you —
			# so Block is a real answer to it and a turn spent walling is not also a turn dealing
			# damage. This is the one relic in the pool that gets STRONGER as enemies scale, which
			# is why it is here and not another flat percent.
			var retal := _mod("retaliate_pct")
			if retal > 0 and landed > 0:
				var back := maxi(1, int(round(float(landed) * float(retal) / 100.0)))
				e.take_damage(back)
				out += " It takes %d back." % back
			if player.thorns > 0:
				e.take_damage(player.thorns)
				out += " Thorns bite back for %d." % player.thorns
			if (retal > 0 or player.thorns > 0) and e.is_dead():
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
		# D204 combo state. Mid-turn, all of it: D22's whole point is that a fight going
		# badly cannot be rolled back, and a reload that quietly refunded a spent discount
		# or wiped an owed +6 would be a partial retry of the turn — the save scum this
		# file exists to remove, in miniature. `previous_card` rides as an id and is
		# re-found in the discard on the way back in; if the fight has moved it, the echo
		# target is honestly gone rather than guessed at.
		"next_attack_bonus": next_attack_bonus,
		"next_card_discount": next_card_discount,
		"previous_card": previous_card.id if previous_card != null else "",
		"exhausted_this_combat": exhausted_this_combat,
		"rules_fired": rules_fired,
		"relic_fired": relic_fired,
		"draw": _cards_to_state(draw_pile),
		"hand": _cards_to_state(hand),
		"discard": _cards_to_state(discard_pile),
		# The errand tally is fight state and outlives a quit (D203). A resumed fight that
		# started its counters again would quietly halve what the floor's errand was owed —
		# and silently, because the errand is judged at the stairs and never says whether it
		# is currently met. `taken` rides on the combatant's own save for the same reason.
		"tally": tally,
		"turn_damage": turn_damage,
		"played_attack": played_attack,
		"played_skill": played_skill,
		"fired_power": fired_power,
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
	next_attack_bonus = int(d.get("next_attack_bonus", 0))
	next_card_discount = int(d.get("next_card_discount", 0))
	exhausted_this_combat = int(d.get("exhausted_this_combat", 0))
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

	tally = {}
	for k in d.get("tally", {}):
		# Checked against the catalogue on the way in, the way the archetype above is: a
		# counter this build no longer has is dropped rather than carried as dead weight the
		# floor would then try to compare against.
		if String(k) in Balance.TALLIES:
			tally[String(k)] = maxi(0, int(d["tally"][k]))
	turn_damage = maxi(0, int(d.get("turn_damage", 0)))
	played_attack = bool(d.get("played_attack", false))
	played_skill = bool(d.get("played_skill", false))
	fired_power = bool(d.get("fired_power", false))

	draw_pile = _cards_from_state(d.get("draw", []), catalog)
	hand = _cards_from_state(d.get("hand", []), catalog)
	discard_pile = _cards_from_state(d.get("discard", []), catalog)

	# AFTER the piles, because the echo target is a card IN one of them and has to exist
	# before it can be pointed at. An id rather than a position: a discard pile is
	# reshuffled by any draw that empties the draw pile, so an index would come back
	# pointing at a different card, which is worse than coming back pointing at nothing.
	previous_card = null
	var prev_id := String(d.get("previous_card", ""))
	if prev_id != "":
		for c in discard_pile:
			if c.id == prev_id:
				previous_card = c
				break

## What this fight did, for the floor's errand (D203).
##
## The running counters plus the five facts that can only be known at the end. Built here
## rather than accumulated as the fight goes, because "won without playing an attack" is not a
## thing that happens at a moment — it is a property of the whole fight, and a flag set
## optimistically at turn one and cleared later is a flag that is wrong for most of the fight.
##
## `hurt` is read off the combatant's own counter for the same reason it lives there: the three
## early returns in `end_turn` are exactly the paths a before-and-after difference would miss.
func fight_tally() -> Dictionary:
	var out := tally.duplicate()
	out[Balance.TALLY_HURT] = player.taken
	if not won():
		return out
	out[Balance.TALLY_FIGHTS] = 1
	if player.taken == 0:
		out[Balance.TALLY_FLAWLESS] = 1
	if turn <= Balance.ERRAND_SWIFT_TURNS:
		out[Balance.TALLY_SWIFT] = 1
	if not played_attack:
		out[Balance.TALLY_NOATTACK] = 1
	if not played_skill:
		out[Balance.TALLY_NOSKILL] = 1
	# A run with no Power equipped wins every fight without firing one, and that is a real
	# thing the player chose at the deck builder rather than a loophole: the equipped slot is
	# a whole deckbuilding decision (D80), and leaving it empty costs throughput everywhere
	# else. `power_ratio` already prices it.
	if not fired_power:
		out[Balance.TALLY_NOPOWER] = 1
	return out

func won() -> bool:
	return living_enemies() == 0

func lost() -> bool:
	return player.is_dead()

func over() -> bool:
	return won() or lost()
