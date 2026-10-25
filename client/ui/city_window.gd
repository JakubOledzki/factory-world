class_name CityWindow
extends GameWindow
## The town a city plot belongs to: what it wants today and pays better than the trader for, how it grows from a
## village to a metropolis on what players deliver, the rubbish it pays to have taken away, the services of the
## players' offices, and the town hall, where the townsfolk elect a mayor who sets a tax and one bonus a week.

signal inventory_changed
signal balance_changed
signal failed(reply: Dictionary)
signal toast(text: String)

const TABS := ["Potrzeby", "Rozwój", "Wysypisko", "Usługi", "Ratusz"]

var plot := Vector2i(-1, -1)

var _state := {}
var _tab := 0
var _tab_buttons: Array[Button] = []
var _header: Label
var _body := VBoxContainer.new()


func _init() -> void:
	super("Miasto", 520)
	_header = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _show_tab.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons.append(b)
	content.add_child(tabs)
	content.add_child(HSeparator.new())
	_body.add_theme_constant_override("separation", 6)
	content.add_child(_body)


func open_at(at: Vector2i) -> void:
	if at != plot:
		_state = {}
	plot = at
	show_window()
	refresh()


func refresh() -> void:
	_apply(await Net.request("city.get", {"x": plot.x, "y": plot.y}))


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "city":
		failed.emit(reply)
		return false
	_state = reply["payload"]["state"]
	_render()
	return true


func _show_tab(i: int) -> void:
	_tab = i
	_render()


func _render() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	UI.clear(_body)
	if _state.is_empty():
		return
	var town: Dictionary = _state["town"]
	set_title(town["name"])
	var distance := float(town["distance"])
	_header.text = "%s · %s · %s mieszkańców · %s" % [town["name"], town["levelName"], _thousands(int(town["population"])),
		"w samym centrum" if distance < 0.5 else "%s działki od centrum (im bliżej, tym więcej klientów)" % str(snappedf(distance, 0.1)).replace(".", ",")]
	match _tab:
		0: _render_needs()
		1: _render_growth()
		2: _render_trash()
		3: _render_services()
		4: _render_hall()
	_fit.call_deferred()


