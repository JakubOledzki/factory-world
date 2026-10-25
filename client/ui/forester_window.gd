class_name ForesterWindow
extends GameWindow
## A forester's building on a plot (forester's hut, lodge, forestry station): how its forest grows,
## the kind of tree it plants (picked here), how much wood it keeps, and a button to take the wood out.
## It plants and cuts by itself while the player is away too; an inserter next to the building takes
## the wood out as well.

## After every answer from the server, with the plot's forestry as it is now.
signal updated(forestry: Dictionary)
## Wood came out: [{id, name, quantity}], and the XP gain or null.
signal inventory_changed(taken: Array, xp: Variant)
signal failed(reply: Dictionary)
## The player asked to put the building back into the inventory.
signal pick_up_requested(id: String)

## Kinds of tree as in "posadzi …".
const PLANTS := {"pine": "sosnę", "spruce": "świerk", "birch": "brzozę", "oak": "dąb", "linden": "lipę"}

var forester := ""
var plot := Vector2i(-1, -1)

var _state := {}

var _level: Label
var _forest: Label
## One button per kind of tree, by the server's id; the one it plants is lit.
var _kinds := {}
var _kinds_row: HFlowContainer
var _kind_info: Label
var _store_icon: TextureRect
var _store: Label
var _wood_bar: ProgressBar
var _take: Button
var _status: Label
var _upgrade: Label
var _help: Label


func _init() -> void:
	super("Leśniczówka", 420)
	poll_every = 3000.0
	_level = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_level)
	_forest = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_forest)
	content.add_child(HSeparator.new())
	content.add_child(UI.label("Co sadzi:", UI.GOLD))
	_kinds_row = HFlowContainer.new()
	_kinds_row.add_theme_constant_override("h_separation", 4)
	_kinds_row.add_theme_constant_override("v_separation", 4)
	content.add_child(_kinds_row)
	_kind_info = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_kind_info)
	content.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_store_icon = UI.item_icon("wood", 30)
	row.add_child(_store_icon)
	_store = UI.label("")
	_store.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_store)
	_take = UI.button("Wyjmij drewno", _take_wood, true)
	row.add_child(_take)
	content.add_child(row)
	_wood_bar = ProgressBar.new()
	_wood_bar.show_percentage = false
	_wood_bar.custom_minimum_size.y = 10
	content.add_child(_wood_bar)
	_status = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_status)
	content.add_child(HSeparator.new())
	_upgrade = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_upgrade)
	_help = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_help)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(forester))
	pick_up.tooltip_text = "Drewno ze środka wróci do ekwipunku, a las, który posadził, zniknie z działki"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	plot = at
	forester = id
	show_window()
	refresh()


## Shows the forester from a "forestry" answer the plot asked for itself.
func show_state(forestry: Dictionary) -> void:
	for f: Dictionary in forestry.get("foresters", []):
		if f["id"] == forester:
			_state = f
			_render()
			return


func refresh() -> void:
	if forester == "":
		return
	var reply := await fetch("forestry.get", {"x": plot.x, "y": plot.y})
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "forestry":
		failed.emit(reply)
		return
	updated.emit(reply["payload"])
	show_state(reply["payload"])


