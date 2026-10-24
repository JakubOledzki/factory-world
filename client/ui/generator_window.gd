class_name GeneratorWindow
extends GameWindow
## A steam generator on a plot: wood or coal goes on its fire and it gives power to the machines on
## the poles it stands next to, as much as they draw, up to its full power. It burns only while a
## pole connects it to machines, faster the more they draw. A water wheel or a small water power
## plant opens the same window without the fire: water turns it all the time and it burns nothing.

## Items went from the inventory into the generator or back: [{id, name, quantity}] taken out.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open: inserters may put fuel in.
const POLL := 2000.0
const HYDRO_NAMES := {"power_water_wheel": "Koło wodne", "power_hydro_plant": "Mała elektrownia wodna"}

var generator := ""
var plot := Vector2i(-1, -1)

var _state := {}
var _items: Array = []
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _fuel_row := HBoxContainer.new()
var _output: Label
var _output_bar: ProgressBar
var _network: Label
var _runs_out: Label
var _load := VBoxContainer.new()
var _load_heading: Label
var _help: Label
var _pick_up: Button


func _init() -> void:
	super("Generator parowy", 400)
	content.add_child(_fuel_row)
	_output = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_output)
	_output_bar = ProgressBar.new()
	_output_bar.show_percentage = false
	_output_bar.custom_minimum_size.y = 10
	content.add_child(_output_bar)
	_runs_out = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_runs_out)
	_network = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_network)
	content.add_child(HSeparator.new())
	_load_heading = UI.label("Dołóż do ognia", UI.GOLD)
	_load_heading.add_theme_font_override("font", UI.bold())
	content.add_child(_load_heading)
	_load.add_theme_constant_override("separation", 4)
	content.add_child(_load)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	_pick_up = UI.button("Schowaj generator do ekwipunku", func() -> void: pick_up_requested.emit(generator))
	content.add_child(_pick_up)


func open_at(at: Vector2i, id: String) -> void:
	if id != generator:
		_state = {}
	generator = id
	plot = at
	show_window()
	refresh()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func refresh() -> void:
	if generator == "":
		return
	_refreshing = true
	_next_poll = _server_now() + POLL
	var reply := await Net.request("generator.get", {"x": plot.x, "y": plot.y, "id": generator})
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "generator":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_render()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


static func kw(value: float) -> String:
	return ("%d kW" % roundi(value)) if absf(value - roundf(value)) < 0.05 else ("%.1f kW" % value).replace(".", ",")


