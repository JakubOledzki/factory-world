class_name CategoryList
extends ScrollContainer
## The categories of ItemInfo down the side of a big window: "Wszystko" first, then each
## category with how many of the window's items it holds. Scrolls on its own when it is long.

## The player picked a category: its index in ItemInfo.CATEGORIES, or -1 for all.
signal chosen(category: int)

var _box := VBoxContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size.x = 270 if UI.touch() else 200
	_box.add_theme_constant_override("separation", 3)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)


## Draws the buttons for `counts` (one per category) with `selected` lit. Empty categories are
## dimmed, or left out with `hide_empty`; "Inne" only shows when something falls into it.
func show_counts(counts: Array, selected: int, hide_empty := false) -> void:
	for child in _box.get_children():
		child.free()
	var total := 0
	for count: int in counts:
		total += count
	_box.add_child(_button("Wszystko", total, -1, selected))
	var last := ItemInfo.CATEGORIES.size() - 1
	for i in ItemInfo.CATEGORIES.size():
		if counts[i] == 0 and i != selected and (hide_empty or i == last):
			continue
		var b := _button(ItemInfo.CATEGORIES[i][0], counts[i], i, selected)
		b.disabled = counts[i] == 0 and i != selected
		_box.add_child(b)


## How many of `items` (ids) fall into each category.
static func count(items: Array) -> Array:
	var counts := []
	counts.resize(ItemInfo.CATEGORIES.size())
	counts.fill(0)
	for item: String in items:
		counts[ItemInfo.category_of(item)] += 1
	return counts


func _button(text: String, n: int, category: int, selected: int) -> Button:
	var b := UI.button("%s  (%d)" % [text, n], chosen.emit.bind(category), category == selected)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return b
