extends Control
## The player's garage: a 3D-rendered room with the trash bin, and a side panel
## with sorting, the storage and the trader.

## Positions of the rendered sprites on the 1280×720 screen, written by tools/render_art.py.
const LAYOUT_FILE := "res://art/garage/layout.json"
## Pixels per metre of the room and of the character renders; the character is scaled to match.
const PANEL_WIDTH := 380
const SLOTS := 10
## The garage is lit by one bulb, so the character is drawn darker than in the editor.
const ROOM_LIGHT := Color(0.66, 0.62, 0.58)

const TABS := ["Segregacja", "Magazyn", "Rynek"]

var _layout := {}
var _garage := {}
var _items: Array = []
var _prices: Array = []
var _balance := 0
## Server time minus local time, in ms, so timers follow the server's clock.
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _bin: TextureButton
var _effects: Control

var _level: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _money: Label
var _tab_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _error: Label

var _trash: Label
var _sort_buttons: Array[Button] = []
var _queue_text: Label
var _job_bar: ProgressBar
var _job_text: Label
var _recent: HFlowContainer

var _slots: GridContainer
var _market: VBoxContainer


func _ready() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_FILE))
	_build_room()
	_build_hud()
	_build_side_panel()
	_show_tab(0)
	_refresh_character()
	_load()


# --- Room ------------------------------------------------------------------------

func _build_room() -> void:
	var background := TextureRect.new()
	background.texture = load("res://art/garage/background.jpg")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The bin is already in the background; this copy only lights up under the mouse.
	var spot: Dictionary = _layout["bin"]
	_bin = TextureButton.new()
	_bin.texture_normal = load("res://art/garage/bin.png")
	_bin.texture_click_mask = _alpha_mask(_bin.texture_normal)
	_bin.position = Vector2(spot["x"], spot["y"])
	_bin.self_modulate = Color(1, 1, 1, 0)
	_bin.tooltip_text = "Kosz na śmieci: kliknij, aby segregować"
	_bin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bin.pressed.connect(_sort.bind(1))
	_bin.mouse_entered.connect(func() -> void: _bin.self_modulate = Color(1.6, 1.5, 1.3, 1))
	_bin.mouse_exited.connect(func() -> void: _bin.self_modulate = Color(1, 1, 1, 0))
	add_child(_bin)

	var player := CharacterPreview.new()
	player.options = Game.appearance_options
	player.appearance = Game.character.get("appearance", {})
	player.display_scale = float(_layout["pixelsPerMetre"]) / float(CharacterPreview.meta()["pixelsPerMetre"])
	player.light = ROOM_LIGHT
	player.show_shadow = true
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.position = Vector2(_layout["player"]["x"], _layout["player"]["y"]) - player.feet_offset()
	add_child(player)

	_effects = Control.new()
	_effects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effects)


func _alpha_mask(texture: Texture2D) -> BitMap:
	var mask := BitMap.new()
	mask.create_from_image_alpha(texture.get_image(), 0.3)
	return mask


# --- HUD -------------------------------------------------------------------------

