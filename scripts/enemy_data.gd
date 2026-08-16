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

## How TALL this creature is, as a multiple of the hero (D320).
##
## The crawl draws the hero and the thing hunting her on the same floor, so the only useful
## unit for a creature's size is the hero herself. 1.0 is a person: a skeleton, a cultist, a
## thrall. A rat is 0.3, a hound about 0.6, an ogre 1.25, and the thing at the bottom of the
## Abyssal Stair is 1.6.
##
## BOTH screens read it (D323). The battle screen has no hero on it, so 1.0 there is the
## height an ordinary person is drawn at — the same claim, measured against a figure the
## player remembers rather than one standing beside it. One number, so a creature cannot be
## a rat in the corridor and a person in the fight it starts.
##
## It is the CREATURE and never a correction to a painting. Two iso files are busts cut at
## the thigh, and D320 hid that in here as a stature of 0.78; the moment a second screen
## read the number it drew an iron giant four fifths of a person tall. The crop belongs to
## the file that has it, and it lives in `Balance.ISO_CROP`.
##
## Stated per archetype because there is nowhere else it can be read from. It was inferred
## from `count_max` and `hp_mult` before, through `Balance.iso_family`, and those answer
## "how does this fight behave", which is a different question with the same shape: the
## Ossuary Wretch comes in threes, so it was a `swarm`, so it was drawn at knee height — a
## human skeleton the size of a rat. **A creature's size is not a function of its stats and
## cannot be derived from them.**
##
## The default is a PERSON, so an archetype whose line nobody wrote is hero-sized rather
## than vermin-sized. Wrong by a head reads as a stylistic choice; wrong by a factor of
## three reads as a bug, which is what the report that started this said.
@export var stature: float = 1.0

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

@export_group("Signature (bosses only)")
## The one thing this boss does that no number can say (D295).
##
## Every verb in `Action` above is a QUANTITY — hit harder, shield, weaken, drain. A fight built
## out of them is the same fight at a different size, which is why twelve named bosses read as
## twelve big cultists. What makes a Hearthstone boss memorable is that it breaks a rule of the
## card game itself, so the deck that beat the last one is the wrong deck here.
##
## Each field below bends one rule the card game otherwise guarantees, and each has exactly one
## seam in `CombatEngine` — the same discipline `RelicData`'s rule modifiers keep, pointing the
## other way. **A boss carries exactly one**, enforced by `tests/test_signature.gd`: two would be
## a difficulty setting wearing a rule's clothes, and the player could not name what went wrong.
##
## Zero means "unset" on every one of them, which is why `block_worth_pct` is 0-for-100 rather
## than 100-for-100: a default of 100 in a `.tres` would be indistinguishable from an author
## deliberately setting it, and a signature nobody chose is the one thing this group must not be
## able to grow by accident.
##
## **Three of the first eight were built, measured and deleted, and they failed the same way.**
## `sig_card_tax` (+N to every card), `sig_energy_tax` (-N Energy a turn) and `sig_draw_tax`
## (-N cards a turn) all SUBTRACT FROM A PER-TURN RESOURCE, and at this game's scale the
## smallest step each can take is a large fraction of the whole engine: one of three Energy,
## one of five cards drawn, or — worst — one Energy on every card in a three-Energy turn.
## Measured against the repaired boss column: the card tax took the Ember Road from 87% to 0%,
## the draw tax took the CRYPT, the tutorial dungeon, from 85% to 19%, and the energy tax took
## the Drowned Market from 87% to 0%. There was no gentler setting to retreat to in any of the
## three, because each one's minimum useful value was already the cliff.
##
## What survives are the rules that can be DIALLED — a ceiling or a percentage, where the next
## value along is a small step rather than a different game. **A knob whose smallest step is a
## cliff is not a knob**, and that is the property to test a new signature against before
## authoring it, not the fiction.
##
## The original note, kept because it is the case that found the rule: at
## `MAX_ENERGY` 3 the smallest step an integer cost can take is +1, and +1 on every card is a
## turn of one card where there were three. Measured, +1 took the Ember Road from **87% to 0%**
## and +2 took the Drowned Market from 40% to 0%. There was no gentler setting to retreat to,
## because the field's minimum useful value already cost two thirds of a turn. **A knob whose
## smallest step is a cliff is not a knob**, and the two bosses that wore it took rules that can
## be dialled instead.
##
## Non-bosses author none. That is not a style rule — `count_max` above lets an archetype spawn
## three of itself, and three copies each taking an Energy is not a signature, it is a softlock.
## Hand size ceiling while this fight lasts. Bites the draw builds hardest, which are the
## strongest in the game (D280's table: Draw at 11.53x against Barricade at 1.30x).
##
## **Never below `Balance.HAND_SIZE`, and that is a rule rather than a preference.** At or above
## the opening draw a cap only takes cards the player was HOLDING, which is a ceiling on hoarding
## and dials smoothly: 6 measured about -10 points of boss win rate and 7 rather less. One below
## it starts eating the base draw itself, and the curve breaks — 4 cost the Draw build **61
## points** at the Sunken Vault and averaged -12.9 across its cells. That is not a harder ceiling,
## it is `sig_draw_tax` wearing a ceiling's clothes, and `sig_draw_tax` was deleted for being a
## cliff. `tests/test_signature.gd` fails a cap under `HAND_SIZE`.
@export var sig_hand_cap: int = 0
## Most cards that may be played in one turn.
@export var sig_cards_per_turn: int = 0
## What your Block is worth here, as a percent. D45 says block cannot be a complete answer at
## depth, and until now the only thing saying so was piercing damage.
@export var sig_block_worth_pct: int = 0
## The FIRST card you play each turn leaves the fight for good. Turns the fight into a race
## against your own deck rather than against the boss's HP bar.
##
## "First each turn" and not "every card", which is what this was first written as and what the
## arithmetic threw out. A boss runs 12 turns (`TIER_TARGET_TURNS`) and a run deck is 12 to 20
## cards, so exhausting everything played empties the deck around turn four and the remaining
## eight turns are the player watching. **A rule that ends the fight for you is a lose condition
## wearing a puzzle's clothes.** One a turn costs the same 12 cards over the whole fight while
## leaving two or three a turn to play with, which is a race the player is in rather than a
## countdown they are subject to.
@export var sig_exhaust_first: bool = false

