class_name FurnaceWindow
extends GameWindow
## A stone furnace: coal goes on the fire, ore goes in and comes out as ingots, one piece after
## another, while the player is away too. One coal lasts for a few smelts. The furnace holds one
## kind of ore at a time; ingots wait in it until taken out.

## After every answer from the server, with the furnace as it is now.
signal updated(furnace: Dictionary)
## Items went from the inventory into the furnace or back: [{id, name, quantity}] taken out, XP.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
## The player asked to put the furnace back into the inventory (only where `can_pick_up`).
signal pick_up_requested(id: String)

const COAL := "coal"
## What goes on the fire: coal and charcoal burn alike.
const FUELS := ["coal", "charcoal"]

var furnace := ""
var can_pick_up := false

var _state := {}
var _items: Array = []
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _slots := VBoxContainer.new()
var _status: Label
var _smelt_bar: ProgressBar
var _load := VBoxContainer.new()
var _help: Label
var _pick_up_button: Button


func _init() -> void:
	super("Piec kamienny", 400)
	_slots.add_theme_constant_override("separation", 4)
	content.add_child(_slots)
	_status = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	_smelt_bar = ProgressBar.new()
	_smelt_bar.show_percentage = false
	_smelt_bar.custom_minimum_size.y = 10
	content.add_child(_smelt_bar)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Włóż do pieca"))
	_load.add_theme_constant_override("separation", 4)
	content.add_child(_load)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	_pick_up_button = UI.button("Schowaj piec do ekwipunku", func() -> void: pick_up_requested.emit(furnace))
	_pick_up_button.tooltip_text = "Wszystko, co jest w piecu, wróci do ekwipunku"
	_pick_up_button.visible = false
	content.add_child(_pick_up_button)


func open_at(id: String) -> void:
	if id != furnace:
		_state = {}
	furnace = id
	_pick_up_button.visible = can_pick_up
	show_window()
	refresh()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func refresh() -> void:
	if furnace == "":
		return
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("furnace.get", {"furnace": furnace})
	_refreshing = false
	_apply(reply)


## Until when (server milliseconds) a furnace in this state keeps burning, or 0 when it is cold.
static func burns_until(state: Dictionary) -> float:
	if state.get("startedAt") == null or state.get("input") == null or state.get("smeltSeconds") == null:
		return 0.0
	var smelts := mini(int(state["input"]["quantity"]), int(state["heat"]) + int(state["fuel"]) * int(state.get("smeltsPerCoal", 5)))
	return float(state["startedAt"]) + smelts * float(state["smeltSeconds"]) * 1000.0


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "furnace":
		failed.emit(reply)
		return
	_state = reply["payload"]
	set_title(_state.get("name", "Piec kamienny"))
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	updated.emit(_state)
	_render()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _smeltable() -> Dictionary:
	var by_ore := {}
	for recipe: Dictionary in _state.get("recipes", []):
		by_ore[recipe["input"]] = recipe
	return by_ore


