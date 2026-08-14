## Set every card's and every relic's rarity from what the game says it is WORTH (D224).
##
## Rarity was authored by hand and drifted: `power_value()` — the same score the
## collection screen sorts by, and the same one `Balance.power_ratio` prices a deck
## with — said the strongest card in the game was an epic, that 29 of 32 commons beat
## the weakest uncommon, and that relic rarity did not ascend at all. This walks the
## catalogue in power order and writes the bands back.
##
## Run: godot --headless --script tools/rerarify.gd            (dry run, prints a plan)
##      godot --headless --script tools/rerarify.gd -- --write  (rewrites the .tres)
##
## Band sizes are the ones the catalogue already had, so the pyramid the rarity suite
## checks — commons the bulk, legendaries scarce — is preserved rather than re-argued.
## A band boundary NEVER splits cards of equal power: it slides down to the next
## distinct value, because two identical scores wearing different rarities is the very
## thing this is here to remove.
extends SceneTree

const NAMES := ["COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY"]
## From the top down: legendary, epic, rare, uncommon, and commons take the rest.
const CARD_BANDS := [6, 12, 22, 28]
const RELIC_BANDS := [3, 5, 7, 8]
## Scaled with the set when it went from ten to thirty (D250). At ten the pyramid was
## [1, 2, 2, 2] — one legendary, two epic, two rare, two uncommon, three common — and left
## unchanged at thirty it would have filed twenty-three of them common, which is not a pyramid,
## it is a pile with a hat on. [2, 4, 6, 8] keeps the shape: two legendary, four epic, six rare,
## eight uncommon, ten common.
##
## The band SIZES are what this file owns and the power ORDER is what `power_value()` owns, so
## growing the set re-files the old ten as well — the same absolute-count behaviour that moved 22 of
## 37 relics in D233. That is the derived system working, not drift.
const POWER_BANDS := [2, 4, 6, 8]

func _init() -> void:
	var write := "--write" in OS.get_cmdline_user_args()
	var m = load("res://scripts/meta_state.gd").new()

	# The yardstick is TOTAL power — what the card does when you play it — and not power
	# per energy. Per energy was tried, because it is the measure the balance model uses
	# everywhere else (enemies scale against the deck's power per energy, energy being
	# the binding constraint), and it is the wrong measure for RARITY. It divides a
	# card's impact by its cost, so it files big expensive cards at the bottom: Massacre
	# (12.3 power, 3 energy) and Stave In (15.0, 3) came out COMMON, while Second Heart
	# (25.4, 2) and Plague Bearer (22.1, 2) were pushed out of the top band by 1-energy
	# cards worth half as much. A common is what a pack is full of, and a big expensive
	# card is not that. Rarity is impact; scaling is efficiency; they are two questions.
	#
	# `--rate` keeps the experiment runnable rather than only described.
	var rate := "--rate" in OS.get_cmdline_user_args()
	var cards: Array = []
	for id in m.CATALOG:
		var c := load(m.CATALOG[id]) as CardData
		if c != null:
			var p: float = c.power_value()
			if rate:
				p /= maxf(1.0, Balance.card_energy_cost(c))
			cards.append({"id": String(id), "path": String(m.CATALOG[id]), "name": c.name,
				"power": p, "total": c.power_value(), "cost": Balance.card_energy_cost(c),
				"was": int(c.rarity), "special": c.changes_a_rule()})
	_apply("CARDS", cards, CARD_BANDS, write, true)

	var relics: Array = []
	for id in m.RELIC_CATALOG:
		var r := load(m.RELIC_CATALOG[id]) as RelicData
		if r != null:
			relics.append({"id": String(id), "path": String(m.RELIC_CATALOG[id]), "name": r.name,
				"power": r.power_value(), "was": int(r.rarity), "special": true})
	_apply("RELICS", relics, RELIC_BANDS, write, false)

	# Powers wear a rarity too — `PowerData extends CardData` — and it is not decoration
	# there either: `Balance.power_price` is `card_price(rarity) * 2` and
	# `power_upgrade_cost` is the fusion gold curve at that rarity. So the band a power
	# wears is what it costs to buy and what every level of it costs after that, and the
	# ten of them were filed with two rares (Kindle and Siphon, 4.5) sitting under a
	# common (Foresight, 5.0) and no legendary at all.
	var powers: Array = []
	for pid in Balance.POWERS:
		var p := Balance.power(pid)
		if p != null:
			powers.append({"id": String(pid), "path": Balance.POWER_DIR + pid + ".tres",
				"name": p.name, "power": p.power_value(), "was": int(p.rarity),
				"special": p.changes_a_rule()})
	_apply("POWERS", powers, POWER_BANDS, write, true)
	quit()

