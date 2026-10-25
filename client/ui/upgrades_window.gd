class_name UpgradesWindow
extends GameWindow
## The garage's upgrades: five tracks (floor, walls, lighting, shelves, heating), each bought
## level by level for money and materials. A level needs the one before it, sometimes a level of
## another track too, and gives the track's bonus.

## A level was bought: the garage's new levels (track → level) and the balance afterwards.
signal upgraded(levels: Dictionary, balance_cents: int)
signal failed(reply: Dictionary)

var _state := {}
var _items: Array = []
var _balance := 0
var _track := "floor"

var _rank: Label
var _tabs := HBoxContainer.new()
var _page := VBoxContainer.new()
var _busy := false


func _init() -> void:
	super("Ulepszenia garażu", 560)
	_rank = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_rank)
	_tabs.add_theme_constant_override("separation", 4)
	content.add_child(_tabs)
	content.add_child(HSeparator.new())
	_page.add_theme_constant_override("separation", 6)
	content.add_child(_page)


func set_player(items: Array, balance_cents: int) -> void:
	_items = items
	_balance = balance_cents
	if visible:
		_render()


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	var reply := await Net.request("garage.upgrades")
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "garage.upgrades":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_balance = int(_state["balanceCents"])
	_render()


func _tracks() -> Array:
	return _state.get("tracks", [])


func _find(track_id: String) -> Dictionary:
	for track: Dictionary in _tracks():
		if track["id"] == track_id:
			return track
	return {}


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _render() -> void:
	if _state.is_empty():
		return
	var total := 0
	var most := 0
	for track: Dictionary in _tracks():
		total += int(track["level"])
		most += int(track["maxLevel"])
	_rank.text = "Twój lokal: %s. Ulepszenia: %d z %d. Każdy poziom daje premię na zawsze." % [_state["rank"], total, most]

	UI.clear(_tabs)
	for track: Dictionary in _tracks():
		var b := UI.button("%s  %d/%d" % [track["name"], int(track["level"]), int(track["maxLevel"])], func() -> void:
			_track = track["id"]
			_render(), track["id"] == _track)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(b)

	UI.clear(_page)
	var track := _find(_track)
	var level := int(track["level"])
	var steps: Array = track["steps"]
	var now := UI.label("Teraz: %s" % (track["start"] if level == 0 else steps[level - 1]["name"]))
	now.add_theme_font_override("font", UI.bold())
	_page.add_child(now)
	var bonus := UI.label("%s %d%s (każdy poziom: +%d%s)" % [track["bonusName"], int(track["bonus"]), track["unit"], int(track["perLevel"]), track["unit"]], UI.GOOD)
	_page.add_child(bonus)

	if level < steps.size():
		_page.add_child(_next_card(track, steps[level]))
	else:
		_page.add_child(UI.label("Ulepszone do końca.", UI.GOLD))

	_page.add_child(_heading("Wszystkie poziomy"))
	var list := GridContainer.new()
	list.columns = 3
	list.add_theme_constant_override("h_separation", 12)
	list.add_theme_constant_override("v_separation", 2)
	for i in steps.size():
		var step: Dictionary = steps[i]
		var done := i < level
		var color := UI.GOOD if done else (UI.GOLD if i == level else UI.MUTED)
		list.add_child(UI.label("%s %d." % ["✓" if done else ("▶" if i == level else " "), i + 1], color))
		var name_label := UI.label(step["name"], color)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_child(name_label)
		list.add_child(UI.label("+%d%s" % [(i + 1) * int(track["perLevel"]), track["unit"]], color, HORIZONTAL_ALIGNMENT_RIGHT))
	_page.add_child(list)
	_fit.call_deferred()


## What the next level costs and needs, with the button that buys it.
func _next_card(track: Dictionary, step: Dictionary) -> Control:
	var parts := UI.panel(4)
	var card: PanelContainer = parts[0]
	var box: VBoxContainer = parts[1]
	var head := HBoxContainer.new()
	var title := UI.label("Poziom %d: %s" % [int(step["level"]), step["name"]], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.label("+%d%s" % [int(track["perLevel"]), track["unit"]], UI.GOOD))
	box.add_child(head)

	var ready := true
	var price := int(step["priceCents"])
	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 6)
	money.add_child(UI.icon("coin", 22))
	var enough_money := _balance >= price
	ready = ready and enough_money
	money.add_child(UI.label(UI.money(price), UI.TEXT if enough_money else UI.ERROR))
	box.add_child(money)

	var materials := HFlowContainer.new()
	materials.add_theme_constant_override("h_separation", 12)
	for material: Dictionary in step["materials"]:
		var have := _count(material["id"])
		var need := int(material["quantity"])
		ready = ready and have >= need
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var icon := UI.item_icon(material["id"], 26)
		icon.tooltip_text = material["name"]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(icon)
		row.add_child(UI.label("%s %d/%d" % [material["name"], mini(have, need), need], UI.TEXT if have >= need else UI.ERROR))
		materials.add_child(row)
	box.add_child(materials)

	for need: Dictionary in step["requires"]:
		var other := _find(need["track"])
		var met := int(other.get("level", 0)) >= int(need["level"])
		ready = ready and met
		box.add_child(UI.label("%s Wymaga: %s na poziomie %d" % ["✓" if met else "✗", need["name"], int(need["level"])], UI.GOOD if met else UI.ERROR))

	var buy := UI.button("Ulepsz", _buy.bind(track["id"]), true)
	buy.disabled = not ready or _busy
	if not ready:
		buy.tooltip_text = "Brakuje pieniędzy, materiałów albo innego ulepszenia."
	box.add_child(buy)
	return card


func _buy(track_id: String) -> void:
	_busy = true
	var reply := await Net.request("garage.upgrade", {"track": track_id})
	_busy = false
	if reply["type"] != "garage.upgrades":
		failed.emit(reply)
		_render()
		return
	_apply(reply)
	var levels := {}
	for track: Dictionary in _tracks():
		levels[track["id"]] = int(track["level"])
	upgraded.emit(levels, _balance)


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
