class_name CanteenWindow
extends GameWindow
## A works canteen on a plot: dishes from the inventory feed the crews of the plot's machines that
## burn fuel or run on power, and while there is food they work faster. Shows how long the food lasts
## and how many machines it feeds; inserters next to it can serve dishes too.

## Dishes went from the inventory into the canteen.
signal inventory_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

const POLL := 5000.0

var canteen := ""

var _state := {}
var _items: Array = []
var _clock_offset := 0.0

var _status: Label
var _crews: Label
var _dishes := VBoxContainer.new()
var _help: Label


func _init() -> void:
	super("Stołówka zakładowa", 400)
	poll_every = POLL
	_status = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	_crews = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_crews)
	content.add_child(HSeparator.new())
	var heading := UI.label("Wydaj jedzenie", UI.GOLD)
	heading.add_theme_font_override("font", UI.bold())
	content.add_child(heading)
	_dishes.add_theme_constant_override("separation", 4)
	content.add_child(_dishes)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	content.add_child(UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(canteen)))


func open_at(id: String) -> void:
	if id != canteen:
		_state = {}
	canteen = id
	show_window()
	_items = await _inventory()
	refresh()


func refresh() -> void:
	if canteen == "":
		return
	var reply := await fetch("canteen.get", {"canteen": canteen})
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "canteen":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_render()


func _render() -> void:
	if _state.is_empty():
		return
	var bonus := int(_state["bonusPercent"])
	if _state.get("fed", false):
		var left := (float(_state["fedUntil"]) - (Time.get_unix_time_from_system() * 1000.0 + _clock_offset)) / 1000.0
		_status.text = "Załogi najedzone jeszcze %s: maszyny na opał i na prąd pracują o %d%% szybciej." % [_duration(left), bonus]
		_status.add_theme_color_override("font_color", UI.GOLD)
	else:
		_status.text = "Stołówka pusta: maszyny pracują zwykłym tempem."
		_status.add_theme_color_override("font_color", UI.MUTED)
	var crews := int(_state["crews"])
	_crews.text = "Karmi %d %s; porcja wystarcza jednej maszynie na %d min." % [crews, "maszynę" if crews == 1 else "maszyny" if crews < 5 else "maszyn",
		int(_state["portionMinutes"])]
	UI.clear(_dishes)
	var any := false
	for dish: Dictionary in _state.get("dishes", []):
		var owned := _count(dish["id"])
		if owned == 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(dish["id"], 26))
		var name_label := UI.label("%s  ×%d  (%d porcji)" % [dish["name"], owned, int(dish["portions"])])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for amount: int in [1, 10, 0]:
			var count := owned if amount == 0 else amount
			var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _load.bind(dish["id"], count))
			b.disabled = count > owned
			row.add_child(b)
		_dishes.add_child(row)
	if not any:
		var names: Array[String] = []
		for dish: Dictionary in _state.get("dishes", []):
			names.append(String(dish["name"]).to_lower())
		_dishes.add_child(UI.label("Nie masz dań, które stołówka wydaje (%s)." % ", ".join(names), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_help.text = "Zapas wystarcza najwyżej na %d h. Podajnik obok stołówki sam doniesie dania z taśmy albo skrzyni. Jedna stołówka na działkę." % int(_state["maxHours"])
	_fit.call_deferred()


func _load(item: String, quantity: int) -> void:
	var reply := await Net.request("canteen.load", {"canteen": canteen, "item": item, "quantity": quantity})
	_apply(reply)
	if reply["type"] == "canteen":
		_items = await _inventory()
		_render()
		inventory_changed.emit()


func _inventory() -> Array:
	var reply := await Net.request("inventory.get")
	return reply["payload"]["items"] if reply["type"] == "inventory" else []


func _count(item: String) -> int:
	var total := 0
	for stack: Dictionary in _items:
		if stack["id"] == item:
			total += int(stack["quantity"])
	return total


func _duration(seconds: float) -> String:
	var minutes := maxi(1, ceili(seconds / 60.0))
	return "%d min" % minutes if minutes < 60 else "%d h %d min" % [minutes / 60, minutes % 60]
