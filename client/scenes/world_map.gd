extends Control
## The world map: the Earth in plots of 5 × 5 km, coloured by biome, with town names. Drag to move
## it, scroll or pinch to zoom, click a plot to see its biome, owner and price, and buy it.

## Keyboard actions of this screen: name and keys.
const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"zoom_in": [KEY_EQUAL, KEY_KP_ADD],
	"zoom_out": [KEY_MINUS, KEY_KP_SUBTRACT],
	"legend": [KEY_L],
	"cancel": [KEY_ESCAPE],
}

## Screen pixels per plot when zoomed in all the way.
const MAX_ZOOM := 48.0
## Plot borders are drawn from this zoom; owned plots are loaded from the server from AREA_ZOOM.
const AREA_ZOOM := 1.5
const PAN_SPEED := 700.0
## How far (pixels) the mouse may move between press and release to still count as a click.
const CLICK_SLOP := 6.0
## At most this many town names on screen at once.
const MAX_LABELS := 160
const MINE := Color("#f5b041")
const OTHERS := Color("#d4553f")
## Deposit sizes as the server numbers them.
const DEPOSITS := ["brak", "małe złoże", "średnie złoże", "duże złoże"]
## The coast biome, whose seabed may hold oil as well.
const COAST := 10

## Loaded once and kept, so the map opens instantly the second time.
static var _data: WorldData

var _biomes := {}
var _my_plots: Array[Vector2i] = []
## Owned plots loaded around the view: Vector2i → true when they are the player's.
var _owned := {}
var _balance := 0
var _next_base_price := 0

## The point of the map (in plots) in the middle of the screen, and pixels per plot.
var _center := Vector2.ZERO
var _zoom := 1.0
var _area_in := 0.0

## Set once the map and the interface exist.
var _built := false
var _world: Node2D
var _materials: Array[ShaderMaterial] = []
var _overlay: Control

var _pressed := false
var _dragged := false
var _press_at := Vector2.ZERO
var _touches := {}
var _pinch := 0.0
var _hovered := Vector2i(-1, -1)
var _selected := Vector2i(-1, -1)
var _my_index := -1

## Interface over the map; town names keep clear of it.
var _hud: Array[Control] = []
var _status: Label
var _money: Label
var _search: LineEdit
var _mine_button: Button
var _legend: PanelContainer
var _toast: Label
var _toast_tween: Tween
var _loading: Label

var _panel: PanelContainer
var _plot_box: VBoxContainer
var _buy: Button
var _plot := {}
var _confirming := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key: Key in ACTIONS[action]:
				var event := InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)

	var background := ColorRect.new()
	background.color = WorldData.COLORS[WorldData.OCEAN] * Color(0.86, 0.88, 0.92)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_loading = UI.title("Wczytywanie mapy świata...", 22)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_loading)
	# Let the screen show the message before the map files are read.
	await get_tree().process_frame
	await get_tree().process_frame

	if _data == null:
		var data := WorldData.new()
		if not data.load_files():
			_loading.text = "Nie udało się wczytać mapy."
			return
		_data = data
	_loading.queue_free()
	_build_map()
	_build_hud()
	_built = true
	resized.connect(_apply_camera)
	_center = _data.from_geo(30.0, 15.0)
	_zoom = 0.0
	_apply_camera()
	if Game.plot.x >= 0:
		_go_to(Game.plot, 16.0)
	_load()


# --- Map ---------------------------------------------------------------------------

func _build_map() -> void:
	_world = Node2D.new()
	add_child(_world)
	var colors := PackedVector3Array()
	for color in WorldData.COLORS:
		colors.append(Vector3(color.r, color.g, color.b))
	# Two strips, each drawn three times (the map wraps around east to west).
	var strip := ceili(_data.width / 2.0)
	for part in 2:
		var columns := mini(strip, _data.width - part * strip)
		var texture := _data.texture(part * strip, columns)
		var material := ShaderMaterial.new()
		material.shader = load("res://world/world_map.gdshader")
		material.set_shader_parameter("colors", colors)
		material.set_shader_parameter("strip_size", Vector2(columns, _data.height))
		material.set_shader_parameter("strip_from", part * strip)
		_materials.append(material)
		for copy in [-1, 0, 1]:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.centered = false
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.material = material
			sprite.position = Vector2(copy * _data.width + part * strip, 0)
			_world.add_child(sprite)

	# Darker edges, like a map under a desk lamp.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.6))
	gradient.add_point(0.55, Color(0, 0, 0, 0))
	var vignette_texture := GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(0.5, 0.5)
	vignette_texture.fill_to = Vector2(1.05, 1.05)
	var vignette := TextureRect.new()
	vignette.texture = vignette_texture
	vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Keeps the view on the map, moves the map under it and redraws what lies on top.
