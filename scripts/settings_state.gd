## Player settings, persisted separately from the game save.
##
## Kept apart from MetaState on purpose: settings belong to the machine, not to a
## save slot, so deleting a save or switching slots must never change them.
extends Node

const PATH := "user://settings.json"
## Overridable so tests never write over the player's real settings.
static var path_override := ""

static func settings_path() -> String:
	return path_override if path_override != "" else PATH
const VERSION := 1

## Audio volumes, 0-100. These drive real mixer buses (see Audio.apply_volumes).
var master_volume: int = 80
var music_volume: int = 70
var sfx_volume: int = 80
var ui_scale: float = 1.6
var fullscreen: bool = true
## Show the balance-facing numbers (incoming damage, intents) in combat.
var show_numbers: bool = true

func _ready() -> void:
	load_settings()
	apply()

func apply() -> void:
	# fetched by path, not as a global: autoloads are not registered in headless
	# `--script` runs, and a compile-time reference would make this script
	# unloadable there (project convention — see CLAUDE/DESIGN notes).
	var theme := (get_node_or_null("/root/UITheme") if is_inside_tree() else null)
	if theme != null:
		theme.set_scale_silent(ui_scale)
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
			"sfx_volume": sfx_volume, "ui_scale": ui_scale,
			"fullscreen": fullscreen, "show_numbers": show_numbers,
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
	ui_scale = clampf(float(d.get("ui_scale", ui_scale)), 0.6, 3.0)
	fullscreen = bool(d.get("fullscreen", fullscreen))
	show_numbers = bool(d.get("show_numbers", show_numbers))
