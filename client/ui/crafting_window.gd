class_name CraftingWindow
extends GameWindow
## The workbench or the anvil: pick a recipe, see what it takes, and press "Wytwórz". Each shows
## only its own recipes (the anvil forges the tools), but both share one queue. The ingredients go at
## once; the item is made after the recipe's time, one order after another, and lands in the
## inventory even when the player walks away. The window keeps an eye on the queue while closed,
## so the screen hears about finished orders. It covers most of the screen: recipes sorted into
## categories on the left, the chosen recipe and the queue on the right. Research is done at the
## research table (ResearchWindow); recipes still to be researched aren't shown here.

## Orders were finished: [{id, name, quantity}] and the XP gain (or null).
signal finished(done: Array, xp: Variant)
## Ingredients were taken or given back; the screen reloads the inventory.
signal inventory_changed
signal failed(reply: Dictionary)
## The player asked to put this workbench back into the inventory (only where `can_pick_up`).
signal pick_up_requested(id: String)

const WORKBENCH := "furniture_workbench"
const ANVIL := "furniture_anvil"
const SHIPYARD := "furniture_shipyard"
const TAILOR := "furniture_tailor"
const STATION_TITLES := {ANVIL: "Kowadło", SHIPYARD: "Stocznia", TAILOR: "Pracownia krawiecka"}
const STATION_PICK_UP := {ANVIL: "Schowaj kowadło do ekwipunku", SHIPYARD: "Schowaj stocznię do ekwipunku", TAILOR: "Schowaj pracownię do ekwipunku"}

## The workbench or anvil the window was opened at (its object id in the garage or on the plot).
var workbench := ""
## What it is: WORKBENCH or ANVIL; it shows the recipes made there.
var station := WORKBENCH
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
var _recipe_list := ScrollContainer.new()
## The chosen category (index in ItemInfo.CATEGORIES), or -1 for all.
var _category := -1
var _categories := CategoryList.new()
var _search := UI.line_edit("Szukaj przepisu…")
var _details := VBoxContainer.new()
var _craft_button: Button
var _queue := VBoxContainer.new()
var _job_bar: ProgressBar
var _job_text: Label
var _pick_up_button: Button
var _body := HBoxContainer.new()


