#!/usr/bin/env bash
# Every platform must stay EXPORTABLE, even the ones this machine cannot build.
#
# Android needs a JDK and the Android SDK; iOS needs macOS, Xcode and a team ID.
# None of that can live in a repository, so those two will never build in CI. What
# CAN be guaranteed is that the only thing standing between the project and a build
# is the toolchain — never the project itself.
#
# Godot reports both kinds of problem the same way, as "configuration errors". This
# script exports every preset and classifies each error line:
#
#   toolchain/credential absent -> SKIP, expected, not a failure
#   anything else               -> FAIL, the project has regressed
#
# So the day someone installs the Android SDK, `--export-release "Android"` works
# with no further edits — and if that stops being true, this fails first.
#
# Usage:  tests/export_ready.sh
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || { echo "godot not on PATH; set GODOT=" >&2; exit 127; }

# Reasons a build may legitimately be impossible on this machine. Each is a missing
# tool or a per-developer credential, never something the repository controls.
ALLOWED='A valid Java SDK path|Android SDK path|platform-tools|build-tools|apksigner|adb command|App Store Team ID|only supported on macOS|Xcode|export template|Unable to open Android'

mkdir -p build/_ready
pass=0; skip=0; fail=0

# Pair each preset name with its own export_path: the file EXTENSION matters
# (macOS wants .zip or .app, Windows .exe), so invented output names fail for
# reasons that have nothing to do with whether the project is exportable.
mapfile -t pairs < <(awk -F'"' '
	/^name=/      { n = $2 }
	/^export_path=/ { if (n != "") { print n "\t" $2; n = "" } }' export_presets.cfg)
[ "${#pairs[@]}" -eq 0 ] && { echo "no presets found in export_presets.cfg" >&2; exit 1; }

for pair in "${pairs[@]}"; do
	name="${pair%%$'\t'*}"
	out="$PWD/build/_ready/$(basename "${pair##*$'\t'}")"
	log=$("$GODOT" --headless --export-release "$name" "$out" 2>&1)

	if [ -e "$out" ] || echo "$log" | grep -q "DONE.*savepack"; then
		printf '  built   %s\n' "$name"
		pass=$((pass + 1))
		continue
	fi

	# The reasons sit between the "configuration errors:" header and the blank line
	# that follows. Filter out engine noise that is not a reason at all.
	reasons=$(echo "$log" \
		| sed -n '/due to configuration errors:/,/^ *at: /p' \
		| grep -vE 'due to configuration errors|^ *at: |^\s*$')
	# a total failure with no stated reason is itself a regression
	if [ -z "$reasons" ]; then
		printf '  FAIL    %s — export failed with no stated reason\n' "$name"
		echo "$log" | grep -iE 'error' \
			| grep -viE 'include_filter|exclude_filter|encrypt|script_export' \
			| head -3 | sed 's/^/            /'
		fail=$((fail + 1))
		continue
	fi

	blocking=$(echo "$reasons" | grep -vE "$ALLOWED")
	if [ -n "$blocking" ]; then
		printf '  FAIL    %s — blocked by the PROJECT, not the toolchain:\n' "$name"
		echo "$blocking" | sed 's/^/            /'
		fail=$((fail + 1))
	else
		printf '  skip    %s — toolchain only: %s\n' "$name" \
			"$(echo "$reasons" | head -1 | sed 's/^ *//')"
		skip=$((skip + 1))
	fi
done

rm -rf build/_ready
echo
echo "$pass buildable here, $skip need a toolchain, $fail blocked by the project"
[ "$fail" -eq 0 ] || exit 1
