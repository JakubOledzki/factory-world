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

const BELT := "logistics_belt"
const INSERTER := "logistics_inserter"
const SPLITTER := "logistics_splitter"
## Places a tick an item moves along a belt of each level, and ticks an inserter's arm takes to swing one way.
const BELT_SPEEDS := {"logistics_belt": 1, "logistics_fast_belt": 2, "logistics_express_belt": 3}
const INSERTER_SWINGS := {"logistics_inserter": 4, "logistics_fast_inserter": 2, "logistics_express_inserter": 1}
## Sprites of upgraded belts and inserters end in the level's name.
const TIER_SUFFIXES := {"logistics_fast_belt": "_fast", "logistics_express_belt": "_express",
	"logistics_fast_inserter": "_fast", "logistics_express_inserter": "_express"}
const ARM_COLORS := {"": Color("#d9a21c"), "_fast": Color("#c8321e"), "_express": Color("#2c62c8")}
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
## Storage summaries from the last answer, by object id.
var _storages := {}
## Server time (ms) of the last tick worked out here.
var _time := 0.0
var _textures := {}
var _icons := {}


func _ready() -> void:
	for sprite: String in ["belt_ns", "belt_ew"] + CURVE_SPRITES.values():
		for suffix: String in ["", "_fast", "_express"]:
			_textures[sprite + suffix] = load("res://art/plot/%s%s.png" % [sprite, suffix])


## "_fast" or "_express" for upgraded belts and inserters, whose sprites end so; "" for the rest.
static func tier_suffix(kind: String) -> String:
	return TIER_SUFFIXES.get(kind, "")


func has_machinery() -> bool:
	return not _belts.is_empty() or not _inserters.is_empty()


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


## Takes the objects standing on the plot (tile → { id, kind, rotation }); belts and inserters
## that were there before keep what they carry.
func set_objects(placed: Dictionary) -> void:
	var belts := {}
	var inserters := {}
	for cell: Vector2i in placed:
		var object: Dictionary = placed[cell]
		var rotation := int(object.get("rotation", 0))
		if BELT_SPEEDS.has(object["kind"]) or object["kind"] == SPLITTER:
			var old: Dictionary = _find(_belts, object["id"])
			var items: Array = old.get("items", [])
			if items.size() != belt_slots * belt_lanes:
				items = []
				items.resize(belt_slots * belt_lanes)
			belts[cell] = {"id": object["id"], "rotation": rotation, "items": items, "moved": {}, "out": [], "bend": 0,
				"splitter": object["kind"] == SPLITTER, "filter": old.get("filter", []), "filterSide": int(old.get("filterSide", 0)),
				"turn": int(old.get("turn", 0)), "speed": int(BELT_SPEEDS.get(object["kind"], 1)), "suffix": tier_suffix(object["kind"])}
		elif INSERTER_SWINGS.has(object["kind"]):
			var old: Dictionary = _find(_inserters, object["id"])
			inserters[cell] = {"id": object["id"], "rotation": rotation, "hand": old.get("hand"), "swing": int(old.get("swing", 0)),
				"was": int(old.get("swing", 0)), "arm": old.get("arm"), "swingTicks": int(INSERTER_SWINGS[object["kind"]]),
				"suffix": tier_suffix(object["kind"]), "speed": float(old.get("speed", 1.0)), "charge": float(old.get("charge", 0.0))}
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
	queue_redraw()


## Applies an answer to "logistics.get": the machinery as the server worked it out.
func apply(state: Dictionary) -> void:
	tick_ms = float(state.get("tickMs", tick_ms))
	belt_slots = int(state.get("beltSlots", belt_slots))
	belt_lanes = int(state.get("beltLanes", belt_lanes))
	swing_ticks = int(state.get("swingTicks", swing_ticks))
	if state.get("names") != null:
		names = state["names"]
	var belts_by_id := {}
	for belt: Dictionary in state.get("belts", []):
		belts_by_id[belt["id"]] = belt
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		if belts_by_id.has(belt["id"]):
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
			inserter["hand"] = inserters_by_id[inserter["id"]]["hand"]
			inserter["swing"] = int(inserters_by_id[inserter["id"]]["swing"])
			inserter["swingTicks"] = int(inserters_by_id[inserter["id"]].get("swingTicks", inserter["swingTicks"]))
			inserter["was"] = inserter["swing"]
			inserter["speed"] = float(inserters_by_id[inserter["id"]].get("speed", 1.0))
			inserter["charge"] = float(inserters_by_id[inserter["id"]].get("charge", 0.0))
	_storages = {}
	for summary: Dictionary in state.get("storages", []):
		_storages[summary["id"]] = summary
	_time = float(state["simulatedAt"])
	queue_redraw()


