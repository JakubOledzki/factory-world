class_name PlotLogistics
extends Node2D
## The belts, splitters and inserters of a plot. Belts lie flat on the ground (they can be walked
## over) with stripes running along them and the items they carry on two lanes; a belt fed from one
## side only turns the corner. Splitters stand where a belt meets them from behind and send what it
## brings to the belts on their left and right. Inserters stand on their tiles and swing an arm from
## the tile behind them to the tile in front, when they have power.
## The server works the machinery out in ticks; between its answers the same rules run here, so
## items glide along the belts instead of jumping once a second. Fast and express belts move their
## items 2 and 3 places a tick, in turns within the tick, and a splitter keeps up with the belt that
## feeds it from behind; fast and express inserters swing in fewer ticks. They are painted red and blue.
## A cable station runs like a fast belt, but sends what reaches its end along a cable, over whatever
## stands below, to the next station ahead facing the same way (up to CABLE_SPAN tiles off).
## An express cable station runs like an express belt and its cable reaches EXPRESS_CABLE_SPAN tiles.
## Pipes and pumps are the belts and inserters of fluids: a pipe joins only pipes and carries only
## fluids, a pump moves only fluids, and an inserter never touches them.
## Underground belts pair up along a line, from the back: one takes what reaches its end down under
## whatever stands on the tiles ahead, the next one (up to TUNNEL_SPAN tiles on) brings it up again; both
## keep up with the belt feeding the first. A long-armed inserter reaches two tiles each way, and with
## bigger grippers an inserter carries a few pieces at once. Drones fly from each drone port without a
## filter to the ports set to take what it holds, while both have power.

## Emitted after each answer from the server, which may have changed the filters.
signal filters_changed

const BELT := "logistics_belt"
const INSERTER := "logistics_inserter"
const SPLITTER := "logistics_splitter"
const CABLE := "logistics_cable_station"
const UNDERGROUND := "logistics_underground_belt"
const DRONE_PORT := "logistics_drone_port"
## Tiles a cable runs at most, and places a tick a cable station moves items, as on the server.
const CABLE_SPAN := 24
const CABLE_SPEED := 2
const EXPRESS_CABLE_SPAN := 48
## Cable stations of both levels: the tiles their cable runs and the places a tick they move items.
const CABLES := {CABLE: [CABLE_SPAN, CABLE_SPEED], "logistics_express_cable_station": [EXPRESS_CABLE_SPAN, 3]}
## Tiles at most from an underground belt going down to the one coming up.
const TUNNEL_SPAN := 5
## Height of the cable at the stations, in metres.
const CABLE_HEIGHT := 2.3
const CABLE_COLOR := Color("#2b2b30")
const GONDOLA_COLOR := Color("#c8321e")
const GONDOLA_COLORS := {"": GONDOLA_COLOR, "_express": Color("#2c62c8")}
## Places a tick an item moves along a belt of each level, and ticks an inserter's arm takes to swing one way.
const BELT_SPEEDS := {"logistics_belt": 1, "logistics_fast_belt": 2, "logistics_express_belt": 3, "logistics_pipe": 3}
const INSERTER_SWINGS := {"logistics_inserter": 4, "logistics_fast_inserter": 2, "logistics_express_inserter": 1,
	"logistics_long_inserter": 3, "logistics_pump": 1}
## Tiles away an inserter picks up behind it and drops in front, where not one.
const INSERTER_REACH := {"logistics_long_inserter": 2}
## What carries fluids: a pipe instead of a belt, a pump instead of an inserter.
const FLUID_CARRIERS := ["logistics_pipe", "logistics_pump"]
## Sprites of upgraded belts and inserters end in the level's name.
const TIER_SUFFIXES := {"logistics_fast_belt": "_fast", "logistics_express_belt": "_express",
	"logistics_fast_inserter": "_fast", "logistics_express_inserter": "_express", "logistics_pipe": "_pipe", "logistics_pump": "_pump",
	"logistics_long_inserter": "_long", "logistics_express_cable_station": "_express"}
const ARM_COLORS := {"": Color("#d9a21c"), "_fast": Color("#c8321e"), "_express": Color("#2c62c8"), "_long": Color("#3d8f3a")}
## Sprites of underground belts by the side their opening faces: the way in at the back of one going
## down, the way out at the front of one coming up.
const TUNNEL_SPRITES := ["tunnel_s", "tunnel_e", "tunnel_n", "tunnel_w"]
## Height drones fly at, in metres, and how long (ms) one takes to fly a tile.
const DRONE_HEIGHT := 3.2
const DRONE_TILE_MS := 120.0
## Belt sprites by rotation: south and north run up and down the screen, east and west across.
const BELT_SPRITES := ["belt_ns", "belt_ew", "belt_ns", "belt_ew"]
## Sprites of belts turning a corner, by the two sides of the tile they join.
const CURVE_SPRITES := {"ne": "belt_ne", "es": "belt_es", "sw": "belt_sw", "nw": "belt_nw"}
## How far either lane runs from the middle of the band, in tiles.
const LANE_OFFSET := 0.2
## Height of the top of the band and of the inserter's shoulder, in metres, and px per metre.
const BAND_HEIGHT := 0.24
const SHOULDER_HEIGHT := 0.68
const PPM := 32.0
const ITEM_SIZE := 14.0
const ARM_COLOR := Color("#d9a21c")
const ARM_DARK := Color("#2a2418")
const STRIPE := Color(0.32, 0.31, 0.3, 0.9)
## Pixels around the screen that are drawn as well.
const VIEW_MARGIN := 200.0

