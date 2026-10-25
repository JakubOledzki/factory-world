class_name FarmsteadWindow
extends GameWindow
## A farmer's building on a plot (farmstead, manor farm): its fields, the crop it sows (picked here),
## the manure it keeps for sowing, the crops it keeps and a button to take them out. It sows and reaps
## by itself while the player is away too; an inserter next to it takes the crops out and puts manure in.

## After every answer from the server, with the plot's farmsteads as they are now.
signal updated(farmsteads: Dictionary)
## Crops came out or manure went in: [{id, name, quantity}] taken, and the XP gain or null.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
## The player asked to put the building back into the inventory.
signal pick_up_requested(id: String)

## How much manure one press of the button puts in.
const MANURE_STEP := 10

var farmstead := ""
var plot := Vector2i(-1, -1)

var _state := {}

var _level: Label
var _fields: Label
## One button per crop, by the server's id; the one it sows is lit.
var _kinds := {}
var _kinds_row: HFlowContainer
var _kind_info: Label
var _manure: Label
var _add_manure: Button
var _store: Label
var _crop_bar: ProgressBar
var _take: Button
var _status: Label
var _upgrade: Label
var _help: Label


func _init() -> void:
	super("Zagroda rolnika", 420)
	poll_every = 3000.0
	_level = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_level)
	_fields = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_fields)
	content.add_child(HSeparator.new())
	content.add_child(UI.label("Co sieje:", UI.GOLD))
	_kinds_row = HFlowContainer.new()
	_kinds_row.add_theme_constant_override("h_separation", 4)
	_kinds_row.add_theme_constant_override("v_separation", 4)
	content.add_child(_kinds_row)
	_kind_info = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_kind_info)
	var manure_row := HBoxContainer.new()
	manure_row.add_theme_constant_override("separation", 6)
	manure_row.add_child(UI.item_icon("manure", 30))
	_manure = UI.label("")
	_manure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manure_row.add_child(_manure)
	_add_manure = UI.button("Dosyp %d" % MANURE_STEP, _put_manure)
	_add_manure.tooltip_text = "Obornik z ekwipunku: idzie pod siew, po jednym na pole, i uprawa rośnie o 25% szybciej"
	manure_row.add_child(_add_manure)
	content.add_child(manure_row)
	content.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_store = UI.label("")
	_store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_store)
	_take = UI.button("Wyjmij plony", _take_crops, true)
	row.add_child(_take)
	content.add_child(row)
	_crop_bar = ProgressBar.new()
	_crop_bar.show_percentage = false
	_crop_bar.custom_minimum_size.y = 10
	content.add_child(_crop_bar)
	_status = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	content.add_child(HSeparator.new())
	_upgrade = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_upgrade)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(farmstead))
	pick_up.tooltip_text = "Plony i obornik ze środka wrócą do ekwipunku, a pola, które obsiała, znikną z działki"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	plot = at
	farmstead = id
	show_window()
	refresh()


## Shows the farmstead from a "farmsteads" answer the plot asked for itself.
func show_state(farmsteads: Dictionary) -> void:
	for f: Dictionary in farmsteads.get("farmsteads", []):
		if f["id"] == farmstead:
			_state = f
			_render()
			return


func refresh() -> void:
	if farmstead == "":
		return
	var reply := await fetch("farmstead.get", {"x": plot.x, "y": plot.y})
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "farmsteads":
		failed.emit(reply)
		return
	updated.emit(reply["payload"])
	show_state(reply["payload"])


