class_name StationWindow
extends GameWindow
## The railway station of a plot, in four tabs: the goods waiting in it (unloaded to the
## inventory, loaded from it), sending one train by hand, the routes whose trains leave by
## themselves every few minutes, and the trains on their way. A train goes to another plot of the
## player's or to another player's station, found by their name.

## Items went between the inventory and the station.
signal inventory_changed
## The player paid for a train.
signal balance_changed
signal failed(reply: Dictionary)
signal toast(text: String)

const TABS := ["Magazyn", "Wyślij", "Rozkład jazdy", "W drodze"]
const PROBLEMS := {
	"empty": "Czeka na towar: na stacji nie było nic do zabrania.",
	"no_money": "Stoi: brakuje pieniędzy na opłatę.",
	"no_station": "Stoi: działka docelowa nie ma już właściciela.",
}

var plot := Vector2i(-1, -1)
var world_width := 6933
var my_plots: Array[Vector2i] = []
var items: Array = []
var balance := 0
## A port stands on this plot: goods can go by ship to another plot with a port, slower but for a quarter of the fee.
var port := false
var _by_sea := false
## A dog kennel or a snowmobile garage stands on this plot on the glacier or the tundra: goods can go by sled, free, up to sledMaxKm.
var sled := false
## A stable stands on this plot off the glacier and the tundra: a horse cart takes goods up to horseMaxKm, free, on concentrate feed
## from the station. It goes as a sled does ("sled" when sending).
var horse := false
var _by_sled := false

var _state := {}
var _clock_offset := 0.0
var _tab := 0
var _tab_buttons: Array[Button] = []
var _body := VBoxContainer.new()
var _trip_labels: Array = []
var _route_labels: Array = []
var _next_poll := 0.0
var _refreshing := false

## Where trains go: a plot of the player's, one of a player found by name, or typed in by hand.
var _found: Array = []
var _destination := Vector2i(-1, -1)
var _destination_name := ""
var _search := LineEdit.new()

var _send_x: SpinBox
var _send_y: SpinBox
var _send_item: OptionButton
var _send_quantity: SpinBox
var _send_info: Label
var _send_button: Button

## The route being set up: chosen items (none for everything) and minutes between trains.
var _route_items: Array[String] = []
var _route_minutes := 5


func _init() -> void:
	super("Stacja kolejowa", 470)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _open_tab.bind(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(b)
		_tab_buttons.append(b)
	content.add_child(top)
	content.add_child(HSeparator.new())
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_body)
	_search.placeholder_text = "Nazwa gracza"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t: String) -> void: _find())


func open_at(at: Vector2i) -> void:
	if at != plot:
		_state = {}
		_destination = Vector2i(-1, -1)
	plot = at
	show_window()
	refresh()


func set_player(inventory: Array, cents: int) -> void:
	items = inventory
	balance = cents
	if visible and not _state.is_empty() and _tab in [0, 1, 2]:
		_render()


## The station as the server sees it now; the plot screen also asks it to draw trains.
func state() -> Dictionary:
	return _state


func server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func refresh() -> void:
	if plot.x < 0 or _refreshing:
		return
	_refreshing = true
	_next_poll = Time.get_ticks_msec() + 5000.0
	var reply := await Net.request("station.get", {"x": plot.x, "y": plot.y})
	_refreshing = false
	apply(reply)


func apply(reply: Dictionary) -> void:
	if reply["type"] != "station":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	var tab_names := TABS.duplicate()
	var trips: int = _state["incoming"].size() + _state["outgoing"].size()
	if trips > 0:
		tab_names[3] = "W drodze (%d)" % trips
	if not _state["routes"].is_empty():
		tab_names[2] = "Rozkład (%d)" % _state["routes"].size()
	for i in TABS.size():
		_tab_buttons[i].text = tab_names[i]
	if visible:
		# Typing in a field is not interrupted by the countdowns being drawn anew.
		if _tab == 3 or (_tab == 0 and not _editing()):
			_render()
		elif _body.get_child_count() == 0:
			_render()
		_update_times()


func _editing() -> bool:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return focus != null and is_ancestor_of(focus)


