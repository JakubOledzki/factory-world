class_name WellWindow
extends GameWindow
## An oil or gas well: a pumpjack, a gas well or an offshore platform. It pumps what the survey found
## under the plot by itself, unit after unit, until the deposit it shares with the plot's other wells
## of its kind runs dry. It wears through a gasket every so many units; without a spare it leaks,
## pumps at half the pace and fouls the ground around it unless an oil separator stands near.

## Oil or gas came out, or gaskets went in: [{id, name, quantity}], and the XP gain or null.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 2000.0
const DEPOSITS := ["brak", "małe", "średnie", "duże"]

var well := ""
var plot := Vector2i(-1, -1)

var _state := {}

var _deposit: Label
var _pace: Label
var _icon: TextureRect
var _store: Label
var _stored_bar: ProgressBar
var _take: Button
var _status: Label
var _gaskets: Label
var _wear_bar: ProgressBar
var _seal: Button
var _left: Label


func _init() -> void:
	super("Szyb", 420)
	poll_every = POLL
	_deposit = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_deposit)
	_pace = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_pace)
	content.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_icon = UI.item_icon("crude_oil", 30)
	row.add_child(_icon)
	_store = UI.label("")
	_store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_store)
	_take = UI.button("Wyjmij", _take_product, true)
	row.add_child(_take)
	content.add_child(row)
	_stored_bar = ProgressBar.new()
	_stored_bar.show_percentage = false
	_stored_bar.custom_minimum_size.y = 10
	content.add_child(_stored_bar)
	_status = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	content.add_child(HSeparator.new())
	var gasket_row := HBoxContainer.new()
	gasket_row.add_theme_constant_override("separation", 6)
	gasket_row.add_child(UI.item_icon("gasket", 26))
	_gaskets = UI.label("")
	_gaskets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gasket_row.add_child(_gaskets)
	_seal = UI.button("Włóż uszczelki", _seal_well)
	_seal.tooltip_text = "Włoży wszystkie uszczelki z ekwipunku, do kompletu"
	gasket_row.add_child(_seal)
	content.add_child(gasket_row)
	_wear_bar = ProgressBar.new()
	_wear_bar.show_percentage = false
	_wear_bar.custom_minimum_size.y = 8
	content.add_child(_wear_bar)
	_left = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_left)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(well))
	pick_up.tooltip_text = "To, co jest w szybie, i jego uszczelki wrócą do ekwipunku"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	if id != well:
		_state = {}
	plot = at
	well = id
	show_window()
	refresh()


func refresh() -> void:
	if well == "":
		return
	var reply := await fetch("well.get", {"x": plot.x, "y": plot.y, "id": well})
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "well":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


func _render() -> void:
	if _state.is_empty():
		return
	set_title(_state["name"])
	var product: String = _state["productName"]
	_icon.texture = UI.item_icon(_state["product"], 30).texture
	_deposit.text = "%s · złoże %s (%s)" % [_state["name"], DEPOSITS[clampi(int(_state["size"]), 0, 3)], product.to_lower()]
	var speed := float(_state["speed"])
	_pace.text = "Jedna jednostka na %s s%s." % [_number(float(_state["seconds"])), " (z pełnym prądem)" if _state["powered"] else ""]
	if _state["leaking"]:
		_pace.text += " Cieknie: pompuje dwa razy wolniej."
	if speed <= 0.0:
		_pace.text += " Brak prądu: szyb stoi. Postaw słup obok i elektrownię."
		_pace.add_theme_color_override("font_color", UI.ERROR)
	elif speed < 0.999:
		_pace.text += " Za mało prądu: pracuje na %d%%." % roundi(speed * 100.0)
		_pace.add_theme_color_override("font_color", UI.ERROR)
	else:
		_pace.add_theme_color_override("font_color", UI.ERROR if _state["leaking"] else UI.TEXT)
	var stored := int(_state["stored"])
	var capacity := int(_state["capacity"])
	_store.text = "%s: %d / %d" % [product, stored, capacity]
	_stored_bar.max_value = capacity
	_stored_bar.value = stored
	_take.disabled = stored == 0
	var left := int(_state["left"])
	if left <= 0:
		_status.text = "Złoże wyczerpane: szyb nic już nie wypompuje."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif _state.get("full", false):
		_status.text = "Pełny: szyb nie pompuje, dopóki go nie opróżnisz (ręcznie albo pompą do rury)."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif _state["polluting"]:
		_status.text = "Ropa wycieka i zanieczyszcza ziemię do 6 pól wokół: nic tam nie posiejesz ani nie posadzisz. Włóż uszczelkę albo postaw obok separator ropy."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif speed > 0.0:
		_status.text = "Pracuje: %s płynie sama, wyjmij ją ręcznie albo pompą." % product.to_lower()
		_status.add_theme_color_override("font_color", UI.GOLD)
	else:
		_status.text = ""
	var wear_limit := int(_state["wearLimit"])
	_gaskets.text = "Uszczelki w zapasie: %d / %d%s" % [int(_state["gaskets"]), int(_state["maxGaskets"]),
		" · szyb cieknie!" if _state["leaking"] else ""]
	_gaskets.add_theme_color_override("font_color", UI.ERROR if _state["leaking"] else UI.TEXT)
	_wear_bar.max_value = wear_limit
	_wear_bar.value = wear_limit if _state["leaking"] else int(_state["wear"])
	_seal.disabled = not _state["leaking"] and int(_state["gaskets"]) >= int(_state["maxGaskets"])
	_left.text = "W złożu zostało %d z %d. Uszczelka starcza na %d jednostek." % [left, int(_state["reserve"]), wear_limit]
	_fit.call_deferred()


func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0").replace(".", ",")



func _take_product() -> void:
	var reply := await Net.request("well.take", {"x": plot.x, "y": plot.y, "id": well})
	_apply(reply)
	if reply["type"] == "well":
		inventory_changed.emit(_state.get("taken", []), _state.get("xp"))


func _seal_well() -> void:
	var reply := await Net.request("well.seal", {"x": plot.x, "y": plot.y, "id": well})
	_apply(reply)
	if reply["type"] == "well":
		inventory_changed.emit([], null)
