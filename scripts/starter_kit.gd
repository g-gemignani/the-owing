## Starting kit choice. Shown once, when a new game begins.
##
## Its real job is to make the first decision the same decision the game is about:
## which archetype are you heading toward. It also hands over 12 cards instead of
## the bare legal minimum, so the deck builder has something to choose between and
## fusion is available on run 1.
extends Control

var slot := 0

func _ready() -> void:
	slot = GameState.pending_new_slot
	var col := UI.screen(self, "Choose a Beginning")
	UI.label(col, "Twelve cards. Each set leans a different way — you are not locked in, but you are pointed somewhere.")
	var list := UI.scroll(col)

	for kid in MetaState.STARTER_KITS:
		var kit: Dictionary = MetaState.STARTER_KITS[kid]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.sep(4))
		list.add_child(box)

		var b := Button.new()
		UITheme.style_button(b)
		b.text = "%s — %s" % [kit["name"], kit["hint"]]
		b.custom_minimum_size = Vector2(0, UITheme.button_height(44))
		b.pressed.connect(_pick.bind(kid))
		box.add_child(b)

		# spell the contents out: the choice is meaningless if it is opaque
		var parts: Array[String] = []
		for cid in kit["cards"]:
			var c := load(MetaState.CATALOG[cid]) as CardData
			parts.append("%dx %s" % [int(kit["cards"][cid]), c.name if c != null else cid])
		UI.label(box, "    %s" % ", ".join(parts))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(8))
		box.add_child(gap)

	UI.exit_button(col, "Back", func(): UI.goto(self, "res://scenes/SaveSlots.tscn"))

func _pick(kid: String) -> void:
	MetaState.slot = slot
	MetaState.new_save(kid)
	GameState.reset_run_progress()
	UI.goto(self, "res://scenes/Overworld.tscn")