## Pixels of one tile on screen, the sprites' anchors, the node that y-sorts inserter arms with
## everything else standing on the plot, and the server clock (milliseconds).
var tile := Vector2(64, 45)
var layout := {}
var arms_parent: Node2D
var server_now := func() -> float: return Time.get_unix_time_from_system() * 1000.0

var tick_ms := 200.0
var belt_slots := 4
var belt_lanes := 2
var swing_ticks := 4

## What every item is called, when the plot has a splitter.
var names := {}

## Belts and splitters, and inserters, by tile: { id, rotation, items / hand, swing, ... }.
var _belts := {}
var _inserters := {}
## Belts downstream first, as the server moves them.
var _order: Array[Vector2i] = []
## Underground belts going down and the one each brings its items up at, by tile.
var _tunnels := {}
## Drone ports by tile, and their speed on the power they have (0 stands still) by object id.
var _drone_ports := {}
var _drone_speeds := {}
## Storage summaries from the last answer, by object id.
var _storages := {}
## The one item each inserter, storage or machine with a filter takes, by object id.
var _filters := {}
## Server time (ms) of the last tick worked out here.
var _time := 0.0
var _textures := {}
var _icons := {}
## Drawn above everything standing on the plot: the cables between stations, and drones in flight.
var _cables: CableLines
## Cable stations that send their items over a cable, by tile.
var _cable_starts: Array[Vector2i] = []
var _drones: DroneFlights


func _ready() -> void:
	for sprite: String in ["belt_ns", "belt_ew"] + CURVE_SPRITES.values():
		for suffix: String in ["", "_fast", "_express", "_pipe"]:
			_textures[sprite + suffix] = load("res://art/plot/%s%s.png" % [sprite, suffix])


## "_fast" or "_express" for upgraded belts and inserters, "_pipe" for pipes, whose sprites end so; "" for the rest.
static func tier_suffix(kind: String) -> String:
	return TIER_SUFFIXES.get(kind, "")


## Belts or inserters to animate, drones to fly, or filters to keep up to date.
func has_machinery() -> bool:
	return not _belts.is_empty() or not _inserters.is_empty() or not _filters.is_empty() or not _drone_ports.is_empty()


## The item an inserter, storage or machine is set to take, or "" without a filter.
func filter(id: String) -> String:
	return _filters.get(id, "")


## Objects with a filter: object id → item.
func filters() -> Dictionary:
	return _filters


func is_belt(object: Dictionary) -> bool:
	return BELT_SPEEDS.has(object.get("kind", ""))


## A splitter's filter: { items: [ids], side: 0 left / 1 right }.
func splitter(id: String) -> Dictionary:
	var belt := _find(_belts, id)
	var items: Array = belt.get("filter", [])
	# Without a filter there is no side yet; the right one is offered first.
	return {"items": items, "side": int(belt.get("filterSide", 0)) if not items.is_empty() else 1}


func storage(id: String) -> Dictionary:
	return _storages.get(id, {})


## The item an inserter holds, or "".
func held(cell: Vector2i) -> String:
	var hand: Variant = _inserters.get(cell, {}).get("hand")
	return hand if hand != null else ""


## How many pieces an inserter holds.
func held_count(cell: Vector2i) -> int:
	return int(_inserters.get(cell, {}).get("count", 1)) if held(cell) != "" else 0


## The sprite of the underground belt at a tile, by the way its opening faces: back for one going down
## (or without a pair), front for one coming up.
func tunnel_sprite(cell: Vector2i, rotation: int) -> String:
	var up: bool = _belts.get(cell, {}).get("up", false)
	return TUNNEL_SPRITES[(rotation + (0 if up else 2)) & 3]


## Whether the underground belt at a tile brings items up, "up", takes them down, "down", or has no pair, "".
func tunnel_role(cell: Vector2i) -> String:
	var belt: Dictionary = _belts.get(cell, {})
	return "up" if belt.get("up", false) else ("down" if belt.get("down", false) else "")


