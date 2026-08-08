#!/usr/bin/env bash
# Regenerates the download table in README.md, in place, between the markers.
#
# The sizes used to be typed. All four were wrong by about three megabytes — not
# because anybody mistyped them, but because they were correct once, in 2024, and
# the game has had art added to it since. A number that is only true on the day it
# is written is the D34 shape in a document: two places state one fact, and the one
# nobody re-runs is the one the reader believes.
#
#     tools/readme_downloads.sh          # rewrite the block
#     tools/readme_downloads.sh --check  # non-zero if the block is out of date
#
# The sizes come from the PUBLISHED RELEASE rather than from a local build, because
# what the table documents is what a player downloads. A local `staged/` or `build/`
# copy is a different file — a different commit, possibly a different set of export
# presets — and sizing the table off it would make the page accurate about a build
# nobody can reach.
#
# No authentication: the repository is public and the releases endpoint is
# unauthenticated, so this runs anywhere `curl` does. `gh` is used when it is present
# and logged in, purely because it is politer to the rate limit.
set -euo pipefail
cd "$(dirname "$0")/.."

DOC=README.md
REPO=g-gemignani/the-owing
TAG=latest
BEGIN='<!-- BEGIN GENERATED DOWNLOADS -- tools/readme_downloads.sh -->'
END='<!-- END GENERATED DOWNLOADS -->'

# What each asset is called on the page, and what to do with it once it has landed.
# Keyed by the asset filename, which is what CI actually uploads — so an asset that
# stops being built drops out of the table by being absent rather than by somebody
# noticing.
label_for() {
	case "$1" in
		TheOwing-linux-x86_64.zip)   echo "Linux" ;;
		TheOwing-windows-x86_64.zip) echo "Windows" ;;
		TheOwing-macos-universal.zip) echo "macOS" ;;
		TheOwing-android.apk)        echo "Android phone or tablet" ;;
		*) echo "$1" ;;
	esac
}

# Commonest platform first, not alphabetical — a reader looking for their own machine should
# find it near the top, and sorting by label put Android there. Explicit rather than "the order
# the API answered in", because that order is not stable and `--check` would then report a
# block as stale on a run that changed nothing.
rank_for() {
	case "$1" in
		TheOwing-windows-x86_64.zip) echo 1 ;;
		TheOwing-macos-universal.zip) echo 2 ;;
		TheOwing-linux-x86_64.zip)   echo 3 ;;
		TheOwing-android.apk)        echo 4 ;;
		*) echo 9 ;;
	esac
}

# Backticks are written PLAIN here, not backslash-escaped. They pass through `awk -v`, which
# treats `\`` as an unknown escape, warns, and silently drops the backslash — so the escaped
# version produced correct output and a warning on every run, which is the kind of thing that
# gets ignored until it is hiding something real.
opening_for() {
	case "$1" in
		TheOwing-linux-x86_64.zip)
			echo 'Unzip, then run `TheOwing.x86_64`. If it will not start, mark it executable first: `chmod +x TheOwing.x86_64`' ;;
		TheOwing-windows-x86_64.zip)
			echo 'Unzip and run **TheOwing.exe**. Windows shows a blue "unrecognised app" box the first time — click **More info**, then **Run anyway**' ;;
		TheOwing-macos-universal.zip)
			echo 'Unzip, then **right-click the app and choose Open** (not double-click) so macOS offers you the Open button' ;;
		TheOwing-android.apk)
			echo 'Copy it to your phone and tap it. Android 7 or newer. If it says *App not installed*, delete the older copy first' ;;
		*) echo "" ;;
	esac
}

# Whole megabytes. Deliberately coarse: the exact byte count changes on every push and
# a table quoting it would be stale within the hour, which is the failure this script
# exists to end rather than to automate. Rounded, a size only moves when something
# genuinely got bigger.
mib() { echo $(( ($1 + 524288) / 1048576 )); }

fetch() {
	if command -v gh >/dev/null 2>&1 \
			&& gh release view "$TAG" --repo "$REPO" --json assets >/dev/null 2>&1; then
		gh release view "$TAG" --repo "$REPO" --json assets \
			--jq '.assets[] | "\(.name)\t\(.size)"'
		return
	fi
	curl -sS --fail --max-time 30 \
		"https://api.github.com/repos/$REPO/releases/tags/$TAG" \
		| python3 -c '
import json, sys
for a in json.load(sys.stdin).get("assets", []):
    print("%s\t%d" % (a["name"], a["size"]))
'
}

build() {
	local assets
	assets=$(fetch)
	[ -n "$assets" ] || { echo "no release assets found for $REPO@$TAG" >&2; return 1; }

	echo "$BEGIN"
	echo
	echo '| | download | opening it |'
	echo '|---|---|---|'
	while IFS=$'\t' read -r name size; do
		[ -n "$name" ] || continue
		printf '%s\t%s\t%s\t%s\n' "$(rank_for "$name")" "$(label_for "$name")" "$name" "$size"
	done <<<"$assets" | sort -t$'\t' -k1,1n -k2,2 \
			| while IFS=$'\t' read -r _rank label name size; do
		printf '| **%s** | [`%s`](https://github.com/%s/releases/download/%s/%s) (%s MB) | %s |\n' \
			"$label" "$name" "$REPO" "$TAG" "$name" "$(mib "$size")" "$(opening_for "$name")"
	done
	echo
	echo "<sub>Sizes read from the current build by \`tools/readme_downloads.sh\` — not typed here,"
	echo "because typed ones were three megabytes stale and nobody could tell (D207).</sub>"
	echo "$END"
}

if [ "${1:-}" = "--check" ]; then
	current=$(awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$DOC")
	if [ "$current" = "$(build)" ]; then
		echo "readme downloads: current"
	else
		echo "readme downloads: STALE — run tools/readme_downloads.sh" >&2
		exit 1
	fi
	exit 0
fi

if ! grep -qF "$BEGIN" "$DOC"; then
	echo "$DOC has no generated-downloads block; add the markers first" >&2
	exit 1
fi

tmp=$(mktemp)
block=$(build)
awk -v b="$BEGIN" -v e="$END" -v block="$block" '
	$0==b { print block; skip=1; next }
	$0==e { skip=0; next }
	!skip { print }
' "$DOC" > "$tmp"
mv "$tmp" "$DOC"
echo "readme downloads: rewritten"
