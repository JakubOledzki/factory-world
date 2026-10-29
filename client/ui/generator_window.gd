class_name GeneratorWindow
extends GameWindow
## A generator on a plot: wood or coal on the fire of a steam generator, gas in a gas power plant, diesel
## or petrol in a diesel generator, coolant in a fusion plant; it gives power to the machines on
## the poles it stands next to, as much as they draw, up to its full power. It burns only while a
## pole connects it to machines, faster the more they draw. A water wheel or a small water power
## plant opens the same window without the fire: water turns it all the time and it burns nothing. So do
## solar power, which gives power by day only, a wind turbine, which gives as much as the wind blows, and a battery,
## which stores what the free power has to spare. A heater has the fire but gives no power: on the glacier it warms
## the machines around it, which work at half pace in the cold.

## Items went from the inventory into the generator or back: [{id, name, quantity}] taken out.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open: inserters may put fuel in.
const POLL := 2000.0
const HYDRO_NAMES := {"power_water_wheel": "Koło wodne", "power_hydro_plant": "Mała elektrownia wodna", "power_tidal_plant": "Elektrownia pływowa",
	"power_geothermal_plant": "Elektrownia geotermalna"}
const FUEL_NAMES := {"power_gas_plant": "Elektrownia gazowa", "power_diesel_generator": "Agregat spalinowy", "power_fusion_plant": "Elektrownia fuzyjna",
	"power_coal_plant": "Elektrownia węglowa", "power_nuclear_plant": "Elektrownia jądrowa", "power_biomass_plant": "Elektrownia na biomasę",
	"power_chp_plant": "Elektrociepłownia", "power_fuel_cell": "Ogniwo paliwowe"}
