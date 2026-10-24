class_name MachineWindow
extends GameWindow
## A processing machine on a plot (mill, oil press, pickling barrel, bakery, field kitchen):
## pick what it makes, load the ingredients (and fuel, where it burns it), and it makes one batch
## after another while the player is away too. Products wait in it until taken out.

## After every answer from the server, with the machine as it is now.
signal updated(machine: Dictionary)
## Items came back from the machine: [{id, name, quantity}] taken out, and the XP gain or null.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
## The player asked to put the machine back into the inventory.
signal pick_up_requested(id: String)

var machine := ""

var _state := {}
var _items: Array = []
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _recipes := HFlowContainer.new()
var _formula: Label
var _slots := VBoxContainer.new()
var _status: Label
var _progress: ProgressBar
var _help: Label


func _init() -> void:
	super("Maszyna", 420)
	content.add_child(_heading("Co ma powstawać?"))
	_recipes.add_theme_constant_override("h_separation", 4)
	_recipes.add_theme_constant_override("v_separation", 4)
	content.add_child(_recipes)
	_formula = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_formula)
	content.add_child(HSeparator.new())
	_slots.add_theme_constant_override("separation", 4)
	content.add_child(_slots)
	_status = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 10
	content.add_child(_progress)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(machine))
	pick_up.tooltip_text = "Wszystko, co jest w środku, wróci do ekwipunku"
	content.add_child(pick_up)


func open_at(id: String, title: String) -> void:
	if id != machine:
		_state = {}
	machine = id
	set_title(title)
	show_window()
	refresh()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func refresh() -> void:
	if machine == "":
		return
	_refreshing = true
	_next_poll = _server_now() + (500.0 if _speed() >= 0.999 else 2000.0)
	var reply := await Net.request("machine.get", {"machine": machine})
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "machine":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	set_title(_state["name"])
	updated.emit(_state)
	_render()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _recipe() -> Dictionary:
	for recipe: Dictionary in _state.get("recipes", []):
		if recipe["id"] == _state.get("recipe"):
			return recipe
	return {}


func _render() -> void:
	if _state.is_empty():
		return
	for child in _recipes.get_children():
		child.free()
	for recipe: Dictionary in _state["recipes"]:
		var chosen: bool = recipe["id"] == _state.get("recipe")
		var b := UI.button(recipe["name"], _choose.bind(recipe["id"]), chosen)
		b.icon = UI.item_texture(recipe["id"])
		b.set_meta("item", recipe["id"])
		b.add_theme_constant_override("icon_max_width", 24)
		b.tooltip_text = _formula_text(recipe)
		if recipe.get("locked") != null:
			b.disabled = true
			b.tooltip_text += "\nNajpierw zbadaj: %s (drzewko technologii przy stole warsztatowym)" % recipe["locked"]
		_recipes.add_child(b)

	var recipe := _recipe()
	_formula.text = _formula_text(recipe) if not recipe.is_empty() else "Wybierz przepis, a potem włóż składniki."

	for child in _slots.get_children():
		child.free()
	if not recipe.is_empty():
		for input: Dictionary in _state["inputs"]:
			var room := int(_state["maxInput"]) - int(input["quantity"])
			_slots.add_child(_stack_row(input["id"], "%s: %d" % [input["name"], int(input["quantity"])], [int(input["need"]), 10, 0], room))
		var take_inputs := UI.button("Wyjmij składniki", _take.bind("input"))
		take_inputs.disabled = _state["inputs"].all(func(i: Dictionary) -> bool: return int(i["quantity"]) == 0)
		_slots.add_child(take_inputs)
	if _state["fired"]:
		_slots.add_child(HSeparator.new())
		var fuel: Variant = _state.get("fuel")
		var heat := int(_state["heat"])
		var text := "Opał: %s × %d" % [fuel["name"], int(fuel["quantity"])] if fuel != null else "Opał: pusto"
		if heat > 0:
			text += "  (w ogniu jeszcze na %d)" % heat
		_slots.add_child(UI.label(text))
		for f: Dictionary in _state["fuels"]:
			if _count(f["id"]) > 0:
				var blocked: bool = fuel != null and fuel["id"] != f["id"]
				var room := 0 if blocked else int(_state["maxFuel"]) - (int(fuel["quantity"]) if fuel != null else 0)
				_slots.add_child(_stack_row(f["id"], "%s (1 = %d %s)" % [f["name"], int(f["batches"]), _batches_word(int(f["batches"]))], [1, 10, 0], room))
		var take_fuel := UI.button("Wyjmij opał", _take.bind("fuel"))
		take_fuel.disabled = fuel == null
		_slots.add_child(take_fuel)
	_slots.add_child(HSeparator.new())
	var output: Variant = _state.get("output")
	var out_row := HBoxContainer.new()
	out_row.add_theme_constant_override("separation", 6)
	out_row.add_child(UI.item_icon(output["id"], 30) if output != null else _gap(30))
	var out_label := UI.label("Gotowe: %s × %d" % [output["name"], int(output["quantity"])] if output != null else "Gotowe: pusto")
	out_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_row.add_child(out_label)
	var take := UI.button("Wyjmij", _take.bind("output"), output != null)
	take.disabled = output == null
	out_row.add_child(take)
	_slots.add_child(out_row)

	var help: Array[String] = ["Maszyna pracuje dalej, gdy odejdziesz. Mieści %d sztuk gotowych produktów." % int(_state["maxOutput"])]
	if _state["fired"]:
		help.append("Potrzebuje opału: węgla albo drewna.")
	if _state.get("powered", false):
		help.append("Działa na prąd: postaw generator parowy z opałem i słup energetyczny najwyżej 2 pola od maszyny.")
	_help.text = " ".join(help)
	_update_status()
	_fit.call_deferred()


