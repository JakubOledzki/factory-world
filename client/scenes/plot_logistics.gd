class_name PlotLogistics
extends Node2D
## The belts and inserters of a plot. Belts lie flat on the ground (they can be walked over) with
## stripes running along them and the items they carry; inserters stand on their tiles and swing an
## arm from the tile behind them to the tile in front.
## The server works the machinery out in ticks; between its answers the same rules run here, so
## items glide along the belts instead of jumping once a second.

const BELT := "logistics_belt"
const INSERTER := "logistics_inserter"
## Belt sprites by rotation: south and north run up and down the screen, east and west across.
const BELT_SPRITES := ["belt_ns", "belt_ew", "belt_ns", "belt_ew"]
## Height of the top of the band and of the inserter's shoulder, in metres, and px per metre.
const BAND_HEIGHT := 0.24
const SHOULDER_HEIGHT := 0.68
const PPM := 32.0
const ITEM_SIZE := 16.0
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
var swing_ticks := 4

## Belts and inserters by tile: { id, rotation, items / hand, swing, ... }.
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
	for sprite: String in ["belt_ns", "belt_ew"]:
		_textures[sprite] = load("res://art/plot/%s.png" % sprite)


func has_machinery() -> bool:
	return not _belts.is_empty() or not _inserters.is_empty()


func is_belt(object: Dictionary) -> bool:
	return object.get("kind", "") == BELT


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
		if object["kind"] == BELT:
			var old: Dictionary = _find(_belts, object["id"])
			var items: Array = old.get("items", [])
			if items.size() != belt_slots:
				items = []
				items.resize(belt_slots)
			belts[cell] = {"id": object["id"], "rotation": rotation, "items": items, "moved": [], "next": Vector2i(-1, -1), "entry": 0}
		elif object["kind"] == INSERTER:
			var old: Dictionary = _find(_inserters, object["id"])
			inserters[cell] = {"id": object["id"], "rotation": rotation, "hand": old.get("hand"), "swing": int(old.get("swing", 0)),
				"was": int(old.get("swing", 0)), "arm": old.get("arm")}
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
	swing_ticks = int(state.get("swingTicks", swing_ticks))
	var belts_by_id := {}
	for belt: Dictionary in state.get("belts", []):
		belts_by_id[belt["id"]] = belt["items"]
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		if belts_by_id.has(belt["id"]):
			belt["items"] = (belts_by_id[belt["id"]] as Array).duplicate()
			belt["moved"] = []
	var inserters_by_id := {}
	for inserter: Dictionary in state.get("inserters", []):
		inserters_by_id[inserter["id"]] = inserter
	for cell: Vector2i in _inserters:
		var inserter: Dictionary = _inserters[cell]
		if inserters_by_id.has(inserter["id"]):
			inserter["hand"] = inserters_by_id[inserter["id"]]["hand"]
			inserter["swing"] = int(inserters_by_id[inserter["id"]]["swing"])
			inserter["was"] = inserter["swing"]
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


## Which belt each belt feeds and where, and the order to move them in: as on the server.
func _link_belts() -> void:
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		var target: Vector2i = cell + facing(belt["rotation"])
		belt["next"] = Vector2i(-1, -1)
		if _belts.has(target) and (int(_belts[target]["rotation"]) & 3) != ((int(belt["rotation"]) + 2) & 3):
			belt["next"] = target
			belt["entry"] = 0 if (int(_belts[target]["rotation"]) & 3) == (int(belt["rotation"]) & 3) else 1
	_order = []
	var seen := {}
	for start: Vector2i in _belts:
		var path: Array[Vector2i] = []
		var at := start
		while at.x >= 0 and not seen.has(at):
			seen[at] = true
			path.append(at)
			at = _belts[at]["next"]
		path.reverse()
		_order.append_array(path)


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


## One tick: belts move their items forward, inserter arms swing; picking up and dropping is left to the server.
func _step() -> void:
	for cell in _order:
		var belt: Dictionary = _belts[cell]
		var items: Array = belt["items"]
		var moved: Array = []
		var end := items.size() - 1
		var next: Vector2i = belt["next"]
		if items[end] != null and next.x >= 0 and _belts[next]["items"][belt["entry"]] == null:
			_belts[next]["items"][belt["entry"]] = items[end]
			_belts[next]["moved"].append(belt["entry"])
			items[end] = null
		for i in range(end - 1, -1, -1):
			if items[i] != null and items[i + 1] == null:
				items[i + 1] = items[i]
				items[i] = null
				moved.append(i + 1)
		belt["moved"] = moved
	for cell: Vector2i in _inserters:
		var inserter: Dictionary = _inserters[cell]
		inserter["was"] = inserter["swing"]
		if inserter["hand"] != null and int(inserter["swing"]) < swing_ticks:
			inserter["swing"] = int(inserter["swing"]) + 1
		elif inserter["hand"] == null and int(inserter["swing"]) > 0:
			inserter["swing"] = int(inserter["swing"]) - 1


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


func _draw() -> void:
	var f := _fraction()
	for cell: Vector2i in _belts:
		var sprite: String = BELT_SPRITES[int(_belts[cell]["rotation"]) & 3]
		var texture: Texture2D = _textures[sprite]
		var anchor := Vector2(layout[sprite]["anchorX"], layout[sprite]["anchorY"])
		draw_texture(texture, (Vector2(cell) + Vector2(0.5, 0.5)) * tile - anchor)
	# Chevrons pointing the way the band runs, moving one slot a tick.
	var phase := fmod(float(server_now.call()) / tick_ms, 1.0)
	for cell: Vector2i in _belts:
		var dir := Vector2(facing(_belts[cell]["rotation"]))
		var side := Vector2(-dir.y, dir.x)
		for k in belt_slots:
			var s := (k + phase) / belt_slots - 0.5
			if s > 0.42 or s < -0.48:
				continue
			var tip := _screen(cell, dir * (s + 0.05), BAND_HEIGHT)
			draw_polyline([_screen(cell, side * 0.2 + dir * s, BAND_HEIGHT), tip, _screen(cell, -side * 0.2 + dir * s, BAND_HEIGHT)], STRIPE, 2.0, true)
	for cell: Vector2i in _belts:
		var belt: Dictionary = _belts[cell]
		var dir := Vector2(facing(belt["rotation"]))
		var items: Array = belt["items"]
		for i in items.size():
			if items[i] == null:
				continue
			var at := (i + 0.5) / items.size() - 0.5
			if i in belt["moved"]:
				at -= (1.0 - f) / items.size()
			var p := _screen(cell, dir * at, BAND_HEIGHT)
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
		var swing := lerpf(float(inserter["was"]), float(inserter["swing"]), f) / maxf(logistics.swing_ticks, 1)
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
		for pass_color: Color in [PlotLogistics.ARM_DARK, PlotLogistics.ARM_COLOR]:
			var width := 7.0 if pass_color == PlotLogistics.ARM_DARK else 4.0
			draw_polyline([shoulder, elbow, hand], pass_color, width, true)
		draw_circle(shoulder, 3.5, PlotLogistics.ARM_DARK)
		draw_rect(Rect2(hand - Vector2(5, 3), Vector2(10, 6)), Color("#55585c"))
		var held: Variant = inserter.get("hand")
		if held != null:
			var size := PlotLogistics.ITEM_SIZE
			draw_texture_rect(logistics._icon(held), Rect2(hand - Vector2(size / 2, size * 0.75), Vector2(size, size)), false)
