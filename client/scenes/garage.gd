extends Control
## The player's garage: the rendered room with furniture the player can move, and the
## character, who walks with WSAD or by clicking. Sorting opens at the trash bin; the
## inventory and the market are windows opened from the toolbar.

const SLOTS := 20
## The garage is lit by one bulb, so the character is drawn darker than in the editor.
const ROOM_LIGHT := Color(0.74, 0.7, 0.66)
## How close to a piece of furniture (in metres, from the edge of its footprint) the player
## must stand to use it, and when the sorting window closes again after walking away.
const REACH := 0.55
const LEAVE := 1.2
## Furniture is placed on this grid; the walking paths use it too. Metres.
const GRID := 0.1
const BIN := "furniture_trash_bin"

## Keyboard actions of this screen: name and keys.
const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E],
	"inventory": [KEY_I],
	"market": [KEY_M],
	"cancel": [KEY_ESCAPE],
}

var _garage := {}
var _items: Array = []
var _prices: Array = []
var _balance := 0
## Server time minus local time, in ms, so timers follow the server's clock.
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _room := Vector2(8, 6)
## Name and footprint (width, depth) of every kind of furniture, from the server.
var _furniture_info := {}
## Furniture on the floor by id.
var _objects := {}
var _astar := AStarGrid2D.new()

var _shadows: Node2D
var _footprint: Polygon2D
var _sorted: Node2D
var _player: GaragePlayer
var _overlay: Control

## Where the player is walking after a click, and what to do on arrival.
var _path: PackedVector2Array = []
var _on_arrival := Callable()
var _hovered: Furniture
var _menu: PanelContainer
var _menu_box: VBoxContainer

## The kind of furniture being placed, and its see-through copy following the mouse.
var _placing := ""
var _ghost: Furniture
var _ghost_valid := false

var _prompt: Label
var _bin_status: VBoxContainer
var _bin_bar: ProgressBar
var _bin_text: Label
var _toast: Label
var _toast_tween: Tween

var _level: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _money: Label

var _sorting_window: GameWindow
var _inventory_window: GameWindow
var _market_window: GameWindow

var _trash: Label
var _sort_buttons: Array[Button] = []
var _queue_text: Label
var _job_bar: ProgressBar
var _job_text: Label
var _recent: HFlowContainer
var _slots: GridContainer
var _market: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in ACTIONS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)
	_build_room()
	_build_hud()
	_build_windows()
	_build_menu()
	_refresh_character()
	_load()


# --- Room ------------------------------------------------------------------------

