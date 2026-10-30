extends Node
## The player's settings, kept on this device: how big the interface is, the effects, the frame
## limit and the keys. [F1] (or the cog next to the money) opens their window on any screen.

## After any setting changed; screens redraw what depends on it (the plot's camera, the garage room).
signal changed

const FILE := "user://settings.cfg"
## Steps of the interface size, from small to big.
const SCALES := [0.75, 0.85, 1.0, 1.15, 1.3, 1.5]
## Frame limits offered: 0 is none; 30 saves the battery on a phone.
const FPS_LIMITS := [0, 60, 30]
## The screens with keys, and the script whose ACTIONS lists them.
const SCREENS := {
	"Działka": "res://scenes/plot.gd",
	"Garaż": "res://scenes/garage.gd",
	"Mapa świata": "res://scenes/world_map.gd",
}
## What each action does, as the list of keys says it.
const ACTION_NAMES := {
	"move_up": "Idź w górę",
	"move_down": "Idź w dół",
	"move_left": "Idź w lewo",
	"move_right": "Idź w prawo",
	"interact": "Użyj",
	"inventory": "Ekwipunek",
	"station": "Stacja kolejowa",
	"company": "Spółka",
	"bank": "Banki",
	"tool": "Narzędzia",
	"plant": "Sadzenie",
	"upgrade_mine": "Rozbuduj kopalnię",
	"cancel": "Anuluj, zamknij okna",
	"world_map": "Mapa świata",
	"garage": "Garaż",
	"rotate": "Obróć",
	"market": "Rynek",
	"stats": "Statystyki",
	"achievements": "Osiągnięcia",
	"character": "Postać",
	"hotbar_1": "Pasek: slot 1",
	"hotbar_2": "Pasek: slot 2",
	"hotbar_3": "Pasek: slot 3",
	"hotbar_4": "Pasek: slot 4",
	"hotbar_5": "Pasek: slot 5",
	"plan": "Plany budowy",
	"pipette": "Pipeta: weź taki sam obiekt",
	"photo": "Tryb zdjęć",
	"contracts": "Zlecenia",
	"upgrades": "Ulepszenia garażu",
	"zoom_in": "Przybliż",
	"zoom_out": "Oddal",
	"legend": "Legenda",
}
## Shortcuts that are not single keys, so they are only listed.
const FIXED := [
	["Ctrl + Z", "Cofnij postawienie albo schowanie"],
	["Enter", "Czat"],
	["Środkowy przycisk myszy", "Wskaż miejsce innym graczom"],
	["Przytrzymanie prawego przycisku", "Schowaj obiekt do ekwipunku"],
	["Shift + klik na przedmiot", "Włóż cały stos do otwartej maszyny lub skrzyni"],
	["Ctrl + klik na przedmiot", "Włóż połowę stosu"],
	["Shift + prawy przycisk", "Kopiuj ustawienia maszyny (przepis, filtr)"],
	["Shift + lewy przycisk", "Wklej ustawienia na inną maszynę"],
	["Ctrl + mysz nad przedmiotem", "Opis i ceny przedmiotu"],
	["F1", "To okno"],
]

## How big the interface is: 1 as designed, more for bigger letters and buttons.
var ui_scale := 1.0
## Smoke, sparks, confetti and the shaking screen; off for calm or for a slow phone.
var effects := true
## Frames per second at most; 0 for no limit.
var fps_limit := 0
## Loudness of the music and of the effects, 0 (off) to 1.
var music_volume := 0.5
var sfx_volume := 0.8

## Keys the player chose: action → physical keycode, in place of the first default key.
var _keys := {}
## Default keys of every action seen so far: action → [keys].
var _defaults := {}
var _layer: CanvasLayer
var _window: GameWindow
var _general := VBoxContainer.new()
var _controls := VBoxContainer.new()
var _general_tab: Button
var _controls_tab: Button
var _scale_label: Label
var _effects_button: Button
var _fps_buttons: Array[Button] = []
var _volume_labels := {}
## The action waiting for its new key, and the button that shows it.
var _capturing := ""
var _capture_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(FILE) == OK:
		ui_scale = float(config.get_value("view", "scale", 1.0))
		effects = bool(config.get_value("view", "effects", true))
		fps_limit = int(config.get_value("view", "fps", 0))
		music_volume = clampf(float(config.get_value("sound", "music", 0.5)), 0.0, 1.0)
		sfx_volume = clampf(float(config.get_value("sound", "effects", 0.8)), 0.0, 1.0)
		for action: String in config.get_section_keys("keys") if config.has_section("keys") else []:
			_keys[action] = int(config.get_value("keys", action))
	if not SCALES.has(ui_scale):
		ui_scale = 1.0
	_apply_view()
	# Every screen's keys are known from the start, so the list shows them all and the player's
	# choices hold however the screens register them.
	for path: String in SCREENS.values():
		register((load(path) as Script).get_script_constant_map().get("ACTIONS", {}))


