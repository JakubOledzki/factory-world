class_name CharacterPreview
extends Control
## Draws the player character as 16×24 pixel art from layers: body, clothes, hair,
## then adds shading and a dark outline like the rest of the game's sprites.
## Colours come from the server's palettes, so the editor and the game always agree.

const WIDTH := 16
const HEIGHT := 24
## The sprite has a 1 px border for the outline.
const BORDER := 1
const EYE := Color("#181425")
const OUTLINE := Color("#181425")

## Indexes into the palettes: skinTone, hairStyle, hairColor, shirtStyle, shirtColor, pantsColor, shoesColor.
var appearance := {}:
	set(value):
		appearance = value
		_texture = null
		queue_redraw()

## Palettes from "character.options".
var options := {}:
	set(value):
		options = value
		_texture = null
		queue_redraw()

## Screen pixels per art pixel.
var pixel := 6:
	set(value):
		pixel = value
		custom_minimum_size = _full_size() * pixel
		queue_redraw()

var _texture: ImageTexture
var _image: Image


func _init() -> void:
	custom_minimum_size = _full_size() * pixel


func _full_size() -> Vector2:
	return Vector2(WIDTH, HEIGHT) + Vector2.ONE * BORDER * 2


func _draw() -> void:
	if appearance.is_empty() or options.is_empty():
		return
	if _texture == null:
		_texture = ImageTexture.create_from_image(render())
	var drawn := _full_size() * pixel
	draw_texture_rect(_texture, Rect2(((size - drawn) / 2).floor(), drawn), false)


## The character as an image with its outline, (WIDTH + 2) × (HEIGHT + 2) pixels.
func render() -> Image:
	var full := _full_size()
	_image = Image.create_empty(int(full.x), int(full.y), false, Image.FORMAT_RGBA8)
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

	# Head, neck, face: shaded jaw and side, eyes and mouth.
	_rect(5, 2, 6, 6, skin)
	_rect(10, 3, 1, 5, skin.darkened(0.15))
	_rect(6, 7, 4, 1, skin.darkened(0.1))
	_rect(7, 8, 2, 1, skin.darkened(0.25))
	_rect(6, 5, 1, 1, EYE)
	_rect(9, 5, 1, 1, EYE)
	_rect(7, 6, 2, 1, skin.darkened(0.2))

	# Arms: skin, covered by sleeves depending on the shirt.
	_rect(3, 9, 1, 7, skin)
	_rect(12, 9, 1, 7, skin.darkened(0.15))
	match shirt_style:
		0:  # T-shirt: short sleeves.
			_rect(3, 9, 1, 2, shirt)
			_rect(12, 9, 1, 2, shirt)
		2:  # Hoodie: long sleeves and a hood around the neck.
			_rect(3, 9, 1, 6, shirt)
			_rect(12, 9, 1, 6, shirt)
			_rect(6, 8, 4, 1, shirt.darkened(0.25))

	# Torso; a tank top leaves the shoulders bare.
	# Torso, lit from the left; a tank top leaves the shoulders bare.
	if shirt_style == 1:
		_rect(5, 9, 6, 7, shirt)
		_rect(4, 9, 1, 1, skin)
		_rect(11, 9, 1, 1, skin)
		_rect(10, 10, 1, 6, shirt.darkened(0.2))
	else:
		_rect(4, 9, 8, 7, shirt)
		_rect(5, 9, 6, 1, shirt.lightened(0.15))
		_rect(11, 10, 1, 6, shirt.darkened(0.2))
	_rect(5, 15, 6, 1, shirt.darkened(0.3))

	# Belt line, legs with a shaded gap between them, then shoes with soles.
	_rect(5, 16, 6, 6, pants)
	_rect(5, 16, 6, 1, pants.darkened(0.2))
	_rect(10, 17, 1, 5, pants.darkened(0.2))
	_rect(7, 18, 2, 4, Color(0, 0, 0, 0))
	_rect(4, 22, 3, 2, shoes)
	_rect(9, 22, 3, 2, shoes)
	_rect(4, 23, 3, 1, shoes.darkened(0.35))
	_rect(9, 23, 3, 1, shoes.darkened(0.35))

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
	if hair_style != 0:
		_rect(6, 1, 3, 1, hair.lightened(0.25))

	_outline()
	return _image


func _rect(x: int, y: int, w: int, h: int, color: Color) -> void:
	_image.fill_rect(Rect2i(x + BORDER, y + BORDER, w, h), color)


## Darkens every empty pixel that touches the character, so it reads on any background.
func _outline() -> void:
	var source := _image.duplicate() as Image
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < source.get_width() and n.y < source.get_height() \
						and source.get_pixel(n.x, n.y).a > 0.0:
					_image.set_pixel(x, y, OUTLINE)
					break


func _color(palette: String, key: String) -> Color:
	var colors: Array = options.get(palette, [])
	var index: int = appearance.get(key, 0)
	return Color(colors[index]) if index >= 0 and index < colors.size() else Color.MAGENTA
