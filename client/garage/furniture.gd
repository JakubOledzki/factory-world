class_name Furniture
extends Node2D
## A piece of furniture standing on the garage floor's grid: its rendered sprite for the current
## rotation, anchored at the centre of its footprint, and its shadow on a separate layer.

const HIGHLIGHT := preload("res://garage/highlight.gdshader")

var id := ""
var kind := ""
var display_name := ""
## Front-left cell, quarter turns anticlockwise (0 faces the camera) and cells taken unturned.
var cell := Vector2i.ZERO
var rotation_steps := 0
var cells := Vector2i.ONE
## Floor position of the footprint's centre, in metres.
var floor_pos := Vector2.ZERO
var shadow := Sprite2D.new()

var _cell_size := 0.5
var _sprite := Sprite2D.new()
var _image: Image


func _init(furniture_kind: String, info: Dictionary, cell_size: float) -> void:
	kind = furniture_kind
	display_name = info.get("name", kind)
	cells = Vector2i(info.get("width", 1), info.get("depth", 1))
	_cell_size = cell_size
	_sprite.centered = false
	_sprite.material = ShaderMaterial.new()
	_sprite.material.shader = HIGHLIGHT
	add_child(_sprite)
	shadow.centered = false


## Cells taken with the current rotation.
func size_cells(steps := rotation_steps) -> Vector2i:
	return cells if steps % 2 == 0 else Vector2i(cells.y, cells.x)


func place(at: Vector2i, steps: int) -> void:
	cell = at
	if steps != rotation_steps or _image == null:
		rotation_steps = steps
		var art: Dictionary = RoomProjection.layout()["objects"][kind][steps]
		_sprite.texture = load("res://art/garage/%s_r%d.png" % [kind, steps])
		_sprite.offset = -Vector2(art["anchorX"], art["anchorY"])
		shadow.texture = load("res://art/garage/%s_r%d_shadow.png" % [kind, steps])
		shadow.offset = _sprite.offset
		_image = _sprite.texture.get_image()
	floor_pos = (Vector2(cell) + Vector2(size_cells()) / 2) * _cell_size
	position = RoomProjection.to_screen(floor_pos)
	shadow.position = position


## The footprint on the floor, in metres.
func rect() -> Rect2:
	return Rect2(Vector2(cell) * _cell_size, Vector2(size_cells()) * _cell_size)


## The footprint in cells.
func cell_rect() -> Rect2i:
	return Rect2i(cell, size_cells())


func set_highlighted(on: bool) -> void:
	(_sprite.material as ShaderMaterial).set_shader_parameter("enabled", on)


## Whether a screen point lands on a solid pixel of the sprite.
func hit(screen: Vector2) -> bool:
	var p := Vector2i((screen - position - _sprite.offset).floor())
	if p.x < 0 or p.y < 0 or p.x >= _image.get_width() or p.y >= _image.get_height():
		return false
	return _image.get_pixelv(p).a > 0.5


## Tints the sprite for the placement preview.
func set_ghost(valid: bool) -> void:
	modulate = Color(0.7, 1.3, 0.7, 0.75) if valid else Color(1.5, 0.5, 0.45, 0.75)
	shadow.visible = false
