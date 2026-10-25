class_name ShopWindow
extends GameWindow
## A shop in a city: the owner puts goods on its shelves at a price, and the townspeople come in and buy by
## themselves, more the bigger the town and the closer to its centre. At the trader's price every customer buys,
## at twice that half of them, at three times nobody. The money goes straight into the wallet, less the mayor's tax.

signal inventory_changed
signal balance_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 5000.0

var shop := ""

var _state := {}
var _items: Array = []
## Item → what the trader pays for it, in cents.
var _trader := {}
var _summary: Label
var _shelves := VBoxContainer.new()
var _picker: OptionButton
var _quantity: SpinBox
var _price: SpinBox
var _chance: Label


func _init() -> void:
	super("Sklep", 480)
	poll_every = POLL
	_summary = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_summary)
	content.add_child(HSeparator.new())
	_shelves.add_theme_constant_override("separation", 4)
	content.add_child(_shelves)
	content.add_child(HSeparator.new())
	content.add_child(UI.label("Wystaw z ekwipunku", UI.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_picker = OptionButton.new()
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.clip_text = true
	_picker.item_selected.connect(func(_i: int) -> void: _suggest_price())
	row.add_child(_picker)
	_quantity = _spin(1, 1000, 10)
	row.add_child(_quantity)
	content.add_child(row)
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 6)
	price_row.add_child(UI.label("Cena ($)"))
	_price = _spin(1, 10_000_000, 1)
	_price.step = 0.01
	_price.rounded = false
	_price.value_changed.connect(func(_v: float) -> void: _update_chance())
	price_row.add_child(_price)
	_chance = UI.label("", UI.MUTED)
	_chance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_row.add_child(_chance)
	price_row.add_child(UI.button("Wystaw", _stock, true))
	content.add_child(price_row)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(shop))
	pick_up.tooltip_text = "Towar z półek wróci do ekwipunku"
	content.add_child(pick_up)


func open_at(id: String) -> void:
	if id != shop:
		_state = {}
	shop = id
	show_window()
	refresh()
	_reload_items()


func refresh() -> void:
	if shop == "":
		return
	var reply := await fetch("shop.get", {"id": shop})
	_apply(reply)


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "shop":
		failed.emit(reply)
		return false
	var sold_before := int(_state.get("soldCents", -1))
	_state = reply["payload"]
	if sold_before >= 0 and int(_state["soldCents"]) != sold_before:
		balance_changed.emit()
	_render()
	return true


func _render() -> void:
	if _state.is_empty():
		return
	set_title("Sklep · %s" % _state["town"])
	var tax := int(_state["taxPercent"])
	_summary.text = "Około %s klientów na godzinę. Sprzedano %d szt. za %s.%s" % [str(_state["customersPerHour"]).replace(".", ","),
		int(_state["soldItems"]), UI.money(int(_state["soldCents"])), " Burmistrz bierze %d%% podatku." % tax if tax > 0 else ""]
	UI.clear(_shelves)
	if (_state["items"] as Array).is_empty():
		_shelves.add_child(UI.label("Półki są puste: wystaw towar, a klienci zaczną przychodzić.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for item: Dictionary in _state["items"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(item["id"], 28))
		var trader: Variant = item["traderCents"]
		var text := UI.label("%s: %d szt. po %s\nhandlarz płaci %s · kupuje %d%% klientów" % [item["name"], int(item["quantity"]),
			UI.money(int(item["priceCents"])), UI.money(int(trader)) if trader != null else "-", int(item["buyPercent"])])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(UI.button("Zdejmij", func() -> void: _take(item["id"], int(item["quantity"]))))
		_shelves.add_child(row)
	_fit.call_deferred()


func _reload_items() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		return
	_items = reply["payload"]["items"]
	if _trader.is_empty():
		var prices := await Net.request("market.prices")
		if prices["type"] == "market.prices":
			for p: Dictionary in prices["payload"]["items"]:
				if p.get("sellCents") != null:
					_trader[p["id"]] = int(p["sellCents"])
	var selected: String = _picker.get_item_metadata(_picker.selected) if _picker.selected >= 0 else ""
	_picker.clear()
	for stack: Dictionary in _items:
		_picker.add_item("%s (%d)" % [stack["name"], int(stack["quantity"])])
		_picker.set_item_metadata(_picker.item_count - 1, stack["id"])
		if stack["id"] == selected:
			_picker.select(_picker.item_count - 1)
	_suggest_price()


## Starts the price at what the trader pays, if the shop sells it already its price there.
func _suggest_price() -> void:
	if _picker.selected < 0:
		return
	var item: String = _picker.get_item_metadata(_picker.selected)
	for shelf: Dictionary in _state.get("items", []):
		if shelf["id"] == item:
			_price.value = int(shelf["priceCents"]) / 100.0
			return
	if _trader.has(item):
		_price.value = int(_trader[item]) / 100.0
	_update_chance()


## How many customers buy at the price set: all at the trader's price, half at twice that, none at three times.
func _update_chance() -> void:
	var item: String = _picker.get_item_metadata(_picker.selected) if _picker.selected >= 0 else ""
	if not _trader.has(item):
		_chance.text = "Nikt tego nie kupi" if item != "" else ""
		return
	var accepts := clampf(1.5 - _price.value * 100.0 / (2.0 * float(_trader[item])), 0.0, 1.0)
	_chance.text = "kupi %d%%" % roundi(accepts * 100.0)


func _stock() -> void:
	if _picker.selected < 0:
		return
	var item: String = _picker.get_item_metadata(_picker.selected)
	var reply := await Net.request("shop.stock", {"id": shop, "item": item, "quantity": int(_quantity.value),
		"priceCents": roundi(_price.value * 100.0)})
	if _apply(reply):
		inventory_changed.emit()
		_reload_items()


func _take(item: String, quantity: int) -> void:
	if _apply(await Net.request("shop.take", {"id": shop, "item": item, "quantity": quantity})):
		inventory_changed.emit()
		_reload_items()


func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size.x = 90
	spin.select_all_on_focus = true
	return spin