func _process(_delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_update_times()
	var now := server_now()
	var due := Time.get_ticks_msec() >= _next_poll
	for trip: Dictionary in _state.get("incoming", []):
		due = due or float(trip["arrivesAt"]) <= now
	for route: Dictionary in _state.get("routes", []):
		due = due or float(route["nextAt"]) <= now
	if due and Time.get_ticks_msec() >= _next_poll - 3500.0:
		refresh()


func _open_tab(tab: int) -> void:
	_tab = tab
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == tab else ""
	_render()


func show_window() -> void:
	super()
	_open_tab(_tab)


func _render() -> void:
	# The player search field lives on between redraws, so what was typed stays.
	if _search.get_parent() != null:
		_search.get_parent().remove_child(_search)
	for child in _body.get_children():
		child.free()
	_trip_labels.clear()
	_route_labels.clear()
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == _tab else ""
	if _state.is_empty():
		_body.add_child(UI.label("Wczytywanie…", UI.MUTED))
		return
	match _tab:
		0: _render_stock()
		1: _render_send()
		2: _render_routes()
		3: _render_trips()


# --- Stock ---------------------------------------------------------------------------------------

func _render_stock() -> void:
	_section("Magazyn stacji")
	var stock: Array = _state["items"]
	if stock.is_empty():
		_body.add_child(UI.label("Pusto. Załaduj towary z ekwipunku poniżej.", UI.MUTED))
	for stack: Dictionary in stock:
		var row := _item_row(stack["id"], stack["name"], "× %d" % int(stack["quantity"]))
		row.add_child(UI.button("Do ekwipunku", _stock_action.bind("station.unload", stack["id"], int(stack["quantity"]))))
		_body.add_child(row)

	_body.add_child(HSeparator.new())
	_section("Załaduj z ekwipunku")
	var loadable := 0
	for stack: Dictionary in items:
		var item: String = stack["id"]
		if item.begins_with("furniture_"):
			continue
		loadable += 1
		var quantity := int(stack["quantity"])
		var row := _item_row(item, stack["name"], "masz %d" % quantity)
		if quantity > 10:
			row.add_child(UI.button("10", _stock_action.bind("station.load", item, 10)))
		row.add_child(UI.button("Wszystko", _stock_action.bind("station.load", item, quantity)))
		_body.add_child(row)
	if loadable == 0:
		_body.add_child(UI.label("Ekwipunek jest pusty.", UI.MUTED))
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label(
		"Podajnik stojący przodem do toru przed stacją ładuje na nią towary, a stojący tyłem do toru je zdejmuje.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


func _stock_action(type: String, item: String, quantity: int) -> void:
	var reply := await Net.request(type, {"x": plot.x, "y": plot.y, "item": item, "quantity": quantity})
	if reply["type"] != "station":
		failed.emit(reply)
		return
	apply(reply)
	_render()
	inventory_changed.emit()


# --- Destination -----------------------------------------------------------------------------------

## The choice of where trains go, shared by sending by hand and by routes.
func _destination_picker() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)

	grid.add_child(UI.label("Dokąd", UI.MUTED))
	var to := OptionButton.new()
	to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to.clip_text = true
	var choices: Array = []
	for p in my_plots:
		if p != plot:
			choices.append([p, "", "Moja działka %d × %d" % [p.x, p.y]])
	for player: Dictionary in _found:
		for p: Dictionary in player["plots"]:
			choices.append([Vector2i(p["x"], p["y"]), player["name"], "%s · działka %d × %d" % [player["name"], p["x"], p["y"]]])
	choices.append([null, "", "Inna działka (podaj X i Y)"])
	var selected := choices.size() - 1
	for i in choices.size():
		to.add_item(choices[i][2])
		to.set_item_metadata(i, choices[i])
		if choices[i][0] == _destination and _destination.x >= 0:
			selected = i
	if _destination.x < 0 and choices.size() > 1:
		selected = 0
	to.select(selected)
	grid.add_child(to)

	grid.add_child(UI.label("Gracz", UI.MUTED))
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 4)
	search_row.add_child(_search)
	search_row.add_child(UI.button("Szukaj", _find))
	grid.add_child(search_row)

	grid.add_child(UI.label("X, Y", UI.MUTED))
	var xy := HBoxContainer.new()
	_send_x = SpinBox.new()
	_send_x.max_value = world_width - 1
	_send_y = SpinBox.new()
	_send_y.max_value = 3000
	for spin: SpinBox in [_send_x, _send_y]:
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xy.add_child(spin)
	grid.add_child(xy)

	var chose := func(index: int) -> void:
		var choice: Array = to.get_item_metadata(index)
		var manual: bool = choice[0] == null
		_send_x.editable = manual
		_send_y.editable = manual
		if manual:
			if _destination.x < 0:
				_destination = plot
			_destination_name = ""
		else:
			_destination = choice[0]
			_destination_name = choice[1]
		_send_x.set_value_no_signal(_destination.x)
		_send_y.set_value_no_signal(_destination.y)
		_update_costs()
	to.item_selected.connect(chose)
	for spin: SpinBox in [_send_x, _send_y]:
		spin.value_changed.connect(func(_v: float) -> void:
			_destination = Vector2i(int(_send_x.value), int(_send_y.value))
			_destination_name = ""
			_update_costs())
	chose.call(selected)