func _apply_camera() -> void:
	if not _built:
		return
	var min_zoom := maxf(size.y / _data.height, size.x / _data.width)
	_zoom = clampf(_zoom, min_zoom, MAX_ZOOM)
	_center.x = fposmod(_center.x, _data.width)
	var half := size.y / 2.0 / _zoom
	_center.y = clampf(_center.y, half, _data.height - half)
	_world.scale = Vector2(_zoom, _zoom)
	_world.position = (size / 2.0 - _center * _zoom).round()
	for material in _materials:
		material.set_shader_parameter("zoom", _zoom)
	_overlay.queue_redraw()
	_area_in = 0.3


func _zoom_at(factor: float, screen: Vector2) -> void:
	var before := _to_map(screen)
	_zoom *= factor
	_apply_camera()
	_center += before - _to_map(screen)
	_apply_camera()


## Map point (in plots, not wrapped) under a point of the screen.
func _to_map(screen: Vector2) -> Vector2:
	return (screen - size / 2.0) / _zoom + _center


func _plot_at(screen: Vector2) -> Vector2i:
	var point := _to_map(screen).floor()
	return Vector2i(posmod(int(point.x), _data.width), int(point.y))


## Screen position of a map point, taking the short way round the globe.
func _to_screen(point: Vector2) -> Vector2:
	return Vector2(_data.wrap_dx(point.x - _center.x), point.y - _center.y) * _zoom + size / 2.0


func _go_to(plot: Vector2i, zoom: float) -> void:
	_center = Vector2(plot) + Vector2(0.5, 0.5)
	_zoom = zoom
	_apply_camera()


# --- Input -------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not _built:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				_zoom_at(1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.2, event.position)
		elif event.pressed:
			_pressed = true
			_dragged = false
			_press_at = event.position
			if event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
				_zoom_at(2.0, event.position)
		else:
			if _pressed and not _dragged and event.button_index == MOUSE_BUTTON_LEFT:
				_select(_plot_at(event.position))
			_pressed = false
		accept_event()
	elif event is InputEventMouseMotion:
		if _pressed and event.button_mask != 0:
			if not _dragged and event.position.distance_to(_press_at) > CLICK_SLOP:
				_dragged = true
			if _dragged and _touches.size() < 2:
				_center -= event.relative / _zoom
				_apply_camera()
		_hover(event.position)
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.factor, event.position)
	elif event is InputEventPanGesture:
		_center += event.delta * 12.0 / _zoom
		_apply_camera()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch = 0.0
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			# Two fingers: pinch to zoom around the point between them.
			var points: Array = _touches.values()
			var distance: float = points[0].distance_to(points[1])
			if _pinch > 0.0:
				_zoom_at(distance / _pinch, (points[0] + points[1]) / 2.0)
			_pinch = distance
			_dragged = true


func _unhandled_input(event: InputEvent) -> void:
	if not _built:
		return
	if event.is_action_pressed("cancel"):
		if _panel.visible:
			_close_panel()
		else:
			Game.open_garage()
	elif event.is_action_pressed("legend"):
		_toggle_legend()


func _process(delta: float) -> void:
	if not _built:
		return
	if not get_viewport().gui_get_focus_owner() is LineEdit:
		var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if move != Vector2.ZERO:
			_center += move * PAN_SPEED * delta / _zoom
			_apply_camera()
		var zoom := Input.get_axis("zoom_out", "zoom_in")
		if zoom != 0.0:
			_zoom_at(pow(3.0, zoom * delta), size / 2.0)
	if _area_in > 0.0:
		_area_in -= delta
		if _area_in <= 0.0:
			_load_area()


