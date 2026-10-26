class_name PlotEffects
extends Node2D
## What makes the plot feel alive: a mark over every machine that stands still (what it waits for, blinking),
## smoke over the fired machines at work, and short bursts of dust, sparks and confetti. Only what is on the
## screen is drawn, and there are only so many smoke plumes and bursts at a time, so a big factory costs no more.
## The marks and pings always show; smoke and bursts only while the player has effects on (Settings).

## The most smoke plumes and bursts at a time; the plumes go to the working machines nearest the middle of the screen.
const MAX_SMOKE := 16
const MAX_BURSTS := 12
const SMOKE_EVERY := 0.5
## How long a ping marks its tile (ms).
const PING_MS := 7000.0
const PING_COLOR := Color("#5ab4e8")
## Why a machine stands still, as its mark says it on hover.
const REASONS := {
	"no_input": "czeka na składniki",
	"no_fuel": "brak opału",
	"output_full": "pełna, odbierz produkty",
	"no_recipe": "nie wybrano przepisu",
	"no_power": "brak prądu",
}
const MARK_COLORS := {
	"no_input": Color(0.96, 0.69, 0.25),
	"no_fuel": Color(0.92, 0.45, 0.2),
	"output_full": Color(0.56, 0.84, 0.35),
	"no_recipe": Color(0.6, 0.6, 0.62),
	"no_power": Color(1.0, 0.85, 0.2),
}

## How the plot draws a machine: the tile size, and the middle of an object of a kind standing on a tile.
var tile := Vector2(64, 45)
var centre_of := Callable()

## By object id: { state, missing: [{ id, name }], fired } as the server last said.
var _statuses := {}
## By object id: { kind, cell } of the anchor tile, from the placed objects.
var _objects := {}
var _icons := {}
var _smoke: Array[CPUParticles2D] = []
var _next_smoke := 0.0
var _bursts := 0
## Places players pointed at: [{ at, until (ticks ms) }].
var _pings: Array = []


func _ready() -> void:
	z_index = 20
	for i in MAX_SMOKE:
		var plume := _particles(18, 2.2)
		plume.emitting = false
		plume.direction = Vector2(0.15, -1)
		plume.spread = 14.0
		plume.gravity = Vector2(12, -18)
		plume.initial_velocity_min = 18.0
		plume.initial_velocity_max = 30.0
		plume.scale_amount_min = 5.0
		plume.scale_amount_max = 9.0
		plume.color_ramp = _fade(Color(0.55, 0.53, 0.5, 0.55))
		_smoke.append(plume)
		add_child(plume)


## Takes the placed objects (tile → object), to know where each machine stands.
func set_objects(placed: Dictionary) -> void:
	_objects = {}
	for cell: Vector2i in placed:
		var object: Dictionary = placed[cell]
		var anchor := Vector2i(int(object["tileX"]), int(object["tileY"]))
		if cell == anchor:
			_objects[str(object["id"])] = {"kind": str(object["kind"]), "cell": anchor}
	_next_smoke = 0.0
	queue_redraw()


## Shows a "stats.machines" reply.
func apply(machines: Array) -> void:
	_statuses = {}
	for m: Dictionary in machines:
		_statuses[str(m["id"])] = {"state": str(m["state"]), "missing": m.get("missing", []), "fired": bool(m.get("fired", false))}
	_next_smoke = 0.0
	queue_redraw()


func clear() -> void:
	_statuses = {}
	queue_redraw()


## What a machine is waiting for, as a note after its name on hover; "" while it works or says nothing.
func note(id: String) -> String:
	var status: Dictionary = _statuses.get(id, {})
	var state: String = status.get("state", "working")
	if state == "working" or not REASONS.has(state):
		return ""
	var missing: Array = status.get("missing", [])
	var names: Array[String] = []
	for item: Dictionary in missing.slice(0, 3):
		names.append(str(item["name"]).to_lower())
	return " (stoi: %s%s)" % [REASONS[state], ": " + ", ".join(names) if not names.is_empty() and state != "no_fuel" else ""]