func _render() -> void:
	if _state.is_empty():
		return
	set_title(_state["name"])
	var side := 2 * int(_state["radius"]) + 1
	_level.text = "%s · poziom %d z 2" % [_state["name"], int(_state["level"])]
	_fields.text = "Pole %d × %d: %d obsianych grządek, w tym %d dojrzałych. Zbiera jedną na %s s." % [
		side, side, int(_state["fields"]), int(_state["ripe"]), _number(float(_state["reapSeconds"]))]
	_render_kinds()
	_manure.text = "Obornik: %d / %d" % [int(_state["manure"]), int(_state["maxManure"])]
	_add_manure.disabled = int(_state["manure"]) >= int(_state["maxManure"])
	var crops := int(_state["crops"])
	var capacity := int(_state["capacity"])
	var store: Array = _state.get("store", [])
	if store.is_empty():
		_store.text = "Plony: 0 / %d" % capacity
	else:
		var parts := store.map(func(s: Dictionary) -> String: return "%s: %d" % [s["name"], int(s["quantity"])])
		_store.text = "%s (razem %d / %d)" % [", ".join(parts), crops, capacity]
	_crop_bar.max_value = capacity
	_crop_bar.value = crops
	_take.disabled = crops == 0
	if _state.get("full", false):
		_status.text = "Magazyn pełny: zagroda nie zbiera, dopóki nie wyjmiesz plonów (ręcznie albo podajnikiem)."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif int(_state["ripe"]) > 0:
		_status.text = "Pracuje: zbiera dojrzałe plony i od razu sieje od nowa."
		_status.add_theme_color_override("font_color", UI.GOLD)
	else:
		_status.text = "Uprawy rosną. Pierwszy zbiór, gdy dojrzeją."
		_status.add_theme_color_override("font_color", UI.MUTED)
	var next: Variant = _state.get("upgrade")
	if next == null:
		_upgrade.text = "To najlepszy budynek rolnika."
	else:
		var next_side := 2 * int(next["radius"]) + 1
		_upgrade.text = "Lepszy: %s (pole %d × %d, %d plonów, uprawy rosną %s raza szybciej, zbiór co %s s). Zrobisz go przy stole warsztatowym z tego budynku." % [
			next["name"], next_side, next_side, int(next["capacity"]), _number(float(next["growSpeed"])), _number(float(next["reapSeconds"]))]
	_help.text = "Zagroda zostawia wolne podwórze wokół budynku i drogę od drzwi do skraju pola. Pól zaoranych przez ciebie nie rusza. Postaw podajnik obok budynku, a plony same trafią na taśmę albo do skrzyni; podajnik w drugą stronę dosypie obornik."
	_fit.call_deferred()


## The buttons to pick the crop, made once, then pressed to match the one it sows.
func _render_kinds() -> void:
	var kinds: Array = _state.get("kinds", [])
	var crop: String = _state.get("crop", "wheat")
	if _kinds.size() != kinds.size():
		UI.clear(_kinds_row)
		_kinds = {}
		for kind: Dictionary in kinds:
			var b := Button.new()
			b.icon = UI.item_texture(kind["id"])
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 28 if UI.touch() else 22)
			b.text = kind["name"]
			if UI.touch():
				b.custom_minimum_size.y = 44
			var id: String = kind["id"]
			b.pressed.connect(_sow.bind(id))
			_kinds_row.add_child(b)
			_kinds[id] = b
	for kind: Dictionary in kinds:
		var b: Button = _kinds[kind["id"]]
		b.theme_type_variation = "AccentButton" if kind["id"] == crop else ""
		b.tooltip_text = "%s: rośnie %s (na oborniku %s), daje %d z grządki." % [kind["name"], _minutes(float(kind["growSeconds"])),
			_minutes(float(kind["manureSeconds"])), int(kind["yield"])]
		if kind["id"] == crop:
			var growing := int(kind.get("growing", 0))
			var all := int(_state["fields"])
			var change := "" if growing >= all else " Inne uprawy zbierze, jak dojrzeją, i w ich miejsce posieje tę (%d z %d)." % [growing, all]
			_kind_info.text = "%s: rośnie tu %s, na oborniku %s, daje %d z grządki.%s" % [kind["name"], _minutes(float(kind["growSeconds"])),
				_minutes(float(kind["manureSeconds"])), int(kind["yield"]), change]


func _sow(crop: String) -> void:
	if crop == _state.get("crop", "wheat"):
		_render_kinds()
		return
	var reply := await Net.request("farmstead.sow", {"x": plot.x, "y": plot.y, "id": farmstead, "crop": crop})
	_apply(reply)
	if reply["type"] != "farmsteads":
		_render_kinds()


func _put_manure() -> void:
	var room := int(_state.get("maxManure", 0)) - int(_state.get("manure", 0))
	var reply := await Net.request("farmstead.sow", {"x": plot.x, "y": plot.y, "id": farmstead, "manure": mini(MANURE_STEP, room)})
	_apply(reply)
	if reply["type"] == "farmsteads":
		inventory_changed.emit([], null)


func _minutes(seconds: float) -> String:
	return "%s min" % _number(seconds / 60.0)


func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0").replace(".", ",")



func _take_crops() -> void:
	var reply := await Net.request("farmstead.take", {"x": plot.x, "y": plot.y, "id": farmstead})
	_apply(reply)
	if reply["type"] == "farmsteads":
		inventory_changed.emit(reply["payload"].get("taken", []), reply["payload"].get("xp"))
