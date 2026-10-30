class_name CityWindow
extends GameWindow
## The town a city plot belongs to: what it wants today and pays better than the trader for, how it grows from a
## village to a metropolis on what players deliver, the rubbish it pays to have taken away, the services of the
## players' offices, and the town hall, where the townsfolk elect a mayor who sets a tax and one bonus a week: the
## tax goes into the town's treasury, which the mayor spends on buildings, the mayor puts ordinances to the vote,
## candidates stand with a programme and companies back them, and two thirds of the townsfolk recall a mayor.
## Players also compete here: for the title of the chief supplier (who delivered the most last week gets a little more)
## and in the week's tender, a large order that goes to the lowest sealed bid.

signal inventory_changed
signal balance_changed
signal failed(reply: Dictionary)
signal toast(text: String)

const TABS := ["Potrzeby", "Przetarg", "Rozwój", "Wysypisko", "Usługi", "Ratusz", "Wybory", "Kasa"]
## Tabs only a city plot has: the town buys, takes rubbish and sells services in the city; the rest of its county
## (the countryside it governs) has the town hall, the election, the treasury and the tender.
const CITY_TABS := [0, 3, 4]
## Where the window opens on a plot of the county outside the city: the town hall.
const HALL_TAB := 5

var plot := Vector2i(-1, -1)

var _state := {}
var _tab := 0
var _tab_buttons: Array[Button] = []
var _header: Label
var _body := VBoxContainer.new()


func _init() -> void:
	super("Miasto", 520)
	_header = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], _show_tab.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_buttons.append(b)
	content.add_child(tabs)
	content.add_child(HSeparator.new())
	_body.add_theme_constant_override("separation", 6)
	content.add_child(_body)


func open_at(at: Vector2i) -> void:
	if at != plot:
		_state = {}
	plot = at
	show_window()
	refresh()


func refresh() -> void:
	_apply(await Net.request("city.get", {"x": plot.x, "y": plot.y}))


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "city":
		failed.emit(reply)
		return false
	_state = reply["payload"]["state"]
	_render()
	return true


func _show_tab(i: int) -> void:
	_tab = i
	_render()


func _render() -> void:
	var town: Dictionary = _state.get("town", {})
	var in_city := bool(town.get("inCity", true))
	if not in_city and _tab in CITY_TABS:
		_tab = HALL_TAB
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
		_tab_buttons[i].visible = in_city or i not in CITY_TABS
	UI.clear(_body)
	if _state.is_empty():
		return
	set_title(town["name"])
	var distance := float(town["distance"])
	if in_city:
		_header.text = "%s · %s · %s mieszkańców · %s" % [town["name"], town["levelName"], _thousands(int(town["population"])),
			"w samym centrum" if distance < 0.5 else "%s działki od centrum (im bliżej, tym więcej klientów)" % str(snappedf(distance, 0.1)).replace(".", ",")]
	else:
		_header.text = "Powiat miasta %s · %s · %s działki od centrum. Prawa burmistrza obowiązują tu tak samo jak w mieście." \
			% [town["name"], town["levelName"], str(snappedf(distance, 0.1)).replace(".", ",")]
	match _tab:
		0: _render_needs()
		1: _render_tender()
		2: _render_growth()
		3: _render_trash()
		4: _render_services()
		5: _render_hall()
		6: _render_election()
		7: _render_treasury()
	_fit.call_deferred()


