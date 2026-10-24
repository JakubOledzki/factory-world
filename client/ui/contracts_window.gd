class_name ContractsWindow
extends GameWindow
## Orders with a reward and a deadline: NPC companies give the player orders of their own, and
## players put orders on a board for each other. One tab for what the player delivers, one for the
## board and one for the orders the player gave, with a form for a new one.

## Something changed (pieces delivered, an order taken or given); the garage reloads the inventory.
## `result` is the server's contracts.done payload: balanceCents, completed, rewardCents, xp.
signal changed(result: Dictionary)
signal failed(reply: Dictionary)

const TABS := ["Do dostarczenia", "Tablica zleceń", "Moje zlecenia"]
const STATES := {"open": "czeka na wykonawcę", "taken": "w realizacji", "done": "wykonane",
		"expired": "minął termin", "cancelled": "odwołane", "abandoned": "porzucone"}

var _tab := 0
var _tab_buttons: Array[Button] = []
var _page := VBoxContainer.new()
var _list := ScrollContainer.new()

## From the garage: the player's inventory stacks and balance.
var _items: Array = []
var _balance := 0
## The last contracts.get answer, and server time minus local time in ms.
var _view := {}
var _clock_offset := 0.0
var _loading := false
## Labels that count down to a deadline: [label, deadline ms, text before the time].
var _countdowns: Array = []
var _tick := 0.0
## The fields of the new order form, kept between redraws.
var _new_item := "iron_ingot"
var _new_quantity := 50
var _new_reward := 500.0
var _new_hours := 24


func _init() -> void:
	super("Zlecenia", 0)
	fill_margin = Vector2(80, 32)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _open_tab.bind(i))
		b.custom_minimum_size.x = 170
		top.add_child(b)
		_tab_buttons.append(b)
	content.add_child(top)

	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 6)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_page)
	_list.add_child(margin)
	content.add_child(_list)


func show_window() -> void:
	super()
	_open_tab(_tab)


## The garage calls this whenever the inventory or the balance changes.
func set_player(items: Array, balance: int) -> void:
	_items = items
	_balance = balance
	if visible and not _view.is_empty():
		_render()


## Fetches the orders again, e.g. after a delivery.
func refresh() -> void:
	if visible:
		await _reload()


func _open_tab(tab: int) -> void:
	if tab != _tab:
		_list.scroll_vertical = 0
	_tab = tab
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == tab else ""
	if not _view.is_empty():
		_render()
	await _reload()


