class_name PlotPower
extends Node2D
## Power on a plot: wires hang between poles wired together and from each generator to the pole
## that reaches it, and a bolt over a machine that runs on power shows when it has too little
## (orange) or none (red). Which poles are wired is worked out here with the server's rules, so a
## new pole is wired at once; how well each network is powered comes with the plot's logistics.

const GENERATOR := "power_generator"
## Generators that burn fuel: the steam generator, the gas power plant, the diesel generator and the fusion plant (on coolant).
const GENERATORS := [GENERATOR, "power_gas_plant", "power_diesel_generator", "power_fusion_plant"]
## Water power: wired to a pole like a generator, but burns nothing.
const HYDRO := ["power_water_wheel", "power_hydro_plant", "power_tidal_plant"]
## Solar power and batteries: wired to a pole too; the sun gives power by day, a battery stores it.
const SOLAR := ["power_solar_panel", "power_solar_tower"]
const BATTERY := "power_battery"
## Wind power: wired to a pole too, it gives as much as the wind blows. A heater gives no power, it warms machines on the glacier.
const WIND := ["power_wind_turbine", "power_large_wind_turbine"]
const HEATER := "power_heater"
## Sprites whose layout says where wires meet them, by kind.
const WIRE_SPRITES := {"power_generator": "generator", "power_water_wheel": "water_wheel", "power_hydro_plant": "hydro_plant",
	"power_tidal_plant": "tidal_plant", "power_gas_plant": "gas_plant", "power_diesel_generator": "diesel_generator",
	"power_solar_panel": "solar_panel", "power_solar_tower": "solar_tower", "power_battery": "battery",
	"power_wind_turbine": "wind_turbine", "power_large_wind_turbine": "large_wind_turbine", "power_fusion_plant": "fusion_plant"}
const POLE := "power_pole"
const WIRE := Color(0.08, 0.07, 0.06, 0.9)
const WIRE_SHINE := Color(0.62, 0.42, 0.25, 0.55)
const SHORT := Color(1.0, 0.62, 0.15)
const DARK := Color(1.0, 0.3, 0.25)

var tile := Vector2(64, 45)
var layout := {}

## A pole powers tiles this far from it each way; poles this far apart (in tiles) are wired.
var supply_radius := 2
var wire_reach := 7.0
## What every machine that runs on power draws (kW), by kind.
var demand := {"logistics_inserter": 5.0, "furniture_mill": 30.0, "furniture_oil_press": 30.0}

## Objects on the plot by tile, as plot.gd keeps them.
var _placed := {}
## The network of every pole, generator and machine, by object id, and each network's last state.
var _network_of := {}
var _networks := {}
var _blink := 0.0
## Machines on the glacier no heater warms, which work at half pace: by id.
var _cold := {}


func set_objects(placed: Dictionary) -> void:
	_placed = placed
	queue_redraw()


## Applies the "power" part of an answer to "logistics.get".
func apply(summary: Dictionary) -> void:
	if summary.is_empty():
		return
	supply_radius = int(summary.get("supplyRadius", supply_radius))
	wire_reach = float(summary.get("wireReach", wire_reach))
	if summary.get("demand") != null:
		demand = summary["demand"]
	_network_of = {}
	_networks = {}
	for network: Dictionary in summary.get("networks", []):
		_networks[int(network["id"])] = network
		for key: String in ["poles", "generators", "consumers", "hydro", "solar", "batteries", "wind"]:
			for id: String in network.get(key, []):
				_network_of[id] = int(network["id"])
	_cold = {}
	for id: String in summary.get("cold", []):
		_cold[id] = true
	queue_redraw()


## Whether the plot has anything to do with power, so its state is worth asking for.
func has_power() -> bool:
	for cell: Vector2i in _placed:
		var kind: String = _placed[cell]["kind"]
		if kind == POLE or _source(kind) or demand.has(kind) or kind == HEATER:
			return true
	return false


## Whether an object of `kind` gives power to a network: a generator, water or solar power or a battery.
func _source(kind: String) -> bool:
	return kind in GENERATORS or kind in HYDRO or kind in SOLAR or kind == BATTERY or kind in WIND


## Whether a machine on the glacier stands in the cold, no heater warming it.
func cold(id: String) -> bool:
	return _cold.has(id)


## How full a battery's network is, as players read it.
func describe_battery(id: String) -> String:
	var n := network(id)
	if n.is_empty():
		return "bez sieci: postaw obok słup"
	var capacity := float(n.get("bankCapacityKj", 0.0))
	var rate := float(n.get("bankRateKw", 0.0))
	var state := "ładuje się %s" % GeneratorWindow.kw(rate) if rate > 0.001 else ("oddaje %s" % GeneratorWindow.kw(-rate) if rate < -0.001 else "czeka")
	return "naładowane %d%%, %s" % [roundi(100.0 * float(n.get("bankKj", 0.0)) / capacity) if capacity > 0.0 else 0, state]


func runs_on_power(kind: String) -> bool:
	return demand.has(kind)


