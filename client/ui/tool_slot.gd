class_name ToolSlot
extends HBoxContainer
## The tool bar: the slots of the tools in the player's hand (one, two or three with a backpack
## on) and the backpack worn. Click a slot to pick another tool or backpack from the inventory or
## to put it away; Game.character follows the server's reply.

## After a tool or the backpack changed; the inventory changed with it.
signal changed
## When the server refused, with its error reply.
signal failed(reply: Dictionary)

const TOOLS := ["tool_axe", "tool_chainsaw", "tool_shovel", "tool_pickaxe", "tool_bronze_pickaxe", "tool_steel_pickaxe", "tool_hoe", "tool_shears"]
## Backpacks from the cheapest; each adds inventory tiles, any gives a second tool slot,
## the dearest a third. Follows the server's Items.Backpacks.
const BACKPACKS := ["backpack_school", "backpack_hiking", "backpack_trekking", "backpack_expedition", "backpack_tycoon"]
const UNEQUIP := 1000
## The slot `open` is about: a tool slot's index, or this for the backpack.
const BACKPACK_SLOT := -2

var _tool_tiles: Array[PanelContainer] = []
var _backpack_tile: PanelContainer
var _menu := PopupMenu.new()
var _choices: Array[String] = []
var _menu_slot := 0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_menu.add_theme_constant_override("icon_max_width", 28)
	_menu.id_pressed.connect(_on_choice)
	add_child(_menu)
	refresh()


## Shows the tools and the backpack from Game.character.
func refresh() -> void:
	var slots := Game.tool_slots()
	while _tool_tiles.size() < slots.size():
		var tile := _tile("Q" if _tool_tiles.is_empty() else "", _tool_tiles.size())
		add_child(tile)
		_tool_tiles.append(tile)
	while _tool_tiles.size() > slots.size():
		var gone: PanelContainer = _tool_tiles.pop_back()
		remove_child(gone)
		gone.queue_free()
	for i in slots.size():
		var held: Variant = slots[i]
		var icon: TextureRect = _tool_tiles[i].get_meta("icon")
		icon.visible = held is Dictionary
		if held is Dictionary:
			icon.texture = UI.texture("icons/item_" + held["id"])
			_tool_tiles[i].tooltip_text = "Narzędzie: %s\nKliknij, aby zmienić" % held["name"]
		else:
			_tool_tiles[i].tooltip_text = "Narzędzie: brak\nKliknij, aby wziąć narzędzie z ekwipunku"
	if _backpack_tile == null:
		_backpack_tile = _tile("", BACKPACK_SLOT)
		add_child(_backpack_tile)
	move_child(_backpack_tile, -1)
	var worn := Game.backpack()
	var bag: TextureRect = _backpack_tile.get_meta("icon")
	bag.texture = UI.item_texture(worn["id"] if not worn.is_empty() else "backpack_school")
	bag.modulate = Color.WHITE if not worn.is_empty() else Color(1, 1, 1, 0.25)
	if worn.is_empty():
		_backpack_tile.tooltip_text = "Plecak: brak\nPlecak z rynku powiększa ekwipunek i dokłada slot na narzędzie.\nKliknij, aby założyć plecak z ekwipunku"
	else:
		_backpack_tile.tooltip_text = "Plecak: %s\n+%d miejsc w ekwipunku, %d sloty na narzędzia\nKliknij, aby zmienić" % [
			worn["name"], int(worn["extraSlots"]), int(worn["toolSlots"])]
	_shrink.call_deferred()


## Fits the panel around the bar again: it keeps its size when slots go, leaving a gap.
func _shrink() -> void:
	var box: Control = self
	while box.get_parent() is Container:
		box = box.get_parent()
	box.reset_size()


## The list of tools (or backpacks) in the inventory, next to a slot: the first empty tool slot
## by default, so [Q] fills the tool bar before it swaps.
func open(slot := -1) -> void:
	if slot == -1:
		slot = maxi(0, Game.tool_slots().find(null))
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		failed.emit(reply)
		return
	_menu_slot = slot
	_menu.clear()
	_choices.clear()
	var kinds: Array = BACKPACKS if slot == BACKPACK_SLOT else TOOLS
	for stack: Dictionary in reply["payload"]["items"]:
		var item: String = stack["id"]
		if item in kinds:
			_menu.add_icon_item(UI.item_texture(item), ("Załóż: %s" if slot == BACKPACK_SLOT else "Weź: %s") % stack["name"], _choices.size())
			_choices.append(item)
	if slot == BACKPACK_SLOT and not Game.backpack().is_empty():
		_menu.add_item("Zdejmij plecak", UNEQUIP)
	elif slot >= 0 and slot < Game.tool_slots().size() and Game.tool_slots()[slot] is Dictionary:
		_menu.add_item("Schowaj do ekwipunku", UNEQUIP)
	if _menu.item_count == 0:
		_menu.add_item("Nie masz plecaka. Kupisz go u handlarza na rynku." if slot == BACKPACK_SLOT
			else "Nie masz narzędzi. Dostaniesz je za zakup działki.", -1)
		_menu.set_item_disabled(0, true)
	_menu.reset_size()
	var tile: Control = _backpack_tile if slot == BACKPACK_SLOT else _tool_tiles[mini(slot, _tool_tiles.size() - 1)]
	var at := tile.get_screen_transform() * Vector2(0, 0)
	_menu.popup(Rect2i(Vector2i(at) - Vector2i(0, _menu.size.y + 4), Vector2i.ZERO))


func _on_choice(id: int) -> void:
	if id == UNEQUIP:
		if _menu_slot == BACKPACK_SLOT:
			_send("character.unequip", {"backpack": true})
		else:
			_send("character.unequip", {"slot": _menu_slot})
	elif id >= 0 and id < _choices.size():
		equip(_choices[id], _menu_slot)


## Takes a tool from the inventory into the tool bar (`slot`, or the first free one), or puts a
## backpack on; "" puts the tool from the first slot away.
func equip(item: String, slot := -1) -> void:
	if item == "":
		_send("character.unequip", {"slot": maxi(slot, 0)})
	elif item in BACKPACKS or slot < 0:
		_send("character.equip", {"item": item})
	else:
		_send("character.equip", {"item": item, "slot": slot})


func _send(type: String, payload: Dictionary) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "character":
		failed.emit(reply)
		return
	Game.character = reply["payload"]
	refresh()
	changed.emit()


## One slot of the bar: a frame with an icon, and the key that opens it in the corner.
func _tile(key: String, slot: int) -> PanelContainer:
	var tile := PanelContainer.new()
	var frame := StyleBoxTexture.new()
	frame.texture = UI.texture("ui/inset")
	frame.set_texture_margin_all(8)
	frame.set_content_margin_all(4)
	tile.add_theme_stylebox_override("panel", frame)
	tile.custom_minimum_size = Vector2(60, 60)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			open(slot)
			tile.accept_event())
	var icon := UI.icon("item_tool_axe", 50)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(icon)
	tile.set_meta("icon", icon)
	if key != "":
		var label := UI.label(key, UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		label.add_theme_font_size_override("font_size", 12)
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(label)
	return tile
