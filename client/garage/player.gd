class_name GaragePlayer
extends Node2D
## The player's character walking around the garage, drawn from the walk atlas
## (rows: down, left, right, up; columns: idle, step A, step B) in layers like the portrait.

## Metres per second.
const SPEED := 2.4
## Half the width of the body on the floor, for collisions.
const RADIUS := 0.2
## Walk cycle: step A, idle, step B, idle.
const CYCLE := [1, 0, 2, 0]
const STEPS_PER_SECOND := 7.0

const ROWS := {"down": 0, "left": 1, "right": 2, "up": 3}

## Multiplied into the colours, so the character fits the dim garage.
var light := Color.WHITE:
	set(value):
		light = value
		_body.light = light

var floor_pos := Vector2.ZERO
var facing := "down"
var walking := false
var shadow := Sprite2D.new()

var _body := CharacterLayers.new()
var _frame := Vector2.ZERO
var _feet := Vector2.ZERO
var _time := 0.0


func _init(appearance: Dictionary, options: Dictionary) -> void:
	var m: Dictionary = CharacterLayers.meta()["walk"]
	_frame = Vector2(m["frameWidth"], m["frameHeight"])
	_feet = Vector2(m["feetX"], m["feetY"])
	add_child(_body)
	_body.target = Rect2(-_feet, _frame)
	set_look(appearance, options)
	shadow.texture = load("res://art/character/shadow.png")
	shadow.centered = false
	shadow.offset = -_feet


## Dresses the character again, e.g. after the player changed clothes.
func set_look(appearance: Dictionary, options: Dictionary) -> void:
	_body.set_look("walk", appearance, options)
	_body.light = light
	queue_redraw()


func move_to(pos: Vector2) -> void:
	floor_pos = pos
	position = RoomProjection.to_screen(pos)
	shadow.position = position


## Turns towards a direction of movement on the floor (+y is away from the camera).
func face(direction: Vector2) -> void:
	if direction.length() < 0.001:
		return
	var turned: String
	if absf(direction.x) > absf(direction.y):
		turned = "right" if direction.x > 0 else "left"
	else:
		turned = "up" if direction.y > 0 else "down"
	if turned != facing:
		facing = turned
		queue_redraw()


func _process(delta: float) -> void:
	if walking:
		_time += delta
		queue_redraw()
	elif _time != 0.0:
		_time = 0.0
		queue_redraw()


func _draw() -> void:
	var column: int = CYCLE[int(_time * STEPS_PER_SECOND) % CYCLE.size()] if walking else 0
	var source := Rect2(Vector2(column, ROWS[facing]) * _frame, _frame)
	_body.source = source
