class_name CharacterPreview
extends Control
## Draws the player character's portrait from 3D renders (see CharacterLayers): the body tinted
## with the colours picked in the editor, the face, the facial hair and the clothes worn.

## Indexes into the palettes (skinTone, hairStyle, hairColor, shirtStyle, shirtColor, pantsColor,
## shoesColor, faceStyle, eyeColor, facialHair) and the clothes worn by slot under "outfit".
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
		_layers.light = light

var _layers := CharacterLayers.new()


func _init() -> void:
	add_child(_layers)
	resized.connect(_resize)
	_resize()


## Image sizes and the feet position inside them, written by the renderer.
static func meta() -> Dictionary:
	return CharacterLayers.meta()


func _region_px() -> Rect2:
	var m: Dictionary = meta()["portrait"]
	var full := Vector2(m["width"], m["height"])
	return Rect2(region.position * full, region.size * full)


func _resize() -> void:
	var src := _region_px()
	custom_minimum_size = src.size * display_scale
	_layers.source = src
	# Centred in whatever room the container gives.
	_layers.target = Rect2(((size - custom_minimum_size) / 2).max(Vector2.ZERO).floor(), src.size * display_scale)


func _update() -> void:
	if appearance.is_empty() or options.is_empty():
		return
	_layers.set_look("portrait", appearance, options)
