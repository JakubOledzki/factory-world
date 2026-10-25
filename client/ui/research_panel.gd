class_name ResearchPanel
extends VBoxContainer
## The technology trees, shown at the research table. Every branch of industry (logistics,
## mining, forestry, oil…) has a tree of its own, picked with the tabs on top. In a tree each
## technology is a card in the column of its depth within the branch, joined by curves to the
## ones it needs; what it needs from other branches shows as small icons on the card. The chosen
## one shows its cost, time and what it unlocks on the right. Research uses up its cost at once
## and takes time, one technology at a time, and goes on while the player is away. The panel
## keeps an eye on it while hidden too, so the screen hears when it is done.

## Research finished: [{id, name}] and the XP gain (or null).
signal researched(finished: Array, xp: Variant)
## The cost was taken or given back; the screen reloads the inventory.
signal inventory_changed
signal failed(reply: Dictionary)

const STATUS_COLORS := {"done": UI.GOOD, "active": UI.GOLD, "available": UI.TEXT, "locked": UI.MUTED}
## Where the tree starts inside its canvas: room for the column titles above.
const TREE_MARGIN := Vector2(18, 40)

var _state := {}
var _items: Array = []
var _selected := ""
## The branch whose tree is shown.
var _branch := ""
var _clock_offset := 0.0
var _refreshing := false
var _next_poll := 0.0
var _busy := false
## The second the countdown last showed, so the cards are written anew once a second.
var _last_second := -1
## Card by technology id, and the status line of the chosen one.
var _cards := {}
var _status: Label

