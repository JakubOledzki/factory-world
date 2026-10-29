class_name GridTieWindow
extends GameWindow
## A grid tie: the end of a power cable to another plot. It stands next to a pole and joins the plot's
## network to the network of the plot at the cable's other end. A cable costs per tile it runs; between
## one owner's plots the power along it is free, from another player it flows only for the hours paid
## for at the price that player asks for a kWh. The owner of a tie sets that price and opens the tie.

signal balance_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 3000.0

var tie := ""
var plot := Vector2i(-1, -1)

var _state := {}
## The rows of the cables shown, by line id: {label, hours, buy}. Kept while the same cables are shown,
## so a poll does not reset the hours being typed in.
var _rows := {}

var _intro: Label
var _price: SpinBox
var _open: CheckBox
var _lines_box: VBoxContainer
var _none: Label
var _kw: SpinBox
var _offers_box: VBoxContainer
var _offers_note: Label


func _init() -> void:
	super("Przyłącze sieciowe", 460)
	poll_every = POLL
	_intro = UI.label("Postaw słup obok przyłącza, a kabel połączy sieć tej działki z siecią innej.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_intro)
	content.add_child(HSeparator.new())

	content.add_child(UI.label("Sprzedaż prądu", UI.GOLD))
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 6)
	price_row.add_child(UI.label("Cena za 1 kWh:"))
	_price = SpinBox.new()
	_price.min_value = 0
	_price.max_value = 1000
	_price.step = 0.01
	_price.suffix = "$"
	_price.custom_minimum_size.x = 120
	_price.select_all_on_focus = true
	price_row.add_child(_price)
	_open = CheckBox.new()
	_open.text = "sprzedawaj innym"
	_open.tooltip_text = "Inni gracze mogą poprowadzić kabel do tego przyłącza i kupować prąd po twojej cenie"
	price_row.add_child(_open)
	price_row.add_child(UI.button("Zapisz", _save_price))
	content.add_child(price_row)
	content.add_child(HSeparator.new())

	content.add_child(UI.label("Kable", UI.GOLD))
	_none = UI.label("Do tego przyłącza nie prowadzi jeszcze żaden kabel.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_none)
	_lines_box = VBoxContainer.new()
	_lines_box.add_theme_constant_override("separation", 6)
	content.add_child(_lines_box)
	content.add_child(HSeparator.new())

	content.add_child(UI.label("Nowy kabel do tej działki", UI.GOLD))
	var kw_row := HBoxContainer.new()
	kw_row.add_theme_constant_override("separation", 6)
	kw_row.add_child(UI.label("Moc kabla:"))
	_kw = SpinBox.new()
	_kw.min_value = 10
	_kw.max_value = 5000
	_kw.step = 10
	_kw.value = 100
	_kw.suffix = "kW"
	_kw.custom_minimum_size.x = 120
	_kw.select_all_on_focus = true
	kw_row.add_child(_kw)
	kw_row.add_child(UI.button("Szukaj przyłączy", _find_offers, true))
	content.add_child(kw_row)
	_offers_note = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_offers_note)
	_offers_box = VBoxContainer.new()
	_offers_box.add_theme_constant_override("separation", 4)
	content.add_child(_offers_box)

	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(tie))
	pick_up.tooltip_text = "Kable tego przyłącza zostaną zwinięte. Kabla, którym sprzedajesz opłacony prąd, nie zwiniesz, dopóki ten czas nie minie"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	if id != tie:
		_state = {}
		_clear_rows()
		UI.clear(_offers_box)
		_offers_note.text = ""
	plot = at
	tie = id
	show_window()
	refresh()


func refresh() -> void:
	if tie == "":
		return
	var reply := await fetch("powertie.get", {"x": plot.x, "y": plot.y, "id": tie})
	_apply(reply, false)


func _apply(reply: Dictionary, prices := true) -> void:
	if reply["type"] != "powertie":
		failed.emit(reply)
		return
	var first := _state.is_empty()
	_state = reply["payload"]
	if first or prices:
		_price.value = int(_state["priceCents"]) / 100.0
		_open.button_pressed = _state["open"]
	_kw.min_value = float(_state["minKw"])
	_kw.max_value = float(_state["maxKw"])
	if _state.get("balanceCents") != null:
		balance_changed.emit()
	_render()


func _render() -> void:
	var lines: Array = _state["lines"]
	var ids := lines.map(func(l: Dictionary) -> String: return str(l["id"]))
	ids.sort()
	var shown := _rows.keys()
	shown.sort()
	if ids != shown:
		_clear_rows()
		for line: Dictionary in lines:
			_add_row(line)
	_none.visible = lines.is_empty()
	for line: Dictionary in lines:
		_update_row(line)
	_fit.call_deferred()


func _clear_rows() -> void:
	UI.clear(_lines_box)
	_rows = {}


