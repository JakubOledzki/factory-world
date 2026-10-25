class_name CharacterWindow
extends GameWindow
## The player's character, opened from the portrait in the corner: the clothes worn on the head,
## body, legs and feet with the bonuses they give the industries, and a new look (face, hair,
## colours) for a fee, and what every fifth level adds to the same bonuses. Clothes are sewn in the
## tailor's workshop in town or bought.

signal failed(reply: Dictionary)
## After paying for a new look, so the money shown follows.
signal balance_changed

const TABS := ["Ubrania", "Wygląd", "Poziomy"]
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
## What can be eaten on the go, for a while of faster hand work (as the server's Items.Meals).
const MEALS := ["bread", "scrambled_eggs", "workers_lunch", "cheese_sandwich", "miners_breakfast", "lumberjack_goulash"]
const EAT := 2000

var _tab := 0
var _tab_buttons: Array[Button] = []
var _preview := CharacterPreview.new()
var _clothes_page := VBoxContainer.new()
var _look_page := VBoxContainer.new()
var _levels_page := VBoxContainer.new()
var _level_summary := VBoxContainer.new()
var _level_rows := VBoxContainer.new()
var _level_heading := UI.label("", UI.GOLD)
var _level_progress := UI.label("", UI.MUTED)
var _slot_tiles := {}
var _bonuses := VBoxContainer.new()
var _rows := AppearanceRows.new(2 if UI.touch() else 1)
var _save: Button
var _error := UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
var _menu := PopupMenu.new()
var _choices: Array[String] = []
var _menu_slot := ""
var _meal := UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
var _eat: Button


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
	pages.add_child(_levels_page)
	columns.add_child(pages)
	_build_clothes()
	_build_look()
	_build_levels()
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
	_levels_page.visible = _tab == 2
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
	var heading := UI.label("Premie z ubrań i poziomu", UI.GOLD)
	heading.add_theme_font_override("font", UI.bold())
	_clothes_page.add_child(heading)
	_bonuses.add_theme_constant_override("separation", 2)
	_clothes_page.add_child(_bonuses)
	_clothes_page.add_child(HSeparator.new())
	var meal_heading := UI.label("Posiłek", UI.GOLD)
	meal_heading.add_theme_font_override("font", UI.bold())
	_clothes_page.add_child(meal_heading)
	var meal_row := HBoxContainer.new()
	meal_row.add_theme_constant_override("separation", 6)
	_meal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_meal.custom_minimum_size.x = 220
	meal_row.add_child(_meal)
	_eat = UI.button("Zjedz…", func() -> void: _open_meals(_eat))
	meal_row.add_child(_eat)
	_clothes_page.add_child(meal_row)
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
	var meal: Variant = Game.character.get("meal")
	if meal is Dictionary:
		var left := (float(meal["until"]) - Time.get_unix_time_from_system() * 1000.0) / 60000.0
		_meal.text = "%s: %s jeszcze ok. %d min." % [meal["name"], _bonus_text(meal.get("bonuses", {})), maxi(1, ceili(left))]
		_meal.add_theme_color_override("font_color", UI.GOOD)
	else:
		_meal.text = "Głodny. Zjedz coś w biegu: chleb, kanapkę, gulasz drwala…, a przez chwilę popracujesz szybciej."
		_meal.add_theme_color_override("font_color", UI.MUTED)
	_refresh_levels()
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


## The meals in the inventory, next to the button; a new one replaces what was eaten before.
func _open_meals(tile: Control) -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] != "inventory":
		failed.emit(reply)
		return
	_menu.clear()
	_choices.clear()
	var seen := {}
	for stack: Dictionary in reply["payload"]["items"]:
		var item: String = stack["id"]
		if item in MEALS and not seen.has(item):
			seen[item] = true
			_menu.add_icon_item(UI.item_texture(item), "Zjedz: %s" % stack["name"], EAT + _choices.size())
			_choices.append(item)
	if _menu.item_count == 0:
		_menu.add_item("Nie masz nic do jedzenia w biegu.", -1)
		_menu.set_item_disabled(0, true)
	_menu.reset_size()
	var at := tile.get_screen_transform() * Vector2(tile.size.x + 4, 0)
	_menu.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


func _on_choice(id: int) -> void:
	if id >= EAT and id - EAT < _choices.size():
		_send("character.eat", {"item": _choices[id - EAT]})
	elif id == TAKE_OFF:
		_send("character.unequip", {"clothing": _menu_slot})
	elif id >= 0 and id < _choices.size():
		_send("character.equip", {"item": _choices[id]})


func _send(type: String, payload: Dictionary) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "character":
		failed.emit(reply)
		return
	Game.character = reply["payload"]


# --- Levels ----------------------------------------------------------------------

func _build_levels() -> void:
	_levels_page.add_theme_constant_override("separation", 8)
	_level_heading.add_theme_font_override("font", UI.bold())
	_levels_page.add_child(_level_heading)
	_level_progress.add_theme_font_size_override("font_size", 13)
	_levels_page.add_child(_level_progress)
	_level_summary.add_theme_constant_override("separation", 2)
	_levels_page.add_child(_level_summary)
	_levels_page.add_child(HSeparator.new())
	var intro := UI.label("Co piąty poziom dodaje premię, która sumuje się z premiami z ubrań.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	intro.add_theme_font_size_override("font_size", 13)
	intro.custom_minimum_size.x = 300
	_levels_page.add_child(intro)
	var list := ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.custom_minimum_size.y = 260 if UI.touch() else 300
	_level_rows.add_theme_constant_override("separation", 2)
	_level_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(_level_rows)
	_levels_page.add_child(list)


func _refresh_levels() -> void:
	var c := Game.character
	var level := int(c.get("level", 1))
	var next_xp: Variant = c.get("nextLevelXp")
	_level_heading.text = "Poziom %d" % level
	_level_progress.text = "%d / %d XP do poziomu %d" % [int(c.get("xp", 0)), int(next_xp), level + 1] if next_xp != null else "%d XP, najwyższy poziom" % int(c.get("xp", 0))
	UI.clear(_level_summary)
	var reached: Variant = c.get("levelBonuses")
	if reached is Dictionary and not reached.is_empty():
		for industry: String in INDUSTRIES:
			if reached.has(industry):
				var row := HBoxContainer.new()
				var name_label := UI.label(INDUSTRIES[industry][0], UI.MUTED)
				name_label.custom_minimum_size.x = 120
				row.add_child(name_label)
				row.add_child(UI.label(INDUSTRIES[industry][1] % int(reached[industry]), UI.GOOD))
				_level_summary.add_child(row)
	else:
		_level_summary.add_child(UI.label("Jeszcze bez premii z poziomu.", UI.MUTED))
	UI.clear(_level_rows)
	var marked_next := false
	for reward: Dictionary in c.get("levelRewards", []):
		var at := int(reward["level"])
		var industry: String = reward["industry"]
		var done := at <= level
		var is_next := not done and not marked_next
		marked_next = marked_next or is_next
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var at_label := UI.label("Poziom %d" % at, UI.GOLD if is_next else (UI.TEXT if done else UI.MUTED))
		at_label.custom_minimum_size.x = 90
		if is_next:
			at_label.add_theme_font_override("font", UI.bold())
		row.add_child(at_label)
		var names: Array = INDUSTRIES.get(industry, [industry, "+%d%%"])
		var text := UI.label("%s +%d%%" % [names[0], int(reward["percent"])], UI.GOOD if done else UI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(UI.label("zdobyte" if done else ("następna" if is_next else ""), UI.GOOD if done else UI.GOLD))
		_level_rows.add_child(row)


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
