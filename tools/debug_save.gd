## Write a save you can play an ARCHETYPE from, without grinding to one (D310).
##
## The point of it is feedback the simulator cannot give. A report can say a deck completes 1% of
## its runs; it cannot say whether the run was lost to a decision or was never survivable, and it
## cannot say whether a fight was long and boring. Those are the two questions that decide whether
## a number is a tuning problem or a design problem, and only a person playing can answer them.
##
## What stops that today is not the deck builder — that exists, and six loadouts can be saved. It
## is that the cards have to be OWNED at a level, and reaching Lv15 across a collection is hours of
## fusing. So this grants the collection and the progression, and leaves the choosing alone.
##
## Run:
##     godot --headless --script tools/debug_save.gd -- --slot=3 --level=15 --clears=4
##
## Then boot the game and pick that slot. Every card is owned, the named decks are in the deck bar,
## and you can ignore all of them and build something else — which is most of the point.
##
## Options, all optional:
##     --slot=N      which save slot (default 3, and slots 1-3 are refused without --force)
##     --level=N     card level, clamped per card by rarity (default 15, the sim's mid profile)
##     --clears=N    dungeons marked cleared (default 4). Drives max HP, unlocks and relic gates.
##     --gold=N      purse (default 3000)
##     --copies=N    copies of each card (default MAX_DECK_SIZE, so ANY legal deck is buildable)
##     --builds=a,b  which archetypes to save as loadouts (default: the six in question)
##     --force       allow writing over an existing save
extends SceneTree

## Away from 1, 2 and 3 as the slot screen numbers them — this writes index 3, the fourth row.
const DEFAULT_SLOT := 3
## The six archetypes the balance table has open questions about (D303), and it happens to be
## exactly `MetaState.MAX_DECKS`. Overridable, because the interesting six will move.
const DEFAULT_BUILDS := ["poison", "swarm", "tempo", "vampire", "fortress", "thorns"]

var slot := DEFAULT_SLOT
var level := 15
var clears := 4
var gold := 3000
## Enough of every card that no legal loadout can be clamped short. Four was the first guess and
## the tool's own read-back rejected it within a minute: `new_save`'s Starter deck asks for five
## Hack, `save_deck` clamps every entry to what is owned, and the deck came back as eleven cards —
## a slot the player would open, press Start on, and be told "deck too small". **The promise here
## is "build anything", and any number below `MAX_DECK_SIZE` quietly is not that.**
var copies := Balance.MAX_DECK_SIZE
var builds: Array = DEFAULT_BUILDS.duplicate()
var force := false

