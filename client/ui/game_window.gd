class_name GameWindow
extends PanelContainer
## A small window over the game with a title bar and a close button; drag it by the title.
## Content taller than the screen scrolls.

signal closed

## Every window is in this group, so the touch controls can step out of its way.
const GROUP := "game_windows"

var content := VBoxContainer.new()

var _dragging := false
var _bar := HBoxContainer.new()
var _scroll := ScrollContainer.new()


func _init(title: String, width: int) -> void:
	custom_minimum_size.x = width
	visible = false
	add_to_group(GROUP)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_bar.gui_input.connect(_on_bar_input)
	var label := UI.label(title, UI.GOLD)
	label.add_theme_font_override("font", UI.bold())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(label)
	var close := UI.button("×", hide_window)
	close.tooltip_text = "Zamknij (Esc)"
	_bar.add_child(close)
	box.add_child(_bar)
	box.add_child(HSeparator.new())

	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.minimum_size_changed.connect(_fit)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(content)
	box.add_child(_scroll)


func toggle() -> void:
	if visible:
		hide_window()
	else:
		show_window()


func show_window() -> void:
	visible = true
	move_to_front()
	_fit.call_deferred()


## As tall as the content but no taller than the screen, and inside it: with bigger
## letters on phones a window can grow past the edge.
func _fit() -> void:
	if not is_inside_tree():
		return
	var frame := get_theme_stylebox("panel").get_minimum_size().y
	var room := get_viewport_rect().size.y - 16 - frame - _bar.get_combined_minimum_size().y - 40
	_scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, room)
	reset_size()
	position = position.clamp(Vector2.ZERO, (get_viewport_rect().size - size).max(Vector2.ZERO))


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
