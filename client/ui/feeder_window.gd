class_name FeederWindow
extends GameWindow
## A feeder on the plot: the feed in it, a button per feed the player has to pour some in, and a button to take it all out.
## It feeds the hungry animals around it by itself, while the player is away too; an inserter next to it fills it. An automatic
## barn opens the same window: it also collects what the animals around it give, which shows here and comes out with the feed.

## Feed came out or went in: [{id, name, quantity}] taken.
signal inventory_changed(taken: Array)
## After every answer from the server, with the plot's animals as they are now.
signal animals_changed(animals: Array)
signal failed(reply: Dictionary)
## The player asked to put the feeder back into the inventory.
signal pick_up_requested(id: String)

## How much one press of a button pours in.
const STEP := 10

var feeder := ""
var plot := Vector2i(-1, -1)
## What animals eat, [{id, name}], from the plot.
var feeds: Array = []

var _items: Array = []

var _state := {}
var _summary: Label
var _store: Label
var _output: Label
var _fill_bar: ProgressBar
var _pour: HFlowContainer
var _take: Button


func _init() -> void:
	super("Karmnik", 400)
	poll_every = 5000.0
	_summary = UI.label("", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_summary)
	content.add_child(HSeparator.new())
	_store = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_store)
	_fill_bar = ProgressBar.new()
	_fill_bar.show_percentage = false
	_fill_bar.custom_minimum_size.y = 10
	content.add_child(_fill_bar)
	_output = UI.label("", UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	content.add_child(_output)
	content.add_child(UI.label("Wsyp z ekwipunku:", UI.GOLD))
	_pour = HFlowContainer.new()
	_pour.add_theme_constant_override("h_separation", 4)
	_pour.add_theme_constant_override("v_separation", 4)
	content.add_child(_pour)
	_take = UI.button("Wyjmij paszę", _take_out)
	content.add_child(_take)
	var pick_up := UI.button("Schowaj do ekwipunku", func() -> void: pick_up_requested.emit(feeder))
	pick_up.tooltip_text = "Pasza z karmnika wróci do ekwipunku"
	content.add_child(pick_up)


func open_at(at: Vector2i, id: String) -> void:
	if id != feeder:
		_state = {}
	plot = at
	feeder = id
	show_window()
	refresh()


func refresh() -> void:
	if feeder == "":
		return
	_apply(await fetch("feeder.get", {"x": plot.x, "y": plot.y, "id": feeder}))


func _apply(reply: Dictionary) -> bool:
	if reply["type"] != "feeder":
		failed.emit(reply)
		return false
	_state = reply["payload"]["feeder"]
	animals_changed.emit(reply["payload"].get("animals", []))
	_render()
	return true


func _render() -> void:
	if _state.is_empty():
		return
	var animals := int(_state["animals"])
	var hungry := int(_state["hungry"])
	var barn: bool = _state.get("collects", false)
	set_title("Obora automatyczna" if barn else "Karmnik")
	var around := "W zasięgu %d pól nie ma zwierząt: wypuść je obok." % int(_state["reach"]) if animals == 0 \
		else "Zwierząt w zasięgu %d pól: %d, głodnych: %d." % [int(_state["reach"]), animals, hungry]
	if barn:
		_summary.text = "Sama karmi zwierzęta wokół siebie, %d sztuki paszy na posiłek, i zbiera, co dają: jajka, wełnę, mleko, mięso, obornik i młode. Podajnik obok napełni ją paszą i wyjmie zbiory. %s" \
			% [int(_state["feedPerMeal"]), around]
	else:
		_summary.text = "Sam karmi głodne zwierzęta wokół siebie, %d sztuki paszy na posiłek: od razu po wypuszczeniu, po każdym zbiorze i gdy dostanie paszę. Podajnik obok też go napełni. %s" \
			% [int(_state["feedPerMeal"]), around]
	var collected := PackedStringArray()
	var count := 0
	for stack: Dictionary in _state.get("output", []):
		collected.append("%s × %d" % [stack["name"], int(stack["quantity"])])
		count += int(stack["quantity"])
	_output.visible = barn
	_output.text = "Zebrane: %d/%d%s" % [count, int(_state.get("maxOutput", 0)), (": " + ", ".join(collected)) if not collected.is_empty() else ""]
	var parts := PackedStringArray()
	for stack: Dictionary in _state["store"]:
		parts.append("%s × %d" % [stack["name"], int(stack["quantity"])])
	var feed := int(_state["feed"])
	var capacity := int(_state["capacity"])
	_store.text = "Pasza: %d/%d%s" % [feed, capacity, (": " + ", ".join(parts)) if not parts.is_empty() else " (pusty, głodne zwierzęta czekają)" if hungry > 0 else ""]
	_fill_bar.max_value = capacity
	_fill_bar.value = feed
	_take.text = "Wyjmij paszę i zbiory" if barn else "Wyjmij paszę"
	_take.disabled = feed == 0 and count == 0
	for child in _pour.get_children():
		child.queue_free()
	var room := capacity - feed
	var any := false
	for kind: Dictionary in feeds:
		var have := _have(kind["id"])
		if have <= 0:
			continue
		any = true
		var some := mini(mini(STEP, have), room)
		var button := UI.button("%s +%d" % [kind["name"], some], func() -> void: _fill(kind["id"], some))
		button.icon = UI.texture("icons/item_" + str(kind["id"]))
		button.expand_icon = false
		button.disabled = some <= 0
		button.tooltip_text = "Masz %d" % have
		_pour.add_child(button)
	if not any:
		_pour.add_child(UI.label("Nie masz paszy: pszenicy, kukurydzy, marchwi, kapusty, mączki rybnej, daktyli, wysłodków ani paszy treściwej.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	_fit.call_deferred()


## The player's inventory, for the buttons that pour feed in.
func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func _have(item: String) -> int:
	for stack: Dictionary in _items:
		if stack["id"] == item:
			return int(stack["quantity"])
	return 0


func _fill(item: String, quantity: int) -> void:
	if _apply(await Net.request("feeder.fill", {"x": plot.x, "y": plot.y, "id": feeder, "item": item, "quantity": quantity})):
		inventory_changed.emit([])


func _take_out() -> void:
	var reply := await Net.request("feeder.take", {"x": plot.x, "y": plot.y, "id": feeder})
	if _apply(reply):
		inventory_changed.emit(reply["payload"].get("taken", []))
