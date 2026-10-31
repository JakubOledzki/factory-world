class_name CountryWindow
extends GameWindow
## A country of the map as its players govern it: citizenship, the president and the ministers, the laws they set
## (plot tax, the fee foreigners pay for plots, tariffs, a subsidy), the treasury and what it builds, the election
## of the next president, the recall, relations with other countries, the ranking of countries and the parties.

signal balance_changed
signal failed(reply: Dictionary)
signal toast(text: String)

const TABS := ["Kraj", "Rząd", "Wybory", "Dyplomacja", "Państwa", "Partie"]
const LAW_NAMES := {
	"plotTax": "Podatek od działek (‰ wartości dziennie)",
	"foreignerFee": "Opłata od cudzoziemców za działkę (%)",
	"tariff": "Cło na towary z innych krajów (%)",
}

## Country code by lower-case name, for typing the other country in diplomacy (the map sets it; elsewhere it is read when needed).
var codes_by_name := {}

var _code := ""
var _state := {}
var _ranking := {}
var _parties := {}
var _tab := 0
var _tab_buttons: Array[Button] = []
var _header: Label
var _body := VBoxContainer.new()


func _init() -> void:
	super("Państwo", 560)
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


func open_country(code: String) -> void:
	if code != _code:
		_state = {}
	_code = code
	_tab = 0
	show_window()
	refresh()


## Opens on the ranking of countries, or on the player's own country when they have one.
func open_ranking() -> void:
	_tab = 4
	show_window()
	await _load_ranking()
	var home: Variant = _ranking.get("citizenship")
	if home != null and _code.is_empty():
		_code = str(home)
		await refresh()
		_tab = 0
	_render()


func refresh() -> void:
	if not _code.is_empty():
		_apply(await Net.request("country.get", {"country": _code}))
	if _tab == 4:
		await _load_ranking()
	elif _tab == 5:
		await _load_parties()
	_render()


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "country":
		failed.emit(reply)
		return false
	_state = reply["payload"]["state"]
	_render()
	return true


func _load_ranking() -> void:
	var reply := await Net.request("country.list")
	if reply["type"] == "countries":
		_ranking = reply["payload"]
	else:
		failed.emit(reply)


func _load_parties() -> void:
	var reply := await Net.request("party.get")
	if reply["type"] == "party":
		_parties = reply["payload"]
	else:
		failed.emit(reply)


func _show_tab(i: int) -> void:
	_tab = i
	if i == 4:
		await _load_ranking()
	elif i == 5:
		await _load_parties()
	_render()


func _render() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	UI.clear(_body)
	if _state.is_empty():
		_header.text = "Wybierz kraj na mapie albo z listy państw."
		set_title("Państwa")
	else:
		set_title(_state["name"])
		var president: Variant = _state["government"]["president"]
		_header.text = "%s · %d obywateli · prezydent: %s · kadencja kończy się za %s" % [_state["name"], int(_state["citizens"]),
			president if president != null else "brak", _left(int(_state["termEndsAt"]))]
	match _tab:
		0: _render_country()
		1: _render_government()
		2: _render_election()
		3: _render_diplomacy()
		4: _render_ranking()
		5: _render_parties()
	_fit.call_deferred()


