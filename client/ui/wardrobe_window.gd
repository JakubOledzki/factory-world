class_name WardrobeWindow
extends GameWindow
## The wardrobe in the garage: clothes hang in it, and up to four outfits are saved to change
## into at once. Each piece of an outfit comes from the wardrobe or the inventory; what was worn
## is hung up instead.

## Clothes went between the wardrobe, the inventory and the character.
signal changed
signal failed(reply: Dictionary)

const SLOTS := ["head", "body", "legs", "feet"]
const SLOT_NAMES := {"head": "Głowa", "body": "Tułów", "legs": "Nogi", "feet": "Stopy"}

var wardrobe := ""

var _state := {}
var _items: Array = []
var _outfits := VBoxContainer.new()
var _worn := HBoxContainer.new()
var _stored := VBoxContainer.new()
var _hang := VBoxContainer.new()
var _names := {}


func _init() -> void:
	super("Szafa na ubrania", 470)
	content.add_child(_heading("Komplety"))
	_outfits.add_theme_constant_override("separation", 6)
	content.add_child(_outfits)
	var hint := UI.label("Zapisz, co masz na sobie, a potem przebieraj się jednym kliknięciem. Ubrania bierze z szafy albo z ekwipunku, a zdjęte wiesza w szafie.", UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
	hint.add_theme_font_size_override("font_size", 13)
	content.add_child(hint)
	content.add_child(HSeparator.new())
	content.add_child(_heading("Na sobie"))
	_worn.add_theme_constant_override("separation", 6)
	content.add_child(_worn)
	content.add_child(HSeparator.new())
	content.add_child(_heading("W szafie"))
	_stored.add_theme_constant_override("separation", 4)
	content.add_child(_stored)
	content.add_child(_heading("Powieś z ekwipunku"))
	_hang.add_theme_constant_override("separation", 4)
	content.add_child(_hang)


func open_at(id: String) -> void:
	if id != wardrobe:
		_state = {}
	wardrobe = id
	show_window()
	_send("wardrobe.get", {})


func set_items(items: Array) -> void:
	_items = items
	if visible:
		_render()


func _send(type: String, payload: Dictionary) -> void:
	payload["id"] = wardrobe
	var reply := await Net.request(type, payload)
	if reply["type"] != "wardrobe":
		failed.emit(reply)
		return
	_state = reply["payload"]
	_render()
	if type != "wardrobe.get":
		changed.emit()


func _render() -> void:
	if _state.is_empty():
		return
	UI.clear(_outfits)
	for outfit: Dictionary in _state["outfits"]:
		_outfits.add_child(_outfit_row(outfit))

	UI.clear(_worn)
	for slot: String in SLOTS:
		_worn.add_child(_piece(_state["worn"].get(slot), slot, 34))

	UI.clear(_stored)
	var stored: Array = _state["stored"]
	if stored.is_empty():
		_stored.add_child(UI.label("Pusto.", UI.MUTED))
	for stack: Dictionary in stored:
		var row := _item_row(stack["id"], "%s  ×%d" % [stack["name"], int(stack["quantity"])])
		row.add_child(UI.button("Wyjmij", _send.bind("wardrobe.take", {"item": stack["id"], "quantity": 1})))
		_stored.add_child(row)

	UI.clear(_hang)
	var any := false
	for stack: Dictionary in _items:
		var item: String = stack["id"]
		if not item.begins_with("clothes_"):
			continue
		any = true
		var row := _item_row(item, "%s  ×%d" % [stack["name"], int(stack["quantity"])])
		row.add_child(UI.button("Powieś", _send.bind("wardrobe.put", {"item": item, "quantity": 1})))
		_hang.add_child(row)
	if not any:
		_hang.add_child(UI.label("W ekwipunku nie ma ubrań.", UI.MUTED))
	_fit.call_deferred()


func _outfit_row(outfit: Dictionary) -> Control:
	var number := int(outfit["number"])
	var parts := UI.panel(4)
	var card: PanelContainer = parts[0]
	var box: VBoxContainer = parts[1]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var name_edit := UI.line_edit("Komplet %d" % number)
	name_edit.text = outfit["name"] if outfit["saved"] else ""
	name_edit.max_length = 20
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_names[number] = name_edit
	head.add_child(name_edit)
	for slot: String in SLOTS:
		head.add_child(_piece(outfit["pieces"].get(slot), slot, 26))
	box.add_child(head)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	var wear := UI.button("Załóż", _send.bind("wardrobe.wear", {"number": number}), true)
	wear.disabled = not outfit["saved"]
	buttons.add_child(wear)
	var save := UI.button("Zapisz to, co mam na sobie", func() -> void:
		_send("wardrobe.save", {"number": number, "name": (_names[number] as LineEdit).text}))
	buttons.add_child(save)
	if outfit["saved"]:
		buttons.add_child(UI.button("Usuń", _send.bind("wardrobe.forget", {"number": number})))
	box.add_child(buttons)
	return card


## A piece of clothing (or an empty slot) as an icon with its name in the tooltip.
func _piece(piece: Variant, slot: String, size: int) -> TextureRect:
	var icon: TextureRect
	if piece is Dictionary:
		icon = UI.item_icon(piece["id"], size)
		icon.tooltip_text = "%s: %s" % [SLOT_NAMES[slot], piece["name"]]
	else:
		icon = UI.item_icon(CharacterWindow.EMPTY_ICONS[slot], size)
		icon.modulate = Color(0, 0, 0, 0.35)
		icon.tooltip_text = "%s: nic" % SLOT_NAMES[slot]
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	return icon


func _item_row(item: String, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UI.item_icon(item, 26))
	var name_label := UI.label(text)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	return row


func _heading(text: String) -> Label:
	var l := UI.label(text, UI.GOLD)
	l.add_theme_font_override("font", UI.bold())
	return l
