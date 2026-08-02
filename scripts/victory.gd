## Shown when the final dungeon falls. The world had no ending before this.
extends Control

func _ready() -> void:
	var col := UI.screen(self, "The Maw Is Quiet", "", "victory", true)
	UI.label(col, "You cleared every door anyone had mapped, and then the one nobody had.")
	UI.label(col, "")

	var builds_done := 0
	for b in Balance.all_builds():
		var have := 0
		for c in b.cards:
			if MetaState.collection.has(c):
				have += 1
		if have == b.cards.size():
			builds_done += 1
	UI.label(col, "Dungeons cleared: %d / %d" % [MetaState.clear_count(), Balance.DUNGEONS.size()])
	UI.label(col, "Builds completed: %d / %d" % [builds_done, Balance.BUILDS.size()])
	UI.label(col, "Relics found: %d / %d" % [MetaState.relics.size(), MetaState.RELIC_CATALOG.size()])
	UI.label(col, "Card types owned: %d / %d" % [MetaState.collection.size(), MetaState.CATALOG.size()])
	UI.label(col, "Ascension: %d" % MetaState.ascension)
	UI.spacer(col)

	# Ascension keeps the collection and relics but re-locks the world, so the
	# hundred cards have somewhere to go after the last door.
	#
	# The offer sits in its own scrim, and it is the width of the buttons it belongs
	# to. It used to run the full 1280 straight across the lit doorway — the brightest
	# thing in `bg_victory.png` and the reason the painting is any good — where the
	# worst backdrop pixel under the sentence measured 0.222 luma, 3.86:1 against
	# white. That is under the 4.5:1 the same suite holds every button frame to, and
	# it lands in the middle of the sentence, which is the half a reader cannot skip.
	#
	# Three fixes were on the table and this is two of them at once, because neither
	# alone is safe. A NARROWER MEASURE alone would be a bet on where the light
	# happens to fall, and `bg_victory.png` is being re-painted; a SCRIM alone would
	# still stretch a 1244px plate across the doorway to carry one sentence. Dimming
	# the painting was refused outright. A 480-wide plate ends before the doorway
	# begins, guarantees its own contrast whatever is repainted behind it, and makes
	# the sentence read as the caption to the two buttons under it rather than as a
	# banner across the room.
	var bay := PanelContainer.new()
	bay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bay.custom_minimum_size.x = UITheme.px(UI.BUTTON_WIDTH)
	bay.add_theme_stylebox_override("panel", _offer_scrim())
	col.add_child(bay)
	UI.label(bay, "Descend again? Ascension %d makes every enemy stronger and the loot richer. You keep your collection, relics and ropes; the dungeons re-lock." % (MetaState.ascension + 1))
	UI.button(col, "Begin Ascension %d" % (MetaState.ascension + 1), func(): _ascend())
	UI.exit_button(col, "Stay here", func(): UI.goto(self, "res://scenes/Overworld.tscn"))

## The plate behind the ascension offer. Local to this screen because only this
## screen puts prose below the fold on a painting — everything else down there is a
## button carrying its own opaque frame, which is the reason `SCENE_FOOT_ALPHA`
## exists and the reason it was tuned for one line rather than for a block.
##
## Both numbers are borrowed rather than chosen, and both are READ rather than
## restated: the colour is the clear colour `UITheme` sets — what the game shows
## where there is no art at all — and `UI.SCRIM_ALPHA` is the opacity the title
## screen already measured for "enough to read white text over a painting". On the
## capture, the worst pixel of the plate is 0.130 luma — 5.8:1, up from 3.86:1, and
## clear of the 4.5:1 floor. Worth recording that the plate is doing real work rather
## than duplicating the narrower measure: immediately outside its right edge the wall
## reads 0.285, which is 3.1:1, so a 480-wide line with no scrim behind it would
## still have been under the floor for its whole length.
func _offer_scrim() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bg := RenderingServer.get_default_clear_color()
	bg.a = UI.SCRIM_ALPHA
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.content_margin_left = UITheme.px(12)
	sb.content_margin_right = UITheme.px(12)
	sb.content_margin_top = UITheme.px(8)
	sb.content_margin_bottom = UITheme.px(8)
	return sb

func _ascend() -> void:
	MetaState.ascension += 1
	Balance.ascension = MetaState.ascension
	MetaState.cleared_dungeons = []
	GameState.reset_run_progress()
	GameState.clear_run()
	MetaState.save_game()
	UI.goto(self, "res://scenes/Overworld.tscn")