## Takes the objects standing on the plot (tile → { id, kind, rotation }); belts and inserters
## that were there before keep what they carry.
func set_objects(placed: Dictionary) -> void:
	var belts := {}
	var inserters := {}
	var old_belts := _by_id(_belts)
	var old_inserters := _by_id(_inserters)
	for cell: Vector2i in placed:
		var object: Dictionary = placed[cell]
		var rotation := int(object.get("rotation", 0))
		if BELT_SPEEDS.has(object["kind"]) or object["kind"] in [SPLITTER, UNDERGROUND] or CABLES.has(object["kind"]):
			var old: Dictionary = old_belts.get(object["id"], {})
			var items: Array = old.get("items", [])
			if items.size() != belt_slots * belt_lanes:
				items = []
				items.resize(belt_slots * belt_lanes)
			belts[cell] = {"id": object["id"], "rotation": rotation, "items": items, "moved": {}, "out": [], "bend": 0,
				"splitter": object["kind"] == SPLITTER, "filter": old.get("filter", []), "filterSide": int(old.get("filterSide", 0)),
				"turn": int(old.get("turn", 0)),
				"speed": int(CABLES[object["kind"]][1]) if CABLES.has(object["kind"]) else int(BELT_SPEEDS.get(object["kind"], 1)),
				"suffix": tier_suffix(object["kind"]), "cable": CABLES.has(object["kind"]), "span": int(CABLES.get(object["kind"], [0])[0]),
				"tunnel": object["kind"] == UNDERGROUND, "down": false, "up": false, "fluid": object["kind"] in FLUID_CARRIERS}
		elif INSERTER_SWINGS.has(object["kind"]):
			var old: Dictionary = old_inserters.get(object["id"], {})
			inserters[cell] = {"id": object["id"], "rotation": rotation, "hand": old.get("hand"), "swing": int(old.get("swing", 0)),
				"was": int(old.get("swing", 0)), "arm": old.get("arm"), "swingTicks": int(INSERTER_SWINGS[object["kind"]]),
				"suffix": tier_suffix(object["kind"]), "speed": float(old.get("speed", 1.0)), "charge": float(old.get("charge", 0.0)),
				"reach": int(INSERTER_REACH.get(object["kind"], 1)), "count": int(old.get("count", 1))}
	_drone_ports = {}
	for cell: Vector2i in placed:
		if placed[cell]["kind"] == DRONE_PORT:
			_drone_ports[cell] = placed[cell]["id"]
	var kept := {}
	for cell: Vector2i in inserters:
		if inserters[cell]["arm"] != null:
			kept[inserters[cell]["arm"]] = true
	for cell: Vector2i in _inserters:
		var old_arm: Variant = _inserters[cell]["arm"]
		if old_arm != null and not kept.has(old_arm):
			(old_arm as Node).queue_free()
	_belts = belts
	_inserters = inserters
	for cell: Vector2i in _inserters:
		var inserter: Dictionary = _inserters[cell]
		if inserter["arm"] == null:
			inserter["arm"] = InserterArm.new(self, cell)
			arms_parent.add_child(inserter["arm"])
		var arm: InserterArm = inserter["arm"]
		arm.cell = cell
		arm.position = (Vector2(cell) + Vector2(0.5, 0.5)) * tile + Vector2(0, 1)
	_link_belts()
	if _cables == null and arms_parent != null:
		_cables = CableLines.new(self)
		arms_parent.add_child(_cables)
		_drones = DroneFlights.new(self)
		arms_parent.add_child(_drones)
	queue_redraw()


## Applies an answer to "logistics.get": the machinery as the server worked it out.
func apply(state: Dictionary) -> void:
	tick_ms = float(state.get("tickMs", tick_ms))
	belt_slots = int(state.get("beltSlots", belt_slots))
	belt_lanes = int(state.get("beltLanes", belt_lanes))
	swing_ticks = int(state.get("swingTicks", swing_ticks))
	if state.get("names") != null:
		names = state["names"]
	# The short form lists only belts that carry something (and splitters): any other is empty.
	var compact: bool = state.get("compact", false)
	var belts_by_id := {}
	for belt: Dictionary in state.get("belts", []):
		belts_by_id[belt["id"]] = belt
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		if compact and not belts_by_id.has(belt["id"]):
			if (belt["items"] as Array).any(func(item: Variant) -> bool: return item != null):
				belt["items"] = []
				belt["items"].resize(belt_slots * belt_lanes)
			belt["moved"] = {}
		elif belts_by_id.has(belt["id"]):
			var known: Dictionary = belts_by_id[belt["id"]]
			belt["items"] = (known["items"] as Array).duplicate()
			belt["items"].resize(belt_slots * belt_lanes)
			belt["moved"] = {}
			belt["filter"] = known.get("filter") if known.get("filter") != null else []
			belt["filterSide"] = int(known.get("filterSide", 0))
			belt["turn"] = int(known.get("turn", 0))
	var inserters_by_id := {}
	for inserter: Dictionary in state.get("inserters", []):
		inserters_by_id[inserter["id"]] = inserter
	for cell: Vector2i in _inserters:
		var inserter: Dictionary = _inserters[cell]
		if inserters_by_id.has(inserter["id"]):
			inserter["hand"] = inserters_by_id[inserter["id"]].get("hand")
			inserter["swing"] = int(inserters_by_id[inserter["id"]]["swing"])
			inserter["swingTicks"] = int(inserters_by_id[inserter["id"]].get("swingTicks", inserter["swingTicks"]))
			inserter["was"] = inserter["swing"]
			inserter["speed"] = float(inserters_by_id[inserter["id"]].get("speed", 1.0))
			inserter["charge"] = float(inserters_by_id[inserter["id"]].get("charge", 0.0))
			inserter["count"] = int(inserters_by_id[inserter["id"]].get("count", 1))
	_storages = {}
	for summary: Dictionary in state.get("storages", []):
		_storages[summary["id"]] = summary
	_filters = {}
	for f: Dictionary in state.get("filters", []):
		_filters[f["id"]] = f["item"]
	_drone_speeds = {}
	for port: Dictionary in state.get("drones", []):
		_drone_speeds[port["id"]] = float(port.get("speed", 0.0))
	filters_changed.emit()
	_time = float(state["simulatedAt"])
	queue_redraw()


func _find(by_cell: Dictionary, id: String) -> Dictionary:
	for cell: Vector2i in by_cell:
		if by_cell[cell]["id"] == id:
			return by_cell[cell]
	return {}


## Belts or inserters by object id.
static func _by_id(by_cell: Dictionary) -> Dictionary:
	var found := {}
	for cell: Vector2i in by_cell:
		found[by_cell[cell]["id"]] = by_cell[cell]
	return found


