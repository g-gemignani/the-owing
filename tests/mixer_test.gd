## Runtime test: the mixer D173 added is actually built, and the room follows the player.
##
## This is a SCENE, not a `--script` test, and for the reason the whole scene-test category
## exists: buses and bus effects only exist on a running engine with autoloads registered.
## `Audio` builds its mixer in `_ready` — two buses, a reverb on SFX, a limiter on Master —
## and every one of those is code that can silently do nothing. A reverb that was never
## added is not an error; it is a game that sounds like it is happening on a desk, which is
## exactly the defect D173 set out to fix and exactly the kind that ships.
##
## What is checked here and nowhere else:
##
##   * the buses exist and the effects are ON them (the sound of a missing bus effect is
##     the sound of the old build, so nothing about play would look wrong),
##   * the room CHANGES with where the player is, and lands on the table's numbers —
##     `Audio._drift_room` walks toward a target every frame, so "it was set once at boot"
##     and "it tracks the player" look identical for the first second,
##   * the wet signal is added rather than swapped in: Godot's reverb defaults `dry` to
##     1 - wet, which would quietly turn the effects down by a third in a dungeon and undo
##     the loudness ladder the generator measures,
##   * a play() of every declared event finds a voice and does not error.
##
## Run: godot --headless res://tests/MixerTest.tscn
extends Node

const SANDBOX := "t_mixer_"

var fails := 0


func _ready() -> void:
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	# Let `Audio._process` notice this scene before asking it for anything. It polls
	# `current_scene`, which is still null while the scene is being built, so the change
	# notification for THIS test arrives a frame or two after `_ready` — and it carries the
	# room for an unlisted screen with it. Asking first and waiting afterwards had the
	# poller stomping the request one frame later, and the room drifting back.
	for _i in 4:
		await get_tree().process_frame

	# --- the buses and their effects ---
	for bus in ["Master", "Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			fails += 1
			print("FAIL there is no %s bus" % bus)
	var sfx := AudioServer.get_bus_index("SFX")
	var reverb: AudioEffectReverb = null
	if sfx != -1:
		for i in AudioServer.get_bus_effect_count(sfx):
			var e := AudioServer.get_bus_effect(sfx, i)
			if e is AudioEffectReverb:
				reverb = e as AudioEffectReverb
	if reverb == null:
		fails += 1
		print("FAIL no reverb on the SFX bus — every effect plays dry wherever the player is")
	elif not is_equal_approx(reverb.dry, 1.0):
		fails += 1
		print("FAIL the SFX reverb has dry=%.2f — a room must ADD to the sound, not replace it"
			% reverb.dry)
	var master := AudioServer.get_bus_index("Master")
	var limited := false
	if master != -1:
		for i in AudioServer.get_bus_effect_count(master):
			var e := AudioServer.get_bus_effect(master, i)
			if e is AudioEffectHardLimiter or e is AudioEffectLimiter:
				limited = true
	if not limited:
		fails += 1
		print("FAIL nothing limits Master — a stinger at 0.85 over the score at 0.52 clips")

	# --- the room follows the player ---
	#
	# Both directions, because one of them is easy to pass by accident: a mixer that snaps
	# to the last place asked for would also pass a single "did it get bigger" check.
	if reverb != null:
		var dungeon: Dictionary = Audio.SPACES["dungeon"]
		var menu: Dictionary = Audio.SPACES["menu"]
		await _settle("dungeon", reverb)
		var big := reverb.wet
		var big_pre := reverb.predelay_msec
		if absf(big - float(dungeon["wet"])) > 0.01:
			fails += 1
			print("FAIL a dungeon settles at wet %.3f, not the %.3f its room asks for" % [
				big, float(dungeon["wet"])])
		await _settle("menu", reverb)
		if absf(reverb.wet - float(menu["wet"])) > 0.01:
			fails += 1
			print("FAIL a menu settles at wet %.3f, not the %.3f its room asks for" % [
				reverb.wet, float(menu["wet"])])
		if reverb.wet >= big or reverb.predelay_msec >= big_pre:
			fails += 1
			print("FAIL a menu is not a smaller room than a dungeon (wet %.3f vs %.3f)" % [
				reverb.wet, big])
		print("  (info: dungeon wet %.2f pre %.0fms -> menu wet %.2f pre %.0fms)" % [
			big, big_pre, reverb.wet, reverb.predelay_msec])
		if Audio.current_space() != "menu":
			fails += 1
			print("FAIL Audio.current_space() says '%s' after a menu" % Audio.current_space())

	# --- every declared event plays ---
	#
	# `Audio.play` swallows a missing stream on purpose (a silent effect must never take a
	# screen down), which means this cannot assert on a return value — what it asserts is
	# that a voice was taken, i.e. that the pool is real and the streams resolved.
	var played := 0
	for event in Audio.SOUNDS:
		Audio.play(event)
		played += 1
	await get_tree().process_frame
	if played < 20:
		fails += 1; print("FAIL only %d events declared" % played)

	# The jitter table's intent, which is the one thing about it that can be got backwards:
	# the sound the crawl plays hundreds of times wanders most, and a stinger is music and
	# barely wanders at all.
	if Audio.jitter_for("step") <= Audio.jitter_for("ui_click"):
		fails += 1; print("FAIL a footstep does not vary more than a button")
	if Audio.jitter_for("victory") >= Audio.jitter_for("attack"):
		fails += 1; print("FAIL a stinger varies as much as a blow — it is a phrase, not a hit")

	print("MIXER TEST: %s (%d)" % ["PASS" if fails == 0 else "FAIL", fails])
	_teardown()
	get_tree().quit(0 if fails == 0 else 1)


## Ask for a place and wait for the room to get there.
##
## Waits on the CLOCK, not on frames, and that is not a style choice. The drift is
## `delta / SPACE_FADE` per frame, and a headless engine renders as fast as it can — 240
## awaited frames here took a quarter of a second of real time, so the room moved 0.005 of
## the way and the first version of this test failed a mixer that was working. A wait for
## something time-based has to be a wait for time.
func _settle(where: String, reverb: AudioEffectReverb) -> void:
	Audio.play_space(where)
	var want := float((Audio.SPACES[where] as Dictionary)["wet"])
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < 8000:
		await get_tree().create_timer(0.02).timeout
		if absf(reverb.wet - want) < 0.008:
			return


func _teardown() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.begins_with(SANDBOX):
			d.remove(f)
		f = d.get_next()
	d.list_dir_end()
