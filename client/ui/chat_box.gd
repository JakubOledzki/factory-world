class_name ChatBox
extends PanelContainer
## The chat in the corner of the plot: the last few lines fade away by themselves; [Enter] (or the chat button) opens
## the history and a line to write in, to everybody or to the players on this plot. Quick phrases and pointing at a
## place on the plot are one click away. It asks the server for news every few seconds, only for what it has not seen.

signal failed(reply: Dictionary)
## A new message: the plot shows it over the head of who said it, and a ping as a mark on the ground.
signal heard(message: Dictionary)
## The player wants to point at a place: the next click on the plot sends the ping.
signal ping_requested

const POLL := 2000.0
## How long a line stays in the corner while the chat is closed (s).
const FADE_AFTER := 12.0
const SHOWN_CLOSED := 5
const KEPT := 60
const PHRASES := ["Cześć!", "Dzięki!", "Super fabryka!", "Pomóc?", "Chodź tutaj!"]
const WORLD_COLOR := Color("#9cc4dc")
const PLOT_COLOR := Color("#8fd65a")

## The plot the player is on; its chat comes with everybody's.
var plot := Vector2i(-1, -1)
var is_open := false

var _last := -1
var _next_poll := 0.0
var _polling := false
## [{ message, at (ticks ms) }], oldest first.
var _lines: Array[Dictionary] = []
var _channel := "plot"
var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _open_part := VBoxContainer.new()
var _line: LineEdit
var _channel_buttons := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = 340 * (UI.TOUCH_SCALE if UI.touch() else 1.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 1)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)
	box.add_child(_scroll)

	_open_part.visible = false
	_open_part.add_theme_constant_override("separation", 4)
	var channels := HBoxContainer.new()
	channels.add_theme_constant_override("separation", 4)
	for channel: String in ["plot", "world"]:
		var b := UI.button("Działka" if channel == "plot" else "Świat", _set_channel.bind(channel))
		b.toggle_mode = true
		b.tooltip_text = "Piszesz do graczy na tej działce" if channel == "plot" else "Piszesz do wszystkich w grze"
		_channel_buttons[channel] = b
		channels.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channels.add_child(spacer)
	var ping := UI.button("Wskaż miejsce", func() -> void: ping_requested.emit())
	ping.tooltip_text = "Kliknij potem pole działki: inni zobaczą tam znacznik (albo kliknij pole środkowym przyciskiem myszy)"
	channels.add_child(ping)
	_open_part.add_child(channels)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_line = UI.line_edit("Napisz wiadomość i naciśnij Enter")
	_line.max_length = 200
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.text_submitted.connect(_on_submitted)
	row.add_child(_line)
	row.add_child(UI.button("Wyślij", func() -> void: _on_submitted(_line.text), true))
	_open_part.add_child(row)
	var phrases := HFlowContainer.new()
	phrases.add_theme_constant_override("h_separation", 4)
	phrases.add_theme_constant_override("v_separation", 4)
	for phrase: String in PHRASES:
		phrases.add_child(UI.button(phrase, _send.bind(phrase)))
	_open_part.add_child(phrases)
	box.add_child(_open_part)
	_mark_channel()
	_set_frame(false)


func _ready() -> void:
	set_process(true)


## Opens the history and the line to write in, with the cursor in it.
func open() -> void:
	is_open = true
	_open_part.visible = true
	_set_frame(true)
	_render()
	_line.grab_focus()


func close() -> void:
	is_open = false
	_open_part.visible = false
	_line.release_focus()
	_set_frame(false)
	_render()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Sends a ping: a mark on a tile of the plot for everybody there.
func ping(cell: Vector2i) -> void:
	var reply := await Net.request("chat.send", {"channel": "plot", "x": plot.x, "y": plot.y, "text": "Patrz tutaj!", "pingX": cell.x, "pingY": cell.y})
	if reply["type"] != "chat.sent":
		failed.emit(reply)
		return
	_next_poll = 0.0


func _process(_delta: float) -> void:
	if not _polling and Time.get_ticks_msec() >= _next_poll and plot.x >= 0:
		_poll()
	# Lines fade out of the corner while the chat is closed.
	if not is_open:
		var now := Time.get_ticks_msec()
		for row: Control in _list.get_children():
			var at: float = row.get_meta("at", now)
			var left := FADE_AFTER - (now - at) / 1000.0
			row.modulate.a = clampf(left, 0.0, 1.0)


func _poll() -> void:
	_polling = true
	_next_poll = Time.get_ticks_msec() + POLL
	var reply := await Net.request("chat.get", {"after": maxi(_last, 0), "x": plot.x, "y": plot.y})
	if reply["type"] == "error":
		# No longer allowed on the plot (made private): everybody's chat still comes.
		reply = await Net.request("chat.get", {"after": maxi(_last, 0)})
	_polling = false
	if reply["type"] != "chat":
		return
	var first := _last < 0
	_last = int(reply["payload"]["last"])
	var messages: Array = reply["payload"]["messages"]
	if messages.is_empty():
		return
	for m: Dictionary in messages:
		# What was said before the player came is history, not news: no bubbles nor pings for it.
		_lines.append({"message": m, "at": 0.0 if first else float(Time.get_ticks_msec())})
		if not first:
			heard.emit(m)
	while _lines.size() > KEPT:
		_lines.pop_front()
	_render()


func _render() -> void:
	UI.clear(_list)
	var shown: Array = _lines if is_open else _lines.slice(maxi(0, _lines.size() - SHOWN_CLOSED))
	for line: Dictionary in shown:
		var m: Dictionary = line["message"]
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.scroll_active = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_constant_override("outline_size", 4)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		var color := WORLD_COLOR if m["channel"] == "world" else PLOT_COLOR
		var text := str(m["text"])
		if m.get("ping") != null:
			text = "wskazuje miejsce na działce"
		label.text = "[color=#%s]%s[/color] [b]%s:[/b] %s" % [color.to_html(false), "[Świat]" if m["channel"] == "world" else "[Działka]",
			_escape(str(m["name"])), _escape(text)]
		label.set_meta("at", line["at"])
		_list.add_child(label)
	_scroll.custom_minimum_size.y = 220.0 if is_open else 0.0
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if is_open else ScrollContainer.SCROLL_MODE_DISABLED
	if is_open:
		await get_tree().process_frame
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


## Square brackets in a name or message are shown as they are, not read as formatting.
func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


func _on_submitted(text: String) -> void:
	if text.strip_edges() == "":
		close()
		return
	_send(text)
	_line.clear()


func _send(text: String) -> void:
	var payload := {"channel": _channel, "text": text}
	if _channel == "plot":
		payload["x"] = plot.x
		payload["y"] = plot.y
	var reply := await Net.request("chat.send", payload)
	if reply["type"] != "chat.sent":
		failed.emit(reply)
		return
	_next_poll = 0.0


func _set_channel(channel: String) -> void:
	_channel = channel
	_mark_channel()
	_line.grab_focus()


func _mark_channel() -> void:
	for channel: String in _channel_buttons:
		(_channel_buttons[channel] as Button).button_pressed = channel == _channel


## A dark panel behind the open chat; closed, the lines float over the game with only their outline.
func _set_frame(on: bool) -> void:
	if on:
		remove_theme_stylebox_override("panel")
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		mouse_filter = Control.MOUSE_FILTER_IGNORE
