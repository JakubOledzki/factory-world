extends Node
## Whether other players are in the game: a dot next to their name, green online and red offline.
## Every dot on screen names its player; the server is asked about all of them in one request,
## right after a new name shows up and then every few seconds.

const ONLINE_COLOR := Color("#5fd35f")
const OFFLINE_COLOR := Color("#e2483a")
const GROUP := "online_dots"
## Seconds between asking again about the names on screen.
const REFRESH := 10.0
## Seconds to wait after a new name shows up, so a whole list is asked about at once.
const SOON := 0.2

## Name -> whether the player is online, from the last answer.
var _online := {}
var _wait := 0.0
var _asking := false


## One small dot. A player's dot on a plot, or anywhere a name is shown.
class Dot extends Control:
	var player := ""

	func _init(player_name: String, diameter: float) -> void:
		player = player_name
		custom_minimum_size = Vector2(diameter, diameter)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _enter_tree() -> void:
		add_to_group(Online.GROUP)
		Online.ask_soon(player)
		refresh()

	func refresh() -> void:
		tooltip_text = "W grze" if Online.is_online(player) else "Poza grą"
		queue_redraw()

	func _draw() -> void:
		var radius := minf(size.x, size.y) / 2.0
		draw_circle(size / 2.0, radius, Color(0, 0, 0, 0.7))
		draw_circle(size / 2.0, radius - 1.5, Online.ONLINE_COLOR if Online.is_online(player) else Online.OFFLINE_COLOR)


func is_online(player: String) -> bool:
	if not Game.character.is_empty() and player == str(Game.character.get("name", "")):
		return true
	return _online.get(player.to_lower(), false)


## A dot for the player with this name.
func dot(player: String, diameter := 12.0) -> Control:
	return Dot.new(player, diameter)


## Points a dot at another player, e.g. when a window shows whose something is only after loading.
## Without a name the dot hides.
func show_player(shown: Control, player: String) -> void:
	var player_dot := shown as Dot
	player_dot.player = player
	player_dot.visible = player != ""
	ask_soon(player)
	player_dot.refresh()


## The label with the player's dot in front, in one row: add the row where the label would go.
## Without a name (or "?") there is no player to show, and the label comes back as it is.
func with_dot(label: Control, player: Variant) -> Control:
	if player == null or str(player) in ["", "?"]:
		return label
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = label.size_flags_horizontal
	row.size_flags_vertical = label.size_flags_vertical
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot(str(player)))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


## A name not asked about yet is asked about in a moment.
func ask_soon(player: String) -> void:
	if player != "" and not _online.has(player.to_lower()):
		_wait = minf(_wait, SOON)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or _asking:
		return
	_wait = REFRESH
	if Game.character.is_empty() or not Net.is_open():
		return
	var names := {}
	for node in get_tree().get_nodes_in_group(GROUP):
		var player := (node as Dot).player
		if player != "":
			names[player] = true
	if not names.is_empty():
		_ask(names.keys())


func _ask(names: Array) -> void:
	_asking = true
	var reply := await Net.request("players.online", {"names": names})
	_asking = false
	if reply["type"] != "players.online":
		return
	for player: Dictionary in reply["payload"]["players"]:
		_online[str(player["name"]).to_lower()] = bool(player["online"])
	get_tree().call_group(GROUP, "refresh")
