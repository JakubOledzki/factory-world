extends CanvasLayer
## The tutorial's tasks, in a small panel on the left of the garage, the world map and the plot:
## the task at hand, how far the player got, a hint and the reward. The server follows what the
## player does; after each reply the task at hand watches, the panel asks it again, and when a
## task is done it shows what it paid and brings money and XP on the screen up to date.

## Screens the panel shows on.
const SCREENS := [Game.GARAGE_SCENE, Game.WORLD_MAP_SCENE, Game.PLOT_SCENE]
const SETTINGS_FILE := "user://tutorial.cfg"
const WIDTH := 290
## Below the character or plot panel in the top left corner.
const TOP := 132
const LEFT := 12
const DONE_COLOR := UI.GOOD

## The last "tutorial" payload from the server, or empty before the first one.
var _state := {}
var _scene: Node
var _collapsed := false
var _confirming_skip := false

var _root: Control
var _panel: PanelContainer
var _header: Label
var _collapse: Button
var _title: Label
var _details: VBoxContainer
var _text: Label
var _progress_row: HBoxContainer
var _bar: ProgressBar
var _count: Label
var _hint: Label
var _reward: Label
var _skip: Button
var _toast: PanelContainer
var _toast_text: Label
var _toast_tween: Tween


func _ready() -> void:
	layer = 10
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) == OK:
		_collapsed = config.get_value("tutorial", "collapsed", false)
	_build()
	Net.message_received.connect(_on_message)


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		if _on_game_screen():
			Net.send("tutorial.get")
		else:
			_state = {}
		_show()
	# Out of the way of open windows, the way the touch controls step aside.
	if _panel.visible == _covered():
		_panel.visible = not _panel.visible


func _on_game_screen() -> bool:
	return _scene != null and _scene.scene_file_path in SCREENS and not Game.character.is_empty()


func _on_message(type: String, payload: Variant, _id: String) -> void:
	if type == "tutorial" and payload is Dictionary:
		_apply(payload)
	elif not _state.is_empty() and type in _state.get("watch", []):
		Net.send("tutorial.get")


func _apply(state: Dictionary) -> void:
	var before: int = _state.get("current", -1)
	_state = state
	var now: int = state["current"]
	var steps: Array = state["steps"]
	if before >= 0 and now > before:
		_celebrate(steps.slice(before, now), now >= steps.size())
	_show()


## Shows the task at hand, or hides the panel when there is none to show.
func _show() -> void:
	var steps: Array = _state.get("steps", [])
	var current: int = _state.get("current", 0)
	var wanted: bool = _on_game_screen() and not _state.is_empty() and not _state.get("skipped", false) and current < steps.size()
	_root.visible = wanted
	if not wanted:
		return
	var step: Dictionary = steps[current]
	var goal: int = step["goal"]
	_header.text = "Samouczek  ·  zadanie %d z %d" % [current + 1, steps.size()]
	_collapse.text = "+" if _collapsed else "–"
	_collapse.tooltip_text = "Rozwiń" if _collapsed else "Zwiń"
	_title.text = step["title"]
	_details.visible = not _collapsed
	_text.text = step["text"]
	_progress_row.visible = goal > 1
	_bar.max_value = goal
	_bar.value = mini(int(_state.get("count", 0)), goal)
	_count.text = "%d / %d" % [mini(int(_state.get("count", 0)), goal), goal]
	_hint.text = step["hint"]
	_reward.text = "Nagroda: " + _reward_text(int(step["rewardCents"]), int(step["rewardXp"]), step.get("rewardItems", []))
	_set_confirming(false)


func _covered() -> bool:
	if not _root.visible:
		return false
	var rect := _panel.get_global_rect()
	for window: Control in get_tree().get_nodes_in_group(GameWindow.GROUP):
		if window.is_visible_in_tree() and window.get_global_rect().intersects(rect):
			return true
	return false


## Money, XP and items ({id, name, quantity}), as "50,00 $  ·  20 XP  ·  10 × Sztabka żelaza".
func _reward_text(cents: int, xp: int, items: Array = []) -> String:
	var parts: Array[String] = []
	if cents > 0:
		parts.append(UI.money(cents))
	if xp > 0:
		parts.append("%d XP" % xp)
	for item: Dictionary in items:
		parts.append("%d × %s" % [int(item["quantity"]), item["name"]])
	return "  ·  ".join(parts)