## What of the plot is on the screen, in the plot's own coordinates, with a margin of a few tiles around for
## what stands up from the tiles below it and for the camera moving on before the next frame.
static func view_rect(item: CanvasItem, margin := VIEW_MARGIN) -> Rect2:
	var view := item.get_canvas_transform().affine_inverse() * item.get_viewport_rect()
	return view.grow(margin)


## The tiles of `cells` (by tile) inside `view`: looked up tile by tile when the screen holds fewer tiles than there
## are cells, so drawing a big factory costs what is on the screen, not what is on the plot.
func _on_screen(cells: Dictionary, view: Rect2) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var low := Vector2i((view.position / tile).floor())
	var high := Vector2i((view.end / tile).ceil())
	if (high.x - low.x) * (high.y - low.y) < cells.size():
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				if cells.has(Vector2i(x, y)):
					found.append(Vector2i(x, y))
	else:
		var tiles := Rect2i(low, high - low)
		for cell: Vector2i in cells:
			if tiles.has_point(cell):
				found.append(cell)
	return found


static func facing(rotation: int) -> Vector2i:
	return [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][rotation & 3]


## The tile on the left of something going the way a rotation faces.
static func left_of(rotation: int) -> Vector2i:
	var f := facing(rotation)
	return Vector2i(f.y, -f.x)


## Which side a belt turns in from: -1 when the only belt feeding it comes from its left, 1 from its
## right, 0 when it runs straight. Splitters neither turn nor make a belt turn.
func _bend(cell: Vector2i) -> int:
	var belt: Dictionary = _belts[cell]
	if belt["splitter"] or belt["tunnel"]:
		return 0
	# An underground belt going down feeds no belt in front of it, only the one it comes up at.
	var feeds := func(from: Vector2i) -> bool:
		var other: Dictionary = _belts.get(cell + from, {})
		return not other.is_empty() and not other["splitter"] and not other["down"] and other["fluid"] == belt["fluid"] \
			and facing(other["rotation"]) == -from
	var left := left_of(belt["rotation"])
	var from_left: bool = feeds.call(left)
	var from_right: bool = feeds.call(-left)
	if feeds.call(-facing(belt["rotation"])) or from_left == from_right:
		return 0
	return -1 if from_left else 1


## How items leave the belt at a tile towards a side: { to, into (lane by lane), entry }, or {}.
func _connect(cell: Vector2i, way: Vector2i) -> Dictionary:
	var target := cell + way
	if not _belts.has(target):
		return {}
	var next: Dictionary = _belts[target]
	var next_facing := facing(next["rotation"])
	if next_facing == -way or next["fluid"] != _belts[cell]["fluid"]:
		return {}
	if next_facing == way or int(next["bend"]) != 0:
		return {"to": target, "into": [0, 1], "entry": 0}
	var near := 0 if left_of(next["rotation"]) == -way else 1
	return {"to": target, "into": [near, near], "entry": 1}


## Where each belt sends its items and the order to move them in: as on the server.
func _link_belts() -> void:
	_tunnels = _tunnel_links()
	for cell: Vector2i in _tunnels:
		_belts[cell]["down"] = true
		_belts[_tunnels[cell]]["up"] = true
	for cell: Vector2i in _belts:
		_belts[cell]["bend"] = _bend(cell)
	# A splitter or an underground belt going down keeps up with the belt behind it, the one coming up
	# with the one going down; over and over, as one may feed the next, until nothing changes.
	for pass_number in _belts.size() + 1:
		var changed := false
		for cell: Vector2i in _belts:
			var belt: Dictionary = _belts[cell]
			if not belt["splitter"] and not (belt["tunnel"] and not belt["up"]):
				continue
			var feeder: Dictionary = _belts.get(cell - facing(belt["rotation"]), {})
			if not feeder.is_empty() and not feeder["splitter"] and feeder["rotation"] == belt["rotation"] and int(feeder["speed"]) != int(belt["speed"]):
				belt["speed"] = int(feeder["speed"])
				changed = true
		for cell: Vector2i in _tunnels:
			var up: Dictionary = _belts[_tunnels[cell]]
			changed = changed or int(up["speed"]) != int(_belts[cell]["speed"])
			up["speed"] = int(_belts[cell]["speed"])
		if not changed:
			break
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		var cable := _cable_target(cell)
		if cable.x > -9999:
			# Over the cable onto the start of the station ahead.
			belt["out"] = [{"to": cable, "into": [0, 1], "entry": 0, "cable": true}]
		elif _tunnels.has(cell):
			# Under the ground onto the start of the one coming up.
			belt["out"] = [{"to": _tunnels[cell], "into": [0, 1], "entry": 0, "tunnel": true}]
		elif belt["splitter"]:
			var left := left_of(belt["rotation"])
			belt["out"] = [_connect(cell, left), _connect(cell, -left)]
		else:
			belt["out"] = [_connect(cell, facing(belt["rotation"]))]
	_order = []
	var seen := {}
	for start: Vector2i in _belts:
		_downstream(start, seen)
	_cable_starts = []
	for cell: Vector2i in _belts:
		var out: Array = _belts[cell]["out"]
		if not out.is_empty() and not out[0].is_empty() and out[0].get("cable", false):
			_cable_starts.append(cell)


