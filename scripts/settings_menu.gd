## Settings. Audio rows are deliberately present but inert: the surface exists so
## adding sound later is a wiring job, not a UI job.
extends Control

var back_to := "res://scenes/MainMenu.tscn"

## Where Back goes, decided once and held for the life of the screen.
##
## `UI.gear()` put a settings door in the top-right corner of every screen (D133), so
## "back" stopped being derivable from run state: the same live run can be paused, or
## browsing Relics, or standing on the world map, and all three now open this screen.
## The corner records where it was pressed and this consumes that record — see
## `UI.settings_return()` for why consuming rather than reading is what keeps the two
## routes from answering for each other.
##
## The old derivation stays underneath it, unchanged, and is not dead code: the three
## text buttons that still open Settings record nothing, and neither would anything
## else that navigates here directly. An absent record is the normal case, not an
## error case.
##
## Read in `_ready` and not in `_build`, because `_build` runs again whenever a toggle
## changes the shape of the screen, and re-reading a consumed record there would send
## Back to the title the moment the player switched combat effects off.
func _ready() -> void:
	var opener := UI.settings_return()
	if opener != "":
		back_to = opener
	elif GameState.dungeon_id != "" or GameState.in_run():
		back_to = "res://scenes/PauseMenu.tscn"
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	# Scrolls, because it does not fit and never really did (D182). Measured at the
	# project's own 1280x720: the column asks for 972px of a 720px window, so the bottom
	# 252px — the build stamp, and Back — was drawn past the edge of the screen with no
	# way to reach it. It grows further whenever a control explains itself: switching
	# effects on adds a slider, opening a save adds four lines of difficulty blurb.
	var col := UI.screen(self, "Settings", "", "ledger", false, "", true)

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

	# "and intents" came off the label in D133. The setting had never touched the intent
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
	_build_difficulty(col)

	UI.divider(col)
	UI.label(col, "Controls")
	# Three states, not a checkbox: see `SettingsState.Pad`. The current reading of
	# Automatic is spelled out beside it, because "Automatic" alone leaves the player
	# guessing which way it went on their own machine.
	var pad_row := UI.row(col, 10)
	var pad_lbl := Label.new()
	pad_lbl.text = "Dungeon movement pad"
	pad_lbl.custom_minimum_size.x = UITheme.px(300)
	pad_row.add_child(pad_lbl)
	var pad := OptionButton.new()
	for i in SettingsState.PAD_NAMES.size():
		pad.add_item(String(SettingsState.PAD_NAMES[i]), i)
	pad.select(SettingsState.pad_mode)
	pad.item_selected.connect(func(i: int):
		SettingsState.pad_mode = i
		Audio.play("ui_select")
		SettingsState.save_settings()
		_build())
	pad_row.add_child(pad)
	var pad_now := Label.new()
	pad_now.text = "   shown" if UI.pad_visible() else "   hidden — W A S D, or click a tile"
	pad_now.add_theme_color_override("font_color", Color(0.70, 0.72, 0.82))
	pad_row.add_child(pad_now)

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

	UI.divider(col)
	UI.label(col, "Build")
	# The same string as the title screen's corner, from the same place, because a build
	# stamp that two screens can disagree about is worse than no stamp (D156). This is the
	# deliberate place to look for it: the corner of the menu is for noticing, a Settings
	# row is for reading out to somebody.
	var stamp := UI.label(col, BuildInfo.label(), false)
	if BuildInfo.is_dev():
		UI.label(col, "Made by hand from a checkout, not by CI, so there is no commit in it.")
	else:
		UI.label(col, "Commit %s. Quote this in a bug report — every published build has the same filename." % BuildInfo.commit())
	stamp.add_theme_font_size_override("font_size", UITheme.title_font())

	UI.spacer(col)
	UI.label(col, "Shortcuts: F11 fullscreen, Esc back")
	UI.exit_button(col, "Back", func(): UI.goto(self, back_to))

## The difficulty rung (D175). The one row on this screen that is NOT a machine
## setting: it is stored per save, beside `ascension`, for the reasons written on
## `MetaState.difficulty`. It is drawn here anyway because this is where a player
## looks for it, and a setting hidden from the settings screen to satisfy a storage
## rule would be the rule serving itself.
##
## Three states, because two of them are honest refusals rather than a greyed control
## with no explanation:
##   * no save open  — there is nothing to write to; say so and say where to go
##   * a run under way — a rung the player could change mid-boss is not a difficulty,
##     it is a retry button, so it is fixed from the moment they go down
##   * otherwise      — live, and applied to `Balance` the moment it changes
func _build_difficulty(col: VBoxContainer) -> void:
	UI.label(col, "Difficulty")
	var in_run: bool = GameState.in_run()
	# `MetaState.slot` is only meaningful once the title screen has picked one; before
	# that the autoload is holding defaults for nobody.
	var have_save := MetaState.loaded

	var row := UI.row(col, 10)
	var lbl := Label.new()
	lbl.text = "Dungeon difficulty"
	lbl.custom_minimum_size.x = UITheme.px(300)
	row.add_child(lbl)

	var opt := OptionButton.new()
	for i in Balance.DIFFICULTIES.size():
		opt.add_item(Balance.difficulty_name(i), i)
	opt.select(clampi(MetaState.difficulty, 0, Balance.DIFFICULTIES.size() - 1))
	opt.disabled = in_run or not have_save
	opt.item_selected.connect(func(i: int):
		MetaState.difficulty = i
		Balance.difficulty = i        # static, so the change is live without a reload
		Audio.play("ui_select")
		MetaState.save_game()
		_build())                     # the blurb below names the rung, so redraw it
	row.add_child(opt)

	if not have_save:
		UI.label(col, "Difficulty belongs to a save, not to this machine — open or start one first.")
		return
	if in_run:
		UI.label(col, "Fixed until this run ends. What a dungeon costs is decided when you go down, not while you are standing in it.")

	# What the rung does, in the player's vocabulary. A label that only says "Hard"
	# asks them to find out by dying; "scaling ratio x2.80" answers a question nobody
	# asked, in a word from the source tree. Say what it costs and where it lands.
	var row_data := Balance.difficulty_row(MetaState.difficulty)
	UI.label(col, String(row_data["blurb"]))
	if MetaState.difficulty == Balance.DIFFICULTY_LEGACY:
		UI.label(col, "Enemies answer the deck you bring, up to what the dungeon's own depth allows.")
	else:
		# The shape is the point and it is not obvious: a stronger deck is answered
		# harder, so the opening floors barely move and a built deck feels all of it.
		UI.label(col, "Enemies answer the deck you bring far more sharply. A starting deck notices little; a built one is met with everything the dungeon's depth allows.")
	UI.label(col, "Rewards are unchanged at every setting — a harder run pays exactly the same, so this is a preference and never a grind.")
	if MetaState.ascension > 0:
		UI.label(col, "Ascension %d is on top of this." % MetaState.ascension)
