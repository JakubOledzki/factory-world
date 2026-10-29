class_name CompanyWindow
extends GameWindow
## The player's company: members and their roles, the plots brought in, the shared warehouse and what happened
## lately; its cash, shares and dividend; the big projects, weekly orders and tasks members work on together; deals
## with other companies; the stock exchange and the rankings. Without a company: founding one, the invitations from
## others, the exchange and the rankings.

## Items went between the inventory and the warehouse.
signal inventory_changed
## Money went between the wallet and the company.
signal balance_changed
signal failed(reply: Dictionary)

const ROLE_NAMES := {"owner": "Prezes", "partner": "Wspólnik", "treasurer": "Skarbnik", "manager": "Kierownik działki",
	"logistician": "Logistyk", "worker": "Pracownik"}
const ROLE_HELP := {
	"owner": "Zaprasza i usuwa członków, nadaje role, przydziela działki kierownikom, a poza tym może to samo co wspólnik i skarbnik.",
	"partner": "Buduje na działkach spółki, ustawia rozkłady pociągów, wyjmuje z magazynu, skrzyń i stacji, wybiera badania i wielkie projekty.",
	"treasurer": "Zarządza kasą: wypłaca, kupuje i sprzedaje dla spółki, zleca zadania z pensją i podpisuje umowy z innymi spółkami.",
	"manager": "Buduje tylko na działkach, które przydzielił mu prezes; na pozostałych pracuje jak pracownik.",
	"logistician": "Ustawia rozkłady pociągów i wysyła pociągi ze wszystkich działek spółki, wyjmuje ze skrzyń i stacji.",
	"worker": "Pracuje na działkach spółki: zbiera, kopie, uprawia i obsługuje maszyny, wkłada do magazynu, ale nic nie wyjmuje i nie buduje.",
}
const TABS := ["Spółka", "Kasa", "Projekty", "Zlecenia", "Umowy", "Giełda", "Ranking"]
const DEAL_STATES := {"offered": "oferta", "active": "trwa", "done": "zakończona", "broken": "zerwana", "cancelled": "wycofana"}

var _state := {}
var _items: Array = []
## The player's own plots, from "world.info": [{x, y, biome}].
var _my_plots: Array = []
var _biome_names := {}
## Every item the trader deals in, from "market.prices": [{id, name, buyCents, sellCents}].
var _catalog: Array = []
var _exchange := {}
var _rankings := {}

var _tab := 0
var _tab_buttons: Array[Button] = []
var _tabs_row := HBoxContainer.new()
var _body := VBoxContainer.new()
var _name_edit: LineEdit
var _invite_edit: LineEdit


func _init() -> void:
	super("Spółka", 560)
	_tabs_row.add_theme_constant_override("separation", 3)
	for i in TABS.size():
		var b := UI.button(TABS[i], _show_tab.bind(i))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs_row.add_child(b)
		_tab_buttons.append(b)
	content.add_child(_tabs_row)
	_body.add_theme_constant_override("separation", 6)
	content.add_child(_body)


func show_window() -> void:
	super()
	refresh()


func refresh() -> void:
	var replies := [await Net.request("company.get"), await Net.request("inventory.get"), await Net.request("world.info")]
	if replies[1]["type"] == "inventory":
		_items = replies[1]["payload"]["items"]
	if replies[2]["type"] == "world.info":
		_my_plots = replies[2]["payload"]["plots"]
		for biome: Dictionary in replies[2]["payload"]["biomes"]:
			_biome_names[int(biome["id"])] = biome["name"]
	if _catalog.is_empty():
		var prices := await Net.request("market.prices")
		if prices["type"] == "market.prices":
			_catalog = prices["payload"]["items"]
			_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	_apply(replies[0])
	_load_tab()


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "company":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


func _show_tab(i: int) -> void:
	_tab = i
	_render()
	_load_tab()


## The exchange and the rankings come from their own messages, asked for when their tab opens.
func _load_tab() -> void:
	match TABS[_tab]:
		"Giełda":
			_apply_exchange(await Net.request("company.exchange", {}))
		"Ranking":
			var reply := await Net.request("company.rankings", {})
			if reply["type"] == "company.rankings":
				_rankings = reply["payload"]
				_render()
			else:
				failed.emit(reply)


func _apply_exchange(reply: Dictionary) -> void:
	if reply["type"] != "company.exchange":
		failed.emit(reply)
		return
	_exchange = reply["payload"]
	_render()


## Sends a company message; on success shows the new state and, when things moved, the inventory and the wallet.
func _send(type: String, payload := {}, items_moved := false, money_moved := false) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "company":
		failed.emit(reply)
		return
	if items_moved:
		var inventory := await Net.request("inventory.get")
		if inventory["type"] == "inventory":
			_items = inventory["payload"]["items"]
		inventory_changed.emit()
	if money_moved:
		balance_changed.emit()
	_apply(reply)


