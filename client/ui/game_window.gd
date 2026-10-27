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

## What the window takes in from the inventory, by item: { room, put: Callable(quantity) }. A window that
## loads items fills it while it draws its rows (offer), and a Shift-click, a drag or a tap on an
## inventory tile puts the item in through it (InventoryGrid).
var intake := {}

## Counts how often windows were opened, so the one opened last is found (receiver).
static var _opened := 0

## Set by dock_right(): until the player drags it, the window opens this far from the right edge of
## the screen, however wide the screen is (-1: wherever its position puts it).
var _right_gap := -1.0
var _dragging := false
var _poll_at := 0.0
var _poll_busy := false
var _title: Label
var _bar := HBoxContainer.new()
var _scroll := ScrollContainer.new()
## Under the content: buttons the screen adds for the object the window shows (set_tools).
var _tools := HBoxContainer.new()
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
	_tools.add_theme_constant_override("separation", 4)
	_tools.visible = false
	box.add_child(_tools)
	visibility_changed.connect(func() -> void:
		# A hidden window that only polls has nothing to do each frame.
		if poll_every > 0.0:
			set_process(visible))


func toggle() -> void:
	if visible:
		hide_window()
	else:
		show_window()


## Opens the window at the right edge of the screen, `gap` from it and `top` from the top, until the
## player drags it somewhere else.
func dock_right(gap := 12.0, top := 64.0) -> void:
	_right_gap = gap
	position.y = top
	if is_inside_tree():
		_dock()


func show_window() -> void:
	visible = true
	_opened += 1
	set_meta("opened", _opened)
	move_to_front()
	_dock()
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
	var room := screen.y - 16 - frame - _bar.get_combined_minimum_size().y - 40 \
		- (_tools.get_combined_minimum_size().y + 6 if _tools.visible else 0.0)
	_scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, room)
	reset_size()
	_dock()
	position = position.clamp(Vector2.ZERO, (get_viewport_rect().size - size).max(Vector2.ZERO))


func _dock() -> void:
	if _right_gap >= 0.0 and fill_margin == Vector2.ZERO and is_inside_tree():
		position.x = get_viewport_rect().size.x - size.x - _right_gap


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
		_right_gap = -1.0
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


## Says the window takes `item` in, at most `room` pieces, through `put` (called with the quantity).
func offer(item: String, room: int, put: Callable) -> void:
	if not intake.has(item) and room > 0:
		intake[item] = {"room": room, "put": put}


## The open window last opened that takes `item` in, or null; with `at` (global, in pixels) the one under it.
static func receiver(tree: SceneTree, item: String, at := Vector2.INF) -> GameWindow:
	var best: GameWindow = null
	for window: GameWindow in tree.get_nodes_in_group(GROUP):
		if not window.is_visible_in_tree() or not window.intake.has(item):
			continue
		if at != Vector2.INF and not window.get_global_rect().has_point(at):
			continue
		if best == null or int(window.get_meta("opened", 0)) > int(best.get_meta("opened", 0)):
			best = window
	return best


## Buttons under the content for the object shown, e.g. "Kopiuj ustawienia"; none takes them away.
func set_tools(buttons: Array[Button]) -> void:
	UI.clear(_tools)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tools.add_child(b)
	_tools.visible = not buttons.is_empty()
	_fit.call_deferred()


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