func _needs_country() -> bool:
	if _state.is_empty():
		_body.add_child(UI.label("Najpierw wybierz kraj: kliknij działkę na mapie i „Państwo” albo otwórz listę państw.", UI.MUTED,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		return true
	return false


# --- Country ----------------------------------------------------------------------------------

func _render_country() -> void:
	if _needs_country():
		return
	var me: Dictionary = _state["me"]
	var home: Variant = me["citizenship"]
	if home == _state["code"]:
		_body.add_child(UI.label("Jesteś obywatelem tego kraju.", UI.GOOD))
		if int(me["plotsHere"]) == 0:
			_body.add_child(_note("Nie masz już tu działki: dopóki jej nie kupisz, nie głosujesz i nie kandydujesz."))
	else:
		var text := "Twoje obywatelstwo: %s." % (me["citizenshipName"] if home != null else "żadne")
		_body.add_child(UI.label(text, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		if int(me["plotsHere"]) > 0:
			var change := UI.button("Przyjmij obywatelstwo", _choose_citizenship, true)
			if me["changeAt"] != null:
				change.disabled = true
				_body.add_child(_note("Obywatelstwo zmienisz za %s (raz w tygodniu)." % _left(int(me["changeAt"]))))
			_body.add_child(change)
		else:
			_body.add_child(_note("Kup działkę w tym kraju, by zostać jego obywatelem: obywatele wybierają prezydenta i sami kandydują."))
	if me["party"] != null:
		_body.add_child(_note("Twoja partia: %s" % me["party"]))
	var offices: Array = me["offices"]
	if not offices.is_empty():
		_body.add_child(UI.label("Twoje urzędy: %s" % ", ".join(offices.map(func(o: String) -> String: return _office_title(o))), UI.GOLD))

	_body.add_child(HSeparator.new())
	var government: Dictionary = _state["government"]
	var president: Variant = government["president"]
	var who := UI.label("Prezydent: %s%s" % [president if president != null else "brak", _party(government["presidentParty"])], UI.GOLD)
	_body.add_child(Online.with_dot(who, president) if president != null else who)
	if government["recalled"]:
		_body.add_child(_note("Obywatele odwołali prezydenta w tej kadencji; prawo wróciło do ustawień domyślnych."))
	for m: Dictionary in government["ministers"]:
		if m["name"] != null:
			_body.add_child(UI.label("%s: %s" % [m["title"], m["name"]]))
	var laws: Dictionary = government["laws"]
	_body.add_child(HSeparator.new())
	_body.add_child(UI.label("Prawo", UI.GOLD))
	_body.add_child(UI.label("Podatek od działek: %s‰ wartości dziennie (%d%% trafia do skarbca)" % [
		str(int(laws["plotTaxPerMille"])), int(laws["treasurySharePercent"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(UI.label("Opłata od cudzoziemców za działkę: %d%%" % int(laws["foreignerFeePercent"])))
	_body.add_child(UI.label("Cło: %d%%%s" % [int(laws["tariffPercent"]), _item_tariffs(laws["itemTariffs"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(UI.label("Dotacja: %s" % _subsidy_name(laws), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))

	_body.add_child(HSeparator.new())
	var treasury: Dictionary = _state["treasury"]
	_body.add_child(UI.label("Skarbiec: %s" % UI.money(int(treasury["cents"])), UI.GOLD))
	_body.add_child(_note("Prezydent dostaje %d%% wpływów jako pensję." % int(treasury["presidentSharePercent"])))
	for line: Dictionary in treasury["ledger"]:
		var cents := int(line["cents"])
		_body.add_child(_small("%s%s  %s" % ["+" if cents > 0 else "", UI.money(cents), line["reason"]], UI.GOOD if cents > 0 else UI.ERROR))
	for i: Dictionary in _state["investments"]:
		_body.add_child(UI.label("%s: poziom %d z %d (%s)" % [i["name"], int(i["level"]), int(i["maxLevel"]), i["effect"]], UI.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true))


# --- Government -------------------------------------------------------------------------------

func _render_government() -> void:
	if _needs_country():
		return
	var offices: Array = _state["me"]["offices"]
	var president := "president" in offices
	if offices.is_empty():
		_body.add_child(_note("Tu rządzą prezydent i ministrowie. Zostań obywatelem i wygraj wybory albo poproś prezydenta o urząd ministra."))
		return
	var laws: Dictionary = _state["government"]["laws"]
	if president or "finance" in offices:
		_body.add_child(UI.label("Minister finansów", UI.GOLD))
		_law_row("plotTax", int(laws["plotTaxPerMille"]), int(laws["minPlotTaxPerMille"]), int(laws["maxPlotTaxPerMille"]))
		_law_row("foreignerFee", int(laws["foreignerFeePercent"]), 0, int(laws["maxForeignerFeePercent"]))
		_law_row("tariff", int(laws["tariffPercent"]), 0, int(laws["maxTariffPercent"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var item := UI.line_edit("Id towaru, np. coal")
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(item)
		var percent := _spin(-1, int(laws["maxTariffPercent"]), 10)
		percent.tooltip_text = "-1 zdejmuje cło na ten towar"
		row.add_child(percent)
		row.add_child(UI.button("Cło na towar", func() -> void: _set_law("itemTariff", int(percent.value), item.text.strip_edges())))
		_body.add_child(row)
	if president or "industry" in offices:
		_body.add_child(UI.label("Minister przemysłu", UI.GOLD))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var pick := OptionButton.new()
		pick.add_item("Bez dotacji")
		pick.set_item_metadata(0, "")
		for s: Dictionary in laws["subsidies"]:
			pick.add_item("%s (+%d%%)" % [s["name"], int(laws["subsidyPercent"])])
			pick.set_item_metadata(pick.item_count - 1, s["id"])
			if s["id"] == laws["subsidy"]:
				pick.select(pick.item_count - 1)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pick)
		row.add_child(UI.button("Ustaw dotację", func() -> void: _set_law("subsidy", 0, str(pick.get_item_metadata(pick.selected)))))
		_body.add_child(row)
		_body.add_child(_note("Miasta w kraju płacą za te towary więcej, a różnicę dopłaca skarbiec, dopóki ma pieniądze."))
	for i: Dictionary in _state["investments"]:
		if president or i["office"] in offices:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var text := UI.label("%s (poziom %d/%d): %s" % [i["name"], int(i["level"]), int(i["maxLevel"]), i["effect"]], UI.TEXT,
				HORIZONTAL_ALIGNMENT_LEFT, true)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
			if i["nextCents"] != null:
				row.add_child(UI.button("Buduj za %s" % UI.money(int(i["nextCents"])), _invest.bind(str(i["id"]))))
			_body.add_child(row)
	if president:
		_body.add_child(HSeparator.new())
		_body.add_child(UI.label("Ministrowie", UI.GOLD))
		for m: Dictionary in _state["government"]["ministers"]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var title := UI.label(m["title"])
			title.custom_minimum_size.x = 230
			row.add_child(title)
			var field := UI.line_edit("Imię obywatela")
			field.text = str(m["name"]) if m["name"] != null else ""
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(field)
			row.add_child(UI.button("Mianuj", func() -> void: _appoint(str(m["office"]), field.text.strip_edges())))
			_body.add_child(row)


func _law_row(law: String, value: int, low: int, high: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := UI.label(LAW_NAMES[law], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var spin := _spin(low, high, value)
	row.add_child(spin)
	row.add_child(UI.button("Ustaw", func() -> void: _set_law(law, int(spin.value), "")))
	_body.add_child(row)


# --- Election ---------------------------------------------------------------------------------

func _render_election() -> void:
	if _needs_country():
		return
	var election: Dictionary = _state["election"]
	var voter: bool = _state["me"]["voter"]
	_body.add_child(_note("Wybory prezydenta na następną kadencję, koniec za %s. Głosują i kandydują obywatele z działką w kraju." \
		% _left(int(_state["termEndsAt"]))))
	var candidates: Array = election["candidates"]
	if candidates.is_empty():
		_body.add_child(_note("Nikt jeszcze nie kandyduje."))
	var total := 0
	for c: Dictionary in candidates:
		total += int(c["votes"])
	for c: Dictionary in candidates:
		_body.add_child(_candidate_card(c, election["myVote"] == c["name"], voter, total))

	if not candidates.is_empty():
		var sponsor := _flow()
		sponsor.add_child(_middle(UI.label("Wesprzyj z kasy spółki:", UI.MUTED)))
		var whom := OptionButton.new()
		for c: Dictionary in candidates:
			whom.add_item(str(c["name"]))
		sponsor.add_child(whom)
		var amount := _spin(1, 1000000, 100)
		amount.suffix = "$"
		sponsor.add_child(amount)
		sponsor.add_child(UI.button("Wesprzyj", func() -> void:
			_sponsor(whom.get_item_text(whom.selected), int(amount.value) * 100)))
		_body.add_child(sponsor)

	if voter:
		_body.add_child(HSeparator.new())
		var laws: Dictionary = _state["government"]["laws"]
		_body.add_child(UI.label("Kandyduj" if not election["standing"] else "Zmień swój program", UI.GOLD))
		var form := _flow()
		form.add_child(_middle(UI.label("Podatek ‰")))
		var tax := _spin(int(laws["minPlotTaxPerMille"]), int(laws["maxPlotTaxPerMille"]), int(laws["plotTaxPerMille"]))
		form.add_child(tax)
		form.add_child(_middle(UI.label("Opłata %")))
		var fee := _spin(0, int(laws["maxForeignerFeePercent"]), int(laws["foreignerFeePercent"]))
		form.add_child(fee)
		var slogan := UI.line_edit("Hasło wyborcze")
		slogan.max_length = 80
		slogan.custom_minimum_size.x = 200
		slogan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		form.add_child(slogan)
		_body.add_child(form)
		var stand_row := HBoxContainer.new()
		stand_row.add_theme_constant_override("separation", 8)
		var stand := UI.button("Kandyduj (kaucja %s)" % UI.money(int(election["depositCents"])) if not election["standing"] else "Zapisz program",
			func() -> void: _stand(int(tax.value), int(fee.value), slogan.text), true)
		stand_row.add_child(stand)
		if election["standing"]:
			stand_row.add_child(UI.button("Wycofaj się", _withdraw))
		var refund := _note("Kaucja wraca przy co najmniej %d%% głosów, inaczej trafia do skarbca." % int(election["depositBackPercent"]))
		refund.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stand_row.add_child(_middle(refund))
		_body.add_child(stand_row)

	var recall: Dictionary = _state["recall"]
	if _state["government"]["president"] != null:
		_body.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var count := UI.label("Wotum nieufności: %d z %d podpisów (2/3 obywateli)" % [int(recall["signatures"]), int(recall["needed"])], UI.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_middle(count))
		var sign := UI.button("Podpisz odwołanie", _recall)
		sign.tooltip_text = "Podpisz wniosek o odwołanie prezydenta"
		sign.disabled = not voter or recall["signed"]
		row.add_child(sign)
		_body.add_child(row)


## One candidate on a card: the name and the votes with the vote button beside them, under it the
## program and who backs it, each on one line.
func _candidate_card(c: Dictionary, mine: bool, voter: bool, total: int) -> Control:
	var card := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(UI.GOLD, 0.08) if mine else Color(1, 1, 1, 0.04)
	frame.set_corner_radius_all(4)
	frame.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var who := UI.label("%s%s%s" % [c["name"], " (ty)" if c["me"] else "", _party(c["party"])], UI.GOLD if mine else UI.TEXT)
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(Online.with_dot(who, c["name"]))
	var votes := int(c["votes"])
	top.add_child(_middle(UI.label("%s · %d%%" % [_votes(votes), roundi(100.0 * votes / total) if total > 0 else 0], UI.MUTED)))
	if mine:
		top.add_child(_middle(UI.label("twój głos", UI.GOLD)))
	else:
		var vote := UI.button("Głosuj", _vote.bind(str(c["name"])))
		vote.disabled = not voter
		top.add_child(vote)
	box.add_child(top)
	var program := "Podatek %s‰ · opłata od cudzoziemców %d%%" % [str(int(c["plotTaxPerMille"])), int(c["foreignerFeePercent"])]
	if str(c["slogan"]) != "":
		program += " · „%s”" % c["slogan"]
	box.add_child(_note(program))
	var sponsors: Array = c["sponsors"]
	if not sponsors.is_empty():
		var cents := 0
		for s: Dictionary in sponsors:
			cents += int(s["cents"])
		box.add_child(_note("Wsparcie: %s (%s)" % [UI.money(cents), ", ".join(sponsors.map(func(s: Dictionary) -> String: return str(s["company"])))]))
	return card


# --- Diplomacy --------------------------------------------------------------------------------

func _render_diplomacy() -> void:
	if _needs_country():
		return
	var relations: Dictionary = _state["relations"]
	for part: Array in [["allies", "Sojusznicy (bez opłat i ceł między sobą)"], ["embargoes", "Embargo nałożone przez ten kraj"],
			["embargoedBy", "Embargo na ten kraj"], ["offersMade", "Propozycje sojuszu wysłane"], ["offersGot", "Propozycje sojuszu otrzymane"]]:
		var list: Array = relations[part[0]]
		var names := list.map(func(c: Dictionary) -> String: return c["name"])
		_body.add_child(UI.label("%s: %s" % [part[1], ", ".join(names) if not names.is_empty() else "brak"], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var offices: Array = _state["me"]["offices"]
	if not ("president" in offices or "foreign" in offices):
		_body.add_child(_note("Sojusze i embarga ustala prezydent albo minister spraw zagranicznych."))
		return
	_body.add_child(HSeparator.new())
	var field := UI.line_edit("Nazwa kraju, np. Niemcy")
	_body.add_child(field)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for action: Array in [["Zaproponuj sojusz", "country.alliance", true], ["Zerwij sojusz", "country.alliance", false],
			["Nałóż embargo", "country.embargo", true], ["Znieś embargo", "country.embargo", false]]:
		row.add_child(UI.button(action[0], func() -> void: _relation(action[1], field.text, action[2])))
	_body.add_child(row)
	_body.add_child(_note("Sojusz zaczyna obowiązywać, gdy drugi kraj też go zaproponuje. Embargo: obywatele tamtego kraju nie kupią tu działek, a ich towary nie wjadą."))


# --- Ranking and parties ------------------------------------------------------------------------

func _render_ranking() -> void:
	if _ranking.is_empty():
		_body.add_child(_note("Wczytywanie..."))
		return
	_body.add_child(_note("Kraje, w których gracze mają działki, od największych."))
	var place := 0
	for c: Dictionary in _ranking["countries"]:
		place += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var president: Variant = c["president"]
		var text := UI.label("%d. %s · %d działek · %d obywateli · skarbiec %s%s" % [place, c["name"], int(c["boughtPlots"]), int(c["citizens"]),
			UI.money(int(c["treasuryCents"])), " · prezydent: %s" % president if president != null else ""], UI.GOLD if c["mine"] else UI.TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(UI.button("Pokaż", open_country.bind(str(c["code"]))))
		_body.add_child(row)


func _render_parties() -> void:
	if _parties.is_empty():
		_body.add_child(_note("Wczytywanie..."))
		return
	var mine: Variant = _parties["mine"]
	if mine != null:
		_body.add_child(UI.label("Twoja partia: %s · lider: %s" % [mine["name"], mine["leader"]], UI.GOLD))
		_body.add_child(_note("Członkowie: %s" % ", ".join(mine["members"])))
		_body.add_child(UI.button("Wystąp z partii", _leave_party))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var field := UI.line_edit("Nazwa partii")
		field.max_length = 32
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(field)
		row.add_child(UI.button("Załóż (%s)" % UI.money(int(_parties["costCents"])), func() -> void: _party_action("party.create", field.text.strip_edges())))
		row.add_child(UI.button("Dołącz", func() -> void: _party_action("party.join", field.text.strip_edges())))
		_body.add_child(row)
		_body.add_child(_note("Nazwa partii pokazuje się przy twoim imieniu w wyborach w miastach i krajach."))
	_body.add_child(HSeparator.new())
	for p: Dictionary in _parties["parties"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var text := UI.label("%s · lider %s · %d członków · prezydentów: %d" % [p["name"], p["leader"], int(p["members"]), int(p["presidents"])],
			UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		if mine == null:
			row.add_child(UI.button("Dołącz", func() -> void: _party_action("party.join", str(p["name"]))))
		_body.add_child(row)


# --- Requests ---------------------------------------------------------------------------------

func _choose_citizenship() -> void:
	if _apply(await Net.request("country.citizenship", {"country": _code})):
		toast.emit("Jesteś obywatelem: %s" % _state["name"])


func _withdraw() -> void:
	if _apply(await Net.request("country.withdraw", {"country": _code})):
		toast.emit("Wycofałeś kandydaturę, kaucja wróciła")
		balance_changed.emit()


func _stand(tax: int, fee: int, slogan: String) -> void:
	if _apply(await Net.request("country.stand", {"country": _code, "plotTaxPerMille": tax, "foreignerFeePercent": fee, "slogan": slogan})):
		toast.emit("Kandydujesz na prezydenta")
		balance_changed.emit()


func _vote(candidate: String) -> void:
	if _apply(await Net.request("country.vote", {"country": _code, "candidate": candidate})):
		toast.emit("Oddano głos na: %s" % candidate)


func _sponsor(candidate: String, cents: int) -> void:
	if _apply(await Net.request("country.sponsor", {"country": _code, "candidate": candidate, "cents": cents})):
		toast.emit("Spółka wsparła kandydata: %s" % candidate)


func _recall() -> void:
	var reply := await Net.request("country.recall", {"country": _code})
	if _apply(reply):
		toast.emit("Prezydent odwołany!" if reply["payload"]["result"]["recalled"] else "Podpisano wniosek o odwołanie")


func _set_law(law: String, value: int, item: String) -> void:
	if _apply(await Net.request("country.law", {"country": _code, "law": law, "value": value, "item": item})):
		toast.emit("Ustawiono nowe prawo")


func _appoint(office: String, name: String) -> void:
	if _apply(await Net.request("country.appoint", {"country": _code, "office": office, "name": name})):
		toast.emit("Mianowano: %s" % name if name != "" else "Urząd jest wolny")


func _invest(kind: String) -> void:
	if _apply(await Net.request("country.invest", {"country": _code, "kind": kind})):
		toast.emit("Inwestycja zbudowana ze skarbca")


func _relation(type: String, other_name: String, on: bool) -> void:
	if codes_by_name.is_empty():
		codes_by_name = WorldData.country_codes_by_name()
	var other: String = codes_by_name.get(other_name.strip_edges().to_lower(), other_name.strip_edges().to_upper())
	var reply := await Net.request(type, {"country": _code, "other": other, "on": on})
	if _apply(reply):
		var result: Variant = reply["payload"]["result"]
		if result is Dictionary and result.get("allied", false):
			toast.emit("Sojusz zawarty")
		else:
			toast.emit("Zapisano")


func _party_action(type: String, name: String) -> void:
	var reply := await Net.request(type, {"name": name})
	if reply["type"] != "party":
		failed.emit(reply)
		return
	_parties = reply["payload"]
	if type == "party.create":
		balance_changed.emit()
	_render()


func _leave_party() -> void:
	await _party_action("party.leave", "")


# --- Helpers ----------------------------------------------------------------------------------

func _office_title(office: String) -> String:
	if office == "president":
		return "prezydent"
	for m: Dictionary in _state["government"]["ministers"]:
		if m["office"] == office:
			return str(m["title"]).to_lower()
	return office


func _party(party: Variant) -> String:
	return " (%s)" % party if party != null else ""


func _subsidy_name(laws: Dictionary) -> String:
	for s: Dictionary in laws["subsidies"]:
		if s["id"] == laws["subsidy"]:
			return "%s: miasta płacą o %d%% więcej, dopłaca skarbiec" % [s["name"], int(laws["subsidyPercent"])]
	return "brak"


func _item_tariffs(tariffs: Array) -> String:
	if tariffs.is_empty():
		return ""
	return " (osobno: %s)" % ", ".join(tariffs.map(func(t: Dictionary) -> String: return "%s %d%%" % [t["name"], int(t["percent"])]))


func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.rounded = true
	spin.value = value
	spin.custom_minimum_size.x = 76
	spin.select_all_on_focus = true
	return spin


func _small(text: String, color: Color) -> Label:
	var l := UI.label(text, color, HORIZONTAL_ALIGNMENT_LEFT, true)
	l.add_theme_font_size_override("font_size", roundi(13 * UI.TOUCH_SCALE) if UI.touch() else 13)
	return l


func _note(text: String) -> Label:
	return _small(text, UI.MUTED)


func _flow() -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	return flow


## A label centred on the height of the buttons and fields beside it.
func _middle(label: Label) -> Label:
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _votes(n: int) -> String:
	if n == 1:
		return "1 głos"
	if n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		return "%d głosy" % n
	return "%d głosów" % n


## Time from now until `at` (ms since the epoch), as "5 h 12 min" or "2 dni 3 h".
func _left(at: int) -> String:
	var seconds := maxi(0, (at - int(Time.get_unix_time_from_system() * 1000.0)) / 1000)
	var days := seconds / 86400
	var hours := (seconds % 86400) / 3600
	if days > 0:
		return "%d %s %d h" % [days, "dzień" if days == 1 else "dni", hours]
	return "%d h %d min" % [hours, (seconds % 3600) / 60]
