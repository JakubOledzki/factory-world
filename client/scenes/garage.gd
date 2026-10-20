extends Control
## The player's garage. For now it shows the character; machines arrive in stage 2.


func _ready() -> void:
	var c := Game.character
	var box := UI.centered_panel(self, 360)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	box.add_child(header)

	var preview := CharacterPreview.new()
	preview.pixel = 4
	preview.options = Game.appearance_options
	preview.appearance = c.get("appearance", {})
	header.add_child(preview)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(info)
	info.add_child(UI.label(c.get("name", "")))
	info.add_child(UI.label("Poziom %d" % c.get("level", 1), UI.MUTED))

	var xp := ProgressBar.new()
	var level_xp: float = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	xp.show_percentage = false
	xp.custom_minimum_size.y = 8
	xp.max_value = (next_xp - level_xp) if next_xp != null else 1.0
	xp.value = c.get("xp", 0) - level_xp
	info.add_child(xp)
	var xp_text := "%d / %d XP" % [c.get("xp", 0), next_xp] if next_xp != null else "%d XP" % c.get("xp", 0)
	info.add_child(UI.label(xp_text, UI.MUTED))

	box.add_child(HSeparator.new())
	box.add_child(UI.label("Twój garaż. Kosz na śmieci i segregacja pojawią się w etapie 2.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(UI.button("Wyloguj", Game.logout))