## Field names of the signature group, discovered from the property list rather than written out.
##
## D250's lesson, and D89's before it: a hand-kept list of what a resource contains is a list that
## goes stale the moment a field is added, and the failure is silent — a new signature would be
## authored, honoured nowhere, and pass every test. Everything that asks "which signatures exist"
## asks here: `signature_of`, `signature_text`, and the suite that checks each one is read.
static func signature_fields() -> Array[String]:
	var out: Array[String] = []
	for p in EnemyData.new().get_property_list():
		var n := String(p["name"])
		if n.begins_with("sig_"):
			out.append(n)
	return out

## Which signature this archetype carries, and at what size: `["sig_energy_tax", 1]`, or `[]` for
## none. The pair rather than the name alone, because every caller that wants one wants the other.
func signature_of() -> Array:
	for f in signature_fields():
		var v = get(f)
		if v is bool:
			if v:
				return [f, 1]
		elif int(v) != 0:
			return [f, int(v)]
	return []

## What the signature does, in the words the player is shown before committing (D41, D187).
##
## Written HERE and not in `Balance.boss_warning`, because the rule and the sentence about it have
## to move together — a boss line generated from a field the sentence does not know about is the
## D50 lie, and the whole value of naming a boss in advance is that the naming is true.
func signature_text() -> String:
	var s := signature_of()
	if s.is_empty():
		return ""
	var n: int = int(s[1])
	match String(s[0]):
		"sig_hand_cap":
			return "your hand cannot hold more than %d cards" % n
		"sig_cards_per_turn":
			return "you may play only %d cards a turn" % n
		"sig_block_worth_pct":
			return "your Block is worth %d%% here" % n
		"sig_exhaust_first":
			return "the first card you play each turn is gone for good"
	return ""

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
