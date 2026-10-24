class_name UI
## The game's dark industrial theme and small helpers for building screens in code.

const BACKGROUND := Color("#0c0c0d")
const TEXT := Color("#e6e1d6")
const ERROR := Color("#ff6b5a")
const MUTED := Color("#9a968e")
const GOOD := Color("#8fd65a")
const GOLD := Color("#f5b041")

const FONT_SIZE := 15
const TITLE_SIZE := 28
## On phones and tablets letters are this much bigger, and buttons taller.
const TOUCH_SCALE := 1.5

static var _theme: Theme
static var _bold: Font
static var _touch: Variant = null


## Whether the game runs on a touch screen. In the browser, ?touch=1 or ?touch=0 in the
## address overrides it, for trying the phone controls on a computer.
static func touch() -> bool:
	if _touch == null:
		_touch = DisplayServer.is_touchscreen_available()
		if OS.has_feature("web"):
			var param: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('touch')")
			if param in ["0", "1"]:
				_touch = param == "1"
	return _touch


## Game sets this theme on the root window, so every screen uses it.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = load("res://fonts/TitilliumWeb-Regular.ttf")
	t.default_font_size = roundi(FONT_SIZE * TOUCH_SCALE) if touch() else FONT_SIZE
	# Taller buttons and fields on touch screens, so a finger hits them.
	var pad := 7 if touch() else 0

	var window := _box("panel", 12, 12, 10)
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)

	t.set_color("font_color", "Label", TEXT)

	for type in ["Button", "AccentButton"]:
		var prefix := "button" if type == "Button" else "button_accent"
		t.set_stylebox("normal", type, _box(prefix, 8, 10, 3 + pad))
		t.set_stylebox("hover", type, _box(prefix + "_hover", 8, 10, 3 + pad))
		t.set_stylebox("pressed", type, _box("button_pressed", 8, 10, 3 + pad, 1))
		t.set_stylebox("disabled", type, _box("button_pressed", 8, 10, 3 + pad, 1, Color(1, 1, 1, 0.55)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_font("font", type, bold())
		var ink := TEXT if type == "Button" else Color("#2a1604")
		t.set_color("font_color", type, ink)
		t.set_color("font_hover_color", type, Color.WHITE if type == "Button" else ink)
		t.set_color("font_pressed_color", type, MUTED)
		t.set_color("font_focus_color", type, ink)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.55))
	t.set_type_variation("AccentButton", "Button")

	t.set_stylebox("normal", "LineEdit", _box("inset", 8, 8, 5 + pad))
	t.set_stylebox("focus", "LineEdit", _box("inset", 8, 8, 5 + pad, 0, Color(1.25, 1.2, 1.1)))
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.35))

	for bar in [["ProgressBar", "bar_progress"], ["XpBar", "bar_xp"]]:
		t.set_stylebox("background", bar[0], _box("inset", 6, 2))
		t.set_stylebox("fill", bar[0], _box(bar[1], 3, 0))
	t.set_type_variation("XpBar", "ProgressBar")

	t.set_stylebox("panel", "TooltipPanel", _box("panel", 12, 8, 4))

	t.set_stylebox("panel", "PopupMenu", _box("panel", 12, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _box("button_accent", 8, 6, 2))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color("#2a1604"))
	t.set_color("font_disabled_color", "PopupMenu", Color(MUTED, 0.55))
	t.set_constant("v_separation", "PopupMenu", 6)
	t.set_color("font_color", "TooltipLabel", TEXT)

	var line := StyleBoxLine.new()
	line.color = Color("#3a3a3e")
	line.thickness = 1
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 6)

	_theme = t
	return t


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://fonts/TitilliumWeb-Bold.ttf")
	return _bold


static func texture(path: String) -> Texture2D:
	return load("res://art/%s.png" % path)


## A 9-sliced texture box: margin = slice size, content = padding inside.
static func _box(art: String, margin: int, content_x: int, content_y := -1, shift := 0, tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture("ui/" + art)
	box.set_texture_margin_all(margin)
	box.content_margin_left = content_x
	box.content_margin_right = content_x
	var y := content_x if content_y < 0 else content_y
	box.content_margin_top = y + shift
	box.content_margin_bottom = y - shift
	box.modulate_color = tint
	if art in ["panel", "inset"]:
		# Tiling keeps the metal's grain sharp instead of smearing it over large panels.
		box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return box


## The garage render, dimmed, behind a centered panel; returns the panel's vertical box.
static func centered_panel(parent: Control, width: int) -> VBoxContainer:
	var background := TextureRect.new()
	background.texture = load("res://art/garage/background.jpg")
	background.modulate = Color(0.45, 0.45, 0.48)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = width
	center.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	frame.add_child(box)
	return box


## A panel with its own vertical box, for floating windows; returns [panel, box].
static func panel(separation := 6) -> Array:
	var p := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	p.add_child(box)
	return [p, box]


static func title(text: String, size := TITLE_SIZE) -> Label:
	var l := label(text, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", bold())
	l.add_theme_font_size_override("font_size", size)
	return l


## Set wrap only for labels inside a box of fixed width; in a grid a wrapping label collapses.
static func label(text: String, color := TEXT, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l


## The icon of an inventory item: furniture icons are named after the item, others "item_<id>".
static func item_icon(item: String, size := 32) -> TextureRect:
	var rect := icon(item if item.begins_with("furniture_") else "item_" + item, size)
	# For the card ItemTooltip shows with Ctrl held.
	rect.set_meta("item", item)
	rect.mouse_filter = Control.MOUSE_FILTER_PASS
	return rect


static func item_texture(item: String) -> Texture2D:
	return texture("icons/" + (item if item.begins_with("furniture_") else "item_" + item))


## An item or coin icon from art/icons, shown at `size` pixels.
static func icon(name: String, size := 32) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture("icons/" + name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(size, size)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


static func line_edit(placeholder: String, secret := false) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	return edit


static func button(text: String, on_pressed: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	if accent:
		b.theme_type_variation = "AccentButton"
	b.pressed.connect(on_pressed)
	return b


## Money in cents as "1 234,50 $".
static func money(cents: int) -> String:
	var whole := str(absi(cents) / 100)
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			grouped += " "
		grouped += whole[i]
	return "%s%s,%02d $" % ["-" if cents < 0 else "", grouped, absi(cents) % 100]
