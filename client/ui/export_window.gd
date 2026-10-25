class_name ExportWindow
extends GameWindow
## The export chest by a plot's station: the player sets a price for each kind of goods in it, and every full hour a train
## takes everything priced to the nearest buying market in a town, which lists it on the players' market at that price when
## the train gets there. Over land the train needs a tenth of a minute a plot; across the sea it goes on a ferry from a rail
## port, three times as slow, for the port owner's fee. The market's owner takes a commission on the goods.

signal inventory_changed
signal balance_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 5000.0
const PROBLEMS := {
	"empty": "Ostatni pociąg odjechał pusty: skrzynia była pusta.",
	"no_price": "Ostatni pociąg nic nie zabrał: żaden towar w skrzyni nie ma ceny.",
	"no_market": "Ostatni pociąg nic nie zabrał: na świecie nie ma jeszcze żadnego rynku skupu.",
	"no_route": "Ostatni pociąg nic nie zabrał: do żadnego rynku skupu nie da się dojechać, brakuje portów pociągowych.",
	"no_money": "Ostatni pociąg nic nie zabrał: zabrakło pieniędzy na prowizję i opłaty portów.",
}

var plot := Vector2i(-1, -1)

var _state := {}
var _clock_offset := 0.0
var _items: Array = []
## Item → what the trader pays for it, in cents, to suggest a price.
var _trader := {}
var _next: Label
var _route: Label
var _last: Label
var _fill: ProgressBar
var _rows := VBoxContainer.new()
var _on_way := VBoxContainer.new()
var _picker: OptionButton
var _quantity: SpinBox
## Item → its price field, so a poll does not overwrite what the player is typing.
var _price_fields := {}
var _times: Array = []


