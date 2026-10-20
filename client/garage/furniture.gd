class_name Furniture
extends Node2D
## A piece of furniture standing on the garage floor: its rendered sprite, anchored at the
## centre of its footprint, and its shadow on a separate layer under everything.

const HIGHLIGHT := preload("res://garage/highlight.gdshader")

var id := ""
var kind := ""
var display_name := ""
## Floor position of the footprint's centre and its size, in metres.
var floor_pos := Vector2.ZERO
var footprint := Vector2.ONE
var shadow := Sprite2D.new()

var _sprite := Sprite2D.new()
var _image: Image


func _init(object: Dictionary, info: Dictionary) -> void:
	id = object.get("id", "")
	kind = object["kind"]
	display_name = info.get("name", kind)
	footprint = Vector2(info.get("width", 1.0), info.get("depth", 1.0))
	var art: Dictionary = RoomProjection.layout()["objects"].get(kind, {"anchorX": 0, "anchorY": 0})
	var texture: Texture2D = load("res://art/garage/%s.png" % kind)
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.offset = -Vector2(art["anchorX"], art["anchorY"])
	_sprite.material = ShaderMaterial.new()
	_sprite.material.shader = HIGHLIGHT
	add_child(_sprite)
	shadow.texture = load("res://art/garage/%s_shadow.png" % kind)
	shadow.centered = false
	shadow.offset = _sprite.offset
	_image = texture.get_image()
	move_to(Vector2(object.get("x", 0.0), object.get("y", 0.0)))


func move_to(pos: Vector2) -> void:
	floor_pos = pos
	position = RoomProjection.to_screen(pos)
	shadow.position = position


## The footprint on the floor, in metres.
func rect() -> Rect2:
	return Rect2(floor_pos - footprint / 2, footprint)


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