## The rarity suite's rule: a legendary has to CHANGE something, not just be a big
## number. Honoured here rather than discovered as a failure afterwards — a card that
## is only numbers is passed over for the top band and the next one down takes its
## place.
## `_rule_changer` now lives on `CardData` as `changes_a_rule()` (D250). It was a hand-written list
## of eight fields here AND a second copy of the same list in `tests/test_rarity.gd`, and the two
## disagreed the moment one was fixed. One owner, beside the fields it reads.

func _apply(what: String, rows: Array, bands: Array, write: bool, guard_legendary: bool) -> void:
	# Descending by power, ties broken by id so two runs of this tool agree.
	rows.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(float(a["power"]), float(b["power"])):
			return float(a["power"]) > float(b["power"])
		return String(a["id"]) < String(b["id"]))

	# The top band may not take a card that is only numbers. Pull the next eligible one
	# up past it rather than dropping the rule or the ranking.
	if guard_legendary:
		var want: int = int(bands[0])
		var i := 0
		while i < mini(want, rows.size()):
			if bool(rows[i]["special"]):
				i += 1
				continue
			var swap := -1
			for j in range(want, rows.size()):
				if bool(rows[j]["special"]):
					swap = j
					break
			if swap < 0:
				break
			var moved = rows[swap]
			rows.remove_at(swap)
			rows.insert(i, moved)
			print("  (%s is only numbers — %s takes the top band instead)" % [
				rows[i + 1]["name"], moved["name"]])
			i += 1

	# Walk down, closing each band at its target size or at the next distinct power,
	# whichever comes later.
	var rarity := 4
	var placed := 0
	var band_i := 0
	var counts := [0, 0, 0, 0, 0]
	var moves: Array = []
	for i in rows.size():
		var row = rows[i]
		if band_i < bands.size():
			var target: int = int(bands[band_i])
			var full: bool = placed >= target
			var breakable: bool = i == 0 or not is_equal_approx(
				float(rows[i - 1]["power"]), float(row["power"]))
			if full and breakable:
				rarity -= 1
				band_i += 1
				placed = 0
		row["now"] = rarity
		counts[rarity] += 1
		placed += 1
		if int(row["was"]) != rarity:
			moves.append(row)

	print("\n=== %s" % what)
	for r in range(4, -1, -1):
		var lo := 99999.0
		var hi := -1.0
		for row in rows:
			if int(row["now"]) == r:
				lo = minf(lo, float(row["power"]))
				hi = maxf(hi, float(row["power"]))
		if counts[r] > 0:
			print("  %-9s n=%2d   power %.1f .. %.1f" % [NAMES[r], counts[r], lo, hi])
	# Both ladders the rarity suite checks, printed together: this tool can only rank on
	# one number, and the other one has to be watched rather than assumed.
	var tot := [0.0, 0.0, 0.0, 0.0, 0.0]
	var n := [0, 0, 0, 0, 0]
	for row in rows:
		if row.has("total"):
			tot[int(row["now"])] += float(row["total"])
			n[int(row["now"])] += 1
	for r in range(5):
		if n[r] > 0:
			print("    %-9s avg total power %.1f" % [NAMES[r], tot[r] / float(n[r])])
	print("  %d of %d change band" % [moves.size(), rows.size()])
	if "--list" in OS.get_cmdline_user_args():
		for row in rows:
			print("    %6.2f rate %6.1f total %d E  %-9s %-22s %s" % [
				row["power"], row.get("total", row["power"]), int(row.get("cost", 1)),
				NAMES[int(row["now"])], row["name"],
				"" if int(row["was"]) == int(row["now"]) else "(was %s)" % NAMES[int(row["was"])]])
	for row in moves:
		print("    %6.1f  %-22s %-9s -> %s" % [
			row["power"], row["name"], NAMES[int(row["was"])], NAMES[int(row["now"])]])

	if not write:
		return
	for row in rows:
		if int(row["was"]) != int(row["now"]):
			_write_rarity(String(row["path"]), int(row["now"]))
	print("  written.")

## Rewrite the `rarity = N` line, or add one where the resource relied on the default.
func _write_rarity(path: String, rarity: int) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("  CANNOT READ %s" % path)
		return
	var text := f.get_as_text()
	f.close()
	var lines := text.split("\n")
	var out: Array[String] = []
	var done := false
	for line in lines:
		if line.begins_with("rarity = "):
			out.append("rarity = %d" % rarity)
			done = true
		else:
			out.append(line)
	if not done:
		# after `type = N` if there is one, else after `cost`/`name`, else at the end of
		# the resource block — order in a .tres is cosmetic, but keeping it near its
		# neighbours keeps the diff readable
		var at := -1
		for i in out.size():
			if out[i].begins_with("type = ") or out[i].begins_with("cost = "):
				at = i
		if at >= 0:
			out.insert(at + 1, "rarity = %d" % rarity)
		else:
			out.append("rarity = %d" % rarity)
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		print("  CANNOT WRITE %s" % path)
		return
	w.store_string("\n".join(out))
	w.close()