## The station a cable station sends its items to: the nearest one (of either level) ahead facing the
## same way, at least two tiles off and within its span; (-9999, -9999) when there is none (it then
## passes items on like a belt).
func _cable_target(cell: Vector2i) -> Vector2i:
	var belt: Dictionary = _belts[cell]
	if not belt.get("cable", false):
		return Vector2i(-9999, -9999)
	var way := facing(belt["rotation"])
	for d in range(2, int(belt["span"]) + 1):
		var other: Dictionary = _belts.get(cell + way * d, {})
		if not other.is_empty() and other.get("cable", false) and int(other["rotation"]) == int(belt["rotation"]):
			return cell + way * d
	return Vector2i(-9999, -9999)


## Which underground belt brings up what each one going down takes under: the nearest ahead facing the
## same way, up to TUNNEL_SPAN tiles on; along a line they pair up from the back, as on the server.
func _tunnel_links() -> Dictionary:
	var tunnels: Array[Vector2i] = []
	for cell: Vector2i in _belts:
		if _belts[cell]["tunnel"]:
			tunnels.append(cell)
	tunnels.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var fa := facing(_belts[a]["rotation"])
		var fb := facing(_belts[b]["rotation"])
		return fa.x * a.x + fa.y * a.y < fb.x * b.x + fb.y * b.y)
	var links := {}
	var exits := {}
	for cell in tunnels:
		if exits.has(cell):
			continue
		var rotation := int(_belts[cell]["rotation"])
		for d in range(1, TUNNEL_SPAN + 1):
			var other: Dictionary = _belts.get(cell + facing(rotation) * d, {})
			if not other.is_empty() and other["tunnel"] and int(other["rotation"]) == rotation:
				links[cell] = cell + facing(rotation) * d
				exits[cell + facing(rotation) * d] = true
				break
	return links


func _downstream(cell: Vector2i, seen: Dictionary) -> void:
	if seen.has(cell):
		return
	seen[cell] = true
	for link: Dictionary in _belts[cell]["out"]:
		if not link.is_empty():
			_downstream(link["to"], seen)
	_order.append(cell)


func _process(_delta: float) -> void:
	if not has_machinery() or _time <= 0.0:
		return
	var now: float = server_now.call()
	# Never run far ahead of the server: it may know of an inserter that picked something up.
	var steps := 0
	while now - _time >= tick_ms and steps < 10:
		_step()
		_time += tick_ms
		steps += 1
	if now - _time >= tick_ms:
		_time = now - fmod(now - _time, tick_ms)
	queue_redraw()
	if _cables != null:
		_cables.queue_redraw()
		_drones.queue_redraw()
	# An arm off the screen keeps what it drew last; it is drawn anew once it is on the screen again.
	for cell in _on_screen(_inserters, view_rect(self)):
		_inserters[cell]["arm"].queue_redraw()


## One tick: belts move their items forward, inserter arms swing (slower short of power, not at
## all without, as on the server); picking up and dropping is left to the server.
func _step() -> void:
	var phases := 0
	for cell in _order:
		_belts[cell]["moved"] = {}
		phases = maxi(phases, int(_belts[cell]["speed"]))
	# Each turn of a tick, the belts fast enough move their items one place on, downstream first.
	for phase in phases:
		for cell in _order:
			var belt: Dictionary = _belts[cell]
			if int(belt["speed"]) <= phase:
				continue
			var items: Array = belt["items"]
			var moved: Dictionary = belt["moved"]
			for lane in belt_lanes:
				var start := lane * belt_slots
				var end := start + belt_slots - 1
				if items[end] != null and _pass(belt, lane, items[end], int(moved.get(end, 0)) + 1):
					items[end] = null
					moved.erase(end)
				for i in range(end - 1, start - 1, -1):
					if items[i] != null and items[i + 1] == null:
						items[i + 1] = items[i]
						items[i] = null
						moved[i + 1] = int(moved.get(i, 0)) + 1
						moved.erase(i)
	for cell: Vector2i in _inserters:
		var inserter: Dictionary = _inserters[cell]
		inserter["was"] = inserter["swing"]
		var speed := float(inserter["speed"])
		if speed <= 0.0:
			continue
		if speed < 1.0:
			inserter["charge"] = minf(float(inserter["charge"]), 1.0) + speed
			if float(inserter["charge"]) < 1.0:
				continue
			inserter["charge"] = float(inserter["charge"]) - 1.0
		if inserter["hand"] != null and int(inserter["swing"]) < int(inserter["swingTicks"]):
			inserter["swing"] = int(inserter["swing"]) + 1
		elif inserter["hand"] == null and int(inserter["swing"]) > 0:
			inserter["swing"] = int(inserter["swing"]) - 1


## Puts the item at the end of a lane on the belt it goes on to, when there is room: a splitter
## sends items left and right in turn, or filtered ones one way and the rest the other. `moved` is
## how many places it has gone this tick, counting this one, for drawing it on its way.
func _pass(belt: Dictionary, lane: int, item: String, moved: int) -> bool:
	var ways: Array = [0]
	if belt["splitter"]:
		var side := int(belt["filterSide"])
		if not (belt["filter"] as Array).is_empty():
			ways = [side if item in belt["filter"] else 1 - side]
		else:
			ways = [int(belt["turn"]), 1 - int(belt["turn"])]
	for way: int in ways:
		var link: Dictionary = belt["out"][way]
		if link.is_empty():
			continue
		var next: Dictionary = _belts[link["to"]]
		var at: int = int(link["into"][lane]) * belt_slots + int(link["entry"])
		if next["items"][at] == null:
			next["items"][at] = item
			next["moved"][at] = moved
			if belt["splitter"]:
				belt["turn"] = 1 - way
			return true
	return false


