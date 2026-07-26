## Sound. Autoload.
##
## Sounds are CC0 Kenney packs (`assets/audio/`, licences alongside). Unlike the
## art packs these ship *named* files, so the mapping is semantically correct
## rather than arbitrary: `knifeSlice` really is the attack sound.
##
## Three things this owns:
##
## * **Buses.** Music and SFX are separate buses under Master, created in code so
##   there is no bus-layout resource to keep in sync. The settings sliders drive
##   these.
## * **A voice pool.** Each play grabs a free player rather than allocating one, so
##   a burst of hits during a turn cannot spawn dozens of nodes.
## * **The score.** One looping voice on the Music bus, switched by where the
##   player is. Until this existed the Music bus and its slider were real and
##   nothing was routed to them: the slider adjusted the volume of silence, which
##   is the same placeholder problem the sliders were built to end.
##
## The music is *generated* (`tools/gen_music.py`), not a downloaded pack, and the
## reasoning is in that file: there was no CC0 music pack whose licence I could
## verify the way the art packs' were, and choosing tracks by ear is not something
## I can do honestly. It is measured instead — loop seam, level, distinctness.
extends Node

const DIR := "res://assets/audio/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOICES := 8
## How long a change of place takes to cross over. Long enough not to be a cut,
## short enough that walking through a menu is not a smear.
const FADE := 0.45

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

## Score name -> file stem in MUSIC_DIR.
const SCORES := {
	"menu": "music_menu", "world": "music_world", "dungeon": "music_dungeon",
	"combat": "music_combat", "boss": "music_boss",
}

## Which score a screen gets. ONE table, read in ONE place (`_process` below
## watches the current scene), so no screen has to remember to ask for music and
## a new screen cannot be silent by omission — the same reason `UI.button`
## attaches its own click sound. Anything unlisted gets `DEFAULT_SCORE`.
const SCENE_SCORE := {
	"MainMenu": "menu", "SaveSlots": "menu", "StarterKit": "menu", "Victory": "menu",
	"Map": "dungeon", "DeckRun": "dungeon", "DiceRun": "dungeon", "IsoRun": "dungeon",
	"Shop": "dungeon", "Encounter": "dungeon", "PauseMenu": "dungeon",
	"Combat": "combat",
}
const DEFAULT_SCORE := "world"

var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _music: AudioStreamPlayer
var _fade: Tween = null
var _score := ""
var _watched_scene: Node = null

func _ready() -> void:
	_ensure_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	# The stingers (victory, defeat, boss cleared) stay on SFX although they came
	# from a music pack: they are feedback for a thing that just happened, and a
	# player who turns the music off still wants to hear that they won.
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	apply_volumes()

## Follow the player from screen to screen. Polling the current scene beats asking
## each screen to announce itself: screens are entered from a dozen places, some
## of them raw `change_scene_to_file`, and the one that forgets is the one that
## goes quiet.
func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cur := tree.current_scene
	if cur == _watched_scene:
		return
	_watched_scene = cur
	if cur != null:
		play_music(score_for(cur.scene_file_path.get_file().get_basename()))

## The score a screen should carry. Combat is the one screen whose music depends
## on more than which screen it is.
func score_for(scene_name: String) -> String:
	if scene_name == "Combat":
		var gs := get_node_or_null("/root/GameState")
		if gs != null and int(gs.pending.get("type", -1)) == gs.NodeType.BOSS:
			return "boss"
	return String(SCENE_SCORE.get(scene_name, DEFAULT_SCORE))

func music_stream(score: String) -> AudioStream:
	if not SCORES.has(score):
		return null
	var key := "music:" + score
	if _cache.has(key):
		return _cache[key]
	var path: String = MUSIC_DIR + String(SCORES[score]) + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var st := load(path) as AudioStream
	# Set here rather than trusting the .import: a track that does not loop stops
	# after half a minute, and silence reads as "there is no music" (D32's lesson
	# about a missing sound being indistinguishable from intent).
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_cache[key] = st
	return st

## Switch the score. Asking for the one already playing does nothing — walking
## between two dungeon screens must not restart the track.
func play_music(score: String) -> void:
	if score == _score:
		return
	var st := music_stream(score)
	if st == null:
		return
	_score = score
	if not _music.playing:
		_music.stream = st
		_music.volume_db = 0.0
		_music.play()
		return
	# Kill the previous crossfade first. Walking quickly through menus starts one
	# per screen, and two tweens animating the same volume fight each other — the
	# audible result is a track that stutters instead of one that changes.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	var tw := create_tween()
	_fade = tw
	tw.tween_property(_music, "volume_db", -40.0, FADE * 0.5)
	tw.tween_callback(func():
		_music.stream = st
		_music.play())
	tw.tween_property(_music, "volume_db", 0.0, FADE)

## What is playing right now (""/none). For tests and for the settings screen.
func current_score() -> String:
	return _score if _music != null and _music.playing else ""

## Which bus the score is on. The whole point of the feature, so it is checkable.
func music_bus() -> String:
	return _music.bus if _music != null else ""

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