func _init() -> void:
	super("Skrzynia eksportowa", 500)
	poll_every = POLL
	_next = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_next)
	_route = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_route)
	_last = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_last)
	content.add_child(HSeparator.new())
	_fill = ProgressBar.new()
	_fill.show_percentage = false
	_fill.custom_minimum_size.y = 8
	content.add_child(_fill)
	_rows.add_theme_constant_override("separation", 4)
	content.add_child(_rows)
	content.add_child(HSeparator.new())
	content.add_child(UI.label("Włóż z ekwipunku", UI.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.clip_text = true
	row.add_child(_picker)
	_quantity = _spin(1, 1600, 100)
	row.add_child(_quantity)
	row.add_child(UI.button("Włóż", _load, true))
	content.add_child(row)
	content.add_child(HSeparator.new())
	_on_way.add_theme_constant_override("separation", 4)
	content.add_child(_on_way)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(str(_state.get("id", ""))))
	pick_up.tooltip_text = "Towar ze skrzyni wróci do ekwipunku; pociągi w drodze i tak dojadą"
	content.add_child(pick_up)


func open_at(at: Vector2i) -> void:
	if at != plot:
		_state = {}
		_price_fields = {}
	plot = at
	show_window()
	refresh()
	_reload_items()


func refresh() -> void:
	if plot.x < 0:
		return
	_apply(await fetch("export.get", {"x": plot.x, "y": plot.y}))


func server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "export":
		failed.emit(reply)
		return false
	var shipped_before := int(_state.get("lastAt", 0) if _state.get("lastAt") != null else 0)
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var shipped: int = int(_state["lastAt"]) if _state["lastAt"] != null else 0
	if shipped_before > 0 and shipped != shipped_before:
		# The train took the goods and paid the fees.
		balance_changed.emit()
	_render()
	return true


func _render() -> void:
	if _state.is_empty():
		return
	_times.clear()
	var rates: Dictionary = _state["rates"]
	_route.text = _route_text()
	_last.text = _last_text()
	var used := 0
	for item: Dictionary in _state["items"]:
		used += int(item["quantity"])
	_fill.max_value = int(_state["capacity"])
	_fill.value = used
	_fill.tooltip_text = "%d / %d szt., najwyżej %d rodzajów" % [used, int(_state["capacity"]), int(_state["maxKinds"])]

	UI.clear(_rows)
	_price_fields = {}
	var header := UI.label("W skrzyni %d / %d szt. Cena za sztukę, po której pociąg wystawi towar (0 = zostaje w skrzyni):" % [used, int(_state["capacity"])],
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	_rows.add_child(header)
	if (_state["items"] as Array).is_empty() and (_state["prices"] as Array).is_empty():
		_rows.add_child(UI.label("Skrzynia jest pusta. Włóż towar albo dowieź go podajnikiem z taśmy.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for item: Dictionary in _state["items"]:
		_item_row(item["id"], item["name"], int(item["quantity"]), item["priceCents"])
	for price: Dictionary in _state["prices"]:
		_item_row(price["id"], price["name"], 0, price["priceCents"])

	UI.clear(_on_way)
	var title := UI.label("W drodze na rynek", UI.GOLD)
	_on_way.add_child(title)
	if (_state["shipments"] as Array).is_empty():
		_on_way.add_child(UI.label("Żaden pociąg z towarem z tej skrzyni nie jest w drodze. Pociąg przyjeżdża co %d min, o pełnej godzinie." %
			int(rates["everyMinutes"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for trip: Dictionary in _state["shipments"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(trip["item"], 26))
		var text := UI.label("%d × %s po %s · %s" % [int(trip["quantity"]), trip["name"], _money(int(trip["priceCents"])), trip["town"]])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		row.add_child(text)
		var left := UI.label("", UI.MUTED)
		left.custom_minimum_size.x = 64
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(left)
		_on_way.add_child(row)
		_times.append([left, float(trip["arrivesAt"]), "na rynku"])
	_times.append([_next, float(_state["nextAt"]), ""])
	_update_times()
	_fit.call_deferred()


func _item_row(item: String, name: String, quantity: int, price: Variant) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 28))
	var text := UI.label("%s\n%s" % [name, "%d szt." % quantity if quantity > 0 else "brak w skrzyni"], UI.TEXT if quantity > 0 else UI.MUTED)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.clip_text = true
	row.add_child(text)
	var field := _spin(0, 1_000_000, 0)
	field.step = 0.01
	field.rounded = false
	field.suffix = "$"
	field.value = int(price) / 100.0 if price != null else (_trader.get(item, 0) / 100.0)
	field.tooltip_text = "Cena za sztukę na rynku graczy"
	row.add_child(field)
	_price_fields[item] = field
	var set_price := UI.button("Ustaw" if price == null else "Zmień", func() -> void: _set_price(item, roundi(field.value * 100.0)), price == null)
	row.add_child(set_price)
	if quantity > 0:
		row.add_child(UI.button("Wyjmij", func() -> void: _unload(item, quantity)))
	_rows.add_child(row)


func _route_text() -> String:
	var route: Variant = _state["route"]
	if route == null:
		if int(_state["markets"]) == 0:
			return "Na świecie nie ma jeszcze żadnego rynku skupu, więc nic nie da się wystawić. Rynek skupu buduje się w mieście (po badaniu „Rynek skupu”)."
		return "Żaden rynek skupu nie leży na tym lądzie, a pociągi nie jeżdżą po wodzie: potrzebny jest port pociągowy na wybrzeżu tego lądu i drugi tam, gdzie stoi rynek."
	var market: Dictionary = route["market"]
	var text := "Najbliższy rynek skupu: %s (%s, prowizja %d%%). Droga: %s lądem" % [route["town"], market["owner"], int(route["commissionPercent"]),
		_plots(float(route["landPlots"]))]
	if float(route["seaPlots"]) > 0.0:
		text += " i %s promem (3 × wolniej)" % _plots(float(route["seaPlots"]))
	text += ", %s jazdy." % _duration(int(route["tripSeconds"]))
	var ports: Array = route["ports"]
	if not ports.is_empty():
		var names: Array[String] = []
		for port: Dictionary in ports:
			names.append("%d × %d (%s, %s)" % [int(port["x"]), int(port["y"]), port["owner"], _money(int(port["value"]))])
		text += "\nPorty pociągowe: %s. Za przeprawę zapłacisz %s." % [", ".join(names), _money(int(route["portFeesCents"]))]
	return text


func _last_text() -> String:
	var problem: Variant = _state["problem"]
	if problem != null:
		return PROBLEMS.get(problem, "Ostatni pociąg nic nie zabrał.")
	if _state["lastAt"] == null:
		return "Pierwszy pociąg przyjedzie o pełnej godzinie i zabierze każdy towar, który ma cenę."
	return "Ostatni pociąg zabrał %d szt." % int(_state["lastQuantity"])


func _update_times() -> void:
	var now := server_now()
	for entry: Array in _times:
		var label: Label = entry[0]
		if not is_instance_valid(label):
			continue
		var seconds := ceili(maxf(entry[1] - now, 0.0) / 1000.0)
		if label == _next:
			label.text = "Następny pociąg za %s: zabierze towar z ceną na rynek skupu." % _clock(seconds) if seconds > 0 else "Pociąg ładuje towar…"
		else:
			label.text = _clock(seconds) if seconds > 0 else entry[2]


func _process(delta: float) -> void:
	super(delta)
	if visible and not _times.is_empty():
		_update_times()


func _reload_items() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		return
	_items = reply["payload"]["items"]
	if _trader.is_empty():
		var prices := await Net.request("market.prices")
		if prices["type"] == "market.prices":
			for p: Dictionary in prices["payload"]["items"]:
				# What the trader pays for a piece: a price to start from.
				if p.get("sellCents") != null:
					_trader[p["id"]] = int(p["sellCents"])
	var selected: String = _picker.get_item_metadata(_picker.selected) if _picker.selected >= 0 else ""
	_picker.clear()
	for stack: Dictionary in _items:
		_picker.add_item("%s (%d)" % [stack["name"], int(stack["quantity"])])
		_picker.set_item_metadata(_picker.item_count - 1, stack["id"])
		if stack["id"] == selected:
			_picker.select(_picker.item_count - 1)


func _load() -> void:
	if _picker.selected < 0:
		return
	var item: String = _picker.get_item_metadata(_picker.selected)
	if _apply(await Net.request("export.load", {"x": plot.x, "y": plot.y, "item": item, "quantity": int(_quantity.value)})):
		inventory_changed.emit()
		_reload_items()


func _unload(item: String, quantity: int) -> void:
	if _apply(await Net.request("export.unload", {"x": plot.x, "y": plot.y, "item": item, "quantity": quantity})):
		inventory_changed.emit()
		_reload_items()


func _set_price(item: String, cents: int) -> void:
	_apply(await Net.request("export.price", {"x": plot.x, "y": plot.y, "item": item, "priceCents": cents}))


func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size.x = 96
	spin.select_all_on_focus = true
	return spin


static func _plots(plots: float) -> String:
	return "%s dz." % str(snappedf(plots, 0.1)).replace(".", ",")


static func _duration(seconds: int) -> String:
	if seconds < 3600:
		return "%d min %02d s" % [seconds / 60, seconds % 60]
	return "%d h %02d min" % [seconds / 3600, (seconds % 3600) / 60]


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## An amount that never breaks between the number and the dollar sign.
func _money(cents: int) -> String:
	return UI.money(cents).replace(" ", "\u00a0")
