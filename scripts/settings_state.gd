## Player settings, persisted separately from the game save.
##
## Kept apart from MetaState on purpose: settings belong to the machine, not to a
## save slot, so deleting a save or switching slots must never change them.
extends Node

const PATH := "user://settings.json"
## Overridable so tests never write over the player's real settings.
##
## Sandboxed by default under `--headless` for the same reason MetaState is: the
## game is never played headless, so a headless writer is a test or a diagnostic,
## and this file was corrupted once by one that forgot to opt out. OWING_SANDBOX
## separates concurrently-running suites from each other; see meta_state.gd.
static var _sandbox := OS.get_environment("OWING_SANDBOX")
static var path_override := (
	("user://t_%s_settings.json" % _sandbox if _sandbox != "" else "user://t_headless_settings.json")
	if DisplayServer.get_name() == "headless" else "")

static func settings_path() -> String:
	return path_override if path_override != "" else PATH
const VERSION := 1

## Audio volumes, 0-100. These drive real mixer buses (see Audio.apply_volumes).
var master_volume: int = 80
var music_volume: int = 70
var sfx_volume: int = 80
var fullscreen: bool = true
## Float the damage, heal and block numbers off the thing that changed.
##
## Cosmetic only, and deliberately so: the bars and the enemy's intent carry the same
## information and are not affected by this. A setting that can hide what the player
## needs in order to choose a card is not a comfort setting, it is a difficulty one.
##
## Was dead for its whole life — persisted, offered in the menu, and read by nothing
## outside that menu (D130). The label promised "and intents" as well, which was the
## half that would have changed the game.
var show_numbers: bool = true

# --- combat effects (D129's six, and who they are not for) ----------------------
#
# Two controls rather than one, because they answer two different needs and a single
# "effects" slider serves neither properly. Speed is a pace preference; the toggle is
# an accessibility answer, and turning particles UP is not a reduced-motion setting.

## Draw the combat effects at all. Off is safe by construction: every effect goes
## through `Fx._ok`, nothing downstream depends on one having run, and the death
## dissolve is a stand-in for a slot the refresh already hid rather than the thing
## that removes it.
var effects_enabled: bool = true
## Percent of `Fx`'s authored durations. 100 is what D129 tuned by eye.
##
## Bounded well away from zero at the bottom: an effect fast enough to be a single
## frame is a flash, which is the one thing a motion-sensitive player is most likely
## to have come to this screen to stop. Off is the toggle's job, not this slider's.
var effect_speed: int = 100
const EFFECT_SPEED_MIN := 50
const EFFECT_SPEED_MAX := 200

# --- the crawl's movement pad (D168) -------------------------------------------

## Whether the dungeon draws an on-screen direction pad.
##
## Three states rather than a checkbox, because the honest default is neither on nor off:
## a phone has no keyboard and MUST have the pad, a desktop has WASD and is better without
## it, and `UI.touch_ui()` already knows which machine this is. So AUTO is the shipped
## value and the other two exist for the cases the platform test cannot see — a desktop
## played with a touchscreen, a tablet with a keyboard attached, and anyone who simply
## wants the floor uncovered.
## What AUTO resolves to lives in `UI.pad_visible()`, next to the platform test it
## depends on — this script holds the player's choice and nothing else, because it is an
## autoload and a compile-time reference out of one is what makes a script unloadable in
## the headless `--script` runs the test suite is made of.
enum Pad {AUTO, ALWAYS, NEVER}
var pad_mode: int = Pad.AUTO
const PAD_NAMES := ["Automatic", "Always", "Never"]

func _ready() -> void:
	load_settings()
	apply()

func apply() -> void:
	# fetched by path, not as a global: autoloads are not registered in headless
	# `--script` runs, and a compile-time reference would make this script
	# unloadable there (project convention — see CLAUDE/DESIGN notes).
	# Nothing to apply to UITheme any more: the interface is a fixed size and the
	# engine's canvas_items stretch handles the window (D65).
	var audio := (get_node_or_null("/root/Audio") if is_inside_tree() else null)
	if audio != null:
		audio.apply_volumes()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> void:
	var f := FileAccess.open(settings_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"version": VERSION,
			"master_volume": master_volume, "music_volume": music_volume,
			"sfx_volume": sfx_volume,
			"fullscreen": fullscreen, "show_numbers": show_numbers,
			"effects_enabled": effects_enabled, "effect_speed": effect_speed,
			"pad_mode": pad_mode,
		}))
		f.close()

func load_settings() -> void:
	if not FileAccess.file_exists(settings_path()):
		return
	var f := FileAccess.open(settings_path(), FileAccess.READ)
	if not f:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		return
	master_volume = clampi(int(d.get("master_volume", master_volume)), 0, 100)
	music_volume = clampi(int(d.get("music_volume", music_volume)), 0, 100)
	sfx_volume = clampi(int(d.get("sfx_volume", sfx_volume)), 0, 100)
	# `ui_scale` may still be present in an older settings file. It is read by
	# nobody now and deliberately not carried forward: the zoom it drove is gone.
	fullscreen = bool(d.get("fullscreen", fullscreen))
	show_numbers = bool(d.get("show_numbers", show_numbers))
	# absent in a settings file written before D130, and `get`'s default is what makes
	# that a non-event: an older file simply keeps the shipped defaults. That is why
	# there is no migration step here and VERSION did not move.
	effects_enabled = bool(d.get("effects_enabled", effects_enabled))
	effect_speed = clampi(int(d.get("effect_speed", effect_speed)),
		EFFECT_SPEED_MIN, EFFECT_SPEED_MAX)
	pad_mode = clampi(int(d.get("pad_mode", pad_mode)), 0, PAD_NAMES.size() - 1)
