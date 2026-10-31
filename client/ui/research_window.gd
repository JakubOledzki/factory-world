class_name ResearchWindow
extends GameWindow
## The research table: the technology trees (see ResearchPanel). Every garage has one from the
## start; another can be bought from the trader and put in the garage or on a plot. Research goes
## on while the window is closed, and the panel keeps an eye on it, so the screen hears when it is done.

## Research finished: [{id, name}] and the XP gain (or null).
signal researched(finished: Array, xp: Variant)
## The cost was taken or given back; the screen reloads the inventory.
signal inventory_changed
## Money went from the wallet to the company's research or came back.
signal balance_changed
signal failed(reply: Dictionary)
## The player asked to put this table back into the inventory (only where `can_pick_up`).
signal pick_up_requested(id: String)

const TABLE := "furniture_research_table"

## The research table the window was opened at (its object id in the garage or on the plot).
var table := ""
## Whether the window offers to put the table away (on a plot; the garage has its own menu).
var can_pick_up := false

var _items: Array = []
var _slots := 0
var _panel := ResearchPanel.new()
var _pick_up_button: Button


func _init() -> void:
	super("Stół badawczy", 0)
	fill_margin = Vector2(40, 24)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var heading := UI.label("Drzewko technologii", UI.GOLD)
	heading.add_theme_font_override("font", UI.bold())
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_pick_up_button = UI.button("Schowaj stół do ekwipunku", func() -> void: pick_up_requested.emit(table))
	_pick_up_button.visible = false
	top.add_child(_pick_up_button)
	content.add_child(top)
	_panel.researched.connect(researched.emit)
	_panel.inventory_changed.connect(inventory_changed.emit)
	_panel.balance_changed.connect(balance_changed.emit)
	_panel.failed.connect(failed.emit)
	content.add_child(_panel)


## Opens the window at a research table.
func open_at(id: String) -> void:
	table = id
	_pick_up_button.visible = can_pick_up
	show_window()
	_panel.set_items(_items, _slots)
	_panel.refresh()


## The screen calls this whenever the inventory changes, with the inventory's tiles.
func set_items(items: Array, slots := 0) -> void:
	_items = items
	_slots = slots
	_panel.set_items(items, slots)


## Asks the server for the tree once, so research that ended while the game was closed is
## announced without opening the table.
func refresh() -> void:
	if not _panel.loaded() or visible:
		_panel.refresh()
