class_name Hotbar
extends HBoxContainer
## The quick bar: five numbered slots, each holding an item from the inventory (belts, inserters, a
## furnace...). Key 1 to 5 or a click (a tap) on a slot picks its item up, as a click on it in the
## inventory would: a belt goes straight into placing. An empty slot, a right click or a long press
## opens a list to put another item there; an item dragged from the inventory lands on the slot it
## is dropped on. The server keeps the slots, so they stay after logging in again; the number in a
## slot's corner is how many the inventory holds.

## The player picked the item of a slot (key or click) and holds some.
signal selected(item: String)
## The server refused, with its error reply.
signal failed(reply: Dictionary)
## A slot's item has run out; the screen tells the player.
signal empty(item: String)

const SLOTS := 5
const TILE := 56
## Holding a finger on a slot this long (seconds) opens its list instead of picking the item.
const HOLD_FOR := 0.5
const CLEAR := 1000

## Whether an item can go on the bar: the screen says which items a click does something with.
var can_hold := func(_item: String) -> bool: return true
## The item of each slot, "" for an empty one.
var items: Array[String] = []
var _tiles: Array[Tile] = []
## Item id → how many the inventory holds, and its name.
var _counts := {}
var _names := {}
var _active := ""
var _menu := PopupMenu.new()
var _menu_slot := 0
var _choices: Array[String] = []


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_menu.add_theme_constant_override("icon_max_width", 28)
	_menu.id_pressed.connect(_on_choice)
	add_child(_menu)
	for slot in SLOTS:
		items.append("")
		var tile := Tile.new(self, slot)
		add_child(tile)
		_tiles.append(tile)
	_redraw()


## Loads the slots from the server.
func reload() -> void:
	var reply := await Net.request("hotbar.get")
	if reply["type"] == "hotbar":
		_show(reply["payload"])


## Takes the counts and names from the inventory's items.
func set_items(stacks: Array) -> void:
	_counts.clear()
	for stack: Dictionary in stacks:
		_counts[stack["id"]] = int(stack["quantity"])
		_names[stack["id"]] = stack["name"]
	_redraw()


## Marks the slot of the item being used (placed, planted...), or none for "".
func mark(item: String) -> void:
	if item != _active:
		_active = item
		_redraw()


## Picks the item of a slot (0 to 4), as key 1 to 5 does; an empty slot opens its list.
func use(slot: int) -> void:
	var item := items[slot]
	if item == "":
		open(slot)
	elif int(_counts.get(item, 0)) <= 0:
		empty.emit(item)
	else:
		selected.emit(item)


## Puts an item on a slot ("" empties it); the item leaves the slot it was on.
func assign(slot: int, item: String) -> void:
	var reply := await Net.request("hotbar.set", {"slot": slot, "item": item if item != "" else null})
	if reply["type"] != "hotbar":
		failed.emit(reply)
		return
	_show(reply["payload"])


## The list of items to put on a slot, from the inventory, above the slot.
func open(slot: int) -> void:
	_menu_slot = slot
	_menu.clear()
	_choices.clear()
	for item: String in _counts:
		if int(_counts[item]) > 0 and can_hold.call(item) and item != items[slot]:
			_menu.add_icon_item(UI.item_texture(item), "%s (%d)" % [_names.get(item, item), int(_counts[item])], _choices.size())
			_choices.append(item)
	if items[slot] != "":
		_menu.add_item("Opróżnij slot %d" % (slot + 1), CLEAR)
	if _menu.item_count == 0:
		_menu.add_item("Nie masz niczego do postawienia. Taśmociągi, podajniki i maszyny zrobisz przy stole albo kupisz.", -1)
		_menu.set_item_disabled(0, true)
	_menu.reset_size()
	var at := _tiles[slot].get_screen_transform() * Vector2(0, 0)
	_menu.popup(Rect2i(Vector2i(at) - Vector2i(0, _menu.size.y + 4), Vector2i.ZERO))


