class_name ItemTooltip
extends CanvasLayer
## With Ctrl held, the item under the mouse gets a small card next to it: its name, category,
## what it is for and where it comes from (ItemInfo). Any control showing an item marks it with
## the meta "item" (UI.item_icon does); a row whose icon is marked counts too.

const WIDTH := 320

var _panel := PanelContainer.new()
var _icon := TextureRect.new()
var _name: Label
var _category: Label
var _about: Label
var _source: Label
var _item := ""


func _init() -> void:
	layer = 100
	_panel.visible = false
	# A layer does not pass the screen's theme on to its controls.
	_panel.theme = UI.theme()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = WIDTH * (UI.TOUCH_SCALE if UI.touch() else 1.0)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(40, 40)
	head.add_child(_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	_name = UI.label("", UI.GOLD)
	_name.add_theme_font_override("font", UI.bold())
	names.add_child(_name)
	_category = UI.label("", UI.MUTED)
	names.add_child(_category)
	head.add_child(names)
	box.add_child(head)
	_about = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_about)
	box.add_child(UI.label("Skąd:", UI.MUTED))
	_source = UI.label("", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_source)
	for node: Node in box.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var item := _hovered_item() if Input.is_key_pressed(KEY_CTRL) else ""
	if item == "" or not ItemInfo.ITEMS.has(item):
		_panel.visible = false
		_item = ""
		return
	if item != _item:
		_item = item
		_icon.texture = UI.item_texture(item)
		_name.text = ItemInfo.name_of(item)
		_category.text = ItemInfo.CATEGORIES[ItemInfo.category_of(item)][0]
		_about.text = ItemInfo.description(item)
		_source.text = ItemInfo.source(item)
	_panel.visible = true
	# Wrapped lines know their height only once laid out, so the card is fitted every frame.
	_panel.reset_size()
	# Beside the pointer, turned inwards near the right and bottom edges of the screen.
	var viewport := _panel.get_viewport()
	var screen := viewport.get_visible_rect().size
	var at := viewport.get_mouse_position() + Vector2(18, 18)
	if at.x + _panel.size.x > screen.x:
		at.x -= _panel.size.x + 30
	if at.y + _panel.size.y > screen.y:
		at.y = screen.y - _panel.size.y - 4
	_panel.position = at.max(Vector2.ZERO)


## The item of the control under the mouse, of one of its parents, or of an icon in its row.
func _hovered_item() -> String:
	var node: Node = _panel.get_viewport().gui_get_hovered_control()
	for i in 4:
		if node == null:
			return ""
		if node.has_meta("item"):
			return node.get_meta("item")
		if node is HBoxContainer:
			for child in node.get_children():
				if child.has_meta("item"):
					return child.get_meta("item")
		node = node.get_parent()
	return ""
