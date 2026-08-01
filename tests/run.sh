#!/usr/bin/env bash
# Run every test. One command, so nobody hand-lists suite names and quietly drops one.
#
# Two kinds live here:
#   *.gd        headless script tests  (godot --script)
#   *Test.tscn  scene tests            (godot <scene>)
# Scene tests exist because some properties — mouse_filter, wrapped line counts,
# scaled rects — only exist on a tree that has actually been built, and autoloads
# are not registered in a `--script` run.
#
# Suites run CONCURRENTLY, one engine per suite. Three things had to be true first,
# and all three are load-bearing — undo any of them and the suite goes quietly wrong
# rather than red:
#   * each suite gets its own user:// sandbox (DECKCRAWL_SANDBOX, read by
#     meta_state.gd and settings_state.gd), because the shared default is one save
#     file that whichever suite writes last gets to define;
#   * each teardown deletes only its own prefix (tests/*.gd `SANDBOX`), because the
#     old sweep of everything matching `t_` deleted the LIVE saves of every suite
#     running beside it;
#   * each engine writes its own log, because they otherwise rotate one file
#     underneath each other and the failure you want is the one that gets lost.
#
# Usage:  tests/run.sh [name-filter]
#         JOBS=1 tests/run.sh     serial, for bisecting a suite that only fails in company
set -uo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")   # workers re-invoke this
cd "$(dirname "$SELF")/.."

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || {
	echo "godot not on PATH; set GODOT=/path/to/godot" >&2; exit 127; }

# A test passes only if it SAYS so and then exits cleanly. The exit code is
# checked because a crash during engine shutdown — after the report is printed —
# still means something is wrong, and it is otherwise invisible: stdout to a pipe
# is block-buffered, so an abort discards the very "PASS" line this greps for.
# That failure mode reported three green tests as failures with no explanation.
#
# `--quit` is what makes a broken test cheap. These scripts do their work in
# `_init()` and call `quit()` at the end, so a script error ABORTS `_init()`, never
# reaches `quit()`, and leaves the SceneTree spinning until something kills it —
# seven suites left stale card ids after a rename and the run took thirty-five
# minutes to report them, all of it asleep. Quitting after one iteration turns that
# back into the one second it costs to fail. The timeout is now only a backstop for
# a genuine infinite loop, so it no longer has to be generous.
TIMEOUT="${TIMEOUT:-120}"

USERDATA=~/.local/share/godot/app_userdata/Deckcrawl

run_one() {  # run_one <label> <script|scene> <target>   (results land in $RESULTS)
	local label="$1" kind="$2" target="$3" dir="$RESULTS"
	local out code start dur extra=()
	[[ $kind == script ]] && extra=(--quit --script)
	start=$SECONDS
	out=$(DECKCRAWL_SANDBOX="$label" timeout "$TIMEOUT" "$GODOT" --headless \
		--log-file "user://logs/$label.log" "${extra[@]}" "$target" 2>/dev/null)
	code=$?
	dur=$((SECONDS - start))
	# Remove the sandbox this run handed out, now that its engine has exited. Scoped
	# to the one label, so it cannot touch a suite still running beside it. A suite's
	# own teardown is still the first line of defence; this catches the ones that
	# never had one, and the save an autoload writes at boot before a scene test can
	# set its prefix. Anything left after this is a test writing OUTSIDE its sandbox,
	# which is exactly what the stray check at the bottom is for.
	rm -f "$USERDATA/t_${label}_"*
	if [[ $code -eq 0 ]] && grep -qE "TEST: PASS" <<<"$out"; then
		printf '  ok   %-22s %3ds\n' "$label" "$dur"
		: >"$dir/$label.pass"
	else
		printf '  FAIL %-22s %3ds (exit %d)\n' "$label" "$dur" "$code"
		# The output is the diagnosis. Discarding it is what made a null-deref in
		# `_init()` read as a bare "exit 124" with nothing to go on.
		{ printf '=== %s (exit %d) ===\n' "$label" "$code"
		  if [[ -n "$out" ]]; then grep -E "FAIL|ERROR|SCRIPT ERROR|at: " <<<"$out" | head -20
		  else echo "  (no output — the engine died before it could report)"; fi
		} >"$dir/$label.fail"
	fi
}

# Workers re-enter this script; everything above this line has already run for them,
# and RESULTS/TIMEOUT/GODOT arrive through the environment.
if [[ "${1:-}" == "--worker" ]]; then
	run_one "$2" "$3" "$4"
	exit 0
fi

FILTER="${1:-}"
JOBS="${JOBS:-$(( $(nproc 2>/dev/null || echo 4) - 2 ))}"
(( JOBS > 0 )) || JOBS=1

"$GODOT" --headless --import >/dev/null 2>&1

RESULTS=$(mktemp -d)
trap 'rm -rf "$RESULTS"' EXIT
export RESULTS GODOT TIMEOUT

jobs_for() {
	local f name
	for f in tests/test_*.gd; do
		name=$(basename "$f" .gd)
		[[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue
		printf '%s\t%s\t%s\n' "$name" script "$f"
	done
	for f in tests/*Test.tscn; do
		name=$(basename "$f" .tscn)
		[[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue
		# Scene tests await real frames, so they must NOT be cut off after one.
		printf '%s\t%s\t%s\n' "$name" scene "res://${f}"
	done
}

# Longest first: with one engine per suite the run cannot finish before its slowest
# member, so starting that one last wastes exactly as long as it takes. Measured, not
# guessed — re-read the per-suite seconds the run prints if this stops being true.
SLOWEST="test_softlock PlayableTest test_traversal CardTextTest test_art MenuArtTest"
order() {
	jobs_for | awk -v slow="$SLOWEST" '
		BEGIN { n = split(slow, s, " "); for (i = 1; i <= n; i++) rank[s[i]] = i }
		{ print (($1 in rank) ? rank[$1] : 999) "\t" $0 }
	' | sort -s -k1,1n | cut -f2-
}

start=$SECONDS
order | tr '\t' '\n' | xargs -r -P "$JOBS" -n 3 "$SELF" --worker
wall=$((SECONDS - start))

pass=$(ls "$RESULTS"/*.pass 2>/dev/null | wc -l)
mapfile -t failed < <(cd "$RESULTS" 2>/dev/null && ls *.fail 2>/dev/null | sed 's/\.fail$//')

echo
if ((${#failed[@]})); then
	cat "$RESULTS"/*.fail
	echo
fi
echo "$pass passed, ${#failed[@]} failed in ${wall}s (-P $JOBS)"
if ((${#failed[@]})); then
	printf 'failed: %s\n' "${failed[*]}"
	exit 1
fi

# Tests are sandboxed (MetaState.path_prefix / SettingsState.path_override) because
# they once wrote over a real save and a real settings file. Prove it every run.
strays=$(ls "$USERDATA" 2>/dev/null | grep -c '^t_' || true)
if [[ "$strays" != "0" ]]; then
	echo "WARNING: $strays sandbox file(s) left in the player's data directory" >&2
	exit 1
fi
