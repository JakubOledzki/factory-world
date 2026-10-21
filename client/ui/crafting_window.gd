class_name CraftingWindow
extends GameWindow
## The workbench: pick a recipe, see what it takes, and press "Wytwórz". The ingredients go at
## once; the item is made after the recipe's time, one order after another, and lands in the
## inventory even when the player walks away. The window keeps an eye on the queue while closed,
## so the screen hears about finished orders.

## Orders were finished: [{id, name, quantity}] and the XP gain (or null).
signal finished(done: Array, xp: Variant)
## Ingredients were taken or given back; the screen reloads the inventory.
signal inventory_changed
signal failed(reply: Dictionary)
## The player asked to put this workbench back into the inventory (only where `can_pick_up`).
signal pick_up_requested(id: String)

## The workbench the window was opened at (its object id in the garage or on the plot).
var workbench := ""
## Whether the window offers to put the workbench away (on a plot; the garage has its own menu).
var can_pick_up := false

var _state := {}
var _items: Array = []
var _selected := ""
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0
var _busy := false

var _recipes := VBoxContainer.new()
var _details := VBoxContainer.new()
var _craft_button: Button
var _queue := VBoxContainer.new()
var _job_bar: ProgressBar
var _job_text: Label
var _pick_up_button: Button


func _init() -> void:
	super("Stół warsztatowy", 400)
	content.add_child(_heading("Co chcesz wytworzyć?"))
	_recipes.add_theme_constant_override("separation", 4)
	content.add_child(_recipes)
	content.add_child(HSeparator.new())
	_details.add_theme_constant_override("separation", 4)
	content.add_child(_details)
	_craft_button = UI.button("Wytwórz", _craft, true)
	content.add_child(_craft_button)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Kolejka"))
	var job := HBoxContainer.new()
	_job_bar = ProgressBar.new()
	_job_bar.show_percentage = false
	_job_bar.custom_minimum_size.y = 10
	_job_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job.add_child(_job_bar)
	_job_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_job_text.custom_minimum_size.x = 44
	job.add_child(_job_text)
	content.add_child(job)
	_queue.add_theme_constant_override("separation", 2)
	content.add_child(_queue)
	content.add_child(UI.label("Wytwarzanie trwa dalej, gdy odejdziesz od stołu. Gotowe przedmioty trafiają do ekwipunku.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_pick_up_button = UI.button("Schowaj stół do ekwipunku", func() -> void: pick_up_requested.emit(workbench))
	_pick_up_button.visible = false
	content.add_child(_pick_up_button)


## Opens the window at a workbench.
func open_at(id: String) -> void:
	workbench = id
	_pick_up_button.visible = can_pick_up
	show_window()
	refresh()


## The screen calls this whenever the inventory changes.
func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


## Asks the server for the recipes and the queue; it hands out finished orders.
func refresh() -> void:
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("crafting.get")
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "crafting":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	if _selected == "" and not _state["recipes"].is_empty():
		_selected = _state["recipes"][0]["id"]
	var done: Array = _state.get("done", [])
	if not done.is_empty():
		finished.emit(done, _state.get("xp"))
	_render()


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _recipe(id: String) -> Dictionary:
	for recipe: Dictionary in _state.get("recipes", []):
		if recipe["id"] == id:
			return recipe
	return {}


func _can_make(recipe: Dictionary) -> bool:
	for ingredient: Dictionary in recipe["ingredients"]:
		if _count(ingredient["id"]) < int(ingredient["quantity"]):
			return false
	return true


func _render() -> void:
	if _state.is_empty():
		return
	for child in _recipes.get_children():
		child.free()
	for recipe: Dictionary in _state["recipes"]:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = UI.item_texture(recipe["id"])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 30)
		var amount := int(recipe["quantity"])
		b.text = "%s%s  ·  %s" % [recipe["name"], "  ×%d" % amount if amount > 1 else "", _seconds(float(recipe["seconds"]))]
		if recipe["id"] == _selected:
			b.theme_type_variation = "AccentButton"
		elif not _can_make(recipe):
			b.modulate = Color(1, 1, 1, 0.6)
		b.pressed.connect(func() -> void:
			_selected = recipe["id"]
			_render())
		_recipes.add_child(b)

	for child in _details.get_children():
		child.free()
	var selected := _recipe(_selected)
	if not selected.is_empty():
		var title := UI.label(selected["name"], UI.GOLD)
		title.add_theme_font_override("font", UI.bold())
		_details.add_child(title)
		_details.add_child(UI.label("Potrzebne:", UI.MUTED))
		for ingredient: Dictionary in selected["ingredients"]:
			var need := int(ingredient["quantity"])
			var have := _count(ingredient["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.add_child(UI.item_icon(ingredient["id"], 26))
			var name_label := UI.label("%d × %s" % [need, ingredient["name"]])
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			row.add_child(UI.label("masz %d" % have, UI.GOOD if have >= need else UI.ERROR, HORIZONTAL_ALIGNMENT_RIGHT))
			_details.add_child(row)
		_details.add_child(UI.label("Czas: %s  ·  %d XP" % [_seconds(float(selected["seconds"])), int(selected["xp"])], UI.MUTED))
		if _selected == "nails":
			_details.add_child(UI.label("Gwoździe kupisz też u handlarza na rynku.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var queue: Array = _state.get("queue", [])
	var full := queue.size() >= int(_state.get("maxQueue", 5))
	_craft_button.disabled = selected.is_empty() or not _can_make(selected) or full or _busy
	_craft_button.text = "Kolejka pełna" if full else "Wytwórz"

	for child in _queue.get_children():
		child.free()
	if queue.is_empty():
		_queue.add_child(UI.label("Nic się nie wytwarza.", UI.MUTED))
	for i in queue.size():
		var job: Dictionary = queue[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(job["recipe"], 24))
		var label := UI.label(job["name"] + ("  (teraz)" if i == 0 else ""), UI.TEXT if i == 0 else UI.MUTED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var cancel := UI.button("Anuluj", _cancel.bind(int(job["id"])))
		cancel.tooltip_text = "Składniki wrócą do ekwipunku"
		row.add_child(cancel)
		_queue.add_child(row)
	_update_job()
	_fit.call_deferred()


func _seconds(seconds: float) -> String:
	var s := roundi(seconds)
	return "%d s" % s if s < 60 else "%d min %02d s" % [s / 60, s % 60]


func _update_job() -> void:
	var queue: Array = _state.get("queue", [])
	if queue.is_empty():
		_job_bar.value = 0
		_job_text.text = ""
		return
	var job: Dictionary = queue[0]
	var total := float(job["finishesAt"]) - float(job["startsAt"])
	var left := maxf(float(job["finishesAt"]) - _server_now(), 0.0)
	_job_bar.max_value = total
	_job_bar.value = total - left
	_job_text.text = "%d s" % ceili(left / 1000.0)


func _process(_delta: float) -> void:
	var queue: Array = _state.get("queue", [])
	if queue.is_empty():
		return
	if visible:
		_update_job()
	var now := _server_now()
	if now >= float(queue[0]["finishesAt"]) and now >= _next_poll and not _refreshing:
		refresh()


func _craft() -> void:
	if workbench == "" or _selected == "":
		return
	_busy = true
	_render()
	var reply := await Net.request("crafting.craft", {"workbench": workbench, "recipe": _selected})
	_busy = false
	_apply(reply)
	if reply["type"] == "crafting":
		inventory_changed.emit()


func _cancel(id: int) -> void:
	var reply := await Net.request("crafting.cancel", {"id": id})
	_apply(reply)
	if reply["type"] == "crafting":
		inventory_changed.emit()


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
