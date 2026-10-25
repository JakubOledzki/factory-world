class_name ItemTooltip
extends CanvasLayer
## With Ctrl held, the item under the mouse gets a small card next to it: its name, category,
## what it is for and where it comes from (ItemInfo), and what it costs on the market today: the
## cheapest way to buy it (a player's listing or the trader) and what the trader pays for it.
## Any control showing an item marks it with the meta "item" (UI.item_icon does); a row whose
## icon is marked counts too. On touch screens, where there is no Ctrl, holding a finger still
## on an item shows the card; lifting the finger then doesn't tap the item.

const WIDTH := 320
## Prices change during the day (the trader's every hour, players' with every offer), so they
## are asked for again when a card opens and the last answer is older than this (seconds).
const PRICES_LAST := 15.0
## Touch: how long a finger stays still on an item (seconds) before the card shows, how far it
## may move meanwhile (pixels), and how long the card stays after the finger is lifted.
const HOLD_FOR := 0.4
const HOLD_SLOP := 14.0
const CARD_STAYS := 6.0

var _panel := PanelContainer.new()
var _icon := TextureRect.new()
var _name: Label
var _category: Label
var _about: Label
var _source: Label
var _market_box := VBoxContainer.new()
var _buy: Label
var _sell: Label
var _item := ""

## From the server, by item id: the trader's prices ("market.prices") and players' best offers
## ("market.overview"); when they came, and whether a request is on its way.
var _trader := {}
var _players := {}
var _prices_at := -INF
var _asking := false
## The server answered with an error (e.g. nobody is logged in yet): no prices on the card.
var _no_prices := false

## Touch: the finger held still, where it went down and for how long; the item whose card it
## opened and for how long more the card stays once the finger is lifted.
var _finger := -1
var _finger_at := Vector2.ZERO
var _finger_for := 0.0
var _held_item := ""
var _card_left := 0.0
## The card opened under the finger, so the coming release must not tap what is under it.
var _swallow_release := false


func _init() -> void:
	layer = 100
	_panel.visible = false
	# A layer does not pass the screen's theme on to its controls.
	_panel.theme = UI.theme()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = WIDTH * (UI.TOUCH_SCALE if UI.touch() else 1.0)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(40, 40)
	head.add_child(_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", -4)
	_name = UI.label("", UI.GOLD)
	_name.add_theme_font_override("font", UI.bold())
	names.add_child(_name)
	_category = UI.label("", UI.MUTED)
	names.add_child(_category)
	head.add_child(names)
	box.add_child(head)
	_about = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_about)
	box.add_child(UI.label("Skąd:", UI.MUTED))
	_source = UI.label("", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true)
	box.add_child(_source)
	_market_box.add_theme_constant_override("separation", 4)
	_market_box.add_child(HSeparator.new())
	_market_box.add_child(UI.label("Na rynku dziś:", UI.MUTED))
	_buy = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	_market_box.add_child(_buy)
	_sell = UI.label("", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true)
	_market_box.add_child(_sell)
	box.add_child(_market_box)
	for node: Node in box.find_children("*", "Control", true, false):
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not UI.touch():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			# A new touch closes the card; a single finger may open the next one.
			_held_item = ""
			_card_left = 0.0
			_swallow_release = false
			_finger = event.index if _finger < 0 and event.index == 0 else -2
			_finger_at = event.position
			_finger_for = 0.0
		elif event.index == _finger or _finger == -2:
			_finger = -1
			if _held_item != "":
				_card_left = CARD_STAYS
	elif event is InputEventScreenDrag and event.index == _finger and event.position.distance_to(_finger_at) > HOLD_SLOP:
		# Moving the finger drags or scrolls, so it is no hold, and the card would only be in the way.
		_finger = -2
		_held_item = ""
		_swallow_release = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _swallow_release:
		# Godot turns the lifted finger into a mouse release, which would tap the item held. The
		# control under it still waits for a release, so it gets one far away, where it is no tap.
		_swallow_release = false
		get_viewport().set_input_as_handled()
		var away := Vector2(-10000, -10000)
		var motion := InputEventMouseMotion.new()
		motion.position = away
		motion.global_position = away
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		var release: InputEventMouseButton = event.duplicate()
		release.position = away
		release.global_position = away
		Input.parse_input_event(release)