func _on_choice(id: int) -> void:
	if id == CLEAR:
		assign(_menu_slot, "")
	elif id >= 0 and id < _choices.size():
		assign(_menu_slot, _choices[id])


func _show(payload: Dictionary) -> void:
	var slots: Array = payload["slots"]
	for slot in SLOTS:
		items[slot] = slots[slot] if slot < slots.size() and slots[slot] != null else ""
	_redraw()


func _redraw() -> void:
	for tile in _tiles:
		tile.show_item(items[tile.slot], int(_counts.get(items[tile.slot], 0)), _names.get(items[tile.slot], items[tile.slot]), items[tile.slot] == _active and _active != "")


## One slot: the key's number in the top left corner, the item's icon and how many are left.
class Tile extends PanelContainer:
	var slot := 0
	var _bar: Hotbar
	var _icon: TextureRect
	var _count: Label
	var _lit := false
	var _active := false
	var _held := -1.0

	func _init(bar: Hotbar, index: int) -> void:
		_bar = bar
		slot = index
		var frame := StyleBoxTexture.new()
		frame.texture = UI.texture("ui/inset")
		frame.set_texture_margin_all(8)
		frame.set_content_margin_all(4)
		add_theme_stylebox_override("panel", frame)
		var tile := TILE * (UI.TOUCH_SCALE if UI.touch() else 1.0)
		custom_minimum_size = Vector2(tile, tile)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_icon = TextureRect.new()
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.custom_minimum_size = Vector2(tile - 12, tile - 12)
		_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_icon)
		var key := UI.label(str(index + 1), UI.MUTED)
		key.add_theme_font_override("font", UI.bold())
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_constant_override("outline_size", 4)
		key.add_theme_color_override("font_outline_color", UI.BACKGROUND)
		key.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(key)
		_count = UI.label("", Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		_count.add_theme_font_override("font", UI.bold())
		_count.add_theme_font_size_override("font_size", 13)
		_count.add_theme_constant_override("outline_size", 4)
		_count.add_theme_color_override("font_outline_color", UI.BACKGROUND)
		_count.size_flags_horizontal = Control.SIZE_SHRINK_END
		_count.size_flags_vertical = Control.SIZE_SHRINK_END
		_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_count)
		mouse_exited.connect(_light.bind(false))

	func show_item(item: String, count: int, name: String, active: bool) -> void:
		_icon.visible = item != ""
		_count.visible = item != ""
		if item == "":
			tooltip_text = "Slot %d: pusty\nKliknij albo przeciągnij tu przedmiot z ekwipunku" % (slot + 1)
		else:
			_icon.texture = UI.item_texture(item)
			# A slot whose item ran out stays, greyed out, until the player gets more.
			_icon.modulate = Color.WHITE if count > 0 else Color(1, 1, 1, 0.3)
			_count.text = str(count)
			_count.add_theme_color_override("font_color", Color.WHITE if count > 0 else UI.ERROR)
			tooltip_text = "[%d] %s: %d\nKliknij, aby użyć; prawy przycisk zmienia przedmiot" % [slot + 1, name, count]
		if active != _active:
			_active = active
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_bar.open(slot)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_held = 0.0
			elif _held >= 0.0:
				_held = -1.0
				_bar.use(slot)
			accept_event()

	func _process(delta: float) -> void:
		if _held < 0.0:
			return
		_held += delta
		if _held >= HOLD_FOR:
			# A long press (a finger has no right button) opens the list; lifting the finger then picks nothing.
			_held = -1.0
			_bar.open(slot)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and data.has("inventory_tile") and is_instance_valid(data["inventory_tile"]) \
			and not data["inventory_tile"].stack.is_empty() and _bar.can_hold.call(data["inventory_tile"].stack["id"])
		_light(ok)
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_light(false)
		_bar.assign(slot, data["inventory_tile"].stack["id"])

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_light(false)

	func _light(on: bool) -> void:
		if on != _lit:
			_lit = on
			queue_redraw()

	func _draw() -> void:
		if _lit or _active:
			draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), UI.GOLD, false, 2.0 if _lit else 3.0)