func _formula_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for i: Dictionary in recipe["ingredients"]:
		parts.append("%d × %s" % [int(i["quantity"]), i["name"].to_lower()])
	return "%s → %d × %s, %d s" % [" + ".join(parts), int(recipe["quantity"]), recipe["name"].to_lower(), int(recipe["seconds"])]


func _batches_word(n: int) -> String:
	return "partię" if n == 1 else "partie"


## A row with an item, its text and buttons that put `amounts` of it from the inventory (0 = all that fits).
func _stack_row(item: String, text: String, amounts: Array, room: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var label := UI.label(text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var owned := _count(item)
	var shown := {}
	for amount: int in amounts:
		if shown.has(amount):
			continue
		shown[amount] = true
		var count := mini(owned, room) if amount == 0 else amount
		var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _put.bind(item, count))
		b.disabled = count < 1 or count > owned or count > room
		row.add_child(b)
	return row


func _gap(size: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(size, size)
	return gap


## How fast the machine works on the power it has: 1 for machines that need none.
func _speed() -> float:
	return float(_state.get("speed", 1.0)) if _state.get("powered", false) else 1.0


## Milliseconds of work done on the batch being made; short of power the machine works slower.
func _done() -> float:
	var server_time := float(_state["serverTime"])
	return server_time - float(_state["startedAt"]) + maxf(_server_now() - server_time, 0.0) * _speed()


func _update_status() -> void:
	var started: Variant = _state.get("startedAt")
	_progress.visible = started != null
	var recipe := _recipe()
	if started != null:
		var total := float(_state["seconds"]) * 1000.0
		var left := maxf(total - _done(), 0.0)
		_progress.max_value = total
		_progress.value = total - left
		var speed := _speed()
		if speed <= 0.0:
			_status.text = "Brak prądu: %s czeka. Postaw generator z opałem i słup obok maszyny." % recipe["name"].to_lower()
			_status.add_theme_color_override("font_color", UI.ERROR)
		else:
			var short := " Za mało prądu: pracuje na %d%%." % roundi(speed * 100.0) if speed < 0.999 else ""
			_status.text = "Pracuje: %s, %d s (wystarczy jeszcze na %d).%s" % [recipe["name"].to_lower(), ceili(left / 1000.0 / speed),
				int(_state["batches"]), short]
			_status.add_theme_color_override("font_color", UI.GOLD if short == "" else UI.ERROR)
	else:
		_status.add_theme_color_override("font_color", UI.MUTED)
		if recipe.is_empty():
			_status.text = "Maszyna czeka na przepis."
		elif _state.get("output") != null and int(_state["output"]["quantity"]) >= int(_state["maxOutput"]):
			_status.text = "Maszyna jest pełna: wyjmij gotowe produkty."
		elif _state["fired"] and _state.get("fuel") == null and int(_state["heat"]) == 0:
			_status.text = "Ogień wygasł: dołóż opału."
		else:
			_status.text = "Stoi: włóż składniki na pełną partię."


func _process(_delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_update_status()
	var started: Variant = _state.get("startedAt")
	# A machine short of power is asked again now and then: a generator may get fuel.
	var due := started != null and (_done() >= float(_state["seconds"]) * 1000.0 or _speed() < 0.999)
	if due and _server_now() >= _next_poll and not _refreshing:
		refresh()


func _choose(recipe: String) -> void:
	_changed(await Net.request("machine.recipe", {"machine": machine, "recipe": recipe}))


func _put(item: String, quantity: int) -> void:
	_changed(await Net.request("machine.load", {"machine": machine, "item": item, "quantity": quantity}))


func _take(what: String) -> void:
	_changed(await Net.request("machine.take", {"machine": machine, "what": what}))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "machine":
		inventory_changed.emit(_state.get("taken", []), _state.get("xp"))


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