func _find(by_cell: Dictionary, id: String) -> Dictionary:
	for cell: Vector2i in by_cell:
		if by_cell[cell]["id"] == id:
			return by_cell[cell]
	return {}


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
	if belt["splitter"]:
		return 0
	var feeds := func(from: Vector2i) -> bool:
		var other: Dictionary = _belts.get(cell + from, {})
		return not other.is_empty() and not other["splitter"] and facing(other["rotation"]) == -from
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
	if next_facing == -way:
		return {}
	if next_facing == way or int(next["bend"]) != 0:
		return {"to": target, "into": [0, 1], "entry": 0}
	var near := 0 if left_of(next["rotation"]) == -way else 1
	return {"to": target, "into": [near, near], "entry": 1}


## Where each belt sends its items and the order to move them in: as on the server.
func _link_belts() -> void:
	for cell: Vector2i in _belts:
		_belts[cell]["bend"] = _bend(cell)
		var belt: Dictionary = _belts[cell]
		if belt["splitter"]:
			# A splitter keeps up with the belt behind it.
			var feeder: Dictionary = _belts.get(cell - facing(belt["rotation"]), {})
			belt["speed"] = int(feeder["speed"]) if not feeder.is_empty() and not feeder["splitter"] and feeder["rotation"] == belt["rotation"] else 1
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		if belt["splitter"]:
			var left := left_of(belt["rotation"])
			belt["out"] = [_connect(cell, left), _connect(cell, -left)]
		else:
			belt["out"] = [_connect(cell, facing(belt["rotation"]))]
	_order = []
	var seen := {}
	for start: Vector2i in _belts:
		_downstream(start, seen)


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
	for cell: Vector2i in _inserters:
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
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		var sprites: Array = [_belt_sprite(belt) + ("" if belt["splitter"] else String(belt["suffix"]))]
		if belt["splitter"]:
			# Crossed by a belt from side to side, where the items go out.
			sprites.append(BELT_SPRITES[(int(belt["rotation"]) + 1) & 3])
		for sprite: String in sprites:
			var anchor := Vector2(layout[sprite]["anchorX"], layout[sprite]["anchorY"])
			draw_texture(_textures[sprite], (Vector2(cell) + Vector2(0.5, 0.5)) * tile - anchor)
	# Chevrons pointing the way the band runs, moving as many slots a tick as the belt is fast.
	for cell: Vector2i in _belts:
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
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		var items: Array = belt["items"]
		for i in items.size():
			if items[i] == null:
				continue
			var lane := 0 if i < belt_slots else 1
			var at := (i % belt_slots + 0.5) / belt_slots
			if belt["moved"].has(i):
				at -= (1.0 - f) * int(belt["moved"][i]) / belt_slots
			var point: Array = _belt_point(cell, at, LANE_OFFSET if lane == 0 else -LANE_OFFSET)
			var p := _screen(cell, point[0], BAND_HEIGHT)
			draw_texture_rect(_icon(items[i]), Rect2(p - Vector2(ITEM_SIZE / 2, ITEM_SIZE * 0.8), Vector2(ITEM_SIZE, ITEM_SIZE)), false)


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
		var swing := lerpf(float(inserter["was"]), float(inserter["swing"]), f) / maxf(int(inserter["swingTicks"]), 1)
		var dir := Vector2(PlotLogistics.facing(inserter["rotation"]))
		var side := Vector2(-dir.y, dir.x)
		# From the tile behind (swing 0) round the side to the tile in front (swing 1).
		var angle := swing * PI
		var reach := (-dir * cos(angle) + side * sin(angle)) * 0.78
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