func _hover(screen: Vector2) -> void:
	var plot := _plot_at(screen)
	if plot == _hovered:
		return
	_hovered = plot
	if plot.y < 0 or plot.y >= _data.height:
		_status.text = ""
		return
	var parts := [_biome_name(_data.biome(plot)), WorldData.geo_text(_data.to_geo(Vector2(plot) + Vector2(0.5, 0.5)))]
	var town := _data.nearest_town(plot)
	if town >= 0:
		parts.append("okolice: %s" % _data.town_names[town])
	if _owned.has(plot):
		parts.append("Twoja działka" if _owned[plot] else "działka zajęta")
	_status.text = "  ·  ".join(parts)
	if _zoom >= 4.0:
		_overlay.queue_redraw()


# --- Drawing over the map ----------------------------------------------------------

func _draw_overlay() -> void:
	var plot_size := Vector2(_zoom, _zoom)
	for plot: Vector2i in _owned:
		var at := _to_screen(Vector2(plot))
		if Rect2(Vector2.ZERO, size).grow(_zoom).has_point(at):
			var color := MINE if _owned[plot] else OTHERS
			var rect := Rect2(at, plot_size.max(Vector2(3, 3)))
			_overlay.draw_rect(rect, Color(color, 0.45))
			if _zoom >= 4.0:
				_overlay.draw_rect(rect, color, false, 2.0)
	if _zoom < 6.0:
		# Too small to see a plot: mark the player's own with pins.
		for plot in _my_plots:
			_draw_pin(_to_screen(Vector2(plot) + Vector2(0.5, 0.5)), MINE)

	if _zoom >= 4.0 and _hovered.y >= 0 and _hovered.y < _data.height:
		_overlay.draw_rect(Rect2(_to_screen(Vector2(_hovered)), plot_size), Color(1, 1, 1, 0.55), false, 1.0)
	if _selected.y >= 0:
		var at := _to_screen(Vector2(_selected))
		if _zoom >= 4.0:
			_overlay.draw_rect(Rect2(at, plot_size).grow(1.0), Color.BLACK, false, 4.0)
			_overlay.draw_rect(Rect2(at, plot_size).grow(1.0), UI.GOLD, false, 2.0)
		else:
			var centre := at + plot_size / 2.0
			_overlay.draw_arc(centre, 9.0, 0.0, TAU, 24, Color.BLACK, 4.0)
			_overlay.draw_arc(centre, 9.0, 0.0, TAU, 24, UI.GOLD, 2.0)

	_draw_towns()
	_draw_scale()


func _draw_pin(at: Vector2, color: Color) -> void:
	var points := PackedVector2Array([at + Vector2(0, -12), at + Vector2(6, -6), at, at + Vector2(-6, -6)])
	_overlay.draw_colored_polygon(points, color)
	points.append(points[0])
	_overlay.draw_polyline(points, Color.BLACK, 1.5)


