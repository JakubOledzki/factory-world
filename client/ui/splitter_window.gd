class_name SplitterWindow
extends GameWindow
## A splitter's settings: which items it sorts out to one side. Without any it sends what comes in
## left and right in turn; with some, those go to the chosen side and everything else to the other.

## The server answered with the plot's logistics after a change.
signal applied(state: Dictionary)
signal failed(reply: Dictionary)

const MAX_FILTER := 8
const MAX_CHOICES := 8
## The way a splitter's left and right outputs face, by its rotation (as PlotLogistics.facing).
const COMPASS := {Vector2i(0, 1): "na południe", Vector2i(1, 0): "na wschód", Vector2i(0, -1): "na północ", Vector2i(-1, 0): "na zachód"}

var splitter := ""
var plot := Vector2i(-1, -1)
var rotation_index := 0
## What every item is called, and the inventory (listed first among the choices).
var names := {}
var _items: Array = []
var _filter: Array = []
var _side := 1

var _sides := HBoxContainer.new()
var _chosen := VBoxContainer.new()
var _search := LineEdit.new()
var _choices := VBoxContainer.new()


func _init() -> void:
	super("Rozdzielacz", 400)
	content.add_child(UI.label("Bierze przedmioty z taśmy za sobą i oddaje je na taśmy po swojej lewej i prawej stronie.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	content.add_child(_heading("Wybrane przedmioty idą"))
	_sides.add_theme_constant_override("separation", 6)
	content.add_child(_sides)
	_chosen.add_theme_constant_override("separation", 4)
	content.add_child(_chosen)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Dodaj przedmiot"))
	_search.placeholder_text = "Szukaj…"
	_search.text_changed.connect(func(_text: String) -> void: _render_choices())
	content.add_child(_search)
	_choices.add_theme_constant_override("separation", 4)
	content.add_child(_choices)


func open_at(at: Vector2i, id: String, rotation: int, filter: Dictionary) -> void:
	splitter = id
	plot = at
	rotation_index = rotation
	_filter = (filter.get("items", []) as Array).duplicate()
	_side = int(filter.get("side", 1))
	_search.text = ""
	show_window()
	_render()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render_choices()


func _name(item: String) -> String:
	return names.get(item, item)


func _way(side: int) -> String:
	var forward := PlotLogistics.facing(rotation_index)
	var left := Vector2i(forward.y, -forward.x)
	return COMPASS[left if side == 0 else -left]


func _render() -> void:
	for child in _sides.get_children():
		child.free()
	for side: int in [0, 1]:
		var b := UI.button("%s%s (%s)" % ["✓ " if side == _side else "", "w lewo" if side == 0 else "w prawo", _way(side)],
			_apply_filter.bind(_filter, side), side == _side)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sides.add_child(b)

	for child in _chosen.get_children():
		child.free()
	if _filter.is_empty():
		_chosen.add_child(UI.label("Bez filtra: przedmioty idą na zmianę w lewo i w prawo.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		for item: String in _filter:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.add_child(UI.item_icon(item, 26))
			var name_label := UI.label(_name(item))
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			row.add_child(UI.button("Usuń", _apply_filter.bind(_filter.filter(func(i: String) -> bool: return i != item), _side)))
			_chosen.add_child(row)
		_chosen.add_child(UI.label("Wszystko inne idzie %s." % ("w prawo" if _side == 0 else "w lewo"), UI.MUTED))
	_render_choices()


## Items to add: those the player has first, then the rest by name, narrowed by the search.
func _render_choices() -> void:
	for child in _choices.get_children():
		child.free()
	if _filter.size() >= MAX_FILTER:
		_choices.add_child(UI.label("Można wybrać najwyżej %d przedmiotów." % MAX_FILTER, UI.MUTED))
		_fit.call_deferred()
		return
	var query := _search.text.strip_edges().to_lower()
	var owned: Array = _items.map(func(stack: Dictionary) -> String: return stack["id"])
	var rest: Array = names.keys().filter(func(i: String) -> bool: return not i in owned)
	rest.sort_custom(func(a: String, b: String) -> bool: return _name(a) < _name(b))
	var shown := 0
	for item: String in owned + rest:
		if item in _filter or (query != "" and not _name(item).to_lower().contains(query)):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(item, 22))
		var name_label := UI.label(_name(item))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UI.button("Dodaj", _apply_filter.bind(_filter + [item], _side)))
		_choices.add_child(row)
		shown += 1
		if shown >= MAX_CHOICES:
			break
	if shown == 0:
		_choices.add_child(UI.label("Nic takiego nie ma.", UI.MUTED))
	_fit.call_deferred()


func _apply_filter(items: Array, side: int) -> void:
	var reply := await Net.request("splitter.set", {"x": plot.x, "y": plot.y, "id": splitter, "side": side, "items": items})
	if reply["type"] != "logistics":
		failed.emit(reply)
		return
	_filter = items.duplicate()
	_side = side
	applied.emit(reply["payload"])
	_render()


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