func _init() -> void:
	_read_args()

	# **The headless prefix, and this is the whole reason the tool needs a note.**
	#
	# `MetaState.path_prefix` is `t_headless_` under a headless display, so a save written here
	# lands in `user://t_headless_save_3.json` and the game — which is not headless — reads
	# `user://save_3.json` and finds nothing. The tool would report success and the slot would be
	# empty. Cleared explicitly, because writing where the player can see it IS the job.
	var Meta = load("res://scripts/meta_state.gd")
	Meta.path_prefix = ""
	Meta.writes_disabled = false

	var path: String = Meta.path_for(slot)
	if FileAccess.file_exists(path) and not force:
		print("REFUSED: %s already exists. Pass --force to overwrite it." % path)
		print("         Slot numbers on the game's own screen are one higher than this index.")
		quit(1)
		return

	var m = Meta.new()
	m.slot = slot
	# A real opening save first, so every field this tool does not set is whatever a new game has
	# rather than whatever a default happens to be. `persist` false: nothing is written until the
	# end, so a tool that fails half way leaves no half-made save behind.
	m.new_save("blade", false)

	# --- the collection: everything, at a level ---
	#
	# Clamped per card, because `Balance.max_level` is derived from drop weight — a legendary caps
	# at 5 and asking for 15 would write a level the game refuses to sell. Silent clamping is fine
	# here and only here: it is the same clamp the fusion screen applies.
	var granted := 0
	var clamped := 0
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		if c == null:
			continue
		var lv: int = mini(level, Balance.max_level(c.rarity))
		if lv < level:
			clamped += 1
		m.collection[id] = {"count": copies, "level": lv}
		granted += 1

	# --- the progression: clears, and what they buy ---
	#
	# Not just the cards. The report calls one deck "Poison build (Lv15)" and that player has 4
	# clears and 100 HP; handing over the poison cards at Lv15 with no clears is a different
	# person, and the feedback and the table would not be about the same run. D208 is the entry
	# that cost 42 cells a mean of +17 points for exactly this.
	for i in mini(clears, Balance.DUNGEONS.size()):
		m.mark_cleared(Balance.DUNGEONS[i])
	m.gold = gold

	# --- the decks, read from the game's own archetype data ---
	var saved: Array[String] = []
	var missing: Array[String] = []
	var over: Array[String] = []
	for bid in builds:
		var b := Balance.build(String(bid))
		if b == null:
			missing.append(String(bid))
			continue
		if saved.size() >= m.MAX_DECKS:
			over.append(String(bid))
			continue
		var loadout := _loadout_for(b, m)
		if loadout.is_empty():
			missing.append(String(bid))
			continue
		m.save_deck(b.name.substr(0, Balance.MAX_DECK_NAME), loadout)
		saved.append("%s (%s)" % [b.name, bid])

	m.save_game()

	# --- read it back, because a debug save that writes an unplayable deck is worse than none ---
	#
	# The failure it catches is quiet: `save_deck` clamps every entry to what is owned, so a
	# loadout asking for more copies than `--copies` granted comes back short of `MIN_DECK_SIZE`
	# and the Start button simply refuses with "deck too small" — on a screen the player reached
	# expecting to press it. Checked against the file rather than against memory, so the write
	# itself is part of what is verified.
	var back = Meta.new()
	back.slot = slot
	back.load_game()
	var bad: Array[String] = []
	if back.collection.size() != granted:
		bad.append("the collection came back as %d types, not %d" % [back.collection.size(), granted])
	for dname in back.decks:
		if not back.deck_valid(back.decks[dname]):
			bad.append("'%s' is %d cards, outside %d-%d" % [dname,
				back.loadout_size(back.decks[dname]), Balance.MIN_DECK_SIZE, Balance.MAX_DECK_SIZE])
	if not bad.is_empty():
		print("WROTE A BROKEN SAVE — %s" % "; ".join(bad))
		quit(1)
		return

	print("Wrote %s" % path)
	print("  %d card types x%d at Lv%d%s" % [granted, copies, level,
		"  (%d capped lower by rarity)" % clamped if clamped > 0 else ""])
	print("  %d clears, %d max HP, %d gold" % [
		clears, Balance.max_hp_for(clears), gold])
	print("  decks: %s" % ", ".join(saved))
	# Said out loud rather than dropped. A tool that quietly saves five of six decks is a tool
	# whose output you cannot read as a list of what you asked for.
	if not over.is_empty():
		print("  NOT saved, over MAX_DECKS (%d): %s" % [m.MAX_DECKS, ", ".join(over)])
	if not missing.is_empty():
		print("  NOT saved, unknown or unbuildable: %s" % ", ".join(missing))
	print("  Open the game and pick slot %d on the save screen." % (slot + 1))
	quit()

## A legal deck made of one build's own cards.
##
## Dealt round robin rather than in list order, so a build whose first entries happen to be its
## cheap enablers does not become a deck of nothing else. `MIN_DECK_SIZE` and not `MAX_DECK_SIZE`,
## because the smallest legal deck is the one the game hands you (D249) and anything above it is a
## choice this tool should not be making for the player.
func _loadout_for(b: BuildData, m) -> Dictionary:
	var pool: Array = []
	for cid in b.cards:
		if m.CATALOG.has(cid):
			pool.append(cid)
	if pool.is_empty():
		return {}
	var out := {}
	var n := 0
	var i := 0
	while n < Balance.MIN_DECK_SIZE:
		var cid: String = String(pool[i % pool.size()])
		var have: int = int(out.get(cid, 0))
		# Never past what the collection holds, or `save_deck` clamps it back and the deck comes
		# out short of legal without saying so.
		if have < copies:
			out[cid] = have + 1
			n += 1
		elif i % pool.size() == pool.size() - 1 and n < Balance.MIN_DECK_SIZE:
			# A full lap with nothing addable: the build is smaller than the deck it has to fill.
			break
		i += 1
	return out

func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="):
			slot = maxi(0, int(arg.substr(7)))
		elif arg.begins_with("--level="):
			level = maxi(1, int(arg.substr(8)))
		elif arg.begins_with("--clears="):
			clears = maxi(0, int(arg.substr(9)))
		elif arg.begins_with("--gold="):
			gold = maxi(0, int(arg.substr(7)))
		elif arg.begins_with("--copies="):
			copies = maxi(1, int(arg.substr(9)))
		elif arg.begins_with("--builds="):
			builds = arg.substr(9).split(",", false)
		elif arg == "--force":
			force = true
