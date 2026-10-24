class_name CompanyWindow
extends GameWindow
## The player's company: members and their roles, the plots brought in, the shared warehouse and
## what happened lately. Without a company: founding one and the invitations from others.

## Items went between the inventory and the warehouse.
signal inventory_changed
signal failed(reply: Dictionary)

const ROLE_NAMES := {"owner": "Prezes", "partner": "Wspólnik", "worker": "Pracownik"}
const ROLE_HELP := {
	"owner": "Zaprasza i usuwa członków, nadaje role, a poza tym może to samo co wspólnik.",
	"partner": "Buduje na działkach spółki i wyjmuje z magazynu, skrzyń i stacji.",
	"worker": "Pracuje na działkach spółki: zbiera, kopie, uprawia i obsługuje maszyny, wkłada do magazynu, ale nic nie wyjmuje i nie buduje.",
}

var _state := {}
var _items: Array = []
## The player's own plots, from "world.info": [{x, y, biome}].
var _my_plots: Array = []
var _biome_names := {}

var _body := VBoxContainer.new()
var _name_edit: LineEdit
var _invite_edit: LineEdit


func _init() -> void:
	super("Spółka", 520)
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
	_apply(replies[0])


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "company":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()


## Sends a company message; on success shows the new state and, for the warehouse, the inventory.
func _send(type: String, payload := {}, items_moved := false) -> void:
	var reply := await Net.request(type, payload)
	if reply["type"] != "company":
		failed.emit(reply)
		return
	if items_moved:
		var inventory := await Net.request("inventory.get")
		if inventory["type"] == "inventory":
			_items = inventory["payload"]["items"]
		inventory_changed.emit()
	_apply(reply)


func _render() -> void:
	UI.clear(_body)
	var company: Variant = _state.get("company")
	if company == null:
		set_title("Spółka")
		_render_without()
	else:
		set_title("Spółka: %s" % company["name"])
		_render_company(company)
	_fit.call_deferred()


