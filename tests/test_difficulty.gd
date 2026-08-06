## Headless test: the chosen difficulty rung (D175).
##
## The rung multiplies the same two enemy numbers ascension does, is stored per SAVE,
## and is deliberately invisible to the reward side. Each of those three is a claim
## something can break silently, so each gets an assertion:
##
##   * the ladder is ordered, and the legacy rung is EXACTLY 1.0/1.0 — the migration
##     promises an existing save plays the game it was playing, and that promise is
##     only kept if that rung is a true no-op;
##   * a rung reaches enemy stats, and reaches them through `Balance` rather than
##     through a second hook the simulator would not see;
##   * a rung changes NO reward. This is the one the feature would most plausibly
##     grow by accident: ascension sweetens loot two functions away, and a difficulty
##     that paid better would stop being a preference and become a grind nobody opted
##     into. It is asserted over every rung and every tier, not spot-checked.
##
## Run: godot --headless --script tests/test_difficulty.gd
extends SceneTree

const SANDBOX := "t_test_difficulty_"

func _init() -> void:
	var Meta = load("res://scripts/meta_state.gd")
	Meta.path_prefix = SANDBOX
	_cleanup_sandbox()
	Meta.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"

	var fails := 0
	var restore := Balance.difficulty

	fails += _test_table()
	fails += _test_scaling()
	fails += _test_rewards_untouched()
	fails += _test_persistence(Meta)
	fails += _test_migration(Meta)
	fails += _test_offered_and_read()

	Balance.difficulty = restore
	Balance.hp_mult_override = NAN
	Balance.dmg_mult_override = NAN
	if fails == 0:
		print("DIFFICULTY TEST: PASS (ladder ordered, legacy is a no-op, scaling reached, rewards untouched, per-save, migrated, offered+read)")
	else:
		print("DIFFICULTY TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit(1 if fails > 0 else 0)

## The ladder itself: ordered, named, and anchored at a true no-op.
func _test_table() -> int:
	var fails := 0
	var n: int = Balance.DIFFICULTIES.size()
	if n < 2:
		fails += 1; print("FAIL a difficulty CHOICE needs at least two rungs; found %d" % n)

	# The legacy rung must be exactly 1.0/1.0. Not "close to" — `_migrate` puts every
	# pre-D175 save here and tells the player nothing changed, so anything but 1.0 makes
	# that a lie, and a lie of a few percent is the hardest kind to ever notice.
	if Balance.difficulty_hp_mult(Balance.DIFFICULTY_LEGACY) != 1.0 \
			or Balance.difficulty_dmg_mult(Balance.DIFFICULTY_LEGACY) != 1.0 \
			or Balance.difficulty_ratio_mult(Balance.DIFFICULTY_LEGACY) != 1.0:
		fails += 1
		print("FAIL the legacy rung is not a no-op: hp x%.3f dmg x%.3f ratio x%.3f — every migrated save silently changes difficulty" % [
			Balance.difficulty_hp_mult(Balance.DIFFICULTY_LEGACY),
			Balance.difficulty_dmg_mult(Balance.DIFFICULTY_LEGACY),
			Balance.difficulty_ratio_mult(Balance.DIFFICULTY_LEGACY)])

	if Balance.DIFFICULTY_DEFAULT < 0 or Balance.DIFFICULTY_DEFAULT >= n:
		fails += 1; print("FAIL DIFFICULTY_DEFAULT %d is not a rung" % Balance.DIFFICULTY_DEFAULT)

	# Monotone, and strictly increasing SOMEWHERE on every step: two rungs that scale
	# identically are two names for one difficulty, which is a menu that lies about
	# how many choices it offers.
	for i in range(1, n):
		var hp0 := Balance.difficulty_hp_mult(i - 1)
		var hp1 := Balance.difficulty_hp_mult(i)
		var dm0 := Balance.difficulty_dmg_mult(i - 1)
		var dm1 := Balance.difficulty_dmg_mult(i)
		if hp1 < hp0 or dm1 < dm0:
			fails += 1
			print("FAIL rung %s is not harder than %s (hp %.2f->%.2f, dmg %.2f->%.2f)" % [
				Balance.difficulty_name(i), Balance.difficulty_name(i - 1), hp0, hp1, dm0, dm1])
		var rt0 := Balance.difficulty_ratio_mult(i - 1)
		var rt1 := Balance.difficulty_ratio_mult(i)
		if rt1 < rt0:
			fails += 1
			print("FAIL rung %s answers the deck less sharply than %s (ratio %.2f -> %.2f)" % [
				Balance.difficulty_name(i), Balance.difficulty_name(i - 1), rt0, rt1])
		if is_equal_approx(hp0, hp1) and is_equal_approx(dm0, dm1) and is_equal_approx(rt0, rt1):
			fails += 1
			print("FAIL rungs %s and %s scale identically — one of them is decoration" % [
				Balance.difficulty_name(i - 1), Balance.difficulty_name(i)])

	# Every rung needs a name and a blurb: the Settings row prints both, and an empty
	# one reads as a bug rather than as a rung.
	for i in n:
		var row: Dictionary = Balance.difficulty_row(i)
		if String(row.get("name", "")).strip_edges() == "" \
				or String(row.get("blurb", "")).strip_edges() == "":
			fails += 1; print("FAIL rung %d has no name or no blurb" % i)
	return fails

## A rung must reach the two enemy numbers, and reach them by the amount it claims.
func _test_scaling() -> int:
	var fails := 0
	var n: int = Balance.DIFFICULTIES.size()
	Balance.ascension = 0
	for d in [1, 4, 8]:
		for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
			Balance.difficulty = Balance.DIFFICULTY_LEGACY
			var base_hp := Balance.enemy_max_hp(d, tier, 4.0)
			var base_dm := Balance.enemy_damage(d, tier, 4.0, 1)
			for i in range(1, n):
				Balance.difficulty = i
				var hp := Balance.enemy_max_hp(d, tier, 4.0)
				var dm := Balance.enemy_damage(d, tier, 4.0, 1)
				# HP is the flat multiplier and nothing else. Asserted exactly (to
				# rounding) because the `ratio` knob must NOT reach enemy HP: more HP
				# means longer fights, and longer fights are the mechanism behind the
				# depth inversion at d7/d8. A rung must not buy danger that way.
				var want_hp := float(base_hp) * Balance.difficulty_hp_mult(i)
				if absf(float(hp) - want_hp) > 1.5:
					fails += 1
					print("FAIL rung %s at d%d tier %d: enemy HP %d, expected ~%.0f — the ratio knob has reached enemy HP" % [
						Balance.difficulty_name(i), d, tier, hp, want_hp])
				# Damage carries both knobs, so the assertion is a FLOOR rather than an
				# equality: at least the flat part, and never less than the rung below.
				if float(dm) < float(base_dm) * Balance.difficulty_dmg_mult(i) - 1.5:
					fails += 1
					print("FAIL rung %s at d%d tier %d: enemy damage %d is under its own flat multiplier" % [
						Balance.difficulty_name(i), d, tier, dm, ])
	# and the hardest rung must actually be felt somewhere: equal-after-rounding at
	# every depth would pass the per-cell checks above and still be a dead control.
	Balance.difficulty = Balance.DIFFICULTY_LEGACY
	var soft := Balance.enemy_damage(4, Balance.Tier.BOSS, 4.0, 1)
	Balance.difficulty = n - 1
	var hard := Balance.enemy_damage(4, Balance.Tier.BOSS, 4.0, 1)
	if hard <= soft:
		fails += 1
		print("FAIL the top rung does not hit harder than the bottom one (%d vs %d)" % [hard, soft])
	Balance.difficulty = Balance.DIFFICULTY_LEGACY
	fails += _test_lands_on_the_strong()
	return fails

## The property the whole design rests on, and the reason the first attempt was thrown
## away: a rung must cost a BUILT deck more than a starting one.
##
## The flat version measured the opposite. At enemy damage x1.50 the tutorial Crypt fell
## from 99% to 34% and the Ossuary from 69% to 1%, while Barricade at the Warrens and
## Late at the Drowned Market both stayed at 100%. That is a difficulty setting that
## punishes the player who has nothing and leaves the walkovers untouched — the exact
## inverse of its job. Nothing in the suite could see it, because every assertion asked
## whether the numbers went UP.
##
## So the shape gets pinned, not just the direction: the relative cost of a rung, at a
## fixed depth, must be strictly larger for a strong deck than for a starter one.
func _test_lands_on_the_strong() -> int:
	var fails := 0
	var top: int = Balance.DIFFICULTIES.size() - 1
	# A depth whose ceiling is high enough that both ratios are actually answered —
	# at d1 the ratchet clamps everything and the question is meaningless.
	const DEPTH := 6
	const STARTER_RATIO := 1.06    # measured: the fresh-save profile in sim_balance
	const BUILT_RATIO := 15.1      # measured: the Late profile
	## How much harder a rung must land on a built deck than on a starting one.
	const MIN_LEAN := 1.10

	Balance.difficulty = Balance.DIFFICULTY_LEGACY
	var starter0 := float(Balance.enemy_damage(DEPTH, Balance.Tier.NORMAL, STARTER_RATIO, 1))
	var built0 := float(Balance.enemy_damage(DEPTH, Balance.Tier.NORMAL, BUILT_RATIO, 1))
	for i in range(1, top + 1):
		Balance.difficulty = i
		var starter := float(Balance.enemy_damage(DEPTH, Balance.Tier.NORMAL, STARTER_RATIO, 1))
		var built := float(Balance.enemy_damage(DEPTH, Balance.Tier.NORMAL, BUILT_RATIO, 1))
		var starter_cost := starter / maxf(1.0, starter0)
		var built_cost := built / maxf(1.0, built0)
		# A MARGIN, not just an inequality, and the margin is what makes this assertion
		# real. Checked against the design it exists to reject: the flat version scored
		# starter x1.500 / built x1.545 — it passes a bare `built > starter` by 3%, on
		# nothing but the ratio term already in `enemy_damage`. The shipped shape scores
		# x1.250 / x1.455, a 16% gap. 1.10 sits between them with room on both sides.
		if built_cost < starter_cost * MIN_LEAN:
			fails += 1
			print("FAIL rung %s lands almost as hard on a starter deck as on a built one (x%.3f vs x%.3f, needs x%.2f) — that is a flat multiplier wearing a curve's clothes: it walls the opening and leaves the walkovers standing" % [
				Balance.difficulty_name(i), starter_cost, built_cost, starter_cost * MIN_LEAN])
	Balance.difficulty = Balance.DIFFICULTY_LEGACY
	return fails

## The promise that makes this a preference and not a ladder: no rung pays better.
##
## Checked across every reward surface the run touches, because "difficulty does not
## change loot" is the kind of claim that stays true until somebody adds one line to
## the wrong function — which is exactly how ascension's loot tilt got there, correctly,
## two functions away from the thing this multiplies.
func _test_rewards_untouched() -> int:
	var fails := 0
	Balance.ascension = 0
	var n: int = Balance.DIFFICULTIES.size()
	for d in [1, 4, 8]:
		for tier in [Balance.Tier.NORMAL, Balance.Tier.ELITE, Balance.Tier.BOSS]:
			Balance.difficulty = Balance.DIFFICULTY_LEGACY
			var w0: Array = Balance.reward_weights(tier, d)
			var g0 := Balance.gold_reward(d, tier, 3)
			for i in range(1, n):
				Balance.difficulty = i
				var w: Array = Balance.reward_weights(tier, d)
				var g := Balance.gold_reward(d, tier, 3)
				if str(w) != str(w0):
					fails += 1
					print("FAIL rung %s changes reward rarity at d%d tier %d (%s vs %s) — a difficulty that pays better is a grind, not a preference" % [
						Balance.difficulty_name(i), d, tier, str(w), str(w0)])
				if g != g0:
					fails += 1
					print("FAIL rung %s changes gold at d%d tier %d (%d vs %d)" % [
						Balance.difficulty_name(i), d, tier, g, g0])
	Balance.difficulty = Balance.DIFFICULTY_LEGACY
	return fails

## Per SAVE: it round-trips, it reaches the static, and two slots disagree.
func _test_persistence(Meta) -> int:
	var fails := 0
	var top: int = Balance.DIFFICULTIES.size() - 1

	var a = Meta.new()
	a.slot = 0
	a.new_save()
	if a.difficulty != Balance.DIFFICULTY_DEFAULT:
		fails += 1; print("FAIL a new save does not start on the shipped rung")
	a.difficulty = top
	a.save_game()

	Balance.difficulty = Balance.DIFFICULTY_LEGACY   # so the load has to do the work
	var a2 = Meta.new()
	a2.slot = 0
	if not a2.load_game():
		fails += 1; print("FAIL the save did not load")
	if a2.difficulty != top:
		fails += 1; print("FAIL difficulty not persisted (%d, wanted %d)" % [a2.difficulty, top])
	if Balance.difficulty != top:
		fails += 1; print("FAIL loading a save did not apply its difficulty to scaling")
	if not a2.loaded:
		fails += 1; print("FAIL a loaded save does not report itself loaded")

	# Two slots must be able to disagree — that is the whole reason this is not in
	# SettingsState, so it is the thing worth proving rather than assuming.
	var b = Meta.new()
	b.slot = 1
	b.new_save()
	if b.difficulty != Balance.DIFFICULTY_DEFAULT:
		fails += 1; print("FAIL a second slot inherited the first slot's rung")
	b.save_game()
	var a3 = Meta.new()
	a3.slot = 0
	a3.load_game()
	if a3.difficulty != top:
		fails += 1; print("FAIL writing slot 1 changed slot 0's difficulty")
	return fails

## A save from before the feature must land on the rung that plays the same game.
func _test_migration(Meta) -> int:
	var fails := 0
	var m = Meta.new()
	m.slot = 2
	# A v8 save: everything the loader needs, and no "difficulty" key, because that
	# is precisely the shape this migration exists for.
	var old := {
		"version": 8, "collection": {"hack": {"count": 6, "level": 2}},
		"relics": ["iron_heart"], "gold": 120, "cleared_dungeons": ["crypt"],
		"decks": {"Starter": {"hack": 4}}, "consumables": {"escape_rope": 2},
		"starter_kit": "blade", "ascension": 0, "highest_dungeon": 3,
	}
	var f := FileAccess.open(Meta.path_for(2), FileAccess.WRITE)
	if f == null:
		print("FAIL could not write the v8 fixture"); return 1
	f.store_string(JSON.stringify(old))
	f.close()

	Balance.difficulty = Balance.DIFFICULTIES.size() - 1   # a wrong value to overwrite
	if not m.load_game():
		fails += 1; print("FAIL a v8 save no longer loads"); return fails
	if m.difficulty != Balance.DIFFICULTY_LEGACY:
		fails += 1
		print("FAIL a pre-D175 save migrated onto rung %d (%s), not the legacy rung — an existing player's game got harder because they opened it" % [
			m.difficulty, Balance.difficulty_name(m.difficulty)])
	if Balance.difficulty != Balance.DIFFICULTY_LEGACY:
		fails += 1; print("FAIL migration did not reach the scaling static")
	if m.gold != 120 or m.owned("hack") != 6:
		fails += 1; print("FAIL the v8 migration lost data")
	return fails

## The D130 rule, applied to a control that is NOT in SettingsState.
##
## `test_flow.gd` asserts every setting the menu offers is read by something, over a
## hand-kept list of keys and a hand-kept list of readers — which is the shape AGENTS
## warns about, and it is why this control needs its own check rather than an entry on
## that list. A difficulty selector that the game never consults is the worst possible
## version of a dead control: the player believes they chose something.
func _test_offered_and_read() -> int:
	var fails := 0
	var menu := _read("res://scripts/settings_menu.gd")
	if menu.find("difficulty") == -1:
		fails += 1; print("FAIL the Settings screen no longer offers difficulty")
	# offered AND stored AND consumed by scaling — all three, because any one of them
	# missing leaves a control that appears to work.
	if _read("res://scripts/meta_state.gd").find("difficulty") == -1:
		fails += 1; print("FAIL nothing persists the chosen difficulty")
	var bal := _read("res://scripts/balance.gd")
	if bal.find("difficulty_hp_mult()") == -1 or bal.find("difficulty_dmg_mult()") == -1:
		fails += 1
		print("FAIL enemy scaling does not read the difficulty multipliers — the setting is offered and ignored")
	# the run must be able to refuse a mid-run change, or the rung is a retry button
	if menu.find("in_run") == -1:
		fails += 1; print("FAIL the difficulty row does not lock during a run")
	return fails

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

func _cleanup_sandbox() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