func _build_hud() -> void:
	var parts := UI.panel(2)
	var hud: PanelContainer = parts[0]
	hud.position = Vector2(16, 16)
	add_child(hud)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parts[1].add_child(row)

	var portrait := CharacterPreview.new()
	portrait.options = Game.appearance_options
	portrait.appearance = Game.character.get("appearance", {})
	portrait.region = Rect2(0.12, 0.0, 0.76, 0.36)
	portrait.display_scale = 1.0
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	var name_label := UI.label(Game.character.get("name", ""))
	name_label.add_theme_font_override("font", UI.bold())
	name_label.add_theme_font_size_override("font_size", 22)
	name_row.add_child(name_label)
	_level = UI.label("", UI.GOLD)
	_level.add_theme_font_override("font", UI.bold())
	name_row.add_child(_level)
	info.add_child(name_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(220, 14)
	info.add_child(_xp_bar)
	_xp_text = UI.label("", UI.MUTED)
	info.add_child(_xp_text)


func _refresh_character() -> void:
	var c := Game.character
	var xp: int = c.get("xp", 0)
	var level_xp: int = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	_level.text = "Poziom %d" % c.get("level", 1)
	_xp_bar.max_value = (next_xp - level_xp) if next_xp != null else 1.0
	_xp_bar.value = xp - level_xp if next_xp != null else 1.0
	_xp_text.text = "%d / %d XP" % [xp, next_xp] if next_xp != null else "%d XP" % xp


## Applies an XP gain from the server; level thresholds follow the server's formula 200 × (L − 1)².
func _gain_xp(gain: Dictionary) -> void:
	var level: int = gain["level"]
	Game.character["xp"] = gain["xp"]
	Game.character["level"] = level
	Game.character["levelXp"] = 200 * (level - 1) * (level - 1)
	Game.character["nextLevelXp"] = 200 * level * level
	_refresh_character()
	if gain.get("leveledUp", false):
		_banner("Awans! Poziom %d" % level)


# --- Side panel --------------------------------------------------------------------

func _build_side_panel() -> void:
	var parts := UI.panel(10)
	var side: PanelContainer = parts[0]
	side.position = Vector2(1280 - PANEL_WIDTH - 16, 16)
	side.size = Vector2(PANEL_WIDTH, 720 - 32)
	add_child(side)
	var box: VBoxContainer = parts[1]

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.add_child(UI.icon("coin", 30))
	_money = UI.label("", UI.GOLD)
	_money.add_theme_font_override("font", UI.bold())
	_money.add_theme_font_size_override("font_size", 22)
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_money)
	header.add_child(UI.button("Wyloguj", Game.logout))
	box.add_child(header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _show_tab.bind(i))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons.append(b)
	box.add_child(tabs)

	for page in [_build_sorting(), _build_storage(), _build_market()]:
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(page)
		_pages.append(page)

	_error = UI.label("", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true)
	_error.visible = false
	box.add_child(_error)


