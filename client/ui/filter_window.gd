class_name FilterWindow
extends GameWindow
## The filter of an inserter, a storage or a machine: the one item it takes. An inserter with a
## filter picks up only that item; a storage or a machine lets in nothing else. Without one it
## takes anything, as before. The item shows as a small icon on the object on the plot.
## An inserter or a pump also has a condition: it fills a storage in front up to so many pieces and
## keeps so many in a storage behind it.

## The server answered with the plot's logistics after a change.
signal applied(state: Dictionary)
signal failed(reply: Dictionary)

const MAX_CHOICES := 8
## What the filter does, by what the object is.
const ABOUT := {
	"inserter": "Podajnik z filtrem podnosi tylko wybrany przedmiot, a resztę zostawia.",
	"storage": "Magazyn z filtrem przyjmuje tylko wybrany przedmiot, z podajników i z ekwipunku.",
	"machine": "Maszyna z filtrem przyjmuje z podajników tylko wybrany przedmiot.",
}

var object_id := ""
var plot := Vector2i(-1, -1)
## What every item is called, and the inventory (listed first among the choices).
var names := {}
var _items: Array = []
## Items the object can take at all (a pile takes only wood); empty for any.
var _allowed: Array = []
var _filter := ""
var _what := ""

var _about: Label
var _chosen := VBoxContainer.new()
var _search := LineEdit.new()
var _choices := VBoxContainer.new()
## The condition of an inserter or a pump: fill the storage in front up to so many, keep so many in the one behind.
var _condition := VBoxContainer.new()
var _below := SpinBox.new()
var _keep := SpinBox.new()


func _init() -> void:
	super("Filtr", 400)
	_about = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_about)
	content.add_child(_heading("Ustawiony filtr"))
	_chosen.add_theme_constant_override("separation", 4)
	content.add_child(_chosen)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Wybierz przedmiot"))
	_search.placeholder_text = "Szukaj…"
	_search.text_changed.connect(func(_text: String) -> void: _render_choices())
	content.add_child(_search)
	_choices.add_theme_constant_override("separation", 4)
	content.add_child(_choices)
	_condition.add_theme_constant_override("separation", 4)
	_condition.add_child(HSeparator.new())
	_condition.add_child(_heading("Warunek pracy"))
	_condition.add_child(UI.label("Działa tylko ze skrzynią albo zbiornikiem. 0 to brak warunku.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_condition.add_child(_spin_row("Napełniaj skrzynię przed sobą do", _below))
	_condition.add_child(_spin_row("Zostawiaj w skrzyni za sobą", _keep))
	_condition.add_child(UI.button("Zapisz warunek", _apply_condition, true))
	content.add_child(_condition)


## Opens the filter of object `id` on the plot at `at`. `name` is what the object is called, `role`
## "inserter", "storage" or "machine", `allowed` the only items it takes at all (empty for any).
## `condition` is the inserter's { below, keep }.
func open_at(at: Vector2i, id: String, name: String, item: String, role: String, allowed: Array = [], condition := {}) -> void:
	object_id = id
	plot = at
	_filter = item
	_allowed = allowed
	_condition.visible = role == "inserter"
	_below.value = int(condition.get("below", 0))
	_keep.value = int(condition.get("keep", 0))
	_what = "podnosi" if role == "inserter" else "przyjmuje"
	set_title("Filtr: %s" % name)
	_about.text = ABOUT.get(role, ABOUT["machine"])
	_search.text = ""
	show_window()
	_render()


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render_choices()


func _name(item: String) -> String:
	return names.get(item, item)


func _render() -> void:
	for child in _chosen.get_children():
		child.free()
	if _filter == "":
		_chosen.add_child(UI.label("Bez filtra: %s wszystko." % _what, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(_filter, 26))
		var name_label := UI.label("%s tylko: %s" % [_what.capitalize(), _name(_filter)])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UI.button("Usuń", _apply.bind("")))
		_chosen.add_child(row)
	_render_choices()


## Items to choose: those the player has first, then the rest by name, narrowed by the search.
func _render_choices() -> void:
	for child in _choices.get_children():
		child.free()
	var query := _search.text.strip_edges().to_lower()
	var owned: Array = _items.map(func(stack: Dictionary) -> String: return stack["id"])
	var all: Array = _allowed if not _allowed.is_empty() else names.keys()
	owned = owned.filter(func(i: String) -> bool: return i in all)
	var rest: Array = all.filter(func(i: String) -> bool: return not i in owned)
	rest.sort_custom(func(a: String, b: String) -> bool: return _name(a) < _name(b))
	var shown := 0
	for item: String in owned + rest:
		if item == _filter or (query != "" and not _name(item).to_lower().contains(query)):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(item, 22))
		var name_label := UI.label(_name(item))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UI.button("Wybierz", _apply.bind(item)))
		_choices.add_child(row)
		shown += 1
		if shown >= MAX_CHOICES:
			break
	if shown == 0:
		_choices.add_child(UI.label("Nic takiego nie ma.", UI.MUTED))
	_fit.call_deferred()


func _apply(item: String) -> void:
	var reply := await Net.request("filter.set", {"x": plot.x, "y": plot.y, "id": object_id, "item": item})
	if reply["type"] != "logistics":
		failed.emit(reply)
		return
	_filter = item
	if reply["payload"].get("names") != null:
		names = reply["payload"]["names"]
	applied.emit(reply["payload"])
	_render()


func _apply_condition() -> void:
	var reply := await Net.request("inserter.condition",
		{"x": plot.x, "y": plot.y, "id": object_id, "below": int(_below.value), "keep": int(_keep.value)})
	if reply["type"] != "logistics":
		failed.emit(reply)
		return
	applied.emit(reply["payload"])


func _spin_row(text: String, spin: SpinBox) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_label := UI.label(text, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	spin.min_value = 0
	spin.max_value = 1000000
	spin.custom_minimum_size.x = 110
	row.add_child(spin)
	return row


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
