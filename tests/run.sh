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
# Usage:  tests/run.sh [name-filter]
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || {
	echo "godot not on PATH; set GODOT=/path/to/godot" >&2; exit 127; }

FILTER="${1:-}"
# A slow suite is not a failing suite: the fuzz tests genuinely take a while.
TIMEOUT="${TIMEOUT:-300}"

"$GODOT" --headless --import >/dev/null 2>&1

pass=0; fail=0; failed=()
run() {  # run <label> <godot args...>
	local label="$1"; shift
	if timeout "$TIMEOUT" "$GODOT" --headless "$@" 2>/dev/null | grep -qE "TEST: PASS"; then
		pass=$((pass + 1)); printf '  ok   %s\n' "$label"
	else
		fail=$((fail + 1)); failed+=("$label"); printf '  FAIL %s\n' "$label"
	fi
}

for f in tests/test_*.gd; do
	name=$(basename "$f" .gd)
	[[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue
	run "$name" --script "$f"
done

for f in tests/*Test.tscn; do
	name=$(basename "$f" .tscn)
	[[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && continue
	run "$name" "res://${f}"
done

echo
echo "$pass passed, $fail failed"
if ((fail)); then
	printf 'failed: %s\n' "${failed[*]}"
	exit 1
fi

# Tests are sandboxed (MetaState.path_prefix / SettingsState.path_override) because
# they once wrote over a real save and a real settings file. Prove it every run.
strays=$(ls ~/.local/share/godot/app_userdata/Deckcrawl/ 2>/dev/null | grep -c '^t_' || true)
if [[ "$strays" != "0" ]]; then
	echo "WARNING: $strays sandbox file(s) left in the player's data directory" >&2
	exit 1
fi
