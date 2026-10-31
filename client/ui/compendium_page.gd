class_name CompendiumPage
extends VBoxContainer
## The "Kompendium" tab of the character window: every item of the game by the categories of
## ItemInfo, and for the chosen one what it is for and where it comes from (ItemInfo), and,
## read from the server's own lists ("compendium.get"), which stations make it and of what, what
## it goes into, whether it burns or feeds a canteen, what research it still needs and what the
## trader asks and pays. So a new item or recipe shows up here without touching this file.

const LIST_HEIGHT := 420
## An ingot goes into hundreds of recipes: this many show at first, the rest on a click.
const USES_SHOWN := 20

var _search := UI.line_edit("Szukaj przedmiotu…")
var _categories := CategoryList.new()
var _list := ScrollContainer.new()
var _rows := VBoxContainer.new()
var _detail_scroll := ScrollContainer.new()
var _details := VBoxContainer.new()
var _status := UI.label("Wczytuję kompendium…", UI.MUTED)
var _category := -1
var _selected := ""
var _selected_button: Button
## Whether the chosen item shows every recipe it goes into, not just the first USES_SHOWN.
var _all_uses := false
var _loading := false

## From the server: names by id (in the server's order), recipes by the item they make and by
## each ingredient, fuels, canteen portions, locked items, and the trader's prices by id.
var _names := {}
## How many pieces of each item fill a tile of the inventory.
var _stacks := {}
var _made_by := {}
var _used_in := {}
var _fuels := {}
var _furnace_coal := {}
var _canteen := {}
var _locked := {}
var _prices := {}
## The production calculator: pieces a minute wanted of the selected item, and where its answer goes.
var _calc_rate := 0.0
var _calc_box := VBoxContainer.new()


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var intro := UI.label("Wszystko, co da się zdobyć, wytworzyć albo kupić: do czego służy, skąd się bierze i do czego się przydaje.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	intro.add_theme_font_size_override("font_size", 13)
	intro.custom_minimum_size.x = 300
	add_child(intro)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void:
		_list.scroll_vertical = 0
		_render_list())
	add_child(_search)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	var height := 0 if UI.touch() else LIST_HEIGHT
	_categories.custom_minimum_size.y = height
	_categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_categories.chosen.connect(func(category: int) -> void:
		_category = category
		_list.scroll_vertical = 0
		_render_list())
	body.add_child(_categories)
	body.add_child(VSeparator.new())

	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.custom_minimum_size = Vector2(300 if UI.touch() else 240, height)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_rows)
	_list.add_child(margin)
	body.add_child(_list)
	body.add_child(VSeparator.new())

	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_scroll.custom_minimum_size.y = height
	_detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation", 4)
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_margin := MarginContainer.new()
	detail_margin.add_theme_constant_override("margin_right", 14)
	detail_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_margin.add_child(_details)
	_detail_scroll.add_child(detail_margin)
	body.add_child(_detail_scroll)
	_details.add_child(_status)


## Asks the server again: research unlocks items and the trader's prices change during the day.
func refresh() -> void:
	if _loading:
		return
	_loading = true
	var reply := await Net.request("compendium.get")
	var prices := await Net.request("market.prices")
	_loading = false
	if reply["type"] != "compendium":
		if _names.is_empty():
			_status.text = Game.error_text(reply)
		return
	_read(reply["payload"])
	_prices.clear()
	if prices["type"] == "market.prices":
		for price: Dictionary in prices["payload"]["items"]:
			_prices[price["id"]] = price
	if _selected == "" and not _names.is_empty():
		_selected = _names.keys()[0]
	_render_list()
	_render_details()


func _read(payload: Dictionary) -> void:
	_names.clear()
	_stacks.clear()
	for item: Dictionary in payload.get("items", []):
		_names[item["id"]] = item["name"]
		_stacks[item["id"]] = int(item.get("stack", 0))
	_made_by.clear()
	_used_in.clear()
	for recipe: Dictionary in payload.get("recipes", []):
		_add(_made_by, recipe["id"], recipe)
		for extra: Dictionary in recipe.get("extras", []):
			_add(_made_by, extra["id"], recipe)
		var seen := {}
		for ingredient: Dictionary in recipe.get("ingredients", []):
			if not seen.has(ingredient["id"]):
				seen[ingredient["id"]] = true
				_add(_used_in, ingredient["id"], recipe)
	_fuels = payload.get("fuels", {})
	_furnace_coal = payload.get("furnaceCoal", {})
	_canteen = payload.get("canteen", {})
	_locked = payload.get("locked", {})