## Town names, biggest first, skipping any that would cover one already drawn.
func _draw_towns() -> void:
	var half := size / 2.0 / _zoom
	var view := Rect2i(Vector2i((_center - half).floor()), Vector2i((half * 2.0).ceil()) + Vector2i.ONE)
	var min_population := maxi(1000, int(700000.0 / pow(_zoom, 1.7)))
	var found := _data.towns_in(view, min_population)
	var towns: Array = Array(found)
	towns.sort_custom(func(a: int, b: int) -> bool: return _data.town_population[a] > _data.town_population[b])

	var regular := get_theme_default_font()
	var bold := UI.bold()
	# Names never go under the interface.
	var taken: Array[Rect2] = []
	for control: Control in _hud:
		if control.visible:
			taken.append(control.get_rect().grow(4.0))
	taken.append(Rect2(size.x - 200, size.y - 100, 200, 40))  # the scale bar
	var screen := Rect2(Vector2.ZERO, size)
	var labels := 0
	for i: int in towns:
		if labels >= MAX_LABELS:
			break
		var dot := _to_screen(Vector2(_data.town_x[i], _data.town_y[i]) + Vector2(0.5, 0.5))
		if not screen.has_point(dot):
			continue
		var population := _data.town_population[i]
		var big := population >= 1000000
		var font: Font = bold if population >= 100000 else regular
		var font_size := 17 if big else (14 if population >= 100000 else 12)
		var name := _data.town_names[i]
		var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var box := Rect2(dot + Vector2(6, -text_size.y / 2.0), text_size).grow(2.0)
		var clear := true
		for other in taken:
			if other.intersects(box):
				clear = false
				break
		if not clear:
			continue
		taken.append(box)
		taken.append(Rect2(dot - Vector2(3, 3), Vector2(6, 6)))
		labels += 1
		var color := Color("#f3e3b5") if big else (UI.TEXT if population >= 100000 else Color("#cfc9bd"))
		_overlay.draw_circle(dot, 3.0 if big else 2.2, Color.BLACK)
		_overlay.draw_circle(dot, 2.0 if big else 1.4, color)
		var baseline := dot + Vector2(7, font.get_ascent(font_size) - text_size.y / 2.0)
		_overlay.draw_string_outline(font, baseline, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
		_overlay.draw_string(font, baseline, name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## A scale bar at the bottom right. East-west distances on the map stretch away from 30° latitude.
func _draw_scale() -> void:
	var km := 5
	for step in [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]:
		km = step
		if step / WorldData.PLOT_KM * _zoom >= 70.0:
			break
	var length := km / WorldData.PLOT_KM * _zoom
	var right := Vector2(size.x - 24, size.y - 70)
	var left := right - Vector2(length, 0)
	for pass_color in [Color.BLACK, UI.TEXT]:
		var width := 4.0 if pass_color == Color.BLACK else 2.0
		_overlay.draw_line(left, right, pass_color, width)
		_overlay.draw_line(left, left - Vector2(0, 6), pass_color, width)
		_overlay.draw_line(right, right - Vector2(0, 6), pass_color, width)
	var text := "%d km" % km
	var font := get_theme_default_font()
	var at := Vector2(right.x - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, right.y - 10)
	_overlay.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color.BLACK)
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT)


# --- Interface ---------------------------------------------------------------------