func _build_room() -> void:
	var background := Sprite2D.new()
	background.texture = load("res://art/garage/background.jpg")
	background.centered = false
	add_child(background)

	# Shadows lie on the floor under everything; the rest is drawn back to front.
	_shadows = Node2D.new()
	add_child(_shadows)
	_footprint = Polygon2D.new()
	_footprint.visible = false
	_footprint.z_index = 1
	add_child(_footprint)
	_sorted = Node2D.new()
	_sorted.y_sort_enabled = true
	add_child(_sorted)

	var layout := RoomProjection.layout()
	_player = GaragePlayer.new(Game.character.get("appearance", {}), Game.appearance_options)
	_player.light = ROOM_LIGHT
	_shadows.add_child(_player.shadow)
	_sorted.add_child(_player)
	_player.move_to(Vector2(layout["player"]["x"], layout["player"]["y"]))

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_prompt = _outlined(UI.label("[E] Segreguj", UI.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_prompt.visible = false
	_overlay.add_child(_prompt)

	# Sorting progress over the bin, visible while something is being sorted.
	_bin_status = VBoxContainer.new()
	_bin_status.add_theme_constant_override("separation", 0)
	_bin_status.visible = false
	_bin_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bin_text = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_bin_text.add_theme_font_size_override("font_size", 13)
	_bin_status.add_child(_bin_text)
	_bin_bar = ProgressBar.new()
	_bin_bar.show_percentage = false
	_bin_bar.custom_minimum_size = Vector2(70, 8)
	_bin_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bin_status.add_child(_bin_bar)
	_overlay.add_child(_bin_status)

	_toast = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_toast.size = Vector2(800, 30)
	_toast.position = Vector2(240, 628)
	_toast.modulate.a = 0.0
	_overlay.add_child(_toast)


func _outlined(label: Label) -> Label:
	label.add_theme_font_override("font", UI.bold())
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bin() -> Furniture:
	for object: Furniture in _objects.values():
		if object.kind == BIN:
			return object
	return null


## Shows the furniture the server sent: adds new pieces, moves and removes the others.
func _sync_objects(objects: Array) -> void:
	var seen := {}
	for object: Dictionary in objects:
		var id: String = object["id"]
		seen[id] = true
		var pos := Vector2(object["x"], object["y"])
		if _objects.has(id):
			_objects[id].move_to(pos)
			continue
		var piece := Furniture.new(object, _furniture_info.get(object["kind"], {}))
		_objects[id] = piece
		_shadows.add_child(piece.shadow)
		_sorted.add_child(piece)
	for id: String in _objects.keys():
		if not seen.has(id):
			var piece: Furniture = _objects[id]
			_objects.erase(id)
			if piece == _hovered:
				_hovered = null
			piece.shadow.queue_free()
			piece.queue_free()
	_rebuild_paths()


# --- Walking ---------------------------------------------------------------------

## Whether the player can stand at a floor position.
func _free(pos: Vector2) -> bool:
	var r := GaragePlayer.RADIUS
	if pos.x < r or pos.y < r or pos.x > _room.x - r or pos.y > _room.y - r * 0.5:
		return false
	for object: Furniture in _objects.values():
		if object.rect().grow(r).has_point(pos):
			return false
	return true


func _rebuild_paths() -> void:
	_astar.region = Rect2i(0, 0, roundi(_room.x / GRID), roundi(_room.y / GRID))
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for x in _astar.region.size.x:
		for y in _astar.region.size.y:
			_astar.set_point_solid(Vector2i(x, y), not _free(_cell_centre(Vector2i(x, y))))


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i((pos / GRID).floor()).clamp(Vector2i.ZERO, _astar.region.size - Vector2i.ONE)


func _cell_centre(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * GRID


## Walks to a floor position along a path around the furniture, then calls `arrival`.
func _walk_to(target: Vector2, arrival := Callable()) -> void:
	var from := _cell(_player.floor_pos)
	var was_solid := _astar.is_point_solid(from)
	_astar.set_point_solid(from, false)
	var cells := _astar.get_id_path(from, _cell(target), true)
	_astar.set_point_solid(from, was_solid)
	_path = PackedVector2Array()
	for i in range(1, cells.size()):
		_path.append(_cell_centre(cells[i]))
	if not cells.is_empty() and cells[-1] == _cell(target) and _free(target):
		if _path.is_empty():
			_path.append(target)
		else:
			_path[-1] = target
	_on_arrival = arrival
	if _path.is_empty():
		_arrive()


func _arrive() -> void:
	var arrival := _on_arrival
	_on_arrival = Callable()
	if arrival.is_valid():
		arrival.call()


## Walks next to a piece of furniture, then calls `action` if it is within reach.
func _walk_up_to(object: Furniture, action: Callable) -> void:
	if _near(object):
		action.call()
		return
	var spot := object.rect().grow(GaragePlayer.RADIUS + 0.12)
	var target := _player.floor_pos.clamp(spot.position, spot.end)
	_walk_to(target, func() -> void:
		if is_instance_valid(object) and _objects.has(object.id) and _near(object):
			action.call()
		else:
			_show_toast("Nie da się tam podejść.", UI.ERROR))


func _near(object: Furniture, distance := REACH) -> bool:
	var r := object.rect()
	var p := _player.floor_pos
	return p.distance_to(p.clamp(r.position, r.end)) <= distance


func _move_player(delta: float) -> void:
	var step := Vector2.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_down", "move_up")
	if _placing == "" and input != Vector2.ZERO:
		_path = PackedVector2Array()
		_on_arrival = Callable()
		step = input * GaragePlayer.SPEED * delta
	elif not _path.is_empty():
		var to_next := _path[0] - _player.floor_pos
		var length := GaragePlayer.SPEED * delta
		if to_next.length() <= length:
			step = to_next
			_path.remove_at(0)
		else:
			step = to_next.normalized() * length
	var start := _player.floor_pos
	var pos := start
	# Slide along whatever blocks the way, one axis at a time.
	if _free(pos + Vector2(step.x, 0)):
		pos.x += step.x
	if _free(pos + Vector2(0, step.y)):
		pos.y += step.y
	_player.walking = pos.distance_to(start) > 0.0001
	if _player.walking:
		_player.face(step)
		_player.move_to(pos)
	elif not _path.is_empty():
		_path = PackedVector2Array()  # Stuck: give up instead of pushing against a wall.
	if _path.is_empty() and _on_arrival.is_valid():
		_arrive()


# --- Mouse -----------------------------------------------------------------------

func _object_at(screen: Vector2) -> Furniture:
	var best: Furniture = null
	for object: Furniture in _objects.values():
		if object.hit(screen) and (best == null or object.position.y > best.position.y):
			best = object
	return best


func _update_hover() -> void:
	var over_ui := get_viewport().gui_get_hovered_control() != null
	var found: Furniture = null
	if not over_ui and _placing == "" and not _menu.visible:
		found = _object_at(get_global_mouse_position())
	if found != _hovered:
		if _hovered != null and is_instance_valid(_hovered):
			_hovered.set_highlighted(false)
		_hovered = found
		if found != null:
			found.set_highlighted(true)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if found != null else Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse := get_global_mouse_position()
		_update_hover()  # The mouse may have moved since the last frame.
		if _placing != "":
			if event.button_index == MOUSE_BUTTON_LEFT:
				_confirm_place()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				_stop_placing()
		elif _menu.visible:
			_menu.visible = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if _hovered != null:
				_open_menu(_hovered, mouse)
			else:
				var target := RoomProjection.to_floor(mouse)
				if Rect2(Vector2.ZERO, _room).has_point(target):
					_walk_to(target)
		elif event.button_index == MOUSE_BUTTON_RIGHT and _hovered != null:
			_open_menu(_hovered, mouse)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel"):
		if _placing != "":
			_stop_placing()
		elif _menu.visible:
			_menu.visible = false
		else:
			for window: GameWindow in [_sorting_window, _inventory_window, _market_window]:
				window.hide_window()
	elif event.is_action_pressed("interact"):
		var bin := _bin()
		if bin != null and _near(bin):
			_sorting_window.toggle()
	elif event.is_action_pressed("inventory"):
		_inventory_window.toggle()
	elif event.is_action_pressed("market"):
		_market_window.toggle()


func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.visible = false
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 4)
	_menu.add_child(_menu_box)
	add_child(_menu)


## The actions of a piece of furniture, next to the mouse.
func _open_menu(object: Furniture, at: Vector2) -> void:
	for child in _menu_box.get_children():
		child.free()
	var title := UI.label(object.display_name, UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	_menu_box.add_child(title)
	var actions := []
	if object.kind == BIN:
		actions.append(["Użyj  [E]", _walk_up_to.bind(object, _sorting_window.show_window)])
	actions.append(["Przenieś", _walk_up_to.bind(object, _pick_up.bind(object, true))])
	actions.append(["Schowaj do ekwipunku", _walk_up_to.bind(object, _pick_up.bind(object, false))])
	for action: Array in actions:
		var callback: Callable = action[1]
		var b := UI.button(action[0], func() -> void:
			_menu.visible = false
			callback.call())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_menu_box.add_child(b)
	_menu.reset_size()
	_menu.visible = true
	_menu.position = (at + Vector2(12, 4)).clamp(Vector2.ZERO, get_viewport_rect().size - _menu.get_combined_minimum_size())
	_update_hover()


# --- Moving furniture --------------------------------------------------------------

func _pick_up(object: Furniture, then_place: bool) -> void:
	var kind := object.kind
	var piece_name := object.display_name
	var reply := await Net.request("garage.pickup", {"id": object.id})
	if reply["type"] != "garage":
		_show_error(reply)
		return
	_apply_garage(reply["payload"])
	await _reload_inventory()
	if then_place:
		_start_placing(kind)
	else:
		_show_toast("%s: schowano do ekwipunku." % piece_name)


func _start_placing(kind: String) -> void:
	_stop_placing()
	if _count(kind) < 1:
		return
	_placing = kind
	_inventory_window.hide_window()
	_menu.visible = false
	_path = PackedVector2Array()
	_ghost = Furniture.new({"kind": kind}, _furniture_info.get(kind, {}))
	_ghost.z_index = 2  # Over everything, so it shows even behind tall furniture.
	_sorted.add_child(_ghost)
	_footprint.visible = true
	_update_ghost()
	_show_toast("Kliknij, aby postawić. Prawy przycisk myszy lub Esc anuluje.")


func _stop_placing() -> void:
	_placing = ""
	_footprint.visible = false
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


func _update_ghost() -> void:
	var size := _ghost.footprint
	var pos := RoomProjection.to_floor(get_global_mouse_position())
	# Snap so the edges, not the centre, land on the grid; keep it inside the room.
	var corner := ((pos - size / 2) / GRID).round() * GRID
	corner = corner.clamp(Vector2.ZERO, _room - size)
	_ghost.move_to(corner + size / 2)
	var rect := _ghost.rect()
	_ghost_valid = not rect.grow(GaragePlayer.RADIUS).has_point(_player.floor_pos)
	for object: Furniture in _objects.values():
		if rect.grow(-0.001).intersects(object.rect().grow(-0.001)):
			_ghost_valid = false
	_ghost.set_ghost(_ghost_valid)
	var corners := PackedVector2Array()
	for c: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		corners.append(RoomProjection.to_screen(c))
	_footprint.polygon = corners
	_footprint.color = Color(0.4, 0.9, 0.3, 0.35) if _ghost_valid else Color(1.0, 0.3, 0.2, 0.35)


func _confirm_place() -> void:
	if not _ghost_valid:
		_show_toast("Tu nie można tego postawić.", UI.ERROR)
		return
	var kind := _placing
	var pos := _ghost.floor_pos
	_stop_placing()
	var reply := await Net.request("garage.place", {"kind": kind, "x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01)})
	if reply["type"] != "garage":
		_show_error(reply)
		return
	_apply_garage(reply["payload"])
	_reload_inventory()


# --- HUD -------------------------------------------------------------------------

func _build_hud() -> void:
	var parts := UI.panel(2)
	var hud: PanelContainer = parts[0]
	hud.position = Vector2(12, 12)
	add_child(hud)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parts[1].add_child(row)

	var portrait := CharacterPreview.new()
	portrait.options = Game.appearance_options
	portrait.appearance = Game.character.get("appearance", {})
	portrait.region = Rect2(0.15, 0.06, 0.7, 0.22)
	portrait.display_scale = 0.6
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	var name_label := UI.label(Game.character.get("name", ""))
	name_label.add_theme_font_override("font", UI.bold())
	name_row.add_child(name_label)
	_level = UI.label("", UI.GOLD)
	_level.add_theme_font_override("font", UI.bold())
	name_row.add_child(_level)
	info.add_child(name_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(160, 10)
	info.add_child(_xp_bar)
	_xp_text = UI.label("", UI.MUTED)
	_xp_text.add_theme_font_size_override("font_size", 13)
	info.add_child(_xp_text)

	var money_parts := UI.panel(0)
	var money_panel: PanelContainer = money_parts[0]
	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 6)
	money_row.add_child(UI.icon("coin", 22))
	_money = UI.label("", UI.GOLD)
	_money.add_theme_font_override("font", UI.bold())
	_money.add_theme_font_size_override("font_size", 17)
	money_row.add_child(_money)
	money_parts[1].add_child(money_row)
	add_child(money_panel)
	money_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	money_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	# Toolbar at the bottom: the windows and logging out.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.add_child(UI.button("Ekwipunek  [I]", func() -> void: _inventory_window.toggle()))
	bar.add_child(UI.button("Rynek  [M]", func() -> void: _market_window.toggle()))
	bar.add_child(UI.button("Wyloguj", Game.logout))
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 10)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _refresh_character() -> void:
	var c := Game.character
	var xp: int = c.get("xp", 0)
	var level_xp: int = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	_level.text = "Poziom %d" % c.get("level", 1)
	_xp_bar.max_value = (next_xp - level_xp) if next_xp != null else 1.0
	_xp_bar.value = xp - level_xp if next_xp != null else 1.0
	_xp_text.text = "%d / %d XP" % [xp, next_xp] if next_xp != null else "%d XP" % xp


## Applies an XP gain from the server; level thresholds follow the server's formula 200 × (L − 1)².
func _gain_xp(gain: Dictionary) -> void:
	var level: int = gain["level"]
	Game.character["xp"] = gain["xp"]
	Game.character["level"] = level
	Game.character["levelXp"] = 200 * (level - 1) * (level - 1)
	Game.character["nextLevelXp"] = 200 * level * level
	_refresh_character()
	if gain.get("leveledUp", false):
		_banner("Awans! Poziom %d" % level)


# --- Windows ---------------------------------------------------------------------

func _build_windows() -> void:
	_sorting_window = GameWindow.new("Kosz na śmieci", 320)
	_sorting_window.position = Vector2(1280 - 320 - 12, 64)
	_build_sorting(_sorting_window.content)
	_inventory_window = GameWindow.new("Ekwipunek", 0)
	_inventory_window.position = Vector2(12, 120)
	_build_storage(_inventory_window.content)
	_market_window = GameWindow.new("Rynek", 340)
	_market_window.position = Vector2(1280 - 340 - 12, 64)
	_build_market(_market_window.content)
	for window: GameWindow in [_sorting_window, _inventory_window, _market_window]:
		add_child(window)


func _build_sorting(page: VBoxContainer) -> void:
	var bin := HBoxContainer.new()
	bin.add_theme_constant_override("separation", 8)
	bin.add_child(UI.item_icon("trash", 40))
	var bin_text := VBoxContainer.new()
	bin_text.add_theme_constant_override("separation", 0)
	bin_text.alignment = BoxContainer.ALIGNMENT_CENTER
	_trash = UI.label("")
	_trash.add_theme_font_override("font", UI.bold())
	bin_text.add_child(_trash)
	bin_text.add_child(UI.label("Worek: 10 s, losowy surowiec i 5 XP", UI.MUTED))
	bin.add_child(bin_text)
	page.add_child(bin)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	for count in [1, 10]:
		var b := UI.button("Segreguj %d" % count, _sort.bind(count), count == 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
		_sort_buttons.append(b)
	page.add_child(buttons)

	_queue_text = UI.label("", UI.MUTED)
	page.add_child(_queue_text)
	var job := HBoxContainer.new()
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size.y = 10
	_job_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job.add_child(_job_bar)
	_job_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_job_text.custom_minimum_size.x = 36
	job.add_child(_job_text)
	page.add_child(job)

	page.add_child(UI.label("Ostatnio wysegregowane:", UI.MUTED))
	_recent = HFlowContainer.new()
	_recent.add_theme_constant_override("h_separation", 2)
	_recent.add_theme_constant_override("v_separation", 2)
	_recent.custom_minimum_size.y = 32
	page.add_child(_recent)


func _build_storage(page: VBoxContainer) -> void:
	_slots = GridContainer.new()
	_slots.columns = 5
	_slots.add_theme_constant_override("h_separation", 4)
	_slots.add_theme_constant_override("v_separation", 4)
	page.add_child(_slots)
	page.add_child(UI.label("Kliknij mebel, aby go postawić.", UI.MUTED))


func _build_market(page: VBoxContainer) -> void:
	_market = VBoxContainer.new()
	_market.add_theme_constant_override("separation", 2)
	page.add_child(_market)


# --- Data from the server -------------------------------------------------------------

func _load() -> void:
	var replies := [
		await Net.request("garage.get"),
		await Net.request("inventory.get"),
		await Net.request("wallet.get"),
		await Net.request("market.prices"),
	]
	for reply: Dictionary in replies:
		if reply["type"] == "error":
			_show_error(reply)
			return
	_prices = replies[3]["payload"]["items"]
	_apply_garage(replies[0]["payload"])
	_apply_inventory(replies[1]["payload"])
	_set_balance(int(replies[2]["payload"]["balanceCents"]))


func _apply_garage(garage: Dictionary) -> void:
	_garage = garage
	_clock_offset = float(garage["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_room = Vector2(garage["room"]["width"], garage["room"]["depth"])
	_furniture_info = garage["furniture"]
	_sync_objects(garage["objects"])
	_trash.text = "Śmieci: %d" % garage["trash"]

	var results: Array = garage.get("results", [])
	for i in results.size():
		var item: Dictionary = results[i]
		_float_text("+1 %s" % item["name"], UI.TEXT, i * 0.25)
		var icon := UI.item_icon(item["id"], 30)
		icon.tooltip_text = item["name"]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_recent.add_child(icon)
		_recent.move_child(icon, 0)
	while _recent.get_child_count() > 18:
		_recent.get_child(_recent.get_child_count() - 1).free()
	if garage.get("xp") != null:
		_float_text("+%d XP" % (results.size() * 5), UI.GOLD, 0.0, -24)
		_gain_xp(garage["xp"])
	if not results.is_empty():
		_reload_inventory()
	_update_queue()


func _apply_inventory(inventory: Dictionary) -> void:
	_items = inventory["items"]
	for child in _slots.get_children():
		child.free()
	for i in maxi(SLOTS, ceili(_items.size() / 5.0) * 5):
		_slots.add_child(_slot(_items[i] if i < _items.size() else {}))
	_rebuild_market()


func _reload_inventory() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] == "inventory":
		_apply_inventory(reply["payload"])


func _set_balance(cents: int) -> void:
	_balance = cents
	_money.text = UI.money(cents)
	_rebuild_market()


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


# --- Every frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_move_player(delta)
	if _placing != "":
		_update_ghost()
	_update_hover()
	_update_bin()
	if _garage.is_empty():
		return
	_update_queue()
	var queue: Array = _garage["queue"]
	var now := _server_now()
	if not queue.is_empty() and now >= float(queue[0]) and now >= _next_poll and not _refreshing:
		_collect()


## The "[E]" prompt next to the bin, and the sorting progress over it.
func _update_bin() -> void:
	var bin := _bin()
	if bin == null:
		_sorting_window.hide_window()
		_prompt.visible = false
		_bin_status.visible = false
		return
	if _sorting_window.visible and not _near(bin, LEAVE):
		_sorting_window.hide_window()
	_prompt.visible = _near(bin) and not _sorting_window.visible and _placing == ""
	var top := RoomProjection.to_screen(bin.floor_pos, 1.25)
	_prompt.reset_size()
	_prompt.position = top - Vector2(_prompt.size.x / 2, _prompt.size.y + 26)
	var queue: Array = _garage.get("queue", [])
	_bin_status.visible = not queue.is_empty()
	if _bin_status.visible:
		var total: float = _garage.get("sortSeconds", 10) * 1000.0
		_bin_bar.max_value = total
		_bin_bar.value = total - maxf(float(queue[0]) - _server_now(), 0.0)
		_bin_text.text = "Segregacja: %d" % queue.size()
		_bin_status.reset_size()
		_bin_status.position = top - Vector2(_bin_status.size.x / 2, _bin_status.size.y)


# --- Sorting --------------------------------------------------------------------------

func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


## Asks the server for the garage; it hands out the sortings that have finished.
func _collect() -> void:
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("garage.get")
	_refreshing = false
	if reply["type"] == "garage":
		_apply_garage(reply["payload"])


func _update_queue() -> void:
	var queue: Array = _garage.get("queue", [])
	var max_queue: int = _garage.get("maxQueue", 10)
	var trash: int = _garage.get("trash", 0)
	var free := max_queue - queue.size()
	_queue_text.text = "Kolejka: %d / %d" % [queue.size(), max_queue]
	_sort_buttons[0].disabled = free < 1 or trash < 1
	_sort_buttons[1].disabled = free < 1 or trash < 1
	var batch := mini(mini(free, trash), 10)
	_sort_buttons[1].text = "Segreguj %d" % (batch if batch > 0 else 10)

	if queue.is_empty():
		_job_bar.value = 0
		_job_text.text = ""
		return
	var total: float = _garage.get("sortSeconds", 10) * 1000.0
	var left := maxf(float(queue[0]) - _server_now(), 0.0)
	_job_bar.max_value = total
	_job_bar.value = total - left
	_job_text.text = "%d s" % ceili(left / 1000.0)


func _sort(count: int) -> void:
	var queue: Array = _garage.get("queue", [])
	count = mini(count, mini(_garage.get("maxQueue", 10) - queue.size(), _garage.get("trash", 0)))
	if count < 1:
		_show_error({"payload": {"code": "queue_full" if _garage.get("trash", 0) > 0 else "not_enough_items"}})
		return
	_pulse()
	var reply := await Net.request("recycling.sort", {"count": count})
	if reply["type"] == "garage":
		_apply_garage(reply["payload"])
	else:
		_show_error(reply)


# --- Inventory and market -----------------------------------------------------------------

func _slot(stack: Dictionary) -> Control:
	var slot := PanelContainer.new()
	var frame := StyleBoxTexture.new()
	frame.texture = UI.texture("ui/inset")
	frame.set_texture_margin_all(8)
	frame.set_content_margin_all(3)
	slot.add_theme_stylebox_override("panel", frame)
	slot.custom_minimum_size = Vector2(52, 52)
	if stack.is_empty():
		return slot
	var item: String = stack["id"]
	slot.tooltip_text = "%s: %d" % [stack["name"], int(stack["quantity"])]
	if _furniture_info.has(item):
		# Furniture: click to place it in the garage.
		slot.tooltip_text += "\nKliknij, aby postawić"
		slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		slot.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_start_placing(item))
	var icon := UI.item_icon(item, 44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_child(icon)
	var count := UI.label(str(int(stack["quantity"])), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	count.add_theme_font_override("font", UI.bold())
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_constant_override("outline_size", 4)
	count.add_theme_color_override("font_outline_color", UI.BACKGROUND)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(count)
	return slot


func _rebuild_market() -> void:
	for child in _market.get_children():
		child.free()
	for price: Dictionary in _prices:
		var item: String = price["id"]
		var owned := _count(item)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.add_child(UI.item_icon(item, 26))
		var name_label := UI.label(price["name"])
		name_label.add_theme_font_override("font", UI.bold())
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		top.add_child(UI.label("masz %d" % owned, UI.MUTED))
		_market.add_child(top)

		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 4)
		var buying: bool = price.get("sellCents") == null
		var cents := int(price["buyCents"] if buying else price["sellCents"])
		var price_label := UI.label(("cena %s" if buying else "skup %s") % UI.money(cents), UI.GOLD if buying else UI.GOOD)
		price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(price_label)
		if buying:
			for amount in [1, 10]:
				var b := UI.button("Kup %d" % amount, _trade.bind("market.buy", item, amount))
				b.disabled = _balance < cents * amount
				bottom.add_child(b)
		else:
			var one := UI.button("Sprzedaj 1", _trade.bind("market.sell", item, 1))
			var all := UI.button("Wszystko", _trade.bind("market.sell", item, -1))
			one.disabled = owned < 1
			all.disabled = owned < 1
			bottom.add_child(one)
			bottom.add_child(all)
		_market.add_child(bottom)


## quantity -1 sells everything the player has.
func _trade(type: String, item: String, quantity: int) -> void:
	if quantity < 0:
		quantity = mini(_count(item), 1000)
	var reply := await Net.request(type, {"item": item, "quantity": quantity})
	if reply["type"] != "market.traded":
		_show_error(reply)
		return
	_set_balance(int(reply["payload"]["balanceCents"]))
	await _reload_inventory()
	if item == "trash":
		var garage := await Net.request("garage.get")
		if garage["type"] == "garage":
			_apply_garage(garage["payload"])


# --- Effects ---------------------------------------------------------------------------

func _float_text(text: String, color: Color, delay := 0.0, lift := 0) -> void:
	var bin := _bin()
	var origin := RoomProjection.to_screen(bin.floor_pos, 1.3) if bin != null else _player.position + Vector2(0, -150)
	var l := _outlined(UI.label(text, color, HORIZONTAL_ALIGNMENT_CENTER))
	l.add_theme_font_size_override("font_size", 17)
	l.modulate.a = 0.0
	l.size = Vector2(240, 26)
	var start := origin + Vector2(-120, -60 + lift)
	l.position = start
	_overlay.add_child(l)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(l, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(l, "position:y", start.y - 50, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "modulate:a", 0.0, 0.4)
	tween.tween_callback(l.queue_free)


func _banner(text: String) -> void:
	var l := UI.title(text, 40)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.size = Vector2(1280, 60)
	l.position = Vector2(0, 260)
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ZERO
	_overlay.add_child(l)
	var tween := create_tween()
	tween.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.0)
	tween.tween_property(l, "modulate:a", 0.0, 0.5)
	tween.tween_callback(l.queue_free)


## Flashes the bin, as feedback that sorting started.
func _pulse() -> void:
	var bin := _bin()
	if bin == null:
		return
	var tween := create_tween()
	tween.tween_property(bin, "modulate", Color(1.6, 1.5, 1.2), 0.08)
	tween.tween_property(bin, "modulate", Color.WHITE, 0.35)


func _show_toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _show_error(reply: Dictionary) -> void:
	_show_toast(Game.error_text(reply), UI.ERROR)
