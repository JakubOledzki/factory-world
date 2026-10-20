class_name UI
## Pixel-art theme and small helpers for building screens in code.

const BACKGROUND := Color("#181425")
const TEXT := Color("#ead4aa")
const ERROR := Color("#e43b44")
const MUTED := Color("#8b9bb4")
const GOOD := Color("#63c74d")
const GOLD := Color("#feae34")

const FONT_SIZE := 16
const TITLE_SIZE := 32

static var _theme: Theme


## The game's theme: pixel font and 9-sliced pixel-art panels, buttons, slots and bars.
## Game sets it on the root window, so every screen uses it.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()

	t.default_font = pixel_font("Jersey10")
	t.default_font_size = FONT_SIZE

	var window := _box("ui_panel", 6, 9)
	t.set_stylebox("panel", "PanelContainer", window)
	t.set_stylebox("panel", "Panel", window)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	for type in ["Button", "AccentButton"]:
		var prefix := "ui_button" if type == "Button" else "ui_button_accent"
		var hover := prefix + "_hover"
		t.set_stylebox("normal", type, _box(prefix, 4, 6, 2))
		t.set_stylebox("hover", type, _box(hover, 4, 6, 2))
		t.set_stylebox("pressed", type, _box("ui_button_pressed", 4, 6, 2, 1))
		t.set_stylebox("disabled", type, _box("ui_button_pressed", 4, 6, 2, 1, Color(1, 1, 1, 0.5)))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT if type == "Button" else Color.WHITE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, MUTED)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.6))
		t.set_color("font_focus_color", type, TEXT if type == "Button" else Color.WHITE)
	t.set_type_variation("AccentButton", "Button")

	var field := _box("ui_slot", 3, 5, 3)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _box("ui_slot", 3, 5, 3, 0, Color("#c0cbdc")))
	t.set_color("font_color", "LineEdit", Color.WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color("#3a4466"))

	t.set_stylebox("background", "ProgressBar", _box("ui_slot", 2, 2))
	t.set_stylebox("fill", "ProgressBar", _box("ui_bar_progress", 1, 1))
	t.set_stylebox("background", "XpBar", _box("ui_slot", 2, 2))
	t.set_stylebox("fill", "XpBar", _box("ui_bar_xp", 1, 1))
	t.set_type_variation("XpBar", "ProgressBar")

	var tooltip := _box("ui_panel", 6, 5)
	t.set_stylebox("panel", "TooltipPanel", tooltip)
	t.set_color("font_color", "TooltipLabel", TEXT)

	t.set_stylebox("separator", "HSeparator", _line())
	t.set_constant("separation", "HSeparator", 6)

	_theme = t
	return t


## A font from res://fonts rasterised once at its native pixel size and only scaled by whole
## numbers, so every glyph sits on the pixel grid even when the window is enlarged.
static func pixel_font(name: String) -> FontFile:
	var font: FontFile = load("res://fonts/%s.ttf" % name)
	font.fixed_size = 16
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return font


static func texture(name: String) -> Texture2D:
	return load("res://art/%s.png" % name)


## A 9-sliced texture box: margin = slice size in art pixels, content = padding inside.
static func _box(art: String, margin: int, content_x: int, content_y := -1, shift := 0, tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture(art)
	box.set_texture_margin_all(margin)
	box.content_margin_left = content_x
	box.content_margin_right = content_x
	var y := content_x if content_y < 0 else content_y
	box.content_margin_top = y + shift
	box.content_margin_bottom = y - shift
	box.modulate_color = tint
	return box


static func _line() -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = Color("#3a4466")
	line.thickness = 1
	return line


## A full-screen background with a centered panel; returns the panel's vertical box.
static func centered_panel(parent: Control, width: int) -> VBoxContainer:
	var background := TextureRect.new()
	background.texture = texture("bricks")
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.modulate = Color(0.45, 0.42, 0.5)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = width
	center.add_child(frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)
	return box


## A panel with its own vertical box, for floating windows; returns [panel, box].
static func panel(separation := 4) -> Array:
	var p := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	p.add_child(box)
	return [p, box]


static func title(text: String) -> Label:
	var l := label(text, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", pixel_font("Jersey10"))
	l.add_theme_font_size_override("font_size", TITLE_SIZE)
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


static func icon(name: String, scale := 1) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture(name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = rect.texture.get_size() * scale
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


## Money in cents as "1 234,50"; screens show the coin icon next to it instead of a "$",
## which the pixel font draws almost like an "S".
static func money(cents: int) -> String:
	var whole := str(absi(cents) / 100)
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			grouped += " "
		grouped += whole[i]
	return "%s%s,%02d" % ["-" if cents < 0 else "", grouped, absi(cents) % 100]
