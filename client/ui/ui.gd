class_name UI
## Small helpers for building screens in code.

const BACKGROUND := Color(0.13, 0.12, 0.15)
const PANEL := Color(0.2, 0.19, 0.23)
const ERROR := Color(1.0, 0.45, 0.4)
const MUTED := Color(0.7, 0.68, 0.74)


## A full-screen background with a centered panel; returns the panel's vertical box.
static func centered_panel(parent: Control, width: int) -> VBoxContainer:
	var theme := Theme.new()
	theme.default_font_size = 12
	parent.theme = theme

	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = width
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


## Set wrap only for labels inside a box of fixed width; in a grid a wrapping label collapses.
static func label(text: String, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	return l


static func line_edit(placeholder: String, secret := false) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.secret = secret
	return edit


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b
