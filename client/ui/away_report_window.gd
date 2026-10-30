class_name AwayReportWindow
extends GameWindow
## "Gdy cię nie było": what came in and went out of the wallet while the player was away, by source,
## and what their machines made. The server hands the report out once, on the first return after a break.


func _init() -> void:
	super("Gdy cię nie było", 460)


## Asks for the report and opens the window when there is one.
func check() -> void:
	var reply := await Net.request("report.away")
	if reply["type"] != "report.away" or not reply["payload"].get("away", false):
		return
	_show_report(reply["payload"])
	show_window()


func _show_report(report: Dictionary) -> void:
	UI.clear(content)
	var minutes := int(report["minutes"])
	var away := "%d h %02d min" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d min" % minutes
	if minutes >= 48 * 60:
		away = "%d dni" % (minutes / (24 * 60))
	content.add_child(UI.label("Nie było cię %s. Oto, co się w tym czasie działo." % away, UI.TEXT, HORIZONTAL_ALIGNMENT_LEFT, true))
	var net := int(report["netCents"])
	var total := UI.label("Razem: %s%s" % ["+" if net > 0 else "", UI.money(net)], UI.GOOD if net >= 0 else UI.ERROR)
	total.add_theme_font_override("font", UI.bold())
	total.add_theme_font_size_override("font_size", 20)
	content.add_child(total)
	_section("Wpływy", report["income"], UI.GOOD)
	_section("Wydatki", report["expenses"], UI.ERROR)
	var made: Array = report["made"]
	if not made.is_empty():
		content.add_child(HSeparator.new())
		content.add_child(_head("Twoje maszyny wyprodukowały"))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		for item: Dictionary in made:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			row.add_child(UI.item_icon(item["id"], 28))
			row.add_child(UI.label("%d × %s" % [int(item["quantity"]), item["name"]]))
			grid.add_child(row)
		content.add_child(grid)
	var income: Array = report["income"]
	var expenses: Array = report["expenses"]
	if income.is_empty() and expenses.is_empty() and made.is_empty():
		content.add_child(UI.label("Tym razem nic się nie zmieniło. Pociągi eksportowe, banki i sklepy pracują, także gdy cię nie ma.",
			UI.MUTED, HORIZONTAL_ALIGNMENT_LEFT, true))
	content.add_child(UI.button("Do roboty!", hide_window, true))


func _head(text: String) -> Label:
	var head := UI.label(text, UI.GOLD)
	head.add_theme_font_override("font", UI.bold())
	return head


func _section(title: String, rows: Array, color: Color) -> void:
	if rows.is_empty():
		return
	content.add_child(HSeparator.new())
	content.add_child(_head(title))
	for row: Dictionary in rows:
		var line := HBoxContainer.new()
		var name := UI.label(row["name"])
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		var cents := int(row["cents"])
		line.add_child(UI.label(("+" if cents > 0 else "") + UI.money(cents), color, HORIZONTAL_ALIGNMENT_RIGHT))
		content.add_child(line)
