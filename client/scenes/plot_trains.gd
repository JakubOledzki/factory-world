class_name PlotTrains
extends Node2D
## Trains on the track across a plot, drawn from what the station knows: a train coming to the
## station rolls in from the east and slows down to stop at the platform when it arrives, stands a
## moment while it unloads and leaves to the west; a train sent from here stands at the platform
## while it is loaded and pulls out to the west. A bigger load comes with more wagons.

## Seconds a train takes to roll in, stands at the platform and takes to leave.
const ROLL_IN := 8.0
const STAND := 6.0
const ROLL_OUT := 9.0
## How far (px) a train rolls in from and out to, beyond what can be seen around the station.
const RUN := 2600.0
const GAP := 10.0
## Items per wagon, and most wagons a train has.
const PER_WAGON := 400
const MAX_WAGONS := 5

var layout := {}
## Where trains stop: the middle of the platform, on the middle of the track (px).
var stop := Vector2.ZERO
## The node shadows go on, under everything standing.
var shadows_parent: Node2D
var world_width := 6933
var server_now := func() -> float: return Time.get_unix_time_from_system() * 1000.0

## Trains to draw: { start (ms, when it shows up), stop_at (ms, when it stands at the platform),
## leave_at (ms), wagons, seed }.
var _trains: Array = []
## Sprites in use, by train index: [[sprite, shadow, offset px from the locomotive's middle]...].
var _drawn := {}


func _ready() -> void:
	y_sort_enabled = true


## Works out the trains from a "station" reply.
func show_station(station: Dictionary, at: Vector2i) -> void:
	var rates: Dictionary = station.get("rates", {})
	var trains := {}
	for trip: Dictionary in station.get("incoming", []):
		var arrives := float(trip["arrivesAt"])
		var key := "in %d %d %d" % [arrives, int(trip["fromX"]), int(trip["fromY"])]
		var train: Dictionary = trains.get(key, {
			"start": arrives - ROLL_IN * 1000.0, "stop_at": arrives, "leave_at": arrives + STAND * 1000.0, "quantity": 0, "seed": key.hash(),
		})
		train["quantity"] += int(trip["quantity"])
		trains[key] = train
	for trip: Dictionary in station.get("outgoing", []):
		# It left when it arrives less the trip, worked out like the server does.
		var dx := absi(int(trip["toX"]) - at.x)
		dx = mini(dx, world_width - dx)
		var km := sqrt(float(dx * dx + (int(trip["toY"]) - at.y) * (int(trip["toY"]) - at.y))) * 5.0
		var seconds := maxf(float(rates.get("minTripSeconds", 10.0)), km / 100.0 * float(rates.get("secondsPer100Km", 5.0)))
		var left := float(trip["arrivesAt"]) - seconds * 1000.0
		var key := "out %d %d %d" % [left, int(trip["toX"]), int(trip["toY"])]
		var train: Dictionary = trains.get(key, {
			"start": left, "stop_at": left, "leave_at": left + STAND * 1000.0, "quantity": 0, "seed": key.hash(),
		})
		train["quantity"] += int(trip["quantity"])
		trains[key] = train
	# A train that arrived is unloaded and gone from the station's list, but it still stands and leaves.
	var now: float = server_now.call()
	for train: Dictionary in _trains:
		if not trains.has(train["key"]) and train["leave_at"] + ROLL_OUT * 1000.0 > now:
			trains[train["key"]] = train
	for key: String in trains:
		trains[key]["key"] = key
	_trains = trains.values()
	_trains.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["stop_at"] < b["stop_at"])
	for train: Dictionary in _trains:
		train["wagons"] = clampi(ceili(train["quantity"] / float(PER_WAGON)), 1, MAX_WAGONS)
	for index: int in _drawn.keys():
		_free(index)
	_drawn.clear()


## Whether a train is standing at the platform or about to, so the screen can ask the station again sooner.
func busy() -> bool:
	var now: float = server_now.call()
	for train: Dictionary in _trains:
		if now >= train["start"] - 2000.0 and now <= train["leave_at"] + ROLL_OUT * 1000.0:
			return true
	return false


func _process(_delta: float) -> void:
	var now: float = server_now.call()
	# One train on the track at a time: the one due first that has not gone yet.
	var shown := -1
	for i in _trains.size():
		var train: Dictionary = _trains[i]
		if now >= train["start"] and now <= train["leave_at"] + ROLL_OUT * 1000.0:
			shown = i
			break
	for index: int in _drawn.keys():
		if index != shown:
			_free(index)
	if shown < 0:
		return
	var train: Dictionary = _trains[shown]
	if not _drawn.has(shown):
		_drawn[shown] = _build(train)
	var x := stop.x
	if now < train["stop_at"]:
		# Slowing down: the distance left shrinks with the square of the time left.
		var r: float = (train["stop_at"] - now) / (ROLL_IN * 1000.0)
		x += RUN * r * r
	elif now > train["leave_at"]:
		var s: float = (now - train["leave_at"]) / (ROLL_OUT * 1000.0)
		x -= RUN * s * s
	for part: Array in _drawn[shown]:
		var at := Vector2(x + part[2], stop.y)
		part[0].position = at
		part[1].position = at


## The locomotive at the front (west) and the wagons behind it, the whole train centred on the platform.
func _build(train: Dictionary) -> Array:
	var names := ["train_locomotive"]
	var rng := RandomNumberGenerator.new()
	rng.seed = train["seed"]
	for i in train["wagons"]:
		names.append("train_wagon_open" if rng.randf() < 0.5 else "train_wagon")
	var lengths: Array[float] = []
	var total := 0.0
	for name: String in names:
		var length := float(layout[name]["lengthPx"])
		lengths.append(length)
		total += length + GAP
	total -= GAP
	var parts: Array = []
	var at := -total / 2.0
	for i in names.size():
		var name: String = names[i]
		var anchor := Vector2(layout[name]["anchorX"], layout[name]["anchorY"])
		var sprite := Sprite2D.new()
		sprite.texture = PlotArt.texture(name)
		sprite.centered = false
		sprite.offset = -anchor
		add_child(sprite)
		var shadow := Sprite2D.new()
		shadow.texture = PlotArt.texture(name + "_shadow")
		shadow.centered = false
		shadow.offset = -anchor
		shadows_parent.add_child(shadow)
		parts.append([sprite, shadow, at + lengths[i] / 2.0])
		at += lengths[i] + GAP
	return parts


func _free(index: int) -> void:
	for part: Array in _drawn.get(index, []):
		part[0].queue_free()
		part[1].queue_free()
	_drawn.erase(index)
