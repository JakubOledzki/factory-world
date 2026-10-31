class_name StorageWindow
extends GameWindow
## A chest, pile, heap or silo standing on a plot: what is in it, taken out to the inventory or
## put in from it. Inserters fill and empty it too, so the window asks again while it is open.
## The shelf and the delivery pallet in the garage open in it too (open_in_garage).

## Items went between the inventory and the storage.
signal inventory_changed
signal failed(reply: Dictionary)
## The player asked to put the storage back into the inventory, with what is in it.
signal pick_up_requested(id: String)

var storage := ""
## The plot the storage stands on.
var plot := Vector2i(-1, -1)
## The storage is the shelf or the pallet in the garage, not something on a plot.
var in_garage := false

var _state := {}
var _items: Array = []

var _fill: ProgressBar
var _fill_label: Label
var _stored := VBoxContainer.new()
var _load := VBoxContainer.new()
var _help: Label
var _load_heading: Label
var _pick_up_button: Button


func _init() -> void:
	super("Magazyn", 420)
	poll_every = 1000.0
	_fill = ProgressBar.new()
	_fill.show_percentage = false
	_fill.custom_minimum_size.y = 10
	content.add_child(_fill)
	_fill_label = UI.label("", UI.MUTED)
	content.add_child(_fill_label)
	_stored.add_theme_constant_override("separation", 4)
	content.add_child(_stored)
	content.add_child(HSeparator.new())
	_load_heading = _heading("Włóż z ekwipunku")
	content.add_child(_load_heading)
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
	in_garage = false
	_pick_up_button.visible = true
	show_window()
	refresh()


## The shelf or the delivery pallet in the garage.
func open_in_garage(id: String) -> void:
	if id != storage:
		_state = {}
	storage = id
	in_garage = true
	_pick_up_button.visible = false
	show_window()
	refresh()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func refresh() -> void:
	if storage == "":
		return
	var reply := await fetch("garage.storage", {"id": storage}) if in_garage else await fetch("storage.get", {"x": plot.x, "y": plot.y, "id": storage})
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "storage":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


## Inserters may be filling or emptying it; nothing does in the garage.
func _wants_poll() -> bool:
	return not in_garage


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
	var can_put: bool = _state.get("canPut", true)
	_fill.max_value = int(_state["slots"])
	_fill.value = int(_state["usedSlots"])
	_fill.visible = can_put
	if not can_put:
		_fill_label.text = "Czeka tu, co z zakupów nie zmieściło się w ekwipunku: %d szt." % stored if stored > 0 else "Nic nie czeka na odbiór."
	elif int(_state["slots"]) > 1:
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
		_take_on_click(row, stack)
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
	intake.clear()
	_load.visible = can_put
	_load_heading.visible = can_put
	_help.text = ""
	if not can_put:
		_help.text = "Co z zakupów od handlarza i od graczy nie zmieści się w ekwipunku, trafia na tę paletę. Odbierzesz to, gdy zrobisz miejsce."
		_fit.call_deferred()
		return
	var any := false
	for stack: Dictionary in _items:
		var item: String = stack["id"]
		var room := _room(item)
		if room == 0 and not _holds(item):
			continue
		any = true
		var owned := int(stack["quantity"])
		offer(item, room, func(quantity: int) -> void: _put(item, quantity))
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
	if in_garage:
		_help.text = "Każdy rodzaj przedmiotu zajmuje osobne miejsca, po %d sztuk. Więcej miejsc dają ulepszenia regałów." % int(_state["slotSize"])
	elif only != null:
		_help.text = "Mieści tylko: %s, jeden rodzaj naraz." % ", ".join((only as Array).map(func(o: Dictionary) -> String: return o["name"].to_lower()))
	else:
		_help.text = "Każdy rodzaj przedmiotu zajmuje osobne miejsca. Podajnik ustawiony przodem do skrzyni wkłada do niej, tyłem wyjmuje."
	_help.text += " Przy otwartym ekwipunku [I] dotknij przedmiotu, aby go tu włożyć." if UI.touch() \
		else " Przy otwartym ekwipunku [I] Shift + klik na kafelek wkłada tu jego stos, a przeciągnięcie kafelka na to okno też."
	_fit.call_deferred()


## Shift-click on what lies in the storage takes all of it, Ctrl-click half; a tap on a phone asks how many.
func _take_on_click(row: Control, stack: Dictionary) -> void:
	var item: String = stack["id"]
	var stored := int(stack["quantity"])
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = "Dotknij, aby wybrać, ile wziąć" if UI.touch() else "Shift + klik: weź wszystko, Ctrl + klik: połowę"
	row.gui_input.connect(func(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if UI.touch():
			QuantityDialog.ask(self, item, stack["name"], "Weź", stored, func(quantity: int) -> void: _take(item, quantity))
		elif event.shift_pressed:
			_take(item, 0)
		elif event.ctrl_pressed:
			_take(item, ceili(stored / 2.0))
		else:
			return
		row.accept_event())


func _holds(item: String) -> bool:
	for stack: Dictionary in _state.get("items", []):
		if stack["id"] == item:
			return true
	return false


func _put(item: String, quantity: int) -> void:
	if in_garage:
		_changed(await Net.request("garage.storage.put", {"id": storage, "item": item, "quantity": quantity}))
	else:
		_changed(await Net.request("storage.put", {"x": plot.x, "y": plot.y, "id": storage, "item": item, "quantity": quantity}))


func _take(item: String, quantity: int) -> void:
	if in_garage:
		_changed(await Net.request("garage.storage.take", {"id": storage, "item": item, "quantity": quantity}))
	else:
		_changed(await Net.request("storage.take", {"x": plot.x, "y": plot.y, "id": storage, "item": item, "quantity": quantity}))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "storage":
		inventory_changed.emit()


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
