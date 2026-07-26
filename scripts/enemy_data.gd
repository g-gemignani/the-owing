## Enemy archetype. Data-only Resource, one .tres per archetype — same approach as
## cards, so adding an enemy is a data file plus a catalog entry, not code.
##
## `hp_mult` / `dmg_mult` scale the tier's budget rather than setting absolute
## numbers, so archetypes stay balanced automatically when Balance is retuned.
class_name EnemyData
extends Resource

## What an enemy does on a given turn. The pattern cycles, and the upcoming
## action is shown to the player as intent — telegraphing is what makes combat
## a decision instead of a dice roll.
## New verbs are appended, never inserted: `pattern` in every .tres stores these
## as raw ints, so renumbering would silently rewrite every enemy in the game.
enum Action { ATTACK, DEBUFF_VULN, DEBUFF_WEAK, DEFEND, EMPOWER, SUNDER, ENRAGE, DRAIN }

## When a conditional rule fires. Rules are checked in order and the FIRST match
## replaces the patterned action for that turn.
##
## Enemies used to be clockwork: `pattern[turn % n]`, blind to the player's HP, the
## player's Block, their own HP and everything else. Every fight was solvable once
## and then repeated forever. Conditions are what make an encounter a conversation.
enum Trigger {
	SELF_HP_BELOW_PCT,      ## its own HP has dropped below threshold%
	PLAYER_BLOCK_ABOVE,     ## the player soaked at least this much Block last turn
	PLAYER_HP_BELOW_PCT,    ## the player is below threshold% and it goes for the kill
	CARDS_PLAYED_ABOVE,     ## the player emptied their hand last turn
	EVERY_N_TURNS,          ## a drumbeat: every threshold-th turn
}

@export var id: String = "cultist"
@export var name: String = "Cultist"
## Share of the encounter's HP / damage budget (1.0 = the whole tier budget).
## Keep these within roughly +/-20%: they multiply an already-tuned budget, and
## larger deviations let a dungeon's ROSTER swamp its difficulty rating (a roster
## of 1.35x hitters made a difficulty-3 dungeon harder than difficulty 6).
@export var hp_mult: float = 1.0
@export var dmg_mult: float = 1.0
## How many of this archetype can appear together.
## A group archetype should NOT also apply debuffs: several copies stacking
## Vulnerable or Weak every turn compounds into a permanent multiplier and swamps
## the dungeon's difficulty rating. Keep debuffs on single-spawn archetypes.
@export var count_min: int = 1
@export var count_max: int = 1
## Cycling action pattern (values from Action).
@export var pattern: PackedInt32Array = PackedInt32Array([0])
## Magnitudes for non-attack actions.
@export var debuff_stacks: int = 1
@export var block_amount: int = 6
@export var strength_gain: int = 2

@export_group("Conditional behaviour")
## Rules belong on SINGLE-spawn archetypes only. Three copies of an enemy that
## empowers itself on a drumbeat compound into a difficulty the dungeon rating
## knows nothing about — the same trap already documented above for debuffs, which
## a rat swarm walked straight into. tests/test_reactive.gd enforces this.
## Parallel arrays, one entry per rule. Parallel rather than an array of sub-
## resources so a rule is authored as four numbers in a .tres instead of a nested
## resource per rule — and so the whole table is trivially inspectable in a test.
@export var rule_trigger: PackedInt32Array = PackedInt32Array()
@export var rule_threshold: PackedInt32Array = PackedInt32Array()
@export var rule_action: PackedInt32Array = PackedInt32Array()
## Magnitude for the rule's action. 0 means "use this archetype's normal value".
@export var rule_value: PackedInt32Array = PackedInt32Array()
## 1 = fires at most once per fight (an enrage should not re-trigger every turn).
@export var rule_once: PackedInt32Array = PackedInt32Array()

func rule_count() -> int:
	return mini(rule_trigger.size(), mini(rule_action.size(), rule_threshold.size()))

func _rule_field(a: PackedInt32Array, i: int, fallback: int) -> int:
	return a[i] if i < a.size() else fallback

## Which rule (if any) applies this turn. Returns the rule index, or -1 for none.
##
## `ctx` carries the state the rules read; `fired` holds indices of once-only rules
## already spent this fight. Evaluated at INTENT time and stored, so the telegraph
## the player sees is the action that actually resolves — a reactive enemy whose
## displayed intent could still change would be a liar, not a puzzle.
func rule_for(turn: int, ctx: Dictionary, fired: Array) -> int:
	for i in rule_count():
		if _rule_field(rule_once, i, 0) == 1 and i in fired:
			continue
		var threshold: int = rule_threshold[i]
		var hit := false
		match rule_trigger[i]:
			Trigger.SELF_HP_BELOW_PCT:
				var mx: float = maxf(1.0, float(ctx.get("self_max_hp", 1)))
				hit = float(ctx.get("self_hp", 0)) * 100.0 / mx < float(threshold)
			Trigger.PLAYER_BLOCK_ABOVE:
				hit = int(ctx.get("player_block_last_turn", 0)) >= threshold
			Trigger.PLAYER_HP_BELOW_PCT:
				var pmx: float = maxf(1.0, float(ctx.get("player_max_hp", 1)))
				hit = float(ctx.get("player_hp", 0)) * 100.0 / pmx < float(threshold)
			Trigger.CARDS_PLAYED_ABOVE:
				hit = int(ctx.get("cards_played_last_turn", 0)) >= threshold
			Trigger.EVERY_N_TURNS:
				hit = threshold > 0 and turn % threshold == 0
		if hit:
			return i
	return -1

func action_for_turn(turn: int) -> int:
	if pattern.is_empty():
		return Action.ATTACK
	return pattern[maxi(0, turn - 1) % pattern.size()]

## Fraction of pattern turns spent attacking. The engine divides the damage
## budget by this so a pattern changes the *texture* of a fight (when hits land,
## what else happens) without quietly lowering total damage output — otherwise
## every archetype with a utility turn would be a stealth difficulty nerf.
func attack_frequency() -> float:
	if pattern.is_empty():
		return 1.0
	var attacks := 0
	for a in pattern:
		if a == Action.ATTACK:
			attacks += 1
	if attacks == 0:
		return 1.0
	return float(attacks) / float(pattern.size())

## Multiplier applied to per-hit damage to offset utility turns.
##
## Deliberately only a PARTIAL offset (sqrt, not 1/f). A Vulnerable or Empower
## turn is not lost damage — it is deferred and amplified damage — so fully
## compensating for it double-counts and makes every utility archetype brutal.
func damage_compensation() -> float:
	return sqrt(1.0 / maxf(0.25, attack_frequency()))

func spawn_count() -> int:
	if count_max <= count_min:
		return maxi(1, count_min)
	return count_min + randi() % (count_max - count_min + 1)