func _process(delta: float) -> void:
	var item := _touch_item(delta) if UI.touch() else (_hovered_item() if Input.is_key_pressed(KEY_CTRL) else "")
	if item == "" or not ItemInfo.ITEMS.has(item):
		_panel.visible = false
		_item = ""
		return
	if item != _item:
		_item = item
		_icon.texture = UI.item_texture(item)
		_name.text = ItemInfo.name_of(item)
		_category.text = ItemInfo.CATEGORIES[ItemInfo.category_of(item)][0]
		_about.text = ItemInfo.description(item)
		_source.text = ItemInfo.source(item)
		_show_prices()
		if Time.get_ticks_msec() / 1000.0 - _prices_at > PRICES_LAST:
			_ask_prices()
	_panel.visible = true
	# Wrapped lines know their height only once laid out, so the card is fitted every frame.
	_panel.reset_size()
	var viewport := _panel.get_viewport()
	var screen := viewport.get_visible_rect().size
	var at: Vector2
	if UI.touch():
		# Above the finger, which would cover it, and beside it.
		at = _finger_at + Vector2(24, -_panel.size.y - 24)
		if at.x + _panel.size.x > screen.x:
			at.x = _finger_at.x - _panel.size.x - 24
		if at.y < 0:
			at.y = screen.y - _panel.size.y - 4
	else:
		# Beside the pointer, turned inwards near the right and bottom edges of the screen.
		at = viewport.get_mouse_position() + Vector2(18, 18)
		if at.x + _panel.size.x > screen.x:
			at.x -= _panel.size.x + 30
		if at.y + _panel.size.y > screen.y:
			at.y = screen.y - _panel.size.y - 4
	_panel.position = at.clamp(Vector2.ZERO, (screen - _panel.size).max(Vector2.ZERO))


## Touch: the item held under a still finger long enough, or whose card is still showing.
func _touch_item(delta: float) -> String:
	if _finger >= 0 and _held_item == "":
		_finger_for += delta
		if _finger_for >= HOLD_FOR:
			_held_item = _hovered_item()
			_swallow_release = _held_item != ""
			if _held_item == "":
				_finger = -2
	elif _finger < 0 and _held_item != "":
		_card_left -= delta
		if _card_left <= 0.0:
			_held_item = ""
	return _held_item


## The item of the control under the mouse, of one of its parents, or of an icon in its row.
func _hovered_item() -> String:
	var node: Node = _panel.get_viewport().gui_get_hovered_control()
	for i in 4:
		if node == null:
			return ""
		if node.has_meta("item"):
			return node.get_meta("item")
		if node is HBoxContainer:
			for child in node.get_children():
				if child.has_meta("item"):
					return child.get_meta("item")
		node = node.get_parent()
	return ""


## Asks for the trader's prices and players' offers now; the card shows them once both are in.
func _ask_prices() -> void:
	if _asking:
		return
	_asking = true
	var trader := await Net.request("market.prices")
	var players := await Net.request("market.overview")
	_asking = false
	_prices_at = Time.get_ticks_msec() / 1000.0
	_no_prices = trader["type"] != "market.prices" or players["type"] != "market.overview"
	if not _no_prices:
		_trader.clear()
		for price: Dictionary in trader["payload"]["items"]:
			_trader[price["id"]] = price
		_players.clear()
		for entry: Dictionary in players["payload"]["items"]:
			_players[entry["id"]] = entry
	_show_prices()


## The cheapest way to buy the card's item and what the trader pays for it, as of the last answer.
func _show_prices() -> void:
	_market_box.visible = not _no_prices
	if _trader.is_empty() and _players.is_empty():
		_buy.text = "Sprawdzam ceny…"
		_buy.add_theme_color_override("font_color", UI.MUTED)
		_sell.text = ""
		_sell.visible = false
		return
	var trader: Dictionary = _trader.get(_item, {})
	var players: Dictionary = _players.get(_item, {})
	var npc = trader.get("buyCents")
	var listed = players.get("lowestCents")
	if npc == null and listed == null:
		_buy.text = "Kupno: nikt tego nie sprzedaje"
		_buy.add_theme_color_override("font_color", UI.MUTED)
	elif listed != null and (npc == null or int(listed) < int(npc)):
		_buy.text = "Najtaniej kupisz: %s/szt. od gracza (%d szt.)" % [UI.money(int(listed)), int(players.get("listed", 0))]
		_buy.add_theme_color_override("font_color", UI.GOLD)
	else:
		_buy.text = "Najtaniej kupisz: %s/szt. u handlarza%s" % [UI.money(int(npc)), _change(trader.get("buyChange"))]
		_buy.add_theme_color_override("font_color", UI.GOLD)
	_sell.visible = true
	if trader.get("sellCents") != null:
		_sell.text = "Handlarz skupi za: %s/szt.%s" % [UI.money(int(trader["sellCents"])), _change(trader.get("sellChange"))]
		_sell.add_theme_color_override("font_color", UI.GOOD)
	else:
		_sell.text = "Handlarz tego nie skupuje"
		_sell.add_theme_color_override("font_color", UI.MUTED)


## How far the trader's price is from the usual one today, like "  (+12%)", or "" when usual.
func _change(percent) -> String:
	if percent == null or int(percent) == 0:
		return ""
	return "  (%s%d%% od zwykłej)" % ["+" if int(percent) > 0 else "-", absi(int(percent))]
