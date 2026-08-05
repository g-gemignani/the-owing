## Sound. Autoload.
##
## Everything it plays is *generated*, from ONE instrument: `tools/audio_voices.py` holds
## the voices, the tuning and the room, and both generators import it — the score from
## `gen_music.py` (D33, rewritten D173) and the 24 effects from `gen_sfx.py` (D150,
## rewritten D173). Provenance and the measurements that gate each run sit beside the
## files, in `assets/audio/PROVENANCE.txt`.
##
## Two rewrites, and the second one is why this file grew a mixer.
##
## D150: the effects were three CC0 Kenney packs at three sample rates over a score of our
## own, so the game answered a button, a sword and a won run in three different voices.
## D173: what replaced them was uniform and it was a chiptune — square waves, no room,
## fine at 22 kHz beside pixel art and nothing like the painted dungeon this game became.
## The set is now physically modelled (a plucked string, bowed strings, a choir, struck
## metal, frame drums, filtered air) at 44.1 kHz, and every file is recorded in a small
## room.
##
## Four things this owns:
##
## * **Buses.** Music and SFX under Master, created in code so there is no bus-layout
##   resource to keep in sync. The settings sliders drive these.
## * **The space.** A reverb on the SFX bus, retuned by *where the player is* — a blow in
##   a dungeon rings on and the same blow in a menu does not. This is the half of the
##   sound that cannot be baked into a file: the files carry a small close room so they
##   are never naked, and the bus carries the building. A hard limiter on Master keeps a
##   stinger over music from clipping, since the ladder deliberately puts stingers at 0.85.
## * **A voice pool.** Each play grabs a free player rather than allocating one, so a
##   burst of hits during a turn cannot spawn dozens of nodes.
## * **The score.** One looping voice on the Music bus, switched by where the player is.
##   Until this existed the Music bus and its slider were real and nothing was routed to
##   them: the slider adjusted the volume of silence, which is the placeholder problem the
##   sliders were built to end.
##
## Choosing sound by ear is not something I can do honestly, so neither generator does:
## each authors a recipe and then *measures* the result — seam, level, register, weight and
## whether a track has a beat for the score; level, length, register, onset and tail for the
## effects. A run that produces a file outside its band fails instead of shipping.
extends Node

const DIR := "res://assets/audio/"
const MUSIC_DIR := "res://assets/audio/music/"
## Twelve, up from eight in D173. A footstep now plays on every tile of the crawl, and
## `gold` is eleven struck grains inside one file rather than three, so the arithmetic of
## "how many can be ringing at once" changed: a hit landing while the previous hit's
## room tail is still going should not steal its voice.
const VOICES := 12
## How long a change of place takes to cross over. Long enough not to be a cut,
## short enough that walking through a menu is not a smear.
const FADE := 0.45

## Event name -> file stem. Call sites ask for an event, never a filename.
const SOUNDS := {
	"ui_click": "ui_click", "ui_select": "ui_select", "ui_back": "ui_back",
	"ui_confirm": "ui_confirm", "ui_denied": "ui_denied", "ui_open": "ui_open",
	"step": "step",
	"attack": "attack", "attack_heavy": "attack_heavy", "block": "block",
	"hurt": "hurt", "poison": "poison", "card_play": "card_play", "buff": "buff",
	"gold": "gold", "event": "event", "enter": "enter", "leave": "leave",
	"treasure": "treasure", "fuse": "fuse",
	"reward": "reward", "victory": "victory", "defeat": "defeat",
	"boss_cleared": "boss_cleared",
}

## How much an event may wander in pitch, per play. Everything unlisted gets `JITTER`.
##
## One number for the whole set was wrong in one direction: a footstep plays on every tile
## of a crawl — hundreds of times a floor, more than any other sound in the game — and at
## ±6% two in a row are recognisably the same recording, which is the thing that says
## "sample" rather than "boots". A stinger is the opposite case: `victory` is a phrase with
## a bell in it, and detuning a phrase by 6% is not variety, it is out of tune.
const JITTER := 0.06
const JITTER_BY_EVENT := {
	"step": 0.15, "attack": 0.09, "attack_heavy": 0.08, "hurt": 0.09, "block": 0.08,
	"gold": 0.05, "card_play": 0.07,
	"reward": 0.01, "victory": 0.01, "defeat": 0.01, "boss_cleared": 0.01,
	"buff": 0.02, "fuse": 0.02,
}
## And how much it may wander in level, in dB. Small: the generator's loudness ladder is
## the design, and this is only here so a repeated hit is not the identical waveform twice.
## Off for the stingers for the same reason their pitch is: they are music.
const LEVEL_JITTER_DB := 1.6

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
	"IsoRun": "dungeon",
	"Shop": "dungeon", "Encounter": "dungeon", "PauseMenu": "dungeon",
	"Combat": "combat",
}
const DEFAULT_SCORE := "world"

## The room the effects are heard in, keyed by the SAME name as the score.
##
## One table decides the music and the space together, because they are one answer to one
## question — where is the player — and two tables would let a screen get dungeon music in
## a menu-sized room. It is also why this is keyed by score name and not by scene: every
## screen already resolves to a score through `score_for`, including the ones nobody
## remembered to list.
##
## The numbers are `AudioEffectReverb`'s: `room` is size, `damp` is how much stone eats the
## top of each reflection, `pre` is the gap before the first reflection in ms — which is
## the parameter that actually says *large* — and `wet` is how much of it you hear. The
## dungeon is the big one; the menu is a room with furniture in it; a fight is tighter than
## the corridor outside it, because a fight needs its transients back.
const SPACES := {
	"menu":    {"room": 0.35, "damp": 0.65, "wet": 0.10, "pre": 6.0},
	"world":   {"room": 0.50, "damp": 0.55, "wet": 0.13, "pre": 12.0},
	"dungeon": {"room": 0.88, "damp": 0.32, "wet": 0.30, "pre": 28.0},
	"combat":  {"room": 0.70, "damp": 0.45, "wet": 0.20, "pre": 16.0},
	"boss":    {"room": 0.82, "damp": 0.38, "wet": 0.26, "pre": 22.0},
}
## How long the space takes to change. Longer than the music's crossfade on purpose: the
## score is allowed to cut across a scene change, but a room that resizes in half a second
## sounds like a filter sweep, and a room nobody notices changing is the point.
const SPACE_FADE := 1.2

