class_name AppearanceRows
extends GridContainer
## The rows of the character editor: a "<" and ">" button per part of the look (skin, hair, face,
## shirt...), stepping through the options the server allows. Used when the character is made and
## when the player pays for a new look.

signal changed

## Label, appearance key and the option holding the palette or the number of styles.
const ROWS := [
	["Skóra", "skinTone", "skinTones"],
	["Twarz", "faceStyle", "faceStyles"],
	["Oczy", "eyeColor", "eyeColors"],
	["Fryzura", "hairStyle", "hairStyles"],
	["Kolor włosów", "hairColor", "hairColors"],
	["Zarost", "facialHair", "facialHairStyles"],
	["Koszulka", "shirtStyle", "shirtStyles"],
	["Kolor koszulki", "shirtColor", "clothColors"],
	["Spodnie", "pantsColor", "clothColors"],
	["Buty", "shoesColor", "clothColors"],
]

## Names of the styles, in the renderer's order (tools/render_character.py).
const NAMES := {
	"hairStyle": ["łysy", "krótkie", "nastroszone", "długie", "kucyk", "kręcone"],
	"shirtStyle": ["t-shirt", "bezrękawnik", "bluza"],
	"faceStyle": ["spokojna", "zmęczona", "pogodna", "dojrzała"],
	"facialHair": ["gładko ogolony", "wąsy", "kozia bródka", "pełna broda"],
}

## The look being edited: an index per appearance key.
var appearance := {}

var _values := {}
var _swatches := {}


## `per_line` rows side by side: two fit a phone's wide screen without scrolling.
func _init(per_line := 1) -> void:
	columns = 4 * per_line
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Array in ROWS:
		var key: String = row[1]
		add_child(UI.label(row[0], UI.MUTED))
		add_child(UI.button("<", _step.bind(key, -1)))
		var value := HBoxContainer.new()
		value.alignment = BoxContainer.ALIGNMENT_CENTER
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size.x = 140
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value.add_child(swatch)
		var text := UI.label("", Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		value.add_child(text)
		_swatches[key] = swatch
		_values[key] = text
		add_child(value)
		add_child(UI.button(">", _step.bind(key, 1)))


## Shows a look; keys it lacks start at the first option.
func set_appearance(look: Dictionary) -> void:
	appearance = {}
	for row: Array in ROWS:
		appearance[row[1]] = int(look.get(row[1], 0))
	_refresh()


func randomize_look() -> void:
	for row: Array in ROWS:
		appearance[row[1]] = randi() % _count(row[1])
	_refresh()
	changed.emit()


func _count(key: String) -> int:
	for row: Array in ROWS:
		if row[1] == key:
			var option: Variant = Game.appearance_options.get(row[2], 1)
			return maxi(1, option.size() if option is Array else int(option))
	return 1


func _step(key: String, delta: int) -> void:
	appearance[key] = posmod(appearance.get(key, 0) + delta, _count(key))
	_refresh()
	changed.emit()


func _refresh() -> void:
	for row: Array in ROWS:
		var key: String = row[1]
		var index: int = appearance.get(key, 0)
		var names: Array = NAMES.get(key, [])
		_values[key].text = names[index] if index < names.size() else "%d / %d" % [index + 1, _count(key)]
		var palette: Variant = Game.appearance_options.get(row[2])
		_swatches[key].visible = palette is Array and index < palette.size()
		if _swatches[key].visible:
			_swatches[key].color = Color(palette[index])
