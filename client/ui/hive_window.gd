class_name HiveWindow
extends GameWindow
## A beehive on the plot: its bees make honey by themselves, and a piece of wax with every few jars, faster among lindens in
## flower. A full hive waits until the honey is taken out.

signal inventory_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 5000.0

var hive := ""

var _state := {}
var _summary: Label
var _honey: Label
var _wax: Label
var _progress: ProgressBar
var _take: Button


func _init() -> void:
	super("Ul", 400)
	poll_every = POLL
	_summary = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_summary)
	content.add_child(HSeparator.new())
	for row_item: Array in [["honey", "Miód"], ["wax", "Wosk"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(row_item[0], 32))
		var label := UI.label(row_item[1])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		content.add_child(row)
		if row_item[0] == "honey":
			_honey = label
		else:
			_wax = label
	_progress = ProgressBar.new()
	_progress.max_value = 1.0
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 10
	content.add_child(_progress)
	_take = UI.button("Wybierz miód i wosk", _take_out, true)
	content.add_child(_take)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(hive))
	pick_up.tooltip_text = "Miód i wosk z ula wrócą do ekwipunku"
	content.add_child(pick_up)


func open_at(id: String) -> void:
	if id != hive:
		_state = {}
	hive = id
	show_window()
	refresh()


func refresh() -> void:
	if hive == "":
		return
	var reply := await fetch("hive.get", {"id": hive})
	_apply(reply)


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "hive":
		failed.emit(reply)
		hide_window()
		return false
	_state = reply["payload"]["hive"]
	_render()
	return true


func _render() -> void:
	if _state.is_empty():
		return
	var lindens := int(_state["lindens"])
	var speed := "Lip w zasięgu %d pól: %d, pszczoły pracują %d%% normalnego tempa." % [int(_state["reach"]), lindens, int(_state["speedPercent"])] \
		if lindens > 0 else "Brak kwitnących lip w zasięgu %d pól: posadź je wokół ula, a pszczoły będą pracować do dwóch razy szybciej." % int(_state["reach"])
	var minutes := float(_state["honeySeconds"]) / 60.0
	_summary.text = "Słoik miodu co %s min, kawałek wosku co %d słoiki. %s" % [str(snappedf(minutes, 0.1)).replace(".", ","),
		int(_state["honeyPerWax"]), speed]
	_honey.text = "Miód: %d/%d%s" % [int(_state["honey"]), int(_state["maxHoney"]), " (ul pełny, pszczoły czekają)" if _state["full"] else ""]
	_wax.text = "Wosk: %d" % int(_state["wax"])
	_progress.value = float(_state["progress"])
	_take.disabled = int(_state["honey"]) == 0 and int(_state["wax"]) == 0
	_fit.call_deferred()


func _take_out() -> void:
	if _apply(await Net.request("hive.take", {"id": hive})):
		inventory_changed.emit()
