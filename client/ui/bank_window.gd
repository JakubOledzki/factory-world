class_name BankWindow
extends GameWindow
## Banks of companies: a bank stands in a town and has branches in others. The player opens an account in any of them, pays
## money in from the wallet, takes it out and sends it to other players' accounts. Money travels: paying in or out takes as
## long as an export train between the player's nearest plot (their own or their company's) and the bank's nearest building;
## between accounts of one bank it takes a minute, to another bank six hours. What is on its way shows with a countdown.

signal balance_changed
signal failed(reply: Dictionary)

## How often (ms) the window asks again while it is open.
const POLL := 5000.0
const BANK := "furniture_bank"
const KINDS := {"deposit": "Wpłata", "withdraw": "Wypłata", "transfer": "Przelew"}

var _state := {}
var _clock_offset := 0.0
## The bank whose page shows; "" for the first one.
var _bank := ""
var _about: Label
var _accounts := VBoxContainer.new()
var _picker: OptionButton
var _page := VBoxContainer.new()
var _on_way := VBoxContainer.new()
var _amount: SpinBox
var _recipient: LineEdit
var _target: OptionButton
var _sent: SpinBox
var _times: Array = []
var _transfers := -1


func _init() -> void:
	super("Banki", 520)
	poll_every = POLL
	_about = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_about)
	content.add_child(HSeparator.new())
	_accounts.add_theme_constant_override("separation", 4)
	content.add_child(_accounts)
	content.add_child(HSeparator.new())
	_picker = OptionButton.new()
	_picker.clip_text = true
	_picker.item_selected.connect(func(index: int) -> void:
		_bank = _picker.get_item_metadata(index)
		_render())
	content.add_child(_picker)
	_page.add_theme_constant_override("separation", 6)
	content.add_child(_page)
	content.add_child(HSeparator.new())
	_on_way.add_theme_constant_override("separation", 4)
	content.add_child(_on_way)
	_amount = _spin()
	_sent = _spin()
	_recipient = UI.line_edit("Nick odbiorcy")
	_recipient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target = OptionButton.new()
	_target.clip_text = true
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Opens on the page of one bank, e.g. after clicking its building.
func open_bank(bank: String) -> void:
	_bank = bank
	show_window()


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	_apply(await fetch("bank.get"))


func server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "bank":
		failed.emit(reply)
		return false
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	# Fewer transfers on the way than last time: some got there, perhaps into the wallet.
	var count := (_state["transfers"] as Array).size()
	if _transfers >= 0 and count < _transfers:
		balance_changed.emit()
	_transfers = count
	_render()
	return true


