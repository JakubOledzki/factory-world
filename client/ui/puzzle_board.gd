class_name PuzzleBoard
extends Control
## The yard of an engineering puzzle: a grid with the supply chest and the chest that takes the product,
## where the player puts belts, inserters and machines. A click puts the chosen piece down (on a piece:
## turns it), a right click takes it away, R turns the next piece. After a check the server's flow
## through each piece (pieces a minute) is drawn on it.

signal changed

const CELL := 52
## Arrows for the four ways a piece faces: 0 south, 1 east, 2 north, 3 west, as on the server.
const ARROWS := ["↓", "→", "↑", "←"]

var puzzle := {}
## Pieces put down: {kind, x, y, rotation}.
var pieces: Array[Dictionary] = []
## The piece the next click puts down, and which way it faces.
var kind := ""
var rotation_index := 1
## Pieces a minute through each piece after the last check, by index; empty before one.
var flow: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK


func show_puzzle(p: Dictionary, layout: Array = []) -> void:
	puzzle = p
	pieces.clear()
	for piece: Dictionary in layout:
		pieces.append({"kind": piece["kind"], "x": int(piece["x"]), "y": int(piece["y"]), "rotation": int(piece["rotation"])})
	flow = []
	custom_minimum_size = Vector2(int(p["width"]) * CELL, int(p["height"]) * CELL)
	queue_redraw()


func clear_pieces() -> void:
	pieces.clear()
	flow = []
	changed.emit()
	queue_redraw()


func size_of(piece_kind: String) -> int:
	for allowed: Dictionary in puzzle.get("allowed", []):
		if allowed["id"] == piece_kind:
			return int(allowed["size"])
	return 1


## The piece covering cell (x, y), or -1. A piece of size 2 covers its own cell and those right of and below it.
func piece_at(x: int, y: int) -> int:
	for i in pieces.size():
		var p := pieces[i]
		var s := size_of(p["kind"])
		var low := (s - 1) / 2
		var high := s / 2
		if x >= p["x"] - low and x <= p["x"] + high and y >= p["y"] - low and y <= p["y"] + high:
			return i
	return -1


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(int(at.x / CELL), int(at.y / CELL))


func _is_chest(c: Vector2i) -> bool:
	return c == _point("source") or c == _point("sink")


func _point(name: String) -> Vector2i:
	var p: Dictionary = puzzle.get(name, {"x": -9, "y": -9})
	return Vector2i(int(p["x"]), int(p["y"]))


func _gui_input(event: InputEvent) -> void:
	if puzzle.is_empty():
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		rotation_index = (rotation_index + 1) % 4
		accept_event()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var c := _cell(event.position)
	if c.x < 0 or c.y < 0 or c.x >= int(puzzle["width"]) or c.y >= int(puzzle["height"]) or _is_chest(c):
		return
	var at := piece_at(c.x, c.y)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if at >= 0:
			pieces.remove_at(at)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if at >= 0:
			pieces[at]["rotation"] = (int(pieces[at]["rotation"]) + 1) % 4
		elif kind != "":
			pieces.append({"kind": kind, "x": c.x, "y": c.y, "rotation": rotation_index})
		else:
			return
	else:
		return
	flow = []
	accept_event()
	changed.emit()
	queue_redraw()


func _draw() -> void:
	if puzzle.is_empty():
		return
	var w := int(puzzle["width"])
	var h := int(puzzle["height"])
	draw_rect(Rect2(Vector2.ZERO, Vector2(w, h) * CELL), Color("#1d1f1a"))
	for x in w + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, h * CELL), Color(1, 1, 1, 0.08))
	for y in h + 1:
		draw_line(Vector2(0, y * CELL), Vector2(w * CELL, y * CELL), Color(1, 1, 1, 0.08))
	_draw_chest(_point("source"), puzzle["input"]["id"], Color("#3d6b2f"))
	_draw_chest(_point("sink"), puzzle["output"]["id"], Color("#7a5a1c"))
	var font := ThemeDB.fallback_font
	for i in pieces.size():
		var p := pieces[i]
		var s := size_of(p["kind"])
		var low := (s - 1) / 2
		var rect := Rect2(Vector2(int(p["x"]) - low, int(p["y"]) - low) * CELL, Vector2(s, s) * CELL).grow(-3)
		draw_rect(rect, Color("#2c2f36"))
		draw_rect(rect, Color("#5d6370"), false, 1.5)
		var icon := UI.item_texture(p["kind"])
		if icon:
			draw_texture_rect(icon, rect.grow(-6 if s == 1 else -14), false, Color(1, 1, 1, 0.85))
		if s == 1:
			draw_string(font, rect.position + Vector2(rect.size.x - 16, 16), ARROWS[int(p["rotation"]) % 4],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.GOLD)
		if i < flow.size() and float(flow[i]) > 0.0:
			draw_string(font, rect.position + Vector2(4, rect.size.y - 4), "%s/min" % _number(float(flow[i])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.GOOD)


func _draw_chest(c: Vector2i, item: String, color: Color) -> void:
	var rect := Rect2(Vector2(c) * CELL, Vector2(CELL, CELL)).grow(-3)
	draw_rect(rect, color)
	var icon := UI.item_texture(item)
	if icon:
		draw_texture_rect(icon, rect.grow(-8), false)


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
