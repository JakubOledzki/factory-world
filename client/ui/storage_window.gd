class_name StorageWindow
extends GameWindow
## A chest, pile, heap or silo standing on a plot: what is in it, taken out to the inventory or
## put in from it. Inserters fill and empty it too, so the window asks again while it is open.

## Items went between the inventory and the storage.
signal inventory_changed
signal failed(reply: Dictionary)
## The player asked to put the storage back into the inventory, with what is in it.
signal pick_up_requested(id: String)

var storage := ""
## The plot the storage stands on.
var plot := Vector2i(-1, -1)

var _state := {}
var _items: Array = []
var _next_poll := 0.0
var _refreshing := false

var _fill: ProgressBar
var _fill_label: Label
var _stored := VBoxContainer.new()
var _load := VBoxContainer.new()
var _help: Label
var _pick_up_button: Button


func _init() -> void:
	super("Magazyn", 420)
	_fill = ProgressBar.new()
	_fill.show_percentage = false
	_fill.custom_minimum_size.y = 10
	content.add_child(_fill)
	_fill_label = UI.label("", UI.MUTED)
	content.add_child(_fill_label)
	_stored.add_theme_constant_override("separation", 4)
	content.add_child(_stored)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Włóż z ekwipunku"))
	_load.add_theme_constant_override("separation", 4)
	content.add_child(_load)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	_pick_up_button = UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(storage))
	_pick_up_button.tooltip_text = "Wszystko, co jest w środku, wróci do ekwipunku"
	content.add_child(_pick_up_button)


func open_at(at: Vector2i, id: String) -> void:
	if id != storage:
		_state = {}
	storage = id
	plot = at
	show_window()
	refresh()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func refresh() -> void:
	if storage == "":
		return
	_refreshing = true
	_next_poll = Time.get_ticks_msec() + 1000.0
	var reply := await Net.request("storage.get", {"x": plot.x, "y": plot.y, "id": storage})
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "storage":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


func _process(_delta: float) -> void:
	# Inserters may be filling or emptying it.
	if visible and not _refreshing and Time.get_ticks_msec() >= _next_poll:
		refresh()


## How many more pieces of an item fit, as the server counts: each kind fills whole slots.
func _room(item: String) -> int:
	var only: Variant = _state.get("only")
	if only != null and not (only as Array).any(func(o: Dictionary) -> bool: return o["id"] == item):
		return 0
	var size := int(_state["slotSize"])
	var mine := 0
	var others := 0
	for stack: Dictionary in _state.get("items", []):
		if stack["id"] == item:
			mine = int(stack["quantity"])
		else:
			others += ceili(float(stack["quantity"]) / size)
	return maxi(0, (int(_state["slots"]) - others) * size - mine)


func _render() -> void:
	if _state.is_empty():
		return
	set_title(_state["name"])
	var stored := int(_state["stored"])
	_fill.max_value = int(_state["slots"])
	_fill.value = int(_state["usedSlots"])
	if int(_state["slots"]) > 1:
		_fill_label.text = "Zajęte miejsca: %d z %d (po %d sztuk)" % [int(_state["usedSlots"]), int(_state["slots"]), int(_state["slotSize"])]
	else:
		_fill_label.text = "Zapełnienie: %d z %d" % [stored, int(_state["capacity"])]

	for child in _stored.get_children():
		child.free()
	if (_state["items"] as Array).is_empty():
		_stored.add_child(UI.label("Pusto.", UI.MUTED))
	for stack: Dictionary in _state["items"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(stack["id"], 28))
		var name_label := UI.label("%s  ×%d" % [stack["name"], int(stack["quantity"])])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for amount: int in [10, 0]:
			var b := UI.button("Wszystko" if amount == 0 else "Weź %d" % amount, _take.bind(stack["id"], amount), amount == 0)
			b.disabled = amount > int(stack["quantity"])
			row.add_child(b)
		_stored.add_child(row)

	for child in _load.get_children():
		child.free()
	var any := false
	for stack: Dictionary in _items:
		var item: String = stack["id"]
		var room := _room(item)
		if room == 0 and not _holds(item):
			continue
		any = true
		var owned := int(stack["quantity"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(item, 26))
		var name_label := UI.label("%s  ×%d" % [stack["name"], owned])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for amount: int in [1, 10, 0]:
			var count := mini(owned, room) if amount == 0 else amount
			var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _put.bind(item, count))
			b.disabled = count < 1 or count > owned or count > room
			if room == 0:
				b.tooltip_text = "Nie ma już miejsca."
			row.add_child(b)
		_load.add_child(row)
	if not any:
		_load.add_child(UI.label("Nie masz nic, co by tu pasowało.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var only: Variant = _state.get("only")
	if only != null:
		_help.text = "Mieści tylko: %s, jeden rodzaj naraz." % ", ".join((only as Array).map(func(o: Dictionary) -> String: return o["name"].to_lower()))
	else:
		_help.text = "Każdy rodzaj przedmiotu zajmuje osobne miejsca. Podajnik ustawiony przodem do skrzyni wkłada do niej, tyłem wyjmuje."
	_fit.call_deferred()


func _holds(item: String) -> bool:
	for stack: Dictionary in _state.get("items", []):
		if stack["id"] == item:
			return true
	return false


func _put(item: String, quantity: int) -> void:
	_changed(await Net.request("storage.put", {"x": plot.x, "y": plot.y, "id": storage, "item": item, "quantity": quantity}))


func _take(item: String, quantity: int) -> void:
	_changed(await Net.request("storage.take", {"x": plot.x, "y": plot.y, "id": storage, "item": item, "quantity": quantity}))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "storage":
		inventory_changed.emit()


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
