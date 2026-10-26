class_name NoticeFeed
extends CanvasLayer
## Short messages for the player ("Tu nie można tego postawić", "Pożar lasu!"), over every screen.
## They stack one above another instead of replacing each other, and fade after a few seconds;
## the last ones stay in the log under the bell (CornerButtons), where a message about a place
## on a plot takes the player there.

## A message or the log changed: the bell shows how many are unread.
signal updated
## The player clicked a message about a place: { plot: Vector2i, cell: Vector2i }.
signal place_chosen(place: Dictionary)

## Messages on screen at once; the oldest goes first.
const SHOWN := 4
## Seconds a message stays before it fades.
const STAYS := 4.0
const FADES := 0.6
## Messages kept in the log.
const KEPT := 30

## The log, newest last: { text, color, at (unix s), place, count }.
var history: Array[Dictionary] = []
## Messages that came since the log was last opened.
var unread := 0

## A place asked for from another screen: the plot takes it once it has loaded (take_pending).
var _pending := {}
var _root: Control
var _stack := VBoxContainer.new()
var _window: GameWindow
var _list := VBoxContainer.new()
## From the bottom (or, with _top, the top) edge of the screen to the messages.
var _gap := 90.0
var _top := false


func _ready() -> void:
	layer = 40
	_root = Control.new()
	# A layer does not pass the screen's theme on to its controls.
	_root.theme = UI.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_stack.add_theme_constant_override("separation", 2)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stack)
	_place_stack()
	_window = GameWindow.new("Powiadomienia", 420)
	_root.add_child(_window)
	_window.dock_right(12.0, 64.0)
	_list.add_theme_constant_override("separation", 4)
	_window.content.add_child(_list)


## Called by every screen as it opens: its messages show `gap` from the bottom of the screen (above the
## quick bar on a plot), or from the top; what the last screen said goes from the screen, and the log closes.
func dock(gap: float, top := false) -> void:
	_gap = gap
	_top = top
	_place_stack()
	clear_screen()
	_window.hide_window()


## Shows a message and keeps it in the log; `place` ({ plot, cell }) makes it lead there. The same
## message again only counts up, so a repeated refusal doesn't fill the screen. A mere instruction
## ("Kliknij wolne pole…") passes `keep` false: it shows but stays out of the log.
func show_notice(text: String, color := UI.TEXT, place := {}, keep := true) -> void:
	if not keep:
		_show_line({"text": text, "color": color, "place": place, "count": 1})
		return
	var last: Dictionary = history.back() if not history.is_empty() else {}
	if not last.is_empty() and last["text"] == text and Time.get_unix_time_from_system() - float(last["at"]) < 30.0:
		last["count"] = int(last["count"]) + 1
		last["at"] = Time.get_unix_time_from_system()
	else:
		history.append({"text": text, "color": color, "at": Time.get_unix_time_from_system(), "place": place, "count": 1})
		if history.size() > KEPT:
			history.pop_front()
	if _window.visible:
		_render_log()
	else:
		unread += 1
	updated.emit()
	_show_line(history.back())


func _input(event: InputEvent) -> void:
	if _window.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_window.hide_window()
		get_viewport().set_input_as_handled()


## The place on plot `at` the player asked to see from elsewhere, once; empty if none.
func take_pending(at: Vector2i) -> Dictionary:
	if _pending.is_empty() or _pending["plot"] != at:
		return {}
	var place := _pending
	_pending = {}
	return place


func toggle_log() -> void:
	if _window.visible:
		_window.hide_window()
		return
	unread = 0
	updated.emit()
	_render_log()
	_window.show_window()


## Clears the messages on screen, e.g. when the screen changes.
func clear_screen() -> void:
	UI.clear(_stack)


func _place_stack() -> void:
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if _top:
		_stack.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_stack.offset_top = _gap
		_stack.offset_bottom = _gap
		_stack.grow_vertical = Control.GROW_DIRECTION_END
	else:
		_stack.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_stack.offset_top = -_gap
		_stack.offset_bottom = -_gap
		_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_left = -450
	_stack.offset_right = 450


func _show_line(entry: Dictionary) -> void:
	# The same message again: the line on screen stays a while longer and shows how many times.
	for line: Label in _stack.get_children():
		if is_same(line.get_meta("entry"), entry) and not line.is_queued_for_deletion():
			line.text = _text(entry)
			_fade(line)
			return
	var line := UI.label(_text(entry), entry["color"], HORIZONTAL_ALIGNMENT_CENTER, true)
	line.set_meta("entry", entry)
	line.add_theme_font_override("font", UI.bold())
	line.add_theme_constant_override("outline_size", 5)
	line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	line.custom_minimum_size.x = minf(900.0, _root.size.x - 40.0)
	var place: Dictionary = entry["place"]
	if place.is_empty():
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		line.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		line.tooltip_text = "Kliknij, aby tam pójść"
		line.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_go(place)
				line.accept_event())
	_stack.add_child(line)
	if _stack.get_child_count() > SHOWN:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	_fade(line)


## Takes the player to a place: the plot on screen walks there (place_chosen); from another screen
## (or plot) the game goes to that plot first, which then takes the place (take_pending).
func _go(place: Dictionary) -> void:
	_pending = place
	place_chosen.emit(place)
	var scene := get_tree().current_scene
	if not _pending.is_empty() and (scene == null or scene.scene_file_path != Game.PLOT_SCENE or Game.plot != place["plot"]):
		Game.enter_plot(place["plot"])


func _fade(line: Label) -> void:
	if line.has_meta("tween"):
		(line.get_meta("tween") as Tween).kill()
	line.modulate.a = 1.0
	var tween := line.create_tween()
	tween.tween_interval(STAYS)
	tween.tween_property(line, "modulate:a", 0.0, FADES)
	tween.tween_callback(func() -> void:
		if line.get_parent() == _stack:
			_stack.remove_child(line)
		line.queue_free())
	line.set_meta("tween", tween)


func _text(entry: Dictionary) -> String:
	return "%s  ×%d" % [entry["text"], int(entry["count"])] if int(entry["count"]) > 1 else entry["text"]


func _render_log() -> void:
	UI.clear(_list)
	if history.is_empty():
		_list.add_child(UI.label("Nic jeszcze się nie wydarzyło.", UI.MUTED))
	for i in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UI.label(Time.get_time_string_from_unix_time(int(entry["at"]) + _zone()).substr(0, 5), UI.MUTED))
		var text := UI.label(_text(entry), entry["color"], HORIZONTAL_ALIGNMENT_LEFT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var place: Dictionary = entry["place"]
		if not place.is_empty():
			row.add_child(UI.button("Pokaż", func() -> void:
				_window.hide_window()
				_go(place)))
		_list.add_child(row)
	_window._fit.call_deferred()


## Seconds the player's clock is ahead of UTC, so the log shows their time.
func _zone() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

