class_name PlotPlayers
extends Node2D
## The other players walking on the same plot (the owner and the members of the company it is
## brought into), drawn from where their clients last said they stand. Each one glides to the new
## position so the few updates a second look like walking, and carries their name over the head.

## Updates further than this (tiles) apart are a jump, not a walk.
const SNAP := 4.0
## How quickly a character catches up with where it was last seen.
const FOLLOW := 10.0
## How high (px on screen) the name floats over the feet.
const NAME_HEIGHT := 72.0
## Their facing as a direction GaragePlayer.face() understands (+y is away from the camera).
const FACINGS := {"down": Vector2(0, -1), "up": Vector2(0, 1), "left": Vector2(-1, 0), "right": Vector2(1, 0)}

var tile := Vector2(64, 45)
var player_scale := 1.0 / 3.0
var light := Color.WHITE
## The node shadows go on, under everything standing.
var shadows_parent: Node2D
## The minimap, and the plot's size in tiles, for a dot per player.
var minimap: Control
var plot_size := 250

## By account id: { character: GaragePlayer, target: Vector2 (tiles), walking: bool, dot: Control }.
var _players := {}


func _ready() -> void:
	y_sort_enabled = true


## Shows the players of a "plot.presence" reply; whoever is missing from it has left.
func apply(players: Array) -> void:
	var seen := {}
	for p: Dictionary in players:
		var id := str(p["id"])
		seen[id] = true
		var target := Vector2(float(p["x"]), float(p["y"]))
		if not _players.has(id):
			_add(id, p, target)
		var entry: Dictionary = _players[id]
		entry["target"] = target
		entry["walking"] = bool(p.get("walking", false))
		var character: GaragePlayer = entry["character"]
		character.face(FACINGS.get(str(p.get("facing", "down")), Vector2(0, -1)))
	for id: String in _players.keys():
		if not seen.has(id):
			_remove(id)


func clear() -> void:
	for id: String in _players.keys():
		_remove(id)


func count() -> int:
	return _players.size()


func _add(id: String, p: Dictionary, at: Vector2) -> void:
	var appearance: Dictionary = p.get("appearance", {}) if p.get("appearance") is Dictionary else {}
	var character := GaragePlayer.new(appearance, Game.appearance_options)
	character.light = light
	character.scale = Vector2.ONE * player_scale
	character.shadow.scale = Vector2.ONE * player_scale
	if shadows_parent != null:
		shadows_parent.add_child(character.shadow)
	add_child(character)
	# The name floats over the head at its own size, however small the character is drawn.
	var label := UI.label(str(p.get("name", "?")), UI.GOLD)
	label.add_theme_font_override("font", UI.bold())
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Over the trees and buildings in front, so the name is always readable.
	label.z_index = 10
	label.scale = Vector2.ONE / player_scale
	label.size = Vector2(240, 24)
	label.position = Vector2(-120.0, -NAME_HEIGHT) / player_scale
	character.add_child(label)
	# The dot that tells they are in the game, just before the centred name.
	var text_width := UI.bold().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var online := Online.dot(label.text, 10.0)
	online.mouse_filter = Control.MOUSE_FILTER_IGNORE
	online.z_index = 10
	online.scale = label.scale
	online.size = Vector2(10, 10)
	online.position = Vector2(-text_width / 2.0 - 16.0, -NAME_HEIGHT + 7.0) / player_scale
	character.add_child(online)
	var dot: Control = null
	if minimap != null:
		var rect := ColorRect.new()
		rect.color = Color(0.45, 0.78, 1.0)
		rect.size = Vector2(4, 4)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		minimap.add_child(rect)
		dot = rect
	_players[id] = {"character": character, "target": at, "walking": false, "dot": dot}
	_place(character, at)


func _remove(id: String) -> void:
	var entry: Dictionary = _players[id]
	_players.erase(id)
	var character: GaragePlayer = entry["character"]
	character.shadow.queue_free()
	character.queue_free()
	if entry["dot"] != null:
		(entry["dot"] as Control).queue_free()


func _place(character: GaragePlayer, pos: Vector2) -> void:
	character.floor_pos = pos
	character.position = pos * tile
	character.shadow.position = character.position


func _process(delta: float) -> void:
	for entry: Dictionary in _players.values():
		var character: GaragePlayer = entry["character"]
		var target: Vector2 = entry["target"]
		var pos := character.floor_pos
		if pos.distance_to(target) > SNAP:
			pos = target
		else:
			pos = pos.lerp(target, 1.0 - exp(-FOLLOW * delta))
		character.walking = entry["walking"] or pos.distance_to(target) > 0.05
		_place(character, pos)
		if entry["dot"] != null and minimap != null:
			var dot: Control = entry["dot"]
			dot.position = pos * (minimap.size / float(plot_size)) - dot.size / 2