func _reload() -> void:
	if _loading:
		return
	_loading = true
	var reply := await Net.request("contracts.get")
	_loading = false
	if reply["type"] != "contracts":
		failed.emit(reply)
		return
	_view = reply["payload"]
	_clock_offset = float(_view["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	_render()


func _process(delta: float) -> void:
	if not visible or _view.is_empty():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var now := _now()
	var due := false
	for countdown: Array in _countdowns:
		var label: Label = countdown[0]
		if is_instance_valid(label):
			label.text = countdown[2] + _left(int(countdown[1]) - now)
		due = due or int(countdown[1]) <= now
	# A deadline passed or the next NPC order is here: the server settles it on the next look.
	if due and not _loading:
		await _reload()


func _render() -> void:
	UI.clear(_page)
	_countdowns.clear()
	match _tab:
		0: _render_delivering()
		1: _render_board()
		2: _render_issued()


# --- Delivering ------------------------------------------------------------------------------

func _render_delivering() -> void:
	_page.add_child(_heading("Zlecenia firm"))
	_page.add_child(_note("Firmy zamawiają u ciebie towar. Dostarczaj z ekwipunku, także po trochu; nagroda i XP przychodzą, gdy oddasz ostatnią sztukę przed terminem."))
	var npc: Array = _view.get("npc", [])
	for contract: Dictionary in npc:
		_page.add_child(_delivery_card(contract))
	if _view.get("nextNpcAt") != null:
		var next := UI.label("", UI.MUTED)
		_page.add_child(next)
		_countdowns.append([next, int(_view["nextNpcAt"]), "Następne zlecenie firmy za "])
		next.text = "Następne zlecenie firmy za " + _left(int(_view["nextNpcAt"]) - _now())

	_page.add_child(_heading("Zlecenia graczy, które realizujesz"))
	var taken: Array = _view.get("taken", [])
	if taken.is_empty():
		_page.add_child(_note("Żadnych. Przyjmiesz zlecenie innego gracza w zakładce Tablica zleceń."))
	for contract: Dictionary in taken:
		_page.add_child(_delivery_card(contract))

	var finished: Array = _view.get("finished", [])
	if not finished.is_empty():
		_page.add_child(_heading("Wykonane w ostatniej dobie"))
		for contract: Dictionary in finished:
			_page.add_child(_summary_row(contract, "%s, +%s" % [_issuer(contract), UI.money(int(contract["rewardCents"]))], UI.GOOD))


## An order the player delivers: what, for whom, how much is done, the reward, time left, and buttons.
func _delivery_card(contract: Dictionary) -> Control:
	var item: String = contract["item"]
	var left := int(contract["quantity"]) - int(contract["delivered"])
	var card := _card(contract, _issuer(contract))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var can_give := mini(_count(item), left)
	var amount := _spin(1, maxi(can_give, 1), maxi(can_give, 1))
	amount.editable = can_give > 0
	buttons.add_child(amount)
	var give := UI.button("Dostarcz", func() -> void:
		_send("contracts.deliver", {"id": int(contract["id"]), "quantity": int(amount.value)}), true)
	give.disabled = can_give < 1
	give.tooltip_text = "Masz %d szt." % _count(item) if can_give > 0 else "Nie masz tego w ekwipunku."
	buttons.add_child(give)
	var quit := UI.button("Zrezygnuj", _send.bind("contracts.abandon", {"id": int(contract["id"])}))
	quit.tooltip_text = "Dostarczone sztuki wrócą do ekwipunku. " + \
			("Nowe zlecenie firmy przyjdzie za 5 minut." if contract["npc"] else "Zlecenie wróci na tablicę.")
	buttons.add_child(quit)
	card.get_child(0).add_child(buttons)
	return card


# --- Board ---------------------------------------------------------------------------------

func _render_board() -> void:
	_page.add_child(_note("Zlecenia innych graczy. Przyjęte zlecenie realizujesz tylko ty, aż do terminu; nagroda jest już odłożona i trafi do ciebie, gdy dostarczysz wszystko. Naraz możesz realizować %d." % int(_view.get("limits", {}).get("maxTaken", 5))))
	var board: Array = _view.get("board", [])
	if board.is_empty():
		_page.add_child(_note("Na tablicy nie ma teraz zleceń. Wystaw własne w zakładce Moje zlecenia."))
	for contract: Dictionary in board:
		var card := _card(contract, _issuer(contract))
		var take := UI.button("Przyjmij", _send.bind("contracts.accept", {"id": int(contract["id"])}), true)
		take.tooltip_text = "Masz %d szt." % _count(contract["item"])
		card.get_child(0).add_child(take)
		_page.add_child(card)


# --- Issued ---------------------------------------------------------------------------------

func _render_issued() -> void:
	_page.add_child(_heading("Nowe zlecenie"))
	_page.add_child(_note("Nagroda schodzi z portfela od razu i czeka w zleceniu. Wykonawca dostaje ją, gdy dostarczy wszystko przed terminem, a towar trafia do twojego ekwipunku. Gdy termin minie, nagroda wraca do ciebie."))
	_page.add_child(_new_form())

	_page.add_child(_heading("Wystawione"))
	var issued: Array = _view.get("issued", [])
	if issued.is_empty():
		_page.add_child(_note("Nie wystawiłeś jeszcze zleceń."))
	for contract: Dictionary in issued:
		var state: String = contract["state"]
		if state in ["open", "taken"]:
			var who := "czeka na wykonawcę" if state == "open" else "realizuje: %s" % contract["contractor"]
			var card := _card(contract, who)
			if state == "open":
				var cancel := UI.button("Odwołaj", _send.bind("contracts.cancel", {"id": int(contract["id"])}))
				cancel.tooltip_text = "Nagroda wróci do portfela."
				card.get_child(0).add_child(cancel)
			_page.add_child(card)
		else:
			var detail: String = STATES.get(state, state)
			if state == "done" and contract.get("contractor") != null:
				detail += ", wykonał(a) %s" % contract["contractor"]
			_page.add_child(_summary_row(contract, detail, UI.GOOD if state == "done" else UI.MUTED))


func _new_form() -> Control:
	var box := VBoxContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picker := OptionButton.new()
	picker.custom_minimum_size.x = 240
	for i in ItemInfo.CATEGORIES.size():
		var ids := ItemInfo.ITEMS.keys().filter(func(id: String) -> bool: return ItemInfo.category_of(id) == i)
		if ids.is_empty():
			continue
		picker.add_separator(ItemInfo.CATEGORIES[i][0])
		for id: String in ids:
			picker.add_icon_item(UI.item_texture(id), ItemInfo.name_of(id))
			picker.set_item_metadata(picker.item_count - 1, id)
			if id == _new_item:
				picker.select(picker.item_count - 1)
	picker.get_popup().max_size = Vector2i(0, 460)
	picker.item_selected.connect(func(index: int) -> void: _new_item = picker.get_item_metadata(index))
	row.add_child(picker)
	row.add_child(UI.label("Ilość", UI.MUTED))
	var limits: Dictionary = _view.get("limits", {})
	var quantity := _spin(1, int(limits.get("maxQuantity", 100000)), _new_quantity)
	quantity.custom_minimum_size.x = 96
	row.add_child(quantity)
	row.add_child(UI.label("Nagroda", UI.MUTED))
	var reward := SpinBox.new()
	reward.min_value = 0.01
	reward.max_value = int(limits.get("maxRewardCents", 1000000000)) / 100.0
	reward.step = 0.01
	reward.value = _new_reward
	reward.suffix = "$"
	reward.custom_minimum_size.x = 120
	reward.select_all_on_focus = true
	row.add_child(reward)
	row.add_child(UI.label("Termin", UI.MUTED))
	var hours := _spin(int(limits.get("minHours", 1)), int(limits.get("maxHours", 168)), _new_hours)
	hours.suffix = "h"
	row.add_child(hours)
	var submit := UI.button("Wystaw", func() -> void:
		_send("contracts.create", {"item": _new_item, "quantity": int(quantity.value),
				"rewardCents": roundi(reward.value * 100), "hours": int(hours.value)}), true)
	row.add_child(submit)
	box.add_child(row)
	var total := UI.label("", UI.MUTED)
	var update := func(_v: float = 0) -> void:
		_new_quantity = int(quantity.value)
		_new_reward = reward.value
		_new_hours = int(hours.value)
		var cents := roundi(reward.value * 100)
		total.text = "%s za sztukę, termin za %s" % [UI.money(cents / maxi(_new_quantity, 1)), _left(_new_hours * 3600000)]
		submit.disabled = cents > _balance
		if submit.disabled:
			total.text += " (nie masz tyle pieniędzy)"
	quantity.value_changed.connect(update)
	reward.value_changed.connect(update)
	hours.value_changed.connect(update)
	update.call()
	box.add_child(total)
	return box


# --- Pieces --------------------------------------------------------------------------------

## A card for an open order: icon, name and amount, who, progress, reward and time left on the
## left; the caller adds buttons to the returned card's row (its first child).
func _card(contract: Dictionary, who: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", get_theme_stylebox("normal", "LineEdit"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(UI.item_icon(contract["item"], 40))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", -2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.label("%s  ×%d" % [contract["name"], int(contract["quantity"])])
	title.add_theme_font_override("font", UI.bold())
	text.add_child(title)
	text.add_child(UI.label(who, UI.MUTED))
	var progress := HBoxContainer.new()
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = int(contract["quantity"])
	bar.value = int(contract["delivered"])
	progress.add_child(bar)
	progress.add_child(UI.label("%d / %d" % [int(contract["delivered"]), int(contract["quantity"])], UI.MUTED))
	text.add_child(progress)
	row.add_child(text)

	var prize := VBoxContainer.new()
	prize.add_theme_constant_override("separation", -2)
	prize.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var money := UI.label(UI.money(int(contract["rewardCents"])), UI.GOLD, HORIZONTAL_ALIGNMENT_RIGHT)
	money.add_theme_font_override("font", UI.bold())
	prize.add_child(money)
	if int(contract.get("xp", 0)) > 0:
		prize.add_child(UI.label("+%d XP" % int(contract["xp"]), UI.GOOD, HORIZONTAL_ALIGNMENT_RIGHT))
	var deadline := int(contract["deadline"])
	var time_left := UI.label("zostało " + _left(deadline - _now()), _deadline_color(deadline), HORIZONTAL_ALIGNMENT_RIGHT)
	_countdowns.append([time_left, deadline, "zostało "])
	prize.add_child(time_left)
	prize.custom_minimum_size.x = 130
	row.add_child(prize)
	return card


## A finished order in one line: icon, name and amount, and how it ended.
func _summary_row(contract: Dictionary, detail: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(contract["item"], 26))
	var title := UI.label("%s  ×%d" % [contract["name"], int(contract["quantity"])])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	row.add_child(UI.label(detail, color))
	return row


func _send(type: String, payload: Dictionary) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "contracts.done":
		failed.emit(reply)
	else:
		changed.emit(reply["payload"])
	await _reload()


func _issuer(contract: Dictionary) -> String:
	return str(contract["issuer"]) if contract["npc"] else "Gracz %s" % contract["issuer"]


func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0 + _clock_offset)


## Time left as "2 d 5 h", "3 h 12 min" or "8 min".
static func _left(ms: int) -> String:
	var minutes := maxi(ms, 0) / 60000
	if minutes >= 24 * 60:
		return "%d d %d h" % [minutes / 1440, minutes % 1440 / 60]
	if minutes >= 60:
		return "%d h %d min" % [minutes / 60, minutes % 60]
	if minutes >= 1:
		return "%d min" % minutes
	return "%d s" % (maxi(ms, 0) / 1000)


## Red when less than an hour is left.
func _deadline_color(deadline: int) -> Color:
	return UI.ERROR if deadline - _now() < 3600000 else UI.TEXT


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l


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