## How far into the current tick the clock is, 0 to 1.
func _fraction() -> float:
	return clampf((float(server_now.call()) - _time) / tick_ms, 0.0, 1.0)


func _screen(cell: Vector2i, along: Vector2, height: float) -> Vector2:
	var p := (Vector2(cell) + Vector2(0.5, 0.5) + along) * tile
	return p - Vector2(0, height * PPM * cos(PI / 4))


func _icon(item: String) -> Texture2D:
	if not _icons.has(item):
		_icons[item] = UI.item_texture(item)
	return _icons[item]


## A point on the belt at a tile, `along` (0 where items come on to 1 where they leave) its lanes,
## `lateral` tiles to the left of the way it runs; and the way it runs there.
func _belt_point(cell: Vector2i, along: float, lateral: float) -> Array:
	var belt: Dictionary = _belts[cell]
	var dir := Vector2(facing(belt["rotation"]))
	var bend := int(belt["bend"])
	var at: Vector2
	var way := dir
	if bend == 0:
		# A splitter's lanes end in its middle, where items go off to the sides.
		var length := 0.55 if belt["splitter"] else 1.0
		at = dir * (along * length - 0.5)
	else:
		# Round a quarter circle about the corner between the side it comes in from and the way out.
		var side := Vector2(left_of(belt["rotation"])) * (1 if bend < 0 else -1)
		var corner := (side + dir) * 0.5
		var a := along * PI / 2
		var e := -dir * 0.5
		var x := -side * 0.5
		at = corner + e * cos(a) + x * sin(a)
		way = (-e * sin(a) + x * cos(a)).normalized()
	var left := Vector2(way.y, -way.x)
	return [at + left * lateral, way]


func _belt_sprite(belt: Dictionary) -> String:
	var bend := int(belt["bend"])
	if bend == 0:
		return BELT_SPRITES[int(belt["rotation"]) & 3]
	var side := left_of(belt["rotation"]) * (1 if bend < 0 else -1)
	var compass := {Vector2i(0, -1): "n", Vector2i(1, 0): "e", Vector2i(0, 1): "s", Vector2i(-1, 0): "w"}
	var pair: Array = [compass[side], compass[facing(belt["rotation"])]]
	for key: String in CURVE_SPRITES:
		if pair[0] in key and pair[1] in key:
			return CURVE_SPRITES[key]
	return BELT_SPRITES[int(belt["rotation"]) & 3]


func _draw() -> void:
	var f := _fraction()
	var shown := _on_screen(_belts, view_rect(self))
	for cell: Vector2i in shown:
		var belt: Dictionary = _belts[cell]
		var sprites: Array = [_belt_sprite(belt) + ("" if belt["splitter"] else String(belt["suffix"]))]
		if belt["splitter"]:
			# Crossed by a belt from side to side, where the items go out.
			sprites.append(BELT_SPRITES[(int(belt["rotation"]) + 1) & 3])
		for sprite: String in sprites:
			var anchor := Vector2(layout[sprite]["anchorX"], layout[sprite]["anchorY"])
			draw_texture(_textures[sprite], (Vector2(cell) + Vector2(0.5, 0.5)) * tile - anchor)
	# Chevrons pointing the way the band runs, moving as many slots a tick as the belt is fast.
	for cell: Vector2i in shown:
		if _belts[cell]["fluid"]:
			continue  # a pipe is closed
		var phase := fmod(float(server_now.call()) / tick_ms * int(_belts[cell]["speed"]), 1.0)
		for k in belt_slots:
			var s := (k + phase) / belt_slots
			if s > 0.92 or s < 0.02:
				continue
			var tip: Array = _belt_point(cell, s + 0.05, 0.0)
			var back: Array = _belt_point(cell, s, 0.0)
			var side := Vector2(back[1].y, -back[1].x) * 0.2
			draw_polyline([_screen(cell, back[0] + side, BAND_HEIGHT), _screen(cell, tip[0], BAND_HEIGHT),
				_screen(cell, back[0] - side, BAND_HEIGHT)], STRIPE, 2.0, true)
	for cell: Vector2i in shown:
		var belt: Dictionary = _belts[cell]
		var items: Array = belt["items"]
		for i in items.size():
			if items[i] == null:
				continue
			var lane := 0 if i < belt_slots else 1
			var at := (i % belt_slots + 0.5) / belt_slots
			if belt["moved"].has(i) and (_came_by_cable(cell, i) or _came_by_tunnel(cell, i)):
				# Just off the cable: it rides the gondola, drawn with the cable; or still under the ground.
				continue
			if belt["moved"].has(i):
				at -= (1.0 - f) * int(belt["moved"][i]) / belt_slots
			var point: Array = _belt_point(cell, at, LANE_OFFSET if lane == 0 else -LANE_OFFSET)
			var p := _screen(cell, point[0], BAND_HEIGHT)
			draw_texture_rect(_icon(items[i]), Rect2(p - Vector2(ITEM_SIZE / 2, ITEM_SIZE * 0.8), Vector2(ITEM_SIZE, ITEM_SIZE)), false)