var _tabs := HFlowContainer.new()
var _header := HBoxContainer.new()
var _tree_scroll := ScrollContainer.new()
var _tree := _TreeCanvas.new()
var _details := VBoxContainer.new()
var _start_button: Button
var _cancel_button: Button
var _bar: ProgressBar
var _bar_text: Label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_constant_override("h_separation", 6)
	_tabs.add_theme_constant_override("v_separation", 6)
	add_child(_tabs)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	# The tree sits on a dark board under the branch's name and progress.
	var board := PanelContainer.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#121315", 0.92)
	style.border_color = Color("#2c2d31")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	board.add_theme_stylebox_override("panel", style)
	body.add_child(board)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	board.add_child(column)
	_header.add_theme_constant_override("separation", 10)
	column.add_child(_header)
	_tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_scroll.add_child(_tree)
	column.add_child(_tree_scroll)
	_tree.chosen.connect(_choose)

	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_scroll.custom_minimum_size.x = 380 if UI.touch() else 340
	body.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(side)
	side_scroll.add_child(margin)
	_details.add_theme_constant_override("separation", 4)
	side.add_child(_details)
	var progress := HBoxContainer.new()
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	progress.add_child(_bar)
	_bar_text = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_bar_text.custom_minimum_size.x = 70
	progress.add_child(_bar_text)
	side.add_child(progress)
	_start_button = UI.button("Zbadaj", _start, true)
	side.add_child(_start_button)
	_cancel_button = UI.button("Przerwij badanie", _cancel)
	_cancel_button.tooltip_text = "Wszystko, co zużyło badanie, wróci do ekwipunku"
	side.add_child(_cancel_button)
	side.add_child(HSeparator.new())
	side.add_child(UI.label("Naraz bada się jedną technologię. Badanie trwa dalej, gdy odejdziesz od stołu.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	side.add_child(UI.label("Czego jeszcze nie zbadasz, tego nie ma dla ciebie na rynku: ani u handlarza, ani u innych graczy.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


## Whether the tree came from the server yet.
func loaded() -> bool:
	return not _state.is_empty()


func set_items(items: Array) -> void:
	_items = items
	if is_visible_in_tree():
		_render()


## Asks the server for the tree; it hands out XP for finished research.
func refresh() -> void:
	_refreshing = true
	_next_poll = _server_now() + 500.0
	var reply := await Net.request("research.get")
	_refreshing = false
	_apply(reply)


func _apply(reply: Dictionary) -> void:
	if reply["type"] != "research":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_clock_offset = float(_state["serverTime"]) - Time.get_unix_time_from_system() * 1000.0
	if _selected == "":
		var first := _technologies().filter(func(t: Dictionary) -> bool: return t["status"] == "active")
		first.append_array(_technologies().filter(func(t: Dictionary) -> bool: return t["status"] == "available"))
		_selected = first[0]["id"] if not first.is_empty() else _technologies()[0]["id"]
	if _branch == "":
		_branch = _technology(_selected).get("branch", "")
	var finished: Array = _state.get("finished", [])
	if not finished.is_empty():
		researched.emit(finished, _state.get("xp"))
	_render()


func _technologies() -> Array:
	return _state.get("technologies", [])


func _technology(id: String) -> Dictionary:
	for technology: Dictionary in _technologies():
		if technology["id"] == id:
			return technology
	return {}


func _active() -> Dictionary:
	for technology: Dictionary in _technologies():
		if technology["status"] == "active":
			return technology
	return {}


func _server_now() -> float:
	return Time.get_unix_time_from_system() * 1000.0 + _clock_offset


func _count(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _can_pay(technology: Dictionary) -> bool:
	for cost: Dictionary in technology["cost"]:
		if _count(cost["id"]) < int(cost["quantity"]):
			return false
	return true


## What the card says under the name: one missing requirement by name, more by their count (the list is in the details).
func _status_text(technology: Dictionary) -> String:
	match technology["status"]:
		"done": return "Zbadane"
		"active": return "Badanie: %s" % _left(technology)
		"available":
			if technology.get("companyOnly", false):
				return "Tylko dla spółek"
			return "Gotowe do zbadania" if _can_pay(technology) else "Brakuje materiałów"
	var missing: Array = technology["requires"].filter(func(id: String) -> bool: return _technology(id).get("status") != "done")
	if missing.size() > 1:
		return "Wymaga %d badań" % missing.size()
	return "Wymaga: %s" % ", ".join(missing.map(func(id: String) -> String: return _technology(id).get("name", id)))


func _left(technology: Dictionary) -> String:
	var left := maxf(float(technology["finishesAt"]) - _server_now(), 0.0) / 1000.0
	return _seconds(ceilf(left))


func _render() -> void:
	if _state.is_empty():
		return
	_render_tabs()
	_render_header()
	_render_tree()
	_render_details()


func _branches() -> Array:
	return _state.get("branches", [])


func _branch_of(id: String) -> Dictionary:
	for branch: Dictionary in _branches():
		if branch["id"] == id:
			return branch
	return {}


## Shows the technology, switching to its branch's tree if it lies in another one.
func _choose(id: String) -> void:
	if id == _selected:
		return
	_selected = id
	var branch: String = _technology(id).get("branch", _branch)
	if branch != _branch:
		_branch = branch
		_tree_scroll.scroll_horizontal = 0
		_tree_scroll.scroll_vertical = 0
		_render()
		return
	for card_id: String in _cards:
		_cards[card_id].queue_redraw()
	_render_details()


## Opens a branch's tree with its most interesting technology chosen: the one being researched,
## else one ready to research, else the first.
func _open_branch(id: String) -> void:
	if id == _branch:
		return
	_branch = id
	var members := _technologies().filter(func(t: Dictionary) -> bool: return t["branch"] == id)
	var pick: Array = members.filter(func(t: Dictionary) -> bool: return t["status"] == "active")
	pick.append_array(members.filter(func(t: Dictionary) -> bool: return t["status"] == "available"))
	pick.append_array(members)
	_selected = pick[0]["id"]
	_tree_scroll.scroll_horizontal = 0
	_tree_scroll.scroll_vertical = 0
	_render()


func _render_tabs() -> void:
	UI.clear(_tabs)
	var touch := UI.touch()
	for branch: Dictionary in _branches():
		var members := _technologies().filter(func(t: Dictionary) -> bool: return t["branch"] == branch["id"])
		var done := members.filter(func(t: Dictionary) -> bool: return t["status"] == "done").size()
		var active := members.any(func(t: Dictionary) -> bool: return t["status"] == "active")
		var tab := UI.button("", _open_branch.bind(branch["id"]), branch["id"] == _branch)
		tab.icon = UI.item_texture(branch["icon"])
		tab.expand_icon = false
		tab.add_theme_constant_override("icon_max_width", 30 if touch else 22)
		# On phones the tabs show just the icon and the count, so they fit in one row; the name is above the tree.
		tab.text = "%d/%d" % [done, members.size()] if touch else "%s  %d/%d" % [branch["name"], done, members.size()]
		tab.tooltip_text = branch["name"] + (" (trwa badanie)" if active else "")
		if branch["id"] != _branch:
			if active:
				tab.add_theme_color_override("font_color", UI.GOLD)
			elif done == members.size():
				tab.add_theme_color_override("font_color", UI.GOOD)
		_tabs.add_child(tab)


func _render_header() -> void:
	UI.clear(_header)
	var branch := _branch_of(_branch)
	if branch.is_empty():
		return
	var members := _technologies().filter(func(t: Dictionary) -> bool: return t["branch"] == _branch)
	var done := members.filter(func(t: Dictionary) -> bool: return t["status"] == "done").size()
	_header.add_child(UI.item_icon(branch["icon"], 30))
	var title := UI.label(branch["name"], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_font_size_override("font_size", roundi(get_theme_default_font_size() * 1.3))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(title)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(members.size(), 1)
	bar.value = done
	bar.custom_minimum_size = Vector2(120, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.add_child(bar)
	var count := UI.label("zbadane %d z %d" % [done, members.size()], UI.MUTED)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(count)
	if UI.touch():
		return
	for state: Array in [["done", "Zbadane"], ["active", "W toku"], ["available", "Do zbadania"], ["locked", "Zablokowane"]]:
		var dot := ColorRect.new()
		dot.color = _TechCard.border_color(state[0])
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_header.add_child(dot)
		_header.add_child(UI.label(state[1], UI.MUTED))


## Lays the chosen branch out: a column for each depth within the branch, left to right. Each
## card sits level with the middle of the cards it needs, as far as the cards above let it,
## so the curves between them run mostly straight across.
func _render_tree() -> void:
	UI.clear(_tree)
	_cards.clear()
	var members := _technologies().filter(func(t: Dictionary) -> bool: return t["branch"] == _branch)
	var inside := {}
	for technology: Dictionary in members:
		inside[technology["id"]] = technology
	var depth := {}
	for technology: Dictionary in members:
		_depth(technology["id"], inside, depth)
	var columns: Array[Array] = []
	for technology: Dictionary in members:
		var d: int = depth[technology["id"]]
		while columns.size() <= d:
			columns.append([])
		columns[d].append(technology)

	var card := _TechCard.card_size()
	var gap := Vector2(card.x * 0.22, 22)
	var places := {}
	var bottom := 0.0
	for d in columns.size():
		var wanted := {}
		for technology: Dictionary in columns[d]:
			var parents: Array = technology["requires"].filter(func(id: String) -> bool: return places.has(id))
			var y := 0.0
			for id: String in parents:
				y += places[id].y
			wanted[technology["id"]] = y / parents.size() if not parents.is_empty() else -1.0
		var column := columns[d].duplicate()
		if d > 0:
			column.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return wanted[a["id"]] < wanted[b["id"]])
		var next := TREE_MARGIN.y
		for technology: Dictionary in column:
			var y := maxf(next, wanted[technology["id"]])
			places[technology["id"]] = Vector2(TREE_MARGIN.x + d * (card.x + gap.x), y)
			next = y + card.y + gap.y
		bottom = maxf(bottom, next - gap.y)

	for technology: Dictionary in members:
		var outside: Array = technology["requires"].filter(func(id: String) -> bool: return not inside.has(id)) \
				.map(func(id: String) -> Dictionary: return _technology(id))
		var c := _TechCard.new(self, technology, outside)
		c.position = places[technology["id"]]
		_cards[technology["id"]] = c
		_tree.add_child(c)

	var lines := []
	for technology: Dictionary in members:
		for id: String in technology["requires"]:
			if places.has(id):
				lines.append([places[id] + Vector2(card.x, card.y / 2), places[technology["id"]] + Vector2(0, card.y / 2),
						_technology(id)["status"], technology["status"]])
	var titles := []
	for d in columns.size():
		titles.append([Vector2(TREE_MARGIN.x + d * (card.x + gap.x), TREE_MARGIN.y - 12), "ETAP %d" % (d + 1)])
	_tree.lines = lines
	_tree.titles = titles
	_tree.card_width = card.x
	_tree.custom_minimum_size = Vector2(TREE_MARGIN.x * 2 + columns.size() * (card.x + gap.x) - gap.x, bottom + TREE_MARGIN.x)
	_tree.queue_redraw()


## How deep a technology lies in its branch: 0 when it needs nothing from the branch.
func _depth(id: String, inside: Dictionary, depth: Dictionary) -> int:
	if not depth.has(id):
		var d := 0
		for need: String in inside[id]["requires"]:
			if inside.has(need):
				d = maxi(d, _depth(need, inside, depth) + 1)
		depth[id] = d
	return depth[id]


func _render_details() -> void:
	UI.clear(_details)
	var technology := _technology(_selected)
	var active := _active()
	_bar.get_parent().visible = not active.is_empty() and active["id"] == _selected
	_update_bar()
	if technology.is_empty():
		_start_button.visible = false
		_cancel_button.visible = false
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var icon := TextureRect.new()
	icon.texture = _icon_for(technology)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(40, 40)
	head.add_child(icon)
	var title := UI.label(technology["name"], UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_details.add_child(head)
	_details.add_child(UI.label(technology["description"], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_status = UI.label(_status_text(technology), STATUS_COLORS[technology["status"]], HORIZONTAL_ALIGNMENT_LEFT, true)
	_details.add_child(_status)
	if not technology["requires"].is_empty():
		_details.add_child(UI.label("Wymaga:", UI.MUTED))
		for id: String in technology["requires"]:
			_details.add_child(_requirement(_technology(id), technology["branch"]))

	if technology.get("shared", false):
		_details.add_child(UI.label("Zbadała to twoja spółka: masz to, dopóki w niej jesteś.", UI.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
	if technology.get("companyOnly", false):
		_details.add_child(UI.label("Tylko dla spółek: bada ją spółka, razem, dla wszystkich członków.", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
	if not technology["unlocks"].is_empty():
		_details.add_child(UI.label("Odblokowuje:", UI.MUTED))
	for unlock: Dictionary in technology["unlocks"]:
		_details.add_child(_item_row(unlock["id"], unlock["name"], ""))
	if technology["status"] != "done":
		_details.add_child(UI.label("Zużywa (wymagane/masz):", UI.MUTED))
		for cost: Dictionary in technology["cost"]:
			var need := int(cost["quantity"])
			var have := _count(cost["id"])
			var text := "%d/%d" % [need, have]
			_details.add_child(_item_row(cost["id"], cost["name"], text, UI.GOOD if have >= need or technology["status"] == "active" else UI.ERROR))
	_details.add_child(UI.label("Czas: %s  ·  %d XP" % [_seconds(float(technology["seconds"])), int(technology["xp"])], UI.MUTED))

	_render_company(technology)
	var busy := not active.is_empty()
	_start_button.visible = technology["status"] in ["available", "locked"] and not technology.get("companyOnly", false)
	_start_button.disabled = technology["status"] != "available" or busy or not _can_pay(technology) or _busy
	if technology["status"] == "locked":
		_start_button.text = "Najpierw zbadaj wymagane"
	elif busy:
		_start_button.text = "Trwa inne badanie: %s" % active["name"]
	elif not _can_pay(technology):
		_start_button.text = "Brakuje materiałów"
	else:
		_start_button.text = "Zbadaj"
	_cancel_button.visible = technology["status"] == "active"
	_cancel_button.disabled = _busy
	if technology["status"] == "active":
		_render_boosts()


## The company's research: members bring the cost together, then it is researched once for all of them.
func _render_company(technology: Dictionary) -> void:
	var company: Variant = _state.get("company")
	if company == null:
		return
	_details.add_child(HSeparator.new())
	var current: Variant = company["technology"]
	if current == technology["id"]:
		if company["startsAt"] == null:
			_details.add_child(UI.label("Spółka %s zbiera na to badanie. Dołóż, co masz:" % company["name"], UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
			for part: Dictionary in company["delivered"]:
				var needed := int(part["needed"])
				var delivered := int(part["delivered"])
				var row := _item_row(part["id"], part["name"], "%d/%d" % [delivered, needed], UI.GOOD if delivered >= needed else UI.TEXT)
				if delivered < needed:
					var have := _count(part["id"])
					var give := UI.button("Dołóż", func() -> void: _company("research.contribute", {"item": part["id"], "quantity": mini(have, needed - delivered)}))
					give.disabled = have < 1 or _busy
					row.add_child(give)
				_details.add_child(row)
		else:
			var left := maxf(float(company["finishesAt"]) - _server_now(), 0.0) / 1000.0
			_details.add_child(UI.label("Spółka %s bada to dla wszystkich członków: zostało %s." % [company["name"], _seconds(ceilf(left))], UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true))
		if company["leads"]:
			var cancel := UI.button("Odwołaj badanie spółki", func() -> void: _company("research.companyCancel", {}))
			cancel.tooltip_text = "To, co członkowie dołożyli, trafi do twojego ekwipunku."
			_details.add_child(cancel)
	elif current != null:
		_details.add_child(UI.label("Spółka bada teraz: %s." % _technology(current).get("name", current), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	elif technology["status"] != "done" and company["leads"]:
		var start := UI.button("Badaj w spółce", func() -> void: _company("research.companyStart", {"technology": technology["id"]}), true)
		start.tooltip_text = "Członkowie razem dokładają koszt, a technologię dostaną wszyscy."
		start.disabled = technology["status"] == "locked" or _busy
		_details.add_child(start)
	elif technology["status"] != "done":
		_details.add_child(UI.label("Badania spółki wybierają prezes i wspólnicy.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


func _company(type: String, payload: Dictionary) -> void:
	_busy = true
	_render()
	var reply := await Net.request(type, payload)
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


static func _icon_for(technology: Dictionary) -> Texture2D:
	var unlocks: Array = technology["unlocks"]
	return UI.item_texture(unlocks[0]["id"]) if not unlocks.is_empty() else UI.texture("icons/toolbar_company")


## Research data and computing power from the glacier speed the research being done up: a button for each held.
func _render_boosts() -> void:
	var held: Array = _state.get("boosts", []).filter(func(boost: Dictionary) -> bool: return _count(boost["id"]) > 0)
	if held.is_empty():
		return
	_details.add_child(UI.label("Przyspiesz badanie:", UI.MUTED))
	for boost: Dictionary in held:
		var have := _count(boost["id"])
		var row := _item_row(boost["id"], "%s (masz %d, każda −%s)" % [boost["name"], have, _seconds(float(boost["seconds"]))], "")
		var button := UI.button("Użyj", func() -> void: _boost(boost["id"], have))
		button.disabled = _busy
		row.add_child(button)
		_details.add_child(row)


func _boost(item: String, quantity: int) -> void:
	_busy = true
	_render()
	var reply := await Net.request("research.boost", {"item": item, "quantity": quantity})
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


## A required technology as a button that shows it; one from another branch names its branch.
func _requirement(need: Dictionary, branch: String) -> Button:
	var b := UI.button("", _choose.bind(need["id"]))
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = _icon_for(need)
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 26)
	b.text = need["name"] + ("  (%s)" % _branch_of(need["branch"]).get("name", "") if need["branch"] != branch else "")
	b.text += "  ✓" if need["status"] == "done" else ""
	b.add_theme_color_override("font_color", STATUS_COLORS[need["status"]])
	b.tooltip_text = "Pokaż w drzewku"
	return b


func _item_row(item: String, name: String, amount: String, color := UI.TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var name_label := UI.label(name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if amount != "":
		row.add_child(UI.label(amount, color, HORIZONTAL_ALIGNMENT_RIGHT))
	return row


func _seconds(seconds: float) -> String:
	var s := roundi(seconds)
	return "%d s" % s if s < 60 else "%d min %02d s" % [s / 60, s % 60]


func _update_bar() -> void:
	var active := _active()
	if active.is_empty():
		return
	var total := float(active["finishesAt"]) - float(active["startsAt"])
	var left := maxf(float(active["finishesAt"]) - _server_now(), 0.0)
	_bar.max_value = total
	_bar.value = total - left
	_bar_text.text = _left(active)


func _process(_delta: float) -> void:
	var active := _active()
	if active.is_empty():
		return
	if is_visible_in_tree():
		_update_bar()
		# The card and the status count down once a second, redrawn in place (not built anew,
		# which would swallow a click on a card being pressed).
		var second := int(_server_now() / 1000.0)
		if second != _last_second:
			_last_second = second
			if _cards.has(active["id"]):
				_cards[active["id"]].queue_redraw()
			if _status != null and is_instance_valid(_status) and _selected == active["id"]:
				_status.text = _status_text(active)
	var now := _server_now()
	if now >= float(active["finishesAt"]) and now >= _next_poll and not _refreshing:
		refresh()


func _start() -> void:
	if _selected == "":
		return
	_busy = true
	_render()
	var reply := await Net.request("research.start", {"technology": _selected})
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


func _cancel() -> void:
	_busy = true
	var reply := await Net.request("research.cancel")
	_busy = false
	_apply(reply)
	if reply["type"] == "research":
		inventory_changed.emit()


## Holds the cards where the panel puts them and draws the column titles and the curves
## between the cards underneath: green from what is done, gold into what is being researched.
class _TreeCanvas:
	extends Control

	signal chosen(id: String)

	## [[from, to, from status, to status]] in the canvas' coordinates.
	var lines := []
	## [[position, text]]
	var titles := []
	var card_width := 0.0

	func _draw() -> void:
		var font_size := get_theme_default_font_size()
		for title: Array in titles:
			draw_string(UI.bold(), title[0], title[1], HORIZONTAL_ALIGNMENT_LEFT, card_width, roundi(font_size * 0.8), Color(UI.MUTED, 0.7))
			draw_line(title[0] + Vector2(0, 6), title[0] + Vector2(card_width, 6), Color("#2c2d31"), 1.0)
		for line: Array in lines:
			var from: Vector2 = line[0]
			var to: Vector2 = line[1]
			var color := Color("#4a4b51")
			if line[2] == "done":
				color = UI.GOLD if line[3] == "active" else UI.GOOD
			var bend := maxf((to.x - from.x) * 0.5, 30.0)
			var points := PackedVector2Array()
			for i in 25:
				var t := i / 24.0
				var u := 1.0 - t
				points.append(u * u * u * from + 3 * u * u * t * (from + Vector2(bend, 0)) + 3 * u * t * t * (to - Vector2(bend, 0)) + t * t * t * to)
			if line[2] == "done":
				draw_polyline(points, Color(color, 0.18), 8.0, true)
			draw_polyline(points, color, 2.5, true)
			draw_circle(from, 4.0, color)
			draw_circle(to, 4.0, color)


## One technology on the tree: its icon in a ring, name and status, coloured by its state, a
## progress bar while it is researched, and small icons for what it needs from other branches.
class _TechCard:
	extends Button

	var _panel: Variant
	var _technology: Dictionary
	var _outside: Array
	## Held here: a texture only drawn, with nothing keeping it, is freed and shows white.
	var _icon: Texture2D
	var _chips: Array[Texture2D] = []

	static func card_size() -> Vector2:
		return Vector2(280, 90) if UI.touch() else Vector2(216, 68)

	static func border_color(status: String) -> Color:
		match status:
			"done": return UI.GOOD
			"active": return UI.GOLD
			"available": return Color("#c9c3b4")
		return Color("#3c3d42")

	func _init(panel: Variant, technology: Dictionary, outside: Array) -> void:
		_panel = panel
		_technology = technology
		_outside = outside
		_icon = panel._icon_for(technology)
		for need: Dictionary in outside:
			_chips.append(panel._icon_for(need) if not need.is_empty() else null)
		size = card_size()
		custom_minimum_size = size
		for style in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(style, StyleBoxEmpty.new())
		var names := ", ".join(outside.map(func(t: Dictionary) -> String: return t.get("name", "")))
		tooltip_text = technology["name"] + ("\nWymaga z innych gałęzi: " + names if names != "" else "")
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)
		pressed.connect(func() -> void: _panel._tree.chosen.emit(_technology["id"]))

	func _draw() -> void:
		var status: String = _technology["status"]
		var selected: bool = _panel._selected == _technology["id"]
		var ring := border_color(status)
		var rect := Rect2(Vector2.ZERO, size)

		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(10)
		box.bg_color = Color("#26272b") if status != "locked" else Color("#1b1c1f")
		if is_hovered():
			box.bg_color = box.bg_color.lightened(0.08)
		box.border_color = ring if status != "available" else Color(ring, 0.55)
		box.set_border_width_all(2)
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 6
		box.shadow_offset = Vector2(0, 3)
		if selected:
			var glow := StyleBoxFlat.new()
			glow.set_corner_radius_all(13)
			glow.draw_center = false
			glow.border_color = UI.GOLD
			glow.set_border_width_all(2)
			glow.set_expand_margin_all(4)
			draw_style_box(glow, rect)
		draw_style_box(box, rect)

		# The icon in a ring of the state's colour; done ones get a tick.
		var radius := size.y * 0.33
		var center := Vector2(10 + radius, size.y / 2)
		draw_circle(center, radius, Color("#141517"))
		draw_arc(center, radius, 0, TAU, 40, ring, 2.5, true)
		var side := radius * 1.35
		draw_texture_rect(_icon, Rect2(center - Vector2(side, side) / 2, Vector2(side, side)), false,
				Color(1, 1, 1, 0.4) if status == "locked" else Color.WHITE)
		if status == "done":
			var tick := center + Vector2(radius * 0.72, radius * 0.72)
			draw_circle(tick, radius * 0.36, UI.GOOD)
			var r := radius * 0.36
			draw_polyline(PackedVector2Array([tick + Vector2(-r * 0.5, 0), tick + Vector2(-r * 0.1, r * 0.4), tick + Vector2(r * 0.5, -r * 0.4)]),
					Color("#14210c"), 2.0, true)

		# What it needs from other branches: their icons on the top edge, green once done, so
		# they take no room from the name. Past a handful, a count stands for the rest.
		var chip := roundf(size.y * 0.26)
		var shown := mini(_outside.size(), 5 if _outside.size() > 6 else 6)
		var at_x := size.x - 14 - chip / 2
		if _outside.size() > shown:
			var more := Vector2(at_x, 0)
			draw_circle(more, chip / 2 + 1, Color("#141517"))
			draw_arc(more, chip / 2 + 1, 0, TAU, 24, Color("#5a5b61"), 1.5, true)
			var label := "+%d" % (_outside.size() - shown)
			var label_size := roundi(chip * 0.55)
			var width := UI.bold().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
			draw_string(UI.bold(), more + Vector2(-width / 2, label_size * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, UI.MUTED)
			at_x -= chip + 4
		for i in range(shown - 1, -1, -1):
			var need: Dictionary = _outside[i]
			var at := Vector2(at_x, 0)
			at_x -= chip + 4
			draw_circle(at, chip / 2 + 1, Color("#141517"))
			draw_arc(at, chip / 2 + 1, 0, TAU, 24, UI.GOOD if need.get("status") == "done" else Color("#5a5b61"), 1.5, true)
			if _chips[i] != null:
				draw_texture_rect(_chips[i], Rect2(at - Vector2(chip, chip) * 0.35, Vector2(chip, chip) * 0.7), false)

		var font_size := get_theme_default_font_size()
		var text_x := center.x + radius + 10
		var name_line := TextLine.new()
		name_line.add_string(_technology["name"], UI.bold(), font_size)
		name_line.width = size.x - 10 - text_x
		name_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var name_y := size.y / 2 - name_line.get_size().y + 2
		name_line.draw(get_canvas_item(), Vector2(text_x, name_y), UI.TEXT if status != "locked" else UI.MUTED)
		var status_line := TextLine.new()
		status_line.add_string(_panel._status_text(_technology), get_theme_default_font(), roundi(font_size * 0.9))
		status_line.width = size.x - 10 - text_x
		status_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status_line.draw(get_canvas_item(), Vector2(text_x, size.y / 2 + 1), STATUS_COLORS[status] if status != "locked" else Color(UI.MUTED, 0.8))

		if status == "active":
			var total := float(_technology["finishesAt"]) - float(_technology["startsAt"])
			var left := maxf(float(_technology["finishesAt"]) - _panel._server_now(), 0.0)
			var bar := Rect2(text_x, size.y - 12, size.x - 12 - text_x, 5)
			draw_rect(bar, Color("#141517"))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(1.0 - left / maxf(total, 1.0), 0.0, 1.0), bar.size.y)), UI.GOLD)
