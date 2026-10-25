extends Control
## Character editor, shown once after registering.

var _appearance := {
	"skinTone": 1, "hairStyle": 1, "hairColor": 1, "shirtStyle": 0,
	"shirtColor": 7, "pantsColor": 8, "shoesColor": 1, "faceStyle": 0, "eyeColor": 0, "facialHair": 0,
}
var _preview: CharacterPreview
var _rows := AppearanceRows.new()
var _name: LineEdit
var _error: Label
var _create: Button


func _ready() -> void:
	var box := UI.centered_panel(self, 640)
	box.add_child(UI.title("Stwórz swoją postać"))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)

	_preview = CharacterPreview.new()
	_preview.display_scale = 0.6
	_preview.options = Game.appearance_options
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	columns.add_child(_preview)

	_rows.set_appearance(_appearance)
	_rows.changed.connect(_refresh)
	columns.add_child(_rows)

	_name = UI.line_edit("Nazwa postaci (3–16 znaków)")
	_name.max_length = 16
	box.add_child(_name)

	_error = UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
	_error.visible = false
	box.add_child(_error)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Losuj", _rows.randomize_look))
	_create = UI.button("Stwórz postać", _submit, true)
	buttons.add_child(_create)
	box.add_child(buttons)

	_refresh()


func _refresh() -> void:
	_appearance = _rows.appearance.duplicate()
	_preview.appearance = _appearance.duplicate()


func _submit() -> void:
	_create.disabled = true
	_error.text = ""
	var reply := await Net.request("character.create", {"name": _name.text.strip_edges(), "appearance": _appearance})
	if reply["type"] == "character":
		Game.character = reply["payload"]
		Game.watch_achievements()
		get_tree().change_scene_to_file(Game.GARAGE_SCENE)
		return
	_error.text = Game.error_text(reply)
	_error.visible = true
	_create.disabled = false