func _render() -> void:
	if _state.is_empty():
		return
	var rates: Dictionary = _state["rates"]
	var banks: Array = _state["banks"]
	_about.text = ("Pieniądze w banku nie jadą od razu: wpłata i wypłata idą tyle, ile pociąg z twojej najbliższej działki (własnej albo spółki) " +
		"do najbliższego budynku banku, %s min na działkę lądem i 3 razy wolniej promem. Przelew w tym samym banku trwa %s, " +
		"do innego banku %s, a bez działki wpłata i wypłata trwają %s.") % [str(rates["minutesPerPlot"]).replace(".", ","),
		_duration(int(rates["sameBankSeconds"])), _duration(int(rates["otherBankSeconds"])), _duration(int(rates["noPlotSeconds"]))]
	if _state["companyBanks"]:
		_about.text += "\nTwoja spółka zbadała bankowość: postaw bank (5 × 5) na działce spółki w mieście, a oddziały (3 × 3) w innych miastach."

	UI.clear(_accounts)
	_accounts.add_child(UI.label("Twoje konta", UI.GOLD))
	var any := false
	for bank: Dictionary in banks:
		if bank["balanceCents"] == null:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var title := UI.label(bank["name"])
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.clip_text = true
		row.add_child(title)
		row.add_child(UI.label(_money(int(bank["balanceCents"])), UI.GOLD))
		var open := UI.button("Otwórz", func() -> void:
			_bank = bank["id"]
			_render())
		row.add_child(open)
		_accounts.add_child(row)
	if not any:
		_accounts.add_child(UI.label("Nie masz jeszcze konta w żadnym banku." if not banks.is_empty() else
			"Żaden bank jeszcze nie działa. Spółka, która zbada „Bankowość”, postawi bank w mieście.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	_picker.clear()
	_picker.visible = not banks.is_empty()
	var selected: Dictionary = {}
	for bank: Dictionary in banks:
		_picker.add_item("%s · %d %s" % [bank["name"], (bank["buildings"] as Array).size(), "budynek" if (bank["buildings"] as Array).size() == 1 else "budynki"])
		_picker.set_item_metadata(_picker.item_count - 1, bank["id"])
		if bank["id"] == _bank or selected.is_empty():
			selected = bank
	if not selected.is_empty():
		_bank = selected["id"]
		for i in _picker.item_count:
			if _picker.get_item_metadata(i) == _bank:
				_picker.select(i)
	_render_page(selected)
	_render_on_way()
	_fit.call_deferred()


func _render_page(bank: Dictionary) -> void:
	# The fields stay from one render to the next, keeping what the player typed; the rows they stood in go.
	for field: Control in [_amount, _recipient, _target, _sent]:
		if field.get_parent() != null:
			field.get_parent().remove_child(field)
	UI.clear(_page)
	if bank.is_empty():
		return
	var places: Array[String] = []
	for building: Dictionary in bank["buildings"]:
		places.append(("%s (bank)" if building["kind"] == BANK else "%s") % building["town"])
	_page.add_child(UI.label("%s%s. Klientów: %d." % ["Twoja spółka · " if bank["mine"] else "",
		("Budynki: " + ", ".join(places)) if not places.is_empty() else "Bank nie ma dziś żadnego budynku: wpłaty i wypłaty idą pocztą",
		int(bank["customers"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_page.add_child(UI.label(_trip_text(bank["trip"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if bank["balanceCents"] == null:
		var open := UI.button("Otwórz konto", func() -> void: _send("bank.open", {"bank": bank["id"]}), true)
		open.disabled = (bank["buildings"] as Array).is_empty()
		_page.add_child(open)
		return

	_page.add_child(UI.label("Na koncie: %s" % _money(int(bank["balanceCents"])), UI.GOLD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_reparent(_amount, row)
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(UI.button("Wpłać", func() -> void: _send("bank.deposit", {"bank": bank["id"], "cents": _cents(_amount)}), true))
	row.add_child(UI.button("Wypłać", func() -> void: _send("bank.withdraw", {"bank": bank["id"], "cents": _cents(_amount)})))
	_page.add_child(row)

	_page.add_child(UI.label("Przelew na konto innego gracza", UI.GOLD))
	var to := HBoxContainer.new()
	to.add_theme_constant_override("separation", 6)
	_reparent(_recipient, to)
	var target_before: String = _target.get_item_metadata(_target.selected) if _target.selected >= 0 else str(bank["id"])
	_target.clear()
	for other: Dictionary in _state["banks"]:
		_target.add_item(other["name"])
		_target.set_item_metadata(_target.item_count - 1, other["id"])
		if other["id"] == target_before:
			_target.select(_target.item_count - 1)
	_target.tooltip_text = "Bank, w którym odbiorca ma konto"
	_reparent(_target, to)
	_page.add_child(to)
	var send := HBoxContainer.new()
	send.add_theme_constant_override("separation", 6)
	_reparent(_sent, send)
	_sent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send.add_child(UI.button("Wyślij", func() -> void:
		_send("bank.transfer", {"bank": bank["id"], "to": _recipient.text.strip_edges(),
			"toBank": _target.get_item_metadata(_target.selected), "cents": _cents(_sent)}), true))
	_page.add_child(send)
	var close := UI.button("Zamknij konto", func() -> void: _send("bank.close", {"bank": bank["id"]}))
	close.tooltip_text = "Tylko puste konto, do którego nic nie jest w drodze"
	_page.add_child(close)


func _render_on_way() -> void:
	_times.clear()
	UI.clear(_on_way)
	_on_way.add_child(UI.label("W drodze", UI.GOLD))
	var transfers: Array = _state["transfers"]
	if transfers.is_empty():
		_on_way.add_child(UI.label("Żadne pieniądze nie są w drodze.", UI.MUTED))
	for t: Dictionary in transfers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var text := UI.label(_transfer_text(t), UI.GOOD if t["incoming"] else UI.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.clip_text = true
		text.tooltip_text = text.text
		row.add_child(text)
		var left := UI.label("", UI.MUTED)
		left.custom_minimum_size.x = 72
		left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(left)
		_on_way.add_child(row)
		_times.append([left, float(t["arrivesAt"])])
	_update_times()


func _transfer_text(t: Dictionary) -> String:
	var cents := _money(int(t["cents"]))
	match t["kind"]:
		"deposit":
			return "%s · %s → konto w %s" % [KINDS["deposit"], cents, t["toBank"]]
		"withdraw":
			return "%s · %s z %s → portfel" % [KINDS["withdraw"], cents, t["fromBank"]]
	if t["incoming"]:
		return "Przelew od %s · %s → %s" % [t["from"], cents, t["toBank"]]
	return "Przelew do %s · %s → %s" % [t["to"], cents, t["toBank"]]


func _trip_text(trip: Dictionary) -> String:
	var time := _duration(int(trip["seconds"]))
	if trip["fromX"] == null:
		return "Wpłata i wypłata: %s." % time
	var text := "Wpłata i wypłata: %s, z działki %d × %d do budynku w %s (%s lądem" % [time, int(trip["fromX"]), int(trip["fromY"]), trip["town"],
		_plots(float(trip["landPlots"]))]
	if float(trip["seaPlots"]) > 0.0:
		text += ", %s promem" % _plots(float(trip["seaPlots"]))
	return text + ")."


func _send(type: String, payload: Dictionary) -> void:
	if _apply(await Net.request(type, payload)):
		balance_changed.emit()


func _update_times() -> void:
	var now := server_now()
	for entry: Array in _times:
		var label: Label = entry[0]
		if is_instance_valid(label):
			var seconds := ceili(maxf(entry[1] - now, 0.0) / 1000.0)
			label.text = _clock(seconds) if seconds > 0 else "dociera…"


func _process(delta: float) -> void:
	super(delta)
	if visible and not _times.is_empty():
		_update_times()


## Puts a field kept between renders into a new row.
func _reparent(control: Control, parent: Control) -> void:
	if control.get_parent() != null:
		control.get_parent().remove_child(control)
	parent.add_child(control)


func _spin() -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0.01
	spin.max_value = 1_000_000_000_000
	spin.step = 0.01
	spin.value = 100
	spin.suffix = "$"
	spin.custom_minimum_size.x = 140
	spin.select_all_on_focus = true
	return spin


static func _cents(spin: SpinBox) -> int:
	return roundi(spin.value * 100.0)


static func _plots(plots: float) -> String:
	return "%s dz." % str(snappedf(plots, 0.1)).replace(".", ",")


static func _duration(seconds: int) -> String:
	if seconds < 3600:
		return "%d min" % ceili(seconds / 60.0) if seconds % 60 == 0 or seconds >= 600 else "%d min %02d s" % [seconds / 60, seconds % 60]
	return "%d h" % (seconds / 3600) if seconds % 3600 == 0 else "%d h %02d min" % [seconds / 3600, (seconds % 3600) / 60]


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## An amount that never breaks between the number and the dollar sign.
func _money(cents: int) -> String:
	return UI.money(cents).replace(" ", " ")
