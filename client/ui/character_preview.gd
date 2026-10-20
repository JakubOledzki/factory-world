class_name CharacterPreview
extends Control
## Draws the player character as 16×24 pixel art from layers: body, clothes, hair.
## Colours come from the server's palettes, so the editor and the game always agree.

const WIDTH := 16
const HEIGHT := 24
const EYE := Color("#1a1a22")

## Indexes into the palettes: skinTone, hairStyle, hairColor, shirtStyle, shirtColor, pantsColor, shoesColor.
var appearance := {}:
	set(value):
		appearance = value
		queue_redraw()

## Palettes from "character.options".
var options := {}:
	set(value):
		options = value
		queue_redraw()

## Screen pixels per art pixel.
var pixel := 6:
	set(value):
		pixel = value
		custom_minimum_size = Vector2(WIDTH, HEIGHT) * pixel
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT) * pixel


func _draw() -> void:
	if appearance.is_empty() or options.is_empty():
		return
	var skin := _color("skinTones", "skinTone")
	var hair := _color("hairColors", "hairColor")
	var shirt := _color("clothColors", "shirtColor")
	var pants := _color("clothColors", "pantsColor")
	var shoes := _color("clothColors", "shoesColor")
	var hair_style: int = appearance.get("hairStyle", 0)
	var shirt_style: int = appearance.get("shirtStyle", 0)

	# Hair that hangs behind the body.
	if hair_style == 3:
		_rect(4, 3, 8, 7, hair)
	elif hair_style == 4:
		_rect(11, 4, 2, 5, hair)

	# Head, neck and eyes.
	_rect(5, 2, 6, 6, skin)
	_rect(7, 8, 2, 1, skin)
	_rect(6, 5, 1, 1, EYE)
	_rect(9, 5, 1, 1, EYE)

	# Arms: skin, covered by sleeves depending on the shirt.
	_rect(3, 9, 1, 7, skin)
	_rect(12, 9, 1, 7, skin)
	match shirt_style:
		0:  # T-shirt: short sleeves.
			_rect(3, 9, 1, 2, shirt)
			_rect(12, 9, 1, 2, shirt)
		2:  # Hoodie: long sleeves and a hood around the neck.
			_rect(3, 9, 1, 6, shirt)
			_rect(12, 9, 1, 6, shirt)
			_rect(6, 8, 4, 1, shirt.darkened(0.25))

	# Torso; a tank top leaves the shoulders bare.
	if shirt_style == 1:
		_rect(5, 9, 6, 7, shirt)
		_rect(4, 9, 1, 1, skin)
		_rect(11, 9, 1, 1, skin)
	else:
		_rect(4, 9, 8, 7, shirt)

	# Legs with a shaded gap between them, then shoes.
	_rect(5, 16, 6, 6, pants)
	_rect(7, 18, 2, 4, pants.darkened(0.35))
	_rect(4, 22, 3, 2, shoes)
	_rect(9, 22, 3, 2, shoes)

	# Hair on top of the head.
	match hair_style:
		1:  # Short.
			_rect(5, 1, 6, 2, hair)
			_rect(5, 3, 1, 1, hair)
			_rect(10, 3, 1, 1, hair)
		2:  # Spiky.
			_rect(5, 1, 6, 2, hair)
			_rect(5, 0, 1, 1, hair)
			_rect(7, 0, 1, 1, hair)
			_rect(9, 0, 1, 1, hair)
		3:  # Long.
			_rect(5, 1, 6, 2, hair)
			_rect(4, 2, 1, 1, hair)
			_rect(11, 2, 1, 1, hair)
		4:  # Ponytail.
			_rect(5, 1, 6, 2, hair)
			_rect(11, 3, 1, 2, hair)
		5:  # Curly.
			_rect(4, 1, 8, 2, hair)
			_rect(5, 0, 2, 1, hair)
			_rect(9, 0, 2, 1, hair)
			_rect(4, 3, 1, 2, hair)
			_rect(11, 3, 1, 2, hair)


func _rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	var origin := (size - Vector2(WIDTH, HEIGHT) * pixel) / 2
	draw_rect(Rect2(origin + Vector2(x, y) * pixel, Vector2(w, h) * pixel), color)


func _color(palette: String, key: String) -> Color:
	var colors: Array = options.get(palette, [])
	var index: int = appearance.get(key, 0)
	return Color(colors[index]) if index >= 0 and index < colors.size() else Color.MAGENTA
