class_name ConfirmDialog
extends PanelContainer
## A small card in the middle of the screen that asks before something big happens: a title, a few
## lines on what it will do and two buttons, one that does it and one that calls it off.

static var _open: ConfirmDialog

var _done := Callable()


## Asks over `parent` whether to go on; `verb` is the button that does it and calls `done`.
static func ask(parent: Control, title: String, text: String, verb: String, done: Callable) -> ConfirmDialog:
	close()
	var dialog := ConfirmDialog.new()
	dialog._done = done
	dialog._build(title, text, verb)
	parent.add_child(dialog)
	_open = dialog
	var screen := dialog.get_viewport_rect().size
	dialog.custom_minimum_size.x = minf(420, screen.x - 24)
	dialog.reset_size()
	dialog.position = ((screen - dialog.size) / 2).max(Vector2.ZERO)
	return dialog


## Whether a question is waiting for an answer.
static func asking() -> bool:
	return is_instance_valid(_open)


static func close() -> void:
	if is_instance_valid(_open):
		_open.queue_free()
	_open = null


func _build(title: String, text: String, verb: String) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := UI.label(title, UI.GOLD)
	head.add_theme_font_override("font", UI.bold())
	box.add_child(head)
	box.add_child(UI.label(text, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var cancel := UI.button("Anuluj", close)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel)
	var go := UI.button(verb, _finish, true)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(go)
	box.add_child(buttons)


func _finish() -> void:
	var done := _done
	close()
	done.call()
