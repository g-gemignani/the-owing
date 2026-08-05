# Building and running

## Just playing it

Don't build it — download it. Every green push to `main` publishes Linux, Windows and
macOS binaries under a permanent link:

**<https://github.com/g-gemignani/the-owing/releases/tag/latest>**

Or, from a checkout with **Godot 4.7**:

```bash
GODOT=/path/to/godot ./run.sh      # or put godot on PATH and run ./run.sh
```

## The release pipeline

`.github/workflows/ci.yml` runs the suite, checks every preset is still exportable, and
then — only from `main`, only after both of those pass — builds **all five platforms**
and republishes them under the fixed tag `latest`.

| job | runner | why |
|---|---|---|
| `build-desktop` | `ubuntu-latest` | Godot cross-exports Windows and macOS from Linux, so one runner does three platforms |
| `build-android` | `ubuntu-latest` | the runner image already carries a JDK and the SDK; Godot finds both through `JAVA_HOME` and `ANDROID_HOME` |
| ~~`build-ios`~~ | `macos-latest` | written, **commented out** — it never got past `xcodebuild` (D147) |

Five things about it are deliberate and easy to undo by accident:

* **The tag is fixed, and there is no version history.** The README links to
  `releases/download/latest/<file>`, which is only a stable URL because the tag never
  moves off that name. A release channel that depends on somebody remembering to cut a
  version tag is a download link that goes stale, which is worse than no link. Add a
  `v*`-triggered job beside it the day there is a v1; do not repoint this one.
* **The release is deleted and recreated, not edited.** Force-moving a git tag under an
  existing GitHub release leaves the release still recording the *old* commit, and
  nothing in `gh release edit` can correct it — so the page would state a provenance
  that is false. The cost is a few seconds where the download 404s.
* **The exit code of `--export-release` is not trusted.** It returns non-zero on import
  warnings that did not stop it, so the job checks the output file exists and clears a
  size floor instead — the same verdict `tests/export_ready.sh` uses, for the same
  reason. A zero-byte file at the right path is precisely what would otherwise be
  published.

* **The Android key is stable if the repository has one, and a throwaway if it does not.**
  Either way it is passed in through `GODOT_ANDROID_KEYSTORE_RELEASE_*` — the one part of
  Android export designed for CI, so no editor-settings file has to be forged — and either
  way the APK is installable rather than *trusted*; a Play Store build needs a real identity
  held outside this repository.

  Which one matters to anyone with a phone. **Android identifies an app by the key that
  signed it, not by its version**, so two builds signed by different keys are two different
  apps claiming one package name and the installer refuses the second with *"App not
  installed"* — a message that never mentions signatures, which is why it was reported as a
  bug in the build (D157). With `ANDROID_KEYSTORE_BASE64` and
  `ANDROID_KEYSTORE_PASSWORD` set (plus `ANDROID_KEYSTORE_ALIAS` if the key does not use the
  default `theowing`), every build installs over the last one. The password has no default:
  with a real keystore supplied, a missing one is an error rather than a guess that reports
  itself as a wrong password (D162). Without it, CI generates a fresh key per build and every install needs an
  uninstall first — which is deliberate rather than lazy, because a fork with no secrets
  must still produce an APK, and a job that fails for a missing secret teaches people to
  ignore red builds.

  They are **repository secrets** — Settings → Secrets and variables → Actions → *Secrets*.
  Not the *Variables* tab (plaintext, and not read for these), and not *environment* secrets:
  `build-android` declares no `environment:`, so those would be invisible to it and the build
  would quietly fall back to a throwaway key. Environments are for approval gates and
  per-target keys; one rolling channel with one key needs neither (D161).

  `tools/make_release_key.sh` creates the key and prints the three secrets to set. It needs
  `keytool`, which comes with a JDK: the dev shell carries one (`nix develop`, or `direnv
  allow`), and run outside it the script fetches one through `nix shell nixpkgs#jdk` for the
  length of the command rather than failing — the first version checked for it *after* asking
  for a password twice (D159). **Keep the file**: a different key is a different app, so losing it costs everyone one more uninstall.
  `version/code` is stamped from the CI run number (D156), which is the other half of what an
  update needs — a newer code AND a matching signature.
* **`build-ios` is commented out, not deleted.** It ran for three rounds and never got
  past `xcodebuild`; the job log needs repository-admin rights to read, so continuing
  meant blind iteration against a toolchain that cannot be reproduced off a Mac. A
  permanently red job trains everyone to ignore the one place a failure is supposed to
  be visible. The whole block is preserved verbatim in `ci.yml` — including the parts
  that DID work: the macOS half of `setup-godot`, and the CI-only preset patch (a
  placeholder team ID plus `export_project_only`) without which Godot refuses an iOS
  export even when it is only being asked for an Xcode project. Restart from the
  `xcodebuild -list` dump the job prints before it fails. `export_ready.sh` still proves
  on every run that the preset is blocked by the toolchain and never by the project.

Nothing in it needs a secret. `GITHUB_TOKEN` with `contents: write` is enough, and the
jobs refuse to run outside this owner's repositories so a fork cannot try to publish
into it.

