## Which build this is — one place, because the answer has to be identical everywhere it is
## shown and the string is the only thing a tester can quote back (D156).
##
## The release channel is a rolling tag: every green push replaces the assets under it, so
## `TheOwing-android.apk` is the name of every Android build there has ever been and a phone
## holding one cannot say which. The release notes record the commit, but the notes are on a
## web page and the build is on the phone. So the commit travels *inside* the build.
##
## Read from `application/config/version` in `project.godot`, which is in the PCK by
## construction — no export filter to remember, nothing to forget to include. The committed
## value is the dev sentinel; `tools/stamp_build.sh` rewrites it per export in CI.
class_name BuildInfo
extends RefCounted

## The setting the stamp lives in.
const KEY := "application/config/version"
## What an unstamped checkout says. A build carrying this was made by hand, not by CI, and
## saying so is more useful than a version number that is not one.
const DEV_SUFFIX := "-dev"


## The raw stamp: `0.1.0-dev`, or `0.1.0+2026-08-03.318918d` from CI.
static func version() -> String:
	var v := String(ProjectSettings.get_setting(KEY, ""))
	return v if v != "" else "unknown"


## Was this built from an unstamped checkout?
static func is_dev() -> bool:
	return version().ends_with(DEV_SUFFIX) or version() == "unknown"


## The commit this was built from, or "" for a dev build. Split out because it is the part
## worth quoting in a bug report, and a caller should not have to know the stamp's grammar.
static func commit() -> String:
	var v := version()
	var plus := v.find("+")
	if plus < 0:
		return ""
	var tail := v.substr(plus + 1)
	var dot := tail.rfind(".")
	return tail.substr(dot + 1) if dot >= 0 else tail


## One line, for a corner of the screen. Deliberately short: on a phone this sits under four
## buttons and competes with nothing.
static func label() -> String:
	return "v%s" % version()
