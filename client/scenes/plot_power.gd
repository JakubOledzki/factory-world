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

## What is drawn, worked out again only when the objects or the networks change (see _refresh), not every frame:
## the wires as lines of points, the poles' tiles, the marks over machines ([centre, colour], a null colour for
## the frost) and whether the plot has anything to do with power.
var _wires: Array[PackedVector2Array] = []
## All the wires as one set of triangles (their corners, colours and which corners make each), drawn with one command:
## a big plot has hundreds of wires, and a drawing command for each slows every frame.
var _wire_corners := PackedVector2Array()
var _wire_colors := PackedColorArray()
var _wire_triangles := PackedInt32Array()
var _poles: Array[Vector2i] = []
var _marks: Array = []
var _powered := false
var _stale := true
## The pulsing marks, redrawn every frame while there are any; the wires stay as they were drawn.
var _pulse: PowerMarks


func _ready() -> void:
	_pulse = PowerMarks.new(self)
	add_child(_pulse)


func set_objects(placed: Dictionary) -> void:
	_placed = placed
	_changed()


## The objects or the networks changed: what is drawn is worked out again, once, before the next frame.
func _changed() -> void:
	_stale = true
	queue_redraw()
	if _pulse != null:
		_pulse.queue_redraw()


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
	_changed()


## Whether the plot has anything to do with power, so its state is worth asking for.
func has_power() -> bool:
	_refresh()
	return _powered


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
	_refresh()
	return _poles.duplicate()


func covers(pole: Vector2i, cell: Vector2i) -> bool:
	return absi(pole.x - cell.x) <= supply_radius and absi(pole.y - cell.y) <= supply_radius


func wired(a: Vector2i, b: Vector2i) -> bool:
	return Vector2(a - b).length() <= wire_reach + 0.001


## Whether any pole reaches a tile.
func covered(cell: Vector2i) -> bool:
	_refresh()
	for pole in _poles:
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
	if not _marks.is_empty():
		_pulse.queue_redraw()


func _draw() -> void:
	_refresh()
	if not _wire_triangles.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _wire_triangles, _wire_corners, _wire_colors)


## Works out the poles, the wires and the marks over machines again when the objects or the networks changed.
## Poles are looked up by squares of the wires' reach, so wiring a big plot does not compare every pole with every other.
func _refresh() -> void:
	if not _stale:
		return
	_stale = false
	_poles = []
	_wires = []
	_marks = []
	_powered = false
	for cell: Vector2i in _placed:
		var kind: String = _placed[cell]["kind"]
		if kind == POLE:
			_poles.append(cell)
		if not _powered and (kind == POLE or _source(kind) or demand.has(kind) or kind == HEATER):
			_powered = true
	var square := maxi(1, ceili(wire_reach))
	var near := {}
	for pole in _poles:
		var key := Vector2i(floori(pole.x / float(square)), floori(pole.y / float(square)))
		if not near.has(key):
			near[key] = []
		near[key].append(pole)
	for pole in _poles:
		var key := Vector2i(floori(pole.x / float(square)), floori(pole.y / float(square)))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for other: Vector2i in near.get(key + Vector2i(dx, dy), []):
					# Each pair once.
					if (other.y > pole.y or (other.y == pole.y and other.x > pole.x)) and wired(pole, other):
						_wires.append(_wire_points(_wire_point(pole), _wire_point(other)))
	for cell: Vector2i in _placed:
		var object: Dictionary = _placed[cell]
		# A big object is in _placed once for every tile it covers: wire and mark it once, from where it stands.
		if not _placed_anchor(cell, object):
			continue
		var kind: String = object["kind"]
		var centre := (Vector2(cell) + Vector2(0.5, 0.5) + Footprints.shift(kind)) * tile
		if _source(kind):
			var reach := supply_radius + Footprints.size(kind)
			for pole in _poles:
				if absi(pole.x - cell.x) <= reach and absi(pole.y - cell.y) <= reach \
						and Footprints.tiles(kind, cell).any(func(t: Vector2i) -> bool: return covers(pole, t)):
					_wires.append(_wire_points(_wire_point(cell), _wire_point(pole)))
					break
		elif demand.has(kind):
			var s := speed(object["id"]) if not _networks.is_empty() else (1.0 if Footprints.tiles(kind, cell).any(covered) else 0.0)
			if _cold.has(object["id"]):
				_marks.append([centre, null])
			elif s < 0.999:
				_marks.append([centre, DARK if s <= 0.0 else SHORT])
	_build_wire_triangles()


## Lays every wire out as strips of triangles: a faint wider one softening its edges, the wire, and its shine.
func _build_wire_triangles() -> void:
	_wire_corners = PackedVector2Array()
	_wire_colors = PackedColorArray()
	_wire_triangles = PackedInt32Array()
	for look: Array in [[3.0, Color(WIRE, 0.15)], [2.0, WIRE], [1.0, WIRE_SHINE]]:
		var half: float = look[0] / 2.0
		for points in _wires:
			var first := _wire_corners.size()
			for k in points.size():
				var along := points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]
				var side := along.orthogonal().normalized() * half
				_wire_corners.append(points[k] + side)
				_wire_corners.append(points[k] - side)
				_wire_colors.append(look[1])
				_wire_colors.append(look[1])
			for k in points.size() - 1:
				var at := first + k * 2
				_wire_triangles.append_array([at, at + 1, at + 2, at + 1, at + 3, at + 2])


## Whether a tile is where an object stands (its centre for a big one), so it is marked once.
func _placed_anchor(cell: Vector2i, object: Dictionary) -> bool:
	return cell == Vector2i(int(object["tileX"]), int(object["tileY"]))


## A wire sagging between two points.
static func _wire_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var sag := 4.0 + a.distance_to(b) * 0.06
	for k in 13:
		var t := k / 12.0
		points.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	return points


## The marks over machines short of power (a bolt) or in the cold (a snowflake), pulsing: a node of its own,
## redrawn every frame, so the wires under them are not. Only those on the screen are drawn.
class PowerMarks extends Node2D:
	var power: PlotPower

	func _init(owner_node: PlotPower) -> void:
		power = owner_node

	func _draw() -> void:
		power._refresh()
		var view := PlotLogistics.view_rect(self)
		for mark: Array in power._marks:
			if not view.has_point(mark[0]):
				continue
			if mark[1] == null:
				_flake(mark[0])
			else:
				_bolt(mark[0], mark[1])

	## A snowflake over a machine slowed by the frost, pulsing.
	func _flake(centre: Vector2) -> void:
		var at := centre - Vector2(0, 64)
		var pulse := 0.65 + 0.35 * sin(power._blink * 3.0)
		draw_circle(at, 13, Color(0.05, 0.08, 0.12, 0.75 * pulse))
		for k in 3:
			var d := Vector2.from_angle(k * PI / 3.0) * 9.0
			draw_line(at - d, at + d, Color(0.7, 0.9, 1.0, pulse), 2.0, true)

	## A lightning bolt over a machine short of power, pulsing.
	func _bolt(centre: Vector2, color: Color) -> void:
		var at := centre - Vector2(0, 64)
		var pulse := 0.65 + 0.35 * sin(power._blink * 5.0)
		var shape := PackedVector2Array([Vector2(2, -10), Vector2(-6, 1), Vector2(-1, 1), Vector2(-3, 10), Vector2(6, -2), Vector2(1, -2), Vector2(4, -10)])
		for i in shape.size():
			shape[i] = at + shape[i] * 1.3
		draw_circle(at, 13, Color(0.05, 0.04, 0.03, 0.75 * pulse))
		draw_colored_polygon(shape, Color(color, pulse))