## Whether the item at place `i` of the belt at `cell` came on this tick over a cable.
func _came_by_cable(cell: Vector2i, i: int) -> bool:
	if i % belt_slots != 0:
		return false
	var belt: Dictionary = _belts[cell]
	if not belt.get("cable", false) or int(belt["moved"][i]) > i % belt_slots + 1:
		return false
	return _came_from_afar(cell)


## Whether the item at place `i` of an underground belt coming up came out of the tunnel this tick:
## it shows only once it is out.
func _came_by_tunnel(cell: Vector2i, i: int) -> bool:
	return i % belt_slots == 0 and _belts[cell].get("up", false) and _came_from_afar(cell)


## Whether what comes onto the start of the belt at `cell` comes from further than the tile behind it.
func _came_from_afar(cell: Vector2i) -> bool:
	var belt: Dictionary = _belts[cell]
	var behind: Dictionary = _belts.get(cell - facing(belt["rotation"]), {})
	return behind.is_empty() or behind.get("out", [{}])[0].get("to", Vector2i(-9999, -9999)) != cell


## The cables between stations, high above the plot, with gondolas running along them and the items
## that ride over this tick. A node of its own so it is drawn above everything standing on the plot.
class CableLines extends Node2D:
	var logistics: PlotLogistics

	func _init(owner_node: PlotLogistics) -> void:
		logistics = owner_node
		z_index = 20

	func _draw() -> void:
		var t := logistics.tile
		var lift := PlotLogistics.CABLE_HEIGHT * PlotLogistics.PPM * cos(PI / 4)
		var f := logistics._fraction()
		var now: float = logistics.server_now.call()
		var view := PlotLogistics.view_rect(self)
		for cell: Vector2i in logistics._cable_starts:
			var belt: Dictionary = logistics._belts[cell]
			var to: Vector2i = belt["out"][0]["to"]
			if not view.intersects(Rect2(Vector2(cell) * t, Vector2.ZERO).expand((Vector2(to) + Vector2.ONE) * t)):
				continue
			var dir := Vector2(PlotLogistics.facing(belt["rotation"]))
			var side := Vector2(-dir.y, dir.x) * 0.18
			var from_px := (Vector2(cell) + Vector2(0.5, 0.5)) * t - Vector2(0, lift)
			var to_px := (Vector2(to) + Vector2(0.5, 0.5)) * t - Vector2(0, lift)
			var sag := Vector2(0, minf(18.0, from_px.distance_to(to_px) * 0.04))
			# Two ropes, one each way, hanging a little in the middle.
			for s: float in [1.0, -1.0]:
				var offset := side * t * s
				var points: PackedVector2Array = []
				for k in 13:
					var u := k / 12.0
					points.append(from_px.lerp(to_px, u) + offset + sag * 4.0 * u * (1.0 - u))
				draw_polyline(points, PlotLogistics.CABLE_COLOR, 2.0, true)
			# Gondolas go round, out along the left rope and back along the right one.
			var length := maxf(1.0, from_px.distance_to(to_px) / t.x)
			var turn := fmod(now / 4000.0 / length * 3.0, 1.0)
			for g in 3:
				var u := fmod(turn + g / 3.0, 1.0)
				var s := 1.0 if u < 0.5 else -1.0
				var v := u * 2.0 if u < 0.5 else (1.0 - u) * 2.0
				var p := from_px.lerp(to_px, v) + side * t * s + sag * 4.0 * v * (1.0 - v)
				draw_line(p, p + Vector2(0, 7), PlotLogistics.CABLE_COLOR, 1.5)
				draw_rect(Rect2(p + Vector2(-6, 7), Vector2(12, 8)), PlotLogistics.GONDOLA_COLORS.get(belt["suffix"], PlotLogistics.GONDOLA_COLOR))
			# What came over this tick rides down the cable to the station ahead.
			var next: Dictionary = logistics._belts.get(to, {})
			if next.is_empty():
				continue
			for lane in logistics.belt_lanes:
				var at := lane * logistics.belt_slots
				var item: Variant = next["items"][at]
				if item != null and next["moved"].has(at) and logistics._came_by_cable(to, at):
					var p := from_px.lerp(to_px, f) + sag * 4.0 * f * (1.0 - f) + Vector2(0, 9)
					var size := PlotLogistics.ITEM_SIZE
					draw_texture_rect(logistics._icon(item), Rect2(p - Vector2(size / 2, size * 0.8), Vector2(size, size)), false)


