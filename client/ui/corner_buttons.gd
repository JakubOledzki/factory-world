class_name CornerButtons
extends HBoxContainer
## Two small buttons beside the money in the top right corner of every screen: the bell with the
## last messages (NoticeFeed), with how many came since it was opened, and the cog of the settings.

var _count: Label


func _init() -> void:
	add_theme_constant_override("separation", 4)
	var bell := UI.toolbar_button("bell", "Powiadomienia\nOstatnie komunikaty gry", func() -> void: Game.notices.toggle_log())
	_count = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_count.add_theme_font_override("font", UI.bold())
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_constant_override("outline_size", 4)
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.add_theme_color_override("font_color", UI.GOLD)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bell.add_child(_count)
	_count.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 1)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(bell)
	var cog := UI.toolbar_button("settings", "Ustawienia  [F1]\nWielkość interfejsu, efekty, klatki, klawisze", func() -> void: Settings.toggle())
	add_child(cog)
	# As tall as the money panel beside them, so the corner keeps its height.
	for b: Button in [bell, cog]:
		b.custom_minimum_size = Vector2(38, 0) * (UI.TOUCH_SCALE if UI.touch() else 1.0)
	Game.notices.updated.connect(_show_count)
	_show_count()


func _show_count() -> void:
	var unread: int = Game.notices.unread
	_count.text = "" if unread == 0 else ("9+" if unread > 9 else str(unread))


## The buttons and the money panel side by side in the top right corner of `parent`.
static func beside(parent: Control, money_panel: Control) -> HBoxContainer:
	var corner := HBoxContainer.new()
	corner.add_theme_constant_override("separation", 6)
	corner.add_child(CornerButtons.new())
	corner.add_child(money_panel)
	parent.add_child(corner)
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return corner
