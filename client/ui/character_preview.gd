class_name CharacterPreview
extends Control
## Draws the player character's portrait from 3D renders (see tools/render_art.py): a grey
## shading image per hair and shirt style, tinted by a shader with the colours picked in the editor.

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

var _shade: Texture2D


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	_resize()


## Image sizes and the feet position inside them, written by the renderer.
static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/character/meta.json"))
	return _meta


## Points a tint shader at the images of a hair and shirt style ("portrait" or "walk") and
## sets the colours picked in the editor; returns the shading texture to draw.
static func apply_tints(shader: ShaderMaterial, kind: String, appearance: Dictionary, options: Dictionary) -> Texture2D:
	var prefix := "res://art/character/%s/h%d_s%d" % [kind, appearance.get("hairStyle", 0), appearance.get("shirtStyle", 0)]
	shader.set_shader_parameter("mask_a", load(prefix + "_mask_a.png"))
	shader.set_shader_parameter("mask_b", load(prefix + "_mask_b.png"))
	for tint: Array in TINTS:
		var colors: Array = options.get(tint[2], [])
		var index: int = appearance.get(tint[1], 0)
		var c := Color(colors[index]) if index >= 0 and index < colors.size() else Color.MAGENTA
		shader.set_shader_parameter(tint[0], Vector3(c.r, c.g, c.b))
	return load(prefix + ".png")


func _region_px() -> Rect2:
	var m: Dictionary = meta()["portrait"]
	var full := Vector2(m["width"], m["height"])
	return Rect2(region.position * full, region.size * full)


func _resize() -> void:
	var src := _region_px()
	custom_minimum_size = src.size * display_scale
	size = custom_minimum_size
	queue_redraw()


func _update() -> void:
	if appearance.is_empty() or options.is_empty():
		return
	_shade = apply_tints(material, "portrait", appearance, options)
	queue_redraw()


func _draw() -> void:
	if _shade == null:
		return
	var src := _region_px()
	draw_texture_rect_region(_shade, Rect2(Vector2.ZERO, src.size * display_scale), src)

