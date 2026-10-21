extends CanvasLayer
## On-screen controls for phones and tablets, over every screen. Screens that walk the character
## (their ACTIONS have "interact") get a joystick on the left and action buttons on the right; the
## joystick presses the move_* actions, the buttons send their action as if its key was pressed.
## Taps elsewhere reach the game as left clicks (Godot turns the first finger into a mouse).
## On the web there is also a full screen button, which turns a phone to landscape.

## Texts of the action buttons, in the order they are shown, bottom to top.
const BUTTONS := {
	"interact": "Użyj",
	"rotate": "Obróć",
	"cancel": "Anuluj",
}
## Joystick: centre (from the bottom left corner) and radius of the ring, in pixels of the
## 1280 × 720 screen; the knob follows the finger up to the ring.
const STICK_CENTRE := Vector2(150, -250)
const STICK_RADIUS := 80.0
## Centres of the action buttons, from the bottom right corner; the first one is bigger.
const BUTTON_SPOTS := [Vector2(-130, -260), Vector2(-255, -330), Vector2(-140, -410)]
const MAIN_RADIUS := 62.0
const BUTTON_RADIUS := 42.0

var _root: Control
var _stick: Control
var _stick_finger := -1
var _stick_vector := Vector2.ZERO
var _buttons: Array[TouchButton] = []
var _fullscreen: Button
var _scene: Node
var _check_fullscreen_in := 0.0
## Keys in the texts of buttons, like "Ekwipunek  [I]", mean nothing without a keyboard.
var _key_hint := RegEx.new()


## A round button that sends `action` while a finger holds it.
class TouchButton extends Control:
	var action := ""
	var text := ""
	var radius := 40.0
	var finger := -1

	func _init(action_name: String, label: String, r: float) -> void:
		action = action_name
		text = label
		radius = r
		size = Vector2(r, r) * 2
		mouse_filter = Control.MOUSE_FILTER_STOP

	func centre() -> Vector2:
		return global_position + size / 2

	func _draw() -> void:
		var c := size / 2
		draw_circle(c, radius, Color(0.05, 0.05, 0.06, 0.7 if finger < 0 else 0.9))
		draw_arc(c, radius - 1.5, 0, TAU, 48, Color(UI.GOLD, 0.85 if finger < 0 else 1.0), 3.0, true)
		var font := UI.bold()
		var font_size := int(radius * 0.42)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, c + Vector2(-width / 2, font_size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.TEXT)


func _ready() -> void:
	layer = 50
	if not UI.touch():
		set_process(false)
		set_process_input(false)
		return
	_key_hint.compile("\\s*\\[\\w+\\]$")
	get_tree().node_added.connect(_adapt)

	_root = Control.new()
	_root.theme = UI.theme()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_stick = Control.new()
	_stick.size = Vector2.ONE * STICK_RADIUS * 3.2
	_stick.mouse_filter = Control.MOUSE_FILTER_STOP
	_stick.draw.connect(_draw_stick)
	_root.add_child(_stick)

	for action: String in BUTTONS:
		var button := TouchButton.new(action, BUTTONS[action], BUTTON_RADIUS if _buttons else MAIN_RADIUS)
		_root.add_child(button)
		_buttons.append(button)

	if OS.has_feature("web") and JavaScriptBridge.eval("!!document.fullscreenEnabled"):
		_fullscreen = UI.button("Pełny ekran", _go_fullscreen)
		_root.add_child(_fullscreen)
		_fullscreen.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 8)
		_fullscreen.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_show_controls(false)


## Bigger letters also where a screen sets its own size, and buttons without keys.
func _adapt(node: Node) -> void:
	if node is Control and node.has_theme_font_size_override("font_size") and not node.has_meta("touch_scaled"):
		node.set_meta("touch_scaled", true)
		node.add_theme_font_size_override("font_size", roundi(node.get_theme_font_size("font_size") * UI.TOUCH_SCALE))
	if node is Button:
		node.text = _key_hint.sub(node.text, "")


func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		_release_stick()
		_show_controls(_walks(scene))
	_layout()
	_check_fullscreen_in -= delta
	if _fullscreen != null and _check_fullscreen_in <= 0.0:
		_check_fullscreen_in = 1.0
		# The editor and the world map have their own buttons at the top.
		_fullscreen.visible = not JavaScriptBridge.eval("!!document.fullscreenElement") \
			and not (scene != null and scene.scene_file_path in [Game.EDITOR_SCENE, Game.WORLD_MAP_SCENE])