static func _add(into: Dictionary, item: String, recipe: Dictionary) -> void:
	if not into.has(item):
		into[item] = []
	into[item].append(recipe)


func _name(item: String) -> String:
	return _names.get(item, ItemInfo.name_of(item))


func _matches(item: String, query: String) -> bool:
	return query == "" or _name(item).to_lower().contains(query) or ItemInfo.description(item).to_lower().contains(query)


func _render_list() -> void:
	UI.clear(_rows)
	var query := _search.text.strip_edges().to_lower()
	var found: Array = _names.keys().filter(func(item: String) -> bool: return _matches(item, query))
	_categories.show_counts(CategoryList.count(found), _category, true)
	var groups := {}
	for item: String in found:
		var category := ItemInfo.category_of(item)
		if _category != -1 and category != _category:
			continue
		if not groups.has(category):
			groups[category] = []
		groups[category].append(item)
	var order := groups.keys()
	order.sort()
	for category: int in order:
		if _category == -1:
			var heading := UI.label(ItemInfo.CATEGORIES[category][0].to_upper(), UI.MUTED)
			heading.add_theme_font_override("font", UI.bold())
			_rows.add_child(heading)
		for item: String in groups[category]:
			_rows.add_child(_item_button(item))
	if found.is_empty() and not _names.is_empty():
		_rows.add_child(UI.label("Nic nie pasuje do wyszukiwania.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


func _item_button(item: String) -> Button:
	var b := Button.new()
	b.set_meta("item", item)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = _name(item)
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.icon = UI.item_texture(item)
	b.add_theme_constant_override("icon_max_width", 26)
	if item == _selected:
		b.theme_type_variation = "AccentButton"
		_selected_button = b
	elif _locked.has(item):
		b.modulate = Color(1, 1, 1, 0.6)
	b.pressed.connect(_select.bind(item))
	return b


## Shows `item`; from a link in the details, the list follows to its category.
func _select(item: String, follow := false) -> void:
	if item != _selected:
		_calc_rate = 0.0
	_selected = item
	_all_uses = false
	if follow and _category != -1:
		_category = ItemInfo.category_of(item)
	_render_list()
	_render_details()
	_detail_scroll.scroll_vertical = 0
	if follow:
		# Once the list is laid out, so its button has a place to scroll to.
		await get_tree().process_frame
		if is_instance_valid(_selected_button):
			_list.ensure_control_visible(_selected_button)


func _render_details() -> void:
	# The calculator's box is kept, not freed with the rest.
	if _calc_box.get_parent():
		_calc_box.get_parent().remove_child(_calc_box)
	UI.clear(_details)
	var item := _selected
	if item == "":
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UI.item_icon(item, 56))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.label(_name(item), UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_font_size_override("font_size", 19)
	titles.add_child(title)
	titles.add_child(UI.label(ItemInfo.CATEGORIES[ItemInfo.category_of(item)][0], UI.MUTED))
	if int(_stacks.get(item, 0)) > 0:
		titles.add_child(UI.label("Stos: %d szt. na kafelek ekwipunku" % int(_stacks[item]), UI.MUTED))
	head.add_child(titles)
	_details.add_child(head)
	if _locked.has(item):
		_details.add_child(_text("Wymaga badania: %s (stół badawczy)." % _locked[item], UI.ERROR))

	var about := ItemInfo.description(item)
	if about != "":
		_section("Do czego służy")
		_details.add_child(_text(about))
	var source := ItemInfo.source(item)
	if source != "":
		_section("Skąd się bierze")
		_details.add_child(_text(source))

	var made: Array = _made_by.get(item, [])
	if not made.is_empty():
		_section("Gdzie się wytwarza")
		for recipe: Dictionary in made:
			_details.add_child(_recipe_row(recipe, item))
		_calculator(item)
	var uses: Array = _used_in.get(item, [])
	if not uses.is_empty():
		_section("Do czego się przydaje (%d)" % uses.size())
		var shown := uses.size() if _all_uses else mini(uses.size(), USES_SHOWN)
		for i in shown:
			_details.add_child(_recipe_row(uses[i], item))
		if shown < uses.size():
			_details.add_child(UI.button("Pokaż wszystkie (%d)" % uses.size(), func() -> void:
				_all_uses = true
				var at := _detail_scroll.scroll_vertical
				_render_details()
				_detail_scroll.scroll_vertical = at))
	var other: Array[String] = []
	if _fuels.has(item):
		other.append("Opał w maszynach z paleniskiem: jedna sztuka starcza na %d partii." % int(_fuels[item]))
	if item == "coal" and not _furnace_coal.is_empty():
		var parts: Array[String] = []
		for kind: String in _furnace_coal:
			parts.append("%s %d" % [_name(kind).to_lower(), int(_furnace_coal[kind])])
		other.append("Opał w piecach, przetopień z jednej bryły: %s." % ", ".join(parts))
	if _canteen.has(item):
		other.append("Stołówka zakładowa wydaje z niego %s dla załóg maszyn." % _portions(int(_canteen[item])))
	if not other.is_empty():
		_section("Opał i stołówka")
		for line in other:
			_details.add_child(_text(line))

	var price: Dictionary = _prices.get(item, {})
	_section("Handlarz na rynku")
	var buy: Variant = price.get("buyCents")
	var sell: Variant = price.get("sellCents")
	if buy == null and sell == null:
		_details.add_child(_text("Handlarz tego nie kupuje ani nie sprzedaje." if not _locked.has(item)
				else "Handlarz sprzeda to dopiero po badaniu; wystaw albo kup u innych graczy.", UI.MUTED))
	else:
		if buy != null:
			_details.add_child(_text("Sprzedaje po %s/szt." % UI.money(int(buy))))
		if sell != null:
			_details.add_child(_text("Kupuje po %s/szt." % UI.money(int(sell))))
		_details.add_child(_text("Ceny handlarza zmieniają się w ciągu dnia; między graczami handlujesz na rynku.", UI.MUTED))


## Belt lanes are counted at the plain belt's pace, as on the server.
const BELT_PER_MINUTE := 300.0
## How deep the calculator follows ingredients made from other ingredients.
const PLAN_DEPTH := 8


## How many machines and how much of each raw material a wanted pace of `item` takes, following the first
## recipe of every ingredient down to what is gathered or bought.
func _calculator(item: String) -> void:
	var recipe := _main_recipe(item)
	if recipe.is_empty():
		return
	_section("Kalkulator produkcji")
	if _calc_rate <= 0.0:
		_calc_rate = _per_machine(recipe, item)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_small("Chcę"))
	var rate := SpinBox.new()
	rate.min_value = 0.1
	rate.max_value = 100000
	rate.step = 0.1
	rate.value = snappedf(_calc_rate, 0.1)
	rate.suffix = "szt./min"
	rate.custom_minimum_size.x = 150
	rate.value_changed.connect(func(value: float) -> void:
		_calc_rate = value
		_render_plan(item))
	row.add_child(rate)
	var one := UI.button("1 maszyna", func() -> void: rate.value = snappedf(_per_machine(recipe, item), 0.1))
	row.add_child(one)
	_details.add_child(row)
	_calc_box.add_theme_constant_override("separation", 2)
	_details.add_child(_calc_box)
	_render_plan(item)


func _render_plan(item: String) -> void:
	for child in _calc_box.get_children():
		_calc_box.remove_child(child)
		child.queue_free()
	var steps: Array[Dictionary] = []
	var raw := {}
	_plan(item, _calc_rate, 0, {}, steps, raw)
	var machines := {}
	for step: Dictionary in steps:
		var line := "%s%s %s/min" % ["    ".repeat(step["depth"]), _name(step["item"]), _number(step["rate"])]
		if step.has("station"):
			line += "  ←  %s × %s" % [_number(step["machines"]), _name(step["station"])]
			machines[step["station"]] = machines.get(step["station"], 0.0) + float(step["machines"])
		_calc_box.add_child(_text(line, UI.TEXT if step["depth"] == 0 else UI.MUTED))
	if not machines.is_empty():
		var parts: Array[String] = []
		for station: String in machines:
			parts.append("%d × %s" % [ceili(machines[station] - 0.001), _name(station)])
		_calc_box.add_child(_text("Maszyny razem: " + ", ".join(parts) + ".", UI.GOLD))
	if not raw.is_empty():
		var parts: Array[String] = []
		for r: String in raw:
			parts.append("%s %s/min" % [_name(r), _number(raw[r])])
		_calc_box.add_child(_text("Surowce do dowiezienia: " + ", ".join(parts) + ".", UI.GOLD))
	var lanes := ceili(_calc_rate / BELT_PER_MINUTE - 0.001)
	_calc_box.add_child(_text("Gotowy towar zmieści się na %d %s zwykłej taśmy (%d szt./min na pas). Maszyny liczone na pierwszym poziomie, bez premii."
		% [lanes, "pasie" if lanes == 1 else "pasach", int(BELT_PER_MINUTE)], UI.MUTED))


## Adds the step making `rate` of `item` a minute and, under it, the steps making its ingredients.
func _plan(item: String, rate: float, depth: int, path: Dictionary, steps: Array[Dictionary], raw: Dictionary) -> void:
	var recipe := _main_recipe(item)
	if recipe.is_empty() or depth >= PLAN_DEPTH or path.has(item):
		steps.append({"item": item, "rate": rate, "depth": depth})
		raw[item] = raw.get(item, 0.0) + rate
		return
	var machines := rate / _per_machine(recipe, item)
	steps.append({"item": item, "rate": rate, "depth": depth, "station": recipe["station"], "machines": machines})
	var inner := path.duplicate()
	inner[item] = true
	var runs := machines * 60.0 / float(recipe["seconds"])
	for ingredient: Dictionary in recipe["ingredients"]:
		_plan(ingredient["id"], runs * float(ingredient["quantity"]), depth + 1, inner, steps, raw)


## The recipe that makes `item` as its product (not as a by-product), the first one listed; {} if none.
func _main_recipe(item: String) -> Dictionary:
	for recipe: Dictionary in _made_by.get(item, []):
		if recipe["id"] == item and float(recipe["seconds"]) > 0.0:
			return recipe
	return {}


## Pieces of `item` a minute one machine makes with `recipe`, kept busy.
static func _per_machine(recipe: Dictionary, item: String) -> float:
	var made := float(recipe["quantity"]) if recipe["id"] == item else 0.0
	return made * 60.0 / float(recipe["seconds"])


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return String.num(value, 2 if value < 1.0 else 1).replace(".", ",")


## "1 porcję", "2 porcje", "5 porcji".
static func _portions(n: int) -> String:
	if n == 1:
		return "1 porcję"
	var few := n % 10 in [2, 3, 4] and not n % 100 in [12, 13, 14]
	return "%d %s" % [n, "porcje" if few else "porcji"]


func _section(text: String) -> void:
	_details.add_child(HSeparator.new())
	var heading := UI.label(text, UI.GOLD)
	heading.add_theme_font_override("font", UI.bold())
	_details.add_child(heading)


func _text(text: String, color := UI.TEXT) -> Label:
	var label := UI.label(text, color, HORIZONTAL_ALIGNMENT_LEFT, true)
	label.add_theme_font_size_override("font_size", 14)
	label.custom_minimum_size.x = 240
	return label


## One recipe on a card: the station and its time, then what goes in and what comes out, each an
## icon the player can click to read about.
func _recipe_row(recipe: Dictionary, item: String) -> Control:
	var card := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(1, 1, 1, 0.04)
	frame.set_corner_radius_all(4)
	frame.set_content_margin_all(4)
	card.add_theme_stylebox_override("panel", frame)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 0)
	card.add_child(flow)
	var station: String = recipe["station"]
	flow.add_child(_link(station, 0, item))
	# The assembling machines make the workbench's recipes by themselves.
	if station == "furniture_workbench":
		flow.add_child(_small("/ stacja montażowa"))
	flow.add_child(_small(_seconds(float(recipe["seconds"])) + ":"))
	for ingredient: Dictionary in recipe["ingredients"]:
		flow.add_child(_link(ingredient["id"], int(ingredient["quantity"]), item))
	flow.add_child(UI.label("→", UI.MUTED))
	flow.add_child(_link(recipe["id"], int(recipe["quantity"]), item))
	for extra: Dictionary in recipe.get("extras", []):
		flow.add_child(_link(extra["id"], int(extra["quantity"]), item))
	return card


func _small(text: String) -> Label:
	var label := UI.label(text, UI.MUTED)
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## An item to click through to; `quantity` 0 shows just its name. The shown item itself is not a link.
func _link(item: String, quantity: int, shown: String) -> Button:
	var b := Button.new()
	b.set_meta("item", item)
	b.flat = true
	b.icon = UI.item_texture(item)
	b.add_theme_constant_override("icon_max_width", 22)
	b.text = ("%d × %s" % [quantity, _name(item)]) if quantity > 0 else _name(item)
	b.add_theme_font_size_override("font_size", 13)
	if item == shown:
		b.add_theme_color_override("font_color", UI.GOLD)
		b.add_theme_color_override("font_disabled_color", UI.GOLD)
		b.disabled = true
	else:
		b.tooltip_text = "Pokaż w kompendium"
		b.pressed.connect(_select.bind(item, true))
	return b


func _seconds(seconds: float) -> String:
	if seconds < 10:
		return "%s s" % String.num(seconds, 1).replace(".", ",")
	var s := roundi(seconds)
	return "%d s" % s if s < 60 else "%d min %02d s" % [s / 60, s % 60]
