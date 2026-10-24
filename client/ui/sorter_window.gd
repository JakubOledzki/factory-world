class_name SorterWindow
extends GameWindow
## The automatic sorting machine: trash loaded into it waits in its queue and is sorted bag after
## bag, while the player is away too. What it sorts stays in the machine until taken out; a full
## machine stops until some is taken out.

## After every answer from the server, with the machine as it is now.
signal updated(sorter: Dictionary)
## Items went from the inventory into the machine or back: [{id, name, quantity}] taken out, XP.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)

const TRASH := "trash"

var sorter := ""

var _state := {}
var _trash := 0
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _queue_text: Label
var _status: Label
var _sort_bar: ProgressBar
var _load_buttons: Array[Button] = []
var _take_trash: Button
var _stored_text: Label
var _stored := VBoxContainer.new()
var _take_all: Button
var _help: Label


func _init() -> void:
	super("Automatyczna sortownia", 360)
	content.add_child(_heading("Kolejka do segregacji"))
	var queue := HBoxContainer.new()
	queue.add_theme_constant_override("separation", 8)
	queue.add_child(UI.item_icon(TRASH, 32))
	_queue_text = UI.label("")
	_queue_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue.add_child(_queue_text)
	_take_trash = UI.button("Wyjmij", _take.bind(TRASH))
	_take_trash.tooltip_text = "Zabierz z powrotem śmieci, które jeszcze czekają"
	queue.add_child(_take_trash)
	content.add_child(queue)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for amount: int in [1, 10, 0]:
		var b := UI.button("Włóż wszystko" if amount == 0 else "Włóż %d" % amount, _load_trash.bind(amount), amount == 0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
		_load_buttons.append(b)
	content.add_child(buttons)
	_status = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	_sort_bar = ProgressBar.new()
	_sort_bar.show_percentage = false
	_sort_bar.custom_minimum_size.y = 10
	content.add_child(_sort_bar)
	content.add_child(HSeparator.new())
	var stored_head := HBoxContainer.new()
	var title := _heading("Posegregowane")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stored_head.add_child(title)
	_stored_text = UI.label("", UI.MUTED)
	stored_head.add_child(_stored_text)
	content.add_child(stored_head)
	_stored.add_theme_constant_override("separation", 4)
	content.add_child(_stored)
	_take_all = UI.button("Wyjmij wszystko", _take.bind(""), true)
	content.add_child(_take_all)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)


func open_at(id: String) -> void:
	if id != sorter:
		_state = {}
	sorter = id
	show_window()
	refresh()


## The trash the player has, from the inventory.
func set_items(items: Array) -> void:
	_trash = 0
	for stack: Dictionary in items:
		if stack["id"] == TRASH:
			_trash = int(stack["quantity"])
	if visible:
		_render()


func refresh() -> void:
	if sorter == "":
		return
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("sorter.get", {"sorter": sorter})
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "sorter":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	updated.emit(_state)
	_render()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _room() -> int:
	return int(_state["maxQueue"]) - int(_state["queued"])


func _render() -> void:
	if _state.is_empty():
		return
	var queued := int(_state["queued"])
	_queue_text.text = "Śmieci: %d / %d  (masz %d)" % [queued, int(_state["maxQueue"]), _trash]
	_take_trash.disabled = queued < 1
	for i in _load_buttons.size():
		var amount: int = [1, 10, 0][i]
		var count := mini(_trash, _room()) if amount == 0 else amount
		_load_buttons[i].disabled = count < 1 or count > _trash or count > _room()

	for child in _stored.get_children():
		child.free()
	var stored: Array = _state.get("stored", [])
	_stored_text.text = "%d / %d" % [int(_state["storedCount"]), int(_state["maxStored"])]
	for stack: Dictionary in stored:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(stack["id"], 26))
		var label := UI.label("%s  ×%d" % [stack["name"], int(stack["quantity"])])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(UI.button("Wyjmij", _take.bind(stack["id"])))
		_stored.add_child(row)
	if stored.is_empty():
		_stored.add_child(UI.label("pusto", UI.MUTED))
	_take_all.disabled = stored.is_empty()

	var chances: Array[String] = []
	for drop: Dictionary in _state.get("drops", []):
		chances.append("%s %d%%" % [drop["name"].to_lower(), int(drop["percent"])])
	_help.text = ("Sortownia segreguje sama, także gdy cię nie ma: worek w %d s, 5 XP za każdy wyjęty przedmiot. Mieści %d worków w kolejce i %d posegregowanych przedmiotów; gdy jest pełna, staje, dopóki czegoś nie wyjmiesz.\nZ worka: %s."
		% [int(_state["sortSeconds"]), int(_state["maxQueue"]), int(_state["maxStored"]), ", ".join(chances)])
	_update_status()
	_fit.call_deferred()


func _update_status() -> void:
	var started: Variant = _state.get("startedAt")
	_sort_bar.visible = started != null
	if started != null:
		var total := float(_state["sortSeconds"]) * 1000.0
		var left := maxf(float(started) + total - _server_now(), 0.0)
		_sort_bar.max_value = total
		_sort_bar.value = total - left
		_status.text = "Segreguje: %d s do następnego przedmiotu" % ceili(left / 1000.0)
		_status.add_theme_color_override("font_color", UI.GOLD)
	elif int(_state["queued"]) > 0:
		_status.text = "Sortownia jest pełna: wyjmij posegregowane przedmioty, aby segregowała dalej."
		_status.add_theme_color_override("font_color", UI.ERROR)
	else:
		_status.text = "Włóż śmieci, a sortownia zacznie segregować."
		_status.add_theme_color_override("font_color", UI.MUTED)


func _process(_delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_update_status()
	var started: Variant = _state.get("startedAt")
	if started != null and _server_now() >= float(started) + float(_state["sortSeconds"]) * 1000.0 and _server_now() >= _next_poll and not _refreshing:
		refresh()


func _load_trash(amount: int) -> void:
	var count := mini(_trash, _room()) if amount == 0 else amount
	_changed(await Net.request("sorter.load", {"sorter": sorter, "quantity": count}))


## Takes out one kind of sorted item, all of them (""), or the trash still waiting.
func _take(item: String) -> void:
	var payload := {"sorter": sorter}
	if item != "":
		payload["item"] = item
	_changed(await Net.request("sorter.take", payload))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "sorter":
		inventory_changed.emit(_state.get("taken", []), _state.get("xp"))


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
