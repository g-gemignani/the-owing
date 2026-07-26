#!/usr/bin/env bash
# Launch the game. Resolves Godot in this order:
#   $GODOT  ->  godot on PATH  ->  the flake dev shell
#
# An earlier version hardcoded a /nix/store path from one machine. That works
# until the store is garbage-collected, and never works for anyone else.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "${GODOT:-}" && -x "${GODOT}" ]]; then
	exec "$GODOT" "$@"
fi
if command -v godot >/dev/null 2>&1; then
	exec godot "$@"
fi
if command -v nix >/dev/null 2>&1 && [[ -f flake.nix ]]; then
	exec nix develop --command godot "$@"
fi

echo "Godot 4.7 not found. Install it, put it on PATH, or set GODOT=/path/to/godot" >&2
exit 127
