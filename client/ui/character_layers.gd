class_name CharacterLayers
extends Node2D
## A character drawn from its renders (see tools/render_character.py), one child per layer, bottom
## first: the body (hair and shirt style), the face, the facial hair and the clothes worn. The body,
## face and beard are grey images tinted by masks; clothes come in their own colours.

const TINT := preload("res://ui/character_tint.gdshader")
const OVERLAY := preload("res://ui/character_overlay.gdshader")
## Shader uniform, appearance key and palette for each tinted part.
const TINTS := [
	["skin", "skinTone", "skinTones"],
	["shirt", "shirtColor", "clothColors"],
	["pants", "pantsColor", "clothColors"],
	["hair", "hairColor", "hairColors"],
	["shoes", "shoesColor", "clothColors"],
]
## Clothes are drawn in this order: the jacket over the trousers, the hat over everything.
const SLOT_ORDER := ["legs", "feet", "body", "head"]
## Hair styles that would stick out through a hat, and the style drawn under one instead.
const HAT_HAIR := {2: 1, 5: 1}

static var _meta: Dictionary

## Multiplied into the colours, to match the lighting of the place the character stands in.
var light := Color.WHITE:
	set(value):
		light = value
		for layer: Node2D in get_children():
			(layer.material as ShaderMaterial).set_shader_parameter("light", Vector3(light.r, light.g, light.b))

## The part of every image to draw, and where.
var source := Rect2():
	set(value):
		source = value
		_redraw()
var target := Rect2():
	set(value):
		target = value
		_redraw()


## Image sizes, the feet position inside them and the clothes rendered, written by the renderer.
static func meta() -> Dictionary:
	if _meta.is_empty():
		_meta = JSON.parse_string(FileAccess.get_file_as_string("res://art/character/meta.json"))
	return _meta


## Draws a character: `kind` is "portrait" or "walk"; `look` holds the indexes picked in the editor
## and, under "outfit", the clothes worn by slot.
func set_look(kind: String, look: Dictionary, options: Dictionary) -> void:
	for old in get_children():
		remove_child(old)
		old.queue_free()
	var dir := "res://art/character/%s/" % kind
	var outfit: Dictionary = look.get("outfit", {}) if look.get("outfit") is Dictionary else {}
	var hair: int = look.get("hairStyle", 0)
	if outfit.has("head"):
		hair = HAT_HAIR.get(hair, hair)
	var tints := _tints(look, options)
	_add(dir + "h%d_s%d" % [hair, look.get("shirtStyle", 0)], tints)
	# The iris takes its colour in the shirt's place.
	var eyes: Array = options.get("eyeColors", [])
	var eye: int = look.get("eyeColor", 0)
	tints["shirt"] = Color(eyes[eye]) if eye >= 0 and eye < eyes.size() else Color.SADDLE_BROWN
	_add(dir + "face%d" % look.get("faceStyle", 0), tints)
	var beard: int = look.get("facialHair", 0)
	if beard > 0:
		_add(dir + "beard%d" % beard, tints)
	var rendered: Dictionary = meta().get("clothes", {})
	for slot: String in SLOT_ORDER:
		var item: Variant = outfit.get(slot)
		if item is String and rendered.has(item):
			_add(dir + item, {})
	light = light


func _tints(look: Dictionary, options: Dictionary) -> Dictionary:
	var tints := {}
	for tint: Array in TINTS:
		var colors: Array = options.get(tint[2], [])
		var index: int = look.get(tint[1], 0)
		tints[tint[0]] = Color(colors[index]) if index >= 0 and index < colors.size() else Color.MAGENTA
	return tints


## One layer: `tints` empty for a garment, which needs no masks.
func _add(path: String, tints: Dictionary) -> void:
	if not ResourceLoader.exists(path + ".png"):
		return
	var layer := Layer.new()
	layer.texture = load(path + ".png")
	var shader := ShaderMaterial.new()
	if tints.is_empty():
		shader.shader = OVERLAY
	else:
		shader.shader = TINT
		shader.set_shader_parameter("mask_a", load(path + "_mask_a.png"))
		shader.set_shader_parameter("mask_b", load(path + "_mask_b.png"))
		for part: String in tints:
			var c: Color = tints[part]
			shader.set_shader_parameter(part, Vector3(c.r, c.g, c.b))
	layer.material = shader
	add_child(layer)


func _redraw() -> void:
	for layer: Node2D in get_children():
		layer.queue_redraw()


class Layer:
	extends Node2D
	var texture: Texture2D

	func _draw() -> void:
		var owner_layers: CharacterLayers = get_parent()
		draw_texture_rect_region(texture, owner_layers.target, owner_layers.source)
