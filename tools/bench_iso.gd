## Benchmark for the iso crawl: how long is a generated dungeon, and a full walk of it?
##
## Exists because `tools/sim_balance.gd` spends most of its life here rather than in
## combat, and a twenty-minute feedback loop is one nobody runs (D99). Use it to check a
## change to the crawl before paying for a full report.
##
## Run: godot --headless --script tools/bench_iso.gd
##
## **Reported as the MINIMUM of several batches, not the mean.** Repeated runs of
## identical code drifted 40% on a loaded machine and single readings sent this
## optimisation the wrong way twice; load can only ever make a batch slower, so the
## fastest batch is the honest estimate of the work itself. The two arms are also
## interleaved, so a slow patch of machine cannot land on one of them only.
##
## The A/B arm drives the walk through `_compute_options()` instead of `options()`,
## which is exactly the memo `options()` added — the way to check it still pays.
extends SceneTree
const BATCHES := 7
const PER_BATCH := 60

func _walk(dd, memoized: bool) -> int:
	var iso := TraversalIso.new()
	iso.generate(dd)
	var steps := 0
	while not iso.is_complete() and steps < 400:
		steps += 1
		# The only difference: a driver that asks through the memo, versus one that
		# forces the list to be rebuilt the way every caller did before it existed.
		var o: Array = iso.options() if memoized else iso._compute_options()
		if o.is_empty():
			break
		var pick := 0
		for j in o.size():
			if not o[j].has("hp_cost"):
				pick = j
				break
		if not iso.select(pick).is_empty():
			iso.clear_pending()
	return steps

func _best(dd, memoized: bool) -> float:
	var best := 1.0e30
	for b in BATCHES:
		var t := Time.get_ticks_usec()
		for i in PER_BATCH:
			_walk(dd, memoized)
		var ms := float(Time.get_ticks_usec() - t) / 1000.0 / PER_BATCH
		best = minf(best, ms)
	return best

func _init() -> void:
	var dd := Balance.dungeon("fungal_deep")
	# interleaved, so a slow patch of machine cannot land on one arm only
	var a := _best(dd, false)
	var b := _best(dd, true)
	var a2 := _best(dd, false)
	var b2 := _best(dd, true)
	var no_memo := minf(a, a2)
	var memo := minf(b, b2)

	var t := Time.get_ticks_usec()
	for i in 400:
		var iso := TraversalIso.new()
		iso.generate(dd)
	var gen := float(Time.get_ticks_usec() - t) / 1000.0 / 400.0

	print("generate            %.3f ms" % gen)
	print("full run, no memo   %.3f ms" % no_memo)
	print("full run, memoized  %.3f ms   (%.2fx)" % [memo, no_memo / maxf(memo, 0.0001)])
	quit()
