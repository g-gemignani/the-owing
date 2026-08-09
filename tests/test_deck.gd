## Headless test: deck loadouts (D4) — validation, clamping, build, persistence.
## Run: godot --headless --script tests/test_deck.gd
extends SceneTree

## Every user:// file this suite may create begins with this. The teardown below
## deletes by it rather than by "t_", which would delete the live save of every
## other suite running at the same time.
const SANDBOX := "t_test_deck_"

func _init() -> void:
	# sandbox: tests must never write over the player's real save or settings
	var Meta_ = load("res://scripts/meta_state.gd")
	Meta_.path_prefix = SANDBOX
	_cleanup_sandbox()   # a flush after a previous run can outlive its cleanup
	Meta_.writes_disabled = false
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var Meta = load("res://scripts/meta_state.gd")
	var fails := 0

	var m = Meta.new()
	m.new_save()   # collection strike4/defend4; decks {Starter:{strike4,defend4}}

	# default Starter deck exists and is valid
	if not m.decks.has("Starter"): fails += 1; print("FAIL no Starter deck")
	if not m.deck_valid(m.decks["Starter"]): fails += 1; print("FAIL Starter invalid")

	# loadout_size clamps to ownership
	if m.loadout_size({"hack": 99}) != m.owned("hack"):
		fails += 1; print("FAIL clamp size %d (owned %d)" % [m.loadout_size({"hack": 99}), m.owned("hack")])

	# too-small deck is invalid
	if m.deck_valid({"hack": 2}): fails += 1; print("FAIL small deck accepted")

	# build_deck materializes clamped copies at collection level
	var d = m.build_deck({"hack": 2, "cover": 3})
	if d.size() != 5: fails += 1; print("FAIL build size ", d.size())   # both owned in every kit

	# leveled cards build at their level.
	# Earn spare copies first: fusion is blocked if it would drop the collection
	# below the minimum legal deck (see MIN_KEEP / softlock guard).
	for i in 4:
		m.add_card("hack")               # strike 4 -> 8, total 12
	m.add_gold(m.fuse_gold_cost("hack"))  # fusion is bought with gold too
	if not m.fuse("hack"):
		fails += 1; print("FAIL fuse rejected with ample copies")
	var owned_after: int = m.owned("hack")
	var d2 = m.build_deck({"hack": 99})  # clamp to what is owned
	if d2.size() != owned_after: fails += 1; print("FAIL leveled build size ", d2.size())
	var ref := (load("res://resources/cards/hack.tres") as CardData).duplicate()
	ref.level = 2
	var want: int = ref.eff_damage()
	if d2.size() > 0 and d2[0].eff_damage() != want:
		fails += 1; print("FAIL leveled dmg %d (expect %d)" % [d2[0].eff_damage(), want])

	# save / delete / persist
	m.save_deck("Aggro", {"hack": 2, "stave_in": 0, "cover": 6})  # bash not owned -> dropped
	if m.decks["Aggro"].has("stave_in"): fails += 1; print("FAIL unowned card saved")
	m.save_game()

	var m2 = Meta.new()
	m2.load_game()
	if not m2.decks.has("Aggro") or not m2.decks.has("Starter"):
		fails += 1; print("FAIL decks not persisted ", m2.decks.keys())
	if int(m2.decks["Aggro"]["hack"]) != 2: fails += 1; print("FAIL deck content not persisted")

	m2.delete_deck("Aggro")
	if m2.decks.has("Aggro"): fails += 1; print("FAIL delete_deck")

	# --- rename, delete and the slot cap (D212) ---------------------------------------
	# A rename keeps the deck where it sits on the Load bar. Erase-and-reinsert would
	# pass a "the name changed" check and still move the chip to the far end of the row.
	m2.save_deck("A", {"hack": 2})
	m2.save_deck("B", {"cover": 2})
	if not m2.rename_deck("A", "Anvil"): fails += 1; print("FAIL rename rejected")
	if m2.decks.has("A") or not m2.decks.has("Anvil"):
		fails += 1; print("FAIL rename left the old name ", m2.decks.keys())
	if int(m2.decks["Anvil"]["hack"]) != 2: fails += 1; print("FAIL rename lost the loadout")
	var order: Array = m2.decks.keys()
	if order.find("Anvil") > order.find("B"):
		fails += 1; print("FAIL rename reordered the bar ", order)

	# Renaming onto a name another deck holds would silently eat that deck.
	if m2.rename_deck("Anvil", "B"): fails += 1; print("FAIL rename over an existing deck")
	if int(m2.decks["B"]["cover"]) != 2: fails += 1; print("FAIL collided rename overwrote B")
	if m2.rename_deck("nosuch", "C"): fails += 1; print("FAIL renamed a deck that is not there")
	if m2.rename_deck("Anvil", ""): fails += 1; print("FAIL renamed to nothing")

	# The cap counts decks that EXIST. Overwriting one must stay possible at the cap,
	# or the last slot becomes unusable the moment it is filled.
	while m2.decks.size() < m2.MAX_DECKS:
		m2.save_deck("filler%d" % m2.decks.size(), {"hack": 1})
	if m2.decks.size() != m2.MAX_DECKS: fails += 1; print("FAIL filled to ", m2.decks.size())
	if m2.save_deck("one too many", {"hack": 1}):
		fails += 1; print("FAIL saved past the cap of %d" % m2.MAX_DECKS)
	if m2.decks.has("one too many"): fails += 1; print("FAIL over-cap deck stored anyway")
	if not m2.save_deck("Anvil", {"hack": 3}):
		fails += 1; print("FAIL cannot overwrite an existing deck at the cap")
	if int(m2.decks["Anvil"]["hack"]) != 3: fails += 1; print("FAIL overwrite at cap did nothing")
	# ...and a free slot takes a new one again.
	m2.delete_deck("B")
	if not m2.save_deck("B2", {"cover": 2}):
		fails += 1; print("FAIL deleting a deck did not free a slot")

	if fails == 0:
		print("DECK TEST: PASS (validation, clamp, build, level, persistence, rename/delete/cap)")
	else:
		print("DECK TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	quit()

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
