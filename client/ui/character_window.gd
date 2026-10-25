class_name CharacterWindow
extends GameWindow
## The player's character, opened from the portrait in the corner: the clothes worn on the head,
## body, legs and feet with the bonuses they give the industries, and a new look (face, hair,
## colours) for a fee. Clothes are sewn in the tailor's workshop in town or bought.

signal failed(reply: Dictionary)
## After paying for a new look, so the money shown follows.
signal balance_changed

const TABS := ["Ubrania", "Wygląd"]
const SLOTS := ["head", "body", "legs", "feet"]
const SLOT_NAMES := {"head": "Głowa", "body": "Tułów", "legs": "Nogi", "feet": "Stopy"}
## How each industry's bonus reads.
const INDUSTRIES := {
	"forestry": ["Leśnictwo", "wycinka i sadzenie drzew %d%% szybciej"],
	"mining": ["Górnictwo", "kopanie %d%% szybciej"],
	"farming": ["Rolnictwo", "orka, siew i zbiory %d%% szybciej"],
	"fishing": ["Rybołówstwo", "łowienie %d%% szybciej"],
	"crafting": ["Rzemiosło", "wytwarzanie %d%% szybciej"],
	"trade": ["Handel", "handlarz płaci %d%% więcej"],
}
## Shown faded in an empty slot.
const EMPTY_ICONS := {"head": "clothes_beanie", "body": "clothes_flannel_jacket", "legs": "clothes_work_trousers", "feet": "clothes_work_boots"}
const TAKE_OFF := 1000

var _tab := 0
var _tab_buttons: Array[Button] = []
var _preview := CharacterPreview.new()
var _clothes_page := VBoxContainer.new()
var _look_page := VBoxContainer.new()
var _slot_tiles := {}
var _bonuses := VBoxContainer.new()
var _rows := AppearanceRows.new(2 if UI.touch() else 1)
var _save: Button
var _error := UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
var _menu := PopupMenu.new()
var _choices: Array[String] = []
var _menu_slot := ""


func _init() -> void:
	super("Postać", 0 if UI.touch() else 720)
	if UI.touch():
		fill_margin = Vector2(24, 16)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _open_tab.bind(i))
		b.custom_minimum_size.x = 150
		top.add_child(b)
		_tab_buttons.append(b)
	content.add_child(top)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	content.add_child(columns)
	_preview.display_scale = 1.0 if UI.touch() else 0.85
	_preview.options = Game.appearance_options
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(_preview)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(_clothes_page)
	pages.add_child(_look_page)
	columns.add_child(pages)
	_build_clothes()
	_build_look()
	_error.visible = false
	content.add_child(_error)

	_menu.add_theme_constant_override("icon_max_width", 32)
	_menu.id_pressed.connect(_on_choice)
	add_child(_menu)
	Game.character_changed.connect(_refresh)


func show_window() -> void:
	super()
	_error.visible = false
	_rows.set_appearance(Game.character.get("appearance", {}))
	_open_tab(_tab)


func _open_tab(tab: int) -> void:
	_tab = tab
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == _tab else ""
	_clothes_page.visible = _tab == 0
	_look_page.visible = _tab == 1
	_refresh()


# --- Clothes ---------------------------------------------------------------------