func _init() -> void:
	super("Stół warsztatowy", 0)
	fill_margin = Vector2(40, 24)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var heading := _heading("Co chcesz wytworzyć?")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_search.custom_minimum_size.x = 260
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void:
		_recipe_list.scroll_vertical = 0
		_render())
	top.add_child(_search)
	content.add_child(top)

	# Categories, then the recipes, then the chosen recipe and the queue; each part scrolls on its own.
	var body := _body
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_categories.chosen.connect(func(category: int) -> void:
		_category = category
		_recipe_list.scroll_vertical = 0
		_render())
	body.add_child(_categories)
	body.add_child(VSeparator.new())
	_recipe_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipes.add_theme_constant_override("separation", 4)
	_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_recipes)
	_recipe_list.add_child(margin)
	body.add_child(_recipe_list)
	body.add_child(VSeparator.new())

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size.x = 470 if UI.touch() else 360
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_right", 16)
	side_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_margin.add_child(side)
	side_scroll.add_child(side_margin)
	_details.add_theme_constant_override("separation", 4)
	side.add_child(_details)
	_craft_button = UI.button("Wytwórz", _craft, true)
	side.add_child(_craft_button)
	side.add_child(HSeparator.new())
	side.add_child(_heading("Kolejka"))
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
	side.add_child(job)
	_queue.add_theme_constant_override("separation", 2)
	side.add_child(_queue)
	side.add_child(UI.label("Wytwarzanie trwa dalej, gdy odejdziesz. Stół i kowadło mają wspólną kolejkę; gotowe przedmioty trafiają do ekwipunku.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	side.add_child(UI.label("Przytrzymaj palec na przedmiocie, aby zobaczyć jego opis i ceny na rynku." if UI.touch()
			else "Przytrzymaj Ctrl i najedź myszą na przedmiot, aby zobaczyć jego opis i ceny na rynku.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_pick_up_button = UI.button("Schowaj stół do ekwipunku", func() -> void: pick_up_requested.emit(workbench))
	_pick_up_button.visible = false
	side.add_child(_pick_up_button)


## Opens the window at a workbench or, with `kind` ANVIL, SHIPYARD or TAILOR, at an anvil, a shipyard or a tailor's.
func open_at(id: String, kind := WORKBENCH) -> void:
	workbench = id
	if kind != station:
		_selected = ""
	station = kind
	set_title(STATION_TITLES.get(kind, "Stół warsztatowy"))
	_pick_up_button.text = STATION_PICK_UP.get(kind, "Schowaj stół do ekwipunku")
	_pick_up_button.visible = can_pick_up
	show_window()
	refresh()


## The recipes made where the window is open; those still to be researched are left out.
func _station_recipes() -> Array:
	return _state.get("recipes", []).filter(func(recipe: Dictionary) -> bool:
		return recipe.get("station", WORKBENCH) == station and recipe.get("locked") == null)


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
	var here := _station_recipes()
	if not here.any(func(recipe: Dictionary) -> bool: return recipe["id"] == _selected) and not here.is_empty():
		_selected = here[0]["id"]
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
	UI.clear(_recipes)
	var query := _search.text.strip_edges().to_lower()
	var found: Array = _station_recipes().filter(func(recipe: Dictionary) -> bool:
		return query == "" or recipe["name"].to_lower().contains(query))
	_categories.show_counts(CategoryList.count(found.map(func(recipe: Dictionary) -> String: return recipe["id"])), _category, true)
	var grids := {}
	for recipe: Dictionary in found:
		var category := ItemInfo.category_of(recipe["id"])
		if _category != -1 and category != _category:
			continue
		if not grids.has(category):
			grids[category] = GridContainer.new()
			grids[category].columns = 1 if UI.touch() else 2
			grids[category].add_theme_constant_override("h_separation", 6)
			grids[category].add_theme_constant_override("v_separation", 4)
		var b := Button.new()
		b.set_meta("item", recipe["id"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		grids[category].add_child(b)
	# In the order of the categories, under their names when all are shown.
	var order := grids.keys()
	order.sort()
	for category: int in order:
		if _category == -1:
			var heading := UI.label(ItemInfo.CATEGORIES[category][0].to_upper(), UI.MUTED)
			heading.add_theme_font_override("font", UI.bold())
			_recipes.add_child(heading)
		_recipes.add_child(grids[category])
	if found.is_empty():
		_recipes.add_child(UI.label("Żaden przepis nie pasuje do wyszukiwania.", UI.MUTED))
	if station == WORKBENCH and _state.get("recipes", []).any(func(recipe: Dictionary) -> bool: return recipe.get("locked") != null):
		_recipes.add_child(UI.label("Więcej przepisów odblokujesz przy stole badawczym.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	UI.clear(_details)
	var selected := _recipe(_selected)
	if not selected.is_empty():
		var title := UI.label(selected["name"], UI.GOLD)
		title.add_theme_font_override("font", UI.bold())
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(UI.item_icon(_selected, 40))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		_details.add_child(head)
		var about := ItemInfo.description(_selected)
		if about != "":
			_details.add_child(UI.label(about, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		_details.add_child(UI.label("Potrzebne (wymagane/masz):", UI.MUTED))
		for ingredient: Dictionary in selected["ingredients"]:
			var need := int(ingredient["quantity"])
			var have := _count(ingredient["id"])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.add_child(UI.item_icon(ingredient["id"], 26))
			var name_label := UI.label(ingredient["name"])
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			row.add_child(UI.label("%d/%d" % [need, have], UI.GOOD if have >= need else UI.ERROR, HORIZONTAL_ALIGNMENT_RIGHT))
			_details.add_child(row)
		_details.add_child(UI.label("Czas: %s  ·  %d XP" % [_seconds(float(selected["seconds"])), int(selected["xp"])], UI.MUTED))
		if _selected == "nails":
			_details.add_child(UI.label("Gwoździe kupisz też u handlarza na rynku.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		elif _selected.begins_with("tool_"):
			_details.add_child(UI.label("Narzędzia kupisz też u handlarza na rynku po 100 $.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	var queue: Array = _state.get("queue", [])
	var full := queue.size() >= int(_state.get("maxQueue", 5))
	_craft_button.disabled = selected.is_empty() or not _can_make(selected) or full or _busy
	_craft_button.text = "Kolejka pełna" if full else "Wytwórz"

	UI.clear(_queue)
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
