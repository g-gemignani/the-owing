## The dungeons of one zone. Split out from the overworld so travelling somewhere
## is a real step: you commit to a region, then choose a door inside it.
extends Control

var list: VBoxContainer

func _ready() -> void:
	var z := Balance.zone(GameState.current_zone) if GameState.current_zone != "" else null
	if z == null:
		call_deferred("_back")
		return
	var col := UI.screen(self, z.name)
	UI.label(col, z.description)
	UI.label(col, "Gold %d    Relics %d    Cleared %d/%d" % [
		MetaState.gold, MetaState.relics.size(),
		MetaState.clear_count(), Balance.DUNGEONS.size()])
	list = UI.scroll(col)
	UI.button(col, "Back to the world", func(): _back())
	_fill(z)

func _fill(z: ZoneData) -> void:
	for did in z.dungeons:
		var d := Balance.dungeon(did)
		if d == null:
			continue
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", UITheme.sep(4))
		list.add_child(box)

		var unlocked: bool = MetaState.dungeon_unlocked(d)
		var tag := "  [cleared]" if MetaState.has_cleared(d.id) else ""
		if not unlocked:
			tag = "  [locked — clear %d dungeons]" % Balance.effective_gate(d.id)
		UI.button(box, "%s   difficulty %d   %s%s" % [
			d.name, d.difficulty, _kind(d.traversal), tag],
			(func(): _enter(d.id)) if unlocked else Callable(), 40.0)
		UI.label(box, "    %s" % d.description)
		var only := _exclusives(d)
		if only != "":
			UI.label(box, "    Found only here: %s" % only)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UITheme.px(10))
		box.add_child(gap)

func _kind(k: int) -> String:
	match k:
		Traversal.Kind.DECK: return "encounter deck"
		Traversal.Kind.DICE: return "dice board"
		_: return "branching map"

func _exclusives(d: DungeonData) -> String:
	var names: Array[String] = []
	for cid in d.exclusive_cards:
		if MetaState.CATALOG.has(cid):
			var c := load(MetaState.CATALOG[cid]) as CardData
			if c != null:
				names.append(c.name)
	return ", ".join(names)

func _enter(id: String) -> void:
	GameState.select_dungeon(id)
	GameState.manage_only = false
	UI.goto(self, "res://scenes/DeckBuilder.tscn")

func _back() -> void:
	UI.goto(self, "res://scenes/Overworld.tscn")