## Marks a place a player pointed at with a pulsing ring and an arrow over it, for a few seconds.
func ping(at: Vector2) -> void:
	_pings.append({"at": at, "until": Time.get_ticks_msec() + PING_MS})
	queue_redraw()


## Dust rising where something was put down or picked up.
func dust(at: Vector2, size := 1.0) -> void:
	var puff := _burst(14, 0.7)
	if puff == null:
		return
	puff.position = at
	puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	puff.emission_rect_extents = tile * 0.4 * size
	puff.direction = Vector2(0, -1)
	puff.spread = 70.0
	puff.gravity = Vector2(0, 30)
	puff.initial_velocity_min = 25.0
	puff.initial_velocity_max = 60.0
	puff.scale_amount_min = 3.0
	puff.scale_amount_max = 6.0
	puff.color_ramp = _fade(Color(0.72, 0.64, 0.5, 0.7))
	puff.emitting = true


## Chips flying where a tree, a rock or a mine was worked.
func chips(at: Vector2, color: Color) -> void:
	var burst := _burst(12, 0.6)
	if burst == null:
		return
	burst.position = at
	burst.direction = Vector2(0, -1)
	burst.spread = 60.0
	burst.gravity = Vector2(0, 260)
	burst.initial_velocity_min = 70.0
	burst.initial_velocity_max = 140.0
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 4.0
	burst.color_ramp = _fade(color)
	burst.emitting = true


## Confetti over the player for a level, a finished research or a building plan put up.
func confetti(at: Vector2) -> void:
	var burst := _burst(60, 1.6)
	if burst == null:
		return
	burst.position = at - Vector2(0, tile.y * 1.5)
	burst.direction = Vector2(0, -1)
	burst.spread = 50.0
	burst.gravity = Vector2(0, 220)
	burst.initial_velocity_min = 140.0
	burst.initial_velocity_max = 260.0
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 5.0
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	colors.colors = PackedColorArray([Color("#f5b041"), Color("#8fd65a"), Color("#5ab4e8"), Color("#e8894a"), Color("#e6e1d6")])
	burst.color_initial_ramp = colors
	burst.color_ramp = _fade(Color.WHITE)
	burst.emitting = true


func _process(delta: float) -> void:
	_next_smoke -= delta
	if _next_smoke <= 0.0:
		_next_smoke = SMOKE_EVERY
		_place_smoke()
	# The marks blink and the pings pulse, so they are redrawn while any is shown.
	if _statuses.size() > 0 or not _pings.is_empty():
		queue_redraw()


func _draw() -> void:
	var view := _view()
	_draw_pings()
	var blink := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 220.0)
	for id: String in _statuses:
		var status: Dictionary = _statuses[id]
		var state: String = status["state"]
		if state == "working" or not _objects.has(id):
			continue
		var object: Dictionary = _objects[id]
		var at := _mark_at(object)
		if not view.has_point(at):
			continue
		var color: Color = MARK_COLORS.get(state, Color.WHITE)
		draw_circle(at, 13.0, Color(0.09, 0.08, 0.07, 0.9 * blink))
		draw_arc(at, 13.0, 0, TAU, 24, Color(color, blink), 2.0, true)
		var icon := _mark_icon(status)
		if icon != null:
			draw_texture_rect(icon, Rect2(at - Vector2(9, 9), Vector2(18, 18)), false, Color(1, 1, 1, blink))
		else:
			_draw_symbol(state, at, Color(color, blink))


func _draw_pings() -> void:
	var now := Time.get_ticks_msec()
	_pings = _pings.filter(func(p: Dictionary) -> bool: return float(p["until"]) > now)
	for p: Dictionary in _pings:
		var at: Vector2 = p["at"]
		var pulse := fmod(now / 900.0, 1.0)
		draw_set_transform(at, 0, Vector2(1, tile.y / tile.x))
		draw_arc(Vector2.ZERO, tile.x * (0.3 + 0.5 * pulse), 0, TAU, 32, Color(PING_COLOR, 1.0 - pulse), 3.0, true)
		draw_arc(Vector2.ZERO, tile.x * 0.3, 0, TAU, 32, PING_COLOR, 2.0, true)
		draw_set_transform(Vector2.ZERO)
		var bob := sin(now / 160.0) * 4.0
		var tip := at - Vector2(0, 14 + bob)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-11, -18), tip + Vector2(11, -18)]), PING_COLOR)
		draw_rect(Rect2(tip + Vector2(-5, -36), Vector2(10, 18)), PING_COLOR)


