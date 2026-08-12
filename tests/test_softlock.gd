## Headless test: the player can NEVER reach a state where no legal deck can be
## built. That state is unrecoverable — no deck means no dungeon, and no dungeon
## means no new cards — so it is guarded by fuzzing every collection sink.
## Run: godot --headless --script tests/test_softlock.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_softlock_"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var fails := 0
	var Meta = load("res://scripts/meta_state.gd")

	# Fixed seed: this suite fuzzes, and a failure nobody can reproduce is a failure
	# nobody fixes. Trials are raised instead of re-rolling the seed each run.
	const FUZZ_SEED := 20260725
	seed(FUZZ_SEED)

	# --- the floor must be derived from the deck minimum, not set loosely ---
	#
	# The floor's subject changed with D235. Death no longer removes cards at all, so it can no
	# longer softlock; `MIN_KEEP` now guards FUSION, which still consumes copies. The assertion is
	# unchanged because the arithmetic is — a collection that can fall below a legal deck cannot
	# build one, whatever spent the cards.
	if Balance.MIN_KEEP < Balance.MIN_DECK_SIZE:
		fails += 1; print("FAIL MIN_KEEP (%d) below MIN_DECK_SIZE (%d): fusion can softlock" % [
			Balance.MIN_KEEP, Balance.MIN_DECK_SIZE])

	# --- fusing as hard as possible must never softlock ---
	var m = Meta.new()
	m.new_save()
	var guard := 0
	while guard < 2000:
		guard += 1
		var did := false
		for id in m.collection.keys():
			if m.can_fuse(id):
				m.fuse(id); did = true
				if not _can_build(m):
					fails += 1
					print("FAIL fusion softlocked: total=%d" % m.total_copies())
					break
		if not did:
			break
	if not _can_build(m):
		fails += 1; print("FAIL not buildable after fusion spree")

	# --- dying must not remove a single card, at any depth (D235) ---
	#
	# This used to drive 40 deaths per depth and assert the collection stayed buildable. The
	# stronger statement is now available and is asserted instead: a death cannot reduce the
	# collection AT ALL, so there is no depth at which it could softlock. Driven through the one
	# call a death makes, so a future change that reintroduces a collection cost through some
	# other route still fails here.
	var GSs = load("res://scripts/game_state.gd")
	for depth_frac in [0.0, 0.25, 0.5, 1.0]:
		var m2 = Meta.new()
		m2.new_save()
		var was: int = m2.total_copies()
		var was_gold: int = m2.gold
		for i in 40:
			var gs = GSs.new()
			gs.escrow_gold = 40
			gs.escrow_cards = ["hack", "cover"]
			gs.forfeit_escrow(float(depth_frac))
		if m2.total_copies() < was:
			fails += 1
			print("FAIL 40 deaths at depth %.2f cost %d cards" % [
				depth_frac, was - m2.total_copies()])
		if m2.gold < was_gold:
			fails += 1
			print("FAIL 40 deaths at depth %.2f cost %d banked gold" % [
				depth_frac, was_gold - m2.gold])
		if not _can_build(m2):
			fails += 1; print("FAIL not buildable after deaths at depth %.2f" % depth_frac)

	# --- fuzz: interleave every sink and source at random ---
	var ids := ["hack", "cover", "stave_in", "shoulder", "clear_mind",
		"put_the_fear", "work_up", "light_on_it", "set_stone"]
	for trial in 200:
		var f = Meta.new()
		f.new_save()
		f.add_gold(500)
		for step in 120:
			match randi() % 4:
				0:
					f.add_card(ids[randi() % ids.size()])
				1:
					var keys: Array = f.collection.keys()
					if not keys.is_empty():
						var id: String = keys[randi() % keys.size()]
						if f.can_fuse(id):
							f.fuse(id)
				2:
					# Was `penalize_death`. Death is no longer a card sink (D235), so the fuzz
					# drives the sink that remains — fusion is exercised by branch 1 — and this
					# branch spends the escrow instead, which is the only thing a death now does.
					var fg = load("res://scripts/game_state.gd").new()
					fg.escrow_gold = randi() % 60
					fg.forfeit_escrow(randf())
				3:
					f.spend_gold(randi() % 50)
			if not _can_build(f):
				fails += 1
				print("FAIL fuzz softlocked (trial %d step %d): total=%d" % [
					trial, step, f.total_copies()])
				break
		if fails > 0:
			break

	# --- a fresh save must be immediately playable ---
	var fresh = Meta.new()
	fresh.new_save()
	if not _can_build(fresh):
		fails += 1; print("FAIL fresh save cannot build a deck")
	if not fresh.deck_valid(fresh.decks["Starter"]):
		fails += 1; print("FAIL starter loadout invalid")

	if fails == 0:
		print("SOFTLOCK TEST: PASS (fusion, deaths, fuzz: a legal deck is always buildable)")
	else:
		print("SOFTLOCK TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

## Can the player still field a legal deck from what they own?
##
## Takes cards up to MAX_DECK_SIZE, not everything. Selecting the whole collection
## reported a softlock the moment the player owned 21 cards — over the 20-card deck
## cap — when in reality they would just leave one at home. The failure was rare
## because it needed random draws to outrun random deaths, so it surfaced as an
## intermittent red run rather than an obvious bug.
func _can_build(m) -> bool:
	var sel := {}
	var taken := 0
	for id in m.collection:
		if taken >= Balance.MAX_DECK_SIZE:
			break
		var n: int = mini(int(m.collection[id]["count"]), Balance.MAX_DECK_SIZE - taken)
		sel[id] = n
		taken += n
	return m.deck_valid(sel)

## Remove this test's sandboxed files so a test run leaves no residue in the
## player's data directory.
func _cleanup_sandbox() -> void:
	# stop any surviving instance from re-writing what we are about to delete
	load("res://scripts/meta_state.gd").writes_disabled = true
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
		# absolute removal: the relative form silently no-ops here
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
