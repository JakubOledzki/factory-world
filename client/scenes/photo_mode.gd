class_name PhotoMode
extends CanvasLayer
## Photo mode on a plot ([H] or the camera on the toolbar): the interface hides, the camera may pull
## further out than in play, and "Zrób zdjęcie" saves what is on the screen with the plot's name in
## the corner, as a PNG: downloaded in the browser, in the game's folder elsewhere. Esc or [H] ends it.

signal toggled(on: bool)

## How far out the camera may go in photo mode (in play: the plot's MIN_ZOOM).
const MIN_ZOOM := 0.2
const FOLDER := "user://zdjecia"

var active := false
## Asked for the caption's first line, e.g. "Działka 120 × 80 · Las".
var caption_source: Callable
## Called with a factor to zoom the camera, e.g. 1.1 to come closer.
var zoom_by: Callable

var _hidden: Array[CanvasLayer] = []
var _bar: PanelContainer
var _caption: PanelContainer
var _caption_title: Label
var _caption_line: Label
var _busy := false


func _init() -> void:
	layer = 70
	visible = false
	var root := Control.new()
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var parts := UI.panel(6)
	_bar = parts[0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parts[1].add_child(row)
	row.add_child(UI.label("Tryb zdjęć: %s" % ("dwoma palcami oddalisz widok" if UI.touch() else "kółko myszy oddala widok, WASD przesuwa postać"), UI.MUTED))
	row.add_child(UI.button("Zrób zdjęcie", _take, true))
	row.add_child(UI.button("Wyjdź", leave))
	root.add_child(_bar)
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# The caption only shows on the picture itself.
	parts = UI.panel(2)
	_caption = parts[0]
	_caption.modulate = Color(1, 1, 1, 0.92)
	_caption_title = UI.label("", UI.GOLD)
	_caption_title.add_theme_font_override("font", UI.bold())
	parts[1].add_child(_caption_title)
	_caption_line = UI.label("", UI.MUTED)
	parts[1].add_child(_caption_line)
	root.add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.visible = false


func toggle() -> void:
	if active:
		leave()
	else:
		enter()


func enter() -> void:
	if active:
		return
	active = true
	_hidden.clear()
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas != self and canvas.visible and canvas.layer > 0:
			canvas.visible = false
			_hidden.append(canvas)
	visible = true
	_bar.visible = true
	toggled.emit(true)


func leave() -> void:
	if not active:
		return
	active = false
	visible = false
	for canvas in _hidden:
		if is_instance_valid(canvas):
			canvas.visible = true
	_hidden.clear()
	toggled.emit(false)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed("cancel") or event.is_action_pressed("photo"):
		leave()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and zoom_by.is_valid():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by.call(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by.call(1 / 1.1)
		# Clicks in photo mode build, gather and open nothing.
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventMouseButton:
		# Nor do keys; walking still works, as it reads the keys held down.
		get_viewport().set_input_as_handled()


func _take() -> void:
	if _busy:
		return
	_busy = true
	_caption_title.text = caption_source.call() if caption_source.is_valid() else "Factory World"
	var date := Time.get_datetime_dict_from_system()
	_caption_line.text = "%s  ·  %02d.%02d.%d  ·  Factory World" % [Game.character.get("name", ""), date["day"], date["month"], date["year"]]
	_bar.visible = false
	_caption.visible = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_caption.visible = false
	_bar.visible = true
	_busy = false
	Sound.play("shutter")
	var name := "factory-world-%04d%02d%02d-%02d%02d%02d.png" % [date["year"], date["month"], date["day"], date["hour"], date["minute"], date["second"]]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), name, "image/png")
		Game.notices.show_notice("Zdjęcie pobrane: %s" % name, UI.GOOD)
		return
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var path := "%s/%s" % [FOLDER, name]
	if image.save_png(path) == OK:
		Game.notices.show_notice("Zdjęcie zapisane: %s" % ProjectSettings.globalize_path(path), UI.GOOD)
	else:
		Game.notices.show_notice("Nie udało się zapisać zdjęcia.", UI.ERROR)
