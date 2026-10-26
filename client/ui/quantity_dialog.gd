class_name QuantityDialog
extends PanelContainer
## A small card over a window that asks how many pieces to move: a slider, quick choices and one
## button that does it. Phones use it in place of Shift-click (InventoryGrid, StorageWindow).

static var _open: QuantityDialog

var _most := 1
var _done := Callable()
var _slider := HSlider.new()
var _count: Label
var _go: Button
var _verb := ""


## Asks over `window` how many of `item` (1 to `most`) to move, then calls `done` with the number.
## `verb` names what happens, e.g. "Włóż" or "Weź".
static func ask(window: Control, item: String, name: String, verb: String, most: int, done: Callable) -> void:
	if is_instance_valid(_open):
		_open.queue_free()
	var dialog := QuantityDialog.new()
	dialog._most = most
	dialog._done = done
	dialog._verb = verb
	dialog._build(item, name)
	window.get_parent().add_child(dialog)
	_open = dialog
	dialog.reset_size()
	var screen := dialog.get_viewport_rect().size
	dialog.position = (window.position + (window.size - dialog.size) / 2).clamp(Vector2.ZERO, (screen - dialog.size).max(Vector2.ZERO))


func _build(item: String, name: String) -> void:
	custom_minimum_size.x = 360
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UI.item_icon(item, 30))
	var title := UI.label("%s: %s" % [_verb, name], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	box.add_child(head)

	_slider.min_value = 1
	_slider.max_value = _most
	_slider.step = 1
	_slider.value = _most
	_slider.custom_minimum_size.y = 32
	_slider.value_changed.connect(func(_value: float) -> void: _show())
	box.add_child(_slider)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	for choice: Array in [["1", 1], ["Połowa", maxi(1, _most / 2)], ["Wszystko", _most]]:
		var b := UI.button(choice[0], func() -> void: _slider.value = choice[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(b)
	box.add_child(quick)
	_count = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_count)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var cancel := UI.button("Anuluj", queue_free)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(cancel)
	_go = UI.button("", _finish, true)
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_go)
	box.add_child(buttons)
	_show()


func _show() -> void:
	var n := int(_slider.value)
	_count.text = "%d z %d" % [n, _most]
	_go.text = "%s %d" % [_verb, n]


func _finish() -> void:
	_done.call(int(_slider.value))
	queue_free()
