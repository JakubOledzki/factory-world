class_name MarketWindow
extends GameWindow
## The market: the NPC trader (sells trash, saplings, animals and the sorting machine, quick sale at the floor
## price) and trading between players (listings, buy orders and the player's own offers).
## The trader's prices change: a little from day to day, and a lot during events like a drought.
## It covers most of the screen: categories on the left and a search field filter every tab.
## The garage opens it anywhere; on a plot it opens at a computer standing there.
## What the player hasn't researched yet the server leaves out of every tab.

## A trade went through; the garage or the plot reloads the inventory and shows the new balance.
signal traded(balance_cents: int, item: String)
signal failed(reply: Dictionary)
## The player asked to put the computer the window was opened at back into the inventory.
signal pick_up_requested(id: String)

const TABS := ["Handlarz", "Gracze", "Moje oferty"]
const MAX_QUANTITY := 10000
var _tab := 0
var _tab_buttons: Array[Button] = []
var _page := VBoxContainer.new()
## The item whose offers the "Gracze" tab shows, or "" for the list of all items.
var _item := ""
## The chosen category (index in ItemInfo.CATEGORIES), or -1 for all; kept when switching tabs.
var _category := -1
var _categories := CategoryList.new()
var _list := ScrollContainer.new()
var _search := UI.line_edit("Szukaj przedmiotu…")
var _pick_up_button: Button
## The computer on a plot the window was opened at, or "" in the garage.
var computer := ""
## Two columns of items when they fit; with the bigger letters on phones one.
var _columns := 1 if UI.touch() else 2

## From the garage: the player's inventory stacks and balance.
var _items: Array = []
var _balance := 0
## From the server: NPC prices, every item with the best offers, one item's board, own offers.
var _prices: Array = []
## The trader's event now and the next one coming, or null; their times are the server's.
var _event = null
var _next = null
## Server time minus this computer's, in milliseconds.
var _clock_offset := 0
var _overview: Array = []
var _board := {}
var _mine := {}
## A request for the open tab is on its way; `_again` asks for one more once it is answered.
var _loading := false
var _again := false


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
	var hint := UI.label("" if UI.touch() else "Ctrl + mysz na przedmiocie: opis", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(hint)
	_search.custom_minimum_size.x = 260
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search)
	top.add_child(_search)
	_pick_up_button = UI.button("Schowaj komputer", func() -> void: pick_up_requested.emit(computer))
	_pick_up_button.tooltip_text = "Schowaj komputer do ekwipunku"
	_pick_up_button.visible = false
	top.add_child(_pick_up_button)
	content.add_child(top)

	# Categories on the left, the open tab's items on the right; each list scrolls on its own.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	_categories.chosen.connect(_choose_category)
	body.add_child(_categories)
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


## Opens the market at a computer on a plot, with a button to put the computer away.
func open_at(id: String) -> void:
	computer = id
	_pick_up_button.visible = true
	show_window()


## The garage or the plot calls this whenever the inventory or the balance changes.
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


## Draws the open tab at once from what came last, then fetches it again and draws it anew.
## One request at a time: clicking through tabs faster than the server answers only asks once
## more for whatever is open when the answer comes, instead of piling up requests.
func _reload() -> void:
	if _tab == 0 or _has_cached():
		_render()
	if _loading:
		_again = true
		return
	_loading = true
	var reply := await _fetch()
	while _again:
		_again = false
		reply = await _fetch()
	_loading = false
	if reply["type"] == "error":
		failed.emit(reply)
		return
	_render()


## Asks the server for what the open tab shows and keeps it.
func _fetch() -> Dictionary:
	var reply: Dictionary
	if _tab == 0:
		# Prices change with time, so the trader asks for them every time it opens.
		reply = await Net.request("market.prices")
		if reply["type"] == "market.prices":
			var payload: Dictionary = reply["payload"]
			_prices = payload["items"]
			_event = payload.get("event")
			_next = payload.get("next")
			_clock_offset = int(payload["serverTime"]) - int(Time.get_unix_time_from_system() * 1000)
	elif _tab == 1 and _item != "":
		reply = await Net.request("market.item", {"item": _item})
		if reply["type"] == "market.item":
			_board = reply["payload"]
	elif _tab == 1:
		reply = await Net.request("market.overview")
		if reply["type"] == "market.overview":
			# Items that have offers first, the rest in the server's order.
			var items: Array = reply["payload"]["items"]
			_overview = items.filter(_has_offers) + items.filter(func(e: Dictionary) -> bool: return not _has_offers(e))
	else:
		reply = await Net.request("market.mine")
		if reply["type"] == "market.mine":
			_mine = reply["payload"]
	return reply