## The network an object is on, or {} when no pole reaches it.
func network(id: String) -> Dictionary:
	return _networks.get(_network_of.get(id, -1), {})


## How fast a machine works on its power: 1 full, 0 none.
func speed(id: String) -> float:
	var n := network(id)
	return float(n.get("speed", 0.0)) if not n.is_empty() else 0.0


func poles() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _placed:
		if _placed[cell]["kind"] == POLE:
			cells.append(cell)
	return cells


func covers(pole: Vector2i, cell: Vector2i) -> bool:
	return absi(pole.x - cell.x) <= supply_radius and absi(pole.y - cell.y) <= supply_radius


func wired(a: Vector2i, b: Vector2i) -> bool:
	return Vector2(a - b).length() <= wire_reach + 0.001


## Whether any pole reaches a tile.
func covered(cell: Vector2i) -> bool:
	for pole in poles():
		if covers(pole, cell):
			return true
	return false


## What a pole's network draws and gets, as players read it.
func describe(id: String) -> String:
	var n := network(id)
	if n.is_empty():
		return "bez sieci"
	if float(n["demandKw"]) <= 0.0:
		return "sieć bez maszyn, %s mocy" % GeneratorWindow.kw(float(n["supplyKw"]))
	return "sieć: maszyny pobierają %s, źródła prądu dają %s" % [GeneratorWindow.kw(float(n["demandKw"])),
		GeneratorWindow.kw(minf(float(n["demandKw"]), float(n["supplyKw"])))]


## Where the wires meet an object standing on a tile, on the screen of the plot.
func _wire_point(cell: Vector2i) -> Vector2:
	var kind: String = _placed[cell]["kind"]
	var sprite: String = "pole" if kind == POLE else WIRE_SPRITES.get(kind, "generator")
	var at: Dictionary = layout.get(sprite, {})
	var centre := (Vector2(cell) + Vector2(0.5, 0.5)) * tile
	return centre + Vector2(float(at.get("wireX", 0)) - float(at.get("anchorX", 0)), float(at.get("wireY", 0)) - float(at.get("anchorY", 0)))


func _process(delta: float) -> void:
	_blink += delta
	if not _placed.is_empty():
		queue_redraw()


func _draw() -> void:
	var all_poles := poles()
	for i in all_poles.size():
		for j in range(i + 1, all_poles.size()):
			if wired(all_poles[i], all_poles[j]):
				_wire(_wire_point(all_poles[i]), _wire_point(all_poles[j]))
	for cell: Vector2i in _placed:
		var object: Dictionary = _placed[cell]
		if _source(object["kind"]):
			for pole in all_poles:
				if covers(pole, cell):
					_wire(_wire_point(cell), _wire_point(pole))
					break
		elif demand.has(object["kind"]):
			var s := speed(object["id"]) if not _networks.is_empty() else (1.0 if covered(cell) else 0.0)
			if s < 0.999 and not _cold.has(object["id"]):
				_bolt(cell, DARK if s <= 0.0 else SHORT)
			elif _cold.has(object["id"]) and _placed_anchor(cell, object):
				_flake(cell)


## Whether a tile is where an object stands (its centre for a big one), so it is marked once.
func _placed_anchor(cell: Vector2i, object: Dictionary) -> bool:
	return cell == Vector2i(int(object["tileX"]), int(object["tileY"]))


## A snowflake over a machine slowed by the frost, pulsing.
func _flake(cell: Vector2i) -> void:
	var at := (Vector2(cell) + Vector2(0.5, 0.5)) * tile - Vector2(0, 64)
	var pulse := 0.65 + 0.35 * sin(_blink * 3.0)
	draw_circle(at, 13, Color(0.05, 0.08, 0.12, 0.75 * pulse))
	for k in 3:
		var d := Vector2.from_angle(k * PI / 3.0) * 9.0
		draw_line(at - d, at + d, Color(0.7, 0.9, 1.0, pulse), 2.0, true)


## A wire sagging between two points.
func _wire(a: Vector2, b: Vector2) -> void:
	var points := PackedVector2Array()
	var sag := 4.0 + a.distance_to(b) * 0.06
	for k in 13:
		var t := k / 12.0
		points.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	draw_polyline(points, WIRE, 2.0, true)
	draw_polyline(points, WIRE_SHINE, 1.0, true)


## A lightning bolt over a machine short of power, pulsing.
func _bolt(cell: Vector2i, color: Color) -> void:
	var at := (Vector2(cell) + Vector2(0.5, 0.5)) * tile - Vector2(0, 64)
	var pulse := 0.65 + 0.35 * sin(_blink * 5.0)
	var shape := PackedVector2Array([Vector2(2, -10), Vector2(-6, 1), Vector2(-1, 1), Vector2(-3, 10), Vector2(6, -2), Vector2(1, -2), Vector2(4, -10)])
	for i in shape.size():
		shape[i] = at + shape[i] * 1.3
	draw_circle(at, 13, Color(0.05, 0.04, 0.03, 0.75 * pulse))
	draw_colored_polygon(shape, Color(color, pulse))
