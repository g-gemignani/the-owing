#!/usr/bin/env bash
# Stamp the commit into the build, so a downloaded copy can say which one it is (D156).
#
# The release channel is a rolling tag: every green push replaces the assets under it, so
# every Android build this project has ever published is called `TheOwing-android.apk`. The
# release notes record the commit; the notes are on a web page and the build is on a phone.
# This puts the commit inside the build, where `BuildInfo` reads it.
#
# Run it in CI immediately before an export, never as a commit:
#
#   tools/stamp_build.sh                 # uses git HEAD and today's UTC date
#   tools/stamp_build.sh <sha> <run>     # explicit, for a runner that has the values already
#
# What it rewrites, both in place and both meant to be thrown away with the runner:
#
#   project.godot        application/config/version   -> 0.1.0+<date>.<short sha>
#   export_presets.cfg   version/name (Android)       -> the same string
#   export_presets.cfg   version/code (Android)       -> the run number, so a phone can tell
#                                                        one build is newer than another
#
# `tests/test_content.gd` fails if a stamped `project.godot` is ever committed: the committed
# value must stay `-dev`, or every hand build would claim to be whichever CI build was
# exported last.
set -euo pipefail
cd "$(dirname "$0")/.."

sha="${1:-$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)}"
run="${2:-0}"
# UTC, because a build stamped in two timezones is two builds that claim different days.
date_part="$(date -u +%Y-%m-%d)"

# The base version is whatever is committed, minus the dev sentinel: it is edited by a human
# when the game's version means something, and this script must not be the thing that decides
# what release it is.
base="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot | head -1)"
base="${base%-dev}"
[ -n "$base" ] || { echo "no config/version in project.godot" >&2; exit 1; }

stamp="${base}+${date_part}.${sha}"

# `sed -i` on the one line, matched from the start, so a `config/version` inside a comment
# or a string elsewhere in the file cannot be hit.
sed -i "s|^config/version=\".*\"$|config/version=\"${stamp}\"|" project.godot
grep -q "^config/version=\"${stamp}\"$" project.godot || {
	echo "failed to stamp project.godot" >&2; exit 1; }

# Android carries its own version, and the OS shows it in App info — the one place a stamp
# is visible without launching the game. `version/code` must be an integer that increases.
if [ -f export_presets.cfg ]; then
	sed -i "s|^version/name=\".*\"$|version/name=\"${stamp}\"|" export_presets.cfg
	if [ "$run" != "0" ]; then
		sed -i "s|^version/code=.*$|version/code=${run}|" export_presets.cfg
	fi
fi

echo "stamped ${stamp}${run:+ (version/code ${run})}"
