class_name AchievementsWindow
extends GameWindow
## Badges for milestones (chopped wood, ingots, plots, money...) with the progress towards each,
## and the rankings of the best players: the richest, the most experienced, the biggest producers.

signal failed(reply: Dictionary)

const TABS := ["Osiągnięcia", "Rankingi"]

var _tab := 0
var _tab_buttons: Array[Button] = []
var _summary := UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
var _page := VBoxContainer.new()
## The ranking shown on the "Rankingi" tab, or "" for the server's first.
var _ranking := ""
## A request is on its way; `_again` asks for one more once it is answered.
var _loading := false
var _again := false


func _init() -> void:
	super("Osiągnięcia i rankingi", 0)
	fill_margin = Vector2(140, 36) if not UI.touch() else Vector2(24, 16)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _open_tab.bind(i))
		b.custom_minimum_size.x = 150
		top.add_child(b)
		_tab_buttons.append(b)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	content.add_child(top)

	var list := ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 4)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Room on the right, so the scroll bar does not cover the progress.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_page)
	list.add_child(margin)
	content.add_child(list)


func show_window() -> void:
	super()
	refresh()


## Asks the server again for the open tab.
func refresh() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == _tab else ""
	if _loading:
		_again = true
		return
	_loading = true
	var reply: Dictionary
	if _tab == 0:
		reply = await Net.request("achievements.get")
	else:
		reply = await Net.request("rankings.get", {"ranking": _ranking} if _ranking != "" else null)
	_loading = false
	if _again:
		_again = false
		refresh()
		return
	if reply["type"] == "achievements":
		_show_badges(reply["payload"])
	elif reply["type"] == "rankings":
		_show_ranking(reply["payload"])
	else:
		failed.emit(reply)


func _open_tab(tab: int) -> void:
	_tab = tab
	refresh()


func _show_badges(state: Dictionary) -> void:
	UI.clear(_page)
	_summary.text = "Zdobyte odznaki: %d z %d" % [state["unlocked"], state["total"]]
	for group: Dictionary in state["groups"]:
		var badges: Array = group["badges"]
		var got := badges.filter(func(b: Dictionary) -> bool: return b["unlockedAt"] != null).size()
		var head := UI.label("%s  (%d/%d)" % [group["name"], got, badges.size()], UI.GOLD)
		head.add_theme_font_override("font", UI.bold())
		_page.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 1 if UI.touch() else 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for badge: Dictionary in badges:
			grid.add_child(_badge_row(badge))
		_page.add_child(grid)
		_page.add_child(HSeparator.new())


func _badge_row(badge: Dictionary) -> Control:
	var unlocked: bool = badge["unlockedAt"] != null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var medal := Medal.new()
	medal.unlocked = unlocked
	row.add_child(medal)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UI.label(badge["name"], UI.TEXT if unlocked else UI.MUTED)
	name_label.add_theme_font_override("font", UI.bold())
	text.add_child(name_label)
	var description := UI.label(badge["description"], UI.MUTED)
	description.add_theme_font_size_override("font_size", 13)
	text.add_child(description)
	if unlocked:
		var when := Time.get_datetime_dict_from_unix_time(int(badge["unlockedAt"]) / 1000)
		var date := UI.label("Zdobyta %02d.%02d.%d" % [when["day"], when["month"], when["year"]], UI.GOOD)
		date.add_theme_font_size_override("font_size", 13)
		text.add_child(date)
	else:
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 8)
		bar.max_value = float(badge["goal"])
		bar.value = float(badge["progress"])
		text.add_child(bar)
		var progress := UI.label(badge["text"], UI.MUTED)
		progress.add_theme_font_size_override("font_size", 12)
		text.add_child(progress)
	row.add_child(text)
	return row


func _show_ranking(state: Dictionary) -> void:
	UI.clear(_page)
	_ranking = state["ranking"]
	_summary.text = "Najlepsi gracze"
	var choice := HFlowContainer.new()
	choice.add_theme_constant_override("h_separation", 4)
	choice.add_theme_constant_override("v_separation", 4)
	for ranking: Dictionary in state["rankings"]:
		var id: String = ranking["id"]
		choice.add_child(UI.button(ranking["name"], func() -> void:
			_ranking = id
			refresh(), id == _ranking))
	_page.add_child(choice)
	_page.add_child(HSeparator.new())

	var top: Array = state["top"]
	if top.is_empty():
		_page.add_child(UI.label("Nikt jeszcze nie trafił do tego rankingu.", UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for entry: Dictionary in top:
		var color := UI.GOLD if entry["mine"] else UI.TEXT
		var place := UI.label("%d." % entry["place"], _place_color(int(entry["place"]), color), HORIZONTAL_ALIGNMENT_RIGHT)
		place.custom_minimum_size.x = 40
		place.add_theme_font_override("font", UI.bold())
		grid.add_child(place)
		var player := UI.label(entry["name"] + ("  (ty)" if entry["mine"] else ""), color)
		player.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry["mine"]:
			player.add_theme_font_override("font", UI.bold())
		grid.add_child(player)
		grid.add_child(UI.label(entry["text"], color, HORIZONTAL_ALIGNMENT_RIGHT))
	_page.add_child(grid)

	_page.add_child(HSeparator.new())
	var me: Variant = state["me"]
	if me is Dictionary:
		var mine := UI.label("Twoje miejsce: %d.  %s" % [me["place"], me["text"]], UI.GOLD)
		mine.add_theme_font_override("font", UI.bold())
		_page.add_child(mine)
	else:
		_page.add_child(UI.label("Nie ma cię jeszcze w tym rankingu.", UI.MUTED))


## Gold, silver and bronze for the podium.
static func _place_color(place: int, otherwise: Color) -> Color:
	match place:
		1:
			return UI.GOLD
		2:
			return Color("#c9ced6")
		3:
			return Color("#cd8a4f")
	return otherwise


## A round medal on a ribbon: gold when the badge is unlocked, dark when not yet.
class Medal:
	extends Control

	var unlocked := false

	func _init() -> void:
		custom_minimum_size = Vector2(34, 40)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var ribbon := Color("#b8432f") if unlocked else Color("#3a3a3e")
		draw_colored_polygon(PackedVector2Array([Vector2(9, 0), Vector2(16, 0), Vector2(20, 16), Vector2(13, 16)]), ribbon)
		draw_colored_polygon(PackedVector2Array([Vector2(18, 0), Vector2(25, 0), Vector2(21, 16), Vector2(14, 16)]), ribbon.darkened(0.25))
		var centre := Vector2(17, 25)
		var rim := UI.GOLD.darkened(0.35) if unlocked else Color("#2a2a2d")
		var face := UI.GOLD if unlocked else Color("#4a4a4f")
		draw_circle(centre, 13, rim)
		draw_circle(centre, 10, face)
		# A five-pointed star stamped in the middle.
		var star := PackedVector2Array()
		for i in 10:
			var r := 7.0 if i % 2 == 0 else 3.0
			var a := -PI / 2 + i * PI / 5
			star.append(centre + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(star, rim if unlocked else Color("#3a3a3e"))