func _show_tab(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == index else ""


func _build_sorting() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)

	var bin := HBoxContainer.new()
	bin.add_theme_constant_override("separation", 10)
	bin.add_child(UI.icon("item_trash", 56))
	var bin_text := VBoxContainer.new()
	bin_text.add_theme_constant_override("separation", 0)
	bin_text.alignment = BoxContainer.ALIGNMENT_CENTER
	var bin_title := UI.label("Kosz na śmieci")
	bin_title.add_theme_font_override("font", UI.bold())
	bin_text.add_child(bin_title)
	_trash = UI.label("", UI.MUTED)
	bin_text.add_child(_trash)
	bin.add_child(bin_text)
	page.add_child(bin)

	page.add_child(UI.label("Segregacja worka trwa 10 s i daje losowy surowiec oraz 5 XP.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	for count in [1, 10]:
		var b := UI.button("Segreguj %d" % count, _sort.bind(count), count == 10)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
		_sort_buttons.append(b)
	page.add_child(buttons)

	page.add_child(HSeparator.new())
	_queue_text = UI.label("")
	page.add_child(_queue_text)
	var job := HBoxContainer.new()
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size.y = 14
	_job_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job.add_child(_job_bar)
	_job_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_job_text.custom_minimum_size.x = 44
	job.add_child(_job_text)
	page.add_child(job)

	page.add_child(HSeparator.new())
	page.add_child(UI.label("Ostatnio wysegregowane:", UI.MUTED))
	_recent = HFlowContainer.new()
	_recent.add_theme_constant_override("h_separation", 4)
	_recent.add_theme_constant_override("v_separation", 4)
	page.add_child(_recent)
	return page


func _build_storage() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var heading := UI.label("Magazyn garażu")
	heading.add_theme_font_override("font", UI.bold())
	page.add_child(heading)
	_slots = GridContainer.new()
	_slots.columns = 5
	_slots.add_theme_constant_override("h_separation", 6)
	_slots.add_theme_constant_override("v_separation", 6)
	page.add_child(_slots)
	page.add_child(UI.label("Surowce sprzedasz handlarzowi w zakładce Rynek.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	return page


func _build_market() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	_market = VBoxContainer.new()
	_market.add_theme_constant_override("separation", 2)
	page.add_child(_market)
	return page


# --- Data from the server -------------------------------------------------------------

func _load() -> void:
	var replies := [
		await Net.request("garage.get"),
		await Net.request("inventory.get"),
		await Net.request("wallet.get"),
		await Net.request("market.prices"),
	]
	for reply: Dictionary in replies:
		if reply["type"] == "error":
			_show_error(reply)
			return
	_prices = replies[3]["payload"]["items"]
	_apply_garage(replies[0]["payload"])
	_apply_inventory(replies[1]["payload"])
	_set_balance(int(replies[2]["payload"]["balanceCents"]))


func _apply_garage(garage: Dictionary) -> void:
	_garage = garage
	_clock_offset = float(garage["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_trash.text = "Śmieci: %d" % garage["trash"]

	var results: Array = garage.get("results", [])
	for i in results.size():
		var item: Dictionary = results[i]
		_float_text("+1 %s" % item["name"], UI.TEXT, i * 0.25)
		var icon := UI.icon("item_" + item["id"], 40)
		icon.tooltip_text = item["name"]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_recent.add_child(icon)
		_recent.move_child(icon, 0)
	while _recent.get_child_count() > 24:
		_recent.get_child(_recent.get_child_count() - 1).free()
	if garage.get("xp") != null:
		_float_text("+%d XP" % (results.size() * 5), UI.GOLD, 0.0, -30)
		_gain_xp(garage["xp"])
	if not results.is_empty():
		_reload_inventory()
	_update_queue()


func _apply_inventory(inventory: Dictionary) -> void:
	_items = inventory["items"]
	for child in _slots.get_children():
		child.free()
	for i in SLOTS:
		_slots.add_child(_slot(_items[i] if i < _items.size() else {}))
	_rebuild_market()


func _reload_inventory() -> void:
	var reply := await Net.request("inventory.get")
	if reply["type"] == "inventory":
		_apply_inventory(reply["payload"])


func _set_balance(cents: int) -> void:
	_balance = cents
	_money.text = UI.money(cents)
	_rebuild_market()


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


# --- Sorting --------------------------------------------------------------------------

func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _process(_delta: float) -> void:
	if _garage.is_empty():
		return
	_update_queue()
	var queue: Array = _garage["queue"]
	var now := _server_now()
	if not queue.is_empty() and now >= float(queue[0]) and now >= _next_poll and not _refreshing:
		_collect()


## Asks the server for the garage; it hands out the sortings that have finished.
func _collect() -> void:
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("garage.get")
	_refreshing = false
	if reply["type"] == "garage":
		_apply_garage(reply["payload"])


func _update_queue() -> void:
	var queue: Array = _garage.get("queue", [])
	var max_queue: int = _garage.get("maxQueue", 10)
	var trash: int = _garage.get("trash", 0)
	var free := max_queue - queue.size()
	_queue_text.text = "Kolejka: %d / %d" % [queue.size(), max_queue]
	_sort_buttons[0].disabled = free < 1 or trash < 1
	_sort_buttons[1].disabled = free < 1 or trash < 1
	var batch := mini(mini(free, trash), 10)
	_sort_buttons[1].text = "Segreguj %d" % (batch if batch > 0 else 10)

	if queue.is_empty():
		_job_bar.value = 0
		_job_text.text = ""
		return
	var total: float = _garage.get("sortSeconds", 10) * 1000.0
	var left := maxf(float(queue[0]) - _server_now(), 0.0)
	_job_bar.max_value = total
	_job_bar.value = total - left
	_job_text.text = "%d s" % ceili(left / 1000.0)


func _sort(count: int) -> void:
	var queue: Array = _garage.get("queue", [])
	count = mini(count, mini(_garage.get("maxQueue", 10) - queue.size(), _garage.get("trash", 0)))
	if count < 1:
		_show_error({"payload": {"code": "queue_full" if _garage.get("trash", 0) > 0 else "not_enough_items"}})
		return
	_hide_error()
	_pulse()
	var reply := await Net.request("recycling.sort", {"count": count})
	if reply["type"] == "garage":
		_apply_garage(reply["payload"])
	else:
		_show_error(reply)


# --- Storage and market -----------------------------------------------------------------

func _slot(stack: Dictionary) -> Control:
	var slot := PanelContainer.new()
	var frame := StyleBoxTexture.new()
	frame.texture = UI.texture("ui/inset")
	frame.set_texture_margin_all(8)
	frame.set_content_margin_all(4)
	slot.add_theme_stylebox_override("panel", frame)
	slot.custom_minimum_size = Vector2(64, 64)
	if stack.is_empty():
		return slot
	slot.tooltip_text = "%s: %d" % [stack["name"], int(stack["quantity"])]
	var icon := UI.icon("item_" + stack["id"], 52)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_child(icon)
	var count := UI.label(str(int(stack["quantity"])), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	count.add_theme_font_override("font", UI.bold())
	count.add_theme_constant_override("outline_size", 5)
	count.add_theme_color_override("font_outline_color", UI.BACKGROUND)
	slot.add_child(count)
	return slot


func _rebuild_market() -> void:
	for child in _market.get_children():
		child.free()
	for price: Dictionary in _prices:
		var item: String = price["id"]
		var owned := _count(item)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(UI.icon("item_" + item, 36))
		var name_label := UI.label(price["name"])
		name_label.add_theme_font_override("font", UI.bold())
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		top.add_child(UI.label("masz %d" % owned, UI.MUTED))
		_market.add_child(top)

		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 6)
		var buying: bool = price.get("sellCents") == null
		var cents := int(price["buyCents"] if buying else price["sellCents"])
		var price_label := UI.label(("cena %s" if buying else "skup %s") % UI.money(cents), UI.GOLD if buying else UI.GOOD)
		price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(price_label)
		if buying:
			for amount in [1, 10]:
				var b := UI.button("Kup %d" % amount, _trade.bind("market.buy", item, amount))
				b.disabled = _balance < cents * amount
				bottom.add_child(b)
		else:
			var one := UI.button("Sprzedaj 1", _trade.bind("market.sell", item, 1))
			var all := UI.button("Wszystko", _trade.bind("market.sell", item, -1))
			one.disabled = owned < 1
			all.disabled = owned < 1
			bottom.add_child(one)
			bottom.add_child(all)
		_market.add_child(bottom)


## quantity -1 sells everything the player has.
func _trade(type: String, item: String, quantity: int) -> void:
	if quantity < 0:
		quantity = mini(_count(item), 1000)
	_hide_error()
	var reply := await Net.request(type, {"item": item, "quantity": quantity})
	if reply["type"] != "market.traded":
		_show_error(reply)
		return
	_set_balance(int(reply["payload"]["balanceCents"]))
	await _reload_inventory()
	if item == "trash":
		var garage := await Net.request("garage.get")
		if garage["type"] == "garage":
			_apply_garage(garage["payload"])


# --- Effects ---------------------------------------------------------------------------

func _float_text(text: String, color: Color, delay := 0.0, lift := 0) -> void:
	var l := UI.label(text, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UI.bold())
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.modulate.a = 0.0
	l.size = Vector2(280, 32)
	var start := _bin.position + Vector2(_bin.size.x / 2 - 140, -10 + lift)
	l.position = start
	_effects.add_child(l)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(l, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(l, "position:y", start.y - 60, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "modulate:a", 0.0, 0.4)
	tween.tween_callback(l.queue_free)


func _banner(text: String) -> void:
	var l := UI.title(text, 48)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.size = Vector2(1280 - PANEL_WIDTH - 32, 70)
	l.position = Vector2(0, 280)
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ZERO
	_effects.add_child(l)
	var tween := create_tween()
	tween.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.0)
	tween.tween_property(l, "modulate:a", 0.0, 0.5)
	tween.tween_callback(l.queue_free)


## Flashes the bin, as feedback that sorting started.
func _pulse() -> void:
	var tween := create_tween()
	tween.tween_property(_bin, "self_modulate", Color(1.8, 1.6, 1.2, 1), 0.08)
	tween.tween_property(_bin, "self_modulate", Color(1, 1, 1, 0), 0.35)


func _show_error(reply: Dictionary) -> void:
	_error.text = Game.error_text(reply)
	_error.visible = true


func _hide_error() -> void:
	_error.visible = false