func _find() -> void:
	var query := _search.text.strip_edges()
	if query.length() < 2:
		toast.emit("Wpisz co najmniej 2 litery nazwy gracza.")
		return
	var reply := await Net.request("station.find", {"query": query})
	if reply["type"] != "station.found":
		failed.emit(reply)
		return
	_found = reply["payload"]["players"]
	if _found.is_empty():
		toast.emit("Nie ma gracza z działką o nazwie zaczynającej się od „%s”." % query)
		return
	var first: Dictionary = _found[0]["plots"][0]
	_destination = Vector2i(first["x"], first["y"])
	_render()


func _km_to(target: Vector2i) -> float:
	var dx := absi(target.x - plot.x)
	dx = mini(dx, world_width - dx)
	return sqrt(float(dx * dx + (target.y - plot.y) * (target.y - plot.y))) * 5.0


## Fee and time of a trip, as the server counts them (see RailRules).
func _trip(quantity: int) -> Dictionary:
	var rates: Dictionary = _state["rates"]
	var km := _km_to(_destination)
	return {
		"km": km,
		"seconds": maxf(rates["minTripSeconds"], km / 100.0 * rates["secondsPer100Km"]),
		# Cheaper from a city plot, with a freight terminal or with the mayor's rail bonus.
		"fee": ceili((int(rates["baseFeeCents"]) + ceili(km / 100.0 * quantity * float(rates["centsPerItemPer100Km"])))
			* float(rates.get("feeFactor", 1.0))),
	}


func _update_costs() -> void:
	if _tab == 1 and _send_info != null and is_instance_valid(_send_info):
		_update_send()
	elif _tab == 2 and _send_info != null and is_instance_valid(_send_info):
		_update_route_info()


# --- Sending by hand ----------------------------------------------------------------------------------

