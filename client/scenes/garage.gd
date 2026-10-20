extends Control
## The player's garage: a pixel-art room with the trash bin, and a side panel
## with sorting, the storage and the trader.

## Room art is drawn at 2× in a 320×180 space; the side panel covers its right part.
const ROOM_SCALE := 2
const FLOOR_Y := 130
const PANEL_X := 404
const SLOTS := 10

const TABS := ["Segregacja", "Magazyn", "Rynek"]

var _garage := {}
var _items: Array = []
var _prices: Array = []
var _balance := 0
## Server time minus local time, in ms, so timers follow the server's clock.
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _room: Control
var _bin: TextureButton
var _player: TextureRect
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
	_build_room()
	_build_hud()
	_build_side_panel()
	_show_tab(0)
	_refresh_character()
	_load()


# --- Room ------------------------------------------------------------------------

func _build_room() -> void:
	var sky := ColorRect.new()
	sky.color = UI.BACKGROUND
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	_room = Control.new()
	_room.scale = Vector2.ONE * ROOM_SCALE
	_room.size = Vector2(320, 180)
	_room.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_room)

	# Dimmed a little: it's indoors, and the bright bin and items should stand out.
	_tile("bricks", Rect2(0, 0, 320, FLOOR_Y - 6), Color(0.78, 0.72, 0.76))
	_tile("baseboard", Rect2(0, FLOOR_Y - 6, 320, 6))
	_tile("floor", Rect2(0, FLOOR_Y, 320, 180 - FLOOR_Y), Color(0.62, 0.62, 0.7))
	# Soft dark band where the wall meets the floor.
	_shade(Rect2(0, FLOOR_Y, 320, 2), 0.35)

	_sprite("garage_door", Vector2(10, FLOOR_Y - 6 - 56))
	_sprite("window", Vector2(98, 30))
	_sprite("shelf", Vector2(150, 62))
	_shade(Rect2(132, FLOOR_Y + 3, 40, 2), 0.3)
	_sprite("workbench", Vector2(132, FLOOR_Y - 17))

	_shade(Rect2(91, FLOOR_Y + 3, 22, 2), 0.3)
	_bin = TextureButton.new()
	_bin.texture_normal = UI.texture("trash_bin")
	_bin.position = Vector2(90, FLOOR_Y - 25)
	_bin.tooltip_text = "Kosz na śmieci: kliknij, aby segregować"
	_bin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bin.pressed.connect(_sort.bind(1))
	_bin.mouse_entered.connect(func() -> void: _bin.modulate = Color(1.25, 1.25, 1.25))
	_bin.mouse_exited.connect(func() -> void: _bin.modulate = Color.WHITE)
	_room.add_child(_bin)

	_shade(Rect2(69, FLOOR_Y + 3, 14, 2), 0.3)
	_player = TextureRect.new()
	_player.position = Vector2(67, FLOOR_Y - 21)
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(_player)

	# Floating "+5 XP" texts live at screen scale, so the font stays crisp.
	_effects = Control.new()
	_effects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effects)


func _tile(art: String, rect: Rect2, tint := Color.WHITE) -> void:
	var t := TextureRect.new()
	t.modulate = tint
	t.texture = UI.texture(art)
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.position = rect.position
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(t)


func _sprite(art: String, at: Vector2) -> void:
	var t := TextureRect.new()
	t.texture = UI.texture(art)
	t.position = at
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(t)


func _shade(rect: Rect2, alpha: float) -> void:
	var c := ColorRect.new()
	c.color = Color(UI.BACKGROUND, alpha)
	c.position = rect.position
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room.add_child(c)


# --- HUD -------------------------------------------------------------------------

func _build_hud() -> void:
	var parts := UI.panel(1)
	var hud: PanelContainer = parts[0]
	hud.position = Vector2(4, 4)
	add_child(hud)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parts[1].add_child(row)

	var portrait := CharacterPreview.new()
	portrait.pixel = 2
	portrait.options = Game.appearance_options
	portrait.appearance = Game.character.get("appearance", {})
	row.add_child(portrait)
	_player.texture = ImageTexture.create_from_image(portrait.render())

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(info)
	var name_row := HBoxContainer.new()
	name_row.add_child(UI.label(Game.character.get("name", "")))
	_level = UI.label("", UI.GOLD)
	name_row.add_child(_level)
	info.add_child(name_row)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = "XpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(120, 7)
	info.add_child(_xp_bar)
	_xp_text = UI.label("", UI.MUTED)
	info.add_child(_xp_text)