func _render() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == _tab)
	UI.clear(_body)
	intake.clear()
	var company: Variant = _state.get("company")
	set_title("Spółka" if company == null else "Spółka: %s" % company["name"])
	# Without a company only founding, the exchange and the rankings make sense.
	for i in _tab_buttons.size():
		_tab_buttons[i].visible = company != null or TABS[i] in ["Spółka", "Giełda", "Ranking"]
	match TABS[_tab]:
		"Spółka":
			if company == null:
				_render_without()
			else:
				_render_company(company)
		"Kasa":
			if company != null:
				_render_cash(company)
		"Projekty":
			if company != null:
				_render_projects(company)
		"Zlecenia":
			if company != null:
				_render_orders(company)
		"Umowy":
			if company != null:
				_render_deals(company)
		"Giełda":
			_render_exchange()
		"Ranking":
			_render_rankings()
	_fit.call_deferred()


func _render_without() -> void:
	_body.add_child(UI.label("Spółka to kilku graczy budujących jedną fabrykę: członkowie wnoszą swoje działki, pracują na wszystkich naraz, mają wspólny magazyn, kasę i badania.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(_heading("Załóż spółkę"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_name_edit = UI.line_edit("Nazwa spółki (3–24 znaki)")
	_name_edit.max_length = 24
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_text: String) -> void: _create())
	row.add_child(_name_edit)
	row.add_child(UI.button("Załóż", _create, true))
	_body.add_child(row)

	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Zaproszenia"))
	var invitations: Array = _state.get("invitations", [])
	if invitations.is_empty():
		_body.add_child(UI.label("Nikt cię jeszcze nie zaprosił. Prezes spółki zaprasza po nazwie postaci.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for invitation: Dictionary in invitations:
		var line := _row()
		var text := UI.label("%s  (%s)" % [invitation["name"], _members_text(int(invitation["members"]))])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		line.add_child(UI.button("Dołącz", _send.bind("company.accept", {"company": invitation["company"]}), true))
		line.add_child(UI.button("Odrzuć", _send.bind("company.decline", {"company": invitation["company"]})))
		_body.add_child(line)


func _render_company(company: Dictionary) -> void:
	var role: String = company["role"]
	var owner := role == "owner"
	var may_take := role != "worker"
	var you := UI.label("Twoja rola: %s. %s" % [ROLE_NAMES.get(role, role), ROLE_HELP.get(role, "")], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_body.add_child(you)

	# Members.
	var members: Array = company["members"]
	_body.add_child(_heading("Członkowie (%d z %d)" % [members.size(), int(_state["maxMembers"])]))
	for member: Dictionary in members:
		var line := _row()
		var who := UI.label("%s%s" % [member["name"], "  (ty)" if member["you"] else ""], UI.GOLD if member["role"] == "owner" else UI.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(Online.with_dot(who, member["name"]))
		var plots := int(member["plots"])
		if plots > 0:
			line.add_child(UI.label("działki: %d" % plots, UI.MUTED))
		if owner and not member["you"]:
			var roles := OptionButton.new()
			for id: String in ["partner", "treasurer", "manager", "logistician", "worker", "owner"]:
				roles.add_item(ROLE_NAMES[id] if id != "owner" else "Przekaż prezesurę")
				roles.set_item_metadata(roles.item_count - 1, id)
				roles.set_item_tooltip(roles.item_count - 1, ROLE_HELP[id])
				if id == member["role"]:
					roles.select(roles.item_count - 1)
			roles.item_selected.connect(func(index: int) -> void:
				_send("company.role", {"name": member["name"], "role": roles.get_item_metadata(index)}))
			line.add_child(roles)
			line.add_child(UI.button("Usuń", _send.bind("company.kick", {"name": member["name"]})))
		else:
			line.add_child(UI.label(ROLE_NAMES.get(member["role"], member["role"]), UI.MUTED))
		_body.add_child(line)
	if owner:
		var invited: Array = company["invited"]
		for name: String in invited:
			var line := _row()
			var text := UI.label("%s  (zaproszony, czeka)" % name, UI.MUTED)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(Online.with_dot(text, name))
			line.add_child(UI.button("Cofnij", _send.bind("company.uninvite", {"name": name})))
			_body.add_child(line)
		var row := _row()
		_invite_edit = UI.line_edit("Nazwa postaci")
		_invite_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_invite_edit.text_submitted.connect(func(_text: String) -> void: _invite())
		row.add_child(_invite_edit)
		row.add_child(UI.button("Zaproś", _invite, true))
		_body.add_child(row)

	# Plots.
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Działki spółki"))
	var plots: Array = company["plots"]
	if plots.is_empty():
		_body.add_child(UI.label("Żadnej jeszcze nie wniesiono. Wnieś swoją działkę, żeby inni mogli na niej pracować; za jej cenę dostaniesz udziały.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var brought := {}
	for plot: Dictionary in plots:
		var at := Vector2i(int(plot["x"]), int(plot["y"]))
		brought[at] = true
		var line := _row()
		var text := UI.label("%s %d:%d  ·  %s" % [_biome_names.get(int(plot["biome"]), "Działka"), at.x, at.y, "twoja" if plot["mine"] else plot["owner"]])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text if plot["mine"] else Online.with_dot(text, plot["owner"]))
		if owner:
			var managers := OptionButton.new()
			managers.tooltip_text = "Kierownik działki buduje tylko na działkach, które mu przydzielisz."
			managers.add_item("Kierownik: nikt")
			managers.set_item_metadata(0, "")
			for member: Dictionary in members:
				if member["role"] == "manager":
					managers.add_item("Kierownik: %s" % member["name"])
					managers.set_item_metadata(managers.item_count - 1, member["name"])
					if plot.get("manager") == member["name"]:
						managers.select(managers.item_count - 1)
			managers.item_selected.connect(func(index: int) -> void:
				_send("company.assign", {"x": at.x, "y": at.y, "name": managers.get_item_metadata(index)}))
			line.add_child(managers)
		elif plot.get("manager") != null:
			line.add_child(Online.with_dot(UI.label("kierownik: %s" % plot["manager"], UI.MUTED), plot["manager"]))
		line.add_child(UI.button("Wejdź", func() -> void: Game.enter_plot(at)))
		if plot["mine"]:
			var b := UI.button("Zabierz", _send.bind("company.removePlot", {"x": at.x, "y": at.y}))
			b.tooltip_text = "Działka przestanie być wspólna. To, co postawili na niej inni, zostanie na miejscu."
			line.add_child(b)
		_body.add_child(line)
	for plot: Dictionary in _my_plots:
		var at := Vector2i(int(plot["x"]), int(plot["y"]))
		if brought.has(at):
			continue
		var line := _row()
		var text := UI.label("%s %d:%d  ·  tylko twoja" % [_biome_names.get(int(plot["biome"]), "Działka"), at.x, at.y], UI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		line.add_child(UI.button("Wnieś do spółki", _send.bind("company.addPlot", {"x": at.x, "y": at.y})))
		_body.add_child(line)

	# Warehouse.
	var warehouse: Dictionary = company["warehouse"]
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Wspólny magazyn"))
	_body.add_child(_progress(float(warehouse["stored"]), float(warehouse["capacity"])))
	_body.add_child(UI.label("Zapełnienie: %d z %d sztuk" % [int(warehouse["stored"]), int(warehouse["capacity"])], UI.MUTED))
	var stock: Array = warehouse["items"]
	if stock.is_empty():
		_body.add_child(UI.label("Pusto.", UI.MUTED))
	for stack: Dictionary in stock:
		var line := _item_row(stack["id"], "%s  ×%d" % [stack["name"], int(stack["quantity"])])
		if may_take:
			for amount: int in [10, 0]:
				var count := int(stack["quantity"]) if amount == 0 else amount
				var b := UI.button("Wszystko" if amount == 0 else "Weź %d" % amount, _send.bind("company.take", {"item": stack["id"], "quantity": count}, true), amount == 0)
				b.disabled = count > int(stack["quantity"])
				line.add_child(b)
		_body.add_child(line)
	if not may_take:
		_body.add_child(UI.label("Jako pracownik tylko wkładasz do magazynu; wyjmują pozostałe role.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(_heading("Włóż z ekwipunku"))
	var room := int(warehouse["capacity"]) - int(warehouse["stored"])
	if _items.is_empty():
		_body.add_child(UI.label("Ekwipunek jest pusty.", UI.MUTED))
	for stack: Dictionary in _items:
		var owned := int(stack["quantity"])
		var line := _item_row(stack["id"], "%s  ×%d" % [stack["name"], owned])
		var id: String = stack["id"]
		offer(id, room, func(quantity: int) -> void: _send("company.put", {"item": id, "quantity": quantity}, true))
		for amount: int in [1, 10, 0]:
			var count := mini(owned, room) if amount == 0 else amount
			var b := UI.button("Wszystko" if amount == 0 else "+%d" % amount, _send.bind("company.put", {"item": stack["id"], "quantity": count}, true))
			b.disabled = count < 1 or count > owned or count > room
			line.add_child(b)
		_body.add_child(line)

	# Log.
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Ostatnio w spółce"))
	for entry: Dictionary in company["log"]:
		var line := _row(8)
		var when := UI.label(_ago(int(entry["at"])), UI.MUTED)
		when.custom_minimum_size.x = 90
		line.add_child(when)
		line.add_child(UI.label(_log_text(entry), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		line.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(line)

	_body.add_child(HSeparator.new())
	var leave_text := "Zamknij spółkę" if members.size() == 1 else "Opuść spółkę"
	var leave := UI.button(leave_text, _send.bind("company.leave", {}, members.size() == 1, members.size() == 1))
	if members.size() == 1:
		leave.tooltip_text = "Jesteś ostatnim członkiem: to, co jest w magazynie, wróci do twojego ekwipunku, a kasa do portfela."
	elif owner:
		leave.tooltip_text = "Najpierw przekaż prezesurę innemu członkowi."
	else:
		leave.tooltip_text = "Twoje działki przestaną być wspólne; udziały zostaną twoje."
	_body.add_child(leave)


# --- Cash and shares -----------------------------------------------------------------------------

func _render_cash(company: Dictionary) -> void:
	var economy: Dictionary = company["economy"]
	var money: bool = company["money"]
	var owner: bool = company["role"] == "owner"
	_body.add_child(_heading("Kasa spółki: %s" % UI.money(int(economy["cashCents"]))))
	_body.add_child(UI.label("Zarobione od ostatniej dywidendy: %s. Zarobione w ostatnim tygodniu: %s. Wartość spółki: %s (kasa, magazyn po cenach handlarza i dziesięć razy tygodniowy zarobek)." % [
		UI.money(int(economy["incomeCents"])), UI.money(int(economy["profitCents"])), UI.money(int(economy["valueCents"]))],
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))

	_body.add_child(_heading("Wpłata"))
	_body.add_child(UI.label("Każdy członek może wpłacić pieniądze do kasy i dostaje za nie nowe udziały po %s za udział." % UI.money(int(economy["sharePriceCents"])),
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var deposit := _money_row("Wpłać", func(cents: int) -> void: _send("company.deposit", {"cents": cents}, false, true))
	_body.add_child(deposit)
	if money:
		_body.add_child(_heading("Wypłata"))
		_body.add_child(UI.label("Pieniądze z kasy na twój portfel, np. żeby kupić działkę dla spółki.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		_body.add_child(_money_row("Wypłać", func(cents: int) -> void: _send("company.withdraw", {"cents": cents}, false, true)))

	# Selling from the warehouse and buying into it.
	if company["role"] != "worker":
		_body.add_child(HSeparator.new())
		_body.add_child(_heading("Sprzedaż z magazynu handlarzowi"))
		var sold := 0
		for stack: Dictionary in company["warehouse"]["items"]:
			var price := _trader_buys(stack["id"])
			if price <= 0:
				continue
			sold += 1
			var line := _item_row(stack["id"], "%s  ×%d  ·  %s za sztukę" % [stack["name"], int(stack["quantity"]), UI.money(price)])
			for amount: int in [10, 0]:
				var count := int(stack["quantity"]) if amount == 0 else amount
				var b := UI.button("Wszystko" if amount == 0 else "Sprzedaj %d" % amount, _send.bind("company.sell", {"item": stack["id"], "quantity": count}))
				b.disabled = count > int(stack["quantity"])
				line.add_child(b)
			_body.add_child(line)
		if sold == 0:
			_body.add_child(UI.label("W magazynie nie ma nic, co handlarz kupuje.", UI.MUTED))
	if money:
		_body.add_child(_heading("Zakup do magazynu"))
		var row := _row()
		var items := _catalog_picker(func(entry: Dictionary) -> bool: return entry.get("buyCents") != null)
		row.add_child(items)
		var quantity := _spin(1, 10000, 100)
		row.add_child(quantity)
		row.add_child(UI.button("Kup z kasy", func() -> void:
			_send("company.buy", {"item": items.get_item_metadata(items.selected), "quantity": int(quantity.value)}), true))
		_body.add_child(row)

	# Shares.
	var shares: Dictionary = economy["shares"]
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Udziały (%d)" % int(shares["total"])))
	for holder: Dictionary in shares["holders"]:
		var line := _row()
		var text := UI.label("%s%s" % [holder["name"], "  (ty)" if holder["you"] else ""])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(Online.with_dot(text, holder["name"]))
		line.add_child(UI.label("%d  ·  %s%%" % [int(holder["shares"]), str(holder["percent"]).replace(".", ",")], UI.MUTED))
		_body.add_child(line)

	_body.add_child(_heading("Dywidenda"))
	_body.add_child(UI.label("Raz na dobę %d%% tego, co spółka zarobiła, trafia do udziałowców według udziałów. Następna: %s." % [
		int(economy["dividendPercent"]), _in(int(economy["nextDividendAt"]))], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if owner:
		var row := _row()
		row.add_child(UI.label("Część zarobku na dywidendę (%):"))
		var percent := _spin(0, 100, int(economy["dividendPercent"]))
		row.add_child(percent)
		row.add_child(UI.button("Ustaw", func() -> void: _send("company.dividend", {"percent": int(percent.value)})))
		_body.add_child(row)

	var trophies: Array = economy["trophies"]
	if not trophies.is_empty():
		_body.add_child(_heading("Trofea sezonów"))
		for trophy: Dictionary in trophies:
			_body.add_child(UI.label("%s: %d. miejsce (%s zarobku)" % [_season_name(int(trophy["season"])), int(trophy["place"]), UI.money(int(trophy["valueCents"]))], UI.GOLD))


# --- Big projects ---------------------------------------------------------------------------------

func _render_projects(company: Dictionary) -> void:
	var economy: Dictionary = company["economy"]
	var may_take: bool = company["role"] != "worker"
	_body.add_child(UI.label("Wielkie budowy, których nikt nie postawi sam: członkowie znoszą tysiące części, a potem budowa trwa kilka dni.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if not economy["mayBuild"]:
		_body.add_child(UI.label("Najpierw spółka musi zbadać Wielkie budowy (technologia tylko dla spółek, w drzewku badań).", UI.ERROR, HORIZONTAL_ALIGNMENT_LEFT, true))
	var now := Time.get_unix_time_from_system() * 1000.0
	for project: Dictionary in economy["projects"]:
		_body.add_child(HSeparator.new())
		var built_at: Variant = project["builtAt"]
		var status := "nierozpoczęty"
		if built_at != null:
			status = "gotowy" if float(built_at) <= now else "w budowie, gotowy %s" % _in(int(built_at))
		elif project["started"]:
			status = "zbieranie części"
		var taken_by: Variant = project.get("takenBy")
		if taken_by != null:
			status = "zbudowała już spółka %s" % taken_by
		_body.add_child(_heading("%s%s  (%s)" % ["Cud świata: " if project.get("wonder", false) else "", project["name"], status]))
		_body.add_child(UI.label("%s Budowa trwa %d dni." % [project["description"], int(float(project["buildSeconds"]) / 86400.0)], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		var requires: Array = project.get("requires", [])
		if not requires.is_empty():
			_body.add_child(UI.label("Wymaga: %s." % ", ".join(requires), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		if project.get("wonder", false) and taken_by == null:
			_body.add_child(UI.label("Wyścig spółek: buduje tylko ta, która pierwsza zbierze wszystkie części. Pozostałe dostaną swoje części z powrotem do magazynu.",
				UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
		if taken_by != null:
			continue
		if not project["started"]:
			if company["leads"] and economy["mayBuild"]:
				_body.add_child(UI.button("Rozpocznij projekt", _send.bind("company.project.start", {"project": project["id"]}), true))
		for part: Dictionary in project["parts"]:
			var needed := int(part["needed"])
			var delivered := int(part["delivered"])
			var line := _item_row(part["id"], "%s  %d/%d" % [part["name"], delivered, needed])
			if project["started"] and built_at == null and delivered < needed:
				var owned := _owned(part["id"])
				var give := UI.button("Z ekwipunku", _send.bind("company.project.give", {"project": project["id"], "item": part["id"], "quantity": mini(owned, needed - delivered)}, true))
				give.disabled = owned < 1
				line.add_child(give)
				if may_take:
					var stored := _stored(company, part["id"])
					var from := UI.button("Z magazynu", _send.bind("company.project.give", {"project": project["id"], "item": part["id"],
						"quantity": mini(stored, needed - delivered), "fromWarehouse": true}))
					from.disabled = stored < 1
					line.add_child(from)
			_body.add_child(line)
			_body.add_child(_progress(delivered, needed))


# --- Orders and tasks -----------------------------------------------------------------------------

func _render_orders(company: Dictionary) -> void:
	var economy: Dictionary = company["economy"]
	var may_take: bool = company["role"] != "worker"
	_body.add_child(_heading("Zlecenia tygodnia"))
	_body.add_child(UI.label("Duże zamówienia handlarza tylko dla spółek: dostarcz całość z magazynu do końca tygodnia, a nagroda trafi do kasy.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for order: Dictionary in economy["orders"]:
		var quantity := int(order["quantity"])
		var delivered := int(order["delivered"])
		var line := _item_row(order["id"], "%s  %d/%d  ·  nagroda %s  ·  do %s" % [order["name"], delivered, quantity, UI.money(int(order["rewardCents"])),
			_in(int(order["endsAt"]))])
		if may_take and delivered < quantity:
			var stored := _stored(company, order["id"])
			var b := UI.button("Dostarcz z magazynu", _send.bind("company.order.deliver", {"slot": order["slot"], "quantity": mini(stored, quantity - delivered)}))
			b.disabled = stored < 1
			line.add_child(b)
		elif delivered >= quantity:
			line.add_child(UI.label("wykonane", UI.GOOD))
		_body.add_child(line)
		_body.add_child(_progress(delivered, quantity))

	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Zadania z pensją"))
	_body.add_child(UI.label("Przynieś do magazynu tyle sztuk, ile chce zadanie, a pensja z kasy przyjdzie od razu, za każdą sztukę po równo.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var tasks: Array = economy["tasks"]
	if tasks.is_empty():
		_body.add_child(UI.label("Nie ma żadnych zadań.", UI.MUTED))
	for task: Dictionary in tasks:
		var quantity := int(task["quantity"])
		var delivered := int(task["delivered"])
		var who := "dla każdego" if task["assignee"] == null else "dla: %s" % task["assignee"]
		var line := _item_row(task["item"], "%s  %d/%d  ·  pensja %s  ·  %s" % [task["name"], delivered, quantity, UI.money(int(task["wageCents"])), who])
		if task["done"]:
			line.add_child(UI.label("wykonane", UI.GOOD))
		else:
			if task["yours"]:
				var owned := _owned(task["item"])
				var b := UI.button("Przynieś", _send.bind("company.task.deliver", {"id": task["id"], "quantity": mini(owned, quantity - delivered)}, true, true), true)
				b.disabled = owned < 1
				line.add_child(b)
			if company["money"]:
				line.add_child(UI.button("Odwołaj", _send.bind("company.task.cancel", {"id": task["id"]})))
		_body.add_child(line)
	if company["money"]:
		_body.add_child(_heading("Nowe zadanie"))
		var row := _row()
		var items := _catalog_picker(func(_entry: Dictionary) -> bool: return true)
		row.add_child(items)
		var quantity := _spin(1, 100000, 500)
		quantity.tooltip_text = "Ile sztuk"
		row.add_child(quantity)
		_body.add_child(row)
		var second := _row()
		second.add_child(UI.label("Pensja ($):"))
		var wage := _spin(0, 1000000, 100)
		second.add_child(wage)
		var assignee := OptionButton.new()
		assignee.add_item("Dla każdego")
		assignee.set_item_metadata(0, "")
		for member: Dictionary in company["members"]:
			assignee.add_item(member["name"])
			assignee.set_item_metadata(assignee.item_count - 1, member["name"])
		second.add_child(assignee)
		second.add_child(UI.button("Zleć", func() -> void:
			_send("company.task.create", {"item": items.get_item_metadata(items.selected), "quantity": int(quantity.value),
				"wageCents": int(wage.value) * 100, "name": assignee.get_item_metadata(assignee.selected)}), true))
		_body.add_child(second)


# --- Deals ----------------------------------------------------------------------------------------

func _render_deals(company: Dictionary) -> void:
	var economy: Dictionary = company["economy"]
	_body.add_child(UI.label("Stałe umowy z innymi spółkami: co dobę towar przechodzi z magazynu dostawcy do magazynu kupca, a pieniądze w drugą stronę. Dostawca, któremu zabraknie towaru, płaci kupcowi połowę dziennej ceny; kupiec bez pieniędzy zrywa umowę.",
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var deals: Array = economy["deals"]
	if deals.is_empty():
		_body.add_child(UI.label("Spółka nie ma jeszcze żadnych umów.", UI.MUTED))
	for deal: Dictionary in deals:
		var line := _item_row(deal["item"], "%s %s: %d × %s dziennie za %s, %d dni  ·  %s%s" % [
			"Dostarczamy do" if deal["weSupply"] else "Kupujemy od", deal["other"], int(deal["perDay"]), deal["name"], UI.money(int(deal["priceCents"])),
			int(deal["days"]), DEAL_STATES.get(deal["state"], deal["state"]),
			"" if deal["state"] == "offered" else " (%d/%d, braki: %d)" % [int(deal["settled"]), int(deal["days"]), int(deal["missed"])]])
		if deal["state"] == "offered" and company["money"]:
			if not deal["offeredByUs"]:
				line.add_child(UI.button("Przyjmij", _send.bind("company.deal.accept", {"id": deal["id"]}), true))
			line.add_child(UI.button("Wycofaj" if deal["offeredByUs"] else "Odrzuć", _send.bind("company.deal.cancel", {"id": deal["id"]})))
		_body.add_child(line)
	if not company["money"]:
		return
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Nowa oferta"))
	var row := _row()
	var side := OptionButton.new()
	side.add_item("Sprzedajemy")
	side.add_item("Kupujemy")
	row.add_child(side)
	var other := UI.line_edit("Nazwa drugiej spółki")
	other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(other)
	_body.add_child(row)
	var second := _row()
	var items := _catalog_picker(func(_entry: Dictionary) -> bool: return true)
	second.add_child(items)
	second.add_child(UI.label("dziennie:"))
	var per_day := _spin(1, 10000, 100)
	second.add_child(per_day)
	_body.add_child(second)
	var third := _row()
	third.add_child(UI.label("Cena za dzień ($):"))
	var price := _spin(0, 1000000, 100)
	third.add_child(price)
	third.add_child(UI.label("dni:"))
	var days := _spin(1, 30, 7)
	third.add_child(days)
	third.add_child(UI.button("Wyślij ofertę", func() -> void:
		_send("company.deal.offer", {"company": other.text.strip_edges(), "item": items.get_item_metadata(items.selected), "perDay": int(per_day.value),
			"priceCents": int(price.value) * 100, "days": int(days.value), "sell": side.selected == 0}), true))
	_body.add_child(third)


# --- Stock exchange -------------------------------------------------------------------------------

func _render_exchange() -> void:
	var company: Variant = _state.get("company")
	_body.add_child(UI.label("Spółki na giełdzie sprzedają nowe akcje każdemu: pieniądze trafiają do ich kasy, a akcje dają dywidendę. Spółka odkupuje akcje za %d%% ich ceny, jeśli ma pieniądze. Kto ma ponad połowę akcji, może przejąć spółkę." % int(_exchange.get("buybackPercent", 95)),
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	if company != null and company["role"] == "owner":
		var economy: Dictionary = company["economy"]
		if economy["listed"]:
			_body.add_child(UI.button("Wycofaj spółkę z giełdy", _send.bind("company.list", {"listed": false})))
		elif economy["mayList"]:
			_body.add_child(UI.button("Wprowadź spółkę na giełdę", _send.bind("company.list", {"listed": true}), true))
		else:
			_body.add_child(UI.label("Żeby wejść na giełdę, spółka musi zbadać Finanse korporacyjne.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var companies: Array = _exchange.get("companies", [])
	if companies.is_empty():
		_body.add_child(UI.label("Na giełdzie nie ma jeszcze żadnej spółki.", UI.MUTED))
	for listed: Dictionary in companies:
		_body.add_child(HSeparator.new())
		var title := "%s%s" % [listed["name"], "  (twoja spółka)" if listed["mine"] else ""]
		_body.add_child(_heading(title))
		_body.add_child(UI.label("Akcja: %s  ·  akcji: %d  ·  wartość: %s  ·  zarobek w tygodniu: %s  ·  masz: %d%s" % [
			UI.money(int(listed["priceCents"])), int(listed["shares"]), UI.money(int(listed["valueCents"])), UI.money(int(listed["profitCents"])),
			int(listed["yours"]), "" if listed["listed"] else "  ·  poza giełdą"], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := _row()
		var count := _spin(1, 1000000, 10)
		row.add_child(count)
		var buy := UI.button("Kup", func() -> void: _trade("company.shares.buy", listed["id"], int(count.value)), true)
		buy.disabled = not listed["listed"]
		row.add_child(buy)
		var sell := UI.button("Sprzedaj", func() -> void: _trade("company.shares.sell", listed["id"], int(count.value)))
		sell.disabled = int(listed["yours"]) < 1
		row.add_child(sell)
		if int(listed["yours"]) * 2 > int(listed["shares"]):
			row.add_child(UI.button("Przejmij spółkę", func() -> void:
				await _send("company.takeover", {"company": listed["id"]})
				_load_tab()))
		_body.add_child(row)


func _trade(type: String, company: String, shares: int) -> void:
	var reply := await Net.request(type, {"company": company, "shares": shares})
	_apply_exchange(reply)
	if reply["type"] == "company.exchange":
		balance_changed.emit()
		_apply(await Net.request("company.get"))


# --- Rankings -------------------------------------------------------------------------------------

func _render_rankings() -> void:
	if _rankings.is_empty():
		return
	var prizes: Array = _rankings["prizesCents"]
	_body.add_child(UI.label("Sezon %s kończy się %s. Trzy spółki, które zarobią w nim najwięcej, dostaną do kasy %s, %s i %s oraz trofeum." % [
		_season_name(int(_rankings["season"])), _in(int(_rankings["endsAt"])), UI.money(int(prizes[0])), UI.money(int(prizes[1])), UI.money(int(prizes[2]))],
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for list: Array in [["Największy zarobek w sezonie", "production", true], ["Najbogatsze spółki", "richest", true], ["Najwięcej działek", "plots", false],
			["Zwycięzcy poprzedniego sezonu", "lastSeason", true]]:
		_body.add_child(_heading(list[0]))
		var entries: Array = _rankings[list[1]]
		if entries.is_empty():
			_body.add_child(UI.label("Nikogo jeszcze nie ma.", UI.MUTED))
		for entry: Dictionary in entries:
			var line := _row()
			var text := UI.label("%d. %s" % [int(entry["place"]), entry["name"]], UI.GOLD if entry["yours"] else UI.TEXT)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(text)
			line.add_child(UI.label(UI.money(int(entry["value"])) if list[2] else str(int(entry["value"])), UI.MUTED))
			_body.add_child(line)


# --- Helpers --------------------------------------------------------------------------------------

func _create() -> void:
	_send("company.create", {"name": _name_edit.text.strip_edges()})


func _invite() -> void:
	var name := _invite_edit.text.strip_edges()
	if name != "":
		_send("company.invite", {"name": name})


func _owned(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


static func _stored(company: Dictionary, item: String) -> int:
	for stack: Dictionary in company["warehouse"]["items"]:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


## What the trader pays for one piece, in cents; 0 when it buys none.
func _trader_buys(item: String) -> int:
	for entry: Dictionary in _catalog:
		if entry["id"] == item:
			return int(entry["sellCents"]) if entry.get("sellCents") != null else 0
	return 0


func _catalog_picker(keep: Callable) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.fit_to_longest_item = false
	for entry: Dictionary in _catalog:
		if keep.call(entry):
			picker.add_icon_item(UI.item_texture(entry["id"]), entry["name"])
			picker.set_item_metadata(picker.item_count - 1, entry["id"])
	return picker


func _money_row(text: String, on_amount: Callable) -> HBoxContainer:
	var row := _row()
	row.add_child(UI.label("$"))
	var amount := _spin(1, 10000000, 100)
	amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(amount)
	row.add_child(UI.button(text, func() -> void: on_amount.call(int(amount.value) * 100), true))
	return row


static func _spin(low: int, high: int, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.value = value
	spin.custom_minimum_size.x = 110
	return spin


static func _row(separation := 6) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	return row


static func _item_row(item: String, text: String) -> HBoxContainer:
	var line := _row()
	line.add_child(UI.item_icon(item, 26))
	var label := UI.label(text, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(label)
	return line


static func _progress(value: float, most: float) -> ProgressBar:
	var fill := ProgressBar.new()
	fill.show_percentage = false
	fill.custom_minimum_size.y = 8
	fill.max_value = maxf(most, 1.0)
	fill.value = value
	return fill


static func _log_text(entry: Dictionary) -> String:
	var who: String = entry["who"]
	var other: String = str(entry["other"]) if entry["other"] != null else "?"
	var quantity := int(entry["quantity"])
	var name: String = str(entry["name"]) if entry.get("name") != null else str(entry["item"])
	match entry["action"]:
		"founded":
			return "%s zakłada spółkę" % who
		"joined":
			return "%s dołącza do spółki" % who
		"left":
			return "%s odchodzi ze spółki" % who
		"kicked":
			return "%s usuwa ze spółki gracza %s" % [who, other]
		"role":
			return "%s: %s ma teraz rolę %s" % [who, other, ROLE_NAMES.get(entry["item"], "?").to_lower()]
		"plotAdded":
			return "%s wnosi działkę %s (udziały: %d)" % [who, entry["item"], quantity]
		"plotRemoved":
			return "%s zabiera działkę %s" % [who, entry["item"]]
		"put":
			return "%s wkłada %d × %s" % [who, quantity, name]
		"take":
			return "%s wyjmuje %d × %s" % [who, quantity, name]
		"deposit":
			return "%s wpłaca %s" % [who, UI.money(quantity)]
		"withdraw":
			return "%s wypłaca %s" % [who, UI.money(quantity)]
		"sell":
			return "%s sprzedaje handlarzowi %d × %s" % [who, quantity, name]
		"buy":
			return "%s kupuje u handlarza %d × %s" % [who, quantity, name]
		"dividend":
			return "Dywidenda: udziałowcy dostają %s" % UI.money(quantity)
		"dividendSet":
			return "%s ustawia dywidendę na %d%%" % [who, quantity]
		"assigned":
			return "%s: działka %s ma kierownika %s" % [who, entry["item"], other if entry["other"] != null else "(nikt)"]
		"listed":
			return "%s wprowadza spółkę na giełdę" % who
		"delisted":
			return "%s wycofuje spółkę z giełdy" % who
		"sharesBought":
			return "%s kupuje %d akcji" % [who, quantity]
		"sharesSold":
			return "%s sprzedaje spółce %d akcji" % [who, quantity]
		"takeover":
			return "%s przejmuje spółkę" % who
		"projectStarted":
			return "%s rozpoczyna wielki projekt" % who
		"projectPart":
			return "%s dokłada do projektu %d × %s" % [who, quantity, name]
		"projectDone":
			return "Wielki projekt gotowy!"
		"wonderLost":
			return "Inna spółka zbudowała cud świata pierwsza; części wróciły do magazynu"
		"order", "orderPart":
			return "%s dostarcza zlecenie: %s%s" % [who, name, " (nagroda %s)" % UI.money(quantity) if entry["action"] == "order" else " × %d" % quantity]
		"task":
			return "%s zleca zadanie: %d × %s%s" % [who, quantity, name, "" if entry["other"] == null else " dla %s" % other]
		"taskPart", "taskDone":
			return "%s przynosi %d × %s do zadania%s" % [who, quantity, name, " i kończy je" if entry["action"] == "taskDone" else ""]
		"taskCancelled":
			return "%s odwołuje zadanie: %s" % [who, name]
		"dealOffered":
			return "%s wysyła ofertę umowy: %s" % [who, name]
		"dealAccepted":
			return "%s przyjmuje umowę" % who
		"dealMissed":
			return "Umowa: zabrakło towaru (%s), kara %s" % [name, UI.money(quantity)]
		"dealBroken":
			return "Umowa na %s zerwana: kupcowi zabrakło pieniędzy" % name
		"season":
			return "Sezon %s: %d. miejsce i nagroda w kasie!" % [_season_name(int(entry["item"])), quantity]
	return "%s: %s" % [who, entry["action"]]


static func _season_name(season: int) -> String:
	const MONTHS := ["styczeń", "luty", "marzec", "kwiecień", "maj", "czerwiec", "lipiec", "sierpień", "wrzesień", "październik", "listopad", "grudzień"]
	return "%s %d" % [MONTHS[season % 100 - 1], season / 100]


static func _ago(at_ms: int) -> String:
	var seconds := int(Time.get_unix_time_from_system() - at_ms / 1000.0)
	if seconds < 60:
		return "przed chwilą"
	if seconds < 3600:
		return "%d min temu" % (seconds / 60)
	if seconds < 86400:
		return "%d godz. temu" % (seconds / 3600)
	return "%d dni temu" % (seconds / 86400)


static func _in(at_ms: int) -> String:
	var seconds := int(at_ms / 1000.0 - Time.get_unix_time_from_system())
	if seconds <= 0:
		return "teraz"
	if seconds < 3600:
		return "za %d min" % maxi(1, seconds / 60)
	if seconds < 86400:
		return "za %d godz." % (seconds / 3600)
	return "za %d dni" % (seconds / 86400)


static func _members_text(count: int) -> String:
	if count == 1:
		return "1 członek"
	if count % 10 in [2, 3, 4] and not count % 100 in [12, 13, 14]:
		return "%d członkowie" % count
	return "%d członków" % count


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
