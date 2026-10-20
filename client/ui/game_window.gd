class_name GameWindow
extends PanelContainer
## A small window over the game with a title bar and a close button; drag it by the title.

signal closed

var content := VBoxContainer.new()

var _dragging := false


func _init(title: String, width: int) -> void:
	custom_minimum_size.x = width
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	bar.gui_input.connect(_on_bar_input)
	var label := UI.label(title, UI.GOLD)
	label.add_theme_font_override("font", UI.bold())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(label)
	var close := UI.button("×", hide_window)
	close.tooltip_text = "Zamknij (Esc)"
	bar.add_child(close)
	box.add_child(bar)
	box.add_child(HSeparator.new())

	content.add_theme_constant_override("separation", 6)
	box.add_child(content)


func toggle() -> void:
	if visible:
		hide_window()
	else:
		show_window()


func show_window() -> void:
	visible = true
	move_to_front()


func hide_window() -> void:
	if visible:
		visible = false
		closed.emit()


func _on_bar_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			move_to_front()
	elif event is InputEventMouseMotion and _dragging:
		var area := get_viewport_rect().size
		position = (position + event.relative).clamp(Vector2.ZERO, area - size)