func _render_needs() -> void:
	_body.add_child(UI.label("Dziś miasto kupi to, czego potrzebuje, drożej niż handlarz. Jutro zechce czego innego (zostało %s)." \
		% _left(int(_state["dayEndsAt"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for need: Dictionary in _state["needs"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(need["id"], 30))
		var wanted := int(need["wanted"])
		var delivered := int(need["delivered"])
		var text := UI.label("%s\n%d / %d · %s za sztukę" % [need["name"], delivered, wanted, UI.money(int(need["priceCents"]))])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var left := wanted - delivered
		var spin := _spin(1, maxi(left, 1), maxi(left, 1))
		spin.editable = left > 0
		row.add_child(spin)
		var own := UI.button("Z ekwipunku", func() -> void: _deliver(need["id"], int(spin.value), false), true)
		own.disabled = left <= 0
		row.add_child(own)
		var station := UI.button("Ze stacji", func() -> void: _deliver(need["id"], int(spin.value), true))
		station.tooltip_text = "Prosto ze stacji kolejowej tej działki"
		station.disabled = left <= 0
		row.add_child(station)
		_body.add_child(row)


func _render_growth() -> void:
	var town: Dictionary = _state["town"]
	var level := int(town["level"])
	var names: Array = town["levelNames"]
	var cents: Array = town["levelCents"]
	var delivered := int(town["deliveredCents"])
	_body.add_child(UI.label("Miasto rośnie na wszystkim, co gracze mu dostarczą. Większe chce więcej i droższych rzeczy, płaci więcej, " +
		"ma więcej śmieci i klientów w sklepach.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if level + 1 < cents.size():
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 12
		bar.min_value = int(cents[level])
		bar.max_value = int(cents[level + 1])
		bar.value = delivered
		_body.add_child(UI.label("%s → %s: %s / %s" % [names[level], names[level + 1], UI.money(delivered), UI.money(int(cents[level + 1]))]))
		_body.add_child(bar)
	else:
		_body.add_child(UI.label("%s: największe, jakie może być. Dostarczono %s." % [names[level], UI.money(delivered)], UI.GOLD))
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label("Najwięcej dostarczyli", UI.GOLD))
	if (_state["contributors"] as Array).is_empty():
		_body.add_child(UI.label("Jeszcze nikt.", UI.MUTED))
	for c: Dictionary in _state["contributors"]:
		_body.add_child(Online.with_dot(UI.label("%s%s: %s" % [c["name"], " (ty)" if c["mine"] else "", UI.money(int(c["cents"]))],
			UI.GOLD if c["mine"] else UI.TEXT), c["name"]))
	_body.add_child(UI.label("Twój wkład: %s" % UI.money(int(_state["myCents"])), UI.MUTED))
	_render_supplier()


## The chief supplier: who delivered the most last week holds the title this week and gets a little more for deliveries.
func _render_supplier() -> void:
	var supplier: Dictionary = _state["supplier"]
	_body.add_child(HSeparator.new())
	var chief: Variant = supplier["name"]
	var title := "Główny dostawca tego tygodnia: %s" % (chief if chief != null else "nikt")
	if supplier["isMe"]:
		title += " (ty! miasto płaci ci o %d%% więcej)" % int(supplier["percent"])
	_body.add_child(Online.with_dot(UI.label(title, UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true), chief))
	_body.add_child(UI.label(("Kto w tym tygodniu dostarczy najwięcej (co najmniej %s), ten od następnego tygodnia nosi tytuł, " +
		"a miasto płaci mu za dostawy o %d%% więcej. Koniec tygodnia za %s.") % [UI.money(int(supplier["minCents"])),
		int(supplier["percent"]), _left(int(supplier["weekEndsAt"]))], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for r: Dictionary in supplier["race"]:
		_body.add_child(Online.with_dot(UI.label("%d. %s%s: %s" % [int(r["place"]), r["name"], " (ty)" if r["mine"] else "", UI.money(int(r["cents"]))],
			UI.GOLD if r["mine"] else UI.TEXT), r["name"]))
	_body.add_child(UI.label("Twoje dostawy w tym tygodniu: %s" % UI.money(int(supplier["myCents"])), UI.MUTED))


## The week's tender: sealed bids while bidding is open, then the winner delivers until the week's end.
func _render_tender() -> void:
	var t: Dictionary = _state["tender"]
	var quantity := int(t["quantity"])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UI.item_icon(t["item"], 30))
	head.add_child(UI.label("%d × %s · najwyżej %s za sztukę" % [quantity, t["name"], UI.money(int(t["capCents"]))], UI.GOLD))
	_body.add_child(head)
	match str(t["state"]):
		"open":
			_body.add_child(UI.label(("Miasto zamawia dużą partię. Właściciele działek w powiecie składają ukryte oferty: cenę za sztukę. " +
				"Wygrywa najniższa (przy równych: wcześniejsza). Oferta kosztuje wadium %d%% wartości zamówienia, które wraca, gdy przegrasz " +
				"albo dostarczysz całość; zwycięzca, który nie zdąży do końca tygodnia, traci je. Oferty do końca za %s.") % [
				int(t["depositPercent"]), _left(int(t["closesAt"]))], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
			_body.add_child(UI.label("Złożone oferty: %d" % int(t["bids"])))
			var mine: Variant = t["myBid"]
			if mine is Dictionary:
				_body.add_child(UI.label("Twoja oferta: %s za sztukę (wadium %s)" % [UI.money(int(mine["priceCents"])), UI.money(int(mine["depositCents"]))],
					UI.GOOD))
			if t["canBid"]:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)
				row.add_child(UI.label("Cena za sztukę $"))
				var price := SpinBox.new()
				price.min_value = 0.01
				price.max_value = int(t["capCents"]) / 100.0
				price.step = 0.01
				price.value = (int(mine["priceCents"]) if mine is Dictionary else int(t["capCents"])) / 100.0
				price.custom_minimum_size.x = 110
				price.select_all_on_focus = true
				row.add_child(price)
				var deposit := UI.label("")
				var show_deposit := func(value: float) -> void:
					deposit.text = "wadium %s" % UI.money(ceili(roundi(value * 100.0) * quantity * int(t["depositPercent"]) / 100.0))
				show_deposit.call(price.value)
				price.value_changed.connect(show_deposit)
				deposit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(deposit)
				row.add_child(UI.button("Zmień ofertę" if mine is Dictionary else "Złóż ofertę", func() -> void: _bid(roundi(price.value * 100.0)), true))
				if mine is Dictionary:
					row.add_child(UI.button("Wycofaj", _withdraw))
				_body.add_child(row)
			else:
				_body.add_child(UI.label("Oferty składają tylko właściciele działek w tym mieście.", UI.MUTED))
		"won":
			_body.add_child(Online.with_dot(UI.label("Przetarg wygrał %s: %s za sztukę." % [t["winner"], UI.money(int(t["priceCents"]))], UI.TEXT), t["winner"]))
			_body.add_child(UI.label("Dostarczono %d z %d. Termin mija za %s." % [int(t["delivered"]), quantity, _left(int(t["endsAt"]))]))
			if t["isWinner"]:
				var left := quantity - int(t["delivered"])
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 6)
				var spin := _spin(1, maxi(left, 1), maxi(left, 1))
				row.add_child(spin)
				row.add_child(UI.button("Z ekwipunku", func() -> void: _deliver_tender(int(spin.value), false), true))
				var station := UI.button("Ze stacji", func() -> void: _deliver_tender(int(spin.value), true))
				station.tooltip_text = "Prosto ze stacji kolejowej tej działki"
				row.add_child(station)
				_body.add_child(row)
				_body.add_child(UI.label("Wadium %s wróci po dostarczeniu całości." % UI.money(int(t["depositCents"])), UI.MUTED))
		"done":
			_body.add_child(UI.label("%s dostarczył całość po %s za sztukę. Nowy przetarg w przyszłym tygodniu." % [t["winner"], UI.money(int(t["priceCents"]))],
				UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
		"failed":
			_body.add_child(UI.label("%s nie zdążył dostarczyć całości (%d z %d) i stracił wadium." % [t["winner"], int(t["delivered"]), quantity],
				UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true))
		_:
			_body.add_child(UI.label("Nikt nie złożył oferty w tym tygodniu. Nowy przetarg w przyszłym.", UI.MUTED))


func _render_trash() -> void:
	var trash: Dictionary = _state["trash"]
	var left := int(trash["perDay"]) - int(trash["taken"])
	_body.add_child(UI.label(("Miasto płaci %s za każdy wywieziony śmieć. Śmieci trafiają na stację działki: posortuj je w sortowni " +
		"miejskiej albo w recyklingu.") % UI.money(int(trash["feeCents"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(UI.label("Dziś do wywiezienia: %d z %d" % [left, int(trash["perDay"])]))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon("trash", 30))
	var spin := _spin(1, maxi(left, 1), maxi(left, 1))
	spin.editable = left > 0
	row.add_child(spin)
	var take := UI.button("Wywieź na stację", func() -> void: _take_trash(int(spin.value)), true)
	take.disabled = left <= 0
	row.add_child(take)
	_body.add_child(row)


func _render_services() -> void:
	_body.add_child(UI.label("Biura graczy z tego miasta sprzedają swoje usługi. Właściciel dostaje zapłatę, burmistrz podatek.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if (_state["services"] as Array).is_empty():
		_body.add_child(UI.label("Nikt w mieście nie ma jeszcze biura projektowego, laboratorium ani warsztatu serwisowego.", UI.MUTED,
			HORIZONTAL_ALIGNMENT_LEFT, true))
	for s: Dictionary in _state["services"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.item_icon(s["item"], 30))
		var text := UI.label("%s (%s)\n%d× %s za %s · dziś jeszcze %d" % [s["name"], s["owner"], int(s["quantity"]), s["itemName"],
			UI.money(int(s["priceCents"])), int(s["left"])])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(Online.with_dot(text, s["owner"]))
		var buy := UI.button("Twoje" if s["own"] else "Kup", func() -> void: _buy_service(s["id"]), true)
		buy.disabled = s["own"] or int(s["left"]) <= 0
		row.add_child(buy)
		_body.add_child(row)


func _render_hall() -> void:
	var hall: Dictionary = _state["hall"]
	var mayor: Variant = hall["mayor"]
	_body.add_child(Online.with_dot(UI.label("Burmistrz tego tygodnia: %s" % (mayor if mayor != null else "brak (nikt nie głosował)"), UI.GOLD),
		mayor))
	var bonus_name := "żaden"
	for b: Dictionary in hall["bonuses"]:
		if b["id"] == hall["bonus"]:
			bonus_name = b["name"]
	_body.add_child(UI.label("Podatek od sklepów i usług: %d%% · Od działek powiatu: %d‰ dziennie · Premia: %s" \
		% [int(hall["taxPercent"]), int(hall.get("plotTaxPerMille", 0)), bonus_name], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	if hall["isMayor"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("Podatek %"))
		var tax := _spin(0, int(hall["maxTaxPercent"]), int(hall["taxPercent"]))
		row.add_child(tax)
		var pick := OptionButton.new()
		pick.add_item("Bez premii")
		pick.set_item_metadata(0, "")
		for b: Dictionary in hall["bonuses"]:
			pick.add_item(b["name"])
			pick.set_item_metadata(pick.item_count - 1, b["id"])
			if b["id"] == hall["bonus"]:
				pick.select(pick.item_count - 1)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		row.add_child(pick)
		_body.add_child(row)
		# The tax on the county's plots, on top of the country's plot tax; the mayor's own plots don't pay it.
		var plots := HBoxContainer.new()
		plots.add_theme_constant_override("separation", 6)
		plots.add_child(UI.label("Od działek powiatu ‰ dziennie"))
		var plot_tax := _spin(0, int(hall.get("maxPlotTaxPerMille", 0)), int(hall.get("plotTaxPerMille", 0)))
		plots.add_child(plot_tax)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plots.add_child(spacer)
		plots.add_child(UI.button("Ustaw", func() -> void:
			_set_policy(int(tax.value), pick.get_item_metadata(pick.selected), int(plot_tax.value)), true))
		_body.add_child(plots)
	# A festival with fine dishes from the mayor's inventory: the town pays more for what it wants for a day.
	var festival: Variant = hall.get("festivalUntil")
	if festival != null:
		_body.add_child(UI.label("Trwa festyn: miasto płaci o %d%% więcej jeszcze %s." % [int(hall["festivalPercent"]), _left(int(festival))],
			UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
	elif hall["isMayor"]:
		var feast := HBoxContainer.new()
		feast.add_theme_constant_override("separation", 6)
		var note := UI.label("Festyn: %d × pieczeń lub sernik z ekwipunku, a przez %d h miasto płaci o %d%% więcej." % [
			int(hall["festivalDishes"]), int(hall["festivalHours"]), int(hall["festivalPercent"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feast.add_child(note)
		feast.add_child(UI.button("Wyprawiaj festyn", _festival, true))
		_body.add_child(feast)
	var politics: Dictionary = hall["politics"]
	if politics["recalled"]:
		_body.add_child(UI.label("Mieszkańcy odwołali burmistrza w tym tygodniu.", UI.ERROR))
	elif mayor != null:
		var recall: Dictionary = politics["recall"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var text := UI.label("Wotum nieufności: %d z %d podpisów (2/3 mieszkańców)" % [int(recall["signatures"]), int(recall["needed"])], UI.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var sign := UI.button("Podpisz", _recall)
		sign.disabled = not hall["canVote"] or recall["signed"]
		row.add_child(sign)
		_body.add_child(row)

	# Ordinances: the mayor puts one to the vote of the townsfolk for a day; those that pass hold until the week is out.
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label("Uchwały", UI.GOLD))
	var ordinances: Array = politics["ordinances"]
	if ordinances.is_empty():
		_body.add_child(_note("W tym tygodniu nie było uchwał."))
	for o: Dictionary in ordinances:
		var state := "głosowanie trwa jeszcze %s" % _left(int(o["votingEnds"])) if o["open"] else ("obowiązuje do końca tygodnia" if o["inForce"] else "odrzucona")
		_body.add_child(UI.label("%s · za %d, przeciw %d · %s" % [o["name"], int(o["yes"]), int(o["no"]), state],
			UI.GOOD if o["inForce"] else UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		if o["open"] and hall["canVote"]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var yes := UI.button("Za", _vote_ordinance.bind(str(o["id"]), true))
			yes.disabled = o["myVote"] == true
			var no := UI.button("Przeciw", _vote_ordinance.bind(str(o["id"]), false))
			no.disabled = o["myVote"] == false
			row.add_child(yes)
			row.add_child(no)
			_body.add_child(row)
	if hall["isMayor"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pick := OptionButton.new()
		for kind: Dictionary in politics["ordinanceKinds"]:
			pick.add_item(kind["name"])
			pick.set_item_metadata(pick.item_count - 1, kind["id"])
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		row.add_child(pick)
		row.add_child(UI.button("Pod głosowanie", func() -> void: _propose(str(pick.get_item_metadata(pick.selected))), true))
		_body.add_child(row)
		_body.add_child(_note("Głosowanie trwa %d h; uchwała przechodzi, gdy więcej mieszkańców jest za niż przeciw." % int(politics["ordinanceHours"])))


## Candidates for next week's mayor with their programmes, the money companies gave them and the promises they kept.
func _render_election() -> void:
	var hall: Dictionary = _state["hall"]
	var politics: Dictionary = hall["politics"]
	_body.add_child(UI.label("Wybory na przyszły tydzień (koniec za %s). Głosują i mogą wygrać właściciele działek w powiecie miasta, także poza samym miastem." \
		% _left(int(hall["weekEndsAt"])), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for c: Dictionary in politics["people"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var mine: bool = hall["myVote"] == c["name"]
		var party := " (%s)" % c["party"] if c["party"] != null else ""
		var text := UI.label("%s%s%s: %d głosów%s" % [c["name"], " (ty)" if c["me"] else "", party, int(c["votes"]), " · twój głos" if mine else ""],
			UI.GOLD if mine else UI.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(Online.with_dot(text, c["name"]))
		var vote := UI.button("Głosuj", func() -> void: _vote(c["name"]))
		vote.disabled = not hall["canVote"] or mine
		row.add_child(vote)
		_body.add_child(row)
		var details: Array[String] = []
		if c["stands"]:
			details.append("program: podatek %d%%, premia: %s" % [int(c["taxPercent"]), _bonus_name(hall, c["bonus"])])
			if str(c["slogan"]) != "":
				details.append("„%s”" % c["slogan"])
		if int(c["promisesMade"]) > 0:
			details.append("dotrzymane obietnice: %d z %d" % [int(c["promisesKept"]), int(c["promisesMade"])])
		for sponsor: Dictionary in c["sponsors"]:
			details.append("wsparcie: %s %s" % [sponsor["company"], UI.money(int(sponsor["cents"]))])
		if not details.is_empty():
			_body.add_child(_note(" · ".join(details)))
		if c["stands"]:
			var back := HBoxContainer.new()
			back.add_theme_constant_override("separation", 6)
			back.add_child(_note("Wesprzyj z kasy swojej spółki:"))
			var amount := _spin(1, 1000000, 100)
			amount.suffix = "$"
			back.add_child(amount)
			back.add_child(UI.button("Wesprzyj", func() -> void: _sponsor(str(c["name"]), int(amount.value) * 100)))
			_body.add_child(back)
	if hall["canVote"]:
		_body.add_child(HSeparator.new())
		_body.add_child(UI.label("Zmień swój program" if politics["standing"] else "Kandyduj na burmistrza", UI.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("Podatek %"))
		var tax := _spin(0, int(hall["maxTaxPercent"]), 5)
		row.add_child(tax)
		var pick := OptionButton.new()
		pick.add_item("Bez premii")
		pick.set_item_metadata(0, "")
		for b: Dictionary in hall["bonuses"]:
			pick.add_item(b["name"])
			pick.set_item_metadata(pick.item_count - 1, b["id"])
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		row.add_child(pick)
		_body.add_child(row)
		var slogan := UI.line_edit("Hasło wyborcze")
		slogan.max_length = 80
		_body.add_child(slogan)
		_body.add_child(UI.button("Zapisz program" if politics["standing"] else "Kandyduj (kaucja %s)" % UI.money(int(politics["depositCents"])),
			func() -> void: _stand(int(tax.value), str(pick.get_item_metadata(pick.selected)), slogan.text), true))
		_body.add_child(_note("Kaucja wraca, gdy dostaniesz co najmniej %d%% głosów; inaczej trafia do kasy miasta. Przy twoim imieniu widać, czy jako burmistrz dotrzymałeś obietnic." \
			% int(politics["depositBackPercent"])))


## The town's treasury: what came in and went out, and the buildings the mayor puts up with it.
func _render_treasury() -> void:
	var hall: Dictionary = _state["hall"]
	var politics: Dictionary = hall["politics"]
	_body.add_child(UI.label("Kasa miasta: %s" % UI.money(int(politics["treasuryCents"])), UI.GOLD))
	_body.add_child(_note("Trafia tu podatek od sklepów i usług (burmistrz dostaje %d%% jako pensję) i przepadłe kaucje wyborcze." \
		% int(politics["mayorSharePercent"])))
	for line: Dictionary in politics["ledger"]:
		var cents := int(line["cents"])
		_body.add_child(_note("%s%s  %s" % ["+" if cents > 0 else "", UI.money(cents), line["reason"]]))
	_body.add_child(HSeparator.new())
	for i: Dictionary in politics["investments"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var text := UI.label("%s (poziom %d/%d): %s" % [i["name"], int(i["level"]), int(i["maxLevel"]), i["effect"]], UI.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		if hall["isMayor"] and i["nextCents"] != null:
			var build := UI.button("Buduj za %s" % UI.money(int(i["nextCents"])), _invest.bind(str(i["id"])))
			build.disabled = int(politics["treasuryCents"]) < int(i["nextCents"])
			row.add_child(build)
		_body.add_child(row)


func _deliver(item: String, quantity: int, from_station: bool) -> void:
	var reply := await Net.request("city.deliver", {"x": plot.x, "y": plot.y, "item": item, "quantity": quantity, "fromStation": from_station})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		var subsidy := int(result.get("subsidyCents", 0))
		toast.emit("Miasto kupiło %d szt. za %s%s" % [int(result["quantity"]), UI.money(int(result["cents"])),
			" + dotacja państwa %s" % UI.money(subsidy) if subsidy > 0 else ""])
		inventory_changed.emit()
		balance_changed.emit()


func _bid(price_cents: int) -> void:
	if _apply(await Net.request("city.tenderBid", {"x": plot.x, "y": plot.y, "priceCents": price_cents})):
		toast.emit("Oferta złożona: %s za sztukę" % UI.money(price_cents))
		balance_changed.emit()


func _withdraw() -> void:
	if _apply(await Net.request("city.tenderWithdraw", {"x": plot.x, "y": plot.y})):
		toast.emit("Oferta wycofana, wadium wróciło")
		balance_changed.emit()


func _deliver_tender(quantity: int, from_station: bool) -> void:
	var reply := await Net.request("city.tenderDeliver", {"x": plot.x, "y": plot.y, "quantity": quantity, "fromStation": from_station})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Dostarczono do przetargu %d szt. za %s" % [int(result["quantity"]), UI.money(int(result["cents"]))])
		inventory_changed.emit()
		balance_changed.emit()


func _take_trash(quantity: int) -> void:
	var reply := await Net.request("city.trash", {"x": plot.x, "y": plot.y, "quantity": quantity})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Wywieziono %d śmieci na stację, miasto zapłaciło %s" % [int(result["quantity"]), UI.money(int(result["cents"]))])
		balance_changed.emit()


func _buy_service(id: String) -> void:
	var reply := await Net.request("city.service", {"x": plot.x, "y": plot.y, "id": id})
	if _apply(reply):
		var result: Dictionary = reply["payload"]["result"]
		toast.emit("Kupiono: %d× %s" % [int(result["quantity"]), result["name"]])
		inventory_changed.emit()
		balance_changed.emit()


func _festival() -> void:
	if _apply(await Net.request("city.festival", {"x": plot.x, "y": plot.y})):
		toast.emit("Festyn trwa! Miasto płaci więcej przez całą dobę.")
		inventory_changed.emit()


func _vote(candidate: String) -> void:
	if _apply(await Net.request("city.vote", {"x": plot.x, "y": plot.y, "candidate": candidate})):
		toast.emit("Oddano głos na: %s" % candidate)


func _set_policy(tax: int, bonus: String, plot_tax: int) -> void:
	if _apply(await Net.request("city.policy", {"x": plot.x, "y": plot.y, "taxPercent": tax, "bonus": bonus, "plotTaxPerMille": plot_tax})):
		toast.emit("Ustawiono podatki i premię miasta na ten tydzień")


func _recall() -> void:
	var reply := await Net.request("city.recall", {"x": plot.x, "y": plot.y})
	if _apply(reply):
		toast.emit("Burmistrz odwołany!" if reply["payload"]["result"]["recalled"] else "Podpisano wniosek o odwołanie burmistrza")


func _propose(kind: String) -> void:
	if _apply(await Net.request("city.propose", {"x": plot.x, "y": plot.y, "kind": kind})):
		toast.emit("Uchwała poddana pod głosowanie")


func _vote_ordinance(id: String, yes: bool) -> void:
	if _apply(await Net.request("city.ordinance", {"x": plot.x, "y": plot.y, "id": id, "yes": yes})):
		toast.emit("Oddano głos %s uchwałą" % ("za" if yes else "przeciw"))


func _stand(tax: int, bonus: String, slogan: String) -> void:
	if _apply(await Net.request("city.stand", {"x": plot.x, "y": plot.y, "taxPercent": tax, "bonus": bonus, "slogan": slogan})):
		toast.emit("Kandydujesz na burmistrza")
		balance_changed.emit()


func _sponsor(candidate: String, cents: int) -> void:
	if _apply(await Net.request("city.sponsor", {"x": plot.x, "y": plot.y, "candidate": candidate, "cents": cents})):
		toast.emit("Spółka wsparła kandydata: %s" % candidate)


func _invest(kind: String) -> void:
	if _apply(await Net.request("city.invest", {"x": plot.x, "y": plot.y, "kind": kind})):
		toast.emit("Zbudowano z kasy miasta")


func _bonus_name(hall: Dictionary, bonus: Variant) -> String:
	for b: Dictionary in hall["bonuses"]:
		if b["id"] == bonus:
			return b["name"]
	return "żadna"


func _note(text: String) -> Label:
	var l := UI.label(text, UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_theme_font_size_override("font_size", 13)
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


## Time from now until `at` (ms since the epoch), as "5 h 12 min" or "2 dni 3 h".
func _left(at: int) -> String:
	var seconds := maxi(0, (at - int(Time.get_unix_time_from_system() * 1000.0)) / 1000)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	if days > 0:
		return "%d %s %d h" % [days, "dzień" if days == 1 else "dni", hours]
	return "%d h %d min" % [hours, (seconds % 3600) / 60]


func _thousands(n: int) -> String:
	var whole := str(n)
	var grouped := ""
	for i in whole.length():
		if i > 0 and (whole.length() - i) % 3 == 0:
			grouped += " "
		grouped += whole[i]
	return grouped
