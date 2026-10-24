class_name MarketWindow
extends GameWindow
## The market: the NPC trader (sells trash, saplings and the sorting machine, quick sale at the floor
## price) and trading between players (listings, buy orders and the player's own offers).
## It covers most of the screen: categories on the left and a search field filter every tab.

## A trade went through; the garage reloads the inventory and shows the new balance.
signal traded(balance_cents: int, item: String)
signal failed(reply: Dictionary)

const TABS := ["Handlarz", "Gracze", "Moje oferty"]
const MAX_QUANTITY := 10000
## Categories in the order they are shown: name, items, and id patterns for the rest, so a new
## ore, tool, belt or decoration finds its place on its own. Listed items win over patterns.
const CATEGORIES := [
	["Rośliny i nasiona", ["sapling", "wheat", "carrot", "cabbage", "corn", "potato", "sunflower"], []],
	["Drewno i kamień", ["wood", "stone", "sand"], []],
	["Rudy i węgiel", ["coal"], ["*_ore"]],
	["Sztabki i materiały", ["nails"], ["*_ingot"]],
	["Jedzenie", ["flour", "corn_flour", "sunflower_oil", "sauerkraut", "bread", "corn_bread",
			"carrot_cake", "fries", "vegetable_soup", "bigos"], []],
	["Maszyny", ["furniture_workbench", "furniture_furnace", "furniture_sorting_machine", "furniture_mill",
			"furniture_oil_press", "furniture_pickling_barrel", "furniture_bakery", "furniture_kitchen"], []],
	["Logistyka i magazyny", [], ["logistics_*", "storage_*"]],
	["Narzędzia", [], ["tool_*"]],
	["Wyposażenie", [], ["furniture_*"]],
	["Odpady i złom", ["trash"], ["waste_*"]],
	["Inne", [], ["*"]],
]

var _tab := 0
var _tab_buttons: Array[Button] = []
var _page := VBoxContainer.new()
## The item whose offers the "Gracze" tab shows, or "" for the list of all items.
var _item := ""
## The chosen category (index in CATEGORIES), or -1 for all; kept when switching tabs.
var _category := -1
var _category_list := VBoxContainer.new()
var _list := ScrollContainer.new()
var _search := UI.line_edit("Szukaj przedmiotu…")
## Two columns of items when they fit; with the bigger letters on phones one.
var _columns := 1 if UI.touch() else 2

## From the garage: the player's inventory stacks and balance.
var _items: Array = []
var _balance := 0
## From the server: NPC prices, every item with the best offers, one item's board, own offers.
var _prices: Array = []
var _overview: Array = []
var _board := {}
var _mine := {}


func _init() -> void:
	super("Rynek", 0)
	fill_margin = Vector2(40, 24)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _open_tab.bind(i))
		b.custom_minimum_size.x = 150
		top.add_child(b)
		_tab_buttons.append(b)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_search.custom_minimum_size.x = 260
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search)
	top.add_child(_search)
	content.add_child(top)

	# Categories on the left, the open tab's items on the right; each list scrolls on its own.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var side := ScrollContainer.new()
	side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.custom_minimum_size.x = 270 if UI.touch() else 200
	_category_list.add_theme_constant_override("separation", 3)
	_category_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_category_list)
	body.add_child(side)
	body.add_child(VSeparator.new())
	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 4)
	# Room on the right, so the scroll bar does not cover the buttons.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_page)
	_list.add_child(margin)
	body.add_child(_list)


func show_window() -> void:
	super()
	_open_tab(_tab)


## The garage calls this whenever the inventory or the balance changes.
func set_player(items: Array, balance: int) -> void:
	_items = items
	_balance = balance
	if visible and _tab == 0:
		_render()


func set_prices(prices: Array) -> void:
	_prices = prices


func _open_tab(tab: int) -> void:
	if tab != _tab:
		_item = ""
		_list.scroll_vertical = 0
	_tab = tab
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == tab else ""
	await _reload()


