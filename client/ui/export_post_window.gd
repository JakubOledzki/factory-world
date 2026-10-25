class_name ExportPostWindow
extends GameWindow
## A buying market in a town or a rail port on the coast. Export trains from every player's export chest go to the nearest
## market, which lists their goods on the players' market, and cross the sea on a ferry from port to port. The owner of the
## plot sets the market's commission on other players' goods, or the fee the port takes for each train of someone else's,
## and sees what it has earned; everyone else sees what they would pay.

signal balance_changed
signal failed(reply: Dictionary)
signal pick_up_requested(id: String)

## How often (ms) the window asks again while it is open.
const POLL := 10000.0
const MARKET := "furniture_buy_market"

var post := ""

var _state := {}
var _about: Label
var _owner: Label
var _earned: Label
var _setting := HBoxContainer.new()
var _value: SpinBox
var _pick_up: Button


func _init() -> void:
	super("Rynek skupu", 440)
	poll_every = POLL
	_about = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_about)
	content.add_child(HSeparator.new())
	_owner = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_owner)
	_earned = UI.label("", UI.GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_earned)
	_setting.add_theme_constant_override("separation", 6)
	_value = SpinBox.new()
	_value.min_value = 0
	_value.custom_minimum_size.x = 110
	_value.select_all_on_focus = true
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setting.add_child(_value)
	_setting.add_child(UI.button("Zapisz", _save, true))
	content.add_child(_setting)
	_pick_up = UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(post))
	content.add_child(_pick_up)


func open_at(id: String) -> void:
	if id != post:
		_state = {}
	post = id
	show_window()
	refresh()


func refresh() -> void:
	if post == "":
		return
	_apply(await fetch("export.post", {"id": post}))


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "export.post":
		failed.emit(reply)
		return false
	var editing := _value.get_line_edit().has_focus()
	_state = reply["payload"]
	_render(not editing)
	return true


func _render(set_value: bool) -> void:
	var market: bool = _state["kind"] == MARKET
	var value := int(_state["value"])
	var mine: bool = _state["mine"]
	if market:
		set_title("Rynek skupu · %s" % _state["town"])
		_about.text = ("Pociągi ze skrzyń eksportowych przy stacjach przywożą tu co godzinę towar z najbliższej okolicy i wystawiają go na rynek graczy " +
			"po cenach sprzedawców. Jeden rynek skupu na miasto; na świecie stoi ich teraz %d.") % int(_state["markets"])
		_owner.text = "Prowadzi: %s · prowizja od cudzych towarów: %d%% wartości, płatna przy wystawieniu." % [_state["owner"], value]
	else:
		set_title("Port pociągowy · %d × %d" % [int(_state["x"]), int(_state["y"])])
		_about.text = ("Pociągi nie jeżdżą po wodzie: tu wjeżdżają na prom i płyną do innego portu pociągowego, trzy razy wolniej niż lądem. " +
			"Pociąg wybiera najszybszą drogę do rynku skupu, przez dowolne porty.")
		_owner.text = "Właściciel: %s · opłata za przeprawę cudzego pociągu: %s." % [_state["owner"], UI.money(value).replace(" ", "\u00a0")]
	_earned.visible = mine
	_setting.visible = mine
	_pick_up.visible = mine
	if mine:
		_earned.text = "Zarobiono %s (%d %s)." % [UI.money(int(_state["earnedCents"])), int(_state["uses"]),
			"wystawień" if market else "przepraw"]
		_value.max_value = int(_state["maxValue"]) if market else int(_state["maxValue"]) / 100.0
		_value.step = 1 if market else 0.01
		_value.rounded = market
		_value.suffix = "%" if market else "$"
		_value.tooltip_text = "Prowizja od wartości cudzych towarów (0–%d%%)" % int(_state["maxValue"]) if market \
			else "Opłata za każdy cudzy pociąg (0–%s)" % UI.money(int(_state["maxValue"]))
		if set_value:
			_value.value = value if market else value / 100.0
	_fit.call_deferred()


func _save() -> void:
	var market: bool = _state.get("kind", "") == MARKET
	var value := roundi(_value.value) if market else roundi(_value.value * 100.0)
	_apply(await Net.request("export.setPost", {"id": post, "value": value}))
