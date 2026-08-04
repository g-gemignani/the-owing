#!/usr/bin/env bash
# Make the signing key that lets one Android build install OVER the last one, and print how
# to give it to CI (D157).
#
# Why this exists: Android identifies an app by the key that signed it. Until this key is
# configured, CI generates a fresh self-signed key per build, so a phone sees each APK as a
# different app claiming the same package name and refuses the install with "App not
# installed" — no mention of signatures anywhere in that message.
#
#   tools/make_release_key.sh                 # writes ./the-owing-release.keystore, prints the secret
#   tools/make_release_key.sh /path/to/out.jks
#
# Then set THREE repository secrets (Settings → Secrets and variables → Actions), or use the
# `gh` commands this prints:
#
#   ANDROID_KEYSTORE_BASE64      the base64 blob below
#   ANDROID_KEYSTORE_ALIAS       theowing
#   ANDROID_KEYSTORE_PASSWORD    whatever you chose
#
# KEEP THE FILE. It is not in the repository and it cannot be regenerated: a different key is
# a different app, so losing it means every existing install has to be uninstalled by hand
# once more. Back it up somewhere that is not this checkout.
#
# What it is NOT: a trusted identity. It is self-signed, so Android still calls the app
# "unknown source" and the Play Store would want a different key entirely. All it buys is
# that two builds are recognisably the same app.
set -euo pipefail

out="${1:-$PWD/the-owing-release.keystore}"
alias="${ALIAS:-theowing}"

# `keytool` ships with a JDK, and this project's dev shell had no JDK in it — so the first run
# of this script asked for a password twice and THEN died on `keytool: command not found`
# (D159). Checked first, and fixed rather than reported: the shell carries a JDK now, and if
# this is run outside it, `nix shell` fetches one for the length of the command, which is the
# same move `tools/gen_music.py` documents for ffmpeg.
if ! command -v keytool >/dev/null 2>&1; then
	if [ -n "${OWING_JDK_REEXEC:-}" ]; then
		echo "keytool is still missing inside the nix shell — that should not happen" >&2
		exit 127
	fi
	if command -v nix >/dev/null 2>&1; then
		echo "no keytool here; fetching a JDK through nix for this one command..." >&2
		# STOREPASS is exported rather than re-prompted: the inner run must not ask twice.
		export OWING_JDK_REEXEC=1
		exec nix shell nixpkgs#jdk --command "$0" "$@"
	fi
	cat >&2 <<'MISSING'
keytool not found. It comes with a JDK. Either:

  * enter this project's dev shell, which now carries one:   nix develop   (or `direnv allow`)
  * or run this script through nix directly:                 nix shell nixpkgs#jdk --command tools/make_release_key.sh
  * or install any JDK your distribution packages (openjdk / temurin).
MISSING
	exit 127
fi

if [ -e "$out" ]; then
	echo "refusing to overwrite $out — a new key would orphan every existing install" >&2
	exit 1
fi

# Asked for rather than defaulted: this password is the only thing between a copy of the file
# and a signed build, and a script that bakes one in is a script that publishes it.
if [ -z "${STOREPASS:-}" ]; then
	read -r -s -p "Keystore password (min 6 chars): " STOREPASS; echo
	read -r -s -p "Again: " confirm; echo
	[ "$STOREPASS" = "$confirm" ] || { echo "passwords differ" >&2; exit 1; }
fi
[ "${#STOREPASS}" -ge 6 ] || { echo "keytool requires at least 6 characters" >&2; exit 1; }

# 10000 days: the key outliving the project is the only failure mode that matters here, and
# an expired signing key means the same forced uninstall this exists to prevent.
keytool -keyalg RSA -keysize 2048 -genkeypair \
	-alias "$alias" -keypass "$STOREPASS" \
	-keystore "$out" -storepass "$STOREPASS" \
	-dname "CN=The Owing, O=The Owing, C=IT" \
	-validity 10000 -deststoretype pkcs12

echo
echo "keystore: $out"
echo "alias:    $alias"
keytool -list -v -keystore "$out" -storepass "$STOREPASS" -alias "$alias" \
	| grep -i "SHA256:" || true
echo
echo "--- set these three secrets on the repository ---"
echo
if command -v gh >/dev/null 2>&1; then
	echo "  base64 -w0 '$out' | gh secret set ANDROID_KEYSTORE_BASE64"
	echo "  printf %s '$alias' | gh secret set ANDROID_KEYSTORE_ALIAS"
	echo "  gh secret set ANDROID_KEYSTORE_PASSWORD    # paste the password"
else
	echo "  ANDROID_KEYSTORE_ALIAS    = $alias"
	echo "  ANDROID_KEYSTORE_PASSWORD = the password you just typed"
	echo "  ANDROID_KEYSTORE_BASE64   = the blob below (one line, no newlines)"
	echo
	base64 -w0 "$out"
	echo
fi
echo
echo "The FIRST build after this is signed by the new key, so it still needs one uninstall"
echo "of whatever is on the phone now. Every build after that installs over the last one."
