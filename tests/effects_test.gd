## Runtime test: the two combat-effect settings actually reach the effects (D130).
##
## This is a SCENE, not a `--script` test, and the reason is the thing it is testing.
## `Fx` reaches SettingsState with `get_node_or_null("/root/SettingsState")`, because
## autoloads are not registered in a headless script run and a compile-time reference
## would make the file unloadable there. In a `--script` run a node added to `root`
## during `_init` is not inside the ACTIVE tree — `is_inside_tree()` is false and an
## absolute node path errors — so every effect bails at its own first guard and the
## setting is never consulted. A test written that way passes for the wrong reason and
## would keep passing with the settings unwired, which is the failure mode this whole
## suite exists to answer for: `show_numbers` shipped dead.
##
## Run: godot --headless res://tests/EffectsTest.tscn
extends Node

const SANDBOX := "t_effects_"

var fails := 0

func _ready() -> void:
	load("res://scripts/settings_state.gd").path_override = "user://" + SANDBOX + "settings.json"
	var layer := Control.new()
	layer.size = Vector2(400, 300)
	add_child(layer)
	# a Control has no usable rect until the frame after it is added, and `Fx._ok`
	# rightly refuses to draw into an empty box
	await get_tree().process_frame

	var box := Rect2(Vector2(10, 10), Vector2(120, 120))
	var ramp: Array = Fx.palette("crypt")
	var settings := get_node_or_null("/root/SettingsState")
	if settings == null:
		_fail("SettingsState is not an autoload, so nothing here can be driven")
		_finish()
		return

	var was_on: bool = settings.effects_enabled
	var was_speed: int = settings.effect_speed

	# --- on: something is drawn ---
	settings.effects_enabled = true
	settings.effect_speed = 100
	for e in _effects(layer, box, ramp):
		_clear(layer)
		e[1].call()
		if layer.get_child_count() == 0:
			_fail("%s drew nothing with effects ON" % e[0])

	# --- off: nothing is, for every one of the six ---
	settings.effects_enabled = false
	for e in _effects(layer, box, ramp):
		_clear(layer)
		e[1].call()
		if layer.get_child_count() != 0:
			_fail("%s spawned %d node(s) with effects OFF" % [e[0], layer.get_child_count()])
	_clear(layer)

	# --- speed scales the authored durations, and never to nothing ---
	#
	# Checked on every constant rather than one, because `_dur` is the single place
	# they are scaled and the point of that is that none can be missed.
	settings.effects_enabled = true
	for pair in [["slash", Fx.T_SLASH], ["impact", Fx.T_IMPACT], ["ward", Fx.T_WARD],
			["cloud", Fx.T_CLOUD], ["heal", Fx.T_HEAL], ["death", Fx.T_DEATH]]:
		var base: float = pair[1]
		settings.effect_speed = settings.EFFECT_SPEED_MAX
		var slow: float = Fx._dur(layer, base)
		settings.effect_speed = settings.EFFECT_SPEED_MIN
		var fast: float = Fx._dur(layer, base)
		settings.effect_speed = 100
		var norm: float = Fx._dur(layer, base)
		if not is_equal_approx(norm, base):
			_fail("%s at 100%% is %.3f, not its authored %.3f" % [pair[0], norm, base])
		if not (fast < base and base < slow):
			_fail("%s does not scale: min=%.3f base=%.3f max=%.3f" % [pair[0], fast, base, slow])
		# the floor is what keeps a "fast" effect from becoming a single-frame flash,
		# which is the thing a motion-sensitive player came here to stop
		if fast < 0.05:
			_fail("%s at the fastest setting is %.3fs — that is a flash" % [pair[0], fast])

	settings.effects_enabled = was_on
	settings.effect_speed = was_speed
	layer.queue_free()
	_finish()

## Name and call for each of the six, bound to one layer and box.
func _effects(layer: Control, box: Rect2, ramp: Array) -> Array:
	return [
		["slash", func(): Fx.slash(layer, box, ramp)],
		["impact", func(): Fx.impact(layer, box, ramp)],
		["block_up", func(): Fx.block_up(layer, box, ramp)],
		["poison_cloud", func(): Fx.poison_cloud(layer, box, ramp)],
		["heal", func(): Fx.heal(layer, box, ramp)],
		["death_dissolve", func(): Fx.death_dissolve(layer, box, ramp)],
	]

## `free`, not `queue_free`: the next effect is spawned on this same frame, and a
## queued node is still a child when it is counted.
func _clear(layer: Control) -> void:
	for c in layer.get_children():
		layer.remove_child(c)
		c.free()

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL " + msg)

func _finish() -> void:
	if fails == 0:
		print("EFFECTS TEST: PASS (both settings reach all six effects)")
	else:
		print("EFFECTS TEST: FAIL (%d)" % fails)
	_cleanup_sandbox()
	get_tree().quit()

func _cleanup_sandbox() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	var doomed: Array[String] = []
	while f != "":
		if f.begins_with(SANDBOX):
			doomed.append(f)
		f = d.get_next()
	d.list_dir_end()
	for x in doomed:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + x))
