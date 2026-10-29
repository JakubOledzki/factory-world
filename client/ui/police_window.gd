class_name PoliceWindow
extends GameWindow
## The police of the countries players govern. "Prawo" shows the player's country's laws, their licences, cases and bans, and
## lets them report a player or ask to join the police; the government appoints the chief and sets what is banned. "Służba" is the
## officer's desk: trains that crossed the border, reports, cases to sentence, investigations and search warrants, and for the chief
## the officers. "Sąd" is for the president and the minister of justice: appeals and warrants. "Paser" is the fence of the underworld.

signal balance_changed
signal inventory_changed
signal failed(reply: Dictionary)

## How often (ms) the window asks again while it is open.
const POLL := 8000.0
const TABS := ["Prawo", "Służba", "Sąd", "Paser"]
const RANKS := ["Kadet", "Posterunkowy", "Detektyw", "Komendant"]
const CRIMES := {"smuggling": "Przemyt", "contraband": "Zakazane towary", "logging": "Nielegalna wycinka",
	"black_market": "Czarny rynek", "bribe": "Łapówka"}
const STATUS := {"open": "Otwarta", "sentenced": "Wyrok", "dismissed": "Umorzona", "appealed": "Odwołanie",
	"upheld": "Wyrok utrzymany", "overturned": "Wyrok uchylony"}
const SANCTIONS := {"trade": "Zakaz handlu", "travel": "Zakaz przekraczania granic", "wanted": "List gończy"}

var _state := {}
var _fence := {}
var _tab := 0
var _clock_offset := 0.0
var _tabs := HBoxContainer.new()
var _page := VBoxContainer.new()
## What the last inspection or search found, shown on the officer's desk.
var _finding := ""
## The case whose sentence form is open, or -1.
var _sentencing := -1


func _init() -> void:
	super("Policja", 560)
	poll_every = POLL
	_tabs.add_theme_constant_override("separation", 4)
	content.add_child(_tabs)
	content.add_child(HSeparator.new())
	_page.add_theme_constant_override("separation", 6)
	content.add_child(_page)


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	if _tab == 3:
		_apply_fence(await fetch("fence.get"))
	else:
		_apply(await fetch("law.get"))


func _now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "law":
		failed.emit(reply)
		return false
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	if int(_state["paidCents"]) > 0:
		balance_changed.emit()
	_render()
	return true


func _apply_fence(reply: Dictionary) -> bool:
	if reply["type"] != "fence":
		failed.emit(reply)
		return false
	_fence = reply["payload"]
	_render()
	return true


## Sends a law message; most answer with the whole window again.
func _send(type: String, payload: Dictionary = {}, money := false) -> void:
	var reply: Dictionary = await Net.request(type, payload)
	match reply["type"]:
		"law":
			_apply(reply)
		"law.found":
			_finding = _found_text(reply["payload"])
			_apply(await Net.request("law.get"))
		"law.investigated":
			var opened: Array = reply["payload"]["cases"]
			_finding = "Śledztwo: nic nie wyszło na jaw." if opened.is_empty() else "Śledztwo otworzyło sprawy: %d." % opened.size()
			_apply(await Net.request("law.get"))
		"law.reported":
			_finding = "Zgłoszenie trafiło na policję."
			_apply(await Net.request("law.get"))
		"law.bribed":
			balance_changed.emit()
			_apply(await Net.request("law.get"))
		"fence":
			_apply_fence(reply)
			inventory_changed.emit()
		_:
			failed.emit(reply)
			return
	if money:
		balance_changed.emit()


func _render() -> void:
	UI.clear(_tabs)
	for i in TABS.size():
		var index := i
		var b := UI.button(TABS[i], func() -> void:
			_tab = index
			_render()
			refresh(), i == _tab)
		_tabs.add_child(b)
	UI.clear(_page)
	if _state.is_empty() and _tab != 3:
		return
	match _tab:
		0:
			_render_law()
		1:
			_render_duty()
		2:
			_render_court()
		3:
			_render_fence()
	_fit.call_deferred()


func _heading(text: String) -> void:
	_page.add_child(UI.label(text, UI.GOLD))


func _note(text: String, color := UI.MUTED) -> void:
	_page.add_child(UI.label(text, color, HORIZONTAL_ALIGNMENT_LEFT, true))


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for child: Control in children:
		row.add_child(child)
	_page.add_child(row)
	return row


func _grow(control: Control) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control