func _refresh_character() -> void:
	var c := Game.character
	var xp: int = c.get("xp", 0)
	var level_xp: int = c.get("levelXp", 0)
	var next_xp: Variant = c.get("nextLevelXp")
	_level.text = " Poz. %d" % c.get("level", 1)
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
	var parts := UI.panel(5)
	var side: PanelContainer = parts[0]
	side.position = Vector2(PANEL_X, 4)
	side.size = Vector2(640 - PANEL_X - 4, 352)
	add_child(side)
	var box: VBoxContainer = parts[1]

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header.add_child(UI.icon("coin", 2))
	_money = UI.label("", UI.GOLD)
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_money)
	header.add_child(UI.button("Wyloguj", Game.logout))
	box.add_child(header)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
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
	page.add_theme_constant_override("separation", 5)

	var bin := HBoxContainer.new()
	bin.add_theme_constant_override("separation", 6)
	bin.add_child(UI.icon("item_trash", 2))
	var bin_text := VBoxContainer.new()
	bin_text.add_theme_constant_override("separation", 0)
	bin_text.add_child(UI.label("Kosz na śmieci"))
	_trash = UI.label("", UI.MUTED)
	bin_text.add_child(_trash)
	bin.add_child(bin_text)
	page.add_child(bin)

	page.add_child(UI.label("Segregacja worka trwa 10 s i daje losowy surowiec oraz 5 XP.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
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
	_job_bar.custom_minimum_size.y = 8
	_job_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job.add_child(_job_bar)
	_job_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_job_text.custom_minimum_size.x = 30
	job.add_child(_job_text)
	page.add_child(job)

	page.add_child(HSeparator.new())
	page.add_child(UI.label("Ostatnio wysegregowane:", UI.MUTED))
	_recent = HFlowContainer.new()
	_recent.add_theme_constant_override("h_separation", 2)
	_recent.add_theme_constant_override("v_separation", 2)
	page.add_child(_recent)
	return page


func _build_storage() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(UI.label("Magazyn garażu", UI.TEXT))
	_slots = GridContainer.new()
	_slots.columns = 5
	_slots.add_theme_constant_override("h_separation", 3)
	_slots.add_theme_constant_override("v_separation", 3)
	page.add_child(_slots)
	page.add_child(UI.label("Surowce sprzedasz handlarzowi w zakładce Rynek.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	return page


func _build_market() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	_market = VBoxContainer.new()
	_market.add_theme_constant_override("separation", 1)
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
		var icon := UI.icon("item_" + item["id"])
		icon.tooltip_text = item["name"]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		_recent.add_child(icon)
		_recent.move_child(icon, 0)
	while _recent.get_child_count() > 24:
		_recent.get_child(_recent.get_child_count() - 1).free()
	if garage.get("xp") != null:
		_float_text("+%d XP" % (results.size() * 5), UI.GOLD, 0.0, -16)
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
	_shake(_bin)
	var reply := await Net.request("recycling.sort", {"count": count})
	if reply["type"] == "garage":
		_apply_garage(reply["payload"])
	else:
		_show_error(reply)


# --- Storage and market -----------------------------------------------------------------

func _slot(stack: Dictionary) -> Control:
	var slot := PanelContainer.new()
	var frame := StyleBoxTexture.new()
	frame.texture = UI.texture("ui_slot")
	frame.set_texture_margin_all(3)
	slot.add_theme_stylebox_override("panel", frame)
	slot.custom_minimum_size = Vector2(40, 40)
	if stack.is_empty():
		return slot
	slot.tooltip_text = "%s: %d" % [stack["name"], int(stack["quantity"])]
	var icon := UI.icon("item_" + stack["id"], 2)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.add_child(icon)
	var count := UI.label(str(int(stack["quantity"])), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	count.size_flags_horizontal = Control.SIZE_SHRINK_END
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	count.add_theme_constant_override("outline_size", 3)
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
		top.add_theme_constant_override("separation", 4)
		top.add_child(UI.icon("item_" + item))
		var name_label := UI.label(price["name"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name_label)
		top.add_child(UI.label("masz %d" % owned, UI.MUTED))
		_market.add_child(top)

		var bottom := HBoxContainer.new()
		bottom.add_theme_constant_override("separation", 3)
		var buying: bool = price.get("sellCents") == null
		var cents := int(price["buyCents"] if buying else price["sellCents"])
		bottom.add_child(UI.label(("cena %s" if buying else "skup %s") % UI.money(cents), UI.GOLD if buying else UI.GOOD))
		bottom.add_child(UI.icon("coin"))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bottom.add_child(spacer)
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
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", UI.BACKGROUND)
	l.modulate.a = 0.0
	l.size = Vector2(120, 14)
	var start := (_bin.position + Vector2(12, -4)) * ROOM_SCALE - Vector2(60, -lift)
	l.position = start
	_effects.add_child(l)
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(l, "modulate:a", 1.0, 0.1)
	tween.parallel().tween_property(l, "position:y", start.y - 30, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "modulate:a", 0.0, 0.3)
	tween.tween_callback(l.queue_free)


func _banner(text: String) -> void:
	var l := UI.title(text)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", UI.BACKGROUND)
	l.size = Vector2(PANEL_X, 30)
	l.position = Vector2(0, 120)
	l.pivot_offset = l.size / 2
	l.scale = Vector2.ZERO
	_effects.add_child(l)
	var tween := create_tween()
	tween.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(2.0)
	tween.tween_property(l, "modulate:a", 0.0, 0.5)
	tween.tween_callback(l.queue_free)


func _shake(node: Control) -> void:
	var base := Vector2(90, FLOOR_Y - 25)
	var tween := create_tween()
	for dx in [-1, 1, -1, 0]:
		tween.tween_property(node, "position", base + Vector2(dx, 0), 0.04)


func _show_error(reply: Dictionary) -> void:
	_error.text = Game.error_text(reply)
	_error.visible = true


func _hide_error() -> void:
	_error.visible = false
