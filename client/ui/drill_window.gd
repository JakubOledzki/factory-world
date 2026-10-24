class_name DrillWindow
extends GameWindow
## A mining drill or heavy drill standing next to a mine: it works the mine by itself on power,
## load after load, and keeps the ore until it is taken out by hand or by an inserter. It shares the
## mine with the player: what it digs is gone from the mine, and it waits while the mine fills up.

## Ore came out: [{id, name, quantity}], and the XP gain or null.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 2000.0

var drill := ""
var plot := Vector2i(-1, -1)

var _state := {}
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0

var _level: Label
var _pace: Label
var _store: Label
var _ore_bar: ProgressBar
var _take: Button
var _ores := VBoxContainer.new()
var _mine: Label
var _status: Label
var _upgrade: Label


func _init() -> void:
	super("Wiertło górnicze", 420)
	_level = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_level)
	_pace = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_pace)
	content.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon("iron_ore", 30))
	_store = UI.label("")
	_store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_store)
	_take = UI.button("Wyjmij urobek", _take_ore, true)
	row.add_child(_take)
	content.add_child(row)
	_ore_bar = ProgressBar.new()
	_ore_bar.show_percentage = false
	_ore_bar.custom_minimum_size.y = 10
	content.add_child(_ore_bar)
	_ores.add_theme_constant_override("separation", 2)
	content.add_child(_ores)
	_status = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	_mine = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_mine)
	content.add_child(HSeparator.new())
	_upgrade = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_upgrade)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(drill))
	pick_up.tooltip_text = "Urobek ze środka wróci do ekwipunku"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	if id != drill:
		_state = {}
	plot = at
	drill = id
	show_window()
	refresh()


func refresh() -> void:
	if drill == "":
		return
	_refreshing = true
	_next_poll = Time.get_ticks_msec() + POLL
	var reply := await Net.request("drill.get", {"x": plot.x, "y": plot.y, "id": drill})
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "drill":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_render()


func _render() -> void:
	if _state.is_empty():
		return
	set_title(_state["name"])
	_level.text = "%s · poziom %d z 2 · kopalnia poziomu %d" % [_state["name"], int(_state["level"]), int(_state["mineLevel"])]
	var speed := float(_state["speed"])
	var seconds := float(_state["seconds"])
	_pace.text = "Jeden urobek na %s s (z pełnym prądem)." % _number(seconds)
	if speed <= 0.0:
		_pace.text += " Brak prądu: wiertło stoi. Postaw słup obok i generator albo koło wodne."
		_pace.add_theme_color_override("font_color", UI.ERROR)
	elif speed < 0.999:
		_pace.text += " Za mało prądu: pracuje na %d%%." % roundi(speed * 100.0)
		_pace.add_theme_color_override("font_color", UI.ERROR)
	else:
		_pace.add_theme_color_override("font_color", UI.TEXT)
	var stored := int(_state["stored"])
	var capacity := int(_state["capacity"])
	_store.text = "Urobek: %d / %d" % [stored, capacity]
	_ore_bar.max_value = capacity
	_ore_bar.value = stored
	_take.disabled = stored == 0
	for child in _ores.get_children():
		child.free()
	for ore: Dictionary in _state.get("ores", []):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UI.item_icon(ore["id"], 22))
		line.add_child(UI.label("%s × %d" % [ore["name"], int(ore["quantity"])]))
		_ores.add_child(line)
	if _state.get("full", false):
		_status.text = "Pełne: wiertło nie kopie, dopóki nie wyjmiesz urobku (ręcznie albo podajnikiem)."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif _state.get("waiting", false):
		_status.text = "Kopalnia wyczerpana: wiertło czeka, aż się odnowi%s." % _refill_in()
		_status.add_theme_color_override("font_color", UI.MUTED)
	elif speed > 0.0:
		_status.text = "Pracuje: wydobywa rudy, węgiel i to, co kryje góra."
		_status.add_theme_color_override("font_color", UI.GOLD)
	else:
		_status.text = ""
	_mine.text = "W kopalni zostało %d z %d urobków. Kopiesz w niej razem z wiertłem." % [int(_state["unitsLeft"]), int(_state["units"])]
	var next: Variant = _state.get("upgrade")
	if next == null:
		_upgrade.text = "To najlepsze wiertło. Głębsza kopalnia (poziomy 4 i 5) da więcej srebra i złota."
	else:
		_upgrade.text = "Lepsze: %s (urobek co %s s, mieści %d). Zrobisz je przy stole warsztatowym z tego wiertła." % [
			next["name"], _number(float(next["seconds"])), int(next["capacity"])]
	_fit.call_deferred()


func _refill_in() -> String:
	var at: Variant = _state.get("refillAt")
	if at == null:
		return ""
	var left := maxi(0, ceili((float(at) - (Time.get_unix_time_from_system() * 1000.0 + _clock_offset)) / 1000.0))
	return " (za %d:%02d)" % [left / 60, left % 60]


func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0").replace(".", ",")


func _process(_delta: float) -> void:
	if visible and not _refreshing and Time.get_ticks_msec() >= _next_poll:
		refresh()


func _take_ore() -> void:
	var reply := await Net.request("drill.take", {"x": plot.x, "y": plot.y, "id": drill})
	_apply(reply)
	if reply["type"] == "drill":
		inventory_changed.emit(_state.get("taken", []), _state.get("xp"))