## A task (or several at once) is done: says what it paid and updates money and XP on the screen.
func _celebrate(done: Array, finished: bool) -> void:
	var cents := 0
	var xp := 0
	var items: Array = []
	for step: Dictionary in done:
		cents += int(step["rewardCents"])
		xp += int(step["rewardXp"])
		items.append_array(step.get("rewardItems", []))
	var names := ", ".join(done.map(func(step: Dictionary) -> String: return step["title"]))
	var text := "Zadanie wykonane: %s" % names
	if finished:
		text = "Samouczek ukończony! Twoja pierwsza linia działa."
	if cents > 0 or xp > 0 or not items.is_empty():
		text += "\n+" + _reward_text(cents, xp, items).replace("  ·  ", "   +")
	_flash(text)
	_refresh_screen()


func _refresh_screen() -> void:
	var wallet := await Net.request("wallet.get")
	var character := await Net.request("character.get")
	var scene := get_tree().current_scene
	if wallet["type"] == "wallet" and scene != null and scene.has_method("_set_balance"):
		scene.call("_set_balance", int(wallet["payload"]["balanceCents"]))
	if character["type"] == "character":
		Game.character = character["payload"]
		if scene != null and scene.has_method("_refresh_character"):
			scene.call("_refresh_character")


func _flash(text: String) -> void:
	_toast_text.text = text
	if _toast_tween != null:
		_toast_tween.kill()
	_toast.visible = true
	_toast.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.25)
	_toast_tween.tween_interval(4.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(func() -> void: _toast.visible = false)


func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	config.set_value("tutorial", "collapsed", _collapsed)
	config.save(SETTINGS_FILE)
	_show()


## The first press asks again; the second hides the tutorial for good.
func _on_skip() -> void:
	if not _confirming_skip:
		_set_confirming(true)
		get_tree().create_timer(4.0).timeout.connect(func() -> void: _set_confirming(false))
		return
	Net.send("tutorial.skip", {"skipped": true})


func _set_confirming(on: bool) -> void:
	_confirming_skip = on
	_skip.text = "Na pewno? Kliknij jeszcze raz" if on else "Pomiń samouczek"


func _build() -> void:
	_root = Control.new()
	_root.theme = UI.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	var parts := UI.panel(4)
	_panel = parts[0]
	_panel.custom_minimum_size.x = WIDTH
	_panel.position = Vector2(LEFT, TOP)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_panel)
	var box: VBoxContainer = parts[1]

	var top := HBoxContainer.new()
	_header = UI.label("", UI.MUTED)
	_header.add_theme_font_size_override("font_size", 12)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	_collapse = UI.button("–", _toggle_collapsed)
	_collapse.flat = true
	_collapse.focus_mode = Control.FOCUS_NONE
	top.add_child(_collapse)
	box.add_child(top)

	_title = UI.label("", UI.GOLD)
	_title.add_theme_font_override("font", UI.bold())
	_title.add_theme_font_size_override("font_size", 17)
	box.add_child(_title)

	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 4)
	box.add_child(_details)
	_text = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_text.custom_minimum_size.x = WIDTH - 24
	_details.add_child(_text)

	_progress_row = HBoxContainer.new()
	_progress_row.add_theme_constant_override("separation", 8)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_row.add_child(_bar)
	_count = UI.label("", UI.TEXT)
	_count.add_theme_font_override("font", UI.bold())
	_progress_row.add_child(_count)
	_details.add_child(_progress_row)

	_hint = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.custom_minimum_size.x = WIDTH - 24
	_details.add_child(_hint)

	_reward = UI.label("", DONE_COLOR, HORIZONTAL_ALIGNMENT_LEFT, true)
	_reward.custom_minimum_size.x = WIDTH - 24
	_reward.add_theme_font_size_override("font_size", 13)
	_details.add_child(_reward)

	_skip = UI.button("Pomiń samouczek", _on_skip)
	_skip.flat = true
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.add_theme_font_size_override("font_size", 12)
	_skip.add_theme_color_override("font_color", UI.MUTED)
	_skip.size_flags_horizontal = Control.SIZE_SHRINK_END
	_details.add_child(_skip)

	# The note that a task is done, at the top in the middle; it shows on any screen.
	var toast_parts := UI.panel(0)
	_toast = toast_parts[0]
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_text = UI.label("", DONE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_text.add_theme_font_override("font", UI.bold())
	_toast_text.add_theme_font_size_override("font_size", 17)
	toast_parts[1].add_child(_toast_text)
	var toast_layer := Control.new()
	toast_layer.theme = UI.theme()
	toast_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_layer)
	toast_layer.add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 72)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
