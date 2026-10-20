extends Control
## Character editor, shown once after registering.

## Editor rows: label, appearance key and how many options it has.
const ROWS := [
	["Skóra", "skinTone", "skinTones"],
	["Fryzura", "hairStyle", "hairStyles"],
	["Kolor włosów", "hairColor", "hairColors"],
	["Koszulka", "shirtStyle", "shirtStyles"],
	["Kolor koszulki", "shirtColor", "clothColors"],
	["Spodnie", "pantsColor", "clothColors"],
	["Buty", "shoesColor", "clothColors"],
]

const HAIR_STYLES := ["łysy", "krótkie", "nastroszone", "długie", "kucyk", "kręcone"]
const SHIRT_STYLES := ["t-shirt", "bezrękawnik", "bluza"]

var _appearance := {
	"skinTone": 1, "hairStyle": 1, "hairColor": 1, "shirtStyle": 0,
	"shirtColor": 7, "pantsColor": 8, "shoesColor": 1,
}
var _preview: CharacterPreview
var _values := {}
var _name: LineEdit
var _error: Label
var _create: Button


func _ready() -> void:
	var box := UI.centered_panel(self, 380)
	box.add_child(UI.title("Stwórz swoją postać"))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	box.add_child(columns)

	_preview = CharacterPreview.new()
	_preview.pixel = 5
	_preview.options = Game.appearance_options
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(_preview)

	var rows := GridContainer.new()
	rows.columns = 4
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(rows)
	for row: Array in ROWS:
		var key: String = row[1]
		rows.add_child(UI.label(row[0], UI.MUTED))
		rows.add_child(UI.button("<", _step.bind(key, -1)))
		var value := UI.label("", Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.custom_minimum_size.x = 80
		_values[key] = value
		rows.add_child(value)
		rows.add_child(UI.button(">", _step.bind(key, 1)))

	_name = UI.line_edit("Nazwa postaci (3–16 znaków)")
	_name.max_length = 16
	box.add_child(_name)

	_error = UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
	_error.visible = false
	box.add_child(_error)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Losuj", _randomize))
	_create = UI.button("Stwórz postać", _submit, true)
	buttons.add_child(_create)
	box.add_child(buttons)

	_refresh()


func _count(key: String) -> int:
	for row: Array in ROWS:
		if row[1] == key:
			var option: Variant = Game.appearance_options.get(row[2], 1)
			return option.size() if option is Array else int(option)
	return 1


func _step(key: String, delta: int) -> void:
	_appearance[key] = posmod(_appearance[key] + delta, _count(key))
	_refresh()


func _randomize() -> void:
	for row: Array in ROWS:
		_appearance[row[1]] = randi() % _count(row[1])
	_refresh()


func _refresh() -> void:
	for row: Array in ROWS:
		var key: String = row[1]
		var index: int = _appearance[key]
		var text := "%d / %d" % [index + 1, _count(key)]
		if key == "hairStyle" and index < HAIR_STYLES.size():
			text = HAIR_STYLES[index]
		elif key == "shirtStyle" and index < SHIRT_STYLES.size():
			text = SHIRT_STYLES[index]
		_values[key].text = text
	_preview.appearance = _appearance.duplicate()


func _submit() -> void:
	_create.disabled = true
	_error.text = ""
	var reply := await Net.request("character.create", {"name": _name.text.strip_edges(), "appearance": _appearance})
	if reply["type"] == "character":
		Game.character = reply["payload"]
		get_tree().change_scene_to_file(Game.GARAGE_SCENE)
		return
	_error.text = Game.error_text(reply)
	_error.visible = true
	_create.disabled = false