**The Android build is not signed for distribution and has not been run on real
hardware.** See [Is it actually playable on a phone?](#is-it-actually-playable-on-a-phone)
— the answer is still "nobody has checked".

## Building distributables

Export templates must match the engine version exactly. Install them once, either
from the editor (*Editor → Manage Export Templates*) or by hand:

```bash
V=4.7.1-stable
curl -L -o templates.tpz \
  "https://github.com/godotengine/godot/releases/download/$V/Godot_v${V}_export_templates.tpz"
mkdir -p ~/.local/share/godot/export_templates/4.7.1.stable
unzip -j templates.tpz 'templates/*' -d ~/.local/share/godot/export_templates/4.7.1.stable
```

Then, from the project root:

```bash
godot --headless --export-release "Linux"   "$PWD/build/linux/TheOwing.x86_64"
godot --headless --export-release "Windows" "$PWD/build/windows/TheOwing.exe"
godot --headless --export-release "macOS"   "$PWD/build/macos/TheOwing.zip"
```

Presets live in `export_presets.cfg` and contain no credentials.

### Keeping every platform buildable

```bash
GODOT=/path/to/godot tests/export_ready.sh
```

Attempts every preset and classifies each failure. A missing JDK, Android SDK or
App Store team ID is reported as `skip` — those are toolchain and credentials,
which no repository can carry. Anything else is a `FAIL`, because it means the
*project* has regressed and installing the SDK would not be enough.

```
  built   Linux
  built   Windows
  built   macOS
  skip    Android — toolchain only: A valid Java SDK path is required...
  skip    iOS     — toolchain only: App Store Team ID not specified.
```

So the day you install the Android SDK, one command builds the APK with no other
edits. `tests/test_content.gd` covers the half that needs no templates: presets
exist for all five platforms, `import_etc2_astc` is on (every arm64 target refuses
without it), landscape orientation is set, and touch has a path to read cards.

### Verify the build, don't assume it

```bash
GODOT=/path/to/godot tests/export.sh
```

This packs the project and runs `tests/export_smoke.gd` **inside the pack**. It
exists because an exported PCK does not contain source `.png` files — it contains
the imported texture plus a `.import` sidecar, and that sidecar is what directory
listing returns. Code matching `.png` found every sprite in development and none
in a shipped build. Nothing but a real export can catch that.

## Running each build

| platform | how |
|----------|-----|
| **Linux** | `chmod +x TheOwing.x86_64 && ./TheOwing.x86_64` |
| **Windows** | double-click `TheOwing.exe` (unsigned: SmartScreen will warn once → *More info* → *Run anyway*) |
| **macOS** | unzip, then `xattr -dr com.apple.quarantine "The Owing.app"` and open it. Unsigned and un-notarised, so Gatekeeper blocks it otherwise |
| **Android** | `adb install TheOwing-android.apk`, or copy it to the device and allow install from unknown sources |
| **iOS** | must be built on macOS; see below |

> On **NixOS** a stock Linux binary will not start (`Could not start dynamically
> linked executable`). Either run it with `steam-run`, or patch it:
> `patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" TheOwing.x86_64`

## Mobile

Both mobile targets need a toolchain this repository cannot provide.

### Android

Needs a JDK (17+) and the Android SDK with `platform-tools` and `build-tools`:

```bash
# JDK and SDK command-line tools, then:
sdkmanager "platform-tools" "build-tools;34.0.0" "platforms;android-34"
keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
  -keystore ~/.android/debug.keystore -storepass android \
  -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
```

Point Godot at both in *Editor Settings → Export → Android* (`java_sdk_path`,
`android_sdk_path`), then:

```bash
godot --headless --export-release "Android" "$PWD/build/android/TheOwing.apk"
```

The preset is already in `export_presets.cfg`.

**How wide the APK reaches, and why the preset says so out loud.** Android 7.0 is the
oldest version that can run it, and that is Godot's floor rather than a choice — the
engine's own `config.gradle` pins `minSdk 24`, so going lower means rebuilding the
native libraries against a lower NDK API. Nothing in the pipeline can move it.

What the pipeline *does* control is the ABI, and there the default was wrong. Godot
ships all four ABIs inside the export template and copies out only the ones the preset
asks for; asking for nothing means `arm64-v8a` alone, which a 32-bit-only phone cannot
install at all. So the preset now names all four explicitly — both ARM ABIs on, both
x86 off:

```ini
architectures/armeabi-v7a=true
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
```

That costs 25 MB (64 MB → 89 MB). The x86 pair stays off: it is another 25 MB each and
buys emulators, not phones. Two things check this, because the editor **rewrites**
`export_presets.cfg` whenever the export dialog is touched and a rewrite that drops the
keys is silent — `tests/test_content.gd` reads the preset on every PR, and CI reads the
ABIs back out of the finished APK (D170).

### iOS

**Requires macOS with Xcode.** Apple's toolchain does not run on Linux or Windows,
and there is no way around it. On a Mac, add an iOS preset, supply a bundle
identifier and a signing team, export, then build the generated Xcode project.

## Is it actually playable on a phone?

The layout is landscape (`window/handheld/orientation=4`) and touch generates the
button presses the UI needs. One interaction differs by input device:

* **Mouse** — hover a card to enlarge it and read its rules text.
* **Touch** — *tap once* to open a card and read it, *tap again* to play it.

A finger sends no hover events at all, so without that split the only way to learn
what a card does on a phone would be to play it. `UI.touch_ui()` picks the mode.

Untested on real hardware: nobody has run this on a phone yet. Text size at phone DPI
is the most likely thing to need work, and there is **no runtime knob for it** — the
interface is laid out at a fixed 1280×720 and the engine's `canvas_items` stretch
scales the whole canvas to the window (D65). `UITheme.UI_SCALE` is a constant `1.0`
that nothing varies and Settings does not expose. If phone text turns out to be too
small, the fix is the layout or the font, not a scale slider.
