## Sound. Autoload.
##
## Sounds are CC0 Kenney packs (`assets/audio/`, licences alongside). Unlike the
## art packs these ship *named* files, so the mapping is semantically correct
## rather than arbitrary: `knifeSlice` really is the attack sound.
##
## Two things this owns:
##
## * **Buses.** Music and SFX are separate buses under Master, created in code so
##   there is no bus-layout resource to keep in sync. The settings sliders were
##   placeholders until now; they drive these.
## * **A voice pool.** Each play grabs a free player rather than allocating one, so
##   a burst of hits during a turn cannot spawn dozens of nodes.
extends Node

const DIR := "res://assets/audio/"
const VOICES := 8

## Event name -> file stem. Call sites ask for an event, never a filename.
const SOUNDS := {
	"ui_click": "ui_click", "ui_select": "ui_select", "ui_back": "ui_back",
	"ui_confirm": "ui_confirm", "ui_denied": "ui_denied", "ui_open": "ui_open",
	"attack": "attack", "attack_heavy": "attack_heavy", "block": "block",
	"hurt": "hurt", "poison": "poison", "card_play": "card_play", "buff": "buff",
	"gold": "gold", "event": "event", "enter": "enter", "leave": "leave",
	"treasure": "treasure", "fuse": "fuse",
	"reward": "reward", "victory": "victory", "defeat": "defeat",
	"boss_cleared": "boss_cleared",
}

var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}

func _ready() -> void:
	_ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	apply_volumes()

## Music and SFX buses, created at runtime so there is no separate resource to
## drift out of step with this file.
func _ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")

## Map the 0-100 settings sliders onto bus volumes.
## Linear-to-dB, because a linear slider on a dB scale feels wrong everywhere but
## the top; 0 mutes outright rather than leaving a whisper at -80 dB.
static func to_db(percent: int) -> float:
	if percent <= 0:
		return -80.0
	return linear_to_db(clampf(float(percent) / 100.0, 0.0001, 1.0))

func apply_volumes() -> void:
	var s := get_node_or_null("/root/SettingsState")
	if s == null:
		return
	_set_bus("Master", int(s.master_volume))
	_set_bus("Music", int(s.music_volume))
	_set_bus("SFX", int(s.sfx_volume))

func _set_bus(name: String, percent: int) -> void:
	var i := AudioServer.get_bus_index(name)
	if i == -1:
		return
	AudioServer.set_bus_volume_db(i, to_db(percent))
	AudioServer.set_bus_mute(i, percent <= 0)

func stream(event: String) -> AudioStream:
	if _cache.has(event):
		return _cache[event]
	if not SOUNDS.has(event):
		return null
	var path: String = DIR + String(SOUNDS[event]) + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var st := load(path) as AudioStream
	_cache[event] = st
	return st

## Play an event. Unknown or missing sounds are silently ignored — a missing
## effect should never take a screen down with it.
func play(event: String, pitch_variation: float = 0.06) -> void:
	var st := stream(event)
	if st == null or _voices.is_empty():
		return
	# round-robin, reusing the oldest voice if all are busy
	var p := _voices[_next]
	for v in _voices:
		if not v.playing:
			p = v
			break
	_next = (_next + 1) % _voices.size()
	p.stream = st
	# a little pitch jitter, or repeated hits sound like one long machine noise
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()