## Fetches what the open tab shows again, e.g. after a trade.
func refresh() -> void:
	if visible:
		await _reload()


## Fetches what the open tab shows, then draws it.
func _reload() -> void:
	var reply: Dictionary
	if _tab == 1 and _item != "":
		reply = await Net.request("market.item", {"item": _item})
		if reply["type"] == "market.item":
			_board = reply["payload"]
	elif _tab == 1:
		reply = await Net.request("market.overview")
		if reply["type"] == "market.overview":
			# Items that have offers first, the rest in the server's order.
			var items: Array = reply["payload"]["items"]
			_overview = items.filter(_has_offers) + items.filter(func(e: Dictionary) -> bool: return not _has_offers(e))
	elif _tab == 2:
		reply = await Net.request("market.mine")
		if reply["type"] == "market.mine":
			_mine = reply["payload"]
	else:
		reply = {"type": "ok"}
	if reply["type"] == "error":
		failed.emit(reply)
		return
	_render()


func _render() -> void:
	for child in _page.get_children():
		child.free()
	_render_categories()
	match _tab:
		0: _render_trader()
		1:
			if _item != "":
				_render_board()
			else:
				_render_overview()
		2: _render_mine()


# --- Categories ------------------------------------------------------------------------------

## The index in CATEGORIES of the category an item belongs to.
static func category_of(item: String) -> int:
	for i in CATEGORIES.size():
		if item in CATEGORIES[i][1]:
			return i
	for i in CATEGORIES.size():
		for pattern: String in CATEGORIES[i][2]:
			if item.match(pattern):
				return i
	return CATEGORIES.size() - 1


## "Wszystko" and every category with how many of the open tab's items it holds; empty ones are
## dimmed, "Inne" shows only when something falls into it.
func _render_categories() -> void:
	for child in _category_list.get_children():
		child.free()
	var counts := []
	counts.resize(CATEGORIES.size())
	counts.fill(0)
	var total := 0
	for entry: Dictionary in _tab_entries():
		if _matches_search(entry["name"]):
			counts[category_of(entry["id"])] += 1
			total += 1
	_category_list.add_child(_category_button("Wszystko", total, -1))
	for i in CATEGORIES.size():
		if i == CATEGORIES.size() - 1 and counts[i] == 0 and _category != i:
			continue
		var b := _category_button(CATEGORIES[i][0], counts[i], i)
		b.disabled = counts[i] == 0 and _category != i
		_category_list.add_child(b)


func _category_button(text: String, count: int, category: int) -> Button:
	var b := UI.button("%s  (%d)" % [text, count], _choose_category.bind(category), category == _category)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b


func _choose_category(category: int) -> void:
	_category = category
	_list.scroll_vertical = 0
	if _item != "":
		await _back()
	else:
		_render()


## Typing a search on one item's offers goes back to the list it searches.
func _on_search(_text: String) -> void:
	_list.scroll_vertical = 0
	if _item != "":
		await _back()
	else:
		_render()


func _matches_search(item_name: String) -> bool:
	var query := _search.text.strip_edges().to_lower()
	return query == "" or item_name.to_lower().contains(query)


## Every item the open tab lists, as {id, name}, for the counts next to the categories.
func _tab_entries() -> Array:
	var entries := {}
	match _tab:
		0:
			for price: Dictionary in _prices:
				if price.get("buyCents") != null or (price.get("sellCents") != null and _count(price["id"]) > 0):
					entries[price["id"]] = price["name"]
		1:
			for entry: Dictionary in _overview:
				entries[entry["id"]] = entry["name"]
		2:
			for part: String in ["listings", "orders"]:
				for offer: Dictionary in _mine.get(part, []):
					entries[offer["item"]] = offer["name"]
	return entries.keys().map(func(id: String) -> Dictionary: return {"id": id, "name": entries[id]})