func _build_hud() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.position = Vector2(12, 12)
	add_child(top)
	top.add_child(UI.button("‹ Garaż", Game.open_garage))
	var title_parts := UI.panel(0)
	var title := UI.label("Mapa świata", UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_font_size_override("font_size", 18)
	title_parts[1].add_child(title)
	top.add_child(title_parts[0])
	_search = UI.line_edit("Szukaj miejscowości...")
	_search.custom_minimum_size.x = 230
	_search.text_submitted.connect(_on_search)
	top.add_child(_search)
	_mine_button = UI.button("Moje działki", _next_mine)
	_mine_button.tooltip_text = "Pokaż kolejną swoją działkę"
	top.add_child(_mine_button)

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

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	bottom.add_child(UI.button("Legenda  [L]", _toggle_legend))
	bottom.add_child(UI.button("−", func() -> void: _zoom_at(1 / 1.6, size / 2.0)))
	bottom.add_child(UI.button("+", func() -> void: _zoom_at(1.6, size / 2.0)))
	add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_status = _outlined(UI.label("", UI.TEXT))
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_status)

	_toast = _outlined(UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.size = Vector2(800, 30)
	_toast.position = Vector2((size.x - 800) / 2.0, 70)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_build_legend()
	_build_panel()
	_hud.assign([top, money_panel, bottom, _status, _panel, _legend])


func _build_legend() -> void:
	var parts := UI.panel(3)
	_legend = parts[0]
	_legend.visible = false
	var box: VBoxContainer = parts[1]
	box.add_child(UI.label("Legenda", UI.GOLD))
	for id in [WorldData.FOREST, WorldData.FARMLAND, WorldData.GRASSLAND, WorldData.DESERT, WorldData.MOUNTAINS,
			WorldData.TUNDRA, WorldData.ICE, WorldData.CITY, WorldData.COAST, WorldData.LAKESHORE, WorldData.LAKE, WorldData.OCEAN]:
		box.add_child(_biome_row(id, _biome_name(id)))
	var note := UI.label("1 działka = 5 × 5 km", UI.MUTED)
	note.add_theme_font_size_override("font_size", 13)
	box.add_child(note)
	add_child(_legend)
	_legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_legend.offset_bottom = -44
	_legend.offset_top = _legend.offset_bottom - _legend.get_combined_minimum_size().y
	_legend.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _toggle_legend() -> void:
	_legend.visible = not _legend.visible
	_overlay.queue_redraw()


func _biome_row(id: int, name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var swatch := ColorRect.new()
	swatch.color = WorldData.COLORS[id]
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	row.add_child(UI.label(name))
	return row


func _build_panel() -> void:
	var parts := UI.panel(6)
	_panel = parts[0]
	_panel.visible = false
	_panel.custom_minimum_size.x = 300
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_panel.offset_top = 62
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_plot_box = parts[1]


func _select(plot: Vector2i) -> void:
	if plot.y < 0 or plot.y >= _data.height:
		return
	_selected = plot
	_confirming = false
	_overlay.queue_redraw()
	_plot = {"x": plot.x, "y": plot.y, "biome": _data.biome(plot), "loading": true}
	_show_plot()
	var reply := await Net.request("world.plot", {"x": plot.x, "y": plot.y})
	if _selected != plot:
		return
	if reply["type"] == "world.plot":
		_plot = reply["payload"]
		_show_plot()
	else:
		_show_error(reply)


func _close_panel() -> void:
	_panel.visible = false
	_selected = Vector2i(-1, -1)
	_overlay.queue_redraw()


func _show_plot() -> void:
	for child in _plot_box.get_children():
		child.free()
	var plot := Vector2i(_plot["x"], _plot["y"])
	var biome: int = _plot["biome"]
	var info: Dictionary = _biomes.get(biome, {})

	var head := HBoxContainer.new()
	var plot_name: Variant = _plot.get("name")
	var named := plot_name != null and str(plot_name) != ""
	var title := UI.label(str(plot_name) if named else "Działka %d × %d" % [plot.x, plot.y], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.button("×", _close_panel))
	_plot_box.add_child(head)
	if named:
		_plot_box.add_child(_small("Działka %d × %d" % [plot.x, plot.y], UI.MUTED))

	var biome_row := _biome_row(biome, _biome_name(biome))
	(biome_row.get_child(1) as Label).add_theme_font_override("font", UI.bold())
	_plot_box.add_child(biome_row)
	var where := []
	var town := _data.nearest_town(plot)
	if town >= 0:
		where.append("okolice: %s" % _data.town_names[town])
	where.append(WorldData.geo_text(_data.to_geo(Vector2(plot) + Vector2(0.5, 0.5))))
	where.append("powierzchnia 5 × 5 km (25 km²)")
	for line in where:
		_plot_box.add_child(_small(line, UI.MUTED))
	_plot_box.add_child(HSeparator.new())

	var bonuses: Array = info.get("bonuses", [])
	if not info.get("buyable", true):
		_plot_box.add_child(UI.label("Woda: nie da się jej kupić.", UI.MUTED))
	elif bonuses.is_empty():
		_plot_box.add_child(UI.label("Brak bonusów.", UI.MUTED))
	for bonus: Dictionary in bonuses:
		_plot_box.add_child(UI.label(bonus["text"], UI.GOOD if bonus["good"] else UI.ERROR))

	if _plot.get("loading", false):
		_plot_box.add_child(HSeparator.new())
		_plot_box.add_child(UI.label("Sprawdzam właściciela...", UI.MUTED))
	elif info.get("buyable", true):
		_plot_box.add_child(HSeparator.new())
		var owner: Variant = _plot.get("owner")
		if owner != null:
			var mine: bool = owner["mine"]
			var owner_label := UI.label("Twoja działka" if mine else "Właściciel: %s" % owner.get("name", "?"),
				UI.GOLD if mine else UI.TEXT)
			_plot_box.add_child(owner_label if mine else Online.with_dot(owner_label, owner.get("name")))
			var company: Variant = _plot.get("company")
			if company != null:
				_plot_box.add_child(UI.label("Działka spółki %s%s" % [company["name"], " (twojej)" if company["member"] and not mine else ""],
					UI.GOLD if company["member"] else UI.MUTED))
			if mine:
				_plot_box.add_child(UI.button("Wejdź na działkę", Game.enter_plot.bind(plot), true))
				_show_rename(plot)
				_show_access()
				_show_survey()
			elif _plot.get("canEnter", false) and company != null and company["member"]:
				_plot_box.add_child(UI.button("Wejdź na działkę spółki", Game.enter_plot.bind(plot), true))
			elif _plot.get("canEnter", false):
				_plot_box.add_child(_note("Działka publiczna: możesz po niej chodzić i oglądać, ale niczego nie ruszysz."))
				_plot_box.add_child(UI.button("Odwiedź działkę", Game.enter_plot.bind(plot), true))
			else:
				_plot_box.add_child(_note("Działka prywatna: wchodzą tylko właściciel i jego spółka."))
		elif _plot.get("priceCents") != null:
			var price: int = _plot["priceCents"]
			var price_row := HBoxContainer.new()
			price_row.add_theme_constant_override("separation", 6)
			price_row.add_child(UI.label("Cena:"))
			var amount := UI.label(UI.money(price), UI.GOLD)
			amount.add_theme_font_override("font", UI.bold())
			price_row.add_child(amount)
			var factor: float = info.get("priceFactor", 1.0)
			if factor != 1.0:
				price_row.add_child(_small("(×%s za biom)" % str(factor).replace(".", ","), UI.MUTED))
			_plot_box.add_child(price_row)
			_buy = UI.button("Potwierdź zakup" if _confirming else "Kup działkę", _on_buy, true)
			_buy.disabled = _balance < price
			_plot_box.add_child(_buy)
			if _balance < price:
				_plot_box.add_child(_small("Brakuje %s." % UI.money(price - _balance), UI.ERROR))
			elif _confirming:
				_plot_box.add_child(_small("Kliknij jeszcze raz, by zapłacić %s." % UI.money(price), UI.MUTED))
	_panel.visible = true
	_panel.reset_size()
	_overlay.queue_redraw()


## The owner names the plot: the name shows here and in the routes of trains between their plots.
func _show_rename(plot: Vector2i) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var field := UI.line_edit("Nazwa działki")
	field.max_length = 32
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current: Variant = _plot.get("name")
	field.text = str(current) if current != null else ""
	var save := func() -> void:
		var reply := await Net.request("world.rename", {"x": plot.x, "y": plot.y, "name": field.text.strip_edges()})
		if reply["type"] != "world.plot":
			_show_error(reply)
			return
		if _selected == plot:
			_plot = reply["payload"]
			_show_plot()
		_show_toast("Nazwa zapisana." if reply["payload"].get("name") != null else "Działka nie ma już nazwy.", UI.GOLD)
	field.text_submitted.connect(func(_t: String) -> void: save.call())
	row.add_child(field)
	row.add_child(UI.button("Nazwij", save))
	_plot_box.add_child(row)


## Who may come onto the player's own plot: anyone (only to look around) or just them and their company.
func _show_access() -> void:
	var open: bool = _plot.get("public", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.label("Dostęp:"))
	row.add_child(UI.label("publiczna" if open else "prywatna", UI.GOOD if open else UI.GOLD))
	_plot_box.add_child(row)
	_plot_box.add_child(_note("Każdy może wejść i pochodzić, ale nie zajrzy do skrzyń, niczego nie zbierze, nie wydobędzie ani nie postawi."
		if open else "Wchodzisz tylko ty i członkowie spółki, jeśli działka do niej należy."))
	_plot_box.add_child(UI.button("Zmień na prywatną" if open else "Udostępnij wszystkim", _on_access.bind(not open)))


func _on_access(open: bool) -> void:
	var reply := await Net.request("plot.setPublic", {"x": _plot["x"], "y": _plot["y"], "public": open})
	if reply["type"] != "world.plot":
		_show_error(reply)
		return
	var plot: Dictionary = reply["payload"]
	if _selected == Vector2i(plot["x"], plot["y"]):
		_plot["public"] = plot.get("public", false)
		_plot["canEnter"] = plot.get("canEnter", false)
		_show_plot()
	_show_toast("Działka jest teraz publiczna." if open else "Działka jest teraz prywatna.", UI.GOOD)


## Oil and gas under the player's own plot: unknown until they pay for a geological survey.
func _show_survey() -> void:
	_plot_box.add_child(HSeparator.new())
	var survey: Variant = _plot.get("survey")
	if survey is Dictionary:
		_plot_box.add_child(UI.label("Badanie geologiczne:", UI.MUTED))
		for row: Array in [["Ropa naftowa", survey["oil"]], ["Gaz ziemny", survey["gas"]]]:
			var size := int(row[1])
			_plot_box.add_child(UI.label("%s: %s" % [row[0], DEPOSITS[size]], UI.GOOD if size > 0 else UI.TEXT))
		# On the coast the seabed may hold oil too, which an offshore platform reaches.
		if int(_plot.get("biome", -1)) == COAST:
			var seabed := int(survey.get("seabed", 0))
			_plot_box.add_child(UI.label("Ropa pod dnem morza: %s" % DEPOSITS[seabed], UI.GOOD if seabed > 0 else UI.TEXT))
		# Mountain rock may hold a mineral, which comes up from the mines with the ore.
		if int(_plot.get("biome", -1)) == 6:
			var mineral := int(survey.get("mineralSize", 0))
			var text := "Minerał w skale: %s (%s)" % [survey.get("mineralName", ""), DEPOSITS[mineral]] if mineral > 0 else "Minerał w skale: brak"
			_plot_box.add_child(UI.label(text, UI.GOOD if mineral > 0 else UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	_plot_box.add_child(UI.label("Ropa, gaz i minerały: nie wiadomo" if int(_plot.get("biome", -1)) == 6 else "Ropa i gaz: nie wiadomo", UI.TEXT))
	var price := int(_plot.get("surveyPriceCents", 0))
	_plot_box.add_child(_small("Złoża zobaczysz dopiero po badaniu geologicznym.", UI.MUTED))
	var order := UI.button("Zleć badanie (%s)" % UI.money(price), _on_survey)
	order.disabled = _balance < price
	_plot_box.add_child(order)


func _on_survey() -> void:
	var plot := Vector2i(_plot["x"], _plot["y"])
	var reply := await Net.request("world.survey", {"x": plot.x, "y": plot.y})
	if reply["type"] != "world.surveyed":
		_show_error(reply)
		return
	var result: Dictionary = reply["payload"]
	_set_balance(int(result["balanceCents"]))
	var survey: Dictionary = result["survey"]
	var found := int(survey["oil"]) > 0 or int(survey["gas"]) > 0 or int(survey.get("seabed", 0)) > 0 or int(survey.get("mineralSize", 0)) > 0
	_show_toast("Badanie zakończone: %s." % ("są złoża!" if found else "brak złóż"), UI.GOLD if found else UI.TEXT)
	if _selected == plot:
		_plot["survey"] = survey
		_show_plot()


func _on_buy() -> void:
	if not _confirming:
		_confirming = true
		_show_plot()
		return
	_confirming = false
	if is_instance_valid(_buy):
		_buy.disabled = true
	var plot := Vector2i(_plot["x"], _plot["y"])
	var reply := await Net.request("world.buy", {"x": plot.x, "y": plot.y})
	if reply["type"] != "world.bought":
		_show_error(reply)
		_select(plot)
		return
	var bought: Dictionary = reply["payload"]
	_set_balance(int(bought["balanceCents"]))
	_owned[plot] = true
	_my_plots.append(plot)
	_update_mine_button()
	var xp: Dictionary = bought["xp"]
	var gained := int(xp["xp"]) - int(Game.character.get("xp", 0))
	Game.gain_xp(xp)
	var text := "Kupiłeś działkę %d × %d!  +%d XP" % [plot.x, plot.y, gained]
	if bought.get("tool") != null:
		text += "  ·  Dostajesz: %s" % bought["tool"]["name"]
		# The new tool goes into a free slot of the tool bar, otherwise into the inventory.
		Game.reload_character()
	if xp.get("leveledUp", false):
		text += "  ·  Awans na poziom %d" % xp["level"]
	_show_toast(text, UI.GOLD)
	if _selected == plot:
		_plot = bought["plot"]
		_show_plot()
	_overlay.queue_redraw()


func _on_search(text: String) -> void:
	var town := _data.find_town(text)
	if town < 0:
		_show_toast("Nie znaleziono: %s" % text, UI.ERROR)
		return
	_search.release_focus()
	var plot := Vector2i(_data.town_x[town], _data.town_y[town])
	_go_to(plot, 12.0)
	_select(plot)


func _next_mine() -> void:
	if _my_plots.is_empty():
		_show_toast("Nie masz jeszcze działek. Kliknij wolną działkę na lądzie, by ją kupić.", UI.MUTED)
		return
	_my_index = (_my_index + 1) % _my_plots.size()
	_go_to(_my_plots[_my_index], 16.0)
	_select(_my_plots[_my_index])


func _update_mine_button() -> void:
	_mine_button.text = "Moje działki (%d)" % _my_plots.size()


# --- Server ------------------------------------------------------------------------

func _load() -> void:
	var info := await Net.request("world.info")
	var wallet := await Net.request("wallet.get")
	for reply: Dictionary in [info, wallet]:
		if reply["type"] == "error":
			_show_error(reply)
			return
	for biome: Dictionary in info["payload"]["biomes"]:
		_biomes[int(biome["id"])] = biome
	_next_base_price = info["payload"]["nextBasePriceCents"]
	for plot: Dictionary in info["payload"]["plots"]:
		var at := Vector2i(plot["x"], plot["y"])
		_my_plots.append(at)
		_owned[at] = true
	# Plots other members brought into the player's company: theirs to work on too.
	for plot: Dictionary in info["payload"].get("sharedPlots", []):
		_my_plots.append(Vector2i(plot["x"], plot["y"]))
	_update_mine_button()
	_set_balance(int(wallet["payload"]["balanceCents"]))
	# The legend was built before the names arrived.
	var shown := _legend.visible
	_hud.erase(_legend)
	_legend.free()
	_build_legend()
	_legend.visible = shown
	_hud.append(_legend)
	_overlay.queue_redraw()


## Loads who owns the plots around the view, once the camera stops moving.
func _load_area() -> void:
	if _zoom < AREA_ZOOM:
		return
	# A screen's width and height around the view, so short moves need no new request.
	var reach := size / _zoom
	var from := Vector2i((_center - reach).floor())
	var span := Vector2i((reach * 2.0).ceil())
	from.y = maxi(from.y, 0)
	span = Vector2i(mini(span.x, _data.width), mini(span.y, _data.height - from.y))
	# The view may cross the 180° meridian: ask for each side separately.
	var rects: Array[Rect2i] = []
	var x := posmod(from.x, _data.width)
	var first := mini(span.x, _data.width - x)
	rects.append(Rect2i(x, from.y, first, span.y))
	if first < span.x:
		rects.append(Rect2i(0, from.y, span.x - first, span.y))
	var owned := {}
	for plot in _my_plots:
		owned[plot] = true
	for rect in rects:
		var reply := await Net.request("world.area", {"x": rect.position.x, "y": rect.position.y,
			"width": rect.size.x, "height": rect.size.y})
		if reply["type"] != "world.area":
			return
		for plot: Dictionary in reply["payload"]["plots"]:
			owned[Vector2i(plot["x"], plot["y"])] = plot["mine"]
	_owned = owned
	_overlay.queue_redraw()


func _set_balance(cents: int) -> void:
	_balance = cents
	_money.text = UI.money(cents)


# --- Helpers -----------------------------------------------------------------------

func _biome_name(id: int) -> String:
	return _biomes.get(id, {}).get("name", "")


func _small(text: String, color: Color) -> Label:
	var l := UI.label(text, color)
	l.add_theme_font_size_override("font_size", 13)
	return l


## A small muted line that wraps to the panel's width.
func _note(text: String) -> Label:
	var l := UI.label(text, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_theme_font_size_override("font_size", 13)
	return l


func _outlined(label: Label) -> Label:
	label.add_theme_font_override("font", UI.bold())
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _show_toast(text: String, color := UI.TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.position.x = (size.x - _toast.size.x) / 2.0
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)


func _show_error(reply: Dictionary) -> void:
	_show_toast(Game.error_text(reply), UI.ERROR)
