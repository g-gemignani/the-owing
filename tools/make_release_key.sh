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