func _render() -> void:
	if _state.is_empty():
		return
	var hydro: bool = _state.get("hydro", false)
	set_title(HYDRO_NAMES.get(_state.get("kind", ""), "Generator parowy"))
	_pick_up.text = "Schowaj do ekwipunku" if hydro else "Schowaj generator do ekwipunku"
	_fuel_row.visible = not hydro
	_load_heading.visible = not hydro
	_load.visible = not hydro
	_runs_out.visible = not hydro
	for child in _fuel_row.get_children():
		child.free()
	var fuel: Variant = _state.get("fuel")
	_fuel_row.add_theme_constant_override("separation", 6)
	if fuel != null:
		_fuel_row.add_child(UI.item_icon(fuel["id"], 30))
	var label := UI.label("Opał:", UI.MUTED)
	label.custom_minimum_size.x = 64
	_fuel_row.add_child(label)
	var burning := float(_state.get("energy", 0.0)) > 0.0
	var text := "%s × %d" % [fuel["name"], int(fuel["quantity"])] if fuel != null else "pusto"
	if burning:
		text += "  (w ogniu jeszcze %s)" % _energy(float(_state["energy"]))
	var value := UI.label(text)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_row.add_child(value)
	var take := UI.button("Wyjmij", _take)
	take.disabled = fuel == null
	take.tooltip_text = "Opał, który się jeszcze nie pali, wraca do ekwipunku"
	_fuel_row.add_child(take)

	var output := float(_state["outputKw"])
	var capacity := float(_state["capacityKw"])
	_output.text = ("Woda daje %s z %s" if hydro else "Daje %s z %s") % [kw(output), kw(capacity)]
	_output.add_theme_color_override("font_color", UI.GOLD if output > 0 else UI.MUTED)
	_output_bar.max_value = capacity
	_output_bar.value = output

	var network: Variant = _state.get("network")
	if network == null:
		_network.text = "Żaden słup go nie sięga. Postaw słup energetyczny najwyżej 2 pola od niego, a słupy przy maszynach połączą się przewodami."
		_network.add_theme_color_override("font_color", UI.ERROR)
	elif int(network["machines"]) == 0:
		_network.text = "Słupy nie sięgają jeszcze żadnej maszyny." if hydro else "Słupy nie sięgają jeszcze żadnej maszyny, więc generator nie pali opału."
		_network.add_theme_color_override("font_color", UI.MUTED)
	else:
		var speed := float(network["speed"])
		var count := int(network["machines"])
		var line := "Sieć: %d %s %s %s, źródła prądu dają %s." % [count, _machines(count), ("pobierają" if _machines(count) == "maszyny" else "pobiera"),
			kw(float(network["demandKw"])), kw(minf(float(network["supplyKw"]), float(network["demandKw"])))]
		if speed >= 0.999:
			line += " Maszyny mają pełną moc."
			_network.add_theme_color_override("font_color", UI.TEXT)
		elif speed > 0.0:
			line += " Za mało prądu: maszyny pracują na %d%%. Dołóż drugi generator albo koło wodne." % roundi(speed * 100.0)
			_network.add_theme_color_override("font_color", UI.ERROR)
		else:
			line += " Brak prądu: maszyny stoją."
			_network.add_theme_color_override("font_color", UI.ERROR)
		_network.text = line

	for child in _load.get_children():
		child.free()
	var any := false
	var held := int(fuel["quantity"]) if fuel != null else 0
	for option: Dictionary in _state.get("fuels", []):
		var owned := _count(option["id"])
		if owned == 0:
			continue
		any = true
		var blocked: bool = fuel != null and fuel["id"] != option["id"]
		var room := int(_state["maxFuel"]) - held
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(option["id"], 26))
		var name_label := UI.label("%s  ×%d" % [option["name"], owned])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		for amount: int in [1, 10, 0]:
			var count := mini(owned, room) if amount == 0 else amount
			var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _put.bind(option["id"], count))
			b.disabled = blocked or count < 1 or count > owned or count > room
			if blocked:
				b.tooltip_text = "Przy ogniu leży już inny opał. Wyjmij go najpierw."
			row.add_child(b)
		_load.add_child(row)
	if not any:
		_load.add_child(UI.label("Nie masz drewna ani węgla. Drewno daje ścinanie drzew, węgiel skały i kopalnie w górach.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	if hydro:
		var bonus := float(_state.get("hydroBonus", 1.0))
		_help.text = "Woda kręci nim bez przerwy i nie trzeba dokładać opału. Daje prąd od razu, przed generatorami parowymi: one dopalają tylko to, czego brakuje.%s" % [
			" Górski potok płynie szybciej: +%d%% mocy." % roundi((bonus - 1.0) * 100.0) if bonus > 1.0 else ""]
		_fit.call_deferred()
		return
	var lines: Array[String] = []
	for option: Dictionary in _state.get("fuels", []):
		lines.append("%s: %s, przy pełnej mocy na %d s." % [option["name"], _energy(float(option["kj"])), roundi(float(option["kj"]) / capacity)])
	lines.append("Podajnik może dokładać opał z taśmy albo ze skrzyni.")
	_help.text = "\n".join(lines)
	_update_runs_out()
	_fit.call_deferred()


func _update_runs_out() -> void:
	if _state.get("hydro", false):
		return
	var at: Variant = _state.get("runsOutAt")
	if at == null:
		_runs_out.text = "Generator wygasł: dołóż drewna albo węgla." if float(_state.get("total", 0.0)) <= 0.0 else ""
		return
	var left := maxi(0, ceili((float(at) - _server_now()) / 1000.0))
	if left >= 3600:
		_runs_out.text = "Opał skończy się za %d h %02d min." % [left / 3600, left / 60 % 60]
	else:
		_runs_out.text = "Opał skończy się za %d min %02d s." % [left / 60, left % 60]


static func _energy(kj: float) -> String:
	return ("%.1f MJ" % (kj / 1000.0)).replace(".", ",") if kj >= 1000.0 else "%d kJ" % roundi(kj)


static func _machines(count: int) -> String:
	if count == 1:
		return "maszyna"
	if count % 10 in [2, 3, 4] and not count % 100 in [12, 13, 14]:
		return "maszyny"
	return "maszyn"


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _process(_delta: float) -> void:
	if not visible or _state.is_empty():
		return
	_update_runs_out()
	if _server_now() >= _next_poll and not _refreshing:
		refresh()


func _put(item: String, quantity: int) -> void:
	_changed(await Net.request("generator.load", {"x": plot.x, "y": plot.y, "id": generator, "item": item, "quantity": quantity}))


func _take() -> void:
	_changed(await Net.request("generator.take", {"x": plot.x, "y": plot.y, "id": generator}))


func _changed(reply: Dictionary) -> void:
	_apply(reply)
	if reply["type"] == "generator":
		inventory_changed.emit(_state.get("taken", []), null)
