class_name AchievementToast
extends CanvasLayer
## Shows each badge the server says the player just unlocked ("achievement.unlocked"), one after
## another, as a card sliding down from the top of the screen.

const SHOWN_FOR := 4.0

var _queue: Array[Dictionary] = []
var _showing := false


func _ready() -> void:
	layer = 50
	Net.message_received.connect(_on_message)


func _on_message(type: String, payload: Variant, _id: String) -> void:
	if type == "achievement.unlocked" and payload is Dictionary:
		_queue.append(payload)
		if not _showing:
			_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var badge: Dictionary = _queue.pop_front()
	var parts := UI.panel(2)
	var card: PanelContainer = parts[0]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var medal := AchievementsWindow.Medal.new()
	medal.unlocked = true
	row.add_child(medal)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(UI.label("Nowa odznaka!", UI.MUTED))
	var title := UI.label(badge.get("name", ""), UI.GOLD)
	title.add_theme_font_override("font", UI.bold())
	title.add_theme_font_size_override("font_size", 20)
	text.add_child(title)
	text.add_child(UI.label(badge.get("description", "")))
	row.add_child(text)
	parts[1].add_child(row)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	var width := get_viewport().get_visible_rect().size.x
	card.reset_size()
	var shown := Vector2((width - card.size.x) / 2, 16)
	card.position = shown - Vector2(0, card.size.y + 24)
	var tween := create_tween()
	tween.tween_property(card, "position", shown, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(SHOWN_FOR)
	tween.tween_property(card, "modulate:a", 0.0, 0.5)
	tween.tween_callback(card.queue_free)
	tween.tween_callback(_next)
