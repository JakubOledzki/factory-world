class_name PlansWindow
extends GameWindow
## Building plans kept on the server by name, and the sketchbook: a sandbox where any object that stands
## on a plot is drawn as a ghost, without having it and without building anything, until the sketch is
## saved as a plan. A saved plan is put up like a copied one: its ghost follows the mouse, a click builds it.

signal failed(reply: Dictionary)
## The player picked a plan to put up: [{ kind, dx, dy, rotation }].
signal use_plan(objects: Array)
## The player picked what to draw in the sketchbook.
signal sketch_kind(kind: String)
## The player cleared the sketch.
signal sketch_cleared

const MAX_CHOICES := 10

## Every object that stands on a plot (from plot.enter), and what each is called.
var placeable: Array = []
var names := {}
## Asked for the objects to save: the sketch when the sketchbook is open, else the copied plan.
var current_plan := func() -> Array: return []
var sketch_size := func() -> int: return 0

var _plans: Array = []
var _list := VBoxContainer.new()
var _name := LineEdit.new()
var _search := LineEdit.new()
var _choices := VBoxContainer.new()
var _sketch_info: Label


func _init() -> void:
	super("Plany i szkicownik", 460)
	content.add_child(_heading("Szkicownik"))
	content.add_child(UI.label("Rysuj fabrykę z dowolnych obiektów, bez przedmiotów w ekwipunku: wybierz obiekt i klikaj pola działki; kliknięcie narysowanego obiektu go zmazuje, [R] obraca. Szkic zapisz jako plan i postaw, gdy zbierzesz przedmioty.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_sketch_info = UI.label("", UI.TEXT)
	content.add_child(_sketch_info)
	_search.placeholder_text = "Szukaj obiektu…"
	_search.text_changed.connect(func(_text: String) -> void: _render_choices())
	content.add_child(_search)
	_choices.add_theme_constant_override("separation", 4)
	content.add_child(_choices)
	content.add_child(UI.button("Wyczyść szkic", func() -> void:
		sketch_cleared.emit()
		render_sketch()))
	content.add_child(HSeparator.new())
	content.add_child(_heading("Zapisz plan"))
	content.add_child(UI.label("Zapisuje szkic, a bez szkicu ostatnio skopiowany kawałek fabryki [V]. Plan o tej samej nazwie zostaje zastąpiony.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_name.placeholder_text = "Nazwa planu"
	_name.max_length = 40
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	row.add_child(UI.button("Zapisz", _save, true))
	content.add_child(row)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Twoje plany"))
	_list.add_theme_constant_override("separation", 4)
	content.add_child(_list)


func show_window() -> void:
	super()
	_search.text = ""
	_render_choices()
	render_sketch()
	refresh()


func refresh() -> void:
	var reply := await fetch("plans.get")
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "plans":
		failed.emit(reply)
		return
	_plans = reply["payload"]["plans"]
	UI.clear(_list)
	if _plans.is_empty():
		_list.add_child(UI.label("Nie masz jeszcze zapisanych planów.", UI.MUTED))
	for plan: Dictionary in _plans:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var title := UI.label("%s (%d obiektów)" % [plan["name"], (plan["objects"] as Array).size()])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		line.add_child(title)
		line.add_child(UI.button("Postaw", _use.bind(plan), true))
		line.add_child(UI.button("Usuń", _delete.bind(int(plan["id"]))))
		_list.add_child(line)
	_fit.call_deferred()


func render_sketch() -> void:
	var count: int = sketch_size.call()
	_sketch_info.text = "Szkic: %d obiektów." % count if count > 0 else "Szkic jest pusty."


func _render_choices() -> void:
	UI.clear(_choices)
	var query := _search.text.strip_edges().to_lower()
	var kinds: Array = placeable.duplicate()
	kinds.sort_custom(func(a: String, b: String) -> bool: return _item_name(a) < _item_name(b))
	var shown := 0
	for kind: String in kinds:
		if query != "" and not _item_name(kind).to_lower().contains(query):
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UI.item_icon(kind, 22))
		var label := UI.label(_item_name(kind))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		line.add_child(UI.button("Rysuj", func() -> void: sketch_kind.emit(kind)))
		_choices.add_child(line)
		shown += 1
		if shown >= MAX_CHOICES:
			break
	if shown == 0:
		_choices.add_child(UI.label("Nic takiego nie ma.", UI.MUTED))
	_fit.call_deferred()


func _item_name(kind: String) -> String:
	return names.get(kind, ItemInfo.name_of(kind))


func _save() -> void:
	var objects: Array = current_plan.call()
	if objects.is_empty():
		failed.emit({"type": "error", "payload": {"code": "bad_plan", "message": "Nothing to save."}})
		return
	var reply := await Net.request("plans.save", {"name": _name.text.strip_edges(), "objects": objects})
	_apply(reply)
	if reply["type"] == "plans":
		_name.text = ""


func _use(plan: Dictionary) -> void:
	use_plan.emit(plan["objects"])


func _delete(id: int) -> void:
	_apply(await Net.request("plans.delete", {"id": id}))


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
