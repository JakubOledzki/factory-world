class_name InventoryGrid
extends GridContainer
## The tiles of the player's inventory: 20, more with a backpack on; each holds one kind of item.
## Kinds beyond the tiles (given back while the inventory was full) show after them, in red. Drag an item onto another tile to move it there (onto
## an item, they swap places); the server keeps the order. Works with the mouse and with a
## finger, which Godot turns into a mouse. A tap or click without dragging emits `clicked`.

## The player clicked an item; the screen decides what that does (e.g. take a tool in hand).
signal clicked(item: String)
## The server answered a move with the new inventory.
signal changed(items: Array)
## The server refused a move, with its error reply.
signal failed(reply: Dictionary)

const COLUMNS := 5
const MIN_TILES := 20
## Size of a tile; bigger on touch screens, so a finger can hit and drag it.
const TILE := 52
const TOUCH_TILE := 68
## A press that moves less than this is a click, not a drag.
const CLICK_SLOP := 8.0

## Returns the extra tooltip line of an item, e.g. "Kliknij, aby postawić", or "" when a click
## does nothing.
var hint := func(_item: String) -> String: return ""
## Tiles of the inventory, as the server counts them.
var slots := MIN_TILES


func _init() -> void:
	columns = COLUMNS
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)


## Shows the inventory from the server: items with their tiles.
func show_items(inventory: Dictionary) -> void:
	var by_slot := {}
	var last := -1
	for i in inventory["items"].size():
		var stack: Dictionary = inventory["items"][i]
		var slot: int = int(stack["slot"]) if stack.get("slot") != null else i
		by_slot[slot] = stack
		last = maxi(last, slot)
	slots = int(inventory.get("slots", MIN_TILES))
	for child in get_children():
		child.free()
	var count := maxi(ceili(slots / float(COLUMNS)) * COLUMNS, ceili((last + 1) / float(COLUMNS)) * COLUMNS)
	for slot in count:
		add_child(Tile.new(self, slot, by_slot.get(slot, {})))


## Moves the item at once, then asks the server; its reply (or a refusal) redraws the tiles.
func _move(from: Tile, to: Tile) -> void:
	if from == to or from.stack.is_empty():
		return
	var item: String = from.stack["id"]
	var moved := from.stack
	from.set_stack(to.stack)
	to.set_stack(moved)
	var reply := await Net.request("inventory.move", {"item": item, "slot": to.slot})
	if reply["type"] == "inventory":
		show_items(reply["payload"])
		changed.emit(reply["payload"]["items"])
		return
	failed.emit(reply)
	var fresh := await Net.request("inventory.get")
	if fresh["type"] == "inventory":
		show_items(fresh["payload"])
		changed.emit(fresh["payload"]["items"])


## One tile; it can hold one stack of items.
class Tile extends PanelContainer:
	var slot := 0
	var stack := {}
	var _grid: InventoryGrid
	var _icon: TextureRect
	var _count: Label
	var _press := Vector2.INF
	var _dragged := false
	var _lit := false

	func _init(grid: InventoryGrid, index: int, items: Dictionary) -> void:
		_grid = grid
		slot = index
		var frame := StyleBoxTexture.new()
		frame.texture = UI.texture("ui/inset")
		frame.set_texture_margin_all(8)
		frame.set_content_margin_all(3)
		add_theme_stylebox_override("panel", frame)
		var tile := TOUCH_TILE if UI.touch() else TILE
		custom_minimum_size = Vector2(tile, tile)
		_icon = TextureRect.new()
		_icon.custom_minimum_size = Vector2(tile - 8, tile - 8)
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(_icon)
		_count = UI.label("", Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		_count.size_flags_horizontal = Control.SIZE_SHRINK_END
		_count.size_flags_vertical = Control.SIZE_SHRINK_END
		_count.add_theme_font_override("font", UI.bold())
		_count.add_theme_font_size_override("font_size", 13)
		_count.add_theme_constant_override("outline_size", 4)
		_count.add_theme_color_override("font_outline_color", UI.BACKGROUND)
		_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_count)
		mouse_exited.connect(_light.bind(false))
		set_stack(items)

	func set_stack(items: Dictionary) -> void:
		stack = items
		_icon.visible = not items.is_empty()
		_count.visible = not items.is_empty()
		modulate = Color.WHITE if slot < _grid.slots else Color(1.0, 0.55, 0.5, 0.8 if items.is_empty() else 1.0)
		if slot >= _grid.slots and items.is_empty():
			modulate.a = 0.0
		if items.is_empty():
			remove_meta("item")
			tooltip_text = ""
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			return
		_icon.texture = UI.item_texture(items["id"])
		set_meta("item", items["id"])
		_count.text = str(int(items["quantity"]))
		tooltip_text = "%s: %d" % [items["name"], int(items["quantity"])]
		var hint: String = _grid.hint.call(items["id"])
		if not hint.is_empty():
			tooltip_text += "\n" + hint
		if slot >= _grid.slots:
			tooltip_text += "\nNie mieści się w ekwipunku: przenieś na wolny kafelek albo załóż większy plecak"
		tooltip_text += "\nPrzeciągnij, aby przenieść"
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			return
		if event.pressed:
			_press = event.position
			_dragged = false
		elif not _dragged and not stack.is_empty() and event.position.distance_to(_press) < CLICK_SLOP:
			_press = Vector2.INF
			_grid.clicked.emit(stack["id"])

	func _get_drag_data(_at: Vector2) -> Variant:
		if stack.is_empty():
			return null
		_dragged = true
		modulate = Color(1, 1, 1, 0.35)
		# The icon under the pointer; on touch screens above the finger, so it stays in sight.
		var preview := Control.new()
		var icon := UI.item_icon(stack["id"], 56)
		icon.position = -icon.custom_minimum_size / 2 - (Vector2(0, 50) if UI.touch() else Vector2.ZERO)
		icon.size = icon.custom_minimum_size
		preview.add_child(icon)
		set_drag_preview(preview)
		return {"inventory_tile": self}

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and data.has("inventory_tile") and is_instance_valid(data["inventory_tile"]) \
			and data["inventory_tile"]._grid == _grid and slot < _grid.slots
		_light(ok and data["inventory_tile"] != self)
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_light(false)
		_grid._move(data["inventory_tile"], self)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_light(false)
			if not stack.is_empty():
				set_stack(stack)

	## Marks the tile an item would land on.
	func _light(on: bool) -> void:
		if on != _lit:
			_lit = on
			queue_redraw()

	func _draw() -> void:
		if _lit:
			draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), UI.GOLD, false, 2.0)