func _render_needs() -> void:
	_body.add_child(UI.label("Dziś miasto kupi to, czego potrzebuje, drożej niż handlarz. Jutro zechce czego innego (zostało %s)." \
		% _left(int(_state["dayEndsAt"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for need: Dictionary in _state["needs"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(need["id"], 30))
		var wanted := int(need["wanted"])
		var delivered := int(need["delivered"])
		var text := UI.label("%s\n%d / %d · %s za sztukę" % [need["name"], delivered, wanted, UI.money(int(need["priceCents"]))])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var left := wanted - delivered
		var spin := _spin(1, maxi(left, 1), maxi(left, 1))
		spin.editable = left > 0
		row.add_child(spin)
		var own := UI.button("Z ekwipunku", func() -> void: _deliver(need["id"], int(spin.value), false), true)
		own.disabled = left <= 0
		row.add_child(own)
		var station := UI.button("Ze stacji", func() -> void: _deliver(need["id"], int(spin.value), true))
		station.tooltip_text = "Prosto ze stacji kolejowej tej działki"
		station.disabled = left <= 0
		row.add_child(station)
		_body.add_child(row)


func _render_growth() -> void:
	var town: Dictionary = _state["town"]
	var level := int(town["level"])
	var names: Array = town["levelNames"]
	var cents: Array = town["levelCents"]
	var delivered := int(town["deliveredCents"])
	_body.add_child(UI.label("Miasto rośnie na wszystkim, co gracze mu dostarczą. Większe chce więcej i droższych rzeczy, płaci więcej, " +
		"ma więcej śmieci i klientów w sklepach.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if level + 1 < cents.size():
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 12
		bar.min_value = int(cents[level])
		bar.max_value = int(cents[level + 1])
		bar.value = delivered
		_body.add_child(UI.label("%s → %s: %s / %s" % [names[level], names[level + 1], UI.money(delivered), UI.money(int(cents[level + 1]))]))
		_body.add_child(bar)
	else:
		_body.add_child(UI.label("%s: największe, jakie może być. Dostarczono %s." % [names[level], UI.money(delivered)], UI.GOLD))
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label("Najwięcej dostarczyli", UI.GOLD))
	if (_state["contributors"] as Array).is_empty():
		_body.add_child(UI.label("Jeszcze nikt.", UI.MUTED))
	for c: Dictionary in _state["contributors"]:
		_body.add_child(UI.label("%s%s: %s" % [c["name"], " (ty)" if c["mine"] else "", UI.money(int(c["cents"]))],
			UI.GOLD if c["mine"] else UI.TEXT))
	_body.add_child(UI.label("Twój wkład: %s" % UI.money(int(_state["myCents"])), UI.MUTED))


func _render_trash() -> void:
	var trash: Dictionary = _state["trash"]
	var left := int(trash["perDay"]) - int(trash["taken"])
	_body.add_child(UI.label(("Miasto płaci %s za każdy wywieziony śmieć. Śmieci trafiają na stację działki: posortuj je w sortowni " +
		"miejskiej albo w recyklingu.") % UI.money(int(trash["feeCents"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(UI.label("Dziś do wywiezienia: %d z %d" % [left, int(trash["perDay"])]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon("trash", 30))
	var spin := _spin(1, maxi(left, 1), maxi(left, 1))
	spin.editable = left > 0
	row.add_child(spin)
	var take := UI.button("Wywieź na stację", func() -> void: _take_trash(int(spin.value)), true)
	take.disabled = left <= 0
	row.add_child(take)
	_body.add_child(row)


func _render_services() -> void:
	_body.add_child(UI.label("Biura graczy z tego miasta sprzedają swoje usługi. Właściciel dostaje zapłatę, burmistrz podatek.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if (_state["services"] as Array).is_empty():
		_body.add_child(UI.label("Nikt w mieście nie ma jeszcze biura projektowego, laboratorium ani warsztatu serwisowego.", UI.MUTED,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	for s: Dictionary in _state["services"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(s["item"], 30))
		var text := UI.label("%s (%s)\n%d× %s za %s · dziś jeszcze %d" % [s["name"], s["owner"], int(s["quantity"]), s["itemName"],
			UI.money(int(s["priceCents"])), int(s["left"])])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var buy := UI.button("Twoje" if s["own"] else "Kup", func() -> void: _buy_service(s["id"]), true)
		buy.disabled = s["own"] or int(s["left"]) <= 0
		row.add_child(buy)
		_body.add_child(row)


func _render_hall() -> void:
	var hall: Dictionary = _state["hall"]
	var mayor: Variant = hall["mayor"]
	_body.add_child(UI.label("Burmistrz tego tygodnia: %s" % (mayor if mayor != null else "brak (nikt nie głosował)"), UI.GOLD))
	var bonus_name := "żaden"
	for b: Dictionary in hall["bonuses"]:
		if b["id"] == hall["bonus"]:
			bonus_name = b["name"]
	_body.add_child(UI.label("Podatek od sklepów i usług: %d%% · Premia: %s" % [int(hall["taxPercent"]), bonus_name], UI.TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if hall["isMayor"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("Podatek %"))
		var tax := _spin(0, int(hall["maxTaxPercent"]), int(hall["taxPercent"]))
		row.add_child(tax)
		var pick := OptionButton.new()
		pick.add_item("Bez premii")
		pick.set_item_metadata(0, "")
		for b: Dictionary in hall["bonuses"]:
			pick.add_item(b["name"])
			pick.set_item_metadata(pick.item_count - 1, b["id"])
			if b["id"] == hall["bonus"]:
				pick.select(pick.item_count - 1)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		row.add_child(pick)
		row.add_child(UI.button("Ustaw", func() -> void: _set_policy(int(tax.value), pick.get_item_metadata(pick.selected)), true))
		_body.add_child(row)
	# A festival with fine dishes from the mayor's inventory: the town pays more for what it wants for a day.
	var festival: Variant = hall.get("festivalUntil")
	if festival != null:
		_body.add_child(UI.label("Trwa festyn: miasto płaci o %d%% więcej jeszcze %s." % [int(hall["festivalPercent"]), _left(int(festival))],
			UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
	elif hall["isMayor"]:
		var feast := HBoxContainer.new()
		feast.add_theme_constant_override("separation", 6)
		var note := UI.label("Festyn: %d × pieczeń lub sernik z ekwipunku, a przez %d h miasto płaci o %d%% więcej." % [
			int(hall["festivalDishes"]), int(hall["festivalHours"]), int(hall["festivalPercent"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feast.add_child(note)
		feast.add_child(UI.button("Wyprawiaj festyn", _festival, true))
		_body.add_child(feast)
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label("Wybory na przyszły tydzień (koniec za %s). Głosują i mogą wygrać właściciele działek w mieście." \
		% _left(int(hall["weekEndsAt"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for c: Dictionary in hall["candidates"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mine: bool = hall["myVote"] == c["name"]
		var text := UI.label("%s%s: %d głosów%s" % [c["name"], " (ty)" if c["me"] else "", int(c["votes"]), " · twój głos" if mine else ""],
			UI.GOLD if mine else UI.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var vote := UI.button("Głosuj", func() -> void: _vote(c["name"]))
		vote.disabled = not hall["canVote"] or mine
		row.add_child(vote)
		_body.add_child(row)


func _deliver(item: String, quantity: int, from_station: bool) -> void:
	var reply := await Net.request("city.deliver", {"x": plot.x, "y": plot.y, "item": item, "quantity": quantity, "fromStation": from_station})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Miasto kupiło %d szt. za %s" % [int(result["quantity"]), UI.money(int(result["cents"]))])
		inventory_changed.emit()
		balance_changed.emit()


func _take_trash(quantity: int) -> void:
	var reply := await Net.request("city.trash", {"x": plot.x, "y": plot.y, "quantity": quantity})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Wywieziono %d śmieci na stację, miasto zapłaciło %s" % [int(result["quantity"]), UI.money(int(result["cents"]))])
		balance_changed.emit()


func _buy_service(id: String) -> void:
	var reply := await Net.request("city.service", {"x": plot.x, "y": plot.y, "id": id})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Kupiono: %d× %s" % [int(result["quantity"]), result["name"]])
		inventory_changed.emit()
		balance_changed.emit()


func _festival() -> void:
	if _apply(await Net.request("city.festival", {"x": plot.x, "y": plot.y})):
		toast.emit("Festyn trwa! Miasto płaci więcej przez całą dobę.")
		inventory_changed.emit()


func _vote(candidate: String) -> void:
	if _apply(await Net.request("city.vote", {"x": plot.x, "y": plot.y, "candidate": candidate})):
		toast.emit("Oddano głos na: %s" % candidate)


func _set_policy(tax: int, bonus: String) -> void:
	if _apply(await Net.request("city.policy", {"x": plot.x, "y": plot.y, "taxPercent": tax, "bonus": bonus})):
		toast.emit("Ustawiono podatek i premię miasta na ten tydzień")


func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size.x = 76
	spin.select_all_on_focus = true
	return spin


## Time from now until `at` (ms since the epoch), as "5 h 12 min" or "2 dni 3 h".
func _left(at: int) -> String:
	var seconds := maxi(0, (at - int(Time.get_unix_time_from_system() * 1000.0)) / 1000)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	if days > 0:
		return "%d %s %d h" % [days, "dzień" if days == 1 else "dni", hours]
	return "%d h %d min" % [hours, (seconds % 3600) / 60]


func _thousands(n: int) -> String:
	var whole := str(n)
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			grouped += " "
		grouped += whole[i]
	return grouped