const FREE_NAMES := {"power_solar_panel": "Panel słoneczny", "power_solar_tower": "Elektrownia słoneczna z lustrami", "power_battery": "Akumulator", "power_energy_store": "Magazyn energii",
	"power_wind_turbine": "Turbina wiatrowa", "power_large_wind_turbine": "Duża turbina wiatrowa", "power_heater": "Kocioł grzewczy"}

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
	var solar: bool = _state.get("solar", false)
	var battery: bool = _state.get("battery", false)
	var wind: bool = _state.get("wind", false)
	var heater: bool = _state.get("heater", false)
	# Everything that burns nothing shows the same window without the fire.
	var hydro: bool = _state.get("hydro", false) or solar or battery or wind
	var kind: String = _state.get("kind", "")
	set_title(HYDRO_NAMES.get(kind, FUEL_NAMES.get(kind, FREE_NAMES.get(kind, "Generator parowy"))))
	_pick_up.text = "Schowaj do ekwipunku" if hydro or heater else "Schowaj generator do ekwipunku"
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
	_output_bar.visible = not heater
	if heater:
		var warmed := int(_state.get("warmed", 0))
		if not _state.get("icy", false):
			_output.text = "Tu nie ma mrozu: maszyny pracują pełną parą i bez kotła."
		elif float(_state.get("total", 0.0)) <= 0.0:
			_output.text = "Kocioł wygasł: %d %s wokół niego marznie i pracuje wolniej." % [warmed, _machines(warmed)]
		else:
			_output.text = "Grzeje %d %s na %d pól wokół siebie." % [warmed, _machines(warmed), int(_state.get("heaterReach", 3))]
	elif battery:
		var charge := float(_state.get("chargeKj", 0.0))
		var full := float(_state.get("capacityKj", 1.0))
		_output.text = "Naładowany %s z %s (%d%%) · %s" % [_energy(charge), _energy(full), roundi(100.0 * charge / full),
			("oddaje %s" % kw(output)) if output > 0.001 else (("ładuje się %s" % kw(-output)) if output < -0.001 else "czeka")]
		_output_bar.max_value = full
		_output_bar.value = charge
	else:
		_output.text = ("Słońce daje %s z %s" if solar else ("Wiatr daje %s z %s" if wind else ("Woda daje %s z %s" if hydro else "Daje %s z %s"))) % [kw(output), kw(capacity)]
		_output_bar.max_value = capacity
		_output_bar.value = output
	_output.add_theme_color_override("font_color", UI.GOLD if output > 0 else UI.MUTED)

	var network: Variant = _state.get("network")
	_network.visible = not heater
	if heater:
		pass
	elif network == null:
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
	intake.clear()
	var any := false
	var held := int(fuel["quantity"]) if fuel != null else 0
	for option: Dictionary in _state.get("fuels", []):
		var owned := _count(option["id"])
		if owned == 0:
			continue
		any = true
		var blocked: bool = fuel != null and fuel["id"] != option["id"]
		var room := int(_state["maxFuel"]) - held
		if not blocked:
			var id: String = option["id"]
			offer(id, room, func(quantity: int) -> void: _put(id, quantity))
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
		var names: Array[String] = []
		for option: Dictionary in _state.get("fuels", []):
			names.append(String(option["name"]).to_lower())
		var burner: String = _state.get("kind", "")
		var hint := "Drewno daje ścinanie drzew, węgiel skały i kopalnie w górach." if burner in ["power_generator", "power_biomass_plant", "power_chp_plant"] \
			else ("Wodór robi z wody elektrolizer na prąd." if burner == "power_fuel_cell" else "Gaz pompuje głowica gazowa, paliwa robi rafineria.")
		_load.add_child(UI.label("Nie masz opału, który ten generator spala (%s). %s" % [", ".join(names), hint],
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	if heater:
		_load_heading.text = "Dołóż do kotła"
		_help.text = "Na lodowcu maszyny na prąd bez ogrzewania pracują o połowę wolniej. Kocioł spala opał bez przerwy (%s, nawet gdy nic nie grzeje) i ogrzewa maszyny do %d pól wokół siebie, a słup nie jest mu potrzebny." % [
			kw(float(_state.get("heaterKw", 15.0))), int(_state.get("heaterReach", 3))]
		_update_runs_out()
		_fit.call_deferred()
		return
	_load_heading.text = "Dołóż do ognia"
	if wind:
		var strength := roundi(float(_state.get("windStrength", 0.0)) * 100.0)
		var bonus := float(_state.get("windBonus", 1.0))
		var now := "Teraz wieje na %d%% pełnej siły." % strength
		if _state.get("blizzard", false):
			now = "Szaleje zamieć: turbina stoi, żeby wiatr jej nie połamał."
		_help.text = "Wiatr kręci nią bez opału, a jego siła zmienia się co 10 minut.%s Nadwyżkę zbiera akumulator w tej samej sieci. %s" % [
			" Tu wieje mocniej: +%d%% mocy." % roundi((bonus - 1.0) * 100.0) if bonus > 1.0 else "", now]
		_fit.call_deferred()
		return
	if solar:
		var sun := "Teraz dzień." if _state.get("day", true) else "Teraz noc: panele nie dają prądu do świtu."
		if _state.get("storm", false):
			sun = "Wieje burza piaskowa: %s" % ("płot trzcinowy osłania ten panel." if _state.get("sheltered", false) else "bez płotu trzcinowego w pobliżu daje ćwierć mocy.")
		_help.text = "Słońce daje prąd za dnia (36 z każdych 60 minut), na pustyni i w oazie o 25%% więcej. Nadwyżkę zbiera akumulator w tej samej sieci. %s" % sun
		_fit.call_deferred()
		return
	if battery:
		_help.text = "%s bierze to, czego woda, słońce i wiatr dają za dużo (do %s), i oddaje, gdy im brakuje, zanim generatory zaczną palić opał. Wszystkie akumulatory i magazyny sieci ładują się i rozładowują razem, każdy według pojemności; schowany traci ładunek." % [
			"Magazyn energii" if _state.get("kind", "") == "power_energy_store" else "Akumulator", kw(capacity)]
		_fit.call_deferred()
		return
	if hydro and _state.get("geothermal", false):
		var heat := float(_state.get("hydroBonus", 1.0))
		_help.text = "Ciepło ziemi kręci turbiną bez przerwy i nie trzeba dokładać opału. Daje prąd od razu, przed generatorami parowymi.%s" % [
			" Pod lodowcem skała jest gorętsza: +%d%% mocy." % roundi((heat - 1.0) * 100.0) if heat > 1.0
			else (" Na tundrze skała jest chłodniejsza: %d%% mocy." % roundi(heat * 100.0) if heat < 1.0 else "")]
		_fit.call_deferred()
		return
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
	if _state.get("dry", false):
		lines.append("Na piasku brak wody do chłodzenia: daje tylko 70% mocy.")
	if _state.get("chp", false):
		lines.append("Na lodowcu, póki pali, ogrzewa maszyny do %d pól wokół (teraz %d), jak kocioł grzewczy." % [int(_state.get("chpReach", 6)), int(_state.get("warmed", 0))])
	_help.text = "\n".join(lines)
	_update_runs_out()
	_fit.call_deferred()


func _update_runs_out() -> void:
	if _state.get("hydro", false) or _state.get("solar", false) or _state.get("battery", false) or _state.get("wind", false):
		return
	var at: Variant = _state.get("runsOutAt")
	if at == null:
		_runs_out.text = "Generator wygasł: dołóż opału." if float(_state.get("total", 0.0)) <= 0.0 else ""
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