func _render() -> void:
	if _state.is_empty():
		return
	set_title(_state["name"])
	var side := 2 * int(_state["radius"]) + 1
	_level.text = "%s · poziom %d z 3" % [_state["name"], int(_state["level"])]
	var grow: Variant = _state.get("growSeconds")
	_forest.text = "Las %d × %d pól: %d drzew, w tym %d do ścięcia. Drzewo rośnie tu %s, ścina jedno na %s s." % [
		side, side, int(_state["trees"]), int(_state["grown"]), _minutes(float(grow)) if grow != null else "—",
		_number(float(_state["cutSeconds"]))]
	_render_kinds()
	var wood := int(_state["wood"])
	var capacity := int(_state["capacity"])
	var store: Array = _state.get("store", [])
	if store.size() > 1:
		var parts := store.map(func(s: Dictionary) -> String: return "%s: %d" % [s["name"], int(s["quantity"])])
		_store.text = "%s, %s (razem %d / %d)" % [parts[0], String(parts[1]).to_lower(), wood, capacity]
	elif store.size() == 1:
		_store.text = "%s: %d / %d" % [store[0]["name"], wood, capacity]
	else:
		_store.text = "Drewno: %d / %d" % [wood, capacity]
	_store_icon.texture = UI.item_texture(store[store.size() - 1]["id"] if store.size() > 0 else "wood")
	_wood_bar.max_value = capacity
	_wood_bar.value = wood
	_take.disabled = wood == 0
	if _state.get("full", false):
		_status.text = "Magazyn pełny: leśnik nie tnie, dopóki nie wyjmiesz drewna (ręcznie albo podajnikiem)."
		_status.add_theme_color_override("font_color", UI.ERROR)
	elif int(_state["grown"]) > 0:
		_status.text = "Pracuje: ścina drzewa i od razu sadzi nowe w ich miejscu."
		_status.add_theme_color_override("font_color", UI.GOLD)
	else:
		_status.text = "Sadzonki rosną. Pierwsze drzewa będą do ścięcia, gdy urosną."
		_status.add_theme_color_override("font_color", UI.MUTED)
	var next: Variant = _state.get("upgrade")
	if next == null:
		_upgrade.text = "To najlepszy budynek leśny."
	else:
		var next_side := 2 * int(next["radius"]) + 1
		_upgrade.text = "Lepszy: %s (las %d × %d, %d drewna, drzewo rośnie %s, cięcie co %s s). Zrobisz go przy stole warsztatowym z tego budynku." % [
			next["name"], next_side, next_side, int(next["capacity"]), _minutes(float(next["growSeconds"])) if next.get("growSeconds") != null else "—",
			_number(float(next["cutSeconds"]))]
	_help.text = "Leśnik zostawia wolną polanę wokół budynku i drogę od drzwi do skraju lasu. Postaw tam podajnik obok budynku, a drewno samo trafi na taśmę albo do skrzyni."
	_fit.call_deferred()


## The buttons to pick the kind of tree, made once, then pressed to match the one it plants.
func _render_kinds() -> void:
	var kinds: Array = _state.get("kinds", [])
	var species: String = _state.get("species", "pine")
	if _kinds.size() != kinds.size():
		UI.clear(_kinds_row)
		_kinds = {}
		for kind: Dictionary in kinds:
			var b := Button.new()
			b.icon = UI.item_texture(kind["sapling"])
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 28 if UI.touch() else 22)
			b.text = kind["name"]
			if UI.touch():
				b.custom_minimum_size.y = 44
			var id: String = kind["id"]
			b.pressed.connect(_plant.bind(id))
			_kinds_row.add_child(b)
			_kinds[id] = b
	var picked: Dictionary = {}
	for kind: Dictionary in kinds:
		var b: Button = _kinds[kind["id"]]
		b.theme_type_variation = "AccentButton" if kind["id"] == species else ""
		var grow: Variant = kind.get("growSeconds")
		b.tooltip_text = "%s: rośnie %s, daje %d × %s. %s." % [kind["name"], _minutes(float(grow)) if grow != null else "—",
			int(kind["woodQuantity"]), kind["woodName"], kind["note"]]
		if kind["id"] == species:
			picked = kind
	if picked.is_empty():
		_kind_info.text = ""
		return
	var grow: Variant = picked.get("growSeconds")
	var standing := int(picked.get("standing", 0))
	var all := int(_state["trees"])
	var change := "" if standing >= all else " Rosnące już drzewa innych gatunków zetnie, jak urosną, i w ich miejsce posadzi %s (%d z %d)." % [
		PLANTS.get(picked["id"], String(picked["name"]).to_lower()), standing, all]
	_kind_info.text = "%s: rośnie tu %s, daje %d × %s. %s.%s" % [picked["name"], _minutes(float(grow)) if grow != null else "—",
		int(picked["woodQuantity"]), String(picked["woodName"]).to_lower(), picked["note"], change]


func _plant(species: String) -> void:
	if species == _state.get("species", "pine"):
		_render_kinds()
		return
	var reply := await Net.request("forester.plant", {"x": plot.x, "y": plot.y, "id": forester, "species": species})
	_apply(reply)
	if reply["type"] != "forestry":
		_render_kinds()


func _minutes(seconds: float) -> String:
	return "%s min" % _number(seconds / 60.0)


func _number(value: float) -> String:
	return str(snappedf(value, 0.1)).trim_suffix(".0").replace(".", ",")



func _take_wood() -> void:
	var reply := await Net.request("forester.take", {"x": plot.x, "y": plot.y, "id": forester})
	_apply(reply)
	if reply["type"] == "forestry":
		inventory_changed.emit(reply["payload"].get("taken", []), reply["payload"].get("xp"))
