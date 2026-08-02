# Building and running

## Just playing it

Don't build it — download it. Every green push to `main` publishes Linux, Windows and
macOS binaries under a permanent link:

**<https://github.com/g-gemignani/deckcrawl/releases/tag/latest>**

Or, from a checkout with **Godot 4.7**:

```bash
GODOT=/path/to/godot ./run.sh      # or put godot on PATH and run ./run.sh
```

## The release pipeline

`.github/workflows/ci.yml` runs the suite, checks every preset is still exportable, and
then — only from `main`, only after both of those pass — exports the three desktop
platforms and republishes them under the fixed tag `latest`. One Ubuntu runner does all
three; Godot cross-exports Windows and macOS from Linux without a Windows or a Mac
anywhere in the loop.

Three things about it are deliberate and easy to undo by accident:

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

Nothing in it needs a secret. `GITHUB_TOKEN` with `contents: write` is enough, and the
job refuses to run outside this repository so a fork cannot try to publish into it.

Android and iOS are **exportable but not published**: see [Mobile](#mobile) below. The
blocker is a toolchain and a paid identity, not the project — `export_ready.sh` proves
that on every run.

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
godot --headless --export-release "Linux"   "$PWD/build/linux/deckcrawl.x86_64"
godot --headless --export-release "Windows" "$PWD/build/windows/deckcrawl.exe"
godot --headless --export-release "macOS"   "$PWD/build/macos/deckcrawl.zip"
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
| **Linux** | `chmod +x deckcrawl.x86_64 && ./deckcrawl.x86_64` |
| **Windows** | double-click `deckcrawl.exe` (unsigned: SmartScreen will warn once → *More info* → *Run anyway*) |
| **macOS** | unzip, then `xattr -dr com.apple.quarantine Deckcrawl.app` and open it. Unsigned and un-notarised, so Gatekeeper blocks it otherwise |
| **Android** | `adb install deckcrawl.apk`, or copy it to the device and allow install from unknown sources |
| **iOS** | must be built on macOS; see below |

> On **NixOS** a stock Linux binary will not start (`Could not start dynamically
> linked executable`). Either run it with `steam-run`, or patch it:
> `patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" deckcrawl.x86_64`

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
godot --headless --export-release "Android" "$PWD/build/android/deckcrawl.apk"
```

The preset is already in `export_presets.cfg`.

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
