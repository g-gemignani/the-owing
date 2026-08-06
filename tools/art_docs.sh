#!/usr/bin/env bash
# Regenerates BOTH generated art documents, together.
#
# Two reasons this is a script and not two lines in a README:
#
#   1. Godot prints its version banner to stdout before the script runs, so a bare
#      `> ART_ASSETS.md` captures it ABOVE the "GENERATED — do not edit" comment.
#      That is how the banner shipped at the top of ART_ASSETS.md. The strip below
#      is the fix, and it belongs in one place rather than in the six documents
#      that quote the command.
#   2. They come off the same tool and the same catalogues, so regenerating one
#      and not the other is how the pair drifts — which D101 already paid for
#      (both files spent two commits asking for art that was already installed).
#
#     tools/art_docs.sh          # rewrite both
#     tools/art_docs.sh --check  # non-zero if either is out of date
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
gen() { "$GODOT" --headless --script tools/art_manifest.gd ${1:+-- $1} | sed -n '/^<!-- GENERATED/,$p'; }

if [ "${1:-}" = "--check" ]; then
	rc=0
	diff -q <(gen) ART_ASSETS.md >/dev/null 2>&1 || { echo "ART_ASSETS.md: STALE" >&2; rc=1; }
	diff -q <(gen --prompts) ART_PROMPTS.md >/dev/null 2>&1 || { echo "ART_PROMPTS.md: STALE" >&2; rc=1; }
	[ "$rc" = 0 ] && echo "art docs: current"
	exit "$rc"
fi

gen           > ART_ASSETS.md
gen --prompts > ART_PROMPTS.md
head -n 6 ART_ASSETS.md | grep -m1 'files wanted' || true
echo "art docs: rewritten"