## Whether a screen moves the character, so it needs the joystick.
func _walks(scene: Node) -> bool:
	if scene == null or scene.get_script() == null:
		return false
	var actions: Dictionary = scene.get_script().get_script_constant_map().get("ACTIONS", {})
	return actions.has("interact")


## Shows the joystick and the buttons of the actions the screen has, or hides them all.
func _show_controls(walking: bool) -> void:
	_stick.set_meta("wanted", walking)
	var actions: Dictionary = {}
	if walking:
		actions = _scene.get_script().get_script_constant_map().get("ACTIONS", {})
	var spot := 0
	for button in _buttons:
		button.set_meta("wanted", actions.has(button.action))
		if actions.has(button.action):
			button.set_meta("offset", BUTTON_SPOTS[spot])
			spot += 1
	for control: Control in [_stick] + _buttons:
		control.visible = control.get_meta("wanted")


## Keeps the controls in their corners, and hides those under an open window, so they
## never cover the window's buttons.
func _layout() -> void:
	var area := _root.size
	_stick.position = Vector2(0, area.y) + STICK_CENTRE - _stick.size / 2
	var windows: Array[Rect2] = []
	for window: Control in get_tree().get_nodes_in_group(GameWindow.GROUP):
		if window.is_visible_in_tree():
			windows.append(window.get_global_rect())
	for control: Control in [_stick] + _buttons:
		if not control.get_meta("wanted"):
			continue
		if control != _stick:
			control.position = area + (control.get_meta("offset") as Vector2) - control.size / 2
		var covered := windows.any(func(rect: Rect2) -> bool: return rect.intersects(control.get_global_rect()))
		if covered and control.visible:
			if control == _stick:
				_release_stick()
			control.visible = false
		elif not covered and not control.visible:
			control.visible = true


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _stick.visible and _stick.get_global_rect().has_point(event.position) and _stick_finger < 0:
				_stick_finger = event.index
				_move_stick(event.position)
				get_viewport().set_input_as_handled()
				return
			for button in _buttons:
				if button.visible and button.finger < 0 and button.centre().distance_to(event.position) <= button.radius * 1.15:
					button.finger = event.index
					button.queue_redraw()
					_send(button.action, true)
					get_viewport().set_input_as_handled()
					return
		else:
			if event.index == _stick_finger:
				_release_stick()
				get_viewport().set_input_as_handled()
				return
			for button in _buttons:
				if button.finger == event.index:
					button.finger = -1
					button.queue_redraw()
					_send(button.action, false)
					get_viewport().set_input_as_handled()
					return
	elif event is InputEventScreenDrag and event.index == _stick_finger:
		_move_stick(event.position)
		get_viewport().set_input_as_handled()


func _send(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _move_stick(at: Vector2) -> void:
	_stick_vector = ((at - _stick.get_global_rect().get_center()) / STICK_RADIUS).limit_length(1.0)
	_press("move_right", _stick_vector.x)
	_press("move_left", -_stick_vector.x)
	_press("move_down", _stick_vector.y)
	_press("move_up", -_stick_vector.y)
	_stick.queue_redraw()


func _press(action: String, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _release_stick() -> void:
	_stick_finger = -1
	_stick_vector = Vector2.ZERO
	for action in ["move_right", "move_left", "move_down", "move_up"]:
		_press(action, 0.0)
	if _stick != null:
		_stick.queue_redraw()


func _draw_stick() -> void:
	var c := _stick.size / 2
	_stick.draw_circle(c, STICK_RADIUS, Color(0.05, 0.05, 0.06, 0.45))
	_stick.draw_arc(c, STICK_RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.35), 3.0, true)
	var knob := c + _stick_vector * STICK_RADIUS
	_stick.draw_circle(knob, STICK_RADIUS * 0.42, Color(UI.GOLD, 0.75 if _stick_finger >= 0 else 0.5))


## Full screen, and landscape on phones that allow locking the orientation. Runs right after
## the tap, which browsers require.
func _go_fullscreen() -> void:
	JavaScriptBridge.eval("""
		document.documentElement.requestFullscreen({ navigationUI: 'hide' })
			.then(() => screen.orientation && screen.orientation.lock && screen.orientation.lock('landscape'))
			.catch(() => {});
	""")
	_check_fullscreen_in = 0.5
