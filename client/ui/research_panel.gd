class_name ResearchPanel
extends HBoxContainer
## The technology tree, a tab of the workbench window. Each technology is a card in the column of
## its depth, with lines from the ones it needs; the chosen one shows its cost, time and what it
## unlocks on the right. Research uses up its cost at once and takes time, one technology at a
## time, and goes on while the player is away. The panel keeps an eye on it while hidden too,
## so the screen hears when it is done.

## Research finished: [{id, name}] and the XP gain (or null).
signal researched(finished: Array, xp: Variant)
## The cost was taken or given back; the screen reloads the inventory.
signal inventory_changed
signal failed(reply: Dictionary)

const CARD := Vector2(224, 64)
const GAP := Vector2(50, 14)
const STATUS_COLORS := {"done": UI.GOOD, "active": UI.GOLD, "available": UI.TEXT, "locked": UI.MUTED}

var _state := {}
var _items: Array = []
var _selected := ""
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0
var _busy := false
## The second the countdown last showed, so the cards are written anew once a second.
var _last_second := -1
## Card button by technology id, and the status line of the chosen one.
var _cards := {}
var _status: Label

var _tree := _TreeCanvas.new()
var _details := VBoxContainer.new()
var _start_button: Button
var _cancel_button: Button
var _bar: ProgressBar
var _bar_text: Label


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tree)
	add_child(scroll)
	add_child(VSeparator.new())

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size.x = 470 if UI.touch() else 360
	add_child(side_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(side)
	side_scroll.add_child(margin)
	_details.add_theme_constant_override("separation", 4)
	side.add_child(_details)
	var progress := HBoxContainer.new()
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress.add_child(_bar)
	_bar_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar_text.custom_minimum_size.x = 70
	progress.add_child(_bar_text)
	side.add_child(progress)
	_start_button = UI.button("Zbadaj", _start, true)
	side.add_child(_start_button)
	_cancel_button = UI.button("Przerwij badanie", _cancel)
	_cancel_button.tooltip_text = "Wszystko, co zużyło badanie, wróci do ekwipunku"
	side.add_child(_cancel_button)
	side.add_child(HSeparator.new())
	side.add_child(UI.label("Naraz bada się jedną technologię. Badanie trwa dalej, gdy odejdziesz od stołu.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	side.add_child(UI.label("Czego jeszcze nie zbadasz, tego nie ma dla ciebie na rynku: ani u handlarza, ani u innych graczy.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


## Whether the tree came from the server yet.
func loaded() -> bool:
	return not _state.is_empty()


func set_items(items: Array) -> void:
	_items = items
	if is_visible_in_tree():
		_render()


## Asks the server for the tree; it hands out XP for finished research.
func refresh() -> void:
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("research.get")
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "research":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	if _selected == "":
		var first := _technologies().filter(func(t: Dictionary) -> bool: return t["status"] == "active")
		first.append_array(_technologies().filter(func(t: Dictionary) -> bool: return t["status"] == "available"))
		_selected = first[0]["id"] if not first.is_empty() else _technologies()[0]["id"]
	var finished: Array = _state.get("finished", [])
	if not finished.is_empty():
		researched.emit(finished, _state.get("xp"))
	_render()


func _technologies() -> Array:
	return _state.get("technologies", [])


func _technology(id: String) -> Dictionary:
	for technology: Dictionary in _technologies():
		if technology["id"] == id:
			return technology
	return {}


func _active() -> Dictionary:
	for technology: Dictionary in _technologies():
		if technology["status"] == "active":
			return technology
	return {}


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _can_pay(technology: Dictionary) -> bool:
	for cost: Dictionary in technology["cost"]:
		if _count(cost["id"]) < int(cost["quantity"]):
			return false
	return true


## What the card says under the name; `full` names every missing requirement (cards have room for one).
func _status_text(technology: Dictionary, full := false) -> String:
	match technology["status"]:
		"done": return "Zbadane"
		"active": return "Badanie: %s" % _left(technology)
		"available": return "Gotowe do zbadania" if _can_pay(technology) else "Brakuje materiałów"
	var missing: Array = technology["requires"].filter(func(id: String) -> bool: return _technology(id).get("status") != "done")
	if missing.size() > 1 and not full:
		return "Wymaga %d badań" % missing.size()
	return "Wymaga: %s" % ", ".join(missing.map(func(id: String) -> String: return _technology(id).get("name", id)))


func _left(technology: Dictionary) -> String:
	var left := maxf(float(technology["finishesAt"]) - _server_now(), 0.0) / 1000.0
	return _seconds(ceilf(left))


func _render() -> void:
	if _state.is_empty():
		return
	_render_tree()
	_render_details()


func _render_tree() -> void:
	UI.clear(_tree)
	_cards.clear()
	var rows := {}
	var places := {}
	var rows_of := {}
	for technology: Dictionary in _technologies():
		var tier := int(technology["tier"])
		var row: int = rows.get(tier, 0)
		rows[tier] = row + 1
		var at := Vector2(tier * (CARD.x + GAP.x), row * (CARD.y + GAP.y)) + Vector2(4, 4)
		places[technology["id"]] = at
		rows_of[technology["id"]] = row
		_cards[technology["id"]] = _card(technology, at)
		_tree.add_child(_cards[technology["id"]])
	var tallest := 0
	for tier: int in rows:
		tallest = maxi(tallest, rows[tier])
	_tree.custom_minimum_size = Vector2(rows.size() * (CARD.x + GAP.x) - GAP.x, tallest * (CARD.y + GAP.y) - GAP.y) + Vector2(8, 8)

	# A line from each requirement's right edge to the left edge of what it leads to. One that
	# skips a column runs through it in the gap above the target's row, not behind its cards.
	# In the gap between two columns each card's lines go down their own lane, so lines from
	# different cards never share a stretch and it is clear which card leads where.
	var lines := []
	for technology: Dictionary in _technologies():
		for id: String in technology["requires"]:
			var from: Vector2 = places[id] + Vector2(CARD.x, CARD.y / 2)
			var to: Vector2 = places[technology["id"]] + Vector2(0, CARD.y / 2)
			var color := UI.GOOD if _technology(id)["status"] == "done" else UI.MUTED.darkened(0.3)
			var points := PackedVector2Array([from])
			var lane := from.x + 10 + 8 * int(rows_of[id])
			if to.x - from.x > GAP.x + 1:
				var gap_y: float = places[technology["id"]].y - GAP.y / 2
				points.append_array([Vector2(lane, from.y), Vector2(lane, gap_y), Vector2(to.x - 12, gap_y)])
				lane = to.x - 12
			var mid := lane
			points.append_array([Vector2(mid, points[points.size() - 1].y), Vector2(mid, to.y), to])
			lines.append([points, color])
	_tree.lines = lines
	_tree.queue_redraw()


func _card(technology: Dictionary, at: Vector2) -> Button:
	var b := Button.new()
	b.position = at
	b.size = CARD
	b.custom_minimum_size = CARD
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = UI.item_texture(technology["unlocks"][0]["id"])
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 36)
	b.text = "%s\n%s" % [technology["name"], _status_text(technology)]
	b.add_theme_color_override("font_color", STATUS_COLORS[technology["status"]])
	b.add_theme_color_override("font_hover_color", STATUS_COLORS[technology["status"]].lightened(0.2))
	if technology["id"] == _selected:
		b.theme_type_variation = "AccentButton"
	if technology["status"] == "locked":
		b.modulate = Color(1, 1, 1, 0.6)
	b.set_meta("technology", technology["id"])
	b.pressed.connect(func() -> void:
		_selected = technology["id"]
		_render())
	return b


func _render_details() -> void:
	UI.clear(_details)
	var technology := _technology(_selected)
	var active := _active()
	_bar.get_parent().visible = not active.is_empty() and active["id"] == _selected
	_update_bar()
	if technology.is_empty():
		_start_button.visible = false
		_cancel_button.visible = false
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UI.item_icon(technology["unlocks"][0]["id"], 40))
	var title := UI.label(technology["name"], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_details.add_child(head)
	_details.add_child(UI.label(technology["description"], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_status = UI.label(_status_text(technology, true), STATUS_COLORS[technology["status"]], HORIZONTAL_ALIGNMENT_LEFT, true)
	_details.add_child(_status)

	_details.add_child(UI.label("Odblokowuje:", UI.MUTED))
	for unlock: Dictionary in technology["unlocks"]:
		_details.add_child(_item_row(unlock["id"], unlock["name"], ""))
	if technology["status"] != "done":
		_details.add_child(UI.label("Zużywa (wymagane/masz):", UI.MUTED))
		for cost: Dictionary in technology["cost"]:
			var need := int(cost["quantity"])
			var have := _count(cost["id"])
			var text := "%d/%d" % [need, have]
			_details.add_child(_item_row(cost["id"], cost["name"], text, UI.GOOD if have >= need or technology["status"] == "active" else UI.ERROR))
	_details.add_child(UI.label("Czas: %s  ·  %d XP" % [_seconds(float(technology["seconds"])), int(technology["xp"])], UI.MUTED))

	var busy := not active.is_empty()
	_start_button.visible = technology["status"] in ["available", "locked"]
	_start_button.disabled = technology["status"] != "available" or busy or not _can_pay(technology) or _busy
	if technology["status"] == "locked":
		_start_button.text = "Najpierw zbadaj wymagane"
	elif busy:
		_start_button.text = "Trwa inne badanie: %s" % active["name"]
	elif not _can_pay(technology):
		_start_button.text = "Brakuje materiałów"
	else:
		_start_button.text = "Zbadaj"
	_cancel_button.visible = technology["status"] == "active"
	_cancel_button.disabled = _busy


func _item_row(item: String, name: String, amount: String, color := UI.TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var name_label := UI.label(name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if amount != "":
		row.add_child(UI.label(amount, color, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _seconds(seconds: float) -> String:
	var s := roundi(seconds)
	return "%d s" % s if s < 60 else "%d min %02d s" % [s / 60, s % 60]


func _update_bar() -> void:
	var active := _active()
	if active.is_empty():
		return
	var total := float(active["finishesAt"]) - float(active["startsAt"])
	var left := maxf(float(active["finishesAt"]) - _server_now(), 0.0)
	_bar.max_value = total
	_bar.value = total - left
	_bar_text.text = _left(active)


func _process(_delta: float) -> void:
	var active := _active()
	if active.is_empty():
		return
	if is_visible_in_tree():
		_update_bar()
		# The card and the status count down once a second, written in place (not drawn anew,
		# which would swallow a click on a card being pressed).
		var second := int(_server_now() / 1000.0)
		if second != _last_second:
			_last_second = second
			if _cards.has(active["id"]):
				_cards[active["id"]].text = "%s\n%s" % [active["name"], _status_text(active)]
			if _status != null and is_instance_valid(_status) and _selected == active["id"]:
				_status.text = _status_text(active)
	var now := _server_now()
	if now >= float(active["finishesAt"]) and now >= _next_poll and not _refreshing:
		refresh()


func _start() -> void:
	if _selected == "":
		return
	_busy = true
	_render()
	var reply := await Net.request("research.start", {"technology": _selected})
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


func _cancel() -> void:
	_busy = true
	var reply := await Net.request("research.cancel")
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


## Holds the cards where the panel puts them and draws the lines between them underneath.
class _TreeCanvas:
	extends Control

	## [[points, color]] in the canvas' coordinates.
	var lines := []

	func _draw() -> void:
		for line: Array in lines:
			draw_polyline(line[0], line[1], 2.0, true)
