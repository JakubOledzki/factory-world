class_name GameWindow
extends PanelContainer
## A small window over the game with a title bar and a close button; drag it by the title.
## Content taller than the screen scrolls.

signal closed

## Every window is in this group, so the touch controls can step out of its way.
const GROUP := "game_windows"

var content := VBoxContainer.new()
## Set before showing: the window covers the screen but this margin, whatever its content,
## and its content fills it (to put its own scrolling lists inside), instead of growing to fit.
var fill_margin := Vector2.ZERO

## Set by a window that shows something kept on the server (ms): while it is open, refresh() is called
## again this often. Its refresh() asks with fetch(), so only one request is on the way at a time.
var poll_every := 0.0:
	set(value):
		poll_every = value
		set_process(visible and value > 0.0)

var _dragging := false
var _poll_at := 0.0
var _poll_busy := false
var _title: Label
var _bar := HBoxContainer.new()
var _scroll := ScrollContainer.new()
## On the title bar of windows of objects that can have a filter (see show_filter_button).
var _filter_button: Button
var _on_filter := Callable()


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
	_title = UI.label(title, UI.GOLD)
	_title.add_theme_font_override("font", UI.bold())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(_title)
	_filter_button = UI.button("Filtr", func() -> void:
		if _on_filter.is_valid():
			_on_filter.call())
	_filter_button.add_theme_constant_override("icon_max_width", 20)
	_filter_button.visible = false
	_bar.add_child(_filter_button)
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
	visibility_changed.connect(func() -> void:
		# A hidden window that only polls has nothing to do each frame.
		if poll_every > 0.0:
			set_process(visible))


func toggle() -> void:
	if visible:
		hide_window()
	else:
		show_window()


func show_window() -> void:
	visible = true
	move_to_front()
	_fit.call_deferred()
	if fill_margin != Vector2.ZERO:
		position = fill_margin


## As tall as the content but no taller than the screen, and inside it: with bigger
## letters on phones a window can grow past the edge.
func _fit() -> void:
	if not is_inside_tree():
		return
	var frame := get_theme_stylebox("panel").get_minimum_size().y
	var screen := get_viewport_rect().size
	if fill_margin != Vector2.ZERO:
		custom_minimum_size.x = screen.x - 2 * fill_margin.x
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.custom_minimum_size.y = 0
		_scroll.custom_minimum_size.y = screen.y - 2 * fill_margin.y - get_combined_minimum_size().y
		reset_size()
		return
	var room := screen.y - 16 - frame - _bar.get_combined_minimum_size().y - 40
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


## Shows the "Filtr" button on the title bar, with the icon of the filtered item when there is one.
func show_filter_button(item: String, on_pressed: Callable) -> void:
	_on_filter = on_pressed
	_filter_button.icon = UI.item_texture(item) if item != "" else null
	_filter_button.tooltip_text = "Filtr: przyjmuje tylko jeden wybrany przedmiot" if item == "" else "Filtr ustawiony: kliknij, aby zmienić"
	_filter_button.visible = true


func has_filter_button() -> bool:
	return _filter_button.visible


func hide_filter_button() -> void:
	_on_filter = Callable()
	_filter_button.visible = false


func set_title(title: String) -> void:
	_title.text = title


## Asks the server for what the window shows, for refresh(): the next ask comes poll_every from now.
func fetch(type: String, payload: Dictionary = {}) -> Dictionary:
	_poll_busy = true
	_poll_at = Time.get_ticks_msec() + poll_every
	var reply: Dictionary = await Net.request(type, payload)
	_poll_busy = false
	return reply


## Asks the server again for what the window shows; windows with poll_every set implement it.
func refresh() -> void:
	pass


## Whether the open window should ask again when it is time, e.g. not for a chest in the garage, which nothing fills.
func _wants_poll() -> bool:
	return true


func _process(_delta: float) -> void:
	if poll_every > 0.0 and visible and not _poll_busy and Time.get_ticks_msec() >= _poll_at and _wants_poll():
		refresh()
