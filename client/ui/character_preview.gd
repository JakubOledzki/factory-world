class_name CharacterPreview
extends Control
## Draws the player character from 3D renders (see tools/render_art.py): a grey shading image
## per hair and shirt style, tinted by a shader with the colours picked in the editor.

const SHADER := preload("res://ui/character_tint.gdshader")
## Shader uniform, appearance key and palette for each tinted part.
const TINTS := [
	["skin", "skinTone", "skinTones"],
	["shirt", "shirtColor", "clothColors"],
	["pants", "pantsColor", "clothColors"],
	["hair", "hairColor", "hairColors"],
	["shoes", "shoesColor", "clothColors"],
]

static var _meta: Dictionary

## Indexes into the palettes: skinTone, hairStyle, hairColor, shirtStyle, shirtColor, pantsColor, shoesColor.
var appearance := {}:
	set(value):
		appearance = value
		_update()

## Palettes from "character.options".
var options := {}:
	set(value):
		options = value
		_update()

## Size on screen relative to the rendered images.
var display_scale := 1.0:
	set(value):
		display_scale = value
		_resize()

## Part of the image to show, as fractions of its size (the HUD shows only the head and chest).
var region := Rect2(0, 0, 1, 1):
	set(value):
		region = value
		_resize()

## Multiplied into the colours, to match the lighting of the place the character stands in.
var light := Color.WHITE:
	set(value):
		light = value
		(material as ShaderMaterial).set_shader_parameter("light", Vector3(light.r, light.g, light.b))

## Draws the soft shadow on the floor under the character.
var show_shadow := false:
	set(value):
		show_shadow = value
		_shadow.visible = value

var _shade: Texture2D
var _shadow := TextureRect.new()


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	_shadow.texture = load("res://art/character/shadow.png")
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.show_behind_parent = true
	_shadow.use_parent_material = false
	_shadow.material = CanvasItemMaterial.new()
	_shadow.visible = false
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)
	_resize()


## Image size and the feet position inside it, written by the renderer.
static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/character/meta.json"))
	return _meta


## Where the feet are, relative to this control's top-left corner.
func feet_offset() -> Vector2:
	var m := meta()
	return (Vector2(m["feetX"], m["feetY"]) - _region_px().position) * display_scale


func _region_px() -> Rect2:
	var m := meta()
	var full := Vector2(m["width"], m["height"])
	return Rect2(region.position * full, region.size * full)


func _resize() -> void:
	var src := _region_px()
	custom_minimum_size = src.size * display_scale
	size = custom_minimum_size
	var full := Vector2(meta()["width"], meta()["height"])
	_shadow.position = -src.position * display_scale
	_shadow.size = full * display_scale
	queue_redraw()


func _update() -> void:
	if appearance.is_empty() or options.is_empty():
		return
	var prefix := "res://art/character/h%d_s%d" % [appearance.get("hairStyle", 0), appearance.get("shirtStyle", 0)]
	_shade = load(prefix + ".png")
	var shader := material as ShaderMaterial
	shader.set_shader_parameter("mask_a", load(prefix + "_mask_a.png"))
	shader.set_shader_parameter("mask_b", load(prefix + "_mask_b.png"))
	for tint: Array in TINTS:
		var c := _color(tint[2], tint[1])
		shader.set_shader_parameter(tint[0], Vector3(c.r, c.g, c.b))
	queue_redraw()


func _draw() -> void:
	if _shade == null:
		return
	var src := _region_px()
	draw_texture_rect_region(_shade, Rect2(Vector2.ZERO, src.size * display_scale), src)


func _color(palette: String, key: String) -> Color:
	var colors: Array = options.get(palette, [])
	var index: int = appearance.get(key, 0)
	return Color(colors[index]) if index >= 0 and index < colors.size() else Color.MAGENTA