var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}
var _music: AudioStreamPlayer
var _fade: Tween = null
var _score := ""
var _watched_scene: Node = null
var _reverb: AudioEffectReverb = null
## The room we are heading for, and where it is now. Walked toward the target in `_process`
## rather than with a Tween, because the target changes on every scene change and two Tweens
## animating one resource fight each other — the defect the music crossfade below documents,
## which there is no reason to make twice.
var _space := ""
var _room := {}

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
##
## The score and the room are both changed from here, off the one answer, so a screen
## cannot end up with one and not the other.
func _process(delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	_drift_room(delta)
	var cur := tree.current_scene
	if cur == _watched_scene:
		return
	_watched_scene = cur
	if cur != null:
		var where := score_for(cur.scene_file_path.get_file().get_basename())
		play_music(where)
		play_space(where)

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

## Change the room the effects are heard in. Asking for the one already set does nothing —
## the drift is toward a target, and restarting it every frame would freeze it.
##
## `_process` owns this in normal play: the room is a fact about which screen the player is
## on, and one table decides it. Calling it from anywhere else is a hint rather than a
## setting — the next scene change overrides it, and "the next scene change" includes the
## one that is still on its way when a screen's `_ready` runs, because the poller notices a
## new scene a frame or two after the scene itself does.
func play_space(where: String) -> void:
	if not SPACES.has(where) or where == _space:
		return
	_space = where

## Walk the live reverb toward the room the player is in. Linear over `SPACE_FADE`, which
## for a parameter nobody is listening to is indistinguishable from anything cleverer.
func _drift_room(delta: float) -> void:
	if _reverb == null or _space == "" or _room.is_empty():
		return
	var want: Dictionary = SPACES[_space]
	var step: float = clampf(delta / SPACE_FADE, 0.0, 1.0)
	var moved := false
	for k in want:
		var from: float = float(_room[k])
		var to: float = float(want[k])
		if absf(to - from) < 0.0005:
			continue
		_room[k] = from + (to - from) * step
		moved = true
	if moved:
		_write_room()

func _write_room() -> void:
	if _reverb == null:
		return
	_reverb.room_size = clampf(float(_room.get("room", 0.5)), 0.0, 1.0)
	_reverb.damping = clampf(float(_room.get("damp", 0.5)), 0.0, 1.0)
	_reverb.wet = clampf(float(_room.get("wet", 0.15)), 0.0, 1.0)
	_reverb.predelay_msec = maxf(1.0, float(_room.get("pre", 10.0)))

## The room currently in force, for tests and for anybody debugging the mix.
func current_space() -> String:
	return _space

## Music and SFX buses, created at runtime so there is no separate resource to
## drift out of step with this file.
##
## The effects on them are built here for the same reason: a `.tres` bus layout is a second
## place the mix lives, and the one that gets edited is never the one that ships.
func _ensure_buses() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx != -1 and _reverb == null:
		# `dry` stays at 1: this reverb ADDS a space, it does not replace the sound. Left
		# at Godot's default of 1.0 minus wet, a dungeon would quietly turn the effects
		# down by a third, and the loudness ladder the generator measures would stop being
		# the ladder the player hears.
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.spread = 1.0
		_reverb.hipass = 0.05
		AudioServer.add_bus_effect(sfx, _reverb)
		_room = (SPACES[DEFAULT_SCORE] as Dictionary).duplicate()
		_space = DEFAULT_SCORE
		_write_room()
	# A ceiling on Master, because the ladder is deliberately steep: a stinger peaks at
	# 0.85 and the score sits at 0.52 under it, and a run that ends while the boss track is
	# playing sums the two. Without this the sum clips, and digital clipping is the one
	# artefact that cannot be mistaken for a choice.
	var master := AudioServer.get_bus_index("Master")
	if master != -1 and AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.8
		lim.release = 0.15
		AudioServer.add_bus_effect(master, lim)

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

## How far this event may wander in pitch. Per event, because a footstep and a fanfare
## want opposite answers — see `JITTER_BY_EVENT`.
func jitter_for(event: String) -> float:
	return float(JITTER_BY_EVENT.get(event, JITTER))

## Play an event. Unknown or missing sounds are silently ignored — a missing
## effect should never take a screen down with it.
##
## `pitch_variation` is an override for a call site that knows better than the table; left
## out, which is every call site in the game, the table decides.
func play(event: String, pitch_variation: float = -1.0) -> void:
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
	# Pitch and level jitter, or a repeated hit is one recording played twice and reads as
	# a machine. Both are per event: a stinger gets almost none because it is music, and a
	# footstep gets the most because the crawl plays it more often than anything else.
	var spread: float = pitch_variation if pitch_variation >= 0.0 else jitter_for(event)
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	var level: float = LEVEL_JITTER_DB * clampf(spread / JITTER, 0.0, 1.0)
	p.volume_db = randf_range(-level, 0.0)
	p.play()