func _render_send() -> void:
	_section("Wyślij pociąg")
	var stock: Array = _state["items"]
	if stock.is_empty():
		_body.add_child(UI.label("Najpierw załaduj coś na stację (zakładka Magazyn).", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		_send_info = null
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	grid.add_child(UI.label("Towar", UI.MUTED))
	_send_item = OptionButton.new()
	_send_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for stack: Dictionary in stock:
		_send_item.add_icon_item(UI.item_texture(stack["id"]), "%s (%d)" % [stack["name"], int(stack["quantity"])])
		_send_item.set_item_metadata(_send_item.item_count - 1, stack)
	_send_item.add_theme_constant_override("icon_max_width", 22)
	_send_item.item_selected.connect(func(_i: int) -> void:
		_send_quantity.max_value = _send_stack()["quantity"]
		_send_quantity.value = _send_quantity.max_value
		_update_send())
	grid.add_child(_send_item)
	grid.add_child(UI.label("Ilość", UI.MUTED))
	_send_quantity = SpinBox.new()
	_send_quantity.min_value = 1
	_send_quantity.max_value = stock[0]["quantity"]
	_send_quantity.value = stock[0]["quantity"]
	_send_quantity.value_changed.connect(func(_v: float) -> void: _update_send())
	grid.add_child(_send_quantity)

	_send_info = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	_send_button = UI.button("Wyślij statkiem" if _by_sea and port else "Wyślij pociąg", _send, true)
	_destination_picker()
	if port:
		grid.add_child(UI.label("Czym", UI.MUTED))
		var sea := CheckBox.new()
		sea.text = "Statkiem z portu (dwa razy wolniej, za ćwierć ceny)"
		sea.button_pressed = _by_sea
		sea.toggled.connect(func(on: bool) -> void:
			_by_sea = on
			_send_button.text = "Wyślij statkiem" if on else "Wyślij pociąg"
			_update_send())
		grid.add_child(sea)
	if sled:
		grid.add_child(UI.label("Saniami", UI.MUTED))
		var by_sled := CheckBox.new()
		by_sled.text = "Psim zaprzęgiem lub skuterem (bez opłaty, do %d km)" % int(_state["rates"].get("sledMaxKm", 150))
		by_sled.button_pressed = _by_sled
		by_sled.toggled.connect(func(on: bool) -> void:
			_by_sled = on
			_send_button.text = _send_text()
			_update_send())
		grid.add_child(by_sled)
	elif horse:
		grid.add_child(UI.label("Wozem", UI.MUTED))
		var by_cart := CheckBox.new()
		by_cart.text = "Wozem konnym ze stajni (bez opłaty, do %d km, za paszę treściwą)" % int(_state["rates"].get("horseMaxKm", 50))
		by_cart.button_pressed = _by_sled
		by_cart.toggled.connect(func(on: bool) -> void:
			_by_sled = on
			_send_button.text = _send_text()
			_update_send())
		grid.add_child(by_cart)
	_send_button.text = _send_text()
	_body.add_child(grid)
	_body.add_child(_send_info)
	_body.add_child(_send_button)
	_update_send()


## Diesel a train to `km` away burns, as DieselRules counts it, when the station has enough of it
## besides what is being sent; 0 when it goes by steam.
func _diesel_for(km: float, sending: Dictionary, quantity: int) -> int:
	var per_unit := float(_state["rates"].get("dieselKmPerUnit", 0))
	if per_unit <= 0.0:
		return 0
	var need := maxi(1, ceili(km / per_unit))
	for stack: Dictionary in _state["items"]:
		if stack["id"] == "diesel":
			var spare := int(stack["quantity"]) - (quantity if sending.get("id", "") == "diesel" else 0)
			return need if spare >= need else 0
	return 0


func _send_text() -> String:
	if sled and _by_sled:
		return "Wyślij saniami"
	if horse and _by_sled:
		return "Wyślij wozem"
	return "Wyślij statkiem" if _by_sea and port else "Wyślij pociąg"


## Petrol in the station besides what is being sent, for a snowmobile.
func _petrol_spare(sending: Dictionary, quantity: int) -> int:
	for stack: Dictionary in _state["items"]:
		if stack["id"] == "gasoline":
			return int(stack["quantity"]) - (quantity if sending.get("id", "") == "gasoline" else 0)
	return 0


func _send_stack() -> Dictionary:
	return _send_item.get_item_metadata(_send_item.selected)


func _update_send() -> void:
	var quantity := int(_send_quantity.value)
	var trip := _trip(quantity)
	if _by_sea and port:
		# As SeaRules counts it; a lighthouse by either port makes the trip shorter, which shows on arrival.
		trip["fee"] = (int(trip["fee"]) + 3) / 4
		trip["seconds"] = float(trip["seconds"]) * 2.0
	var diesel := 0 if _by_sea and port else _diesel_for(float(trip["km"]), _send_stack(), quantity)
	if diesel > 0:
		trip["seconds"] = float(trip["seconds"]) * float(_state["rates"].get("dieselTripFactor", 1.0))
	_send_info.text = "%s  ·  %s km  ·  w drodze %s  ·  opłata %s" % [
		_where(), _grouped(roundi(trip["km"])), _clock(trip["seconds"]), UI.money(trip["fee"])]
	if diesel > 0:
		_send_info.text += "\nPociąg spalinowy: spali %d × olej napędowy ze stacji i dojedzie szybciej." % diesel
	elif not (_by_sea and port) and _state["rates"].has("dieselKmPerUnit"):
		_send_info.text += "\nZaładuj na stację olej napędowy, a pojedzie szybszy pociąg spalinowy."
	if horse and _by_sled:
		var rates: Dictionary = _state["rates"]
		var km := float(trip["km"])
		var feed := maxi(1, ceili(km / float(rates.get("horseKmPerFeed", 10))))
		var max_km := float(rates.get("horseMaxKm", 50))
		_send_info.text = "%s  ·  %s km  ·  w drodze %s  ·  bez opłaty" % [_where(), _grouped(roundi(km)),
			_clock(float(trip["seconds"]) * float(rates.get("horseTrip", 2)))]
		_send_info.text += "\nKonie zjedzą %d × pasza treściwa ze stacji." % feed
		_send_button.disabled = _destination == plot or km > max_km
		if km > max_km:
			_send_info.text += "\nZa daleko: wóz konny jedzie najwyżej %d km." % int(max_km)
		elif _destination == plot:
			_send_info.text += "\nTo jest ta sama stacja."
		return
	if sled and _by_sled:
		var rates: Dictionary = _state["rates"]
		var km := float(trip["km"])
		var petrol := maxi(1, ceili(km / float(rates.get("sledKmPerPetrol", 50))))
		var snowmobile := _petrol_spare(_send_stack(), quantity) >= petrol
		var factor := float(rates.get("sledSnowmobileTrip", 0.8)) if snowmobile else float(rates.get("sledDogTrip", 1.5))
		_send_info.text = "%s  ·  %s km  ·  w drodze %s  ·  bez opłaty" % [_where(), _grouped(roundi(km)), _clock(float(trip["seconds"]) * factor)]
		_send_info.text += "\nSkuter spali %d × benzyna ze stacji (jeśli stoi garaż), inaczej pojadą psy." % petrol if snowmobile \
			else "\nPojadą psy (jeśli stoi psiarnia). Z benzyną na stacji i garażem pojedzie szybszy skuter."
		_send_button.disabled = _destination == plot or km > float(rates.get("sledMaxKm", 150))
		if km > float(rates.get("sledMaxKm", 150)):
			_send_info.text += "\nZa daleko: sanie jadą najwyżej %d km." % int(rates.get("sledMaxKm", 150))
		elif _destination == plot:
			_send_info.text += "\nTo jest ta sama stacja."
		return
	_send_button.disabled = _destination == plot or trip["fee"] > balance
	if trip["fee"] > balance:
		_send_info.text += "\nNie masz tyle pieniędzy."
	elif _destination == plot:
		_send_info.text += "\nTo jest ta sama stacja."


func _send() -> void:
	var target := _destination
	var stack := _send_stack()
	var quantity := int(_send_quantity.value)
	_send_button.disabled = true
	var reply := await Net.request("station.send", {
		"x": plot.x, "y": plot.y, "toX": target.x, "toY": target.y, "item": stack["id"], "quantity": quantity,
		"sea": _by_sea and port, "sled": (sled or horse) and _by_sled,
	})
	if reply["type"] != "station":
		failed.emit(reply)
		_send_button.disabled = false
		return
	if sled and _by_sled:
		toast.emit("Sanie z %d × %s ruszyły: %s." % [quantity, stack["name"], _where()])
	elif horse and _by_sled:
		toast.emit("Wóz konny z %d × %s ruszył: %s." % [quantity, stack["name"], _where()])
	else:
		toast.emit("%s z %d × %s %s: %s." % ["Statek" if _by_sea and port else "Pociąg", quantity, stack["name"],
			"wypłynął" if _by_sea and port else "odjechał", _where()])
	apply(reply)
	_render()
	balance_changed.emit()


# --- Routes ---------------------------------------------------------------------------------------------

func _render_routes() -> void:
	var routes: Array = _state["routes"]
	var rates: Dictionary = _state["rates"]
	_section("Kursy z tej stacji")
	if routes.is_empty():
		_body.add_child(UI.label("Brak kursów. Kurs to pociąg, który sam odjeżdża co kilka minut i zabiera to, co czeka na stacji.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for route: Dictionary in routes:
		_route_row(route)

	_body.add_child(HSeparator.new())
	_section("Nowy kurs")
	if routes.size() >= int(rates["maxRoutes"]):
		_body.add_child(UI.label("Ze stacji może odjeżdżać najwyżej %d kursów." % int(rates["maxRoutes"]), UI.MUTED))
		_send_info = null
		return
	_destination_picker()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	grid.add_child(UI.label("Co ile", UI.MUTED))
	var every := OptionButton.new()
	for minutes in rates["routeMinutes"]:
		every.add_item("co %d min" % int(minutes) if int(minutes) < 60 else "co godzinę")
		every.set_item_metadata(every.item_count - 1, int(minutes))
		if int(minutes) == _route_minutes:
			every.select(every.item_count - 1)
	every.item_selected.connect(func(i: int) -> void: _route_minutes = every.get_item_metadata(i))
	grid.add_child(every)

	_body.add_child(UI.label("Co wozić (nic nie zaznaczone: wszystko ze stacji)", UI.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	var known := {}
	for stack: Dictionary in _state["items"] + items:
		if not stack["id"].begins_with("furniture_"):
			known[stack["id"]] = stack["name"]
	for item: String in _route_items:
		if not known.has(item):
			known[item] = item
	if known.is_empty():
		flow.add_child(UI.label("Towary ze stacji i z ekwipunku pojawią się tutaj.", UI.MUTED))
	for item: String in known:
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = item in _route_items
		b.icon = UI.item_texture(item)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 22)
		b.text = known[item]
		b.tooltip_text = known[item]
		b.toggled.connect(func(on: bool) -> void:
			if on and item not in _route_items:
				if _route_items.size() >= int(rates["maxRouteItems"]):
					b.set_pressed_no_signal(false)
					toast.emit("Kurs może wozić najwyżej %d rodzajów towaru." % int(rates["maxRouteItems"]))
					return
				_route_items.append(item)
			elif not on:
				_route_items.erase(item))
		flow.add_child(b)
	_body.add_child(flow)

	_send_info = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	_body.add_child(_send_info)
	_send_button = UI.button("Uruchom kurs", _add_route, true)
	_body.add_child(_send_button)
	_update_route_info()


func _route_row(route: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var to := Vector2i(route["toX"], route["toY"])
	var receiver: Variant = route["receiver"]
	var title := UI.label("→ %s" % ("%s · %d × %d" % [receiver, to.x, to.y] if receiver != null else "moja działka %d × %d" % [to.x, to.y]))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(Online.with_dot(title, receiver))
	var minutes := int(route["everyMinutes"])
	top.add_child(UI.label("co %d min" % minutes if minutes < 60 else "co godzinę", UI.GOLD))
	top.add_child(UI.button("Usuń", _remove_route.bind(int(route["id"]))))
	box.add_child(top)

	var cargo := HBoxContainer.new()
	cargo.add_theme_constant_override("separation", 4)
	if route["items"].is_empty():
		cargo.add_child(UI.label("wozi wszystko ze stacji", UI.MUTED))
	for item: Dictionary in route["items"]:
		var icon := UI.item_icon(item["id"], 20)
		icon.tooltip_text = item["name"]
		cargo.add_child(icon)
	var status := UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cargo.add_child(status)
	box.add_child(cargo)
	var problem: Variant = route["problem"]
	if problem != null:
		box.add_child(UI.label(PROBLEMS.get(problem, problem), UI.ERROR if problem != "empty" else UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	elif route["lastAt"] != null:
		box.add_child(UI.label("Ostatni pociąg zabrał %d szt." % int(route["lastQuantity"]), UI.GOOD))
	_body.add_child(box)
	_route_labels.append([status, float(route["nextAt"])])


func _update_route_info() -> void:
	var rates: Dictionary = _state["rates"]
	var capacity := int(rates["routeCapacity"])
	var trip := _trip(capacity)
	_send_info.text = "%s  ·  %s km  ·  w drodze %s\nPociąg zabiera do %s sztuk. Pełny kosztuje %s, mniejszy mniej; pusty nie odjeżdża i nic nie kosztuje." % [
		_where(), _grouped(roundi(trip["km"])), _clock(trip["seconds"]), _grouped(capacity), UI.money(trip["fee"])]
	_send_button.disabled = _destination == plot
	if _destination == plot:
		_send_info.text += "\nTo jest ta sama stacja."


func _add_route() -> void:
	_send_button.disabled = true
	var reply := await Net.request("station.route", {
		"x": plot.x, "y": plot.y, "toX": _destination.x, "toY": _destination.y,
		"items": _route_items, "everyMinutes": _route_minutes,
	})
	if reply["type"] != "station":
		failed.emit(reply)
		_send_button.disabled = false
		return
	toast.emit("Kurs uruchomiony: pociąg do %s co %d min." % [_where(), _route_minutes])
	_route_items.clear()
	apply(reply)
	_render()
	balance_changed.emit()


func _remove_route(id: int) -> void:
	var reply := await Net.request("station.unroute", {"x": plot.x, "y": plot.y, "id": id})
	if reply["type"] != "station":
		failed.emit(reply)
		return
	apply(reply)
	_render()


# --- Trains on their way -----------------------------------------------------------------------------

func _render_trips() -> void:
	var incoming: Array = _state["incoming"]
	var outgoing: Array = _state["outgoing"]
	_section("Przyjeżdżają")
	if incoming.is_empty():
		_body.add_child(UI.label("Nic nie jedzie na tę stację.", UI.MUTED))
	for trip: Dictionary in incoming:
		var sender: Variant = trip["sender"]
		_trip_row(trip, "z %s%d × %d" % ["%s · " % sender if sender != null else "", int(trip["fromX"]), int(trip["fromY"])])
	_body.add_child(HSeparator.new())
	_section("Odjechały")
	if outgoing.is_empty():
		_body.add_child(UI.label("Żaden pociąg stąd nie jest w drodze.", UI.MUTED))
	for trip: Dictionary in outgoing:
		var receiver: Variant = trip["receiver"]
		_trip_row(trip, "do %s%d × %d" % ["%s · " % receiver if receiver != null else "", int(trip["toX"]), int(trip["toY"])])


func _trip_row(trip: Dictionary, route: String) -> void:
	var row := _item_row(trip["item"], "%d × %s  %s" % [int(trip["quantity"]), trip["name"], route], "")
	var left: Label = row.get_child(2)
	left.custom_minimum_size.x = 64
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body.add_child(row)
	_trip_labels.append([left, float(trip["arrivesAt"])])


func _update_times() -> void:
	var now := server_now()
	for entry: Array in _trip_labels:
		var label: Label = entry[0]
		if is_instance_valid(label):
			var seconds := ceili(maxf(entry[1] - now, 0.0) / 1000.0)
			label.text = _clock(seconds) if seconds > 0 else "dojechał"
	for entry: Array in _route_labels:
		var label: Label = entry[0]
		if is_instance_valid(label):
			var seconds := ceili(maxf(entry[1] - now, 0.0) / 1000.0)
			label.text = "następny za %s" % _clock(seconds) if seconds > 0 else "odjeżdża…"


# --- Helpers ---------------------------------------------------------------------------------------------

func _where() -> String:
	if _destination_name != "":
		return "%s, działka %d × %d" % [_destination_name, _destination.x, _destination.y]
	if _destination in my_plots:
		return "moja działka %d × %d" % [_destination.x, _destination.y]
	return "działka %d × %d" % [_destination.x, _destination.y]


func _section(text: String) -> void:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	_body.add_child(l)


func _item_row(item: String, name: String, quantity_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var name_label := UI.label(name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(UI.label(quantity_text, UI.MUTED))
	return row


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


static func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += " "
		out += text[i]
	return out
