class_name AdventuresWindow
extends GameWindow
## Everything to do besides the factory: the holiday on now with its treats and decorations, the album
## of finds, expeditions to far regions, engineering puzzles, the mentor of a new player, and the
## trophy case (the player's own or another's).

signal failed(reply: Dictionary)
signal toast(text: String)
signal inventory_changed

const TABS := ["Wydarzenie", "Album", "Wyprawy", "Zagadki", "Mentor", "Gablota"]
const EVENT := 0
const ALBUM := 1
const EXPEDITIONS := 2
const PUZZLES := 3
const MENTOR := 4
const SHOWCASE := 5
const MEDALS := ["", "Brąz", "Srebro", "Złoto"]
const MEDAL_COLORS := [Color.WHITE, Color("#c27c3a"), Color("#c9cdd3"), Color("#f5b041")]

var _tab := EVENT
var _tab_buttons: Array[Button] = []
var _summary := UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
var _page := VBoxContainer.new()
var _loading := false
var _again := false
## The trophy case shown: "" for the player's own, or another player's name.
var _showcase_of := ""
## The puzzle open in the editor ({} for the list), and the board it is laid out on.
var _puzzle := {}
var _board := PuzzleBoard.new()
var _result := UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
var _piece_buttons := HBoxContainer.new()
## Expeditions as the server last sent them, and when (ticks), for the countdowns.
var _expeditions := {}
var _expeditions_at := 0
var _countdowns: Array[Dictionary] = []


func _init() -> void:
	super("Przygody", 0)
	fill_margin = Vector2(120, 36) if not UI.touch() else Vector2(24, 16)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	for i in TABS.size():
		var b := UI.button(TABS[i], open_tab.bind(i))
		b.custom_minimum_size.x = 110
		top.add_child(b)
		_tab_buttons.append(b)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_summary)
	content.add_child(top)

	var list := ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 6)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_page)
	list.add_child(margin)
	content.add_child(list)
	_board.changed.connect(func() -> void: _result.text = "")
	set_process(true)


func show_window() -> void:
	super()
	refresh()


## Opens the window at a tab; the trophy case of `player` ("" for one's own).
func open_tab(tab: int, player := "") -> void:
	_tab = tab
	if tab == SHOWCASE:
		_showcase_of = player
	if tab != PUZZLES:
		_puzzle = {}
	if not visible:
		show_window()
	else:
		refresh()


func refresh() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].theme_type_variation = "AccentButton" if i == _tab else ""
	if _loading:
		_again = true
		return
	_loading = true
	var tab := _tab
	var reply: Dictionary
	match tab:
		EVENT:
			reply = await Net.request("season.get")
		ALBUM:
			reply = await Net.request("album.get")
		EXPEDITIONS:
			reply = await Net.request("expedition.get")
		PUZZLES:
			reply = await Net.request("puzzle.get")
		MENTOR:
			reply = await Net.request("mentor.get")
		_:
			reply = await Net.request("showcase.get", {"name": _showcase_of} if _showcase_of != "" else null)
	_loading = false
	if _again or tab != _tab:
		_again = false
		refresh()
		return
	if reply["type"] == "error":
		failed.emit(reply)
		if tab == SHOWCASE and _showcase_of != "":
			_showcase_of = ""
		return
	_show(tab, reply["payload"])


func _show(tab: int, state: Dictionary) -> void:
	_clear_page()
	_countdowns.clear()
	_summary.text = ""
	match tab:
		EVENT:
			_show_event(state)
		ALBUM:
			_show_album(state)
		EXPEDITIONS:
			_show_expeditions(state)
		PUZZLES:
			_show_puzzles(state)
		MENTOR:
			_show_mentor(state)
		_:
			_show_showcase(state)


## Empties the page, keeping the puzzle board, its result and its piece buttons for the next time.
func _clear_page() -> void:
	for kept: Control in [_board, _result, _piece_buttons]:
		if kept.get_parent():
			kept.get_parent().remove_child(kept)
	UI.clear(_page)


func _heading(text: String) -> Label:
	var head := UI.label(text, UI.GOLD)
	head.add_theme_font_override("font", UI.bold())
	_page.add_child(head)
	return head


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_page.add_child(row)
	return row