## Adds a row for every entry in the chosen category that matches the search, in `columns`
## columns; with all categories shown, under a heading per category. `key` names the entry's item
## id. Returns how many rows were added.
func _add_items(entries: Array, key: String, make_row: Callable, columns := _columns) -> int:
	var groups := []
	for i in CATEGORIES.size():
		groups.append([])
	for entry: Dictionary in entries:
		var category := category_of(entry[key])
		if (_category == -1 or category == _category) and _matches_search(entry["name"]):
			groups[category].append(entry)
	var added := 0
	for i in CATEGORIES.size():
		if groups[i].is_empty():
			continue
		if _category == -1:
			_page.add_child(_category_heading(CATEGORIES[i][0]))
		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		for entry: Dictionary in groups[i]:
			var row: Control = make_row.call(entry)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(row)
			added += 1
		_page.add_child(grid)
	return added


## What to say when a section has nothing: why, depending on whether a filter hides things.
func _nothing(text: String) -> Label:
	if _category != -1 or _search.text.strip_edges() != "":
		return _note("Nic takiego w wybranej kategorii lub wyszukiwaniu.")
	return _note(text)


# --- Trader ------------------------------------------------------------------------------

func _render_trader() -> void:
	_page.add_child(_heading("Handlarz sprzedaje"))
	var sold := _prices.filter(func(price: Dictionary) -> bool: return price.get("buyCents") != null)
	if _add_items(sold, "id", _trader_row) == 0:
		_page.add_child(_nothing("Handlarz nic teraz nie sprzedaje."))

	_page.add_child(_heading("Szybka sprzedaż"))
	_page.add_child(_note("Handlarz płaci od razu, ale najniższą cenę. Więcej dostaniesz, wystawiając ogłoszenie w zakładce Gracze."))
	var bought := _prices.filter(func(price: Dictionary) -> bool:
		return price.get("sellCents") != null and _count(price["id"]) > 0)
	if _add_items(bought, "id", _quick_sale_row) == 0:
		_page.add_child(_nothing("Nie masz nic, co skupuje handlarz."))


func _trader_row(price: Dictionary) -> Control:
	var item: String = price["id"]
	var cents := int(price["buyCents"])
	var row := _item_row(item, price["name"], "cena %s" % UI.money(cents), UI.GOLD)
	for amount: int in ([1] if item.begins_with("furniture_") else [1, 10]):
		var b := UI.button("Kup %d" % amount, _send.bind("market.buy", {"item": item, "quantity": amount}, item, "market.traded"))
		b.disabled = _balance < cents * amount
		row.add_child(b)
	return row


func _quick_sale_row(price: Dictionary) -> Control:
	var item: String = price["id"]
	var owned := _count(item)
	var row := _item_row(item, "%s  ×%d" % [price["name"], owned], "skup %s" % UI.money(int(price["sellCents"])), UI.GOOD)
	row.add_child(UI.button("Sprzedaj 1", _send.bind("market.sell", {"item": item, "quantity": 1}, item, "market.traded")))
	row.add_child(UI.button("Wszystko", _send.bind("market.sell", {"item": item, "quantity": mini(owned, 1000)}, item, "market.traded")))
	return row


# --- Players ------------------------------------------------------------------------------

func _render_overview() -> void:
	_page.add_child(_note("Kliknij przedmiot, aby zobaczyć oferty graczy, kupić, sprzedać albo wystawić własną ofertę."))
	if _add_items(_overview, "id", _overview_row) == 0:
		_page.add_child(_nothing("Na rynku nie ma jeszcze przedmiotów."))