## The arm of one inserter, a node of its own so it is drawn in front of or behind what stands near.
class InserterArm extends Node2D:
	var logistics: PlotLogistics
	var cell := Vector2i.ZERO

	func _init(owner_node: PlotLogistics, at: Vector2i) -> void:
		logistics = owner_node
		cell = at

	func _draw() -> void:
		var inserter: Dictionary = logistics._inserters.get(cell, {})
		if inserter.is_empty():
			return
		var f := logistics._fraction()
		if inserter["suffix"] == "_pump":
			# A pump has no arm: what it moves shows over it while it flows through.
			var flowing: Variant = inserter.get("hand")
			if flowing != null:
				var lift_px := PlotLogistics.PPM * cos(PI / 4)
				var size := PlotLogistics.ITEM_SIZE
				draw_texture_rect(logistics._icon(flowing), Rect2(Vector2(-size / 2, -1.1 * lift_px - size), Vector2(size, size)), false)
			return
		var swing := lerpf(float(inserter["was"]), float(inserter["swing"]), f) / maxf(int(inserter["swingTicks"]), 1)
		var dir := Vector2(PlotLogistics.facing(inserter["rotation"]))
		var side := Vector2(-dir.y, dir.x)
		# From the tile behind (swing 0) round the side to the tile in front (swing 1).
		var angle := swing * PI
		# A long arm reaches a tile further.
		var reach := (-dir * cos(angle) + side * sin(angle)) * (0.78 + int(inserter.get("reach", 1)) - 1)
		var t := logistics.tile
		var lift := PlotLogistics.PPM * cos(PI / 4)
		var shoulder := Vector2(0, -1 - PlotLogistics.SHOULDER_HEIGHT * lift)
		var hand := Vector2(reach.x * t.x, reach.y * t.y - 1 - 0.36 * lift)
		var elbow := (shoulder + hand) / 2 - Vector2(0, 7)
		var paint: Color = PlotLogistics.ARM_COLORS.get(inserter["suffix"], PlotLogistics.ARM_COLOR)
		for pass_color: Color in [PlotLogistics.ARM_DARK, paint]:
			var width := 7.0 if pass_color == PlotLogistics.ARM_DARK else 4.0
			draw_polyline([shoulder, elbow, hand], pass_color, width, true)
		draw_circle(shoulder, 3.5, PlotLogistics.ARM_DARK)
		draw_rect(Rect2(hand - Vector2(5, 3), Vector2(10, 6)), Color("#55585c"))
		var held: Variant = inserter.get("hand")
		if held != null:
			var size := PlotLogistics.ITEM_SIZE
			draw_texture_rect(logistics._icon(held), Rect2(hand - Vector2(size / 2, size * 0.75), Vector2(size, size)), false)
			if int(inserter.get("count", 1)) > 1:
				# Bigger grippers: how many pieces it carries.
				var font := ThemeDB.fallback_font
				var text := "×%d" % int(inserter["count"])
				draw_string_outline(font, hand + Vector2(size / 2 - 2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.8))
				draw_string(font, hand + Vector2(size / 2 - 2, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## Drones flying between drone ports, high over the plot: from each port without a filter to every
## port set to take something it holds, there and back, with the item hanging under them on the way
## there. A node of its own so it is drawn above everything standing on the plot.
class DroneFlights extends Node2D:
	var logistics: PlotLogistics

	func _init(owner_node: PlotLogistics) -> void:
		logistics = owner_node
		z_index = 21

	func _draw() -> void:
		var t := logistics.tile
		var lift := PlotLogistics.DRONE_HEIGHT * PlotLogistics.PPM * cos(PI / 4)
		var now: float = logistics.server_now.call()
		for from: Vector2i in logistics._drone_ports:
			var sender: String = logistics._drone_ports[from]
			if logistics._filters.has(sender) or float(logistics._drone_speeds.get(sender, 0.0)) <= 0.0:
				continue
			var held := {}
			for stack: Dictionary in logistics.storage(sender).get("items", []):
				held[stack["id"]] = true
			for to: Vector2i in logistics._drone_ports:
				var receiver: String = logistics._drone_ports[to]
				var wanted: String = logistics._filters.get(receiver, "")
				if to == from or wanted == "" or not held.has(wanted) or float(logistics._drone_speeds.get(receiver, 0.0)) <= 0.0:
					continue
				var a := (Vector2(from) + Vector2(0.5, 0.5)) * t - Vector2(0, lift)
				var b := (Vector2(to) + Vector2(0.5, 0.5)) * t - Vector2(0, lift)
				var trip := maxf(Vector2(from).distance_to(Vector2(to)), 1.0) * PlotLogistics.DRONE_TILE_MS
				# Two drones on each route, half a round apart: out loaded, back empty.
				for k in 2:
					var u := fmod(now / (2.0 * trip) + k * 0.5 + float(absi(from.x * 7 + to.y * 13) % 10) / 10.0, 1.0)
					var going := u < 0.5
					var v := u * 2.0 if going else (1.0 - u) * 2.0
					# Up off the pad, along, and down onto the other one.
					var rise := minf(1.0, minf(v, 1.0 - v) * 8.0)
					var p := a.lerp(b, v) + Vector2(0, lift * (1.0 - rise) * 0.6)
					_drone(p, logistics._icon(wanted) if going else null, now)

	func _drone(at: Vector2, carrying: Texture2D, now: float) -> void:
		var body := Color("#2f3338")
		if carrying != null:
			var size := PlotLogistics.ITEM_SIZE * 0.8
			draw_line(at, at + Vector2(0, 6), body, 1.0)
			draw_texture_rect(carrying, Rect2(at + Vector2(-size / 2, 5), Vector2(size, size)), false)
		# Its shadow far below would be lost among the machines; four rotors whirring round a body.
		for corner: Vector2 in [Vector2(-7, -3), Vector2(7, -3), Vector2(-7, 3), Vector2(7, 3)]:
			draw_line(at, at + corner, body, 2.0, true)
			var spin := fmod(now / 40.0, TAU)
			draw_arc(at + corner, 4.0, spin, spin + PI * 1.4, 8, Color(0.85, 0.88, 0.9, 0.55), 1.2, true)
		draw_rect(Rect2(at - Vector2(4, 2.5), Vector2(8, 5)), body)
		draw_circle(at + Vector2(0, -0.5), 1.4, Color("#5ad04a"))