func _render() -> void:
	if _state.is_empty():
		return
	for child in _slots.get_children():
		child.free()
	var input: Variant = _state.get("input")
	var output: Variant = _state.get("output")
	var fuel := int(_state["fuel"])
	var heat := int(_state["heat"])
	_slots.add_child(_slot_row(input["id"] if input != null else "", "Ruda", "%s × %d" % [input["name"], int(input["quantity"])] if input != null else "pusto", "input", input != null, false))
	var fuel_text := "%d" % fuel
	if heat > 0:
		fuel_text += "  (w ogniu jeszcze na %d)" % heat
	_slots.add_child(_slot_row(COAL if fuel > 0 else "", "Węgiel", fuel_text if fuel > 0 or heat > 0 else "pusto", "fuel", fuel > 0, false))
	_slots.add_child(_slot_row(output["id"] if output != null else "", "Gotowe", "%s × %d" % [output["name"], int(output["quantity"])] if output != null else "pusto", "output", output != null, true))

	for child in _load.get_children():
		child.free()
	var smeltable := _smeltable()
	var any := false
	for stack: Dictionary in _items:
		var item: String = stack["id"]
		if not FUELS.has(item) and not smeltable.has(item):
			continue
		any = true
		var owned := int(stack["quantity"])
		var room := int(_state["maxFuel"]) - fuel if FUELS.has(item) else int(_state["maxInput"]) - (int(input["quantity"]) if input != null else 0)
		var blocked: bool = not FUELS.has(item) and input != null and input["id"] != item
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(item, 26))
		var name_label := UI.label("%s  ×%d" % [stack["name"], owned])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not FUELS.has(item):
			name_label.tooltip_text = "→ %s, %s s" % [smeltable[item]["outputName"], _seconds(float(smeltable[item]["seconds"]))]
			name_label.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(name_label)
		for amount: int in [1, 10, 0]:
			var count := mini(owned, room) if amount == 0 else amount
			var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _put.bind(item, count))
			b.disabled = blocked or count < 1 or count > owned or count > room
			if blocked:
				b.tooltip_text = "W piecu jest już inna ruda. Wyjmij ją najpierw."
			row.add_child(b)
		_load.add_child(row)
	if not any:
		_load.add_child(UI.label("Nie masz rudy ani węgla. Rudy i węgiel wydobywa się w kopalniach w górach, a węgiel drzewny wypala z drewna mielerz.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var lines: Array[String] = []
	if int(_state.get("speed", 1)) > 1:
		lines.append("Poziom %d: przetapia %d razy szybciej niż piec kamienny i mieści po %d rudy i węgla."
			% [int(_state["level"]), int(_state["speed"]), int(_state["maxInput"])])
	lines.append("1 węgiel wystarcza na %d przetopień." % int(_state["smeltsPerCoal"]))
	for recipe: Dictionary in _state.get("recipes", []):
		lines.append("%s → %s: %s s" % [recipe["inputName"], recipe["outputName"].to_lower(), _seconds(float(recipe["seconds"]))])
	_help.text = "\n".join(lines)
	_update_status()
	_fit.call_deferred()


## Seconds as players read them: 10, or 2,5 with a decimal comma.
static func _seconds(seconds: float) -> String:
	return "%d" % int(seconds) if is_equal_approx(seconds, roundf(seconds)) else ("%.1f" % seconds).replace(".", ",")


func _slot_row(item: String, title: String, text: String, what: String, can_take: bool, accent: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if item != "":
		row.add_child(UI.item_icon(item, 30))
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(30, 30)
		row.add_child(gap)
	var label := UI.label("%s:" % title, UI.MUTED)
	label.custom_minimum_size.x = 64
	row.add_child(label)
	var value := UI.label(text)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var b := UI.button("Wyjmij", _take.bind(what), accent and can_take)
	b.disabled = not can_take
	row.add_child(b)
	return row


func _update_status() -> void:
	var input: Variant = _state.get("input")
	var started: Variant = _state.get("startedAt")
	_smelt_bar.visible = started != null
	if started != null:
		var total := float(_state["smeltSeconds"]) * 1000.0
		var left := maxf(float(started) + total - _server_now(), 0.0)
		_smelt_bar.max_value = total
		_smelt_bar.value = total - left
		_status.text = "Pali się: %s → %s, %d s" % [input["name"], _output_name(input["id"]).to_lower(), ceili(left / 1000.0)]
		_status.add_theme_color_override("font_color", UI.GOLD)
	elif input != null:
		_status.text = "Piec wygasł: dołóż węgla, aby przetapiać dalej."
		_status.add_theme_color_override("font_color", UI.MUTED)
	else:
		_status.text = "Włóż rudę i węgiel, a piec zacznie przetapiać."
		_status.add_theme_color_override("font_color", UI.MUTED)


func _output_name(ore: String) -> String:
	return _smeltable().get(ore, {}).get("outputName", "")


func _process(_delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_update_status()
	var started: Variant = _state.get("startedAt")
	if started != null and _server_now() >= float(started) + float(_state["smeltSeconds"]) * 1000.0 and _server_now() >= _next_poll and not _refreshing:
		refresh()


func _put(item: String, quantity: int) -> void:
	_changed(await Net.request("furnace.load", {"furnace": furnace, "item": item, "quantity": quantity}))


func _take(what: String) -> void:
	_changed(await Net.request("furnace.take", {"furnace": furnace, "what": what}))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "furnace":
		inventory_changed.emit(_state.get("taken", []), _state.get("xp"))


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
