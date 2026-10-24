class_name StatsWindow
extends GameWindow
## Production statistics: how much of each item the player's factory makes and uses up per
## minute over the last 10 minutes, hour or day, as a chart, and where it stalls: machines
## standing still for want of something, and items used up faster than they are made.

signal failed(reply: Dictionary)

const PERIODS := {10: "10 min", 60: "1 godzina", 1440: "24 godziny"}
const MADE := Color("#8fd65a")
const USED := Color("#e8894a")
const REASONS := {
	"no_input": "czeka na składniki",
	"no_fuel": "brak paliwa",
	"output_full": "pełna, odbierz produkty",
	"no_recipe": "nie wybrano przepisu",
	"no_power": "brak prądu",
}

var _minutes := 10
var _state := {}
var _selected := ""
var _next_poll := 0.0
var _refreshing := false

var _period_buttons := {}
var _bottlenecks := VBoxContainer.new()
var _machines := VBoxContainer.new()
var _chart_title: Label
var _chart: BarChart
var _items := VBoxContainer.new()


func _init() -> void:
	super("Statystyki produkcji", 640)
	var periods := HBoxContainer.new()
	periods.add_theme_constant_override("separation", 6)
	for minutes: int in PERIODS:
		var b := UI.button(PERIODS[minutes], _set_period.bind(minutes))
		b.toggle_mode = true
		_period_buttons[minutes] = b
		periods.add_child(b)
	content.add_child(periods)

	content.add_child(_heading("Wąskie gardła"))
	_bottlenecks.add_theme_constant_override("separation", 4)
	content.add_child(_bottlenecks)
	content.add_child(_machines)
	content.add_child(HSeparator.new())

	_chart_title = _heading("")
	content.add_child(_chart_title)
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 14)
	legend.add_child(_legend("Produkcja", MADE))
	legend.add_child(_legend("Zużycie", USED))
	content.add_child(legend)
	_chart = BarChart.new()
	_chart.custom_minimum_size = Vector2(0, 150)
	content.add_child(_chart)
	content.add_child(HSeparator.new())

	var header := _item_row("", "Przedmiot", "Produkcja", "Zużycie", "Bilans", UI.MUTED)
	content.add_child(header)
	_items.add_theme_constant_override("separation", 2)
	content.add_child(_items)
	content.add_child(UI.label("Na minutę. Liczy się to, co zrobiły piece, maszyny i stół warsztatowy, oraz to, co zebrałeś, wykopałeś i posegregowałeś. Kliknij przedmiot, aby zobaczyć jego wykres.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_mark_period()


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	_refreshing = true
	_next_poll = Time.get_ticks_msec() + 5000.0
	var reply := await Net.request("stats.production", {"minutes": _minutes})
	_refreshing = false
	if reply["type"] != "stats.production":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


func _process(_delta: float) -> void:
	if visible and not _refreshing and Time.get_ticks_msec() >= _next_poll:
		refresh()


func _set_period(minutes: int) -> void:
	_minutes = minutes
	_mark_period()
	refresh()


func _mark_period() -> void:
	for minutes: int in _period_buttons:
		(_period_buttons[minutes] as Button).set_pressed_no_signal(minutes == _minutes)


func _render() -> void:
	if _state.is_empty():
		return
	_render_bottlenecks()

	UI.clear(_machines)
	for machine: Dictionary in _state["machines"]:
		var working := int(machine["working"])
		var total := int(machine["total"])
		_machines.add_child(UI.label("%s: pracuje %d z %d" % [machine["name"], working, total], UI.GOOD if working == total else UI.MUTED))

	var items: Array = _state["items"]
	if not items.any(func(i: Dictionary) -> bool: return i["id"] == _selected):
		_selected = items[0]["id"] if not items.is_empty() else ""
	UI.clear(_items)
	if items.is_empty():
		_items.add_child(UI.label("W tym czasie fabryka nic nie zrobiła ani nie zużyła.", UI.MUTED))
	for item: Dictionary in items:
		# Rounded as shown, so the balance adds up with the two numbers beside it.
		var made := snappedf(float(item["producedPerMinute"]), 0.1)
		var used := snappedf(float(item["consumedPerMinute"]), 0.1)
		var net := made - used
		var row := _item_row(item["id"], item["name"], _rate(made), _rate(used), ("+" if net > 0 else "") + _rate(net),
			UI.GOLD if item["id"] == _selected else UI.TEXT, UI.GOOD if net > 0 else UI.ERROR if net < 0 else UI.MUTED)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.tooltip_text = "Razem: zrobiono %d, zużyto %d" % [int(item["produced"]), int(item["consumed"])]
		row.gui_input.connect(_on_row_input.bind(item["id"]))
		_items.add_child(row)
	_render_chart()
	_fit.call_deferred()


func _render_bottlenecks() -> void:
	UI.clear(_bottlenecks)
	var any := false
	for stall: Dictionary in _state["stalls"]:
		any = true
		var what: String = stall["name"]
		if stall["productName"] != null:
			what += " (%s)" % stall["productName"]
		if int(stall["count"]) > 1:
			what = "%d × %s" % [int(stall["count"]), what]
		var reason: String = REASONS.get(stall["reason"], stall["reason"])
		var missing: Array = (stall["missing"] as Array).map(func(m: Dictionary) -> String: return m["name"])
		if not missing.is_empty():
			reason += ": " + (" lub " if stall["reason"] == "no_fuel" else ", ").join(missing).to_lower()
		_bottlenecks.add_child(_warning(stall["kind"], "%s stoi, %s" % [what, reason]))
	for shortage: Dictionary in _state["shortages"]:
		any = true
		_bottlenecks.add_child(_warning(shortage["id"], "%s: zużywasz %s/min, a robisz %s/min. Zapas się kończy." % [
			shortage["name"], _rate(float(shortage["consumedPerMinute"])), _rate(float(shortage["producedPerMinute"]))]))
	if not any:
		_bottlenecks.add_child(UI.label("Nie widać wąskich gardeł: maszyny pracują, a niczego nie zużywasz szybciej, niż robisz.", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))


func _render_chart() -> void:
	var item := {}
	for i: Dictionary in _state["items"]:
		if i["id"] == _selected:
			item = i
	var bars := int(_state["minutes"]) / int(_state["barMinutes"])
	var empty := []
	empty.resize(bars)
	empty.fill(0)
	_chart_title.text = "Wykres: %s" % item["name"] if not item.is_empty() else "Wykres"
	_chart.set_data(item.get("producedBars", empty), item.get("consumedBars", empty), int(_state["barMinutes"]), PERIODS[int(_state["minutes"])])


func _on_row_input(event: InputEvent, item: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_selected = item
		_render()


func _item_row(item: String, name: String, made: String, used: String, net: String, color: Color, net_color := UI.MUTED) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if item != "":
		row.add_child(UI.item_icon(item, 24))
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(24, 0)
		row.add_child(gap)
	var name_label := UI.label(name, color)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_label)
	for part: Array in [[made, MADE if item != "" else color], [used, USED if item != "" else color], [net, net_color if item != "" else color]]:
		var l := UI.label(part[0], part[1], HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size.x = 96
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	return row


func _warning(item: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UI.item_icon(item, 24))
	var l := UI.label(text, UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _legend(text: String, color: Color) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(swatch)
	box.add_child(UI.label(text, UI.MUTED))
	return box


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l


## A rate per minute the Polish way: "2,5", whole numbers without the comma.
static func _rate(value: float) -> String:
	var rounded := snappedf(value, 0.1)
	if is_equal_approx(rounded, roundf(rounded)):
		return str(int(roundf(rounded)))
	return ("%.1f" % rounded).replace(".", ",")


## Bars of what was made and used up, side by side, one pair per stretch of time, oldest on the left.
class BarChart:
	extends Control

	var _made: Array = []
	var _used: Array = []
	var _bar_minutes := 1
	var _period := ""

	func set_data(made: Array, used: Array, bar_minutes: int, period: String) -> void:
		_made = made
		_used = used
		_bar_minutes = bar_minutes
		_period = period
		queue_redraw()

	func _draw() -> void:
		var font := get_theme_default_font()
		var font_size := get_theme_default_font_size()
		var axis := Color(UI.MUTED, 0.5)
		var top := 4.0
		var bottom := size.y - font_size - 6
		var left := 44.0
		var width := size.x - left
		var peak := 1.0
		for v: Variant in _made + _used:
			peak = maxf(peak, float(v))
		# Per minute, as in the table, even where one bar covers several minutes.
		var per_minute := peak / _bar_minutes
		draw_line(Vector2(left, bottom), Vector2(size.x, bottom), axis)
		draw_line(Vector2(left, top), Vector2(size.x, top), Color(axis, 0.25))
		draw_string(font, Vector2(0, top + font_size * 0.8), StatsWindow._rate(per_minute) + "/min", HORIZONTAL_ALIGNMENT_LEFT, left - 4, font_size - 3, UI.MUTED)
		draw_string(font, Vector2(0, bottom), "0", HORIZONTAL_ALIGNMENT_LEFT, left - 4, font_size - 3, UI.MUTED)
		var n := maxi(1, _made.size())
		var slot := width / n
		var bar := maxf(1.0, slot * 0.38)
		for i in _made.size():
			var x := left + slot * i + slot * 0.1
			var made := float(_made[i]) / peak * (bottom - top)
			var used := float(_used[i]) / peak * (bottom - top) if i < _used.size() else 0.0
			if made > 0:
				draw_rect(Rect2(x, bottom - made, bar, made), StatsWindow.MADE)
			if used > 0:
				draw_rect(Rect2(x + bar, bottom - used, bar, used), StatsWindow.USED)
		draw_string(font, Vector2(left, size.y - 2), _period + " temu", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, UI.MUTED)
		draw_string(font, Vector2(left, size.y - 2), "teraz", HORIZONTAL_ALIGNMENT_RIGHT, width, font_size - 3, UI.MUTED)