func _build_clothes() -> void:
	_clothes_page.add_theme_constant_override("separation", 8)
	for slot: String in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tile := PanelContainer.new()
		var frame := StyleBoxTexture.new()
		frame.texture = UI.texture("ui/inset")
		frame.set_texture_margin_all(8)
		frame.set_content_margin_all(4)
		tile.add_theme_stylebox_override("panel", frame)
		tile.custom_minimum_size = Vector2(64, 64)
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.tooltip_text = "Kliknij, aby założyć albo zdjąć"
		tile.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_open_slot(slot, tile)
				tile.accept_event())
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(54, 54)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon)
		row.add_child(tile)
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 0)
		text.alignment = BoxContainer.ALIGNMENT_CENTER
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := UI.label("")
		name_label.add_theme_font_override("font", UI.bold())
		text.add_child(name_label)
		var bonus := UI.label("", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true)
		bonus.add_theme_font_size_override("font_size", 13)
		text.add_child(bonus)
		row.add_child(text)
		_clothes_page.add_child(row)
		_slot_tiles[slot] = {"icon": icon, "name": name_label, "bonus": bonus}

	_clothes_page.add_child(HSeparator.new())
	var heading := UI.label("Premie z ubrań", UI.GOLD)
	heading.add_theme_font_override("font", UI.bold())
	_clothes_page.add_child(heading)
	_bonuses.add_theme_constant_override("separation", 2)
	_clothes_page.add_child(_bonuses)
	var hint := UI.label("Ubrania szyje pracownia krawiecka w mieście (badanie „Krawiectwo”). Niektóre sprzedają sklepy miast i handlarz.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	hint.add_theme_font_size_override("font_size", 13)
	hint.custom_minimum_size.x = 300
	_clothes_page.add_child(hint)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var look := Game.look()
	if _tab == 1:
		look.merge(_rows.appearance, true)
	_preview.appearance = look
	var outfit: Variant = Game.character.get("outfit")
	for slot: String in SLOTS:
		var parts: Dictionary = _slot_tiles[slot]
		var worn: Variant = outfit.get(slot) if outfit is Dictionary else null
		var icon: TextureRect = parts["icon"]
		if worn is Dictionary:
			icon.texture = UI.item_texture(worn["id"])
			icon.modulate = Color.WHITE
			parts["name"].text = "%s: %s" % [SLOT_NAMES[slot], worn["name"]]
			parts["bonus"].text = _bonus_text(worn.get("bonuses", {}))
		else:
			icon.texture = UI.item_texture(EMPTY_ICONS[slot])
			icon.modulate = Color(0, 0, 0, 0.35)
			parts["name"].text = "%s: nic" % SLOT_NAMES[slot]
			parts["bonus"].text = ""
	UI.clear(_bonuses)
	var bonuses: Variant = Game.character.get("bonuses")
	if bonuses is Dictionary and not bonuses.is_empty():
		for industry: String in INDUSTRIES:
			if bonuses.has(industry):
				var row := HBoxContainer.new()
				var name_label := UI.label(INDUSTRIES[industry][0], UI.MUTED)
				name_label.custom_minimum_size.x = 120
				row.add_child(name_label)
				row.add_child(UI.label(INDUSTRIES[industry][1] % int(bonuses[industry]), UI.GOOD))
				_bonuses.add_child(row)
	else:
		_bonuses.add_child(UI.label("Brak. Załóż ubranie, by pracować szybciej.", UI.MUTED))
	_update_save()


func _bonus_text(bonuses: Dictionary) -> String:
	var parts: Array[String] = []
	for industry: String in INDUSTRIES:
		if bonuses.has(industry):
			parts.append("%s +%d%%" % [INDUSTRIES[industry][0], int(bonuses[industry])])
	return ", ".join(parts)


## The clothes for a slot in the inventory, next to its tile, and "take off".
func _open_slot(slot: String, tile: Control) -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		failed.emit(reply)
		return
	_menu_slot = slot
	_menu.clear()
	_choices.clear()
	var rendered: Dictionary = CharacterLayers.meta().get("clothes", {})
	for stack: Dictionary in reply["payload"]["items"]:
		var item: String = stack["id"]
		if rendered.get(item) == slot:
			_menu.add_icon_item(UI.item_texture(item), "Załóż: %s" % stack["name"], _choices.size())
			_choices.append(item)
	var outfit: Variant = Game.character.get("outfit")
	if outfit is Dictionary and outfit.has(slot):
		_menu.add_item("Zdejmij do ekwipunku", TAKE_OFF)
	if _menu.item_count == 0:
		_menu.add_item("Nie masz ubrań na to miejsce.", -1)
		_menu.set_item_disabled(0, true)
	_menu.reset_size()
	var at := tile.get_screen_transform() * Vector2(tile.size.x + 4, 0)
	_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_choice(id: int) -> void:
	if id == TAKE_OFF:
		_send("character.unequip", {"clothing": _menu_slot})
	elif id >= 0 and id < _choices.size():
		_send("character.equip", {"item": _choices[id]})


func _send(type: String, payload: Dictionary) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "character":
		failed.emit(reply)
		return
	Game.character = reply["payload"]


# --- Look --------------------------------------------------------------------------

func _build_look() -> void:
	_look_page.add_theme_constant_override("separation", 8)
	var intro := UI.label("Nowa twarz, fryzura, zarost albo kolory. Podgląd obok pokazuje zmiany od razu, zapłacisz dopiero przy zapisie.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	intro.add_theme_font_size_override("font_size", 13)
	intro.custom_minimum_size.x = 300
	_look_page.add_child(intro)
	_rows.changed.connect(_refresh)
	_look_page.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.add_child(UI.button("Przywróć", func() -> void:
		_rows.set_appearance(Game.character.get("appearance", {}))
		_refresh()))
	buttons.add_child(UI.button("Losuj", _rows.randomize_look))
	_save = UI.button("", _restyle, true)
	_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_save)
	_look_page.add_child(buttons)


func _changed_look() -> bool:
	var now: Dictionary = Game.character.get("appearance", {})
	for key: String in _rows.appearance:
		if int(now.get(key, 0)) != int(_rows.appearance[key]):
			return true
	return false


func _update_save() -> void:
	if _save == null:
		return
	var cost := int(Game.character.get("restyleCents", 100000))
	_save.text = "Zmień wygląd za %s" % UI.money(cost)
	_save.disabled = not _changed_look()


func _restyle() -> void:
	_save.disabled = true
	_error.visible = false
	var reply := await Net.request("character.restyle", {"appearance": _rows.appearance})
	if reply["type"] != "character":
		_error.text = Game.error_text(reply)
		_error.visible = true
		_update_save()
		return
	Game.character = reply["payload"]
	_rows.set_appearance(Game.character.get("appearance", {}))
	balance_changed.emit()
	_refresh()