## Whether the open tab has something from an earlier answer to show while it loads.
func _has_cached() -> bool:
	match _tab:
		1: return _board.get("item", "") == _item if _item != "" else not _overview.is_empty()
		2: return not _mine.is_empty()
	return true


func _render() -> void:
	UI.clear(_page)
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

## Every category with how many of the open tab's items (matching the search) it holds.
func _render_categories() -> void:
	var items := []
	for entry: Dictionary in _tab_entries():
		if _matches_search(entry["name"]):
			items.append(entry["id"])
	_categories.show_counts(CategoryList.count(items), _category)


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
	for i in ItemInfo.CATEGORIES.size():
		groups.append([])
	for entry: Dictionary in entries:
		var category := ItemInfo.category_of(entry[key])
		if (_category == -1 or category == _category) and _matches_search(entry["name"]):
			groups[category].append(entry)
	var added := 0
	for i in ItemInfo.CATEGORIES.size():
		if groups[i].is_empty():
			continue
		if _category == -1:
			_page.add_child(_category_heading(ItemInfo.CATEGORIES[i][0]))
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
	_render_event()
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
	var row := _item_row(item, price["name"], "cena %s%s" % [UI.money(cents), _change(price.get("buyChange"))], UI.GOLD)
	for amount: int in ([1] if item.begins_with("furniture_") else [1, 10]):
		var b := UI.button("Kup %d" % amount, _send.bind("market.buy", {"item": item, "quantity": amount}, item, "market.traded"))
		b.disabled = _balance < cents * amount
		row.add_child(b)
	return row


func _quick_sale_row(price: Dictionary) -> Control:
	var item: String = price["id"]
	var owned := _count(item)
	var row := _item_row(item, "%s  ×%d" % [price["name"], owned], "skup %s%s" % [UI.money(int(price["sellCents"])), _change(price.get("sellChange"))], UI.GOOD)
	row.add_child(UI.button("Sprzedaj 1", _send.bind("market.sell", {"item": item, "quantity": 1}, item, "market.traded")))
	row.add_child(UI.button("Wszystko", _send.bind("market.sell", {"item": item, "quantity": mini(owned, 1000)}, item, "market.traded")))
	return row


## What is going on at the market now, what it changes, and what comes next.
func _render_event() -> void:
	if _event != null:
		_page.add_child(_heading("Wydarzenie: %s" % _event["name"]))
		_page.add_child(UI.label("Jeszcze %s." % _duration(int(_event["endsAtMs"])), UI.MUTED))
		_page.add_child(_note(_event["description"]))
		var effects := []
		for effect: Dictionary in _event["effects"]:
			if effect.get("sellChange") != null:
				effects.append("%s: skup %s" % [effect["name"], _percent(effect["sellChange"])])
			if effect.get("buyChange") != null:
				effects.append("%s: cena %s" % [effect["name"], _percent(effect["buyChange"])])
		_page.add_child(_note(", ".join(effects) + "."))
	else:
		_page.add_child(_heading("Na rynku spokojnie"))
		_page.add_child(_note("Ceny handlarza zmieniają się trochę z dnia na dzień. Co kilka godzin zdarza się wydarzenie, które mocno zmienia ceny niektórych towarów."))
	if _next != null:
		_page.add_child(_note("Następne wydarzenie: %s, za %s. %s" % [_next["name"], _duration(int(_next["startsAtMs"])), _next["description"]]))


## How far a price is from the usual one, like "  (+12%)", or "" when it is the usual price.
func _change(percent) -> String:
	if percent == null or int(percent) == 0:
		return ""
	return "  (%s)" % _percent(percent)


## A change in percent with its sign, like "+12%" or "-25%".
func _percent(percent) -> String:
	return "%s%d%%" % ["+" if int(percent) > 0 else "-", absi(int(percent))]


## The time from now until `at_ms` on the server's clock, like "2 godz. 15 min".
func _duration(at_ms: int) -> String:
	var minutes := maxi(1, ceili((at_ms - _clock_offset - Time.get_unix_time_from_system() * 1000) / 60000.0))
	if minutes < 60:
		return "%d min" % minutes
	if minutes % 60 == 0:
		return "%d godz." % (minutes / 60)
	return "%d godz. %d min" % [minutes / 60, minutes % 60]


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
	# The screen reloads the inventory, then calls refresh().
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
