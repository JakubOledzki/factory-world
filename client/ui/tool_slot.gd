class_name ToolSlot
extends PanelContainer
## The slot of the tool in the player's hand. Click it to pick another tool from the inventory
## or to put the tool away; Game.character follows the server's reply.

## After the tool changed; the inventory changed with it.
signal changed
## When the server refused, with its error reply.
signal failed(reply: Dictionary)

const TOOLS := ["tool_axe", "tool_shovel", "tool_pickaxe"]
const UNEQUIP := 1000

var _icon: TextureRect
var _menu := PopupMenu.new()
var _choices: Array[String] = []


func _ready() -> void:
	var frame := StyleBoxTexture.new()
	frame.texture = UI.texture("ui/inset")
	frame.set_texture_margin_all(8)
	frame.set_content_margin_all(4)
	add_theme_stylebox_override("panel", frame)
	custom_minimum_size = Vector2(60, 60)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_input)

	_icon = UI.icon("item_tool_axe", 50)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	var key := UI.label("Q", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	key.add_theme_font_size_override("font_size", 12)
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key)

	_menu.add_theme_constant_override("icon_max_width", 28)
	_menu.id_pressed.connect(_on_choice)
	add_child(_menu)
	refresh()


## Shows the tool from Game.character.
func refresh() -> void:
	var held := Game.tool()
	_icon.visible = not held.is_empty()
	if held.is_empty():
		tooltip_text = "Narzędzie: brak\nKliknij, aby wziąć narzędzie z ekwipunku"
	else:
		_icon.texture = UI.texture("icons/item_" + held["id"])
		tooltip_text = "Narzędzie: %s\nKliknij, aby zmienić" % held["name"]


## The list of tools in the inventory, next to the slot.
func open() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		failed.emit(reply)
		return
	_menu.clear()
	_choices.clear()
	for stack: Dictionary in reply["payload"]["items"]:
		var item: String = stack["id"]
		if item in TOOLS:
			_menu.add_icon_item(UI.texture("icons/item_" + item), "Weź: %s" % stack["name"], _choices.size())
			_choices.append(item)
	if not Game.tool().is_empty():
		_menu.add_item("Schowaj do ekwipunku", UNEQUIP)
	if _menu.item_count == 0:
		_menu.add_item("Nie masz narzędzi. Dostaniesz je za zakup działki.", -1)
		_menu.set_item_disabled(0, true)
	_menu.reset_size()
	var at := get_screen_transform() * Vector2(0, 0)
	_menu.popup(Rect2i(Vector2i(at) - Vector2i(0, _menu.size.y + 4), Vector2i.ZERO))


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open()
		accept_event()


func _on_choice(id: int) -> void:
	if id == UNEQUIP:
		equip("")
	elif id >= 0 and id < _choices.size():
		equip(_choices[id])


## Takes a tool from the inventory into the hand; "" puts the tool in hand away.
func equip(item: String) -> void:
	var reply: Dictionary
	if item == "":
		reply = await Net.request("character.unequip")
	else:
		reply = await Net.request("character.equip", {"item": item})
	if reply["type"] != "character":
		failed.emit(reply)
		return
	Game.character = reply["payload"]
	refresh()
	changed.emit()
