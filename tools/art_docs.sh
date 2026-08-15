#!/usr/bin/env bash
# Regenerates ALL THREE generated art documents, together.
#
# Two reasons this is a script and not two lines in a README:
#
#   1. Godot prints its version banner to stdout before the script runs, so a bare
#      `> ART_ASSETS.md` captures it ABOVE the "GENERATED — do not edit" comment.
#      That is how the banner shipped at the top of ART_ASSETS.md. The strip below
#      is the fix, and it belongs in one place rather than in the six documents
#      that quote the command.
#   2. They come off the same tool and the same catalogues, so regenerating one
#      and not the others is how the set drifts — which D101 already paid for
#      (two of them spent two commits asking for art that was already installed).
#
# ART_REDO.md is the third and it is the odd one: it MEASURES the installed PNGs
# rather than reading a catalogue, so it is the slowest of the three and the only
# one whose output changes when nothing in `scripts/` did. That is the point — a
# set that has been re-rolled drops out of it without anybody editing a list.
#
#     tools/art_docs.sh          # rewrite all three
#     tools/art_docs.sh --check  # non-zero if any is out of date
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
gen() { "$GODOT" --headless --script tools/art_manifest.gd ${1:+-- $1} | sed -n '/^<!-- GENERATED/,$p'; }

if [ "${1:-}" = "--check" ]; then
	rc=0
	diff -q <(gen) ART_ASSETS.md >/dev/null 2>&1 || { echo "ART_ASSETS.md: STALE" >&2; rc=1; }
	diff -q <(gen --prompts) ART_PROMPTS.md >/dev/null 2>&1 || { echo "ART_PROMPTS.md: STALE" >&2; rc=1; }
	diff -q <(gen --redo) ART_REDO.md >/dev/null 2>&1 || { echo "ART_REDO.md: STALE" >&2; rc=1; }
	[ "$rc" = 0 ] && echo "art docs: current"
	exit "$rc"
fi

gen           > ART_ASSETS.md
gen --prompts > ART_PROMPTS.md
gen --redo    > ART_REDO.md
head -n 6 ART_ASSETS.md | grep -m1 'files wanted' || true
echo "art docs: rewritten"