func _render_without() -> void:
	_body.add_child(UI.label("Spółka to kilku graczy budujących jedną fabrykę: członkowie wnoszą swoje działki, pracują na wszystkich naraz i mają wspólny magazyn.",
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
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
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
	var you := UI.label("Twoja rola: %s. %s" % [ROLE_NAMES[role], ROLE_HELP[role]], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	_body.add_child(you)

	# Members.
	var members: Array = company["members"]
	_body.add_child(_heading("Członkowie (%d z %d)" % [members.size(), int(_state["maxMembers"])]))
	for member: Dictionary in members:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var who := UI.label("%s%s" % [member["name"], "  (ty)" if member["you"] else ""], UI.GOLD if member["role"] == "owner" else UI.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(who)
		var plots := int(member["plots"])
		if plots > 0:
			line.add_child(UI.label("działki: %d" % plots, UI.MUTED))
		if owner and not member["you"]:
			var roles := OptionButton.new()
			for id: String in ["partner", "worker", "owner"]:
				roles.add_item(ROLE_NAMES[id] if id != "owner" else "Przekaż prezesurę")
				roles.set_item_metadata(roles.item_count - 1, id)
				if id == member["role"]:
					roles.select(roles.item_count - 1)
			roles.item_selected.connect(func(index: int) -> void:
				_send("company.role", {"name": member["name"], "role": roles.get_item_metadata(index)}))
			line.add_child(roles)
			line.add_child(UI.button("Usuń", _send.bind("company.kick", {"name": member["name"]})))
		else:
			line.add_child(UI.label(ROLE_NAMES[member["role"]], UI.MUTED))
		_body.add_child(line)
	if owner:
		var invited: Array = company["invited"]
		for name: String in invited:
			var line := HBoxContainer.new()
			var text := UI.label("%s  (zaproszony, czeka)" % name, UI.MUTED)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(text)
			line.add_child(UI.button("Cofnij", _send.bind("company.uninvite", {"name": name})))
			_body.add_child(line)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
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
		_body.add_child(UI.label("Żadnej jeszcze nie wniesiono. Wnieś swoją działkę, żeby inni mogli na niej pracować.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var brought := {}
	for plot: Dictionary in plots:
		var at := Vector2i(int(plot["x"]), int(plot["y"]))
		brought[at] = true
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var text := UI.label("%s %d:%d  ·  %s" % [_biome_names.get(int(plot["biome"]), "Działka"), at.x, at.y, "twoja" if plot["mine"] else plot["owner"]])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
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
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var text := UI.label("%s %d:%d  ·  tylko twoja" % [_biome_names.get(int(plot["biome"]), "Działka"), at.x, at.y], UI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		line.add_child(UI.button("Wnieś do spółki", _send.bind("company.addPlot", {"x": at.x, "y": at.y})))
		_body.add_child(line)

	# Warehouse.
	var warehouse: Dictionary = company["warehouse"]
	_body.add_child(HSeparator.new())
	_body.add_child(_heading("Wspólny magazyn"))
	var fill := ProgressBar.new()
	fill.show_percentage = false
	fill.custom_minimum_size.y = 10
	fill.max_value = float(warehouse["capacity"])
	fill.value = float(warehouse["stored"])
	_body.add_child(fill)
	_body.add_child(UI.label("Zapełnienie: %d z %d sztuk" % [int(warehouse["stored"]), int(warehouse["capacity"])], UI.MUTED))
	var stock: Array = warehouse["items"]
	if stock.is_empty():
		_body.add_child(UI.label("Pusto.", UI.MUTED))
	for stack: Dictionary in stock:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UI.item_icon(stack["id"], 28))
		var text := UI.label("%s  ×%d" % [stack["name"], int(stack["quantity"])])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if may_take:
			for amount: int in [10, 0]:
				var count := int(stack["quantity"]) if amount == 0 else amount
				var b := UI.button("Wszystko" if amount == 0 else "Weź %d" % amount, _send.bind("company.take", {"item": stack["id"], "quantity": count}, true), amount == 0)
				b.disabled = count > int(stack["quantity"])
				line.add_child(b)
		_body.add_child(line)
	if not may_take:
		_body.add_child(UI.label("Jako pracownik tylko wkładasz do magazynu; wyjmują prezes i wspólnicy.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_body.add_child(_heading("Włóż z ekwipunku"))
	var room := int(warehouse["capacity"]) - int(warehouse["stored"])
	if _items.is_empty():
		_body.add_child(UI.label("Ekwipunek jest pusty.", UI.MUTED))
	for stack: Dictionary in _items:
		var owned := int(stack["quantity"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(UI.item_icon(stack["id"], 26))
		var text := UI.label("%s  ×%d" % [stack["name"], owned])
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
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
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var when := UI.label(_ago(int(entry["at"])), UI.MUTED)
		when.custom_minimum_size.x = 90
		line.add_child(when)
		line.add_child(UI.label(_log_text(entry), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		line.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(line)

	_body.add_child(HSeparator.new())
	var leave_text := "Zamknij spółkę" if members.size() == 1 else "Opuść spółkę"
	var leave := UI.button(leave_text, _send.bind("company.leave", {}, members.size() == 1))
	if members.size() == 1:
		leave.tooltip_text = "Jesteś ostatnim członkiem: to, co jest w magazynie, wróci do twojego ekwipunku."
	elif owner:
		leave.tooltip_text = "Najpierw przekaż prezesurę innemu członkowi."
	else:
		leave.tooltip_text = "Twoje działki przestaną być wspólne."
	_body.add_child(leave)


func _create() -> void:
	_send("company.create", {"name": _name_edit.text.strip_edges()})


func _invite() -> void:
	var name := _invite_edit.text.strip_edges()
	if name != "":
		_send("company.invite", {"name": name})


static func _log_text(entry: Dictionary) -> String:
	var who: String = entry["who"]
	var other: String = str(entry["other"]) if entry["other"] != null else "?"
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
			return "%s wnosi działkę %s" % [who, entry["item"]]
		"plotRemoved":
			return "%s zabiera działkę %s" % [who, entry["item"]]
		"put":
			return "%s wkłada %d × %s" % [who, int(entry["quantity"]), entry["name"]]
		"take":
			return "%s wyjmuje %d × %s" % [who, int(entry["quantity"]), entry["name"]]
	return "%s: %s" % [who, entry["action"]]


static func _ago(at_ms: int) -> String:
	var seconds := int(Time.get_unix_time_from_system() - at_ms / 1000.0)
	if seconds < 60:
		return "przed chwilą"
	if seconds < 3600:
		return "%d min temu" % (seconds / 60)
	if seconds < 86400:
		return "%d godz. temu" % (seconds / 3600)
	return "%d dni temu" % (seconds / 86400)


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
