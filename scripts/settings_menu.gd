## Settings. Audio rows are deliberately present but inert: the surface exists so
## adding sound later is a wiring job, not a UI job.
extends Control

var back_to := "res://scenes/MainMenu.tscn"

func _ready() -> void:
	if GameState.dungeon_id != "" or GameState.in_run():
		back_to = "res://scenes/PauseMenu.tscn"
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var col := UI.screen(self, "Settings", "", "ledger")

	UI.label(col, "Display")
	# The UI-scale slider used to live here. Removed with the zoom it drove: the
	# engine's canvas_items stretch already resizes the whole interface with the
	# window, so this was a second scale fighting the one that works (D65).
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = SettingsState.fullscreen
	fs.toggled.connect(func(on):
		SettingsState.fullscreen = on
		SettingsState.apply()
		SettingsState.save_settings())
	col.add_child(fs)

	# "and intents" came off the label in D130. The setting had never touched the intent
	# — it had never touched anything — and an intent is what the player reads to decide
	# whether to block, so hiding it would have been a difficulty option wearing a
	# comfort option's clothes. A control now says exactly what it does.
	var nums := CheckBox.new()
	nums.text = "Float damage numbers"
	nums.button_pressed = SettingsState.show_numbers
	nums.toggled.connect(func(on):
		SettingsState.show_numbers = on
		SettingsState.save_settings())
	col.add_child(nums)

	UI.divider(col)
	UI.label(col, "Combat effects")
	# The toggle is the accessibility answer and the slider is a pace preference; see
	# the two of them in settings_state.gd for why one control could not be both.
	var fx_on := CheckBox.new()
	fx_on.text = "Show combat effects"
	fx_on.button_pressed = SettingsState.effects_enabled
	fx_on.toggled.connect(func(on):
		SettingsState.effects_enabled = on
		SettingsState.save_settings()
		_build())   # the speed slider below is meaningless with effects off
	col.add_child(fx_on)

	if SettingsState.effects_enabled:
		UI.slider(col, "Effect speed", SettingsState.effect_speed,
				SettingsState.EFFECT_SPEED_MIN, SettingsState.EFFECT_SPEED_MAX, 25, func(v):
			SettingsState.effect_speed = int(v)
			SettingsState.save_settings())

	UI.divider(col)
	UI.label(col, "Audio")
	UI.slider(col, "Master volume", SettingsState.master_volume, 0, 100, 5, func(v):
		SettingsState.master_volume = int(v)
		Audio.apply_volumes()
		Audio.play("ui_click")   # hear the change you just made
		SettingsState.save_settings())
	# no click on this one: the score is playing, so it IS the feedback
	UI.slider(col, "Music volume", SettingsState.music_volume, 0, 100, 5, func(v):
		SettingsState.music_volume = int(v)
		Audio.apply_volumes()
		SettingsState.save_settings())
	UI.slider(col, "Sound effects", SettingsState.sfx_volume, 0, 100, 5, func(v):
		SettingsState.sfx_volume = int(v)
		Audio.apply_volumes()
		Audio.play("ui_click")   # hear the change you just made
		SettingsState.save_settings())

	UI.spacer(col)
	UI.label(col, "Shortcuts: F11 fullscreen, Esc back")
	UI.exit_button(col, "Back", func(): UI.goto(self, back_to))
