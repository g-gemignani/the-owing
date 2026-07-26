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
	var col := UI.screen(self, "Settings")

	UI.label(col, "Display")
	UI.slider(col, "UI scale", SettingsState.ui_scale, 0.8, 2.6, 0.1, func(v):
		SettingsState.ui_scale = v
		UITheme.set_scale_silent(v)
		SettingsState.save_settings()
		call_deferred("_build"))
	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = SettingsState.fullscreen
	fs.toggled.connect(func(on):
		SettingsState.fullscreen = on
		SettingsState.apply()
		SettingsState.save_settings())
	col.add_child(fs)

	var nums := CheckBox.new()
	nums.text = "Show damage numbers and intents"
	nums.button_pressed = SettingsState.show_numbers
	nums.toggled.connect(func(on):
		SettingsState.show_numbers = on
		SettingsState.save_settings())
	col.add_child(nums)

	UI.label(col, "")
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
	UI.label(col, "Shortcuts: Ctrl +/- scale, Ctrl+0 reset, F11 fullscreen, Esc back")
	UI.exit_button(col, "Back", func(): UI.goto(self, back_to))