func _render_law() -> void:
	var country: Variant = _state["country"]
	if country == null:
		_note("Nie jesteś obywatelem żadnego kraju. Kraj, jego prawa i policja pojawią się, gdy zostaniesz obywatelem (okno polityki).")
	else:
		_note("Obywatelstwo: %s%s" % [country, "" if _state["hasGovernment"] else " · kraj nie ma jeszcze rządu, więc nie ma też policji ani ceł"], UI.TEXT)
	var laws: Dictionary = _state["laws"]
	_heading("Prawo twojego kraju")
	var banned: Array = laws["banned"]
	var licensed: Array = laws["licensed"]
	_note("Zakazane: " + (", ".join(banned.map(func(r: Dictionary) -> String: return str(r["name"]))) if not banned.is_empty() else "nic"))
	if licensed.is_empty():
		_note("Na licencję: nic")
	for rule: Dictionary in licensed:
		var buy := UI.button("Kup licencję", func() -> void: _send("law.buyLicence", {"country": country, "item": rule["item"]}, true))
		buy.tooltip_text = "Licencja na tydzień; opłata trafia do skarbca kraju"
		_row([_grow(UI.label("Na licencję: %s · %s / tydzień" % [rule["name"], UI.money(int(rule["feeCents"]))])), buy])
	_note("Lasy chronione: wycinka bez certyfikatu leśnego jest nielegalna." if laws["forestProtection"] else "Lasy nie są chronione.")
	_note("Przemyt: pociąg przez granicę z zaznaczonym „przemytem” nie płaci cła i może wieźć zakazane towary, ale celnicy łapią część takich " +
		"pociągów, a policja może je skontrolować przez 48 godzin.")

	if _state["mayAppointChief"]:
		_render_government()

	var licences: Array = _state["licences"]
	if not licences.is_empty():
		_heading("Twoje licencje")
		for l: Dictionary in licences:
			_note("%s (%s) do %s" % [l["name"], l["country"], _date(float(l["untilMs"]))], UI.TEXT)
	var sanctions: Array = _state["sanctions"]
	if not sanctions.is_empty():
		_heading("Twoje kary")
		for s: Dictionary in sanctions:
			_note("%s (%s) do %s" % [SANCTIONS.get(s["kind"], s["kind"]), s["country"], _date(float(s["untilMs"]))], UI.ERROR)
	var cases: Array = _state["cases"]
	_heading("Sprawy przeciw tobie")
	if cases.is_empty():
		_note("Czysta kartoteka.")
	for c: Dictionary in cases:
		var line := _grow(UI.label(_case_text(c), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		var children: Array = [line]
		if c["appealUntilMs"] != null and float(c["appealUntilMs"]) > _now():
			var appeal := UI.button("Odwołaj się", func() -> void: _send("law.appeal", {"id": c["id"]}))
			appeal.tooltip_text = "Sąd (minister sprawiedliwości albo prezydent) utrzyma wyrok albo go uchyli i odda grzywnę"
			children.append(appeal)
		_row(children)

	_heading("Zgłoś gracza")
	var who := UI.line_edit("Nick")
	var what := UI.line_edit("Co się stało (do 200 znaków)")
	what.max_length = 200
	_row([who, _grow(what), UI.button("Zgłoś", func() -> void: _send("law.report", {"name": who.text.strip_edges(), "text": what.text.strip_edges()}))])

	_heading("Służba w policji")
	var police: Variant = _state["police"]
	if police != null:
		_note("Służysz jako %s. Biurko jest w zakładce „Służba”." % RANKS[int(police["rank"])].to_lower(), UI.GOOD)
		_row([UI.button("Odejdź z policji", func() -> void: _send("law.resign"))])
	elif _state["applied"] != null:
		_note("Twoje podanie czeka na komendanta.")
		_row([UI.button("Wycofaj podanie", func() -> void: _send("law.resign"))])
	else:
		var rules: Dictionary = _state["rules"]
		_note("Policja przyjmuje obywateli od poziomu %d bez wyroku w ostatnim tygodniu. Pensja ze skarbca kraju: %s." % [int(rules["protectedBelowLevel"]),
			" · ".join((rules["ranks"] as Array).map(func(r: Dictionary) -> String: return "%s %s/dzień" % [RANKS[int(r["rank"])], UI.money(int(r["salaryCents"]))]))])
		_row([UI.button("Złóż podanie", func() -> void: _send("law.apply"), true)])


func _render_government() -> void:
	_heading("Rząd: policja i zakazy")
	var chief := UI.line_edit("Nick obywatela")
	_row([_grow(chief), UI.button("Mianuj komendanta", func() -> void: _send("law.appointChief", {"name": chief.text.strip_edges()}))])
	var laws: Dictionary = _state["laws"]
	var banned := UI.line_edit("Zakazane towary, po przecinku (np. Dynamit, Ruda uranu)")
	banned.text = ", ".join((laws["banned"] as Array).map(func(r: Dictionary) -> String: return str(r["name"])))
	_page.add_child(banned)
	var licensed := UI.line_edit("Na licencję: Nazwa = cena $, po przecinku")
	licensed.text = ", ".join((laws["licensed"] as Array).map(func(r: Dictionary) -> String: return "%s = %s" % [r["name"], str(int(r["feeCents"]) / 100)]))
	_page.add_child(licensed)
	var forests := CheckBox.new()
	forests.text = "Chroń lasy (wycinka tylko z certyfikatem leśnym)"
	forests.button_pressed = laws["forestProtection"]
	_page.add_child(forests)
	_row([UI.button("Zapisz prawo", func() -> void:
		var licences := []
		for part in licensed.text.split(",", false):
			var pair := part.split("=")
			licences.append({"item": _item_id(pair[0]), "feeCents": roundi(float(pair[1].strip_edges()) * 100.0) if pair.size() > 1 else 0})
		_send("law.setLaws", {"banned": Array(banned.text.split(",", false)).map(_item_id), "licensed": licences,
			"forestProtection": forests.button_pressed}), true)])


## The id of an item the player typed by its Polish name (or its id).
func _item_id(text: String) -> String:
	var wanted := text.strip_edges().to_lower()
	for id: String in ItemInfo.ITEMS:
		if id == wanted or str(ItemInfo.ITEMS[id][0]).to_lower() == wanted:
			return id
	return wanted


func _render_duty() -> void:
	var police: Variant = _state["police"]
	if police == null:
		_note("Nie służysz w policji. Podanie złożysz w zakładce „Prawo”.")
		return
	var rank := int(police["rank"])
	_note("%s · %s · pensja %s/dzień · kontrole dziś: %d%s" % [police["country"], RANKS[rank], UI.money(int(police["salaryCents"])),
		int(police["inspectionsLeft"]), (" · śledztwa: %d" % int(police["investigationsLeft"])) if rank >= 2 else ""], UI.TEXT)
	if _finding != "":
		_note(_finding, UI.GOOD)

	_heading("Pociągi na granicy (48 h)")
	var crossings: Array = police["crossings"]
	if crossings.is_empty():
		_note("Żaden pociąg nie wjechał ostatnio do kraju.")
	for c: Dictionary in crossings:
		var goods: Variant = c["goods"]
		var text := "%s · %s → %s · %s · %d szt." % [c["owner"], c["from"], c["to"], _date(float(c["atMs"])), int(c["pieces"])]
		if c["declared"]:
			text += " · zgłoszony, cło %s" % UI.money(int(c["dutyCents"]))
		else:
			text += " · niezgłoszony"
		if goods != null:
			text += " · " + _goods_text(goods)
		var children: Array = [_grow(UI.label(text, UI.TEXT if c["declared"] else UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))]
		if not c["inspected"] and not c["mine"] and not c["declared"]:
			children.append(UI.button("Kontroluj", func() -> void: _send("law.inspect", {"id": c["id"]})))
		_row(children)

	_heading("Sprawy")
	var cases: Array = police["cases"]
	if cases.is_empty():
		_note("Nie ma otwartych spraw.")
	for c: Dictionary in cases:
		var children: Array = [_grow(UI.label(_case_text(c, true), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))]
		if c["status"] == "open" and rank >= 1:
			children.append(UI.button("Wyrok", func() -> void:
				_sentencing = int(c["id"])
				_render()))
			children.append(UI.button("Umorz", func() -> void: _send("law.dismiss", {"id": c["id"]})))
		_row(children)
		if _sentencing == int(c["id"]) and c["status"] == "open":
			_render_sentence(c)

	_heading("Zgłoszenia")
	var reports: Array = police["reports"]
	if reports.is_empty():
		_note("Brak zgłoszeń.")
	for r: Dictionary in reports:
		var children: Array = [_grow(UI.label("%s zgłasza %s: %s" % [r["reporter"], r["suspect"], r["text"]], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))]
		if rank >= 2:
			children.append(UI.button("Śledztwo", func() -> void: _send("law.investigate", {"name": r["suspect"]})))
		children.append(UI.button("Zamknij", func() -> void: _send("law.closeReport", {"id": r["id"]})))
		_row(children)

	if rank >= 2:
		_heading("Śledztwo i nakazy")
		var suspect := UI.line_edit("Nick podejrzanego albo policjanta")
		_row([_grow(suspect), UI.button("Wszczęj śledztwo", func() -> void: _send("law.investigate", {"name": suspect.text.strip_edges()}))])
		var x := _spin(0, 9999, 1)
		var y := _spin(0, 9999, 1)
		_row([UI.label("Działka"), x, y, UI.button("Poproś o nakaz", func() -> void: _send("law.requestWarrant", {"x": int(x.value), "y": int(y.value)}))])
		for w: Dictionary in police["warrants"]:
			var children: Array = [_grow(UI.label("Nakaz na działkę %d × %d (%s)%s" % [int(w["x"]), int(w["y"]), w["requestedBy"],
				"" if w["granted"] else " · czeka na sąd"]))]
			if w["granted"]:
				children.append(UI.button("Przeszukaj", func() -> void: _send("law.search", {"id": w["id"]}), true))
			_row(children)

	var wanted: Array = police["wanted"]
	if not wanted.is_empty():
		_heading("List gończy")
		_note(", ".join(wanted.map(func(w: Dictionary) -> String: return str(w["name"]))), UI.ERROR)

	_heading("Funkcjonariusze")
	for o: Dictionary in police["officers"]:
		var children: Array = [_grow(UI.label("%s · %s" % [o["name"], RANKS[int(o["rank"])]], UI.GOOD if o["me"] else UI.TEXT))]
		if rank == 3 and not o["me"]:
			var pick := OptionButton.new()
			for i in 3:
				pick.add_item(RANKS[i])
			pick.select(mini(int(o["rank"]), 2))
			pick.item_selected.connect(func(index: int) -> void: _send("law.setRank", {"name": o["name"], "rank": index}))
			children.append(pick)
			children.append(UI.button("Zwolnij", func() -> void: _send("law.fire", {"name": o["name"]})))
		_row(children)
	for a: Dictionary in police["applications"]:
		_row([_grow(UI.label("Podanie: %s" % a["name"], UI.GOLD)),
			UI.button("Przyjmij", func() -> void: _send("law.hire", {"name": a["name"], "yes": true}), true),
			UI.button("Odrzuć", func() -> void: _send("law.hire", {"name": a["name"], "yes": false}))])


func _render_sentence(c: Dictionary) -> void:
	var rules: Dictionary = _state["rules"]
	var fine := _spin(0, float(c["maxFineCents"]) / 100.0, 0.01)
	fine.suffix = "$"
	fine.value = float(c["maxFineCents"]) / 200.0
	var trade := _spin(0, float(rules["maxBanHours"]), 1)
	var travel := _spin(0, float(rules["maxBanHours"]), 1)
	var wanted := _spin(0, float(rules["maxWantedHours"]), 1)
	for s: SpinBox in [trade, travel, wanted]:
		s.suffix = "h"
	_row([UI.label("Grzywna (do %s)" % UI.money(int(c["maxFineCents"]))), _grow(fine)])
	_row([UI.label("Zakaz handlu"), trade, UI.label("granic"), travel, UI.label("list gończy"), wanted])
	var seize := CheckBox.new()
	seize.text = "Zabierz znalezione towary"
	seize.button_pressed = c["seizable"]
	seize.visible = c["seizable"]
	_row([seize, UI.button("Ogłoś wyrok", func() -> void:
		_sentencing = -1
		_send("law.sentence", {"id": c["id"], "fineCents": roundi(fine.value * 100.0), "tradeBanHours": int(trade.value),
			"travelBanHours": int(travel.value), "wantedHours": int(wanted.value), "seize": seize.button_pressed}), true)])


func _render_court() -> void:
	var court: Variant = _state["court"]
	if court == null:
		_note("Sąd to prezydent i minister sprawiedliwości. Rozpatrują odwołania od wyroków i wydają nakazy przeszukania.")
		return
	_heading("Odwołania")
	if (court["appeals"] as Array).is_empty():
		_note("Nie ma odwołań.")
	for c: Dictionary in court["appeals"]:
		_row([_grow(UI.label(_case_text(c, true), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)),
			UI.button("Utrzymaj", func() -> void: _send("law.judge", {"id": c["id"], "yes": true})),
			UI.button("Uchyl", func() -> void: _send("law.judge", {"id": c["id"], "yes": false}))])
	_heading("Wnioski o nakaz przeszukania")
	if (court["warrants"] as Array).is_empty():
		_note("Nie ma wniosków.")
	for w: Dictionary in court["warrants"]:
		_row([_grow(UI.label("Działka %d × %d · prosi %s" % [int(w["x"]), int(w["y"]), w["requestedBy"]])),
			UI.button("Wydaj", func() -> void: _send("law.decideWarrant", {"id": w["id"], "yes": true}), true),
			UI.button("Odmów", func() -> void: _send("law.decideWarrant", {"id": w["id"], "yes": false}))])


func _render_fence() -> void:
	_note("Paser płaci więcej niż handlarz za materiały wybuchowe, uran, skamieliny i to, czego zakazuje twój kraj. Każda transakcja zostawia " +
		"ślad, który detektyw może znaleźć. Paser handluje z graczami od poziomu %s." % str(_fence.get("level", 5)))
	if _fence.is_empty():
		return
	for item: Dictionary in _fence["items"]:
		var quantity := _spin(1, maxf(1.0, float(item["have"])), 1)
		var trader: Variant = item["traderCents"]
		var sell := UI.button("Sprzedaj", func() -> void: _send("fence.sell", {"item": item["id"], "quantity": int(quantity.value)}, true))
		sell.disabled = int(item["have"]) == 0
		_row([UI.item_icon(item["id"], 28), _grow(UI.label("%s · %s/szt.%s · masz %d" % [item["name"], UI.money(int(item["priceCents"])),
			(" (handlarz %s)" % UI.money(int(trader))) if trader != null else "", int(item["have"])])), quantity, sell])
	_heading("Skrytka w wagonach")
	if _fence["compartment"]:
		_note("Twoje pociągi mają skrytkę: celnicy łapią je dwa razy rzadziej, a towar w niej znajdzie tylko detektyw.", UI.GOOD)
	else:
		_row([_grow(UI.label("Skrytka dla wszystkich twoich pociągów: %s" % UI.money(int(_fence["compartmentCents"])), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)),
			UI.button("Kup", func() -> void: _send("fence.compartment", {}, true))])
	_heading("Prezent dla policjanta")
	var who := UI.line_edit("Nick policjanta")
	var cents := _spin(1, 1_000_000, 1)
	cents.suffix = "$"
	cents.value = 100
	var give := UI.button("Daj", func() -> void: _send("law.bribe", {"name": who.text.strip_edges(), "cents": roundi(cents.value * 100.0)}, true))
	give.tooltip_text = "Pieniądze idą od razu. To łapówka: wydział wewnętrzny może ją wykryć, a sprawa obejmie was obu."
	_row([_grow(who), cents, give])


func _case_text(c: Dictionary, with_suspect := false) -> String:
	var text := "#%d %s%s · %s" % [int(c["id"]), CRIMES.get(c["kind"], c["kind"]), (" · " + str(c["suspect"])) if with_suspect else "",
		STATUS.get(c["status"], c["status"])]
	if c["status"] in ["sentenced", "appealed", "upheld", "overturned"]:
		text += " · grzywna %s" % UI.money(int(c["collectedCents"]))
		for pair: Array in [["tradeBanHours", "bez handlu"], ["travelBanHours", "bez granic"], ["wantedHours", "list gończy"]]:
			if int(c[pair[0]]) > 0:
				text += " · %s %d h" % [pair[1], int(c[pair[0]])]
	text += "\n" + str(c["detail"])
	return text


func _found_text(found: Dictionary) -> String:
	if found["caseId"] != null:
		return "Znaleziono u %s: %s. Otwarto sprawę #%d." % [found["suspect"], _goods_text(found["forbidden"]), int(found["caseId"])]
	if found["protected"]:
		return "%s jest poniżej poziomu %d: nowych graczy się nie ściga." % [found["suspect"], int(_state["rules"]["protectedBelowLevel"])]
	if (found["goods"] as Array).is_empty():
		return "Kontrola u %s: nic podejrzanego." % found["suspect"]
	return "Kontrola u %s: %s. Wszystko w porządku." % [found["suspect"], _goods_text(found["goods"])]


static func _goods_text(goods: Array) -> String:
	return ", ".join(goods.map(func(g: Dictionary) -> String: return "%d × %s" % [int(g["quantity"]), g["name"]]))


static func _date(ms: float) -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))
	return "%02d.%02d %02d:%02d" % [t["day"], t["month"], t["hour"], t["minute"]]


static func _spin(low: float, high: float, step: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.custom_minimum_size.x = 90
	spin.select_all_on_focus = true
	return spin