## Over the machine, like the filter's mark but a little higher, so both show.
func _mark_at(object: Dictionary) -> Vector2:
	var kind: String = object["kind"]
	var cell: Vector2i = object["cell"]
	var centre: Vector2 = centre_of.call(kind, cell) if centre_of.is_valid() else (Vector2(cell) + Vector2(0.5, 0.5)) * tile
	return centre - Vector2(0, tile.y * (0.8 + 0.6 * Footprints.size(kind)))


## The icon of what the machine waits for: the missing ingredient, or the coal it would burn.
func _mark_icon(status: Dictionary) -> Texture2D:
	var state: String = status["state"]
	var missing: Array = status.get("missing", [])
	if state not in ["no_input", "no_fuel"] or missing.is_empty():
		return null
	var item := str((missing[0] as Dictionary)["id"])
	if not _icons.has(item):
		_icons[item] = UI.item_texture(item)
	return _icons[item]


## A plain sign for a machine that waits for no item: a bolt for power, an arrow up for a full one, a question mark for no recipe.
func _draw_symbol(state: String, at: Vector2, color: Color) -> void:
	match state:
		"no_power":
			draw_colored_polygon(PackedVector2Array([at + Vector2(2, -9), at + Vector2(-5, 1), at + Vector2(0, 1),
				at + Vector2(-2, 9), at + Vector2(5, -1), at + Vector2(0, -1)]), color)
		"output_full":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(2.5, 0),
				at + Vector2(2.5, 7), at + Vector2(-2.5, 7), at + Vector2(-2.5, 0), at + Vector2(-7, 0)]), color)
		_:
			draw_string(UI.bold(), at + Vector2(-5, 7), "?", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, color)


## The plumes go to the fired machines at work nearest the middle of the screen; the rest stop.
func _place_smoke() -> void:
	var view := _view()
	var middle := view.get_center()
	var working: Array = []
	for id: String in _statuses if Settings.effects else {}:
		var status: Dictionary = _statuses[id]
		if status["state"] != "working" or not status["fired"] or not _objects.has(id):
			continue
		var object: Dictionary = _objects[id]
		var kind: String = object["kind"]
		var cell: Vector2i = object["cell"]
		var centre: Vector2 = centre_of.call(kind, cell) if centre_of.is_valid() else (Vector2(cell) + Vector2(0.5, 0.5)) * tile
		var top := centre - Vector2(0, tile.y * (0.6 + 0.5 * Footprints.size(kind)))
		if view.grow(tile.x * 2).has_point(top):
			working.append(top)
	working.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(middle) < b.distance_squared_to(middle))
	for i in _smoke.size():
		var plume := _smoke[i]
		if i < working.size():
			var at: Vector2 = working[i]
			if not plume.emitting or plume.position.distance_to(at) > 1.0:
				plume.position = at
				plume.emitting = true
		else:
			plume.emitting = false


## The part of the plot on the screen, in the plot's coordinates.
func _view() -> Rect2:
	var shown := get_viewport_rect()
	return get_canvas_transform().affine_inverse() * shown


## A one-shot burst, freed when it is done; null when too many are flying already.
func _burst(amount: int, lifetime: float) -> CPUParticles2D:
	# The player turned effects off (Settings).
	if not Settings.effects:
		return null
	if _bursts >= MAX_BURSTS:
		return null
	var burst := _particles(amount, lifetime)
	burst.one_shot = true
	burst.explosiveness = 0.9
	_bursts += 1
	add_child(burst)
	burst.finished.connect(func() -> void:
		_bursts -= 1
		burst.queue_free())
	return burst


func _particles(amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	return p


## A colour that fades out over a particle's life.
func _fade(color: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([color, Color(color, 0.0)])
	return g
