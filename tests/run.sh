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
#   * each suite gets its own user:// sandbox (OWING_SANDBOX, read by
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

# The player's data directory. PINNED in project.godot by config/custom_user_dir_name,
# which is why this can be a literal: without the pin Godot derives it from
# config/name, and renaming the game moves it. This path being wrong does not fail
# loudly — the stray-sandbox check below would find nothing and pass, so a test writing
# over a real save would stop being caught (D127). Note the shape: use_custom_user_dir
# drops the `godot/app_userdata/` layer rather than just replacing the last segment.
USERDATA=~/.local/share/Deckcrawl

# A suite that means to provoke script errors says so, on stdout, and is exempt from the
# stderr check below. Two do: `test_compile` and `test_layout` both `load()` scripts that
# name autoloads, and autoloads do not exist in a `--script` run, so a compile error there
# is the tool working. Every other suite is required to be silent.
EXPECTS_ERRORS="TEST EXPECTS ERRORS"

run_one() {  # run_one <label> <script|scene> <target>   (results land in $RESULTS)
	local label="$1" kind="$2" target="$3" dir="$RESULTS"
	local out err code start dur extra=()
	[[ $kind == script ]] && extra=(--quit --script)
	start=$SECONDS
	err=$(mktemp)
	out=$(OWING_SANDBOX="$label" timeout "$TIMEOUT" "$GODOT" --headless \
		--log-file "user://logs/$label.log" "${extra[@]}" "$target" 2>"$err")
	code=$?
	dur=$((SECONDS - start))
	# Remove the sandbox this run handed out, now that its engine has exited. Scoped
	# to the one label, so it cannot touch a suite still running beside it. A suite's
	# own teardown is still the first line of defence; this catches the ones that
	# never had one, and the save an autoload writes at boot before a scene test can
	# set its prefix. Anything left after this is a test writing OUTSIDE its sandbox,
	# which is exactly what the stray check at the bottom is for.
	rm -f "$USERDATA/t_${label}_"*
	# A SCRIPT ERROR is a FAILURE, and it has to be read off stderr because that is the only
	# place it appears (D300). A runtime error inside an `await`ed function aborts that
	# function, leaves the exit code at 0 and lets `_ready` go on to print its PASS line — so
	# a whole section of a suite can stop running and the suite still reports green. It cost
	# this project twice: `RewardNoteTest` called `_roll_rewards`, deleted at D297, and went on
	# printing PASS with its largest section dead; then the same file called a constant that had
	# moved onto `UI` and did it again. Discarding stderr is what made that invisible.
	local screamed=0
	if grep -q "SCRIPT ERROR" "$err" && ! grep -qF "$EXPECTS_ERRORS" <<<"$out"; then
		screamed=1
	fi
	if [[ $code -eq 0 && $screamed -eq 0 ]] && grep -qE "TEST: PASS" <<<"$out"; then
		printf '  ok   %-22s %3ds\n' "$label" "$dur"
		: >"$dir/$label.pass"
	else
		printf '  FAIL %-22s %3ds (exit %d)\n' "$label" "$dur" "$code"
		# The output is the diagnosis. Discarding it is what made a null-deref in
		# `_init()` read as a bare "exit 124" with nothing to go on.
		{ printf '=== %s (exit %d) ===\n' "$label" "$code"
		  if [[ $screamed -eq 1 ]]; then
			echo "  a SCRIPT ERROR ran during this suite — a section of it did not execute:"
			grep -E "SCRIPT ERROR|at: " "$err" | head -12
		  fi
		  if [[ -n "$out" ]]; then grep -E "FAIL|ERROR|SCRIPT ERROR|at: " <<<"$out" | head -20
		  elif [[ $screamed -eq 0 ]]; then echo "  (no output — the engine died before it could report)"; fi
		} >"$dir/$label.fail"
	fi
	rm -f "$err"
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
#
# NAME them. "2 sandbox file(s) left" sent someone bisecting the whole suite for a
# writer that turned out to be a tool run by hand in another terminal: anything
# headless without OWING_SANDBOX lands on `t_headless_`, and this directory is
# shared by every process on the machine, not just this run. The filename says which
# it was in one line.
mapfile -t strays < <(ls "$USERDATA" 2>/dev/null | grep '^t_' || true)
if ((${#strays[@]})); then
	echo "WARNING: ${#strays[@]} sandbox file(s) left in the player's data directory:" >&2
	printf '  %s\n' "${strays[@]}" >&2
	echo "  (t_headless_* means a headless run with no OWING_SANDBOX — likely a tool," >&2
	echo "   not a suite. Anything else is a test writing outside the prefix it was given.)" >&2
	exit 1
fi

# The generated documents, checked rather than trusted (D262).
#
# `--check` existed on all three generators from the day they were written and NOTHING
# CALLED IT. AGENTS.md said so about itself — "a generated document with no check is a
# document that is true on the day it is written" — and then ART_ASSETS.md carried a line
# claiming `relics_screen.gd` renders thirty relics as text rows, through three content
# passes, an icon set and eight new relics. D210 is the same failure with two documents
# instead of one. So this is the caller.
#
# It is NOT a suite: it runs after the count is printed and does not move "46 passed". A
# stale document is not a failing test, it is a failing commit, and this is the last thing
# between the two.
#
# `tools/readme_downloads.sh --check` is deliberately absent. It reads the GitHub releases
# API, and a test run that needs the network fails on a train. Run that one by hand before
# a release, which is the only time its subject changes.
gen_rc=0
for gen in tools/art_docs.sh tools/design_index.sh; do
	"$gen" --check >/dev/null 2>&1 || { echo "STALE: $gen --check — run '$gen'" >&2; gen_rc=1; }
done
if ((gen_rc)); then
	echo "  (the suites passed; a generated document is out of step with what generated it)" >&2
	exit 1
fi