static func _date(ms: float) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(ms / 1000.0))
	return "%02d.%02d.%d" % [d["day"], d["month"], d["year"]]


static func _duration(seconds: int) -> String:
	seconds = maxi(seconds, 0)
	var h := seconds / 3600
	var m := (seconds % 3600) / 60
	return "%d h %02d min" % [h, m] if h > 0 else "%d min %02d s" % [m, seconds % 60]


# --- Holiday ----------------------------------------------------------------------------------------

func _show_event(state: Dictionary) -> void:
	var active: Variant = state.get("active")
	if active == null:
		_heading("Teraz nie trwają żadne święta")
		var next: Dictionary = state["next"]
		_page.add_child(UI.label("Najbliższe: %s, od %s. W czasie świąt zbiory, kamienie i ścięte zboże na działce dają co jakiś czas świąteczne przysmaki, które wymienisz tutaj na dekoracje."
			% [next["name"], _date(next["starts"])], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	var season: Dictionary = active
	_heading("%s  (do %s)" % [season["name"], _date(float(season["ends"]) - 1000.0)])
	var token: Dictionary = season["token"]
	_summary.text = "%s: %d" % [token["name"], int(season["tokens"])]
	var row := _row()
	row.add_child(UI.item_icon(token["id"], 40))
	row.add_child(UI.label("Masz %d. Dziś znaleziono %d z %d. Mniej więcej co %d. zbiór, kamień albo ścięte zboże na działce daje przysmak."
		% [int(season["tokens"]), int(season["foundToday"]), int(season["dailyLimit"]), int(season["dropOneIn"])],
		UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_page.add_child(HSeparator.new())
	_heading("Dekoracje na działkę")
	for offer: Dictionary in season["shop"]:
		var line := _row()
		line.add_child(UI.item_icon(offer["id"], 48))
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_child(UI.label(offer["name"]))
		text.add_child(UI.label(ItemInfo.description(offer["id"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		line.add_child(text)
		var buy := UI.button("Wymień za %d × %s" % [int(offer["price"]), token["name"]], _buy_decoration.bind(offer["id"], offer["name"]), true)
		buy.disabled = int(season["tokens"]) < int(offer["price"])
		line.add_child(buy)


func _buy_decoration(item: String, item_name: String) -> void:
	var reply := await Net.request("season.buy", {"item": item})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	toast.emit("%s trafia do ekwipunku. Postaw ją na działce!" % item_name)
	inventory_changed.emit()
	_show(EVENT, reply["payload"]["season"])


# --- Album ------------------------------------------------------------------------------------------

func _show_album(state: Dictionary) -> void:
	_summary.text = "Znaleziono %d z %d" % [int(state["found"]), int(state["total"])]
	_page.add_child(UI.label("Rzadkie rzeczy, które znajdziesz pierwszy raz, trafiają do albumu same. Pełna strona daje %d XP."
		% int(state["pageXp"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for page: Dictionary in state["pages"]:
		var items: Array = page["items"]
		var found := items.filter(func(i: Dictionary) -> bool: return i["found"]).size()
		var head := _row()
		var title := UI.label("%s  (%d/%d)" % [page["name"], found, items.size()], UI.GOLD)
		title.add_theme_font_override("font", UI.bold())
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		if page["claimed"]:
			head.add_child(UI.label("Nagroda odebrana", UI.GOOD))
		elif page["complete"]:
			head.add_child(UI.button("Odbierz %d XP" % int(state["pageXp"]), _claim_page.bind(page["id"]), true))
		_page.add_child(UI.label(page["hint"], UI.MUTED))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		for item: Dictionary in items:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size.x = 92
			cell.tooltip_text = item["name"] + ("\nZnalezione %s" % _date(item["foundAt"]) if item["found"] else "\nJeszcze nie znalezione")
			var icon := UI.item_icon(item["id"], 48)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if not item["found"]:
				icon.modulate = Color(0, 0, 0, 0.6)
			cell.add_child(icon)
			var name := UI.label(item["name"] if item["found"] else "?", UI.TEXT if item["found"] else UI.MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
			name.add_theme_font_size_override("font_size", 12)
			name.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(name)
			grid.add_child(cell)
		_page.add_child(grid)
		_page.add_child(HSeparator.new())


func _claim_page(page: String) -> void:
	var reply := await Net.request("album.claim", {"page": page})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	Game.gain_xp(reply["payload"]["xp"])
	toast.emit("Strona albumu pełna! +%d XP" % int(reply["payload"]["album"]["pageXp"]))
	_show(ALBUM, reply["payload"]["album"])


# --- Expeditions --------------------------------------------------------------------------------------

func _show_expeditions(state: Dictionary) -> void:
	_expeditions = state
	_expeditions_at = Time.get_ticks_msec()
	var trips: Array = state["trips"]
	_summary.text = "Wyprawy w drodze: %d z %d" % [trips.size(), int(state["parties"])]
	if not trips.is_empty():
		_heading("Twoje wyprawy")
		for trip: Dictionary in trips:
			var row := _row()
			var label := UI.label(trip["name"])
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var claim := UI.button("Odbierz łup", _claim_trip.bind(int(trip["id"])), true)
			row.add_child(claim)
			_countdowns.append({"label": label, "button": claim, "name": trip["name"], "returnsAt": float(trip["returnsAt"])})
		_tick_countdowns()
		_page.add_child(HSeparator.new())
	_heading("Dokąd wysłać wyprawę")
	_page.add_child(UI.label("Wyprawa zabiera zapasy i wraca po kilku godzinach z surowcami, a czasem z pamiątką do albumu (%d%% szans). Druga wyprawa naraz od %d poziomu."
		% [int(state["souvenirPercent"]), int(state["secondPartyLevel"])], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var level := int(Game.character.get("level", 1))
	for region: Dictionary in state["regions"]:
		var box := VBoxContainer.new()
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var title := UI.label("%s  ·  %s  ·  od %d poziomu  ·  %d XP" % [region["name"], _duration(int(region["minutes"]) * 60), int(region["level"]), int(region["xp"])], UI.GOLD)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(title)
		var send := UI.button("Wyślij", _send_trip.bind(region["id"], region["name"]), true)
		send.disabled = level < int(region["level"]) or trips.size() >= int(state["parties"])
		head.add_child(send)
		box.add_child(head)
		box.add_child(UI.label(region["description"], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		var supplies := PackedStringArray()
		for s: Dictionary in region["supplies"]:
			supplies.append("%d × %s" % [int(s["quantity"]), s["name"]])
		var finds := PackedStringArray()
		for f: Dictionary in region["finds"]:
			finds.append("%s %d–%d%s" % [f["name"], int(f["min"]), int(f["max"]), "" if int(f["percent"]) >= 100 else " (%d%%)" % int(f["percent"])])
		box.add_child(UI.label("Zapasy: " + ", ".join(supplies), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(UI.label("Przywozi: " + ", ".join(finds) + ". Pamiątka: " + region["souvenir"]["name"], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		_page.add_child(box)
		_page.add_child(HSeparator.new())


func _process(delta: float) -> void:
	super(delta)
	if visible and not _countdowns.is_empty():
		_tick_countdowns()


func _tick_countdowns() -> void:
	var now := float(_expeditions.get("now", 0)) + (Time.get_ticks_msec() - _expeditions_at)
	for c: Dictionary in _countdowns:
		var left := int((c["returnsAt"] - now) / 1000.0)
		var label: Label = c["label"]
		var button: Button = c["button"]
		if not is_instance_valid(label):
			continue
		label.text = "%s: %s" % [c["name"], "wróciła!" if left <= 0 else "wraca za " + _duration(left)]
		button.disabled = left > 0


func _send_trip(region: String, region_name: String) -> void:
	var reply := await Net.request("expedition.send", {"region": region})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	toast.emit("Wyprawa wyrusza: %s." % region_name)
	inventory_changed.emit()
	_show(EXPEDITIONS, reply["payload"])


func _claim_trip(id: int) -> void:
	var reply := await Net.request("expedition.claim", {"id": id})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	var payload: Dictionary = reply["payload"]
	var loot := PackedStringArray()
	for item: Dictionary in payload["items"]:
		loot.append("%d × %s" % [int(item["quantity"]), item["name"]])
	Game.gain_xp(payload["xp"])
	toast.emit("Wyprawa (%s) przywiozła: %s" % [payload["region"], ", ".join(loot) if not loot.is_empty() else "nic"])
	inventory_changed.emit()
	_show(EXPEDITIONS, payload["expeditions"])


# --- Puzzles ------------------------------------------------------------------------------------------

func _show_puzzles(state: Dictionary) -> void:
	if not _puzzle.is_empty():
		for p: Dictionary in state["puzzles"]:
			if p["id"] == _puzzle["id"]:
				_puzzle = p
		_show_editor()
		return
	var medals := 0
	for p: Dictionary in state["puzzles"]:
		medals += 1 if p["best"] != null and int(p["best"]["medal"]) == 3 else 0
	_summary.text = "Złote medale: %d z %d" % [medals, state["puzzles"].size()]
	_page.add_child(UI.label("Ułóż linię z taśm, podajników i maszyn, która dostarczy tyle, ile trzeba, z jak najmniejszej liczby elementów. Pierwsze rozwiązanie daje %d XP, pierwsze złoto drugie tyle."
		% int(state["solveXp"]), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	for p: Dictionary in state["puzzles"]:
		var row := _row()
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var title := UI.label(p["name"], UI.GOLD)
		title.add_theme_font_override("font", UI.bold())
		text.add_child(title)
		text.add_child(UI.label("%s: %s/min. Złoto do %d elementów, srebro do %d." % [p["output"]["name"], _num(p["target"]), int(p["gold"]), int(p["silver"])],
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		row.add_child(text)
		if p["best"] != null:
			var medal := int(p["best"]["medal"])
			row.add_child(UI.label("%s (%d el.)" % [MEDALS[medal], int(p["best"]["objects"])], MEDAL_COLORS[medal]))
		row.add_child(UI.button("Otwórz", _open_puzzle.bind(p), true))


func _open_puzzle(p: Dictionary) -> void:
	_puzzle = p
	_board.kind = p["allowed"][0]["id"]
	_board.show_puzzle(p, p["best"]["layout"] if p["best"] != null else [])
	_result.text = ""
	_show_editor()


func _show_editor() -> void:
	_clear_page()
	var p := _puzzle
	_summary.text = p["name"]
	_page.add_child(UI.label(p["story"], UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	_page.add_child(UI.label("Kliknij pole, by postawić wybrany element; kliknięcie elementu go obraca, prawy przycisk zabiera. R obraca następny. Podajnik bierze z pola za sobą i kładzie na pole przed sobą (strzałka). Taśma niesie %s szt./min."
		% _num(_puzzle_belt()), UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	UI.clear(_piece_buttons)
	_piece_buttons.add_theme_constant_override("separation", 4)
	for allowed: Dictionary in p["allowed"]:
		var b := Button.new()
		b.icon = UI.item_texture(allowed["id"])
		b.expand_icon = true
		b.custom_minimum_size = Vector2(56, 56)
		var pace := "" if allowed["perMinute"] == null else "\n%s szt./min" % _num(allowed["perMinute"])
		b.tooltip_text = "%s (najwyżej %d)%s" % [allowed["name"], int(allowed["most"]), pace]
		b.toggle_mode = true
		b.set_meta("kind", allowed["id"])
		b.button_pressed = _board.kind == allowed["id"]
		b.pressed.connect(_choose_piece.bind(allowed["id"]))
		_piece_buttons.add_child(b)
	_page.add_child(_piece_buttons)
	var holder := CenterContainer.new()
	holder.add_child(_board)
	_page.add_child(holder)
	var row := _row()
	row.add_child(UI.button("Sprawdź", _submit_puzzle, true))
	row.add_child(UI.button("Wyczyść", _board.clear_pieces))
	row.add_child(UI.button("Wszystkie zagadki", func() -> void:
		_puzzle = {}
		refresh()))
	_page.add_child(_result)
	if p["machine"] != null:
		var m: Dictionary = p["machine"]
		_page.add_child(UI.label("Maszyna bierze %s szt./min surowca i robi z każdej sztuki %s szt. produktu."
			% [_num(m["inPerMinute"]), _num(m["outPerIn"])], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))


func _puzzle_belt() -> float:
	for allowed: Dictionary in _puzzle.get("allowed", []):
		if allowed["id"] == "logistics_belt" and allowed["perMinute"] != null:
			return float(allowed["perMinute"])
	return 300.0


func _choose_piece(kind: String) -> void:
	_board.kind = kind
	for b: Button in _piece_buttons.get_children():
		b.button_pressed = b.get_meta("kind") == kind
	_board.grab_focus()


func _name_of(kind: String) -> String:
	for allowed: Dictionary in _puzzle.get("allowed", []):
		if allowed["id"] == kind:
			return allowed["name"]
	return kind


const PROBLEMS := {
	"outside": "Coś wystaje poza plac.",
	"overlap": "Dwa elementy stoją na tym samym polu.",
	"bad_rotation": "Zły obrót elementu.",
	"mixed": "Surowiec i produkt jadą tą samą taśmą albo w tym samym podajniku: linia się zatka.",
	"machine_idle": "Maszyna nic nie dostaje.",
}


func _submit_puzzle() -> void:
	var reply := await Net.request("puzzle.submit", {"puzzle": _puzzle["id"], "pieces": _board.pieces})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	var r: Dictionary = reply["payload"]
	_board.flow = r["flow"]
	_board.queue_redraw()
	var lines := PackedStringArray()
	lines.append("Dostarcza %s z %s szt./min, %d elementów." % [_num(r["rate"]), _num(_puzzle["target"]), int(r["objects"])])
	for problem: String in r["problems"]:
		if problem.begins_with("not_allowed:"):
			lines.append("Ten element nie jest dozwolony w tej zagadce.")
		elif problem.begins_with("too_many:"):
			lines.append("Za dużo elementów: %s." % _name_of(problem.trim_prefix("too_many:")))
		else:
			lines.append(PROBLEMS.get(problem, problem))
	if r["solved"]:
		var medal := int(r["medal"])
		lines.append("Rozwiązane! Medal: %s." % MEDALS[medal])
		_result.add_theme_color_override("font_color", MEDAL_COLORS[medal])
		if r["xp"] != null:
			Game.gain_xp(r["xp"])
			toast.emit("Zagadka „%s” rozwiązana: %s!" % [_puzzle["name"], MEDALS[medal]])
	else:
		_result.add_theme_color_override("font_color", UI.TEXT)
	_result.text = "\n".join(lines)


static func _num(value: Variant) -> String:
	var v := float(value)
	return str(int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")


# --- Mentor -------------------------------------------------------------------------------------------

func _show_mentor(state: Dictionary) -> void:
	var rules: Dictionary = state["rules"]
	_page.add_child(UI.label("Nowy gracz (poniżej %d poziomu) wybiera mentora od %d poziomu. Gdy podopieczny dojdzie do %d poziomu, oboje dostają nagrodę: on %d XP, mentor %d XP. Mentor opiekuje się najwyżej %d graczami."
		% [int(rules["chooseBelowLevel"]), int(rules["mentorLevel"]), int(rules["goalLevel"]), int(rules["menteeXp"]), int(rules["mentorXp"]), int(rules["mentees"])],
		UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var mentor: Variant = state["mentor"]
	if mentor != null:
		_heading("Twój mentor")
		var row := _row()
		var label := UI.label("%s, poziom %d%s" % [mentor["name"], int(mentor["level"]), "  ·  w grze" if mentor["online"] else ""])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if mentor["reward"]:
			row.add_child(UI.button("Odbierz %d XP" % int(rules["menteeXp"]), _claim_mentor.bind(""), true))
		elif mentor["rewarded"]:
			row.add_child(UI.label("Nagroda odebrana", UI.GOOD))
		else:
			row.add_child(UI.label("Nagroda od %d poziomu" % int(rules["goalLevel"]), UI.MUTED))
	elif state["canChoose"]:
		_heading("Wybierz mentora")
		_page.add_child(UI.label("Doświadczony gracz pomoże ci zacząć: podpowie, co budować, i może odwiedzać twoje działki. Wpisz jego nazwę.",
			UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
		var row := _row()
		var name := UI.line_edit("Nazwa gracza")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(UI.button("Wybierz", func() -> void: _choose_mentor(name.text.strip_edges()), true))
	var mentees: Array = state["mentees"]
	if state["canMentor"] or not mentees.is_empty():
		_page.add_child(HSeparator.new())
		_heading("Twoi podopieczni (%d/%d)" % [mentees.size(), int(rules["mentees"])])
		if mentees.is_empty():
			_page.add_child(UI.label("Nikt jeszcze nie wybrał cię na mentora. Podaj nowym graczom swoją nazwę na czacie.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		for m: Dictionary in mentees:
			var row := _row()
			var label := UI.label("%s, poziom %d%s" % [m["name"], int(m["level"]), "  ·  w grze" if m["online"] else ""])
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			if m["reward"]:
				row.add_child(UI.button("Odbierz %d XP" % int(rules["mentorXp"]), _claim_mentor.bind(m["name"]), true))
			elif m["rewarded"]:
				row.add_child(UI.label("Nagroda odebrana", UI.GOOD))
			row.add_child(UI.button("Gablota", open_tab.bind(SHOWCASE, m["name"])))
	elif mentor == null and not state["canChoose"]:
		_page.add_child(UI.label("Od %d poziomu możesz zostać mentorem nowych graczy." % int(rules["mentorLevel"]), UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))


func _choose_mentor(name: String) -> void:
	if name == "":
		return
	var reply := await Net.request("mentor.choose", {"name": name})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	toast.emit("%s jest teraz twoim mentorem." % name)
	_show(MENTOR, reply["payload"])


func _claim_mentor(mentee: String) -> void:
	var reply := await Net.request("mentor.claim", {"mentee": mentee} if mentee != "" else {})
	if reply["type"] == "error":
		failed.emit(reply)
		return
	Game.gain_xp(reply["payload"]["xp"])
	toast.emit("Nagroda za opiekę odebrana!")
	_show(MENTOR, reply["payload"]["mentoring"])


# --- Trophy case ----------------------------------------------------------------------------------------

const HONOUR_KINDS := {"first": "Pierwsi w świecie", "trophy": "Wygrane wyzwania", "badge": "Odznaki"}


func _show_showcase(state: Dictionary) -> void:
	_summary.text = "Odznaki: %d z %d" % [int(state["badges"]), int(state["totalBadges"])]
	_heading("Gablota z trofeami: %s" % state["name"] if not state["mine"] else "Twoja gablota z trofeami")
	var row := _row()
	var other := UI.line_edit("Obejrzyj gablotę gracza…")
	other.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(other)
	row.add_child(UI.button("Pokaż", func() -> void: open_tab(SHOWCASE, other.text.strip_edges())))
	if not state["mine"]:
		row.add_child(UI.button("Moja gablota", open_tab.bind(SHOWCASE, "")))
	var honours: Array = state["honours"]
	if honours.is_empty():
		_page.add_child(UI.label("Gablota jest jeszcze pusta: odznaki, pierwsze miejsca w świecie i wygrane wyzwania pojawią się tu same.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	var kind := ""
	var grid: GridContainer
	for h: Dictionary in honours:
		if h["kind"] != kind:
			kind = h["kind"]
			_page.add_child(HSeparator.new())
			_heading(HONOUR_KINDS.get(kind, kind))
			grid = GridContainer.new()
			grid.columns = 1 if UI.touch() else 2
			grid.add_theme_constant_override("h_separation", 16)
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_page.add_child(grid)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var medal := AchievementsWindow.Medal.new()
		medal.unlocked = true
		cell.add_child(medal)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		text.add_child(UI.label(h["name"], UI.GOLD))
		text.add_child(UI.label("%s  ·  %s" % [h["description"], _date(h["at"])], UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
		cell.add_child(text)
		grid.add_child(cell)
