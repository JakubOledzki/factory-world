class_name GaragePlayer
extends Node2D
## The player's character walking around the garage, drawn from the walk atlas
## (rows: down, left, right, up; columns: idle, step A, step B) and tinted like the portrait.

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
		(material as ShaderMaterial).set_shader_parameter("light", Vector3(light.r, light.g, light.b))

var floor_pos := Vector2.ZERO
var facing := "down"
var walking := false
var shadow := Sprite2D.new()

var _shade: Texture2D
var _frame := Vector2.ZERO
var _feet := Vector2.ZERO
var _time := 0.0


func _init(appearance: Dictionary, options: Dictionary) -> void:
	material = ShaderMaterial.new()
	material.shader = CharacterPreview.SHADER
	_shade = CharacterPreview.apply_tints(material, "walk", appearance, options)
	var m: Dictionary = CharacterPreview.meta()["walk"]
	_frame = Vector2(m["frameWidth"], m["frameHeight"])
	_feet = Vector2(m["feetX"], m["feetY"])
	shadow.texture = load("res://art/character/shadow.png")
	shadow.centered = false
	shadow.offset = -_feet


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
	draw_texture_rect_region(_shade, Rect2(-_feet, _frame), source)