## Adds the actions of a screen to the input map, each with the key the player chose for it.
func register(actions: Dictionary) -> void:
	for action: String in actions:
		if not _defaults.has(action):
			_defaults[action] = actions[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			_bind(action)


## The name of the key an action is on now, e.g. "I", for texts like "Ekwipunek  [I]".
func key_name(action: String) -> String:
	var key := _key(action)
	return OS.get_keycode_string(key) if key != KEY_NONE else "—"


func open(controls := false) -> void:
	_build()
	_show_tab(controls and not UI.touch())
	_window.show_window()


func toggle() -> void:
	if _window != null and _window.visible:
		_window.hide_window()
	else:
		open()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _capturing != "":
		if event.keycode != KEY_ESCAPE:
			_set_key(_capturing, event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode)
		_capturing = ""
		_render_controls()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F1:
		if _window != null and _window.visible:
			_window.hide_window()
		else:
			open(true)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _window != null and _window.visible:
		_window.hide_window()
		get_viewport().set_input_as_handled()


func _key(action: String) -> int:
	if _keys.has(action):
		return _keys[action]
	var keys: Array = _defaults.get(action, [])
	return keys[0] if not keys.is_empty() else KEY_NONE


func _bind(action: String) -> void:
	InputMap.action_erase_events(action)
	var keys: Array = _defaults.get(action, []).duplicate()
	if _keys.has(action):
		if keys.is_empty():
			keys.append(_keys[action])
		else:
			keys[0] = _keys[action]
	for key: int in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


## Puts an action on a key. Another action of the same screen on that key takes the old one, so no key
## does two things and no action is left without a key.
func _set_key(action: String, key: int) -> void:
	var old := _key(action)
	if key == old:
		return
	for other: String in _defaults:
		if other != action and _key(other) == key and _share_screen(action, other):
			_keys[other] = old
			if InputMap.has_action(other):
				_bind(other)
	_keys[action] = key
	if InputMap.has_action(action):
		_bind(action)
	_save()


func _share_screen(a: String, b: String) -> bool:
	for path: String in SCREENS.values():
		var actions: Dictionary = (load(path) as Script).get_script_constant_map().get("ACTIONS", {})
		if actions.has(a) and actions.has(b):
			return true
	return false


func _reset_keys() -> void:
	_keys.clear()
	for action: String in _defaults:
		if InputMap.has_action(action):
			_bind(action)
	_save()
	_render_controls()


func _apply_view() -> void:
	get_tree().root.content_scale_factor = ui_scale
	Engine.max_fps = fps_limit


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("view", "scale", ui_scale)
	config.set_value("view", "effects", effects)
	config.set_value("view", "fps", fps_limit)
	config.set_value("sound", "music", music_volume)
	config.set_value("sound", "effects", sfx_volume)
	for action: String in _keys:
		config.set_value("keys", action, _keys[action])
	config.save(FILE)
	changed.emit()


func _set_scale(step: int) -> void:
	var at := clampi(SCALES.find(ui_scale) + step, 0, SCALES.size() - 1)
	ui_scale = SCALES[at]
	_apply_view()
	_save()
	_render_general()
	_window.show_window.call_deferred()


func _set_fps(limit: int) -> void:
	fps_limit = limit
	_apply_view()
	_save()
	_render_general()


## Turns the music ("music") or the effects ("effects") up or down by a tenth.
func _set_volume(which: String, step: int) -> void:
	var value := snappedf(clampf((music_volume if which == "music" else sfx_volume) + step * 0.1, 0.0, 1.0), 0.1)
	if which == "music":
		music_volume = value
	else:
		sfx_volume = value
	_save()
	_render_general()


func _toggle_effects() -> void:
	effects = not effects
	_save()
	_render_general()


# --- The window ------------------------------------------------------------------------

func _build() -> void:
	if _window != null:
		return
	_layer = CanvasLayer.new()
	_layer.layer = 60
	add_child(_layer)
	var root := Control.new()
	# A layer does not pass the screen's theme on to its controls.
	root.theme = UI.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	_window = GameWindow.new("Ustawienia", 460)
	_window.closed.connect(func() -> void: _capturing = "")
	root.add_child(_window)
	_window.dock_right(12.0, 64.0)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	_general_tab = UI.button("Ogólne", _show_tab.bind(false))
	_controls_tab = UI.button("Sterowanie" if not UI.touch() else "Gesty", _show_tab.bind(true))
	for tab: Button in [_general_tab, _controls_tab]:
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	_window.content.add_child(tabs)
	_general.add_theme_constant_override("separation", 6)
	_window.content.add_child(_general)
	_controls.add_theme_constant_override("separation", 4)
	_window.content.add_child(_controls)

	_general.add_child(_heading("Wielkość interfejsu"))
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	scale_row.add_child(UI.button("−", _set_scale.bind(-1)))
	_scale_label = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_scale_label.custom_minimum_size.x = 70
	scale_row.add_child(_scale_label)
	scale_row.add_child(UI.button("+", _set_scale.bind(1)))
	_general.add_child(scale_row)
	_general.add_child(UI.label("Litery, przyciski, okna i paski. Świat na działce zostaje tej samej wielkości.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_general.add_child(HSeparator.new())

	_general.add_child(_heading("Dźwięk"))
	for which: Array in [["music", "Muzyka"], ["effects", "Efekty dźwiękowe"]]:
		var volume_row := HBoxContainer.new()
		volume_row.add_theme_constant_override("separation", 6)
		var name_label := UI.label(which[1])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		volume_row.add_child(name_label)
		volume_row.add_child(UI.button("−", _set_volume.bind(which[0], -1)))
		var value_label := UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		value_label.custom_minimum_size.x = 70
		_volume_labels[which[0]] = value_label
		volume_row.add_child(value_label)
		volume_row.add_child(UI.button("+", _set_volume.bind(which[0], 1)))
		_general.add_child(volume_row)
	_general.add_child(HSeparator.new())

	_general.add_child(_heading("Efekty"))
	_effects_button = UI.button("", _toggle_effects)
	_general.add_child(_effects_button)
	_general.add_child(UI.label("Dym z pieców, wióry, kurz, konfetti i drżenie ekranu. Znaczki nad stojącymi maszynami i wskazane miejsca zostają zawsze.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_general.add_child(HSeparator.new())

	_general.add_child(_heading("Limit klatek na sekundę"))
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 4)
	for limit: int in FPS_LIMITS:
		var b := UI.button("Bez limitu" if limit == 0 else str(limit), _set_fps.bind(limit))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_fps_buttons.append(b)
		fps_row.add_child(b)
	_general.add_child(fps_row)
	_general.add_child(UI.label("30 klatek oszczędza baterię telefonu i chłodzi laptopa; gra wygląda wtedy odrobinę mniej płynnie.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_general.add_child(UI.label("Ustawienia zostają na tym urządzeniu.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


func _show_tab(controls: bool) -> void:
	_general.visible = not controls
	_controls.visible = controls
	_mark(_general_tab, not controls)
	_mark(_controls_tab, controls)
	if controls:
		_render_controls()
	else:
		_render_general()
	_window._fit.call_deferred()


func _render_general() -> void:
	_scale_label.text = "%d%%" % roundi(ui_scale * 100.0)
	_effects_button.text = "Włączone" if effects else "Wyłączone"
	for which: String in _volume_labels:
		var value := music_volume if which == "music" else sfx_volume
		(_volume_labels[which] as Label).text = "Wyłączone" if value <= 0.0 else "%d%%" % roundi(value * 100.0)
	_mark(_effects_button, effects)
	for i in FPS_LIMITS.size():
		_mark(_fps_buttons[i], FPS_LIMITS[i] == fps_limit)


## The chosen one of a few buttons stands out in gold.
func _mark(button: Button, chosen: bool) -> void:
	button.theme_type_variation = "AccentButton" if chosen else ""


func _render_controls() -> void:
	if _window == null:
		return
	UI.clear(_controls)
	if UI.touch():
		for line: Array in [
			["Dotknięcie", "Kliknięcie: użyj, postaw, idź"],
			["Przytrzymanie obiektu", "Schowaj go do ekwipunku"],
			["Przytrzymanie przedmiotu", "Opis i ceny"],
			["Dwa palce", "Przybliż i oddal"],
			["Dotknięcie przedmiotu w ekwipunku", "Przy otwartej skrzyni lub maszynie: włóż, ile chcesz"],
			["Przeciągnięcie przedmiotu na okno", "Włóż go do skrzyni lub maszyny"],
			["Menu obiektu", "Pipeta, kopiuj i wklej ustawienia"],
		]:
			_controls.add_child(_shortcut_row(line[0], line[1]))
		return
	_controls.add_child(UI.label("Kliknij klawisz, a potem naciśnij nowy. Esc anuluje.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var listed := {}
	for screen: String in SCREENS:
		_controls.add_child(_heading(screen))
		var actions: Dictionary = (load(SCREENS[screen]) as Script).get_script_constant_map().get("ACTIONS", {})
		for action: String in actions:
			if listed.has(action):
				continue
			listed[action] = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var name_label := UI.label(ACTION_NAMES.get(action, action))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var b := UI.button("Naciśnij klawisz…" if _capturing == action else key_name(action), _capture.bind(action))
			b.custom_minimum_size.x = 110
			if _keys.has(action):
				b.theme_type_variation = "AccentButton"
			row.add_child(b)
			_controls.add_child(row)
	_controls.add_child(HSeparator.new())
	_controls.add_child(_heading("Inne skróty"))
	for line: Array in FIXED:
		_controls.add_child(_shortcut_row(line[0], line[1]))
	_controls.add_child(UI.button("Przywróć domyślne klawisze", _reset_keys))
	_window._fit.call_deferred()


func _capture(action: String) -> void:
	_capturing = action
	_render_controls()


func _shortcut_row(keys: String, what: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var key_label := UI.label(keys, UI.GOLD)
	key_label.custom_minimum_size.x = 190
	key_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(key_label)
	var what_label := UI.label(what, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	what_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(what_label)
	return row


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