func _add_row(line: Dictionary) -> void:
	var id := str(line["id"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var label := UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var hours: SpinBox = null
	var buy: Button = null
	# Only the plot that gets the power pays for it, and only to another player.
	if not line["supplying"] and line["paidUntil"] != null:
		hours = SpinBox.new()
		hours.min_value = 1
		hours.max_value = float(_state["maxHours"])
		hours.value = 24
		hours.suffix = "h"
		hours.custom_minimum_size.x = 90
		hours.select_all_on_focus = true
		row.add_child(hours)
		buy = UI.button("Kup prąd", func() -> void: _buy(id, int(hours.value), int(_rows[id]["line"]["priceCents"])), true)
		row.add_child(buy)
		hours.value_changed.connect(func(_v: float) -> void: _update_buy(id))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var remove := UI.button("Zwiń kabel", func() -> void: _remove(id))
	remove.tooltip_text = "Kabel znika, a pieniądze za jego położenie i opłacony prąd przepadają. Sprzedawca nie zwinie kabla, póki prąd jest opłacony"
	row.add_child(remove)
	box.add_child(row)
	box.add_child(HSeparator.new())
	_lines_box.add_child(box)
	_rows[id] = {"label": label, "hours": hours, "buy": buy, "line": line}


func _update_row(line: Dictionary) -> void:
	var row: Dictionary = _rows[str(line["id"])]
	row["line"] = line
	var who := str(line["owner"]) if line["owner"] != null else "?"
	var where := "działka %d, %d (%s)" % [int(line["x"]), int(line["y"]), who]
	var kw := float(line["kw"])
	var flow := float(line["flowKw"])
	var text := ("Wysyła do: %s" if line["supplying"] else "Dostaje z: %s") % where
	text += "\nKabel %s kW, teraz płynie %s kW." % [_number(kw), _number(flow)]
	var label: Label = row["label"]
	if line["paidUntil"] == null:
		text += " Twoje działki: prąd za darmo."
		label.add_theme_color_override("font_color", UI.TEXT)
	else:
		var left := (float(line["paidUntil"]) - float(_state["serverTime"])) / 1000.0
		var price := "%s za kWh" % UI.money(int(line["priceCents"]))
		if left > 0.0:
			text += " Opłacone jeszcze na %s, %s." % [_duration(left), price]
			label.add_theme_color_override("font_color", UI.TEXT)
		else:
			text += " Nieopłacone: prąd nie płynie. Cena %s." % price
			label.add_theme_color_override("font_color", UI.TEXT if line["supplying"] else UI.ERROR)
	label.text = text
	_update_buy(str(line["id"]))


func _update_buy(id: String) -> void:
	var row: Dictionary = _rows.get(id, {})
	if row.is_empty() or row["buy"] == null:
		return
	var line: Dictionary = row["line"]
	var hours: SpinBox = row["hours"]
	var cents := ceili(float(line["kw"]) * hours.value * float(line["priceCents"]) - 0.000001)
	var buy: Button = row["buy"]
	buy.text = "Kup za %s" % UI.money(cents)
	buy.tooltip_text = "%s kW przez %d h po %s za kWh; pieniądze trafią do właściciela elektrowni" % [
		_number(float(line["kw"])), int(hours.value), UI.money(int(line["priceCents"]))]


func _save_price() -> void:
	var cents := roundi(_price.value * 100.0)
	var reply := await Net.request("powertie.price", {"x": plot.x, "y": plot.y, "id": tie, "priceCents": cents, "open": _open.button_pressed})
	_apply(reply)


func _find_offers() -> void:
	var reply := await Net.request("powertie.offers", {"x": plot.x, "y": plot.y, "id": tie})
	if reply["type"] != "powertie.offers":
		failed.emit(reply)
		return
	UI.clear(_offers_box)
	var offers: Array = reply["payload"]["offers"]
	_offers_note.text = "Nikt w pobliżu nie sprzedaje prądu, a na innych twoich działkach nie ma przyłączy (otwórz ich okno raz)." \
		if offers.is_empty() else "Kabel kosztuje %s za każde pole odległości. Płacisz raz, przy kładzeniu." % UI.money(int(_state.get("cableCentsPerTile", 0)))
	for offer: Dictionary in offers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mine: bool = offer["mine"]
		var what := "Działka %d, %d · %s" % [int(offer["x"]), int(offer["y"]), "twoja, prąd za darmo" if mine \
			else "%s, %s za kWh" % [str(offer["owner"]) if offer["owner"] != null else "?", UI.money(int(offer["priceCents"]))]]
		var label := UI.label(what, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var build := UI.button("Kabel za %s" % UI.money(int(offer["cableCents"])), _build.bind(offer))
		build.tooltip_text = "Położy kabel stamtąd do tej działki" + ("" if mine else "; prąd kupisz potem na godziny")
		row.add_child(build)
		_offers_box.add_child(row)
	_fit.call_deferred()


func _build(offer: Dictionary) -> void:
	var reply := await Net.request("powerline.build", {"x": plot.x, "y": plot.y, "id": tie,
		"fromX": int(offer["x"]), "fromY": int(offer["y"]), "fromId": offer["id"], "kw": _kw.value})
	_apply(reply, false)
	if reply["type"] == "powertie":
		UI.clear(_offers_box)
		_offers_note.text = ""


## Buys at the price the player saw: if the seller changed it meanwhile, the server refuses.
func _buy(id: String, hours: int, price_cents: int) -> void:
	var reply := await Net.request("powerline.buy", {"line": id, "hours": hours, "priceCents": price_cents})
	_apply(reply, false)
	if reply["type"] != "powertie":
		refresh()


func _remove(id: String) -> void:
	var reply := await Net.request("powerline.remove", {"x": plot.x, "y": plot.y, "id": tie, "line": id})
	_apply(reply, false)


func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0").replace(".", ",")


func _duration(seconds: float) -> String:
	var minutes := ceili(seconds / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	if minutes % 60 == 0:
		return "%d h" % (minutes / 60)
	return "%d h %d min" % [minutes / 60, minutes % 60]
