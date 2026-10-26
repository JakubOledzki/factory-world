class_name GalleryWindow
extends GameWindow
## The most liked public factories: who built them, how many players like them, and a button to go and look.
## The server counts the likes every few minutes, so the list changes now and then, not at every like.

signal failed(reply: Dictionary)

var _list := VBoxContainer.new()
## The names of the biomes by id, for each plot's line.
var biome_names := {}


func _init() -> void:
	super("Galeria fabryk", 520)
	content.add_child(UI.label("Działki publiczne, które gracze polubili najczęściej. Odwiedź je, podejrzyj układ taśm i maszyn, a jeśli ci się spodobają, kliknij „Podoba mi się”.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_list.add_theme_constant_override("separation", 6)
	content.add_child(_list)


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	var reply := await fetch("plot.gallery")
	if reply["type"] != "plot.gallery":
		failed.emit(reply)
		return
	UI.clear(_list)
	var plots: Array = reply["payload"]["plots"]
	if plots.is_empty():
		_list.add_child(UI.label("Nikt jeszcze nie polubił żadnej fabryki. Udostępnij swoją działkę na mapie świata, a inni będą mogli ją odwiedzić.", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	for p: Dictionary in plots:
		_list.add_child(_row(p))
	_list.add_child(UI.label("Lista odświeża się co %d min." % roundi(float(reply["payload"]["refreshSeconds"]) / 60.0), UI.MUTED))


func _row(p: Dictionary) -> Control:
	var at := Vector2i(int(p["x"]), int(p["y"]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var place := UI.label("%d." % int(p["place"]), UI.GOLD)
	place.add_theme_font_override("font", UI.bold())
	place.custom_minimum_size.x = 30
	row.add_child(place)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.label(str(p["name"]) if p.get("name") != null else "Działka %d × %d" % [at.x, at.y])
	title.add_theme_font_override("font", UI.bold())
	text.add_child(title)
	text.add_child(UI.label("%s  ·  %s  ·  polubienia: %d%s" % [p["owner"], biome_names.get(int(p["biome"]), ""), int(p["likes"]),
		"  ·  lubisz ją" if p.get("liked", false) else ""], UI.MUTED))
	row.add_child(text)
	var visit := UI.button("Odwiedź", _visit.bind(at), true)
	visit.disabled = at == Game.plot
	row.add_child(visit)
	return row


func _visit(at: Vector2i) -> void:
	hide_window()
	Game.enter_plot(at)
