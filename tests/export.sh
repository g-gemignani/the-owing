#!/usr/bin/env bash
# Build a pack and run the export-only checks inside it.
#
# Separate from tests/run.sh because it needs export templates (~1 GB) that a
# normal checkout will not have. Run it before releasing, and after touching
# anything that lists res:// at runtime.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
command -v "$GODOT" >/dev/null 2>&1 || { echo "godot not on PATH; set GODOT=" >&2; exit 127; }

PCK="$PWD/build/export_test.pck"
mkdir -p build
"$GODOT" --headless --import >/dev/null 2>&1
if ! "$GODOT" --headless --export-pack "Linux" "$PCK" >/dev/null 2>&1; then
	echo "export failed — are the export templates for this Godot version installed?" >&2
	exit 1
fi
# run from elsewhere so the editor cannot fall back on the real project directory
cd build
"$GODOT" --headless --main-pack "$PCK" --script res://tests/export_smoke.gd 2>&1 \
	| grep -E "EXPORT TEST|^FAIL|packed:"