func _overview_row(entry: Dictionary) -> Control:
	var item: String = entry["id"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var name_label := UI.label(entry["name"])
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var offers := VBoxContainer.new()
	offers.add_theme_constant_override("separation", -4)
	offers.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if entry.get("lowestCents") != null:
		offers.add_child(UI.label("od %s (%d szt.)" % [UI.money(int(entry["lowestCents"])), int(entry["listed"])], UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
	if entry.get("highestCents") != null:
		offers.add_child(UI.label("skup do %s (%d szt.)" % [UI.money(int(entry["highestCents"])), int(entry["wanted"])], UI.GOOD, HORIZONTAL_ALIGNMENT_RIGHT))
	if offers.get_child_count() == 0:
		offers.add_child(UI.label("brak ofert", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(offers)
	var open := UI.button("›", _open_item.bind(item))
	open.tooltip_text = "Oferty"
	row.add_child(open)
	return row


func _has_offers(entry: Dictionary) -> bool:
	return int(entry["listed"]) > 0 or int(entry["wanted"]) > 0


func _open_item(item: String) -> void:
	_item = item
	await _reload()


func _back() -> void:
	_item = ""
	await _reload()


func _render_board() -> void:
	var item: String = _board.get("item", _item)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	top.add_child(UI.button("‹ Wszystkie", _back))
	top.add_child(UI.item_icon(item, 30))
	var title := UI.label(_board.get("name", item))
	title.add_theme_font_override("font", UI.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(UI.label("masz %d" % _count(item), UI.MUTED))
	_page.add_child(top)

	var listings: Array = _board.get("listings", [])
	var orders: Array = _board.get("orders", [])
	var floor := _quick_sale(item)

	_page.add_child(_heading("Sprzedają"))
	if listings.is_empty():
		_page.add_child(_note("Nikt tego teraz nie sprzedaje."))
	for offer: Dictionary in listings:
		var cents := int(offer["priceCents"])
		_page.add_child(_offer_row(offer, "Kup", "market.purchase",
				mini(int(offer["quantity"]), _balance / cents), item))

	_page.add_child(_heading("Kupują (zlecenia)"))
	if orders.is_empty():
		_page.add_child(_note("Nikt tego teraz nie zamawia."))
	for offer: Dictionary in orders:
		_page.add_child(_offer_row(offer, "Sprzedaj", "market.fill",
				mini(int(offer["quantity"]), _count(item)), item))

	var sell_price := int(listings[0]["priceCents"]) if not listings.is_empty() else maxi(floor * 2, 100)
	var buy_price := int(orders[0]["priceCents"]) if not orders.is_empty() else maxi(floor, 100)
	_page.add_child(_heading("Wystaw na sprzedaż"))
	if _count(item) < 1:
		_page.add_child(_note("Nie masz tego przedmiotu."))
	else:
		_page.add_child(_offer_form("market.list", "Wystaw", item, _count(item), sell_price))
	_page.add_child(_heading("Zleć kupno"))
	_page.add_child(_note("Pieniądze odkładamy od razu; gracz, który dostarczy towar, dostaje zapłatę, a towar trafia do twojego ekwipunku."))
	_page.add_child(_offer_form("market.order", "Zleć", item, MAX_QUANTITY, buy_price))


## One offer of another player: who, how many, price, and a quantity to take with a button.
func _offer_row(offer: Dictionary, action: String, type: String, can_take: int, item: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var who := UI.label(("Ty" if offer["mine"] else offer["owner"]) + "  ×%d" % int(offer["quantity"]))
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(who)
	row.add_child(UI.label("%s/szt." % UI.money(int(offer["priceCents"])), UI.GOLD))
	if offer["mine"]:
		row.add_child(UI.label("twoja", UI.MUTED))
		return row
	var amount := _spin(1, maxi(can_take, 1), maxi(can_take, 1))
	row.add_child(amount)
	var b := UI.button(action, func() -> void:
		_send(type, {"id": int(offer["id"]), "quantity": int(amount.value)}, item))
	b.disabled = can_take < 1
	row.add_child(b)
	return row


## Quantity and price per piece for a new listing or buy order, with the total.
func _offer_form(type: String, action: String, item: String, max_quantity: int, price_cents: int) -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.label("Ilość", UI.MUTED))
	var quantity := _spin(1, mini(max_quantity, MAX_QUANTITY), mini(max_quantity, 10) if type == "market.list" else 1)
	row.add_child(quantity)
	row.add_child(UI.label("Cena/szt.", UI.MUTED))
	var price := SpinBox.new()
	price.min_value = 0.01
	price.max_value = 1000000
	price.step = 0.01
	price.value = price_cents / 100.0
	price.suffix = "$"
	price.custom_minimum_size.x = 110
	price.select_all_on_focus = true
	row.add_child(price)
	var submit := UI.button(action, func() -> void:
		_send(type, {"item": item, "quantity": int(quantity.value), "priceCents": roundi(price.value * 100)}, item), true)
	row.add_child(submit)
	box.add_child(row)
	var total := UI.label("", UI.MUTED)
	var update := func(_v: float = 0) -> void:
		var cents := int(quantity.value) * roundi(price.value * 100)
		total.text = "Razem: %s" % UI.money(cents)
		if type == "market.order":
			submit.disabled = cents > _balance
			if submit.disabled:
				total.text += " (nie masz tyle)"
	quantity.value_changed.connect(update)
	price.value_changed.connect(update)
	update.call()
	box.add_child(total)
	return box


# --- Own offers ------------------------------------------------------------------------------

func _render_mine() -> void:
	for part: Array in [["listings", "Moje ogłoszenia sprzedaży", "sprzedano", "market.unlist"],
			["orders", "Moje zlecenia kupna", "dostarczono", "market.cancelOrder"]]:
		_page.add_child(_heading(part[1]))
		if _add_items(_mine.get(part[0], []), "item", _mine_row.bind(part), 1) == 0:
			_page.add_child(_nothing("Brak. Ofertę wystawisz w zakładce Gracze, przy przedmiocie."))


func _mine_row(offer: Dictionary, part: Array) -> Control:
	var item: String = offer["item"]
	var done := int(offer["done"])
	var quantity := int(offer["quantity"])
	var state := "%s %d z %d" % [part[2], done, quantity]
	if not offer["open"]:
		state += ", zakończone" if done == quantity else ", anulowane"
	var row := _item_row(item, "%s  %s/szt." % [offer["name"], UI.money(int(offer["priceCents"]))], state,
			UI.GOOD if done > 0 else UI.MUTED)
	if offer["open"]:
		var cancel := UI.button("Anuluj", _send.bind(part[3], {"id": int(offer["id"])}, item))
		cancel.tooltip_text = "Niesprzedane przedmioty wrócą do ekwipunku." if part[0] == "listings" else "Niewydane pieniądze wrócą do portfela."
		row.add_child(cancel)
	return row


# --- Helpers ---------------------------------------------------------------------------------

func _send(type: String, payload: Dictionary, item: String, expected := "market.done") -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != expected:
		failed.emit(reply)
		await _reload()
		return
	# The garage reloads the inventory, then calls refresh().
	traded.emit(int(reply["payload"]["balanceCents"]), item)


func _item_row(item: String, title: String, detail: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UI.label(title)
	name_label.add_theme_font_override("font", UI.bold())
	text.add_child(name_label)
	text.add_child(UI.label(detail, color))
	row.add_child(text)
	return row


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l


## A category's name over its items, when all categories are shown.
func _category_heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := UI.label(text.to_upper(), UI.MUTED)
	l.add_theme_font_override("font", UI.bold())
	box.add_child(l)
	box.add_child(HSeparator.new())
	return box


func _note(text: String) -> Label:
	var l := UI.label(text, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.custom_minimum_size.x = 380
	return l


func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size.x = 76
	spin.select_all_on_focus = true
	return spin


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _quick_sale(item: String) -> int:
	for price: Dictionary in _prices:
		if price["id"] == item and price.get("sellCents") != null:
			return int(price["sellCents"])
	return 0
