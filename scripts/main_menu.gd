## Title screen. Owns the decision of which save slot is being played, so no other
## screen has to think about slots.
extends Control

## The carved plate the game's name is set into.
##
## `ui/logo.png` is NOT a wordmark. Its brief asked for an ornamental cartouche
## "EMPTY across its whole middle where type will be set later" and forbade
## lettering, because a generator asked for a word paints a misspelling of it and
## the mistake is permanent (D101, D108, D119). So the two halves of a title are
## split by design: the ornament is painted, the wordmark stays TYPE, and this
## screen is where they meet. Swapping the label for the image would ship a title
## screen with no title on it.
const LOGO_ART := "res://assets/art/ui/logo.png"
## Where that middle is, as fractions of the file. Measured off the pixels, not
## eyeballed: the flat panel runs x 0.16–0.85 and y 0.33–0.68 of the 1600x480, and
## the carved scrollwork starts immediately outside it. Type set to the whole plate
## would be cut across the border. Inset a little from the measurement so a
## descender does not touch the moulding.
const LOGO_TEXT := Rect2(0.19, 0.35, 0.62, 0.30)

func _ready() -> void:
	var col := UI.screen(self, "DECKCRAWL", PixelArt.title_art_path())
	# Keep the menu inside the scrim. Buttons centre their text by default, which
	# would drop every label into the middle of the picture where the backdrop is
	# brightest and no longer covered.
	col.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.custom_minimum_size.x = get_viewport_rect().size.x * UI.MENU_WIDTH
	_cut_the_wordmark(col)
	UI.label(col, "A deckbuilding descent.")
	UI.spacer(col)

	var latest := _latest_slot()
	if latest >= 0:
		var s := MetaState.slot_summary(latest)
		var run_note: String = "  · run in progress" if bool(s.get("in_run", false)) else ""
		UI.button(col, "Continue  —  slot %d (%d clears, %d gold)%s" % [
			latest + 1, s.get("clears", 0), s.get("gold", 0), run_note],
			func(): _play(latest))
	else:
		UI.button(col, "Continue  —  no save found")

	UI.button(col, "New Game", func(): UI.goto(self, "res://scenes/SaveSlots.tscn"))
	UI.button(col, "Load Game", func(): UI.goto(self, "res://scenes/SaveSlots.tscn"))
	UI.button(col, "Settings", func(): UI.goto(self, "res://scenes/Settings.tscn"))
	UI.spacer(col)
	UI.button(col, "Quit", func(): get_tree().quit())

	var v := UI.label(col, "Cards %d   Relics %d   Dungeons %d   Zones %d" % [
		MetaState.CATALOG.size(), MetaState.RELIC_CATALOG.size(),
		Balance.DUNGEONS.size(), Balance.ZONES.size()])
	v.modulate = Color(1, 1, 1, 0.6)

## Re-home the title Label onto the painted cartouche, or leave it exactly where
## `UI.screen` put it if the ornament is not installed — the same "use it if it
## exists" rule the backdrops follow, so a missing file degrades to the old screen
## rather than to a hole where the title was.
##
## The Label is MOVED rather than rebuilt on purpose. `UI.screen` decides what a
## title looks like for every screen in the game; building a second one here would
## be a private copy that goes stale the first time that decision changes.
func _cut_the_wordmark(col: VBoxContainer) -> void:
	if not ResourceLoader.exists(LOGO_ART):
		return
	# The title is the first thing `UI.screen` puts in the column, and only when it
	# was given one. Cast rather than assume: if that ever stops being true this
	# screen keeps working instead of crashing on boot.
	var title := col.get_child(0) as Label
	var tex := load(LOGO_ART) as Texture2D
	if title == null or tex == null:
		return

	# The plate is as wide as the menu column and no wider. The column is pinned to
	# UI.MENU_WIDTH so that everything written on this screen stays inside the part
	# of the scrim held at full opacity (UI.SCRIM_HOLD); a banner that broke out of
	# it would be the one piece of the title screen sitting on bare painting.
	var w: float = col.custom_minimum_size.x
	var h: float = w * float(tex.get_height()) / float(tex.get_width())
	var plate := Control.new()
	plate.custom_minimum_size = Vector2(w, h)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var orn := TextureRect.new()
	orn.texture = tex
	orn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# SCALE, not KEEP_ASPECT: the plate above is built at the file's own ratio, so
	# the two agree and there is nothing to letterbox or crop.
	orn.stretch_mode = TextureRect.STRETCH_SCALE
	# LINEAR, for the reason UI.illustration gives: project.godot forces NEAREST on
	# everything for the pixel art, and a painting taken from 1600px to 512 under
	# NEAREST comes out as gravel.
	orn.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	orn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(orn)
	# `set_anchors_and_offsets_preset`, never `set_anchors_preset` — the latter
	# PRESERVES the rect the node already has, which for one added a line ago is
	# 0x0, and the art is then anchored full-rect and held at nothing (D121).
	orn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	col.remove_child(title)
	plate.add_child(title)
	title.anchor_left = LOGO_TEXT.position.x
	title.anchor_top = LOGO_TEXT.position.y
	title.anchor_right = LOGO_TEXT.end.x
	title.anchor_bottom = LOGO_TEXT.end.y
	title.offset_left = 0.0
	title.offset_top = 0.0
	title.offset_right = 0.0
	title.offset_bottom = 0.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Sized to the hole it is set into, not to a number: the plate scales with the
	# column, so a font size chosen once in pixels would overflow the panel on the
	# first screen that is not 1280 wide.
	title.add_theme_font_size_override("font_size",
		int(h * LOGO_TEXT.size.y * 0.74))
	# And inked from the plate rather than fixed white. The carved stone is a LIGHT
	# face: measured off the render, white type on it comes to 3.6:1, under the
	# 4.5:1 every other piece of text on this screen is held to, while the dark ink
	# comes to 5.0:1. `UITheme.ink_for` reads the middle of the texture — which for
	# this file is exactly the empty panel — and returns dark on a light face, so a
	# re-cut that darkens the stone flips the type back to pale with no edit here.
	title.add_theme_color_override("font_color", UITheme.ink_for(tex))
	col.add_child(plate)
	col.move_child(plate, 0)

## Most recently written slot, or -1.
func _latest_slot() -> int:
	var best := -1
	var best_time := -1
	for i in MetaState.SLOT_COUNT:
		var p := MetaState.path_for(i)
		if not FileAccess.file_exists(p):
			continue
		var t := int(FileAccess.get_modified_time(p))
		if t > best_time:
			best_time = t
			best = i
	return best

func _play(s: int) -> void:
	MetaState.slot = s
	if not MetaState.load_game():
		MetaState.new_save()
	GameState.reset_run_progress()
	# resume a dungeon in progress, including a fight mid-turn
	if MetaState.has_saved_run() and GameState.run_from_dict(MetaState.saved_run):
		UI.goto(self, GameState.resume_scene())
		return
	UI.goto(self, "res://scenes/Overworld.tscn")
